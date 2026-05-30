# Data Quality

## 摘要与洞察

1. 【推断】Palantir Data Quality 不是单个独立产品页，而是跨构建、运行监控、告警、issue 和治理的质量控制面。
2. 【事实】Data Expectations 是 transform input/output 上的 build-time contract；`FAIL` 可 abort job，`WARN` 可继续并进入 Data Health/Builds 可见面。
3. 【事实】Data Health 包含 Monitoring Views 与 Health Checks：前者做 scope-based 规模化监控，后者做单资源 status/time/size/content/schema/freshness 等检查。
4. 【推断】核心价值在跨应用闭环：规则定义、CI 注册、构建执行、结果展示、Health tab/lineage、订阅/告警/issue、生命周期审查。
5. 【建议】自建平台应拆分 BuildCheckResult、HealthCheckResult、MonitoringAlert、IssueLinkage、ExternalRoutePolicy/ExportPolicy，避免把构建期门禁和运行期告警压成一种“规则”。

## Canonical Documents

| 文档 | 用途 |
| --- | --- |
| [docs/synthesis/palantir-data-quality-module-research.md](../synthesis/palantir-data-quality-module-research.md) | Data Quality 模块主结论，已完成第二轮专家复审。 |

## Supporting Evidence

| 证据 | 精简说明 |
| --- | --- |
| [docs/raw/44-data-quality-source-map.md](../raw/44-data-quality-source-map.md) | 资料源、术语边界、Data Expectations / Data Health / Health Checks / Monitoring Views / Foundry Issue 的定义。 |
| [docs/raw/45-data-expectations-build-gates.md](../raw/45-data-expectations-build-gates.md) | 构建期质量门禁、`Check`、`Expectation`、`FAIL/WARN`、CI/PR review。 |
| [docs/raw/46-data-health-health-checks.md](../raw/46-data-health-health-checks.md) | 运行期 Health Checks、资源健康、evaluation trigger、Health tab 和 lineage 入口。 |
| [docs/raw/47-monitoring-views-alert-issue-loop.md](../raw/47-monitoring-views-alert-issue-loop.md) | Monitoring Views、告警、订阅、Issue 闭环。 |
| [docs/raw/48-data-quality-governance-lifecycle.md](../raw/48-data-quality-governance-lifecycle.md) | 质量规则治理、代码评审、生命周期、Marketplace/CI 边界。 |
| [docs/raw/49-data-quality-external-notification-security.md](../raw/49-data-quality-external-notification-security.md) | Slack/PagerDuty/webhook/email 外部通知安全边界。 |
| [docs/raw/26-pro-code-governance-quality-observability.md](../raw/26-pro-code-governance-quality-observability.md) | 高码治理中 Data Expectations、Data Health、lineage、marking、observability 的背景闭环。 |
| [docs/raw/05-testing-and-data-connection.md](../raw/05-testing-and-data-connection.md) | 测试、数据接入和质量检查的早期背景证据。 |
| [docs/raw/08-monitoring-and-observability.md](../raw/08-monitoring-and-observability.md) | Build 监控、SLA、Data Health 和 Monitoring Views 的早期背景证据。 |

## Related Issues

#35、#36、#37、#38、#39、#40、#41、#43、#46

## Open Questions

- Data Expectations result 与 Health Checks result 是否共享内部 schema、ID 和保留策略？
- Java/SQL/R 等非 Python Transform 的 Data Expectations 能力是否完全等价？
- Monitoring severity、alert dedupe、aggregation、resolve/reopen 状态机是否有更完整证据？
- PagerDuty/webhook/email payload、签名、重试、失败告警、接收者权限边界如何设计？
- Health Check 自动 issue 的 dedupe、reopen、rename/delete 后绑定、跨 Marketplace 安装迁移仍需验证。
