# Data Integration 能力地图研究主题覆盖度反查

## 摘要与洞察

1. 【结论】当前 Data Integration 战情图已覆盖接入、Dataset、Pipeline、Build、Lineage/Schedule、Ontology、Quality、Security 的核心链路，但原版本对 Time Series、AI FDE、Pro-Code 工程治理、Branch/Version 解释不够显性。
2. 【决策】本次补充不新增新的汇报主链路节点，避免页面从“数据加工链路战情图”变成全平台菜单；新增内容主要进入既有节点和明细区。
3. 【事实】补充项来自仓库现有 topic/canonical research：Dataset、Pipeline、Scheduling、Lineage、Ontology、Time Series、Data Quality、Security and Marking、Pro-Code、AI FDE、Self-build Roadmap。
4. 【建议】后续汇报时应把 Time Series、Quality/Governance、AI FDE 标为“支撑与加速能力”，不要把它们讲成与 Connectivity/Pipeline/Build 同层的必经主链路。

## 反查方法

以 `docs/index.md` 与 `docs/topics/*.md` 中的主题索引为基准，逐项检查 `deliverables/pages/data-integration-capability-map.html` 的能力数据是否能承载对应研究结论。检查口径是“是否能在领导汇报页中被显式点亮和追踪”，不是“是否全文复述研究文档”。

## 覆盖度矩阵

| Research 主题 | 原页面覆盖 | 本次补充 | 放置位置 |
|---|---|---|---|
| Dataset | 已覆盖 Dataset、transaction、branch、stream | 补充 views、branch view/fallback、target schema/primary key | Core Data Objects；Datasets 汇报节点 |
| Pipeline / Pro-Code | 已覆盖 Pipeline Builder、Code Repositories、Python/SQL/Java、Batch/Incremental/Streaming | 补充 Input/Output declarations、PR/CI/preview、repository upgrades、batch/stream pro-code boundary | Pipeline Authoring、Pipeline Types；Pipeline 汇报节点 |
| Scheduling / Lineage | 已覆盖 schedule、trigger、lineage graph、stale analysis | 补充 permission/marking impact 进入汇报节点；强调 Branch/Version 解释依赖 Dataset + Lineage | Lineage & Schedules 汇报节点 |
| Ontology | 已覆盖 Object types、Object sets、Actions、Object Data Funnel、Object indexing、Functions | 补充 Interfaces/Value types、Time Series Properties、OSDK consumption | Ontology / Object Backend；Ontology 汇报节点 |
| Time Series | 原页面只通过 Streams 间接覆盖 | 补充 time series sync、Time Series Properties、time series alerting | Data Connection、Ontology、Health / Quality |
| Data Quality | 已覆盖 Health checks、Data Expectations、Data Health、Monitoring views | 补充 notification/issue loop、time series alerting | Health / Quality；Ontology 汇报节点的支撑能力 |
| Security and Marking | 已覆盖 roles、organizations、markings、object/property security、audit | 补充 source/credential boundary、export policy、SIEM audit 线索 | Security / Governance；Ontology 汇报节点的支撑能力 |
| AI FDE | 原页面未覆盖 | 新增 AI FDE / Engineering Execution 支撑层，覆盖 session、tool approval、branch/PR handoff、preview/CI/evals、audit attribution | Support 区；Ontology 汇报节点引用 branch/PR handoff |
| Self-build Roadmap | 原页面通过状态配置间接支持路线追踪 | 把新增能力作为可配置状态项，便于后续按 P0/P1/P2 点亮 | 动态能力配置 JSON |

## 内容取舍

- 保留 6 个汇报主节点：Connectivity、Datasets、Pipeline、Builds、Lineage & Schedules、Ontology。原因是它们最能表达“数据从接入到服务业务”的核心链路。
- Time Series 不单独成为主节点。它更像特定数据类型的接入、索引和对象服务路径，因此拆入 Connectivity、Ontology 和 Quality。
- AI FDE 不进入主链路。它是工程执行面和治理加速器，放在支撑层能避免领导误解为 Data Integration 的必经处理步骤。
- Security / Quality 不单独成为主节点，但关键能力被汇报节点引用，确保状态统计能反映治理缺口。

## 后续维护建议

1. 当 `docs/topics` 新增 canonical 主题时，先判断它属于主链路、支撑层还是专题数据服务路径，再决定是否进战情图。
2. 每次新增能力项后，同步检查 B1/B2 两个页面的 `DI_MAP_MODULES` 是否一致。
3. 如果后续页面要支撑正式路线图评审，可在动态配置 JSON 中加入 `priority`、`phase`、`owner` 字段，而不是继续扩展静态卡片文案。
