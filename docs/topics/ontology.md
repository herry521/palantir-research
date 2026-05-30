# Ontology

## 摘要与洞察

1. 【事实】Ontology 是 Dataset、Virtual Table、Model 之上的业务语义与运营层，核心对象包括 Object Type、Property、Link Type、Action Type、Interface、Value Type 和 Function。
2. 【事实】Dataset 更像数据资产和版本化表表示；Ontology 承载业务对象、关系、动作、权限和应用/API 契约。
3. 【推断】Ontology 与传统数仓语义层的最大区别不是字段口径，而是“可操作”：Action Type、Function、Object Set 让业务流程和 AI agent 可围绕对象执行动作。
4. 【事实】Object Type 依赖 backing datasource；Primary Key 必须稳定确定，Link Type 是一等关系，OSDK 将 Ontology 暴露为类型安全开发接口。
5. 【推断】自建平台第一阶段应优先补齐 Property 类型系统、PK/Title Key、Backing Datasource、FK Link Type；Action、Interface、Value Type、OSDK 可分阶段推进。

## Canonical Documents

| 文档 | 用途 |
| --- | --- |
| [docs/superpowers/specs/2026-04-15-ontology-data-model-research.md](../superpowers/specs/2026-04-15-ontology-data-model-research.md) | Ontology 核心业务对象与数据模型主引用；当前 catalog 尚未标记 ontology 专属 canonical synthesis。 |
| [docs/synthesis/palantir-dataset-vs-data-warehouse.md](../synthesis/palantir-dataset-vs-data-warehouse.md) | Dataset 与 Ontology 分工，以及 Ontology-first 与传统数仓 analysis-first 的范式差异。 |

## Supporting Evidence

| 证据 | 精简说明 |
| --- | --- |
| [docs/raw/04-lineage-ontology-integration.md](../raw/04-lineage-ontology-integration.md) | Dataset 到 Ontology Object Type Sync、Actions Writeback、Ontology-Pipeline 集成和待深挖问题。 |
| [docs/raw/30-dataset-permission-marking-architecture.md](../raw/30-dataset-permission-marking-architecture.md) | Ontology Object / Property Security 与 Dataset requirements 的叠加关系。 |
| [docs/raw/11-marking-mechanism-deep-dive.md](../raw/11-marking-mechanism-deep-dive.md) | Marking 与 Ontology object/property policy 的正交叠加。 |
| [docs/raw/29-lineage-branch-version-pipeline-sync.md](../raw/29-lineage-branch-version-pipeline-sync.md) | 血缘、branch/version 与 Pipeline/Sync 数据关系，可支撑 Ontology 数据来源与版本语义。 |
| [docs/raw/42-governance-lineage-audit-contracts.md](../raw/42-governance-lineage-audit-contracts.md) | 治理、血缘、审计与元数据契约，对 Ontology 依赖的元数据治理有参考价值。 |

## Related Issues

#42、#46

## Open Questions

- 是否需要新增 ontology 专属 synthesis，并在 catalog 中标记 canonical？
- Ontology Object Type 删除、重命名或 schema 演进时，下游 Pipeline、OSDK、Workshop 应如何感知和迁移？
- Actions Writeback 的延迟、事务边界、冲突处理和失败恢复是否有更强证据？
- Stream-backed Object Type 的监控、User Edit 限制、多数据源对象限制如何进入自建路线？
- Ontology 权限、Dataset Marking、Object/Property Security 的统一 debug/why-denied 体验如何设计？
