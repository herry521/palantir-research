# Governance and Operations

## 摘要与洞察

1. 【结论】Foundry 的治理强项来自同一资源/版本坐标上的权限、Marking、质量、血缘、告警、issue 和审计闭环。
2. 【事实】Dataset 权限不是单一 RBAC，而是 Project/Resource Role、Organization、Marking、Classification、lineage-derived requirements、Restricted View、Ontology policy 和 Audit 的组合。
3. 【事实】Data Quality 横跨 build-time expectations、runtime health checks、Monitoring Views、notifications/issues 和治理生命周期。
4. 【推断】自研平台不能把权限、质量和血缘做成外围系统；它们必须消费同一 Dataset/Run/Transaction/Resource 元模型。
5. 【建议】所有外发路径，包括 download/export、API、Stream、webhook、Slack/PagerDuty，都应有独立 export policy 和 access decision snapshot。

## 治理闭环

```text
Resource / Dataset / Transaction
  -> Requirement propagation
  -> Query-time PDP / PEP
  -> Quality and health result
  -> Monitoring / issue / external route
  -> Audit / access debugger / recertification
```

这个闭环要求平台把“谁能看”“是否可信”“出了问题谁处理”“能否离开平台”连在一起。只做 ACL 或只做质量规则都不够。

## 权限控制面的最小对象

| 对象 | 为什么必须一等化 | 参考文档 |
| --- | --- | --- |
| Source / Connection | source edit、preview、sync、webhook 都是高风险入口。 | [Data Integration 权限路线图](../synthesis/data-integration-permission-system-roadmap.md) |
| Credential / Secret | secret use、read、expose-to-code、rotation 需要分权。 | [Credential boundary](../raw/51-ingestion-connection-credential-permission-boundary.md) |
| Dataset transaction/view | 历史版本不能被最新权限状态覆盖，需要 requirement snapshot。 | [Requirement propagation](../raw/54-lineage-marking-policy-propagation-model.md) |
| Export / External route | 外部通知和下载/API/stream 是独立外发面。 | [Consumption export control](../raw/53-consumption-export-access-control.md) |
| Audit decision | why-denied、break-glass、recertification 需要可追溯决策记录。 | [Governance audit lifecycle](../raw/55-permission-governance-audit-lifecycle.md) |

## 质量控制面的最小分层

| 层级 | 职责 | 不应混淆为 |
| --- | --- | --- |
| Build-time expectations | 当前 transform build 是否应该继续。 | 通用监控告警。 |
| Single-resource health checks | 单个 dataset/schedule/table 的健康与新鲜度。 | 代码 PR 校验。 |
| Scope-based monitoring views | 多资源规模化监控、订阅和路由。 | 单个数据契约。 |
| Issue / external notification | 分派、恢复、关闭和外部协同。 | 纯日志输出。 |

## 主要证据

- [Dataset 权限与 Marking 机制沉淀](../synthesis/dataset-permission-marking-architecture-summary.md)
- [Data Integration 权限体系建设缺口与路线图](../synthesis/data-integration-permission-system-roadmap.md)
- [Palantir Data Quality 模块调研综合报告](../synthesis/palantir-data-quality-module-research.md)
- [Data Quality topic](../topics/data-quality.md)
- [Security and Marking topic](../topics/security-and-marking.md)
