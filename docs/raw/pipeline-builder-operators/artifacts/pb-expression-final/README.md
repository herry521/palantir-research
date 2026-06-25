# expression 最终统一产物

本目录是 `Issue #2` expression 侧的正式交付入口，只承载最终统一产物，不再把阶段性抓取、比对或调试输出当作正式清单。

## 正式文件

- `expression_inventory.json`
- `expression_inventory.csv`
- `expression_inventory_summary.json`

这三份文件共同构成 expression 侧的最终统一产物：

- `expression_inventory.json` 是机器可读主清单。
- `expression_inventory.csv` 是便于检索与外部查阅的表格化副本。
- `expression_inventory_summary.json` 负责给出数量、唯一性和字段级质量信号的最终汇总。

## 过程文件

以下文件是生成过程中的中间产物，现已从工作区清理；这里只保留路径名用于追溯，不再把它们当作正式结论来源：

- `artifacts/pb-expression-stage-20260515T021924Z/`
- `artifacts/pb-expression-stage-20260515T022645Z-v2/`
- `artifacts/pb-expression-stage-20260515T022938Z-v2/`
- `artifacts/pb-expression-stage-20260515T023339Z-v3/`
- `artifacts/pb-expression-stage-20260515T023539Z-v4/`
- `artifacts/pb-expression-stage-20260515T025809Z-v5/`
- `artifacts/pb-expression-verify-final/`

其中：

- `pb-expression-stage-20260515T025809Z-v5/pb_expressions_full.v5.jsonl` 是生成正式清单时的规范化输入基线，相关 stage 产物已清理。
- `pb-expression-verify-final/palantir_h1_compare.json` 是优先核对线索和候选覆盖基线。
- `pb-expression-verify-final/palantir_compare_final.json` 与 `palantir_compare_final.txt` 仅保留为追溯参考，不直接作为正式事实来源。

## 阅读顺序

建议优先阅读：

1. `docs/pipeline-builder-expression-functions-inventory.md`
2. `docs/expression-usage-examples.md`
3. `docs/transform-expression-comparison.md`

如果需要核对字段级口径，再回到本目录中的正式文件。
