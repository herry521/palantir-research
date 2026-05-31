# Self-build Roadmap

## 摘要与洞察

1. 【建议】自研路线应以能力域为主轴，而不是复刻 Foundry 产品菜单。
2. 【结论】P0 应先补 Dataset/Transaction、Transform Contract、调度、质量、血缘、权限和工程治理这些底座。
3. 【推断】P1 再建设 Operator Registry、Engine Router、Data Quality 控制面、Permission 控制面和统一 observability。
4. 【建议】AI FDE、Ontology/Writeback 和业务应用闭环应建立在工程治理和权限验证能力稳定之后。
5. 【边界】开源栈可覆盖接入、计算、调度和一部分血缘，但统一 Dataset Transaction、权限传播、Ontology 和受控 AI 工程执行仍需要平台自研。

## 三阶段路线

| 阶段 | 建设重点 | 验收方式 |
| --- | --- | --- |
| P0 底座 | Dataset version、Run/Data Version Identity、Transform Contract、basic schedule/build、lineage、permission snapshot。 | 能从一次输出追溯输入版本、代码版本、业务周期、质量结果和访问要求。 |
| P1 控制面 | Operator Registry、Engine Router、Data Quality、Data Integration permission、audit/access debugger、export policy。 | 能统一解释 why-denied、quality failure、staleness、export eligibility 和 lineage impact。 |
| P2 应用闭环 | Ontology、Writeback、OSDK、AI FDE、业务工作流、受控生产变更。 | 能在 branch/PR/proposal/approval/eval 约束下完成平台内工程和业务动作。 |

## 优先级原则

1. 先建设平台能理解的契约，再建设更复杂的 UI。
2. 先保证生产坐标清晰，再做自动化补数和 AI 工程。
3. 先覆盖所有数据接触点的权限和审计，再做细粒度策略优化。
4. 先把质量结果和 issue 闭环打通，再扩大规则数量。

## 能力域到文档入口

| 能力域 | 文档入口 | 关键产物 |
| --- | --- | --- |
| Dataset / Transaction | [Dataset](../topics/dataset.md) | version store、transaction/view、active pointer、partition manifest。 |
| Pipeline / Operator | [Pipeline](../topics/pipeline.md) | Transform Contract、OperatorSpec、Executor、Engine Router。 |
| Scheduling | [Scheduling](../topics/scheduling.md) | freshness scheduling、business-cycle scheduling、ready manifest。 |
| Quality | [Data Quality](../topics/data-quality.md) | build check、health check、monitoring alert、issue linkage。 |
| Permission | [Security and Marking](../topics/security-and-marking.md) | PDP/PEP、requirement propagation、export policy、audit snapshot。 |
| Engineering / AI | [Pro-Code](../topics/pro-code.md)、[AI FDE](../topics/ai-fde.md) | platform IDE、branch/PR、tool approval、preview/CI/eval。 |

## 主要证据

- [Self-build Roadmap topic](../topics/self-build-roadmap.md)
- [算子平台建设方案](../synthesis/operator-platform-design.md)
- [DataWorks 与 Palantir Data Integration 差异研究](../synthesis/dataworks-vs-palantir-integration.md)
- [Data Integration 权限体系建设缺口与路线图](../synthesis/data-integration-permission-system-roadmap.md)
- [类 Palantir Stream 能力自建方案](../raw/20-stream-self-build-architecture.md)
- [开源替代栈：Palantir Foundry Pipeline 能力复刻方案](../raw/10-opensource-alternative-stack.md)
