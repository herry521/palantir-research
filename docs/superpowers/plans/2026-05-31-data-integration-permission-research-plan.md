# Data Integration 权限体系建设缺口调研计划

**日期：** 2026-05-31
**父 Epic：** [#49](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/49)
**目标：** 重新审视自研 Data Integration 权限体系仍需建设的能力，覆盖接入、凭据、同步、Transform、Dataset/Stream 消费、导出、传播、审批、审计和平台对标。

## 摘要与洞察

1. 【建议】本轮权限建设不应停在 Dataset ACL 或 Marking 字段，而要覆盖 Data Integration 的全部数据接触点：source preview、sync、transform build、stream subscribe、download/export、API、alert payload 和 logs。
2. 【事实】Palantir Data Connection 将 agents、sources、syncs、plugins、webhooks 和 external code connections 都建模为 Foundry resources，并允许对这些资源应用 roles、Organizations 和 Markings。
3. 【推断】自研平台最小闭环应拆成三条控制链：identity/credential 链、resource/data requirement 链、export/audit 链；任一链缺失都会产生权限旁路。
4. 【建议】工作项按证据域并行推进，最终由综合 Story #57 统一口径并执行专家评审；任何专家不通过都要补充 raw 文档或修订综合结论后复审。

## Issue Map

| Issue | 角色 | 调研域 | 输出 |
|---|---|---|---|
| [#49](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/49) | Epic | 总规划与跟踪 | 本计划、最终状态评论 |
| [#50](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/50) | Agent A | 权限资料源与术语基线 | `docs/raw/50-data-integration-permission-source-map.md` |
| [#51](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/51) | Agent B | 数据接入、连接与凭据权限边界 | `docs/raw/51-ingestion-connection-credential-permission-boundary.md` |
| [#52](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/52) | Agent C | Transform / Pipeline 构建运行时权限边界 | `docs/raw/52-transform-runtime-build-permission-boundary.md` |
| [#53](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/53) | Agent D | Dataset、Stream、API 消费与导出访问控制 | `docs/raw/53-consumption-export-access-control.md` |
| [#54](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/54) | Agent E | 权限传播、血缘、Marking 与细粒度策略 | `docs/raw/54-lineage-marking-policy-propagation-model.md` |
| [#55](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/55) | Agent F | 权限申请、审批、审计与生命周期治理 | `docs/raw/55-permission-governance-audit-lifecycle.md` |
| [#56](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/56) | Agent G | 主流平台权限模型对标 | `docs/raw/56-open-platform-permission-comparison.md` |
| [#57](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/57) | Coordinator + Expert Review | 综合结论与专家评审 | `docs/synthesis/data-integration-permission-system-roadmap.md` |

## 共享研究协议

1. 优先引用官方文档；公开资料未披露的内部实现只能标为【推断】或【待验证】。
2. 每份 raw/synthesis 文档开头必须包含 3-5 条总结或洞察。
3. 权限结论必须区分 `resource access`、`data access`、`credential use`、`runtime identity`、`export policy` 和 `audit evidence`。
4. 不重复既有 Dataset Marking 文档；只把它作为基线，补齐 Data Integration 全链路缺口。
5. 调研完成后由专家组复审；未通过项必须补充证据或修正文档，并重新评审。

## 共享资料源基线

| 编号 | 资料源 | 用途 |
|---|---|---|
| S01 | <https://www.palantir.com/docs/foundry/data-connection/permissions> | Data Connection agents/sources/syncs/plugins/webhooks/external code permissions |
| S02 | <https://www.palantir.com/docs/foundry/data-connection/export-overview> | Export enablement、exportable markings、source credentials、export history |
| S03 | <https://www.palantir.com/docs/foundry/data-integration/connecting-to-data> | Data Connection、HyperAuto、external transforms 总览 |
| S04 | <https://www.palantir.com/docs/foundry/security/markings/> | Marking 强制控制、继承和 data requirements |
| S05 | <https://www.palantir.com/docs/foundry/security/checking-permissions> | Check access、Data Lineage resource/data access coloring |
| S06 | <https://www.palantir.com/docs/foundry/building-pipelines/remove-inherited-markings> | `stop_propagating` / `stop_requiring` 与 protected branch approval |
| S07 | <https://www.palantir.com/docs/foundry/code-repositories/branch-settings> | protected branch、CI、code review、security approval |
| S08 | <https://www.palantir.com/docs/foundry/security/audit-logs-overview> | audit log 语义、SIEM delivery、audit.3 schema |
| S09 | <https://www.palantir.com/docs/foundry/security/restricted-views/> | Restricted View row-level policy |
| S10 | <https://www.palantir.com/docs/foundry/platform-security-management/manage-restricted-views> | Restricted View permissions and limitations |
| S11 | Databricks Unity Catalog docs | Securable objects、privileges、row filters、column masks、ABAC |
| S12 | Snowflake security/governance docs | RBAC、row access policy、dynamic masking、tag-based masking、Access History |
| S13 | BigQuery docs | IAM、row-level security、column policy tags、data masking、audit logs |
| S14 | Apache Ranger / Atlas docs | tag/classification propagation、row filter、data masking、central audit |
| S15 | OpenLineage / Marquez / Airflow docs | lineage event model、DAG/connection access、non-authz boundaries |

## 专家评审协议

专家组至少包含四类视角：

1. Data Integration 架构专家：检查接入、同步、Transform、Dataset/Stream/API/export 链路是否覆盖完整。
2. 安全治理专家：检查 Marking、Organization、credential、service principal、least privilege、break-glass 是否可审计。
3. 平台工程专家：检查 PDP/PEP、runtime identity、branch/build/schedule、transaction/view requirement 是否能落地。
4. 运维与合规专家：检查 audit/SIEM、access request、recertification、policy drift、incident response 是否闭环。

评审记录采用：

| 专家 | 结论 | 必改项 | 已修订证据 | 残余风险 |
|---|---|---|---|---|

只要任一专家为 `Fail`，Coordinator 必须修订对应 raw/synthesis，再次提交专家组复审。

## 完成标准

1. #50-#56 raw 文档均完成并可独立引用。
2. #57 综合文档能回答“Data Integration 权限体系还需要建设哪些能力、优先级如何、风险在哪里”。
3. 专家评审全部通过，并在综合文档中记录共识。
4. 更新 `docs/catalog.yml` 与相关 topic/index。
5. 运行验证，commit、push，并更新 GitLab issue 状态。
