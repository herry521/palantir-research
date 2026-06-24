# Palantir 资源 Scope 权限配置参照表

**关联 Issue：** #71
**调研日期：** 2026-06-25
**用途：** 作为自研 Data Integration / Pipeline 系统权限配置的 Palantir 对齐参考。

## 摘要与洞察

1. 【事实】Palantir 公开 API scope 比 UI 内部 operation 粗：Dataset 主要是 `api:datasets-read/write`，Build/Schedule 主要是 `api:orchestration-read/write`，Sync/Data Connection 主要是 `api:connectivity-*`。
2. 【事实】Palantir UI 权限仍以 resource role 为主：`Owner`、`Editor`、`Viewer`、`Discoverer`；role 是 operation 的集合，但很多 operation identifier 没有公开。
3. 【事实】Data Connection 的 batch sync 在 API 中对应 `TableImport` / `FileImport`；它们有独立 read/write/execute OAuth scopes，比 UI 默认角色矩阵更适合自研系统直接借鉴。
4. 【建议】自研配置应采用“细粒度 scope + 默认角色包 + 强制 data requirement”三层模型：scope 控制动作，role 聚合 scope，Marking/Organization/lineage requirement 控制数据资格。
5. 【边界】Pipeline Builder / Code Repository 的完整内部 scope 未公开；只能按公开角色行为、Code Repository 少量 operation、Build/Schedule/Dataset API scope 反推配置参照。

## 1. 使用规则

### 1.1 三类权限不要混用

| 类型 | Palantir 表达 | 你系统里的落点 |
|---|---|---|
| Resource role | `Owner` / `Editor` / `Viewer` / `Discoverer` | 角色包，授给用户、组、服务账号 |
| Operation / OAuth scope | `api:datasets-read`、`api:orchestration-write`、`api:connectivity-table-import-execute` 等 | 细粒度权限点，用于 API / 服务端鉴权 |
| Access requirement | Marking、Organization、Classification、lineage-derived requirements | 强制数据资格，role/scope 不能绕过 |

### 1.2 建议命名

下面的“建议 scope”是给你系统配置用的稳定名称。`Palantir 对齐依据` 列说明它来自公开 OAuth scope、公开 UI role 行为，还是公开文档未披露但工程上必须拆分。

## 2. Dataset scopes

| 建议 scope | Palantir 对齐依据 | 动作含义 | 默认授予角色 | 必须叠加检查 |
|---|---|---|---|---|
| `dataset:discover` | `Discoverer` role；Project/folder role inheritance | 发现 Dataset 存在、显示名称/RID 的最低可见性 | Discoverer+ | file-level Marking/Organization |
| `dataset:view-metadata` | `Viewer` role；`api:datasets-read` | 读取 Dataset 元数据、schema、branch、transaction metadata | Viewer+ | file requirements |
| `dataset:read-table` | `api:datasets-read`；Read Table endpoint | 读取表格数据，支持 branch / transaction range / column subset | Viewer+ | data requirements、Marking、Organization、Classification、row/column policy |
| `dataset:read-file` | `api:datasets-read`；List/Get File Content | 列文件、读文件内容、按 branch / transaction 读历史文件 | Viewer+ | data requirements |
| `dataset:read-branch` | `api:datasets-read`；Get/List Branches | 查看 branch 指针和 branch 列表 | Viewer+ | file requirements；必要时 data requirements |
| `dataset:read-transaction` | `api:datasets-read`；Get/List Transactions | 查看 transaction、transaction history、resolved view | Viewer+ | file/data requirements |
| `dataset:create` | `api:datasets-write`；Create Dataset | 在目标 folder/project 创建 Dataset | Editor+ on parent folder/project | parent folder Marking/Organization |
| `dataset:write-schema` | `api:datasets-write`；Put Dataset Schema | 设置或更新 schema | Editor+ | schema governance / breaking change policy |
| `dataset:write-file` | `api:datasets-write`；Upload/Delete File | 写入或删除文件，可隐式创建 transaction | Editor+ | output ownership、branch policy |
| `dataset:create-transaction` | `api:datasets-write`；Create Transaction | 创建 `APPEND` / `UPDATE` / `SNAPSHOT` / `DELETE` transaction | Editor+ | branch write permission、one open transaction constraint |
| `dataset:commit-transaction` | `api:datasets-write`；Commit Transaction | 提交 open transaction，更新 branch pointer | Editor+ | transaction owner / producer ownership |
| `dataset:abort-transaction` | `api:datasets-write`；Abort Transaction | 放弃 open transaction | Editor+ | transaction owner / operator policy |
| `dataset:manage-branch` | `api:datasets-write`；Create/Delete Branch | 创建、删除 Dataset branch | Editor+ 或 Owner，取决于你的治理强度 | branch protection / environment policy |
| `dataset:view-schedules` | `api:datasets-read api:orchestration-read`；Get Dataset Schedules | 查看 target 到该 Dataset 的 schedules | Viewer+ | schedule visibility |
| `dataset:apply-marking` | Palantir Marking sensitive action；公开 API scope 不完整 | 给 Dataset / resource 应用 Marking | Owner + Marking apply/eligibility | Marking admin policy、impact review |
| `dataset:remove-marking` | `Remove marking` / `Expand Access` 语义 | 移除 direct requirement 或审批传播中断 | Marking approver / Organization approver | protected branch、approval、audit |

## 3. Pipeline scopes

这里的 Pipeline 指 Pipeline Builder pipeline、Code Repository transform pipeline、以及它们注册到平台的 Transform / JobSpec 逻辑。Palantir 没有公开一个统一的 `api:pipeline-*` OAuth scope；公开可对齐的是 resource role、Code Repository operation、Dataset I/O 和 Orchestration scope。

| 建议 scope | Palantir 对齐依据 | 动作含义 | 默认授予角色 | 必须叠加检查 |
|---|---|---|---|---|
| `pipeline:discover` | Project/resource `Discoverer` | 发现 pipeline / repository / pipeline resource | Discoverer+ | file requirements |
| `pipeline:view` | Project/resource `Viewer` | 查看 pipeline graph、transform config、repo files、lineage | Viewer+ | input/output Dataset visibility |
| `pipeline:edit` | Project/resource `Editor` | 编辑 Pipeline Builder 节点、transform code、配置参数 | Editor+ | branch policy、repo write policy |
| `pipeline:create` | Parent Project/folder `Editor` | 创建 Pipeline Builder pipeline 或 Code Repository transform project | Editor+ on parent | template / project policy |
| `pipeline:delete` | Resource `Editor` 或 Owner；公开细节因资源类型而异 | 删除 pipeline resource / repo resource / transform config | Owner 或 Editor | production protection |
| `pipeline:manage-settings` | Code Repository settings 默认面向 repository owners | 管理 repo/pipeline settings、branch settings、fallback branches | Owner | settings audit |
| `pipeline:change-default-branch` | 公开 operation 示例 `stemma:mutate-default-branch` | 修改 Code Repository default branch | Owner 默认包含；custom role 可加 | protected branch policy |
| `pipeline:manage-protected-branch` | Code Repository branch protection 文档 | 配置 protected branch、required reviewers、merge controls | Owner | security approval policy |
| `pipeline:review-pr` | PR / protected branch workflow | 审查并批准 pipeline code changes | Reviewer with repo access | required reviewer must also have repo access |
| `pipeline:publish-job-spec` | Code Repository CI / `ci/foundry-publish`；operation 未公开 | 注册 Transform / JobSpec / output ownership | CI principal / repo owner | output Dataset ownership、checks pass |
| `pipeline:run-checks` | Code Repository checks / Pipeline Builder checks | 运行 unit tests、data expectations、build checks | Editor+ / CI principal | compute policy |
| `pipeline:import-source` | Data Connection external code permissions | 把 Source 导入 transform / pipeline / compute module | Source `Editor` + code resource `Editor` | secret exposure、egress policy |
| `pipeline:use-project-reference` | Project references 文档 | 允许下游项目发现和使用上游 data/resource | Dataset/pipeline owner | declassification / sharing review |
| `pipeline:stop-propagating` | `stop_propagating` + `Remove marking` | 在 transform input 上停止 Marking 传播 | Security approver with Remove marking | protected branch、required approver |
| `pipeline:stop-requiring` | `stop_requiring` + `Expand access` | 在 transform input 上停止 Organization requirement 传播 | Org/space approver with Expand access | protected branch、approval |
| `pipeline:artifact-view` | `artifacts:view-repository` | 使用 Artifact repository 中的 artifact | Artifact repo Viewer | artifact repo visibility |
| `pipeline:artifact-manage` | `artifacts:manage-repository` | 发布、召回、管理 Artifact repository | Artifact repo Editor | package provenance |

## 4. Build scopes

Build 是 Orchestration 域对象。公开 API scope 主要是 `api:orchestration-read` 和 `api:orchestration-write`。

| 建议 scope | Palantir 对齐依据 | 动作含义 | 默认授予角色 | 必须叠加检查 |
|---|---|---|---|---|
| `build:view` | `api:orchestration-read`；Get Build / Get Builds Batch | 查看 build 状态、目标、运行结果 | Viewer / Operator | related resource visibility |
| `build:view-jobs` | `api:orchestration-read`；List Jobs Of Build / Get Job | 查看 build 下 job、job state、attempts | Viewer / Operator | log visibility |
| `build:view-logs` | Builds application live logs；API operation 未完整公开 | 查看 live logs / job logs | Operator / Developer | log redaction、sensitive data policy |
| `build:create` | `api:orchestration-write`；Create Build | 创建一次性 build，构建 target datasets | Editor / Operator | target Dataset write、input read、Marking/Org |
| `build:force` | Build staleness / force build behavior；Create Build request 能表达构建策略 | 忽略 staleness 重新构建 | Operator / Owner | cost control、Data Connection sync force-build rule |
| `build:cancel` | `api:orchestration-write`；Cancel Build | 取消未完成 build/jobs | Operator / Owner | build ownership / incident policy |
| `build:retry-job` | Schedule/job retries 文档；公开 API 未完整列出独立 retry endpoint | 重试失败 job 或允许 schedule 自动 retry | Operator / Schedule owner | idempotency |
| `build:read-inputs` | Build resolution 读取 input datasets | runtime 读取 input Dataset view | Runtime principal | input Dataset Viewer + data requirements |
| `build:write-outputs` | Build opens output transactions | runtime 写 output Dataset transaction | Runtime principal / output owner | output Dataset Editor、producer ownership |
| `build:publish-result` | Build completion commits/aborts transactions | 完成 build 后提交 output transactions | Runtime principal | transaction consistency, lineage write |

## 5. Schedule scopes

Schedule 也是 Orchestration 域对象。Palantir 公开强调 user-scoped 与 project-scoped schedules 的差异：生产优先 project-scoped，避免 schedule owner 权限变化导致失败。

| 建议 scope | Palantir 对齐依据 | 动作含义 | 默认授予角色 | 必须叠加检查 |
|---|---|---|---|---|
| `schedule:view` | `api:orchestration-read`；Get Schedule / Get Schedules Batch | 查看 schedule 配置 | Viewer / Operator | target resource visibility |
| `schedule:view-runs` | `api:orchestration-read`；List Runs Of Schedule | 查看 schedule 运行历史 | Viewer / Operator | build visibility |
| `schedule:view-version` | `api:orchestration-read`；Get Schedule Version | 查看 schedule version / 版本来源 | Operator / Auditor | audit policy |
| `schedule:view-affected-resources` | Orchestration affected resources endpoint | 查看 schedule 会影响哪些 resources | Operator | resource visibility |
| `schedule:create` | `api:orchestration-write`；Create Schedule | 创建 schedule | Editor / Operator | target Dataset ownership |
| `schedule:replace` | `api:orchestration-write`；Replace Schedule | 修改 schedule trigger、target、retry、scope | Schedule owner / Operator | owner change audit |
| `schedule:delete` | `api:orchestration-write`；Delete Schedule | 删除 schedule | Owner / Operator | production protection |
| `schedule:run` | `api:orchestration-write`；Run Schedule | 手动触发 schedule | Operator | target build permission |
| `schedule:pause` | `api:orchestration-write`；Pause Schedule | 暂停 schedule | Operator / Owner | incident/change policy |
| `schedule:unpause` | `api:orchestration-write`；Unpause Schedule | 恢复 schedule | Operator / Owner | readiness check |
| `schedule:project-scope` | Scheduling best practices | 使用 project-scoped schedule，避免依赖个人权限 | Project owner / platform operator | project has all target permissions |
| `schedule:user-scope` | Scheduling best practices | 使用 user-scoped schedule | Single service user / team lead | owner lifecycle, deactivation alert |
| `schedule:force-build` | Scheduling best practices | force-build schedule，Palantir 建议只用于 raw Data Connection sync | Sync owner / Operator | cost and target restriction |

## 6. Sync / Data Connection scopes

Palantir API 中，Source 称为 `Connection`，batch sync 分成 `TableImport` 和 `FileImport`。Data Connection UI 的 Sync 默认权限来自 Source + output Dataset；API scopes 更细，建议直接参考 API scopes 建模。

### 6.1 Source / Connection

| 建议 scope | Palantir 对齐依据 | 动作含义 | 默认授予角色 | 必须叠加检查 |
|---|---|---|---|---|
| `connection:view` | `api:connectivity-connection-read`；Source `Viewer` | 查看 source/connection config、assigned agents、状态 | Viewer+ | source Marking/Organization |
| `connection:create` | `api:connectivity-connection-write`；Create Connection | 创建 source/connection | Editor+ on parent | worker/network policy |
| `connection:update-secrets` | `api:connectivity-connection-write`；Update Secrets | 更新 source secrets；API 文档说明服务端会短暂明文处理 | Source owner / security operator | secret handling approval |
| `connection:edit-config` | Source `Editor`; API write scope | 修改 endpoint、worker、配置 | Editor+ | external credential scope |
| `connection:delete` | Source `Editor` | 删除 source | Editor+ / Owner | downstream sync impact |
| `connection:assign-agent` | Source `Editor` + added Agent `Editor` | 修改 source assigned agents | Source Editor + Agent Editor | network path / egress policy |
| `connection:preview` | Source `Editor` | explore / preview source data | Source Editor | external data sensitivity |
| `connection:run-sql` | Source `Editor` | database source 上运行 SQL | Source Editor | DDL/DML restriction |
| `connection:import-to-code` | Source `Editor` | import source into transform / pipeline / compute module | Source Editor | code repo Editor, secret exposure |
| `connection:manage-export-config` | Source owner + ISO / unmarking constraints | enable export、配置 exportable markings/orgs | `Information Security Officer` + unmarking permission | destination write credential |

### 6.2 TableImport batch sync

| 建议 scope | Palantir 对齐依据 | 动作含义 | 默认授予角色 | 必须叠加检查 |
|---|---|---|---|---|
| `sync:table:view` | `api:connectivity-table-import-read`；Get/List Table Import | 查看 table import / batch sync | Source View + output Dataset View | source/output visibility |
| `sync:table:create` | `api:connectivity-table-import-write`；Create Table Import | 创建 table sync，绑定 output dataset/branch/import mode | Source Edit + output Dataset Edit | output Dataset write |
| `sync:table:edit` | `api:connectivity-table-import-write`；Replace Table Import | 修改 table sync config | Source Edit + output Dataset Edit | config review |
| `sync:table:delete` | `api:connectivity-table-import-write`；Delete Table Import | 删除 table sync；不删除 destination dataset | Source Edit + output Dataset Edit | downstream impact |
| `sync:table:execute` | `api:connectivity-table-import-execute`；Execute Table Import | 执行 table sync，异步返回 BuildRid | Output Dataset Edit；API execute scope | source credential, output branch |

### 6.3 FileImport batch sync

| 建议 scope | Palantir 对齐依据 | 动作含义 | 默认授予角色 | 必须叠加检查 |
|---|---|---|---|---|
| `sync:file:view` | `api:connectivity-file-import-read`；Get/List File Import | 查看 file import / batch sync | Source View + output Dataset View | source/output visibility |
| `sync:file:create` | `api:connectivity-file-import-write`；Create File Import | 创建 file sync，绑定 output dataset/branch/import mode/filter | Source Edit + output Dataset Edit | output Dataset write |
| `sync:file:edit` | `api:connectivity-file-import-write`；Replace File Import | 修改 file sync config | Source Edit + output Dataset Edit | config review |
| `sync:file:delete` | `api:connectivity-file-import-write`；Delete File Import | 删除 file sync；不删除 destination dataset | Source Edit + output Dataset Edit | downstream impact |
| `sync:file:execute` | `api:connectivity-file-import-execute`；Execute File Import | 执行 file sync，异步返回 BuildRid | Output Dataset Edit；API execute scope | source credential, output branch |

### 6.4 Virtual table / external table registration

| 建议 scope | Palantir 对齐依据 | 动作含义 | 默认授予角色 | 必须叠加检查 |
|---|---|---|---|---|
| `virtual-table:create` | `api:connectivity-virtual-table-write` | 从 source 注册 virtual table | Source access + parent folder Editor | connection permits virtual table registration |
| `virtual-table:view` | Virtual table 是 Foundry resource；API read scope 未在本轮公开证实 | 查看 virtual table metadata | Viewer+ | source/table data policy |
| `virtual-table:query` | 通过 Foundry data access APIs 查询 | 查询外部表数据 | Viewer+ | external credential, Marking/Organization, row/column policy |
| `virtual-table:write-output` | transforms-tables / virtual table output docs | transform 输出到外部 table | Pipeline runtime / Editor | external write grant, egress, export policy |

## 7. 推荐默认角色包

| 角色包 | 包含核心 scopes | 不应包含 |
|---|---|---|
| `DataViewer` | `dataset:discover`、`dataset:view-metadata`、`dataset:read-table`、`dataset:read-file`、`dataset:read-branch`、`dataset:read-transaction` | write、build、sync execute、export |
| `DatasetEditor` | `DataViewer` + `dataset:write-schema`、`dataset:write-file`、`dataset:create-transaction`、`dataset:commit-transaction`、`dataset:abort-transaction` | marking removal、export config |
| `PipelineDeveloper` | `pipeline:view`、`pipeline:edit`、`pipeline:run-checks`、`build:create` on dev targets | source secret exposure、export config、protected branch bypass |
| `PipelineOwner` | `PipelineDeveloper` + `pipeline:manage-settings`、`pipeline:manage-protected-branch`、`schedule:create/replace/delete` | Marking approval unless separately granted |
| `BuildOperator` | `build:view`、`build:view-jobs`、`build:create`、`build:cancel`、`schedule:run`、`schedule:pause/unpause` | pipeline code edit、source config edit |
| `ScheduleOwner` | `schedule:view`、`schedule:view-runs`、`schedule:create`、`schedule:replace`、`schedule:delete`、`schedule:run` | source preview/run SQL |
| `SourceViewer` | `connection:view`、`sync:table:view`、`sync:file:view` | preview/run SQL/secrets |
| `SourceEditor` | `SourceViewer` + `connection:edit-config`、`connection:assign-agent`、`connection:preview`、`connection:run-sql`、`sync:*:create/edit/delete` | export enable、unmarking approval |
| `SyncOperator` | `sync:table:execute`、`sync:file:execute`、`build:view` | source config edit、run SQL |
| `ExportSecurityOfficer` | `connection:manage-export-config`、exportable marking/org approval | ordinary source edit unless separately granted |
| `MarkingApprover` | `dataset:apply-marking`、`dataset:remove-marking`、`pipeline:stop-propagating`、`pipeline:stop-requiring` | data read unless separately granted |

## 8. 来源

- Palantir Dataset API scopes: `api:datasets-read/write` on Dataset, Branch, Transaction, File, View endpoints.
- Palantir Orchestration API scopes: `api:orchestration-read/write` on Build, Job, Schedule, ScheduleVersion endpoints.
- Palantir Connectivity API scopes: `api:connectivity-connection-read/write`, `api:connectivity-table-import-read/write/execute`, `api:connectivity-file-import-read/write/execute`, `api:connectivity-virtual-table-write`.
- Palantir Data Connection permissions: <https://www.palantir.com/docs/foundry/data-connection/permissions>
- Palantir Data Connection exports: <https://www.palantir.com/docs/foundry/data-connection/export-overview>
- Palantir Builds core concepts: <https://www.palantir.com/docs/foundry/data-integration/builds/>
- Palantir Scheduling overview: <https://www.palantir.com/docs/foundry/building-pipelines/scheduling-overview/>
- Palantir Scheduling best practices: <https://www.palantir.com/docs/foundry/building-pipelines/scheduling-best-practices/>
- Palantir Code Repository branch settings: <https://www.palantir.com/docs/foundry/code-repositories/branch-settings/>
- Palantir Code Repository artifact permissions: <https://www.palantir.com/docs/foundry/code-repositories/manage-permissions/>
- Palantir Manage roles: <https://www.palantir.com/docs/foundry/platform-security-management/manage-roles/>
- Palantir Projects and roles: <https://www.palantir.com/docs/foundry/security/projects-and-roles/>
- Palantir Markings: <https://www.palantir.com/docs/foundry/security/markings/>
- Palantir Remove inherited Markings and Organizations: <https://www.palantir.com/docs/foundry/building-pipelines/remove-inherited-markings>
