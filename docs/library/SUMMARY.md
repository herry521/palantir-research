# Palantir Research Book Summary

## 摘要与洞察

1. 【结论】本目录采用 book 式阅读顺序，但底层仍保持 raw、synthesis、topics、catalog 的多视图结构。
2. 【建议】阅读顺序应从管理结论开始，再进入平台心智、工程底座、治理闭环、AI/工程入口和自研路线。
3. 【事实】每章都回链 topic、synthesis 和 raw 文档，便于从结论追溯到证据。
4. 【约束】`SUMMARY.md` 是导航文件，不是证据文件；任何新增研究结论仍应写入 `docs/raw` 或 `docs/synthesis`。

## Contents

1. [Executive Summary](00-executive-summary.md)
2. [Platform Mental Model](01-platform-mental-model.md)
3. [Data Engineering Core](02-data-engineering-core.md)
4. [Governance and Operations](03-governance-and-operations.md)
5. [AI FDE and Engineering](04-ai-fde-and-engineering.md)
6. [Self-build Roadmap](05-self-build-roadmap.md)
7. [Appendix: Research Document Map](appendices/research-document-map.md)

## Reading Modes

| 模式 | 顺序 | 适用场景 |
| --- | --- | --- |
| 决策速读 | 00 -> 05 -> Appendix | 判断平台建设优先级。 |
| 架构深读 | 01 -> 02 -> 03 -> 05 | 设计 Dataset、Pipeline、权限、质量和血缘底座。 |
| 工程落地 | 02 -> 04 -> 05 | 对齐 Pro-Code、AI FDE、工程治理和 PoC 范围。 |
| 证据复核 | Appendix -> topics -> synthesis -> raw | 查找结论来源和 issue/story 关系。 |

## Maintenance Rule

当 `docs/topics` 或 `docs/synthesis` 新增 canonical 结论时，同步检查本目录：

- 是否需要调整章节导读。
- 是否需要在 Appendix 中补充映射。
- 是否需要更新 [HTML book preview](../../deliverables/pages/book-library.html)。
