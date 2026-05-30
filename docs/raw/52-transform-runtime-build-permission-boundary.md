# 52 - Transform / Pipeline 构建运行时权限边界调研

**所属 Epic：** #49
**对应 Story：** #52
**类型：** Story 调研 / Transform、Code Repository、Build、Schedule 权限边界
**调研日期：** 2026-05-31

## 摘要与洞察

1. 【事实】Foundry Code Repositories 将 PR review、protected branch、`ci/foundry-publish`、security approval 和 impact analysis 绑定在代码发布入口；protected branch 只能通过 PR 修改。
2. 【事实】required reviewer 被指定并不自动获得 PR review 权限；reviewer 仍需要 Code Repository 访问权限。
3. 【推断】构建链路需要独立建模六类主体：代码作者、reviewer/approver、CI/register runner、build runtime identity、schedule identity、Dataset owner/downstream reader。
4. 【建议】自研平台 P0 必须建立 principal chain、权限预检、output producer 唯一性、build/run history 和 schedule identity 治理，避免用单一高权限 service account 跑全部生产任务。
5. 【待验证】Palantir 未公开 `ci/foundry-publish` 的底层 runner 身份、token 生命周期和 job spec register 精确权限模型。

## 1. 构建 / 运行时权限矩阵

| 阶段 / 动作 | 主体 | 应具备权限 | 门禁 / 审批 | 产物与审计 | 自研边界建议 |
|---|---|---|---|---|---|
| 代码编辑 | Author | Code Repository read/write；feature branch 写权限 | protected branch 禁止直改 | commit、branch diff | repo write 不等于生产发布权 |
| PR review | Reviewer / Approver | repo access；如审查 data impact，还需 Dataset read + Markings | required review、no rejection、specific reviewer/group、advanced approval | review record、approval status | 被指定 reviewer 与实际有权查看代码/数据分开校验 |
| Protected branch merge | Merger | 通常 Owner/Editor 可 merge，但受 branch policy 约束 | CI、code review、security approval | merge commit、publish result | merge 权限不能绕过安全审批 |
| Contract register / CI publish | CI runner | 注册 Transform/Job spec 的平台权限；校验 output ownership | `ci/foundry-publish` 成功 | check run、registration result、job spec provenance | 使用受控 CI principal，禁止作者 token 直写生产 job spec |
| 手工 build / preview | Triggering user | output Dataset Editor；inputs read + Markings | branch/fallback branch、quality checks | build report、History、logs、transactions | build 是编辑输出数据，必须独立鉴权 |
| Runtime read/write | Runtime effective identity | input read、output write、Marking/Organization 合规 | Data Expectations、requirement propagation | input transaction range、output transaction id | 记录 trigger actor 与 runtime principal |
| Runtime egress / external call | Runtime effective identity + destination policy | destination resource、destination credential、export policy、network egress allowlist | deny-by-default、payload/log/artifact redaction、external package approval | egress audit、payload class、destination id | 防止 Transform 代码绕过 ExportPolicy 直接外发 |
| Scheduled build | Schedule identity | project scope 或 user on-behalf-of 权限 | trigger、scope、retry、force/staleness | schedule run history、build attempts | 生产优先 project/service scoped；user-scoped 要失活告警 |
| Output Dataset ownership | Repository / Dataset owner | 单一 producer repo 控制 output job spec | ownership transfer | sourceProvenance、job spec owner | output producer 唯一，迁移显式 tombstone |
| Downstream read | Consumer user/service | output role + inherited Markings/Organizations | Marking propagation / unmarking approval | access audit、lineage permissions | 下游读权限不由作者直接授予 |
| Logs / run history | Operator / auditor | logs viewer、audit export 权限 | retention、sensitive log marking | job logs、Workflow Lineage、audit logs | 日志可能含敏感数据，权限应独立于 Dataset read |

## 2. 权限分离模型

```text
Author
  -> Pull Request
  -> Reviewer / Security Approver
  -> CI / Register Runner
  -> Build Trigger
  -> Runtime Effective Principal
  -> Output Dataset Transaction
  -> Downstream Reader
```

关键分离点：

- Author 可写代码，不自动拥有 output Dataset write 或 downstream read。
- Reviewer 可审代码，不自动具备受影响 Dataset 数据权限。
- CI 成功只说明 contract/register 门禁通过，不代表生产 schedule identity 一定可 build。
- User-scoped schedule 依赖最后创建/编辑 schedule 的用户；该用户失活或失权会导致生产 build 失败。
- Output Dataset 需要唯一权威 producer；多个 repo 竞争同一 output 是发布所有权冲突。
- Downstream read 由 output Dataset role、Markings 和 lineage data requirements 决定。

## 3. 自研平台建设建议

| 优先级 | 建设项 | 说明 |
|---|---|---|
| P0 | Principal chain | 记录 requested_by、approved_by、triggered_by、on_behalf_of、runtime_principal、schedule_owner、dataset_owner |
| P0 | 权限预检 API | repo write、PR review、CI register、output write、input read、marking eligibility、schedule scope 分开返回 |
| P0 | Protected branch + PR | 生产分支必须支持 CI、reviewer、owner/security approval |
| P0 | Output producer 唯一性 | CI register 时检测 ownership conflict |
| P0 | Build/run history | 记录 commit、branch、contract version、input/output tx、runtime principal、schedule id、logs |
| P0 | Runtime egress/export PEP | Transform runtime 默认禁止任意 HTTP 出站；外部写出必须绑定 destination、credential、export policy、payload/log/artifact redaction 和 audit |
| P1 | Project/service scoped schedule | 减少 user-scoped schedule 对个人账号依赖 |
| P1 | Dataset owner / steward 审批 | 新增输出、删除输出、质量规则、marking 降级、破坏性 schema 变更触发 review |
| P1 | PR impact analysis | 展示 affected datasets、derived datasets、staleness、inaccessible、fallback branch |
| P1 | 日志权限分层 | 作者调试日志、运行日志、审计日志、敏感日志导出分别授权 |
| P2 | on-behalf-of service account | 短期 delegated token、最小权限、可撤销、可审计 |
| P2 | Schedule/run 异常治理 | 账号失活、失权、scope drift、fallback branch、force build、retry exhaustion |
| P2 | 安全标签传播审批 | stop propagation 必须走 protected branch + security reviewer |

## 4. Runtime identity enforcement table

| 动作 | 权限检查主体 | 必查项 | 审计快照 |
|---|---|---|---|
| PR preview / branch build | triggering user + runtime principal | user 有 repo/build 权限；runtime 有 input read/output branch write；满足 Markings/Organizations | actor、runtime_principal、branch、input view/tx、output branch、requirements |
| CI register / publish | CI principal + repo owner | repo owns output spec；CI principal 可 register；protected branch policy 通过 | ci_principal、repo、commit、job spec、ownership decision |
| Manual build | triggering user + runtime principal | triggering user 可触发；output Dataset Editor；runtime 可读 inputs/写 output | triggered_by、runtime_principal、input tx、output tx、policy versions |
| Scheduled build | schedule identity + runtime principal | schedule scope 覆盖 target；schedule owner/service 未失权；runtime 具备 read/write | schedule_id、schedule_owner、effective principal、scope、retry/backfill flag |
| Retry / backfill | original run policy + retrigger actor | retrigger actor 可操作；使用哪个历史 config/credential/requirements 明确锁定 | original_run_id、retriggered_by、config version、credential version |
| Stream micro-batch | stream runtime principal | source/stream read、checkpoint owner、output write、requirement propagation | stream offset、checkpoint id、runtime_principal、output transaction |
| Export job runtime | export runtime principal + destination credential | user/source data read、export policy、destination write credential、payload redaction | export_job、dataset view/tx、destination、credential、allowed requirements |
| Webhook/notification dispatch | notification service principal | route policy、receiver/channel ownership、secret scope、payload redaction | alert/event id、route id、receiver、payload policy |

## 5. Service ownership by enforcement point

| Enforcement point | Owner service | Required collaborator |
|---|---|---|
| Source preview / SQL | Data Connection service | Credential service、PDP、Audit |
| Sync commit | Sync runtime | Credential service、Lineage propagation、Dataset version store、Audit |
| Transform build | Build runtime | Code repo service、Credential service、Lineage propagation、Dataset version store |
| Runtime egress | Build/runtime sandbox | Export policy、Credential service、Network policy、Audit |
| Query / preview / API | Query or serving gateway | PDP、Dataset version store、Audit |
| Download / export | Export service | PDP、Credential service、Redaction service、Audit |
| Stream subscribe | Stream serving service | PDP、Checkpoint service、Audit |
| Logs | Build/log service | Redaction service、Audit |
| Access request | Access request service | PDP whyDenied、Owner resolver、Audit |

## 6. 风险与证据缺口

1. 【待验证】`ci/foundry-publish` runner 身份、token 生命周期、job spec 写入权限未公开。
2. 【待验证】Build trigger user、schedule on-behalf-of user 与 runtime effective principal 的映射未完整公开。
3. 【待验证】Workflow Lineage、Builds、Data Lineage、audit logs 是否有统一 correlation id 未公开。
4. 【风险】若自研平台用单一超级 service account 跑全部 build，会丢失责任归因，并绕过最小权限。
5. 【风险】只做代码 PR，不做 Dataset ownership、Marking propagation、schedule identity 校验，会在合并后暴露生产失败或敏感传播问题。
6. 【风险】若 runtime 允许任意 HTTP 出站、外部包或日志外传，就可能绕过正式 ExportPolicy。

## 7. 来源

- Palantir Code Repositories branch settings: <https://www.palantir.com/docs/foundry/code-repositories/branch-settings>
- Palantir Remove inherited Markings: <https://www.palantir.com/docs/foundry/building-pipelines/remove-inherited-markings>
- Palantir Markings: <https://www.palantir.com/docs/foundry/security/markings>
- `docs/raw/23-code-repositories-engineering-entry.md`
- `docs/raw/25-transform-contract-dag.md`
- `docs/raw/26-pro-code-governance-quality-observability.md`
- `docs/raw/27-incremental-scheduling-transaction.md`
- `docs/raw/35-ai-fde-governance-branching.md`
- `docs/synthesis/palantir-pro-code-capability-research.md`
