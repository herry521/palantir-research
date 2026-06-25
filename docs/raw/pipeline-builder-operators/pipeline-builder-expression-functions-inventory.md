# Pipeline Builder Expression 函数清单说明

本文当前正式结论是：`docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory.json` 与 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory.csv` 已形成一份 335 条的 expression 函数正式清单；数量、一致性与异常检测结果以 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory_summary.json` 为准，当前显示 `inventory_count = 335`、`unique_slug_count = 335`、`expected_count = 335`、`duplicate_slugs = []`、`mismatches_count = 0`、`anomaly_detected = false`。同时，summary 也额外公开了字段级质量信号：`category_null_count = 3`、`supported_in_null_count = 1`、`return_type_null_count = 0`、`empty_arguments_count = 6`、`notes_nonempty_count = 331`、`partial_argument_record_count = 1`。这些结果说明正式清单在条目数量、slug 去重和既定覆盖校验上已经闭合，但不等于每个字段都完成了人工字段级复核。生成这套正式清单时使用过的 stage / verify 过程产物已经在 final bundle 收口后清理，本篇仅保留其历史路径作为追溯线索。

## 背景

本轮整理来自 Issue #2，但本文按内容目的命名和组织。它不是重新抓取一轮 expression 页面，而是在仓库已有阶段性产物之上，整理出一份可以正式交付、可以复核、也方便后续继续维护的函数清单。Task 1 已经确认 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-stage-20260515T025809Z-v5/pb_expressions_full.v5.jsonl` 是当前唯一可信的规范化输入基线；`docs/raw/pipeline-builder-operators/artifacts/pb-expression-verify-final/palantir_h1_compare.json` 只能作为优先核对线索和候选覆盖校验基线；`palantir_compare_final.*` 现状与其他输入冲突，因此不能直接当作最终事实来源。

在这个前提下，Task 2 到 Task 4 先冻结字段结构和证据边界，再生成正式清单、CSV 导出和汇总校验文件。Task 5 的职责不是重新定义口径，而是基于真实产物回填正式文档，让阅读者能够直接分辨“哪份文件是正式清单”“哪份文件负责数量与校验结论”“哪些字段已经闭合，哪些仍保留自动解析局限”。

## 问题

当前仓库里的 expression 相关产物来自多轮抓取、校验和比对，文件名接近，但用途并不相同。对阅读者来说，最容易混淆的不是“有没有数据”，而是“哪一份数据可以作为正式结论”“哪些字段是事实，哪些还只是自动抽取线索”“遇到页面结构异常时该怎样写入交付物而不误导读者”。

如果这些问题不先冻结口径并结合真实产物回填，后续阅读者很容易把 `expression_inventory.json` 的记录级结果、`expression_inventory.csv` 的查阅便利性和 `expression_inventory_summary.json` 的校验结论混为一谈。这样即便条目数量正确，最终文档也仍然不具备稳定的复查价值。

## 目标

本文要解决的核心问题只有一个：把 expression 正式清单说明成一份可直接交付、可继续复核的正式文档。这里的“正式”有三层含义。第一层是正式清单文件已经落到固定位置，并明确由 `expression_inventory.json` 和 `expression_inventory.csv` 承担；第二层是数量、唯一性和异常检测有固定汇总文件承接，不再散落在临时日志或对比文本里；第三层是文档明确说明事实边界，不把自动解析结果夸大成字段级全部无误。

## 本文范围

本文覆盖正式交付字段结构、真实结果概览、证据分层、局限和交付物清单。它回答的是“本次 expression 全量整理最终交付了什么、这些结果该怎样解读”，而不是重述全部脚本实现细节。

与执行计划相关的步骤拆解请继续阅读 `docs/superpowers/plans/2026-05-15-expression-inventory.md`；与 issue 初始范围相关的上下文请并列阅读 `docs/archive/research-history/issue-2-plan.md`。若需要按“问题场景 -> 代表函数 -> 当前证据”方式进入 expression 侧材料，而不是直接从 335 条正式清单逆向查找，请并列阅读 `docs/expression-usage-examples.md`。若需要回看正式产物本身，应优先直接查看 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/README.md`，而不是继续追溯彼此冲突的阶段性 compare 结果。

## 结果概览

本次正式产物已经闭合成一套“清单文件 + 汇总文件”的交付结构。正式清单以 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory.json` 和 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory.csv` 为准，两者当前都对应同一批 335 条 expression 函数记录；其中 JSON 是机器可读主文件，CSV 主要承担检索、表格查阅和外部对照用途。

数量和校验结果统一以 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory_summary.json` 为准。当前汇总结果表明：正式清单总量为 335，唯一 slug 数也是 335，和既定 `expected_count = 335` 一致；`duplicate_slugs` 为空，说明 summary 没有发现 slug 重复；`mismatches_count = 0`，说明本次汇总口径下没有落出覆盖不一致项；`anomaly_detected = false`，说明 summary 没有检测到需要升级处理的总量级异常。

这些结论只说明“正式清单已经形成且总量校验通过”，不等于“每个字段都已人工逐条确认”。本次 summary 已显式把字段级质量信号单列为 `quality_metrics`，其中 `category_null_count = 3`、`supported_in_null_count = 1`、`empty_arguments_count = 6`、`notes_nonempty_count = 331`，并且 `partial_argument_record_count = 1` 说明当前仍有极少数条目只保留了稳定识别出的部分参数对象。换句话说，`anomaly_detected = false` 只代表数量、slug 和 H1 compare 这一层没有异常，不代表 `category`、`supported_in`、`arguments`、`return_type`、`notes` 等字段已经全部字段级清零。

## 字段定义

正式产物中的每个 expression 函数，至少应输出以下十个字段。字段数量后续可以增加，但不应删改这些基础字段的含义。

- `slug`：官方 URL 末段，作为函数的稳定标识，例如 `addV2`。若页面跳转或链接格式有差异，也应归并到最终稳定末段。
- `title`：官方页面标题（page title）。这个字段优先保留页面原始标题，用于和其他来源做逐项对照。
- `name_zh_or_summary`：名称或摘要占位字段，不承担“已经完成中文化”的含义。当前正式产物主要落的是英文名称或英文摘要，用来保留页面可读描述；若后续需要补做中文整理，应作为单独工作推进，而不是把现有字段直接视为中文功能摘要。下游不应把它当作官方命名字段，也不应默认它已经是中文结果。
- `category`：函数所属类别，例如 Numeric、String、DateTime、Struct。若页面明确给出多个类别，应按可复核形式保留，而不是合并成含糊描述。当前正式产物中该字段允许为数组，也允许在未稳定解析时保留为空。
- `supported_in`：支持的运行环境或执行模式，例如 Batch、Faster、Streaming。若来源只有线索而非明确表述，应在证据字段或备注中标明。
- `arguments`：入参数组。当前正式行为优先追求“诚实且可复核”的保留方式：只要能稳定识别参数名和参数说明，即使类型识别不到，也允许保留部分参数对象，并把 `type` 写成 `null`，同时在 `notes` 记录 `arguments_partial_type_missing:*` 之类说明；只有在参数名、说明和类型都无法稳定分离时，才退回空 `arguments`。若页面提供是否必填、默认值或可变参数等信息，可以继续扩展，但不得依据示例或上下文反推补造。
- `return_type`：返回类型（return type）。若官方页面没有直接给出，应明确保留为空或待复核，而不是从示例中反推后直接写成事实。
- `source_url`：该条目的官方来源链接。正式交付必须能通过这个字段回到原始页面，而不是只保留中间抓取路径。
- `evidence_type`：记录级证据类型。当前统一只使用 `事实` 与 `线索` 两类；前者表示该条记录的主体信息可直接定位到官方页面或已确认的结构化校验结果，后者表示该条记录主要仍依赖自动解析、尚未逐条人工复核。它只描述整条记录的主类型，不负责逐字段表达差异。
- `notes`：备注。用于记录抽取异常、页面编码问题、结构缺失、候选冲突、待人工复核说明，以及任何会影响读者理解该条可信度的补充信息。

为了避免不同输出格式发生语义漂移，后续 JSON、CSV 和面向阅读者的总结文档都应遵守同一原则：`slug`、`source_url` 和 `evidence_type` 用来回答“这条记录是谁、来自哪里、主证据级别是什么”；`title`、`name_zh_or_summary`、`category`、`supported_in`、`arguments`、`return_type` 用来回答“这个函数做什么、怎么调用、返回什么”；字段级缺失、局部不确定性和解析异常不再试图用同一个 `evidence_type` 细分表达，而是通过空值规则与 `notes` 明确保留。

## 事实、推断与局限

事实层已经可以明确写入三点。第一，正式清单文件就是 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory.json` 与 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory.csv`。第二，数量、一致性与异常检测结果应当只引用 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory_summary.json`。第三，按 summary 当前结果，本次正式清单已达到 `inventory_count = 335`、`unique_slug_count = 335`、`expected_count = 335`、`duplicate_slugs = []`、`mismatches_count = 0`、`anomaly_detected = false`，同时还显式暴露 `quality_metrics` 用于表达字段级完整度信号。

推断层主要体现在可读化整理，而不是覆盖数量本身。`name_zh_or_summary` 当前更接近“名称或摘要占位字段”，正式产物里绝大多数值仍是英文名称或英文摘要，不应被误读成已经完成中文整理后的结果；部分 `category`、`arguments` 和 `return_type` 的结构化结果来自自动解析后的归一化整理，读者应把它们理解为“当前可复核的整理结果”，而不是“字段级全部完成人工签字确认的事实层结论”。

局限需要保留得比结果更清楚。当前正式清单虽然已经通过总量与 slug 级校验，但记录级 `evidence_type` 的实际分布是 `335/335` 全部为 `线索`，并不存在一部分条目已经在正式清单中升级成 `事实` 的情况。这说明本次交付的证据等级仍停留在“全量自动整理后待继续复核”的阶段。summary 中新增的 `anomaly_scope` 已明确写出：`anomaly_detected` 只覆盖数量、slug 唯一性/空值，以及 `palantir_h1_compare.json` 的 `expected_count` 与 `mismatches_count`，不覆盖 `category`、`supported_in`、`arguments`、`return_type`、`notes` 等字段级质量问题。因此，即使 `anomaly_detected = false`，仍然可能同时出现 `category_null_count > 0`、`supported_in_null_count > 0`、`empty_arguments_count > 0` 或 `partial_argument_record_count > 0`。这不是 summary 自相矛盾，而是刻意把“数量闭合”和“字段仍待复核”拆成两个层级表达。`notes` 中出现的 `parse_warning: args_missing_but_heading_present`、`arguments_partial_type_missing:*`、类型变量约束提示和其他自动解析线索，也说明参数区块和类型信息并非每页都能稳定抽取。再加上 `name_zh_or_summary` 当前几乎全部还是英文名称或英文摘要，这份正式清单更适合被理解为“结构统一、总量闭合、便于后续复核的正式底稿”，而不是“已完成中文化和字段级人工定稿的最终知识库”。

因此，后续若要继续提升这份清单的证据等级，优先动作应该是针对 `notes` 中的高频告警做人工抽样或规则修订，而不是改写 summary 已闭合的数量结论。现状、历史和后续方向在这里需要分层理解：现状是正式清单与 summary 已落地；历史是它们来自阶段性抓取和规范化脚本整理；后续方向是继续减少 `线索` 和解析告警，而不是重新争论 335 这个总量是否已经闭合。

## 交付物

本次正式交付由三类文件组成。第一类是正式清单文件：`docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory.json` 与 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory.csv`，前者是机器可读主清单，后者是表格化导出。第二类是正式汇总文件：`docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory_summary.json`，负责保存数量、唯一性、重复项、覆盖差异和异常检测结果。第三类是生成这些正式产物所依赖的脚本文件：`scripts/build_expression_inventory.js` 与 `scripts/verify_expression_inventory.js`。

文档层面的正式交付物就是本文本身。它的职责不是复制全部 335 条记录，而是把正式文件的角色分工、结果边界和局限解释清楚，让后续阅读者知道应该以哪份文件为准，以及哪些结论可以直接引用，哪些仍需要继续复核。

## 相关文件

- `docs/superpowers/plans/2026-05-15-expression-inventory.md`：本轮执行计划，说明 Task 1 到 Task 5 的顺序与验证方式。
- `docs/archive/research-history/issue-2-plan.md`：Issue #2 的原始计划与上下文入口；本文与它并列阅读，前者偏任务范围，本文偏正式交付说明。
- `docs/expression-usage-examples.md`：`Issue #4` 的场景化主文档，适合从高频问题入口理解 expression，而不是从全量条目倒推。
- `docs/raw/pipeline-builder-operators/artifacts/pb-expression-stage-20260515T025809Z-v5/pb_expressions_full.v5.jsonl`：生成正式清单时的唯一规范化输入基线，相关 stage 产物已在收口后清理。
- `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory.json`：正式机器可读清单主文件。
- `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory.csv`：正式表格化清单。
- `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/expression_inventory_summary.json`：正式数量与校验结果文件。
- `docs/raw/pipeline-builder-operators/artifacts/pb-expression-final/README.md`：expression 最终统一产物入口，说明正式文件与过程文件的分层。
- `scripts/build_expression_inventory.js`：规范化生成脚本。
- `scripts/verify_expression_inventory.js`：正式清单校验脚本。
- `docs/raw/pipeline-builder-operators/artifacts/pb-expression-verify-final/palantir_h1_compare.json`：生成时的优先核对线索和候选覆盖校验基线，相关 verify 产物已在收口后清理，不直接替代正式条目事实。
- `docs/raw/pipeline-builder-operators/artifacts/pb-expression-verify-final/palantir_compare_final.json` 与 `docs/raw/pipeline-builder-operators/artifacts/pb-expression-verify-final/palantir_compare_final.txt`：生成时的比对产物，曾与其他输入冲突，现已清理，仅保留历史说明。
