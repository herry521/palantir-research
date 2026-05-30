# 调研文档库体系化组织设计

日期：2026-05-31  
关联 Issue：#42 Epic: 调研文档库体系化重组  
状态：专家组条件通过，等待用户确认后进入实施计划

## 摘要与洞察

1. 采用混合式文档库架构：保留 `raw` 证据层和 `synthesis` 结论层，再新增 `library` 阅读层、`topics` 主题索引层与 `catalog.yml` 元数据层。
2. 不把“图书目录”当作物理存储结构；它只适合承载读者路径和叙事顺序，底层研究证据仍应按来源、主题和版本稳定保存。
3. 第一阶段优先做目录、索引、元数据和可追溯关系，不批量搬迁或重命名既有文档，避免破坏引用坐标和 Git 历史。
4. 主组织轴应围绕自研平台能力域展开；Foundry 产品模块、数据生命周期、平台层级只作为交叉索引维度。
5. 当前未跟踪的 Data Quality 调研文件应保持在 intake/draft 状态；在其提交、评审和归档前，不应被纳入 canonical 结论层。

## 背景

本仓库已经形成多批 Palantir Foundry 调研材料，包括 Dataset、Pipeline、Pro-Code、AI FDE、调度、权限、无 `dt` 分区差异等主题。随着材料增长，当前目录暴露出三个问题：

- 入口缺失：仓库没有统一的 `docs/index.md` 或总目录，读者难以判断从哪里开始阅读。
- 层次混合：原始证据、研究计划、阶段结论、最终分析文档分散在 `docs/raw`、`docs/synthesis`、`docs/superpowers` 中，但缺少显式关系。
- 引用脆弱：如果直接按“图书章节”搬动文件，会破坏现有 issue、commit、交叉链接和审阅上下文。

截至本设计形成时，本地文档结构观察如下：

| 区域 | 观察 |
| --- | --- |
| `docs/raw` | 约 51 个 Markdown 文件，包含已提交研究证据，也包含未跟踪的 Data Quality 草稿文件；存在编号重复和主题跨度较大的情况。 |
| `docs/synthesis` | 约 10 个 Markdown 文件，承载多数可复用研究结论。 |
| `docs/superpowers` | 约 10 个计划或规格文档，记录任务拆解、执行计划和设计过程。 |
| 全局入口 | 暂无统一文档库首页、主题索引、catalog 元数据或 canonical 映射。 |

## 专家组评估结论

| 视角 | 结论 | 对设计的约束 |
| --- | --- | --- |
| 信息架构专家 | 推荐“证据层 + 结论层 + 阅读层 + 索引层”的多视图结构。 | 不能用单一树形目录表达所有关系，需要支持多轴检索。 |
| 研究编辑专家 | 图书式组织适合最终叙事，不适合承载证据原文。 | `library` 负责讲述和导读，不复制或替代 `raw` 与 `synthesis`。 |
| 数据平台领域专家 | 组织轴应服务自研平台决策，而不是复刻 Foundry 产品菜单。 | 一级主题使用能力域，产品模块和生命周期作为标签。 |
| 维护与 Git 专家 | 大规模搬迁会增加审阅成本，并削弱历史可追溯性。 | 第一阶段只增量添加入口、索引和 catalog，不搬迁核心文件。 |

专家组一致建议采用混合式方案，并设置两个前置条件：

- 任何结构调整必须保持原始证据坐标稳定。
- 任何新结论都必须能追溯到 synthesis、raw、issue 和来源材料。

## 被否决或降级的方案

### 方案 A：纯图书式物理重组

将所有文档迁移到类似 `book/chapter/section` 的目录下，形成一本完整“书”。

否决原因：

- 证据文档天然多归属，一个 raw 文件可能同时支持 Dataset、权限、调度和治理多个主题。
- 章节迁移会造成链接断裂、Git diff 噪音和历史引用失效。
- 后续主题增加时容易频繁调整章节结构，形成持续的维护成本。

### 方案 B：只做标签与 catalog

完全不新增阅读层，只用 `catalog.yml` 和主题标签描述关系。

降级原因：

- 对维护者友好，但对新读者不友好。
- 无法形成“从问题到结论到证据”的阅读路径。
- 可以作为第一阶段基础设施，但不能替代最终的体系化文档库。

### 方案 C：混合式文档库

保留原有证据和结论路径，新增阅读层、主题索引和元数据 catalog。

评估结果：推荐采用。

## 目标结构

```text
docs/
  index.md
  catalog.yml
  raw/
  synthesis/
  library/
  topics/
  planning/
    active/
    archive/
  archive/
```

### `docs/index.md`

全局入口，回答三个问题：

- 当前文档库有哪些核心主题。
- 新读者应该按什么路径阅读。
- 重要结论、证据、计划和 issue 分别在哪里。

### `docs/catalog.yml`

机器可读的文档目录，维护每个文档的身份、状态、主题、来源层级和引用关系。它是后续自动生成索引、做链接检查、发现过期文档和映射 canonical 结论的基础。

### `docs/raw`

证据层。保留现有文件路径和编号作为引用坐标，不在第一阶段搬迁或批量重命名。

职责：

- 保存来源摘要、产品机制观察、公开材料摘录和原始分析记录。
- 为 `synthesis` 和 `library` 提供证据链接。
- 允许同一 raw 文件服务多个主题。

约束：

- 不在 raw 内引入叙事性章节组织。
- 不把 raw 文档复制到 library。
- 不删除重复编号文件，除非已有 canonical、supersedes 和 alias 映射。

### `docs/synthesis`

结论层。保存经过整理、可复用、可引用的主题分析。

职责：

- 承载研究结论、差异分析、架构判断和自研启示。
- 每篇文档必须包含 3 到 5 条摘要或洞察。
- 每篇重要结论必须指向关键 raw 证据、相关 issue 和后续任务。

### `docs/library`

阅读层。它是“像书一样读”的入口，但不是底层存储。

建议骨架：

```text
docs/library/
  README.md
  00-executive-summary.md
  01-foundry-mental-model/
  02-data-engineering-core/
  03-governance-and-operations/
  04-ai-fde/
  05-self-build-roadmap/
  appendices/
```

定位：

- 给读者提供从背景、机制、差异、设计启示到自研路线的连续阅读路径。
- 引用 `synthesis` 与 `raw`，不复制原文。
- 每个章节可以是导读、整合摘要或专题路线图。

章节契约：

- 3 到 5 条摘要或洞察。
- 读者意图：这章回答什么决策问题。
- 前置知识：阅读前需要理解哪些概念。
- 正文叙事：按问题链组织，而不是按文件编号堆叠。
- 关键结论：标注事实、推断和仍需验证的判断。
- 证据链接：指向 synthesis、raw、issue、外部来源。
- 状态信息：草稿、评审中、canonical、已过期。
- 最后审阅日期与未决问题。

### `docs/topics`

主题索引层。每个主题页不承载长篇正文，而是聚合：

- 本主题的 3 到 5 条当前结论。
- canonical synthesis 文档。
- 支撑 raw 证据。
- 相关 issue、计划和评审记录。
- 开放问题、风险和下一步调研任务。

建议初始主题：

```text
docs/topics/
  dataset.md
  pipeline.md
  scheduling.md
  lineage-and-catalog.md
  security-and-marking.md
  ontology.md
  data-quality.md
  pro-code.md
  ai-fde.md
  self-build-roadmap.md
```

### `docs/planning`

规划层。用于承接当前 `docs/superpowers/plans` 中的研究计划、执行拆解和归档记录。

本阶段只定义目标结构，不立即迁移。待 catalog 稳定后，再判断是否将 `docs/superpowers/plans` 迁入 `docs/planning/active` 与 `docs/planning/archive`。

### `docs/archive`

归档层。只存放明确失效、被替代、或保留历史意义的材料。任何归档都必须在 catalog 中保留 `superseded_by` 或说明原因。

## 能力域组织轴

文档库不应按 Foundry 产品菜单机械分区，而应按自研平台能力域建立主轴：

| 能力域 | 典型问题 |
| --- | --- |
| 数据接入与连接 | 如何连接外部系统、管理凭证、处理增量读取和源端变更。 |
| Dataset、存储、事务与视图 | Dataset 与传统表、分区、事务、快照、视图之间的差异。 |
| Pipeline 表达与转换 | 低代码、SQL、Python、Transform API、DAG 和算子模型如何组合。 |
| 执行与运行时 | Spark、Faster、容器、资源隔离、失败恢复和成本模型。 |
| 增量、流批与时间语义 | 无 `dt` 分区、增量构建、流处理、时间线和回溯能力。 |
| 调度与编排 | Schedule、触发器、依赖、数据变化驱动和运行保障。 |
| 血缘、目录与元数据 | Catalog、lineage、schema、branch、version 和可发现性。 |
| Ontology | 对象模型、关系、动作、权限和业务语义层。 |
| 安全与 Marking | 数据权限、标记传播、策略执行和审计。 |
| 测试、数据质量与可观测性 | Expectations、健康检查、监控视图、告警、问题闭环。 |
| Pro-Code 与开发体验 | 代码仓库、CI/CD、环境、SDK、协作和工程治理。 |
| AI FDE | AI 驱动开发、上下文、工具、技能和治理边界。 |
| 治理与运营 | 生命周期、审计、平台运营、迁移风险和组织流程。 |

交叉索引维度：

- Foundry 产品模块：Dataset、Pipeline Builder、Code Repositories、Ontology、AIP、Workshop、Quiver 等。
- 数据生命周期：接入、建模、转换、质量、服务、治理、运营。
- 平台层级：存储、计算、元数据、语义、安全、开发体验、运营。
- 研究成熟度：raw、draft synthesis、reviewed synthesis、canonical、superseded。

## 元数据契约

`docs/catalog.yml` 建议以文档为基本单元，字段如下：

```yaml
- id: dataset-no-dt-impact
  title: Palantir Dataset 无 dt 分区形态的深层影响
  type: synthesis
  status: canonical
  topics:
    - dataset
    - incremental
    - self-build-roadmap
  source_layer: synthesis
  issue_refs:
    - 28
    - 34
  source_refs:
    - docs/raw/39-foundry-dataset-transaction-view-evidence.md
    - docs/raw/40-traditional-dt-partition-production-semantics.md
  related_docs:
    - docs/synthesis/palantir-dataset-vs-data-warehouse.md
  canonical: true
  supersedes: []
  superseded_by: null
  created: 2026-05-30
  updated: 2026-05-30
  last_reviewed: 2026-05-30
  confidence: medium
  evidence_strength: medium
  owner: codex
  reviewers:
    - expert-panel
```

字段说明：

| 字段 | 说明 |
| --- | --- |
| `id` | 稳定文档标识，不随标题变化。 |
| `title` | 中文标题。 |
| `type` | `raw`、`synthesis`、`library`、`topic`、`plan`、`spec`、`archive`。 |
| `status` | `intake`、`draft`、`reviewed`、`canonical`、`superseded`、`archived`。 |
| `topics` | 能力域主题标签。 |
| `source_layer` | 所在层级。 |
| `issue_refs` | 关联 GitLab issue 编号。 |
| `source_refs` | 关键证据或上游材料。 |
| `related_docs` | 平行或补充文档。 |
| `canonical` | 是否作为当前推荐引用结论。 |
| `supersedes` | 本文替代了哪些旧文档。 |
| `superseded_by` | 本文被哪个新文档替代。 |
| `created`、`updated`、`last_reviewed` | 创建、更新、审阅日期。 |
| `confidence` | `low`、`medium`、`high`。 |
| `evidence_strength` | `weak`、`medium`、`strong`。 |
| `owner`、`reviewers` | 维护人与审阅者。 |

## 迁移阶段

### Phase 0：冻结引用坐标

目标：确认第一阶段不搬迁 `docs/raw` 和 `docs/synthesis`。

动作：

- 记录当前目录结构和未跟踪草稿状态。
- 明确 Data Quality 未跟踪文件暂不纳入 canonical。
- 将本设计作为 issue #42 的评审基线。

### Phase 1：索引与元数据

目标：建立可导航、可追溯、可维护的文档库基础设施。

动作：

- 新增 `docs/index.md`。
- 新增 `docs/catalog.yml`，先覆盖已跟踪文档，再处理未跟踪草稿。
- 新增首批 `docs/topics/*.md`。
- 为主题页和重要 synthesis 文档补齐 issue、证据、状态和 3 到 5 条洞察。
- 增加轻量链接检查约定。

验收：

- 不移动 `raw` 和 `synthesis` 中的既有文件。
- 已跟踪核心文档在 catalog 中可检索。
- 每个主题页能指向 canonical synthesis 和关键 raw 证据。

### Phase 2：阅读层建设

目标：建立面向读者的“书式”阅读路径。

动作：

- 新增 `docs/library/README.md`。
- 新增 `00-executive-summary.md`。
- 选择 Dataset、Pipeline、Security、AI FDE、自研路线作为首批章节。
- 每章只做导读、整合和引用，不复制 raw 原文。

验收：

- 新读者能从 `docs/index.md` 进入 `library`，再跳转到 synthesis 和 raw。
- library 章节均满足章节契约。

### Phase 3：规划层清理

目标：处理计划文档和执行记录的长期存放位置。

动作：

- 评估 `docs/superpowers/plans` 是否迁入 `docs/planning/active` 与 `docs/planning/archive`。
- 若迁移，必须提交 alias map，并更新 catalog 与引用链接。
- 保留必要的历史上下文，不删除已被 issue 引用的计划文件。

验收：

- planning 文档有明确 active/archive 状态。
- 迁移后的路径能通过 catalog 找回。

### Phase 4：受控迁移与归档

目标：只在收益明确时做有限搬迁。

动作：

- 对重复编号、过期草稿、被替代结论进行逐项评估。
- 对每次迁移维护 `supersedes`、`superseded_by` 和 alias。
- 执行链接检查后再提交。

验收：

- 无断链。
- 无证据丢失。
- 每次迁移都有 issue 记录和 commit 说明。

## 禁止动作

- 禁止在第一阶段批量移动 `docs/raw` 或 `docs/synthesis`。
- 禁止批量重命名 raw 文件编号。
- 禁止将 raw 原文复制进 library 章节。
- 禁止将未跟踪或未评审的 Data Quality 文件直接标记为 canonical。
- 禁止把“图书目录”作为唯一文档存储结构。
- 禁止删除重复或过期文档，除非已有 catalog 映射、替代说明和链接检查结果。
- 禁止只在聊天中给出重要结论而不落库。

## 验收标准

| 标准 | 说明 |
| --- | --- |
| 结构稳定 | Phase 1 不搬动 `raw` 与 `synthesis` 既有文件。 |
| 可导航 | `docs/index.md` 能解释文档库结构、阅读路径和主要主题。 |
| 可追溯 | `catalog.yml` 能连接文档、主题、issue、证据和 canonical 状态。 |
| 可读 | `library` 章节有 3 到 5 条摘要或洞察，并服务明确读者问题。 |
| 可维护 | 每个 topic 页有状态、关键结论、证据链接和开放问题。 |
| 可验证 | 提交前执行 Markdown 基础检查、链接检查或至少路径引用检查。 |

## 需用户确认的问题

1. 阅读层目录命名采用 `docs/library` 还是 `docs/book`。建议采用 `docs/library`，因为它比 `book` 更能表达多视图和可演进结构。
2. 第一阶段是否只维护外部 `catalog.yml`，暂不批量修改既有文档 frontmatter。建议先外部 catalog，等 schema 稳定后再补 frontmatter。
3. `docs/superpowers/plans` 是否在 Phase 3 迁移到 `docs/planning`。建议暂不迁移，等索引和 alias 机制建立后再处理。

## 下一步建议

如本设计通过用户确认，后续应将 issue #42 拆解为以下执行任务：

1. 创建 `docs/index.md` 与 `docs/catalog.yml` 初版。
2. 创建首批 `docs/topics` 主题索引。
3. 建立 `docs/library` 阅读层骨架和首篇 executive summary。
4. 补齐核心 synthesis 文档的 catalog 关系和 canonical 状态。
5. 建立链接检查或路径引用检查脚本。
