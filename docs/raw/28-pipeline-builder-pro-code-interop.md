# 28 — Pipeline Builder 与高码互操作调研

**日期：** 2026-05-29
**关联 Issue：** #14
**类型：** 低码 / 高码互操作调研
**输入资料：** `docs/raw/22-pro-code-source-map.md`、`docs/raw/14-transform-operator-library.md`、`docs/raw/07-code-pipeline.md`、Palantir 官方文档

---

## 1. 背景

Pipeline Builder 是 Foundry 的低码数据集成入口；Code Repositories 是 Foundry 内置的高码工程入口，支持 Python、Java、SQL transform repository、Git、PR、lint、preview/debug 等工程化能力。【事实】

本 Story 聚焦二者之间的互操作关系：Pipeline Builder 如何通过后端模型生成代码、如何导出到 Java transforms repository、导出后有哪些不可逆和语义风险，以及这些机制对自研低码 / 高码共享 IR 与 Contract 的设计启发。【推断】

---

## 2. 可信度规则

| 标签 | 判定标准 | 使用边界 |
|---|---|---|
| 【事实】 | 本轮已由 Palantir 官方文档或当前仓库资料直接确认 | 可作为事实陈述 |
| 【推断】 | 多个【事实】事实组合后的工程判断，官方未直接以同一句话表达 | 可作为架构建议，但需保留依据 |
| 【猜测】 | 官方资料未披露、只能从产品行为或通用架构经验外推 | 只能作为待验证问题 |

注意：这里使用“事实”标签表示“当前已验证事实”，不是流式实时能力。【事实】

---

## 3. 核心结论

1. Pipeline Builder 不是只保存 UI 配置的前端工具；官方称其后端是 logic creation 与 execution 之间的中间层，会根据用户描述写 transform code，并执行 pipeline integrity checks，用于识别重构错误、提前发现 schema 问题。【事实】
2. 低码到高码存在官方导出路径：Pipeline Builder pipeline 可导出到既有 Java transforms repository，导出结果会被转换为 Java transform code 并推送到目标 repository。【事实】
3. export pipeline code 是单向迁移 / 接管机制，不是双向同步机制；Java 代码侧修改不能推回 Pipeline Builder pipeline。【事实】
4. 导出存在破坏性写入风险：官方明确目标 repository 指定 branch 上的既有 code 或 files 会被删除，因此应使用专门 repository 或新 branch 承接导出。【事实】
5. 导出不是语义无损编译：Java transform 输出不一定与原 Pipeline Builder 输出完全一致，部分 Pipeline Builder 表达式的自定义优化无法导出，只能回退为 native Spark expressions，边界场景行为可能不同。【事实】
6. 并非所有 Pipeline Builder transformation 都能转换为代码；因此低码 / 高码互操作必须建模为“可转换子集 + 失败诊断 + 手工接管”，而不是假设全量可编译。【事实】
7. Code Repositories 侧的 transform 模型以 Transform / Pipeline 为核心：Java Transform 描述 input/output datasets、compute function 和额外运行配置，并注册到 Pipeline；这与 Pipeline Builder 的 graph/node/output 模型可以通过共享的 dataset I/O contract 对齐。【事实】
8. Pipeline Builder 与 Code Repositories 可通过分支名协作：Pipeline Builder branch 可与 Code Repositories branch 同名，使 Pipeline Builder transform 从匹配 branch 读取输入 dataset；缺失时可通过 fallback branches 控制读取来源。【事实】
9. 最可借鉴的设计不是“把低码图直接还原成手写代码”，而是建立稳定 IR/Contract：数据集路径、schema、类型、输出检查、分支语义、transform 参数、可导出能力集和语义降级说明应成为平台级契约。【推断】

---

## 4. 低码 / 高码关系模型

### 4.1 三层模型

| 层级 | Pipeline Builder | Code Repositories / Transforms | 互操作含义 |
|---|---|---|---|
| Authoring | 图和表单配置；表达式、transform、输出、分支 | Git repository；Java/Python/SQL 代码；PR 和 checks | 面向不同人群的两个 authoring surface【事实】 |
| Contract | 输入 / 输出 dataset、schema、类型、branch、output checks | `Input` / `Output`、Transform/Pipeline 注册、repository checks | 二者可通过 dataset I/O 与 schema contract 对齐【推断】 |
| Execution | 后端生成 transform code，抽象 Spark/Flink 等执行细节 | transform runtime 执行注册到 Pipeline 的 Transform | 低码和高码最终都进入 Foundry build/runtime 链路【推断】 |

### 4.2 协作关系

Pipeline Builder 适合标准数据集成、schema 引导、低码协作和快速构建；Code Repositories 适合需要特定 Java/Python 库、手写复杂逻辑、工程化测试、PR 评审和显式代码所有权的场景。【推断】

Pipeline Builder 可以通过 UDF 引入自定义代码，也可以通过 export pipeline code 将整条 pipeline 迁移为 Java transforms；前者是局部扩展，后者是整体接管。【推断】

Pipeline Builder branch 与 Code Repositories branch 的同名协作说明，Foundry 对低码和高码没有完全割裂版本空间；至少在输入 dataset 读取上，两者可以围绕 branch/fallback 形成协同开发体验。【事实】

---

## 5. Export Pipeline Code 机制

### 5.1 官方流程

1. 在 Pipeline Builder 中打开待导出的 pipeline，进入 `Settings > Export code`。【事实】
2. 选择既有目标 Java transforms repository。【事实】
3. 选择导出来源的 Pipeline Builder branch，并可选择在目标 repository 中创建新 branch。【事实】
4. 导出后，Java transform code 会写入 repository 的 `transforms-java/src/main/java/com/` 路径，主要文件为 `PipelineLogic.java` 和 `PipelineOutputs.java`。【事实】

### 5.2 工程含义

导出目标限定为 Java transforms repository，说明官方公开互操作路径不是“任意语言 IR 反编译”，而是 Pipeline Builder graph 到 Java transform code 的定向 code generation。【事实】

导出适用场景被官方描述为需要访问特定 Java libraries；因此它更像是从低码原型 / 标准 pipeline 迁移到 Java 高码维护，而不是日常双向编辑体验。【推断】

导出到 Java 后，repository 仍需要符合 Java transforms 的 Pipeline/Transform 注册模型；Java 文档要求 Transform 描述 input/output datasets、compute function 和配置，并注册到 Pipeline，运行时通过 Pipeline 定位并执行对应 Transform。【事实】

---

## 6. 不可逆与语义风险

### 6.1 不可逆限制

导出过程不可逆，Java transforms code 的后续修改不能推回 Pipeline Builder pipeline。【事实】

不可逆意味着导出后应明确 owner 切换：Pipeline Builder pipeline 可以作为迁移源或参考，但高码 repository 才是后续演进主线；继续在两边并行改同一逻辑会产生漂移。【推断】

### 6.2 破坏性写入

导出会删除目标 repository 指定 branch 上的既有 code 或 files。【事实】

因此导出不应指向已有手写生产 branch，除非已完成备份、差异审查和 owner 确认；更稳妥做法是新建目标 branch 或专用 repository 承接导出。【推断】

### 6.3 转换失败场景

官方明确“部分 pipeline transformations cannot be converted to code”，但公开文档未列出完整不可转换清单。【事实】

潜在失败类型包括：仅 Pipeline Builder 后端支持但 Java codegen 未覆盖的 transformation、依赖 UI/资源上下文的 output 类型、streaming 或特定执行模式相关节点、以及尚未暴露 Java API 等价物的能力。【猜测】

### 6.4 自定义优化回退

官方明确：部分 Pipeline Builder expressions 被优化并以不同于 native Spark 的方式实现，以获得更高可靠性和更好的错误处理；这些 custom optimizations 无法导出，导出时必须回退到 native Spark expressions，边界场景可能表现不同。【事实】

这意味着导出后的 validation 不能只比较 schema，还需要比较边界数据行为，例如 null、非法 cast、日期解析、字符串/正则、除零、地理空间边界等表达式语义。【推断】

### 6.5 输出差异风险

官方要求将导出到 Java transforms 视为 starting point，并由用户手工验证完整准确性。【事实】

因此导出链路应配套数据对账：同一输入 branch 下运行 Pipeline Builder 输出与 Java transform 输出，比较 row count、schema、关键字段 hash、异常值分布和代表性边界样本。【推断】

---

## 7. 可借鉴 IR/Contract 设计

### 7.1 共享 Contract 优先于共享代码

低码 / 高码共享的稳定层应是 Contract，而不是某一种手写语言源码。【推断】

建议 Contract 至少包含：输入 / 输出 dataset 标识、schema、字段类型、nullability、主键或唯一性期望、branch/fallback 语义、执行模式、transform 参数、输出检查、版本号、语义兼容性标记。【推断】

### 7.2 IR 需要显式表达可导出能力

IR 节点应标注 codegen support matrix，例如 `javaExport: supported | unsupported | lossy`，并给出失败原因或语义降级说明。【推断】

Pipeline Builder 官方 export 的限制说明，低码系统如果不显式表达“不可转换”和“有损转换”，用户会误以为导出代码与低码执行完全等价。【推断】

### 7.3 后端代码生成与 integrity checks 应绑定

Pipeline Builder 官方把后端写 transform code 与 pipeline integrity checks 放在同一层描述，说明 codegen 不能只是打印源码；它还要做 schema 推导、类型检查、输出检查和 refactor 错误定位。【事实】

自研 IR 应把 validation 结果作为一等产物，例如：每个节点的输入 schema、输出 schema、类型 coercion、不可达路径、未连接输出、下游破坏风险和修复建议。【推断】

### 7.4 导出后需要所有权切换

export pipeline code 应被设计成“fork / handoff”，而不是“round-trip editing”。【推断】

可借鉴流程：低码 pipeline 生成高码 branch -> 自动创建 PR -> 附带语义差异报告 -> 高码 owner 验收 -> 标记低码源 pipeline 为只读或 archived reference，避免双写漂移。【推断】

### 7.5 自定义优化需要双实现或显式降级

如果低码运行时有高可靠自定义表达式实现，而导出目标语言只能使用 native engine，应提供以下之一：等价 runtime library、生成端测试用例、或显式 lossy warning。【推断】

Palantir 官方对 custom optimizations 回退 native Spark 的说明，是 IR/Contract 设计中“语义不是只有 AST 形状，还有边界行为”的直接证据。【事实】

---

## 8. 证据缺口

1. Pipeline Builder 内部 IR/schema model/codegen pipeline 未公开，无法确认其真实数据结构、优化阶段和错误诊断算法。【猜测】
2. 官方未公开完整“哪些 transformations 不能 export”的清单，当前只能知道存在不可转换子集。【事实】
3. 官方未公开 `PipelineLogic.java` / `PipelineOutputs.java` 的完整生成模板和映射规则，无法逐节点建立低码算子到 Java API 的确定映射表。【猜测】
4. 官方未说明导出时如何处理 Pipeline Builder 的 streaming pipeline、Ontology output、virtual table output、media/geotemporal/time-series output 等复杂输出；这些能力是否可导出需要实测或更细文档确认。【猜测】
5. 官方未说明 export 是否自动生成测试、PR、impact analysis 或差异报告；公开文档只确认会 push code 到目标 repository。【事实】
6. 现有仓库资料 `docs/raw/14-transform-operator-library.md` 中部分算子数量和扩展模式为前序调研推断，本文只将其作为背景，不把数量级当作官方事实。【推断】

---

## 9. 参考来源

### 官方来源

- Palantir Docs — Pipeline Builder Overview: https://www.palantir.com/docs/foundry/pipeline-builder/overview
- Palantir Docs — Pipeline Builder Export pipeline code: https://www.palantir.com/docs/foundry/pipeline-builder/export-pipeline
- Palantir Docs — Pipeline Builder Transforms Overview: https://www.palantir.com/docs/foundry/pipeline-builder/transforms-overview
- Palantir Docs — Pipeline Builder Branches Overview: https://www.palantir.com/docs/foundry/pipeline-builder/branches-overview
- Palantir Docs — Pipeline Builder Pipeline management Overview: https://www.palantir.com/docs/foundry/pipeline-builder/management-overview
- Palantir Docs — Pipeline Builder Outputs Overview: https://www.palantir.com/docs/foundry/pipeline-builder/outputs-overview
- Palantir Docs — Code Repositories Overview: https://www.palantir.com/docs/foundry/code-repositories/overview/index.html
- Palantir Docs — Code Repositories Create transforms: https://www.palantir.com/docs/foundry/code-repositories/create-transforms
- Palantir Docs — Code Repositories Repository upgrades: https://www.palantir.com/docs/foundry/code-repositories/repository-upgrades
- Palantir Docs — Java Transforms and pipelines: https://www.palantir.com/docs/foundry/transforms-java/transforms-pipelines
- Palantir Docs — Java User-defined functions: https://www.palantir.com/docs/foundry/transforms-java/user-defined-functions

### 仓库内来源

- `docs/raw/22-pro-code-source-map.md`
- `docs/raw/14-transform-operator-library.md`
- `docs/raw/07-code-pipeline.md`
