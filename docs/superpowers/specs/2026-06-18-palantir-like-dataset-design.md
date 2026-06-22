# Palantir-like Dataset 技术方案设计

**日期：** 2026-06-18  
**状态：** Design Approved Draft  
**范围：** P0 + P1 生产闭环  
**目标底座：** Apache Iceberg + 对象存储 + 自研 Dataset Control Plane  
**设计目标：** 在能力上对齐 Palantir Foundry Dataset 的核心语义：Dataset transaction/view、branch、schema version、Marking、quality gate、run ledger、lineage、active pointer 和受控读取。

---

## 1. 总结与洞察

1. 【建议】自研 Dataset 不应等同于 Iceberg table。Iceberg 负责物理 snapshot、manifest、partition 和多引擎基础；Dataset Control Plane 负责平台语义 transaction/view、Marking、发布、质量、血缘和审计。
2. 【建议】P0 必须同时完成 Dataset Kernel 和 Security Kernel：没有受控读写、Marking 和审计，Dataset transaction 只是一层元数据包装，无法对齐 Palantir 的数据治理能力。
3. 【建议】生产消费默认读取 `active_view_pointer(PROD)`，不能直接读取 Iceberg current snapshot 或 Dataset branch head；transaction commit 只证明数据写入成功，不代表可生产消费。
4. 【推断】大规模可行性的关键风险集中在双提交窗口、对象存储旁路、Marking 传播、增量 transaction range、backfill 发布语义、compaction 维护和事件可靠性。
5. 【结论】方案技术可行，评估结论为 `PASS_WITH_CONSTRAINTS`：必须以强控制面、deny-by-default 存储访问、transactional outbox、orphan snapshot quarantine、release gate 和 Marking 审计作为硬约束。

---

## 2. 背景与目标

### 2.1 背景

目标是开发一个能力上对齐 Palantir Foundry Dataset 的数据资产底座。该 Dataset 不是普通表，也不是单纯的数据湖表格式，而是面向生产数据工程、权限治理、质量发布、血缘审计和后续应用消费的控制面。

用户已确认的关键约束：

| 维度 | 决策 |
|---|---|
| 技术底座 | Iceberg-first + 对象存储。 |
| 架构形态 | 强控制面：Dataset Transaction 包住 Iceberg Snapshot。 |
| 范围 | P0 + P1 生产闭环，不进入完整 Pipeline Builder / Ontology / AI 消费层。 |
| 规模 | 千到万级 Dataset，PB 级数据，增量 build 是核心能力。 |
| Marking | 进入 P0，且需要明确实现能力和机制。 |

### 2.2 设计目标

1. 建立 Dataset logical asset、branch、transaction、view、schema version 和 active pointer。
2. 用 Dataset transaction/view 作为对外版本坐标，用 Iceberg snapshot 作为内部物理绑定。
3. 支持受控写入、受控读取、schema contract、增量 transaction range、run ledger、quality gate 和 release gate。
4. 在 P0 实现 Marking：Dataset / transaction / file 级强制访问控制，column 级字段标签与列裁剪，不做 row-level dynamic marking。
5. 形成可行性分析、风险边界和阶段路线，供后续开发计划引用。

### 2.3 非目标

P0/P1 不做以下能力：

1. 不做 row-level dynamic marking。
2. 不承诺跨多个 Dataset 的强原子提交。
3. 不实现完整 Pipeline Builder。
4. 不实现 Ontology object/link/action 映射。
5. 不实现 AI/OSDK 消费层。
6. 不实现复杂多租户 marketplace。
7. 不把 Iceberg branch、Iceberg tag 或 Iceberg current snapshot 直接作为生产语义。

---

## 3. 总体架构

```text
Writer / Reader / Governance Client
        |
Dataset API Gateway
        |
+----------------------+-------------------+----------------+
| Transaction Manager  | View Resolver     | Access Engine  |
+----------------------+-------------------+----------------+
        |
Schema Registry / Run Ledger / Quality Evidence / Lineage Store / Marking Registry
        |
Iceberg Catalog + Iceberg Snapshots + Manifests
        |
Object Storage
```

### 3.1 核心原则

1. **Dataset transaction/view 是对外契约**  
   所有 API、SQL、BI、模型训练、审计、血缘都引用 Dataset transaction/view，而不是直接引用 Iceberg snapshot。

2. **Iceberg snapshot 是内部物理绑定**  
   Iceberg 提供物理一致性、manifest、partition、schema evolution、time travel 和多引擎扫描基础，但不是生产发布的权威状态。

3. **`PROD` 是 Dataset active pointer**  
   `PROD` 指向通过 release gate 的 Dataset transaction。它不是 Iceberg current snapshot，也不是 Iceberg branch。

4. **所有读写导出必须经过 PEP**  
   Dataset Gateway、SQL gateway、Spark credential vending、BI connector、export service 都必须执行同一套 policy enforcement。

5. **Marking 是 P0 一等能力**  
   Marking 不只是标签字段，而是写入、派生、读取、发布、导出和审计的强制约束。

---

## 4. 核心元数据模型

### 4.1 元数据域

| 域 | 核心表 | 职责 |
|---|---|---|
| Asset & Version | `dataset`, `dataset_branch`, `dataset_transaction`, `active_view_pointer` | 管 Dataset 身份、branch 指针、平台 transaction、生产可消费版本。 |
| Schema Contract | `dataset_schema_version`, `schema_compatibility`, `primary_key_contract` | 管 view 级 schema、兼容性和主键/唯一性契约。 |
| Physical Binding | `iceberg_table_binding`, `iceberg_snapshot_binding`, `file_manifest_cache` | 绑定 Dataset transaction 与 Iceberg table/snapshot/manifest。 |
| Run & Lineage | `run_ledger`, `run_input_version`, `run_output_transaction`, `coverage_lineage` | 记录谁生成数据、读了哪些 input transaction range、产出哪个 transaction。 |
| Quality & Release | `quality_evidence`, `release_gate_result`, `sla_readiness` | 记录质量门禁、发布条件、SLA ready 状态。 |
| Permission & Marking | `marking_*`, `resource_requirement`, `transaction_effective_requirement`, `access_decision_audit` | 管资源权限、数据继承 Marking、访问审计。 |
| Operations | `transactional_outbox`, `orphan_snapshot_quarantine`, `maintenance_run` | 管事件可靠性、双提交补偿和 Iceberg 维护任务。 |

### 4.2 关键表

```text
dataset
  dataset_id, path, asset_type, owner, project_id, created_at

dataset_branch
  dataset_id, branch_name, head_transaction_id, parent_branch, parent_transaction_id

dataset_transaction
  transaction_id, dataset_id, branch_name, type, state,
  parent_transaction_id, schema_version_id, producer_run_id,
  committed_at, commit_group_id

iceberg_table_binding
  dataset_id, iceberg_catalog, namespace, table_name, storage_location

iceberg_snapshot_binding
  dataset_id, transaction_id, iceberg_snapshot_id,
  iceberg_parent_snapshot_id, manifest_list_ref, committed_at

dataset_schema_version
  schema_version_id, dataset_id, schema_json, compatibility_hash,
  primary_key_contract_id, created_by_transaction_id

active_view_pointer
  dataset_id, branch_name, pointer_name, transaction_id,
  pointer_version, release_gate_result_id, updated_by, updated_at

run_ledger
  run_id, run_type, schedule_id, build_id, code_version,
  config_version, status, attempt, started_at, finished_at

run_input_version
  run_id, input_alias, dataset_id, requested_branch, resolved_branch,
  previous_end_tx, processed_start_tx, processed_end_tx, current_view_end_tx

run_output_transaction
  run_id, output_alias, dataset_id, branch_name, transaction_id, write_mode

coverage_lineage
  output_transaction_id, input_dataset_id, input_branch,
  input_start_tx, input_end_tx, business_date_range,
  event_time_range, completeness_pct

quality_evidence
  evidence_id, dataset_id, transaction_id, rule_set_version,
  status, blocking, metrics_json, evaluated_at

release_gate_result
  release_gate_result_id, dataset_id, transaction_id,
  status, hard_failures, warnings, waiver_ids, evaluated_at

transactional_outbox
  outbox_id, aggregate_type, aggregate_id, event_type,
  payload_json, status, retry_count, next_retry_at

orphan_snapshot_quarantine
  quarantine_id, dataset_id, iceberg_snapshot_id,
  failed_transaction_id, reason, detected_at, status, cleanup_after
```

---

## 5. API 边界

### 5.1 Write Path API

```text
createDataset(path, contract)
createBranch(dataset, parentBranchOrTransaction)
beginTransaction(dataset, branch, transactionType)
stageFiles(transaction, files)
putSchema(transaction, schema)
commitTransaction(transaction)
abortTransaction(transaction)
```

### 5.2 Read Path API

```text
resolveView(dataset, selector)
getSchema(dataset, selector)
readTable(dataset, selector, projection, predicate)
listFiles(dataset, selector)
getAccessRequirements(dataset, selector)
```

### 5.3 Governance API

```text
addMarking(resource, marking)
computeEffectiveRequirements(transaction)
requestUnmarking(outputTransaction, rule, evidence)
approveUnmarking(request)
recordAccessDecision(request, decision)
setActivePointer(dataset, pointerName, transaction, releaseGateResult)
```

---

## 6. 写入事务设计

### 6.1 Happy Path

```text
1. beginTransaction(dataset, branch, type)
   -> 创建 Dataset OPEN transaction
   -> 分配 staging path
   -> 记录 expected parent branch head

2. stageFiles(transaction)
   -> writer 写 Parquet 到 staging
   -> 生成文件统计、partition stats、row count、checksum

3. validateBeforeCommit(transaction)
   -> schema compatibility
   -> append-only validation
   -> direct marking validation
   -> branch head compare

4. commitIceberg(transaction)
   -> append / overwrite / delete Iceberg files
   -> 生成 Iceberg snapshot_id
   -> 记录 snapshot summary

5. commitDatasetTransaction(transaction)
   -> 绑定 Dataset transaction -> Iceberg snapshot
   -> CAS 更新 dataset_branch.head_transaction_id
   -> transaction 状态变为 COMMITTED
   -> 同控制面事务写 transactional_outbox row

6. async event processing
   -> lineage
   -> quality
   -> marking derivation
   -> downstream build trigger

7. releaseGate(transaction)
   -> hard checks passed 后更新 active_view_pointer(PROD)
```

### 6.2 一致性和隔离

| 决策 | 设计 |
|---|---|
| 对外可见性 | 只有 committed Dataset transaction 对平台读者可见。 |
| Iceberg snapshot 可见性 | Iceberg snapshot 即使已提交，未绑定 committed Dataset transaction 时不对平台读者可见。 |
| 并发控制 | 同一 dataset branch 使用 branch-head CAS；CAS 失败必须重新 resolve、重新 validate。 |
| 隔离级别 | P0 采用 per-branch serializable commit；读取按 resolved transaction 提供 snapshot-style view。 |
| 事件可靠性 | Dataset transaction 与 outbox row 同事务提交，dispatcher 异步投递，消费者幂等。 |

### 6.3 失败补偿

| 场景 | 处理 |
|---|---|
| staging 写失败 | transaction 标记 `ABORTED`，清理 staging 文件。 |
| validate 失败 | transaction 标记 `ABORTED` 或 `FAILED_VALIDATION`，保留失败证据。 |
| Iceberg commit 失败 | transaction 标记 `ABORTED`，清理 staging。 |
| Iceberg commit 成功但 Dataset commit 失败 | 写入 `orphan_snapshot_quarantine`，按 reference-aware expiration 清理。 |
| Dataset commit 成功但事件发送失败 | outbox 重试；reconciliation job 扫描已提交未处理 transaction。 |
| quality 失败 | transaction 保留为 committed，但不更新 `PROD` pointer。 |

---

## 7. 读取与 View Resolver

### 7.1 Selector 语义

| Selector | 用途 |
|---|---|
| `PROD` / active pointer | 生产默认读取，读最新已发布版本。 |
| `branch head` | 开发和调试读取，读指定 branch 最新 committed transaction。 |
| `end_transaction` | 审计、复现、模型训练固定输入。 |
| `timestamp/tag` | P1 可选，先解析为 transaction，再走统一读路径。 |

### 7.2 Read Path

```text
1. Reader request
   -> dataset_id + selector + projection + predicate

2. View Resolver
   -> selector 解析为 resolved_transaction_id
   -> 加载 schema_version
   -> 找到绑定的 Iceberg snapshot_id / manifest
   -> 返回 view descriptor

3. Access Engine
   -> 校验 resource role
   -> 校验 resource marking / organization
   -> 校验 transaction-effective marking / organization
   -> 校验可选 column policy

4. Physical Read
   -> 生成受控 Spark/Trino/Iceberg scan
   -> predicate/projection pushdown
   -> 不暴露底层对象存储永久路径

5. Audit
   -> 记录 requested selector
   -> 记录 resolved branch / transaction / Iceberg snapshot
   -> 记录 policy snapshot、marking snapshot、allow/deny
```

### 7.3 旁路防护

1. Object Storage bucket/prefix 对普通用户 deny-by-default。
2. Iceberg catalog 不向普通用户发放直接读表凭证。
3. Compute engine 通过 Dataset Gateway 或 credential vending 获取受限 token。
4. Token 绑定 dataset、transaction、snapshot、principal、purpose、TTL。
5. Export、download、preview、SQL、BI 都写统一 access audit。

---

## 8. Marking 设计

### 8.1 P0 能力范围

| 能力 | P0 设计 |
|---|---|
| Dataset/resource marking | 支持，作为 resource requirement。 |
| Transaction-effective marking | 支持，作为读取和发布门禁的一等输入。 |
| File-level marking | 支持，用于敏感文件集合和 manifest 追踪。 |
| Column-level marking | 支持字段标签和列裁剪，不做复杂 ABAC。 |
| Row-level marking | 不支持，列为 P2+。 |
| Unmarking / 降标 | 支持受控审批，只影响新 transaction。 |
| Export control | 支持独立 export action 和 export audit。 |

### 8.2 Marking 数据模型

```text
marking_category
  id, name, type, authority_group

marking
  id, category_id, name, description, sensitivity_level

marking_member
  marking_id, principal_id, principal_type, valid_from, valid_to

resource_requirement
  resource_id, requirement_type, requirement_id, source_type, source_resource_id

schema_field_marking
  dataset_id, schema_version_id, field_path, marking_id, source

transaction_effective_requirement
  dataset_id, transaction_id, requirement_type, requirement_id,
  source_input_transaction_id, derivation_id

marking_derivation_evidence
  derivation_id, output_transaction_id, input_transactions,
  inherited_markings, added_markings, removed_markings, rule_version

unmarking_rule
  rule_id, input_marking_id, output_dataset_id, condition,
  evidence_type, approver_policy, valid_from, valid_to

unmarking_approval
  approval_id, rule_id, output_transaction_id, requester,
  approver, evidence_uri, decision, decided_at

access_decision_audit
  audit_id, actor, action, dataset_id, resolved_transaction_id,
  policy_versions, result, deny_reason
```

### 8.3 Marking 传播

默认传播规则：

```text
output_effective_markings
  = union(all input transaction effective markings)
  + directly applied output markings
  - approved unmarking rules
```

写入 / 派生时：

```text
1. Transform run 解析 input transaction range
2. 读取 input transaction_effective_requirement
3. 对所有 input markings 做 union
4. 加上 output dataset/resource 直接要求
5. 应用已批准的 unmarking_rule
6. 写入 marking_derivation_evidence
7. 写入 output transaction_effective_requirement
8. release gate 检查 effective requirements 已计算
```

读取时：

```text
1. resolveView 得到 resolved_transaction_id
2. 加载 resource_requirement
3. 加载 transaction_effective_requirement
4. 加载 principal marking membership
5. 判定 role + marking + organization
6. allow 才生成受控 scan credential
7. 写 access_decision_audit
```

### 8.4 降标规则

1. P0 禁止静默 unmark。
2. 降标必须产生新的 output transaction。
3. 降标必须绑定脱敏、聚合、过滤或人工复核 evidence。
4. 降标必须经过审批。
5. 降标只影响新 transaction，不 retroactive 改历史 transaction。
6. 历史 transaction 的 Marking 如需变更，只能通过 reclassification 流程产生独立审计记录，不能直接修改历史事实。

---

## 9. 增量 Build 与 Run Ledger

### 9.1 增量坐标

增量 build 使用 Dataset transaction range，而不是传统 `dt` 分区作为版本增量坐标。

```text
input range = dataset_id + branch + previous_end_tx + current_view_end_tx
```

业务日期、事件时间和覆盖范围保留在 coverage manifest 中：

```text
business_date
event_time_min/max
snapshot_date
data_interval
coverage_complete
row_count
checksum
```

### 9.2 Build Flow

```text
1. schedule/event/manual trigger
2. resolve input branch and transaction ranges
3. execute transform with read_mode: added | current | previous
4. write output transaction with write_mode: append | modify | replace
5. record run_input_version and run_output_transaction
6. compute coverage_lineage
7. run quality checks
8. compute effective markings
9. release gate decides active pointer update
```

### 9.3 Backfill

1. Backfill 默认写独立 branch 或 staged transaction。
2. Backfill 不直接推进 `PROD`。
3. Backfill promotion 必须经过 release gate。
4. Backfill 产生新 output transaction，不覆盖历史 transaction。
5. 如果 backfill 覆盖已有 business_date，需要记录 supersede relationship。
6. Backfill 与实时增量并发时，active pointer 更新必须 CAS，并检查 coverage freshness。

---

## 10. Quality、Release 与 Active Pointer

### 10.1 Release 状态机

```text
STAGED
-> VALIDATING
-> PARTIALLY_READY | BLOCKED | RELEASED
-> ROLLED_BACK
```

### 10.2 Release Gate

```text
can_publish =
  transaction_committed
  AND schema_compatible
  AND hard_quality_checks_passed
  AND coverage_complete_or_declared_partial
  AND effective_markings_computed
  AND no_critical_security_violation
```

### 10.3 Active Pointer

| Pointer | 含义 |
|---|---|
| `HEAD` | branch 当前最新 committed transaction，由 branch 指针表达。 |
| `PROD` | 生产默认读取 transaction，必须通过 release gate。 |
| `LATEST_PASSED` | 最新通过硬门禁的 transaction。 |
| `PINNED` | 固定版本，用于审计、模型训练和报表复现。 |
| `ROLLBACK` | 回滚到历史 transaction 的发布指针。 |

`active_view_pointer` 更新必须 CAS，必须写审计，必须绑定 `release_gate_result_id`。

### 10.4 Partial Readiness

P1 将 `PARTIALLY_READY` 作为运维/发布状态，不作为普通生产用户默认 selector。授权运维或特殊消费者可查询 partial release，但 audit 必须标记该 view 非完整生产发布。

---

## 11. Iceberg 相关决策

### 11.1 Dataset Pointer 与 Iceberg Ref 边界

1. Dataset active pointer 是生产发布权威。
2. Iceberg branch/tag/ref 可作为内部优化，但不是对外语义源。
3. 读取必须先 resolve Dataset transaction，再读取绑定的 Iceberg snapshot。
4. 如果 Iceberg catalog 支持 branch/tag，可用于 staging、maintenance 或 pinned snapshot，但所有可见性仍由 Dataset Control Plane 控制。

### 11.2 Delete / Update / Merge

P0/P1 策略：

| 操作 | 设计 |
|---|---|
| APPEND | 默认增量写入方式。 |
| SNAPSHOT / REPLACE | 用于全量重算、backfill promotion、schema breaking rebuild。 |
| UPDATE / MERGE | P1 支持，优先通过 Iceberg merge/delete 能力实现，但必须记录 Dataset transaction type。 |
| DELETE | 用于逻辑删除、合规删除或 retention；必须进入 transaction 和 audit。 |

多引擎兼容要求：

1. P0 支持 Spark 写、Spark/Trino 读。
2. P1 扩展 Flink 读写或其他引擎前，必须验证 delete file、schema evolution、snapshot id scan、branch/tag 支持。
3. 不支持指定 snapshot id 或无法执行 controlled scan 的引擎不能作为受控生产读取入口。

### 11.3 Maintenance

PB 级和增量 build 场景下，maintenance 是核心能力：

```text
rewrite data files
rewrite manifests
rewrite delete files
expire snapshots
remove orphan files
partition/sort evolution
```

所有 maintenance 都必须进入 `maintenance_run` 和 audit。可能改变生产可见数据或性能特征的 maintenance 需要经过 release gate 或安全门禁。

---

## 12. 可观测性与 SLO

P0/P1 必须记录以下指标：

| 指标 | 用途 |
|---|---|
| transaction commit latency | 事务提交性能。 |
| Iceberg commit failure rate | 物理提交稳定性。 |
| Dataset CAS conflict rate | 并发冲突和重试压力。 |
| orphan snapshot count / age | 双提交窗口补偿健康度。 |
| outbox lag / retry count | 事件可靠性。 |
| release gate pass/fail/waiver rate | 发布质量。 |
| active pointer freshness | 生产数据新鲜度。 |
| input transaction range lag | 增量积压。 |
| quality evidence missing rate | 质量证据完整性。 |
| marking denied read count | 权限拒绝态势。 |
| audit write failure count | 审计可靠性。 |
| read resolution latency | 读取控制面性能。 |

建议 SLO：

| SLO | 初始目标 |
|---|---|
| View resolution p95 | 小于 200ms，不含物理 scan。 |
| Access decision p95 | 小于 100ms，缓存命中场景。 |
| Transaction commit control-plane p95 | 小于 2s，不含 Iceberg 写文件时间。 |
| Outbox event delivery p99 | 5 分钟内。 |
| Orphan snapshot quarantine cleanup | 24 小时内完成或告警。 |
| Audit durability | allow/deny 决策必须同步落库或阻断高风险读取。 |

---

## 13. 可行性分析

### 13.1 结论

方案结论：`PASS_WITH_CONSTRAINTS`。

技术可行，因为 Iceberg 已提供物理表格式能力，自研 Control Plane 可以补齐 Palantir-like Dataset 的语义层。但该方案的复杂度主要来自治理和生产控制，不是来自 Parquet 或 Iceberg API。

### 13.2 可行性矩阵

| 维度 | 判断 | 说明 |
|---|---|---|
| 技术可行性 | 高 | Iceberg 覆盖 snapshot、manifest、partition、schema evolution、多引擎基础。 |
| Palantir-like 对齐度 | 中高 | 强控制面可补 transaction/view、active pointer、Marking、quality、lineage。 |
| P0 落地难度 | 中高 | 难点是受控读写和 Marking 审计，不是基本读写。 |
| P1 生产难度 | 高 | 增量 range、backfill、release gate、compaction、observability 都要做成平台能力。 |
| 最大风险 | 安全与一致性 | Marking 旁路、双提交窗口、发布竞态、事件丢失。 |

### 13.3 不可接受风险

| 风险 | 处理 |
|---|---|
| 允许用户直接读 Iceberg catalog/object storage | 不接受，破坏 Marking。 |
| 用 Iceberg current snapshot 作为生产最新版本 | 不接受，破坏 active pointer 和 release gate。 |
| 静默 unmark 历史 transaction | 不接受，破坏审计。 |
| quality 失败仍自动推进 PROD | 不接受，破坏生产闭环。 |
| 没有 outbox/reconciliation 的事件触发 | 不接受，增量链路不可恢复。 |

---

## 14. 阶段路线图

### P0-A：Dataset Kernel

交付：

1. Dataset logical asset。
2. Branch 和 transaction。
3. Iceberg table/snapshot binding。
4. Schema registry。
5. View resolver。
6. Write API 和 read API。
7. Orphan snapshot quarantine。

验收：

```text
同一 Dataset 可在两个 branch 上提交不同 transaction；
读取可指定 branch / transaction / PROD；
schema 可按 view 查询；
Iceberg snapshot 未绑定 committed Dataset transaction 时不可被平台读者读取。
```

### P0-B：Security / Marking Kernel

交付：

1. Marking registry。
2. Resource requirement。
3. Transaction-effective requirement。
4. Marking derivation evidence。
5. Controlled scan credential。
6. Access decision audit。
7. Object store / Iceberg catalog deny-by-default。

验收：

```text
用户有 Dataset role 但缺 Marking 时读取被拒绝；
派生 transaction 默认继承 input markings；
降标必须审批并产生新 transaction；
审计可复现 resolved transaction、Iceberg snapshot 和 policy versions。
```

### P1-A：Production Build / Incremental

交付：

1. Run ledger。
2. Input transaction range。
3. Output transaction mapping。
4. Coverage lineage。
5. Transactional outbox。
6. Downstream trigger。
7. Backfill branch / promotion flow。

验收：

```text
下游 build 能基于 input transaction range 增量运行；
backfill 不直接覆盖 PROD；
上游 rollback/pointer change 可触发 downstream invalidation；
事件丢失可通过 reconciliation job 恢复。
```

### P1-B：Release / Quality / Operations

交付：

1. Quality evidence。
2. Release gate。
3. Active pointer。
4. Release 状态机。
5. Maintenance run。
6. Compaction / snapshot expiration / orphan cleanup。
7. SLO metrics and alerts。

验收：

```text
质量失败不会推进 PROD；
release pointer 更新可 CAS、可审计、可回滚；
partial readiness 有明确状态；
compaction 和 maintenance 可追溯、可告警。
```

---

## 15. 专家评估吸收结论

本设计经过四类专家视角评估，结论均为 `PASS_WITH_CONCERNS`，主路线成立，但必须补齐硬约束。已吸收如下：

| 专家视角 | 主要问题 | 本设计处理 |
|---|---|---|
| 数据平台架构 | Marking 粒度、transaction isolation、orphan snapshot、incremental range、active pointer 原子性 | 明确 P0 Marking 粒度、per-branch serializable commit、quarantine、per dataset+branch range、pointer CAS。 |
| Iceberg | 双提交窗口、Iceberg ref 边界、delete/update、compaction、多引擎能力矩阵 | 明确 Dataset pointer 为权威、Iceberg ref 内部化、maintenance run、多引擎 P0 限定。 |
| 权限治理 | Marking propagation、unmarking、旁路访问、export、policy cache/audit | 增加 Marking 章节、deny-by-default、export audit、policy version audit。 |
| 数据质量/运维 | release gate、backfill、partial readiness、outbox、observability | 增加 release 状态机、backfill promotion、transactional outbox、SLO 指标。 |

---

## 16. 后续边界

本 spec 只完成设计，不进入开发计划或实现。后续若进入开发，应另起 implementation plan，至少拆成：

1. Dataset Kernel implementation plan。
2. Marking / Access Engine implementation plan。
3. Incremental Build / Run Ledger implementation plan。
4. Release Gate / Quality / Operations implementation plan。

---

## 17. 自审记录

### Placeholder Scan

未保留占位符或空白章节。

### Internal Consistency

设计中统一采用 Dataset transaction/view 作为对外版本坐标，Iceberg snapshot 作为内部物理绑定；`PROD` 始终是 Dataset active pointer。

### Scope Check

范围限定为 P0 + P1 生产闭环，不包含 Pipeline Builder、Ontology、AI/OSDK 和 row-level marking。

### Ambiguity Check

已明确 Marking 粒度、降标规则、读取旁路、backfill promotion、release gate、partial readiness 和 maintenance 的 P0/P1 边界。
