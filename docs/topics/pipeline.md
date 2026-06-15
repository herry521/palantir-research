# Pipeline

## 摘要与洞察

1. 【事实】Foundry Transform 通过 `Input` / `Output` 声明 Dataset 依赖，平台自动组装 DAG；Pipeline Builder 还需要区分 dataset 级 transform 与字段/值级 expression。
2. 【事实】批处理主要基于托管 Spark；增量能力由 Dataset transaction 类型驱动，`APPEND` 支持增量，`UPDATE` / `SNAPSHOT` 会触发或要求全量重算。
3. 【推断】自研算子平台不能只做函数库，应建设 Operator Registry、类型化 IR、Spec / Executor 分离、执行适配器和质量/血缘契约。
4. 【事实】Pipeline Builder 可导出到 Java transforms repository，但导出是单向接管，不保证语义无损，且存在不可导出节点和破坏性写入风险。

## Canonical Documents

| 文档 | 用途 |
| --- | --- |
| [docs/synthesis/palantir-incremental-batch-chain-deep-dive.md](../synthesis/palantir-incremental-batch-chain-deep-dive.md) | 增量批链路的能力边界、实现主链路、关键控制点与自研启示。 |
| [docs/synthesis/palantir-pipeline-deep-dive.md](../synthesis/palantir-pipeline-deep-dive.md) | Pipeline 表达层、执行引擎、流批、血缘、算子平台综合结论。 |
| [docs/synthesis/operator-platform-design.md](../synthesis/operator-platform-design.md) | 自研算子平台架构设计参考。 |
| [docs/synthesis/palantir-pro-code-capability-research.md](../synthesis/palantir-pro-code-capability-research.md) | 高码 Transform、Contract、DAG、调度和治理的补充结论。 |

## Supporting Evidence

| 证据 | 精简说明 |
| --- | --- |
| [docs/raw/01-pipeline-expression-dsl.md](../raw/01-pipeline-expression-dsl.md) | Transform 装饰器、Pipeline 注册入口和 DAG 构建基础。 |
| [docs/raw/02-execution-engine-spark.md](../raw/02-execution-engine-spark.md) | Spark 执行、增量计算、调度和资源配置证据。 |
| [docs/raw/03-streaming-batch-architecture.md](../raw/03-streaming-batch-architecture.md) | 流批架构和 Pipeline Builder 技术形态。 |
| [docs/raw/06-incremental-pipeline.md](../raw/06-incremental-pipeline.md) | 增量 transform、transaction history、fallback 与流批差异的既有证据整理。 |
| [docs/raw/14-transform-operator-library.md](../raw/14-transform-operator-library.md) | Pipeline Builder 算子与 Code Repository SDK 算子库整理。 |
| [docs/raw/25-transform-contract-dag.md](../raw/25-transform-contract-dag.md) | Transform Contract、DAG 推导和调度解析。 |
| [docs/raw/27-incremental-scheduling-transaction.md](../raw/27-incremental-scheduling-transaction.md) | 增量、调度、Dataset transaction 三者的耦合证据。 |
| [docs/raw/28-pipeline-builder-pro-code-interop.md](../raw/28-pipeline-builder-pro-code-interop.md) | 低码/高码互操作、导出、IR/Contract 风险。 |
| [docs/raw/45-data-expectations-build-gates.md](../raw/45-data-expectations-build-gates.md) | Pipeline build-time 质量门禁补充证据。 |
| [docs/raw/57-pipeline-target-dataset-schema-primary-key.md](../raw/57-pipeline-target-dataset-schema-primary-key.md) | 说明目标 dataset schema 如何固化、Dataset 是否天然有主键，以及主键应如何建模。 |
| [docs/raw/58-pipeline-schema-compatibility-breaking-change.md](../raw/58-pipeline-schema-compatibility-breaking-change.md) | 聚焦 output schema 兼容性判定、破坏性变更处置，以及 rename 与 drop+add 的识别边界。 |

## Related Issues

#2、#3、#9、#11、#12、#14、#40、#46、#63、#64

## Open Questions

- Pipeline Builder 内部 IR、Registry、codegen pipeline 和错误诊断算法未公开。
- Builder integrity checks 如何保存字段级 schema 推导结果、primary key expectation 是否进入统一元数据注册表，公开资料不足。
- 字段级 lineage / refactor 能否对 rename 给出稳定、可机读的官方判定，当前公开资料不足。
- 低码 transform/expression 与自研算子注册中心字段的精确映射还需单独建表。
- OpenLineage adapter、跨系统血缘导入导出和 Foundry 私有血缘模型的兼容边界仍待验证。
