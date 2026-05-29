# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

本仓库是对 Palantir Foundry Pipeline 体系的深度调研文档库，包含原始调研笔记、综合分析报告和架构图。

## 目录结构

```
docs/
  raw/          # 原始调研文档（按主题编号）
  synthesis/    # 综合分析报告
  superpowers/  # 特定功能/方案的深度规格文档
    specs/      # 规格说明文件
diagrams/       # 架构图（draw.io 源文件 + PNG 导出）
```

## 调研文档编号规范

`docs/raw/` 中的文件按主题编号：
- `01` — Pipeline Expression DSL
- `02` — Execution Engine（Spark 批处理 + Flink 流处理）
- `03` — Streaming & Batch Architecture
- `04` — Lineage & Ontology Integration
- `05` — Testing & Data Connection

新增调研文档按顺序继续编号：`06-<主题>.md`

## 工作流程

### 项目级约束

- 所有工作项必须有 GitLab Issue 跟进；如果用户未提供 issue，先查询是否已有对应 issue，没有则创建后再推进。
- 调研结论输出后，必须立即完成验证、commit 和 push；不得只交付结论而把相关文档或 HTML 产物长期留在本地未提交状态。

每完成一轮调研后必须执行 commit + push（见全局 `knowledge-capture.md` 规则）：
```bash
git add docs/ diagrams/
git commit -m "docs: <调研主题>调研完成

- 覆盖方向：...
- 关键修正：...

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
git push
```

远程仓库：`https://gitlabee.chehejia.com/huyongqiang/palantir-research.git`

## 文档写作规范

- 调研结论写入 `docs/raw/` 或 `docs/synthesis/`
- 架构图用 draw.io 制作，同时导出 PNG，两个文件一起提交
- 规格/方案文档命名：`docs/superpowers/specs/YYYY-MM-DD-<主题>.md`
