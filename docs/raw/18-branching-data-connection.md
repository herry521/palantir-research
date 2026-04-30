# Palantir Foundry Data Connection 分支支持调研

**日期：** 2026-04-29  
**文件编号：** 18  
**主题：** Data Connection Sync 任务与产出 Dataset / Stream 的分支能力

---

## 一、核心结论

Data Connection 的"分支"是**配置层面的分支**（用于安全上线新 Sync 配置），不是**数据产出层面的分支**。数据始终流入 master branch，下游的分支隔离和测试能力由 Pipeline Transform 层承接。Stream 支持分支但受"每 branch 单 stream"约束。

---

## 二、三个维度分析

### 2.1 Sync 任务自身：配置可分支，产出数据默认写 master

Sync 任务（源配置 + 同步规则）支持**配置分支**——可以在非 master 分支上创建沙箱版本的 Sync 配置，用于开发和测试，而不影响生产环境正在运行的 Sync。

但**数据产出目标**（写入哪个 dataset branch）并不像 Pipeline Transform 那样自由切换：
- Sync 写入的 dataset 默认始终是 **master 分支**
- 没有官方记录表明可以把 Sync Job 的产出直接指向一个 feature branch

原因在设计上合理：Sync 是持续运行的生产任务，面向外部真实数据源，"写入 feature branch 测试"的场景天然不适合——不可能让生产外部系统只向测试分支推数据。

> **证据：** "Data Connection allows for full branching of new configurations, where the new sync is sandboxed and tested in a branch before it affects any downstream transformation jobs."  
> 这里"分支"指的是 **Sync 配置本身**的分支，而非产出 dataset 的分支。

### 2.2 产出 Dataset：Dataset 本身支持多分支，但 Sync 只写 master

Dataset 作为 Foundry 核心数据对象，完整支持分支：

```
Dataset (RID)
├── master branch   ← Sync Job 写入此处（生产数据持续流入）
├── feature/dev-A   ← Pipeline Transform 可在此 branch 运行
└── feature/dev-B   ← Pipeline Transform 可在此 branch 运行
```

**分支语义（数据层面）**：每个 dataset branch 是一个独立的事务指针，互不干扰，类似 Git branch，但**数据层面不支持 merge**——无法将 feature branch 上的数据事务直接 merge 回 master。

> **注意**：Foundry 的 Global Branching 机制支持在 **Logic/配置层面**（Transform 代码、Sync 配置、Ontology 对象等）提交 proposal 并 merge 回 Main，这是代码/配置的 merge，与 dataset 数据 merge 是不同概念（见第六节）。

典型开发模式：
1. Sync → master（生产数据持续流入）
2. 开发者在 feature branch 上运行 Transform，**读取 master 上的数据**，产出写入 feature branch
3. feature branch 的 Transform 逻辑 review 通过后，合并 Code Repo 到 master 再执行

### 2.3 产出 Stream：支持分支，但每个 branch 只能有一个 active stream

Stream（流式 dataset）的分支支持有特殊约束：

| 规则 | 说明 |
|---|---|
| 每个 branch 最多一个 active stream | 同一 dataset 同一 branch 上不能同时跑两个 stream |
| 创建 stream 时可指定 branch | 默认写 master，可显式指定其他 branch |
| 无 stream merge | 与 dataset 一样，stream branch 之间无法 merge |
| Streaming Sync 写 master | Data Connection 的 streaming sync 产出同样默认走 master branch |

> **证据：** "Each branch of a streaming dataset can have only one active stream. When creating a streaming dataset, you can specify a branch for the initial stream, or it will default to the 'master' branch if none is specified."

---

## 三、整体结构图

```
Data Connection
├── Sync 配置        → ✅ 支持配置分支（沙箱测试新配置）
│
└── 产出 Dataset
    ├── master branch ← Sync Job 实际写入目标（固定，不可切换）
    │   └── 持续接收外部数据（APPEND / SNAPSHOT 事务）
    │
    ├── feature branch A
    │   └── Transform 可在此读 master 数据、产出写此处
    │   └── 不受 Sync 直接写入
    │
    └── 产出 Stream（如有）
        ├── master branch ← Streaming Sync 默认写入
        │   └── 限制：只能有 1 个 active stream
        └── 其他 branch（可手动创建，同样限 1 个 active stream）
```

---

## 四、与 Pipeline Transform 分支能力对比

| 能力 | Data Connection Sync | Pipeline Transform |
|---|---|---|
| **配置可分支** | ✅（Sync 配置沙箱） | ✅（Code Repo / Pipeline Builder） |
| **产出写指定 branch** | ❌（只写 master） | ✅（可在任意 branch 上 build） |
| **分支数据互不干扰** | N/A（只写 master） | ✅（每个 branch 独立数据视图） |
| **Stream 分支** | 受限（每 branch 仅 1 active stream） | 受限（同上） |

---

## 六、Global Branching：Foundry 分支能力的统一体系

Data Connection 的配置分支能力是 Foundry **Global Branching** 体系的组成部分，而非孤立功能。

### 6.1 Global Branching 覆盖范围

Global Branching 提供跨应用的统一分支体验，在一个 branch 上可同时管理：
- **Pipeline Builder / Code Repo** — Transform 逻辑分支
- **Data Connection** — Sync 配置分支（源、调度、字段映射等）
- **Ontology** — 对象类型、Link 类型的定义变更
- **Workshop** — 应用界面变更

这意味着一个 branch 可以承载完整的端到端变更（从 Sync 配置到 Transform 逻辑到 Ontology 对象），在不影响生产环境的前提下整体测试。

### 6.2 Proposal → Merge 流程（Logic 层面）

```
feature branch（端到端开发测试）
        ↓
   创建 Proposal
        ↓
   Review + Approval
        ↓
   一键 Merge 回 Main（配置/代码层面）
```

> **[事实]** Pipeline Builder 在 merge 时有 conflict 检测和解决流程。
>
> **重要区分**：这里的 merge 是 **Logic/配置 merge**（类似 Git PR），不是 dataset 数据内容的 merge。dataset 数据层面仍不支持 merge。

### 6.3 对本文核心结论的影响

| 结论 | 是否受影响 | 说明 |
|---|---|---|
| Sync 配置支持分支 | 是 | Data Connection 配置分支是 Global Branching 体系一部分，不是独立功能 |
| Sync 产出只写 master | 否 | Global Branching 管理的是 **配置**，运行中的 Sync Job 数据产出目标仍为 master |
| Dataset 分支不支持 merge | 需区分 | 数据层面确实不支持；配置/代码层面通过 Global Branching proposal 可 merge |
| Stream 约束 | 否 | 不受影响 |

---

## 七、证据可信度说明

| 结论 | 来源 | 可信度 |
|---|---|---|
| Sync 配置支持分支（沙箱模式）| Palantir 官方文档转述 | 高 |
| Sync 产出只写 master | 官方文档转述 + 设计逻辑推导 | 中（无直接官方明确限制声明） |
| Dataset 支持多分支但不可 merge | Palantir 官方文档转述 | 高 |
| Stream 每 branch 限 1 active stream | Palantir 官方文档转述 | 高 |
| Streaming Sync 默认写 master | 设计逻辑推断，与 batch sync 行为一致 | 中（推断）|
| Data Connection 分支是 Global Branching 体系一部分 | 多来源搜索结果综合 | 高 |
| Global Branching 支持配置/代码层面 merge，不包含数据 merge | 搜索结果 + 官方 Pipeline Builder 文档描述 | 高 |
