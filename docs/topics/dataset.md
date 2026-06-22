# Dataset

## 摘要与洞察

1. 【事实】Foundry Dataset 的基础坐标不是传统 `table + dt`，而是 `Dataset + branch + transaction/view`；物理层仍可使用 Hive-style partitioning、projection 和 repartition 等布局机制。
2. 【推断】传统 `dt` 同时承载业务日期、调度实例、补数、SLA、生命周期、血缘定位和物理裁剪；迁移到 Dataset transaction 后必须拆成显式契约。
3. 【建议】自建平台应保留 `business_date`、`data_interval`、`run_id`、`active_view_pointer` 和 `partition_manifest`，不要把 transaction commit 直接等同于业务可消费成功。
4. 【推断】Dataset 层负责版本、血缘、权限和转换；业务对象、动作和应用语义应由 Ontology 或语义层承接。

## Canonical Documents

| 文档 | 用途 |
| --- | --- |
| [docs/synthesis/palantir-dataset-no-dt-partition-impact.md](../synthesis/palantir-dataset-no-dt-partition-impact.md) | Dataset transaction/view 与传统 `dt` 分区模型差异主结论。 |
| [docs/synthesis/palantir-dataset-vs-data-warehouse.md](../synthesis/palantir-dataset-vs-data-warehouse.md) | Dataset / Ontology 与传统数仓建模范式对比。 |
| [docs/synthesis/dataset-permission-marking-architecture-summary.md](../synthesis/dataset-permission-marking-architecture-summary.md) | Dataset 权限、Marking、传播和访问控制结论。 |
| [docs/synthesis/palantir-dataset-implementation-and-self-build-design.md](../synthesis/palantir-dataset-implementation-and-self-build-design.md) | Dataset 实现机制推断与自研能力对齐蓝图。 |

## Supporting Evidence

| 证据 | 精简说明 |
| --- | --- |
| [docs/raw/39-foundry-dataset-transaction-view-evidence.md](../raw/39-foundry-dataset-transaction-view-evidence.md) | 说明 Dataset、transaction、view、branch 的版本坐标。 |
| [docs/raw/40-traditional-dt-partition-production-semantics.md](../raw/40-traditional-dt-partition-production-semantics.md) | 说明 `dt` 在传统数仓中承担的生产控制语义。 |
| [docs/raw/41-lakehouse-layout-partition-cost-model.md](../raw/41-lakehouse-layout-partition-cost-model.md) | 区分物理布局、查询裁剪、Spark repartition 与成本模型。 |
| [docs/raw/42-governance-lineage-audit-contracts.md](../raw/42-governance-lineage-audit-contracts.md) | 给出 run-to-transaction、coverage lineage、active pointer 和审计契约。 |
| [docs/raw/43-migration-risk-dual-coordinate-patterns.md](../raw/43-migration-risk-dual-coordinate-patterns.md) | 总结双坐标迁移风险和 Ready Barrier / Active Pointer 等模式。 |
| [docs/raw/30-dataset-permission-marking-architecture.md](../raw/30-dataset-permission-marking-architecture.md) | Dataset 权限和 Marking 架构全量证据。 |

## Related Issues

#19、#28、#29、#30、#31、#32、#33、#34、#46

## Open Questions

- Foundry 多输出 build 是否具备跨 Dataset 原子提交，公开证据不足。
- Retention、`DELETE` transaction、history readability 在不同 enrollment 下的可用性仍需实测。
- `business_date`、manifest、active pointer 应如何落成最小产品能力，需要结合自研平台目标链路再裁剪。
