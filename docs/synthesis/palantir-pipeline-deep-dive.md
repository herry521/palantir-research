# Palantir Pipeline 技术实现深度分析

**日期：** 2026-04-16  
**类型：** 技术调研  
**覆盖方向：** Pipeline 表达层 / Pipeline Builder 算子基线 / 算子平台 / 执行引擎 / 流批架构 / 血缘与 Ontology 集成

---

## 背景

本报告聚焦 Palantir Foundry 的 Pipeline 技术实现，从六个维度并行调研：
1. Pipeline 表达层 DSL 与 Transform 抽象
2. Pipeline Builder 算子基线：transform 与 expression 两条主线
3. 执行引擎 Spark 集成与增量计算
4. 流批一体架构与 Streaming Pipeline
5. 数据血缘与 Ontology-Pipeline 集成
6. 算子平台设计：契约、注册、执行路由、治理与建设优先级

原始调研文件：`docs/raw/01~05-*.md`、`docs/raw/14-transform-operator-library.md`，以及外部仓库 `/Users/huyongqiang/code/li/pipeline-transform-research` 的算子总结、HTML 总览和 final bundle。

专题方案文件：`docs/synthesis/operator-platform-design.md`

---

## 一、Pipeline 表达层：DSL、transform 和 expression 的共同契约

### 1.1 Transform 装饰器体系

Foundry 的 Pipeline 编程模型通过 Python 装饰器实现声明式 DAG 定义：

```python
from transforms.api import transform_df, Input, Output

@transform_df(
    Output('/project/output/enriched_events'),
    raw=Input('/project/input/raw_events'),
    config=Input('/project/input/config'),
)
def compute(raw, config):
    return raw.join(config, 'type_id').filter('valid = true')
```

三种核心装饰器的差异：

| 装饰器 | 输入类型 | 输出约束 | 适用场景 |
|---|---|---|---|
| `@transform_df` | PySpark DataFrame（自动注入） | 单输出 | 标准 Spark 转换（最常用） |
| `@transform` | `TransformInput` 对象（手动 `.dataframe()`） | 多输出支持 | 复杂逻辑、多输出写入 |
| `@transform_pandas` | Pandas DataFrame | 单输出 | 中小数据集、科学计算 |

### 1.2 DAG 自动构建原理

**关键洞察：路径即依赖**

Foundry 以**数据集路径（Dataset Path）为节点**，以 Transform 为边，自动构建有向无环图：
- 无需显式 `set_upstream()` / `>>` 算子（对比 Airflow）[事实]
- `@transform_df(Output('/a'), source=Input('/b'))` 即声明 `/b → /a` 的依赖边[事实]
- Foundry 平台级依赖管理（官方称 **Automation dependencies**）统一收集所有 Transform 的声明，构建全局 DAG[事实]

**`pipeline.py` 是注册入口：**
```python
# 所有 Transform 必须通过 Pipeline 对象注册才能被调度系统感知
my_pipeline = Pipeline()
my_pipeline.discover_transforms()  # 扫描当前包下所有 @transform 函数
```

### 1.3 Pipeline Builder 算子分层

外部 `pipeline-transform-research` 调研说明，Pipeline Builder 的可见算子能力不能只理解成一组 Transform 函数。它至少分成两层：
- **转换算子（transform）**：数据集级转换，描述 Pipeline Builder 中的处理步骤，例如 Aggregate、Pivot、Window、Mapping join、Parse Excel、Key by。
- **表达式函数（expression function）**：字段和值级表达，描述某个列、值或结构如何计算，例如数值、布尔、字符串、时间、类型转换、数组、结构体、JSON 和 Map 函数。

这个分层会反过来影响 Transform DSL 的理解：`Input` / `Output` 解决 Dataset graph 的依赖声明，transform / expression 解决 Builder 节点内部的语义、参数和类型校验。也就是说，表达层不是“装饰器 + Spark 代码”这么简单，而是由 Dataset 依赖契约、算子能力目录、表达式类型系统和低代码 / 高码互操作共同组成。【事实 + 推断】

当前可直接复用的外部调研基线是 89 条 transform 和 335 条 expression final bundle。全局调研后续引用算子能力时，应优先回到这两套 final bundle，而不是回到自动解析、stage、verify 或临时渲染文件。【事实】

### 1.4 与 dbt 的本质区别

| 维度 | Foundry Transforms | dbt |
|---|---|---|
| 执行引擎 | 托管 Spark（任意 PySpark 代码） | 数仓原生 SQL（仅 SQL） |
| 多输出 | 支持（`@transform`） | 不支持（1 Model = 1 输出） |
| 流处理 | 支持（Structured Streaming） | 不支持 |
| Dataset 版本 | 内置 Transaction/Branch | 无 |
| Ontology 集成 | 深度原生集成 | 无对应概念 |
| 平台绑定 | 强绑定 Foundry | 数仓无关 |

---

## 二、执行引擎：托管 Spark + Transaction-based 增量计算

### 2.1 托管 Spark 架构

Foundry 对用户完全隐藏集群运维：
- 用户通过 **Compute Profile**（XS/S/M/L/XL）选择资源规格[事实]
- 每个 Build 在独立 Spark Application 中执行（强隔离）[事实]
- `TransformInput/Output` 对象自动处理 Dataset 的 Transaction 版本隔离[事实]

### 2.2 增量计算：Transaction 驱动的差量执行

这是 Foundry Pipeline 最核心的技术设计之一。

**Transaction 类型决定增量可行性：**

```
上游 Dataset 自上次 Build 后的 Transaction 类型？
├── APPEND（只新增文件）→ 增量运行：只处理新增数据
├── UPDATE（覆写已有数据）→ 触发全量重算
└── SNAPSHOT（全量替换）→ 触发全量重算
```

**`@incremental` 装饰器关键参数：**

```python
@incremental(
    snapshot_inputs=['config'],  # 允许 config 全量变化，不阻断增量
    require_incremental=True,    # 强制增量，否则 Build 失败
    semantic_version=2,          # 逻辑变更时递增，触发全量重算
    v2_semantics=True,           # 推荐：更广泛的兼容性
)
@transform_df(Output('/out'), events=Input('/in'), config=Input('/cfg'))
def compute(events, config):
    # events 只包含上次 Build 后的新增数据
    return events.join(config, 'type_id')
```

**增量模式的主要运维问题：**
- 长期 APPEND-only 累积大量 Parquet 小文件，读性能劣化
- 解决方案：定期触发 SNAPSHOT Build 合并文件（类似 Delta Lake `OPTIMIZE`）

### 2.3 调度与 DAG 执行

```
Schedule（时间/事件触发）
    │
    ▼
Build Service：解析 DAG 拓扑
    │  ├── 同层无依赖的 Transform → 并行执行
    │  └── 有依赖关系的 Transform → 拓扑顺序执行
    ▼
Spark Job 执行 → 写入新 Transaction
    │
    ▼
FDS 事件广播 → 触发下游 Build（事件驱动传播）
```

---

## 三、流批架构：Flink Streaming Pipeline + Ontology 层统一

### 3.1 流处理技术栈

**⚠️ 重要修正：流处理引擎是 Apache Flink，非 Spark Structured Streaming**

Foundry 流批使用**不同引擎**，由 Pipeline Builder 统一界面屏蔽：
- **批处理**：Apache Spark（`@transform_df` 等 Code Repository 路径）[事实]
- **流处理**：Apache Flink（Pipeline Builder Streaming Pipeline）[事实]

Flink 在 Foundry 中的关键机制：
- **Keyed State**：有状态转换必须指定 Partition Key，同 Key 记录路由到同一算子实例[事实]
- **Checkpointing**：定期快照状态 + 流位置，故障后无数据丢失地恢复[事实]
- **一致性模式**：`AT_LEAST_ONCE`（默认，低延迟）和 `EXACTLY_ONCE`（需配置，有额外开销）[事实]

典型端到端延迟：**在推荐配置下可达 < 15 秒**（非硬性 SLA，受数据量、算子复杂度、Compute 规格影响）[事实]

**Kafka 集成流程：**
```
Kafka Topic（原始二进制）
    │ [Foundry Kafka Connector]
    ▼
Foundry Stream Dataset（value 列）
    │ [Pipeline Builder: bytes → string → JSON parse]
    ▼
结构化 Dataset
    │ [业务 Transform]
    ▼
Ontology Object Type / 时序应用
```

### 3.2 Pipeline Builder 与 Code Repository：并列关系

Pipeline Builder 和 Code Repository 是**并列关系**，非主从：
- **批处理**：两者均可独立完成，Code Repository 更适合复杂逻辑，Pipeline Builder 适合低代码场景
- **流处理**：主要通过 Pipeline Builder 构建；Code Repository 提供 UDF 补充自定义逻辑
- Pipeline Builder 支持将 Pipeline 逻辑**导出为代码**，促进互操作
- AIP 支持自然语言生成 SQL/PySpark 逻辑，加速开发

### 3.3 流批统一的实现层次

**重要认知纠正：Foundry 的流批统一不在 API 层，而在 Ontology 层**

| 层次 | 是否统一 | 说明 |
|---|---|---|
| 编程 API | ❌ 否 | 流用 Pipeline Builder，批用 `@transform_df` |
| 执行引擎 | ❌ 否 | 批处理主要用 Spark，流处理使用 Flink |
| 数据目的地 | ✅ 是 | 流/批输出都写入 Foundry Dataset / Ontology |
| 上层应用 | ✅ 是 | Workshop/Slate/AIP 无感知数据来自流还是批 |

### 3.4 选型决策

| 场景需求 | 推荐方案 | 理由 |
|---|---|---|
| < 15s 延迟 | Streaming Pipeline | 唯一满足要求的方案 |
| 分钟级延迟可接受 | Incremental Batch | 成本低，开发简单 |
| 复杂 ML 特征工程 | Full Batch | 计算稳定性优先 |
| 流数据 + 历史 Join | Streaming + Ontology | 流写 Ontology，批历史通过 Object 关联 |

---

## 四、数据血缘与 Ontology：从数据到业务实体的语义提升

### 4.1 血缘架构

**Foundry Automation dependencies 是血缘基础设施**：
- 所有 Transform 的 Input/Output 声明在 Build 时自动注册
- 形成跨 Repository 的全平台统一血缘图
- Data Lineage App 基于此提供可视化（支持影响分析 + 触发 Build）
- 注："FDS/Foundry Dependency Services"为非官方术语，官方文档使用 Automation dependencies

**血缘粒度：**
- Dataset 级别：自动捕获，全量支持
- Column 级别：Pipeline Builder SQL 路径部分支持，手写 PySpark 不支持

### 4.2 Dataset 版本管理（Git for Data）

```
Dataset
  └── Branch（master + 开发分支）
        └── Transaction（每次写入 = 一个不可变版本）
              ├── APPEND：新增文件（增量友好）
              ├── UPDATE：覆写数据
              └── SNAPSHOT：全量替换
```

**关键限制：Dataset Branch 不支持 Merge**[事实]
- 与 Git 类比容易误导：代码 Repo 可 Merge，数据集 Branch 不行[事实]
- 多团队协作时需通过 Transform 将数据从一个 Branch 读出写入另一个 Branch[推断]

### 4.3 Ontology 集成的技术路径

**Pipeline → Ontology（正向）：**
```
Transform Output Dataset
    ↓ [Ontology Manager 配置绑定：列 → Object Property]
Object Type（业务实体）
    ↓
Workshop/AIP/应用层消费
```

**应用 → Pipeline（反向 Writeback）：**
```
用户在应用中修改 Object Property
    ↓ [Ontology Action]
Writeback Dataset（变更记录）
    ↓ [Pipeline Build（调度/手动触发）]
原始数据集更新 / 外部系统写回
```

**Writeback 延迟说明：** Writeback Dataset 不是实时自动更新的，依赖 Build 触发，存在**分钟级延迟**。[事实]

### 4.4 开放性短板：与 OpenLineage 不兼容

Foundry 使用私有血缘模型，**未原生支持 OpenLineage 标准**，导致：[事实]
- 无法与 dbt、Databricks、Airflow 的血缘图互通[推断]
- 在多平台企业环境中形成数据血缘孤岛[推断]
- 这是 Foundry 与开源生态最显著的集成壁垒之一[推断]

---

## 五、工程实践：测试框架与数据接入层

### 5.1 Transform 单元测试框架

Foundry 提供 `TransformRunner + InMemoryDatastore + pytest` 测试体系：

```python
from transforms.verbs.testing.TransformRunner import TransformRunner
from transforms.verbs.testing.datastores import InMemoryDatastore
from transforms.api import Pipeline

def test_enrich(spark_session):
    store = InMemoryDatastore()
    store.store_dataframe('/input/events', df_events)
    store.store_dataframe('/input/config', df_config)

    pipeline = Pipeline()
    pipeline.add_transforms(enrich_events)
    runner = TransformRunner(pipeline, datastore=store)

    result = runner.build_dataset(spark_session, '/output/enriched')
    assert result.count() == 2
```

关键约束：
- CI 环境无法访问真实 Foundry Dataset，**必须用 InMemoryDatastore**
- 测试数据需硬编码在 Repository 中，不依赖生产数据
- 增量 Transform 测试需模拟 APPEND 事务的顺序执行，逻辑较复杂

### 5.2 Data Connection 数据接入层

Data Connection 是 Pipeline 的上游入口，负责将外部数据源接入 Foundry Dataset：

**增量同步与 Transform 增量计算的区别（重要）：**
- **Data Connection 增量同步**：解决"外部数据怎么进 Foundry"（只拉增量，减少源系统压力）
- **`@incremental` Transform**：解决"进来的数据怎么高效处理"（只处理新 Transaction）
- 两者相互独立，需配合使用才能实现端到端增量

**Schema 演化是接入层最常见痛点：**
- 静态 Schema 固化后，源系统字段变更会导致接入失败
- 增量 Pipeline 中批次间 Schema 不一致会引发合并错误
- 建议：接入层固化 Schema，Transform 层做容错处理

---

## 六、算子平台：把转换逻辑做成可治理的产品能力

### 6.1 核心判断

本节补充吸收 `/Users/huyongqiang/code/li/pipeline-transform-research` 中的算子调研总结、最终清单和 HTML 总览页。该外部调研已经把 Pipeline Builder 算子拆成两条主线：转换算子（transform）负责数据集级转换，表达式函数（expression function）负责字段和值级表达。【事实，来自外部仓库 `docs/pipeline-builder-operators-research-summary.md` 与 `docs/pipeline-builder-operators-overview.html`】

这改变了全局调研里对“算子平台”的表述重点：算子不是泛泛的函数库，而是低代码 Builder 中可被发现、配置、校验、预览、执行和治理的能力目录。全局建设路线应把算子清单、类型系统、执行适配器和证据边界一起考虑，而不是只讨论 Transform DSL 或 Spark/Flink 执行。【推断】

### 6.2 Transform / Expression 两条主线

外部总结确认，当前调研产物已经形成两套 final bundle：【事实，来自外部仓库 final bundle 说明】

| 主线 | 数量 | 核心定位 | 正式入口 |
|---|---:|---|---|
| transform | 89 条 | 数据集级转换，描述 Pipeline Builder 中的处理步骤 | `artifacts/transform-final/README.md` |
| expression | 335 条 | 字段和值级表达，常作为 transform 参数或列级逻辑出现 | `artifacts/pb-expression-final/README.md` |

transform 的代表性场景包括 Aggregate、Pivot、Window、Mapping join、Geometry intersection join、Parse Excel、Parse KML、First union by name、Key by 和 Rollup。expression 的重点类别包括 Numeric、Boolean、Data preparation、String、Datetime、Cast、Array、Struct、JSON 和 Map。【事实，来自外部仓库 `docs/pipeline-builder-operators-overview.html`】

这两条主线的关系是：transform 更像流水线图中的“步骤”，expression 更像步骤参数里的“表达式”。转换算子可以包含表达式参数，但表达式不应反过来包含转换算子。这个分层对低代码 Builder 很关键，因为它决定了画布节点、参数表单、类型校验和预览反馈如何组织。【推断】

证据边界也需要进入全局调研：两套 final bundle 是正式清单入口；自动解析、stage、verify 和一次性渲染产物只适合作为追溯材料，不应直接作为正式结论引用。Batch、Faster、Streaming 等字段是当前可见的支持环境标签，不等价于 Palantir 内部执行引擎实现。【事实 + 推断，来自外部仓库 `README.md` 与概要设计文档】

### 6.3 平台化核心判断

算子平台的关键不是“内置多少个函数”，而是把转换逻辑沉淀为**有契约的计算单元**。【推断】

一个可平台化的算子至少需要暴露：
- 输入端口、输出端口、参数声明与默认值。
- 输入 Schema 约束、输出 Schema 推导和参数校验。
- 执行资源提示、可用执行引擎、增量语义与质量规则。
- 所属命名空间、版本、兼容性策略、Owner 与治理元数据。

这意味着算子不是普通 SDK 函数库，也不是单纯的前端节点配置。它必须能被平台在**编译期发现和校验**，在**运行期路由和执行**，并在**治理面采集血缘、质量、指标和影响范围**。【推断】

### 6.4 Spec 与 Executor 分离

算子能力应拆成两层：【推断】

| 层次 | 职责 | 调用时机 | 主要消费者 |
|---|---|---|---|
| `OperatorSpec` | 输入/输出/参数/Schema 推导/兼容性声明 | 配置与编译期 | UI、DAG Resolver、Schema 传播、质量门禁 |
| `OperatorExecutor` | 具体执行逻辑 | 运行期 | Spark、Flink、DuckDB/Polars、Container Runtime |

这种拆分的价值在于：平台可以在不启动 Spark/Flink 的情况下完成算子选择、参数校验、Schema 传播和下游影响判断；运行时则可以按数据规模、执行语义和资源成本选择不同 Executor。【推断】

### 6.5 算子注册表是平台控制面的关键

外部概要设计把平台落地架构概括为“算子注册中心 + 类型化中间表示 + 执行适配器”。这与本仓库原有的 Spec / Executor 分层判断一致：注册中心负责能力事实入口，流水线中间表示负责画布、校验、编译和审计之间的稳定边界，执行适配器负责把同一套语义计划映射到 Spark、Flink、文件解析、地理空间、媒体处理和自定义函数等运行环境。【推断，来自外部仓库 `docs/pipeline-builder-operator-platform-architecture-design.md`】

算子注册表应提供三类视图：【推断】

```
Operator Registry
├── 元数据视图：operator_id / version / category / description / owner
├── 契约视图：input_ports / output_ports / params / infer_output_schema
└── 执行视图：engine -> executor / resource_hint / incremental_capability
```

这层注册表决定了低代码 Builder、代码优先 SDK、运行时调度器和治理系统能否共享同一套能力目录。没有注册表，低代码会退化成页面配置，高码会退化成自由脚本，二者很难在血缘、质量和版本管理上合流。【推断】

### 6.6 与 Transform DSL 的关系

Transform DSL 解决“这个计算读写哪些 Dataset”，算子契约解决“这一步计算的语义是什么”。二者互补，不应互相替代。【推断】

| 维度 | Transform DSL | 算子平台 |
|---|---|---|
| 核心对象 | Dataset 输入输出与 Transform 函数 | 可发现、可组合、可校验的计算单元 |
| 平台价值 | 自动构建 Dataset DAG、调度、血缘 | 支撑低代码节点、Schema 传播、复用和治理 |
| 高码路径 | 装饰器 / SDK 生成 Transform Contract | 自定义算子或直接使用底层 SDK |
| 低码路径 | Builder 生成 Pipeline / Transform Contract | Builder 从 Registry 渲染节点和参数表单 |

自建平台的合理目标是让低代码 Builder 和高码 SDK 共享同一套 Contract / IR：低代码编辑器生成 IR，高码 SDK 生成等价 Contract，调度、血缘、权限、质量系统只消费 Contract，而不是分别适配两套产品。【推断】

### 6.7 执行引擎路由

算子不应该默认等同于 Spark 节点。更合理的设计是由 Engine Router 根据数据规模、算子能力、增量需求和成本约束选择执行路径：【推断】

| 引擎路径 | 适合场景 | 边界 |
|---|---|---|
| Lightweight（DuckDB/Polars/DataFusion） | 中小数据、预览、低成本批处理 | 不适合大 shuffle、复杂状态和强一致写入 |
| Spark | 大规模批处理、复杂 Join、通用生产链路 | 成本高，冷启动和小任务开销明显 |
| Flink | 流式、有状态、低延迟处理 | 需要单独的状态、Checkpoint 和生命周期管理 |
| Container | 特殊库、媒体处理、外部工具链 | 治理、资源和安全边界更复杂 |

无论底层选择哪个引擎，输出都必须通过统一的 Dataset WriteSession 提交 Transaction；否则增量、血缘、权限、质量和回滚都会被绕开。【推断】

### 6.8 建设优先级

算子建设应按“框架优先、P0 覆盖主链路、P1 提升分析效率、P2 做差异化”的顺序推进：【推断】

| 阶段 | 重点 | 目标 |
|---|---|---|
| Phase 0 | `OperatorSpec` / `OperatorExecutor`、Registry、Schema 传播、Engine Router | 先让平台能理解算子 |
| Phase 1 | `filter`、`select`、`add_column`、`join`、`union`、`aggregate`、`read/write_dataset` | 覆盖大部分基础 Pipeline |
| Phase 2 | `window`、`pivot`、`deduplicate`、字符串/日期/数值表达式、Spark fallback | 覆盖高频分析场景 |
| Phase 3 | AI/ML、GIS、媒体、用户自定义算子框架、内部 Marketplace、Flink 流式算子 | 形成差异化和生态扩展 |

平台团队应维护高频、标准化、可 Schema 推导、可多引擎实现的官方算子；业务特异逻辑应走自定义算子框架，并通过兼容性扫描、CI、Owner 和版本锁定纳入治理。【推断】

### 6.9 对全局建设路线的影响

算子平台应进入“先补底座”的范围，而不是被放到低代码页面之后再补。原因是：
- Builder 的节点面板、参数表单、Schema 预览和错误提示都依赖算子契约。
- 高码自定义能力如果不纳入 Registry，后续很难被低代码复用和治理。
- Engine Router、Dataset Transaction、质量门禁和 Lineage 采集都需要围绕算子执行边界注入。
- P0 算子覆盖不足时，业务会绕回自由代码；治理和复用能力会在第一阶段就被削弱。

因此，全局路线应从“统一表达层”扩展为“统一表达层 + 算子契约 + Dataset 事务模型”三件事并行打底。【推断】

---

## 七、综合技术评估

### 7.1 核心优势

| 优势 | 技术实现 |
|---|---|
| 零运维 Spark 集群 | Compute Profile 屏蔽集群管理[事实] |
| 算子能力可产品化 | transform / expression 两套 final bundle 已提供 89 + 335 条可对照能力基线，注册中心、类型化 IR 和执行适配器可把清单转成平台能力[事实 + 推断] |
| 自动血缘追踪 | FDS 统一收集 Transform 依赖[事实] |
| 高效增量计算 | Transaction 类型驱动，APPEND → 自动增量[事实] |
| 流批输出统一 | 无论来源，最终都进 Ontology，应用无感知[推断] |
| 数据安全治理 | Column Masking + 数据分类 + 审计日志内置[事实] |
| 低代码开发 | Pipeline Builder + AIP 自然语言生成代码[事实] |

### 7.2 核心限制

| 限制 | 影响 |
|---|---|
| 强平台绑定 | 技术栈锁定，迁移成本极高[推断] |
| Dataset Branch 不支持 Merge | 多团队协作数据流复杂[事实] |
| OpenLineage 不兼容 | 多平台血缘孤岛[推断] |
| Writeback 分钟级延迟 | 不适合强实时写回场景[事实] |
| 列级血缘不完整 | 手写 PySpark 代码血缘缺失[事实] |
| 算子平台建设成本高 | 如果缺少 Spec、Registry、版本兼容和多引擎绑定，很容易退化成函数库或页面配置[推断] |
| 小文件问题 | 增量模式长期运行需定期 SNAPSHOT 合并[推断] |
| 极低延迟限制 | Foundry 推荐配置强调秒级到十秒级流处理，< 1s 强实时场景仍不适合[推断] |

### 7.3 适合 vs 不适合场景

**适合 Palantir Foundry Pipeline：**
- 大型政府/企业，需要高度治理和合规
- 多数据源融合 + 业务语义化（Ontology 价值最大化）
- 团队技术背景混合（业务 + 技术）
- 可接受平台绑定换取开发效率

**不适合场景：**
- 需要跨平台数据血缘互通的多云/多工具架构
- 极低延迟（< 1s）流处理需求
- 技术团队偏好开源、希望避免厂商锁定
- 中小企业（成本门槛高）

---

## 八、关键技术结论汇总

1. **装饰器即 DAG**：`@transform_df` 的 `Input/Output` 声明是 DAG 边的定义，FDS 自动组装全局依赖图，无需手工编排[事实]
2. **Pipeline Builder 算子需要分成 transform 和 expression 两条主线**：transform 是数据集级转换，expression 是字段和值级表达；外部调研已收口 89 条 transform 和 335 条 expression final bundle[事实]
3. **final bundle 是算子调研的正式证据入口**：自动解析、stage、verify 和临时渲染文件只适合追溯，不应直接作为全局结论引用[事实]
4. **算子是有契约的计算单元**：输入/输出/参数/Schema/执行绑定/质量规则需要被平台理解，不能只做成函数库[推断]
5. **Spec 与 Executor 分离是算子平台化前提**：编译期校验和运行期执行分离后，Builder、SDK、调度和治理才能共享同一套能力[推断]
6. **Operator Registry + 类型化 IR + 执行适配器是自研平台复刻算子能力的主架构**：没有这层控制面，低代码节点与高码自定义逻辑会持续分叉[推断]
7. **Transaction 类型是增量计算的开关**：APPEND → 增量可行；UPDATE/SNAPSHOT → 全量重算，这是理解 Pipeline 性能优化的核心[事实]
8. **`semantic_version` 是逻辑变更的信号**：必须在 Transform 逻辑实质性变更时手动递增，否则旧数据不会重算[事实]
9. **流批统一在 Ontology 层而非 API 层**：两者共享数据目的地（Ontology），上层应用无感知，但开发模型不同[推断]
10. **流处理引擎是 Apache Flink（非 Spark）**：批处理用 Spark，流处理用 Flink；Flink 的 Keyed State + Checkpoint 提供有状态流计算能力；< 15s 是推荐配置下的典型值而非硬性 SLA；Exactly-once 需显式配置，默认为 AT_LEAST_ONCE[事实]
11. **Dataset Branch 不支持 Merge**：这是最易被误解的重要限制，影响多团队协作工作流设计[事实]
12. **OpenLineage 不兼容是开放性最大短板**：多平台架构下 Foundry 血缘形成孤岛[推断]

---

## 九、后续深挖建议

### 高优先级
- [ ] Foundry 托管 Spark 的底层基础设施（K8s？自研调度器？）
- [ ] 增量状态存储的具体实现（Build History Service 的数据结构）
- [ ] FDS 跨 Repository 事件传播的技术细节
- [ ] 算子 Registry 与 Pipeline Builder 内部 IR 的真实映射方式
- [ ] transform / expression final bundle 与自研平台算子注册中心字段的映射表

### 中优先级
- [ ] Pipeline Builder 生成代码与手写 Code Repository 的执行路径差异
- [ ] Streaming Schema Evolution 处理机制
- [ ] OpenLineage Adapter 是否在 Palantir 路线图
- [ ] 官方算子与用户自定义算子的边界、版本锁定和兼容性策略

### 扩展调研
- [ ] Foundry AIP Agent 编排 Pipeline 的授权模型与回滚机制
- [ ] MCP 协议与 Foundry Ontology 的集成实现（2025 年底发布）
- [ ] 开源栈复刻方案（Spark + dbt + OpenMetadata + Airflow）

---

## 参考文件

- `docs/raw/01-pipeline-expression-dsl.md`
- `docs/raw/02-execution-engine-spark.md`
- `docs/raw/03-streaming-batch-architecture.md`（已修正：流处理引擎 Flink）
- `docs/raw/04-lineage-ontology-integration.md`（已修正：FDS 术语）
- `docs/raw/05-testing-and-data-connection.md`（新增：测试框架 + 数据接入层）
- `docs/raw/14-transform-operator-library.md`
- `docs/synthesis/operator-platform-design.md`
- `/Users/huyongqiang/code/li/pipeline-transform-research/docs/pipeline-builder-operators-research-summary.md`
- `/Users/huyongqiang/code/li/pipeline-transform-research/docs/pipeline-builder-operators-overview.html`
- `/Users/huyongqiang/code/li/pipeline-transform-research/docs/pipeline-builder-operator-platform-architecture-design.md`
- `/Users/huyongqiang/code/li/pipeline-transform-research/artifacts/transform-final/README.md`
- `/Users/huyongqiang/code/li/pipeline-transform-research/artifacts/pb-expression-final/README.md`
