# 57 — Pipeline 目标 Dataset Schema 与主键确定机制调研

**日期：** 2026-06-13  
**类型：** 技术调研 / Pipeline output contract / Dataset schema / Primary key  
**写入范围：** 本文件  

---

## 1. 总结与洞察

1. 【事实】Foundry 对外公开的稳定语义是：Dataset schema 绑定在 dataset view 上，可按 `branchName`、`endTransactionRid`、`versionId` 查询；因此目标数据集 schema 不是脱离版本存在的静态表头，而是输出 view 的元数据。
2. 【事实 + 推断】Pipeline/Transform 先通过 `Input` / `Output`、Builder transform/expression 类型系统和 integrity checks 声明并校验输出契约；真正的目标 dataset schema 在 build 写出后随 output view 一起固化为 schema version。
3. 【事实】Dataset 层没有公开的“默认主键”或“每个 dataset 必有主键”语义；公开资料里 primary key 出现于 Data Expectations 和 Data Health checks，说明它更像可声明的数据质量/数据契约，而不是 Dataset 底层强制约束。
4. 【事实】Palantir 对 primary key 的公开定义是一组列：每列非空，且列组合唯一；Pipeline Builder output expectations 与 Python Data Expectations 都遵循这个语义。
5. 【建议】自研平台不要把 transaction id、run id、`business_date` 或物理 partition 误当目标 dataset 主键；主键应由业务标识粒度决定，必要时才引入 surrogate key，并将其与版本坐标分开建模。

---

## 2. 问题定义

本任务回答三个问题：

1. Pipeline 的目标数据集 schema 是如何确定的。
2. 目标数据集是否天然存在主键。
3. 如果需要主键，主键应如何确定。

为避免把未公开实现说成已验证事实，本文区分：

- 【事实】：Palantir 官方文档或仓库既有证据直接支持。
- 【推断】：由多个事实拼接得到的工程判断。
- 【待验证】：公开资料没有给出内部实现细节。

---

## 3. 目标 Dataset Schema 如何确定

### 3.1 对外稳定语义：schema 绑定在 dataset view 上

既有证据已经说明，Foundry Dataset 的 schema 不是简单挂在“表”这个抽象上，而是绑定在 dataset view 上。`Get Dataset Schema` API 支持按 `branchName`、`endTransactionRid`、`versionId` 查询 schema，返回值包含 `branchName`、`endTransactionRid` 和 schema `versionId`。【事实】

这意味着：

- 同一个 dataset 在不同 branch / transaction / view 上可以对应不同 schema version。【事实】
- 目标 dataset schema 的最终锚点是“这次 build 产出的 output view 是什么”，而不是 pipeline 定义文件里单独保存的一份静态 schema。【推断】

### 3.2 Pipeline 先声明输出契约，再由 build 产出最终 schema

在高码路径里，Transform 通过 `Input` / `Output` 声明 dataset 级依赖，平台据此组装 DAG；但 `Input` / `Output` 本身主要声明“读哪个 dataset、写哪个 dataset”，不是显式列出完整 schema 的 DDL。【事实】

在低码路径里，Pipeline Builder 不只是连线 UI。仓库既有资料已经记录：

- Builder 至少分成 transform 与 expression 两层，后者有字段和值级类型系统。【事实】
- Builder 后端会生成 transform code，并执行 pipeline integrity checks，提前发现 schema 和 refactor 问题。【事实】

据此可以得到更精确的工程判断：

1. **编译/设计期**：Builder 或 Transform contract 会推导、校验“输出应该长什么样”，例如列名、列类型、字段是否存在、重命名是否破坏下游。【事实 + 推断】
2. **运行期**：实际 compute engine 运行 transform，生成最终输出 DataFrame / table / files，并写入 output dataset transaction。【推断】
3. **提交后**：该 output view 对应的 schema 被固化为新的 schema version，对外可被 Schema API、Lineage、Preview、Health checks 消费。【事实 + 推断】

### 3.3 不能把“schema inference”误解为纯运行后猜测

如果只把 schema 理解成“作业跑完后读一遍文件得到表头”，会漏掉 Builder integrity checks、Data Expectations schema checks 和下游 refactor 校验这些前置约束。

更准确的说法是：

- **前置层**：Transform contract、Builder expression/type system、integrity checks 决定允许什么 schema 变化。【事实 + 推断】
- **提交层**：output view 挂接的 schema version 决定这次产物最终暴露什么 schema。【事实】

因此，“目标 dataset schema 如何确定”应理解为：

> 由 transform / builder 逻辑产生的输出结构，经平台在 build 前后做契约校验，最终随 output dataset view 固化为 schema version。【推断】

---

## 4. 目标 Dataset 是否有主键

### 4.1 Dataset 基础模型没有公开的默认主键语义

仓库现有 Dataset / Pipeline / Lineage 资料一再强调 Dataset 的核心元数据是 schema、permissions、transactions、branches、views、lineage 和 build history；并没有公开文档说明“每个 dataset 必须定义主键”或“平台自动为 dataset 生成主键”。【事实】

这与传统关系型表不同：Dataset 更接近“带 schema 和版本语义的文件集合”，不是自动附带 PK/FK/unique constraints 的 OLTP 表。【推断】

### 4.2 Primary key 作为可声明的数据契约出现

已有 Data Quality 证据明确表明：

- Pipeline Builder 当前支持 output expectations 中的 `primary key` 和 `row count`。【事实】
- Python Data Expectations 支持 `primary key`、`schema`、`group-by`、`foreign value` 等规则。【事实】
- Data Health content checks 也包含 `primary key` 检查。【事实】

这说明 primary key 在 Foundry 公开模型里的位置是：

- 不是 Dataset 底座默认自带的系统主键。【事实】
- 而是可以附着在 output 或 dataset 上的质量/契约约束，用来校验唯一性与非空性。【事实 + 推断】

结论：**目标 dataset 不天然有主键；只有当工程师或产品在质量/契约层显式声明时，它才成为一个被检查的主键语义。**【推断】

---

## 5. 主键如何确定

### 5.1 Palantir 对主键的公开语义

仓库既有证据已经记录，Palantir 对 primary key 的公开定义是：

- 一个或多个列。【事实】
- 每个列必须 non-null。【事实】
- 列组合必须 unique。【事实】

这说明主键的确定不是“挑一个 ID 列”这么简单，而是先确定数据的业务粒度，再决定是单列键还是组合键。【推断】

### 5.2 工程上应按业务身份粒度确定

对自研平台可直接复用的判断是：

1. **优先使用上游稳定业务键**：如订单号、用户号、设备号、事件源唯一 ID。【建议】
2. **若单列不足以唯一，使用组合键**：例如 `tenant_id + order_id`、`source_system + entity_id`。【建议】
3. **不要把业务日期当主键**：`business_date` 更像切片、周期或消费语义，不代表实体唯一性。【建议】
4. **不要把 transaction / run_id 当业务主键**：它们是版本与执行证据，回答“谁在什么时候生成了这批数据”，不能回答“这行记录代表哪个业务实体”。【建议】
5. **没有天然业务键时才引入 surrogate key**：例如稳定 hash 或系统分配键；但仍应保留原始业务去重字段，避免把 surrogate key 变成不可解释的黑盒。【建议】

### 5.3 与增量、去重和质量门禁的关系

主键是否需要声明，通常取决于下游场景：

| 场景 | 是否需要显式主键 | 原因 |
|---|---|---|
| 只做一次性宽表产出、无 upsert / dedup | 未必必须 | 可能只需要 schema contract 和 row count |
| 需要去重、幂等重跑、merge/upsert | 强烈建议 | 没有稳定键就无法判断同一业务记录 |
| 要做 Data Expectations / Health checks | 建议声明 | 可直接用 primary key check 守护唯一性 |
| 需要映射到 Ontology object identity | 必须先定业务键 | 否则对象 identity 不稳定 |

仓库已有高码调研也提到，普通增量方案常依赖 `updated_at`、主键或 CDC 事件；而 Foundry 的增量基座是 Dataset transaction。【事实】这并不意味着主键不重要，而是意味着：

- transaction 负责**版本增量**；【事实】
- primary key 负责**业务实体唯一性/去重语义**；【推断】
- 二者不能混用。【建议】

---

## 6. 对自研 Pipeline / Dataset 设计的直接启示

1. 【建议】把 schema 拆成两层：`declared/expected schema` 与 `materialized schema version`。前者服务编译期校验，后者服务运行结果追溯。
2. 【建议】把 primary key 设计成显式 contract，而不是隐含约定；至少支持单列/组合列、non-null、unique 和校验结果持久化。
3. 【建议】在 metadata 模型里分开保存 `dataset_version_coordinate` 与 `business_identity_key`，避免把 transaction 或 partition 字段误建成主键。
4. 【建议】当 Pipeline Builder/低码入口存在时，必须把字段级类型推导和 schema change impact 分析做成平台能力，否则很难复现 Foundry 的 integrity checks 体验。
5. 【建议】若未来支持 upsert / CDC / ontology writeback，主键应提前进入 contract 与 lineage 模型，而不是事后靠 SQL 约定补齐。

---

## 7. 待验证问题

1. 【待验证】Builder integrity checks 在 build 前保存的是“完整显式 schema IR”还是“按节点惰性推导的字段类型图”，公开资料不足。
2. 【待验证】schema version 的内部持久化表结构、diff 算法和与 refactor warning 的联动机制未公开。
3. 【待验证】Pipeline Builder 的 primary key expectation 是否同时反向写入某种元数据注册表，还是仅作为 build-time / health-time rule 保存，公开资料不足。
4. 【待验证】Java transforms、SQL transforms、lightweight engines 与 Spark 在 schema materialization 上是否共享完全一致的内部模型，仓库现有证据尚未逐一展开。

---

## 8. 参考资料

### 仓库内证据

- `docs/raw/21-pro-code-capability-deep-dive.md`
- `docs/raw/29-lineage-branch-version-pipeline-sync.md`
- `docs/raw/45-data-expectations-build-gates.md`
- `docs/raw/46-data-health-health-checks.md`
- `docs/topics/pipeline.md`
- `docs/topics/dataset.md`

### 上游资料入口

- Palantir Foundry API - Get Dataset Schema: https://www.palantir.com/docs/foundry/api/datasets-v2-resources/datasets/get-dataset-schema
- Palantir Foundry - Define data expectations: https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations
- Palantir Foundry - Pipeline Builder Data Expectations Overview: https://www.palantir.com/docs/foundry/pipeline-builder/dataexpectations-overview
- Palantir Foundry - Data Health Checks Reference: https://www.palantir.com/docs/foundry/data-health/checks-reference/
