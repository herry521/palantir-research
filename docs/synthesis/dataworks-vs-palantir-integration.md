# DataWorks 与 Palantir Data Integration 差异研究

**日期：** 2026-05-30  
**类型：** 产品与架构对比调研  
**覆盖方向：** DataWorks 调度时间语义 / Palantir Foundry Data Integration / Dataset Transaction / 调度与增量 / 融合边界  
**可信度标签：** 【事实】=官方文档可直接确认；【推断】=基于官方能力组合出的架构判断；【建议】=面向后续集成或自研平台的设计建议。

---

## 一、核心结论

1. 【事实】DataWorks 把“业务日期 / 数据时间”和“调度时间”做成调度系统的一等概念。`$bizdate` 表示任务数据时间，默认比调度时间早一天；`$cyctime` 表示任务调度时间。这是 DataWorks 离线数仓、T+1 分区生产、补数据和跨周期依赖的基础语义。
2. 【事实】Palantir Foundry Data Integration 的核心抽象是 Dataset、Transaction、Build、Schedule、Stream 和 Ontology，而不是 DataWorks 式的全局业务日期。Foundry schedule 支持时间触发、数据更新触发、逻辑更新触发及组合触发，但官方文档没有提供等价于 `$bizdate` 的平台级业务日期概念。
3. 【推断】二者的根本差异不是“有没有调度器”，而是调度器的判重对象不同：DataWorks 更偏“任务实例 + 业务日期 / 调度时间 + 业务分区”；Foundry 更偏“输出 Dataset 是否因输入 transaction 或 JobSpec 逻辑变化而 stale”。freshness 机制与 time alignment 机制不是天然互斥，但如果把 freshness 当作业务日期完成信号，就会发生语义冲突。
4. 【建议】二者可以相融，但不能概念等价迁移。若从 DataWorks 输出数据给 Foundry，应把 `business_date`、`schedule_time`、`data_interval_start`、`data_interval_end`、`source_watermark`、`dataworks_instance_id` 等字段写入数据或元数据契约，避免业务日期只存在于 DataWorks 调度上下文中。
5. 【决策】业务周期对齐调度与 freshness 调度必须完全拆开：前者归属 `Run Identity`，负责 `business_date/data_interval`、补数、重跑和实例幂等；后者归属 `Data Version Identity`，负责 staleness、输入版本变化、逻辑版本变化和增量传播。

---

## 二、时间模型差异

### 2.1 DataWorks：业务日期是调度系统内置语义

DataWorks 官方调度参数文档将 `$bizdate` 定义为任务的数据时间，格式为 `yyyymmdd`；默认情况下，任务数据时间比任务调度时间早一天。`$cyctime` 表示任务调度时间，格式为 `yyyymmddhh24miss`。这说明 DataWorks 的调度参数不是单纯字符串替换，而是围绕“数据所属日期”和“任务理论触发日期”建立的一套调度语义。【事实】

在典型 T+1 数仓中，这个模型非常自然：

```text
调度时间：2026-05-30 02:00:00
业务日期：2026-05-29
产出分区：dt = '2026-05-29'
```

这套语义会影响：

- 分区读写：读取和产出哪个 `dt`。
- 实例依赖：今天的任务实例依赖昨天、今天或上游某周期实例。
- 补数据：补的是某个业务日期或日期区间，而不是简单重跑当前时间。
- 审计口径：任务实际运行晚了，不应该改变它处理的数据日期。

### 2.2 Palantir：时间更多是触发条件、事务时间或业务字段

Foundry Scheduling 官方文档描述的 schedule 能力包括按指定时间运行、数据更新后运行、逻辑更新后运行，以及组合这些条件。Foundry Trigger Reference 还说明 time trigger 是满足 cron 表达式的墙钟时间，event trigger 可以由数据更新、job 成功、schedule 成功等事件满足。【事实】

Foundry Datasets 文档把 Dataset Transaction 描述为数据集随时间变化的原子修改，事务类型包括 `SNAPSHOT`、`APPEND`、`UPDATE` 和 `DELETE`。其中 `SNAPSHOT` 是批处理基础，`APPEND` 是增量流水线基础，`UPDATE` 会破坏 append-only 增量假设并导致下游不能按增量处理。【事实】

因此，Foundry 不是没有时间，而是时间分散在不同层次：

| 时间类型 | Foundry 中的承载位置 | 是否等价于 DataWorks 业务日期 |
|---|---|---|
| 调度触发时间 | Schedule time trigger / cron | 否，只表示何时触发 build |
| 数据更新时间 | Dataset transaction commit | 否，只表示数据集版本变化 |
| 事件时间 | Stream / streaming pipeline / 业务字段 | 部分相关，但需要业务建模 |
| 业务日期 / 账期 | Dataset 字段、Transform 参数、Ontology 属性 | 可以表达，但不是平台默认语义 |

---

## 三、产品与架构差异

| 维度 | DataWorks | Palantir Foundry Data Integration |
|---|---|---|
| 核心定位 | 云上大数据开发、集成、调度、治理平台 | 企业数据接入、版本化 Dataset、Pipeline、Ontology 和操作应用平台 |
| 主调度对象 | 任务 / 节点 / 周期实例 | Dataset graph / build / schedule |
| 时间语义 | 业务日期、调度时间、实际运行时间区分清楚 | 无全局业务日期；以触发时间、事务时间、事件时间和业务字段表达 |
| 批处理模型 | 天然适配 T+1、分区、补数据、跨周期依赖 | 适配 snapshot / incremental build；业务日期需显式建模 |
| 增量模型 | 常见做法是按业务日期、分区、更新时间或同步位点处理 | 以 Dataset Transaction 类型和 append-only 约束为核心 |
| 血缘模型 | 节点 DAG、表 / 分区依赖、任务实例状态 | Dataset lineage、Input / Output contract、transaction、build 状态 |
| 业务语义层 | 主要依赖数仓模型、数据地图、数据服务 | Ontology 是核心能力，可把 Dataset 映射成业务对象、关系和动作 |
| 相融难点 | DataWorks 的调度上下文容易留在平台内部 | Foundry 不会天然理解 `$bizdate`，必须通过字段和契约携带 |

---

## 四、为什么 Palantir 中看不到 DataWorks 业务时间概念

这个差异是由平台出发点决定的。【推断】

DataWorks 的设计重心更接近中国互联网和企业数仓常见的离线生产链路：每天固定时间生成当天实例，实例处理某个业务日期的数据，结果进入对应分区。调度器必须理解“今天跑昨天”“周任务跑上周”“月任务跑上月”这类关系，否则补数、依赖和 SLA 都会混乱。

Foundry 的设计重心是把数据接入后变成版本化 Dataset，再通过 pipeline、schedule、lineage、permissions、Ontology 和应用形成闭环。它关心的是“哪个 Dataset 版本被哪个 build 生产、由哪些输入 transaction 触发、影响哪些下游对象”。业务日期可以存在，但它通常是 Dataset schema 或 Ontology 属性的一部分，而不是调度系统自动推导出的全局基准。

因此，同样是“昨天的数据今天跑”，两边语义不同：

```text
DataWorks:
  实例调度时间 = 2026-05-30 02:00
  业务日期 = 2026-05-29
  任务参数和分区天然围绕业务日期展开

Foundry:
  schedule 在 2026-05-30 02:00 触发 build
  build 读取某些 Dataset transaction
  如果要表达 2026-05-29 业务数据，需要字段、参数或输入数据约定显式承载
```

---

## 五、Build 与作业实例判重逻辑

### 5.1 这个问题为什么会落到判重逻辑上

DataWorks 的业务日期概念之所以强，是因为它参与了作业实例生成和重跑判断。DataWorks 官方文档将 recurring instance 定义为调度系统“基于任务调度配置、按每个业务日期生成的运行实体”，任务执行、状态和日志都关联到这个实例。数据回补文档还说明，针对某个业务时间回补，本质上等价于重跑该业务时间对应的周期实例。【事实】

Foundry 的 build 机制则不同。Foundry 官方文档将 Build 定义为计算 Dataset 新版本的机制；build resolution 会校验输入、打开输出 Dataset transaction 做 build locking，并检测其他会改变输入的 build。更关键的是 staleness：如果输出 Dataset 的输入 Dataset 和 JobSpec 逻辑自上次构建以来没有变化，输出被认为 fresh，后续 build 不会重算；schedule run 也可能因为目标都 up-to-date 而 ignored。【事实】

因此，“DataWorks 没有在 Palantir 中体现业务时间”更准确地说是：两者的去重 / 判重基准不同。【推断】

### 5.2 DataWorks 的判重基准：业务周期实例

DataWorks 先根据节点调度配置生成实例，再让实例进入等待调度时间、等待上游、等待资源或运行状态。对于一个日调度节点，平台心智大致是：

```text
节点 A + 业务日期 2026-05-29 + 调度时间 2026-05-30 02:00
  -> 一个可追踪的周期实例
  -> 对应日志、状态、参数替换、上游/下游实例依赖
```

小时、分钟节点会在一天内生成多个调度时刻对应的实例；周、月、年节点在非执行日也可能生成 dry-run 实例，用来打通下游依赖。【事实】

DataWorks 这类判重的关键不是“输入数据有没有变化”，而是“这个节点在这个业务时间 / 调度时刻是否应该有一个实例”。即使外部源数据没有变化，周期实例仍会按调度体系存在；即使代码或源数据变了，历史业务日期也通常要通过重跑、补数据或强制重跑下游来显式处理。【推断】

官方“立即生成实例”文档还显示，修改生产节点调度配置时，DataWorks 会对同日未来时段的实例做替换、保留或删除，并警告可能造成依赖变化、实例替换、实例删除和复杂的当日依赖图。这说明 DataWorks 的判重/替换边界贴近“节点调度配置 + 当日实例时刻”，而不是 Foundry 式的 Dataset 是否 stale。【事实 + 推断】

### 5.3 Foundry 的判重基准：Dataset freshness 与 build locking

Foundry 不先为每个业务日期生成一个“应运行实例”。它的 schedule trigger 满足后，会尝试发起 build；build 再根据 Dataset graph、branch、target、build type、scope、权限、staleness 等条件决定实际要执行哪些 job。【事实】

Foundry 的判重或跳过逻辑至少包含三层：

| 层次 | 机制 | 含义 |
|---|---|---|
| Schedule run | 触发后可能 `Succeeded`、`Ignored` 或 `Failed` | `Ignored` 通常表示没有 work to do，目标都 up-to-date |
| Build resolution | 打开输出 transaction、锁定输出、检测会改变输入的并发 build | 避免并发 build 对同一输出或输入一致性造成冲突 |
| Staleness | 输入 Dataset 和 JobSpec 逻辑未变则输出 fresh | fresh 的输出不会在后续 build 中重算，除非 force build |

这意味着 Foundry 的“同一次是否要算”不是看 `business_date=2026-05-29` 是否跑过，而是看：

```text
目标 Dataset 在目标 branch 上
  自上次成功构建以来，
  输入 Dataset transaction 是否变化？
  计算逻辑 / JobSpec 是否变化？
  是否被 force build 覆盖默认 staleness？
```

对于 Data Connection sync，Foundry 文档还特别说明这类 sync 总是标为 up-to-date，因为输入来自外部系统，Foundry 不知道外部数据是否更新；因此通常需要单独调度并 force build sync。这进一步说明 Foundry 的 freshness 判断只对平台能观察到的 Dataset / JobSpec 变化可靠，对外部系统的“业务日期是否到齐”并不天然可靠。【事实 + 推断】

### 5.4 同一场景下的行为差异

假设一个日批任务每天 `02:00` 处理前一天业务数据。

```text
2026-05-30 02:00
业务日期：2026-05-29
目标分区：dt = '2026-05-29'
```

DataWorks 的心智是：生成并运行“节点 A 在业务日期 2026-05-29 的周期实例”。如果要修复这一天的数据，通常是补 `2026-05-29` 或重跑该业务时间关联的实例。判重 key 更接近：

```text
node_id + business_date / scheduled_time / cycle_slot + environment
```

Foundry 的心智是：schedule 在 `2026-05-30 02:00` 尝试 build 目标 Dataset。如果输入 Dataset 没有新 transaction、JobSpec 没变，schedule 可能 ignored；如果上游对 `2026-05-29` 分区产生了一个新 transaction，Foundry 会看到数据资产版本变化，但它仍然不会天然知道这是“重跑 2026-05-29 业务日期”。判重 key 更接近：

```text
output_dataset + branch + input_transaction_set + jobspec_logic_version
```

这解释了为什么 Palantir 中看不到 DataWorks 的业务时间：Foundry 的去重问题被建模为“是否需要产生新的 Dataset version”，而不是“某个业务周期实例是否已经存在 / 是否应重跑”。【推断】

### 5.5 融合时的关键风险

| 风险 | 产生原因 | 规避方式 |
|---|---|---|
| 业务日期重复消费 | DataWorks 同一业务日期重跑后，Foundry 看到多个 transaction，但没有业务日期幂等键 | 在 Dataset 中写入 `business_date`、`run_id`、`data_interval`，下游按业务主键 + 业务日期去重或覆盖 |
| 历史分区修复未传播 | DataWorks 修复历史分区，但 Foundry 侧没有新 transaction 或 schedule 被 ignored | 每次成功产出都生成可观察的 Dataset transaction 或完成事件 |
| 外部源 freshness 误判 | Foundry 对 Data Connection 外部输入无法天然判断是否更新 | Data Connection sync 单独 force build，或由 DataWorks 写完成标记 / manifest |
| 双重调度主权 | DataWorks 和 Foundry 都按时间独立触发 | 让 DataWorks 负责业务日期完成语义，Foundry 消费完成后的数据版本或 manifest |
| 补数据顺序错乱 | DataWorks 可按业务日期顺序补数，Foundry 只看 transaction 顺序 | manifest 中记录 `business_date`、`sequence`、`is_reprocess`、`supersedes_run_id` |

### 5.6 对自研平台的启发

【建议】如果要把 DataWorks 和 Foundry 的优势合并，自研平台不能只实现 cron 调度，也不能只实现 Dataset Transaction。需要同时有两套互补的身份：

```text
Run Identity:
  task_id
  business_date / data_interval
  scheduled_time
  run_type: scheduled | backfill | manual | force_rerun
  attempt

Data Version Identity:
  output_dataset
  branch
  input_transaction_set
  logic_version
  output_transaction
```

Run Identity 解决 DataWorks 擅长的“某个业务周期是否应该跑、是否补过、是否重跑下游”；Data Version Identity 解决 Foundry 擅长的“数据版本是否过期、是否可增量、是否需要重算、下游受哪些版本影响”。【推断】

最重要的设计点是：**业务日期不能只做调度参数，Dataset Transaction 也不能替代业务日期。** 前者是业务口径，后者是数据版本口径；二者必须在 build/run 元数据中关联起来。【建议】

---

## 六、自研平台模型：Run Identity + Data Version Identity

### 6.1 双身份模型

【建议】自研平台应把“运行身份”和“数据版本身份”拆成两类主键，不要强行合并。

| 模型 | 解决的问题 | 典型判重 key | 来自哪边的启发 |
|---|---|---|---|
| Run Identity | 某业务周期是否应运行、是否补过、是否重跑下游、是否满足跨周期依赖 | `task_id + business_date + cycle_slot + run_type` | DataWorks |
| Data Version Identity | 某输出是否因输入或逻辑变化而 stale、是否可增量、是否需要 force build | `output_dataset + branch + input_version_set + logic_version` | Foundry |

Run Identity 面向业务时间，Data Version Identity 面向数据版本。两者通过一张映射表关联：

```text
run_instance
  -> build
    -> dataset_transaction
```

这条链路允许回答两类问题：

- 从业务侧问：`2026-05-29` 这天的数据是否已产出？补数用了哪次运行？是否影响下游？
- 从数据侧问：某个 Dataset transaction 是由哪个 run 产生？用了哪些输入 transaction？哪些下游 Dataset stale？

### 6.2 Run Identity 状态机

Run Identity 的状态机更接近 DataWorks 周期实例，但应补上更明确的幂等和补数语义。

```text
CREATED
  -> WAITING_TIME
  -> WAITING_UPSTREAM
  -> READY
  -> RUNNING
  -> SUCCEEDED
  -> FAILED
  -> CANCELLED
  -> SKIPPED_DRY_RUN
```

建议保留的关键字段：

| 字段 | 说明 |
|---|---|
| `run_id` | 运行实例唯一 ID |
| `task_id` | 任务 / transform / job 定义 |
| `business_date` | 业务日期或账期 |
| `data_interval_start/end` | 数据覆盖区间，优先于单一日期 |
| `scheduled_time` | 理论调度时间 |
| `actual_start_time/end_time` | 实际执行时间 |
| `cycle_slot` | 小时 / 分钟任务在日内的时刻，例如 `02:00` |
| `run_type` | `scheduled`、`backfill`、`manual`、`force_rerun`、`dry_run` |
| `attempt` | 当前 run 的第几次尝试 |
| `rerun_policy` | 是否允许重跑、运行中能否重跑、是否允许强制下游 |
| `supersedes_run_id` | 本次是否覆盖某次历史运行 |

Run Identity 的幂等约束建议分两层：

```text
scheduled run:
  unique(task_id, business_date, cycle_slot, environment, run_type='scheduled')

backfill / force rerun:
  allow multiple runs for same business_date
  but require supersedes_run_id or explicit output overwrite policy
```

这样既能避免正常调度重复生成同一业务周期实例，又允许补数和修复保留多次运行证据。【建议】

### 6.3 Data Version Identity 状态机

Data Version Identity 的状态机更接近 Foundry Build + Dataset Transaction。

```text
REQUESTED
  -> RESOLVING
  -> LOCKING_OUTPUTS
  -> RUNNING
  -> COMMITTING
  -> COMPLETED
  -> FAILED
  -> ABORTED
  -> IGNORED_FRESH
```

建议保留的关键字段：

| 字段 | 说明 |
|---|---|
| `build_id` | 一次 build 请求 |
| `branch` | 数据分支，例如 `main`、`dev` |
| `target_datasets` | 本次目标输出 |
| `build_type` | `single`、`with_upstream`、`connecting`、`downstream` |
| `force_build` | 是否绕过 staleness |
| `logic_version` | JobSpec / transform code / semantic version |
| `input_version_set` | 输入 Dataset transaction 集合 |
| `output_transaction_set` | 输出 Dataset transaction 集合 |
| `staleness_reason` | `input_changed`、`logic_changed`、`force_build`、`external_unknown` |
| `freshness_result` | `stale`、`fresh`、`unknown_external` |

Data Version Identity 的判重不是“不允许多个 build”，而是“不需要重复计算 fresh 输出”。推荐逻辑：

```text
if not force_build
   and latest_output.input_version_set == current_input_version_set
   and latest_output.logic_version == current_logic_version:
       mark build/run as IGNORED_FRESH
else:
       build and commit a new output transaction
```

对外部数据源要单独处理。Foundry 文档说明 Data Connection sync 因外部输入不可见而经常需要 force build；自研平台也应引入 `external_unknown`，避免把“平台不知道变没变”误判成“没有变化”。【事实 + 建议】

### 6.4 Run 与 Transaction 映射

【建议】核心表应至少包含一张 `run_output_transaction` 映射表：

| 字段 | 说明 |
|---|---|
| `run_id` | 业务运行实例 |
| `build_id` | 数据构建请求 |
| `dataset_id` | 输出 Dataset |
| `transaction_id` | 输出 transaction |
| `business_date` | 本 transaction 对应的业务日期 |
| `data_interval_start/end` | 本 transaction 覆盖的数据区间 |
| `write_mode` | `append`、`replace_partition`、`snapshot`、`merge` |
| `is_reprocess` | 是否为历史修复 / 补数产出 |
| `supersedes_transaction_id` | 是否替代某个旧 transaction |

这张表是统一 DataWorks 和 Foundry 心智的关键。没有它，运维人员只能看到“实例成功了”或“Dataset 版本变了”，但很难回答“这次成功到底修复了哪个业务日期、替代了哪个数据版本、哪些下游需要重算”。【推断】

### 6.5 补数与强制重跑策略

DataWorks 官方强制重跑下游功能表明，它会围绕某个自动触发实例，把目标下游实例设回 Not running，并可选择是否重跑跨日实例。这个能力本质上是业务实例图上的影响传播。【事实】

Foundry 的 force build 则是绕过 staleness，让选定范围内 Dataset 无论是否 stale 都重算；它本质上是数据版本图上的影响传播。【事实】

自研平台应把两种传播都保留：

| 操作 | 传播图 | 适用场景 |
|---|---|---|
| `rerun_instance` | Run DAG | 当前业务日期任务失败或数据质量错误 |
| `rerun_descendants` | Run DAG | 某业务日期上游修复，需要下游同业务周期重跑 |
| `force_build_dataset` | Dataset graph | 逻辑不变但外部源不可信、需要重建数据版本 |
| `recompute_downstream_versions` | Dataset graph | 输入 transaction 或逻辑版本变化，需要刷新下游数据资产 |
| `backfill_interval` | Run DAG + Dataset graph | 历史区间补数，同时需要记录新 output transaction |

最容易出错的是“历史补数”。正确流程不应只是 rerun 任务，也不应只是 force build Dataset，而应该是：

```text
1. 创建 backfill run instances，明确 business_date/data_interval。
2. 每个 run 解析对应输入版本和依赖实例。
3. build 产生新的 output transactions。
4. 记录 run -> transaction 映射。
5. 根据 overwrite/append/merge 策略更新业务日期 manifest。
6. 标记受影响下游 run 或 downstream dataset stale。
```

### 6.6 分区 Manifest

【建议】如果数据以业务日期或时间区间为主要口径，应增加 Dataset Partition Manifest，而不是只依赖底层文件分区。

| 字段 | 说明 |
|---|---|
| `dataset_id` | 数据集 |
| `partition_key` | 如 `dt=2026-05-29` |
| `business_date` | 业务日期 |
| `active_transaction_id` | 当前生效的 transaction |
| `producing_run_id` | 当前分区由哪个 run 生产 |
| `version` | 分区版本号 |
| `status` | `active`、`superseded`、`quarantined` |
| `quality_status` | `passed`、`failed`、`warning` |

这个 Manifest 解决 Foundry 式 transaction 与 DataWorks 式业务分区之间的缺口：同一业务日期可以有多次修复产出，但任何时刻只有一个 active 版本对下游可见。【建议】

### 6.7 多输入 OR 事件触发的业务时间冲突

如果一个 pipeline 同时读取 Dataset A 和 Dataset B，并配置 `OR(A updated, B updated)`，Foundry 的触发语义是：A 或 B 任意一个 Dataset commit transaction 后，schedule 条件满足并尝试 build。官方 Trigger Reference 明确 `OR` 是任一 component trigger 满足即可，`Data updated` 是 Dataset 有 transaction committed；Common schedules 文档也说明 OR 会在时间点或事件发生时触发 build。【事实】

这个语义与 DataWorks 的同周期依赖不同。DataWorks 中如果 C 依赖 A 和 B 的同周期实例，C 的 `business_date=2026-05-29` 实例通常要等 A、B 对应业务周期实例都成功后才运行。Foundry 的 OR 事件触发不是这种业务日期对齐屏障。【推断】

典型冲突如下：

```text
Pipeline C = f(A, B)

02:05 A commits transaction: business_date = 2026-05-29
      OR trigger fires -> Build C#1
      C#1 reads A(2026-05-29), B(latest maybe 2026-05-28)

02:20 B commits transaction: business_date = 2026-05-29
      OR trigger fires -> Build C#2
      C#2 reads A(2026-05-29), B(2026-05-29)
```

C#1 和 C#2 在 Foundry 语义里都可能是合法 build，因为它们对应不同的输入 transaction set。但如果业务上要求“C 的业务日期必须等于 A、B 的共同业务日期”，C#1 就是半新半旧输入，无法被赋予一个可靠的单一业务日期。【推断】

因此，多输入 OR build 的业务时间不能用触发事件推断，只能通过输入版本向量确认：

```text
business_time(C build)
  != trigger_time
  != changed_dataset.business_date

business_time(C build)
  = function(
      A.transaction.business_date / interval,
      B.transaction.business_date / interval,
      output_semantics
    )
```

可以分三类处理：

| 输出语义 | OR 触发是否合适 | 业务时间确认方式 |
|---|---|---|
| Current snapshot / 最新视图 | 可以接受 | 输出没有单一业务日期，只记录 input transaction vector |
| 维表变化驱动的重算 | 通常可以接受 | 业务日期来自事实表，维表只作为 snapshot input |
| 日分区 / 账期产出 | 不建议直接 OR | 必须要求所有关键输入在同一 `data_interval` ready |
| 增量 append 输出 | 高风险 | 容易重复写、错写分区，必须有幂等键和分区 manifest |

对业务日期敏感的 pipeline，应把 `OR(A updated, B updated)` 改成以下模式之一：

1. **AND ready barrier**：A、B 分别写入 `dataset_partition_manifest`，只有 `A(dt)` 和 `B(dt)` 都 ready 时才创建 C 的 run。
2. **事实表主时钟**：只订阅事实表 A 的事件，B 作为 snapshot/reference input；C 的业务日期来自 A。
3. **Watermark 对齐**：以 `data_interval_end` / `source_watermark` 计算所有输入的共同可处理区间，只处理交集区间。
4. **允许临时不一致但可覆盖**：C#1 可以产出 provisional transaction，C#2 到齐后 supersede C#1；必须通过 partition manifest 控制 active transaction。
5. **Foundry 风格最新视图**：承认输出是“最新可得输入版本”的物化视图，不声明单一 business_date。

【建议】判断是否冲突的标准是：下游是否需要一个标量 `business_date`。如果需要，OR 事件触发本身不够，必须增加业务日期 ready barrier；如果不需要，build 应记录 input transaction vector，而不是伪造 business_date。

### 6.8 Freshness 与 Time Alignment 的兼容边界

【推断】freshness 机制和 time alignment 机制不应被理解为同一个调度模型的两个参数。它们解决的是不同问题：

| 机制 | 核心问题 | 判定依据 | 典型优化目标 |
|---|---|---|---|
| Freshness | 输出数据是否需要因输入或逻辑变化而重算 | input transaction set、logic version、staleness | 尽快让 Dataset 最新，避免无意义重算 |
| Time alignment | 多个输入是否在同一业务时间 / 数据区间上对齐 | business_date、data_interval、周期实例状态、watermark | 保证账期、分区、报表口径一致 |

二者的张力来自优化目标不同。freshness 倾向于“谁变了就触发”，time alignment 倾向于“关键输入都到齐再触发”。在单输入 pipeline 或最新视图场景中，这种差异通常不明显；在多输入、日分区、账期、监管报送、财务结算等场景中，差异会变成实质冲突。【推断】

可以把兼容性分成三类：

| 场景 | 是否兼容 | 判断 |
|---|---|---|
| 最新视图 / dashboard cache | 兼容 | 输出语义是 latest available，不承诺单一业务日期 |
| 事实表主时钟 + 维表 snapshot | 基本兼容 | 业务日期由事实表决定，其他输入只影响重算版本 |
| 多事实表同账期汇总 | 不直接兼容 | 必须增加 time alignment barrier，否则会出现半新半旧输入 |
| 财务、结算、监管批处理 | 不应直接使用 freshness 触发作为完成条件 | 需要业务周期实例、ready manifest、watermark 或账期锁 |

因此，不能简单说两种作业调度模型完全不兼容。更准确的结论是：**Foundry 风格 freshness scheduling 与 DataWorks 风格 business-cycle scheduling 是正交模型；若只用其中一种去覆盖另一种的语义，就不兼容。**【建议】

自研平台的设计原则应是：

```text
freshness decides whether a data version is stale
time alignment decides whether a business run is eligible
```

落到执行顺序上，应先做 time alignment，再做 freshness：

```text
1. 根据 business_date / data_interval 判断关键输入是否 ready。
2. ready 后创建 Run Identity。
3. Run 解析当前 input transaction vector。
4. freshness/staleness 判断是否需要 build。
5. build 成功后提交 output transaction，并更新 partition manifest。
```

这能避免两个极端：

- 只看 freshness：输入一变就算，容易产出半新半旧业务分区。
- 只看 time alignment：每个周期都算，容易无视数据版本和逻辑版本，造成重复计算和血缘不清。

### 6.9 复合事件触发的状态计算

Foundry 的复合事件触发不是流式 join，也不是要求多个事件在同一时刻到达。官方 Trigger Reference 说明：event trigger 在指定事件发生后进入 satisfied 状态，并保持 satisfied，直到整个 trigger 被满足且 schedule run 发生。`AND` 表示所有 component trigger 都 satisfied，`OR` 表示任一 component trigger satisfied。【事实】

因此，`AND(A updated, B updated)` 的语义应理解为：

```text
schedule 上次运行完成/触发后，开始一个新的观察窗口

T1: A commit transaction
    -> A_updated = satisfied
    -> B_updated = false
    -> AND(A, B) = false

T2: B commit transaction
    -> A_updated = satisfied
    -> B_updated = satisfied
    -> AND(A, B) = true
    -> schedule run
    -> 事件满足状态被消费，进入下一轮观察窗口
```

Palantir 的 schedule troubleshooting 文档也给出同类说明：如果一个 schedule 有输入触发 A1 和 A2，并开启“Wait until all these datasets update”，且上一次 schedule 在 T1 运行，那么要在 T2 再运行，A1 和 A2 都需要在 `(T1, T2)` 期间更新。【事实】

这暴露出几个重要边界：

| 场景 | Foundry trigger 结果 | 业务时间风险 |
|---|---|---|
| A 先更新，B 后更新 | B 更新时 AND satisfied，触发 run | 只说明二者都在窗口内更新，不说明业务日期相同 |
| A 更新两次，B 更新一次 | 通常只需要 B 到达后触发一次 run | 不会自动产生 A1/B1、A2/B1 这种配对关系 |
| A 更新 `dt=29`，B 更新 `dt=28` | AND 仍可 satisfied | 会触发半错配业务时间的 build |
| schedule 运行中又有事件到达 | 同一 schedule 会保持 triggered，前一次结束后再运行 | 后续 run 仍由 staleness 决定是否真正创建 build |
| 多个 schedule 作用于同一 target | 各 schedule 独立维护 trigger state | 后触发的 schedule 可能因 target 已 up-to-date 被 ignored |

官方 Schedules 文档补充：如果 schedule 在前一次 run 仍在进行时再次被触发，它会保持 triggered，并在前一次 schedule 完成后再运行；run 可能是 `Succeeded`、`Ignored` 或 `Failed`，`Ignored` 通常表示已经 up-to-date 没有工作要做。【事实】

因此，Foundry 的 AND event 只提供“事件都发生过”的闩锁语义，不提供以下能力：

- 不保证事件同时到达。
- 不保证多个输入的 `business_date` 相同。
- 不保证多个输入在同一 `data_interval` 上 ready。
- 不保存每个业务日期维度上的事件配对。
- 不自动选择“共同最大已完成业务日期”。

【建议】如果业务目标是“上游 A 和 B 都完成同一业务日期后触发 C”，不要直接使用 `AND(A updated, B updated)` 作为业务完成条件。应建立业务日期 ready 表或分区 manifest：

```text
input_ready_manifest
  dataset_id
  business_date / data_interval
  transaction_id
  ready_status
  committed_at

trigger C(dt) when:
  A.ready(dt) = true
  and B.ready(dt) = true
  and C.partition(dt) is stale or absent
```

换句话说，Foundry 的 AND/OR 负责 event occurrence，业务平台需要额外负责 event correlation。对 DataWorks 式业务周期调度而言，真正需要的是按 `business_date/data_interval` 做相关性判断，而不是按“上次 schedule run 后是否都更新过”做布尔判断。【建议】

### 6.10 架构决策：拆开业务周期调度与 Freshness 调度

【决策】业务周期对齐调度和 freshness 调度作为两套独立机制设计，不混为一谈。

```text
Business-cycle scheduling:
  owns Run Identity
  decides whether C(dt) is eligible to run
  based on business_date / data_interval / ready manifest / upstream run state

Freshness scheduling:
  owns Data Version Identity
  decides whether C's output dataset version is stale
  based on input transaction set / logic version / force build / external unknown
```

拆分后形成四条硬规则：

1. `Data updated` 事件只表示 Dataset transaction 变化，不表示某个业务日期完成。
2. `AND/OR` trigger 只计算事件满足状态，不做业务日期配对。
3. 任何声明 `business_date` 或 `data_interval` 的输出，必须先经过 business-cycle scheduler 或 ready manifest。
4. freshness/staleness 只能在业务周期 run 已确定后，作为“是否真的需要 build”的二级判断。

推荐执行链路：

```text
1. Upstream dataset writes partition manifest:
     A.ready(dt=2026-05-29, transaction=a123)
     B.ready(dt=2026-05-29, transaction=b456)

2. Business-cycle scheduler checks alignment:
     A.ready(dt) && B.ready(dt)

3. Create Run Identity:
     C.run(dt=2026-05-29)

4. Resolve Data Version Identity:
     input_version_set = {A:a123, B:b456}
     logic_version = current

5. Freshness check:
     if output C(dt) already produced by same input_version_set + logic_version:
        mark run as skipped_fresh
     else:
        build and commit output transaction

6. Update partition manifest:
     C.active(dt=2026-05-29, transaction=c789)
```

这意味着，自研平台不把 Foundry-style trigger expression 暴露为业务周期调度的唯一入口。对业务时间敏感的任务，用户配置的是 `data_interval` 对齐规则；对最新视图或缓存类任务，用户才配置 freshness trigger。【决策】

边界命名建议：

| 子系统 | 不负责 | 负责 |
|---|---|---|
| Business-cycle scheduler | 不判断 Dataset 是否 stale | 业务日期、账期、ready barrier、补数、重跑实例 |
| Freshness scheduler | 不推断业务日期 | Dataset staleness、input transaction diff、logic version、force build |
| Partition manifest | 不执行计算 | 记录每个业务分区当前 active transaction |
| Build engine | 不决定业务周期是否 ready | 在给定 run 和 input version set 下执行并提交 transaction |

---

## 七、相融方式

### 7.1 推荐边界

【建议】如果组织已经大量使用 DataWorks 的业务日期、分区、补数据和跨周期依赖，应让 DataWorks 继续承担强批处理日历语义；Foundry 则承接数据资产化、版本化、血缘、权限、Ontology 和上层应用。

推荐数据流：

```text
DataWorks
  -> 生产按 business_date 分区的数据
  -> 输出到 OSS / S3 / HDFS / JDBC / Kafka 等边界
  -> 显式携带业务时间契约
  -> Foundry Data Connection / Dataset
  -> Foundry Transform / Pipeline
  -> Ontology / 应用 / 决策工作流
```

### 7.2 最小时间契约

跨平台数据集至少建议包含：

| 字段 | 目的 |
|---|---|
| `business_date` | 数据归属业务日期，替代 DataWorks `$bizdate` 的隐式上下文 |
| `schedule_time` | DataWorks 理论调度时间，替代 `$cyctime` 的隐式上下文 |
| `data_interval_start` | 本批数据覆盖区间开始 |
| `data_interval_end` | 本批数据覆盖区间结束 |
| `source_watermark` | 源系统同步水位，支持延迟数据和重放判断 |
| `dataworks_instance_id` | 追溯 DataWorks 周期实例 |
| `pipeline_run_id` | 跨平台运行链路追踪 |
| `ingested_at` | Foundry 接入时间，区分业务时间和接入时间 |

### 7.3 避免双重调度主权

【建议】不要让 DataWorks 和 Foundry 同时独立决定同一份业务日期数据是否应该生产完成。否则容易出现：

- DataWorks 还在补 `2026-05-29`，Foundry 已按墙钟时间消费了半成品。
- Foundry 只看到 Dataset transaction 更新，却不知道这次更新属于哪个业务日期。
- 同一个业务日期在两个系统中被重复重跑，但缺少统一 run id 和数据版本约束。

更稳妥的做法是：DataWorks 产出“业务日期已完成”的数据资产或完成标记，Foundry 以完成后的 Dataset / transaction / event 为输入，而不是用自己的 schedule 去猜 DataWorks 的业务日期状态。

---

## 八、后续讨论问题

1. 如果要自研一个 Foundry-like 平台，是否应该吸收 DataWorks 的业务日期模型？结论倾向是：应该吸收，但不要只做成调度参数，应升级为数据契约、Dataset 分区契约和补数契约。
2. Foundry 的 Dataset Transaction 能否替代 DataWorks 业务日期？结论倾向是：不能替代。Transaction 描述数据版本变化，业务日期描述业务口径归属；二者维度不同。
3. DataWorks 的补数据能否映射到 Foundry build？结论倾向是：可以部分映射，但必须显式传入业务日期区间、输入版本和输出覆盖策略。
4. 如果两边都存在实时能力，应以谁为准？结论倾向是：实时链路用 event time / watermark 作为主语义，离线链路用 business_date / data interval 作为主语义，不能混用。
5. 判重逻辑应该放在哪里？结论倾向是：业务周期判重放在 Run Identity，数据新鲜度判重放在 Data Version Identity，二者通过 run-to-transaction mapping 关联。

---

## 九、来源

- DataWorks 官方文档：[Supported formats of scheduling parameters](https://www.alibabacloud.com/help/doc-detail/2846748.html)
- DataWorks 官方文档：[View auto-triggered instances](https://www.alibabacloud.com/help/en/dataworks/user-guide/view-auto-triggered-node-instances)
- DataWorks 官方文档：[Manage auto-triggered tasks](https://www.alibabacloud.com/help/en/dataworks/user-guide/view-and-manage-auto-triggered-nodes)
- DataWorks 官方文档：[Scheduling time](https://www.alibabacloud.com/help/en/dataworks/user-guide/detailed-description-of-scheduling-cycle-of-data-studio)
- DataWorks 官方文档：[Data backfill](https://www.alibabacloud.com/help/en/dataworks/data-backfilling)
- DataWorks 官方文档：[Instance generation mode: Immediately after deployment](https://www.alibabacloud.com/help/en/dataworks/user-guide/instance-generation-method-instantly-generate-an-instance-after-publishing)
- DataWorks 官方文档：[Force-rerun descendant instances](https://www.alibabacloud.com/help/en/dataworks/user-guide/forcefully-rerun-the-descendant-instances-of-an-auto-triggered-node-instance)
- Palantir 官方文档：[Foundry Data Integration overview](https://www.palantir.com/docs/foundry/data-integration/overview/)
- Palantir 官方文档：[Foundry Datasets](https://www.palantir.com/docs/foundry/data-integration/datasets)
- Palantir 官方文档：[Foundry Builds](https://www.palantir.com/docs/foundry/data-integration/builds)
- Palantir 官方文档：[Foundry Scheduling overview](https://www.palantir.com/docs/foundry/building-pipelines/scheduling-overview)
- Palantir 官方文档：[Foundry Schedules](https://www.palantir.com/docs/foundry/data-integration/schedules)
- Palantir 官方文档：[Foundry Create a schedule](https://www.palantir.com/docs/foundry/building-pipelines/create-schedule)
- Palantir 官方文档：[Foundry Schedule troubleshooting](https://www.palantir.com/docs/foundry/building-pipelines/schedule-troubleshooting)
- Palantir 官方文档：[Foundry Trigger types reference](https://www.palantir.com/docs/foundry/building-pipelines/triggers-reference/)
