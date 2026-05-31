# Platform Mental Model

## 摘要与洞察

1. 【结论】Foundry 的平台心智是“数据资产 + 转换契约 + 业务语义 + 治理控制面”共同工作，而不是单个数据开发工具。
2. 【事实】Dataset 提供数据资产、schema、transaction、branch/view 和权限坐标；Ontology 承载业务对象、关系、动作和应用/API 契约。
3. 【推断】Pipeline 的关键不是运行 Spark，而是让 Transform、expression、DAG、质量、权限和血缘都能被平台解析。
4. 【建议】自研平台的主轴应围绕能力域组织：Dataset、Pipeline、调度、血缘、权限、质量、Pro-Code、AI FDE 和自建路线。

## 四层心智模型

| 层级 | 作用 | 主要文档 |
| --- | --- | --- |
| 数据资产层 | Dataset、transaction、branch/view、schema、文件布局和版本证据。 | [Dataset](../topics/dataset.md) |
| 转换表达层 | Transform Contract、Pipeline Builder、expression、operator registry、engine router。 | [Pipeline](../topics/pipeline.md) |
| 治理运行层 | Lineage、Schedule、Data Quality、Marking、permission、audit、observability。 | [Lineage and Catalog](../topics/lineage-and-catalog.md) |
| 业务语义层 | Ontology object/link/action/function、OSDK、Workshop、AI 工程入口。 | [Ontology](../topics/ontology.md) |

## 关键分工

Dataset 不等于完整业务模型。它更像可治理、可版本化、可构建的数据资产；Ontology 才是面向业务对象、动作和应用交互的语义层。这个分工解释了为什么只建设数据表、指标和调度无法复刻 Foundry 的上层体验。

Pipeline 也不应只理解为任务编排。Transform 的 `Input` / `Output`、参数、运行时、质量规则、增量语义和权限要求共同构成平台可理解的生产契约。低码 Pipeline Builder 和高码 Code Repositories 的长期方向应是共享 Contract/IR，而不是互相复制 UI。

## 阅读路径

1. 先读 [Dataset](../topics/dataset.md) 和 [Ontology](../topics/ontology.md)，明确数据资产与业务语义的边界。
2. 再读 [Pipeline](../topics/pipeline.md) 和 [Pro-Code](../topics/pro-code.md)，理解代码/低码如何变成平台契约。
3. 最后读 [Lineage and Catalog](../topics/lineage-and-catalog.md)，把资源、运行和版本证据放到同一坐标系。

## 主要证据

- [Palantir Dataset 与传统数据仓库建模对比](../synthesis/palantir-dataset-vs-data-warehouse.md)
- [Palantir Pipeline 技术实现深度分析](../synthesis/palantir-pipeline-deep-dive.md)
- [算子平台建设方案](../synthesis/operator-platform-design.md)
- [Transform Contract 与 DAG 推导机制调研](../raw/25-transform-contract-dag.md)
- [血缘、Dataset Branch/Version 与 Pipeline/Sync 数据关系调研](../raw/29-lineage-branch-version-pipeline-sync.md)
