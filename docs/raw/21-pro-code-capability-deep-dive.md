# 21 — Palantir 高码能力深度调研

**日期：** 2026-05-29
**类型：** 技术调研
**覆盖方向：** Code Repositories / Transform DSL / 增量计算 / 工程治理 / 低码互操作 / 可借鉴设计

---

## 0. 可信度标注规则

- 【实时】：本轮调研通过 Palantir 官方文档或当前仓库资料查证到的结论。这里沿用用户给定的标签名，含义等同于“当前已验证事实”。
- 【推断】：由多个【实时】结论组合得出的工程判断，逻辑链明确，但官方未直接以同一句话表达。
- 【猜测】：证据不足，只能作为后续验证假设，不应直接进入设计决策。

---

## 1. 总结论

Palantir 的高码能力强在：它不是把 Spark/Python 暴露给开发者，而是把代码开发、数据资产、依赖声明、调度、增量、测试、质量、版本、权限、血缘和低码协作整合成同一个平台契约。【推断】

换句话说，开发者写的是 Python、Java、SQL 或函数代码，但平台真正沉淀的是“可被理解的生产逻辑”。这也是它比普通 PySpark 作业平台、Airflow DAG、dbt 项目更强的地方。【推断】

---

## 2. 高码能力到底强在哪里

### 2.1 Code Repositories 是平台内 Git 工程环境，不只是代码编辑器

Palantir Code Repositories 提供 Web IDE，并对底层 Git 仓库封装分支、提交、tag、PR/code review、权限、IntelliSense、lint、error checking 和帮助对话框等能力。Transform repositories 支持 Python、Java、SQL，并支持 transform preview/debug。【实时】

工程含义：

- 代码开发不是外部工具链的旁路，而是 Foundry 数据集构建系统的一等入口。【实时】
- PR 与权限控制直接服务数据生产逻辑，而不是只服务普通应用代码。【推断】
- 代码库升级由平台生成 upgrade PR，并可做 impact analysis，说明 runtime/template 升级也被纳入平台治理。【实时】

### 2.2 Transform DSL 让平台静态理解代码

Python transforms 通过 `Input()`、`Output()`、`@transform`、`@transform_df`、`@incremental` 等声明输入、输出和执行语义。官方文档明确 Python 是 Foundry 中最完整的数据转换语言，支持 batch、incremental pipelines、共享代码库、data expectations，以及单节点或多节点 compute engines。【实时】

关键点不是装饰器语法，而是声明式契约：

```python
from transforms.api import transform_df, Input, Output

@transform_df(
    Output("/project/output/clean_events"),
    raw=Input("/project/input/raw_events"),
)
def compute(raw):
    return raw.filter("event_type is not null")
```

这段代码让平台在运行前知道三件事：【推断】

- 这个函数生产哪个 Dataset。
- 它依赖哪个 Dataset。
- 这个 Dataset 生产逻辑可以被调度、血缘、权限和质量系统关联。

### 2.3 多语言高码覆盖不同复杂度

Palantir 高码不是单一 Python 路径：

| 路径 | 已验证能力 | 适合场景 |
|---|---|---|
| Python transforms | batch、incremental、共享库、data expectations、单节点/多节点 compute | 主要数据工程与 ML 特征工程【实时】 |
| Java transforms | Java 库、高低级 Dataset API、batch、incremental、共享库、unit testing | 需要 Java 生态、强类型或 Pipeline Builder 导出代码【实时】 |
| SQL transforms | Spark SQL，适合过滤、聚合、派生、窗口函数；不支持 incremental transforms | 标准 SQL 批处理转换【实时】 |
| Functions repositories | TypeScript/Python 业务逻辑，低延迟执行，并原生访问 Ontology | 面向应用/操作场景的逻辑，而非传统 Pipeline【实时】 |

高码能力的真正边界不是“能不能写代码”，而是每种语言路径是否能被 Foundry 的数据资产模型、运行时、权限和发布流程接管。【推断】

### 2.4 Compute engine 选择被产品化

Python transforms 支持 DuckDB、pandas、Polars 和 Spark。DuckDB/pandas/Polars 属于 single-node lightweight，Spark 用于 distributed compute。官方特性表显示 incremental transforms、external transforms、部分 LLM/API、media set API、dataset unmarking、resource metrics 等能力在不同 compute paradigm 下有差异。【实时】

这说明 Palantir 高码能力不是固定“所有任务上 Spark”，而是把不同计算形态暴露为平台选择项。【实时】

设计启发：

- 小数据、交互式或成本敏感场景应优先 lightweight。【推断】
- 大数据、强 schema、复杂分布式处理仍需要 Spark。【推断】
- 引擎选择必须被纳入能力矩阵，不能只做运行时路由黑盒。【推断】

### 2.5 增量能力基于 Dataset Transaction，而非单纯业务字段

官方增量文档说明，`@incremental()` 包装 transform compute function 后可启用增量计算。默认读模式为 `added`。如果增量输入自上次运行以来只有文件新增，transform 可以增量运行；如果输入发生 full rewrite、update/delete 文件等情况，则不能增量运行，需要 snapshot。【实时】

这与普通增量 ETL 的差异：

- 普通方案常依赖 `updated_at`、主键或 CDC 事件。
- Foundry 增量语义建立在 Dataset Transaction 历史上。
- retention 删除还需要显式 `allow_retention`，否则会破坏增量条件。【实时】

结论：Palantir 的增量不是 transform 内部自己维护状态，而是由 Dataset 版本/事务系统、运行时读模式和输出写模式共同构成。【推断】

### 2.6 调度不是独立 DAG 工具，而是围绕 Dataset 构建

官方 scheduling 文档说明 scheduled builds 可以按时间触发、数据更新触发、逻辑更新触发，或组合触发；可构建单个 Dataset、Dataset 及其依赖、依赖某 Dataset 的所有 Dataset、连接两个 Dataset 的所有 Dataset等。【实时】

这体现了核心平台心智：调度中心不是“任务”，而是“数据集及其依赖图”。【推断】

### 2.7 数据质量和测试进入高码生命周期

Python repository tests 使用 pytest，并可作为 checks 运行；官方文档说明这些 unit tests 只适用于 batch pipelines，不支持 streaming pipelines。【实时】

Data expectations 在 Python transforms 中定义，维护 pipeline 文档说明当 Data Expectation check 失败时可以自动 abort dataset build，从而节省资源并避免下游问题。【实时】

结论：Palantir 高码把测试和质量检查前移到代码库与 Dataset build 生命周期，而不是只在数据落地后监控。【推断】

### 2.8 低码 Pipeline Builder 与高码不是两个孤岛

Pipeline Builder 是 Foundry 的 primary application for data integration，后端会在用户描述 pipeline 时写 transform code，并执行 pipeline integrity checks，提前发现 schema、refactor 等问题。【实时】

Pipeline Builder 还支持将 pipeline export 到已有 Java transforms repository。官方明确限制：导出会转换为 Java transform code 并推送到目标 repository；目标分支已有代码会被删除；导出不可逆；部分转换不能导出；某些自定义优化回退到 native Spark 后输出可能不完全一致。【实时】

结论：

- 低码能力背后不是完全独立的 UI 配置系统，而是有可代码化/可执行的 transform 后端。【推断】
- 低码到高码存在单向升级路径，但不是双向同步。【实时】
- 可视化算子内置优化与代码导出的语义差异，是低码/高码互操作的关键风险。【实时】

---

## 3. 怎么实现：从平台机制看

### 3.1 核心对象模型

```text
Code Repository
  -> Transform definition
    -> Input Dataset references
    -> Output Dataset references
    -> Runtime metadata
    -> Build/check/test metadata
      -> Dataset transaction
        -> Lineage / scheduling / health / governance
```

实现重点是让代码库里的 transform definition 能被平台索引，而不是把代码当普通脚本运行。【推断】

### 3.2 Pipeline DAG 的推导路径

基于已有仓库调研与官方 transform 入口，可以推导出典型链路：【推断】

1. Code Repository 中的 transform 文件声明 `Input` / `Output`。
2. 平台构建或检查时扫描 transform definitions。
3. 输出 Dataset 和输入 Dataset 建立依赖边。
4. Scheduling 和 lineage 系统基于 Dataset graph 工作。
5. Build 运行时注入实际 Dataset view / dataframe / file API。
6. 输出写入新的 Dataset transaction。

待验证点：Palantir 内部扫描、索引与跨 repository 依赖传播的服务边界未在公开文档中完整披露。【猜测】

### 3.3 Runtime 分层

高码 runtime 至少包含三层：【推断】

| 层 | 职责 | 公开证据 |
|---|---|---|
| Authoring layer | Web IDE、Git、PR、lint、template wizard、preview/debug | Code Repositories docs【实时】 |
| Transform runtime | Python/Java/SQL API、compute engine、incremental/read/write modes | Transform docs【实时】 |
| Platform control plane | schedule、checks、repository upgrades、impact analysis、data health | Scheduling/repository upgrade/data expectation docs【实时】 |

### 3.4 低码编译到高码的实现启示

Pipeline Builder 导出 Java code 的限制说明，其内部表达层至少有一部分能映射到 Java transform；但由于 UDF、LLM call、Palantir custom optimizations 等无法完整转译，低码表达 IR 与通用代码之间不是一一等价关系。【实时】

对我们借鉴时的结论：【推断】

- 低码 Builder 应先有稳定 IR，再考虑代码导出。
- 代码导出应定位为“迁移/升级”，不要承诺双向同步。
- UI 算子的平台优化若无法导出，必须在导出报告中显式标注语义风险。

---

## 4. 怎么借鉴

### 4.1 必须借鉴的底层设计

1. 以 Dataset 为平台核心对象，而不是以任务为核心对象。【推断】
2. 高码 API 必须声明输入、输出、参数、运行时、质量规则，不能只暴露自由脚本。【推断】
3. 增量能力要绑定 Dataset transaction/read mode/write mode，避免每个 transform 自己发明增量协议。【推断】
4. 低码和高码必须共享同一个 transform contract，否则治理、血缘、调度会分叉。【推断】
5. 测试、检查、发布、升级影响分析要进入高码生命周期。【推断】

### 4.2 可以分阶段借鉴的能力

| 阶段 | 建设重点 | 原因 |
|---|---|---|
| P0 | Dataset 版本模型、Transform contract、Input/Output 声明、静态 DAG | 没有这些就无法平台化【推断】 |
| P1 | Spark + lightweight engine router、增量 transaction、build checks | 形成可生产运行的高码平台【推断】 |
| P2 | 低码 Builder IR、代码导出、data expectations、unit test harness | 提升协作与工程质量【推断】 |
| P3 | Ontology/应用 writeback、AIP code assist、repository upgrade impact analysis | 形成端到端业务平台闭环【推断】 |

### 4.3 不应直接照搬的点

- 不应一开始复制完整 Foundry UI；先做 Dataset/Transform/Build/Lineage 契约。【推断】
- 不应把所有高码都放到 Spark；lightweight engine 对成本和开发体验有直接价值。【推断】
- 不应承诺低码和高码完全双向转换；Palantir 官方导出也明确不可逆。【实时】
- 不应把增量简化成 `updated_at` 过滤；这会绕开 Dataset transaction 的平台价值。【推断】

---

## 5. 关键风险与待验证问题

1. 跨 Repository 依赖索引、延迟和一致性机制未从公开文档中完整获得。【猜测】
2. Pipeline Builder 后端生成 transform code 的内部 IR 与存储模型未公开。【猜测】
3. Incremental transform 在复杂 UPDATE/DELETE、retention、schema evolution 下的边界需要用真实环境验证。【推断】
4. Data expectations 在 lightweight 与 Spark 上能力不完全一致，落地时需要明确功能矩阵。【实时】
5. SQL transforms 不支持 incremental transforms，不能把 SQL 路径当完整高码替代品。【实时】

---

## 6. 参考来源

- Palantir Code Repositories Overview: https://www.palantir.com/docs/foundry/code-repositories/overview/index.html
- Palantir Create transforms: https://www.palantir.com/docs/foundry/code-repositories/create-transforms
- Palantir Python transforms Overview: https://www.palantir.com/docs/foundry/transforms-python/overview
- Palantir Incremental Python transforms: https://www.palantir.com/docs/foundry/transforms-python/incremental-usage
- Palantir Compute engine selection: https://www.palantir.com/docs/foundry/transforms-python/compute-engines
- Palantir Python Unit tests: https://www.palantir.com/docs/foundry/transforms-python/unit-tests/
- Palantir Data expectations reference: https://www.palantir.com/docs/foundry/transforms-python/data-expectations-reference/
- Palantir Java transforms Overview: https://www.palantir.com/docs/foundry/transforms-java/overview
- Palantir SQL transforms Overview: https://www.palantir.com/docs/foundry/transforms-sql/overview
- Palantir Pipeline Builder Overview: https://www.palantir.com/docs/foundry/pipeline-builder/overview
- Palantir Export pipeline code: https://www.palantir.com/docs/foundry/pipeline-builder/export-pipeline
- Palantir Scheduling Overview: https://www.palantir.com/docs/foundry/building-pipelines/scheduling-overview
- Palantir Repository upgrades: https://www.palantir.com/docs/foundry/code-repositories/repository-upgrades
