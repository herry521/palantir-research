# Palantir Time Series Sync、Projection 与索引机制

**日期：** 2026-06-17
**所属 Epic：** #66

---

## 1. 摘要与洞察

1. 【事实】Time series sync 由 dataset 或 stream 支撑，持有多个 series 的 time-value pairs，并作为 TSP 的数据源。
2. 【事实】每条 sync 输入行表示某个 TSP 在单个时间点的值，核心列是 `seriesId`、`timestamp`、`value`。
3. 【事实】创建 time series sync 会为被同步 dataset 创建 projection；projection 用于优化读取时按 series ID 和 time range 过滤时序数据。
4. 【事实】Foundry time series database 像 cache：读取 indexed data，数据在 read time hydrate，磁盘受限时 least recently hydrated series 会先被 evict。
5. 【推断】Palantir 的性能模型是 lake dataset/projection 提供可重建事实源，time series database 提供按需热索引，而不是把所有时序点永久复制进一个不可回放黑盒。

---

## 2. Sync 输入模型

| 列 | 类型 | 要求 | 说明 |
|---|---|---|---|
| Series ID | `String` | Required | TSP 引用的一组 timestamp/value pairs，必须匹配 TSP 的 series ID。 |
| Timestamp | `Timestamp` 或 `Long` | Required | 测量时间。 |
| Value | `Integer`、`Float`、`Double`、`String` | Required | 单点值；`String` 表示 categorical time series。 |

【事实】Categorical time series 每条 series 最多 10,000 个 unique variants；超过限制后该 series ID 会报错且平台不可访问。来源：<https://www.palantir.com/docs/foundry/time-series/time-series-concepts-glossary>

---

## 3. Sync 与 Projection

```text
dataset or stream
  -> transform / Pipeline Builder output
  -> time series sync target
  -> backing dataset
  -> time series projection
  -> Foundry time series database metadata
  -> hydrate on query
  -> TSP / applications
```

【事实】Time series sync 创建时会为 dataset 创建 projection；projection 是优化 TSP 查询的数据布局。来源：<https://www.palantir.com/docs/foundry/time-series/time-series-syncs>

【事实】FAQ 说明 time series projection 是 dataset 的 materialized copy，优化方式包括按照 series ID 和 time range 过滤，并在时序数据上维持好的 partitioning 和 sort。来源：<https://www.palantir.com/docs/foundry/time-series/faqs>

【推断】Projection 更接近湖仓侧的物理访问优化，而不是业务语义层；TSP 仍然通过 sync 与 projection 间接读取。

---

## 4. Hydration 和 Cache

| 场景 | 官方事实 | 影响 |
|---|---|---|
| 首次查询某 series | 若数据未在 time series database 中 indexed，会触发 hydration。 | 首次加载可能慢。 |
| Snapshot transaction | sync 生成 dataset transaction metadata，database 据此知道可 index 的数据。 | 新 snapshot 可能触发较重 hydration。 |
| Incremental pipeline | 新数据可 incremental hydrate。 | 推荐增量 pipeline 提升后续 indexing 性能。 |
| Cache eviction | time series database 像 cache，磁盘受限时 least recently hydrated series 先 evict。 | 长尾 series 可能重新触发 snapshot hydration。 |
| 查询加 time filter | 只 hydrate 指定 time range，避免拉全量 series。 | 应用和 SDK 应默认支持时间范围过滤。 |

来源：<https://www.palantir.com/docs/foundry/time-series/faqs>

---

## 5. 性能和规模边界

| 主题 | 官方事实 | 自研建议 |
|---|---|---|
| 大 dataset | 输入 dataset 超过 10 TB 时，建议按 series identifier 拆分成多个 dataset，再创建较小 sync，或使用 view optimization。 | 大规模时序应按 series hash/业务域拆分物理 shard，避免单 projection 超大。 |
| Projection outdated | projection 未覆盖的新 transaction 会回读 canonical dataset，可能导致扫描更多文件和超时。 | projection/index build 必须纳入调度和健康监控。 |
| 分区/排序差 | 如果未正确 partition/sort，可能需要扫描过多行，触发内置服务限制。 | 写入链路要强制按照 series ID/time 组织数据。 |
| Missing data | sync 未 build 到最新 dataset transaction 时，新数据无法 hydrate。 | sync checkpoint 和 source dataset transaction 要可观测。 |
| Soho format | FAQ 说明非 Soho format 时 no unprojected data 会 hydrate。 | 自研不必照搬格式名，但必须明确哪些 layout 支持未投影数据读取。 |

来源：<https://www.palantir.com/docs/foundry/time-series/time-series-syncs>、<https://www.palantir.com/docs/foundry/time-series/faqs>

---

## 6. 安全与 Marking

【事实】Time series sync advanced settings 可配置 security markings；继承的 markings 在用户通过 Ontology TSP 查看 sync 数据时仍然需要满足。来源：<https://www.palantir.com/docs/foundry/time-series/time-series-syncs>

【推断】时序访问权限至少包含三层：用户能否看 root/sensor object、能否看 TSP 属性、能否看 sync 数据源 inherited markings。Derived series 还要求用户能访问其逻辑引用的所有输入 TSP。

---

## 7. 自研实现草图

```text
TimeSeriesSync
  id
  source_dataset_or_stream
  value_type
  series_id_column
  timestamp_column
  value_column
  projection_status
  checkpoint_transaction
  markings

TimeSeriesIndex
  sync_id
  series_id
  time_range
  hydrated_status
  last_accessed_at
  source_transaction
```

【建议】不要把 cache/index 当成唯一真相源；可重建事实源仍应是 dataset/stream transaction，index 只负责低延迟读取和热数据缓存。
