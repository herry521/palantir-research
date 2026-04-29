# Palantir Foundry Faster 引擎深度调研

**日期：** 2026-04-29  
**文件编号：** 17  
**主题：** Faster Engine 能力边界与实现方案

---

## 一、背景与定位

Faster 引擎是 Palantir Foundry Pipeline Builder 中的一种**轻量级计算后端**，前身称为 "Lightweight Pipeline"（轻量级 Pipeline）。2024 年 Palantir 将其更名为 "Faster Pipelines"，名称本身即点明其核心价值：**更快的执行速度 + 更低的计算资源消耗**。

> **证据：** Palantir 官方搜索结果描述："Palantir's 'Faster' pipelines, previously known as lightweight pipelines, with the name change reflecting their ability to reduce both execution time and compute resource usage, even for large datasets."

Faster 引擎并非替代 Spark，而是与 Spark **并存**的补充引擎，面向中小规模数据 + 低延迟场景。

---

## 二、核心产品能力

### 2.1 适用 Pipeline 类型

| Pipeline 类型 | Faster 引擎支持 | 说明 |
|---|---|---|
| Batch（快照） | ✅ 支持 | 全量重算，每次执行替换输出 |
| Incremental（增量） | ✅ 支持（有限制） | 仅处理新增事务，见 §4.2 |
| Streaming（流式） | ❌ 不支持 | 流式仍需 Spark/Flink |

### 2.2 性能定位

- **最佳场景**：单次执行时长 **< 15 分钟** 的 Pipeline
- **适用规模**：中小型数据集（Small to medium-sized datasets）
- **加速效果**：相较传统 Spark Pipeline 有显著提速（官方描述 "substantially accelerate"）

> **证据：** "Pipelines that run in under 15 minutes will see the most benefit from faster pipeline configurations."  
> 来源：多个第三方对 Palantir 文档的转述

### 2.3 资源配置

- 可配置分配给单个 Faster Pipeline 的 **CPU 和内存**资源
- 单节点运行（无分布式集群开销），可根据数据量灵活调整

### 2.4 混合 Pipeline

同一 Pipeline 中可以混用 **Faster 引擎节点 + Spark 节点**，即在不支持 Faster 的变换步骤上回退到 Spark，保持整体 Pipeline 的完整性。

---

## 三、技术架构

### 3.1 底层引擎：Apache DataFusion

Faster 引擎的核心是 **Apache DataFusion**，一个基于 Rust 实现的开源查询引擎。

| 特性 | 说明 |
|---|---|
| 语言 | Rust（内存安全，无 GC 停顿） |
| 数据格式 | Apache Arrow（列式内存格式） |
| 存储格式 | Apache Parquet（列式文件格式） |
| 执行模式 | 单节点多线程向量化执行 |
| 查询能力 | 完整查询规划器 + 流式列式多线程执行引擎 |

> **证据：** "These pipelines utilize a backend powered by DataFusion, an open-source query engine written in Rust."  
> 来源：多处搜索结果对 Palantir 文档的描述

### 3.2 FDAP 架构模式

Faster 引擎遵循业界正在兴起的 **FDAP 架构模式**：

```
Flight（数据传输协议）
DataFusion（查询规划与执行）
Arrow（内存数据格式）
Parquet（持久化存储格式）
```

这一架构模式具备：
- 高性能数据传输（Flight）
- 高效查询规划与执行（DataFusion）
- 列式内存处理，减少序列化开销（Arrow）
- 高效存储与读取（Parquet）

### 3.3 单节点 vs. Spark 分布式对比

```
Faster Engine（DataFusion）          Spark Engine
┌────────────────────────┐          ┌────────────────────────────────┐
│  Single Node           │          │  Distributed Cluster           │
│  ┌──────────────────┐  │          │  ┌────────┐  ┌────────────┐   │
│  │ DataFusion Query │  │          │  │ Driver │  │ Executors  │   │
│  │ Planner (Rust)   │  │          │  │ (JVM)  │  │ (JVM × N)  │   │
│  └────────┬─────────┘  │          │  └────────┘  └────────────┘   │
│           │            │          │  DAG Scheduler + Shuffle       │
│  ┌────────▼─────────┐  │          └────────────────────────────────┘
│  │ Vectorized Multi │  │
│  │ Thread Execution │  │          启动开销：JVM spin-up + 依赖下载
│  └────────┬─────────┘  │
│           │ Arrow      │          启动开销：容器启动（轻量）
│  ┌────────▼─────────┐  │
│  │ Parquet I/O      │  │
│  └──────────────────┘  │
└────────────────────────┘
```

**核心差异：**

| 维度 | Faster（DataFusion） | Spark |
|---|---|---|
| 架构 | 单节点多线程 | 分布式多节点 |
| 启动开销 | 低（无 JVM cold start） | 高（JVM + executor 启动） |
| 内存模型 | Arrow 列式内存（堆外） | JVM 堆内 + 堆外 |
| 适用数据量 | 中小型 | 大型 / 超大型 |
| shuffle join | 受内存限制 | 支持大规模 shuffle |
| 序列化 | Arrow 原生，极低开销 | Java 序列化开销较高 |
| GC 压力 | 无（Rust） | 有（JVM GC 停顿） |

---

## 四、能力边界

### 4.1 不支持的能力（已知）

| 限制项 | 说明 |
|---|---|
| 部分地理空间（Geospatial）操作 | 某些高级地理空间计算需要回退 Spark |
| 超大规模 Shuffle Join | 数据超出单节点内存时无法处理 |
| Streaming Pipeline | 不支持，流式场景必须使用 Spark/Flink |
| 部分表达式/变换 | 不是所有 Pipeline Builder 的 expressions 和 transforms 都被支持 |

> **证据（geospatial）：** "certain geospatial capabilities might not be supported in the lightweight version, requiring a switch back to Spark for those specific operations."

> **证据（部分表达式）：** "Not all expressions and transforms available in standard Spark-based pipelines are supported in 'Faster' pipelines."

### 4.2 增量 Pipeline 的约束

增量 Pipeline 使用 Faster 引擎时有额外限制：

- **不能**在同一个增量输出中同时"追加新行 + 替换旧行"
- 需要替换旧行时，必须使用 **Snapshot Replace** 写入模式
- 上游输入必须通过 **APPEND** 事务更新（不能修改已有文件），否则增量逻辑失效

#### 根因分析：为什么有这些约束

这三条限制本质上源于**两个层面的根本原因**的叠加：

**根因一：DataFusion 是无状态查询引擎**

DataFusion 的设计定位是纯查询执行框架（stateless query engine）——它只负责"给我一批数据，我来执行查询，返回结果"，完全不维护任何跨执行的持久状态。

对比 Spark Structured Streaming：
- Spark 内置了 **State Store**（RocksDB-backed），支持跨微批的状态积累，天然能处理"用新行更新旧行"
- DataFusion 没有 State Store，每次执行是完全独立的查询，不知道"上次处理到哪里、已有行是什么"

这直接导致：**DataFusion 无法天然支持 Upsert / Update-in-place 的增量语义**，因为 Upsert 需要"查旧值 → 与新值合并 → 写回"，这是有状态的操作。

> **证据：** "Apache DataFusion is a stateless query engine, meaning it does not inherently manage state for incremental view maintenance."（多处来源一致）

**根因二：Foundry Dataset 的事务模型是"文件粒度不可变"**

Foundry 的 Dataset 本质是一套基于不可变文件的事务日志系统（类似 Delta Lake / Iceberg 思路）：

```
Dataset 版本视图
├── transaction_1: SNAPSHOT → [file_a.parquet, file_b.parquet]
├── transaction_2: APPEND   → [file_c.parquet]   ← 新增文件，不修改旧文件
├── transaction_3: APPEND   → [file_d.parquet]   ← 新增文件
└── 当前视图 = file_a + file_b + file_c + file_d
```

- **APPEND 事务语义**：只往文件列表追加新文件，已有文件不可修改（Parquet 文件天然不可原地更改）
- **SNAPSHOT 事务语义**：整体替换——把当前所有文件引用丢弃，换成一批新文件

增量引擎的工作方式是读取"上次 checkpoint 以来新增的事务"，而不是"重新全量扫描找差异"。若上游是 SNAPSHOT 事务，意味着整批数据被替换，没有"新增文件"可读，DataFusion 无法在文件层面知道"哪些数据是真正新增的"，也没有行级 diff 能力。

**三条约束的逐条推导：**

| 约束 | 推导路径 |
|---|---|
| 不能同时"追加 + 替换" | DataFusion 无状态，无法合并新行与历史行做 Upsert；要替换旧行必须读全量旧数据，这已等价于全量批处理 |
| 替换必须走 Snapshot Replace | ①的自然结论：降级为全量批处理，扔掉旧文件、重新生成全量，对应 Foundry SNAPSHOT 事务 |
| 上游必须是 APPEND 事务 | 增量引擎靠"读新增事务中的新文件"驱动；SNAPSHOT 事务无新增文件语义，DataFusion 拿不到增量数据边界 |

**为什么 Spark Batch 没有这些约束？**

Spark 通过以下机制突破了这些限制：
1. **分布式内存 + spill**：可把全量旧数据和新数据拉进来做 join，数据量不是瓶颈
2. **框架提供 `previous_df`**：`@incremental` transform 显式暴露上次输出的引用，开发者可自行实现 Upsert
3. **Structured Streaming State Store**：对真正流处理场景，RocksDB-backed 状态存储支持跨批次状态持久化

根本结论：Faster 引擎的增量约束不是设计缺陷，而是**单节点无状态查询引擎**与**文件不可变事务模型**共同决定的架构必然。它的优势（低延迟、低开销）和这些约束同源于一个决策：不维护状态、不做分布式协调。

### 4.3 与 Spark 的数据规模边界（推断）

> **注：以下为推断，缺乏官方量化数据**

- 官方描述 Faster 针对"small to medium-sized datasets"，未给出具体 GB/TB 边界
- 实践推荐：单次执行 < 15 分钟作为判断基准
- 超出内存容量的大规模 shuffle join 场景需回退 Spark

---

## 五、Faster 引擎 vs. Spark 选型决策

```
          ┌──────────────────────────────────┐
          │         数据规模判断              │
          └──────────────┬───────────────────┘
                         │
              ┌──────────▼──────────┐
              │  中小型 + < 15min?  │
              └──────────┬──────────┘
                 Yes ◄───┤───► No
                 │              │
    ┌────────────▼───┐    ┌─────▼──────────┐
    │ Faster Engine  │    │ Spark Engine   │
    │ (DataFusion)   │    │ (Distributed)  │
    └────────────────┘    └────────────────┘
    
    适用场景：                适用场景：
    - 低延迟批处理           - TB 级数据集
    - 快速迭代开发           - 复杂 Shuffle Join
    - 增量小批次处理         - Streaming Pipeline
    - 无复杂地理空间操作     - 地理空间密集计算
```

---

## 六、与 Batch 链路的差异（核心对比）

| 维度 | Faster Engine | Spark Batch |
|---|---|---|
| **计算引擎** | Apache DataFusion（Rust，单节点） | Apache Spark（JVM，分布式） |
| **执行模式** | 单节点多线程向量化 | 多节点 DAG 并行 |
| **启动延迟** | 极低 | 高（JVM + executor spin-up） |
| **适用数据量** | 中小型 | 不限（TB 级） |
| **批量全量** | ✅ 支持（Snapshot） | ✅ 支持 |
| **增量处理** | ✅ 支持（有约束） | ✅ 支持（更完整） |
| **Streaming** | ❌ 不支持 | ✅ 支持（Structured Streaming） |
| **地理空间** | 部分支持 | 完整支持 |
| **自定义 UDF** | 受限 | 完整支持（Python/Scala/Java） |
| **资源成本** | 低 | 高 |
| **混合使用** | ✅ 可在同一 Pipeline 中混合 Spark | N/A |

---

## 七、DataFusion 计算实现原理（执行链路拆解）

本节基于 Apache DataFusion 官方文档分析其计算逻辑全链路。

> **证据来源：** [DataFusion 官方架构文档](https://datafusion.apache.org/contributor-guide/architecture.html) 和 [用户指南](https://datafusion.apache.org/user-guide/introduction.html)

### 7.1 整体执行链路（六阶段）

```
用户输入（SQL / DataFrame API）
        │
        ▼
┌──────────────────┐
│  1. SQL 解析     │  SQL → AST（抽象语法树）
│     Parsing      │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  2. 逻辑计划     │  AST → LogicalPlan（关系代数 DAG）
│  Logical Plan    │  描述"做什么"，不关心"怎么做"
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  3. 逻辑优化     │  OptimizerRule 重写逻辑计划
│  Logical Opt.    │  谓词下推、列裁剪、常量折叠、Join 重排序
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  4. 物理计划     │  LogicalPlan → PhysicalPlan（ExecutionPlan 树）
│  Physical Plan   │  决定具体算子：HashJoinExec / SortExec / ...
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  5. 物理优化     │  PhysicalOptimizerRule 进一步调整
│  Physical Opt.   │  选择 join 算法、分区策略、消除冗余 sort
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  6. 执行         │  Pull-based 流式多线程向量化执行
│  Execution       │  输出：RecordBatch 流
└──────────────────┘
```

### 7.2 核心数据结构：RecordBatch

DataFusion 的执行单元不是行，而是 **RecordBatch**——Apache Arrow 定义的列式内存批次：

```
RecordBatch（默认 8192 行）
┌─────────────┬─────────────┬─────────────┐
│  col_a      │  col_b      │  col_c      │
│  (Int64     │  (Utf8      │  (Float64   │
│   Array)    │   Array)    │   Array)    │
├─────────────┼─────────────┼─────────────┤
│ [1,2,3,...] │ ["a","b"..] │ [1.1, 2.2..]│
└─────────────┴─────────────┴─────────────┘
      ↑ 列式存储：同列数据连续，CPU 缓存友好
      ↑ 不可变（immutable），方便并行传递
      ↑ Arrow 格式：跨语言零拷贝共享
```

**为什么列式比行式快？**
- 列式存储使 CPU cache line 命中率极高（同类型数据连续）
- SIMD 指令可对整列做向量化运算（如一次比较 8/16 个值）
- 列裁剪可跳过不需要的列，减少 I/O 和内存占用

### 7.3 关键优化：Parquet 读取层的下推

Faster 引擎处理 Foundry Dataset（Parquet 文件）时，DataFusion 在读取层做多层下推：

```
查询: SELECT a, b FROM t WHERE c > 100 AND d = 'foo'

Parquet 文件层级结构：
┌────────────────────────────────────────┐
│  File Level（文件级 metadata）         │ ← ① 文件剪枝
│  Row Group 1: c_min=50, c_max=80      │   跳过 c_max < 100 的文件
│  Row Group 2: c_min=90, c_max=200     │
│  ┌──────────────────────────────────┐ │
│  │ Page Index: d 的 Bloom Filter    │ │ ← ② Page 级剪枝
│  │ Page 1: 不含 'foo'               │ │   跳过不含目标值的 Page
│  │ Page 2: 可能含 'foo'             │ │
│  │ ┌────────────────────────────┐   │ │
│  │ │ Row Level: 实际行数据      │   │ │ ← ③ 行级延迟物化
│  │ │ 解码时直接过滤 c > 100     │   │ │   解码阶段就过滤，不进内存
│  │ └────────────────────────────┘   │ │
│  └──────────────────────────────────┘ │
└────────────────────────────────────────┘

④ 列裁剪：只读取 a, b, c, d 四列，其他列完全不 I/O
```

这四层下推是 DataFusion 在 Parquet 查询上快的核心原因，尤其对 Foundry 中大量宽表场景效益显著。

> **证据：** DataFusion 官方文档："Predicate Pushdown: File/Row Group Pruning… Page Pruning… Row-Level Filtering (Late Materialization)… Projection Pushdown ensures only necessary columns are read."

### 7.4 物理算子执行机制（Pull-based Streaming）

DataFusion 采用 **Pull-based 流式执行模型**（拉模型），算子树自顶向下拉取数据：

```
      ProjectionExec（输出 a, b）
             ↑ pull RecordBatch
      FilterExec（c > 100）
             ↑ pull RecordBatch
      HashJoinExec（left join right on key）
         ↑                    ↑
   DataSourceExec        DataSourceExec
   (table_a Parquet)     (table_b Parquet)

执行时：
1. ProjectionExec.next() → 调用 FilterExec.next()
2. FilterExec.next()     → 调用 HashJoinExec.next()
3. HashJoinExec          → 并发从两个 DataSource 拉数据，构建哈希表
4. 每次返回一个 RecordBatch（8192 行），向上传递
5. 内存中同时存在的数据只有当前处理批次
```

**关键算子说明：**

| 算子 | 作用 | 核心机制 |
|---|---|---|
| `DataSourceExec` | 读 Parquet/CSV | 含下推优化，多线程并发读多个文件分区 |
| `FilterExec` | 行级过滤 | 向量化布尔计算，SIMD 加速 |
| `ProjectionExec` | 列选择/计算 | Arrow 列式计算，无行拷贝 |
| `HashJoinExec` | Hash Join | 构建哈希表（build side）+ 探测（probe side），支持分区并行 |
| `AggregateExec` | 聚合 | 两阶段：局部聚合（分区内）→ 全局合并；内存不足可 spill 磁盘 |
| `SortExec` | 排序 | 外部归并排序，支持 spill |
| `RepartitionExec` | 重分区 | 调整并行度，类似 Spark shuffle 但在单节点内 |

### 7.5 多线程并行执行

DataFusion 在单节点内通过**数据分区**实现并行：

```
输入数据（N 个 Parquet 文件）
    │
    ├── Partition 0 → Thread 0: DataSourceExec → FilterExec → ...
    ├── Partition 1 → Thread 1: DataSourceExec → FilterExec → ...
    ├── Partition 2 → Thread 2: DataSourceExec → FilterExec → ...
    └── Partition N → Thread N: DataSourceExec → FilterExec → ...
                                        │
                              CoalescePartitionsExec
                              （合并各分区结果）
                                        │
                                  最终输出
```

- 每个 Parquet 文件（或文件内的 RowGroup）可作为一个独立分区
- Tokio 异步运行时驱动，IO 异步、CPU 并行，无阻塞等待
- `RepartitionExec` 可动态调整分区数，适配可用 CPU 核心数

**对比 Spark 分布式并行：**

| 维度 | DataFusion（单节点内并行） | Spark（跨节点分布式） |
|---|---|---|
| 协调开销 | 无（线程间共享内存） | 高（网络 shuffle，序列化） |
| 故障恢复 | 无内置容错（节点挂则失败） | RDD lineage 重算 |
| 扩展上限 | 单机 CPU 核心数 | 水平扩展到数千节点 |
| 数据交换 | Arrow 零拷贝传递 | Java 序列化 + 网络传输 |

### 7.6 Palantir 在 DataFusion 之上的推断封装层

Palantir 使用 DataFusion 作为 Faster Pipeline 的底层执行引擎，其上层封装（推断）大致如下：

```
Pipeline Builder（用户界面）
    │ 可视化 Transform 节点
    │ Filter / Join / Aggregate / Rename...
    ▼
Palantir Pipeline DSL（内部表示）
    │ 转换为 DataFusion LogicalPlan 或 SQL
    ▼
DataFusion 执行引擎
    │ 逻辑优化 → 物理计划 → 向量化执行
    ▼
Foundry Dataset（Parquet 文件）
    │ 通过 TableProvider trait 接入
    │ 读：APPEND 事务中的新文件 / 全量文件
    │ 写：生成新 Parquet 文件 → 提交 APPEND or SNAPSHOT 事务
    ▼
Foundry 存储层（对象存储）
```

Pipeline Builder 中每个可视化节点（Filter、Join、Group By 等）最终被翻译成 DataFusion 的逻辑计划节点，由 DataFusion 的优化器和执行引擎统一处理。

> **注：** Palantir 具体如何将 Pipeline Builder DSL 翻译为 DataFusion 计划属于内部实现，以上为架构推断，可信度为中等。

---

## 八、DataFusion 开源生态背景

DataFusion 被多个知名项目采用，说明其技术成熟度：

| 项目 | 用途 |
|---|---|
| InfluxDB 3.0 | 查询引擎 |
| Apple Comet | Spark 的 native Rust/Arrow 加速层 |
| OpenObserve | 直接查询 S3 Parquet 文件 |
| SpiceAI | 多数据源统一 SQL 查询 |
| Airtable | 查询 S3 Parquet，低延迟产品功能 |
| RisingWave | 替换批处理执行引擎 |

> **证据：** DataFusion 官方及社区资料，多处引用上述项目

---

## 九、关键结论

1. **Faster 引擎 = DataFusion**（推断可信度：高）  
   底层使用 Apache DataFusion，Rust 实现，单节点架构，Arrow 列式内存。

2. **适用场景边界**：中小数据量 + 执行时间 < 15 分钟，不适用 Streaming。

3. **相较 Spark 的核心优势**：无 JVM 冷启动、无 GC 停顿、启动延迟极低、资源成本低。

4. **关键限制**：不能处理超出单节点内存的大规模 shuffle；部分地理空间和 expressions 不支持。

5. **增量 Pipeline 约束的根因**：DataFusion 是无状态引擎（无 State Store）+ Foundry 文件事务模型不可变，两者叠加决定了不能原生支持 Upsert，上游必须是 APPEND 事务。

6. **计算核心是六阶段流水线**：SQL解析 → 逻辑计划 → 逻辑优化（谓词下推/列裁剪）→ 物理计划 → 物理优化 → Pull-based 向量化执行。

7. **性能来源**：Parquet 四层下推剪枝 + Arrow 列式 SIMD 向量化 + 单节点多线程 + 无序列化开销。

8. **混合使用是正式支持的模式**：Faster 节点 + Spark 节点可在同一 Pipeline 中共存。

---

## 十、证据可信度说明

| 结论 | 来源类型 | 可信度 |
|---|---|---|
| Faster = 前 Lightweight Pipeline | Palantir 官方文档转述（多个独立来源） | 高 |
| 底层 DataFusion (Rust) | Palantir 官方文档转述（多个独立来源） | 高 |
| < 15min 建议 | Palantir 官方文档转述 | 高 |
| 部分地理空间不支持 | Palantir 官方文档转述 | 高 |
| 单节点架构 | DataFusion 架构特性 + Palantir "single node" 描述 | 高 |
| 具体 GB/TB 数据规模边界 | 无官方量化，依赖 "< 15min" 代理指标 | 低（推断） |
| Arrow 列式内存 | DataFusion 架构特性（公开文档） | 高 |
| 增量约束根因（无状态 + 文件不可变） | DataFusion 官方文档 + Foundry 事务模型文档推导 | 高 |
| DataFusion 六阶段执行链路 | DataFusion 官方文档直接描述 | 高 |
| Parquet 四层下推 | DataFusion 官方文档直接描述 | 高 |
| Pull-based 流式多线程执行 | DataFusion 官方文档直接描述 | 高 |
| Palantir 封装层翻译逻辑 | 架构推断，无直接证据 | 低（推断） |

> **注：** Palantir 官方文档 `/docs/foundry/pipeline-builder/faster-pipelines/` 等页面返回 404，直接证据来自可信度较高的第三方转述，核心事实可交叉验证。DataFusion 相关章节均有官方文档直接支撑。
