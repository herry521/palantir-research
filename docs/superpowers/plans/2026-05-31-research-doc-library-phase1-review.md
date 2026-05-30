# Research Doc Library Phase 1 Integration Review

**日期：** 2026-05-31
**关联 Issue：** #48
**父 Epic：** #42
**评审范围：** `docs/index.md`、`docs/catalog.yml`、`docs/topics/*.md`、`scripts/verify-doc-library.sh`

## 摘要与决策洞察

1. 【结论】Phase 1 集成评审最终通过；`index -> topic -> canonical/source_refs -> raw/synthesis` 的阅读与追踪链路已经成立。
2. 【事实】#44、#45、#46、#47 均已完成并标记 `status:done`；#48 完成本评审记录后可关闭，#42 应继续保持 open 以承接 Phase 2。
3. 【事实】从 Data Quality 交付提交 `e239836` 到当前 Phase 1 末尾，没有移动或重命名 `docs/raw` 与 `docs/synthesis` 文件。
4. 【修正】第一轮元数据评审发现 3 个 blocker；已通过强化 catalog coverage、修正 canonical 标记、清理 topic canonical 区块完成第二轮复审。
5. 【建议】Phase 2 可以启动，但必须 additive-only：新增 `docs/library` 阅读层，继续禁止移动/重命名 `docs/raw` 与 `docs/synthesis`。

## 交付物状态

| Issue | 交付物 | 评审状态 |
| --- | --- | --- |
| #44 | `docs/index.md` 全局入口与阅读路径 | 通过 |
| #45 | `docs/catalog.yml` 元数据初版 | 通过 |
| #46 | `docs/topics/*.md` 首批 10 个主题索引 | 通过 |
| #47 | `scripts/verify-doc-library.sh` 本地引用与路径校验 | 通过 |
| #48 | Phase 1 集成评审与专家复核 | 本文记录通过结论 |

## 专家组评审

| 评审角色 | 第一轮 Verdict | 关键意见 | 处理结果 | 第二轮 Verdict |
| --- | --- | --- | --- | --- |
| 信息架构评审 | PASS | `docs/index.md` 覆盖 10 个 topic；topic 页都有摘要、canonical、evidence、issues、open questions；未复制 raw 长正文。 | 无阻断项。 | PASS |
| 元数据与可追溯性评审 | FAIL | 校验脚本未强制 index/topics/catalog 入 catalog；`docs/index.md` 被误标 `canonical: true`；`lineage-and-catalog` topic 的 canonical 区块混入 raw/catalog/index。 | 强化脚本 coverage 与 uncataloged-ref 检查；新增 `docs-catalog` entry；`docs-index` 改为 `canonical: false`；清理 topic canonical 区块；Ontology spec 标为 canonical baseline。 | PASS |
| 迁移约束与 Phase 2 准备评审 | PASS | Phase 1 未移动/重命名 raw/synthesis；交付物覆盖设计验收；本地验证通过；可进入 Phase 2。 | 无阻断项。 | PASS |

## Accepted Findings

- `docs/index.md` 能作为人类入口，指向全部 10 个首批 topic 页。
- `docs/catalog.yml` 已覆盖 raw、synthesis、superpowers、index、topics 和 catalog 自身，并记录 topic 的 `source_refs`、`related_docs` 与 issue 关系。
- `scripts/verify-doc-library.sh` 已覆盖 YAML 解析、路径存在、tracked docs catalog coverage、local refs catalog coverage、index/topic Markdown links 和 missing-path self-test。
- `docs/raw` 与 `docs/synthesis` 在 Phase 1 中保持稳定引用坐标，没有发生迁移。

## Rejected Or Non-Blocking Items

- Ontology 暂无专属 synthesis 不阻塞 Phase 1；当前以 Ontology 数据模型 spec 作为 canonical baseline，并在 topic 页保留开放问题。
- `docs/library/` 尚未创建不阻塞 Phase 1；它属于 Phase 2 阅读层建设范围。
- 不建议在 Phase 2 前物理重组 `docs/raw` 或 `docs/synthesis`，否则会破坏当前稳定引用坐标。

## Remaining Risks

- 当前校验脚本仍是结构校验，不能判断 `source_refs` 的语义充分性。
- Markdown link parser 使用轻量正则，对复杂 Markdown 语法覆盖有限。
- Topic 页的 canonical 区块与 catalog `canonical: true` 的语义一致性仍主要依赖评审流程，而非自动语义检查。
- Phase 2 章节质量需要单独验收：每章应包含 3 到 5 条摘要/洞察、明确读者问题、证据链接和状态信息。

## Verification Evidence

已在本地执行并通过：

- `bash scripts/verify-doc-library.sh`
- `bash scripts/verify-doc-library.sh --self-test`
- `git diff --check -- docs/catalog.yml docs/topics scripts/verify-doc-library.sh`
- `git diff --name-status e239836..HEAD -- docs/raw docs/synthesis` 无输出，确认 Phase 1 未触碰 raw/synthesis 路径。

## Phase 2 Recommendation

GO。建议下一轮开启 Phase 2 `docs/library` 阅读层建设，最小范围为：

1. 新增 `docs/library/README.md` 作为阅读层入口。
2. 新增 `docs/library/00-executive-summary.md` 作为跨主题执行摘要。
3. 首批章节优先覆盖 Dataset、Pipeline、Security and Marking、Data Quality、AI FDE、Self-build Roadmap。
4. 所有章节只做导读、综合和引用，不复制 raw 正文，不移动 raw/synthesis 文件。
