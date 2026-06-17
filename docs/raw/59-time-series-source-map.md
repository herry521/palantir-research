# Palantir Time Series 资料源与术语基线

**日期：** 2026-06-17
**所属 Epic：** #66

---

## 1. 摘要与洞察

1. 【事实】Palantir 官方文档把 Time Series 放在 Data connectivity & integration 下，但核心消费依赖 Ontology：Time Series Object Type 和 Time Series Property 负责把时序数据暴露给 Foundry 应用。
2. 【事实】Time Series Sync 是时序点值的索引资源，可由 dataset 或 stream 支撑；它按 series ID 提供 TSP 的值。
3. 【事实】Time Series Catalog 统一管理和发现 time series syncs、time series object types、derived series。
4. 【推断】公开文档能确认“对象语义引用 + sync 索引 + time series database 读取缓存”的架构形态，但没有公开底层数据库实现、cache 配额和完整查询规划细节。
5. 【建议】后续自研设计应把官方可证事实与自研推断拆开管理，避免把 Foundry 内部私有实现当作可复刻接口。

---

## 2. 资料源索引

| 编号 | URL | 覆盖范围 | 可信度 | 备注 |
|---|---|---|---|---|
| S01 | <https://www.palantir.com/docs/foundry/time-series/time-series-overview> | 顶层流程、object type、sync、root/sensor 模型 | 高 | 官方概览 |
| S02 | <https://www.palantir.com/docs/foundry/time-series/time-series-concepts-glossary> | TSP、sync、series ID、qualified series ID | 高 | 术语基线 |
| S03 | <https://www.palantir.com/docs/foundry/time-series/time-series-properties> | TSP 配置、units、interpolation、default TSP | 高 | Ontology Manager 配置 |
| S04 | <https://www.palantir.com/docs/foundry/time-series/create-sensor-ot> | Sensor object type schema、link、categorical、units | 高 | 稀疏/多传感器建模 |
| S05 | <https://www.palantir.com/docs/foundry/time-series/time-series-syncs> | sync 数据源、projection、advanced settings、markings | 高 | 物理链路核心 |
| S06 | <https://www.palantir.com/docs/foundry/time-series/faqs> | projection、hydration、cache、性能与缺失数据排查 | 高 | 运维和性能关键证据 |
| S07 | <https://www.palantir.com/docs/foundry/time-series/derived-series-overview> | derived series 类型、Quiver logic、Ontology 保存 | 高 | 派生序列能力 |
| S08 | <https://www.palantir.com/docs/foundry/time-series/derived-series-permissions> | derived series 权限和保存条件 | 高 | 权限边界 |
| S09 | <https://www.palantir.com/docs/foundry/workshop/time-series-properties> | Workshop widgets、time series transforms、aggregate | 高 | 应用消费 |
| S10 | <https://www.palantir.com/docs/foundry/time-series/foundryts> | FoundryTS Python 查询库 | 高 | 代码消费 |
| S11 | <https://www.palantir.com/docs/foundry/time-series/alerting-overview> | Alerting 定位边界 | 高 | 监控定位 |
| S12 | <https://www.palantir.com/docs/foundry/time-series/alerting-setup> | automation setup、scope、search 限制 | 高 | 自动化规则 |
| S13 | <https://www.palantir.com/docs/foundry/map/time-series> | Map timeline、series panel、time-based styling | 高 | 地理空间消费 |
| S14 | <https://www.palantir.com/docs/foundry/time-series/time-series-permissions> | TSP 权限、sync markings、granular permissions 限制 | 高 | 第二轮权限证据 |
| S15 | <https://www.palantir.com/docs/foundry/time-series/advanced-setup> | Code Repository advanced setup、增量、排序/格式优化 | 高 | 第二轮运维证据 |
| S16 | <https://www.palantir.com/docs/foundry/time-series/alerting-additional-configurations> | batch/streaming alerting job 配置 | 高 | 第二轮告警运行时证据 |
| S17 | <https://www.palantir.com/docs/foundry/time-series/compute-usage> | query compute usage、cost drivers、time range/granularity | 高 | 第二轮成本证据 |
| S18 | <https://www.palantir.com/docs/foundry/time-series/function-backed-time-series-getting-started> | function-backed time series、forecasting workflow | 高 | 第二轮函数式序列证据 |
| S19 | <https://www.palantir.com/docs/foundry/time-series/time-series-in-functions> | Functions 中访问 TSP，Python OSDK 与 FoundryTS 边界 | 高 | 第二轮代码入口证据 |
| S20 | <https://www.palantir.com/docs/foundry/time-series/geospatial-time-series-use-case> | geospatial time series use case 与 geotemporal 取舍提示 | 高 | 第二轮 geospatial 边界证据 |

---

## 3. 术语边界

| 术语 | 定义 | 关键边界 |
|---|---|---|
| Time Series Property (TSP) | Ontology object property 的一种，属性值不是单点标量，而是指向一条时序序列的 series ID。 | TSP 的对象侧值是引用；点值来自 sync/database。 |
| Time Series Object Type | 能暴露 TSP 的 object type，定义时序数据的业务语义和元数据。 | 不等同于底层时序点值存储表。 |
| Time Series Sync | backed by dataset 或 stream 的资源，索引 `seriesId + timestamp + value` 点值并向 TSP 提供数据。 | 所有同一 series ID 的值应在同一个 sync 内。 |
| Series ID | TSP 与 sync 对齐的主引用键。 | 多 sync 支撑同一 TSP 时需要 qualified series ID。 |
| Qualified Series ID | JSON 字符串，包含 `seriesId` 和 `syncRid`。 | 用于消除多个 sync 中 series ID 的歧义。 |
| Sensor Object Type | 与 root object type 通过 link 关联的传感器对象；适合只有部分 root objects 有某类时序数据的场景。 | 防止在 root object 上创建大量稀疏 TSP。 |
| Derived Series | 保存为 Palantir resource 的时序计算逻辑，可作为 TSP 暴露并按需计算。 | 不需要复制存储派生点值，权限依赖输入 TSP。 |
| Time Series Catalog | 发现和管理 sync、time series object type、derived series 的入口。 | 是治理/发现入口，不是底层存储引擎。 |

---

## 4. 证据缺口

| 缺口 | 当前状态 | 自研影响 |
|---|---|---|
| 底层 time series database 类型 | 【待验证】公开文档只说明 indexed database/cache，不说明引擎。 | 自研不能直接假设使用专用 TSDB、ClickHouse、Druid 或湖仓索引。 |
| Cache 容量和淘汰策略参数 | 【待验证】公开文档说明 disk constrained 时 least recently hydrated series 会被 evict，但不公开配额。 | 需要自定义热度、TTL、配额和降级策略。 |
| Projection 内部文件布局 | 【待验证】公开文档说明 projection 按 series ID 和 timestamp 优化过滤/排序，但不公开具体排序键和文件格式细节。 | 自研可复刻逻辑目标，不应复刻不存在的公开实现。 |
| 多租户权限判定顺序 | 【待验证】公开文档说明 inherited markings 会影响通过 TSP 查看 sync 数据，细粒度属性权限需另查。 | 自研需显式设计 object 权限、TSP 权限、sync markings 的合取关系。 |

---

## 5. 后续引用规则

- 需要解释建模时引用 `docs/raw/60-time-series-ontology-model.md`。
- 需要解释性能和存储/索引时引用 `docs/raw/61-time-series-sync-indexing.md`。
- 需要解释应用消费、派生序列和告警时引用 `docs/raw/62-time-series-consumption-alerting.md`。
- 需要解释高级配置、权限、成本、functions、alerting runtime 和 geospatial/geotemporal 边界时引用 `docs/raw/63-time-series-advanced-operations-permissions.md`。
- 需要做自研方案决策时引用 `docs/synthesis/palantir-time-series-implementation-research.md`。
