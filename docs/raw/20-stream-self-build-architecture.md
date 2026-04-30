# 类 Palantir Stream 能力自建方案

**调研日期：** 2026-05-01  
**文件编号：** 20  
**主题：** 基于 Kafka + Flink + Paimon 实现类 Palantir Stream 能力的架构方案  
**前置文档：** [16-streaming-capability-deep-dive.md](./16-streaming-capability-deep-dive.md) | [19-streaming-pipeline-deep-dive.md](./19-streaming-pipeline-deep-dive.md)  
**可信度标注：** 🟢 事实 🟡 推断 🔴 猜测

---

## 一、前提约束

**延迟目标：< 5s 端到端**

此约束决定 Hot Buffer 层必须保留 Kafka，Paimon 单独无法满足（Paimon 数据可见性受 Flink checkpoint interval 约束，最低 ~10s）。

---

## 二、整体架构

```
外部数据源（Kafka / Kinesis / HTTP）
         ↓
 ┌───────────────────────────────┐
 │   Kafka（Hot Buffer）         │  ← 毫秒级读取，retention 24–72h
 │   · 原始消息保留               │
 │   · 下游流消费直接走此层        │
 └──────────────┬────────────────┘
                │ Flink Consumer
                ↓
 ┌──────────────────────────────────────────┐
 │   Flink Processing Pipeline              │
 │   · Schema 解析 / 字段映射               │
 │   · Window 聚合 / Join / Filter          │
 │   · Exactly-once（2PC Checkpoint）       │
 └──────────┬─────────────────┬────────────┘
            ↓                 ↓
 ┌──────────────────┐  ┌──────────────────────────┐
 │  Paimon PK Table │  │  回写 Kafka（Streaming    │
 │  （Cold Storage）│  │   Export，可选）           │
 │  · LSM 分层存储  │  └──────────────────────────┘
 │  · upsert/merge  │
 │  · 批/增量读均可 │
 └──────────────────┘
```

---

## 三、各层实现细节

### 3.1 Hot Buffer 层 — Kafka

直接复用现有 Kafka，关键配置：

```properties
# 保留足够时间供下游消费（按数据量调整）
retention.ms = 86400000        # 24h

# 分区数按吞吐估算，单分区约 5MB/s 上限
# 示例：吞吐 100MB/s → 20 partitions

# offset 管理交给 Flink Checkpoint，不走 consumer group commit
```

**写入保证**：配置 idempotent producer 可达 exactly-once 投递，优于 Palantir hot buffer 的 at-least-once。

### 3.2 Flink Processing Pipeline — 分两段部署

两段分离的核心原因：Segment 1 保证 Cold Storage 数据新鲜度，Segment 2 有状态计算允许更长 checkpoint 以降低开销，两者互不干扰。

**Segment 1：Ingestion（无状态，低延迟）**

```
Kafka → Schema 解析 → 基础字段映射 → 写 Paimon
checkpoint interval = 5–10s
```

**Segment 2：Transform（有状态，允许较高延迟）**

```
Paimon → Window 聚合 / 多流 Join / 复杂计算 → 输出 Paimon / Kafka
checkpoint interval = 30s–2min
```

### 3.3 Cold Storage 层 — Paimon Primary Key Table

```sql
CREATE TABLE stream_events (
    event_id     STRING,
    device_id    STRING,
    event_time   TIMESTAMP(3),
    payload      STRING,
    PRIMARY KEY (device_id, event_id) NOT ENFORCED
) WITH (
    'bucket'                           = '8',
    'changelog-producer'               = 'input',   -- 最低延迟 changelog
    'compaction.optimization-interval' = '1 min',   -- 定期 compact，稳定查询性能
    'lookup.cache-max-memory-size'     = '256mb',   -- 热点 Key 内存缓存
    'snapshot.time-retained'           = '2h',
    'file.format'                      = 'parquet'
);
```

**分层访问模式：**

| 访问场景 | 读的层 | 延迟 |
|---|---|---|
| 实时流消费（Flink downstream） | Kafka Hot Buffer | 毫秒级 |
| 近实时点查 / lookup join | Paimon L0 + lookup cache | ~checkpoint interval（5–10s）|
| 历史批分析（Spark/Trino） | Paimon L1+ compacted files | 秒~分钟 |
| 增量同步（CDC 下游） | Paimon changelog | checkpoint interval 后可见 |

### 3.4 Schema 管理 — Confluent Schema Registry

```
Confluent Schema Registry（开源版）
  ↑
Kafka Producer（写入时注册 Schema）
  ↓
Flink Consumer（通过 Schema ID 反序列化）
  ↓
Paimon（存储层 Schema 由 Paimon 元数据管理，支持 Evolution）
```

Flink 侧使用 `flink-avro-confluent-registry` 直接集成，Schema 变更的兼容性检查由 Registry 统一管控。

### 3.5 Streaming Export（回写链路，可选）

两种实现路径：

**路径 A（推荐，延迟更低）**：直接在 Flink Pipeline 输出侧分叉写 Kafka，无需经过 Paimon。

**路径 B**：读 Paimon changelog → Flink 过滤/转换 → 写外部 Kafka，适合需要基于 Cold Storage 聚合结果回写的场景。

---

## 四、Paimon 替换 Palantir 冷存的能力对比

### Hot Buffer 层

| 维度 | Palantir Hot Buffer | Kafka + Paimon |
|---|---|---|
| 最低延迟 | <1s（append 即可读）| Kafka 毫秒级；Paimon ~checkpoint interval |
| 写入保证 | at-least-once | Kafka idempotent = exactly-once |
| 主键 upsert | ❌ append-only | ✅ Paimon PK table |
| 单行 TTL 管理 | 隐式（buffer 自动淘汰）| Kafka retention.ms 精确控制 |
| 高频小消息 | 原生支持 | Kafka 原生支持；Paimon 需 precommit-compact 防小文件 |

### Cold Storage 层

| 维度 | Palantir Cold Storage（Avro）| Paimon |
|---|---|---|
| 存储格式 | Avro | Parquet / ORC（列式，压缩更优）|
| 索引能力 | ❌ 无索引，全文件扫描 | ✅ LSM 索引 + Bloom filter + 主键过滤 |
| 主键 upsert/merge | ❌ 裸文件，无合并 | ✅ MergeEngine（deduplicate / partial-update / aggregation）|
| Schema Evolution | 依赖外部 Schema Registry | ✅ Paimon 元数据原生管理 |
| 增量读（Changelog）| ❌ 需额外 CDC 组件 | ✅ 原生 changelog，Flink/Spark 均可消费 |
| 多引擎支持 | Foundry 生态内 | ✅ Flink / Spark / Trino / Hive / StarRocks |
| Compaction 开销 | ❌ 无（顺序写完即归档）| ⚠️ 后台持续 LSM compaction，需资源预留 |
| 小文件风险 | 低（定时批量归档）| 高频写入需调优，否则 L0 堆积影响查询 |

---

## 五、与 Palantir Stream 整体能力对比

| 能力 | Palantir Stream | 自建方案 | 差距说明 |
|---|---|---|---|
| Hot Buffer 低延迟读 | ✅ <15s | ✅ Kafka 毫秒级 | **自建更好** |
| Cold Storage 批分析 | ✅ Avro 文件 | ✅ Paimon（有索引）| **自建更好** |
| Exactly-once 写入 | at-least-once（hot）| ✅ Flink 2PC | **自建更好** |
| 主键 upsert | ❌ append-only | ✅ Paimon PK table | **自建更好** |
| Schema Evolution | ✅ Schema Registry | ✅ Confluent Registry + Paimon | 持平 |
| Changelog 下游消费 | ❌ 需额外 CDC | ✅ Paimon 原生 changelog | **自建更好** |
| 分支支持 | 每 branch 限 1 stream | ✅ Paimon branch 功能 | 持平 |
| 低代码 Pipeline UI | ✅ Pipeline Builder | ⚠️ 需自建或引入 StreamPark | **有差距** |
| Ontology 集成 | ✅ 原生 <15s | ⚠️ 需自建对象层 | **有差距** |
| 监控告警 | ✅ Data Health App | ⚠️ Flink Metrics + Grafana | **需建设** |

---

## 六、建设优先级建议

1. **先跑通主链路**：Kafka → Flink Segment 1 → Paimon，验证延迟和吞吐是否满足目标
2. **Schema Registry 早接入**：避免后期 Schema 变更引发 Pipeline 中断
3. **Segment 1/2 分离部署**：Ingestion 和 Transform 独立，互不影响 checkpoint 节奏
4. **监控先行**：Flink Metrics + Paimon 读写延迟 + Kafka Consumer Lag 接入 Grafana，流式链路没有监控等于盲飞
5. **低代码 UI 后建**：主链路稳定后再考虑 StreamPark 或自研 Pipeline 配置界面

---

*文档最后更新：2026-05-01*
