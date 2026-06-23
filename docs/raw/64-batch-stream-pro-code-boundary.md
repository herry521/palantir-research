# 64 — Batch 与 Streaming Pipeline 的高码能力边界

**日期：** 2026-06-23<br>
**类型：** 调研记录 / 低码高码能力边界<br>
**问题：** Batch 和 stream 两类 Pipeline 哪些能力需要高码来支持？

---

## 1. 摘要与洞察

1. 【事实】Batch pipeline 不一定需要高码；Pipeline Builder 能覆盖常见清洗、join、union、表达式、输出和部分增量/快速 pipeline 场景。但一旦需要自定义依赖库、文件/API 访问、复杂 Python/Java/SQL 逻辑、工程化测试或未来演进为 Code Repository 增量 transform，就应进入高码路径。
2. 【事实】Streaming pipeline 也支持 Pipeline Builder；但官方明确 streaming 与 batch 的关键差异包括延迟、计算成本和支持语言，且 streaming 支持 Java transforms、Pipeline Builder，不支持 Python transforms。
3. 【事实】Pipeline Builder 和 Code Repositories 的官方对比显示：Code Repositories 用于 specialized, code-based data transformations，支持 Python/SQL/Java/Mesa、文件系统和 API 访问；Pipeline Builder 是 graph/form 低码界面，不需要代码。
4. 【事实】UDF 是低码与高码之间的局部扩展点：当 Pipeline Builder 现有 transformation 不够、需要外部 Java/Python libraries、或需要跨 pipeline 复用复杂逻辑时，可以创建 UDF。但 Pipeline Builder 中 UDF 当前只支持 row map 和 flat map。
5. 【推断】工程上可把高码需求分成三类：表达能力缺口、运行时/依赖缺口、工程治理缺口。Batch 三类都常见；Streaming 额外有状态、checkpoint、partition key、延迟和 Java runtime 兼容性风险，因此应更保守地把复杂逻辑迁入高码或拆成上游 batch/增量预处理。

### 1.1 2026-06-23 追问结论：Stream 支持高码开发吗？

1. 【事实】支持，但属于 advanced user 路径。官方 Pipeline Builder vs Code Repositories 对比表中，`Streaming pipeline` 在 Pipeline Builder 和 Code Repositories 下都是 `Yes`，其中 Code Repositories 标注为 `Yes (for advanced users)`。
2. 【事实】语言边界不是 batch 的全集。官方 stream-vs-batch 表显示 streaming 支持 Java transforms 和 Pipeline Builder，但 `Python supported transforms` 为 `No`。
3. 【事实】Streaming 可通过 UDF 引入自定义代码；官方 UDF 文档说明 UDF 可在 Pipeline Builder 或 Code Repositories 中运行 Java/Python 自定义代码，并可版本化和升级。但 Pipeline Builder 中 UDF 当前只支持 row map 和 flat map。
4. 【事实】官方曾发布 streaming transforms 迁移到 Java 17 的公告，并明确提到 `UDF streaming transforms` 和 `UDF Definition repository`，这侧面确认 streaming 场景存在用户自定义高码实现。
5. 【推断】因此对外表述应是：Foundry Stream 支持高码开发，主要边界是 Java/Code Repositories/UDF；不要承诺 streaming 支持 Python transforms，也不要把 PB UDF 误解为任意 Flink state API。

---

## 2. 快速结论矩阵

| 能力/场景 | Batch pipeline | Streaming pipeline | 是否需要高码 | 说明 |
|---|---|---|---|---|
| 标准清洗、字段派生、filter、join、union、输出 dataset/Ontology | Pipeline Builder 优先 | Pipeline Builder 优先，但只用 streaming 支持的算子 | 通常不需要 | 低码覆盖常规图形化处理。【事实】 |
| 复杂表达式但仍是逐行/扁平映射 | Pipeline Builder custom expression 或 UDF | UDF 需确认 streaming 兼容；Java UDF 更稳妥 | 可能需要 | UDF 适合现有低码 transform 不足、需复用或需外部库。【事实+推断】 |
| 使用第三方 Python/Java 库 | Python/Java transforms 或 PB UDF | Java/UDF 路径；Python transform 不支持 streaming | 需要 | 官方说明 UDF 可引入 Java/Python libraries；stream-vs-batch 表明确 Python transforms 不支持 streaming。【事实】 |
| 访问文件系统、读写 Foundry dataset 文件、处理非结构化文件 | Python/Java Code Repository | 一般不作为 streaming hot path 处理 | 需要 | Code Repositories 支持 filesystem/API access，Pipeline Builder 不支持。【事实】 |
| 访问外部 API/DB、私网/on-prem、受治理凭据 | Python external transforms 或 PB Python function + source import | 谨慎；通常拆到 batch/增量或专用 source/sync | 通常需要 | 外部调用需要 source/egress/credential 治理；PB 可使用 Python function 调外部系统，但本质是高码函数。【事实+推断】 |
| 大规模分布式 Spark/PySpark、pandas/Polars/DuckDB 引擎选择 | Python/SQL/Java Code Repository | 不适用 Python transforms；stream 用 Flink/Java 语义 | 需要 | Batch 高码有更丰富 runtime；stream 不是 Python transform 路径。【事实】 |
| 增量计算 API、复杂 transaction 语义 | Python/Java Code Repository；低码不够时高码 | streaming 自身持续处理，不等同 batch incremental | 可能需要 | 官方建议若 batch 将来需要 incremental，使用 Python 或 Java；只有 Python/Java APIs 可用于 incremental computation。【事实】 |
| 自定义流式状态机、复杂事件序列、CEP、跨事件可控 state | 不适用或用 batch 窗口重算 | Pipeline Builder stateful transforms 只覆盖预置能力；复杂状态需高码/外部流系统评估 | 高概率需要 | 官方说明 PB stateful transform 的 state type 自动处理且不总是用户可访问；UDF 仅 row/flat map，不等价任意 state API。【事实+推断】 |
| Stream-stream / stream-batch join 的标准形态 | 不适用 | Pipeline Builder 支持，但有缓存、大小、batch 侧转换限制 | 标准场景不需要；超出限制需要 | stream-batch join 中 batch 侧不能先在同一 PB pipeline 里转换；stream-stream join 依赖 cache time 约束状态上界。【事实】 |
| 低码 pipeline 整体接管为代码 | Pipeline Builder 可导出 Java transforms | 是否覆盖 streaming 需实测；官方未给完整清单 | 需要 Java 高码 | 导出用于需要 Java libraries，但不可逆、有删除风险、有不可转换节点、有语义差异。【事实】 |
| 单元测试、PR/code review、共享库、影响分析、工程 owner 接管 | Code Repository | Code Repository / UDF repo | 需要 | 这是工程治理能力，不是单个算子能力。【事实+推断】 |

---

## 3. Batch：哪些能力需要高码

### 3.1 不需要高码的默认区间

Batch pipeline 的默认入口仍应是 Pipeline Builder，适合标准结构化处理、图形化 join/union/filter、字段表达式、输出 dataset/Ontology、preview、output check、branch 协作和常规低码交付。【事实】

官方还建议大多数场景先从 batch pipeline 开始；如果后续需要 incremental，再扩展能力。因此 batch 的低码优先策略成立，但不是所有 batch 都应长期停留在低码。【事实+推断】

### 3.2 需要高码的主要能力

| 高码触发条件 | 推荐路径 | 原因 |
|---|---|---|
| 需要 Python/Java/SQL 生态库，或逻辑很难用低码表达 | Code Repositories：Python/Java/SQL | Code Repositories 是 specialized code-based transformations 的入口。【事实】 |
| 需要文件/API 访问、读写 dataset 文件、处理复杂非结构化文件 | Python/Java transforms | 官方对比表显示 Pipeline Builder 无 filesystem/API access，Code Repositories 有。【事实】 |
| 需要 PySpark 全 API、pandas/Polars/DuckDB、复杂 ML/统计库 | Python transforms | Python 支持外部库和完整 PySpark API；单节点/分布式引擎选择在高码侧。【事实】 |
| 需要 incremental API 或预期未来从 batch 演进为增量 | Python 或 Java transforms | 官方建议有 incremental 预期时用 Python/Java；incremental computation 只有 Python/Java APIs。【事实】 |
| SQL 声明式复杂查询但不需要 incremental | SQL transforms | SQL transforms 基于 Spark SQL，适合声明式处理；但不支持 incremental。【事实】 |
| 需要强类型、Java 库、低码导出后长期维护 | Java transforms | Pipeline Builder export 目标是 Java transforms repository，常用于访问特定 Java libraries。【事实】 |
| 需要生产工程治理：unit test、PR/code review、共享库、影响分析、owner 接管 | Code Repositories | 这是 Code Repositories 的核心价值，而不是 Pipeline Builder 的目标。【事实+推断】 |

### 3.3 Batch 的高码边界判断

如果一个 batch pipeline 只是把数据从 A 清洗到 B，并且主要使用平台内置 transform/expression，低码足够。如果出现以下任一信号，应切高码或局部 UDF：

- 低码图开始堆叠大量 workaround，表达式难以 review。
- 逻辑依赖外部库、复杂正则/解析、ML/统计/优化算法。
- 需要访问外部系统、API、私网、凭据或特殊文件格式。
- 需要严肃单元测试、共享模块、PR 审查和长期代码 owner。
- 已经知道未来要走 Python/Java incremental API。

---

## 4. Streaming：哪些能力需要高码

### 4.1 不需要高码的默认区间

Streaming pipeline 可以通过 Pipeline Builder 配置。标准 streaming 场景包括 stream 输入、逐行转换、内置窗口/聚合、stream-batch join、stream-stream join、输出到 streaming dataset/Ontology/time series 等，优先使用 Pipeline Builder 的受控算子。【事实】

官方 stream-vs-batch 表显示 streaming 与 batch 都支持 Java transforms、Pipeline Builder、Ontology、time series、branching、markings 和 provenance；但 Python transforms 只支持 batch，不支持 streaming。【事实】

### 4.2 需要高码的主要能力

| 高码触发条件 | 推荐路径 | 原因 |
|---|---|---|
| 需要完整高码开发 streaming pipeline | Code Repositories advanced user 路径，优先 Java 语义 | 官方对比表写明 Code Repositories 支持 Streaming pipeline，但标注 for advanced users；stream-vs-batch 表写明 Java supported transforms 为 Yes、Python supported transforms 为 No。【事实】 |
| Pipeline Builder streaming transform 不足以表达逐行逻辑 | UDF，优先评估 Java UDF | UDF 用于 PB 现有 transformation 不足或需要复用复杂逻辑；streaming 用户代码有 Java runtime 兼容性事实证据。【事实+推断】 |
| 需要外部 Java/Python library | Java UDF / UDF repo；Python UDF 是否可用于目标 streaming 场景需实测 | 官方 UDF 文档支持 Java/Python libraries，但 stream-vs-batch 明确 Python transforms 不支持 streaming。【事实+推断】 |
| 需要自定义跨事件状态、复杂状态机、CEP、精细 state TTL/savepoint 迁移 | 高码或外部流处理系统评估，不应默认用 PB UDF 承诺 | PB stateful transforms 是预置能力，state 不总是用户可访问；PB UDF 当前只支持 row map/flat map。【事实+推断】 |
| stream-batch join 超出限制：batch 侧需先转换、维表过大、更新频率/启动时间不可接受 | 拆上游 batch/增量预处理，或高码/架构重构 | 官方限制 batch 侧不能在同一 PB pipeline join 前转换，8-10GB 以上性能可能下降。【事实】 |
| stream-stream join 需要非最近值 join、复杂历史匹配、长期状态 | 高码/外部 Flink 设计评估 | PB stream-stream join 使用 cache，且每 key 只保存最近值；cache expiration 是状态上界要求。【事实】 |
| 需要调试/控制流式重放、logic version、runtime 依赖兼容 | UDF repo / advanced Code Repository 操作 | 官方 Q&A 与公告显示 Java deployment UDF、streaming UDF runtime 兼容是高级用户关注点。【事实】 |

### 4.3 Streaming 的高码边界判断

Streaming 的高码判断要比 batch 更保守。原因不是“低码不能做 streaming”，而是 streaming 的失败形态更接近长期在线服务：状态会增长、checkpoint 会影响恢复、逻辑变更会影响已有 state、计算资源持续占用。

如果需求满足下列任一条件，应优先高码评估或先拆成 batch/增量预处理：

- 需要用户可控的 per-key state，而不是内置窗口/聚合/cache join。
- join 不是“当前值/最近值”语义，而是复杂历史匹配。
- 维表大于官方建议区间，或维表需要先在同一流 pipeline 中清洗。
- 需要外部库、私有协议、复杂解析或业务状态机。
- 需要严格 replay、版本迁移、checkpoint/savepoint 或 Java runtime 兼容控制。

---

## 5. 自建平台借鉴

1. 【推断】低码不是“能力差”，而是受控表达面；高码也不是“万能脚本”，而是复杂度出口。平台应把两者统一到同一套 Transform Contract：输入/输出、schema、branch、runtime、状态、质量、权限、血缘。
2. 【推断】Batch 的高码入口应优先支持 Python/SQL/Java，其中 Python 承担最丰富生态和多引擎路由，Java 承担强类型和低码导出接管，SQL 承担声明式 Spark SQL。
3. 【推断】Streaming 的高码入口不应简单照搬 batch Python 生态；应优先明确 Flink/Java/UDF 的运行时边界、状态模型、checkpoint 兼容、partition key 和 replay 策略。
4. 【推断】UDF 适合作为低码的局部扩展，不适合作为所有复杂 pipeline 的兜底。复杂到需要工程 owner、测试、依赖治理、状态迁移时，应升级为完整高码 pipeline 或拆分 pipeline。

---

## 6. 图关系审阅：Batch / Faster / Incremental / Stream / CodeRepo

1. 【事实】Foundry 官方把 pipeline 类型分成三类：Batch、Incremental、Streaming。图中把 `Stream` 放在 `Batch` 大区域下方容易误导；Streaming pipeline 应与 Batch / Incremental 并列，而不是 Batch 的子类型。
2. 【事实】`Faster` 不是独立 pipeline 类型，而是 batch 和 incremental pipeline 的 faster 版本；官方表述是 Foundry offers faster versions of batch and incremental pipelines。因此图中 `Faster` 应画成 Batch/Incremental 的执行模式或变体，而不是和 Batch/Stream 并列的一级对象。
3. 【事实】`Increment Batch` 建议改名为 `Incremental` 或 `Incremental pipeline`。官方术语是 Incremental pipelines，不是 Increment Batch；它与 Batch 都处理 dataset 构建，但计算语义不同。
4. 【事实】Pipeline Builder 和 Code Repositories 是两个 authoring surface。二者都支持 Batch pipeline；Streaming pipeline 在 Pipeline Builder 下支持，在 Code Repositories 下也支持但标注为 `Yes (for advanced users)`。
5. 【推断】更准确的画法是：外层画 `Foundry Building Pipelines`；内部按开发入口分两列 `Pipeline Builder` 与 `Code Repositories`；再用行或标签表达 pipeline 类型：Batch、Incremental、Streaming。`Faster` 作为 Batch/Incremental 的 compute variant 标注在对应类型旁边。

建议修正结构：

```text
Foundry Building Pipelines
├── Pipeline Builder
│   ├── Batch pipeline
│   │   ├── Standard
│   │   └── Faster
│   ├── Incremental pipeline
│   │   ├── Standard
│   │   └── Faster
│   └── Streaming pipeline
└── Code Repositories
    ├── Batch pipeline
    ├── Incremental pipeline
    └── Streaming pipeline (advanced users; Java/UDF-focused)
```

如果保留你当前图的视觉结构，最小修改是：

- 把左侧大框 `Batch` 改成 `Batch pipelines`，只包住 `常规批` 和 `Faster batch`。
- 把 `Increment Batch` 改成 `Incremental pipelines`，并从 Batch 大框里拿出来，与 Batch 并列。
- 把 `Stream` 改成 `Streaming pipelines`，并与 Batch / Incremental 并列。
- 把 `Faster` 改成 `Faster variant`，同时覆盖 Batch 和 Incremental，不要覆盖 Streaming。
- 把右侧 `CodeRepo` 改成 `Code Repositories`，标注 `Batch: yes; Incremental: yes; Streaming: yes, advanced users`。

---

## 7. 参考来源

- Palantir Docs — Considerations: Pipeline Builder and Code Repositories: https://www.palantir.com/docs/foundry/building-pipelines/considerations-pb-cr/
- Palantir Docs — Comparison: Streaming vs batch: https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/
- Palantir Docs — Pipeline Builder Transforms Overview: https://www.palantir.com/docs/foundry/pipeline-builder/transforms-overview/
- Palantir Docs — Java User-defined functions: https://www.palantir.com/docs/foundry/transforms-java/user-defined-functions/
- Palantir Docs — Types of pipelines: https://www.palantir.com/docs/foundry/building-pipelines/pipeline-types/
- Palantir Docs — Export pipeline code: https://www.palantir.com/docs/foundry/pipeline-builder/export-pipeline/
- Palantir Docs — Joins in streaming Pipeline Builder pipelines: https://www.palantir.com/docs/foundry/pipeline-builder/transforms-streaming-joins/
- Palantir Docs — Streaming stateful transformations: https://www.palantir.com/docs/foundry/building-pipelines/streaming-stateful-transforms/
- Palantir Docs — Use Python functions in Pipeline Builder: https://www.palantir.com/docs/foundry/functions/python-functions-builder/
