# Palantir Time Series 实现与特性调研计划

**日期：** 2026-06-17
**Epic：** [#66](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/66)
**目标：** 研究 Palantir Foundry Time Series 的数据建模、同步索引、应用消费、告警自动化和自建平台复刻路径。

---

## 1. 摘要与研究假设

1. 【事实】Foundry Time Series 不是单纯的宽表或传统 `dt` 分区事实表能力，而是由 Ontology 中的 Time Series Property、Time Series Sync、Foundry time series database/projection 和应用层组件共同构成。
2. 【事实】Time series sync 可以由 dataset 或 stream 支撑，按 `seriesId + timestamp + value` 建模，并为 Time Series Property 提供值查询。
3. 【推断】Palantir 的关键设计是把“时序值存储/索引”和“业务对象语义”拆开：对象只保存 series ID 引用，时序点值由 sync/projection/database 在读取时解析。
4. 【事实】Derived series、Workshop transforms、FoundryTS 和 time series alerting automation 说明 Time Series 已进入分析、应用、代码和自动化多个入口。
5. 【建议】自研平台应优先复刻 TSP 引用模型、sync 索引模型、projection/hydration 性能策略和权限继承边界，而不是先实现复杂 UI。

---

## 2. Issue Map

| Issue | 角色 | 调研域 | 输出 |
|---|---|---|---|
| [#66](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/66) | Epic | 总规划与跟踪 | 本计划、最终状态评论 |
| #66 | Source map | 官方资料、术语和证据缺口 | `docs/raw/59-time-series-source-map.md` |
| #66 | Ontology model | TSP、sensor object type、qualified series ID | `docs/raw/60-time-series-ontology-model.md` |
| #66 | Sync/indexing | dataset/stream sync、projection、hydration、性能边界 | `docs/raw/61-time-series-sync-indexing.md` |
| #66 | Consumption/alerting | Quiver、Workshop、Map、FoundryTS、Derived series、Alerting | `docs/raw/62-time-series-consumption-alerting.md` |
| #66 | Synthesis | 综合实现模型、自建建议和风险清单 | `docs/synthesis/palantir-time-series-implementation-research.md` |

---

## 3. 共享资料源基线

| 编号 | 资料源 | 初始用途 |
|---|---|---|
| S01 | <https://www.palantir.com/docs/foundry/time-series/time-series-overview> | Time Series 顶层流程、Ontology 存储方式 |
| S02 | <https://www.palantir.com/docs/foundry/time-series/time-series-concepts-glossary> | TSP、sync、series ID、qualified series ID 术语 |
| S03 | <https://www.palantir.com/docs/foundry/time-series/time-series-properties> | TSP 配置、units、interpolation、default TSP |
| S04 | <https://www.palantir.com/docs/foundry/time-series/create-sensor-ot> | Sensor object type schema 和配置约束 |
| S05 | <https://www.palantir.com/docs/foundry/time-series/time-series-syncs> | Time series sync、dataset/stream、projection、markings |
| S06 | <https://www.palantir.com/docs/foundry/time-series/faqs> | Projection、time series database cache、hydration、性能问题 |
| S07 | <https://www.palantir.com/docs/foundry/time-series/derived-series-overview> | Derived series 资源、模板化和按需计算 |
| S08 | <https://www.palantir.com/docs/foundry/time-series/derived-series-permissions> | Derived series 权限、Ontology saving |
| S09 | <https://www.palantir.com/docs/foundry/workshop/time-series-properties> | Workshop 中 transforms、aggregate 等消费能力 |
| S10 | <https://www.palantir.com/docs/foundry/time-series/foundryts> | FoundryTS 代码查询入口 |
| S11 | <https://www.palantir.com/docs/foundry/time-series/alerting-overview> | Alerting 定位边界 |
| S12 | <https://www.palantir.com/docs/foundry/time-series/alerting-setup> | Alerting logic、scope、transforms、search 限制 |
| S13 | <https://www.palantir.com/docs/foundry/map/time-series> | Map 中时间选择、timeline、时序样式 |

---

## 4. 调研协议

1. 优先引用 Palantir 官方文档；二级材料只能作为背景。
2. 每份输出开头保留 3 到 5 条总结或洞察。
3. 关键结论标注【事实】、【推断】、【建议】或【待验证】。
4. 区分公开事实和架构推断：Foundry 内部存储引擎、具体索引实现、cache 淘汰算法不公开时必须标为【推断】或【待验证】。
5. 所有重要结论落到 `docs/raw` 或 `docs/synthesis`，并在 `docs/catalog.yml` 建立索引。

---

## 5. 完成标准

1. 已创建或更新上述 6 个 Markdown 输出。
2. 已新增 `docs/topics/time-series.md` 主题入口。
3. 已更新 `docs/catalog.yml` 和 `docs/index.md`。
4. 已运行文档库校验和 whitespace 校验。
5. 已在最终响应中给出 Epic、产物路径、关键结论和证据来源。
