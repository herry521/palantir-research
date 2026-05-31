# Executive Summary

## 摘要与洞察

1. 【结论】Palantir Foundry 的核心壁垒不是单点组件，而是把数据资产、转换、版本、调度、权限、质量、血缘、语义对象和工程入口组织成闭环系统。
2. 【推断】自研平台最危险的短板通常不在 Spark、Flink 或调度器本身，而在跨层契约：Dataset version、Transform Contract、质量结果、权限要求和血缘证据没有统一坐标。
3. 【建议】建设路线应先补底座，再做增强，最后做 AI/业务应用闭环；不要先复制表层产品体验。
4. 【事实】当前仓库已有 topic index、synthesis 结论和 HTML 总览；本 book 层把它们连接成从决策到证据的阅读路径。
5. 【约束】重要结论必须继续落在 `docs/synthesis` 或 `docs/raw`，book 层只负责组织和导读。

## 一句话判断

如果只能带走一个判断：自研类 Foundry 平台的第一性问题是“让数据生产和消费被平台理解”，而不是“接入更多计算引擎”。

平台理解至少包括：

- 这个输出来自哪些输入、代码、参数、分支和数据版本。
- 这次运行覆盖哪个业务日期、数据区间和消费视图。
- 这份数据携带哪些 Marking、Organization、行列策略和导出限制。
- 质量检查、健康状态、告警、issue 和审计如何回到同一条链路。

## 决策地图

| 决策问题 | 推荐入口 | 主要结论 |
| --- | --- | --- |
| 平台壁垒是什么？ | [Platform Mental Model](01-platform-mental-model.md) | 壁垒来自 Dataset、Pipeline、Ontology、治理和工程入口的闭环。 |
| Dataset 与传统数仓有什么根本差异？ | [Data Engineering Core](02-data-engineering-core.md) | 主坐标从 `table + dt` 转向 `dataset + branch + transaction/view`，但业务日期不能丢。 |
| 权限和质量为什么要一起看？ | [Governance and Operations](03-governance-and-operations.md) | 访问控制、质量结果、告警、issue、外部通知和审计都依赖同一资源/版本坐标。 |
| AI FDE 值不值得先做？ | [AI FDE and Engineering](04-ai-fde-and-engineering.md) | 先建设可审计、可审批、可验证的平台工具执行面，再谈自然语言入口。 |
| 自研优先级如何排？ | [Self-build Roadmap](05-self-build-roadmap.md) | P0 是 Dataset/Transaction、Transform Contract、调度、质量、血缘、权限和工程治理。 |

## 当前结论来源

- 主题索引：[docs/topics/self-build-roadmap.md](../topics/self-build-roadmap.md)
- 综合结论：[docs/synthesis/operator-platform-design.md](../synthesis/operator-platform-design.md)
- 差异分析：[docs/synthesis/palantir-dataset-no-dt-partition-impact.md](../synthesis/palantir-dataset-no-dt-partition-impact.md)
- 质量控制面：[docs/synthesis/palantir-data-quality-module-research.md](../synthesis/palantir-data-quality-module-research.md)
- 权限控制面：[docs/synthesis/data-integration-permission-system-roadmap.md](../synthesis/data-integration-permission-system-roadmap.md)
- HTML 预览：[deliverables/pages/book-library.html](../../deliverables/pages/book-library.html)
