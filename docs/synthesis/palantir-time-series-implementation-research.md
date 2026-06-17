# Palantir Time Series 实现机制与特性调研综合报告

**日期：** 2026-06-17
**关联 Issue：** #66
**父 Epic：** #66
**输入文档：** `docs/raw/59-time-series-source-map.md`、`docs/raw/60-time-series-ontology-model.md`、`docs/raw/61-time-series-sync-indexing.md`、`docs/raw/62-time-series-consumption-alerting.md`、`docs/raw/63-time-series-advanced-operations-permissions.md`

---

## 1. 总结与结论

1. 【事实】Palantir Time Series 的实现由两条链路组成：Ontology 语义链路负责把 TSP 挂到 root object 或 sensor object 上，sync/indexing 链路负责从 dataset/stream 按 `seriesId + timestamp + value` 提供点值。
2. 【事实】对象侧通常只保存 series ID 或 qualified series ID，真正时序点值由 time series sync、projection 和 Foundry time series database 在读取时解析；projection 用于按 series ID/time range 优化湖仓读取，database 像 cache 并在读取时 hydrate。
3. 【事实】功能特性覆盖建模、同步、索引、单位/插值、默认 TSP、sensor object、qualified series ID、derived series、Workshop transforms、FoundryTS、Map timeline 和 time series alerting automation。
4. 【推断】Palantir 的核心优势不是“有一张时序表”，而是同一条 TSP 语义能被 Ontology、Quiver、Workshop、Map、SDK、Automate、权限和 Catalog 共用。
5. 【建议】自研优先级应是 TSP 语义模型、sync/projection/index、time range 查询、权限合取和基础 transforms；复杂 Quiver UI、derived series widget、alerting 高级搜索可后置。

---

## 2. 实现主链路

```text
Raw time series data in Foundry dataset or stream
  -> normalize to seriesId + timestamp + value
  -> create time series sync
  -> build backing dataset and projection
  -> register sync as datasource for TSP
  -> object stores series ID or qualified series ID
  -> user/app queries TSP on object
  -> Foundry resolves sync + series ID + time range
  -> hydrate/read indexed data from time series database
  -> render/analyze/alert
```

| 层级 | Palantir 能力 | 关键事实 | 自研对应 |
|---|---|---|---|
| 语义层 | Time Series Property | object property 中保存 series ID，绑定 sync。 | `TimeSeriesPropertyDefinition`。 |
| 建模层 | Root TSP / Sensor object type | 全量适合 root TSP，稀疏/多传感器适合 sensor object。 | root object + sensor object link。 |
| 接入层 | Time series sync | dataset/stream backed，索引 time-value pairs。 | sync job + checkpoint。 |
| 物理优化 | Projection | materialized copy，优化 series ID/time range 读取。 | projection/index layout。 |
| 热索引 | Time series database | read-time hydration，cache-like eviction。 | hot index/cache。 |
| 消费层 | Quiver/Workshop/Map/FoundryTS/Automate | 同一 TSP 跨应用复用。 | API + widgets + SDK + alerting。 |
| 治理层 | Catalog / permissions / markings | Catalog 管理发现，sync markings 影响 TSP 查看。 | registry + policy engine。 |

---

## 3. 关键特性清单

| 特性 | Palantir 做法 | 价值 |
|---|---|---|
| TSP 作为 Ontology 属性类型 | 常规 property 是单值，TSP 存储 timestamped value history 的引用。 | 用户从业务对象进入时序分析。 |
| Series ID 显式引用 | TSP 选择 string property 保存 series ID。 | 业务对象和时序点值解耦。 |
| Multiple sync + qualified ID | 多 sync 支撑一个 TSP 时使用 `seriesId + syncRid` JSON 字符串。 | 避免全局 series ID 冲突，支持多源。 |
| Sensor object type | 用 linked sensor objects 表达稀疏、多传感器、多单位场景。 | root object 不被大量稀疏时序属性污染。 |
| Units / interpolation | 可固定或来自 object string property，应用如 Quiver 会尊重。 | 统一展示和分析语义。 |
| Projection | sync 创建 projection，按 series ID/time range 优化读取。 | 解决湖仓数据直接扫表的性能问题。 |
| Hydration cache | indexed data 从 time series database 读取，read time hydrate，低热度 series 可 evict。 | 平衡存储成本和查询速度。 |
| Derived series | 保存时序计算逻辑为 resource，可作为 TSP 暴露，按需计算。 | 避免复制派生点值和重复计算定义。 |
| Workshop transforms | 支持 aggregate、rolling、formula 等链式 transform。 | 应用构建者可直接做时序分析。 |
| FoundryTS | Python 查询库支持过滤时序或从 Ontology property 查询。 | 代码侧复用同一语义模型。 |
| Time series alerting | raw/derived series 输入，transform 后 search，输出事件/告警。 | 从分析延伸到自动化监控。 |
| Data Health 边界 | Alerting 监控健康数据异常，不替代 pipeline volume/quality 检查。 | 避免把业务异常监控和数据质量监控混为一谈。 |
| Advanced sync settings | input update 自动 build、optimized sync、view backing dataset indexing、sync replacement、markings、Spark/Flink profiles。 | sync 是可运维资源，不只是 schema mapping。 |
| Query cost visibility | 查询成本由 query 数量、series size、query complexity 驱动；usage-based 实例每 query 至少 4 compute-seconds。 | API 和 dashboard 必须有 time range、granularity 和 attribution 控制。 |
| Function-backed series | Foundry function 可返回 numeric time series 供 Quiver 预测类 workflow 使用。 | TSP 不只来自 dataset/stream，也可能来自版本化函数。 |

---

## 4. 自研设计建议

### 4.1 数据模型

```text
ObjectType
  properties[]
  time_series_properties[]

TimeSeriesPropertyDefinition
  object_type
  property_name
  series_id_property
  sync_refs[]
  value_type
  unit_strategy
  interpolation_strategy
  default_flag

TimeSeriesSync
  source_dataset_or_stream
  series_id_column
  timestamp_column
  value_column
  projection_status
  checkpoint_transaction
  markings

TimeSeriesPointIndex
  sync_id
  series_id
  min_time
  max_time
  source_transaction
  hot_cache_status
```

### 4.1.1 时序数据接入方式

【建议】接入时序数据不要把点值直接做成对象宽表，也不要让应用直接扫原始点值 dataset。推荐把接入链路拆成“原始数据标准化 -> dataset/stream 事实源 -> time series sync/index -> Ontology TSP -> 应用查询”。

```text
原始数据源
  -> 标准化为 series_id + timestamp + value
  -> 写入 dataset 或 stream
  -> 创建 time series sync / index
  -> 在 ObjectType 上配置 Time Series Property
  -> 应用按 object + TSP + time range 查询
```

最小点值 schema：

| 字段 | 含义 | 设计要求 |
|---|---|---|
| `series_id` | 一条时序序列的稳定 ID | 不要求全平台全局唯一；多 sync 场景用 qualified series ID。 |
| `timestamp` | 采样时间 | 写入和 projection/index 应按 timestamp 排序或聚簇。 |
| `value` | 点值 | 支持数值或 categorical；categorical variant 要设上限。 |

对象表只保存时序引用，不保存所有点值：

```text
machine_id | name      | temperature_series_id
M123       | Machine 1 | machine_123_temperature
```

点值事实源单独保存：

```text
series_id                | timestamp           | value
machine_123_temperature  | 2026-06-18 10:00:00 | 82.1
machine_123_temperature  | 2026-06-18 10:01:00 | 82.4
```

如果设备/传感器类型很多，优先使用 sensor object 模型：

```text
sensor_id | root_object_id | sensor_name | series_id | unit
S1        | M123           | temperature | ...       | Celsius
S2        | M123           | pressure    | ...       | kPa
```

| 接入场景 | 推荐路径 | 关键控制点 |
|---|---|---|
| 批量历史数据 | dataset-backed sync | 按 `series_id` 分区/聚簇，按 `timestamp` 排序，记录 source transaction。 |
| 实时高频数据 | stream-backed sync | checkpoint、allowed lateness、乱序和迟到数据策略。 |
| 多来源同一属性 | multiple sync + qualified series ID | 使用 `(syncRid, seriesId)` 避免 ID 冲突。 |
| 稀疏多传感器 | sensor object type | root/sensor link、sensor name 唯一性、单位和类型元数据。 |
| 地理位置随时间变化 | geospatial TSP 或 geotemporal series | 图表/详情可用 TSP；轨迹回放和空间范围查询应评估 geotemporal index。 |

### 4.2 查询路径

1. 【建议】应用只按 object + TSP + time range 查询，不直接暴露 raw dataset 扫描。
2. 【建议】服务端解析 TSP definition，读取 object 的 series ID 或 qualified series ID，再路由到 sync/index。
3. 【建议】默认要求 time range，避免首次查询 hydrate 全量长序列。
4. 【建议】latest value、sparkline、downsampled series、full resolution series 分开 API，避免列表页误拉全量。
5. 【建议】cache/index 可被 evict 和重建，事实源仍以 dataset/stream transaction 为准。

### 4.3 权限路径

```text
can_view_object
  AND can_view_property(TSP)
  AND can_view_sync_markings_or_markings_severed_for_tsp_path
  AND can_view_all_input_TSPs_if_derived
```

【事实】Palantir 文档说明，TSP 访问需要用户能访问 object/property，以及 TSP backing time series sync datasources；sync 会继承 input dataset markings。因为 time series syncs 不能 backed by restricted views，不能直接在 sync 层提供 granular permissions。来源：<https://www.palantir.com/docs/foundry/time-series/time-series-permissions>

【事实】如果在 Ontology Manager 中停止继承 sync markings，则通过 object TSP 加载 time series 时不再要求这些 sync markings；但直接访问 sync 仍然需要满足 markings。来源：<https://www.palantir.com/docs/foundry/time-series/time-series-permissions>

【建议】权限不要只挂在对象上。sync inherited markings、TSP 属性权限、derived series 输入依赖和 direct-sync-access 路径都要进入判定，否则容易出现对象可见但时序点值越权的问题。

---

## 4.4 运维与成本控制补充

| 控制面 | Palantir 公开事实 | 自研建议 |
|---|---|---|
| Sync build freshness | time series sync 默认建议在 input dataset update 时 build。 | sync checkpoint 要绑定 source transaction，并进入监控。 |
| Optimized sync builds | 仅通过 TSP 或 qualified series IDs 访问时推荐开启；可加速 build、节省磁盘、不要求 series ID 全局唯一。 | 区分 object-bound sync 与 direct-access sync。 |
| Large view indexing | 对约 10 TB+ 且 backing datasets 少于 10 的 view/union，可 index backing datasets 并生成 projections。 | 超大时序事实源应拆分 dataset，再用 view 聚合。 |
| Query cost | query 数量、series size、query complexity 驱动成本；每 query 有最低 compute-seconds。 | dashboard 和 SDK 默认要求 time range，并提供 rollup series。 |
| Functions | Function-backed time series 可由 tagged Foundry function 返回 numeric series；Functions 中用 Python OSDK 而不是 FoundryTS 访问 TSP。 | 实时预测函数要有版本、点数、超时和资源预算。 |
| Alerting runtime | batch alerting 是 Spark job，streaming alerting 是 Flink job。 | alerting rule 必须保存 runtime mode、lookback/allowed lateness、failure policy。 |

---

## 5. 与现有平台模块的关系

| 既有主题 | 关系 |
|---|---|
| Dataset | Time series sync 的事实源仍来自 dataset/stream transaction，projection 是性能优化，不替代 dataset 真相源。 |
| Pipeline | Pipeline Builder 可生成 time series sync target；时序数据需要在 pipeline 中规范化为 seriesId/timestamp/value。 |
| Ontology | TSP 是 Ontology 属性类型，sensor object type 依赖 link type。 |
| Data Quality | Time series alerting 不负责 pipeline volume/quality；质量问题仍走 Data Health、Health Checks、Data Expectations。 |
| Security and Marking | Sync markings 会影响通过 TSP 查看数据；derived series 权限还要继承输入 TSP。 |
| Self-build Roadmap | Time Series 应作为对象语义层和数据工程层之间的新 capability，而不是单独图表功能。 |
| Geospatial / Geotemporal | Geospatial time series 可跟踪实体位置随时间变化；轨迹回放和时空范围查询应评估 geotemporal series，而不只是两个数值 TSP。 |

---

## 6. 风险与待验证

| 风险 | 状态 | 处理建议 |
|---|---|---|
| 内部 TSDB 未公开 | 【待验证】只知道 read-time hydration/cache 形态。 | 自研按可替换 index/cache 接口设计。 |
| Projection 具体布局未公开 | 【待验证】只知道按 series ID/time range 优化。 | 先实现 series hash partition + timestamp sort，再按查询画像调优。 |
| Cache eviction 参数未公开 | 【待验证】只知道 least recently hydrated series 优先 evict。 | 自研定义明确 TTL、容量、热度和优先级。 |
| Alerting search 有限制 | 【事实】basic search 限制、多条件和多序列公式存在保存限制。 | 第一版 alerting 不承诺复杂 CEP。 |
| Categorical series variant 上限 | 【事实】每 series 最多 10,000 variants。 | 自研也要设上限或单独建模枚举维度。 |
| 权限组合复杂 | 【推断】object、TSP、sync markings、derived input 都影响访问。 | 建立统一 policy evaluation trace。 |
| Sync markings severing 风险 | 【事实】停止继承 markings 后，通过 TSP 访问只依赖 object/property 权限；直接 sync 访问仍检查 markings。 | severing 必须有审批、审计和安全评估。 |
| Streaming alerting 乱序 | 【事实】allowed lateness window 外的 out-of-order points 会被 dropped，默认 5 秒。 | 对迟到数据敏感的业务要显式设置窗口和补偿策略。 |
| Query 成本失控 | 【事实】query 数量、points scanned、logic complexity 会推高 compute。 | 强制 time range、预聚合、dashboard attribution 和预算。 |

---

## 7. 最小可行自研路线

| 阶段 | 能力 | 验收 |
|---|---|---|
| P0 | TSP 元数据、series ID 引用、sync 注册、点值查询 API。 | 对象详情能展示 latest value 和指定 time range 曲线。 |
| P1 | Projection/index layout、incremental sync checkpoint、time range filter、downsampling。 | 大 series 首次/二次查询性能可观测，列表页不拉全量。 |
| P2 | Sensor object type、qualified series ID、units/interpolation、sync ownership 和 permission trace。 | 多源、多单位、多传感器场景可建模，权限可解释。 |
| P3 | Basic transforms、derived series definition、FoundryTS/OSDK 类 SDK、query cost attribution。 | aggregate/rolling/formula 可复用到 UI 和 SDK，成本可归因。 |
| P4 | Alerting automation、event object output、Data Health 边界集成、batch/stream runtime config。 | 异常事件进入告警，不混入 pipeline quality 检查。 |

---

## 8. 来源

- <https://www.palantir.com/docs/foundry/time-series/time-series-overview>
- <https://www.palantir.com/docs/foundry/time-series/time-series-concepts-glossary>
- <https://www.palantir.com/docs/foundry/time-series/time-series-properties>
- <https://www.palantir.com/docs/foundry/time-series/create-sensor-ot>
- <https://www.palantir.com/docs/foundry/time-series/time-series-syncs>
- <https://www.palantir.com/docs/foundry/time-series/faqs>
- <https://www.palantir.com/docs/foundry/time-series/derived-series-overview>
- <https://www.palantir.com/docs/foundry/time-series/derived-series-permissions>
- <https://www.palantir.com/docs/foundry/workshop/time-series-properties>
- <https://www.palantir.com/docs/foundry/time-series/foundryts>
- <https://www.palantir.com/docs/foundry/time-series/alerting-overview>
- <https://www.palantir.com/docs/foundry/time-series/alerting-setup>
- <https://www.palantir.com/docs/foundry/time-series/alerting-additional-configurations>
- <https://www.palantir.com/docs/foundry/time-series/time-series-permissions>
- <https://www.palantir.com/docs/foundry/time-series/advanced-setup>
- <https://www.palantir.com/docs/foundry/time-series/compute-usage>
- <https://www.palantir.com/docs/foundry/time-series/function-backed-time-series-getting-started>
- <https://www.palantir.com/docs/foundry/time-series/time-series-in-functions>
- <https://www.palantir.com/docs/foundry/map/time-series>
