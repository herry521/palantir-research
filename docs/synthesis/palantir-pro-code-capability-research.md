# Palantir 高码能力研究综合结论

**日期：** 2026-05-29
**对应 Issue：** #12
**覆盖 Story：** #6、#7、#8、#9、#10、#11、#14
**可信度标签：** 【事实 ref】=本轮官方资料或仓库材料直接确认，ref 指向对应来源；【推断】=由多个事实组合出的工程判断；【猜测】=证据不足、只能作为后续验证假设。

---

## 一、总判断

Palantir 的高码能力强点不是“允许写 Python / Java / SQL”，而是把代码变成平台可理解、可调度、可治理、可审计的数据生产契约。【推断】

Code Repositories 提供 Git、分支、提交、tag、PR / code review、权限、IntelliSense、lint、error checking、preview、debug、impact analysis 和 repository upgrades 等能力。【事实 [ref](https://www.palantir.com/docs/foundry/code-repositories/overview/index.html)】这些能力把数据生产代码纳入 Foundry 的工程生命周期，而不是停留在外部 IDE + 外部 CI。【推断】

Transform 的 `Input` / `Output` 声明让函数暴露 Dataset 依赖关系，使平台能够围绕 Dataset graph 做血缘、调度、影响分析、权限继承、质量校验和版本化构建。【推断】

Dataset Transaction 是增量、回滚、可重复构建和失败隔离的关键底座。官方增量文档已经确认 append-only 输入通常可增量，full rewrite、update/delete 文件等会触发 snapshot 或破坏增量路径。【事实 [ref](https://www.palantir.com/docs/foundry/transforms-python/incremental-usage)】这说明增量能力不是单个任务内部的 `updated_at` 过滤，而是由 Dataset 事务、输入 read mode、输出 write mode、retention 和 staleness 共同决定。【推断】

Pipeline Builder 与高码不是两套完全割裂的系统。官方文档确认 Pipeline Builder 后端会写 transform code、执行 pipeline integrity checks，并支持导出到 Java transforms repository；但导出不可逆，部分转换无法导出，部分优化会回退到 native Spark 且可能产生输出差异。【事实 [ref](https://www.palantir.com/docs/foundry/pipeline-builder/export-pipeline)】因此可借鉴方向是共享 Contract / IR，而不是承诺低码与高码无损双向同步。【推断】

---

## 二、高码能力强在哪里

| 能力层 | 强点 | 可信度 |
|---|---|---|
| 工程入口 | Code Repositories 把 Git、PR、权限、编辑反馈、preview/debug、impact analysis 放进平台内 | 【事实 [ref](https://www.palantir.com/docs/foundry/code-repositories/overview/index.html)】 |
| 平台契约 | `Input` / `Output`、参数、资源、质量规则、增量语义构成 Transform Contract | 【推断】 |
| 运行时 | Python 支持 Spark、DuckDB、pandas、Polars 等路径；Java 支持 batch/incremental/unit testing；SQL 基于 Spark SQL 但不支持 incremental transforms | 【事实 [ref](https://www.palantir.com/docs/foundry/building-pipelines/supported-languages)】 |
| Dataset graph | Scheduling 可按时间、数据更新、逻辑更新触发，并按单个 Dataset、依赖、下游或两个 Dataset 间链路构建 | 【事实 [ref](https://www.palantir.com/docs/foundry/building-pipelines/scheduling-overview)】 |
| 治理闭环 | Data Lineage、markings、roles、data expectations、health checks、notifications 与代码生产链路关联 | 【事实 [ref](https://www.palantir.com/docs/foundry/data-lineage/overview)】 |
| 低码互操作 | Pipeline Builder 可导出 Java code，但不可逆且存在不可导出/语义差异风险 | 【事实 [ref](https://www.palantir.com/docs/foundry/pipeline-builder/export-pipeline)】 |

最核心的壁垒是“代码被平台理解”。普通 Git + CI 能运行脚本，但无法天然知道脚本生产哪个 Dataset、依赖哪个 Dataset、影响哪些下游、是否可以增量、是否破坏权限继承、是否需要重算。【推断】

---

## 三、怎么实现

```text
Code Repository
  -> Transform Contract
    -> Input / Output / params / resources / quality metadata
      -> Engine Router
        -> Spark / lightweight Python / Java / SQL
          -> Dataset Transaction
            -> Lineage / Scheduling / Permissions / Observability / Ontology
```

### 1. Authoring 与工程入口

Code Repositories 是高码入口，而不是普通文件存储。它把 repository、branch、PR、review、权限、模板、lint、error checking、preview、debug、impact analysis 和 upgrades 组织进同一工作流。【事实 [ref](https://www.palantir.com/docs/foundry/code-repositories/overview/index.html)】

这类入口的设计目的不是替代专业 IDE，而是让平台在代码进入生产前就能理解其数据资产影响范围。【推断】

### 2. Transform Contract 与 DAG

Python transform 通过装饰器声明 `Input` 和 `Output`；Java transform 通过 annotation / API 组织输入输出；SQL transform 也能声明输入输出并运行在 Spark SQL 路径上。【事实 [ref](https://www.palantir.com/docs/foundry/transforms-python/transforms)】

如果 Transform A 生产 Dataset X，Transform B 声明 X 为输入，则 B 依赖 A。官方未公开完整 DAG 生成算法，但 Input/Output contract、Lineage 图和 Scheduling 构建范围共同支持这个推断。【推断】

Transform Contract 至少应包含 Dataset 引用、Schema、参数、执行资源、引擎类型、增量配置、质量规则、权限边界和所有者信息。【推断】

### 3. 运行时与依赖管理

Python 是最完整路径，支持 batch、incremental、共享库、data expectations 和多种 compute engine。【事实 [ref](https://www.palantir.com/docs/foundry/building-pipelines/supported-languages)】

轻量 Python 引擎适合单节点数据处理和快速反馈；Spark 适合分布式处理和大规模 Dataset；Java 适合强类型和工程化组织；SQL 适合声明式转换但存在 incremental 限制。【事实 [ref](https://www.palantir.com/docs/foundry/building-pipelines/supported-languages)】

自建平台不应把引擎选择暴露成完全自由配置，而应建立 Engine Router：根据数据规模、增量需求、依赖库、执行资源和治理要求选择运行路径。【推断】

### 4. Dataset Transaction、调度与增量

Foundry 的增量语义以 Dataset transaction 为基础。输入事务类型、输出写入模式、snapshot / incremental 策略、retention 和 staleness 决定一次 build 是否能增量执行。【事实 [ref](https://www.palantir.com/docs/foundry/transforms-python/incremental-usage)】

Scheduling 支持时间触发、数据更新触发、逻辑更新触发，并能选择不同的 Dataset graph 构建范围。【事实 [ref](https://www.palantir.com/docs/foundry/building-pipelines/scheduling-overview)】这意味着调度中心的主对象更接近 Dataset graph，而不是孤立任务节点。【推断】

### 5. 治理、质量和可观测性

Data expectations、unit tests、preview、health checks、build status、notifications、lineage、markings 和 roles 共同构成高码生产链路的治理面。【事实 [ref](https://www.palantir.com/docs/foundry/data-lineage/overview)】

这类治理能力必须内嵌在 Transform Contract 和 Dataset graph 中；如果只在外部 CI 或监控系统里实现，会丢失对数据资产、权限和下游影响的上下文。【推断】

### 6. 低码 / 高码互操作

Pipeline Builder 的 export pipeline code 是低码到高码的升级路径，不是双向同步机制。【事实 [ref](https://www.palantir.com/docs/foundry/pipeline-builder/export-pipeline)】

自建平台应把低码 Builder 和高码 SDK 建在同一套 Contract / IR 上：低码编辑器生成 IR，高码 SDK 生成同等 Contract，调度、血缘、权限和质量系统只消费 Contract。【推断】

---

## 四、怎么借鉴

### P0：先做平台契约

定义 Transform Contract 和 Dataset Version Spec。没有契约，代码只是脚本；有契约，平台才能索引、调度、治理和复用。【推断】

最小字段建议：

- 输入 Dataset、输出 Dataset、参数、Schema。
- 执行引擎、资源规格、依赖包、运行身份。
- 增量策略、读写模式、staleness 和 retention。
- 质量规则、测试入口、血缘元数据、权限 / marking。

### P1：建立 Dataset Transaction

Dataset 每次写入生成不可变版本，运行时支持 current、previous、added 等视图，输出提交具备原子性，失败时不暴露中间态。【推断】

这是后续增量、回滚、影响分析和可重复构建的基础。没有这一层，调度器只能管理任务状态，无法可靠管理数据状态。【推断】

### P2：做 Engine Router

不要一次性只绑定 Spark，也不要无限制暴露所有执行引擎。建议从 Spark + lightweight Python 两条路径开始，先固化能力矩阵：哪些支持增量、哪些支持质量规则、哪些支持大规模分布式、哪些只适合预览或小数据。【推断】

### P3：统一低码和高码 IR

低码 Builder 应生成同一套 Transform Contract；代码导出可以作为升级路径，但应明确不可逆、不可导出算子、优化回退和输出差异风险。【推断】

### P4：补齐治理闭环

把 PR/check/test、data expectations、build preview、upgrade impact analysis、schedule、freshness、lineage、owner notification 和权限继承做成高码生命周期的一部分。【推断】

---

## 五、低码与高码对比

| 维度 | 低码 Pipeline Builder | 高码 Code Repositories / Transforms | 借鉴结论 |
|---|---|---|---|
| 目标用户 | 数据分析师、数据工程初阶用户 | 数据工程师、平台工程师、复杂业务开发者 | 两者需要共享底层 Contract【推断】 |
| 表达能力 | 可视化、受控算子、反馈快 | 可组织复杂逻辑、依赖库、测试和工程流程 | 高码是复杂度出口【推断】 |
| 迁移路径 | 可导出到 Java transforms repository | 接管后以代码为主 | 导出是单向升级，不是同步【事实 [ref](https://www.palantir.com/docs/foundry/pipeline-builder/export-pipeline)】 |
| 风险 | 算子覆盖不足、复杂逻辑表达困难 | 工程门槛高、自由度带来治理压力 | 用 Contract 和质量规则约束自由度【推断】 |
| 平台治理 | integrity checks、branch 协作 | PR、review、tests、impact analysis | 治理面应消费同一 graph【推断】 |

---

## 六、PoC 建议

1. 实现最小 Transform SDK：`@transform(input=..., output=...)`，生成 JSON Contract。【推断】
2. 实现 Dataset Transaction 原型：append、replace、snapshot、atomic commit、version pointer。【推断】
3. 实现 DAG Resolver：根据 output producer 和 input consumer 生成 graph，并提供 upstream/downstream 查询。【推断】
4. 实现 Spark runtime + lightweight Python runtime 两条路径，建立 Engine Router 能力矩阵。【推断】
5. 实现低码 Builder IR 到 Contract 的转换，并提供一次性 code export report，不承诺双向同步。【推断】
6. 实现质量和治理最小闭环：unit test、data expectation、lineage、owner、marking、build health。【推断】

---

## 七、证据缺口

- Palantir 内部 transform 扫描、依赖索引、跨 repository 事件传播机制未公开，当前只能推断。【猜测】
- Pipeline Builder 的内部 IR 未公开，无法确认其与导出 Java code 的完整映射关系。【猜测】
- 复杂增量场景需要真实 Foundry 环境验证，尤其是 retention、schema evolution、UPDATE / DELETE 混合输入和 snapshot 降级边界。【推断】
- Java / SQL 与 Python 在 unit tests、data expectations、轻量引擎、incremental 支持上的完整等价性需要继续逐项核验。【猜测】

---

## 八、来源索引

- #6 / `docs/raw/22-pro-code-source-map.md`：资料源与可信度矩阵。
- #7 / `docs/raw/23-code-repositories-engineering-entry.md`：Code Repositories 与高码工程入口。
- #8 / `docs/raw/24-pro-code-runtime-compute-engines.md`：运行时、计算引擎与依赖管理。
- #9 / `docs/raw/25-transform-contract-dag.md`：Transform Contract 与 DAG 推导。
- #10 / `docs/raw/26-pro-code-governance-quality-observability.md`：质量、测试、血缘、权限与可观测性。
- #11 / `docs/raw/27-incremental-scheduling-transaction.md`：增量计算、调度与 Dataset Transaction。
- #14 / `docs/raw/28-pipeline-builder-pro-code-interop.md`：Pipeline Builder 与高码互操作。
