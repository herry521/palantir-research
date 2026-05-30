# Palantir Data Quality 模块调研计划

**日期：** 2026-05-30  
**Epic：** [#35](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/35)  
**目标：** 研究 Palantir Foundry Data Quality 模块的能力边界、运行机制、治理闭环和自建平台复刻路径。

---

## 1. 脑暴结论与研究大纲

1. 【推断】Palantir 的 Data Quality 不是单一模块，而是由构建期 Data Expectations、运行期 Data Health/Health Checks、规模化 Monitoring Views、通知/issue 闭环和代码治理共同组成的质量控制面。
2. 【事实】Data Expectations 可以在 dataset build 中运行，并可配置失败时 abort build；检查结果进入 Data Health 监控体系。来源：<https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations/>
3. 【事实】Data Health 同时提供 Monitoring views 和 Health checks：前者适合跨资源规模化监控，后者适合单资源内容/schema/freshness 等细粒度质量检查。来源：<https://www.palantir.com/docs/foundry/observability/data-health>
4. 【推断】自建平台不能只做规则 DSL；必须补齐规则注册、构建阻断、质量结果存储、lineage 展示、订阅告警、自动 issue、规则变更审查和历史保留，否则无法达到 Palantir 式闭环。
5. 【建议】并行调研按证据域拆分：资料源与术语、构建期门禁、运行期健康检查、规模化监控告警、治理生命周期、综合与专家评审。

---

## 2. Issue Map

| Issue | 角色 | 调研域 | 输出 |
|---|---|---|---|
| [#35](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/35) | Epic | 总规划与跟踪 | 本计划、最终状态评论 |
| [#36](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/36) | Agent A | Data Quality 资料源与术语基线 | `docs/raw/44-data-quality-source-map.md` |
| [#40](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/40) | Agent B | Data Expectations 构建期质量门禁 | `docs/raw/45-data-expectations-build-gates.md` |
| [#37](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/37) | Agent C | Data Health 与 Health Checks 运行期监控 | `docs/raw/46-data-health-health-checks.md` |
| [#39](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/39) | Agent D | Monitoring Views、告警与 Issue 闭环 | `docs/raw/47-monitoring-views-alert-issue-loop.md` |
| [#38](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/38) | Agent E | Data Quality 治理、代码评审与生命周期 | `docs/raw/48-data-quality-governance-lifecycle.md` |
| [#43](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/43) | Follow-up | 外部通知安全边界补充 | `docs/raw/49-data-quality-external-notification-security.md` |
| [#41](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/41) | Coordinator + Expert Review | 综合结论、自建建议与专家复审 | `docs/synthesis/palantir-data-quality-module-research.md` |

---

## 3. 共享资料源基线

| 编号 | 资料源 | 初始用途 |
|---|---|---|
| S01 | <https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations/> | Data Expectations 概览、构建期阻断、CI 注册、Data Health 集成 |
| S02 | <https://www.palantir.com/docs/foundry/transforms-python/data-expectations-getting-started> | Python Transforms 中 Check/Expectation 的使用形态 |
| S03 | <https://www.palantir.com/docs/foundry/transforms-python/data-expectations-reference/> | Expectations DSL、主键、schema、group-by、conditional、foreign value 等能力 |
| S04 | <https://www.palantir.com/docs/foundry/pipeline-builder/dataexpectations-overview> | Pipeline Builder 中 primary key、row count expectations |
| S05 | <https://www.palantir.com/docs/foundry/observability/data-health> | Data Health 顶层能力：Monitoring views、Health checks、通知集成 |
| S06 | <https://www.palantir.com/docs/foundry/data-health/overview/> | Health checks 创建、资源类型、Data Lineage/Dataset Preview 入口 |
| S07 | <https://www.palantir.com/docs/foundry/data-health/check-types/> | job/build/schedule/freshness 等检查类型边界 |
| S08 | <https://www.palantir.com/docs/foundry/data-health/check-evaluation> | 自动评价、手动 schedule、transaction update、threshold reset |
| S09 | <https://www.palantir.com/docs/foundry/data-health/checks-reference/> | 可用 health checks 参数参考 |
| S10 | <https://www.palantir.com/docs/foundry/data-health/notifications/> | 通知、email、自动创建/关闭 Foundry issue |
| S11 | <https://www.palantir.com/docs/foundry/monitoring-views/overview> | Monitoring Views、动态 scope、subscription、外部系统集成 |
| S12 | <https://www.palantir.com/docs/foundry/monitoring-views/rules-reference> | Monitoring rules 资源类型和 severity 模型 |
| S13 | <https://www.palantir.com/docs/foundry/data-health/marketplace-data-health/> | Health checks 的 Marketplace packaging 与限制 |
| S14 | <https://www.palantir.com/docs/foundry/data-health/builds-checks-faq/> | Builds/checks 故障排查、CI 失败、timeout 等运维细节 |
| S15 | `docs/raw/26-pro-code-governance-quality-observability.md` | 既有高码质量/治理调研背景 |

---

## 4. 并行研究协议

所有调研 Agent 必须遵守：

1. 优先引用 Palantir 官方文档；二级材料只能作为背景，不得替代官方证据。
2. 每份 raw 文档开头必须输出 3~5 条总结或洞察。
3. 所有关键结论必须标记【事实】、【推断】、【建议】或【待验证】。
4. 每个 Agent 只写自己负责的 raw 文档，避免互相覆盖。
5. 所有 raw 文档必须包含来源 URL、关键流程/矩阵、证据缺口和自建平台启示。
6. 如需要复用 #10 的结论，只做引用和差异化补充，不重复粘贴长段内容。

---

## 5. Agent 分工

### Agent A：资料源与术语基线

**Issue:** [#36](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/36)

- [ ] 创建 `docs/raw/44-data-quality-source-map.md`。
- [ ] 汇总 S01-S15 的来源类型、覆盖范围、采集日期和可信度。
- [ ] 定义 Data Quality、Data Expectations、Check、Expectation、Data Health、Health Checks、Monitoring Views、Monitoring Rules、Foundry Issue 的术语边界。
- [ ] 标出与 #10 既有高码质量调研的继承关系和差异。

### Agent B：Data Expectations 构建期质量门禁

**Issue:** [#40](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/40)

- [ ] 创建 `docs/raw/45-data-expectations-build-gates.md`。
- [ ] 研究 define/register/run/monitor 的生命周期。
- [ ] 比较 Python Transforms 与 Pipeline Builder 的 expectations 能力边界。
- [ ] 分析 FAIL/WARN、build abort、pre/post-condition、CI、protected branch review、incremental full-dataset checks 的影响。

### Agent C：Data Health 与 Health Checks 运行期监控

**Issue:** [#37](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/37)

- [ ] 创建 `docs/raw/46-data-health-health-checks.md`。
- [ ] 研究 job/build/schedule/freshness/content/schema checks 的触发条件和评价语义。
- [ ] 解释 automatic/manual schedule、transaction update、threshold reset。
- [ ] 梳理 Dataset Preview、Data Lineage、Data Health 的观察入口。

### Agent D：Monitoring Views、告警与 Issue 闭环

**Issue:** [#39](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/39)

- [ ] 创建 `docs/raw/47-monitoring-views-alert-issue-loop.md`。
- [ ] 研究 Monitoring Views 与 Health Checks 的职责边界。
- [ ] 梳理 dynamic scope、resource type、severity、subscription、Viewer 权限。
- [ ] 研究 Foundry notifications、email、PagerDuty、Slack、webhook、自动 issue 的闭环行为。

### Agent E：治理、代码评审与生命周期

**Issue:** [#38](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/38)

- [ ] 创建 `docs/raw/48-data-quality-governance-lifecycle.md`。
- [ ] 研究质量规则作为代码变更的 PR review、CI 注册和 protected branch 审查。
- [ ] 梳理 check name、历史保留、规则变更、Marketplace packaging 的生命周期约束。
- [ ] 给出自建平台必须补齐的治理能力。

### Coordinator：综合与专家评审

**Issue:** [#41](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/41)

- [ ] 创建 `docs/synthesis/palantir-data-quality-module-research.md`。
- [ ] 集成 #36/#40/#37/#39/#38 的 raw 结论。
- [ ] 输出模块架构、核心流程、能力矩阵、自建优先级、证据缺口和风险清单。
- [ ] 执行专家评审；如未通过，创建下一轮 follow-up issue 并继续调研。

---

## 6. Agent Prompt Template

```markdown
你正在为 Palantir Data Quality 模块调研处理 issue #[issue-number]。

必须阅读：
- docs/superpowers/plans/2026-05-30-palantir-data-quality-research-plan.md
- GitLab issue #[issue-number] 的 issue body
- 与你的调研域相关的共享资料源
- 如涉及高码治理，阅读 docs/raw/26-pro-code-governance-quality-observability.md

规则：
- 优先使用 Palantir 官方文档。
- 每个重要结论标记【事实】、【推断】、【建议】或【待验证】。
- 不得把公开文档没有验证的内部实现写成事实。
- 只写你负责的 raw 文档。
- 文档开头必须有 3~5 条总结或洞察。
- 文末必须包含证据缺口和自建平台启示。
```

---

## 7. 专家评审协议

综合后邀请专家组复审，至少覆盖：

1. Foundry 数据工程专家：检查 Data Expectations、build abort、CI 注册、incremental full-dataset checks 表述是否准确。
2. 数据质量平台专家：检查规则 DSL、规则生命周期、质量结果存储、阻断与告警边界是否完整。
3. 可观测性/运维专家：检查 Data Health、Health Checks、Monitoring Views、通知和 issue 闭环是否可落地。
4. 数据治理专家：检查 protected branch、PR review、权限、审计、Marketplace packaging 和历史保留是否满足治理闭环。

复审结论记录为：

- 通过/不通过
- 接受的修订项
- 被拒绝的修订项及原因
- 未解决风险
- 下一轮 follow-up issue 建议

---

## 8. 完成标准

本专题完成条件：

1. #36、#40、#37、#39、#38 的 raw 文档均完成并能独立引用。
2. #41 的综合文档能独立回答 Palantir Data Quality 模块是什么、如何工作、如何治理、如何自建。
3. 专家评审通过，或未通过项已进入下一轮 issue 并完成补充调研。
4. 交付物已验证、commit、push，并在 #35/#41 评论最终结论链接。
