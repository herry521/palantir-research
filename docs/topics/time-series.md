# Time Series

## 摘要与洞察

1. 【事实】Palantir Time Series 通过 Ontology TSP 暴露业务语义，通过 time series sync/projection/database 提供点值读取。
2. 【事实】Root object TSP 和 sensor object type 是两种核心建模方式，分别适配普遍存在的时序属性和稀疏/多传感器场景。
3. 【事实】Time series sync 由 dataset 或 stream 支撑，核心数据模型是 `seriesId + timestamp + value`。
4. 【推断】自研平台应优先建设 TSP 语义模型和 sync/index 能力，再做高级分析 UI。
5. 【建议】Time series alerting 与 Data Health 要分层：前者做健康数据上的业务异常事件，后者做 pipeline/data quality。

## Canonical Documents

| 文档 | 用途 |
|---|---|
| [docs/synthesis/palantir-time-series-implementation-research.md](../synthesis/palantir-time-series-implementation-research.md) | Time Series 实现机制、特性清单、自研路线和风险总览。 |

## Supporting Evidence

| 证据 | 精简说明 |
|---|---|
| [docs/raw/59-time-series-source-map.md](../raw/59-time-series-source-map.md) | 官方资料源、术语边界和证据缺口。 |
| [docs/raw/60-time-series-ontology-model.md](../raw/60-time-series-ontology-model.md) | TSP、sensor object type、qualified series ID 建模机制。 |
| [docs/raw/61-time-series-sync-indexing.md](../raw/61-time-series-sync-indexing.md) | Time series sync、projection、hydration、cache 和性能边界。 |
| [docs/raw/62-time-series-consumption-alerting.md](../raw/62-time-series-consumption-alerting.md) | Quiver、Workshop、Map、FoundryTS、Derived series、Alerting 能力。 |
| [docs/raw/63-time-series-advanced-operations-permissions.md](../raw/63-time-series-advanced-operations-permissions.md) | Advanced sync settings、权限、alerting runtime、functions、compute usage 和 geospatial 边界。 |

## Related Issues

#66

## Open Questions

- Foundry 内部 time series database 的具体引擎、cache 配额和淘汰参数未公开。
- Projection 的具体文件布局、排序键、增量合并策略未公开。
- Sync markings severing 的组织审批、审计记录和误配防护仍需产品内验证。
- Alerting output event object 的生命周期、去重和恢复语义仍需进一步验证。
- Geotemporal series 与普通 geospatial TSP 的内部实现和查询边界仍需进一步验证。
