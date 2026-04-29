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

## 七、DataFusion 开源生态背景

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

## 八、关键结论

1. **Faster 引擎 = DataFusion**（推断可信度：高）  
   底层使用 Apache DataFusion，Rust 实现，单节点架构，Arrow 列式内存。

2. **适用场景边界**：中小数据量 + 执行时间 < 15 分钟，不适用 Streaming。

3. **相较 Spark 的核心优势**：无 JVM 冷启动、无 GC 停顿、启动延迟极低、资源成本低。

4. **关键限制**：不能处理超出单节点内存的大规模 shuffle；部分地理空间和 expressions 不支持。

5. **增量 Pipeline 有额外约束**：写入模式和上游事务类型有限制。

6. **混合使用是正式支持的模式**：Faster 节点 + Spark 节点可在同一 Pipeline 中共存。

---

## 九、证据可信度说明

| 结论 | 来源类型 | 可信度 |
|---|---|---|
| Faster = 前 Lightweight Pipeline | Palantir 官方文档转述（多个独立来源） | 高 |
| 底层 DataFusion (Rust) | Palantir 官方文档转述（多个独立来源） | 高 |
| < 15min 建议 | Palantir 官方文档转述 | 高 |
| 部分地理空间不支持 | Palantir 官方文档转述 | 高 |
| 单节点架构 | DataFusion 架构特性 + Palantir "single node" 描述 | 高 |
| 具体 GB/TB 数据规模边界 | 无官方量化，依赖 "< 15min" 代理指标 | 低（推断） |
| Arrow 列式内存 | DataFusion 架构特性（公开文档） | 高 |

> **注：** Palantir 官方文档 `/docs/foundry/pipeline-builder/faster-pipelines/` 等页面返回 404，直接证据来自可信度较高的第三方转述，核心事实可交叉验证。
