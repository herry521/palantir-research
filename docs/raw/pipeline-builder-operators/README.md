# Pipeline Builder 算子调研迁移入口

## 摘要与洞察

1. 【事实】本目录从 `pipeline-transform-research` 迁入 Pipeline Builder 转换算子（transform function）与表达式函数（expression function）的正式调研文档和两套最终统一产物。
2. 【事实】迁入的 final bundle 记录了 89 条 transform 和 335 条 expression，是本仓库引用 Pipeline Builder 算子能力基线时的本地证据入口。
3. 【判断】本目录定位为证据层和设计输入层，不替代 `docs/synthesis/palantir-pipeline-deep-dive.md`、`docs/synthesis/operator-platform-design.md` 和 `docs/topics/pipeline.md` 的综合结论。
4. 【边界】Palantir 官方材料仍是第一事实来源；源项目调研文档和结构化清单是第二事实来源。自动解析、临时渲染或 stage 过程文件未迁入本目录。

## 背景、问题、目标与范围

`palantir-research` 已经在 Pipeline、算子平台和 HTML 预览层吸收过 Pipeline Builder 算子调研的核心结论，但此前部分综合文档仍引用源项目的本地绝对路径。这样会让读者必须依赖另一个工作区才能追溯证据，也不利于 GitLab issue、分支、提交和后续审阅形成闭环。

本次迁移的目标是把源项目已经收口的正式结果纳入本仓库，让 Pipeline Builder 算子能力基线、典型用法、transform/expression 关系和自研算子平台设计输入都能在 `palantir-research` 内部完成追溯。本文只说明迁移后的阅读顺序和证据边界，不重新展开一轮算子调研，也不承诺源项目尚未完成的字段级复核。

## 阅读顺序

第一次阅读时，先看 `pipeline-builder-operators-research-summary.md`，理解本轮调研的收口口径、证据边界和后续方向。之后按目标进入不同材料：需要查能力范围时看两个 final bundle；需要理解业务用法时看 transform 和 expression 的用法示例；需要进入自研平台设计时看概要设计、详细设计和关键模块设计索引。

| 目标 | 入口 |
| --- | --- |
| 总结本轮调研结论 | `pipeline-builder-operators-research-summary.md` |
| 查 transform 条目与结构化清单 | `pipeline-builder-transform-functions.md`、`artifacts/transform-final/README.md` |
| 查 expression 条目与结构化清单 | `pipeline-builder-expression-functions-inventory.md`、`artifacts/pb-expression-final/README.md` |
| 理解 transform 与 expression 的分层 | `transform-expression-comparison.md` |
| 查典型用法 | `transform-usage-examples.md`、`expression-usage-examples.md` |
| 查自研算子平台设计输入 | `pipeline-builder-operator-platform-architecture-design.md`、`pipeline-builder-operator-platform-detailed-design.md`、`pipeline-builder-key-module-designs.md` |

## 与本仓库其他文档的关系

本目录提供证据与设计输入，综合判断仍应优先阅读以下文档：

- `docs/topics/pipeline.md`
- `docs/synthesis/palantir-pipeline-deep-dive.md`
- `docs/synthesis/operator-platform-design.md`
- `deliverables/pages/pipeline-builder-operators-overview.html`

后续如果要继续补充 expression 字段级复核、transform 长尾条目证据或新的使用案例，应新建独立 issue，并在本目录或相关综合文档中补充来源说明。
