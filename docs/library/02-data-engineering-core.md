# Data Engineering Core

## 摘要与洞察

1. 【事实】Foundry Dataset 的主坐标是 `Dataset + branch + transaction/view`，不是传统离线数仓的 `table + dt`。
2. 【推断】`dt` 在传统数仓中同时承担业务日期、调度实例、补数、SLA、生命周期和血缘定位；迁移时必须拆成显式契约。
3. 【事实+推断】Foundry Schedule 更偏 Dataset graph freshness，不保证 DataWorks 式业务周期配对。
4. 【建议】自研平台应保留 `business_date`、`data_interval`、`run_id`、`partition_manifest` 和 `active_view_pointer`，让业务周期与数据版本各自清晰。

## 核心链路

```text
Source / Sync
  -> Dataset transaction / view
  -> Transform Contract / Pipeline DAG
  -> Schedule / Build / Incremental processing
  -> Quality evidence / lineage / active view
  -> Consumption / Ontology / API
```

这条链路的关键不是把每个组件单独做出来，而是确保每次运行都能回答：

- 输入和输出分别是哪一个 transaction/view。
- 运行对应哪个代码版本、branch、schedule 和业务周期。
- 输出是否通过质量门禁，是否进入可消费 active view。
- 下游消费时读取的是哪个稳定视图，而不是哪个瞬时文件集合。

## 对传统 `dt` 模型的迁移要求

| 传统 `dt` 承担的职责 | 自研平台建议承载方式 | 参考文档 |
| --- | --- | --- |
| 业务日期 | `business_date` / `data_interval` 字段或元数据 | [Dataset no-dt impact](../synthesis/palantir-dataset-no-dt-partition-impact.md) |
| 调度实例 | `run_id`、schedule run、build run | [Scheduling](../topics/scheduling.md) |
| 补数与重跑 | ready manifest、active pointer、coverage lineage | [Migration risk patterns](../raw/43-migration-risk-dual-coordinate-patterns.md) |
| 物理裁剪 | Hive-style partitioning、projection、file layout | [Lakehouse layout](../raw/41-lakehouse-layout-partition-cost-model.md) |
| 审计与验收 | run-to-transaction、quality evidence、access snapshot | [Governance contracts](../raw/42-governance-lineage-audit-contracts.md) |

## 与调度的边界

Foundry Schedule 的公开语义更接近 freshness scheduler：触发条件满足后，平台解析 Dataset graph、staleness、scope、branch 和 build locking，再决定是否创建 build。它不天然表达“上游 A 和 B 都属于同一业务日期”的配对关系。

因此，自研平台应拆开：

- Data Version Identity：transaction/view、staleness、input modification、logic version。
- Run Identity：business_date、data_interval、补数、重跑、SLA、实例依赖。

## 主要证据

- [Palantir Dataset 无默认 dt 分区模型的数据模型差异分析](../synthesis/palantir-dataset-no-dt-partition-impact.md)
- [DataWorks 与 Palantir Data Integration 差异研究](../synthesis/dataworks-vs-palantir-integration.md)
- [Foundry Schedule 模块运行模式深度调研](../synthesis/foundry-schedule-module-deep-dive.md)
- [Foundry Dataset transaction/view 证据链](../raw/39-foundry-dataset-transaction-view-evidence.md)
- [增量计算、调度与 Dataset Transaction](../raw/27-incremental-scheduling-transaction.md)
