# Data Integration 权限体系建设缺口与路线图

**父 Epic：** #49
**综合 Story：** #57
**覆盖 Story：** #50、#51、#52、#53、#54、#55、#56
**日期：** 2026-05-31
**适用读者：** 自研数据集成平台、数据治理、安全合规、平台架构团队

## 摘要与洞察

1. 【结论】Data Integration 权限体系还缺的不是一个“数据权限表”，而是一套贯穿 source、credential、sync、transform、dataset/stream、API/export、approval、audit 的控制面。
2. 【结论】P0 必须先做七个底座：资源与版本元模型、credential/service principal 一等对象、source capability 分权、build-time requirement propagation、query-time PDP/PEP、export/egress policy、audit/access decision snapshot。
3. 【事实】Palantir 公开文档已经证明 source、sync、agent、webhook 等 Data Connection 对象是 resources；source Markings/Organizations 会传播到 sync output dataset；export 需要 exportable markings/orgs。
4. 【推断】自研平台最危险的旁路是运行时和外发路径：单一高权限 service account、source editor 过宽、secret 暴露到代码、Preview 自动等同 Download/Export、外部通知 payload 无 redaction。
5. 【建议】路线应按 P0/P1/P2 渐进：先把所有数据接触点纳入统一鉴权和审计，再做受控 unmarking、细粒度策略、recertification、policy drift 和 SDS 自动治理。

## 1. 现状缺口总览

| 能力域 | 现有调研基线 | 仍需建设 | 优先级 |
|---|---|---|---|
| Dataset Marking | 已有 #19 和 `dataset-permission-marking-architecture-summary.md` | 从 Dataset 扩展到 source/sync/transform/export 全链路 | P0 |
| Source / Connection | #51 确认 source edit 高危、source marking 传播 | Source、agent、credential、sync、webhook、external code 分权 | P0 |
| Credential / Secret | #51 确认 secret use/read/expose_to_code 应拆分 | credential 一等对象、runtime-use-only、rotation、last-used、external grants | P0 |
| Build runtime | #52 明确 author/reviewer/CI/runtime/schedule 分离 | principal chain、权限预检、producer ownership、schedule identity | P0 |
| Consumption / Export | #53 明确 query/download/export/API/stream 分权 | query-time PDP、download/export 独立权限、stream subscription ACL | P0 |
| Propagation | #54 明确 transaction/view requirement 快照 | P0 build-time materialization；P1 whyDenied、impact simulation 和大规模重算优化 | P0/P1 |
| Governance | #55 明确 access request/audit/lifecycle | TTL、break-glass、recertification、SIEM、policy drift | P1/P2 |
| Platform comparison | #56 提供 UC/Snowflake/BigQuery/Ranger/Atlas 映射 | 抽象成自研对象模型和 enforcement matrix | P0/P1 |

## 2. 目标架构

```text
Identity / IAM / Group Sync
  -> Principal & Entitlement Resolver
  -> Resource Catalog
       - Project / Source / Agent / Repo / Dataset / Stream / API / Export
  -> Credential & External Principal Service
  -> Dataset Version Store
       - Branch / Transaction / View / Stream Offset
  -> Policy Registry
       - Role / Marking / Organization / Classification / Row / Column / Export
  -> Lineage Graph & Requirement Propagation
  -> Policy Decision Point
  -> Enforcement Points
       - Source preview / Sync / Build / Query / Download / API / Stream / Export / Logs
  -> Approval & Access Request
  -> Audit / SIEM / Access Debugger
```

## 3. P0 建设清单

| P0 能力 | 要解决的问题 | 最小验收 |
|---|---|---|
| 统一对象模型 | source、dataset、stream、repo、job、credential、export 分散 | 每个对象有 RID、owner、resource role、marking/org requirements、audit id |
| Credential 一等对象 | secret 藏在连接配置里，无法分权和轮换 | `secret.admin`、`secret.use`、`secret.read/expose_to_code` 分开；默认 runtime-use-only |
| Source editor 严控 | source edit 等价外部账号高权限 | preview、run_sql、sync_create、agent_assign、import_to_code、export_enable 分权 |
| Build-time requirement propagation | query-time PDP 依赖已物化 requirements | Sync/Transform commit 前 resolve input branch/view/tx，计算并写入 `transaction_requirement`；无法计算时 fail closed |
| Query-time PDP/PEP | 不同入口各自判定，容易旁路 | preview/query/API/download/export/stream/log 统一调 PDP |
| Dataset/Stream version requirement | 最新权限覆盖历史事实 | transaction/view/stream offset 绑定 effective requirements |
| Build/runtime principal chain | 用平台服务账号跑任务缺归因 | 记录 actor、on_behalf_of、runtime_principal、credential、run、commit、tx |
| Runtime egress/export PEP | Transform 代码可能绕过正式 ExportPolicy 直接外发 | 默认禁止任意 HTTP 出站；外部写出必须绑定 destination、credential、export policy、payload/log/artifact redaction 和 audit |
| Export policy | Viewer 直接外发 | deny-by-default；allowed markings/orgs、destination credential、payload audit、RID/name 策略、粗粒度 redaction |
| 基础 audit + access request | 无法解释拒绝和追踪越权 | allow/deny、grant/revoke、marking apply/remove、export、secret use 全量审计；whyDenied 可发起申请 |
| Access decision snapshot | 事后不能回放当时权限 | group/marking/org membership snapshot、credential scope、policy version、transaction requirement version、decision inputs |

## 4. P1 建设清单

| P1 能力 | 要解决的问题 | 最小验收 |
|---|---|---|
| Protected unmarking | 脱敏后降权缺治理 | stop_propagating/stop_requiring 绑定 input/output/requirement/branch/approval |
| Project/service scoped schedule | user-scoped schedule 因人员失活中断 | schedule identity 可迁移、可审计、失活失权告警 |
| Access debugger | 权限拒绝不可解释 | getAccessRequirements、lineage permission coloring、missing requirements |
| External principal inventory | 外部账号权限漂移 | owner、external grants、last used、rotation、scope、risk level |
| Time-bound access | 临时权限长期存在 | TTL grant、自动过期、续期审批、last-used review |
| SIEM export | 审计无法进安全运营 | audit schema 稳定，high-risk export/break-glass/denied burst 可告警 |
| Impact simulation / debugger | 用户不知道加/移除 requirement 的影响 | lineage permission coloring、downstream impact、requirement recompute preview |

## 5. P2 建设清单

| P2 能力 | 要解决的问题 | 最小验收 |
|---|---|---|
| Restricted View / row policy | 需要行级/属性级访问 | row/property policy 叠加 Dataset requirements，不作为 transform input |
| Field-level export redaction | 外发字段粒度过粗 | download/webhook/Kafka/SIEM payload 字段策略 |
| Recertification | owner 不周期复核权限 | 按敏感等级配置 review cadence，未确认自动降权 |
| Break-glass 完整闭环 | 应急访问无事后控制 | 短 TTL、实时 SIEM、事后复盘、异常升级 |
| SDS 自动治理 | 敏感发现和打标靠人工 | scan -> apply marking / obfuscate / create issue / policy drift |
| Policy-as-code | 权限策略难 review | policy diff、branch review、approval、rollback |

## 6. 推荐落地顺序

1. **权限对象建模先行**：Resource、Credential、Policy、Requirement、Lineage、Audit 先立表和 API。
2. **先做 commit-time 保守传播**：Sync/Transform output 没有 `transaction_requirement` 就不能进入可消费状态。
3. **先封所有 PEP**：即使部分策略先返回 allow，也要让 source preview、sync、build、query、download、API、stream、export、logs 入口都走统一 PEP。
4. **先审计再自动化审批**：没有 access decision snapshot 就无法评估 access request、break-glass 和 recertification。
5. **先保守传播再受控降权**：source/input requirements 先默认继承到 output，再通过 protected unmarking 审批移除。
6. **外发能力最后放宽**：Transform runtime egress、download/export/webhook/Kafka/SIEM 先按 deny-by-default + allowlist 设计。

## 7. Runtime identity enforcement table

| 动作 | 权限检查主体 | 必查项 | 审计快照 |
|---|---|---|---|
| PR preview / branch build | triggering user + runtime principal | repo/build 权限、input read、output branch write、Markings/Organizations | actor、runtime_principal、branch、input view/tx、requirements |
| CI register / publish | CI principal + repo owner | repo owns output spec、CI 可 register、protected branch policy 通过 | ci_principal、repo、commit、job spec、ownership decision |
| Manual build | triggering user + runtime principal | user 可触发、output Dataset Editor、runtime 可读 inputs/写 output | triggered_by、runtime_principal、input tx、output tx、policy versions |
| Scheduled build | schedule identity + runtime principal | schedule scope、owner/service 未失权、runtime read/write | schedule_id、schedule_owner、effective principal、scope |
| Retry / backfill | original run policy + retrigger actor | retrigger actor 可操作；历史 config/credential/requirements 明确锁定 | original_run_id、retriggered_by、config version、credential version |
| Stream micro-batch | stream runtime principal | source/stream read、checkpoint owner、output write、requirement propagation | stream offset、checkpoint id、runtime principal、output transaction |
| Export job runtime | export runtime principal + destination credential | internal data read、export policy、destination credential、payload redaction | export job、dataset view/tx、destination、credential、allowed requirements |
| Webhook/notification dispatch | notification service principal | route policy、receiver/channel ownership、secret scope、payload redaction | alert/event id、route id、receiver、payload policy |

## 8. Enforcement ownership matrix

| Enforcement point | Owner service | Required collaborators |
|---|---|---|
| Source preview / SQL | Data Connection | Credential service、PDP、Audit |
| Sync commit | Sync runtime | Credential service、Lineage propagation、Dataset version store、Audit |
| Transform build | Build runtime | Code repo、Credential service、Lineage propagation、Dataset version store |
| Runtime egress | Build/runtime sandbox | Export policy、Credential service、Network policy、Audit |
| Query / preview / API | Query or serving gateway | PDP、Dataset version store、Audit |
| Download / export | Export service | PDP、Credential service、Redaction service、Audit |
| Stream subscribe | Stream serving service | PDP、Checkpoint service、Audit |
| Logs | Build/log service | Redaction service、Audit |
| Access request | Access request service | PDP whyDenied、Owner resolver、Audit |

## 9. 专家评审共识记录

| 专家 | 结论 | 必改项 | 已修订证据 | 残余风险 |
|---|---|---|---|---|
| Data Integration 架构专家 | Pass | 第一轮要求修正 build-time propagation 优先级、Transform runtime egress、source capability 和 export/redaction P0 | #51/#52/#54/#57 已修订并复审通过 | Stream hot path、secret runtime 隔离、export connector 行为需后续实测 |
| 安全治理专家 | Pass | 初稿把 export 写得像 read extension，需改为跨边界策略 | #51/#53/#55 已补 exportable markings、destination credential、payload redaction、audit | PagerDuty/webhook/email payload 仍待 connector 验证 |
| 平台工程专家 | Pass | 第一轮要求修正 propagation P0、runtime identity enforcement、audit snapshot、service ownership | #52/#54/#55/#57 已修订并复审通过 | PDP schema、retry/backfill 历史语义和大规模 requirement recompute 需单独设计 |
| 运维与合规专家 | Pass | 初稿 audit 字段不足，缺 break-glass/recertification | #55 已补 audit schema、审批矩阵、TTL、SIEM、recertification | audit.3/user directory enrichment 需自研 identity snapshot |

**当前评审结论：** 第一轮未全部通过，已按阻塞问题修订；Data Integration 架构专家和平台工程专家复审均为 Pass，四类专家已形成共识。残余风险均进入后续 issue 候选，不阻塞本轮路线图结论。

## 10. 残余风险与后续 issue 建议

| 风险 | 状态 | 后续建议 |
|---|---|---|
| Stream hot path 权限、checkpoint、reset、export sink 权限未实测 | Open | 新建 Stream 权限实测 Story |
| Data Connection secret exposure to code 的具体隔离和 redaction 未公开 | Open | 新建 Secret runtime / code import PoC |
| Export connector payload、retry、partial success、schema mismatch 行为不同 | Open | 按 connector 建 export safety matrix |
| policy propagation 在大规模 lineage 下的重算成本未知 | Open | 设计 requirement propagation service benchmark |
| 外部 IAM/ITSM 与 access request 同步边界未定 | Open | 设计 approval integration contract |

## 11. Source Documents

- `docs/raw/50-data-integration-permission-source-map.md`
- `docs/raw/51-ingestion-connection-credential-permission-boundary.md`
- `docs/raw/52-transform-runtime-build-permission-boundary.md`
- `docs/raw/53-consumption-export-access-control.md`
- `docs/raw/54-lineage-marking-policy-propagation-model.md`
- `docs/raw/55-permission-governance-audit-lifecycle.md`
- `docs/raw/56-open-platform-permission-comparison.md`
- `docs/synthesis/dataset-permission-marking-architecture-summary.md`
