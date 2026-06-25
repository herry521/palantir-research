# Pipeline Builder 算子调研总结

## 背景

本项目围绕 Palantir Foundry 中的转换算子（transform function）与表达式函数（expression function）开展基础调研。本轮工作来自 Issue #195 的收尾整理，但本文按内容命名和组织，作为 Pipeline Builder 算子调研总结保留。到本次收尾开始前，仓库内已经形成了初始计划、transform 条目摘录、自动解析结果、若干典型场景的复现实验输出，以及多批阶段性 artifacts。问题不再是“是否开始调研”，而是“如何把已经完成的工作收敛成一份后续可复用、可交付、可审计的总结”。

## 问题

当前材料存在两个明显特点。第一，正式文档与阶段性产物混在一起，读者很难快速判断哪些内容可以直接当作结论，哪些内容只是辅助线索。第二，现有 `Issue #2` 的标题和验收更偏向 expression 函数列表整理，而仓库内已经沉淀的主要正式材料更集中在 transform 侧。这意味着如果直接把所有现有文件打包称为“调研完成”，会同时引入范围漂移和证据边界不清两个问题。

## 目标

本文的目标不是继续扩展调研，而是为本轮基础调研给出一个可核对的收尾口径。具体来说，本文要回答三件事：本轮已经确认了哪些事实；哪些判断仍然属于推断或待核对线索；如果后续继续推进，最合理的起点应该是什么。

## 本次收尾覆盖范围

本次收尾基于仓库内截至 2026-05-15 已存在的调研文档、复现结果和阶段性 artifacts 进行收敛，不重新发起一轮完整抓取。凡未进入本次总结正文或证据清单的文件，均视为辅助材料，不在本次交付范围内单独承诺。

在收尾整理期间，`docs/raw/pipeline-builder-operators/artifacts/pb-expression-verify-final/our_html_slugs.txt`、`docs/raw/pipeline-builder-operators/artifacts/pb-expression-verify-final/sitemap_slugs.txt`、`docs/raw/pipeline-builder-operators/artifacts/pb-expression-verify-final/slugs_extra_in_html.txt` 与 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-verify-final/slugs_missing_in_html.txt` 只用于 expression 覆盖范围核对。它们与已跟踪的 `palantir_compare_final.json`、`palantir_compare_final.txt`、`palantir_h1_compare.json` 存在信息重叠，且未被现有调研文档作为正式结论引用，因此在 final bundle 成形后已作为辅助中间产物清理掉，不纳入正式交付。

## 结论

本轮基础调研已经完成了一次可复用的 transform 侧入门收敛，已经足以支撑后续继续研究或设计实现时的第一轮认知对齐，因此“继续无边界扩展抓取”不是当前最有价值的动作。更合理的结项方式，是承认这轮成果已经把 transform 侧的若干关键场景摸到了可验证层面，同时明确 expression 全量整理和少数动态渲染条目补完仍未完成，把它们单独放入后续事项，而不是混进本次完成口径里。

更具体地说，当前仓库已经有五类可以直接复用的正式材料：一是初始范围与方法约束，二是 transform 官方条目摘录，三是自动解析得到的覆盖线索，四是至少五个典型场景的复现实验输出，五是围绕 Rollup 等未完全核对条目的补充问题记录。这套材料已经足够支持“本轮做到了哪里、没有做到哪里、为什么如此判断”的说明。

## 现状、历史与后续方向

从现状看，仓库内最扎实的部分是 transform 侧。`docs/pipeline-builder-transform-functions.md` 已经把 Aggregate、Pivot、Window、Parse Excel、Parse KML、Mapping join、Geometry intersection join 等条目按来源、支持环境、参数和说明整理出来；`docs/raw/pipeline-builder-operators/artifacts/transform-final/README.md` 又把这批解析结果正式收口为 `transform_inventory.jsonl`、`transform_inventory.csv` 和 `transform_inventory_summary.json`。expression 侧也已经由 `docs/pipeline-builder-expression-functions-inventory.md` 与 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/README.md` 一起收口成 `expression_inventory.json`、`expression_inventory.csv` 和 `expression_inventory_summary.json`。这意味着“官方说明 + 最终统一产物”已经在两条主线上分别形成了双重证据。

从历史看，本轮工作最初以 `Issue #2` 启动，问题定义是调研 transform / expression 的实现机制与使用场景。但在实际推进过程中，仓库首先沉淀下来的是 transform 侧条目整理与实验输出，expression 侧则更多保留为覆盖核对产物和中间清单。现在这两条线都已经收口到各自的 final bundle，说明本轮已经自然形成了一条更清晰的主线：先把中间产物分层，再把可复用的最终产物固定下来，最后再决定是否继续扩展到新的细分问题。

从后续方向看，最自然的下一步不是继续补零散条目，而是围绕这两套 final bundle 做更细一层的复核或扩展。第一类是 expression 的字段级再校验，如果未来要继续提升证据等级，应在 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/README.md` 这套统一产物之上另开 issue；第二类是 transform 的少数长尾条目补完或证据加固，如果未来要继续扩展，也应以 `docs/raw/pipeline-builder-operators/artifacts/transform-final/README.md` 为起点，而不是回头依赖阶段性解析文件。两者都应独立建 issue，而不应该继续塞进本次收尾范围。

## 证据与边界

### 事实

本次可以直接认定为事实的内容主要来自两类来源。第一类是 Palantir 官方文档及其在 `docs/pipeline-builder-transform-functions.md` 中的摘录，包括条目名称、支持环境、参数结构、示例描述和官方备注。第二类是已经写入 `docs/archive/research-history/issue-2-research-results.md` 的本地复现实验输出，其中至少包含 Aggregate、Pivot、Window、Mapping join、Geometry intersection join 五个场景，因此可以支持“这些样例在给定输入下产生了相应输出”的表述。

### 推断

本次收尾中保留的推断主要有两类。第一类是基于多份 transform 条目归纳出的共性判断，例如这套能力在设计上明显区分了聚合、连接、窗口与文件解析等不同场景，并倾向于通过显式参数约束运行时行为。第二类是基于现有文档结构做出的项目判断，例如“本轮仓库成果更偏 transform 而非 expression”这一点，并不是官方口径，而是对当前仓库产物分布的归纳。

### 局限

本轮材料也有明确局限。原 `docs/transform-functions-parsed.md` 是自动解析结果，存在明显格式噪音，已经不再作为正式文档保留；现在 transform 已经补出 `docs/raw/pipeline-builder-operators/artifacts/transform-final/README.md` 指向的详细清单，但这份清单仍应和 `docs/pipeline-builder-transform-functions.md` 的人工叙述并列理解。`issues/rollup-parameters-complete.md` 也说明了 Rollup 条目仍需借助可执行 JavaScript 的抓取器补齐参数与示例，当前不宜把它表述成“已完整核对”。另外，expression 侧虽然已经收口为 final bundle，但仍需要在 `docs/pipeline-builder-expression-functions-inventory.md` 之外继续保持对字段级完整度信号的谨慎解读。

## 建议动作

本次收尾完成后，建议把后续工作控制在两个方向内。其一，如果目标是继续提升证据等级，优先在 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/README.md` 这套最终统一产物之上处理 expression 的字段级复核，而不要重新回到 stage 或 compare 文件。其二，如果目标是继续提升 transform 文档质量，则优先围绕 `docs/raw/pipeline-builder-operators/artifacts/transform-final/README.md` 这套最终详细清单补齐少数长尾条目或证据说明。无论选哪条路线，都应以本文作为起点，而不是重新从零梳理已有产物。

## 相关文档

- 初始调研计划：`docs/archive/research-history/issue-2-plan.md`
- 调研过程记录：`docs/archive/research-history/issue-2-research.md`
- 复现结果：`docs/archive/research-history/issue-2-research-results.md`
- transform 代表性用法：`docs/transform-usage-examples.md`（`Issue #3` 在本次收尾之后继续补写的场景化主文档，供当前阅读使用，但不回溯改写本文截至 2026-05-15 的收尾判断）
- expression 代表性用法：`docs/expression-usage-examples.md`（`Issue #4` 在本次收尾之后继续补写的场景化主文档，供当前阅读使用，但不回溯改写本文截至 2026-05-15 的收尾判断）
- transform 与 expression 机制对比：`docs/transform-expression-comparison.md`（`Issue #5` 在本次收尾之后继续补写的对比主文档，帮助读者在两条主线之间建立入口判断，但不回溯改写本文截至 2026-05-15 的收尾判断）
- 算子平台概要设计：`docs/pipeline-builder-operator-platform-architecture-design.md`（`Issue #198` 在现有调研材料之后补写，面向自研平台复刻/对齐 Pipeline Builder 算子能力，不回溯改写本文截至 2026-05-15 的收尾判断）
- 算子平台详细设计：`docs/pipeline-builder-operator-platform-detailed-design.md`（`Issue #198` 在概要设计之后补写，面向后续实现拆分，不回溯改写本文截至 2026-05-15 的收尾判断）
- 算子平台关键模块设计索引：`docs/pipeline-builder-key-module-designs.md`（`Issue #200` 至 `Issue #204` 按模块独立拆分，说明注册中心、表达式 AST、类型系统、批处理计划器、输出与数据期望之间的依赖关系）
- transform final bundle：`docs/raw/pipeline-builder-operators/artifacts/transform-final/README.md`
- expression final bundle：`docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/README.md`
- HTML 版本：`docs/pipeline-builder-operators-overview.html`（当前视觉总入口，作为新人了解 transform / expression 算子的内容总览页）
- 官方条目摘录：`docs/pipeline-builder-transform-functions.md`
- transform 结构化清单：`docs/raw/pipeline-builder-operators/artifacts/transform-final/README.md`
- Rollup 后续问题：`issues/rollup-parameters-complete.md`

## 最终收口（补记）

在后续补写完成之后，本轮调研已经形成一条完整的阅读链路：`docs/pipeline-builder-transform-functions.md` 和 `docs/pipeline-builder-expression-functions-inventory.md` 负责各自的正式摘录与清单，`docs/raw/pipeline-builder-operators/artifacts/transform-final/README.md` 和 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/README.md` 负责各自的最终统一产物入口，`docs/transform-usage-examples.md` 和 `docs/expression-usage-examples.md` 负责各自的代表性用法入口，`docs/transform-expression-comparison.md` 负责把 transform 与 expression 放在同一张图里对照，`docs/pipeline-builder-operators-research-summary.md` 继续承担本轮调研的总收口说明。

从交付状态看，这轮调研已经不再需要继续新增主文档来解释 transform / expression 的基础关系。现有材料足以支撑后续复用、再检索和再验证；如果未来还要继续扩展，只需要在新的独立 issue 里按单一目标拆分即可，不必再把新的问题混进本轮收尾里。当前更重要的是，后续阅读应优先从两个 final bundle 入口开始，而不是从 stage、verify 或 parse 产物开始。

从工作区状态看，这类 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-verify-final/*.txt` 辅助文件已经完成分析并从工作区清理，不再保留为正式交付内容。它们只用于表达式覆盖范围的额外核对，相关要点已经由本文和前面的正式文档吸收，不影响本轮正式结论。
