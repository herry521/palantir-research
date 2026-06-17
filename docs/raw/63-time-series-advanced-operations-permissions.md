# Palantir Time Series 高级配置、权限与运行成本补充

**日期：** 2026-06-18
**所属 Epic：** #66

---

## 1. 摘要与洞察

1. 【事实】Time series sync 的高级配置不只是性能参数，还包括 input dataset update 自动触发、optimized sync builds、view backing dataset indexing、旧 sync 替换、markings 和 Spark/Flink profiles。
2. 【事实】TSP 权限至少要求用户能访问对象/属性，以及 TSP backing time series sync 的数据源；sync 会继承 input dataset markings。
3. 【事实】Time series sync 不能由 restricted view 支撑，因此无法直接在 sync 层做 granular permissions；Palantir 推荐用严格 input dataset markings，并可在 Ontology Manager 中停止继承 sync markings，让通过 TSP 访问时只依赖对象/属性权限。
4. 【事实】Time series alerting 的 batch jobs 运行在 Spark 上，streaming jobs 运行在 Flink 上；job-level 配置会影响写入同一 alert object type 的多个 automations。
5. 【建议】自建平台应把 TSP 查询成本、权限判定、sync build 策略和 alerting job 运行时纳入同一个 operational control plane，否则只实现 TSP API 会很快遇到成本和越权风险。

---

## 2. Advanced Sync Settings

| 配置 | Palantir 公开说明 | 自研启示 |
|---|---|---|
| Schedule sync runs on input dataset update | 默认会在 input time series dataset 更新时调度 sync build，官方推荐保留以保证数据更新。 | sync build 应和 source transaction 绑定，避免新数据无法查询。 |
| Enable optimized sync builds | 如果只通过 TSP 或 qualified series IDs 访问该 sync，官方强烈建议开启；可加速 build、减少磁盘空间、不要求 series IDs 全局唯一。 | 自研可区分 object-bound sync 和 direct-access sync，前者可放宽全局 ID 唯一要求。 |
| Index view dataset inputs | 推荐用于由少量 backing datasets 组成、数据量约 10 TB+ 的 view/union sync；会索引 view 的 backing datasets 而不是 view 本身，并透明生成 projections。 | 对超大 canonical dataset，应拆成小 dataset + view + backing projection，而不是单大表硬扛。 |
| Overwrite series from other syncs | dataset-backed sync 可指定旧 sync，以替换 intersecting series IDs；旧 sync 会 fail 并应被 trash。stream inputs 无该设置。 | sync 替换是迁移操作，应有 version、failover 和 trash/rollback 流程。 |
| Security markings | sync 继承的 markings 在通过 Ontology TSP 查看数据时仍需满足，除非在 Ontology Manager 中停止继承。 | 权限判定要显式记录 markings 继承状态。 |
| Spark/Flink profiles | 可配置 sync build compute profiles，但官方说很少需要；Pipeline Builder 创建的 sync 会被下次 pipeline run 覆盖其可配置字段。 | 配置来源要分层：pipeline-owned sync 不应允许 UI 配置长期漂移。 |

来源：<https://www.palantir.com/docs/foundry/time-series/time-series-syncs>

---

## 3. 手工 Advanced Setup 与数据布局

【事实】Palantir 推荐通过 Pipeline Builder 设置 time series pipeline；advanced setup 面向需要低层 transform 控制或 Pipeline Builder 尚未支持的高级能力，并建议先联系 Palantir representative。来源：<https://www.palantir.com/docs/foundry/time-series/advanced-setup>

```text
Code Repository transform
  -> explicitly generate time series dataset or stream
  -> required columns: Series ID, Value, Timestamp
  -> set up time series sync
  -> create time series object type backing dataset
  -> configure TSP on object type
```

【事实】Advanced setup 的 dataset time series 通常配置为 incremental builds，以降低 compute cost 并缩短从 raw data ingest 到可读最新数据之间的 latency。来源：<https://www.palantir.com/docs/foundry/time-series/advanced-setup>

【事实】官方代码示例要求在写出时按 `seriesId` repartition，并在 partition 内按 `seriesId`、`timestamp` 排序，然后写成 `soho` 格式。来源：<https://www.palantir.com/docs/foundry/time-series/advanced-setup>

【建议】自研写入 contract 至少应包含：

1. `series_id` 作为分布键或 primary clustering key。
2. `timestamp` 作为二级排序键。
3. source transaction/checkpoint 与 projection/index build 状态。
4. 对 late data、duplicate timestamp、value type drift 的明确策略。

---

## 4. 权限模型补充

```text
view_tsp_value(user, object, tsp)
  = can_view_object_row(user, object)
    AND can_view_property(user, tsp)
    AND can_access_all_tsp_backing_sync_datasources(user, tsp)
```

【事实】Palantir 文档说明，要查看某对象上的 TSP，用户必须能访问该 object 和 TSP 的 backing data sources。TSP 引用 time series syncs，这些 sync 必须列为该 TSP 的 backing data sources。来源：<https://www.palantir.com/docs/foundry/time-series/time-series-permissions>

【事实】Time series sync 会继承 input dataset 的所有 markings；查看 sync 需要满足这些 markings。来源：<https://www.palantir.com/docs/foundry/time-series/time-series-permissions>

【事实】Time series syncs 不能 backed by restricted views，因此不能拥有 granular permissions。Palantir 推荐对 sync input dataset 设置严格 markings，并可在 Ontology Manager 中停止继承这些 markings；一旦所有 backing sync markings 被 severed，通过 TSP 访问时权限就与标准 property 一样，只取决于 object/property permissions。来源：<https://www.palantir.com/docs/foundry/time-series/time-series-permissions>

【事实】停止继承 markings 只绕过“通过 object TSP 加载 time series”时的 sync marking 要求；直接访问 time series sync 仍然需要满足 markings。来源：<https://www.palantir.com/docs/foundry/time-series/time-series-permissions>

【建议】自建平台要区分两类访问路径：

| 访问路径 | 权限策略 |
|---|---|
| 通过 object/TSP 查看 | object row + property permission + 可配置是否继承 sync policy。 |
| 直接访问 sync/resource | 永远检查 sync/source markings 或 resource ACL。 |
| derived series | 检查 derived resource 权限，并合取所有 input TSP 可见性。 |

---

## 5. Alerting Job 运行时

| 类型 | 执行引擎 | 关键配置 | 自研启示 |
|---|---|---|---|
| Batch alerting | Spark jobs | Spark profiles、fail job on any failure、default lookback window、first job run read limit、job timeout。 | 适合离线/增量 scan；lookback window 控制正确性与延迟/成本。 |
| Streaming alerting | Flink jobs | Flink profiles、fail job on any failure、Ontology polling interval、allowed lateness、excluded time series syncs。 | 适合低延迟事件；必须处理乱序、ontology 更新和 job restart downtime。 |

【事实】Job-level configurations 会影响写入同一 alert object type 的所有 time series alerting automations；多个 automations 可以共享同一个 evaluation job。来源：<https://www.palantir.com/docs/foundry/time-series/alerting-additional-configurations>

【事实】Batch alerting jobs run as Spark jobs；Streaming alerting jobs run as Flink jobs。来源：<https://www.palantir.com/docs/foundry/time-series/alerting-additional-configurations>

【事实】Streaming alerting 会定期 polling ontology 以更新 automation logic 引用的 entities；polling interval 在成本和 ontology update responsiveness 之间取舍。来源：<https://www.palantir.com/docs/foundry/time-series/alerting-additional-configurations>

【事实】Streaming alerting 按 timestamp order 处理数据，并丢弃超出 allowed lateness window 的 out-of-order points；默认 allowed lateness 是 5 秒。来源：<https://www.palantir.com/docs/foundry/time-series/alerting-additional-configurations>

【建议】自研 alerting 不应只保存规则表达式，还应保存：

- job group / alert object type；
- batch 或 streaming execution mode；
- lookback / allowed lateness；
- ontology object scope refresh policy；
- excluded input syncs；
- partial automation failure policy。

---

## 6. Functions、Function-backed Time Series 与查询成本

【事实】Function-backed time series 用于 Quiver 中的 real-time forecasting workflows。前置资源包括一个返回 numeric time series 的 Foundry function，以及一个可在 Quiver 引用的 tagged function version。Python function 返回 serialized pandas DataFrame，至少包含 `timestamp` 和 numeric `value` 列。来源：<https://www.palantir.com/docs/foundry/time-series/function-backed-time-series-getting-started>

【事实】在 Functions 中访问已有 Ontology TSP 时，FoundryTS library 不兼容 functions；Python OSDK 提供替代方式，可以把 TSP datapoints 读成 pandas 或 Polars DataFrame，包含 `timestamp` 和 `value` 两列。来源：<https://www.palantir.com/docs/foundry/time-series/time-series-in-functions>

【事实】Time series query compute usage 主要由 query 数量、被查询 series 的 size、query complexity 三个因素驱动；usage-based 实例上每个 query 最少使用 4 compute-seconds。来源：<https://www.palantir.com/docs/foundry/time-series/compute-usage>

【事实】限制 time range 可以减少 points scanned；选择正确 granularity、为不同工作流维护不同粒度 series，可能比总是查询最细粒度 series 更便宜。来源：<https://www.palantir.com/docs/foundry/time-series/compute-usage>

【建议】自研平台应把 time series query 设计成 cost-visible API：

| 控制点 | 建议 |
|---|---|
| Query budget | 对 dashboard、scheduled build、function 调用分别记账。 |
| Time range | 默认强制或提示 time range；全量查询需要显式确认。 |
| Granularity | 支持预聚合 series 或 materialized rollup。 |
| Function-backed series | 限制返回点数、运行时间和版本引用，避免实时预测函数变成无限制查询入口。 |

---

## 7. Geospatial / Geotemporal 边界

【事实】Geospatial time series properties on objects 可用于跟踪实体位置随时间变化；官方示例使用 `Ship` object type，并有对象信息 backing dataset 与 location updates backing dataset，位置更新包含 latitude、longitude 和 timestamp。来源：<https://www.palantir.com/docs/foundry/time-series/geospatial-time-series-use-case>

【事实】Palantir 在该文档中明确提醒：应先查看 geospatial documentation，判断 geotemporal series 或 time series setup 哪个更适合当前 use case。来源：<https://www.palantir.com/docs/foundry/time-series/geospatial-time-series-use-case>

【推断】普通 TSP 适合把 latitude、longitude 等位置值作为对象相关的时间序列展示；geotemporal series 更可能面向地图/轨迹/时空索引的一等资源。公开资料不足以把二者内部实现等同。

【建议】自研平台中不要把“位置随时间变化”简单等同于两个数值 TSP：

| 场景 | 建议建模 |
|---|---|
| 设备某个数值随时间变化 | TSP。 |
| 对象位置随时间变化，主要用于详情页/图表 | 可用 latitude/longitude TSP 或 geospatial TSP。 |
| 轨迹回放、空间范围查询、地图实时渲染 | 独立 GeotemporalSeries 或 trajectory index。 |

---

## 8. 第二轮结论

1. 【事实】Time Series 的 operational complexity 主要在 sync/index freshness、permissions、alerting runtime 和 query cost，而不是 TSP schema 本身。
2. 【事实】Palantir 使用 Spark/Flink 分别承载 batch/streaming alerting，这说明 alerting 是独立运行时，不是前端图表搜索的简单定时执行。
3. 【推断】TSP 权限的难点在于 sync 不能 restricted-view 化；Palantir 用 markings inheritance/severing 和 object/property permissions 组合解决。
4. 【建议】自研路线应在 P1/P2 就引入 query cost attribution、sync ownership、policy trace 和 alerting job config，否则后期很难补齐治理。
