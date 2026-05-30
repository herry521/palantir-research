# 56 - 主流数据平台权限模型对标与自研映射

**所属 Epic：** #49
**对应 Story：** #56
**类型：** Story 调研 / Databricks、Snowflake、BigQuery、Ranger/Atlas、OpenLineage、Airflow 对标
**调研日期：** 2026-05-31

## 摘要与洞察

1. 【事实】主流平台都把“对象层级 + 主体 + 权限/策略”作为权限底座：Unity Catalog、Snowflake、BigQuery 是层级对象授权；Ranger 是可插拔 service/resource policy；Airflow 是 UI/API/DAG 资源权限。
2. 【推断】自研 Data Integration 权限体系应采用双层模型：对象级 RBAC 负责可见、创建、执行、管理；tag/ABAC 负责敏感级别、业务域、行列级策略和自动覆盖新对象。
3. 【建议】credential/service principal 必须独立建模为高风险资源，不应嵌在 connector 或 pipeline 配置里；短凭证、OIDC/WIF、external secret backend 是更稳妥方向。
4. 【建议】行过滤、列脱敏、masking 可借鉴“声明式策略 + 运行时执行”，但 Data Integration 还覆盖读取、写入、同步、预览、调试、重跑、导出，策略必须绑定 enforcement point。
5. 【边界】OpenLineage/Marquez 只表达血缘元数据，不承担授权执行；可作为 lineage/audit enrichment 输入，不能作为权限系统。

## 1. 对标矩阵

| 平台 | 对象模型 | RBAC/ABAC/tag policy | Row/Column/Masking | Credential / Service Principal | Lineage | Audit | Access request / lifecycle |
|---|---|---|---|---|---|---|---|
| Databricks Unity Catalog | Metastore > Catalog > Schema > Table/View/Volume/Function/Model；对象称 securable object，可授权给 user/service principal/group | RBAC privileges + ownership；ABAC 用 governed tags 和 policy，在 catalog/schema/table 范围匹配 | row filters、column masks；ABAC 推荐用于大规模一致策略 | Service principal 是 API-only identity，可加入 group，并被授予 UC 数据权限 | UC 自动捕获 runtime lineage，支持列级，按权限显示 | audit logs / system tables | Request access 可配置 email、Slack、Teams、webhook 或外部审批 URL |
| Snowflake | Organization/Account > Database > Schema > Table/View/Stage/Policy/Tag 等 securable objects；对象由 role ownership 控制 | DAC + RBAC + UBAC；account/database roles；tag inheritance；tag-based masking | row access policy、dynamic data masking、tag-based masking | Service user + Workload Identity Federation，减少长期密钥 | Snowsight Data Lineage 跟踪 object dependency 和 movement | ACCESS_HISTORY / QUERY_HISTORY / Account Usage | 通用表级申请不是核心能力；Native App/Listing 有审批 |
| BigQuery / GCP | GCP hierarchy + BigQuery project/dataset/table/view/routine；IAM policy 附着资源并继承 | IAM allow/deny + Conditions；BigQuery tags 可用于条件 IAM；policy tags 用于列级控制 | row-level access policies；policy tags；data masking via data policies | Service accounts 是 principal 也是 resource；支持 impersonation、WIF；BigQuery connections 创建托管 service account | Dataplex Universal Catalog Lineage，BigQuery 自动记录数据移动 | Cloud Audit Logs，含 Admin Activity、Data Access、System Event | 依赖 IAM/组织流程，本身无完整数据访问申请闭环 |
| Apache Ranger / Atlas | Ranger service definition 描述资源层级、访问类型、mask/filter；Atlas type/entity/classification/glossary/relationship | Ranger 支持 RBAC、TBAC、ABAC、deny、delegate admin、validity schedules；Atlas classification 可与 Ranger tag policy 联动 | Ranger 支持 data masking、row-filter，含 classification/tag policy | 主要依赖企业认证集成，不是 service principal 生命周期强参考 | Atlas lineage UI/API，classification 可沿 lineage 传播 | Ranger access audit | policy 启停、版本、时间有效期、委派管理；缺 SaaS 式 request access |
| OpenLineage / Marquez | Run、Job、Dataset、facets；Marquez 存 namespace/source/job/run/dataset/version | 不做授权；ownership/tags 只是元数据 | 不执行 row/column/masking；column lineage facet 可标记 transformation | Marquez 默认不是强 authz 参考 | OpenLineage 是事件规范，Marquez 是参考实现 | 运行元数据，不是合规审计 | 无访问申请生命周期 |
| Airflow | DAG、DagRun、Task、Connection、Variable、Pool；DAG 级权限按 `DAG:<dag_id>` | FAB RBAC；resource + action | 不做数据行列权限 | Connection 存外部凭证，可接 external secrets backend | OpenLineage provider 可发 lineage event | Audit logs 存 DB，可 UI/API 查询 | 管用户、角色、DAG 权限和 connection 生命周期；无数据访问申请闭环 |

## 2. 自研映射建议

| 自研能力 | 建议映射 |
|---|---|
| 对象模型 | `workspace/project > data_source > schema/database > table/topic/file > column/field`，另设 pipeline/job/run/task、credential、policy、tag、lineage_edge |
| RBAC | 每个对象有 owner，权限分 discover/browse、read/preview、write/sync、execute、manage_grants、manage_policy、manage_credential |
| ABAC/tag | 建立 governed tag taxonomy：sensitivity、domain、region、environment、retention；tag 赋值权限独立于数据访问 |
| 细粒度策略 | `policy scope + match condition + effect + enforcement point`，effect 含 deny、row_filter、column_deny、mask、redact、hash、tokenize |
| Credential | credential 独立对象化：owner、allowed consumers、rotation state、last used、secret backend reference、service identity、scopes |
| Service principal | 支持 workload/service identity，权限与人类用户同模型，但有过期、禁用、last used、短凭证优先 |
| Lineage | 借鉴 OpenLineage run/job/dataset 事件模型 + column lineage facet；扩展 permission decision、policy references、credential id、masked columns |
| Audit | 至少包含 actor、effective principal、resource、action、decision、policy ids、credential id、run id、source IP、request id、before/after |
| Access request | discover/browse 与 request access 分离；请求路由到 owner、domain steward 或 external approval URL |
| Lifecycle | Grant、policy、credential、service principal 均需 owner、状态、有效期、审计、回收、last-used 分析 |

## 3. 不能直接照搬

| 来源能力 | 不宜直接照搬原因 |
|---|---|
| Snowflake role hierarchy | 强依赖 active role/session；DI 执行常是服务身份代理用户 |
| BigQuery IAM hierarchy | GCP 资源组织模型复杂，直接复制会引入过重云 IAM 语义 |
| Databricks ABAC 细节 | 依赖 Unity Catalog runtime 与 governed tags；可借鉴抽象，不绑定 SQL/UDF 限制 |
| Ranger plugin enforcement | 适合 Hadoop/SQL 引擎插件；DI 还要覆盖连接测试、metadata scan、preview、sync、logs |
| Airflow Connection 权限 | Airflow connection 面向高信任调度管理员；DI 普通用户接入需要更细 secret/test/run 权限 |
| Marquez 默认 auth 模型 | 默认不是强授权系统，不能作为权限参考 |

## 4. 风险与后续验证

| 风险 / 缺口 | 影响 | 后续验证 |
|---|---|---|
| 跨执行阶段策略不一致 | preview 被 mask，但 sync/log/export 泄露原文 | 枚举 metadata scan、sample preview、full extract、transform、load、retry、log、export |
| Tag 治理不成熟 | 错标/漏标导致越权 | tag owner、assignment approval、bulk scan、coverage report、deletion impact |
| Service identity 代理用户语义不清 | 审计无法区分“谁发起”和“用哪个凭证执行” | human actor、effective service principal、credential、run id 同时记录 |
| Row/column policy 下推能力未知 | 可能只能中间层过滤，带来泄露和性能风险 | 为每类 connector 标注 source pushdown、engine enforce、post-read filter、unsupported |
| Access request 与外部 IAM/ITSM 冲突 | 自研审批与企业权限源不一致 | 预留 webhook、external ticket id、SCIM/IAM/group 同步 |

## 5. 来源

- Databricks Unity Catalog privileges: <https://learn.microsoft.com/en-us/azure/databricks/data-governance/unity-catalog/access-control/privileges-reference>
- Databricks row filters and column masks: <https://docs.databricks.com/gcp/en/data-governance/unity-catalog/filters-and-masks>
- Databricks pipelines with Unity Catalog: <https://docs.databricks.com/gcp/en/ldp/unity-catalog>
- Snowflake access control: <https://docs.snowflake.com/en/user-guide/security-access-control-overview>
- Snowflake row access policy: <https://docs.snowflake.com/en/user-guide/security-row-intro>
- Snowflake dynamic data masking: <https://docs.snowflake.com/en/user-guide/security-column-ddm-intro>
- Snowflake tag-based masking: <https://docs.snowflake.com/en/user-guide/tag-based-masking-policies>
- Snowflake Access History: <https://docs.snowflake.com/en/user-guide/access-history>
- BigQuery row-level security: <https://cloud.google.com/bigquery/docs/row-level-security-intro>
- BigQuery column-level security: <https://cloud.google.com/bigquery/docs/column-level-security-intro/>
- Apache Ranger row filter and masking: <https://cwiki.apache.org/confluence/pages/viewpage.action?pageId=65868896>
- Apache Atlas Classification Propagation: <https://atlas.apache.org/1.1.0/ClassificationPropagation.html>
- Airflow Access Control: <https://airflow.apache.org/docs/apache-airflow/2.5.3/administration-and-deployment/security/access-control.html>
