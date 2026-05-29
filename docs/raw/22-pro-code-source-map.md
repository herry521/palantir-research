# 22 — Palantir 高码能力资料源与可信度矩阵

**日期：** 2026-05-29
**关联 Issue：** #6
**所属 Epic：** #4
**类型：** 资料源索引 / 可信度基线 / 后续 Story 引用基线

---

## 0. 目的

本文件为 Palantir 高码能力长链研究建立资料源与可信度基线，避免后续研究把官方事实、工程推断和实现猜测混在一起。

后续 Story 应优先引用本文件列出的官方资料源；如果新增资料源，需要同步扩展本文件或在对应 Story 文档中说明新增依据。

---

## 1. 可信度标签

| 标签 | 判定标准 | 使用边界 |
|---|---|---|
| 【事实】 | 本轮调研已通过 Palantir 官方文档或当前仓库资料直接确认 | 可作为事实陈述进入结论 |
| 【推断】 | 由多个【事实】事实组合得出的工程判断，逻辑链明确，但官方没有直接给出同一句结论 | 可作为架构建议，但需要说明推导依据 |
| 【猜测】 | 公开资料未披露，或只有间接迹象，尚不能形成稳定判断 | 只能作为待验证问题，不应直接进入设计决策 |

注意：这里使用“事实”标签表示“当前已验证事实”，不是实时数据流能力。

---

## 2. 官方资料源矩阵

| 编号 | 资料源 | URL | 覆盖主题 | 可支撑结论 |
|---|---|---|---|---|
| S01 | Code Repositories Overview | https://www.palantir.com/docs/foundry/code-repositories/overview/index.html | Web IDE、Git、PR、权限、lint、preview/debug、repository 类型 | Code Repositories 是 Foundry 内置工程入口，而不是普通脚本上传入口。【事实】 |
| S02 | Create transforms | https://www.palantir.com/docs/foundry/code-repositories/create-transforms | Transform repository 创建、语言选择、pipeline 开发入口 | 高码 Pipeline 可通过 Code Repositories 创建和管理 transform。【事实】 |
| S03 | Repository upgrades | https://www.palantir.com/docs/foundry/code-repositories/repository-upgrades | Repository 模板升级、upgrade PR、impact analysis | 高码工程生命周期包含平台升级与影响分析，不只包含代码提交。【事实】 |
| S04 | Python transforms Overview | https://www.palantir.com/docs/foundry/transforms-python/overview | Python transform 能力概览、batch、incremental、共享库、expectations、compute engines | Python 是 Foundry transform 中能力最完整的高码路径之一。【事实】 |
| S05 | Python incremental transforms | https://www.palantir.com/docs/foundry/transforms-python/incremental-usage | `@incremental`、read/write mode、snapshot、retention | Palantir 增量语义依赖 Dataset 变化历史和 transform read/write mode，而不是只依赖业务字段。【事实】 |
| S06 | Python compute engine selection | https://www.palantir.com/docs/foundry/transforms-python/compute-engines | Spark、DuckDB、pandas、Polars、single-node/distributed 能力矩阵 | 高码运行时不是 Spark 单一路径，而是按能力和规模选择执行引擎。【事实】 |
| S07 | Python unit tests | https://www.palantir.com/docs/foundry/transforms-python/unit-tests | pytest、repository checks、batch pipeline 测试限制 | 高码测试进入 Code Repository 生命周期，但 streaming pipeline 测试能力存在边界。【事实】 |
| S08 | Python data expectations reference | https://www.palantir.com/docs/foundry/transforms-python/data-expectations-reference | Data expectations API、质量规则声明 | 高码质量规则可通过 Python transform 声明并进入构建链路。【事实】 |
| S09 | Java transforms Overview | https://www.palantir.com/docs/foundry/transforms-java/overview | Java transform、Dataset API、batch/incremental、unit testing | Java 是高码路径之一，尤其适合强类型、Java 生态和 Pipeline Builder 导出链路。【事实】 |
| S10 | SQL transforms Overview | https://www.palantir.com/docs/foundry/transforms-sql/overview | SQL transform、Spark SQL、SQL 适用边界 | SQL 是高码路径之一，但不是完整替代 Python/Java 的通用 transform 路径。【事实】 |
| S11 | Pipeline Builder Overview | https://www.palantir.com/docs/foundry/pipeline-builder/overview | 可视化 Pipeline、integrity checks、低码入口 | Pipeline Builder 是低码入口，但其能力与 transform code 后端存在联系。【事实】 |
| S12 | Export pipeline code | https://www.palantir.com/docs/foundry/pipeline-builder/export-pipeline | 导出到 Java transforms repository、不可逆、转换限制 | 低码到高码存在代码导出路径，但不是无损双向同步。【事实】 |
| S13 | Scheduling Overview | https://www.palantir.com/docs/foundry/building-pipelines/scheduling-overview | 时间触发、数据更新触发、逻辑更新触发、Dataset 依赖构建 | Foundry 调度围绕 Dataset 和依赖图组织，而不是只围绕任务节点组织。【事实】 |
| S14 | Supported languages | https://www.palantir.com/docs/foundry/building-pipelines/supported-languages | Pipeline 支持语言与不同开发入口 | 高码路径需要按语言、入口和运行时能力分层看待。【事实】 |
| S15 | Define data expectations | https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations | Pipeline 维护、Data expectations、构建断路 | 数据质量不是事后监控，能进入 pipeline build 生命周期。【事实】 |

---

## 3. 资料源到 Story 的映射

| Story | 主要资料源 | 说明 |
|---|---|---|
| #6 资料源与可信度矩阵 | S01-S15 | 本文件覆盖 |
| #7 Code Repositories 与高码工程入口 | S01、S02、S03 | 聚焦 authoring/review/upgrade/impact analysis |
| #8 高码运行时、计算引擎与依赖管理 | S04、S06、S09、S10、S14 | 聚焦 Spark/lightweight/Java/SQL 和能力矩阵 |
| #9 Transform Contract 与 DAG 推导机制 | S02、S04、S09、S10、S13、S14 | 聚焦 Input/Output、Dataset graph 和平台元数据 |
| #10 质量、测试、血缘、权限与可观测性 | S07、S08、S15；后续需补 pipeline security、health、monitoring 资料源 | 当前资料源覆盖 testing/quality，治理侧还需继续补证 |
| #11 增量计算、调度与 Dataset Transaction | S05、S13 | 聚焦 incremental 和 scheduling |
| 待建 Story：Pipeline Builder 与高码互操作 | S11、S12 | 需要补建 issue；当前已确认资料源 |
| 待建 Story：最终综合与 HTML 产出 | S01-S15 + 各 Story 文档 | 需要补建 issue；用于整合人易读 HTML |

---

## 4. 第一批可稳定使用的结论

1. Code Repositories 是 Foundry 的平台内工程入口，覆盖 Git、PR、权限、lint、preview/debug、transform repository 等能力。【事实】
2. Palantir 高码能力不是单一路径：Python、Java、SQL 分别覆盖不同 transform 场景，且 Python 文档明确覆盖 batch、incremental、shared libraries、data expectations 和 compute engines。【事实】
3. Python transform 的 compute engine 包含 Spark 与 lightweight 路径；因此“高码能力 = Spark 作业平台”是不完整表述。【事实】
4. Incremental transform 的核心不只是函数装饰器，而是 read/write mode、snapshot、retention 和 Dataset 变化历史共同形成的运行语义。【推断】
5. Scheduling 文档围绕 Dataset 及其依赖触发 build，说明 Foundry 的调度心智更接近 Dataset graph，而不是传统任务 DAG。【推断】
6. Pipeline Builder 可以导出到 Java transforms repository，但导出不可逆且存在转换限制；因此低码/高码互操作不能假设为无损双向转换。【事实】
7. 高码质量与测试不是外围治理：unit tests、repository checks、data expectations 都能进入开发或构建生命周期。【事实】

---

## 5. 当前证据缺口

1. 跨 repository 依赖索引、事件传播和一致性机制没有在公开资料中完整披露，后续只能标注为【猜测】或用真实环境验证。
2. Pipeline Builder 内部 IR、代码生成器和 Java export 映射规则未公开，不能直接断言其内部实现。
3. 权限、Marking、Lineage、Data Health 与高码 transform 的完整闭环需要补充更多官方资料源，当前只完成资料源初筛。
4. SQL transforms 与 incremental transforms 的能力边界需要在 Story #8/#9 中继续复核，避免把 SQL 路径过度泛化。

---

## 6. 后续执行建议

下一步优先推进 #7 和 #9：

- #7 先把 Code Repositories 工程入口讲清楚，建立“高码不是脚本入口”的事实基线。
- #9 再深入 Transform Contract 与 DAG 推导，这是“平台如何理解代码”的核心机制。

对 #10、低码互操作、最终 HTML，需要先补齐未创建的 Story issues 后再推进。
