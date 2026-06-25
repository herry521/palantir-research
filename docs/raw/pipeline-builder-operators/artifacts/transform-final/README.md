# transform 最终统一产物

本目录是 transform 侧的正式清单入口，负责把现有 parse 结果收敛成可复用、可检索、可校验的详细列表。

## 正式文件

- `transform_inventory.jsonl`
- `transform_inventory.csv`
- `transform_inventory_summary.json`

这三份文件共同构成 transform 侧的最终统一产物：

- `transform_inventory.jsonl` 是机器可读主清单。
- `transform_inventory.csv` 是便于检索和外部查阅的表格化副本，`supported_in`、`categories` 和 `declared_arguments` 都按 JSON 结构序列化，写法尽量对齐 `expression_inventory.csv`；其中 `declared_arguments` 的每个元素只保留 `name`、`type` 和 `description`，便于快速浏览。
- `transform_inventory_summary.json` 负责给出数量、唯一性、证据类型与抽取方式的最终汇总。

## 过程文件

以下文件是生成过程中的中间产物，现已从工作区清理；这里只保留路径名用于追溯，不直接作为正式清单：

- `artifacts/transform-links.txt`
- `artifacts/transform-slugs.txt`
- `artifacts/transform-parsed.json`
- `artifacts/html/*.html`
- `artifacts/html/*.rendered.html`

其中：

- `artifacts/transform-parsed.json` 曾是正式清单的直接输入，相关过程文件已清理。
- `docs/pipeline-builder-transform-functions.md` 仍承担 transform 官方摘录与人工叙述。
- `docs/transform-usage-examples.md` 负责场景化入口。

## 阅读顺序

建议优先阅读：

1. `docs/pipeline-builder-transform-functions.md`
2. `docs/transform-usage-examples.md`
3. `docs/transform-expression-comparison.md`

如果需要核对详细字段，再回到本目录中的正式文件。
