# 基于 Paimon 数据湖的轻量引擎调研与实现方案

**日期：** 2026-06-17
**关联 Issue：** #67
**类型：** 技术调研 / 自建方案设计
**范围：** 轻量计算引擎、Paimon 数据湖、Transform Runtime、Engine Router

---

## 1. 总结与洞察

1. 【事实】轻量引擎的核心不是“更小的 Spark”，而是单进程或单节点多线程的向量化执行路径：用 Arrow/列式内存、Parquet 裁剪、短生命周期容器和较少调度层级降低启动与执行开销。
2. 【推断】基于 Paimon 做轻量引擎时，最关键的边界是“能否正确解释 Paimon 表语义”。Append 表可较容易映射为快照文件扫描；Primary Key 表由于 LSM、delete、merge engine、changelog 和 compaction，不能简单把底层 Parquet/ORC 文件交给 DuckDB/DataFusion 直接扫。
3. 【建议】第一阶段应采用“Paimon Java Scan Service + Arrow Flight/IPC + DataFusion 或 Polars/DuckDB 执行”的桥接方案，先保证 Paimon 快照、filter/projection pushdown、主键表 latest view 和权限审计正确，再评估是否自研 Rust DataFusion `TableProvider`。
4. 【建议】轻量引擎的产品定位应是 preview、小中规模 batch、append-only 增量、简单聚合/filter/join 和低成本快速构建；大 shuffle、复杂状态、流处理、长任务和高风险 upsert 输出应继续路由到 Spark/Flink。
5. 【推断】自建 Engine Router 必须把数据量、查询形态、Paimon 表类型、增量语义、主键 merge 需求、依赖可解析性和治理约束一起作为输入，而不是只按 GB 阈值选择轻量或 Spark。

---

## 2. 轻量引擎通常如何实现

### 2.1 定位

轻量引擎面向的是 Spark/Flink 过重的工作负载：

- 数据量小到中等，或经过分区/文件/列裁剪后实际扫描量较小。
- 作业以 filter、projection、表达式派生、简单 join、聚合、排序、抽样、preview 为主。
- 用户关心启动延迟、交互反馈和单位任务成本。
- 不需要持续状态、超大 shuffle、复杂容错和跨节点资源调度。

仓库已有 `docs/raw/17-faster-engine-deep-dive.md` 与 `docs/raw/24-pro-code-runtime-compute-engines.md` 指出，Palantir Faster/Python lightweight 的公开路径分别体现为 DataFusion、DuckDB、Polars、pandas 等 single-node compute，而 Spark 保留给 distributed compute。【事实，来自仓库既有调研】

### 2.2 通用架构

```text
Transform / SQL / OperatorSpec
        |
        v
Engine Router
  - capability matrix
  - cost model
  - governance checks
        |
        v
Lightweight Runtime Container
  - DataFusion / DuckDB / Polars
  - Arrow RecordBatch / columnar memory
  - local spill / memory budget
        |
        v
Lake Table Adapter
  - catalog and snapshot resolution
  - file and split planning
  - predicate/projection pushdown
  - write commit adapter
        |
        v
Object Store / HDFS / Paimon Warehouse
```

### 2.3 关键实现点

| 模块 | 作用 | 设计要点 |
|---|---|---|
| Engine Router | 决定轻量、Spark、Flink 或拒绝执行 | 不能只看数据量，还要看表类型、join/shuffle、UDF、写入语义、权限和 SLA |
| Runtime Sandbox | 提供隔离执行环境 | 短生命周期容器、CPU/内存限额、依赖缓存、日志与 metrics 注入 |
| Planner Adapter | 把平台 Transform/SQL 转成引擎计划 | SQL AST 或 Operator DAG 到 DataFusion/DuckDB/Polars 计划 |
| Table Adapter | 把湖表快照变成可扫描的 split | catalog、snapshot、manifest、partition、file stats、projection/filter pushdown |
| Vectorized Execution | 实际执行计算 | Arrow/列式 batch，避免 JVM 和行式对象开销 |
| Commit Adapter | 写回湖表事务 | append、overwrite、snapshot replace、commit/abort、幂等重试 |
| Fallback | 超出边界时回退 | 保留 Spark/Flink 等价实现，避免轻量路径承诺过度 |

### 2.4 为什么快

轻量引擎的收益通常来自四类减少：

1. 【事实】减少调度层级：DataFusion 官方 FAQ 说明 DataFusion 是进程内执行库，通过线程并行执行查询；这省去了 Spark Driver/Executor 的集群调度路径。参考：<https://datafusion.apache.org/user-guide/faq.html>
2. 【事实】减少序列化和对象开销：DataFusion 使用 Arrow 内存格式，Arrow 是列式内存表示；DataFusion 官方介绍强调其 Rust、Arrow、Parquet/CSV/JSON/Avro 支持和可嵌入性。参考：<https://datafusion.apache.org/user-guide/introduction.html>
3. 【事实】减少扫描量：DataFusion `TableProvider` 和 Parquet reader 支持 filter/projection pushdown、file pruning、row group/data page pruning 等扩展点。参考：<https://datafusion.apache.org/library-user-guide/custom-table-providers.html>、<https://datafusion.apache.org/blog/2025/08/15/external-parquet-indexes/>
4. 【推断】减少资源浪费：小作业不再为数秒到数分钟的计算支付 Spark 集群初始化、executor 启动、shuffle service 和 JVM warm-up 成本。

---

## 3. Paimon 对轻量引擎的约束

### 3.1 Paimon 不是裸 Parquet 目录

Apache Paimon 官方定义其为支持 Flink/Spark 流批操作的 lake format，结合湖表格式与 LSM 结构，把实时更新带入 lakehouse；其能力包括 primary key 大规模更新、merge engine、changelog-producer、append table、compaction、ACID、time travel 和 schema evolution。参考：<https://paimon.apache.org/docs/1.3/>

这意味着轻量引擎不能只做：

```text
SELECT * FROM 'warehouse/db/table/**/*.parquet'
```

对 Append 表，这种做法可能在简单场景下“看起来能跑”，但会绕过 snapshot 隔离、partition/bucket 规则、schema evolution、权限审计和 snapshot retention。对 Primary Key 表，这种做法会直接读到 LSM 中未合并的历史文件、delete/update 记录或中间状态，结果可能错误。【推断】

### 3.2 Paimon 表语义对执行器的要求

| Paimon 能力 | 对轻量引擎的要求 |
|---|---|
| Snapshot / manifest | 读取必须绑定明确 snapshot，不能直接枚举当前目录 |
| Partition / bucket | planner 要利用分区、bucket 和文件统计做 split 裁剪 |
| Primary Key + LSM | reader 要能合并 sorted runs，产出 latest view |
| Merge Engine | deduplicate、partial-update、aggregation、first-row 等语义必须由 Paimon 层解释 |
| Changelog Producer | 增量读要区分 input、lookup、full-compaction 等 changelog 来源 |
| Compaction | 查询不能因为 compaction 重写文件而重复或漏读 |
| Schema Evolution | 读写侧要按 snapshot schema 做兼容映射 |
| ACID Commit | 输出必须通过 Paimon commit/abort，不可直接写文件后改目录 |

Paimon Java API 显示，batch read 会先在 coordinator/driver 生成 scan splits，再在 task 读取 split；还支持 projection/filter pushdown。Stream read 通过 `StreamTableScan` 连续生成 splits 并支持 checkpoint/restore。参考：<https://paimon.apache.org/docs/1.3/program-api/java-api/>

---

## 4. 推荐方案：Paimon Scan Service + 轻量执行器

### 4.1 目标架构

```text
Pipeline Builder / Pro Code
        |
        v
Transform Runtime API
        |
        v
Engine Router
        |
        +-- Spark Runtime     : 大规模、复杂 shuffle、Spark-only API
        +-- Flink Runtime     : streaming、持续状态、CEP、低延迟事件处理
        +-- Lightweight Runtime
              |
              v
        Paimon Scan Service
          - resolve catalog/table/snapshot
          - plan splits with filter/projection
          - materialize PK latest view when needed
          - expose Arrow Flight / Arrow IPC stream
              |
              v
        DataFusion / Polars / DuckDB
          - execute vectorized plan
          - apply non-pushed expressions
          - spill within memory budget
              |
              v
        Paimon Commit Service
          - append / overwrite / snapshot replace
          - commit / abort / idempotent retry
          - lineage + build metadata
```

### 4.2 为什么先用 Java Scan Service

Paimon 官方 Java API 是当前最完整的程序化入口，并明确覆盖 catalog、batch read、batch write、stream read、stream write、predicate 和 projection。【事实】

先使用 Java Scan Service 的工程收益：

- 复用 Paimon 官方 reader，避免重新实现 LSM、merge engine、schema evolution 和 changelog 语义。
- 通过 Arrow Flight/IPC 输出列式 batch，轻量执行器仍可保留 Arrow-native 的低开销执行路径。
- 可以在服务层统一做权限、审计、snapshot pin、split metrics、失败重试和缓存。
- 未来如果 Rust/Python Paimon API 成熟，可逐步替换为原生 DataFusion `TableProvider`。

代价：

- 多一个跨进程边界，存在 Arrow 序列化、网络或本机 IPC 开销。
- Java Service 与 Rust/Python 执行器之间需要统一类型映射、错误模型和 backpressure。
- 执行计划的 pushdown 需要做两段优化：能下推给 Paimon 的先下推，剩余表达式由轻量引擎执行。

### 4.3 轻量执行器选择

| 选择 | 适合场景 | 不适合场景 | 建议 |
|---|---|---|---|
| DataFusion | 自建平台内嵌查询执行、Rust 服务、TableProvider 可扩展 | Python 生态依赖重的 transform | 作为平台内核优先评估 |
| Polars | Python DataFrame API、生产中等规模列式处理 | SQL-heavy、多表复杂优化 | 作为 Python transform 默认轻量路径 |
| DuckDB | SQL-heavy、本地分析、Parquet 扫描、spill 友好 | 需要 DataFrame API 或深度平台内嵌自定义 | 作为 SQL lightweight 和 preview 路径 |
| pandas | 小数据、探索、生态兼容 | 生产中等规模、内存敏感任务 | 只作为兼容路径 |

### 4.4 读路径

1. Runtime 固定输入 dataset 的 branch、snapshot 或 build input version。
2. Router 判断表类型：append、primary key、是否 changelog、是否需要 latest view。
3. 将可下推谓词、列裁剪、limit、partition filter 传给 Paimon Scan Service。
4. Paimon Scan Service 使用 Paimon API 生成 splits，并在必要时合并 PK/LSM latest view。
5. Scan Service 输出 Arrow RecordBatch。
6. DataFusion/Polars/DuckDB 执行剩余表达式、join、aggregation 和排序。
7. Runtime 收集 metrics：扫描文件数、裁剪文件数、实际 bytes、峰值内存、spill、耗时。

### 4.5 写路径

轻量写入应从保守能力开始：

| 输出模式 | L1 是否支持 | 说明 |
|---|---:|---|
| Append table append | 是 | 最低风险，适合 append-only transform |
| Snapshot replace / overwrite | 是 | 全量结果替换，适合 batch 小中规模 |
| Primary Key upsert | 暂缓 | 需要 merge engine、主键一致性和幂等 commit 设计 |
| Changelog 输出 | 暂缓 | 需要明确 rowkind、consumer 位点和下游语义 |
| Streaming sink | 否 | 路由到 Flink |

---

## 5. 增量计算方案

### 5.1 Append 表增量

Append 表可以把上次成功 build 的 input snapshot 与当前 snapshot 做 delta 范围读取，轻量引擎只处理新增文件或新增 snapshot 的 split。平台侧保存：

- transform id
- input dataset id
- branch
- last successful input snapshot
- code semantic version
- output snapshot
- engine and runtime version

如果输入发生 overwrite、schema breaking change、semantic version 变更或 delta 过大，Router 应回退到全量 snapshot replace 或 Spark。【建议】

### 5.2 Primary Key 表增量

Primary Key 表有两种不同需求：

1. 读取 latest view 做小中规模 batch transform。
2. 读取 changelog 做行级增量处理。

第一类适合轻量引擎，但必须由 Paimon reader materialize latest view。第二类更接近流式或 CDC 语义，应优先让 Flink/Spark 处理；轻量引擎只在小规模、幂等、无复杂状态的场景试点。【建议】

Paimon 配置项 `changelog-producer` 可生成 changelog 文件，官方配置说明其可用于 primary key 表，并有 `none`、`input`、`full-compaction`、`lookup` 等模式。参考：<https://paimon.apache.org/docs/1.3/maintenance/configurations/>

### 5.3 与现有平台增量模型的映射

| 平台语义 | Paimon 映射 | 轻量策略 |
|---|---|---|
| APPEND | 新 snapshot / 新 data files | 轻量增量优先 |
| SNAPSHOT | overwrite / full replacement | 全量轻量或 Spark |
| UPDATE | PK table merge / changelog | 小规模 latest view 可轻量；行级增量优先 Spark/Flink |
| DELETE | changelog 或 merge state | 默认 Spark/Flink，轻量只读 latest view |

---

## 6. Engine Router 规则草案

### 6.1 路由到轻量引擎

满足以下条件时优先轻量：

- 预计扫描量在单节点内存和 spill 能力内。
- 操作为 filter、projection、简单表达式、低基数 aggregation、小表 join、preview、抽样。
- 输入为 Append 表，或 PK 表但只读 latest view 且 Paimon Scan Service 可正确 materialize。
- 输出为 append 或 snapshot replace。
- 无 Spark-only UDF、分布式依赖、复杂 geospatial、超大 shuffle、长时间运行需求。
- 权限、marking、审计和 lineage 可在 Runtime API 与 Scan/Commit Service 中完整记录。

### 6.2 路由到 Spark

出现以下条件时路由 Spark：

- 扫描量或 shuffle 预计超出单节点上限。
- 多大表 join、复杂窗口、宽表高基数 group by、需要稳定 spill 和分布式容错。
- 依赖 PySpark/Spark SQL API、JVM/Scala UDF 或 Spark-only feature。
- 输出涉及大规模 overwrite、复杂 upsert、重分区或 compaction 协同。

### 6.3 路由到 Flink

出现以下条件时路由 Flink：

- 持续 streaming、低延迟事件处理、窗口状态、CEP。
- 需要 checkpoint/savepoint、exactly-once streaming sink。
- 需要持续读取 Paimon changelog 或 Kafka 并维护状态。

---

## 7. 分阶段建设路线

### L1：只读和 preview

- 支持 Paimon Append 表 snapshot read。
- 支持 filter/projection/limit 下推。
- 输出 Arrow 到 DataFusion/Polars/DuckDB。
- 提供 dataset preview、profile、sample、简单 SQL。
- 只读，不写回生产表。

验收指标：

- 同一 snapshot 与 Spark 查询结果一致。
- 能记录扫描 snapshot、文件数、bytes、耗时、内存。
- 错误时可解释回退原因。

### L2：轻量 batch transform

- 支持 append 输出和 snapshot replace。
- 支持小中规模 transform DAG 中的轻量节点。
- 支持 Engine Router 自动选择和 Spark fallback。
- 支持 Build History、lineage、日志、metrics。
- 支持 Append 表 delta 增量。

验收指标：

- 典型 filter/projection/aggregation 作业启动和完成时间显著低于 Spark。
- 同一输入版本下可重复构建。
- commit/abort 幂等，失败不产生脏数据。

### L3：Primary Key 表与高级优化

- 支持 PK 表 latest view 读取。
- 支持 Paimon split/file metadata 缓存。
- 支持更多表达式和小表 join。
- 评估 Rust DataFusion `TableProvider` 原生化。
- 对 changelog 小规模批式消费做受控试点。

验收指标：

- PK 表读结果与 Flink/Spark Paimon connector 对齐。
- compaction 前后结果一致。
- schema evolution 场景可通过兼容性测试。

---

## 8. 主要风险

1. 【风险】直接读取底层 Parquet/ORC 会破坏 Paimon PK 表语义，必须禁止作为生产读取路径。
2. 【风险】Java Scan Service 与 DataFusion/Polars/DuckDB 的类型映射可能出现 decimal、timestamp、nested type、rowkind 语义差异。
3. 【风险】轻量引擎如果没有严格 memory budget、spill 和 kill 策略，会把小作业变成单机稳定性问题。
4. 【风险】增量位点如果只记录“上次时间”而不是 snapshot/consumer state，会在 compaction、overwrite、重跑时产生漏读或重复读。
5. 【风险】过早支持 PK upsert/changelog 输出会扩大事务一致性面，建议等只读 latest view 和 append/snapshot replace 稳定后再做。

---

## 9. 待验证问题

1. Paimon Java reader 输出 Arrow 的最佳路径：Arrow Flight、Arrow IPC、本地 JNI，还是先落本地临时 Arrow/Parquet。
2. Paimon predicate 与 DataFusion/DuckDB/Polars predicate 的可下推子集如何表达。
3. PK 表 latest view 在高频 compaction 下的 snapshot pin 和 read consistency 细节。
4. 单节点轻量引擎的默认内存、spill、并发和超时阈值。
5. 轻量引擎与现有权限、marking、lineage、build history 的最小闭环接口。

---

## 10. 参考资料

- Apache Paimon 1.3.2 Overview: <https://paimon.apache.org/docs/1.3/>
- Apache Paimon Understand Files: <https://paimon.apache.org/docs/1.3/learn-paimon/understand-files/>
- Apache Paimon Java API: <https://paimon.apache.org/docs/1.3/program-api/java-api/>
- Apache Paimon Configurations: <https://paimon.apache.org/docs/1.3/maintenance/configurations/>
- Apache DataFusion Introduction: <https://datafusion.apache.org/user-guide/introduction.html>
- Apache DataFusion FAQ: <https://datafusion.apache.org/user-guide/faq.html>
- Apache DataFusion Custom Table Provider: <https://datafusion.apache.org/library-user-guide/custom-table-providers.html>
- DataFusion external indexes and metadata caches: <https://datafusion.apache.org/blog/2025/08/15/external-parquet-indexes/>
- 仓库既有调研：`docs/raw/17-faster-engine-deep-dive.md`
- 仓库既有调研：`docs/raw/24-pro-code-runtime-compute-engines.md`
- 仓库既有调研：`docs/raw/20-stream-self-build-architecture.md`
- 仓库既有调研：`docs/raw/41-lakehouse-layout-partition-cost-model.md`
