# Dataset 与传统 dt 分区数据模型差异调研计划

**日期：** 2026-05-30  
**Epic：** [#28](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/28)  
**目标：** 基于专家圆桌结论，拆解并行调研任务，形成有证据链的数据模型差异分析。

---

## 1. 总结与洞察

1. 【推断】本专题的核心不是“Foundry 有没有分区”，而是 `table + dt + task_instance` 与 `dataset + branch + transaction/view` 两套主坐标的差异。
2. 【推断】传统 `dt` 同时承担物理布局、业务日期、调度实例、补数边界、SLA、生命周期和血缘定位，是一个过载但有效的生产控制面。
3. 【推断】Foundry Dataset transaction 能提供版本证据，但不天然提供业务日期解释；迁移时必须补 `business_date`、`run_id`、`partition manifest` 和 coverage lineage。
4. 【建议】并行调研按证据域拆分：Foundry 官方语义、传统数仓生产语义、湖仓布局成本、治理审计元数据、迁移风险案例。
5. 【建议】最终综合需经过专家组复审，重点检查是否把 transaction 误当 `dt`、是否把 partition 概念混用、是否遗漏生产语义。

---

## 2. Issue Map

| Issue | 角色 | 调研域 | 输出 |
|---|---|---|---|
| [#28](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/28) | Epic | 总规划与跟踪 | 本计划、最终状态评论 |
| [#29](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/29) | Agent A | Foundry Dataset transaction/view 证据链 | `docs/raw/39-foundry-dataset-transaction-view-evidence.md` |
| [#32](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/32) | Agent B | 传统 dt 分区生产控制语义 | `docs/raw/40-traditional-dt-partition-production-semantics.md` |
| [#34](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/34) | Agent C | 湖仓布局、分区裁剪与成本模型 | `docs/raw/41-lakehouse-layout-partition-cost-model.md` |
| [#30](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/30) | Agent D | 治理、血缘、审计与元数据契约 | `docs/raw/42-governance-lineage-audit-contracts.md` |
| [#33](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/33) | Agent E | 迁移风险案例与双坐标设计模式 | `docs/raw/43-migration-risk-dual-coordinate-patterns.md` |
| [#31](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/31) | Coordinator + Expert Review | 综合差异分析与专家组复审 | 更新 `docs/synthesis/palantir-dataset-no-dt-partition-impact.md` |

---

## 3. Parallel Research Protocol

所有调研 Agent 必须遵守：

1. 优先引用官方资料：Palantir、Apache Hive、DataWorks、Iceberg、BigQuery、Snowflake、Spark 等。
2. 每份 raw 文档开头必须输出 3~5 条总结或洞察。
3. 所有结论必须标记【事实】、【推断】、【建议】或【待验证】。
4. 不同 Agent 不互相等待，但需避免重复：每个 Agent 只覆盖自己的证据域。
5. 输出必须能被最终综合文档直接引用：包含来源 URL、关键表格、风险点和证据缺口。

---

## 4. Expert Review Protocol

综合后邀请专家组复审，至少覆盖：

1. Foundry 平台架构专家：检查 Dataset transaction/view/Ontology 表述是否准确。
2. 传统数据仓库/调度专家：检查 `dt` 生产语义、补数、SLA、跨周期依赖是否完整。
3. 湖仓/查询引擎专家：检查 partition/projection/clustering/compaction 概念边界是否混用。
4. 数据治理/血缘/审计专家：检查 run-to-transaction、manifest、quality、audit 模型是否可落地。

复审结论需要记录为：

- 接受的修订项
- 被拒绝的修订项及原因
- 未解决风险
- 下一轮 follow-up issue 建议
