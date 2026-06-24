# Palantir Integration 对象权限表达与 RBAC 授权矩阵

**关联 Issue：** #71
**调研日期：** 2026-06-25
**范围：** Palantir Foundry Data Connection / Data Integration 相关对象，延伸到 Dataset、Transform、Export、Ontology 消费路径中与集成权限直接相连的控制点。

## 摘要与洞察

1. 【事实】Palantir 的 Integration 权限不是单一 RBAC；默认表达是 `Resource role / operation` 与 `Organization / Marking / Classification / lineage-derived data requirements` 叠加，角色不能绕过 Marking。
2. 【事实】Palantir 的 role 是 operation 的集合；operation 是应用检查的单个权限点，具有 name 和 unique identifier。公开示例包括 Code Repository 的 `stemma:mutate-default-branch`，但 Data Connection 多数细项只公开了角色行为，未公开 operation identifier。
3. 【事实】Data Connection 的 `Agent`、`Source`、`Sync`、`Plugin/JDBC Driver`、`Webhook`、`External connection from code` 都是 Foundry resources，可放入 Project/folder 并继承角色、Organizations 和 Markings。
4. 【事实】`Source Editor` 是接入侧最高风险默认角色之一：它可改 source 配置、改 assigned agents、创建/编辑 sync、运行数据库 SQL、preview/explore source、share source，并可 import source to code resource。
5. 【事实】Palantir 公开且命名的 Integration 相关 scope/operation 包括 `webhooks:read-privileged-data`、`audit-export:view`、`audit-export:orchestrate-v3`，以及 OAuth/API 的 operation scopes；export enable 由 `Information Security Officer` role 和 unmarking permission 共同约束。

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

## 2. Palantir 官方权限规划与 scope 层次

本节只列 Palantir 公开文档能直接支持的规划和 scope；不把自研建议伪装成 Palantir 内部设计。

| 层次 | Palantir scope / 权限规划 | 授权给哪些角色 / 主体 | Integration 落点 | 公开边界 |
|---|---|---|---|---|
| Resource role scope | `Owner`、`Editor`、`Viewer`、`Discoverer` 是默认角色；role grant 通常在 Project 层授予，并继承到 child resources | 同级或更高 role 可授予相同或更低 role；默认可 custom | Agent、Source、Dataset、Code Repository、Developer Console application 等 Foundry resources | 默认角色的精确 operation 列表未全部公开，且环境可用 custom roles 改写 |
| Operation scope | operation 是单个应用权限点，有 name 和 unique identifier；role 是 operation 集合 | Organization administrator 可在 Foundry Settings / Roles 管理 custom role set 和 operation | 公开示例：Code Repository 的 `stemma:mutate-default-branch` | Data Connection 的 preview、run SQL、sync edit 等 operation identifier 未公开 |
| Data Connection resource scope | agents、sources、syncs、plugins、webhooks、external connections from code 都作为 resources 管理 | 默认按资源 role 授权：Owner / Editor / Viewer | Data Connection 的核心权限面 | 官方强调这些是默认权限，custom roles 可能改变行为 |
| Source capability scope | Source `Editor` 聚合 delete、agent assignment、configuration update、sync create/edit/delete、SQL query、share、explore/preview、import to code | Source `Editor`；部分动作还要求 agent `Editor` 或 output dataset `Editor` | Source 是外部系统账号能力的代理 | 公开文档没有把这些 capability 拆成独立 operation identifiers |
| Webhook privileged history scope | `webhooks:read-privileged-data` | 可加入 custom 或 default role；官方推荐新建 `Webhook Privileged Data Viewer` role | 查看可访问 webhook 的 full request/response history | webhook CRUD/execute 仍继承 source View/Edit |
| Export security scope | export target source 必须 enable exports；配置 exportable markings/orgs | `Information Security Officer` role；添加 exportable marking/org 还需对应 unmarking permission | Dataset/Stream 向外部系统导出 | 外部 credential 还必须有目标系统写权限；export job 具体 role matrix 公开不完整 |
| Marking / Organization eligibility scope | Markings/Organizations 是 access requirements，不是 role；普通 Marking 是 all-of | Marking member / Organization member 或 guest member；移除继承需 `Remove marking` / `Expand access` | Source requirements 传播到 sync output dataset；Dataset data requirement 控制读取 | role 不能绕过；`stop_propagating` / `stop_requiring` 只作用于 Marking/Organization |
| OAuth / API operation scope | token scope = application restrictions、用户/服务用户权限、token request operation scope 的交集 | Developer Console application / OAuth client；authorization-code user 或 client-credentials service user | 外部应用、OSDK、MCP、API 型集成 | API scope 授予的是权限集合，不严格等同单个 endpoint；应用 restrictions 与用户权限同时生效 |
| Audit export organization scope | `audit-export:view` 用于 Audit API/SIEM 读取；`audit-export:orchestrate-v3` 用于导出 audit.3 到 Foundry dataset | Organization permissions 中给 client/user 授 role；`audit-export:orchestrate-v3` 可通过 Organization administrator role 授予 | 审计日志 SIEM / Foundry dataset export | audit dataset 默认应加 organization marking；audit.3 用户组字段当前不填充，需下游 enrich |

## 3. 官方默认角色与操作语义

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

## 4. 官方 Data Connection 对象权限矩阵

| 对象 | 配置的权限 / 要求 | 权限点如何定义 | 默认授权给哪些角色 / 主体 |
|---|---|---|---|
| `Project` / folder | role grants；Organization；Marking；Classification | 资源容器；roles 和 access requirements 向子资源继承 | `Owner` 可授权同级或更低角色；`Editor` 可编辑范围内资源；`Viewer` 可查看；`Discoverer` 可发现。Organization/Marking 由治理主体授予资格 |
| `Agent` | `Owner` / `Editor` / `Viewer`；Project role；Organizations/Markings | 连接运行位置和网络路径。`Editor` 可 deploy source 到 agent、配置 plugins/configs、restart agent、share、delete；`Viewer` 看配置和状态；`Owner` 可重下 agent 或 regenerate token | Agent 创建需要所在 Project `Editor`；管理 agent 通常需要 Project `Owner`。部署 source 到 agent 需要 agent `Editor` |
| `Source` / `DataConnection` | `Owner` / `Editor` / `Viewer`；assigned agents；allowed capabilities；Organizations/Markings；export configuration | 外部系统连接实例，包含 endpoint、worker/network、credentials。`Editor` 可 delete、更新配置、改 assigned agents、rename、创建/编辑/删除 sync、运行 SQL、share、explore/preview、import to code。`Viewer` 看配置。`Owner` 继承 Editor，并可修改 export configuration、允许 import to code | `Owner` / `Editor` / `Viewer` 直接授在 source 或父 Project。改 assigned agents 还需被添加 agent 的 `Editor`。source editor 只应授予可信 pipeline developer |
| `Credential` / `Secret` | 公开文档未披露独立 secret ACL / operation identifier | 用于 source authentication，可是 password、token、API key、OIDC、cloud identity。Palantir 说明 secrets 加密存储；source import to code 后 repo editor 可通过代码使用 connection details，包括 secret values | 公开可证实路径是：source `Editor` 完成 import；code resource / repository `Editor` 可写代码使用 imported source details |
| `ExternalSystemPrincipal` | external grants；source credential scope | 外部 DB user、cloud IAM role、OAuth client 或 service account；credential 权限首先由外部系统决定 | 外部系统管理员授予；Palantir 公开文档强调 source credentials 允许什么，sync/SQL 就可能影响什么 |
| `Sync` / `SyncJob` | 派生自 source 和 output dataset | View sync = source `View` + output dataset `View`；Edit/Delete sync = source `Edit` + output dataset `Edit`; Run sync = output dataset `Edit` | 不是单独默认 role；由 source role 与 output dataset role 组合派生 |
| `Plugin` / JDBC Driver | `Owner` / `Editor` / `Viewer`；agent attachment | `Viewer` 可 view/download，并可 add plugin to agent；add 还需 agent `Editor`。`Editor` 可 delete plugin/driver，前提是未被 agents 使用。`Owner` 继承 Editor | Plugin/driver role 直接授予或从 Project 继承；add-to-agent 组合检查 plugin `Viewer` + agent `Editor` |
| `Webhook` | 完全继承关联 source 权限；可额外授 `webhooks:read-privileged-data` | View/Create/Edit/Delete/configure Action/Execute Webhook 都要求 source 对应 View/Edit。默认只有执行者可看自己的 response history；full request/response history 需要额外 operation | source `Viewer` 可看 webhook config；source `Editor` 可创建、编辑、删除、配置 Action、执行。`webhooks:read-privileged-data` 建议放入专门 custom role，如 `Webhook Privileged Data Viewer` |
| External connection from code | source import permission；code resource editor；repo/build role | Import source into transform/pipeline/compute module requires source `Editor`。触发使用 imported source 的 build 只需 code resource `Editor`，不再要求 source 权限。移除 imported source 需要 source `Editor` 或 code resource `Editor` | source `Editor` 是 import gate；repo/code resource `Editor` 是代码使用与 build gate。高危点是 repo editor 可写代码访问 secret values |
| Export configuration / ExportPolicy | enable exports；exportable markings/orgs；destination credential write scope | 目标 source 必须 enable exports，并配置允许外发的 Markings/Organizations；未列入的 markings/orgs 数据会 fail export。添加 exportable marking/org 需要 `Information Security Officer` 且具备对应 unmarking permission。目标 credential 还需外部写权限，如 S3 `PutObject` 或表 truncate/insert | `Information Security Officer` 执行 enable/exportable scope；source owner 可修改 export config 但仍受 marking/org unmarking 条件约束；export runtime 使用 destination credential |
| Export job | internal read + export configuration + destination write | Export management page 支持 manual run、schedule、view history、modify configuration；export 使用 Foundry build system 运行 | 公开文档未给完整默认 role matrix；可证实的是 target source export configuration、exportable markings/orgs、destination credential write 权限共同约束 |
| Output `Dataset` / transaction / view | resource role；file requirements；lineage-derived data requirements；branch/view/transaction requirements | `Viewer` 只表示可尝试查看资源；读 view 数据还需满足上游继承 Markings/Organizations/Classifications。用户可能能看 metadata 但不能读 data | Project/Dataset `Viewer` + 所有 Marking/Org eligibility。`Editor` 常用于写 output dataset / run sync/build。Marking 资格由 Marking admin 或数据治理授予 |
| `Stream` / streaming sync output | stream resource role；data requirements；consumer group/checkpoint ACL（公开细节不足） | streaming sync 写入 stream；streaming export 可从 stream 推到外部 message queue | 【待验证】Palantir hot stream、checkpoint reset、streaming export sink 的默认角色矩阵未完整公开 |
| `Code Repository` / Transform contract | repo role；branch protection；PR reviewer；CI publish/register；output dataset ownership | 代码编辑、PR review、protected branch merge、CI register、manual build、scheduled build 分属不同主体。Build 需要 input read、output write、runtime principal 合规 | repo `Editor` 可写代码和触发 build；protected branch 政策要求 reviewer/approver；CI principal 负责 register；output dataset `Editor` / owner 约束写入 |
| `Schedule` / scheduled build | schedule 与 export/build job 关联 | export 可配置 schedule，export job 通过 Foundry build system 运行 | 公开文档未在 Data Connection permission reference 中给出 schedule identity 的完整默认角色矩阵 |
| Ontology Object Type / Object / Property | project-based ontology resource role；backing datasource access；object/property policy | Object Type schema 可由 project role 控制；要看 object instances，还需 backing datasource access 或 object/property security policy。Object policy 控制实例，Property policy 控制属性值 | Object type `Viewer` 可看类型；看对象需 object type `Viewer` + datasource `Viewer` 或相应 object/property security policy |
| Audit logs / audit export dataset | audit export operations；dataset marking；Organization | Audit logs 回答 who/what/when/where，内容可能含 PII 和敏感 usage data。导出 audit.3 需要 `audit-export:orchestrate-v3`；SIEM API 读取需要 `audit-export:view` | Organization administrator 可授相关 audit export operation；导出的 audit dataset 应加 Organization/Marking，仅给安全运营和合规人员 |

## 5. Palantir 公开 operation / scope 对齐表

| 官方公开名称 | 类型 | 定义 / 触发动作 | 授权位置 / 角色 | 证据强度 |
|---|---|---|---|---|
| `Owner` | Default resource role | 默认最高资源角色，通常继承 `Editor`；可授予同级或更低 role | Project/folder/file/resource role grant | 高 |
| `Editor` | Default resource role | 默认编辑角色；在 Source 上聚合配置、sync、SQL、preview、share、code import 等动作 | Project/folder/file/resource role grant | 高 |
| `Viewer` | Default resource role | 默认查看角色；在 Source 上可看配置和 assigned agents；读取数据仍需满足 Marking/Org/data requirements | Project/folder/file/resource role grant | 高 |
| `Discoverer` | Default resource role | 默认低权限发现角色 | Project/folder/file/resource role grant | 高 |
| `stemma:mutate-default-branch` | Operation identifier | Code Repository “Change default branch” operation 的公开示例 | 默认 Owner 包含，lesser roles 不包含；可通过 custom roles 调整 | 高，但非 Data Connection |
| `webhooks:read-privileged-data` | Operation identifier | 查看可访问 webhook 的 full request/response history | 加入 custom 或 default role；官方推荐 `Webhook Privileged Data Viewer` | 高 |
| `Information Security Officer` | Enrollment-level default role | enable exports to source；添加 exportable markings/orgs 时还需对应 unmarking permission | Control Panel / Enrollment permissions | 高 |
| `Remove marking` | Marking-specific permission | approve/remove inherited Marking；用于 `stop_propagating` 审批 | Marking 相关权限 | 高 |
| `Expand access` | Organization / Marking expansion permission | approve/remove inherited Organization requirement；用于 `stop_requiring` 审批 | Organization / Marking 相关权限 | 高 |
| `audit-export:view` | Organization operation | Audit API / SIEM 读取 audit.3 logs 的 gatekeeper operation | Organization permissions 中授予 client/user role | 高 |
| `audit-export:orchestrate-v3` | Organization operation | 导出 `audit.3` logs 到 Foundry dataset | Organization permissions；可由 Organization administrator role 授予 | 高 |
| OAuth operation scopes, e.g. `api:ontologies-read`, `api:ontologies-write` | OAuth/API scope | OAuth token request 的 operation scope；实际访问为 user/service permissions、application restrictions、requested scope 的交集 | Developer Console / OAuth client restrictions + token request | 高，但不专属于 Data Connection |
| Source preview / SQL / sync config operation ids | 未公开 | 官方只公开这些动作属于 Source `Editor`，未公开 identifier | Source `Editor` 默认聚合 | 公开行为高，operation id 未披露 |
| Credential `secret.use` / `secret.read` operation ids | 未公开 | 官方说明 source credential 加密存储；source import to code 后 repo editor 可访问 secret values | Source `Editor` + code resource `Editor` 形成可访问路径 | 公开行为高，ACL/operation id 未披露 |

## 6. 官方默认动作到角色授权

### 6.1 接入连接侧

| 动作 / scope | 官方定义 | Palantir 默认归属 | 是否有公开 operation identifier |
|---|---|---|---|
| View source configuration | 查看 source configuration 和 assigned agents | Source `Viewer` | 未公开 |
| Explore / preview source | 查看支持该能力的源数据样本或 schema | Source `Editor` | 未公开 |
| Run SQL queries | 在 database source 上运行 SQL | Source `Editor` | 未公开 |
| Change assigned agents | 修改 source 的 assigned agents | Source `Editor` + every added Agent `Editor` | 未公开 |
| Update source configuration | 更新 source configuration | Source `Editor` + assigned Agent `Editor` | 未公开 |
| Create / edit / delete syncs | 管理 source 下 sync | Source `Editor`；具体 sync edit/delete 还要求 output dataset `Editor` | 未公开 |
| Import source to code resource | 将 source 导入 transform / pipeline / compute module | Source `Editor`；Source `Owner` 可 allow import | 未公开 |
| Access secret values from code | imported source 后，repo editor 可写代码使用 connection details including secret values | Code resource / repository `Editor`，且 source 已被 import | 未公开，公开文档仅描述行为 |

### 6.2 运行与构建侧

| 动作 / scope | 官方定义 | Palantir 默认归属 | 是否有公开 operation identifier |
|---|---|---|---|
| View sync | 查看 sync | Source `View` + output Dataset `View` | 未公开 |
| Edit sync | 编辑 sync | Source `Edit` + output Dataset `Edit` | 未公开 |
| Delete sync | 删除 sync | Source `Edit` + output Dataset `Edit` | 未公开 |
| Run sync | 执行 sync | Output Dataset `Edit` | 未公开 |
| Trigger build using imported source | 触发使用 imported source 的 build | Code resource `Editor`；不再要求 source permission | 未公开 |
| Remove imported source | 从 code resource 移除 imported source | Source `Editor` 或 code resource `Editor` | 未公开 |
| External code egress policy | 用户代码访问外部 destination 必须绑定 network egress policy | Source / code runtime 相关配置 | 未公开为 role operation |

### 6.3 消费、外发与治理侧

| 动作 / scope | 官方定义 | Palantir 默认归属 | 是否有公开 operation identifier |
|---|---|---|---|
| Enable exports for source | 打开 source export configuration | `Information Security Officer` role | 未公开具体 operation id |
| Add exportable markings/orgs | 配置可导出的 Markings / Organizations | `Information Security Officer` + corresponding unmarking permission | 未公开具体 operation id |
| Run / schedule / view export history | export management page 可 manual run、set schedule、view history、modify configuration | 公开文档未给完整 role matrix | 未公开 |
| Execute webhook | 执行 webhook | Source `Editor`；通过 Action 执行 webhook 时不要求此 permission | 未公开 |
| Read full webhook history | 查看 full request/response history | role 包含 `webhooks:read-privileged-data` | `webhooks:read-privileged-data` |
| Ingest audit logs via API | SIEM 读取 audit.3 logs | client/user token 必须有 organization 上 `audit-export:view` | `audit-export:view` |
| Export audit.3 logs to Foundry dataset | 创建 audit log export dataset | organization 上 `audit-export:orchestrate-v3`；可由 Organization administrator role 授予 | `audit-export:orchestrate-v3` |
| Remove inherited Markings | `stop_propagating` 审批 | `Remove marking` permission | 公开权限名称，非 role operation id |
| Remove inherited Organizations | `stop_requiring` 审批 | `Expand access` permission | 公开权限名称，非 role operation id |

## 7. 非 Palantir 官方：自研角色包建议

以下角色包是自研平台对齐 Palantir 默认行为后的拆分建议，不是 Palantir 官方默认角色。

### 7.1 最小角色包

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

### 7.2 授权校验最小快照

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

## 8. 设计结论

1. 【结论】Integration 权限主轴不是“Source ACL”，而是 source / credential / sync / code import / output dataset / export policy / audit 的分层授权。
2. 【结论】Palantir 公开默认模型里，`Source Editor` 聚合了多项高危动作；公开文档没有披露这些动作的 operation identifier。自研平台若要更细分，是在 Palantir 行为对齐基础上的增强，而不是 Palantir 已公开的默认拆分。
3. 【结论】RBAC 只能表达“能执行什么操作”，不能表达“是否有资格接触某类数据”；Marking/Organization/Classifications 必须作为强制要求参与每个数据读写与外发决策。
4. 【结论】外发链路必须独立建模。Dataset Viewer、Source Editor 或 Pipeline Developer 都不应天然获得 download/export/webhook/Kafka/SIEM 外发权。
5. 【结论】审计应记录 access decision snapshot，而不是只记录 grant/revoke；否则无法证明某人某时刻读取了哪版数据、满足了哪些 Marking/Organization、用了哪个 credential 和 runtime principal。

## 9. 证据边界

1. 【待验证】Palantir 未公开 Data Connection 细项 operation identifiers；公开文档只列默认角色行为。
2. 【待验证】Palantir 未公开 Data Connection secret ACL、runtime 解密、source import 后 secret redaction 与 audit event schema 的完整内部结构。
3. 【待验证】Schedule identity、build runtime effective principal、CI publish principal 的精确内部映射未公开。
4. 【待验证】Stream hot subscription、consumer group/checkpoint reset、stream export sink 的默认角色矩阵未完整公开。
5. 【待验证】Download/export 的字段级 redaction、水印、purpose justification 是否按产品/环境可配置，需要具体租户验证。
6. 【说明】Palantir 文档提示 default permission behavior 可能被 custom roles 改写；本文矩阵以公开默认行为为基线。

## 10. 来源

- Palantir Data Connection permissions: <https://www.palantir.com/docs/foundry/data-connection/permissions>
- Palantir Data Connection core concepts: <https://www.palantir.com/docs/foundry/data-connection/core-concepts>
- Palantir Data Connection exports: <https://www.palantir.com/docs/foundry/data-connection/export-overview>
- Palantir Developer Console application restrictions: <https://www.palantir.com/docs/foundry/developer-console/application-restrictions>
- Palantir API authentication and OAuth2 scope: <https://www.palantir.com/docs/foundry/api/general/overview/authentication/>
- Palantir Developer Console permissions: <https://www.palantir.com/docs/foundry/developer-console/permissions>
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
