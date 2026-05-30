# 迁移风险案例与双坐标设计模式

关联 Issue：#33
日期：2026-05-30

## 总结与洞察

1. 【推断】传统数仓主坐标是 `table + dt + task_instance`，Foundry-like Dataset 主坐标是 `dataset + branch + transaction/view`；迁移时最大风险是误以为两者只是在“分区字段命名”上不同。
2. 【推断】Dataset 没有默认 `dt` 主坐标不会自动降低数据治理能力，但会把原来由 `dt` 隐式承载的生产语义暴露出来，要求平台显式建模。
3. 【建议】迁移应采用双坐标：`transaction/view` 管版本证据链，`business_date/partition_manifest` 管业务解释、补数覆盖和 SLA ready。
4. 【建议】强账期链路必须引入 ready barrier、active transaction pointer、supersedes transaction 和 coverage lineage 四类模式，否则容易出现“版本最新但账期不齐”的事故。
5. 【建议】实时、最新状态、对象应用可以弱化 `dt`；T+1 报表、财务、监管、对账、补数频繁链路必须保留业务日期 manifest 和质量发布门禁。

## 1. 问题边界

传统数仓里，`dt` 经常同时扮演以下角色：

```text
业务日期
+ 物理目录
+ 查询裁剪键
+ 调度实例键
+ 补数范围
+ SLA 验收单元
+ 生命周期清理单元
+ 血缘定位入口
```

Foundry-like Dataset 的主坐标则更接近：

```text
dataset_id
+ branch_name
+ transaction_id / view_end_transaction
+ build_run / transform logic version
```

【推断】这不是“更先进所以不需要日期”，而是把传统 `dt` 的复合职责拆成多条显式链路。迁移时若只把数据写进 Dataset，而没有补业务日期、运行实例、质量证据和 active pointer，就会丢失生产控制语义。

## 2. 风险案例矩阵

| 案例 | 传统 `dt` 模型表现 | Foundry-like 迁移风险 | 控制建议 |
|---|---|---|---|
| 补数覆盖历史日期 | 重跑 `task(dt=2026-05-20)`，覆盖 `table/dt=20260520` | 新 transaction 提交成功，但下游不知道它覆盖哪个业务日期 | `partition_manifest` 记录 coverage；active pointer 切换到新 transaction |
| 迟到数据跨日期修正 | 重刷受影响的多个 `dt` 分区 | 单个 transaction 可能影响多个 business_date，若只看 commit time 会误判范围 | coverage lineage 记录 `business_date_start/end` 与 affected keys |
| 多输入同账期 ready barrier | `A(dt=X)`、`B(dt=X)` ready 后才跑 `C(dt=X)` | A 已更新到 X，B 仍停在 X-1，freshness 触发导致混账期 | `input_business_date_correlation` + `ready barrier` |
| view 指针漂移 | 分区路径基本固定，审计时看历史分区 | 报表当时读的是 transaction T1，审计时 branch head 已到 T2 | 消费日志记录 `resolved_transaction_id`；生产读 active pointer |
| 质量发布解耦 | 分区写入后跑质量规则，规则通过才 ready | transaction commit 被误当可消费，坏数据进入下游 | `COMMITTED_NOT_RELEASED` 状态 + quality gate 后更新 active pointer |
| 权限绕行 | 表权限/分区权限较直观 | 历史 transaction、branch fallback、派生 Dataset 可能暴露敏感数据 | branch/view/transaction 鉴权和访问审计 |
| 回滚后的业务解释 | 回滚某个 `dt` 分区或备份 | 回滚 transaction 不等于“业务日期恢复”；可能影响多个日期 | rollback impact report 列出 affected business dates |

## 3. 推荐 Partition Manifest 字段

`partition_manifest` 是双坐标里的关键桥梁：它把业务日期/区间映射到 transaction/view。

| 字段 | 类型 | 用途 |
|---|---|---|
| `dataset_id` | string | Dataset 身份 |
| `branch_name` | string | 分支，例如 `master`、`prod`、feature branch |
| `transaction_id` | string | 本次覆盖或发布的版本 |
| `view_end_transaction` | string | 消费该 view 时的固定端点 |
| `partition_key` | string | 业务分区键，例如 `business_date`、`bizmonth`、`snapshot_date` |
| `partition_value` | string | 分区值，例如 `2026-05-29` |
| `data_interval_start` | timestamp/date | 覆盖区间起点 |
| `data_interval_end` | timestamp/date | 覆盖区间终点，建议半开区间 |
| `event_time_min` / `event_time_max` | timestamp | 事件时间观测范围 |
| `source_watermark` | string/timestamp | 源端消费水位 |
| `row_count` | long | 完整性检查 |
| `file_count` / `byte_size` | long | 小文件和成本监控 |
| `quality_status` | enum | `PENDING`、`PASSED`、`FAILED`、`WAIVED` |
| `ready_status` | enum | `PROVISIONAL`、`READY`、`SUPERSEDED`、`ROLLED_BACK` |
| `producer_run_id` | string | 生产运行 |
| `supersedes_transaction_id` | string | 替代的旧版本 |
| `active_pointer_name` | string | `prod`、`finance_close` 等发布指针 |
| `created_at` / `published_at` | timestamp | 提交与发布时刻 |

【建议】manifest 不应只存在于文档或表注释中，应成为平台可查询、可审计、可被调度器和质量规则消费的元数据表。

## 4. 四个设计模式

### 4.1 Ready Barrier

【问题】Dataset freshness 只说明输入版本发生变化，不说明所有输入已对齐同一业务日期。

【模式】对强账期任务，在 build 前检查所有上游的 manifest：

```text
for each required input dataset:
  require ready_status = READY
  require business_date = target_business_date
  require active_pointer_name = prod
  capture resolved_transaction_id
```

【适用】T+1 日报、财务结算、监管报送、经营分析日报、跨域对账。

【收益】避免 A 表已经发布 2026-05-29、B 表仍是 2026-05-28 时下游被 freshness 触发。

### 4.2 Active Transaction Pointer

【问题】Branch head 只代表“最新提交”，不代表“通过质量、SLA 和权限检查的生产版本”。

【模式】增加可命名发布指针：

```text
dataset_id + branch_name + pointer_name -> transaction_id
```

常见指针：

| 指针 | 语义 |
|---|---|
| `HEAD` | 最新 committed transaction |
| `prod` | 生产可消费 transaction |
| `finance_close` | 财务关账固定版本 |
| `rollback` | 临时回滚版本 |
| `experiment` | 实验或灰度版本 |

【收益】消费者默认读 `prod`，而不是读 branch head；质量未通过的 transaction 不会自动污染生产消费。

### 4.3 Supersedes Transaction

【问题】传统 `INSERT OVERWRITE PARTITION(dt=X)` 会替换旧结果；Dataset transaction 模型中，新 transaction 只是追加版本事实，不天然说明替代关系。

【模式】当补数、修复或重算发生时，记录：

```text
new_transaction_id
supersedes_transaction_id
supersede_scope = business_date / data_interval / key_range
reason = backfill / correction / schema_fix / source_replay
```

【收益】同一 business_date 多版本并存时，下游能明确哪个版本 active、哪个版本被替代、替代原因是什么。

### 4.4 Coverage Lineage

【问题】普通 Dataset lineage 说明“谁依赖谁”，但不一定能说明“某个业务日期的结果消费了哪些输入日期和 transaction range”。

【模式】把血缘边细化到 coverage：

```text
input_dataset_id + input_transaction_range + input_business_date_range
  -> output_transaction_id + output_business_date_range
```

【收益】能够回答：

- 2026-05-29 的指标来自哪些上游 transaction？
- 补跑是否覆盖了完整日期范围？
- 当前报表是否混用了不同 branch 或 fallback branch？
- 回滚一个 transaction 会影响哪些 business_date？

## 5. 适用场景

| 场景 | 是否保留业务日期 manifest | 说明 |
|---|---:|---|
| T+1 日报 | 必须 | 按业务日期验收和补数 |
| 财务/监管 | 必须 | 需要可审计的账期和 active pointer |
| 对账链路 | 必须 | 多输入同账期齐套 |
| 实时监控 | 可选 | 更关注 latest state 和 event_time |
| 用户画像 latest view | 可选 | 以对象最新状态为主，可保留 snapshot_date |
| 事件流明细 | 建议 | 至少保留 event_time、watermark、late data policy |
| Ad hoc 分析 Dataset | 可选 | 可弱化 production-ready 语义，但仍建议记录 processing_date |

## 6. 落地建议

1. 【建议】不要把 `dt` 原样挪成 Dataset 的唯一主键；底座以 transaction/view 建版本证据链。
2. 【建议】对所有生产级 Dataset 建立 `dataset_contract`，声明日期语义、时区、业务日切分、SLA、质量门禁和保留策略。
3. 【建议】对强账期表引入 `partition_manifest`，把 `business_date/data_interval` 映射到 active transaction。
4. 【建议】所有生产消费默认读 active pointer，不直接读 branch head。
5. 【建议】补数和回滚必须生成 impact report，列出 affected business_date、superseded transactions、下游重算范围和质量证据。

## 参考资料 URL

- https://www.palantir.com/docs/foundry/data-integration/datasets
- https://www.palantir.com/docs/foundry/data-integration/branching
- https://www.palantir.com/docs/foundry/building-pipelines/incremental-overview
- https://www.palantir.com/docs/foundry/transforms-python/incremental-usage
- https://www.palantir.com/docs/foundry/transforms-python-spark/incremental-transaction-limits
- https://www.palantir.com/docs/foundry/optimizing-pipelines/hive-style-partitioning/
- https://www.palantir.com/docs/foundry/data-lineage/branching-data-lineage/
- https://www.alibabacloud.com/help/en/dataworks/user-guide/supported-formats-of-scheduling-parameters
- https://www.alibabacloud.com/help/en/dataworks/data-backfilling
- https://hive.apache.org/docs/latest/language/languagemanual-dml/
