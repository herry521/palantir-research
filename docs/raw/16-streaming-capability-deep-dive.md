# Palantir Foundry Stream 能力深度调研

**调研日期：** 2026-04-28  
**调研方向：** Stream 产品能力全景 / 与 Batch 链路差异 / 技术实现架构  
**可信度标注：** 🟢 事实（官方文档/可验证） 🟡 推断（逻辑推理） 🔴 猜测（无直接证据）

---

## 一、产品能力全景

### 1.1 数据摄入能力

**🟢 事实** — Foundry 提供原生连接器支持以下流数据源：
- Apache Kafka（主流，最常见）
- Amazon Kinesis
- Google Pub/Sub
- OSI PI（工业场景）
- 通过 External Transforms 支持其他自定义流源

**🟢 事实** — Kafka 连接方式：
- 支持 Agent-based 连接（推荐方式，改善性能和可用性）
- Connector 读取原始 bytes 到 `value` 列，不自动解析消息内容
- Offset 管理由 Flink Checkpoint 机制全自动处理，无需手动配置
- 支持 Streaming Syncs（数据流入 Foundry）和 Streaming Exports（数据从 Foundry 写出到 Kafka）

### 1.2 数据处理能力

**🟢 事实** — 主要开发界面：Pipeline Builder（低代码可视化工具）

**🟢 事实** — Pipeline Builder 内置 Stream 算子：
- **Filter**：按条件过滤记录
- **Join**：流与流 Join（Outer Caching Join，需指定匹配条件和缓存时间）
- **Aggregate over window**：窗口内聚合（支持各类聚合函数，有 trigger 机制）
- **Project over window**：窗口内投影（每收到新行即触发输出）
- 标准列操作（重命名、类型转换、计算字段等）

**🟢 事实** — UDF 扩展机制：
- 在 Code Repository 中用 Java 或 Python 定义 UDF
- UDF 在 Pipeline Builder 中作为节点调用
- **Python UDF 仅支持部分场景**（不是全量等同于批处理中的 Python Transform）

**🟢 事实** — FoundryTS 时序函数（流场景适用）：
- `functions.rolling_aggregate`：滑动窗口聚合
- `functions.periodic_aggregate`：固定周期窗口聚合

**🟡 推断** — Pipeline Builder 对 Streaming 的算子覆盖范围窄于批处理，复杂流处理逻辑（如多流 Join、复杂状态机）需要 UDF 承载。

### 1.3 数据存储模型：Stream vs Dataset

**🟢 事实** — Foundry Stream 内部架构是双层存储：

```
外部数据源（Kafka 等）
        ↓
  [热存储 Hot Buffer]  ← 低延迟访问层，记录实时读取
        ↓（每隔几分钟归档）
  [冷存储 Cold Storage]  ← 文件系统，Avro 格式
        ↓
  作为普通 Foundry Dataset 可被批处理访问
```

| 特性 | Dataset（批） | Stream |
|---|---|---|
| 存储格式 | Parquet（主流）+ 其他文件 | Avro（热）+ 文件系统（冷） |
| 访问延迟 | 分钟~小时级 | 秒级（<15s）|
| 数据结构 | 结构化/非结构化均支持 | 仅结构化（tabular）|
| 单条记录上限 | 无明确限制 | **1MB**（硬限制）|
| 属性数量上限 | 无明确限制 | **250 个属性** |
| Ontology 集成 | 支持 | 支持（streaming object type）|

**🟢 事实** — Stream 冷存储定期归档后可被非流处理应用访问，实现冷热数据统一。

### 1.4 Ontology 集成

**🟢 事实** — 流数据可直接写入 Foundry Ontology，写入延迟 <15s。

**🟢 事实** — Ontology 集成限制（流处理对比批处理的差异）：
- **不支持 User Edits**（批处理 Object Type 支持）；变通方案：将用户编辑推入输入 Stream
- **不支持 Multi-Datasource Objects（MDO）**
- **不支持监控指标**（如 pipeline latency 监控），批处理有 Monitor 支持
- 事件乱序风险：采用 "最近更新优先（most recent update wins）" 策略，源端乱序会导致 Ontology 数据错误

**🟡 推断** — Foundry 流处理 Ontology 集成的完整度不及批处理，是产品成熟度差距，预期未来版本会缩小。

### 1.5 性能调优能力

**🟢 事实** — 可调参数：
- **Partitions 数量**：增加分区提升并行度和吞吐量
- **Stream Type**：设为 `HIGH THROUGHPUT` 增大每批次记录数，牺牲延迟换取吞吐（适用于 Total Lag > 0 场景）

**🟢 事实** — 计算资源分配模型：
- 静态分配（Static Allocation）：资源按峰值需求固定分配，不随数据量弹性伸缩
- 分两类计费：Live Processing Compute（运行 Transform）+ Archiving Compute（归档到冷存储）
- 即使无数据流入，也持续消耗 Compute-Seconds

**🟡 推断** — 静态分配模型意味着资源利用率在低峰期偏低，这是 Stream 成本高于 Batch 的核心原因之一。

---

## 二、与 Batch 链路的关键差异

### 2.1 三种处理模式对比

| 特性 | Batch Pipeline | Incremental Pipeline | Streaming Pipeline |
|---|---|---|---|
| **处理触发** | 上游数据变化时 | 上游有新数据时 | 持续运行 |
| **处理粒度** | 全量重算 | 仅处理新增/变更行 | 逐行（per-record）|
| **延迟** | 分钟~小时 | 分钟级 | 秒级（<15s）|
| **计算成本** | 中等（按需运行）| 低 | 高（持续占用）|
| **开发复杂度** | 低 | 中（需理解事务机制）| 高 |
| **维护复杂度** | 低 | 中 | 高 |
| **数据规模弹性** | 低（全量重算开销随量增长）| 高 | 高 |
| **主要开发工具** | Pipeline Builder / Code Repository | Code Repository（`@incremental`）| Pipeline Builder + UDF |
| **支持语言** | Python / Java / SQL / Spark | Python / Java | **Java 为主**，Python 限制较多 |
| **SQL 支持** | 完整 SQL（Spark SQL）| Spark SQL | **无完整 SQL**，仅 Pipeline Builder 可视化算子 |

### 2.2 能力边界：Streaming 不支持的场景

**🟢 事实（经官方确认的限制）：**

1. **Python Transform**：流处理不支持纯 Python Transform（与批处理的最大差异之一）
2. **完整 SQL 语法**：不能直接写 Spark SQL / HiveQL，复杂查询需用 UDF 或 Pipeline Builder 算子组合
3. **多数据源对象（MDO）**：Ontology 层不支持
4. **User Edits**：Ontology 对象不支持直接用户编辑
5. **任意 Schema 演进**：流处理对 Schema 变更敏感，批处理更宽容
6. **Frontend 自动刷新**：Workshop 外的 Foundry 前端应用不原生支持流数据自动推送（需手动刷新）
7. **监控指标**：缺乏针对流 Object Type 的 Pipeline Latency 等监控，批处理有完整 Monitor 支持

**🟡 推断** — Code Repository 中无法像批处理一样用 `@transform_df` 定义整个流处理 Pipeline；流处理的"代码优先"路径受限，必须经过 Pipeline Builder，灵活性低于批处理。

### 2.3 引擎差异

**🟢 事实：**
- Batch：Apache Spark（擅长大规模有界数据集的并行处理）
- Stream：Apache Flink（专为无界流数据设计，低延迟，有状态）

**🟡 推断** — Pipeline Builder 对两套引擎做了统一抽象，但两者底层差异导致：
- 某些 Spark SQL 特性无法直接在 Flink 上使用
- 有状态算子（Window、Join）的语义在流处理中更复杂

---

## 三、技术实现架构

### 3.1 Flink 执行架构

**🟢 事实** — Foundry 流处理基于标准 Apache Flink 架构：

```
┌─────────────────────────────────────────┐
│           Foundry Control Plane          │
│  ┌─────────────────────────────────┐    │
│  │         Job Manager              │    │
│  │  - 任务调度                      │    │
│  │  - 资源管理（Task Slots）         │    │
│  │  - Checkpoint 协调               │    │
│  │  - LogicalGraph → ExecutionGraph │    │
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

- **Job Manager**：主节点，负责调度、资源分配、Checkpoint 协调、故障恢复
- **Task Manager**：工作节点，执行实际计算任务，每个 TM 含多个 Task Slots
- **Task Slot**：基本资源分配单位，同一 TM 的多个 Slot 共享内存但隔离 CPU

**🟢 事实** — Flink 算子图（Operator Graph）：
- Flink Job 表示为算子的有向无环图（DAG）
- Job Manager 将逻辑图（JobGraph）转为物理执行图（ExecutionGraph）
- 算子链（Operator Chaining）：相邻算子尽量合并在同一 Task 中，减少网络传输

### 3.2 有状态处理与 Checkpoint

**🟢 事实** — Flink 支持的 State 原语：
- `ValueState`：单个值状态
- `ListState`：列表状态
- `MapState`：KV 映射状态
- `ReducingState` / `AggregatingState`：聚合状态

**🟢 事实** — Checkpoint 机制：
- 基于 Chandy-Lamport 分布式快照算法
- 定期将算子状态 + 流消费位置（如 Kafka offset）快照到持久存储
- 故障后从最近 Checkpoint 恢复，保证 Exactly-Once（配合两阶段提交 Sink）

**🟢 事实** — Foundry 提供两种一致性配置：
- `AT_LEAST_ONCE`：低延迟，可能重复
- `EXACTLY_ONCE`（默认）：精确一次，有额外开销

### 3.3 端到端数据流

**🟢 事实：**

```
外部流源（Kafka/Kinesis/Pub-Sub）
        ↓ [Data Connection / Streaming Sync]
  Foundry Stream（热存储 Hot Buffer + 冷归档）
        ↓ [Pipeline Builder Streaming Pipeline]
  Flink Job（算子链 DAG 执行）
        ↓ [输出]
  ┌──────────────────────────────────┐
  │  写入 Foundry Ontology（<15s）    │
  │  写入 Foundry Dataset（冷存储）   │
  │  写出到外部 Kafka（Streaming Export）│
  └──────────────────────────────────┘
```

**🟡 推断** — Pipeline Builder 内部将低代码配置编译为 Flink JobGraph，然后提交到 Flink 集群执行。这是标准的"低代码平台包裹流处理引擎"模式。

### 3.4 延迟分析

**🟢 事实** — 影响端到端延迟的因素：
1. **Source 生产速度**：Foundry 只能以 Source 速度消费
2. **网络跨边界**：跨网络传输增加延迟
3. **Pipeline 阶段数**：多个 Repository 或 Pipeline Builder 图链式连接会叠加延迟
4. **算子复杂度**：有状态算子（窗口/Join）比无状态算子延迟高
5. **Exactly-Once 开销**：启用精确一次处理增加协调开销

**🟢 事实** — Foundry 的优化手段：
- **Co-location（同节点算子链）**：将多个 Transform 尽量合并在同一硬件，减少网络跳数
- **Operator Chaining**：Flink 层面的算子融合

---

## 四、能力建设参考建议

> 本节为基于调研的设计建议，属于 🟡 推断 / 🔴 猜测，仅供参考。

### 4.1 如果要构建同等 Stream 能力

**核心技术栈（事实层面已经明确）：**
- 流处理引擎：Apache Flink（Palantir 选型已确认）
- 接入层：Kafka（标准流消息队列）
- 低代码界面：类 Pipeline Builder 的可视化算子连接界面
- 存储：热存储（如 Kafka-backed buffer）+ 冷存储（Parquet/Avro in 对象存储）

**🟡 推断 — 关键差距点：**
1. 有状态算子（Window/Join）的低代码化包装复杂度高
2. 流批一体的 Ontology/语义层集成是难点
3. Checkpoint 配置、资源分配对用户屏蔽需要大量平台化工作

### 4.2 流处理 vs 批处理选型判断依据

| 判断条件 | 推荐选型 |
|---|---|
| 端到端延迟需求 >10 分钟 | Batch 或 Incremental |
| 端到端延迟需求 <1 分钟 | Streaming |
| 需要复杂 SQL / Python 逻辑 | Batch（更完整的工具支持）|
| 需要实时告警/实时触发 | Streaming |
| 数据量大但时效性低 | Batch（成本更低）|
| 持续监控/实时大盘 | Streaming |

---

## 五、信息来源说明

**🟢 事实来源：**
- Palantir 官方文档（docs.palantir.com，经 web_search 检索）
- 官方产品描述中的明确功能列表和限制说明

**🟡 推断来源：**
- 基于 Flink 标准架构推导的 Foundry 内部实现
- 基于已知限制推导的设计原因

**🔴 猜测：**
- 本文中未出现明确的 🔴 猜测项，上述推断均有一定逻辑基础

---

*文档持续更新，调研日期 2026-04-28*
