# Self-Build Roadmap

## 摘要与洞察

1. 【建议】自建路线应以能力域为主轴，而不是复刻 Foundry 产品菜单；优先建设 Dataset/Transaction、Pipeline Contract、调度、质量、血缘、权限和工程治理这些底座能力。
2. 【推断】算子平台的核心是“有契约的计算单元”：OperatorSpec 负责编译期 schema/参数/资源契约，Executor 负责运行时执行，多引擎通过 Engine Router 选择。
3. 【建议】迁移传统数仓时不能丢掉 `dt` 承载的生产语义；应采用 `transaction/view` 管版本证据，`business_date/data_interval/partition_manifest` 管业务解释、补数和 SLA。
4. 【推断】类 AI FDE 应放在平台治理底座之后推进：先只读探索，再 branch-local 修改，再 preview/CI validation，最后扩展 ontology/function/tool。
5. 【边界】开源栈可覆盖接入、计算、调度、血缘的一部分，但 Ontology、统一治理、Dataset Transaction、增量语义和受控 AI 工程执行仍需平台自研。

## Canonical Documents

| 文档 | 用途 |
| --- | --- |
| [docs/synthesis/operator-platform-design.md](../synthesis/operator-platform-design.md) | 算子平台主设计，覆盖 Operator Contract、Registry、Engine Router、质量、血缘、可观测和路线图。 |
| [docs/synthesis/dataworks-vs-palantir-integration.md](../synthesis/dataworks-vs-palantir-integration.md) | DataWorks 与 Foundry 时间/调度/事务模型差异，自研平台 Run Identity + Data Version Identity 参考。 |
| [docs/synthesis/palantir-dataset-no-dt-partition-impact.md](../synthesis/palantir-dataset-no-dt-partition-impact.md) | Dataset transaction/view 与传统 `dt` 生产坐标差异，迁移双坐标设计依据。 |
| [docs/synthesis/palantir-data-quality-module-research.md](../synthesis/palantir-data-quality-module-research.md) | 自建质量控制面：build-time expectations、runtime health checks、monitoring views。 |
| [docs/synthesis/palantir-ai-fde-research.md](../synthesis/palantir-ai-fde-research.md) | 类 AI FDE 自建边界和 90 天 PoC 路线。 |
| [docs/superpowers/specs/2026-05-31-research-doc-library-design.md](../superpowers/specs/2026-05-31-research-doc-library-design.md) | 文档库与 topic/index 体系设计基线，关联 #42。 |

## Supporting Evidence

| 证据 | 精简说明 |
| --- | --- |
| [docs/raw/10-opensource-alternative-stack.md](../raw/10-opensource-alternative-stack.md) | 开源替代栈映射，指出 Dagster/OpenLineage/Spark/Iceberg 等可覆盖部分能力，但 Ontology 与增量语义缺口明显。 |
| [docs/raw/20-stream-self-build-architecture.md](../raw/20-stream-self-build-architecture.md) | 类 Palantir Stream 自建方案，Kafka/Flink/Paimon/Schema Registry 分层和建设优先级。 |
| [docs/raw/37-ai-fde-self-build-implementation-blueprint.md](../raw/37-ai-fde-self-build-implementation-blueprint.md) | 类 AI FDE 自建架构、平台原生能力、外部 agent 框架边界、90 天 PoC。 |
| [docs/raw/43-migration-risk-dual-coordinate-patterns.md](../raw/43-migration-risk-dual-coordinate-patterns.md) | 双坐标设计、ready barrier、active pointer、supersedes transaction、coverage lineage。 |
| [docs/raw/26-pro-code-governance-quality-observability.md](../raw/26-pro-code-governance-quality-observability.md) | 高码平台治理闭环，对自建工程入口、质量、血缘、权限、可观测有直接参考价值。 |
| [docs/raw/27-incremental-scheduling-transaction.md](../raw/27-incremental-scheduling-transaction.md) | Dataset Transaction、增量调度、staleness、fallback 与 retention 的自建底座建议。 |
| [docs/superpowers/specs/2026-04-09-platform-upgrade-design.md](../superpowers/specs/2026-04-09-platform-upgrade-design.md) | 大数据平台升级 17 模块 L1-L4 路线。 |
| [docs/superpowers/specs/2026-04-16-roadmap-product-interpretation.md](../superpowers/specs/2026-04-16-roadmap-product-interpretation.md) | 产品阶段视角：I1 基础闭环、I2 生产就绪、I3 规模协作、I4 AI 自运营。 |
| [docs/superpowers/specs/2026-04-16-roadmap-q2-q3-breakdown.md](../superpowers/specs/2026-04-16-roadmap-q2-q3-breakdown.md) | 2026 Q2/Q3 交付拆解：Pipeline Builder v1、H1 演示、文档/时序数据支持。 |

## Related Issues

#24、#28、#31、#33、#35、#41、#42、#43、#46

## Open Questions

- 自研平台当前已有 EOS Dataset、Pipeline、Schedule、Build、OSS 能力与这些路线文档的差距清单在哪里维护？
- Run Identity、Data Version Identity、Dataset Transaction、partition manifest 应由哪个服务拥有主数据模型？
- Operator Contract 与 Pro-Code Transform Contract 是否应合并为同一套 IR？
- Data Quality、Lineage、Permission/Marking、Observability 的最小 P0 范围如何切分，避免做成互相孤立的外围系统？
- 类 AI FDE 何时进入路线图更合适：在工程治理闭环完成后，还是可以先做只读探索型 P0？
