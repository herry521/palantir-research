# Security And Marking

## 摘要与洞察

1. 【事实】Foundry Dataset 权限不是单一 RBAC，而是 Project/Resource Role、Organization、Marking、Classification、Lineage-derived data requirements、Restricted View、Ontology policy、SDS 与 Audit 的组合判定。
2. 【事实】Marking 是强制访问控制要求，不是普通标签；用户即使有 Viewer/Owner 类资源角色，缺少必要 Marking 仍不能读取受保护数据。
3. 【事实】Data Connection 的 source、sync、agent、webhook、external code connection 也是权限对象；source 上的 Marking/Organization 会传播到 sync output dataset。
4. 【事实+推断】Integration 侧 RBAC 的核心是 role/operation 授权，但 Source Editor、Webhook full history、export enable、secret exposure 等高危 operation 需要从默认角色中拆出单独治理。
5. 【待验证】Palantir 未公开完整 Marking 内部表结构、传播引擎实现、Data Connection secret ACL 和 audit event schema；相关数据模型属于工程化推断。

## Canonical Documents

| 文档 | 用途 |
| --- | --- |
| [docs/synthesis/dataset-permission-marking-architecture-summary.md](../synthesis/dataset-permission-marking-architecture-summary.md) | Dataset 权限、Marking、传播和访问控制主结论。 |
| [docs/synthesis/data-integration-permission-system-roadmap.md](../synthesis/data-integration-permission-system-roadmap.md) | Data Integration 全链路权限建设缺口、P0/P1/P2 路线和专家评审结论。 |
| [docs/synthesis/palantir-integration-rbac-permission-expression.md](../synthesis/palantir-integration-rbac-permission-expression.md) | Integration 对象权限表达、RBAC 默认角色/operation 授权矩阵和自研拆分建议。 |
| [docs/synthesis/palantir-resource-scope-configuration-reference.md](../synthesis/palantir-resource-scope-configuration-reference.md) | 可直接用于权限配置的 Dataset、Pipeline、Build、Schedule、Sync scope 清单。 |

## Supporting Evidence

| 证据 | 精简说明 |
| --- | --- |
| [docs/raw/30-dataset-permission-marking-architecture.md](../raw/30-dataset-permission-marking-architecture.md) | Dataset 权限体系与 Marking 架构全量证据。 |
| [docs/raw/06-security-and-permissions.md](../raw/06-security-and-permissions.md) | 安全与权限全景，区分 Marking、CBAC、Organization、行列级安全、Workspace/Dataset 权限。 |
| [docs/raw/11-marking-mechanism-deep-dive.md](../raw/11-marking-mechanism-deep-dive.md) | Marking 本质、AND/OR 类别、传播模拟、`stop_propagating`、Ontology 安全叠加和常见问题。 |
| [docs/raw/12-dataset-marking-implementation.md](../raw/12-dataset-marking-implementation.md) | Dataset Marking 的实现方案背景。 |
| [docs/raw/13-marking-advanced-deep-dive.md](../raw/13-marking-advanced-deep-dive.md) | Marking 进阶机制与治理实践。 |
| [docs/raw/49-data-quality-external-notification-security.md](../raw/49-data-quality-external-notification-security.md) | 外部通知与 Marking/Organization export/redaction policy 的交叉证据。 |
| [docs/raw/51-ingestion-connection-credential-permission-boundary.md](../raw/51-ingestion-connection-credential-permission-boundary.md) | Source、Credential、Sync、ExportPolicy 的接入侧权限边界。 |
| [docs/raw/52-transform-runtime-build-permission-boundary.md](../raw/52-transform-runtime-build-permission-boundary.md) | Transform / Pipeline 构建运行时身份、PR、CI、schedule 和 output ownership 权限边界。 |
| [docs/raw/53-consumption-export-access-control.md](../raw/53-consumption-export-access-control.md) | Dataset、Stream、API、download/export 和外部通知的消费侧访问控制。 |
| [docs/raw/54-lineage-marking-policy-propagation-model.md](../raw/54-lineage-marking-policy-propagation-model.md) | Data Integration 全链路 requirement 传播、transaction/view 快照和受控 unmarking 模型。 |
| [docs/raw/55-permission-governance-audit-lifecycle.md](../raw/55-permission-governance-audit-lifecycle.md) | 权限申请、审批、审计、break-glass、recertification 和 SIEM 生命周期治理。 |
| [docs/synthesis/palantir-data-quality-module-research.md](../synthesis/palantir-data-quality-module-research.md) | Data Quality 外部通知安全边界与 Viewer permission 收窄结论。 |

## Related Issues

#19、#42、#43、#46、#49、#50、#51、#52、#53、#54、#55、#56、#57、#71

## Open Questions

- Palantir 内部 Marking Service、Requirement Service、Propagation Engine 是否与推断模型一致？
- 普通 Marking category 的 OR 语义在资源访问判定中是否存在公开可证实边界？
- Marking audit event 的完整 schema、保留周期、SIEM 导出格式是什么？
- 历史 transaction 的 requirement 变更、重算和审计在大规模下如何治理？
- 外部通知 payload 中 RID、资源名、Marking 信息的敏感等级如何统一定义？
- Data Connection secret import 到 code resource 后的隔离、redaction 和审计细节如何实测？
- Stream hot subscription、checkpoint reset 和 streaming export sink 的权限模型是否与 Dataset view 一致？
