# Transform 与 Expression 机制对比

## 背景

仓库现在已经分别有了 transform 与 expression 两条主线。transform 侧的代表性用法已经整理成 `docs/transform-usage-examples.md`，expression 侧的代表性用法已经整理成 `docs/expression-usage-examples.md`，而 `docs/pipeline-builder-transform-functions.md` 与 `docs/pipeline-builder-expression-functions-inventory.md` 则分别承担各自的正式摘录与清单说明。

问题在于，这两条主线虽然各自都能独立阅读，但如果没有一篇对比主文档，读者很容易在真实任务里把它们混在一起：需要改数据结构时误用 expression 解决整条数据流问题，或者只是想补一个字段值却先上 transform。`Issue #5` 要补的就是这一层认知连接。

## 问题

现在最容易造成混淆的地方，不是两类算子“长得像”，而是它们都属于 Foundry 的数据处理工具，又都会接收结构化参数，看上去都能“做事”。如果只看函数名，很难判断某个动作到底是在处理数据流的形状，还是在处理某个字段的值。

另一个容易混淆的点是，expression 经常嵌在 transform 的参数里。比如 transform 文档中的 `Aggregate`、`Pivot`、`Mapping join` 都把 expression 作为参数或默认值的一部分来使用，这会让边界看上去像是“同一层能力的不同写法”。但从职责上看，它们并不是同一层。

因此，本文要解决的不是“谁更强”，而是“什么时候先想 transform，什么时候先想 expression，以及两者如何组合才更稳”。

## 目标

本文只做一件事：把 transform 和 expression 的差异、共同点与组合方式讲清楚，形成一份可以直接作为入口阅读的机制对比文档。

更具体地说，本文会回答四个问题：它们分别处理什么层级的问题，它们的典型分类怎样分布，它们在真实任务里如何配合，以及当前仓库里的证据强弱如何分层。

## 本文范围

本文覆盖分类、功能、适用场景和组合方式的对比，也会说明当前仓库里两条主线的证据形态差异。

本文不覆盖 transform 全量算子索引，不覆盖 expression 全量正式清单的逐条复述，也不重新解释各自的单条函数参数。读者如果想看场景化入口，应回到 `docs/transform-usage-examples.md` 与 `docs/expression-usage-examples.md`；如果想看官方摘录或正式清单，应回到 `docs/pipeline-builder-transform-functions.md` 与 `docs/pipeline-builder-expression-functions-inventory.md`。

## 如何阅读这篇文档

如果你的问题是“这个任务先从哪一层开始”，先看“核心结论”和“机制对比总览”。如果你的问题是“两个体系怎么一起用”，直接看“组合方式”一节。

如果你已经确定手头问题属于某一类场景，再回到 transform 或 expression 的代表性用法文档。本文的作用不是替代那两篇主文档，而是帮你更快判断应该往哪边走。

## 核心结论

第一，transform 更像结构层，expression 更像值层。前者处理一条数据流怎么被切分、合并、解析、分层或重排，后者处理某个位置上的值怎么被计算、转换、兜底或拼装。这个边界不是绝对机械的，但足够稳定，可以作为第一判断。

第二，两者不是竞争关系，而是嵌套关系。transform 常常把 expression 作为参数、聚合表达式或默认值使用；expression 则经常依附于 transform 输出出来的列、字段或中间结果继续计算。把它们理解成“外层结构动作 + 内层值计算”会比把它们当成两套互斥工具更接近真实使用方式。

第三，当前仓库里 transform 的证据更偏“场景 + 复现”，expression 的证据更偏“正式清单 + 场景归纳”。这意味着 transform 文档更适合直接拿来理解问题怎么落地，expression 文档更适合先建立函数地图，再回到具体场景。对比文档的价值，就是把这两种证据风格接起来。

## 机制对比总览

| 维度 | Transform | Expression | 读者可以怎样判断 |
| --- | --- | --- | --- |
| 抽象层级 | 数据流与算子层，通常描述一整步处理动作 | 字段值与表达式层，通常描述一个值如何被计算 | 需要改表结构、连数据集、做文件解析时，优先想 transform |
| 操作对象 | 数据集、表、文件、流、地理对象 | 单个值、列值、表达式树中的子结果 | 需要对“整条数据”动手时用 transform，需要对“某个值”动手时用 expression |
| 对输入输出的影响 | 可改变行数、列数、数据集形态或执行语义 | 通常生成一个值，或作为更大操作中的一段公式 | 如果任务会改变数据形状，通常已经超出纯 expression 的职责 |
| 常见分类 | Aggregate、Join、File、Geospatial、Streaming、Other | Numeric、Boolean、String、Datetime、Cast、Array、Struct、Map、Data preparation、Popular | transform 的分类更接近场景与执行方式，expression 的分类更接近值的类型与写法 |
| 组合关系 | 经常把 expression 当作参数、聚合规则或默认值 | 经常作为 transform 的内部公式，也可继续嵌套调用 | 看到“某个 transform 参数里写了一段计算”，通常就是两者配合而不是二选一 |
| 当前仓库证据 | `docs/transform-usage-examples.md` 中已有 10 个代表场景与本地复现 | `docs/expression-usage-examples.md` 中已有 10 个高频类别场景，但本地样例较少 | transform 更适合做“怎么落地”的入口，expression 更适合做“怎么表达”的入口 |

## 分类为什么不一样

transform 的分类主要按能力动作展开，例如聚合、连接、文件解析、地理空间处理和流式语义控制。它关心的是“这一步在数据流里做了什么”，所以同一个算子往往会同时定义支持环境、输入表、输出形态和执行约束。

expression 的分类主要按值的类型和写法展开，例如数值、布尔、字符串、时间、类型转换、数组、结构体、映射和数据准备。它关心的是“这个位置上的值怎么计算”，所以同一个类别里常常是一组写法模式，而不是一个独立的数据流动作。

这也是为什么 transform 文档更自然地按场景讲，expression 文档更自然地按类别讲。两者都能按场景解释，但各自最稳定的入口不同。

## 功能边界怎么看

如果问题本身在问“怎么把多行明细变成一个结果”“怎么把多个数据集合并”“怎么从文件里抽出结构化行”“怎么按地理关系或流式语义处理数据”，先看 transform。因为这些任务本质上是在处理数据流形状，通常需要一个明确的算子步骤。

如果问题本身在问“这个值怎么兜底”“多个条件怎么拼起来”“字符串怎么清洗”“时间怎么解析”“map 或 struct 里怎么取值”，先看 expression。因为这些任务本质上是在一个已有位置上表达一个值，而不是在重写整条数据流。

需要注意的是，expression 并不只负责“简单计算”。它也能表达结构化值、条件分支和嵌套数据结构，但这些能力仍然是在值层面工作。反过来，transform 也不只是“移动数据”，它常常把 expression 作为内部公式使用。边界的关键不是“能不能算”，而是“这一步是在改数据流，还是在改字段值”。

## 组合方式

最常见的组合方式是 transform 做外层，expression 做内层。比如 `Aggregate` 的聚合规则就是 expression，`Mapping join` 的默认值也可以写成 expression，`Pivot` 里同样需要表达聚合逻辑。这里的 transform 负责告诉系统“数据怎么组织”，expression 负责告诉系统“每个位置算什么”。

第二种组合方式是先用 transform 把结构整理成更稳定的样子，再用 expression 做后续字段计算。比如先用文件解析、连接或分组把字段落到目标表，再用 `firstNonNullV1`、`caseV2`、`cleanStringV1`、`parseJsonAsSchemaV3` 这类写法继续处理字段值。这样拆开之后，结构层和表达层更容易分别验证。

第三种组合方式是把多个 expression 先组织成一组清晰的值逻辑，再把它们嵌回 transform。这个顺序在复杂规则里尤其重要，因为它能避免把“规则判断”和“数据形状变化”混成一坨。只要任务里同时出现“改结构”和“算值”，通常就意味着两层都要用，但外层和内层不要互相替代。

## 什么时候先选谁

如果你在需求里看到的是“按组汇总”“多表合并”“文件导入”“地理相交”“流式分区”“层级汇总”这类词，先选 transform。它们提示的都是外层动作，单纯 expression 往往不够。

如果你在需求里看到的是“默认值兜底”“条件分支”“字符串清洗”“时间格式化”“数组或 map 取值”“JSON 结构化”这类词，先选 expression。它们提示的都是字段值问题，transform 只是在更大流程里承载这些值。

如果需求同时有两类词，就把它拆成两层。外层先决定数据怎么流转、怎么合并、怎么落表，内层再决定每个字段怎么计算、怎么兜底、怎么格式化。这个拆法通常比直接争论“应该用 transform 还是 expression”更接近实际工作方式。

## 当前仓库的证据分层

事实层上，transform 侧已经有 `docs/pipeline-builder-transform-functions.md` 的官方摘录、`docs/raw/pipeline-builder-operators/artifacts/transform-final/README.md` 指向的最终详细清单，以及 `docs/transform-usage-examples.md` 的代表性场景入口。expression 侧已经有 `docs/pipeline-builder-expression-functions-inventory.md` 的正式清单说明、`docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/README.md` 指向的最终统一产物，以及 `docs/expression-usage-examples.md` 的代表性场景入口。

判断层上，本文把 transform 解释为结构层、expression 解释为值层，是基于这些现有材料做出的归纳，而不是官方直接给出的术语。这个判断对当前仓库足够稳定，但仍然是归纳，不是原文引述。

局限层上，transform 侧的代表性场景已经有较强的本地复现支撑，但 expression 侧当前仍以正式清单和场景归纳为主，缺少同等级的本地输入输出样例。因此本文能明确说明两者的职责差异，但不能把两条主线的证据强度写成完全对称。

## 事实、判断与局限

### 事实

`docs/pipeline-builder-transform-functions.md` 已经把 transform 的官方摘录按场景和参数结构整理出来；`docs/transform-usage-examples.md` 进一步把它收敛成 10 个代表性场景。`docs/pipeline-builder-expression-functions-inventory.md` 已经说明 expression 正式清单的字段、数量与边界；`docs/expression-usage-examples.md` 进一步把它收敛成 10 个高频类别场景。

在这两条主线上，transform 与 expression 都不是孤立存在的文件，而是已经形成“摘录/清单 -> 代表性入口 -> 收尾总结”的阅读链路。本文的位置就是把这两条链路放在同一张图里看。

### 判断

“transform 处理结构，expression 处理值”“transform 常嵌 expression，expression 常嵌在 transform 里”“transform 更适合做流程入口，expression 更适合做字段入口”这些表述，都是基于现有仓库材料的归纳判断。它们足够稳定，适合作为第一版对比口径，但不应被误写成官方术语本身。

### 局限

本文没有尝试把 transform 与 expression 的所有函数一一对照，也没有把每一个场景都做成一对一映射。原因不是材料不足，而是那样会把对比文档写回索引表，反而丢掉入口文档的价值。

另外，expression 侧当前仍缺少像 transform 那样成体系的本地复现样例，因此对比时不能把两者的证据形态写成同一密度。本文能做的是诚实区分证据强弱，并告诉读者该先去看哪一类材料。

## 相关文档

- `docs/transform-usage-examples.md`：transform 代表性用法主文档，适合先看结构层场景。
- `docs/expression-usage-examples.md`：expression 代表性用法主文档，适合先看值层场景。
- `docs/pipeline-builder-transform-functions.md`：transform 官方摘录与参数结构来源。
- `docs/pipeline-builder-expression-functions-inventory.md`：expression 正式清单与字段边界说明。
- `docs/raw/pipeline-builder-operators/artifacts/transform-final/README.md`：transform 最终统一产物入口。
- `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/README.md`：expression 最终统一产物入口。
- `docs/pipeline-builder-operators-research-summary.md`：调研收尾总结，说明现状、历史与后续方向的分层。
