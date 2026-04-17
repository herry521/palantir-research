# Palantir 流批一体架构调研

**调研日期：** 2026-04-16  
**调研方向：** Streaming Pipeline / 流批架构 / Pipeline Builder

---

## 核心发现

### 1. Streaming Pipeline 底层引擎

**⚠️ 修正（原报告错误）：流处理引擎是 Apache Flink，非 Spark Structured Streaming**

Foundry 流批使用**不同引擎**：
- **批处理**：Apache Spark（Code Repository 的 `@transform_df` 等）
- **流处理**：Apache Flink（Pipeline Builder 的 Streaming Pipeline）

Pipeline Builder 统一界面屏蔽了两者差异，但底层执行引擎是分开的。

**Flink 在 Foundry 中的关键特性：**
- 有状态流处理（Keyed State）：`ValueState`、`ListState`、`MapState` 等原语
- Checkpointing：定期快照状态 + 流位置，故障后从最近 Checkpoint 恢复
- 一致性保证：支持 `AT_LEAST_ONCE` 和 `EXACTLY_ONCE` 两种模式（后者有额外延迟开销）
- 有状态转换要求用户指定 **Partition Key**，相同 Key 的记录路由到同一 Flink 算子实例

**延迟指标：**
- 数据从 Kafka 消费到写入 Ontology / 时序应用：**在推荐配置下可达 < 15 秒**（非硬性 SLA，受数据量、算子复杂度、资源规格影响）
- Flink 低延迟特性优于 Spark Streaming，理论上可支持亚秒级场景

**Kafka 集成细节：**
- Foundry 提供原生 Kafka Connector，支持 Kafka 0.10+
- Connector 不解析消息内容，原始消息存入 `value` 列（bytes）
- 下游 Transform 负责解析（如 JSON 解析、Schema 映射）
- Offset 管理：由 Flink Checkpoint 机制自动管理

**一致性模式对比：**
| 模式 | 语义 | 延迟影响 | 适用场景 |
|---|---|---|---|
| `AT_LEAST_ONCE` | 至少一次，可能重复 | 低 | 可幂等处理的场景 |
| `EXACTLY_ONCE` | 精确一次，无重复 | 较高（原子性开销） | 金融、计费等高精度场景 |

---

### 2. Pipeline Builder 技术实现

**定位：** 低代码/无代码可视化 Pipeline 构建器，流批均可用

**与 Code Repository 的关系（修正）：**
- Pipeline Builder 和 Code Repository 是**并列关系**，不是主从关系
  - 批处理：既可用 Pipeline Builder（低代码），也可用 Code Repository `@transform_df`（代码优先）
  - 流处理：主要通过 Pipeline Builder 构建，Code Repository 提供 UDF 补充
- Pipeline Builder 支持将 Pipeline 逻辑**导出为代码**（Export to Code），促进互操作
- 用户在 Pipeline Builder 中配置的 Join/Filter/Cast 等操作，底层编译为相应引擎（Spark/Flink）的 API 调用

**典型流处理开发流程：**
```
Kafka Topic
    │
    ▼ [Foundry Kafka Connector]
Foundry Stream Dataset（原始二进制）
    │
    ▼ [Pipeline Builder - Cast bytes → string]
中间 Dataset（字符串）
    │
    ▼ [Pipeline Builder - JSON Parse]
结构化 Dataset（schema 化）
    │
    ▼ [Pipeline Builder / Code Repository - 业务转换]
输出 Dataset / Ontology Object Type
```

**AIP 辅助功能（2024-2025）：**
- 在 Pipeline Builder 中通过自然语言描述转换逻辑，AIP 自动生成 SQL 或 PySpark 代码
- "AI FDE" 功能：自然语言驱动 Foundry 操作，包括构建 Pipeline、管理 Code Repo

---

### 3. 流批统一接口分析

**Foundry 的流批一体程度：**

Foundry **没有完全统一**的流批编程 API（不同于 Apache Beam 的 PCollection 抽象），但提供了：

1. **统一的 Dataset 抽象**：流数据最终也落地为 Foundry Dataset（Parquet），使流处理输出可以直接被批处理 Transform 消费
2. **同一 Ontology 层**：无论数据来自批处理还是流处理，都写入相同的 Ontology Object Type，上层应用无感知
3. **Pipeline Builder 统一界面**：同一界面既能构建批处理 Pipeline，也能构建 Streaming Pipeline（运行时不同）

**与 Apache Beam 的对比：**
| 维度 | Palantir Foundry | Apache Beam |
|---|---|---|
| 统一 API | 否（批/流用不同 API） | 是（PCollection 统一） |
| 执行引擎 | Flink（流）/ Spark（批） | 可插拔 Runner（Flink/Spark/Dataflow） |
| 编程模型 | 命令式（PySpark/Pipeline Builder） | 声明式（Pipeline + PTransform） |
| 窗口操作 | Flink 原生支持 | 原生支持（更丰富） |
| 平台绑定 | 强绑定 Foundry | Runner 无关 |

---

### 4. 消息队列集成

**支持的流数据源：**
- Kafka（主要）：原生 Connector，生产就绪
- HTTP/REST：支持通过 `curl` 或 OAuth 工作流推送数据（适合测试/轻量场景）
- 其他（Kinesis、Event Hub）：通过 Data Connection 应用配置，具体支持程度取决于版本

**Offset 管理：**
- Flink Checkpoint 自动管理 Kafka Offset（非 Spark Streaming）
- Checkpoint 存储在 Foundry 内部存储（用户透明）
- Exactly-once 语义：需显式配置 `EXACTLY_ONCE` 模式，有额外延迟开销；默认为 `AT_LEAST_ONCE`

**背压处理：**
- Flink 内置背压机制（Credit-based flow control）
- Foundry 通过 Compute Profile 的资源上限间接限制吞吐
- 专用 Streaming 计算资源：分为 **Live processing compute**（处理实时消息）和 **Archiving compute**（归档到存储）两类计量

---

### 5. 延迟与选型建议

**官方选型指南：**

| 场景 | 推荐模式 | 延迟 |
|---|---|---|
| 事件驱动报警、实时监控 | Streaming Pipeline | < 15s |
| 数据近实时同步（分钟级可接受） | Incremental Batch Transform | 1-5min |
| 每日/每小时批量处理 | Full Batch Transform | 分钟~小时级 |
| 复杂 ML 特征工程 | Full Batch Transform | 可接受高延迟 |

**关键原则：**
- 流处理运行**持续消耗 Compute 资源**（即使没有新数据），成本高于批处理
- 简单场景优先考虑 **Incremental Batch**（成本低，开发更简单）
- 真正需要秒级/毫秒级延迟才使用 Streaming Pipeline

---

## 流批对比表

| 维度 | Streaming Pipeline | Incremental Batch | Full Batch |
|---|---|---|---|
| 延迟 | < 15s | 1-5min | 分钟~小时 |
| 开发复杂度 | 高 | 中 | 低 |
| Compute 成本 | 最高（持续运行） | 中 | 最低 |
| 适合数据规模 | 高吞吐流 | 中大规模 | 任意 |
| 一致性保证 | Exactly-once（Foundry + Kafka） | At-least-once（增量语义） | 强一致 |
| 主要工具 | Pipeline Builder | @incremental 装饰器 | @transform_df |
| 状态管理 | Spark Checkpoint | Transaction History | 无状态 |

---

## 关键结论

1. **流处理引擎是 Apache Flink（非 Spark）**：批处理用 Spark，流处理用 Flink，Pipeline Builder 统一界面屏蔽引擎差异；Flink 比 Spark Streaming 更擅长低延迟和有状态计算
2. **Pipeline Builder 与 Code Repository 是并列关系**：批处理两者均可选，流处理主要用 Pipeline Builder；Code Repository 提供 UDF 补充，不是从属关系
3. **流批统一的实现层在 Ontology**：不在 API 层，而在数据目的地层——流和批最终都写入同一 Ontology，上层应用无感知
4. **< 15s 延迟是推荐配置下的典型值，非硬性 SLA**：受数据量、算子复杂度、Compute 规格影响
5. **Exactly-once 需显式配置，非默认**：默认为 `AT_LEAST_ONCE`，`EXACTLY_ONCE` 有额外延迟开销，需根据业务精度要求权衡

---

## 待深挖问题

- Foundry Streaming 是否支持 Flink 作为可选执行引擎（或计划支持）
- `complete` 输出模式下的状态存储实现（外部 KV 还是 Spark 内存）
- 流处理 Pipeline 的 Schema Evolution 如何处理（上游 Kafka 消息 Schema 变更）
- Foundry Streaming 与 Confluent Platform 的集成深度

---

## 参考来源

- Palantir Foundry 文档：Streaming Pipelines、Pipeline Builder
- Kafka Connector 集成文档
- Spark Structured Streaming 官方文档
- 社区调研：Foundry streaming latency、compute usage
