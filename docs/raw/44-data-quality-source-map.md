# 44 — Palantir Data Quality 资料源与术语基线

**日期：** 2026-05-30  
**关联 Issue：** #36  
**所属 Epic：** #35  
**类型：** Story 调研 / 资料源索引与术语基线  
**采集范围：** S01-S15；S01-S14 为 Palantir 官方公开文档，S15 为仓库内 #10 既有调研。

---

## 1. 总结与洞察

1. 【事实】Palantir 公开文档没有把 “Data Quality” 描述为单个独立产品页；本轮可确认的质量能力由 Data Expectations、Data Health、Health Checks、Monitoring Views、Monitoring Rules、notifications/issues 等页面共同覆盖。
2. 【事实】Data Expectations 是应用在 dataset input/output 上的 requirement/expectation，并通过 `Check(expectation, name, on_error)` 进入 build；`FAIL` 会 abort job，check name 会跨 Data Health 和 Builds application 标识同一检查。
3. 【事实】Data Health 是 Foundry 的资源健康监控应用，包含两类主要能力：Monitoring views 用 scope-based monitoring rules 做规模化覆盖，Health checks 用单资源细粒度检查做内容/schema/freshness 等验证。
4. 【推断】Palantir 的 Data Quality 边界应按生命周期分层理解：构建前后契约验证由 Data Expectations 承担，运行期资源健康由 Health Checks/Monitoring Views 承担，告警和 Foundry Issue 负责闭环。
5. 【待验证】公开文档能证明 checks、builds、Data Health、notifications/issues 的功能联动，但未披露 check result 的统一存储模型、内部事件 ID、历史保留策略和告警去重实现。

---

## 2. 可信度与标注规则

| 标签 | 判定标准 | 使用边界 |
|---|---|---|
| 【事实】 | 由 Palantir 官方文档或仓库内已读文档直接支持 | 可作为后续综合文档的事实陈述 |
| 【推断】 | 由多个事实组合出的工程边界或架构判断，官方未逐字给出 | 可进入自建平台启示，但需保留证据链 |
| 【待验证】 | 官方公开文档未披露，或仅有间接迹象 | 只能作为后续 Story/专家复审问题 |

---

## 3. S01-S15 资料源索引

| 编号 | 来源 | 类型 | 覆盖范围 | 采集日期 | 可信度 | 关键事实/用途 |
|---|---|---|---|---|---|---|
| S01 | https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations/ | 官方文档 | Data Expectations 概览、pre/post-condition、build abort、CI/Data Health/Builds application 关系 | 2026-05-30 | 高 | 【事实】pre-condition 用于 transform input，post-condition 用于 output；pre-condition 失败时 abort 当前 transform 的 output，不是 abort 输入 dataset。 |
| S02 | https://www.palantir.com/docs/foundry/transforms-python/data-expectations-getting-started | 官方文档 | Python Transforms 中 `Check`、`Expectation`、`on_error`、input/output 绑定 | 2026-05-30 | 高 | 【事实】`Check(expectation, 'Check unique name', on_error='WARN/FAIL')` 是 Python API 基本结构；check name 必须在 transform 内唯一，并跨 Data Health/Builds application 识别。 |
| S03 | https://www.palantir.com/docs/foundry/transforms-python/data-expectations-reference/ | 官方文档 | Expectations DSL：operators、column、timestamp、array、group-by、primary key、schema、conditional、foreign value、cross-dataset row count | 2026-05-30 | 高 | 【事实】Expectations 是可组合 DSL；可覆盖列级、schema、主键、group-by、条件、跨 dataset 行数比较等数据条件。 |
| S04 | https://www.palantir.com/docs/foundry/pipeline-builder/dataexpectations-overview | 官方文档 | Pipeline Builder Data Expectations | 2026-05-30 | 高 | 【事实】Pipeline Builder 当前支持 output 上的 primary key 和 row count 两类 expectations。 |
| S05 | https://www.palantir.com/docs/foundry/observability/data-health | 官方文档 | Data Health 顶层定位、Monitoring views vs Health checks、通知入口 | 2026-05-30 | 高 | 【事实】Data Health 监控 datasets、builds、functions、actions、automates 等资源；Monitoring views 面向规模化 scope，Health checks 面向单资源细粒度质量验证。 |
| S06 | https://www.palantir.com/docs/foundry/data-health/overview/ | 官方文档 | Health checks 概览、资源类型、Health tab、Data Lineage/Dataset Preview 入口 | 2026-05-30 | 高 | 【事实】Health checks 可用于 datasets、schedules、tables；Dataset Preview 和 Data Lineage 都是查看/配置健康状态的入口。 |
| S07 | https://www.palantir.com/docs/foundry/data-health/check-types/ | 官方文档 | Health check 类型边界 | 2026-05-30 | 中高 | 【事实】页面用于定义 types of checks；本轮仅用作类型索引，不在 Agent A 文档展开每类参数。 |
| S08 | https://www.palantir.com/docs/foundry/data-health/check-evaluation | 官方文档 | check evaluation/schedules、automatic/manual、transaction update、threshold reset | 2026-05-30 | 高 | 【事实】time-based checks 可 automatic 或 manual schedule；automatic 在 dataset update 和超过阈值时运行，dataset update 会重置下一次 threshold。 |
| S09 | https://www.palantir.com/docs/foundry/data-health/checks-reference/ | 官方文档 | Health checks 参数参考 | 2026-05-30 | 中高 | 【事实】该页是可用 check 参数参考；具体参数应由 Agent C 在运行期监控文档逐项展开。 |
| S10 | https://www.palantir.com/docs/foundry/data-health/notifications/ | 官方文档 | Foundry notifications、email、Foundry Issue 自动创建/关闭 | 2026-05-30 | 高 | 【事实】Data Health 可在 check 失败时自动创建 Issue，也可在 check resolved 后自动关闭 Issue，并可指定 assignee。 |
| S11 | https://www.palantir.com/docs/foundry/monitoring-views/overview | 官方文档 | Monitoring Views、scope、subscription、external integrations、alert troubleshooting | 2026-05-30 | 高 | 【事实】Monitoring views 支持 static/dynamic scope；订阅用户可按 severity 收 alerts；可集成 PagerDuty、Slack、webhook。 |
| S12 | https://www.palantir.com/docs/foundry/monitoring-views/rules-reference | 官方文档 | Monitoring rules reference、resource type、severity | 2026-05-30 | 高 | 【事实】Monitoring rules 有 Alert severity 字段，severity 可为 Low/Medium/High；不同资源类型有不同 rule。 |
| S13 | https://www.palantir.com/docs/foundry/data-health/marketplace-data-health/ | 官方文档 | Health checks Marketplace packaging | 2026-05-30 | 中高 | 【事实】该页覆盖将 health checks 加入 Marketplace product 的 Beta 能力；生命周期限制需由 Agent E 深挖。 |
| S14 | https://www.palantir.com/docs/foundry/data-health/builds-checks-faq/ | 官方文档 | Builds/checks 运维 FAQ、CI ownership、timeout、debugging | 2026-05-30 | 高 | 【事实】FAQ 覆盖 CI job fails because repository does not own dataset、checks timeout、build debugging 等运维问题。 |
| S15 | `docs/raw/26-pro-code-governance-quality-observability.md` | 仓库内调研 | #10 高码质量、测试、血缘、权限与可观测性背景 | 2026-05-30 复读 | 中高 | 【事实】#10 已把 repository checks、Data Expectations、Data Health、lineage、markings、observability 作为高码治理闭环分析；本文件只继承边界，不重复展开。 |

说明：【推断】S07/S09/S13 标为“中高”不是质疑官方来源，而是 Agent A 仅建立索引，未逐项验证页面内所有参数、限制和版本差异。

---

## 4. 术语边界

| 术语 | 基线定义 | 不是/不要混淆 | 依据与状态 |
|---|---|---|---|
| Data Quality | 【推断】Foundry 中围绕数据契约、构建阻断、运行健康、规模化监控、通知和 issue 闭环形成的质量控制面。 | 不是公开文档中一个单页定义完整边界的独立模块；也不等同于 Data Expectations。 | S01-S14 综合推断。 |
| Data Expectations | 【事实】应用到 dataset inputs/outputs 的 requirements/expectations，用来创建 checks，提高 pipeline stability。 | 不是 Data Health 本身；不是只能用于运行期告警。 | S01、S02、S04。 |
| Expectation | 【事实】一个可执行的数据条件表达式；Python 文档中 expectation 可以是单一 expectation，也可以是 any/all 等 composite expectation。 | 不是完整 check；没有 name/on_error 时不能独立承担 build 行为边界。 | S02、S03。 |
| Check | 【事实】由 expectation、唯一名称和 `on_error` 行为组成，并被绑定到单个 input 或 output；`FAIL` 默认会 abort job，`WARN` 用于不阻断但记录/监控。 | 不等同于 Health Check；Data Expectations 的 Check 是 transform 代码/API 概念，Health Checks 是 Data Health 中资源检查能力。 | S02。 |
| Check result | 【推断】某次 check evaluation 的通过/失败/告警结果，会在 Builds application、Data Health 或 Health tab 中被展示或触发通知。 | 公开文档未披露统一结果表 schema、事件 ID、保留周期；不能断言内部存储实现。 | S01、S02、S05、S06、S10；内部模型为【待验证】。 |
| pre-condition | 【事实】绑定到 transform input 的 check，通常在继续 build 前验证输入结构或内容的关键假设。失败时 abort 当前 transform 的 output。 | 不是阻断输入 dataset 自身 build 的机制；若要 abort 输入 dataset build，应在输入 dataset 的 transform 上定义 post-condition。 | S01。 |
| post-condition | 【事实】绑定到 transform output 的 check，通常用于保证 dataset SLA 并保护下游依赖。 | 不是运行期 Health Check；它属于 Data Expectations build-time contract。 | S01。 |
| Data Health | 【事实】Foundry 应用，用于监控平台资源健康，并配置 alerts；覆盖 datasets、builds、functions、actions、automates 等资源。 | 不是只针对 dataset content/schema 的功能；Data Health 是 Monitoring views 与 Health checks 的上层应用入口。 | S05。 |
| Health Checks | 【事实】Data Health 中面向单个资源的细粒度 checks，支持 dataset status、time、size、content、schema 等问题监控，并产生通知/邮件。 | 不等同于 Data Expectations 的 `Check` API；Health Checks 可独立于 workflow 做单资源质量检查。 | S05、S06。 |
| Monitoring Views | 【事实】Data Health 中用 scope-based monitoring rules 大规模监控资源的能力；支持 single/folder/project/workflow lineage/workshop/OSDK application 等动态范围，具体取决于资源类型。 | 不是每个 dataset 单独手工配置 Health Check 的替代品；官方建议内容/schema 细粒度验证仍考虑 Health Checks。 | S05、S11。 |
| Monitoring Rules | 【事实】Monitoring Views 中配置在资源 metrics 上的规则，包含 alert severity，触发后产生 alerts。 | 不是 Data Expectations DSL；规则主要面向资源指标、失败次数、延迟、stream lag 等运行指标。 | S11、S12。 |
| Foundry Issue | 【事实】Data Health 可在 check 失败时自动 report/create Issue，用于 debugging/discussion；check resolved 后可自动关闭。 | 不是外部 Jira 的同义词；公开文档这里指 Foundry 内 Issue。与外部 ITSM/Jira 集成关系需另证。 | S10。 |

---

## 5. 核心边界图谱

| 层级 | 主要能力 | 资源粒度 | 触发/评价 | 结果去向 | 可信度 |
|---|---|---|---|---|---|
| 构建期契约 | Data Expectations + `Check` | Transform input/output dataset | build 时检查 expectation；`FAIL` abort job，`WARN` 不阻断 | Builds application、Data Health/Health tab 可见或可监控 | 【事实】 |
| 单资源运行健康 | Health Checks | Dataset、schedule、table 等单资源 | automatic/manual；dataset update 或 threshold 到达可触发 time-based checks | Foundry notifications、email、Issue、Health tab | 【事实】 |
| 规模化资源监控 | Monitoring Views + Monitoring Rules | Single、folder、project、workflow lineage 等 scope | metrics/rules 触发 alerts，severity 可配置 | subscriptions、email/Foundry notifications、PagerDuty/Slack/webhook | 【事实】 |
| 治理与运维 | Marketplace packaging、Builds/checks FAQ、CI ownership、timeout debugging | Product/repository/build/check | package/install/CI/debug 流程 | 后续治理、支持和故障定位 | 【事实】 |
| 统一质量控制面 | 规则注册、阻断、结果、告警、issue、lineage/preview 入口 | 跨 dataset/build/resource | 由构建和运行事件共同驱动 | 统一健康视图与处理闭环 | 【推断】 |

---

## 6. 与既有 #10 的关系

1. 【事实】#10 已确认 Data Expectations 可作为 build-time check，失败时可配置 abort build，失败结果会进入 Builds application、History tab 和 Data Health 视野。
2. 【事实】#10 已把 repository checks、protected branch PR review、Data Expectations、Data Health、Data Lineage、Markings 和 Observability 放入高码治理闭环。
3. 【推断】本文件继承 #10 的“高码治理闭环”结论，但本轮 #36 的职责更窄：只建立 Data Quality 资料源和术语基线，不展开 repository checks、Marking propagation、Workflow Lineage 等非 Data Quality 主线。
4. 【推断】与 #10 相比，本文件新增的贡献是把 Data Expectations `Check` 与 Data Health `Health Checks` 明确拆开，避免后续 Story 把 build-time contract、single-resource health check、scope-based monitoring rule 混称为“规则”。
5. 【待验证】#10 中关于 protected branch review、CI 注册、incremental full-dataset checks 的细节需要由 Agent B/E 在 S01/S14 与 Code Repositories 文档中再次核验。

---

## 7. 后续 Story 引用建议

| 后续 Story | 建议引用方式 | 必引来源 |
|---|---|---|
| #40 Data Expectations 构建期质量门禁 | 引用第 4 节中 Data Expectations、Expectation、Check、pre-condition、post-condition 的术语边界，并展开 define/register/run/monitor 生命周期。 | S01、S02、S03、S04、S14 |
| #37 Data Health 与 Health Checks 运行期监控 | 引用第 4 节 Data Health/Health Checks/Check result 边界，逐项展开 check types、evaluation、Health tab、lineage/preview 入口。 | S05、S06、S07、S08、S09、S10 |
| #39 Monitoring Views、告警与 Issue 闭环 | 引用 Monitoring Views/Monitoring Rules/Foundry Issue 定义，重点展开 dynamic scope、severity、subscriptions、external integrations、snooze、alert debug。 | S05、S10、S11、S12 |
| #38 Data Quality 治理与生命周期 | 引用 S13/S14 的 packaging、CI ownership、timeout 和 #10 的 protected branch 背景，补齐规则变更审查、历史保留、Marketplace 限制。 | S01、S13、S14、S15 |
| #41 综合结论 | 使用第 5 节边界图谱作为综合架构的术语地基；重要结论继续区分【事实】和【推断】。 | S01-S15 |

---

## 8. 证据缺口

1. 【待验证】公开文档未披露 Data Expectations check result 与 Health Checks result 是否共享同一内部数据模型、ID 体系和保留策略。
2. 【待验证】公开文档未披露 Data Expectations 在所有语言/运行引擎中的功能等价性；本轮 S02/S03 主要确认 Python Transforms。
3. 【待验证】S07/S09 的每类 Health Check 参数、默认阈值和适用资源需要 Agent C 逐项核验，Agent A 不应代替运行期监控 Story 下结论。
4. 【待验证】S11/S12 的 Monitoring Rules 对所有资源类型的完整列表、默认 severity 和告警去重/聚合机制需 Agent D 深挖。
5. 【待验证】S13 Marketplace packaging 的 Beta 限制、安装后规则升级策略、产品化迁移约束需 Agent E 深挖。
6. 【待验证】Foundry Issue 与外部 Jira/ITSM 的关系未由 S10 直接证明；当前只能确认 Foundry 内 Issue 自动创建/关闭。
7. 【待验证】#10 中 protected branch review、CI 注册、repository ownership 与 Data Expectations 的治理边界需要在 #40/#38 中结合 Code Repositories 文档复核。

---

## 9. 参考来源

### Palantir 官方文档

- S01 Define data expectations: https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations/
- S02 Python data expectations getting started: https://www.palantir.com/docs/foundry/transforms-python/data-expectations-getting-started
- S03 Python data expectations reference: https://www.palantir.com/docs/foundry/transforms-python/data-expectations-reference/
- S04 Pipeline Builder data expectations overview: https://www.palantir.com/docs/foundry/pipeline-builder/dataexpectations-overview
- S05 Data Health: https://www.palantir.com/docs/foundry/observability/data-health
- S06 Health checks overview: https://www.palantir.com/docs/foundry/data-health/overview/
- S07 Health checks types of checks: https://www.palantir.com/docs/foundry/data-health/check-types/
- S08 Health checks check evaluation: https://www.palantir.com/docs/foundry/data-health/check-evaluation
- S09 Health checks reference: https://www.palantir.com/docs/foundry/data-health/checks-reference/
- S10 Health checks notifications and issues: https://www.palantir.com/docs/foundry/data-health/notifications/
- S11 Monitoring views overview: https://www.palantir.com/docs/foundry/monitoring-views/overview
- S12 Monitoring rules reference: https://www.palantir.com/docs/foundry/monitoring-views/rules-reference
- S13 Add health checks to Marketplace product: https://www.palantir.com/docs/foundry/data-health/marketplace-data-health/
- S14 Builds and checks FAQ: https://www.palantir.com/docs/foundry/data-health/builds-checks-faq/

### 仓库内参考

- S15 `docs/raw/26-pro-code-governance-quality-observability.md`
- `docs/superpowers/plans/2026-05-30-palantir-data-quality-research-plan.md`
