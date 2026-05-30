# Palantir Dataset 无默认 dt 分区模型的架构影响

**日期：** 2026-05-30  
**类型：** 技术调研  
**覆盖方向：** Foundry Dataset / dt 分区 / 传统离线数仓 / Dataset Transaction / 增量计算 / 调度与补数

---

## 1. 总结与洞察

1. 【事实】Foundry Dataset 不是“完全没有分区”。官方支持 Spark/Hive-style partitioning、projection、Spark repartition、stream partitions 等优化或吞吐概念；但 Dataset 的基础语义不是 `dt=yyyy-mm-dd` 分区，而是 `Dataset + branch + transaction/view`。
2. 【推断】传统离线数仓把 `dt` 同时用作物理裁剪、业务日期、调度实例、补数边界、SLA 口径和生命周期单位；Foundry 则把这些职责拆开：物理布局由文件/partition/projection 解决，版本由 transaction 解决，业务日期需要作为 schema 字段、Ontology 属性或 partition manifest 显式建模。
3. 【推断】这个差异的深层影响不是“少了一个分区字段”，而是数据平台的主坐标系从“表 + 分区日期”迁移到“数据资产 + 版本”。这会改变调度、补数、血缘、审计、幂等、成本优化和业务对齐方式。
4. 【推断】Foundry 的模型更适合持续更新、分支协作、版本追溯、流批统一和对象化应用；传统 `dt` 分区模型更适合强 T+1、账期、监管报送、分区级补数和按日期验收的离线生产链路。
5. 【建议】自建或迁移时不要把 `dt` 分区直接丢掉。应把 `business_date` / `data_interval` / `run_id` / `active_transaction_id` 做成显式数据契约，并为需要账期一致性的链路增加 partition manifest 或 ready barrier。

---

## 2. 先澄清：不是没有分区，而是没有默认 dt 主坐标

### 2.1 Foundry Dataset 的一阶语义

【事实】Foundry Dataset 是围绕文件集合构建的数据资产抽象。官方文档定义 Dataset 是 backing filesystem 上文件集合的 wrapper，并提供权限、schema、版本控制和随时间更新能力。Dataset 通过 transaction 改变文件集合，transaction 类型包括 `SNAPSHOT`、`APPEND`、`UPDATE`、`DELETE`。

【事实】Dataset view 是某个 branch 在某个时间点的有效文件集合。它从最近的 `SNAPSHOT` 开始，再按后续 `APPEND`、`UPDATE`、`DELETE` transaction 计算出当前 view。

【推断】因此，Foundry Dataset 的默认主坐标不是：

```text
table_name + dt
```

而是：

```text
dataset_rid/path + branch + transaction/view
```

### 2.2 Foundry 仍然有分区和布局优化

【事实】Foundry 官方支持 Hive-style partitioning。其机制是在 Spark 写出 Dataset 时，根据指定 partition columns 把不同取值组合写成不同文件路径，并在 transaction metadata 里记录 partition columns。Spark、Polars 等 reader 在这些列上过滤时可以利用 metadata 和路径缩小读取文件范围。

【事实】Foundry 也支持 dataset projections。projection 通常面向单一查询模式，优化过滤、join 或聚合；官方还明确指出 incremental pipelines 可能造成很高文件数，projection 可以用于透明 compaction 和加速读取。

【事实】Foundry stream 也有 partitions，但官方强调这是为了吞吐和并行处理，读写行为对生产者/消费者表现得像单分区。这和离线数仓 `dt` 业务分区不是同一层概念。

【推断】所以更准确的表述是：Foundry Dataset 没有把 `dt` 作为所有批处理数据的默认业务分区、调度分区和生命周期分区；分区只是可选的数据布局优化之一。

---

## 3. 传统 dt 分区模型到底承担了什么

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

---

## 4. 与 Foundry Dataset 形态的核心区别

### 4.1 原子边界：分区 vs transaction

| 维度 | 传统 dt 分区数仓 | Foundry Dataset |
|---|---|---|
| 更新单位 | 一个或多个表分区 | 一个 Dataset transaction |
| 成功标志 | 目标分区存在且校验通过 | transaction committed，view 更新 |
| 覆盖语义 | 覆盖 `dt = X` 分区 | `SNAPSHOT` 替换 view，`APPEND` 添加文件，`UPDATE` 替换文件 |
| 回滚/追溯 | 依赖分区备份、快照、版本表 | 依赖 transaction/view/history |

【推断】如果一次 Foundry transaction 包含多个业务日期，平台默认只知道“Dataset 版本变化了”，不知道“哪个 `dt` 是 active、哪个 `dt` 被修复、哪个旧版本被替代”。这需要额外 manifest 或元数据表承接。

### 4.2 调度坐标：业务日期实例 vs 数据新鲜度

| 维度 | 传统 dt 分区数仓 | Foundry Dataset |
|---|---|---|
| 调度主语 | 任务实例 + 业务日期 | Dataset build + 输入 transaction / logic 变化 |
| 触发逻辑 | 到时间后跑某个 `bizdate` | 输入 Dataset 更新、逻辑变更、schedule 触发 stale 资源 |
| 判断重算 | 某个日期分区需要重跑 | 输出 Dataset 是否 stale |
| 多输入对齐 | 等所有上游同一 `dt` ready | 默认是 input transaction set，需要显式对齐 business_date |

【推断】这会带来一个关键差异：Foundry 的 freshness 不等于传统数仓的 time alignment。Dataset 最新，不一定代表某个业务日期完整；某个业务日期完整，也不一定意味着整个 Dataset 需要重算。

### 4.3 增量语义：分区增量 vs transaction 增量

| 维度 | 传统 dt 分区增量 | Foundry transaction 增量 |
|---|---|---|
| 增量来源 | 新日期分区、变更日期分区、更新时间字段 | 新 committed transactions / append-only 文件变化 |
| 读取范围 | `dt in (...)` 或 `updated_at > watermark` | 自上次成功 build 后未处理的 transaction range |
| 修复方式 | 覆盖历史分区 | 新 transaction 表达修复，必要时 snapshot/fallback |
| 风险 | 分区重复、跨分区依赖遗漏 | append-only 被破坏、文件数膨胀、snapshot fallback |

【事实】官方文档说明 `APPEND` transaction 是 incremental pipelines 的基础；`UPDATE` 会破坏 append-only 要求，使下游不能继续按增量处理并需要回落到 `SNAPSHOT` batch processing。

【推断】传统数仓中“重刷某天分区”是常规操作；在 Foundry 式 transaction 模型里，“修复某天数据”更像新增一个更高版本的事实，需要通过主键去重、逻辑覆盖、manifest active pointer 或 snapshot 重算来表达。

### 4.4 查询优化：固定 dt 裁剪 vs 工作负载驱动布局

| 维度 | 传统 dt 分区数仓 | Foundry Dataset |
|---|---|---|
| 默认优化假设 | 大多数查询按日期过滤 | 查询模式不一定固定为日期 |
| 主要技术 | partition pruning、bucket、sort、index | Hive-style partitioning、projection、Spark repartition、file compaction |
| 设计风险 | 小分区、分区爆炸、跨日期查询低效 | 文件数过多、未建 projection、过滤列未布局优化 |

【事实】Foundry 官方提示 Hive-style partitioning 不适合高基数字段，因为每个 partition value combination 至少会写一个文件，过多文件会造成写入和读取性能问题。

【事实】Foundry Linter 也有 “incremental append dataset too many files” 规则，指出分区大小过大或过小都会影响运行时和下游读取性能，并建议检查文件数、调整分区大小或使用 projection。

【推断】传统 `dt` 分区把“按日期过滤”提前固化为平台默认优化；Foundry 的思路更像按实际过滤、join、聚合路径选择布局。好处是灵活，代价是需要更主动的物理设计和观测。

### 4.5 生命周期：drop partition vs retention / delete transaction

| 维度 | 传统 dt 分区数仓 | Foundry Dataset |
|---|---|---|
| 清理单位 | 日期分区 | 文件引用、Dataset retention、DELETE transaction |
| 常见操作 | `drop partition dt < ...` | retention policy / DELETE 改变 Dataset view |
| 对增量影响 | 下游通常按日期边界理解 | 删除可能影响 transaction view 和增量正确性 |

【推断】在 Foundry 中，保留策略不应只按物理文件删除理解，还要考虑 transaction/view 历史和下游增量消费位点。对需要保留 N 天业务数据的场景，仍要显式记录 `data_interval` 或 `business_date`。

---

## 5. 更深远的影响

### 5.1 数据平台的“主坐标系”变化

传统离线数仓的默认主坐标是：

```text
table + dt + task_instance
```

Foundry 的默认主坐标是：

```text
dataset + branch + transaction/view + build
```

【推断】这会改变平台能力建设顺序。传统数仓优先建设调度日历、分区管理、补数、分区血缘；Foundry-like 平台应优先建设 Dataset transaction、branch/view、build lineage、staleness、permission 和 object mapping。`dt` 不消失，但它从平台底座退到业务契约层。

### 5.2 补数从“改分区”变成“产生新版本”

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

### 5.3 多输入任务更容易出现“时间不齐”

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

### 5.4 幂等从分区覆盖转向业务主键和版本指针

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

### 5.5 成本优化从“按日期少扫”变成“按工作负载建布局”

【推断】传统数仓常见优化口径是：查询必须带 `dt`，否则全表扫描。Foundry 不能只靠这个规训，因为 Dataset 面向更广泛的应用、对象查询、join、增量构建和流批数据。优化策略要拆成：

1. 用 Hive-style partitioning 加速稳定的低基数过滤列，如日期、区域、业务线。
2. 用 projection 优化高频过滤、join、聚合路径。
3. 用 compaction 和文件数规则治理 incremental append 的小文件问题。
4. 在 Ontology 层为对象访问路径建立索引或派生对象集。

### 5.6 组织协作从“跑批交付”走向“数据资产版本协作”

【推断】传统团队常围绕“今天哪些分区完成了”协作；Foundry-like 团队会更多围绕“哪个 Dataset 版本、哪个 branch、哪个 transform logic、哪个 Ontology mapping、哪个 application view”协作。这更适合工程化和应用化，但会降低传统离线生产人员对系统状态的直觉可见性。因此需要新的运维界面，直接展示业务日期与 transaction 的映射。

---

## 6. 自建或迁移建议

### 6.1 不要把 dt 做成唯一平台主键

【建议】底座仍应以 Dataset transaction / snapshot / branch 为版本坐标。这样才能支持分支实验、版本追溯、stream/archive、跨应用 lineage 和权限传播。

### 6.2 但必须把业务日期做成显式契约

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

### 6.3 对强账期链路引入 partition manifest

```text
dataset_partition_manifest
  dataset_id
  partition_key              # dt=2026-05-29 或 interval=[...)
  active_transaction_id
  producing_run_id
  status                     # ready / provisional / superseded / failed
  version
  row_count
  data_quality_status
  created_at
```

【建议】manifest 不替代 Dataset transaction，而是把业务分区语义映射到版本系统。它回答“哪个业务日期当前生效”，Dataset transaction 回答“这个版本由哪些文件和上游版本构成”。

### 6.4 区分四类分区

| 分区类型 | 作用 | 是否等同 dt |
|---|---|---|
| 业务分区 | 业务日期、账期、数据区间 | 可能等同 |
| 存储分区 | 文件路径和 pruning | 不一定 |
| 计算分区 | Spark/Flink 并行度 | 不是 |
| 流分区 | 吞吐、ordering、并行消费 | 不是 |

【建议】平台文档和 UI 必须避免把这四类“partition”混用。很多迁移事故本质是把计算分区或文件分区误当业务分区。

### 6.5 为不同场景选择不同模型

| 场景 | 推荐模型 |
|---|---|
| T+1 报表、财务、监管、账期 | 保留 `business_date` + partition manifest + ready barrier |
| 实时监控、事件流、设备状态 | 以 transaction/stream/object latest view 为主，`event_time` 作为属性 |
| 大表按日期过滤查询 | 使用 Hive-style partitioning 或 projection 优化 date filter |
| 多维交互分析 | 以 projection / clustering / materialized derived Dataset 优化主查询路径 |
| Ontology 应用 | Dataset 承载数据版本，Ontology 承载对象和动作，业务时间作为 object property |

---

## 7. 与传统数仓迁移的判断标准

| 问题 | 如果答案是“是” | 迁移含义 |
|---|---|---|
| 下游是否按某个 `dt` 验收？ | 是 | 需要保留 business_date ready 状态 |
| 是否存在历史分区补数？ | 是 | 需要 run -> transaction -> business_date 映射 |
| 是否要求同一账期多输入齐套？ | 是 | 需要 ready barrier，不能只靠 Dataset updated |
| 查询是否强制按日期过滤？ | 是 | 需要 Hive-style partitioning / projection |
| 是否需要同一日期多版本审计？ | 是 | 需要 active/superseded transaction model |
| 是否主要消费最新对象状态？ | 是 | 可以弱化 dt，强化 Ontology/object latest view |

【推断】如果一个系统的主要心智是“每天产出一个分区”，迁移到 Foundry-like Dataset 时最容易丢的是生产语义，而不是数据本身。数据可以进 Dataset，但 `dt` 背后的 run、ready、overwrite、SLA、backfill、retention 都必须重新落模。

---

## 8. 参考资料

- Palantir Foundry Datasets: https://www.palantir.com/docs/foundry/data-integration/datasets
- Palantir Foundry Hive-style partitioning: https://www.palantir.com/docs/foundry/optimizing-pipelines/hive-style-partitioning
- Palantir Foundry Dataset projections: https://www.palantir.com/docs/foundry/optimizing-pipelines/projections-overview
- Palantir Foundry Linter rules: https://www.palantir.com/docs/foundry/linter/rules
- Palantir Foundry Streams: https://www.palantir.com/docs/foundry/data-integration/streams
- Palantir Foundry Incremental pipelines overview: https://www.palantir.com/docs/foundry/building-pipelines/incremental-overview
- Palantir Foundry Python incremental transforms usage: https://www.palantir.com/docs/foundry/transforms-python/incremental-usage/
- Apache Hive DDL partition example: https://hive.apache.org/docs/latest/language/languagemanual-ddl/
- BigQuery partitioned tables: https://docs.cloud.google.com/bigquery/docs/partitioned-tables
- Snowflake micro-partitions and data clustering: https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions
- 本仓库相关文档：`docs/synthesis/dataworks-vs-palantir-integration.md`
- 本仓库相关文档：`docs/raw/27-incremental-scheduling-transaction.md`
