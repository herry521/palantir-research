# 50 - Data Integration 权限体系资料源与术语基线

**所属 Epic：** #49
**类型：** Story 调研 / 资料源索引与术语基线
**调研日期：** 2026-05-31

## 摘要与洞察

1. 【事实】Palantir Data Connection 把 agents、sources、syncs、plugins、webhooks 和 external code connections 都作为 Foundry resources 管理，意味着接入侧权限不是单一连接字符串 ACL。
2. 【事实】Palantir 官方明确区分 resource access 与 lineage-derived additional data requirements；用户可能看见 Dataset metadata，但不能读取数据内容。
3. 【推断】自研 Data Integration 权限体系至少要统一六类对象：resource、data requirement、credential、runtime principal、policy、audit event。
4. 【建议】后续 Story 统一使用“接入、运行、消费、传播、治理、对标”六个证据域，避免把 Dataset Marking、source credential 和 export policy 混成一个“数据权限”概念。
5. 【待验证】Palantir 未公开 Data Connection secret ACL、runtime effective principal、audit event schema 的全部内部结构；这些只能作为自研设计推断。

## 1. 范围和非范围

本文件回答“研究时如何统一口径”。它不重复既有 Dataset Marking 全量结论，而是把 Data Integration 权限体系拆成可复用术语和来源。

覆盖范围：

- Data Connection resources：agent、source、sync、plugin、driver、webhook、external code connection。
- Transform / Pipeline build：Code Repository、branch、PR、CI/register、schedule、build runtime identity。
- Data products：Dataset view/transaction、Stream hot/cold、Restricted View、Ontology/API、download/export。
- Governance：Marking、Organization、Classification、row/column/property policy、access request、audit、SIEM。
- Comparative platforms：Databricks、Snowflake、BigQuery、Apache Ranger/Atlas、OpenLineage/Marquez、Airflow。

非范围：

- 不做 Palantir 内部服务表结构反向工程。
- 不把外部平台的产品菜单直接映射为自研需求。
- 不把“能读数据”与“能管理连接/凭据/运行任务/导出数据”合并。

## 2. 术语基线

| 术语 | 定义 | 设计含义 |
|---|---|---|
| Principal | 用户、组、服务账号、agent、runtime principal 或外部系统 identity | 必须记录 human actor 与 effective principal |
| Resource role | 在 Project、folder、Dataset、source、repo 等资源上的操作能力 | 授予 view/edit/manage，不等于敏感数据资格 |
| Data requirement | 由 Marking、Organization、Classification、lineage 得出的数据读取资格要求 | 应绑定 Dataset transaction/view，而不是只绑最新资源 |
| Marking | 强制访问控制要求，普通 Marking 访问语义为 all-of | 不能被 Owner/Editor role 绕过 |
| Organization | 组织边界访问要求 | Palantir 文档中 Organization 与 Marking 语义不同 |
| Credential / Secret | 外部系统认证材料或短期凭据交换配置 | 应一等对象化，默认只允许 runtime use |
| Source | 外部系统连接实例 | Source edit 往往等价于外部账号能力，应高信任授权 |
| Sync job | 从 source 写 Dataset/Stream/Media 的任务 | run、config edit、schedule、target write 应分权 |
| Runtime identity | 执行 build/sync/export 的有效身份 | 需要 on-behalf-of 链路和最小权限 |
| Export policy | 外发到外部系统的 allowed markings/orgs、field redaction 和 destination policy | 不能由 Dataset Viewer 隐式获得 |
| PDP / PEP | Policy Decision Point / Policy Enforcement Point | 所有 preview/query/export/API/log 入口必须有服务端 PEP |
| Access decision snapshot | 某次访问的 actor、resource、branch/view/tx、requirements、decision | 审计和事后解释的核心证据 |

## 3. 资料源矩阵

| 编号 | 来源 | 覆盖能力 | 可信度 | 后续引用 |
|---|---|---|---|---|
| S01 | Palantir Data Connection Permissions, <https://www.palantir.com/docs/foundry/data-connection/permissions> | agents/sources/syncs/plugins/webhooks/external code 权限、source marking propagation | 高 | #51 |
| S02 | Palantir Data Connection Exports, <https://www.palantir.com/docs/foundry/data-connection/export-overview> | export enablement、exportable markings/orgs、export history、external credential | 高 | #51/#53 |
| S03 | Palantir Connecting to data, <https://www.palantir.com/docs/foundry/data-integration/connecting-to-data> | Data Connection、HyperAuto、external transforms、granular security | 高 | #50/#51 |
| S04 | Palantir Markings, <https://www.palantir.com/docs/foundry/security/markings/> | mandatory control、file/data dependency inheritance、roles 不可绕过 Marking | 高 | #54 |
| S05 | Palantir Checking Permissions, <https://www.palantir.com/docs/foundry/security/checking-permissions> | Check access、additional data requirements、lineage permission coloring | 高 | #53/#54 |
| S06 | Palantir Remove inherited Markings, <https://www.palantir.com/docs/foundry/building-pipelines/remove-inherited-markings> | `stop_propagating`、`stop_requiring`、approval、protected branch | 高 | #52/#54/#55 |
| S07 | Palantir Code Repository branch settings, <https://www.palantir.com/docs/foundry/code-repositories/branch-settings> | protected branch、CI、review、security approval、fallback branch | 高 | #52 |
| S08 | Palantir Audit Logs, <https://www.palantir.com/docs/foundry/security/audit-logs-overview> | audit.3、SIEM、who/what/when/where、service/user initiated 区分 | 高 | #55 |
| S09 | Palantir Restricted Views, <https://www.palantir.com/docs/foundry/security/restricted-views/> | row-level access controls、marking-backed restricted views | 高 | #53/#54 |
| S10 | Palantir Manage Restricted Views, <https://www.palantir.com/docs/foundry/platform-security-management/manage-restricted-views> | create/edit/view restricted view permissions、limitations | 高 | #53 |
| S11 | Databricks Unity Catalog privileges, <https://learn.microsoft.com/en-us/azure/databricks/data-governance/unity-catalog/access-control/privileges-reference> | securable objects、principals、browse、apply tag、service credential | 高 | #56 |
| S12 | Databricks row filters and column masks, <https://docs.databricks.com/gcp/en/data-governance/unity-catalog/filters-and-masks> | query-time row/column policy、ABAC tags、limitations | 高 | #56 |
| S13 | Databricks pipelines with Unity Catalog, <https://docs.databricks.com/gcp/en/ldp/unity-catalog> | pipeline owner vs query invoker context | 高 | #52/#56 |
| S14 | Snowflake access control, <https://docs.snowflake.com/en/user-guide/security-access-control-overview> | securable object hierarchy、roles、ownership、managed access | 高 | #56 |
| S15 | Snowflake row access policy, <https://docs.snowflake.com/en/user-guide/security-row-intro> | query-time row policy、policy owner context、limitations | 高 | #56 |
| S16 | Snowflake dynamic masking, <https://docs.snowflake.com/en/user-guide/security-column-ddm-intro> | column-level masking at query time | 高 | #56 |
| S17 | Snowflake tag-based masking, <https://docs.snowflake.com/en/user-guide/tag-based-masking-policies> | tag inheritance、masking policy on tags、data sharing enforcement | 高 | #56 |
| S18 | Snowflake Access History, <https://docs.snowflake.com/en/user-guide/access-history> | user read/write history and policy audit | 高 | #56 |
| S19 | BigQuery row-level security, <https://cloud.google.com/bigquery/docs/row-level-security-intro> | row access policy、grantee list、filter expression | 高 | #56 |
| S20 | BigQuery column-level security, <https://cloud.google.com/bigquery/docs/column-level-security-intro/> | policy tags、taxonomy、query-time check、masking | 高 | #56 |
| S21 | Apache Atlas classification propagation, <https://atlas.apache.org/1.1.0/ClassificationPropagation.html> | lineage classification propagation and blocking | 中 | #54/#56 |
| S22 | Apache Ranger row filter and masking, <https://cwiki.apache.org/confluence/pages/viewpage.action?pageId=65868896> | centralized row-filter/data-mask policy and audit model | 中 | #56 |
| S23 | Airflow access control, <https://airflow.apache.org/docs/apache-airflow/2.5.3/administration-and-deployment/security/access-control.html> | DAG/resource/action RBAC, Connection as operational resource | 中 | #56 |

## 4. 仓库内证据基线

| 文件 | 可复用结论 |
|---|---|
| `docs/synthesis/dataset-permission-marking-architecture-summary.md` | Dataset 权限不是单一 RBAC；resource access 与 data access 必须分开 |
| `docs/raw/30-dataset-permission-marking-architecture.md` | Marking、Organization、Classification、Restricted View、Ontology policy 全景 |
| `docs/raw/49-data-quality-external-notification-security.md` | 外部通知通道必须有 export/redaction policy，不能只依赖 Viewer permission |
| `docs/raw/26-pro-code-governance-quality-observability.md` | 高码治理中 code review、quality、lineage、permission 需要闭环 |
| `docs/raw/29-lineage-branch-version-pipeline-sync.md` | branch/version/pipeline sync 关系是 requirement 快照的前置条件 |
| `docs/raw/42-governance-lineage-audit-contracts.md` | transaction/view 与 governance lineage audit contract 可支撑版本化审计 |
| `docs/raw/48-data-quality-governance-lifecycle.md` | rule lifecycle、PR review、history retention 的治理模式可迁移到 permission policy |

## 5. 术语禁用和修正

| 禁用说法 | 问题 | 修正 |
|---|---|---|
| “给 Dataset 加 ACL 就完成数据权限” | 忽略 data requirement、lineage propagation、query-time PDP | 使用 `resource role + data requirements + fine-grained policy` |
| “Source Viewer 等于能读下游数据” | Source 包含外部系统配置和可能的敏感 preview | 下游数据消费应走 Dataset 权限，不共享 source |
| “能 Preview 就能 Download/Export” | 外发是跨边界动作 | download/export 需要独立 permission 和 audit |
| “service account 跑任务就不需要用户权限” | 容易绕过最小权限和归因 | 记录 actor、on-behalf-of、runtime principal、credential |
| “Marking 是标签” | Marking 是强制访问控制资格 | 使用 access requirement / mandatory control |

## 6. 后续 Story 引用建议

- #51 使用 S01-S03、S08、S02，聚焦 source/credential/sync/export。
- #52 使用 S06-S08、仓库 Pro-Code 文档，聚焦 branch/build/runtime/schedule。
- #53 使用 S04-S05、S09-S10、S02，聚焦 consumption/export PEP。
- #54 使用 S04-S06、S21，聚焦 propagation and transaction/view requirement。
- #55 使用 S08、S05-S06、仓库 Data Quality lifecycle，聚焦 audit/access request/recertification。
- #56 使用 S11-S23，聚焦平台对标和抽象复用。

## 7. 证据缺口

1. 【待验证】Data Connection secret 使用审计、运行时解密边界和 code import 后的 secret redaction 未由公开文档完整披露。
2. 【待验证】Build runtime effective principal、schedule on-behalf-of 与 audit correlation id 的内部映射未公开。
3. 【待验证】Stream hot subscription 的 Marking/Organization enforcement 细节需要产品实测或内部文档。
4. 【待验证】External export 的 retry、partial success、payload redaction、receiver permission 需要按 connector 验证。
5. 【待验证】细粒度 row/column policy 在批处理、流处理、download/export、AI agent 上的统一执行方式需要自研设计决策。
