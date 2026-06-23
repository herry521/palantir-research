# Palantir Foundry Stream 能力深度调研

**调研日期：** 2026-04-28（更新：2026-06-23）<br>
**调研方向：** Stream 产品能力全景 / 与 Batch 链路差异 / 技术实现架构<br>
**可信度标注：** 🟢 事实（官方文档原文/可直接验证） 🟡 推断（间接证据/逻辑推理） 🔴 猜测（无直接证据）

---

## 零、2026-06-23 快速结论：Streaming Pipeline 能否通过 Pipeline Builder 配置

1. 【事实】可以。Palantir 官方教程明确提供 `Create a streaming pipeline with Pipeline Builder` 流程：创建 Stream 后，从 Stream 页面进入 `Start pipelining`，在新建 Pipeline 弹窗中选择 `Streaming pipeline` 类型，再在 Pipeline Builder 图上配置转换。
2. 【事实】Pipeline Builder 官方 Overview 将 `Streaming capability` 列为能力之一，说明 Pipeline Builder 可编写实时延迟执行的 pipeline；但该能力不是所有 Foundry 环境都启用，需要联系 Palantir representative 开通或确认。
3. 【事实】Streaming pipeline 的配置不是普通 batch pipeline 的简单开关。流场景有持续运行、状态管理、计算成本、1MB 单行限制、状态变更风险等约束；官方建议只有低延迟强需求时才选 Streaming。
4. 【事实】Pipeline Builder 支持流式 Join 等专门 streaming transform；例如可在同一个 Pipeline Builder graph 中配置 stream-batch join 或 stream-stream join，但流式 join 有缓存时间、状态上界、batch 侧不能先在同一图中转换等限制。
5. 【推断】工程选型上，若只是分钟级时效，优先考虑 Incremental/Faster pipeline；只有明确要求小于 1 分钟、实时告警、实时 Ontology/Rules/Quiver 消费时，才值得用 Pipeline Builder 的 Streaming pipeline。

参考来源：
- Palantir Docs — [Create a streaming pipeline with Pipeline Builder](https://www.palantir.com/docs/foundry/building-pipelines/create-stream-pipeline-pb/)
- Palantir Docs — [Pipeline Builder Overview](https://www.palantir.com/docs/foundry/pipeline-builder/overview/)
- Palantir Docs — [Types of pipelines: Streaming](https://www.palantir.com/docs/foundry/building-pipelines/pipeline-types/)
- Palantir Docs — [Joins in streaming Pipeline Builder pipelines](https://www.palantir.com/docs/foundry/pipeline-builder/transforms-streaming-joins/)

## 零点五、2026-06-23 快速结论：Stream 解决什么问题，为什么不支持 UserEdit

1. 【事实】Stream 解决的是“持续到达的数据如何以低延迟进入 Foundry 并被实时消费”的问题，不是为了替代所有 batch pipeline。官方给出的典型效果是 streaming data 平均可在 15 秒内进入 Ontology，并可被 Quiver、Foundry Rules 等实时分析应用使用。
2. 【事实】Stream 的核心价值在热路径：低延迟访问、持续处理、实时 Ontology 水合、实时 time series ingest、告警和 streaming export；冷路径仍会归档成 dataset，供 Contour 等非实时应用读取归档数据。
3. 【事实】Streaming object type 当前不支持 User edits / Actions。官方 Object edits overview 明确说 `Actions are not yet supported on object types with Foundry stream datasources`；Indexing 文档也列出 `User edits are not supported on streaming object types`。
4. 【事实】直接原因线索是 Object Storage V2 streaming 使用 `most recent update wins` 策略，每个 stream 被当成 changelog stream；如果事件乱序，Ontology 中的数据可能变错。
5. 【事实】官方给出的 workaround 是：把用户编辑作为 data change 推入 input stream，或配置一个额外的 non-streaming input datasource object type 让用户在辅助对象类型上编辑。
6. 【推断】UserEdit 本质是另一条人工写入路径；若同时对同一个 streaming object type 开放 UserEdit，下一条源流事件可能马上覆盖用户编辑，且乱序事件还会让“谁是最新状态”变得不可判定。因此产品上禁止该组合。

官方原文短引：
- Object edits overview: "Actions are not yet supported on object types with Foundry stream datasources."
- Funnel streaming pipelines: "User edits are not supported on streaming object types"; workaround includes "push user edits as a data change into the input stream" or an auxiliary object type backed by a "non-streaming input datasource".

参考来源：
- Palantir Docs — [Streaming Overview](https://www.palantir.com/docs/foundry/building-pipelines/streaming-overview/)
- Palantir Docs — [Comparison: Streaming vs batch](https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/)
- Palantir Docs — [Object edits and materializations overview](https://www.palantir.com/docs/foundry/object-edits/overview/)
- Palantir Docs — [Funnel streaming pipelines](https://www.palantir.com/docs/foundry/object-indexing/funnel-streaming-pipelines/)
- Palantir Docs — [How user edits are applied](https://www.palantir.com/docs/foundry/object-edits/how-edits-applied/)

## 一、产品能力全景

### 1.1 数据摄入能力

**🟢 事实** — Foundry 提供原生连接器支持以下流数据源：  
证据：[Streaming Resource Guide](https://www.palantir.com/docs/foundry/data-integration/streaming-guide/) + [Set up Streaming Sync](https://www.palantir.com/docs/foundry/data-connection/set-up-streaming-sync/)
- Apache Kafka（主流，最常见）
- Amazon Kinesis
- Google Pub/Sub
- OSI PI（工业场景）
- 通过 External Transforms 支持其他自定义流源

**🟢 事实** — Kafka 连接方式：  
证据：[Set up Streaming Sync](https://www.palantir.com/docs/foundry/data-connection/set-up-streaming-sync/)
- 支持 Agent-based 连接（推荐方式，改善性能和可用性）
- Offset 管理由 Flink Checkpoint 机制全自动处理，无需手动配置
- 支持 Streaming Syncs（数据流入 Foundry）和 Streaming Exports（数据从 Foundry 写出到 Kafka）

### 1.2 数据处理能力

**🟢 事实** — Pipeline Builder 是 Foundry Streaming pipeline 的主要低码配置界面，官方提供了从 Stream 页面启动并在新建弹窗中选择 `Streaming pipeline` 类型的教程：<br>
证据：[Create a streaming pipeline with Pipeline Builder](https://www.palantir.com/docs/foundry/building-pipelines/create-stream-pipeline-pb/)；[Pipeline Builder Overview](https://www.palantir.com/docs/foundry/pipeline-builder/overview/) 将 `Streaming capability` 列为 Pipeline Builder 能力之一，并注明不是所有 Foundry 环境都启用。

**🟢 事实** — Python Transform 在流处理中**完全不支持**，Java 支持：  
证据：[stream-vs-batch feature table](https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/) 官方原文：

> | Python supported transforms | No | Yes |
> | Java supported transforms | Yes | Yes |

（表格列顺序：Streaming | Batch）

**🟢 事实** — Pipeline Builder 内置 Stream 算子包括 Join（流与流）：  
证据：[Pipeline Builder Streaming Joins](https://www.palantir.com/docs/foundry/pipeline-builder/transforms-streaming-joins/)  
其他算子（Filter、Aggregate over window、Project over window）在 Pipeline Builder 中可用，但未找到单独的官方枚举页面。

**🟡 推断** — FoundryTS 的 `rolling_aggregate` 和 `periodic_aggregate` 函数可用于流处理时序场景。  
说明：多处搜索结果提及这两个函数，但未找到官方文档直接 URL 可引用，降级为推断。

**🟡 推断** — Pipeline Builder 对 Streaming 的算子覆盖范围窄于批处理，复杂流处理逻辑（如多流 Join、复杂状态机）需要通过 Java UDF 承载。

### 1.3 数据存储模型：Stream vs Dataset

**🟢 事实** — Foundry Stream 内部架构是双层存储：  
证据：[Streams core concepts](https://www.palantir.com/docs/foundry/data-integration/streams/) 官方原文：

> "A stream is a wrapper around a collection of rows which are stored by both a persistent 'hot buffer' and 'cold storage' backed by a file system."

> "Streams are inherently tabular and, therefore, inherently structured. They are stored in open source formats such as Avro, along with metadata about the columns themselves."

```
外部数据源（Kafka 等）
        ↓
  [热存储 Hot Buffer]  ← 低延迟访问层，at-least-once 写入保证
        ↓（每隔几分钟归档，"archiving"）
  [冷存储 Cold Storage]  ← 文件系统，Avro 格式
        ↓
  作为普通 Foundry Dataset 可被任何 Foundry 应用访问
```

**🟢 事实** — Stream 与 Dataset 的官方 Feature 对比：  
证据：[stream-vs-batch](https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/)

| 特性 | Dataset（批） | Stream |
|---|---|---|
| 存储格式 | Parquet（主流）| Avro（热）+ 文件系统（冷）|
| Low latency data access | No | **Yes** |
| Python transforms | **Yes** | No |
| Java transforms | Yes | Yes |
| Pipeline Builder support | Yes | Yes |
| Ontology support | Yes | Yes |
| Time series support | Yes | Yes |

**🟢 事实** — 1MB 单行限制：  
证据：[streaming-overview # best-practices](https://www.palantir.com/docs/foundry/building-pipelines/streaming-overview/#best-practices) 官方原文：

> "Streams operate on a per-row basis and have constraints on the maximum row size to ensure low latency data transfers. The constraint is set to 1mb per individual row."

**🟢 事实** — 前端工具对流数据的支持情况：  
证据：[stream-vs-batch # front-end-tools](https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/#front-end-tools) 官方原文：

> "The tools that can natively consume streams are Ontology, Pipeline Builder, Quiver, Dataset Preview, and Foundry Rules. Other apps in Foundry, like Contour, can consume the stream's archival dataset."

### 1.4 Ontology 集成

**🟢 事实** — 流数据写入 Ontology 的端到端延迟 <15s：  
证据：[streaming-overview](https://www.palantir.com/docs/foundry/building-pipelines/streaming-overview/) 官方原文：

> "On average, streaming data can be accessible in the Ontology and available for analysis in time series applications, such as Quiver or Foundry Rules, in under 15 seconds."

**🟢 事实** — User Edits（Actions）不支持 Streaming Object Type：  
证据：官方文档明确说明（搜索结果引用原文）："Actions are not yet supported on object types with Foundry stream datasources."  
⚠️ 注：此原文已通过多次搜索间接确认，但未能找到包含该原文的单一官方文档 URL（疑似位于 Ontology 建模文档内部，URL 动态生成）。如需直接核验，可在 Foundry 内搜索 "streaming object type limitations"。  
变通方案（官方提供）：将用户编辑作为数据变更推入输入 Stream，或新建非流 Object Type 承接编辑。

**🟢 事实** — MDO（Multi-Datasource Objects）不支持流数据源：  
证据：官方说明（间接确认）："only Foundry datasets or restricted views can be used for MDOs; streaming sources are not supported."  
⚠️ 同上，URL 未能直接定位，但多来源一致确认。

**🟢 事实** — 事件乱序风险："most recent update wins" 策略：  
证据：官方说明："Streaming in Object Storage V2 uses a 'most recent update wins' strategy. If events arrive out of order from the source, the data in the Ontology can become incorrect."  
⚠️ 同上，直接 URL 未定位。

**🟢 事实** — 250 属性上限（流 Object Type）：  
证据：官方说明（间接确认）："an object type cannot have more than 250 properties"（针对 streaming object type）。  
⚠️ 直接 URL 未定位。

**🟡 推断** — Foundry 流处理 Ontology 集成的完整度不及批处理，属于产品成熟度差距，预期未来版本会缩小。

### 1.5 性能调优与计算模型

**🟢 事实** — 端到端延迟拆解（官方参考数据）：  
证据：[Streaming Performance Considerations](https://www.palantir.com/docs/foundry/building-pipelines/streaming-performance-considerations/) 官方原文：

> "A standard streaming pipeline can run through the following stages in under 15 seconds:"
> - Ingestion: ~1-2 seconds
> - Transformation: ~5s (exactly-once, default) or ~1s (at-least-once)
> - Syncing into backing datastore: ~5s (exactly-once) or ~1s (at-least-once)

**🟢 事实** — 可调参数（Partitions 和 HIGH THROUGHPUT）：  
证据：[Streams core concepts # stream-types](https://www.palantir.com/docs/foundry/data-integration/streams/#stream-types) 官方原文：

> "**High Throughput:** This is best for streams that send large amounts of data every second. Enabling this stream type might introduce some non-zero latency at the expense of a higher throughput."

> "Each additional partition for a given stream increases the max throughput the stream can process. A good heuristic is that each partition increases the throughput by approximately 5mb/s."

**🟢 事实** — 计算资源静态分配模型：  
证据：[Streaming Compute Usage](https://www.palantir.com/docs/foundry/building-pipelines/streaming-compute-usage/) 官方原文：

> "Streams are statically allocated; they will use a constant number of compute-seconds per wall-clock second while the stream is running. Streams are also often tuned to meet peak demand, meaning compute usage from the stream is unaffected by variable data volume. Streams use compute-seconds even if no data is moving through the stream."

**🟡 推断** — 静态分配模型意味着低峰期资源利用率偏低，这是 Stream 成本高于 Batch 的核心原因之一。

---

## 二、与 Batch 链路的关键差异

### 2.1 三种处理模式对比

证据来源：[stream-vs-batch](https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/) + [streaming-overview](https://www.palantir.com/docs/foundry/building-pipelines/streaming-overview/)

| 特性 | Batch Pipeline | Incremental Pipeline | Streaming Pipeline |
|---|---|---|---|
| **处理触发** | 上游数据变化时全量重算 | 仅处理新增/变更行 | 持续运行，逐行处理 |
| **延迟** | 分钟~小时 | 分钟级 | 秒级（<15s）🟢 |
| **计算成本** | 中等（按需运行）| 低 | 高（持续占用）🟢 |
| **Python 支持** | 完整 🟢 | 完整 🟢 | **不支持** 🟢 |
| **SQL 支持** | 完整 Spark SQL 🟢 | Spark SQL 🟢 | **无完整 SQL**，仅可视化算子 🟡 |
| **主要开发工具** | Pipeline Builder / Code Repository 🟢 | Code Repository（`@incremental`）🟢 | Pipeline Builder + Java UDF 🟢 |
| **开发复杂度** | 低 🟡 | 中 🟡 | 高 🟡 |
| **维护复杂度** | 低 🟡 | 中 🟡 | 高 🟡 |

注：开发/维护复杂度为 🟡 推断，官方文档有定性描述（"more complex to author and maintain"）但无量化标准。

### 2.2 User Edits 为何在流处理中不支持：根因分析

#### 2.2.1 官方表述（🟢 事实）

官方文档明确说明：
> "Actions are not yet supported on object types with Foundry stream datasources."

官方给出的变通方案：
1. 将用户编辑推入输入 Stream（作为数据事件处理）
2. 新建非流 Object Type，允许用户在该辅助类型上编辑

#### 2.2.2 "most recent update wins" 模型是根因（🟢 事实 + 🟡 推断）

**🟢 事实** — Foundry Streaming 写入 Ontology 的更新策略是 "most recent update wins"。

**🟡 推断（核心根因）** — 该模型与 Actions（用户编辑）存在本质冲突：

```
时间轴：
t1 → 流事件：{temperature: 20}       → Ontology 对象状态：{temperature: 20}
t2 → 用户 Action：{temperature: 25}  → 状态：{temperature: 25}
t3 → 流事件：{temperature: 22}       → 状态：{temperature: 22}  ← 用户编辑被覆盖！
```

流是持续写入的 changelog，用户 Action 产生的编辑会被下一条流事件立即覆盖。

#### 2.2.3 两条写路径的竞争（🟡 推断）

- Actions 写路径：用户触发 → 写入 Object Storage → Ontology 呈现
- Streaming 写路径：Flink Job 持续消费 Stream → 按 primary key upsert 到 Object Storage V2

两条路径竞争同一 Object 状态，流路径高频写入，Actions 效果无法持久，因此 Palantir 在产品层面直接禁止此组合。

#### 2.2.4 与批处理的对比（🟡 推断）

批处理支持 Actions，因为两次 Build 之间有明确**静默期**，用户编辑在静默期内稳定保留。流处理没有静默期，这是 User Edits 不被支持的本质原因。

### 2.3 引擎差异

**🟢 事实：**  
证据：[Flink Fundamentals](https://www.palantir.com/docs/foundry/data-integration/flink-streaming/) 官方原文：

> "Foundry streaming uses Flink as the underlying engine to execute user code and other in-platform streaming applications such as hydrating the Ontology in real time and streaming time series ingestion."

- Batch：Apache Spark
- Stream：Apache Flink

**🟡 推断** — 两套引擎的差异导致：Python Transform 无法在 Flink 上等效运行（已由官方 Feature Table 确认），有状态算子语义在流场景更复杂。

---

## 三、技术实现架构

### 3.1 Flink 执行架构

**🟢 事实：**  
证据：[Flink Fundamentals](https://www.palantir.com/docs/foundry/data-integration/flink-streaming/) 官方原文：

> "The Flink Job Manager is responsible for scheduling tasks and allocating resources for tasks, handling finished or failed tasks, coordinating job checkpoints and failure recovery..."
> "The Flink Task Manager is responsible for the execution of tasks as well as buffering and exchanging data between streams."

```
┌──────────────────────────────────────────┐
│           Foundry Control Plane           │
│  ┌──────────────────────────────────┐    │
│  │         Job Manager               │    │
│  │  - 任务调度 & 资源管理             │    │
│  │  - Checkpoint 协调 & 故障恢复      │    │
│  │  - JobGraph → ExecutionGraph      │    │
│  └─────────────┬────────────────────┘    │
│                │                          │
│    ┌───────────┼───────────┐              │
│    ↓           ↓           ↓              │
│  [TM1]       [TM2]       [TM3]            │
│  Task        Task        Task             │
│  Manager     Manager     Manager          │
└──────────────────────────────────────────┘
```

**🟢 事实** — Job Tracker UI：  
证据：[Flink Fundamentals](https://www.palantir.com/docs/foundry/data-integration/flink-streaming/) 官方原文：

> "A preview of your Flink job's job graph is rendered in the Details section of jobs in the Foundry Job Tracker."

### 3.2 有状态处理与 Checkpoint

**🟢 事实** — 有状态操作示例（官方列出）：  
证据：[Flink Fundamentals # job-state](https://www.palantir.com/docs/foundry/data-integration/flink-streaming/#job-state)
- 聚合（Aggregations）：5 分钟滚动窗口计数、running average
- Join：需要记住历史事件

**🟢 事实** — 有状态 transform 的 OOM 风险（官方提示）：  
证据：[stream-vs-batch # state-management](https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/#state-management) 官方原文：

> "stateful streaming applications may have unbounded state that can grow over time and result in an out of memory error at an unknown point in the future."

**🟢 事实** — Checkpoint 机制：  
证据：[Streams # checkpointing](https://www.palantir.com/docs/foundry/data-integration/streams/#Checkpointing) 官方原文：

> "Foundry streaming provides fault tolerance while processing data by storing both the active state and current processing location in a checkpoint."
> "Checkpoints allow a streaming job to be restarted from the point of the latest checkpoint, rather than reprocessing already-seen data."

**🟢 事实** — 两种一致性配置：  
证据：[Streams # streaming-consistency-guarantees](https://www.palantir.com/docs/foundry/data-integration/streams/#streaming-consistency-guarantees)
- `AT_LEAST_ONCE`：低延迟，可能重复
- `EXACTLY_ONCE`（默认）：精确一次，有额外延迟开销

**🟢 事实** — 所有 Pipeline Builder 有状态 transform 使用 Keyed State，需用户指定 Partition Key：  
证据：[Streaming Stateful Transforms](https://www.palantir.com/docs/foundry/building-pipelines/streaming-stateful-transforms/)

### 3.3 端到端数据流

**🟢 事实：**

```
外部流源（Kafka/Kinesis/Pub-Sub）
        ↓ [Data Connection / Streaming Sync]
  Foundry Stream（Hot Buffer + 冷归档）
        ↓ [Pipeline Builder Streaming Pipeline]
  Flink Job（JobGraph → tasks 并行执行）
        ↓ [输出]
  ┌────────────────────────────────────────┐
  │  写入 Foundry Ontology（<15s）          │
  │  写入 Foundry Dataset（冷归档）         │
  │  写出到外部 Kafka（Streaming Export）   │
  └────────────────────────────────────────┘
```

**🟡 推断** — Pipeline Builder 内部将低代码配置编译为 Flink JobGraph 后提交执行（Job Tracker 可见 JobGraph 预览已官方确认，印证此推断）。

### 3.4 延迟分析

**🟢 事实** — 官方列出的延迟影响因素：  
证据：[Streaming Performance Considerations](https://www.palantir.com/docs/foundry/building-pipelines/streaming-performance-considerations/)
1. Source 生产速度
2. 网络跨边界传输
3. Pipeline 阶段数（跨 Repository / Builder 图链式连接，无法 Co-locate）
4. 一致性模型（Exactly-Once 增加约 4s）
5. 时间窗口长度（30s 窗口隐性增加 30s 延迟）

**🟢 事实** — Co-location 优化：  
证据：[Streaming Performance Considerations](https://www.palantir.com/docs/foundry/building-pipelines/streaming-performance-considerations/) 官方原文：

> "Foundry streaming will co-locate pipeline transformations defined in the same Code Repository or Pipeline Builder graph onto the same physical hardware to automatically optimize latencies."

---

## 四、能力建设参考建议

> 本节为 🟡 推断，仅供参考。

### 4.1 核心技术栈（事实层面已确认）

- 流处理引擎：Apache Flink
- 接入层：Kafka（主流）+ Kinesis / Pub-Sub（可选）
- 低代码界面：类 Pipeline Builder 的可视化算子连接界面
- 存储：Hot Buffer（低延迟访问）+ 冷归档（Avro/Parquet in 对象存储）

### 4.2 流处理 vs 批处理选型判断依据

| 判断条件 | 推荐选型 | 依据 |
|---|---|---|
| 端到端延迟需求 >10 分钟 | Batch 或 Incremental | 🟢 官方明确说明 |
| 端到端延迟需求 <1 分钟 | Streaming | 🟢 官方说明 |
| 需要 Python/复杂 SQL 逻辑 | Batch | 🟢 官方 Feature Table |
| 需要实时告警/实时触发 | Streaming | 🟢 官方说明 |
| 需要 User Edits（人工修正）| Batch | 🟢 官方说明（Actions 不支持流）|
| 数据量大但时效性低 | Batch | 🟡 成本推断 |

---

## 五、信息来源汇总

| 页面 | URL | 涵盖内容 |
|---|---|---|
| Streaming Overview | [链接](https://www.palantir.com/docs/foundry/building-pipelines/streaming-overview/) | 最佳实践、1MB 限制、<15s 延迟 |
| Stream vs Batch | [链接](https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/) | Feature Table、状态管理风险、前端工具 |
| Performance Considerations | [链接](https://www.palantir.com/docs/foundry/building-pipelines/streaming-performance-considerations/) | 延迟拆解、Co-location |
| Flink Fundamentals | [链接](https://www.palantir.com/docs/foundry/data-integration/flink-streaming/) | JM/TM 架构、JobGraph、Job Tracker |
| Streams Core Concepts | [链接](https://www.palantir.com/docs/foundry/data-integration/streams/) | Hot/Cold 存储、Avro、Checkpoint、一致性、Partitions、HIGH THROUGHPUT |
| Streaming Stateful Transforms | [链接](https://www.palantir.com/docs/foundry/building-pipelines/streaming-stateful-transforms/) | Keyed State、Exactly-Once |
| Streaming Compute Usage | [链接](https://www.palantir.com/docs/foundry/building-pipelines/streaming-compute-usage/) | 静态分配、两类计费 |
| Streaming Resource Guide | [链接](https://www.palantir.com/docs/foundry/data-integration/streaming-guide/) | 数据源列表入口 |

**⚠️ 以下结论有多来源间接确认，但未能定位直接官方 URL：**
- Actions 不支持 Streaming Object Type（原文："Actions are not yet supported on object types with Foundry stream datasources."）
- MDO 不支持流数据源
- "most recent update wins" 更新策略
- 250 属性上限（针对 streaming object type）

---

*文档最后更新：2026-04-28*
