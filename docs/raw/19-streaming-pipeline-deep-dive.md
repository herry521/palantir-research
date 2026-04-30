# Palantir Foundry 流式链路深度调研（补充篇）

**调研日期：** 2026-04-30  
**文件编号：** 19  
**主题：** 流式链路深度补充 — Window 操作、Schema Evolution、Streaming Export、State 管理、监控告警  
**前置文档：** [03-streaming-batch-architecture.md](./03-streaming-batch-architecture.md) | [16-streaming-capability-deep-dive.md](./16-streaming-capability-deep-dive.md)  
**可信度标注：** 🟢 事实 🟡 推断 🔴 猜测

---

## 一、Window 操作与 Watermark

### 1.1 三种窗口类型

**🟢 事实** — Pipeline Builder 的 `Aggregate Over Window` 算子支持三种窗口类型：

| 窗口类型 | 语义 | 典型用途 |
|---|---|---|
| **Tumbling（滚动）** | 固定大小、互不重叠。事件按时间分桶，各桶独立计算 | 每 5 分钟统计、周期性报表 |
| **Sliding（滑动）** | 固定大小 + 可配置滑动步长，窗口可重叠，同一事件可属于多个窗口 | 移动平均、滑动趋势分析 |
| **Session（会话）** | 由不活跃间隔（gap）定义边界，活动期内窗口持续扩展，超时后关闭 | 用户行为分析、IoT 设备活跃周期 |

> **🟡 推断** — Pipeline Builder 的滑动窗口在部分场景基于 count 而非 time，复杂的基于时间的滑动窗口可能需要 Java UDF 实现。

### 1.2 Watermark 与迟到数据

**🟢 事实** — Foundry 流处理使用 Watermark 追踪事件时间进度，用于判断窗口何时可以关闭并产出结果：

```
事件时间轴：
  t1   t2   t3 ... tN（事件时间戳，可能乱序到达）
                        ↑
                     Watermark（单调递增，表示"早于此时间的事件已基本到齐"）

窗口触发：watermark 超过 window_end_time + allowed_lateness → 窗口关闭，输出结果
```

**🟢 事实** — `Allowed Lateness` 配置：

> 允许窗口在 watermark 超过窗口结束时间后保持一段额外的开放时间，以接收迟到事件。超过 `window_end + allowed_lateness` 后到达的事件将被**丢弃**。

**🟢 事实** — Watermark 停滞风险（官方提示）：

> 若 watermark 停滞（无新事件或事件时间戳停止推进），有状态算子的 state 将无法被及时清理，可能导致状态无界增长，最终触发 OOM。

**触发器（Trigger）：**

除了基于 watermark 的时间触发，还支持：
- **Count-based trigger**：累积 N 条记录后触发输出
- **Time-based trigger**：每隔 N 秒/分钟触发（即使窗口未关闭）

> **🟡 推断** — 时间触发有助于降低 <15s 端到端延迟目标，避免窗口等待过久才产出第一条输出。

---

## 二、Schema Evolution

### 2.1 Foundry 流式 Schema 管理的核心机制

**🟢 事实** — Foundry Stream 内部使用 Avro 格式存储，Avro 原生支持 Schema Evolution（向前/向后兼容）。

**🟡 推断** — Foundry 依赖 Schema Registry 进行集中式 Schema 管理：
- Producer 写入时引用 Schema ID
- Consumer（Flink Job）通过 Schema ID 从 Registry 获取正确 Schema 进行反序列化
- Schema 变更需满足预定义的兼容性规则（BACKWARD / FORWARD / FULL）

### 2.2 上游 Kafka Schema 变更处理策略

| 变更类型 | 处理方式 | 风险等级 |
|---|---|---|
| 新增字段（有默认值）| Avro 向后兼容自动处理，旧消费者忽略新字段 | 低 |
| 删除字段 | 需 Schema Registry 版本管理；旧 Consumer 使用默认值填充 | 中 |
| 字段重命名 | 破坏性变更，需配合 aliases 或新建 Stream | 高 |
| 类型变更 | 破坏性变更，通常需要新建 Stream + 迁移 | 高 |

**🟢 事实** — Object Storage V2（OSv2）提供 Schema Migration Framework：
- Ontology Manager 自动检测 Object Type 属性变更
- 引导用户选择 Migration 选项（保留旧数据 / 重算 / 忽略）
- 支持增量列新增/删除的自动化处理

**🟡 推断** — Pipeline Builder 的输出 Schema 默认**不动态推断**（避免意外 break 下游），当上游 Stream Schema 变更时需手动更新 Pipeline 的输出 Schema 配置。存在官方未 close 的 feature request 希望支持动态 Schema。

### 2.3 Schema 漂移处理建议（🟡 推断）

```
方案 A（推荐）：在 Kafka 层面控制
  → 使用 Schema Registry + BACKWARD 兼容策略
  → Foundry 侧 Pipeline 无需改动

方案 B：增加 Translation Layer
  → 在 Pipeline Builder 中设置 Schema 映射/归一化步骤
  → 检测并映射 source → stable target schema

方案 C（破坏性变更）：新建 Stream + 迁移
  → 旧 Stream 归档，新 Stream 接入新 Schema
  → 下游 Pipeline 切换到新 Stream
```

---

## 三、Streaming Export（数据回写）

### 3.1 架构概览

**🟢 事实** — Foundry 支持将 Stream 数据写出到外部 Kafka，通过 Data Connection 的 Streaming Export 功能实现：

```
Foundry Stream（内部）
        ↓ [Data Connection - Streaming Export]
外部 Kafka Topic
```

### 3.2 配置参数（官方）

**🟢 事实** — 创建 Streaming Export 时支持以下配置：

| 参数 | 说明 | 备注 |
|---|---|---|
| `Topic` | 目标 Kafka Topic | 必填 |
| `Linger milliseconds` | 批量等待时间（ms），提升吞吐 | 调大可提高吞吐，但增加延迟 |
| `Key column` | 作为 Kafka record key 的列 | 必须对所有行有值 |
| `Value column` | 作为消息体的列（不指定则序列化全部字段）| 可选 |
| `Header column` | 作为 Kafka headers 的列，需为 struct 类型 | 可选 |
| `Enable Base64 Decode` | 对二进制数据解码，仅在 Key + Value 均指定时可用 | 可选 |

> **🟢 事实** — 官方建议优先使用 Data Connection Streaming Export，而非 legacy export task。

### 3.3 Batch Dataset → Streaming Export 模式

**🟡 推断** — 若需将批量 Dataset 转为 Stream 写出到 Kafka，官方推荐做法：
1. 在 Pipeline Builder 中创建 Streaming Pipeline
2. 以批量 Dataset 作为输入
3. 输出配置为 Stream
4. 再通过 Streaming Export 写出到 Kafka

---

## 四、State 管理与 OOM 防控

### 4.1 状态无界增长的根因

**🟢 事实** — 官方明确警告：

> "Stateful streaming applications may have unbounded state that can grow over time and result in an out of memory error at an unknown point in the future."

主要场景：
- 大 Key 空间的 Keyed State（如 user_id 维度聚合，Key 数量持续增加）
- Watermark 停滞导致窗口状态无法及时清理
- Join 两侧流数据量不均衡，一侧历史 buffer 积压

### 4.2 官方提供的缓解策略

**🟢 事实** — 通过窗口（Window + Trigger）控制状态：

- 使用 `Aggregate Over Window` 替代无界聚合，窗口关闭时自动清理 state
- 配置合理的 `Allowed Lateness`，避免 watermark 停滞
- 选择合适 Trigger 频率，及时触发输出并释放 state

**🟡 推断** — 其他缓解手段：
- 减小 Partition Key 的 Key Cardinality（降低 State 总量）
- 适当增大 Streaming Compute Profile（静态分配，内存增大）
- 拆分复杂 Stateful Pipeline 为多段，缩小单 Flink Job 的 state 压力

### 4.3 State 变更与 Pipeline 更新风险

**🟢 事实** — 修改有状态 Pipeline 的 Transform 逻辑时存在状态一致性风险：

> 当 Pipeline 代码变更导致 state 结构发生变化，Flink Job 从 Checkpoint 恢复时可能出现 state schema mismatch，需特别处理（清空 state 重启 / 版本化迁移）。

---

## 五、监控与告警

### 5.1 Data Health Application

**🟢 事实** — Foundry 内置 Data Health Application，支持：
- 针对 Stream 资源设置健康规则和阈值
- 配置告警：流摄入量低于阈值（ingest alert）、输出量低于阈值（output alert）
- 告警渠道：PagerDuty、Slack、Webhook、Foundry 内通知

**🟢 事实** — Stream 健康定义：

> 一个 Stream 被认为健康，当且仅当它正在**持续摄入、处理、持久化数据**。可通过 ingest/output 记录数阈值监控。

### 5.2 Stream Monitoring 告警配置

**🟢 事实** — 可配置的告警维度：

| 告警类型 | 触发条件 |
|---|---|
| Ingest Alert | 单位时间内摄入记录数 < 阈值 |
| Output Alert | 单位时间内输出记录数 < 阈值 |
| Job Health | Job 失败/重启 |

### 5.3 可观测性工具链

**🟢 事实** — 可用工具：
- **Job Tracker**：Flink JobGraph 预览、任务状态、执行历史
- **Workflow Lineage**：跨执行历史追踪，支持日志搜索、状态/耗时过滤
- **Metrics（近实时）**：成功/失败数量、P95 执行时长，覆盖 30 天历史

---

## 六、与现有文档的关系

| 主题 | 所在文档 |
|---|---|
| Flink 引擎、Pipeline Builder、<15s 延迟、静态计算分配 | [03](./03-streaming-batch-architecture.md) / [16](./16-streaming-capability-deep-dive.md) |
| 数据源（Kafka/Kinesis/Pub-Sub）、Hot/Cold 存储、Checkpoint | [16](./16-streaming-capability-deep-dive.md) |
| Stream 分支（每 branch 1 active stream）、Data Connection 配置分支 | [18](./18-branching-data-connection.md) |
| **Window/Watermark/迟到数据、Schema Evolution、Streaming Export、State OOM、监控告警** | **本文（19）** |

---

## 七、待深挖问题

- Pipeline Builder 滑动窗口是否真的仅支持 count-based，time-based 是否有限制
- Foundry 是否内置 Schema Registry，还是依赖外部 Confluent Schema Registry
- Streaming Export 的延迟目标（Foundry → 外部 Kafka 的典型端到端延迟）
- State TTL 是否有显式配置项（类似 Flink 原生的 `StateTtlConfig`），还是只能通过 Window 间接控制

---

*文档最后更新：2026-04-30*
