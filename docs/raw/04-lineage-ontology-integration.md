# Palantir 数据血缘与 Ontology 集成调研

**调研日期：** 2026-04-16  
**调研方向：** 数据血缘 / Dataset 版本管理 / Ontology-Pipeline 集成 / 数据治理

---

## 核心发现

### 1. 数据血缘（Data Lineage）实现机制

**架构核心：Foundry Automation dependencies（平台级依赖管理）**

Foundry 使用平台级依赖管理机制，所有 Transform 的 Input/Output 声明在 Build 时自动注册，形成全平台统一的血缘图。（注："FDS/Foundry Dependency Services"为非官方术语，官方文档使用 "Automation dependencies"）

**血缘捕获方式：**
- **静态分析**（编译时）：解析 `@transform_df(Output(...), source=Input(...))` 装饰器，推导数据集级别（Dataset-level）血缘
- **运行时记录**：每次 Build 记录实际执行的输入输出版本（Transaction ID 级别），支持时间点血缘查询

**可视化工具：Data Lineage App**
- 交互式 DAG 视图：可从任意数据集出发，向上追溯数据来源，向下查看影响范围
- 支持跨 Code Repository 的血缘穿透（FDS 统一管理）
- 支持从血缘图直接触发 Build（影响分析后立即重算下游）

**列级血缘（Column-level Lineage）：**
- 基础支持：通过 Pipeline Builder 的 SQL 表达式可部分推导列级血缘
- 局限：手写 PySpark 代码中的列级血缘无法自动捕获（与业界 Atlas/OpenLineage 同样面临的挑战）

**与 OpenLineage 的兼容性：**
- Foundry 使用私有血缘模型，**未原生集成 OpenLineage 标准**
- 社区层面无官方适配，通过自定义 Export 可能实现互通
- 这是与开源生态（Databricks Unity Catalog、Apache Atlas）的主要差距之一

---

### 2. Dataset 版本管理

**核心概念：Transaction-based 版本控制**

Foundry Dataset 的版本管理与 Git 设计理念类似，但面向数据文件：

```
Dataset
  └── Branch（主分支 master + 开发分支）
        └── Transaction（每次写入 = 一个事务）
              └── Files（Parquet 文件集合）
```

**Transaction 类型回顾：**
- `APPEND`：追加新文件（最轻量，增量友好）
- `UPDATE`：覆写已有数据
- `SNAPSHOT`：全量替换（最重，清空旧文件）

**不可变性保证：**
- 每个 Transaction 写入后**不可修改**（Immutable），确保并发读安全
- 下游 Transform 读取时锁定特定 Transaction 版本，不受上游并发写入影响

**Branch（分支）机制：**
- 用于实验性开发：在独立 Branch 上运行 Pipeline，不影响 master 分支
- 多用户可并发写入不同 Branch
- **关键限制**：数据集 Branch **不支持 Merge**（不同于 Git）！代码 Repo 支持 Merge，但数据集不行
- 变通方案：通过 Transform 将 source branch 的数据读出，写入 target branch

**时间旅行（Time Travel）：**
- 支持查询数据集在特定 Transaction 时的状态（类似 Delta Lake `AS OF`）
- 主要用于调试（"上次 Build 前数据是什么样的"）和审计

**与 Delta Lake / Iceberg 对比：**
| 维度 | Foundry Dataset | Delta Lake | Apache Iceberg |
|---|---|---|---|
| 版本控制 | Transaction-based | 基于 Delta Log | 基于 Manifest |
| 时间旅行 | 支持 | 支持（`VERSION AS OF`） | 支持 |
| Branch/Merge | Branch 支持，Merge 不支持 | 有限支持（DeltaSharing） | 不原生支持 |
| ACID 事务 | 支持 | 支持 | 支持 |
| 开放格式 | 专有（Parquet + Foundry 元数据） | 开放（Delta Log） | 开放标准 |
| 跨引擎读取 | 仅 Foundry 内部 | 任意 Spark/Flink/Trino | 任意引擎 |

---

### 3. Ontology-Pipeline 深度集成

**Pipeline 输出到 Ontology 的两种路径：**

**路径 A：Dataset → Ontology Object Type Sync（推荐）**
```
Pipeline Transform 输出 Dataset
    │
    ▼ [Ontology 配置：绑定 Object Type 到 Dataset]
Ontology Object Type（逻辑实体层）
    │  - 每列映射到 Object Property
    │  - Dataset 更新 → Object 自动刷新
    ▼
Workshop / Slate 应用 / AIP Logic
```

**路径 B：Actions Writeback（双向同步）**
```
用户在应用中修改 Object Property
    │
    ▼ [Ontology Action 触发]
Writeback Dataset（记录变更）
    │
    ▼ [Pipeline Build（调度或手动触发）]
原始数据集更新 / 外部系统写回
```

**Object Type 与数据集的绑定：**
- 在 Ontology Manager 中配置：指定哪个 Dataset 的哪些列映射到 Object Type 的哪些 Properties
- 支持计算属性（Derived Properties）：通过公式从多个列计算得出
- Link Type（关系）：通过外键列定义两个 Object Type 之间的关联

**Writeback Dataset 的局限：**
- Writeback Dataset 不是实时自动更新的，需要显式触发 Build 或配置调度
- 每次 Action 写入的变更记录在 Writeback Dataset 中，需通过 Pipeline 处理后才写回原始系统
- 这意味着 Ontology 的"写回"存在**分钟级延迟**，而非实时

**向量化支持（RAG/AIP 场景）：**
- Object Properties 可以被向量化（Embedding），存储在 Foundry 的向量索引中
- AIP Logic 利用向量检索进行语义相似度计算
- 向量更新同样依赖 Pipeline Build 触发，非实时

---

### 4. 数据治理机制

**列级权限控制（Column Masking）：**
- 支持对特定用户/角色屏蔽或脱敏列数据（如 PII 字段）
- Masking 在 Foundry 数据访问层执行，对下游 Transform 和应用透明

**数据分类标记：**
- 支持在 Dataset 和 Object Property 级别打标签（如 `PII`, `CONFIDENTIAL`）
- 标签驱动自动权限策略（如带 PII 标签的列自动要求特定审批才能访问）

**审计日志：**
- 记录每次数据集读写操作（谁、何时、读/写了哪个 Transaction）
- 支持合规性审计（GDPR、HIPAA 场景）

**与业界对比：**
| 维度 | Foundry | Apache Atlas | Databricks Unity Catalog |
|---|---|---|---|
| 血缘模型 | 私有（Dataset-level 自动，Column 部分支持） | 开放（OpenMetadata 兼容） | 开放（支持 OpenLineage） |
| 列级权限 | 支持（Column Masking） | 依赖 Ranger | 支持（Delta Sharing） |
| 数据分类 | 支持（标签系统） | 支持 | 支持 |
| 跨平台集成 | 弱（私有 API） | 强（开放 API） | 强（Unity Catalog 开放）|
| 实时性 | Ontology 分钟级同步 | 近实时 | 近实时 |

---

## 关键结论

1. **FDS 是血缘的基础设施**：Foundry Dependency Services 统一管理跨 Repository 的 Dataset 依赖，这是全平台血缘图能实现的技术前提
2. **Dataset Branch 不支持 Merge 是重要限制**：与 Git 类比易产生误解，数据集分支只能读出再写入，不能直接合并，影响多团队协作场景的工作流设计
3. **Ontology 同步存在分钟级延迟**：Writeback 路径依赖 Build 触发，Pipeline→Ontology 同步不是实时的，这是"数字孪生"的现实约束
4. **OpenLineage 不兼容是开放性短板**：Foundry 使用私有血缘模型，无法与 Databricks、dbt、Airflow 等主流工具的血缘互通，在多平台企业中存在孤岛风险
5. **数据治理能力完整但封闭**：Column Masking、数据分类、审计日志均内置且完善，但所有能力仅在 Foundry 生态内有效，难以延伸到外部系统

---

## 待深挖问题

- Foundry Dataset 的物理存储格式（纯 Parquet？还是有额外的 Foundry 元数据层？）
- OpenLineage Adapter 是否在 Palantir 路线图中
- Ontology Object Type 删除/重命名时，依赖的 Pipeline 如何感知和处理
- 列级血缘在 Pipeline Builder（SQL 路径）的实现深度

---

## 参考来源

- Palantir Foundry 文档：Data Lineage App、Dataset Transactions、Ontology Actions
- 社区调研：Foundry dataset branch merge、writeback dataset
- 技术对比：Delta Lake vs Foundry Dataset versioning
- 开放标准：OpenLineage 规范
