# Security And Marking

## 摘要与洞察

1. 【事实】Foundry Dataset 权限不是单一 RBAC，而是 Project/Resource Role、Organization、Marking、Classification、Lineage-derived data requirements、Restricted View、Ontology policy、SDS 与 Audit 的组合判定。
2. 【事实】Marking 是强制访问控制要求，不是普通标签；用户即使有 Viewer/Owner 类资源角色，缺少必要 Marking 仍不能读取受保护数据。
3. 【事实】Marking 会通过资源层级和数据血缘传播；脱敏后停止传播需要 protected branch、审批人与 remove/expand access 权限。
4. 【推断】自建平台不能只做 `dataset.markings` 字段，应拆成 resource requirement、transaction/view requirement、lineage propagation、query-time PDP、approval 和 audit。
5. 【待验证】Palantir 未公开完整 Marking 内部表结构、传播引擎实现和 audit event schema；相关数据模型属于工程化推断。

## Canonical Documents

| 文档 | 用途 |
| --- | --- |
| [docs/synthesis/dataset-permission-marking-architecture-summary.md](../synthesis/dataset-permission-marking-architecture-summary.md) | Dataset 权限、Marking、传播和访问控制主结论。 |

## Supporting Evidence

| 证据 | 精简说明 |
| --- | --- |
| [docs/raw/30-dataset-permission-marking-architecture.md](../raw/30-dataset-permission-marking-architecture.md) | Dataset 权限体系与 Marking 架构全量证据。 |
| [docs/raw/06-security-and-permissions.md](../raw/06-security-and-permissions.md) | 安全与权限全景，区分 Marking、CBAC、Organization、行列级安全、Workspace/Dataset 权限。 |
| [docs/raw/11-marking-mechanism-deep-dive.md](../raw/11-marking-mechanism-deep-dive.md) | Marking 本质、AND/OR 类别、传播模拟、`stop_propagating`、Ontology 安全叠加和常见问题。 |
| [docs/raw/12-dataset-marking-implementation.md](../raw/12-dataset-marking-implementation.md) | Dataset Marking 的实现方案背景。 |
| [docs/raw/13-marking-advanced-deep-dive.md](../raw/13-marking-advanced-deep-dive.md) | Marking 进阶机制与治理实践。 |
| [docs/raw/49-data-quality-external-notification-security.md](../raw/49-data-quality-external-notification-security.md) | 外部通知与 Marking/Organization export/redaction policy 的交叉证据。 |
| [docs/synthesis/palantir-data-quality-module-research.md](../synthesis/palantir-data-quality-module-research.md) | Data Quality 外部通知安全边界与 Viewer permission 收窄结论。 |

## Related Issues

#19、#42、#43、#46

## Open Questions

- Palantir 内部 Marking Service、Requirement Service、Propagation Engine 是否与推断模型一致？
- 普通 Marking category 的 OR 语义在资源访问判定中是否存在公开可证实边界？
- Marking audit event 的完整 schema、保留周期、SIEM 导出格式是什么？
- 历史 transaction 的 requirement 变更、重算和审计在大规模下如何治理？
- 外部通知 payload 中 RID、资源名、Marking 信息的敏感等级如何统一定义？
