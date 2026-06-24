# Palantir Integration 对象权限表达与 RBAC 授权矩阵

**关联 Issue：** #71
**调研日期：** 2026-06-25
**范围：** Palantir Foundry Data Connection / Data Integration 相关对象，延伸到 Dataset、Transform、Export、Ontology 消费路径中与集成权限直接相连的控制点。

## 摘要与洞察

1. 【事实】Palantir 的 Integration 权限不是单一 RBAC；默认表达是 `Resource role / operation` 与 `Organization / Marking / Classification / lineage-derived data requirements` 叠加，角色不能绕过 Marking。
2. 【事实】Data Connection 的 `Agent`、`Source`、`Sync`、`Plugin/JDBC Driver`、`Webhook`、`External connection from code` 都是 Foundry resources，可放入 Project/folder 并继承角色、Organizations 和 Markings。
3. 【事实】`Source Editor` 是接入侧最高风险默认角色之一：它可改 source 配置、改 assigned agents、创建/编辑 sync、运行数据库 SQL、preview/explore source、share source，并可 import source to code resource。
4. 【推断】Palantir 的 RBAC 实际落点是“role 包含 operation，operation 由应用在具体资源动作上检查”；Data Integration 自研时不应只复刻 Owner/Editor/Viewer，而应拆出 preview、run_sql、sync_config、sync_run、secret_use、code_import、export_enable 等 capability-level permissions。
5. 【建议】授权矩阵应按对象分层：连接/凭据/运行/输出/外发/治理分开授权；默认 deny 外发与 secret 明文读取，所有 source preview、sync、build、query、download、export、webhook、logs 入口都写 access decision snapshot。

## 1. 权限表达总模型

Palantir Foundry 对 Integration 相关对象的权限表达可抽象为：

```text
can_perform(user, action, resource_or_data_version) =
    has_resource_role_or_operation(user, resource, action)
AND satisfies_organization_requirements(user, resource_or_data_version)
AND satisfies_marking_requirements(user, resource_or_data_version)
AND satisfies_classification_requirements(user, resource_or_data_version)
AND satisfies_lineage_derived_data_requirements_if_reading_data(user, data_version)
AND satisfies_action_specific_policy(user, action, destination_or_runtime)
```

其中 RBAC 只解决第一项：用户在某个 resource 上是否有某个 operation。Foundry 官方文档把 roles 定义为 permissions/operations 的集合；默认角色从高到低包括 `Owner`、`Editor`、`Viewer`、`Discoverer`，并可通过 custom roles 改写。角色通常授予在 Project 层，向 folder/file/resource 子级继承。

强制访问控制与 RBAC 正交：

- `Organization`、`Marking`、`Classification` 是 access requirements，不是 role。
- 用户必须满足所有适用 Markings；普通 Marking 语义是 all-of。
- Marking/Organization 会沿文件层级和数据血缘传播。
- `stop_propagating` / `stop_requiring` 只用于 Marking/Organization 传播中断，不用于 role 传播。

## 2. 默认角色与操作语义

| 角色 / 主体 | 权限表达 | 默认授权语义 | Integration 相关风险 |
|---|---|---|---|
| `Owner` | 资源最高默认 role，通常继承 `Editor` | 可管理资源和授权；在 source 上可修改 export configuration、允许 source import to code；在 agent 上可重下 agent 或 regenerate token | Owner 不等于可绕过 Marking；source owner 管 export 仍受 unmarking / ISO 条件约束 |
| `Editor` | 可修改资源的默认 role | 对 agent/source/code repo/dataset 等执行编辑、配置、运行或删除类动作 | 在 source 上过宽，接近外部账号能力；在 repo 上可能通过 code 使用 imported source secrets |
| `Viewer` | 资源查看 role | 查看配置、状态、metadata；读取数据还需满足 data requirements | Source Viewer 可看 source config 和 assigned agents，不应被当作普通数据消费授权 |
| `Discoverer` | 低权限发现 role | 可发现资源存在，通常不能读取内容 | 对敏感 source/dataset 仍受 file Marking/Organization 限制 |
| Custom role | role = operations 集合 | 管理员可把单个 operation 加到默认或自定义 role | Webhook full history 依赖 `webhooks:read-privileged-data` 这类 operation |
| `Information Security Officer` | Enrollment-level / platform security role | 可在 source export configuration 中 enable exports；添加 exportable markings/orgs 还需对应 unmarking permission | 外发治理角色，不应与 Source Editor 混同 |
| Marking member | eligibility，不是 resource role | 满足某类敏感数据 access requirement | 有 Marking 资格不代表有 Project/Dataset Viewer |
| Marking/Organization approver | marking/org 特定高危权限 | 对 Marking/Organization 移除、传播中断或扩大访问进行审批 | 与数据读取资格应分离，避免审批人天然可读数据 |
| Runtime / service principal | 执行身份 | sync/build/export/webhook/audit export 的 effective principal | 必须记录 human actor、on_behalf_of、runtime principal、credential scope |

## 3. Integration 对象权限矩阵

| 对象 | 配置的权限 / 要求 | 权限点如何定义 | 默认授权给哪些角色 / 主体 |
|---|---|---|---|
| `Project` / folder | role grants；Organization；Marking；Classification | 资源容器；roles 和 access requirements 向子资源继承 | `Owner` 可授权同级或更低角色；`Editor` 可编辑范围内资源；`Viewer` 可查看；`Discoverer` 可发现。Organization/Marking 由治理主体授予资格 |
| `Agent` | `Owner` / `Editor` / `Viewer`；Project role；Organizations/Markings | 连接运行位置和网络路径。`Editor` 可 deploy source 到 agent、配置 plugins/configs、restart agent、share、delete；`Viewer` 看配置和状态；`Owner` 可重下 agent 或 regenerate token | Agent 创建需要所在 Project `Editor`；管理 agent 通常需要 Project `Owner`。部署 source 到 agent 需要 agent `Editor` |
| `Source` / `DataConnection` | `Owner` / `Editor` / `Viewer`；assigned agents；allowed capabilities；Organizations/Markings；export configuration | 外部系统连接实例，包含 endpoint、worker/network、credentials。`Editor` 可 delete、更新配置、改 assigned agents、rename、创建/编辑/删除 sync、运行 SQL、share、explore/preview、import to code。`Viewer` 看配置。`Owner` 继承 Editor，并可修改 export configuration、允许 import to code | `Owner` / `Editor` / `Viewer` 直接授在 source 或父 Project。改 assigned agents 还需被添加 agent 的 `Editor`。source editor 只应授予可信 pipeline developer |
| `Credential` / `Secret` | secret admin/use/read/expose-to-code（公开文档未完整披露内部 ACL） | 用于 source authentication，可是 password、token、API key、OIDC、cloud identity。Palantir 说明 secrets 加密存储；source import to code 后 repo editor 可通过代码使用 connection details，包括 secret values | 【推断】默认应只让 runtime `use`，不授明文 `read`。source import to code 由 source `Editor` 触发；code repo `Editor` 可写代码接触 imported connection details |
| `ExternalSystemPrincipal` | external grants；scope；rotation owner；source binding | 外部 DB user、cloud IAM role、OAuth client 或 service account。平台权限不能替代外部系统最小授权 | 外部系统管理员授予；平台侧应由 source owner/security 记录 owner、scope、last_used、rotation |
| `Sync` / `SyncJob` | 派生自 source 和 output dataset | View sync = source `View` + output dataset `View`；Edit/Delete sync = source `Edit` + output dataset `Edit`; Run sync = output dataset `Edit` | 不是单独默认 role；由 source role 与 output dataset role 组合派生。自研建议把 `sync.run` 与 `sync.edit_config` 再拆开 |
| `Plugin` / JDBC Driver | `Owner` / `Editor` / `Viewer`；agent attachment | `Viewer` 可 view/download，并可 add plugin to agent；add 还需 agent `Editor`。`Editor` 可 delete plugin/driver，前提是未被 agents 使用。`Owner` 继承 Editor | Plugin/driver role 直接授予或从 Project 继承；add-to-agent 组合检查 plugin `Viewer` + agent `Editor` |
| `Webhook` | 完全继承关联 source 权限；可额外授 `webhooks:read-privileged-data` | View/Create/Edit/Delete/configure Action/Execute Webhook 都要求 source 对应 View/Edit。默认只有执行者可看自己的 response history；full request/response history 需要额外 operation | source `Viewer` 可看 webhook config；source `Editor` 可创建、编辑、删除、配置 Action、执行。`webhooks:read-privileged-data` 建议放入专门 custom role，如 `Webhook Privileged Data Viewer` |
| External connection from code | source import permission；code resource editor；repo/build role | Import source into transform/pipeline/compute module requires source `Editor`。触发使用 imported source 的 build 只需 code resource `Editor`，不再要求 source 权限。移除 imported source 需要 source `Editor` 或 code resource `Editor` | source `Editor` 是 import gate；repo/code resource `Editor` 是代码使用与 build gate。高危点是 repo editor 可写代码访问 secret values |
| Export configuration / ExportPolicy | enable exports；exportable markings/orgs；destination credential write scope | 目标 source 必须 enable exports，并配置允许外发的 Markings/Organizations；未列入的 markings/orgs 数据会 fail export。添加 exportable marking/org 需要 `Information Security Officer` 且具备对应 unmarking permission。目标 credential 还需外部写权限，如 S3 `PutObject` 或表 truncate/insert | `Information Security Officer` 执行 enable/exportable scope；source owner 可修改 export config 但仍受 marking/org unmarking 条件约束；export runtime 使用 destination credential |
| Export job | internal read + export policy + destination write | 不是 Dataset Viewer 的自然延伸；必须同时满足内部 dataset/stream 读取、target source exportable scope、destination credential write、payload/redaction policy | 【建议】自研拆成 `export.create`、`export.run`、`export.manage_policy`、`export.view_history`，不要把它们并入 source `Editor` 或 dataset `Viewer` |
| Output `Dataset` / transaction / view | resource role；file requirements；lineage-derived data requirements；branch/view/transaction requirements | `Viewer` 只表示可尝试查看资源；读 view 数据还需满足上游继承 Markings/Organizations/Classifications。用户可能能看 metadata 但不能读 data | Project/Dataset `Viewer` + 所有 Marking/Org eligibility。`Editor` 常用于写 output dataset / run sync/build。Marking 资格由 Marking admin 或数据治理授予 |
| `Stream` / streaming sync output | stream resource role；data requirements；consumer group/checkpoint ACL（公开细节不足） | streaming sync 写入 stream；hot subscription 是持续消费，不应等同一次 dataset read | 【待验证】Palantir hot stream 权限细节未完整公开。自研建议拆 `stream.subscribe`、`stream.reset_checkpoint`、`stream.export_sink` |
| `Code Repository` / Transform contract | repo role；branch protection；PR reviewer；CI publish/register；output dataset ownership | 代码编辑、PR review、protected branch merge、CI register、manual build、scheduled build 分属不同主体。Build 需要 input read、output write、runtime principal 合规 | repo `Editor` 可写代码和触发 build；protected branch 政策要求 reviewer/approver；CI principal 负责 register；output dataset `Editor` / owner 约束写入 |
| `Schedule` / scheduled build | schedule owner/identity；target scope；runtime principal | 调度触发 build 时需要 schedule identity 未失权，runtime 能读 inputs、写 outputs，并满足 Markings/Organizations | 【推断】生产应优先 service/project scoped identity；user-scoped schedule 应做失活/失权告警 |
| Ontology Object Type / Object / Property | project-based ontology resource role；backing datasource access；object/property policy | Object Type schema 可由 project role 控制；要看 object instances，还需 backing datasource access 或 object/property security policy。Object policy 控制实例，Property policy 控制属性值 | Object type `Viewer` 可看类型；看对象需 object type `Viewer` + datasource `Viewer` 或相应 object/property security policy |
| Audit logs / audit export dataset | audit export operations；dataset marking；Organization | Audit logs 回答 who/what/when/where，内容可能含 PII 和敏感 usage data。导出 audit.3 需要 `audit-export:orchestrate-v3`；SIEM API 读取需要 `audit-export:view` | Organization administrator 可授相关 audit export operation；导出的 audit dataset 应加 Organization/Marking，仅给安全运营和合规人员 |

## 4. 关键权限点定义

### 4.1 接入连接侧

| 权限点 | 定义 | Palantir 默认归属 | 自研拆分建议 |
|---|---|---|---|
| `connection.view_config` | 查看 source 配置、assigned agents、状态 | source `Viewer` | 保留为低风险配置查看，但隐藏 secret |
| `connection.preview_data` | explore/preview source 中的数据 | source `Editor` | 从 `Editor` 拆出，按源数据敏感要求单独授权 |
| `connection.run_sql` | 在数据库 source 上执行 SQL | source `Editor` | 单独高危权限，限制 DDL/DML 或加审批 |
| `connection.manage_agent_assignment` | 改 source assigned agents / worker path | source `Editor` + agent `Editor` | 单独授权，防止扩大网络路径 |
| `connection.manage_sync_config` | 创建、编辑、删除 sync | source `Editor` + output dataset `Editor` | 拆为 create/edit/delete；高危修改需 review |
| `connection.import_to_code` | 将 source 导入 code resource | source `Editor`，source `Owner` 可允许 import | 高危审批；绑定 repo、branch、runtime egress policy |
| `secret.use` | runtime 注入 secret，不暴露明文 | 公开文档未完整披露 | 默认允许 sync/build/export runtime use |
| `secret.read` / `secret.expose_to_code` | 代码或调试路径读取 secret value | imported source + repo `Editor` 可通过代码访问 | 默认禁止；仅审批后短期开放并强审计 |

### 4.2 运行与构建侧

| 权限点 | 定义 | Palantir 默认归属 | 自研拆分建议 |
|---|---|---|---|
| `sync.view` | 查看 sync 配置 | source `View` + dataset `View` | 同步继承即可 |
| `sync.edit` / `sync.delete` | 修改或删除 sync | source `Edit` + dataset `Edit` | 与 `sync.run` 分离 |
| `sync.run` | 执行同步，写 output dataset | output dataset `Edit` | 增加 source/config/credential version 快照 |
| `build.trigger` | 手工触发 build / preview | code resource `Editor`、output dataset `Editor`、input read requirements | 明确 triggering actor 与 runtime principal |
| `ci.publish` / `contract.register` | 注册 Transform/job spec | CI principal + repo/output ownership | 禁止作者 token 直写生产 spec |
| `schedule.run` | 调度触发生产 build | schedule identity + runtime principal | service-scoped 优先，user-scoped 做失权检测 |
| `runtime.egress` | transform/build/webhook 对外调用 | 与 source/export/webhook policy 相关 | 默认 deny；必须绑定 destination、credential、export policy |

### 4.3 消费、外发与治理侧

| 权限点 | 定义 | Palantir 默认归属 | 自研拆分建议 |
|---|---|---|---|
| `dataset.view_metadata` | 打开资源、看 schema/history 等 metadata | Dataset/Project `Viewer`，还需 file requirements | 与 data read 分开 |
| `dataset.read_view` | 读取 branch/view/transaction 数据 | Dataset `Viewer` + data requirements | 服务端统一 PDP/PEP |
| `dataset.download` | 下载文件或查询结果 | 官方公开细节不足 | 独立于 preview/query，强 audit + purpose |
| `export.enable_source` | 允许 source 作为导出目的地 | `Information Security Officer` | 与 source edit 分离 |
| `export.manage_allowlist` | 配置 exportable markings/orgs | ISO + corresponding unmarking permission | 单独审批，记录 policy version |
| `webhook.execute` | 调用外部 webhook | source `Editor`；通过 Action 执行另有 Action 权限 | 单独路由策略、payload redaction、secret scope |
| `webhook.read_full_history` | 看所有 request/response history | `webhooks:read-privileged-data` operation | 专门 custom role |
| `audit.export` | 导出 audit logs | `audit-export:orchestrate-v3` 或 `audit-export:view` | 专用安全运营角色，导出 dataset 加 marking |
| `marking.stop_propagating` | 在 protected branch 上移除 inherited Marking | 需要 Marking 相关 remove/unmarking permission 和审批 | 绑定 input/output/requirement/branch/approval |
| `organization.stop_requiring` | 在 protected branch 上移除 inherited Organization requirement | 需要 `Expand access` 类权限和审批 | 绑定跨组织共享依据与审计 |

## 5. 授权模式建议

### 5.1 最小角色包

| 建议角色包 | 包含权限 | 不应包含 |
|---|---|---|
| Connection Viewer | `connection.view_config`、source status | preview、run_sql、secret_read、sync_edit、export_enable |
| Source Operator | `sync.run`、查看运行历史 | 改 source endpoint/credential、run_sql、import_to_code |
| Source Developer | preview、explore、sync create/edit | export enable、secret_read、code import、agent reassignment |
| Agent Manager | agent configure/restart/plugin attach | source preview、dataset read、export policy |
| Secret Administrator | secret create/rotate/bind | dataset read、source preview、code secret exposure |
| Pipeline Developer | repo edit、branch build、output write in dev scope | protected branch bypass、unmarking approval、external egress |
| Export Administrator | export job config、destination binding | exportable marking allowlist approval |
| Information Security Officer | export enable、exportable scope approval | 普通 source edit 或 dataset write |
| Webhook Privileged Data Viewer | `webhooks:read-privileged-data` | webhook execute、source edit |
| Audit Operator | audit export/read | broad project Owner、source Editor |

### 5.2 授权校验最小快照

每次关键动作至少记录：

```text
actor_user
groups_snapshot_id
resource_id
resource_role_or_operation
action
decision
missing_requirements
source_config_version
credential_id / credential_scope_version
external_principal
branch / view / transaction_id
marking_membership_snapshot_id
organization_membership_snapshot_id
export_policy_id
runtime_principal
trace_id
timestamp
```

## 6. 设计结论

1. 【结论】Integration 权限主轴不是“Source ACL”，而是 source / credential / sync / code import / output dataset / export policy / audit 的分层授权。
2. 【结论】默认 `Source Editor` 聚合了太多高危 operation；自研平台应拆成 capability-level permissions，并把 source preview、run SQL、code import、export enable 单独审批。
3. 【结论】RBAC 只能表达“能执行什么操作”，不能表达“是否有资格接触某类数据”；Marking/Organization/Classifications 必须作为强制要求参与每个数据读写与外发决策。
4. 【结论】外发链路必须独立建模。Dataset Viewer、Source Editor 或 Pipeline Developer 都不应天然获得 download/export/webhook/Kafka/SIEM 外发权。
5. 【结论】审计应记录 access decision snapshot，而不是只记录 grant/revoke；否则无法证明某人某时刻读取了哪版数据、满足了哪些 Marking/Organization、用了哪个 credential 和 runtime principal。

## 7. 证据边界

1. 【待验证】Palantir 未公开 Data Connection secret ACL、runtime 解密、source import 后 secret redaction 与 audit event schema 的完整内部结构。
2. 【待验证】Schedule identity、build runtime effective principal、CI publish principal 的精确内部映射未公开。
3. 【待验证】Stream hot subscription、consumer group/checkpoint reset、stream export sink 的默认角色矩阵未完整公开。
4. 【待验证】Download/export 的字段级 redaction、水印、purpose justification 是否按产品/环境可配置，需要具体租户验证。
5. 【说明】Palantir 文档提示 default permission behavior 可能被 custom roles 改写；本文矩阵以公开默认行为为基线。

## 8. 来源

- Palantir Data Connection permissions: <https://www.palantir.com/docs/foundry/data-connection/permissions>
- Palantir Data Connection core concepts: <https://www.palantir.com/docs/foundry/data-connection/core-concepts>
- Palantir Data Connection exports: <https://www.palantir.com/docs/foundry/data-connection/export-overview>
- Palantir Projects and roles: <https://www.palantir.com/docs/foundry/security/projects-and-roles>
- Palantir Manage roles: <https://www.palantir.com/docs/foundry/platform-security-management/manage-roles>
- Palantir Markings: <https://www.palantir.com/docs/foundry/security/markings/>
- Palantir Checking permissions: <https://www.palantir.com/docs/foundry/security/checking-permissions/>
- Palantir Remove inherited Markings and Organizations: <https://www.palantir.com/docs/foundry/building-pipelines/remove-inherited-markings>
- Palantir Ontology permissions: <https://www.palantir.com/docs/foundry/object-permissioning/ontology-permissions>
- Palantir Managing object security: <https://www.palantir.com/docs/foundry/object-permissioning/managing-object-security>
- Palantir Audit logs: <https://www.palantir.com/docs/foundry/security/audit-logs-overview>
- `docs/raw/50-data-integration-permission-source-map.md`
- `docs/raw/51-ingestion-connection-credential-permission-boundary.md`
- `docs/raw/52-transform-runtime-build-permission-boundary.md`
- `docs/raw/53-consumption-export-access-control.md`
- `docs/raw/54-lineage-marking-policy-propagation-model.md`
- `docs/raw/55-permission-governance-audit-lifecycle.md`
- `docs/synthesis/data-integration-permission-system-roadmap.md`
- `docs/synthesis/dataset-permission-marking-architecture-summary.md`
