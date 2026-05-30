# Scheduling

## 摘要与洞察

1. 【事实】Foundry Schedule 的主语是 Dataset graph build，而不是传统业务周期实例；trigger 满足后还要经过 graph resolution、staleness、scope、branch 和 build locking 判断。
2. 【事实+推断】Time / Event / Compound trigger 组合的是状态机 satisfied 状态，不保证多个输入属于同一 `business_date` 或 `data_interval`。
3. 【事实】Schedule run `Succeeded` 只表示 build 被成功发起，不等于 build/job 最终成功；`Ignored` 多数表示未创建 build。
4. 【决策】自研平台应拆开 freshness scheduling 与 business-cycle scheduling；涉及业务日期验收的输出必须通过 ready manifest / business-cycle scheduler。

## Canonical Documents

| 文档 | 用途 |
| --- | --- |
| [docs/synthesis/foundry-schedule-module-deep-dive.md](../synthesis/foundry-schedule-module-deep-dive.md) | Schedule trigger、build resolution、staleness、sync、治理和业务时间边界的主结论。 |

## Supporting Evidence

| 证据 | 精简说明 |
| --- | --- |
| [docs/raw/38-foundry-schedule-module-research-plan.md](../raw/38-foundry-schedule-module-research-plan.md) | 调度模块调研范围、待证伪假设和 agent 拆分。 |
| [docs/raw/27-incremental-scheduling-transaction.md](../raw/27-incremental-scheduling-transaction.md) | 调度、增量 transaction limits、re-trigger 和 Dataset graph build 语义。 |
| [docs/raw/15-job-execution-guarantee.md](../raw/15-job-execution-guarantee.md) | Build 事务隔离、失败回退、并发写保护、资源队列和可观测性。 |
| [docs/synthesis/dataworks-vs-palantir-integration.md](../synthesis/dataworks-vs-palantir-integration.md) | DataWorks 业务周期调度与 Foundry freshness 调度的对照背景。 |

## Related Issues

#11、#46

## Open Questions

- Staleness 指纹/比较算法未公开，尤其是 transaction、schema、JobSpec、branch/fallback 的精确参与规则。
- 多个 pending trigger 在前一 run 未完成时是合并、排队还是去重，公开资料不足。
- Data Connection sync schedule 的完整状态机、sync RID 与 schedule RID 映射仍需验证。
- 是否存在私有部署中的业务周期实例能力，公开资料未确认。
