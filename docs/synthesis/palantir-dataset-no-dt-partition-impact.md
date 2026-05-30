# Palantir Dataset 无默认 dt 分区模型的数据模型差异分析

**日期：** 2026-05-30  
**类型：** 技术调研  
**覆盖方向：** Foundry Dataset / dt 分区 / 传统离线数仓 / Dataset Transaction / 增量计算 / 调度与补数 / 治理审计 / 湖仓成本模型

---

## 1. 总结与洞察

1. 【事实】Foundry Dataset 不是“完全没有分区”。官方支持 Spark/Hive-style partitioning、projection、Spark repartition、stream partitions 等优化或吞吐概念；但 Dataset 的基础语义不是 `dt=yyyy-mm-dd` 分区，而是 `Dataset + branch + transaction/view`。
2. 【推断】传统离线数仓把 `dt` 同时用作物理裁剪、业务日期、调度实例、补数边界、SLA 口径、生命周期单位和血缘定位入口；Foundry 则把这些职责拆开：物理布局由文件/partition/projection 解决，版本由 transaction 解决，业务日期需要作为 schema 字段、Ontology 属性或 business partition manifest 显式建模。
3. 【推断】这个差异的深层影响不是“少了一个分区字段”，而是数据平台的主坐标系从“表 + 分区日期”迁移到“数据资产 + 版本”。这会改变调度、补数、血缘、审计、幂等、成本优化和业务对齐方式。
4. 【推断】从架构适配性看，Foundry 的模型更适合持续更新、分支协作、版本追溯、流批统一和对象化应用；传统 `dt` 分区模型更适合强 T+1、账期、监管报送、分区级补数和按日期验收的离线生产链路。
5. 【建议】自建或迁移时不要把 `dt` 分区直接丢掉。应把 `business_date` / `data_interval` / `run_id` / `active_view_pointer` 做成显式数据契约，并为需要账期一致性的链路增加 business partition manifest 或 ready barrier。

---

## 2. 本轮并行调研交付物

本轮调研按 Issue #28 拆成五个并行 story，并把原始结论沉淀为 raw 文档：

| Issue | 调研域 | 输出文档 | 对本文的作用 |
|---|---|---|---|
| #29 | Foundry Dataset transaction/view 证据链 | `docs/raw/39-foundry-dataset-transaction-view-evidence.md` | 证明主坐标是 `dataset + branch + transaction/view`，不是 `table + dt` |
| #32 | 传统 `dt` 分区生产控制语义 | `docs/raw/40-traditional-dt-partition-production-semantics.md` | 证明 `dt` 同时承担业务日期、调度、补数、幂等、SLA 和生命周期 |
| #34 | 湖仓布局、分区裁剪与成本模型 | `docs/raw/41-lakehouse-layout-partition-cost-model.md` | 区分 table/layout partition、projection、stream partition、compute partition |
| #30 | 治理、血缘、审计与元数据契约 | `docs/raw/42-governance-lineage-audit-contracts.md` | 给出 run-to-transaction、coverage lineage、quality evidence、access audit 的最小契约 |
| #33 | 迁移风险案例与双坐标设计模式 | `docs/raw/43-migration-risk-dual-coordinate-patterns.md` | 收敛 ready barrier、active pointer、supersedes transaction、coverage lineage 四类设计模式 |

【推断】五个 story 的交叉结论一致：`dt` 与 transaction 不在同一抽象层。`dt` 是传统离线生产坐标，transaction 是数据版本证据；迁移时必须采用双坐标，而不是二选一。

本轮综合稿随后交给四类专家复审：Foundry 平台架构、传统数据仓库/调度、湖仓与查询引擎、数据治理/血缘/审计。四位专家均给出“有条件通过”：主线成立，但必须补强 branch fallback、schema-on-view、append-only 失败条件、retention 与 `DELETE` 的区分、DataWorks/MaxCompute 边界、成本模型、权限审计和证据边界。本文后续章节已吸收这些必修意见。

---

## 3. 专家圆桌结论

本轮讨论邀请了四类专家视角：Foundry 平台架构、传统数据仓库/调度、湖仓/查询引擎与存储布局、数据治理/血缘/审计。四方观点有明显共识，也有需要在文档中保留的边界分歧。

### 3.1 共识

| 共识 | 含义 |
|---|---|
| `dt` 不是普通字段 | 在传统数仓中，`dt` 同时是业务日期、调度实例键、补数边界、SLA 验收单元、生命周期单元和血缘定位入口。 |
| transaction 不是 `dt` | Foundry Dataset transaction 是版本坐标，能证明某次文件集合变化，但不天然说明这次变化覆盖哪个业务日期。 |
| Foundry 不是反分区模型 | Foundry 支持 Hive-style partitioning、projection、repartition 和 stream partition，但这些不是 Dataset 的默认业务主坐标。 |
| 迁移风险主要在生产语义 | 最大风险不是 SQL 查询改写，而是补数、验收、责任边界、质量证据和业务日期对齐丢失。 |
| 最终应采用双坐标 | transaction/view 负责版本证据链，business_date/partition manifest 负责业务解释和生产控制。 |

### 3.2 分歧与取舍

| 议题 | 专家分歧 | 本文采用的判断 |
|---|---|---|
| 是否保留 `dt` | Foundry 视角倾向弱化 `dt` 主坐标；传统数仓视角强调 `dt` 是生产闭环。 | 保留 `business_date`，但不让它继续承担所有平台底座职责。 |
| 性能优化是否围绕日期 | 数仓习惯要求查询强带 `dt`；湖仓视角认为优化应由访问模式决定。 | 对时间序列事实表保留日期布局；对实体、关系、状态、主数据采用更合适的布局或 projection。 |
| transaction 能否替代补数 | Foundry 视角认为 transaction 能表达版本变化；治理视角认为业务覆盖范围必须显式声明。 | transaction 只能替代表状态版本，不能替代业务日期、补数范围和 SLA 合同。 |
| 是否把 partition manifest 做成必需能力 | 轻量分析链路可能不需要；账期/监管/财务链路强依赖。 | 对强业务日期一致性链路设为必需，对 latest-view 场景设为可选。 |

### 3.3 专家提出的最终论证主线

```text
传统 dt 分区模型
  = table + dt + task_instance
  = 目录/分区裁剪 + 业务日期 + 调度实例 + 补数覆盖 + SLA + 生命周期 + 分区血缘

Foundry Dataset 模型
  = dataset + branch + transaction/view
  = 文件集合版本 + 分支隔离 + 构建血缘 + 权限治理 + Ontology 应用语义

结论
  transaction 管版本证据
  business_date / manifest 管业务解释
  两者互补，不应互相替代
```

---

## 4. 证据链

### 4.1 Foundry 侧证据

| 证据 | 来源 | 支持的结论 |
|---|---|---|
| Dataset 是 backing filesystem 上文件集合的 wrapper，并提供 permission、schema、version control 和 updates over time | Palantir Foundry Datasets | Dataset 的一阶抽象是数据资产和版本化文件集合，不是传统 `table + dt`。 |
| Dataset 通过 `SNAPSHOT`、`APPEND`、`UPDATE`、`DELETE` transaction 改变 view；view 从最近 SNAPSHOT 开始应用后续 transaction | Palantir Foundry Datasets | Foundry 的时间/版本边界是 transaction/view。 |
| Schema 是 dataset view 上的 metadata，API 可用 `branchName`、`endTransactionRid`、`versionId` 定位 schema | Palantir Dataset Schema API | schema 跟随 view 和版本，不应按传统静态表定义理解。 |
| build 在当前 branch 解析输入时可能使用 fallback branch | Palantir Pipeline Builder fallback branches | 血缘和审计必须记录 requested/resolved branch 与 `fallback_used`。 |
| `APPEND` 是 incremental pipelines 的基础，`UPDATE` 会破坏 append-only 要求并让下游回落 snapshot/batch processing | Palantir Foundry Datasets、Incremental transforms | Foundry 增量语义围绕 transaction 类型，而不是围绕 `dt` 分区。 |
| Hive-style partitioning 会把 partition column values 写入文件路径，并在 transaction metadata 记录 partition columns | Palantir Hive-style partitioning | Foundry 可以做分区裁剪，但这是布局优化，不是 Dataset 默认主坐标。 |
| projection 可针对 filter、join、aggregate 优化；incremental pipelines 可能产生很高文件数，projection 可透明 compaction | Palantir Dataset projections | Foundry 性能优化是工作负载驱动，不只依赖 `dt`。 |
| stream partitions 用于吞吐和并行处理，读写行为对生产者/消费者表现得像单分区 | Palantir Streams | “partition”在 Foundry 内部也有不同层级，不能等同传统业务日期分区。 |

### 4.2 传统数仓侧证据

| 证据 | 来源 | 支持的结论 |
|---|---|---|
| DataWorks `$bizdate` 获取业务时间，通常为 T-1；`$cyctime` 获取任务实例理论调度时间，精确到秒，不等于资源排队后的实际启动时间 | 阿里云 DataWorks 调度参数文档 | 传统离线调度明确区分业务日期、理论调度时间和实际运行时间。 |
| DataWorks 文档说明离线计算中 `bizdate` 是业务交易发生日期，例如今天统计昨天营业额 | 阿里云 DataWorks 调度参数最佳实践 | `dt`/business date 是业务事实归属，不是任务运行时间。 |
| DataWorks 补数据流程要求输入业务日期，并生成补数据实例；周/月任务补数据通常需选择实际调度日前一天作为业务时间 | 阿里云 DataWorks 加工数据文档 | 补数边界围绕业务日期实例，而不是只围绕表版本；周/月账期不能从实际运行日直接推导。 |
| Hive DDL 支持 `PARTITIONED BY(dt STRING, country STRING)` | Apache Hive DDL | 传统表模型把分区列建入表定义。 |
| Hive DML 支持 `INSERT OVERWRITE TABLE ... PARTITION(...)`，并说明 INSERT OVERWRITE 会覆盖目标表或分区已有数据 | Apache Hive DML | `dt` 分区是幂等覆盖和重跑边界。 |
| MaxCompute `INSERT OVERWRITE` 会清空并重写指定表或静态分区；动态分区写入和并发创建分区有额外限制 | MaxCompute DML / partition operation | MaxCompute/ODPS 也把分区写入作为生产边界，但实现约束需要单独处理。 |

### 4.3 现代湖仓侧证据

| 证据 | 来源 | 支持的结论 |
|---|---|---|
| Iceberg hidden partition 通过 partition transform、manifest list、manifest file 和文件统计裁剪，不要求用户在 SQL 中显式写物理分区列 | Apache Iceberg Partitioning | 现代表格式正在把逻辑查询和物理分区解耦，但不是没有物理布局。 |
| BigQuery 支持表分区和 clustering block pruning，on-demand 成本主要受 bytes processed 影响 | BigQuery Partitioned / clustered tables | 云数仓仍保留时间分区，但把它作为可选布局和计费优化机制。 |
| Snowflake micro-partition 自动执行，并记录每列 min/max、distinct 等元数据用于 pruning；clustering key 不是 Hive-style directory partition | Snowflake Micro-partitions / clustering keys | 现代数仓可用自动微分区和统计信息替代手工目录分区的一部分职责。 |

### 4.4 证据推导

1. 【事实】Foundry Dataset 的官方基础模型是文件集合、transaction、branch、view 和 schema。
2. 【事实】传统 Hive/DataWorks 的官方基础模型把 partition 和 business date 直接纳入表定义、调度参数和补数流程。
3. 【事实】现代湖仓系统已经出现 hidden partition、partition evolution、micro-partition、projection、clustering 等多种布局机制。
4. 【推断】因此，`dt` 与 Foundry transaction 不在同一抽象层：`dt` 是业务生产坐标，transaction 是数据版本坐标。
5. 【建议】最终建模应使用双坐标：`transaction/view` 负责版本证据，`business_date/data_interval/manifest` 负责业务生产解释。

---

## 5. 先澄清：不是没有分区，而是没有默认 dt 主坐标

### 5.1 Foundry Dataset 的一阶语义

【事实】Foundry Dataset 是围绕文件集合构建的数据资产抽象。官方文档定义 Dataset 是 backing filesystem 上文件集合的 wrapper，并提供权限、schema、版本控制和随时间更新能力。Dataset 通过 transaction 改变文件集合，transaction 类型包括 `SNAPSHOT`、`APPEND`、`UPDATE`、`DELETE`。

【事实】Dataset view 是某个 branch 在某个时间点的有效文件集合。它从最近的 `SNAPSHOT` 开始，再按后续 `APPEND`、`UPDATE`、`DELETE` transaction 计算出当前 view。

【事实】Dataset schema 是 dataset view 上的 metadata，可随 branch、end transaction 和 schema version 变化；schema 也不天然保证底层文件一定符合。迁移时不能把 schema 简化成“静态表定义 + 分区字段”。

【术语边界】本文的小写 `dataset view` 指某个 Dataset branch 在某个 transaction 端点解析出的有效文件集合；Foundry 的 `View` 资源是另一类逻辑资源，基于 backing datasets 在读取时组合数据，本身不等同于 Dataset transaction，也不应被当成 transform output。

【推断】因此，Foundry Dataset 的默认主坐标不是：

```text
table_name + dt
```

而是：

```text
dataset_rid/path + branch + transaction/view
```

### 5.2 Foundry 仍然有分区和布局优化

【事实】Foundry 官方支持 Hive-style partitioning。其机制是在 Spark 写出 Dataset 时，根据指定 partition columns 把不同取值组合写成不同文件路径，并在 transaction metadata 里记录 partition columns。Spark、Polars 等 reader 在这些列上过滤时可以利用 metadata 和路径缩小读取文件范围。

【事实】Foundry 也支持 dataset projections。projection 通常面向单一查询模式，优化过滤、join 或聚合；官方还明确指出 incremental pipelines 可能造成很高文件数，projection 可以用于平台维护的访问路径优化和读取加速。这里的 compaction 指 projection 访问路径的维护，不等同于 canonical Dataset 文件已经被原地物理 compact。

【事实】Foundry stream 也有 partitions，但官方强调这是为了吞吐和并行处理，读写行为对生产者/消费者表现得像单分区。这和离线数仓 `dt` 业务分区不是同一层概念。

【推断】所以更准确的表述是：Foundry Dataset 没有把 `dt` 作为所有批处理数据的默认业务分区、调度分区和生命周期分区；分区只是可选的数据布局优化之一。

---

## 6. 传统 dt 分区模型到底承担了什么

传统 Hive / MaxCompute / DataWorks / T+1 离线数仓里的 `dt` 往往不只是字段，而是一个复合制度。

| 职责 | `dt` 在传统数仓中的作用 | 典型实践 |
|---|---|---|
| 物理布局 | 数据按日期目录或分区存储 | `.../table/dt=2026-05-29/` |
| 查询裁剪 | 查询带 `where dt = ...` 时只扫目标分区 | partition pruning |
| 调度实例 | 每天生成一个业务日期实例 | `bizdate = 调度日 - 1` |
| 补数边界 | 重跑某一天、某几天、某月 | rerun/backfill partition |
| 幂等写入 | `insert overwrite partition(dt=...)` 替换目标日期结果 | 分区级覆盖 |
| SLA 验收 | 判断某个业务日期是否产出完成 | partition ready |
| 生命周期 | 删除过期日期分区 | drop partition / retention |
| 血缘定位 | 追踪哪个任务生产哪个日期分区 | task instance -> table partition |

【推断】传统 `dt` 模型的强项在于“组织生产秩序”。它把数据、调度、补数、验收和存储都钉在同一个日期坐标上，工程人员、调度器和业务方都容易理解。

【边界】不是所有传统数仓表都以日 `dt` 为主坐标。维表、主数据、拉链表、实时明细、月度账期表可能使用 `effective_date`、`snapshot_date`、`bizmonth`、`event_time` 等不同日期语义；迁移时应逐表声明日期含义，而不是机械保留日分区。

---

## 7. 传统 dt 职责到 Foundry-like 机制映射

| 传统 `dt` 承担的职责 | Foundry-like 承接机制 | 必须显式补充的模型 |
|---|---|---|
| 物理裁剪 | Hive-style partitioning、projection、文件统计、Spark/Polars reader pruning | partition columns、projection spec、file size / compaction policy |
| 业务日期 | Dataset schema 字段、Ontology property | `business_date`、`event_time`、`effective_date` 的语义定义 |
| 调度实例 | Build run、schedule run、job metadata | `run_id`、`trigger_type`、`schedule_time`、`code_version` |
| 补数边界 | 新 transaction、snapshot/rebuild、branch 修复 | `data_interval`、`is_reprocess`、`supersedes_transaction_id` |
| 幂等覆盖 | append/update/snapshot 策略、主键去重、active pointer | `business_key + business_date`、`active_transaction_id` |
| SLA 验收 | Build status、quality checks、release/proposal 状态 | `quality_status`、`ready_at`、`sla_status` |
| 生命周期 | `DELETE` transaction 改变 current view 的文件引用；retention policy 更偏物理数据和历史可读性治理 | 按 `business_date` 或 `data_interval` 的保留规则，以及 history/readability 影响评估 |
| 分区血缘 | Dataset lineage、transaction lineage、input transaction ranges | `run_input`、`run_output`、coverage lineage |
| 权限审计 | Foundry 提供资源权限、Marking 和 audit 能力；自建平台需补 branch/view/transaction 级访问审计 | branch/view/transaction access log、导出审计、权限决策快照 |

【推断】这个映射是全文核心。Foundry 并不是把 `dt` 的职责全部交给 transaction，而是把传统 `dt` 的复合职责拆到多个平台机制中；缺少显式补充模型时，迁移会只保留数据，丢失生产控制语义。

---

## 8. 与 Foundry Dataset 形态的核心区别

### 8.1 原子边界：分区 vs transaction

| 维度 | 传统 dt 分区数仓 | Foundry Dataset |
|---|---|---|
| 更新单位 | 一个或多个表分区 | 一个 Dataset transaction |
| 成功标志 | 目标分区存在且校验通过 | transaction committed，view 更新；但不代表 quality passed、ready、published 或 active |
| 覆盖语义 | 覆盖 `dt = X` 分区 | `SNAPSHOT` 替换 view，`APPEND` 添加文件，`UPDATE` 替换文件 |
| 回滚/追溯 | 依赖分区备份、快照、版本表 | 依赖 transaction/view/history |

【推断】如果一次 Foundry transaction 包含多个业务日期，平台默认只知道“Dataset 版本变化了”，不知道“哪个 `dt` 是 active、哪个 `dt` 被修复、哪个旧版本被替代”。这需要额外 manifest 或元数据表承接。

【建议】生产口径应把状态拆开：`COMMITTED_NOT_RELEASED -> QUALITY_PASSED/FAILED -> READY -> PUBLISHED -> ACTIVE_POINTER_UPDATED`。transaction commit 只证明写入和版本提交成功，不应被当作可消费成功。

### 8.2 调度坐标：业务日期实例 vs 数据新鲜度

| 维度 | 传统 dt 分区数仓 | Foundry Dataset |
|---|---|---|
| 调度主语 | 任务实例 + 业务日期 | Dataset build + 输入 transaction / logic 变化 |
| 触发逻辑 | 到时间后跑某个 `bizdate` | 输入 Dataset 更新、逻辑变更、schedule 触发 stale 资源 |
| 判断重算 | 某个日期分区需要重跑 | 输出 Dataset 是否 stale |
| 多输入对齐 | 等所有上游同一 `dt` ready | 默认是 input transaction set，需要显式对齐 business_date |

【推断】这会带来一个关键差异：Foundry 的 freshness 不等于传统数仓的 time alignment。Dataset 最新，不一定代表某个业务日期完整；某个业务日期完整，也不一定意味着整个 Dataset 需要重算。

【事实】在 branch 化构建中，输入 Dataset 可能从 requested branch 解析到 fallback branch。对调度、血缘和审计来说，不能只记录 `requested_branch`，必须记录 `resolved_branch`、`fallback_used`、fallback 顺序和实际读取到的 `view_end_transaction`。

### 8.3 增量语义：分区增量 vs transaction 增量

| 维度 | 传统 dt 分区增量 | Foundry transaction 增量 |
|---|---|---|
| 增量来源 | 新日期分区、变更日期分区、更新时间字段 | 新 committed transactions / append-only 文件变化 |
| 读取范围 | `dt in (...)` 或 `updated_at > watermark` | 自上次成功 build 后未处理的 transaction range |
| 修复方式 | 覆盖历史分区 | 新 transaction 表达修复，必要时 snapshot/fallback |
| 风险 | 分区重复、跨分区依赖遗漏 | append-only 被破坏、文件数膨胀、snapshot fallback |

【事实】官方文档说明 `APPEND` transaction 是 incremental pipelines 的基础；`UPDATE` 会破坏 append-only 要求，使下游不能继续按增量处理并需要回落到 `SNAPSHOT` batch processing。

【事实】增量失败边界不止 `UPDATE`。非 retention `DELETE`、输入 view/schema 变化、transaction limit 当前 view 中出现非 `APPEND` transaction、或 schema change 导致新的 view，都可能使增量失败、回退 snapshot 或需要人工处理。

【推断】传统数仓中“重刷某天分区”是常规操作；在 Foundry 式 transaction 模型里，“修复某天数据”更像新增一个更高版本的事实，需要通过主键去重、逻辑覆盖、manifest active pointer 或 snapshot 重算来表达。

### 8.4 查询优化：固定 dt 裁剪 vs 工作负载驱动布局

| 维度 | 传统 dt 分区数仓 | Foundry Dataset |
|---|---|---|
| 默认优化假设 | 大多数查询按日期过滤 | 查询模式不一定固定为日期 |
| 主要技术 | partition pruning、bucket、sort、index | Hive-style partitioning、projection、file compaction；Spark repartition 只是写入前执行分布/文件形态控制 |
| 设计风险 | 小分区、分区爆炸、跨日期查询低效 | 文件数过多、未建 projection、过滤列未布局优化 |

【事实】Foundry 官方提示 Hive-style partitioning 不适合高基数字段，因为每个 partition value combination 至少会写一个文件，过多文件会造成写入和读取性能问题。

【事实】Foundry Linter 也有 “incremental append dataset too many files” 规则，指出分区大小过大或过小都会影响运行时和下游读取性能，并建议检查文件数、调整分区大小或使用 projection。

【推断】传统 `dt` 分区把“按日期过滤”提前固化为平台默认优化；Foundry 的思路更像按实际过滤、join、聚合路径选择布局。好处是灵活，代价是需要更主动的物理设计和观测。

【边界】`Spark repartition` 不定义 reader 可直接 pruning 的表分区规范；它影响写出前的数据分布、文件数量和小文件风险。Hive-style partitioning 是持久文件布局；projection 是平台维护的二级访问路径；file compaction 是文件治理动作，三者不应混用。

### 8.5 生命周期：drop partition vs retention / delete transaction

| 维度 | 传统 dt 分区数仓 | Foundry Dataset |
|---|---|---|
| 清理单位 | 日期分区 | `DELETE` 改变 view 的文件引用；retention policy 影响物理数据保留和历史可读性 |
| 常见操作 | `drop partition dt < ...` | `DELETE` transaction / retention policy / archive |
| 对增量影响 | 下游通常按日期边界理解 | 删除可能影响 transaction view 和增量正确性 |

【推断】在 Foundry 中，`DELETE` transaction 与 retention policy 不应混为一谈：前者改变 current view 的文件引用，后者更偏物理保留、历史可读性和合规清理。对需要保留 N 天业务数据的场景，仍要显式记录 `data_interval` 或 `business_date`。

【事实】在 MaxCompute 等传统平台中，分区生命周期常按 `LastModifiedTime` 计算；旧 `dt` 分区被补跑或 touch 后可能改变回收时间。这说明 `dt` 生命周期也不是纯日期字面比较，需要和平台回收语义一起治理。

---

## 9. 更深远的影响

### 9.1 数据平台的“主坐标系”变化

传统离线数仓的默认主坐标是：

```text
table + dt + task_instance
```

Foundry 的默认主坐标是：

```text
dataset + branch + transaction/view + build
```

【推断】这会改变平台能力建设顺序。传统数仓优先建设调度日历、分区管理、补数、分区血缘；Foundry-like 平台应优先建设 Dataset transaction、branch/view、build lineage、staleness、permission 和 object mapping。`dt` 不消失，但它从平台底座退到业务契约层。

### 9.2 补数从“改分区”变成“产生新版本”

传统模型：

```text
rerun task(dt=2026-05-29)
  -> overwrite partition dt=2026-05-29
  -> downstream rerun same dt
```

Foundry-like 模型：

```text
rerun / rebuild
  -> commit new transaction
  -> downstream sees new input transaction
  -> decide whether snapshot, append, update, or supersede
```

【推断】补数不再天然是“覆盖某个分区”，而是“创建一个新的数据版本，并声明它覆盖哪个业务区间”。如果没有 `supersedes_transaction_id`、`business_date`、`data_interval`、`run_id` 这类元数据，下游很难判断应该追加、替换还是重算。

### 9.3 多输入任务更容易出现“时间不齐”

在传统数仓里，多输入任务通常要求：

```text
A(dt=2026-05-29) ready
B(dt=2026-05-29) ready
=> C(dt=2026-05-29) run
```

在 Foundry 里，如果只按 Dataset updated 触发，可能出现：

```text
A commits transaction for business_date=2026-05-29
B still latest at business_date=2026-05-28
=> C build triggered by freshness, but business date is mixed
```

【推断】对财务、监管、经营日报、账期结算这类强日期一致性场景，必须增加 ready barrier。Freshness scheduler 负责“数据有没有变”，partition manifest 负责“某个业务日期是否齐套”。

### 9.4 幂等从分区覆盖转向业务主键和版本指针

传统分区幂等：

```sql
insert overwrite table fact_x partition(dt='2026-05-29') ...
```

Foundry-like 幂等更可能依赖：

```text
business_key + business_date + source_version
active_transaction_id
supersedes_transaction_id
dedupe policy
```

【推断】这对事实表设计影响很大。不能假设“同一天只会有一个物理分区版本”；应该承认同一业务日期可能有多次 transaction、多个候选版本、一个 active 版本。

### 9.5 成本优化从“按日期少扫”变成“按工作负载建布局”

【推断】传统数仓常见优化口径是：查询必须带 `dt`，否则全表扫描。Foundry 不能只靠这个规训，因为 Dataset 面向更广泛的应用、对象查询、join、增量构建和流批数据。优化策略要拆成：

1. 用 Hive-style partitioning 加速稳定的低基数过滤列，如日期、区域、业务线。
2. 用 projection 优化高频过滤、join、聚合路径。
3. 用 compaction 和文件数规则治理 incremental append 的小文件问题。
4. 在 Ontology 层为对象访问路径建立索引或派生对象集。

不同引擎的成本模型要分开看：

| 平台/机制 | 成本重点 | 设计检查 |
|---|---|---|
| BigQuery partition / cluster | on-demand `bytes processed`，cluster block pruning 会让预估字节更像上界 | partition filter 是否可裁剪、cluster 列顺序、过细 partition 成本 |
| Snowflake micro-partition / clustering | warehouse credits、serverless clustering credits、运行时间和存储放大 | 谓词是否命中 clustering key、micro-partition overlap/depth、reclustering 成本 |
| Iceberg | metadata planning、manifest list/file 扫描、数据文件扫描、小文件和 manifest rewrite | partition transform、sort order、目标文件大小、snapshot expiration、engine support |
| Foundry Hive-style / projection | 文件数、transaction metadata、projection lag、额外存储和维护成本 | 低基数过滤列用 Hive-style；高频 filter/join/aggregate 路径可用 projection |
| Spark 文件布局 | task 数、shuffle、写出文件数量、compaction 成本 | `repartitionByRange`/排序是否控制小文件，不把 compute partition 当表分区 |

### 9.6 组织协作从“跑批交付”走向“数据资产版本协作”

【推断】传统团队常围绕“今天哪些分区完成了”协作；Foundry-like 团队会更多围绕“哪个 Dataset 版本、哪个 branch、哪个 transform logic、哪个 Ontology mapping、哪个 application view”协作。这更适合工程化和应用化，但会降低传统离线生产人员对系统状态的直觉可见性。因此需要新的运维界面，直接展示业务日期与 transaction 的映射。

### 9.7 高风险案例矩阵

| 风险案例 | 传统 dt 模型如何定位 | Foundry-like 模型的风险 | 建议补强 |
|---|---|---|---|
| 补数覆盖历史日期 | 看 `dt=2026-05-01` 是否重刷 | 只看到新 transaction，不知道覆盖哪个业务日期 | partition manifest + `supersedes_transaction_id` |
| 迟到数据跨日期修正 | 重刷受影响日期分区 | 一次 transaction 可能影响多个 business_date | coverage lineage：transaction -> business date range |
| view 指针漂移 | 固定分区路径或快照 | 审计时 current view 已不同于当时 view | 审计记录 `requested_branch`、`resolved_branch`、`requested_pointer`、`resolved_transaction_id`、`view_end_transaction`、`fallback_used` |
| 多输入时间不齐 | 同周期实例依赖拦截 | A 新 B 旧也可能触发 freshness build | ready barrier + input business_date correlation |
| 质量发布解耦 | 分区校验后标记 ready | transaction 已提交但质量未通过 | `quality_status` 与 `ready_status` 分离 |
| 权限绕行 | 表/分区权限相对直接 | 历史 transaction、branch、派生 Dataset、preview/query/export/API 可能绕过统一口径 | 统一鉴权；记录角色、Marking/Organization、权限决策快照和 denied access |
| 回滚业务解释不足 | 回滚某分区可见 | 回滚 transaction 不等于业务状态回滚 | rollback impact report，列出 affected business dates |

---

## 10. 自建或迁移建议

### 10.1 不要把 dt 做成唯一平台主键

【建议】底座仍应以 Dataset transaction / snapshot / branch 为版本坐标。这样才能支持分支实验、版本追溯、stream/archive、跨应用 lineage 和权限传播。

### 10.2 但必须把业务日期做成显式契约

建议关键 Dataset 至少包含或关联以下字段：

| 字段 | 用途 |
|---|---|
| `business_date` | 传统 `dt` 语义，表示数据所属业务日期 |
| `data_interval_start` / `data_interval_end` | 比单日更通用，支持小时、周、月、滚动窗口 |
| `run_id` | 关联调度或重算实例 |
| `source_watermark` | 表示源数据消费到哪里 |
| `transaction_id` | 关联 Foundry-style Dataset transaction |
| `is_reprocess` | 标记是否补数/修复 |
| `supersedes_transaction_id` | 表示替代哪个旧版本 |

### 10.3 对强账期链路引入 business partition manifest

```text
business_partition_manifest
  dataset_id
  branch_name
  partition_key              # business_date / bizmonth / snapshot_date
  partition_value            # 2026-05-29 或 2026-05
  data_interval_start
  data_interval_end
  view_end_transaction
  active_view_pointer
  active_transaction_id      # 若 active view 可简化为单 transaction
  producing_run_id
  source_watermark
  event_time_min
  event_time_max
  row_count
  file_count
  quality_status
  ready_status               # provisional / ready / superseded / failed
  supersedes_transaction_id
  created_at
  published_at
```

【建议】这里的 manifest 是业务生产 manifest，不是 Iceberg `manifest list/manifest file`。它不替代 Dataset transaction，而是把业务分区语义映射到版本系统。它回答“哪个业务日期当前生效”，Dataset transaction 回答“这个版本由哪些文件和上游版本构成”。

### 10.4 区分四类分区

| 分区类型 | 作用 | 是否等同 dt |
|---|---|---|
| 业务分区 | 业务日期、账期、数据区间 | 可能等同 |
| 存储分区 | 文件路径和 pruning | 不一定 |
| 计算分区 | Spark/Flink 并行度 | 不是 |
| 流分区 | 吞吐、ordering、并行消费 | 不是 |

【建议】平台文档和 UI 必须避免把这四类“partition”混用。很多迁移事故本质是把计算分区或文件分区误当业务分区。

### 10.5 为不同场景选择不同模型

| 场景 | 推荐模型 |
|---|---|
| T+1 报表、财务、监管、账期 | 保留 `business_date` + business partition manifest + ready barrier |
| 实时监控、事件流、设备状态 | 以 transaction/stream/object latest view 为主，`event_time` 作为属性 |
| 大表按日期过滤查询 | 多引擎开放读取优先 Hive-style partitioning；Foundry 内部高频路径可考虑 projection |
| 多维交互分析 | 以 projection / clustering / materialized derived Dataset 优化主查询路径 |
| Ontology 应用 | Dataset 承载数据版本，Ontology 承载对象和动作，业务时间作为 object property |
| ad hoc 分析 | 可弱化 ready barrier，但不能弱化访问审计、schema version 和 resolved view 记录 |

---

## 11. 与传统数仓迁移的判断标准

| 问题 | 如果答案是“是” | 迁移含义 |
|---|---|---|
| 下游是否按某个 `dt` 验收？ | 是 | 需要保留 business_date ready 状态 |
| 是否存在历史分区补数？ | 是 | 需要 run -> transaction -> business_date 映射 |
| 是否要求同一账期多输入齐套？ | 是 | 需要 ready barrier，不能只靠 Dataset updated |
| 查询是否强制按日期过滤？ | 是 | 需要 Hive-style partitioning / projection |
| 是否需要同一日期多版本审计？ | 是 | 需要 active/superseded transaction model |
| 是否主要消费最新对象状态？ | 是 | 可以弱化 dt，强化 Ontology/object latest view |
| 是否存在敏感数据传播或 Marking removal？ | 是 | 需要 transaction-level requirements、unmarking approval、downstream rebuild/resnapshot 和访问审计 |
| 是否需要关账冻结或监管留痕？ | 是 | 需要 release pointer、固定 view、质量证据、不可变审计和重开账期规程 |
| 布局字段是否高基数或写入频繁？ | 是 | 不应直接做 Hive-style 目录分区；先评估 projection、clustering、sort、compaction 和文件数阈值 |

【推断】如果一个系统的主要心智是“每天产出一个分区”，迁移到 Foundry-like Dataset 时最容易丢的是生产语义，而不是数据本身。数据可以进 Dataset，但 `dt` 背后的 run、ready、overwrite、SLA、backfill、retention 都必须重新落模。

---

## 12. 综合模型：双坐标与最小元数据契约

### 12.1 双坐标

【建议】自建 Foundry-like Dataset 模型时，应把同一份数据同时放进两套坐标里：

| 坐标 | 回答的问题 | 典型字段 |
|---|---|---|
| 版本证据坐标 | 这份数据是哪一次文件集合变化？可否复现？ | `dataset_id`, `branch_name`, `transaction_id`, `view_end_transaction`, `schema_version` |
| 业务生产坐标 | 这份数据代表哪个业务日期/区间？是否可消费？ | `business_date`, `data_interval_start/end`, `producer_run_id`, `quality_status`, `ready_status`, `release_pointer` |

【推断】这个双坐标是迁移的关键：transaction/view 替代不了 `dt` 的业务解释，`business_date` 也替代不了 transaction 的版本证据。

生产发布状态建议拆成显式状态机：

```text
OPEN / COMMITTED / ABORTED
  -> QUALITY_PASSED / QUALITY_FAILED
  -> READY
  -> PUBLISHED
  -> ACTIVE_VIEW_POINTER_UPDATED
```

`COMMITTED` 只说明 Dataset 版本提交成功；`ACTIVE_VIEW_POINTER_UPDATED` 才说明生产消费指针已经切到该可消费 view。

### 12.2 最小元数据闭环

```text
run_ledger
  -> run_input_version
  -> run_output_transaction
  -> partition_manifest
  -> quality_evidence
  -> sla_readiness
  -> active_view_pointer
  -> access_audit
```

【建议】最低生产控制面至少要落地 `run_ledger`、`business_partition_manifest`、`quality_evidence`、`active_view_pointer`。没有这些表，平台只能证明“数据写入成功”，不能证明“某个业务日期已经正确、完整地发布”。

【建议】合规审计闭环还必须包含 `run_input_version`、`run_output_transaction`、`sla_readiness` 和 `access_audit`。否则无法解释实际读取的 branch/view、输入 transaction range、ready 判定、权限决策和导出行为。

### 12.3 四个必须优先实现的模式

| 模式 | 解决的问题 | 最小实现 |
|---|---|---|
| Ready Barrier | 多输入同账期不齐 | build 前检查所有上游 `business_date` 和 `ready_status` |
| Active View / Release Pointer | branch head 不等于生产可消费版本 | 生产消费者默认读 `pointer_name='prod'`，并记录 resolved view/transaction |
| Supersedes Transaction | 补数/修复后的替代关系不可见 | 记录 `new_transaction_id -> supersedes_transaction_id` 与 scope |
| Coverage Lineage | 普通血缘不说明业务覆盖范围 | 记录 input/output transaction range 与 business date range |

### 12.4 场景决策

| 场景 | 决策 |
|---|---|
| 财务、监管、对账、T+1 经营报表 | 强制双坐标；`business_date`、business manifest、ready barrier、release pointer 都必须有 |
| T+1 报表 | 必须有 `business_date ready`、补数覆盖记录、上游同账期 barrier 和下游重算范围 |
| 财务账期 | 必须有 `finance_close` 或类似 release pointer、关账冻结、重开账期审批和 supersede 链 |
| 监管报送 | 必须记录 resolved transaction/view、schema version、质量证据、权限快照和不可变审计 |
| 对账链路 | 必须记录双方账期、输入 transaction range、差异处理状态和 active/published 版本 |
| 大表按日期过滤分析 | 保留日期 layout partition 或 projection，但把它定义为性能优化，不是版本主键 |
| 实时事件与 latest state | 可弱化 `dt`，但必须保留 `event_time`、watermark、resolved transaction/view |
| Ontology 应用 | Dataset 负责版本证据；Ontology 属性承载业务时间；应用读 active pointer 或固定 view |
| ad hoc 分析 | 可不建完整 ready barrier，但仍需记录 processing date、schema version 和访问审计 |

布局决策需要单独过一组工程检查：字段基数、查询选择性、每分区数据量、写入频率、目标文件大小、文件数上限、projection lag、存储放大、clustering/reclustering 成本、以及目标查询引擎是否支持对应布局。

---

## 13. 专家复审结论

| 专家视角 | 复审结论 | 已吸收的必修项 |
|---|---|---|
| Foundry 平台架构 | 有条件通过 | branch fallback、schema-on-view、append-only 失败条件、Foundry `View` 与 dataset view 术语边界、`DELETE` 与 retention 区分 |
| 传统数仓/调度 | 有条件通过 | `$cyctime` 理论调度时间、周/月补数据边界、MaxCompute overwrite partition、T+1/账期/监管/对账准入条件 |
| 湖仓/查询引擎 | 有条件通过 | Iceberg/BigQuery/Snowflake 边界、Spark repartition 与 layout partition 区分、成本模型、business manifest 与 Iceberg manifest 区分 |
| 治理/血缘/审计 | 有条件通过 | committed/quality/ready/published/active 状态机、完整 manifest 字段、权限与 Marking 审计、证据边界 |

【结论】复审后主线保持不变：`dt` 与 transaction/view 不同层，迁移应采用双坐标。本文已把四位专家的必修项纳入综合结论；可选项中涉及真实 Foundry 租户行为、具体计费阈值和监管操作规程的内容，保留为后续 follow-up。

---

## 14. 证据边界与待验证

1. 【证据边界】Foundry 公开文档没有披露 run lineage、quality evidence、access audit、transaction requirements 的内部表结构；本文的 `run_ledger`、`quality_evidence`、`access_audit` 等表是自建平台契约建议，不是 Foundry 内部实现复刻。
2. 【证据边界】公开资料未证明跨 Dataset 多输出 build 的原子提交；设计上不应把一次 run 的多个 output transactions 当成不可分割事务。
3. 【待验证】branch fallback 在实际 UI、API、lineage 展示中的可见性，以及不同语言 SDK 对 transaction range、schema change、retention delete 的处理，需要在真实环境复核。
4. 【待验证】Foundry projection、Hive-style partition、Iceberg hidden partition、BigQuery cluster、Snowflake clustering 的实际收益要结合具体数据量、查询模式和计费模型量化。
5. 【待验证】Marking removal 后的 downstream incremental rebuild / resnapshot 策略、财务关账冻结、监管不可变审计和重开账期规程，需要单独形成实施规范。

---

## 15. 参考资料

- Palantir Foundry Datasets: https://www.palantir.com/docs/foundry/data-integration/datasets
- Palantir Foundry Branching: https://www.palantir.com/docs/foundry/data-integration/branching
- Palantir Foundry Views: https://www.palantir.com/docs/foundry/data-integration/views
- Palantir Pipeline Builder fallback branches: https://www.palantir.com/docs/foundry/pipeline-builder/branches-fallback-branches/
- Palantir Foundry Hive-style partitioning: https://www.palantir.com/docs/foundry/optimizing-pipelines/hive-style-partitioning
- Palantir Foundry Dataset projections: https://www.palantir.com/docs/foundry/optimizing-pipelines/projections-overview
- Palantir Foundry Linter rules: https://www.palantir.com/docs/foundry/linter/rules
- Palantir Foundry Streams: https://www.palantir.com/docs/foundry/data-integration/streams
- Palantir Foundry Incremental pipelines overview: https://www.palantir.com/docs/foundry/building-pipelines/incremental-overview
- Palantir Foundry Python incremental transforms usage: https://www.palantir.com/docs/foundry/transforms-python/incremental-usage/
- Palantir Foundry Java incremental transforms: https://www.palantir.com/docs/foundry/transforms-java/incremental-transforms
- Palantir Incremental transaction limits: https://www.palantir.com/docs/foundry/transforms-python-spark/incremental-transaction-limits
- 阿里云 DataWorks 调度参数格式: https://www.alibabacloud.com/help/en/dataworks/user-guide/supported-formats-of-scheduling-parameters
- 阿里云 DataWorks 补数据: https://www.alibabacloud.com/help/en/dataworks/data-backfilling
- MaxCompute insert overwrite static partition: https://www.alibabacloud.com/help/en/maxcompute/user-guide/insert-or-update-data-into-a-table-or-a-static-partition
- MaxCompute partition operation: https://www.alibabacloud.com/help/en/maxcompute/user-guide/partition-operation
- Apache Hive DDL partition example: https://hive.apache.org/docs/latest/language/languagemanual-ddl/
- Apache Hive DML insert overwrite partition: https://hive.apache.org/docs/latest/language/languagemanual-dml/
- Apache Iceberg partitioning: https://iceberg.apache.org/docs/latest/partitioning/
- BigQuery partitioned tables: https://docs.cloud.google.com/bigquery/docs/partitioned-tables
- BigQuery clustered tables: https://docs.cloud.google.com/bigquery/docs/clustered-tables
- Snowflake micro-partitions and data clustering: https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions
- Snowflake clustering keys: https://docs.snowflake.com/en/user-guide/tables-clustering-keys
- 本仓库相关文档：`docs/synthesis/dataworks-vs-palantir-integration.md`
- 本仓库相关文档：`docs/raw/27-incremental-scheduling-transaction.md`
- 本仓库本轮 raw 文档：`docs/raw/39-foundry-dataset-transaction-view-evidence.md`
- 本仓库本轮 raw 文档：`docs/raw/40-traditional-dt-partition-production-semantics.md`
- 本仓库本轮 raw 文档：`docs/raw/41-lakehouse-layout-partition-cost-model.md`
- 本仓库本轮 raw 文档：`docs/raw/42-governance-lineage-audit-contracts.md`
- 本仓库本轮 raw 文档：`docs/raw/43-migration-risk-dual-coordinate-patterns.md`
