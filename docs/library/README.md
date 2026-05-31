# Palantir Research Book

## 摘要与洞察

1. 【结论】`docs/library` 是面向读者的 book 式阅读层，不替代 `docs/raw`、`docs/synthesis` 和 `docs/topics`。
2. 【事实】当前文档库已经具备证据层、结论层、主题索引层和 HTML 预览层；book 层负责把这些材料组织成连续阅读路径。
3. 【建议】新读者先读 `00-executive-summary.md`，再按能力域进入章节；维护者仍以 `docs/catalog.yml` 和 `docs/topics/*.md` 作为索引基线。
4. 【约束】本层只做导读、结论整合和证据回链，不批量搬迁或重命名既有研究文档。

## 如何使用

- 管理层或产品负责人：先读 [00 Executive Summary](00-executive-summary.md)，再看 [05 Self-build Roadmap](05-self-build-roadmap.md)。
- 平台架构团队：按 [01 Platform Mental Model](01-platform-mental-model.md)、[02 Data Engineering Core](02-data-engineering-core.md)、[03 Governance and Operations](03-governance-and-operations.md) 顺序阅读。
- 工程执行团队：重点读 [04 AI FDE and Engineering](04-ai-fde-and-engineering.md) 与 [05 Self-build Roadmap](05-self-build-roadmap.md)。
- 需要查证据时：回到 [Research Document Map](appendices/research-document-map.md)、[docs/topics](../topics/) 或 [docs/catalog.yml](../catalog.yml)。

## Book 目录

| 章节 | 读者问题 | 主要证据入口 |
| --- | --- | --- |
| [00 Executive Summary](00-executive-summary.md) | 这批调研最后服务什么决策？ | [Self-build Roadmap](../topics/self-build-roadmap.md) |
| [01 Platform Mental Model](01-platform-mental-model.md) | Foundry 的平台心智是什么？ | [Pipeline](../topics/pipeline.md)、[Dataset](../topics/dataset.md)、[Ontology](../topics/ontology.md) |
| [02 Data Engineering Core](02-data-engineering-core.md) | Dataset、Pipeline、调度和时间语义如何组合？ | [Dataset](../topics/dataset.md)、[Scheduling](../topics/scheduling.md) |
| [03 Governance and Operations](03-governance-and-operations.md) | 权限、质量、血缘和审计如何闭环？ | [Security and Marking](../topics/security-and-marking.md)、[Data Quality](../topics/data-quality.md) |
| [04 AI FDE and Engineering](04-ai-fde-and-engineering.md) | Pro-Code 和 AI FDE 对工程体系意味着什么？ | [Pro-Code](../topics/pro-code.md)、[AI FDE](../topics/ai-fde.md) |
| [05 Self-build Roadmap](05-self-build-roadmap.md) | 自研平台应按什么顺序落地？ | [Self-build Roadmap](../topics/self-build-roadmap.md) |
| [Appendix: Research Document Map](appendices/research-document-map.md) | 每个结论背后有哪些文档？ | [docs/catalog.yml](../catalog.yml) |

## 与 HTML 预览层的关系

HTML 站点位于 [deliverables](../../deliverables/index.html)。它面向快速浏览和结论预览；book 层面向连续阅读和证据追溯。新增结论时应先更新 Markdown 文档与 catalog，再按需要更新 HTML 预览页。

## 跟踪

- Epic: [#42](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/42)
- Story: [#60](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/60)
