# Palantir Data Quality 模块调研综合报告

**日期：** 2026-05-30  
**关联 Issue：** #41  
**父 Epic：** #35  
**输入文档：** `docs/raw/44-data-quality-source-map.md`、`docs/raw/45-data-expectations-build-gates.md`、`docs/raw/46-data-health-health-checks.md`、`docs/raw/47-monitoring-views-alert-issue-loop.md`、`docs/raw/48-data-quality-governance-lifecycle.md`、`docs/raw/49-data-quality-external-notification-security.md`

---

## 1. 总结与结论

1. 【推断】Palantir Data Quality 不是一个单独页面定义的孤立产品，而是一组跨构建、监控、告警和治理的质量控制面：Data Expectations 负责构建期契约和阻断，Data Health/Health Checks 负责运行期单资源健康，Monitoring Views 负责规模化监控和路由，Foundry notifications/issues 负责处理闭环。
2. 【事实】Data Expectations 定义在 transform input/output 上，作为 build job 的一部分运行；`FAIL` 可 abort job，`WARN` 可继续并上报 Data Health。受保护分支上的规则变更走 Code Repository PR review，check 在相关 branch 的 CI 中注册。
3. 【事实】Data Health 提供两类主要功能：Monitoring views 用 scope-based monitoring rules 监控多资源，Health checks 对单个 dataset/schedule/table 做 status、time、size、content、schema、freshness 等检查。
4. 【推断】Palantir 的质量闭环强项不在规则 DSL 本身，而在“规则定义 -> CI 注册 -> 构建执行 -> 结构化结果 -> Health tab/lineage 展示 -> 订阅/告警/issue -> 规则生命周期审查”的跨应用联动。
5. 【建议】自建平台应优先复刻三层模型：build-time expectations、single-resource health checks、scope-based monitoring rules；三者共享质量结果、告警和 issue 模型，但必须保留不同触发器、责任边界、失败语义和外部通知导出策略。

---

## 2. Issue 与产物索引

| Issue | 角色 | 产物 | 状态 |
|---|---|---|---|
| #35 | Epic | `docs/superpowers/plans/2026-05-30-palantir-data-quality-research-plan.md` | 已创建 |
| #36 | 资料源与术语 | `docs/raw/44-data-quality-source-map.md` | 已完成 |
| #40 | 构建期质量门禁 | `docs/raw/45-data-expectations-build-gates.md` | 已完成 |
| #37 | 运行期 Health Checks | `docs/raw/46-data-health-health-checks.md` | 已完成 |
| #39 | Monitoring Views 与告警/issue | `docs/raw/47-monitoring-views-alert-issue-loop.md` | 已完成 |
| #38 | 治理与生命周期 | `docs/raw/48-data-quality-governance-lifecycle.md` | 已完成 |
| #43 | 外部通知安全边界补充 | `docs/raw/49-data-quality-external-notification-security.md` | 第二轮已完成 |
| #41 | 综合与专家评审 | 本文件 | 第二轮修订中 |

---

## 3. 模块边界

| 层级 | Palantir 能力 | 核心问题 | 结果去向 | 结论 |
|---|---|---|---|---|
| 构建期契约 | Data Expectations / `Check` / `Expectation` | 当前 build 是否应该继续，输出是否满足数据契约 | Builds application、dataset History、Data Health | 【事实】这是可阻断生产的质量门禁。 |
| 单资源运行健康 | Data Health Health Checks | 单个 dataset/schedule/table 是否健康，是否新鲜，schema/content 是否异常 | Health tab、Data Lineage、Data Health、通知、issue | 【事实】这是运行期监控，不应默认等同于 build abort。 |
| 规模化监控 | Monitoring Views / Monitoring Rules | 如何覆盖 project/folder/resource scope 中不断变化的资源集合 | Monitoring View subscriptions、email/Foundry notifications、PagerDuty/Slack/webhook | 【事实】这是告警编排和订阅层。 |
| 协同处理 | Notifications / Foundry Issue | 失败后如何通知、分派、讨论、恢复和关闭 | Foundry notification、email、issue、外部系统 | 【事实】Health Checks 可自动创建/关闭 Foundry Issue。 |
| 外部通知安全 | Slack/PagerDuty/webhook export controls | 资源名称、敏感标签和通知 payload 能否离开 Foundry | Slack exportable markings/organizations、severity route、webhook message | 【事实+推断】外部通道需要独立 export/redaction policy，不能只依赖 Viewer permission。 |
| 治理生命周期 | Code Repositories / CI / protected branch / Marketplace | 质量规则如何审查、注册、升级、删除、打包和迁移 | PR review、CI checks、Marketplace packaging、审计历史 | 【推断】完整 Data Quality 依赖平台工程治理底座。 |

关键边界：Data Expectations 的 `Check` 和 Data Health 的 `Health Checks` 名称相似，但生命周期不同。前者是 transform 代码中的 build-time contract，后者是 Data Health 中的 resource health configuration。【事实】

---

## 4. 核心流程

### 4.1 Data Expectations 构建期门禁

```text
Developer edits transform expectations
  -> Code Repository branch
  -> CI registers checks
  -> Branch/default build runs checks
  -> PASS / WARN / FAIL
  -> FAIL aborts job, WARN continues
  -> Check result appears in Builds, History, Data Health
  -> Health tab notifications and issue triggers
```

【事实】Data Expectations 定义在 Code Repository 中，protected branch 上的变更需要同代码一样经过 PR review；Palantir 建议在 development branch build dataset 后再合并。来源：<https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations>

【事实】Python `Check(expectation, "name", on_error="WARN/FAIL")` 的名称必须在 transform 内唯一，并跨 Data Health、Builds application 等应用识别。来源：<https://www.palantir.com/docs/foundry/transforms-python/data-expectations-getting-started>

【事实】pre-condition 绑定在 input 上，但失败时 abort 当前 transform output；若要阻断输入 dataset 自身 build，应在输入 dataset 的 transform 上定义 post-condition。来源：<https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations>

### 4.2 Health Checks 运行期监控

```text
Resource status / dataset transaction / timer / manual schedule
  -> Health check evaluation
  -> Passed / Failed
  -> Dataset Preview Health tab
  -> Data Lineage health coloring and Health tab
  -> Data Health app filtering / watching / notifications
```

【事实】Health checks 可创建在 datasets、schedules、tables 上；Dataset/table 的 Health tab 位于 Dataset Preview，schedule 的 Health 入口位于 Data Lineage 的 Metrics > Health。来源：<https://www.palantir.com/docs/foundry/data-health/overview/>

【事实】time-based checks 可 automatic 或 manual schedule。automatic 模式在 dataset update 和超过阈值时运行；dataset update transaction 会触发评价并重置下一次 threshold。来源：<https://www.palantir.com/docs/foundry/data-health/check-evaluation>

【推断】Health Checks 适合监控生产漂移、freshness、schema/content 异常和 SLA 状态；如果需要阻断 build，应把规则实现为 Data Expectations 或构建系统内门禁。

### 4.3 Monitoring Views 与告警/issue 闭环

```text
Scope discovers resources
  -> Monitoring rule or health check evaluates
  -> Alert severity LOW / MEDIUM / HIGH
  -> Subscribers receive Foundry/email alerts
  -> Optional PagerDuty / Slack / webhook routes with export/redaction policy
  -> Health check failure can create Foundry Issue
  -> Monitoring alert resolve can notify external routes
  -> Health check resolve can close issue
```

【事实】Monitoring Views 是 monitoring rules 与 health checks 的集合，支持 static/dynamic scope；订阅用户可按 severity 收到 alerts。来源：<https://www.palantir.com/docs/foundry/monitoring-views/overview>

【事实】接收 Monitoring View alert 要求用户同时拥有被监控资源和 monitoring view 的 `Viewer` permission。来源：<https://www.palantir.com/docs/foundry/monitoring-views/overview>

【事实】Health Checks 可在 failed check 时自动创建 Foundry Issue，并可在 check resolves 后自动关闭 issue。来源：<https://www.palantir.com/docs/foundry/data-health/notifications/>

【事实】Monitoring Views 可把 monitors fire 或 resolve 的 alerts 发送到 PagerDuty、Slack、webhooks；这些外部集成按 severity 配置。Slack resource name 只有在资源上的所有 Markings 和 Organizations 都包含在 Slack source 的 exportable markings list 时才显示，否则显示 RID。来源：<https://www.palantir.com/docs/foundry/monitoring-views/external-systems>

【推断】Foundry `Viewer` permission 约束 Foundry 内订阅和 alert 接收；外部通道还需要独立 export/redaction policy。不能把 Slack、PagerDuty、webhook、email 的最终接收者权限等同于 Foundry Viewer。

---

## 5. 能力矩阵

| 能力 | Foundry 表现 | 自建等价能力 | 优先级 |
|---|---|---|---|
| 稳定规则身份 | Check name 维持 history/settings；改名等同删除旧 check 并创建新 check | `rule_id/check_id`、`display_name`、alias、tombstone、retention policy | P0 |
| 质量规则 DSL | Python Expectations 支持 column、schema、primary key、group-by、conditional、foreign value、cross-dataset row count 等；Pipeline Builder 当前覆盖 primary key 和 row count | Typed expectation DSL + low-code basic rules | P0 |
| 规则绑定 | input pre-condition / output post-condition | Rule binding to input/output dataset contract | P0 |
| 失败语义 | `FAIL` abort job；`WARN` continue and report | Build gate runner with hard/soft outcomes | P0 |
| CI 注册 | checks 在 branch CI 中注册 | Rule registry generated and validated in CI | P0 |
| 构建期结果 | check result 进入 Builds、History、Data Health | `BuildCheckResult`：rule、expectation breakdown、build/job、branch、commit、dataset、transaction/view、PASS/WARN/FAIL/ABORT | P0 |
| 运行期结果 | Health checks 覆盖 status/time/size/content/schema/freshness | `HealthCheckResult`：resource type、check type、schedule/build/job granularity、trigger、threshold window、freshness kind、last result | P0 |
| 规则治理 | PR review、protected branch、check name history、Marketplace packaging | Rule lifecycle governance、semantic diff、rename/delete migration、tombstone、install-time rebinding | P0 |
| 规模化监控 | Monitoring Views dynamic scope + rules + severity | `MonitoringAlert`：view、resource type、static/dynamic scope、severity、subscriber、snooze、resolve、permission snapshot | P1 |
| 通知与 issue | Foundry/email/PagerDuty/Slack/webhook；Health Checks 可 auto issue create/close | `IssueLinkage` + alert router；区分 Monitoring alert route 和 Health Check issue trigger | P1 |
| 外部通知安全 | Slack exportable markings/organizations 控制 resource name；webhook message 当前不可自定义 | `ExternalRoutePolicy` + `ExportPolicy` + `PayloadSchema` + receiver/channel audit | P1 |
| 血缘观察 | Dataset Preview、Data Lineage、Health tab、Builds timeline | Lineage-integrated health view and impact navigation | P2 |

---

## 6. 自建参考架构

```text
Authoring Layer
  Code Repo / Low-code Builder
    -> Quality Rule Registry
      -> Build Gate Runner
        -> Build Result / Abort / Warn
          -> Quality Result Store
            -> Health View / Lineage View
              -> Monitoring View Engine
                -> Alert Router
                  -> Notification / Issue / External Systems

Governance Layer
  PR Review / Protected Branch / CI / Owner Policy / Audit / Marketplace Packaging
```

最小模块：

| 模块 | 最小职责 | 必要元数据 |
|---|---|---|
| Quality Rule Registry | 注册规则、校验唯一性、绑定 dataset input/output、记录版本 | rule_id、display_name、alias/tombstone、scope、dataset、branch、commit、owner、FAIL/WARN、retention policy |
| Expectation DSL | 表达 schema、主键、空值、范围、枚举、正则、聚合、分组、跨 dataset 关系 | expression AST、engine support、cost class |
| Build Gate Runner | 在 build job 内执行规则，产生 PASS/WARN/FAIL/ABORT | build id、job id、transaction/view、runtime、breakdown |
| BuildCheckResult Store | 保存构建期规则结果 | rule id、expectation breakdown、input/output binding、build/job id、branch、commit、dataset、transaction/view、outcome、duration、error |
| Health Check Evaluator | 对资源状态、freshness、content、schema、size 做运行期评价 | resource id、resource type、check type、schedule/build/job granularity、trigger、threshold window、manual/automatic schedule、last result |
| HealthCheckResult Store | 保存运行期健康检查结果 | check id、resource id、evaluation trigger、freshness kind、status、observed value、threshold、history retention |
| Monitoring View Engine | 发现 scope 内资源并应用 monitoring rules | view id、resource type、supported scope type、scope query、dynamic membership、severity、subscriber、Viewer permission snapshot |
| MonitoringAlert Store | 管理 alert 状态 | alert id、view/rule/check、resource、severity、fire/resolved/snoozed state、snooze scope、failure reason、lineage/run-history target |
| Alert Router | 将 failed result/alert 发送到 Foundry/email/PagerDuty/Slack/webhook | severity route、receiver/channel、permission snapshot、export policy、redaction result、dedupe key |
| Issue Workflow | 自动创建、分派、恢复、关闭质量 issue | issue id、source alert/check、assignee、state、close condition、reopen/dedupe policy、rename/delete binding |
| External Export Controller | 控制外部通知可发字段和资源名 | exportable markings、organizations、payload schema、RID/name policy、secret reference、receiver audit |
| Governance Controller | 管理 PR review、CI 注册、rename/delete、tombstone、打包安装 | approval policy、rule diff、audit trail、package binding |

设计原则：

1. 【建议】不要用规则名称做唯一主键；应有稳定 `rule_id/check_id`，展示名可改，rename 保留 alias 和历史。
2. 【建议】build-time expectations 与 runtime health checks 共享结果视图，但不要共享失败语义；运行期告警不能直接替代构建期 abort。
3. 【建议】增量场景必须声明 check scope：full dataset、affected partition、delta-only。若选择 delta-only，必须明示它弱于 Foundry 的 full-dataset checks 语义。
4. 【建议】issue/notification 配置不要直接跨环境打包；安装时应重新绑定 owner、watcher、assignee、外部 endpoint 和 export/redaction policy。
5. 【建议】质量失败排查必须能跳转到 lineage、build history、job timeline、logs、rule diff 和最近数据/代码变更。
6. 【建议】运行期 health check 必须保留 schedule/build/job 粒度、transaction freshness 与 business timestamp freshness、automatic/manual trigger、threshold reset 等字段，否则容易造成重复告警或责任边界错误。
7. 【建议】外部通知不能只记录 route；必须记录实际发送 payload 的脱敏结果，尤其是 resource name 是否因 markings/organizations 未 exportable 而降级为 RID。

---

## 7. 关键风险与证据缺口

| 风险/缺口 | 当前结论 | 影响 |
|---|---|---|
| check result 内部模型未公开 | 【待验证】公开文档未披露 Data Expectations result 与 Health Checks result 是否共享同一内部 schema、ID 和保留策略。 | 自建时不能照搬内部实现，只能设计自己的统一结果模型。 |
| 语言等价性未完全验证 | 【待验证】本轮主要确认 Python Transforms；Java/SQL/R 等是否具备等价 Data Expectations 能力未逐页核验。 | 不能把 Python DSL 能力无条件外推到所有 transform 语言。 |
| Monitoring severity 存在文档差异 | 【待验证】核心模型是 LOW/MEDIUM/HIGH，但部分规则文本出现 critical 表述。 | 自建 severity 模型应保留扩展余地。 |
| Health Checks build abort 未证实 | 【事实】当前只确认 Data Expectations 可 build abort；Health Checks 主要是运行期监控/告警。 | 产品文案和架构不能把 Health Checks 误称为构建期阻断能力。 |
| Marketplace packaging 仍有限制 | 【事实】带 Foundry issue 创建配置的 health check validation 不受支持；Data expectation health checks 随 transformation 自动加入且 packager 不能手动增删。 | 自建模板/Marketplace 要区分强制规则与环境相关配置。 |
| 告警去重与 issue 重开未公开 | 【待验证】Data Health issue 自动 create/close 已确认，但去重、升级、重开、rename 后绑定未展开。 | 自建 issue workflow 需要独立设计状态机和 dedupe 策略。 |
| 外部通知安全边界未完全公开 | 【事实】Slack resource name 受 exportable markings/organizations 控制；【待验证】PagerDuty/webhook/email payload 脱敏、签名、重试、接收者权限边界未完整公开。 | 自建外部通知必须单独设计 export/redaction policy，不能只依赖 Viewer permission。 |

---

## 8. 专家评审记录

本轮综合完成后执行专家评审，评审维度包括：

1. Foundry 数据工程专家：Data Expectations、build abort、CI 注册、incremental full-dataset checks。
2. 数据质量平台专家：规则 DSL、结果模型、阻断与告警边界。
3. 可观测性/运维专家：Data Health、Health Checks、Monitoring Views、通知和 issue 闭环。
4. 数据治理专家：protected branch、PR review、规则命名、Marketplace packaging、历史保留。

### 第一轮评审结果

| 专家 | Verdict | 主要意见 | 处理 |
|---|---|---|---|
| Foundry 数据工程专家 | PASS | 核心事实链准确；建议收紧 Monitoring Views URL、issue 表述和自建 severity 字段 | 已修订 |
| 数据质量平台专家 | FAIL | 结果模型过粗，运行期检查边界被压平，规则身份治理应为 P0 | 已扩展能力矩阵和架构模型 |
| 可观测性/运维专家 | PASS | 主结论准确；建议收紧 resolve/issue 和外部 URL | 已修订 |
| 数据治理专家 | FAIL | Viewer permission 被过度外推到外部通知通道；缺 Slack exportable markings/organizations 结论 | 已新增 #43 / raw 49 并修订 |

### 第二轮修订项

1. 新增 `docs/raw/49-data-quality-external-notification-security.md`，补充外部通知安全边界。
2. 将稳定规则身份、rename/delete、tombstone、history retention 提升为 P0。
3. 将结果模型拆成 `BuildCheckResult`、`HealthCheckResult`、`MonitoringAlert`、`IssueLinkage` 和 `ExternalRoutePolicy/ExportPolicy`。
4. 明确 Health Check issue auto create/close 与 Monitoring View external alert route 的边界。
5. 明确外部通知需要 export/redaction policy，Slack resource name 受 exportable markings/organizations 控制。

### 第二轮复审结果

| 专家 | Verdict | 结论 |
|---|---|---|
| 数据质量平台专家 | PASS | 上一轮 4 个 blocking findings 已解除：结果模型已拆分，运行期边界已补全，规则身份治理已升为 P0，Monitoring Views 与 Health Checks 元数据已区分。 |
| 数据治理专家 | PASS | 上一轮 2 个 blocking findings 已解除：Viewer permission 已收窄为 Foundry 内部约束，Slack exportable markings/organizations 和外部 export/redaction policy 已进入综合结论。 |

最终评审结论：通过。剩余 PagerDuty/webhook/email payload、签名、重试、RID 敏感性、issue dedupe/reopen 等问题已作为非阻断证据缺口记录，不影响本轮综合结论成立。

---

## 9. 第二轮自检

| 检查项 | 结果 |
|---|---|
| 每份 raw 文档是否有 3~5 条总结/洞察 | 通过 |
| 是否区分 Data Expectations `Check` 与 Data Health `Health Checks` | 通过 |
| 是否避免把 Health Checks 写成 build abort 能力 | 通过 |
| 是否标注事实/推断/建议/待验证 | 通过 |
| 是否包含来源 URL 和 issue map | 通过 |
| 是否给出自建平台建议 | 通过 |
| 是否补强自建结果模型和生命周期模型 | 通过 |
| 是否修正 Viewer permission 外推到外部通知的问题 | 通过 |
| 是否记录第二轮 follow-up issue #43 | 通过 |

---

## 10. 参考来源

### 本轮 raw 文档

- `docs/raw/44-data-quality-source-map.md`
- `docs/raw/45-data-expectations-build-gates.md`
- `docs/raw/46-data-health-health-checks.md`
- `docs/raw/47-monitoring-views-alert-issue-loop.md`
- `docs/raw/48-data-quality-governance-lifecycle.md`
- `docs/raw/49-data-quality-external-notification-security.md`

### Palantir 官方资料

- Define data expectations: <https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations/>
- Python data expectations getting started: <https://www.palantir.com/docs/foundry/transforms-python/data-expectations-getting-started>
- Python data expectations reference: <https://www.palantir.com/docs/foundry/transforms-python/data-expectations-reference/>
- Pipeline Builder data expectations overview: <https://www.palantir.com/docs/foundry/pipeline-builder/dataexpectations-overview>
- Data Health: <https://www.palantir.com/docs/foundry/observability/data-health>
- Health checks overview: <https://www.palantir.com/docs/foundry/data-health/overview/>
- Health checks check evaluation: <https://www.palantir.com/docs/foundry/data-health/check-evaluation>
- Health checks checks reference: <https://www.palantir.com/docs/foundry/data-health/checks-reference/>
- Health checks notifications and issues: <https://www.palantir.com/docs/foundry/data-health/notifications/>
- Monitoring views overview: <https://www.palantir.com/docs/foundry/monitoring-views/overview>
- Monitoring views external systems: <https://www.palantir.com/docs/foundry/monitoring-views/external-systems>
- Monitoring rules reference: <https://www.palantir.com/docs/foundry/monitoring-views/rules-reference>
- Add health checks to Marketplace product: <https://www.palantir.com/docs/foundry/data-health/marketplace-data-health/>
- Builds and checks FAQ: <https://www.palantir.com/docs/foundry/data-health/builds-checks-faq/>
