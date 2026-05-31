# Research Document Map

## 摘要与洞察

1. 【事实】当前文档库的可靠阅读顺序是 book chapter -> topic index -> synthesis conclusion -> raw evidence。
2. 【建议】不要按 raw 编号线性阅读；raw 编号是证据坐标，不是最终叙事顺序。
3. 【事实】`docs/catalog.yml` 已维护 path、topic、issue、source_refs、canonical 状态，是后续自动生成索引和链接检查的基础。
4. 【约束】本附录只列主要入口；完整文档关系以 [docs/catalog.yml](../../catalog.yml) 为准。

## Chapter To Evidence Map

| Book 章节 | Topic 入口 | Canonical / synthesis | 关键 raw 证据 | Issue |
| --- | --- | --- | --- | --- |
| [00 Executive Summary](../00-executive-summary.md) | [Self-build Roadmap](../../topics/self-build-roadmap.md) | [operator-platform-design.md](../../synthesis/operator-platform-design.md) | [10-opensource-alternative-stack.md](../../raw/10-opensource-alternative-stack.md) | #42、#60 |
| [01 Platform Mental Model](../01-platform-mental-model.md) | [Pipeline](../../topics/pipeline.md)、[Ontology](../../topics/ontology.md) | [palantir-pipeline-deep-dive.md](../../synthesis/palantir-pipeline-deep-dive.md)、[palantir-dataset-vs-data-warehouse.md](../../synthesis/palantir-dataset-vs-data-warehouse.md) | [25-transform-contract-dag.md](../../raw/25-transform-contract-dag.md)、[29-lineage-branch-version-pipeline-sync.md](../../raw/29-lineage-branch-version-pipeline-sync.md) | #4、#28、#46 |
| [02 Data Engineering Core](../02-data-engineering-core.md) | [Dataset](../../topics/dataset.md)、[Scheduling](../../topics/scheduling.md) | [palantir-dataset-no-dt-partition-impact.md](../../synthesis/palantir-dataset-no-dt-partition-impact.md)、[foundry-schedule-module-deep-dive.md](../../synthesis/foundry-schedule-module-deep-dive.md) | [39-foundry-dataset-transaction-view-evidence.md](../../raw/39-foundry-dataset-transaction-view-evidence.md)、[43-migration-risk-dual-coordinate-patterns.md](../../raw/43-migration-risk-dual-coordinate-patterns.md) | #28、#29、#31、#33 |
| [03 Governance and Operations](../03-governance-and-operations.md) | [Security and Marking](../../topics/security-and-marking.md)、[Data Quality](../../topics/data-quality.md) | [dataset-permission-marking-architecture-summary.md](../../synthesis/dataset-permission-marking-architecture-summary.md)、[palantir-data-quality-module-research.md](../../synthesis/palantir-data-quality-module-research.md)、[data-integration-permission-system-roadmap.md](../../synthesis/data-integration-permission-system-roadmap.md) | [44-data-quality-source-map.md](../../raw/44-data-quality-source-map.md)、[54-lineage-marking-policy-propagation-model.md](../../raw/54-lineage-marking-policy-propagation-model.md)、[55-permission-governance-audit-lifecycle.md](../../raw/55-permission-governance-audit-lifecycle.md) | #35、#41、#49、#57 |
| [04 AI FDE and Engineering](../04-ai-fde-and-engineering.md) | [Pro-Code](../../topics/pro-code.md)、[AI FDE](../../topics/ai-fde.md) | [palantir-pro-code-capability-research.md](../../synthesis/palantir-pro-code-capability-research.md)、[palantir-ai-fde-research.md](../../synthesis/palantir-ai-fde-research.md) | [22-pro-code-source-map.md](../../raw/22-pro-code-source-map.md)、[34-ai-fde-context-tools-skills.md](../../raw/34-ai-fde-context-tools-skills.md)、[35-ai-fde-governance-branching.md](../../raw/35-ai-fde-governance-branching.md) | #4、#12、#20、#27 |
| [05 Self-build Roadmap](../05-self-build-roadmap.md) | [Self-build Roadmap](../../topics/self-build-roadmap.md) | [operator-platform-design.md](../../synthesis/operator-platform-design.md)、[dataworks-vs-palantir-integration.md](../../synthesis/dataworks-vs-palantir-integration.md) | [20-stream-self-build-architecture.md](../../raw/20-stream-self-build-architecture.md)、[37-ai-fde-self-build-implementation-blueprint.md](../../raw/37-ai-fde-self-build-implementation-blueprint.md)、[56-open-platform-permission-comparison.md](../../raw/56-open-platform-permission-comparison.md) | #24、#41、#57 |

## HTML Preview Map

HTML 页面只作为结论预览和相关文档列表，不是 canonical 结论源。

| HTML 页面 | 对应 Markdown |
| --- | --- |
| [book-library.html](../../../deliverables/pages/book-library.html) | [SUMMARY.md](../SUMMARY.md)、[README.md](../README.md) |
| [overview.html](../../../deliverables/pages/overview.html) | [docs/index.md](../../index.md)、[Pipeline topic](../../topics/pipeline.md) |
| [data-integration-permission-system.html](../../../deliverables/pages/data-integration-permission-system.html) | [data-integration-permission-system-roadmap.md](../../synthesis/data-integration-permission-system-roadmap.md) |
| [dataset-permission-marking.html](../../../deliverables/pages/dataset-permission-marking.html) | [dataset-permission-marking-architecture-summary.md](../../synthesis/dataset-permission-marking-architecture-summary.md) |

## Maintenance Checklist

- 新增 canonical synthesis 后，更新对应 topic page。
- 新增 topic page 后，更新 [docs/index.md](../../index.md)、[docs/catalog.yml](../../catalog.yml) 和本附录。
- 新增 HTML 预览页后，更新 `scripts/verify-summary-site.sh` 和必要的 browser verification。
