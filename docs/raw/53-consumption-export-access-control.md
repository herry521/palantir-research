# 53 - Dataset、Stream、API 消费与导出访问控制调研

**所属 Epic：** #49
**对应 Story：** #53
**类型：** Story 调研 / Consumption、Stream、API、Export 权限边界
**调研日期：** 2026-05-31

## 摘要与洞察

1. 【事实】Dataset 访问必须拆成 `resource access` 与 `data access`；用户可能能发现/open metadata，但因不满足上游 lineage-derived data requirements 而不能读取 Dataset view 数据。
2. 【推断】所有数据消费入口，包括 Dataset Preview、query engine、download/export、OSDK/API、AIP、Stream archival dataset，都应走统一 query-time PDP/PEP；读取时不应重算 lineage，而应读取已物化 requirements。
3. 【事实】Restricted View 与 Ontology Object/Property Security 是路径级细粒度策略，叠加在 Dataset requirements 后，不能替代 backing Dataset 的基础访问控制。
4. 【建议】Stream subscription 应独立建模为持续消费授权，分开检查 stream resource、consumer group/checkpoint、subscriber/service account、export sink 和审计。
5. 【建议】外部通知/导出必须视为独立 export/redaction policy；Viewer permission 不能自然外推到 Slack、PagerDuty、webhook、Kafka export、download、SIEM 等外部接收者。

## 1. 消费路径权限矩阵

| 消费路径 | 主要资产 | 必要控制 | PDP/PEP 位置 | 细粒度策略 | 导出/显示策略 |
|---|---|---|---|---|---|
| Dataset metadata / resource open | Dataset resource、RID、path、name | Project/resource role、file/resource Marking、Organization、Classification | Resource service / API gateway | 无 | RID/name display |
| Dataset view preview / query | branch + view + transaction requirements | Viewer role + resource requirements + data requirements + scoped session | Query Gateway / Dataset Preview PEP | Restricted View 时追加 row policy | UI redaction |
| Dataset transaction/history | transaction list、schema、producer run、file manifest | resource view；涉及样本/文件详情时追加 data requirements | Dataset Service / Lineage UI | 无；列统计需列策略 | history metadata policy |
| Dataset download | Dataset view 文件或查询结果 | query 权限 + download/export permission + audit + limit | Download service PEP + Query PDP | 列/字段白名单或 redaction | watermark、purpose、audit |
| Stream hot subscription | Stream hot buffer、consumer cursor | Stream role、subscriber/service account、data requirements、consumer group ownership | Stream serving PEP | 可选低延迟 row/column policy | 不适用 |
| Stream cold/archive access | Stream archival Dataset | Dataset view/query 权限 | Query Gateway / Dataset Preview | 同 Dataset | 同 Dataset export |
| Streaming export / Kafka write-out | Stream/Dataset 到外部 topic | source read + export sink permission + export policy | Export job planner + runtime PEP | 字段白名单、redaction | external topic/payload policy |
| Ontology Object read / OSDK / API | Object Type、Object Set、backing Dataset | Dataset data requirements + Ontology object policy | Ontology serving / OSDK API PEP | object/row policy | API field redaction |
| Ontology Property read | property、backing column/value | Dataset requirements + property policy | Ontology serving PEP | property/column/value policy | hidden/masked value |
| Monitoring alert subscription | Monitoring View、monitored resource | monitoring view Viewer + monitored resource Viewer | Monitoring subscription PEP | 无 | internal notification fields |
| Slack/PagerDuty/Webhook notification | Alert payload、resource RID/name、severity | route policy、receiver/channel ownership、secret scope、export policy | Notification dispatcher PEP | payload redaction | RID/name display, exportable markings |
| Audit/SIEM export | audit events | audit export permission、destination permission | Audit export PEP | event field filtering | sensitive event redaction |

## 2. 外部导出/通知旁路风险

1. 【事实】Monitoring Views 的 Viewer permission 约束 Foundry 内部监控资源和 alert 接收资格；公开文档未证明外部 Slack/PagerDuty/webhook 接收者会逐人校验 Foundry Viewer。
2. 【事实】Slack human-readable resource name 受 exportable markings/organizations 控制；缺失时显示 RID。
3. 【待验证】PagerDuty、webhook、email 的完整 payload、重试、签名、dedupe、失败告警和接收者权限变化处理未完整公开。
4. 【推断】RID 不是天然低敏字段；它可以替代 resource name，但不代表在所有租户/场景都可无条件外发。
5. 【建议】所有外发路径统一建模为 `ExportPolicy`：allowed markings、allowed organizations、field-level redaction、RID/name display、payload schema、receiver ownership、secret rotation、delivery audit。

## 3. 自研平台 P0/P1/P2 建设建议

| 优先级 | 建设项 | 验收标准 |
|---|---|---|
| P0 | Dataset/Resource/Branch/Transaction/View 元模型 | 能按 branch + transaction/view 定位数据版本，history 不被最新权限覆盖 |
| P0 | Resource role + requirements + query-time PDP | Preview/API/query/download 的服务端 PEP 调同一 PDP，返回 missing requirements |
| P0 | Dataset download/export 独立权限 | download/export 不由 Preview 自动附赠，所有导出写 audit |
| P0 | Stream subscription permission | subscribe/read/reset/checkpoint/export sink 分权，service account 和 human user 可审计 |
| P1 | Build-time lineage propagation | Transform/Sync commit 前物化 inherited requirements，读取时不重算 lineage |
| P1 | Restricted View 与 Ontology policy | 先检查 backing Dataset requirements，再执行 row/object/property filtering |
| P1 | Export/redaction policy | 对 Slack/webhook/Kafka/download/SIEM 统一字段白名单、RID/name、marking/org allowlist |
| P2 | Protected branch unmarking | unmarking rule 绑定 branch、input、output、requirementId、approval |
| P2 | Impact simulation + whyDenied | 加 marking 或移除继承前预估 downstream 影响 |
| P2 | SDS/Cipher/Audit SIEM 闭环 | sensitive scan、obfuscation、issue、access denied、export redaction 可审计 |

## 4. 证据缺口

1. 【待验证】Stream hot path 的 Marking/Organization enforcement、consumer group ACL、checkpoint reset 权限需要实测。
2. 【待验证】Ontology Property Security 与 backing Dataset requirement 的执行顺序需要在不同 Object Storage 版本下验证。
3. 【待验证】Download/export 是否支持字段级 redaction、watermark、purpose justification 需按具体应用确认。
4. 【待验证】外部 notification payload 的安全等级和 receiver membership 管理边界未完整公开。

## 5. 来源

- Palantir Markings: <https://www.palantir.com/docs/foundry/security/markings/>
- Palantir Checking Permissions: <https://www.palantir.com/docs/foundry/security/checking-permissions>
- Palantir Restricted Views: <https://www.palantir.com/docs/foundry/security/restricted-views/>
- Palantir Manage Restricted Views: <https://www.palantir.com/docs/foundry/platform-security-management/manage-restricted-views>
- Palantir Data Connection exports: <https://www.palantir.com/docs/foundry/data-connection/export-overview>
- `docs/raw/16-streaming-capability-deep-dive.md`
- `docs/raw/29-lineage-branch-version-pipeline-sync.md`
- `docs/raw/30-dataset-permission-marking-architecture.md`
- `docs/raw/49-data-quality-external-notification-security.md`
- `docs/synthesis/dataset-permission-marking-architecture-summary.md`
