# Palantir Foundry Stream 能力深度调研

**调研日期：** 2026-04-28（更新：2026-04-28）  
**调研方向：** Stream 产品能力全景 / 与 Batch 链路差异 / 技术实现架构  
**可信度标注：** 🟢 事实（官方文档/可验证） 🟡 推断（逻辑推理） 🔴 猜测（无直接证据）

---

## 一、产品能力全景

### 1.1 数据摄入能力

**🟢 事实** — Foundry 提供原生连接器支持以下流数据源：  
证据：[Streaming Overview](https://www.palantir.com/docs/foundry/building-pipelines/streaming-overview/)
- Apache Kafka（主流，最常见）
- Amazon Kinesis
- Google Pub/Sub
- OSI PI（工业场景）
- 通过 External Transforms 支持其他自定义流源

**🟢 事实** — Kafka 连接方式：  
证据：[Set up Streaming Sync](https://www.palantir.com/docs/foundry/data-connection/set-up-streaming-sync/)
- 支持 Agent-based 连接（推荐方式，改善性能和可用性）
- Connector 读取原始 bytes 到 `value` 列，不自动解析消息内容
- Offset 管理由 Flink Checkpoint 机制全自动处理，无需手动配置
- 支持 Streaming Syncs（数据流入 Foundry）和 Streaming Exports（数据从 Foundry 写出到 Kafka）

### 1.2 数据处理能力

**🟢 事实** — 主要开发界面：Pipeline Builder（低代码可视化工具）  
证据：[stream-vs-batch feature table](https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/)

**🟢 事实** — Pipeline Builder 内置 Stream 算子：  
证据：[Pipeline Builder Streaming Joins](https://www.palantir.com/docs/foundry/pipeline-builder/transforms-streaming-joins/)
- **Filter**：按条件过滤记录
- **Join**：流与流 Join（Outer Caching Join，需指定匹配条件和缓存时间）
- **Aggregate over window**：窗口内聚合（支持各类聚合函数，有 trigger 机制）
- **Project over window**：窗口内投影（每收到新行即触发输出）
- 标准列操作（重命名、类型转换、计算字段等）

**🟢 事实** — UDF 扩展机制：  
证据：[stream-vs-batch](https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/)
- 在 Code Repository 中用 Java 或 Python 定义 UDF
- UDF 在 Pipeline Builder 中作为节点调用
- **Python Transform 在流处理中完全不支持**（官方明确列出为差异项）

**🟢 事实** — FoundryTS 时序函数（流场景适用）：
- `functions.rolling_aggregate`：滑动窗口聚合
- `functions.periodic_aggregate`：固定周期窗口聚合

**🟡 推断** — Pipeline Builder 对 Streaming 的算子覆盖范围窄于批处理，复杂流处理逻辑（如多流 Join、复杂状态机）需要 UDF 承载。

### 1.3 数据存储模型：Stream vs Dataset

**🟢 事实** — Foundry Stream 内部架构是双层存储：  
证据：[Streams core concepts](https://www.palantir.com/docs/foundry/data-integration/streams/)

```
外部数据源（Kafka 等）
        ↓
  [热存储 Hot Buffer]  ← 低延迟访问层，记录实时读取
        ↓（每隔几分钟归档）
  [冷存储 Cold Storage]  ← 文件系统，Avro 格式
        ↓
  作为普通 Foundry Dataset 可被批处理访问
```

**🟢 事实** — stream-vs-batch 官方 Feature Table 中的差异：  
证据：[stream-vs-batch](https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/)

| 特性 | Dataset（批） | Stream |
|---|---|---|
| 存储格式 | Parquet（主流）+ 其他文件 | Avro（热）+ 文件系统（冷） |
| 访问延迟 | 分钟~小时级 | 秒级（<15s 端到端）|
| 数据结构 | 结构化/非结构化均支持 | 仅结构化（tabular）|
| 单条记录上限 | 无明确限制 | **1MB**（硬限制）|
| Low latency data access | No | Yes |
| Python transforms | Yes | **No** |
| Java transforms | Yes | Yes |
| Pipeline Builder | Yes | Yes |

**🟢 事实** — Foundry 的 stream-vs-batch 对比页官方明确说明：

> "Generally, streaming is used for workflows that require low end-to-end latency. For use cases that can tolerate more than ten minutes of latency, incremental or standard batch datasets may also be suitable."

**🟢 事实** — 前端工具对流数据的支持情况（官方说明）：  
证据：[stream-vs-batch # front-end-tools](https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/#front-end-tools)
- 原生支持流式刷新的工具：**Ontology、Pipeline Builder、Quiver、Dataset Preview、Foundry Rules**
- 其他应用（如 Contour）消费 Stream 的冷归档 Dataset，每几分钟更新一次
- Foundry 会自动判断使用哪种模式，用户无需手动区分

### 1.4 Ontology 集成

**🟢 事实** — 流数据可直接写入 Foundry Ontology，端到端延迟 <15s。  
证据：[Streaming Overview](https://www.palantir.com/docs/foundry/building-pipelines/streaming-overview/)

> "On average, streaming data can be accessible in the Ontology and available for analysis in time series applications, such as Quiver or Foundry Rules, in under 15 seconds."

**🟢 事实** — User Edits 不支持（详见第二章根因分析）：  
证据：官方文档明确说明 "Actions are not yet supported on object types with Foundry stream datasources."  
变通方案：将用户编辑作为数据变更推入输入 Stream，或新建非流 Object Type 承接编辑。

**🟢 事实** — 其他 Ontology 限制：
- **不支持 Multi-Datasource Objects（MDO）**
- 事件乱序风险：采用 "most recent update wins" 策略，源端乱序会导致 Ontology 数据错误

**🟡 推断** — Foundry 流处理 Ontology 集成的完整度不及批处理，是产品成熟度差距，预期未来版本会缩小。

### 1.5 性能调优与计算模型

**🟢 事实** — 端到端延迟拆解（官方提供的参考数据）：  
证据：[Streaming Performance Considerations](https://www.palantir.com/docs/foundry/building-pipelines/streaming-performance-considerations/)

> "A standard streaming pipeline can run through the following stages in under 15 seconds:"
> - Ingestion: ~1-2 seconds
> - Transformation: ~5s (exactly-once) / ~1s (at-least-once)
> - Syncing into backing datastore: ~5s (exactly-once) / ~1s (at-least-once)

**🟢 事实** — 可调参数：
- **Partitions 数量**：增加分区提升并行度和吞吐量
- **Stream Type**：设为 `HIGH THROUGHPUT` 增大每批次记录数，牺牲延迟换取吞吐（适用于 Total Lag > 0 场景）

**🟢 事实** — 计算资源分配模型：  
证据：[Streaming Compute Usage](https://www.palantir.com/docs/foundry/building-pipelines/streaming-compute-usage/)
- **静态分配**：资源按峰值需求固定分配，不随数据量弹性伸缩
- 分两类计费：Live Processing Compute（运行 Transform）+ Archiving Compute（归档到冷存储）
- 即使无数据流入，也持续消耗 Compute-Seconds

**🟡 推断** — 静态分配模型意味着资源利用率在低峰期偏低，这是 Stream 成本高于 Batch 的核心原因之一。

---

## 二、与 Batch 链路的关键差异

### 2.1 三种处理模式对比

证据：[stream-vs-batch](https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/) + [Incremental Pipelines](https://www.palantir.com/docs/foundry/building-pipelines/pipeline-types/#incremental)

| 特性 | Batch Pipeline | Incremental Pipeline | Streaming Pipeline |
|---|---|---|---|
| **处理触发** | 上游数据变化时 | 上游有新数据时 | 持续运行 |
| **处理粒度** | 全量重算 | 仅处理新增/变更行 | 逐行（per-record）|
| **延迟** | 分钟~小时 | 分钟级 | 秒级（<15s）|
| **计算成本** | 中等（按需运行）| 低 | 高（持续占用）|
| **开发复杂度** | 低 | 中（需理解事务机制）| 高 |
| **维护复杂度** | 低 | 中 | 高 |
| **主要开发工具** | Pipeline Builder / Code Repository | Code Repository（`@incremental`）| Pipeline Builder + Java UDF |
| **Python 支持** | 完整 | 完整 | **不支持** |
| **SQL 支持** | 完整 Spark SQL | Spark SQL | **无完整 SQL**，仅可视化算子 |

### 2.2 User Edits 为何在流处理中不支持：根因分析

这是本次调研的重点问题，以下分层说明：

#### 2.2.1 官方表述（🟢 事实）

官方文档明确说明：
> "Actions are not yet supported on object types with Foundry stream datasources."

官方给出的变通方案：
1. 将用户编辑推入输入 Stream（作为数据事件处理）
2. 新建非流 Object Type，允许用户在该辅助类型上编辑

#### 2.2.2 "most recent update wins" 模型是根因（🟢 事实 + 🟡 推断）

**🟢 事实** — Foundry Streaming 写入 Ontology 的更新策略是 "most recent update wins"：即后到的事件覆盖先到的事件，整个对象的状态由最新一条消息决定。

**🟡 推断（核心根因）** — 这一模型与 Actions（用户编辑）存在本质冲突：

```
时间轴：
t1 → 流事件：{temperature: 20}       → Ontology 对象状态：{temperature: 20}
t2 → 用户 Action：{temperature: 25}  → 状态：{temperature: 25}
t3 → 流事件：{temperature: 22}       → 状态：{temperature: 22}  ← 用户编辑被覆盖！
```

流是持续写入的 changelog，用户 Action 产生的编辑会被下一条流事件立即覆盖，导致：
- 用户看到自己的修改"消失"
- 无法区分"流数据"和"人工修正"的语义边界

#### 2.2.3 Actions 的技术实现与流不兼容（🟡 推断）

Foundry Actions 的底层机制是：
1. 用户在前端触发 Action
2. Action 写入 **Object Storage**，产生一条"覆盖"型写操作
3. Ontology 呈现最新状态

而 Streaming Object Type 的写路径是：
1. Flink Job 实时消费 Stream
2. 每条记录 upsert 到 Object Storage V2（基于 primary key）

两条写路径竞争同一个 Object 状态，且流路径持续以高频写入，Actions 的写入效果会被立即覆盖，产品层面无法保证 Actions 的有效性，因此 Palantir 在产品设计上直接禁止了这一组合。

#### 2.2.4 与批处理的对比（为什么批处理支持）

批处理 Object Type 支持 Actions，因为批处理 Pipeline 是**按触发周期运行**的：
- 两次 Build 之间有明确的静默期
- Actions 写入的状态在静默期内稳定保留
- 下次 Build 时，平台可以在合并逻辑中明确区分"流式数据"和"人工修正"

流处理没有静默期，这是 User Edits 不被支持的本质原因。

### 2.3 引擎差异

**🟢 事实：**  
证据：[Flink Fundamentals](https://www.palantir.com/docs/foundry/data-integration/flink-streaming/)
- Batch：Apache Spark（擅长大规模有界数据集的并行处理）
- Stream：Apache Flink（专为无界流数据设计，低延迟，有状态）

官方引用原文：
> "Foundry streaming uses Flink as the underlying engine to execute user code and other in-platform streaming applications such as hydrating the Ontology in real time and streaming time series ingestion."

**🟡 推断** — Pipeline Builder 对两套引擎做了统一抽象，但两者底层差异导致：
- Python Transform 无法在 Flink 上等效运行（官方已确认不支持）
- 有状态算子（Window、Join）的语义在流处理中更复杂，批处理无需关心 state 增长

---

## 三、技术实现架构

### 3.1 Flink 执行架构

**🟢 事实** — Foundry 流处理基于标准 Apache Flink 架构：  
证据：[Flink Fundamentals](https://www.palantir.com/docs/foundry/data-integration/flink-streaming/)

```
┌─────────────────────────────────────────┐
│           Foundry Control Plane          │
│  ┌─────────────────────────────────┐    │
│  │         Job Manager              │    │
│  │  - 任务调度                      │    │
│  │  - 资源管理（Task Slots）         │    │
│  │  - Checkpoint 协调               │    │
│  │  - JobGraph → ExecutionGraph     │    │
│  └──────────────┬──────────────────┘    │
│                 │                        │
│    ┌────────────┼────────────┐           │
│    ↓            ↓            ↓           │
│  [TM1]        [TM2]        [TM3]         │
│  Task        Task          Task          │
│  Manager     Manager       Manager       │
│  (Worker)    (Worker)      (Worker)      │
└─────────────────────────────────────────┘
```

官方引用：
> "The Flink Job Manager is responsible for scheduling tasks and allocating resources for tasks, handling finished or failed tasks, coordinating job checkpoints and failure recovery..."
> "The Flink Task Manager is responsible for the execution of tasks as well as buffering and exchanging data between streams."

**🟢 事实** — Flink 算子图（Operator Graph）：
- Flink Job 内部表示为 JobGraph（逻辑图）
- 执行时转为 physical graph，由 tasks 组成（一个 task = 一个或多个链式算子）
- **Job Tracker**：Foundry 提供 UI 可查看 Flink Job 的 JobGraph 预览（在 Details 面板）

### 3.2 有状态处理与 Checkpoint

**🟢 事实** — 有状态操作的例子（官方明确列出）：  
证据：[Flink Fundamentals # job-state](https://www.palantir.com/docs/foundry/data-integration/flink-streaming/#job-state)
- **聚合（Aggregations）**：如 5 分钟滚动窗口内事件计数、全局 running average
- **Join**：需要记住历史事件才能与当前事件做关联

**🟢 事实** — 有状态 transform 的关键风险（官方提示）：  
证据：[stream-vs-batch # state-management](https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/#state-management)

> "stateful streaming applications may have unbounded state that can grow over time and result in an out of memory error at an unknown point in the future. As an example, performing an aggregation over one or more keys is generally a dangerous operation if the size of the key space is unbounded."

**🟢 事实** — 所有 Pipeline Builder 有状态 transform 使用 **Keyed State**：  
证据：[Streaming Stateful Transforms](https://www.palantir.com/docs/foundry/building-pipelines/streaming-stateful-transforms/)
- 用户必须指定 Partition Key（相同 Key 的记录路由到同一算子实例）
- 不同 Key 的处理并行、隔离

**🟢 事实** — Foundry 提供两种一致性配置：  
证据：[Streaming Stateful Transforms](https://www.palantir.com/docs/foundry/building-pipelines/streaming-stateful-transforms/)
- `AT_LEAST_ONCE`：低延迟，可能重复
- `EXACTLY_ONCE`（默认）：精确一次，有额外开销

### 3.3 端到端数据流

**🟢 事实：**

```
外部流源（Kafka/Kinesis/Pub-Sub）
        ↓ [Data Connection / Streaming Sync]
  Foundry Stream（Hot Buffer + 冷归档）
        ↓ [Pipeline Builder Streaming Pipeline]
  Flink Job（JobGraph → tasks 并行执行）
        ↓ [输出]
  ┌──────────────────────────────────────┐
  │  写入 Foundry Ontology（<15s）        │
  │  写入 Foundry Dataset（冷归档）       │
  │  写出到外部 Kafka（Streaming Export） │
  └──────────────────────────────────────┘
```

**🟡 推断** — Pipeline Builder 内部将低代码配置编译为 Flink JobGraph，然后提交到 Flink 集群执行。Flink JobGraph 的预览在 Job Tracker 中可见（官方已确认），印证了这一推断。

### 3.4 延迟分析

**🟢 事实** — 官方给出的延迟因素和参考数据：  
证据：[Streaming Performance Considerations](https://www.palantir.com/docs/foundry/building-pipelines/streaming-performance-considerations/)

影响端到端延迟的因素（按官方说明）：
1. **Source 生产速度**：Foundry 只能以 Source 速度消费
2. **网络跨边界**：跨网络传输增加延迟
3. **Pipeline 阶段数**：多个 Repository 或 Builder Pipeline 链式连接会叠加延迟（跨阶段无法 Co-locate 优化）
4. **一致性模型**：Exactly-Once 比 At-Least-Once 增加约 4s 延迟
5. **时间窗口**：30s 窗口隐性增加 30s 延迟

**🟢 事实** — Co-location 优化（官方明确说明）：
> "Foundry streaming will co-locate pipeline transformations defined in the same Code Repository or Pipeline Builder graph onto the same physical hardware to automatically optimize latencies."

---

## 四、能力建设参考建议

> 本节为基于调研的设计建议，属于 🟡 推断，仅供参考。

### 4.1 核心技术栈（事实层面已确认）

- 流处理引擎：Apache Flink
- 接入层：Kafka（主流）+ Kinesis / Pub-Sub（可选）
- 低代码界面：类 Pipeline Builder 的可视化算子连接界面
- 存储：热存储（Hot Buffer）+ 冷归档（Parquet/Avro in 对象存储）

### 4.2 流处理 vs 批处理选型判断依据

| 判断条件 | 推荐选型 |
|---|---|
| 端到端延迟需求 >10 分钟 | Batch 或 Incremental |
| 端到端延迟需求 <1 分钟 | Streaming |
| 需要复杂 Python/SQL 逻辑 | Batch（更完整的工具支持）|
| 需要实时告警/实时触发 | Streaming |
| 数据量大但时效性低 | Batch（成本更低）|
| 需要 User Edits（人工修正）| Batch（Streaming 不支持）|

---

## 五、信息来源

| 结论类别 | 来源 URL |
|---|---|
| Streaming 概述、最佳实践 | [building-pipelines/streaming-overview](https://www.palantir.com/docs/foundry/building-pipelines/streaming-overview/) |
| Stream vs Batch 特性对比 | [building-pipelines/stream-vs-batch](https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/) |
| 延迟拆解数据 | [building-pipelines/streaming-performance-considerations](https://www.palantir.com/docs/foundry/building-pipelines/streaming-performance-considerations/) |
| Flink 架构细节 | [data-integration/flink-streaming](https://www.palantir.com/docs/foundry/data-integration/flink-streaming/) |
| 有状态 Transform | [building-pipelines/streaming-stateful-transforms](https://www.palantir.com/docs/foundry/building-pipelines/streaming-stateful-transforms/) |
| 计算资源模型 | [building-pipelines/streaming-compute-usage](https://www.palantir.com/docs/foundry/building-pipelines/streaming-compute-usage/) |
| Stream 数据模型 | [data-integration/streams](https://www.palantir.com/docs/foundry/data-integration/streams/) |

---

*文档最后更新：2026-04-28*
