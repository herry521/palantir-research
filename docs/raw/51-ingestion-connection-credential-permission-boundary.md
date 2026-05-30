# 51 - 数据接入、连接与凭据权限边界调研

**所属 Epic：** #49
**对应 Story：** #51
**类型：** Story 调研 / Data Connection、Credential、Sync 与 Export 权限边界
**调研日期：** 2026-05-31

## 摘要与洞察

1. 【事实】Palantir Data Connection 的 agents、sources、syncs、plugins、webhooks 和 external code connections 都是 Foundry resources；它们可以被组织到 Projects/folders，并叠加 roles、Organizations、Markings。
2. 【事实】Source Editor 是高危权限：官方说明 source editor 可以改配置、创建/编辑 sync、运行数据库 SQL、preview/explore source；如果外部凭据允许，sync 甚至可能删除文件或执行破坏性 SQL。
3. 【推断】Credential/secret 使用权、source data read、sync run、output dataset read 和 export write 是不同边界；自研平台必须把它们拆成独立对象和权限。
4. 【建议】P0 先做 source editor 严控、secret runtime-use-only、sync run 与 config edit 分离、source marking 向 output dataset 保守传播、exportable markings allowlist 和审计。
5. 【待验证】Palantir 未公开 Data Connection secret ACL、runtime 解密细节和 code import 后 secret 防泄漏机制；自研时要按高危路径设计。

## 1. 接入侧权限对象模型

| 对象 | 含义 | 关键权限字段 | 权限边界 |
|---|---|---|---|
| `Source` / `DataConnection` | 外部系统连接实例，包含 endpoint、认证、worker/network 配置、connector capability | owner、viewer、editor、allowed_agents、allowed_capabilities、markings、organizations | Source access 应视作对外部账号能力的间接访问 |
| `Connector` / `SourceType` | JDBC、S3、BigQuery、REST、Slack 等连接器类型或插件 | install、manage、use、version、driver/plugin access | 决定能力，不应授予具体数据访问 |
| `Agent` | 执行连接、同步、导出的 worker 或网络代理 | deploy source、configure plugins、restart、view status | Agent editor 可能让用户把 source 部署到网络路径 |
| `Credential` / `Secret` | 外部系统认证材料、API key、password、OAuth/OIDC 配置 | create、rotate、use、read-secret、bind-to-source、audit | 默认只允许 runtime use，明文读取和 code exposure 是高危权限 |
| `ExternalSystemPrincipal` | 外部系统中的 service account、database user、cloud IAM role、OAuth client | external grants、scope、rotation owner、source binding | 平台权限不能替代外部系统最小授权 |
| `SyncJob` | 从 source 写入 Dataset/Stream/Media 的同步任务 | view、edit、delete、run、schedule、target dataset write | Palantir sync 权限派生自 source 和 output dataset |
| `ExportPolicy` | 允许向外部 source 导出的敏感范围和字段策略 | enable_export、exportable_markings、exportable_orgs、redaction policy | Export 是跨边界外发，不是 Viewer 的隐式能力 |

## 2. 五类权限边界

### 2.1 Connection 管理权限

Palantir source owner/editor 的默认权限包括改 source 配置、改 assigned agents、创建/编辑/删除 sync、运行 SQL、preview/explore source、共享 source、把 source import 到 code resource。官方警告：如果 source credentials 允许，sync 可以改变源系统，例如删除目录/S3 文件或通过任意 SQL drop data。

自研平台不应只有一个 `connection.edit`：

| 权限 | 说明 |
|---|---|
| `connection.view_config` | 查看非敏感配置和状态 |
| `connection.preview_data` | 读取源样本，等价于源数据访问 |
| `connection.run_sql` | 在数据库源上运行 SQL，必须单独授权 |
| `connection.manage_agent` | 修改 agent/worker/network 路径 |
| `connection.import_to_code` | 将 source 绑定到代码资源，高危 |
| `connection.manage_export` | 启用外发和目标写入能力 |

### 2.2 Credential 使用权限

Credential 不能嵌在 source 配置里当普通字段处理。至少需要三层权限：

| 权限 | 语义 | 默认策略 |
|---|---|---|
| `secret.admin` | 创建、绑定、轮换、删除、配置 OIDC | 仅平台安全/连接 owner |
| `secret.use` | 运行任务时注入，不暴露明文 | sync/build/export runtime 可用 |
| `secret.read` / `secret.expose_to_code` | 代码或调试路径可读取 secret value | 默认禁止，需安全审批 |

Palantir external code 文档说明 source 被 import 到 code resource 后，repo editor 可以写代码使用 connection details，包括访问 secret values。自研平台必须把 `import_to_code` 设计成安全审批动作，而不是 source editor 的普通扩展能力。

### 2.3 Source data read 权限

Source data read 包含两层：

1. 外部系统层：外部 service account/database user/API token 能读哪些表、路径、topic、API。
2. 平台层：用户是否能 preview、explore、run SQL、import source to code。

Palantir 建议不要为了让用户读下游数据而共享 agents/sources；应通过 output datasets 授权下游使用。原因是 source access effectively access to data，且 source 应标记其包含数据的所有 Organizations 和 Markings。

### 2.4 同步任务运行权限

Palantir sync 权限派生自 source 和 output dataset：

| 动作 | 默认权限要求 |
|---|---|
| view sync | source View + output dataset View |
| edit/delete sync | source Edit + output dataset Edit |
| run sync | output dataset Edit |

自研平台应在 run 事件中记录：

- triggering actor
- source id and source config version
- credential id and external principal
- output dataset id and branch
- input cursor/transaction/source snapshot
- resulting transaction id
- effective requirements

### 2.5 外部导出权限

Palantir export 需要在 target source 上启用 export，并配置 exportable Markings/Organizations；添加这些 marking/org 需要 Information Security Officer role，并具备对应 unmarking permission。目标 source credential 还必须拥有外部写权限，例如 S3 PutObject 或表 truncate/insert 权限。

自研平台应把 export 判定拆成：

```text
t can_read_internal_dataset(user, dataset_view)
AND has_export_permission(user, export_job)
AND source_allows_export(target_source)
AND exportable_requirements_cover(dataset_view.requirements, target_source.policy)
AND credential_can_write(target_external_path_or_table)
AND payload_redaction_policy_ok
```

## 3. P0/P1/P2 建设建议

| 优先级 | 建设项 | 验收标准 |
|---|---|---|
| P0 | Source、Credential、Sync、ExportPolicy 分离建模 | 连接管理、凭据使用、任务运行、外发授权可分别授权和审计 |
| P0 | Source Marking 保守传播到 output dataset | source 上的 Organizations/Markings 自动进入 sync output requirements |
| P0 | Secret runtime-use-only | 运行注入不暴露明文；read/expose_to_code 需高危审批 |
| P0 | Sync run 审计 | 记录 source/config/credential/output transaction/effective principal |
| P0 | Exportable Marking allowlist | 未覆盖 output requirements 的 export 失败 |
| P0 | Connection capability-level permission | preview、sql_query、sync_create、webhook_execute、export_create、code_import、agent_assign 分权；source editor 不能隐式获得全部能力 |
| P0 | Export 粗粒度 redaction 与 payload audit | deny-by-default；allowed markings/orgs、destination credential、payload audit、RID/name 策略必须先有；字段级 redaction 可后续细化 |
| P1 | External principal inventory | 外部账号 owner、scope、last used、rotation、external grants 可查 |
| P1 | OIDC/短期凭据优先 | 支持 cloud IAM/OIDC，减少长期 secret |
| P1 | whyDenied / impact simulator | 解释缺 source role、dataset role、marking、export policy 或 external grant |
| P2 | 字段级接入和导出策略 | table/column/payload field 级策略和细粒度 redaction |
| P2 | 外部授权回读 | 周期校验 external grants 是否漂移 |
| P2 | Secret exposure static analysis | 检测代码是否打日志、外传或写出 secret |
| P2 | Cross-platform lineage | external table/API/path、sync run、dataset transaction、export run 进入血缘 |

## 4. 关键风险

| 风险 | 等级 | 说明 |
|---|---|---|
| Source Editor 过宽 | 高 | 可预览源、运行 SQL、创建 sync，接近外部账号权限 |
| Code import 泄露 secret | 高 | repo editor 可写代码访问 connection details 和 secret values |
| 只给 output dataset 打标 | 高 | source 本身应先标记全部适用敏感要求，再受控 unmark |
| Export 被当作普通读取 | 高 | 外发需要独立 allowlist、destination credential 和 audit |
| 外部服务账号权限过大 | 高 | 平台最小权限无法约束外部账号已有 DELETE/TRUNCATE/DROP |
| Agent/egress 共享过宽 | 中 | agent editor/source editor 可扩大网络路径 |
| Sync run 与 config edit 混淆 | 中 | 运行任务和修改源 SQL/路径的风险不同 |
| Webhook history 含敏感响应 | 中 | full request/response history 需要专门 viewer 权限 |

## 5. 证据缺口

1. 【待验证】Data Connection secret ACL、解密授权和使用审计 schema 未公开。
2. 【待验证】source import 到 code 后 secret values 的运行时隔离、日志 redaction、代码扫描机制未完整披露。
3. 【待验证】sync run 是否在所有 custom-role 环境都只需 output dataset Edit，需要实测。
4. 【待验证】Export partial success、retry、schema mismatch、truncate/insert 一致性需要按 connector 验证。
5. 【待验证】外部系统 principal 的真实最小权限只能依赖外部系统 grant 回读或人工审计。

## 6. 来源

- Palantir Data Connection permissions: <https://www.palantir.com/docs/foundry/data-connection/permissions>
- Palantir Data Connection exports: <https://www.palantir.com/docs/foundry/data-connection/export-overview>
- Palantir Connecting to data: <https://www.palantir.com/docs/foundry/data-integration/connecting-to-data>
- `docs/raw/05-testing-and-data-connection.md`
- `docs/raw/18-branching-data-connection.md`
- `docs/raw/49-data-quality-external-notification-security.md`
- `docs/synthesis/dataset-permission-marking-architecture-summary.md`
