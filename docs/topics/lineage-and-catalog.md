# Lineage And Catalog

## 摘要与洞察

1. 【事实】Foundry 血缘最小可解释坐标不是“表”，而是 `Dataset branch + transaction/view + producer`；静态 DAG 只能说明依赖，版本血缘才能说明实际读写版本。
2. 【事实+推断】血缘至少有 resource lineage、logic lineage、run lineage、branch lineage 四层；Sync、Pipeline、Schedule、Ontology 都应登记到同一版本坐标系。
3. 【推断】自建平台不能只接 OpenLineage job edge；需要 Dataset transaction/view、branch/fallback resolution、sync task -> transaction、build run -> transaction、schema version 和 staleness。
4. 【事实】当前文档库层面，[docs/catalog.yml](../catalog.yml) 已作为机器可读索引，连接 path、topic、issue、source_refs、canonical 状态，是 topic pages 的生成/审计基础。

## Canonical Documents

| 文档 | 用途 |
| --- | --- |
| [docs/superpowers/specs/2026-05-31-research-doc-library-design.md](../superpowers/specs/2026-05-31-research-doc-library-design.md) | 文档库 catalog/topic/library 分层设计基线；当前没有 lineage 专属 canonical synthesis。 |

## Supporting Evidence

| 证据 | 精简说明 |
| --- | --- |
| [docs/raw/29-lineage-branch-version-pipeline-sync.md](../raw/29-lineage-branch-version-pipeline-sync.md) | Lineage、branch、version、pipeline、sync 关系的最完整主题证据。 |
| [docs/catalog.yml](../catalog.yml) | 机器可读文档目录、topic、issue、canonical 和 source_refs 索引。 |
| [docs/index.md](../index.md) | 人类阅读入口和推荐阅读路径。 |
| [docs/raw/04-lineage-ontology-integration.md](../raw/04-lineage-ontology-integration.md) | 早期 Data Lineage、Dataset version、Ontology-Pipeline 集成证据。 |
| [docs/raw/42-governance-lineage-audit-contracts.md](../raw/42-governance-lineage-audit-contracts.md) | coverage lineage、run-to-transaction、权限审计和元数据契约。 |
| [docs/synthesis/palantir-pipeline-deep-dive.md](../synthesis/palantir-pipeline-deep-dive.md) | Pipeline DAG、Ontology 集成和 OpenLineage 短板的综合引用。 |
| [docs/superpowers/plans/2026-05-31-research-doc-library-phase1-plan.md](../superpowers/plans/2026-05-31-research-doc-library-phase1-plan.md) | Issue #46 topic index 的页面契约和最小链接清单。 |

## Related Issues

#30、#42、#44、#45、#46、#47、#48

## Open Questions

- Foundry Data Lineage 内部索引结构、边主键和 branch-qualified resource id 公开资料不足。
- SyncRun/BuildRun 与 transaction 的 API 级数据模型需要真实环境或内部 API 验证。
- Column-level lineage 对 SQL、Pipeline Builder 表达式、手写 PySpark 的覆盖边界仍不清楚。
- 文档库后续是否自动生成 topic pages，还是继续手工维护，需要在 #46/#47 后决定。
