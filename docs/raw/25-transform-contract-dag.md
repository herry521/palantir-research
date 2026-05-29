# 25 — Transform Contract 与 DAG 推导机制调研

**日期：** 2026-05-29
**关联 Issue：** #9
**类型：** Transform Contract / DAG / lineage / scheduling 机制调研
**写入范围：** 本文件

---

## 背景

本文件承接 `docs/raw/22-pro-code-source-map.md` 对 Story #9 的资料源映射，并复核 `docs/raw/01-pipeline-expression-dsl.md`、`docs/raw/07-code-pipeline.md` 中关于“装饰器即声明、路径即依赖、Pipeline 注册入口”的早期结论。

本轮调研优先使用 Palantir 官方公开文档，重点关注 Code Repositories、Python transforms、Java transforms、SQL transforms、Data Lineage 与 Scheduling。未使用本地浏览器；官方资料通过服务器侧检索/抓取确认。

---

## 可信度规则

| 标签 | 含义 | 使用方式 |
|---|---|---|
| 【事实】 | 本轮已由 Palantir 官方公开文档或仓库既有资料直接确认 | 可作为事实基线 |
| 【推断】 | 多个【事实】事实组合出的工程判断，但官方未以同一句话公开说明 | 可进入架构建议，但需保留边界 |
| 【猜测】 | 官方公开资料未披露，或证据不足 | 只作为验证问题，不作为设计前提 |

注意：这里使用“事实”标签表示“当前已验证事实”，不是“实时流处理能力”。

---

## 核心结论

1. Foundry Transform Contract 的核心不是普通函数签名，而是“输入数据集、输出数据集、计算函数、运行配置、Pipeline 注册入口”的组合元数据。【事实】Java 官方文档明确称 `Transform` 描述如何计算一个 dataset，包含 input/output datasets、compute function 和额外配置；这些信息被指定在 `Transform` 对象中并注册到 `Pipeline`。
2. Python transform 通过 `Input()` / `Output()` 与装饰器声明数据依赖，`Pipeline` 作为 Transform 对象注册表，默认 `pipeline.py` 使用 `discover_transforms(datasets)` 自动发现 `datasets` 包中的 Transform。【事实】
3. Java transform 通过 `@Input` / `@Output` / `@Compute` 注解表达 contract，并通过 `PipelineDefiner`、`Pipeline.autoBindFromPackage()` 或 `Pipeline.register()` 注册到 Pipeline。【事实】
4. SQL transforms 是 Foundry 高码路径之一，使用 Spark SQL 表达转换，但官方明确 SQL transforms 不支持 incremental transforms。【事实】
5. Foundry 调度围绕 Dataset 与 Data Lineage 图组织：schedule 可以按时间、数据更新、逻辑更新触发，并可构建单个 dataset、dataset 及其依赖、依赖某 dataset 的全部下游，或两个 dataset 之间的连接集合。【事实】
6. “路径/RID 是依赖锚点”的表述需要分层：Transform API 示例主要使用 dataset path/location，Foundry 平台资源也有标准化 RID；公开文档确认两者都能标识 dataset，但未公开说明内部 DAG 索引一定以 path 还是 RID 为主键。【推断】
7. 自建 SDK 若想模拟 Foundry，应把 Transform Contract 设计成静态可解析的 manifest/IR，而不是只解析任意业务代码；Input/Output 必须是可审计、可注册、可比较的资源引用。【推断】
8. 跨 repository 全局 DAG、事件传播延迟、冲突检测细节、lineage 索引内部表结构没有在公开文档完整披露。【猜测】

---

## Transform Contract 元模型

### 最小元模型

```text
TransformContract
  id: transform identifier
  language: python | java | sql | pipeline-builder | other
  repository: code repository reference
  entryPoint: pipeline entry point / service loader / SQL artifact
  inputs: DatasetRef[]
  outputs: DatasetRef[]
  compute: function/method/query reference
  runtime: engine/profile/configuration
  buildMode: snapshot | incremental-capable | streaming-capable
  qualityPolicy: expectations/tests/checks, if declared
  versioning: code revision + transform logic version + dataset transactions

DatasetRef
  path/location: human project path, when available
  rid: stable platform resource identifier, when available
  branch: dataset/global branch context, when relevant
```

### 元模型依据

- Python 默认项目结构包含 `pipeline.py`；官方称该文件定义项目的 `Pipeline`，即与数据转换关联的 `Transform` 对象注册表。【事实】
- Python 默认 `pipeline.py` 示例为 `my_pipeline = Pipeline()` 与 `my_pipeline.discover_transforms(datasets)`；官方说明自动注册会发现项目 `datasets` 包中的所有 Transform 对象。【事实】
- Python `setup.py` 默认导出 `transforms.pipelines` entry point，运行时需要通过该入口找到项目的 `Pipeline` 对象。【事实】
- Java 每个 transforms Java subproject 暴露一个 `Pipeline` 对象；官方称该对象用于“注册 Foundry 中 dataset 的构建说明”并在 build 时定位负责构建目标 dataset 的 `Transform`。【事实】
- Java high-level / low-level Transform 的差异影响 contract 表达：high-level 返回 `Dataset<Row>`，low-level 显式写 output，low-level 支持多输出与文件访问。【事实】
- Foundry 资源有 RID，第三方 BI 文档确认 Dataset 可用 RID 或 Location/filepath 指定；API 文档也把 dataset RID 作为 Dataset API path parameter。【事实】
- 由此可推断：面向平台的稳定 contract 至少需要同时容纳“人可读路径/location”和“平台稳定 RID”，否则无法同时支持代码 authoring、API 调用、重命名/移动、权限和 lineage 场景。【推断】

---

## DAG 推导流程

### 1. Authoring 阶段：声明输入输出

Python 中，开发者使用 `Input('/path')`、`Output('/path')` 和 `@transform` / `@transform_df` / `@transform.using` / `@transform.spark.using` 声明输入输出。【事实】官方示例展示了单输入单输出、多输入多输出，以及 PySpark `transform_df` 直接注入 DataFrame 的形式。

Java 中，开发者使用 `@Input("/path")`、`@Output("/path")`、`@Compute` 注解声明输入、输出与计算函数。【事实】官方文档要求 compute function 是 public、non-static，并标注 `@Compute`，否则不会正确注册。

SQL 中，转换逻辑以 Spark SQL 表达；公开概览只确认 SQL transforms 属于 Code Repositories batch pipeline 路径，未在 overview 中展开 Python/Java 同级的注解机制。【事实】

### 2. Registration 阶段：把 transform 暴露给运行时

Python 的 `Pipeline` 是 Transform 对象注册表，自动注册通过 `discover_transforms()` 递归发现模块或包内 Transform；手动注册通过 `add_transforms()` 加入并检查是否有两个 Transform 声明同一 output dataset。【事实】

Java 的自动注册通过 `Pipeline.autoBindFromPackage()` 发现包中带所需 `@Input` / `@Output` 注解的 Transform；手动注册通过 `Pipeline.register()`。【事实】

因此，“平台扫描代码得到 DAG”更精确的表述应是：语言 SDK 在仓库构建/运行时通过约定入口暴露已注册 Transform Contract，平台再把 outputs 与 inputs 连接成可构建的 dataset graph。【推断】

### 3. Resolution 阶段：解析 DatasetRef

Transform Contract 中的 `Input` / `Output` 引用通常在代码示例中表现为 dataset path/location。【事实】Foundry 平台同时为 resource 提供 RID，并且 Dataset API 使用 dataset RID 获取 dataset。【事实】

调度和 lineage 需要跨应用、跨分支、跨权限边界定位资源，因此内部很可能会把 path/location 解析到平台资源 ID，再维护 graph 边。【推断】公开文档未确认内部索引字段、缓存策略或 path 变更后的重绑定规则。【猜测】

### 4. Graph 生成阶段：连接 output producer 与 input consumer

如果 Transform A 声明 output dataset X，Transform B 声明 input dataset X，则 B 依赖 A 的输出。【推断】这个结论由 Input/Output contract、Pipeline 注册、Data Lineage 图和 Scheduling 可按 dependencies/upstream/downstream 构建共同推出；官方未以“算法步骤”公开描述。

Data Lineage 官方文档确认用户可展开 dataset 的 ancestors/descendants，查看 schema、last build time、生成数据的 code，并能跳转到 repository 中的原始代码。【事实】这说明 Foundry 至少保存了 dataset 节点、父子关系、构建状态与代码 provenance 的可查询元数据。

### 5. Scheduling 阶段：从 graph 选择构建范围

官方 Scheduling 文档确认 scheduled builds 可由时间、数据更新、逻辑更新触发，也可构建单个 dataset、单个 dataset 及其 dependencies、依赖某 dataset 的全部下游、连接两个 dataset 的全部 datasets 等范围。【事实】

Create schedule 文档确认 schedule editor 位于 Data Lineage，并且 target datasets、excluded datasets 会影响 graph traversal；dataset 更新可作为事件触发条件。【事实】

因此 Foundry 的调度心智更接近“Dataset graph 上的构建范围选择”，而不是 Airflow 式“预先手写 task DAG 后按 task 执行”。【推断】

### 6. Incremental 与 staleness

Python incremental 文档确认 `@incremental` 可叠加到 transforms，并使用 `snapshot_inputs`、retention 相关配置等影响增量可行性；输入发生非增量兼容变更时会触发 snapshot。【事实】

Java incremental 文档确认 API 可读取 input modification type，并据此选择 `ReadRange` 与 `WriteMode`，例如 append-only 可读 unprocessed，updated/new view 可读 entire view 或写 snapshot。【事实】

增量计算不是 DAG 结构本身，而是每条输入边上的“变更类型、事务范围、读写模式”决定当前 build 是否可局部推进。【推断】

---

## Python / Java / SQL 差异

| 维度 | Python | Java | SQL |
|---|---|---|---|
| Contract 表达 | `Input()` / `Output()` + decorator | `@Input` / `@Output` / `@Compute` + class/method | SQL transform artifact / Spark SQL |
| 注册入口 | `Pipeline` + `discover_transforms()` 或 `add_transforms()`；`setup.py` entry point | `PipelineDefiner` + `autoBindFromPackage()` 或 `register()`；Java service loading | Code Repositories batch pipeline 路径，公开 overview 未展开同等细节 |
| 多输出 | `@transform.using` / `@transform.spark.using` 支持多输出；`transform_df` 更偏单输出 DataFrame 返回 | low-level Transform 支持多输出；high-level 更偏 DataFrame 返回 | 公开 overview 未确认多输出能力 |
| 数据对象 | pandas / Polars / DuckDB / PySpark 等，视 decorator 与 compute engine 而定 | Spark `Dataset<Row>` / `FoundryInput` / `FoundryOutput` | Spark SQL |
| 增量能力 | 官方支持 incremental transforms，含 snapshot inputs、retention、read/write mode 语义 | 官方支持 incremental transforms，显式读取 modification type 并选择 read/write mode | 官方明确不支持 incremental transforms |
| 适合场景 | 灵活高码、PySpark、轻量引擎、Python 生态 | 强类型、Java 生态、Pipeline Builder 导出路径相关场景 | SQL 转换、过滤、聚合、窗口函数等 |

以上差异中，Python/Java 的 Input/Output contract 和 Pipeline 注册均有官方直接支撑。【事实】SQL 的 contract 细节公开资料不足，只能确认其作为 Code Repositories SQL transforms 路径以及不支持 incremental。【事实】

---

## 与 Airflow / dbt / Dagster 对比

| 维度 | Foundry Transforms | Airflow | dbt | Dagster |
|---|---|---|---|---|
| 主要抽象 | Dataset + Transform Contract + Lineage graph【推断】 | Task/operator DAG【事实】 | SQL model + `ref()` 依赖【事实】 | Asset/op graph【事实】 |
| 依赖声明 | Input/Output dataset refs【事实】 | Python DAG 中显式 task dependency【事实】 | `ref()` / source / YAML【事实】 | asset keys / deps / op graph【事实】 |
| 调度范围 | 可按 dataset、dependencies、downstream、between datasets 选择【事实】 | 通常按 DAG run/task run 组织【推断】 | 通常按 selector/model graph 组织【推断】 | 可按 assets/jobs/schedules/sensors 组织【推断】 |
| 血缘 | Data Lineage app 展示 ancestors/descendants、build、code provenance【事实】 | 依赖外部 lineage 集成或 operator 元数据【推断】 | model graph 内置，跨系统 lineage 需集成【推断】 | asset lineage 是核心概念【事实】 |
| 计算逻辑 | Python/Java/SQL 等 Foundry 托管 transforms【事实】 | 任意 operator，平台不天然理解业务数据输出【推断】 | SQL 为主【事实】 | Python 定义资产/ops，执行器可插拔【事实】 |
| 平台绑定 | 强绑定 Foundry Dataset/RID/权限/lineage【推断】 | 开源编排器【事实】 | 数仓/适配器生态【事实】 | 开源编排与资产平台【事实】 |

Foundry 最像 dbt/Dagster 的地方是“数据资产图”心智，最不像 Airflow 的地方是调度文档直接围绕 dataset dependencies/downstream graph 而非 task dependency graph 描述。【推断】

Foundry 与 dbt 的关键差异不是“有没有 DAG”，而是 DAG 节点语义不同：dbt 的核心节点通常是 SQL model，Foundry 的公开调度与 lineage 文档更突出 dataset/resource，并把生成 dataset 的 code 作为 provenance 展示。【推断】

Foundry 与 Dagster 的接近点是 asset graph，但 Foundry 的资源、权限、branch、dataset transaction、Data Lineage 与 Code Repositories 是平台内一体化能力；Dagster 通常需要自行接入存储、权限和外部 catalog。【推断】

---

## 对自建 SDK 建议

1. 把 `Input` / `Output` 设计为一等公民，不要让用户在业务函数里手写 `read(path)` / `write(path)` 作为唯一依赖来源。【推断】
2. 生成稳定的 `TransformContract` manifest：包含 language、entry point、inputs、outputs、compute reference、runtime config、version、quality policy。【推断】
3. 同时支持 human path 与 stable resource id：path 便于 authoring，RID/id 便于重命名、权限、跨 repo 引用和 API 调用。【推断】
4. 在注册阶段检查同一 branch/scope 下的 output 唯一性；Python 官方 `add_transforms()` 会检查两个 Transform 是否声明相同 output dataset，可作为设计参照。【事实】
5. 把 DAG builder 放在 contract 层，而不是解析任意 AST 的业务逻辑层；decorator/annotation/SQL artifact 只负责生成 contract。【推断】
6. 调度器应支持 graph traversal primitives：build target、build upstream dependencies、build downstream dependents、build path between datasets、exclude nodes。【推断】
7. 增量能力应建模为边和 transaction 上的状态：input modification type、read range、write mode、snapshot input、semantic version，而不是单个 boolean。【推断】
8. Lineage UI/API 至少应能回答：此 dataset 的 direct parents/children、全部 ancestors/descendants、最后 build、生成代码位置、当前 staleness、branch 上的资源状态。【推断】
9. 对 Python 类 SDK，保持 decorator 参数名与函数参数绑定的可验证规则；对 Java 类 SDK，保持 annotation 与 registration 的编译期/启动期校验。【推断】
10. 对 SQL 类 SDK，明确是否支持 incremental；若不支持，应像 Foundry SQL transforms 一样在文档中直接声明，避免用户误解。【推断】

---

## 证据缺口

1. Foundry 内部到底以 dataset path、RID、branch-qualified RID，还是其他 ResourceRef 作为 DAG 边主键，公开文档未披露。【猜测】
2. 跨 Code Repository 的依赖发现、缓存刷新、事件传播延迟、最终一致性和失败重试策略，公开文档未完整披露。【猜测】
3. 循环依赖检测的具体发生阶段、错误类型、跨 branch 行为，公开资料不足；只能从 DAG/lineage/scheduling 必须保持可遍历这一点推断存在相关校验。【推断】
4. SQL transforms 在 Code Repositories 中的完整 contract manifest、注册入口和多输出能力，overview 资料不足，需要更细页面或真实环境验证。【猜测】
5. Data Lineage 与 Scheduling 的内部数据模型、索引表、权限裁剪方式未公开，不能直接复刻为设计事实。【猜测】
6. Pipeline Builder 导出到 Java transforms 后，节点级 IR 与 Java Transform Contract 的字段映射细节未公开；不能假设低码/高码完全无损互转。【推断】

---

## 参考来源

### 官方 Palantir 文档

1. Code Repositories - Create transforms: <https://www.palantir.com/docs/foundry/code-repositories/create-transforms>
2. Python transforms - Overview: <https://www.palantir.com/docs/foundry/transforms-python/overview>
3. Python transforms - Transforms: <https://www.palantir.com/docs/foundry/transforms-python/transforms>
4. Python transforms - Pipelines: <https://www.palantir.com/docs/foundry/transforms-python/pipelines>
5. Python transforms - Project structure: <https://www.palantir.com/docs/foundry/transforms-python/project-structure>
6. Python incremental transforms - Usage guide: <https://www.palantir.com/docs/foundry/transforms-python/incremental-usage>
7. Java transforms - Overview: <https://www.palantir.com/docs/foundry/transforms-java/overview>
8. Java transforms - Transforms and pipelines: <https://www.palantir.com/docs/foundry/transforms-java/transforms-pipelines/>
9. Java incremental transforms: <https://www.palantir.com/docs/foundry/transforms-java/incremental-transforms>
10. SQL transforms - Overview: <https://www.palantir.com/docs/foundry/transforms-sql/overview>
11. Building pipelines - Supported languages: <https://www.palantir.com/docs/foundry/building-pipelines/supported-languages>
12. Building pipelines - Scheduling overview: <https://www.palantir.com/docs/foundry/building-pipelines/scheduling-overview>
13. Building pipelines - Create a schedule: <https://www.palantir.com/docs/foundry/building-pipelines/create-schedule>
14. Data Lineage - Overview: <https://www.palantir.com/docs/foundry/data-lineage/overview/>
15. Data Lineage - Explore lineage: <https://www.palantir.com/docs/foundry/data-lineage/explore-lineage/index.html>
16. Data Lineage - Branching data lineage: <https://www.palantir.com/docs/foundry/data-lineage/branching-data-lineage/>
17. Projects and resources: <https://www.palantir.com/docs/foundry/getting-started/projects-and-resources>
18. Identify a dataset's RID or filepath: <https://www.palantir.com/docs/foundry/analytics-connectivity/identify-dataset-rid/>
19. Get Dataset API: <https://www.palantir.com/docs/foundry/api/datasets-v2-resources/datasets/get-dataset/>

### 本仓库资料

1. `docs/raw/22-pro-code-source-map.md`
2. `docs/raw/01-pipeline-expression-dsl.md`
3. `docs/raw/07-code-pipeline.md`

### 对比框架官方/一手资料

1. Apache Airflow - Tasks: <https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/tasks.html>
2. Apache Airflow - DAGs: <https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/dags.html>
3. dbt Developer Hub - `ref` function: <https://docs.getdbt.com/reference/dbt-jinja-functions/ref>
4. dbt Labs - What is data lineage: <https://www.getdbt.com/blog/what-is-data-lineage>
5. dbt Labs - On DAGs, Hierarchies, and IDEs: <https://www.getdbt.com/blog/on-dags-hierarchies-and-ides>
6. Dagster - Assets: <https://docs.dagster.io/guides/build/assets>
