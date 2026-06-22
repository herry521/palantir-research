# Palantir Dataset 实现机制与自研对齐设计

**日期：** 2026-06-17  
**类型：** 技术调研 / 自研平台架构设计  
**覆盖方向：** Foundry Dataset / transaction / branch / schema / build / lineage / permission / quality / self-build blueprint

---

## 1. 总结与洞察

1. 【事实】Palantir Foundry Dataset 的公开稳定模型是“文件集合 + schema 元数据 + transaction / branch / view 版本系统”；它可以表示结构化、半结构化和非结构化数据，不等同于传统数仓的 `table + dt`。
2. 【事实】Dataset branch 是指向最新 transaction 的指针；schema 可按 `branchName`、`endTransactionRid`、`versionId` 定位；这说明 Dataset 的结构解释跟随 view/version，而不是只有一份静态表定义。
3. 【推断】Foundry Dataset 的核心能力不是单一存储格式，而是一个控制面：事务提交、分支隔离、schema contract、build 增量、血缘、权限 Marking、质量证据和消费 API 共同定义“可治理数据资产”。
4. 【建议】自研若要“能力完全对齐”，不能只选 Iceberg/Delta/Hudi 或只做元数据目录；应建设 Dataset Control Plane，并把物理文件、事务 view、业务日期、质量发布、权限要求和血缘证据拆开建模。
5. 【建议】最小可落地路线是先做 P0 Dataset transaction/view + schema registry + run ledger + access gateway，再做 P1 build/incremental + quality gate + active pointer，最后补 P2 branch workspace、低代码 Builder、Ontology 映射和 AI/应用消费层。

---

## 2. 研究边界

本文只基于 Palantir 公开文档、本仓库既有调研和通用数据平台工程判断。Palantir 的内部数据库表、服务拆分、锁实现、存储引擎和性能优化细节未公开，因此本文不声称复原私有实现。

本文把结论分成三类：

| 标记 | 含义 |
|---|---|
| 【事实】 | Palantir 公开文档或本仓库已有证据能直接支持。 |
| 【推断】 | 由公开事实和平台工程常识拼接得到的合理实现判断。 |
| 【建议】 | 面向自研平台的设计选择，不代表 Palantir 内部实现。 |

---

## 3. Palantir Dataset 对外暴露的核心语义

### 3.1 Dataset 是数据资产，不只是表

【事实】Palantir 文档说明，Foundry 的 data integration layer 使用 Dataset 存储和表示结构化、半结构化、非结构化数据。结构化数据通常由 Parquet 等开放格式文件和列元数据组成，schema 与 Dataset 一起存储；非结构化 Dataset 可包含图片、视频、PDF 等文件且不一定有 schema。

【推断】Dataset 的一阶抽象是“可治理的数据资产容器”，不是关系型数据库表。表只是 Dataset 在结构化场景下的一种表现。

自研启示：

```text
Dataset
  = logical asset id
  + physical files / objects
  + metadata and schema
  + transaction history
  + branch/view resolver
  + governance and lineage context
```

### 3.2 Transaction 是内容变化的原子记录

【事实】本仓库既有证据已整理 Foundry Dataset transaction 的公开语义：transaction 有 `OPEN`、`COMMITTED`、`ABORTED` 生命周期，类型包括 `SNAPSHOT`、`APPEND`、`UPDATE`、`DELETE`。

【事实】Dataset view 由 transaction history 计算。一个 view 可理解为从最近的 `SNAPSHOT` 开始，依次应用后续 `APPEND`、`UPDATE`、`DELETE` 得到的有效文件集合。

【推断】这类模型的关键不是“目录覆盖”，而是“文件引用集合的版本化变化”。物理文件可以在对象存储或 HDFS 上，逻辑可见性由 transaction metadata 决定。

### 3.3 Branch 是 transaction 指针

【事实】Palantir Branching 文档将 Dataset、branch、transaction 类比为 Git repository、branch、commit；branch 是指向该 branch 最新 transaction 的指针。某 branch 提交 transaction 不改变其他 branch 的 transactions 和 views；Dataset branch 不支持像 Git 那样 merge 数据内容。

【事实】Foundry build 在用户指定 branch 上运行，job 只修改该 build branch 上的 datasets；build 还会结合 fallback branch 解析输入输出。

【推断】Foundry 的 branch 同时隔离数据版本和逻辑变更实验。它不是简单复制一张表，而是让 build、lineage、schema 和权限都能围绕 branch/view 解释。

### 3.4 Schema 绑定到 view/version

【事实】`Get Dataset Schema` API 支持 `branchName`、`endTransactionRid`、`versionId` 参数；如果不提供 `endTransactionRid`，使用最新 committed version。返回体包含 `branchName`、`endTransactionRid` 和 schema `versionId`。

【推断】Dataset schema 不是只挂在 `dataset_id` 上的一份静态 DDL。更准确的坐标是：

```text
schema = schema(dataset_id, branch_name, end_transaction_id, schema_version_id)
```

自研时应区分：

| 概念 | 用途 |
|---|---|
| declared schema / expected schema | 设计期、编译期、CI、低代码 Builder 的契约。 |
| materialized schema version | 某个 committed view 实际暴露给读取方的结构解释。 |
| schema compatibility policy | 约束加列、删列、改类型、改 nullability、改主键的兼容性。 |

### 3.5 Hive-style partitioning 是布局优化

【事实】Palantir Hive-style partitioning 文档把它定义为优化 Dataset 数据布局的方法，用于提升按特定列过滤的查询性能；高基数字段会带来过多文件，影响写入和读取性能。

【推断】`partition_cols` 不等于 Dataset 的版本坐标。`record_date`、`department`、`business_date` 可以用于文件布局和裁剪，但不能替代 transaction/view、run、quality 和 lineage。

---

## 4. Palantir Dataset 可能的实现分层

以下为【推断】，用于指导自研架构，不代表 Palantir 私有实现。

```text
Client / SQL / Transform / Ontology / OSDK
                |
        Dataset API Gateway
                |
  +-------------+--------------+
  |                            |
Access Decision Engine   View Resolution Engine
  |                            |
RBAC + Marking + Org     branch/pointer/time -> transaction/view
  |                            |
  +-------------+--------------+
                |
       Dataset Metadata Control Plane
                |
  +-------------+--------------+----------------+
  |             |              |                |
Transaction   Schema       Lineage/Run      Quality/Health
Ledger        Registry     Ledger           Evidence
  |
Physical Manifest / File Index
  |
Object Store / HDFS / Lakehouse Table Format
```

### 4.1 存储层

【推断】结构化 Dataset 可落在 Parquet/Avro/Text 等文件格式上，非结构化 Dataset 则是对象文件集合。对象存储路径不应直接暴露给普通消费者；消费者应通过 Dataset API、SQL gateway、compute runtime 或受控导出读取。

自研设计：

| 数据形态 | 推荐物理底座 | 注意事项 |
|---|---|---|
| 结构化批数据 | Apache Iceberg 优先；Delta/Hudi 可选 | 不要把表格式能力误认为完整 Dataset 能力。 |
| 事件追加数据 | Iceberg append + manifest 或 Hudi/Delta CDC | 需要 transaction range 和 watermark 元数据。 |
| 非结构化文件 | 对象存储 + manifest + metadata extractor | schema 可选，重点是文件级权限、索引和派生结构化结果。 |
| 流数据 | Kafka/Pulsar + stream checkpoint +落地 Dataset | 流主键、checkpoint、exactly-once 语义要独立建模。 |

### 4.2 元数据控制面

【建议】自研 Dataset 的真正核心是 metadata control plane。最小对象模型：

```text
dataset
dataset_branch
dataset_transaction
dataset_transaction_file
dataset_view_snapshot
dataset_schema_version
dataset_contract
run_ledger
run_input_version
run_output_transaction
coverage_lineage
quality_evidence
active_view_pointer
resource_requirement
transaction_effective_requirement
access_audit
```

其中 `dataset_transaction_file` 记录逻辑文件变化，`dataset_view_snapshot` 可做 view resolution 加速，`active_view_pointer` 负责把“已提交”与“可消费”解耦。

### 4.3 Transaction Manager

【建议】事务提交流程应采用两阶段思想：

```text
begin_transaction(dataset, branch, type)
  -> create OPEN transaction
  -> allocate staging path
  -> writer writes files
  -> validate schema / file stats / partition manifest / append-only rule
  -> acquire branch commit lock
  -> compare branch head
  -> commit metadata atomically
  -> publish dataset_transaction_committed event
  -> trigger quality / lineage / downstream build
```

关键约束：

| 约束 | 说明 |
|---|---|
| one open transaction per branch | 降低并发提交冲突和 view 解释复杂度。 |
| append-only validation | `APPEND` 不允许覆盖当前 view 已有文件。 |
| branch head compare-and-swap | 防止两个 writer 基于同一 head 并发提交。 |
| metadata commit before exposure | 文件写入成功不等于 Dataset view 可见。 |
| orphan cleanup | aborted transaction 和未引用 staging files 需要 GC。 |

### 4.4 View Resolution Engine

【建议】读取方不应直接读 branch head，而应先解析 view：

```text
resolve_view(dataset_id, selector):
  selector = branch head
           | end_transaction
           | active_pointer
           | timestamp
           | tag / release

  1. resolve branch / pointer / timestamp to end_transaction
  2. locate nearest materialized view snapshot
  3. replay transaction deltas until end_transaction
  4. return file manifest + schema_version + effective_requirements
```

性能上不能每次从头 replay，应做 view checkpoint：

| 加速对象 | 用途 |
|---|---|
| materialized view snapshot | 保存某个 transaction 的有效文件集合摘要。 |
| file-level manifest index | 支撑 projection、partition pruning、file stats pruning。 |
| transaction range index | 支撑增量 build 读取 `previous_end_tx -> current_end_tx`。 |
| schema compatibility cache | 快速判断下游是否受 schema change 影响。 |

---

## 5. 自研 Dataset 的完整能力设计

### 5.1 核心概念坐标

自研平台应明确区分六类坐标：

| 坐标 | 回答的问题 | 典型字段 |
|---|---|---|
| 资产坐标 | 这是哪个数据资产？ | `dataset_id`, `path`, `owner`, `project_id` |
| 版本坐标 | 读的是哪个数据版本？ | `branch_name`, `transaction_id`, `view_id`, `schema_version` |
| 执行坐标 | 谁生成了它？ | `run_id`, `build_id`, `job_id`, `code_version`, `config_version` |
| 业务时间坐标 | 数据代表哪个业务周期？ | `business_date`, `event_time`, `snapshot_date`, `data_interval` |
| 发布坐标 | 哪个版本可被生产消费？ | `active_pointer`, `quality_status`, `sla_readiness` |
| 权限坐标 | 谁能读、写、导出？ | `resource_role`, `marking`, `organization`, `policy_snapshot` |

不要把这些坐标压缩成 `dt`、`run_id` 或 `transaction_id` 一个字段。

### 5.2 Dataset API

最小 API 应覆盖：

| API | 用途 |
|---|---|
| `createDataset(path, contract)` | 创建逻辑数据资产和初始契约。 |
| `createBranch(dataset, parentBranchOrTx)` | 创建 branch 指针。 |
| `beginTransaction(dataset, branch, type)` | 打开写入事务。 |
| `uploadFile / stageFiles` | 写入 staging 文件。 |
| `putSchema(transaction, schema)` | 绑定或更新 schema version。 |
| `commitTransaction(transaction)` | 原子提交 metadata。 |
| `abortTransaction(transaction)` | 中止并释放 staging。 |
| `getSchema(dataset, branch, endTx, version)` | 查询 view/schema。 |
| `readTable(dataset, selector, projection, predicate)` | 通过 gateway 读结构化数据。 |
| `listFiles(dataset, selector)` | 读取文件 manifest。 |
| `setActivePointer(dataset, pointer, tx, evidence)` | 发布生产可消费版本。 |
| `getLineage(dataset, tx)` | 查询 transaction/run 级血缘。 |
| `getAccessRequirements(dataset, selector)` | 查询资源和数据访问要求。 |

### 5.3 Schema Contract

【建议】schema 体系至少包括：

| 能力 | 设计要点 |
|---|---|
| schema versioning | 每个 committed view 绑定 materialized schema version。 |
| compatibility check | 加列、删列、改类型、改 nullability、改顺序、改主键分别定义策略。 |
| declared vs materialized | Builder/Transform 的预期 schema 与实际输出 schema 分开保存。 |
| primary key as contract | 主键不是 Dataset 天然属性，应作为可声明质量/业务契约。 |
| schema diff impact | 下游 Pipeline、Ontology、BI、API 能看到影响分析。 |

### 5.4 Build 与增量

【事实】Foundry incremental pipelines 以 Dataset transaction 随时间变化为基础；常见模式处理新增 transaction，但也要面对 snapshot/recompute。

【建议】自研增量 build 不应只扫 `dt=今天`，而应记录：

```text
run_id
input_dataset_id
requested_branch
resolved_branch
previous_end_transaction
current_view_end_transaction
processed_start_transaction
processed_end_transaction
read_mode: added | current | previous
output_write_mode: append | modify | replace
output_transaction_id
```

增量策略：

| 输入变化 | 默认策略 |
|---|---|
| 只有 APPEND | 允许 delta read。 |
| UPDATE / DELETE | fallback full recompute，或要求 transform 显式声明能处理。 |
| schema breaking change | 阻断增量或强制 semantic version bump。 |
| transaction backlog 太大 | 分段处理并标记 output stale，直到追平。 |

### 5.5 Active Pointer 与发布语义

【建议】`COMMITTED` 不应直接等于生产可读。应引入 active pointer：

```text
HEAD             = branch 最新提交
LATEST_PASSED    = 最新通过质量门禁的版本
PROD             = 生产消费者默认读取版本
PINNED           = 固定版本，用于审计/模型/报表复现
ROLLBACK         = 回滚指针
```

发布条件：

```text
can_publish =
  transaction_committed
  AND schema_compatible
  AND blocking_expectations_passed
  AND coverage_complete
  AND freshness_sla_met
  AND effective_access_requirements_computed
  AND owner_or_release_policy_approved
```

这个设计比直接读 branch head 稍复杂，但能避免坏数据刚 commit 就被报表、模型、API 消费。

### 5.6 权限、Marking 与审计

【事实】Foundry Markings 提供额外访问控制；用户需要满足资源上所有普通 Markings 才能访问。公开文档还说明 Markings/Organizations 可随资源和依赖传播，并在某些场景下受控移除。

【建议】自研访问控制应分两层：

```text
Resource access:
  project / folder / dataset role
  direct resource marking / organization

Data access:
  transaction/view effective requirements
  lineage-inherited markings
  row / column / object policy
  export / external route policy
```

访问审计必须记录 resolved view，而不是只记录 dataset：

| 字段 | 说明 |
|---|---|
| `actor`, `client`, `session_id` | 谁访问。 |
| `dataset_id`, `requested_selector` | 请求的资产和选择器。 |
| `resolved_branch`, `resolved_transaction_id` | 实际读到的版本。 |
| `policy_snapshot` | 判定时角色、Marking、Organization 状态。 |
| `access_result`, `deny_reason` | 放行或拒绝原因。 |
| `export_destination` | 若导出到外部系统，记录通道和脱敏结果。 |

### 5.7 质量、健康与可观测性

【事实】Palantir Health Checks 覆盖 dataset status、time、size、content、schema、freshness 等；Pipeline Builder output expectations 支持 primary key 和 row count，失败可使 build 失败。

【建议】自研质量层拆成三类：

| 类型 | 触发点 | 失败语义 |
|---|---|---|
| Build-time expectations | build job 内 | `FAIL` abort，`WARN` 继续但记录。 |
| Runtime health checks | transaction update / timer / manual | 告警、issue，不默认改写数据。 |
| Release gate | active pointer 更新前 | 阻断生产发布。 |

质量结果必须绑定 transaction、run 和 branch：

```text
quality_evidence(
  rule_id,
  dataset_id,
  branch_name,
  transaction_id,
  run_id,
  status,
  blocking,
  metrics_json,
  evaluated_at
)
```

---

## 6. 自研参考元数据表

| 表 | 关键字段 | 说明 |
|---|---|---|
| `dataset` | `dataset_id`, `path`, `asset_type`, `owner`, `project_id`, `created_at` | 逻辑数据资产。 |
| `dataset_contract` | `dataset_id`, `schema_policy`, `pk_contract`, `date_contract`, `retention_policy`, `quality_policy` | 业务与治理契约。 |
| `dataset_branch` | `dataset_id`, `branch_name`, `head_transaction_id`, `parent_branch`, `parent_transaction_id` | branch 指针。 |
| `dataset_transaction` | `transaction_id`, `dataset_id`, `branch_name`, `type`, `state`, `parent_transaction_id`, `schema_version_id`, `producer_run_id` | 事务事实。 |
| `dataset_transaction_file` | `transaction_id`, `file_path`, `operation`, `content_hash`, `row_count`, `byte_size`, `partition_values` | 文件 delta。 |
| `dataset_view_snapshot` | `dataset_id`, `branch_name`, `end_transaction_id`, `manifest_ref`, `file_count`, `byte_size` | view resolution checkpoint。 |
| `dataset_schema_version` | `schema_version_id`, `dataset_id`, `schema_json`, `compatibility_hash`, `created_by_tx` | schema 版本。 |
| `active_view_pointer` | `dataset_id`, `branch_name`, `pointer_name`, `transaction_id`, `quality_evidence_id`, `updated_by` | 可消费版本指针。 |
| `run_ledger` | `run_id`, `run_type`, `build_id`, `job_id`, `code_version`, `config_version`, `status` | 执行账本。 |
| `run_input_version` | `run_id`, `input_alias`, `dataset_id`, `resolved_branch`, `previous_end_tx`, `processed_start_tx`, `processed_end_tx` | 输入版本和增量位点。 |
| `run_output_transaction` | `run_id`, `output_alias`, `dataset_id`, `branch_name`, `transaction_id`, `write_mode` | 输出 transaction 映射。 |
| `coverage_lineage` | `output_transaction_id`, `input_dataset_id`, `input_start_tx`, `input_end_tx`, `business_date_range`, `completeness_pct` | 覆盖范围血缘。 |
| `quality_evidence` | `evidence_id`, `dataset_id`, `transaction_id`, `rule_set_version`, `status`, `blocking`, `metrics_json` | 质量证据。 |
| `transaction_effective_requirement` | `transaction_id`, `requirement_type`, `requirement_id`, `source_dataset_id`, `source_transaction_id` | view/data 级权限要求。 |
| `access_audit` | `audit_id`, `actor`, `dataset_id`, `requested_selector`, `resolved_transaction_id`, `access_result`, `trace_id` | 访问审计。 |

---

## 7. 能力对齐路线图

### P0：Dataset 内核

必须先完成：

1. Dataset logical asset、branch、transaction、view resolution。
2. Staging write + metadata atomic commit + abort/GC。
3. Schema registry、schema version、schema compatibility。
4. Read gateway，禁止普通消费者绕过权限直接读物理路径。
5. Run ledger、input/output transaction mapping。
6. 基础 RBAC + resource marking + access audit。

验收标准：

```text
同一个 dataset 可在两个 branch 上提交不同 transaction；
读取时能指定 branch/head/end_transaction；
schema 能按 view 查询；
任意读取审计能复现 resolved transaction 和文件 manifest。
```

### P1：生产可用

继续补：

1. Incremental build：transaction range、read mode、write mode、semantic version。
2. Active pointer：`HEAD`、`LATEST_PASSED`、`PROD`、rollback。
3. Quality expectations：schema、row count、primary key、freshness、content checks。
4. Coverage manifest：business_date、event_time、row_count、checksum。
5. Lineage graph：dataset-level + transaction/run-level。
6. Marking propagation：沿资源层级和直接数据依赖传播。

验收标准：

```text
生产消费者默认读 PROD pointer；
坏数据 transaction committed 后不会自动发布；
某个业务日期的当前生产版本能追溯到 output transaction、producer run 和 input transaction range。
```

### P2：Foundry-like 体验

建设：

1. Branch workspace：代码分支与数据分支联动、fallback branch、proposal/merge 检查。
2. Pipeline Builder：低代码 DAG、表达式类型系统、schema impact、unit test。
3. Data Lineage UI：branch-aware、build helper、health tab。
4. Monitoring Views：scope-based health monitoring、告警、issue、外部通知脱敏。
5. Ontology 映射：Dataset -> Object Type / Link Type / Action Type。
6. OSDK / API：围绕对象、数据集和安全策略的应用消费。

### P3：高级对齐

可选增强：

1. 多引擎统一：Spark、Flink、SQL、Python、Java、Ray。
2. Snapshot compaction、file clustering、projection、cost-based pruning。
3. Cross-dataset commit group 和一致性发布。
4. Fine-grained row/property policy 与 query rewriting。
5. Data product marketplace、模板安装、跨租户共享。
6. AI agent 可解释访问：每次工具调用绑定 resolved view、policy snapshot 和 approval。

---

## 8. 与开源组件的映射

| 能力 | 可用组件 | 是否足够 |
|---|---|---|
| ACID 表存储 | Apache Iceberg / Delta Lake / Apache Hudi | 只覆盖部分结构化存储和快照能力，不覆盖完整 Dataset 控制面。 |
| 对象存储 | S3 / GCS / OSS / HDFS | 只提供物理文件底座。 |
| 元数据目录 | Hive Metastore / Nessie / DataHub / OpenMetadata | 目录、血缘、分支能力可复用，但需要补 transaction/run/quality/access 闭环。 |
| 编排 | Airflow / Dagster / Argo / DolphinScheduler | 能运行任务，但不天然理解 Dataset transaction range。 |
| 计算 | Spark / Flink / Trino / DuckDB | 执行引擎，不是 Dataset 治理层。 |
| 权限 | Ranger / Lake Formation / OPA / OpenFGA | 可支撑部分访问控制，但需补 Marking 传播、view 级审计和导出策略。 |
| 质量 | Great Expectations / Deequ / Soda | 可支撑规则执行，但需绑定 build、transaction、active pointer 和 lineage。 |

推荐组合：

```text
Iceberg/Nessie or Delta
  + Dataset Control Plane
  + Spark/Flink/Trino gateways
  + OpenFGA/OPA/Ranger-style authorization
  + DataHub/OpenMetadata-style catalog lineage
  + Great Expectations/Deequ-style quality DSL
  + custom active pointer / transaction range / marking propagation
```

---

## 9. 关键风险

| 风险 | 控制方式 |
|---|---|
| 把 Iceberg snapshot 当成完整 Dataset transaction | 在 Iceberg snapshot 之外保留平台 transaction、run、schema、quality、permission 元数据。 |
| 生产读取 branch head | 默认走 active pointer，branch head 只用于开发或受控场景。 |
| 业务日期与 transaction 混淆 | `business_date`、`event_time`、`processing_time`、`transaction_id` 分开建模。 |
| Schema 漂移破坏下游 | 建 schema compatibility policy、CI impact check 和 breaking-change workflow。 |
| 权限绕过 | 所有 SQL/API/export/preview 都走统一 read gateway；物理路径不直接开放。 |
| Marking 传播不可解释 | `transaction_effective_requirement` 记录 requirement 来源和移除审批。 |
| 增量处理丢事务 | run ledger 记录 processed transaction range，发布前检查是否追平。 |
| 质量结果不可复现 | quality evidence 绑定 transaction、run、rule_set_version 和 branch。 |
| 多输出原子性误判 | 除非明确实现 commit group，否则按单 Dataset 原子提交设计。 |

---

## 10. 参考资料

Palantir 官方资料：

- [Foundry Datasets](https://www.palantir.com/docs/foundry/data-integration/datasets)
- [Foundry Branching](https://www.palantir.com/docs/foundry/data-integration/branching)
- [Get Dataset Schema API](https://www.palantir.com/docs/foundry/api/v2/datasets-v2-resources/datasets/get-dataset-schema)
- [Incremental pipelines overview](https://www.palantir.com/docs/foundry/building-pipelines/incremental-overview)
- [Hive-style partitioning](https://www.palantir.com/docs/foundry/optimizing-pipelines/hive-style-partitioning)
- [Build datasets from Data Lineage](https://www.palantir.com/docs/foundry/data-lineage/build-datasets)
- [Markings](https://www.palantir.com/docs/foundry/security/markings)
- [Health checks](https://www.palantir.com/docs/foundry/data-integration/health-checks)
- [Pipeline Builder core concepts](https://www.palantir.com/docs/foundry/pipeline-builder/core-concepts)

本仓库相关结论：

- [Dataset 主题索引](../topics/dataset.md)
- [Foundry Dataset transaction/view 证据链](../raw/39-foundry-dataset-transaction-view-evidence.md)
- [Pipeline 目标 Dataset Schema 与主键确定机制调研](../raw/57-pipeline-target-dataset-schema-primary-key.md)
- [治理、血缘、审计与元数据契约](../raw/42-governance-lineage-audit-contracts.md)
- [Palantir Dataset 权限体系与 Marking 机制沉淀](dataset-permission-marking-architecture-summary.md)
- [Palantir Data Quality 模块调研综合报告](palantir-data-quality-module-research.md)
- [Palantir Pipeline 技术实现深度分析](palantir-pipeline-deep-dive.md)
