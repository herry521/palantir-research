# 55 - 权限申请、审批、审计与生命周期治理调研

**所属 Epic：** #49
**对应 Story：** #55
**类型：** Story 调研 / Access Request、Approval、Audit、Lifecycle Governance
**调研日期：** 2026-05-31

## 摘要与洞察

1. 【事实】Foundry audit logs 用于回答 who、what、when、where，并支持导入外部 SIEM 或导出到 Foundry 数据集；audit logs 本身也可能包含敏感信息。
2. 【事实】Palantir 对 sensitive actions 支持 Checkpoints justification，对 removing inherited Markings/Organizations 支持 protected branch + special approver。
3. 【推断】权限治理应围绕 effective access requirement 快照设计，而不是静态 ACL；否则无法证明用户在某时刻读到哪一版、满足了哪些要求。
4. 【建议】权限申请、审批、break-glass、recertification、audit/SIEM、policy drift 必须作为 Data Integration 控制面的一等能力。
5. 【待验证】Palantir 未公开所有 Data Integration action 的 audit event name/category；自研需要先定义稳定 audit schema。

## 1. 审计事件清单

| 类别 | 必记事件 | 关键字段 |
|---|---|---|
| 权限配置 | role grant/revoke、Marking member add/remove、Organization member change | actor、target principal/group、before/after、reason、ticket |
| Marking 生命周期 | category/marking create/update/delete、apply/remove resource marking | markingId、resourceId、operator、approval、impact summary |
| 传播与构建 | build started/committed/aborted、transaction_requirement written、lineage edge written | runId、input tx、output tx、branch、commit、requirements |
| 审批中断 | stop_propagating/stop_requiring proposed/approved/rejected/applied | PR、commit、input/output、requirementId、approver、permission check |
| 访问决策 | data_access_allowed/denied、export、preview、API、AIP agent read | user、resource、resolved branch/view/tx、missing requirements、traceId |
| 生命周期治理 | time-bound access granted/expired、break-glass opened/closed、recertification approved/revoked | TTL、emergency reason、reviewer、post-review result |
| 自动治理 | SDS scan/match/action、policy drift、quality gate fail | scanId、match rule、action、affected datasets、issueId |
| SIEM | denied burst、high-risk export、break-glass use、privilege escalation | severity、correlation id、source IP/session/device |

## 2. 审批矩阵

| 操作 | 申请人 | 审批人 | 必要校验 | 结果 |
|---|---|---|---|---|
| Project/Dataset role access | 用户或服务账号 | Project/Dataset owner | 最小权限、业务理由、TTL 可选 | grant role/group |
| Marking membership | 用户/owner 代申请 | Marking admin 或数据治理 owner | 培训/合规资格、数据域 owner 同意、TTL | add marking member |
| Connection/source access | 数据工程师/同步任务 owner | Source owner + platform security | 凭据 scope、目标 Dataset Marking、审计开关 | enable sync/run |
| Apply Marking to Dataset | Resource owner | Marking apply 权限持有人 | lineage impact simulation | add direct requirement |
| Remove direct Marking | Resource owner | Marking remove 权限持有人 | 确认误标或数据迁移 | remove direct requirement |
| stop_propagating | Transform owner | Security reviewer with Remove marking | protected branch、input-specific、脱敏证据、downstream rebuild plan | approved unmarking rule |
| stop_requiring | Transform owner | Org/space expand-access approver | 跨组织共享依据、数据混淆证明 | approved org unrequire |
| Break-glass | on-call / incident owner | emergency approver 或 dual control | 短 TTL、强制理由、只读优先、实时 SIEM | temporary access + post-review |
| Recertification | 系统定期发起 | Dataset owner + Marking admin | 最近使用、角色必要性、离职/转岗 | keep/revoke/expire |
| Policy drift remediation | 平台自动发起 | Data governance / platform owner | desired vs effective diff、影响范围 | fix policy or accept exception |

## 3. 生命周期状态机

```text
requested
  -> approved
  -> active
  -> used
  -> reviewed
  -> renewed | expired | revoked
  -> archived
```

对 break-glass 使用更严格状态：

```text
opened
  -> active_with_live_alert
  -> expired_or_closed
  -> post_review_required
  -> closed_with_findings
```

每个 grant/policy/credential/service principal 至少需要：

- owner
- created_by / approved_by
- reason and ticket
- start/end time
- last_used
- risk level
- review cadence
- revocation path
- audit correlation id

## 4. 自研平台建设建议

| 优先级 | 能力 | 说明 |
|---|---|---|
| P0 | 基础审计 | allow/deny、role/marking membership、resource marking apply/remove、export 全量写 audit |
| P0 | Access request | role + Marking + Organization 组合申请，路由 owner/admin 审批 |
| P0 | Purpose / justification | 高风险 preview、download、export、break-glass 要求理由 |
| P0 | Audit schema | actor、effective principal、resource、action、decision、policy ids、credential id、run id、trace id |
| P0 | Access decision snapshot | 记录决策时的 group membership、Marking/Organization membership、credential scope、policy version、transaction_requirement version、session scope 和 decision inputs，支持事后回放 |
| P1 | Time-bound access | TTL grant、自动过期、到期通知、续期审批 |
| P1 | SIEM export | denied burst、break-glass、high-risk export、privilege escalation 推送外部 SIEM |
| P1 | Access debugger | 用户自助看到缺少 role/marking/org/export policy，不暴露敏感细节 |
| P1 | Policy drift detection | desired policy vs effective requirement vs audit reality |
| P2 | Recertification | 按数据敏感度周期 owner review，未确认自动降权 |
| P2 | Break-glass 完整闭环 | 临时访问、实时告警、强制事后复盘、异常自动升级 |
| P2 | SDS 自动治理 | 扫描命中自动 apply marking/create issue/obfuscate |

## 5. 风险

| 风险 | 影响 | 控制 |
|---|---|---|
| Audit 只记成功不记拒绝 | 无法调查越权尝试和策略误配 | allow/deny 都落库 |
| Service account 无 owner | 凭据长期存在无人回收 | service principal owner + last-used + TTL |
| Break-glass 没有事后复盘 | 临时访问变长期绕过 | 自动过期 + post-review gate |
| Access request 只批 role | 缺 Marking/Organization 仍无法读，或错误授予过宽 | 组合申请 + whyDenied |
| Export 审计缺 payload policy | 外发后无法追踪敏感字段 | export policy id + redaction decision |
| Audit logs 自身过度开放 | 审计日志含 PII、RID、缺失 requirement | audit viewer 专门权限和脱敏 |

## 6. P0 audit snapshot schema

仅记录 actor、resource 和 decision 不足以支持权限回放。P0 access decision snapshot 至少包含：

| 字段组 | 字段 |
|---|---|
| actor context | actor_user、groups_snapshot_id、session_id、session_scope、on_behalf_of、runtime_principal |
| entitlement context | role_grants_version、marking_membership_snapshot_id、organization_membership_snapshot_id、classification_clearance_snapshot_id |
| resource context | resource_id、branch、view_id、transaction_id/range、resource_requirement_version、transaction_requirement_version |
| credential context | credential_id、credential_scope_version、external_principal、destination_resource |
| policy context | PDP version、policy ids、export_policy id、row/column/property policy ids、redaction policy id |
| decision context | action、decision、missing_requirements、purpose/justification、trace_id、request_id、timestamp |

历史回放应基于 snapshot id 和 policy/requirement version，不依赖实时 group lookup；实时目录只用于补充展示。

## 7. 证据缺口

1. 【待验证】Palantir Checkpoints 可覆盖哪些 Data Integration action 未完整公开。
2. 【待验证】Data Connection、Build、Export、Marking 的 audit event name/category 映射未完整公开。
3. 【待验证】audit.3 中 user/group 实时 enrichment 的限制会影响按组权限回放，自研需另建 identity snapshot。
4. 【待验证】break-glass、recertification 是否有 Foundry 内置通用产品能力需进一步查证。

## 8. 来源

- Palantir Audit Logs: <https://www.palantir.com/docs/foundry/security/audit-logs-overview>
- Palantir Monitor audit logs: <https://www.palantir.com/docs/foundry/security/monitor-audit-logs/>
- Palantir Requesting justification for sensitive actions: <https://www.palantir.com/docs/foundry/security/requesting-justification-for-sensitive-actions/>
- Palantir Remove inherited Markings: <https://www.palantir.com/docs/foundry/building-pipelines/remove-inherited-markings>
- `docs/raw/30-dataset-permission-marking-architecture.md`
- `docs/raw/42-governance-lineage-audit-contracts.md`
- `docs/raw/48-data-quality-governance-lifecycle.md`
