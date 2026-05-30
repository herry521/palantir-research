# 治理、血缘、审计与元数据契约：从 `dt` 目录约定迁移到 Dataset transaction

关联 Issue：#30
日期：2026-05-30

## 总结与洞察

1. 【推断】迁移的核心不是把 `dt=YYYY-MM-DD` 换成 `transaction_id`，而是把传统 `dt` 同时承担的业务日期、调度实例、补数范围、SLA、生命周期、血缘定位和物理裁剪职责拆成显式元数据契约。
2. 【事实】Foundry 公开资料确认 Dataset transaction 是原子数据变更，branch 是指向最新 transaction 的指针，view 由 transaction history 计算；这些能力提供版本证据，但不天然解释 `business_date`。
3. 【建议】最小闭环必须新增 `run -> input transaction range -> output transaction -> business date coverage -> quality evidence -> active pointer` 的元数据链路，否则无法替代传统 `dt` 的生产控制面。
4. 【建议】权限模型必须绑定到 branch/view/transaction 级访问审计，而不是只审计 Dataset 资源；branch fallback、active pointer 和 view 重算都会改变“实际读到的数据版本”。
5. 【建议】质量发布应与 transaction commit 解耦：commit 只证明数据写入成功，`active transaction pointer` 才代表通过覆盖率、质量、SLA 和权限检查后的可消费版本。

## 证据口径

- 本仓库 raw 文档已形成的共识：`docs/raw/27-incremental-scheduling-transaction.md`、`docs/raw/29-lineage-branch-version-pipeline-sync.md`、`docs/raw/30-dataset-permission-marking-architecture.md`、`docs/raw/26-pro-code-governance-quality-observability.md`、`docs/raw/11-marking-mechanism-deep-dive.md`。
- Foundry 公开资料显示 Dataset transaction 有 `OPEN`、`COMMITTED`、`ABORTED` 生命周期，类型包括 `SNAPSHOT`、`APPEND`、`UPDATE`、`DELETE`；`APPEND` 是增量基础，`UPDATE` 会破坏 append-only 要求。
- Foundry branch 是 transaction 指针，不支持 Dataset branch 的数据 merge；build 在指定 branch 上写 output，input 可通过 fallback branch 解析。
- Foundry Data Lineage 是 branch-aware，但 Data Lineage graph 本身不是 branched resource；选择 Global Branch 时 dataset fallback display 被禁用。
- Foundry Markings 是强制访问控制；用户必须满足资源上所有普通 Markings，role 不能绕过 Marking；Markings 沿文件层级和直接依赖传播。

## 1. 从 `dt` 到 transaction 的语义拆分

| 传统 `dt` 隐含职责 | Dataset transaction 能否直接替代 | 迁移后显式元数据 |
|---|---:|---|
| 业务日期切片 | 不能 | `business_date`、coverage manifest |
| 事件发生时间 | 不能 | `event_time_min/max`、watermark、late data policy |
| 调度实例 / 运行实例 | 不能 | `run_id`、`schedule_run_id`、`build_id`、`sync_task_id` |
| 产出版本 | 可以部分替代 | `output_transaction_id`、`branch_name`、`view_end_transaction` |
| 补数范围 | 不能 | `coverage_lineage`、`backfill_reason`、`input_transaction_range` |
| SLA readiness | 不能 | `sla_readiness`、freshness deadline、quality gate |
| 权限与审计定位 | 只能提供版本锚点 | `access_audit` 记录 requested/resolved branch/view/transaction |
| 物理分区裁剪 | 不等价 | `partition_manifest` 与物理 layout 分离建模 |

【推断】传统 `dt` 之所以好用，是因为它把“业务日期 + 生产批次 + 查询路径 + 运维状态”压缩到一个目录名里；transaction 更严格，但更低层，必须用契约补回生产语义。

## 2. 必须补的元数据契约

### 2.1 Run-to-Transaction Mapping

【建议】每次 SyncRun / BuildRun / TransformRun 必须写入运行账本，并把运行与输入、输出 transaction 显式绑定。

最小规则：

- 一个 committed output transaction 必须有且只有一个 producer run；如果一次 run 写多个输出，使用 `commit_group_id` 表示同一运行批次，但不要假设跨 Dataset 原子提交。
- 每个 run input 必须记录 `requested_branch`、`resolved_branch`、`fallback_used`、`current_view_range`、`processed_transaction_range`、`previous_end_transaction`、`last_read_transaction`。
- Foundry 增量 transaction limits 的 Spark details 会展示 current view range、processed batch range、previous end transaction、last read transaction；自建平台应把这些变成可查询元数据，而不是只出现在 UI。
- Data Connection sync 也必须进入同一账本：`source_ref + sync_config_version + sync_run_id + transaction_type + output_transaction_id`。
- Foundry 公开资料未证明多输出 build 的跨 Dataset 原子提交语义；自建平台应先按单 Dataset transaction 原子性设计。

### 2.2 日期字段契约

| 字段 | 定义 | 必填建议 | 主要用途 |
|---|---|---:|---|
| `business_date` | 业务归属日期，例如日报口径的交易日、账期日 | 日批事实表/汇总表必填 | SLA、补数、覆盖率、对账 |
| `event_time` | 源事件实际发生时间，通常为 timestamp | 事件事实表必填 | 乱序、迟到、watermark、窗口统计 |
| `snapshot_date` | 本次数据代表的源系统快照日期 | 快照表必填 | 日终库存、账户状态、维表快照 |
| `processing_date` | 平台处理或提交日期，通常来自 run/commit time | 所有 transaction 自动生成 | 运维、审计、延迟计算 |
| `effective_date` | 业务生效日期或有效期起点；常配合 `effective_end_date` | SCD/合同/价格类数据必填 | 点时查询、追溯、冲突检测 |

【建议】`business_date` 不得默认等于 `processing_date`；只有 Dataset contract 明确声明并通过校验时才允许等同。

【推断】一个 transaction 可覆盖多个 `business_date`，因此日期覆盖应写在 `partition_manifest` / `coverage_lineage`，而不是只写在 transaction header。

【建议】每个 Dataset 必须声明 `date_semantics`：时区、业务日切分规则、允许迟到窗口、补数覆盖策略、是否允许同一 business_date 多版本并存。

【建议】某些实时或无业务日期数据可豁免 `business_date`，但必须声明 `date_contract_type=NONE|EVENT_TIME_ONLY`，避免下游误用。

### 2.3 Partition Manifest 与 Active Transaction Pointer

【事实】Foundry Dataset view 是从最近 `SNAPSHOT` 起应用后续 transaction 得到的有效文件集合；`DELETE` 从 view 中移除文件引用但不等于立即物理删除。

【建议】迁移后应把“逻辑分区覆盖”与“物理目录布局”分离，建立 transaction-level partition manifest。

`partition_manifest` 至少记录：

| 字段 | 说明 |
|---|---|
| `manifest_id`, `transaction_id`, `dataset_id`, `branch_name` | 版本锚点 |
| `partition_key`, `partition_value` | 逻辑分区，例如 `business_date=2026-05-29` |
| `business_date_start/end` | 覆盖业务日期范围 |
| `event_time_min/max` | 事件时间范围 |
| `snapshot_date`, `processing_date`, `effective_start/end` | 日期契约字段 |
| `row_count`, `file_count`, `byte_size`, `checksum` | 完整性与回放证据 |
| `quality_status`, `coverage_status` | 是否可发布的摘要 |

【建议】新增 `active_view_pointer`，不要让所有消费者直接读 branch head：

| 指针 | 含义 |
|---|---|
| `HEAD` | branch 当前最新 committed transaction |
| `LATEST_PASSED` | 最新通过质量和 SLA readiness 的 transaction |
| `PINNED` | 被人工或发布流程固定的 transaction |
| `ROLLBACK` | 回滚到历史 transaction 的发布指针 |

所有生产消费默认读取 `active_view_pointer(pointer_name='prod')`，而不是读取 latest branch head。指针更新必须审计，并绑定质量证据。

## 3. Coverage Lineage

【建议】血缘边必须从“Dataset A -> Dataset B”升级为“input transaction + business date range -> output transaction + business date range”。

最小表达：

```text
input_dataset_id + input_branch + input_transaction_range + input_business_date_range
  -> run_id + transform_logic_version
  -> output_dataset_id + output_branch + output_transaction_id + output_business_date_range
```

coverage lineage 应覆盖四类场景：

| 场景 | 必要元数据 |
|---|---|
| 普通日批 | input view end transaction、business_date、output transaction |
| 增量追加 | processed transaction range、event_time range、output append transaction |
| 补数/重算 | backfill_request_id、覆盖日期范围、被替换或 superseded 的 transaction |
| 快照发布 | snapshot_date、完整快照 manifest、active pointer 更新记录 |

coverage lineage 必须能回答：

- 某个 `business_date` 当前生产版本来自哪个 output transaction。
- 某个 output transaction 实际消费了哪些 input transaction range。
- 某次补数是否覆盖了完整日期范围，是否留下 gap 或 overlap。
- 下游某个指标是否混用了不同 input branch 或 fallback branch。
- 某个 transaction 是否只是 committed，还是已经 ready/published。

## 4. Data Quality Evidence 与 SLA Readiness

【事实】Foundry Data Expectations 可作为 build-time check，失败时可 abort build，避免坏数据传播；Data Health 可监控 datasets、builds、schedules 等资源并发出告警。

【建议】自建平台不应只记录“任务成功”，而应把质量证据绑定到 output transaction 和 business_date coverage。

最小质量证据：

| 维度 | 例子 |
|---|---|
| Schema | schema version、字段类型、必填列、兼容性结果 |
| Completeness | 预期日期范围、实际覆盖范围、缺失分区、row count |
| Validity | null rate、range check、枚举值、主键唯一性 |
| Consistency | 上下游行数对账、金额对账、跨表一致性 |
| Freshness | 源数据最新 event_time、commit time、SLA deadline |
| Runtime | run status、attempt、耗时、重试、abort 原因 |

`sla_readiness` 应作为发布条件，而不是 dashboard 装饰字段：

```text
ready = transaction_committed
    AND coverage_complete
    AND blocking_quality_checks_passed
    AND upstream_required_dates_ready
    AND freshness_before_deadline
    AND effective_access_requirements_computed
```

【建议】质量发布解耦：transaction commit 后默认状态为 `COMMITTED_NOT_RELEASED`；只有 readiness 通过后才能更新 `active_view_pointer`。

## 5. 权限、Marking 与访问审计

【事实】Foundry 权限由 DAC roles 与 MAC requirements 叠加；Markings/Organizations/Classifications 是强制控制，roles 不能绕过。

【事实】Foundry `Get Access Requirements` API 返回资源所需 Markings 和 Organizations；Organizations 是析取，Markings 是合取。

【事实】`stop_propagating` / `stop_requiring` 只适用于 Markings 和 Organizations，不适用于 roles；只能在 protected branch 上移除，并需要相应审批权限。

【事实】Foundry guidance 明确：给 Dataset 加 Marking 会影响其历史 transactions；在 transform 中移除 Marking 只影响新的 output transactions，旧 transactions 不会被改写。

【建议】自建平台必须把 access requirements 快照绑定到 transaction/view：

- `resource_direct_requirement`：资源上直接配置的 Marking/Organization。
- `transaction_effective_requirement`：当前 transaction/view 因上游 lineage 继承得到的要求。
- `unmarking_rule`：在哪个 protected branch、哪个 input->output、由谁批准移除了哪个 requirement。
- `access_decision`：用户实际访问时满足了哪些 role、marking、organization、scoped session 条件。

### Branch / View / Transaction Access Audit

【事实】Foundry audit logs 用于回答 who / what / when / where，并支持 `audit.3` API 或导出到 Foundry Dataset。

【建议】访问审计不能只写 “user read dataset X”，必须写清楚实际版本坐标：

| 字段 | 说明 |
|---|---|
| `actor_principal_id`, `session_id`, `token_client_id` | 谁访问 |
| `action` | preview/read/download/export/query/build/pointer_update |
| `dataset_id`, `requested_branch`, `resolved_branch` | 请求与实际 branch |
| `requested_pointer`, `resolved_transaction_id`, `view_end_transaction` | 请求与实际 view |
| `fallback_used` | 是否读了 fallback branch |
| `access_result`, `deny_reason` | allow/deny 及原因 |
| `role_snapshot`, `marking_snapshot`, `organization_snapshot` | 决策时权限上下文 |
| `request_id`, `trace_id`, `audit_category` | 关联日志与 SIEM |

任何 active pointer 更新、quality release、rollback、unmarking approval、marking membership change、branch fallback read、export 都应进入审计事件。

## 6. 最小元数据表设计

| 表 | 关键字段 | 说明 |
|---|---|---|
| `dataset_contract` | `dataset_id`, `owner`, `date_contract_type`, `timezone`, `business_calendar`, `sla_policy_id`, `quality_policy_id`, `retention_policy_id` | Dataset 业务与治理契约 |
| `dataset_transaction_ext` | `transaction_id`, `dataset_id`, `branch_name`, `transaction_type`, `state`, `schema_version`, `producer_run_id`, `manifest_id`, `committed_at` | transaction 扩展事实 |
| `active_view_pointer` | `dataset_id`, `branch_name`, `pointer_name`, `transaction_id`, `pointer_policy`, `quality_evidence_id`, `updated_by`, `updated_at` | 可消费版本指针 |
| `partition_manifest` | `manifest_id`, `transaction_id`, `partition_key`, `partition_value`, `business_date_start/end`, `event_time_min/max`, `row_count`, `checksum` | 逻辑分区与覆盖证据 |
| `run_ledger` | `run_id`, `run_type`, `schedule_run_id`, `build_id`, `sync_task_id`, `code_version`, `config_version`, `status`, `attempt`, `started_at`, `finished_at` | 运行账本 |
| `run_input_version` | `run_id`, `input_alias`, `dataset_id`, `requested_branch`, `resolved_branch`, `current_view_start_tx`, `current_view_end_tx`, `processed_start_tx`, `processed_end_tx`, `previous_end_tx`, `last_read_tx` | 输入版本与增量位点 |
| `run_output_transaction` | `run_id`, `output_alias`, `dataset_id`, `branch_name`, `transaction_id`, `write_mode`, `output_business_date_start/end` | 输出 transaction 映射 |
| `coverage_lineage` | `output_transaction_id`, `output_partition_key`, `input_dataset_id`, `input_branch`, `input_start_tx`, `input_end_tx`, `input_business_date_start/end`, `coverage_type`, `completeness_pct` | 覆盖范围血缘 |
| `quality_evidence` | `evidence_id`, `transaction_id`, `run_id`, `rule_set_version`, `status`, `blocking`, `metrics_json`, `failed_rule_count`, `evaluated_at` | 质量证据 |
| `sla_readiness` | `dataset_id`, `business_date`, `transaction_id`, `ready_state`, `coverage_complete`, `quality_passed`, `freshness_deadline`, `ready_at`, `violation_reason` | SLA 可发布状态 |
| `transaction_effective_requirement` | `transaction_id`, `requirement_type`, `requirement_id`, `source_type`, `source_dataset_id`, `unmarking_rule_id` | transaction/view 级权限要求 |
| `access_audit` | `audit_id`, `event_time`, `actor`, `action`, `dataset_id`, `requested_branch`, `resolved_branch`, `resolved_transaction_id`, `access_result`, `deny_reason`, `trace_id` | 访问与审计事实 |

## 7. 主要风险与控制

| 风险 | 结论与控制 |
|---|---|
| 权限绕行 | 禁止消费者绕过 Dataset API 直接读物理文件；Restricted View 不能替代 backing Dataset 权限；export、download、SQL、preview、API 都必须统一经过 transaction/view 鉴权。 |
| View 指针漂移 | 报表、模型、导出任务必须记录 `resolved_transaction_id`；否则 branch head 或 active pointer 变化后无法复现历史结果。 |
| Branch fallback 误判 | Foundry build 可读 fallback branch，但 Data Lineage 选择 Global Branch 时 fallback display 被禁用；审计和 UI 必须展示 requested/resolved branch 差异。 |
| 质量发布解耦缺失 | 禁止生产消费直接读 latest committed transaction；必须通过 `active_view_pointer` 发布通过质量与 SLA readiness 的版本。 |
| `business_date` 混淆 | 禁止用 `processing_date` 替代 `business_date` 做 SLA 或对账，除非 Dataset contract 显式声明。 |
| 补数覆盖冲突 | 同一 `dataset_id + business_date + active_pointer` 只能有一个 active transaction；历史版本用 supersede 关系保留。 |
| 增量 backlog 未追平 | Foundry transaction limit 场景下一次 build 可能只处理部分 batch；`sla_readiness` 必须检查 `last_read_tx == current_view_end_tx` 或记录 partial ready。 |
| Marking removal 历史不对称 | Marking removal 只影响新 output transactions；unmarking 后的下游增量链路必须 re-snapshot 或证明不再依赖旧 marked transaction。 |
| 审计粒度不足 | 审计必须包含 branch/view/transaction 和 access decision snapshot，否则无法证明“谁在何时读了哪一版敏感数据”。 |

## 8. 证据缺口

1. 【证据边界】Foundry 公开文档没有披露 run lineage、quality evidence、access audit 的内部表结构；本文表设计是自建平台最小契约建议，不是 Foundry 内部实现复刻。
2. 【证据边界】公开资料未证明跨 Dataset 多输出 build 的原子提交；设计上应避免把一个 run 的多个 output transactions 当成不可分割事务。
3. 【待验证】Data Connection batch sync 是否可显式写入任意 Dataset feature branch，公开资料不足；目前只确认 sync config branchable、sync task 与 Dataset version lineage。
4. 【待验证】不同语言和不同执行引擎对 Data Expectations、Marking removal、transaction range 观测字段的覆盖率需要真实环境复核。

## 参考资料 URL

- https://www.palantir.com/docs/foundry/data-integration/datasets
- https://www.palantir.com/docs/foundry/data-integration/branching
- https://www.palantir.com/docs/foundry/data-lineage/overview
- https://www.palantir.com/docs/foundry/data-lineage/branching-data-lineage
- https://www.palantir.com/docs/foundry/data-lineage/see-impact-marking-changes
- https://www.palantir.com/docs/foundry/security/markings
- https://www.palantir.com/docs/foundry/api/filesystem-v2-resources/resources/get-access-requirements
- https://www.palantir.com/docs/foundry/building-pipelines/remove-inherited-markings
- https://www.palantir.com/docs/foundry/building-pipelines/remove-markings
- https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations
- https://www.palantir.com/docs/foundry/observability/data-health
- https://www.palantir.com/docs/foundry/security/audit-logs-overview
- https://www.palantir.com/docs/foundry/security/monitor-audit-logs
- https://www.palantir.com/docs/foundry/transforms-python-spark/incremental-transaction-limits
- https://www.palantir.com/docs/foundry/building-pipelines/create-schedule
- https://www.palantir.com/docs/foundry/data-integration/connecting-to-data
- https://www.palantir.com/docs/foundry/data-connection/file-based-syncs
- https://www.palantir.com/docs/foundry/data-connection/set-up-sync
