# Foundry Dataset transaction/view 证据链

关联 Issue：#29
日期：2026-05-30

## 总结与洞察

1. 【事实】Palantir Foundry Dataset 的官方一阶模型是“backing filesystem 上的一组文件 + Dataset 元数据”，并内建 permission、schema、version control、branch、transaction 和随时间更新能力；它不是以传统 `table + dt` 分区作为默认主坐标。
2. 【事实】Dataset 的可读状态是 `dataset + branch + transaction/view` 解析出来的文件集合：branch 指向最新 transaction，dataset view 由最近 `SNAPSHOT` 起依次应用 `APPEND`、`UPDATE`、`DELETE` 得到。
3. 【事实】Schema 绑定在 dataset view 上；官方 API 也用 `branchName`、`endTransactionRid`、`versionId` 定位 schema，说明“结构版本”跟随 view，而不是只跟随静态表定义。
4. 【推断】Foundry 增量计算的主坐标是 input transaction range、append-only 约束、output write mode、JobSpec 逻辑版本和 staleness；传统 `dt` 只能作为业务日期字段、Ontology 属性或布局列补充建模。
5. 【建议】Hive-style partitioning 应定位为查询裁剪/文件布局优化。若业务仍需要按账期、T+1、补数、SLA 验收组织生产，应额外维护 `business_date/data_interval -> transaction/view` 的 manifest，而不是把 `dt` 误当 Foundry Dataset 的默认底座。

## 1. 论证目标

本文件目标是为 Issue #29 建立证据链：Foundry Dataset 的基础坐标不是传统离线数仓的：

```text
table + dt
```

而是：

```text
dataset + branch + transaction/view
```

`dt` 在传统数仓里经常同时承担业务日期、物理分区、调度实例、补数边界、SLA 验收和生命周期管理。Foundry 没有把这些职责默认压进一个 `dt` 分区列，而是拆成 Dataset transaction/view、build/staleness、schema、branch、lineage、layout optimization 和业务字段/manifest。

## 2. Dataset 是文件集合 wrapper，而不是默认分区表

【事实】Palantir 官方定义 Dataset 是数据进入 Foundry 后到映射进 Ontology 前的核心表示。Dataset 本质上是 backing filesystem 上一组文件的 wrapper，并提供权限管理、schema 管理、版本控制和随时间更新能力。

【事实】Dataset 可表示结构化、半结构化和非结构化数据。结构化 Dataset 通常由 Parquet 等开源格式文件和 schema 元数据组成；非结构化 Dataset 可以是图片、视频、PDF 等文件，不一定有 schema。

【事实】Dataset 文件并不“存储在 Foundry 自身”这一抽象里；Foundry 维护逻辑路径到 backing filesystem 物理路径的映射。Backing filesystem 可基于 Hadoop FileSystem，更常见是 S3 等云对象存储。

【推断】这意味着 Dataset 的底座是“文件集合 + 元数据 + 版本系统”。传统表的 `dt=yyyy-mm-dd` 目录可以出现在文件布局中，但不是 Foundry Dataset 的默认身份坐标。

## 3. Transaction 生命周期与四种类型

【事实】Dataset 通过 transaction 更新。Transaction 生命周期包括：

| 状态 | 含义 |
|---|---|
| `OPEN` | transaction 已开始，可在 backing filesystem 中打开并写入文件 |
| `COMMITTED` | transaction 已提交，写入文件进入最新 dataset view |
| `ABORTED` | transaction 已中止，写入文件被忽略 |

官方将 Dataset transaction 类比为 Git commit：它是对 Dataset 内容的一次原子变化。

Transaction 类型包括四类：

| 类型 | 官方语义 | 对主坐标的含义 |
|---|---|---|
| `SNAPSHOT` | 用一组新文件完全替换当前 view | 新 view 边界；batch pipeline 基础 |
| `APPEND` | 向当前 view 添加新文件，不能修改当前 view 已有文件 | incremental pipeline 基础 |
| `UPDATE` | 添加新文件，也可以覆盖既有文件 | 破坏 append-only，下游不能继续普通增量 |
| `DELETE` | 从当前 view 移除文件引用，但不直接删除 backing filesystem 底层文件 | 常用于 retention / 数据治理 |

【事实】官方示例说明：若一个 branch 上依次有 `SNAPSHOT(A,B)`、`APPEND(C)`、`UPDATE(A -> A')`、`DELETE(B)`，当前 view 包含 `A'` 和 `C`；如果再提交 `SNAPSHOT(D)`，当前 view 变成只包含 `D`，此前 transaction 组成旧 view。

【推断】这直接证明 Foundry 的“版本边界”不是日期分区，而是 transaction history 中的 view 边界。

## 4. Branch 与 Dataset View 语义

【事实】Dataset branch 是指向最新 transaction 的指针；Dataset、branch、transaction 分别类似 Git repository、branch、commit。某 branch 提交新 transaction 不会改变其他 branch 的 transactions 和 views。

【事实】Dataset branch 支持从父 branch 或指定 transaction 创建；branch 指针随后可独立移动。官方同时说明 Dataset branch 不支持像 Git 那样 merge 数据内容。

【事实】Dataset view 是“某个 branch 在某个时间点的有效文件内容”。计算规则是：从该时间点之前最近的 `SNAPSHOT` transaction 开始，如果没有 snapshot 则从最早 transaction 开始；随后依次应用 `APPEND`、`UPDATE`、`DELETE` 得到文件集合。

【事实】Build system 把逻辑分支和 Dataset branch 绑定起来：build 在用户指定 branch 上运行，jobs 只修改该 branch 上的 datasets；输入优先按 build branch 解析，不存在时走 fallback branch。

【事实】Data Lineage 是 branch-aware。选择 Global Branch 后，Dataset 节点会显示 branch-specific data、build status、staleness；官方还明确所有 Global Branch 都有对应 Dataset Branch，但不是每个 Dataset Branch 都绑定 Global Branch。

【推断】血缘最小可解释单元应写成：

```text
dataset + branch + transaction/view + producer run
```

而不是仅写成：

```text
table + partition
```

## 5. Schema 绑定在 Dataset View 上

【事实】官方 Dataset 文档明确：schema 是 dataset view 上的元数据，定义 view 中的文件如何被解释，包括解析方式、列名、字段类型等。因为 schema 存在于 dataset view 上，所以 schema 可以随时间变化。

【事实】官方 API `Get Dataset Schema` 进一步印证这个坐标：请求参数包括 `branchName`、`endTransactionRid`、`versionId`；返回体包含 `branchName`、`endTransactionRid` 和 schema `versionId`。

【事实】官方也提示：schema 不保证底层文件实际符合该 schema；例如给 CSV 文件套 Parquet schema 会导致读取时报错。

【推断】Schema 不是一个静态“表定义”覆盖所有历史数据。更准确的模型是：

```text
schema = schema(dataset, branch, endTransactionRid, versionId)
```

这与传统“表名 + 分区字段”的心智不同。

## 6. 增量 Transform、Transaction Range 与 Append-only 约束

【事实】官方 Incremental pipelines 文档说明，开发增量 pipeline 需要理解 Dataset 如何通过 transactions 随时间变化；虽然增量 pipeline 通常处理以 `APPEND` transaction 到达的变化数据，但逻辑也要能应对输入偶尔被 recompute 并产生 `SNAPSHOT`。

【事实】Python incremental transforms 的默认 input read mode 是 `added`，增量运行时读取上次运行后新增的数据；`previous` 读取上次运行看到的完整输入；`current` 读取本次完整输入。增量运行默认 output write mode 是 `modify`，非增量运行默认是 `replace`。

【事实】官方增量要求可以概括为：非 snapshot incremental inputs 必须只追加文件；如果出现修改既有文件的 `UPDATE` 或非 retention 删除，则不能安全按普通增量处理。

【事实】`APPEND` transaction 自身也有强约束：不能修改当前 view 中已有文件；如果打开 `APPEND` transaction 后覆盖已有文件，commit 会失败。

【事实】Transaction limit 文档把增量读取直接表达为 transaction ranges：Spark details 中可看到 current view range、processed batch range、previous end transaction、last read transaction。开启 transaction limit 后，一次 job 可能只处理未处理 transactions 的一段，成功后 output 仍可能 stale，需要后续 re-trigger 追平。

【事实】Transaction limit 对输入有明确限制：输入必须是 transactional dataset；当前 view 中只能有 `APPEND` transactions，起始 transaction 可以是 `SNAPSHOT`；如果当前 view 中有 `DELETE` 或 `UPDATE`，job 会以 `Build2:InvalidTransactionTypeForBatchInputResolution` 失败。

【事实】Build staleness 也围绕版本坐标。官方 Builds 文档说明：如果 build resolution 判断 input datasets 和 JobSpec 逻辑自上次构建后没有变化，output dataset 被认为 fresh，后续 build 不会重算；force build 可绕过 staleness 强制重算。

【推断】因此 Foundry 增量不是“扫描 `dt = 今天` 分区”，而是：

```text
input dataset branch/view
+ unprocessed transaction range
+ append-only validation
+ transform read/write modes
+ output transaction
+ staleness decision
```

## 7. Hive-style Partitioning 是布局优化，不是业务主坐标

【事实】Palantir 官方 Hive-style partitioning 文档定义它是“优化 Dataset 数据布局的方法”，用于显著提升按特定列过滤的查询性能。

【事实】其机制是：Spark transform 写 output Dataset 时，按指定 partition columns 的取值组合写出独立文件；在文件路径中包含 partition column values；并在 transaction metadata 中记录 Dataset 按这些 columns partitioned。Spark、Polars 等 reader 可利用 metadata 和路径缩小读取文件范围。

【事实】官方同时警告：Hive-style partitioning 不适合高基数字段，因为每个 partition value combination 至少写一个文件，过多文件会拖慢写入和后续读取。

【推断】这说明 partition columns 是物理布局和读取裁剪机制。它们可以选择 `record_date`、`department` 等列，但这不改变 Dataset 的版本身份仍由 branch/transaction/view 决定。

【建议】对按日期过滤的大表，可以把 `business_date` 或 `record_date` 作为 Hive-style partition column；但不要让它同时承担 build 版本、补数、审计和血缘坐标。账期语义应通过 manifest 或元数据显式关联到 transaction/view。

## 8. 与传统 `table + dt` 模型的差异

传统离线数仓中，`dt` 往往是复合制度，不只是字段：

| 职责 | 传统 `dt` 常见作用 | Foundry-like 承接机制 |
|---|---|---|
| 物理裁剪 | `table/dt=2026-05-29/` | Hive-style partitioning / projection / file metadata |
| 业务日期 | 数据所属业务日 | schema 字段、Ontology property、manifest |
| 调度实例 | T+1、小时实例、补数实例 | schedule run / build run / trigger metadata |
| 版本边界 | overwrite partition | transaction/view |
| 增量边界 | 新分区、变更分区、watermark | unprocessed transaction range |
| 幂等重跑 | `insert overwrite partition(dt=...)` | new transaction + active/superseded version mapping |
| SLA 验收 | partition ready | quality status + ready manifest |
| 血缘审计 | task instance -> table partition | producer run -> input/output transaction/view/range |

【推断】Foundry 的核心变化不是“没有分区”，而是把传统 `dt` 的复合职责拆开。版本证据链由 transaction/view 负责；业务日期解释由字段、Ontology 或 manifest 负责；物理裁剪由 partition/projection/file layout 负责。

## 9. 本仓库已有结论衔接点

- `docs/synthesis/palantir-dataset-no-dt-partition-impact.md` 已形成关键判断：Foundry Dataset 不是没有分区，而是基础语义不是 `dt`，主坐标是 `Dataset + branch + transaction/view`；`dt` 应退回业务契约或布局优化角色。
- `docs/raw/27-incremental-scheduling-transaction.md` 已覆盖增量、调度和 Dataset transaction 的关系：`APPEND` 是增量基础，`UPDATE` 破坏 append-only，transaction limits 会导致成功 build 后仍 stale，staleness/force build 决定是否重算。
- `docs/raw/29-lineage-branch-version-pipeline-sync.md` 已把血缘最小单元总结为 `Dataset branch + transaction/view + producer`，并区分数据版本、schema version 和逻辑版本。
- `docs/synthesis/dataworks-vs-palantir-integration.md` 已区分传统 Run Identity 与 Foundry Data Version Identity：业务周期对齐和 freshness/staleness 是两套机制，不能互相替代。

本文件可作为上述结论的“官方证据链补强版”：用 Palantir Dataset、Branching、Schema API、Incremental Transform、Build staleness 和 Hive partitioning 文档证明主坐标迁移。

## 10. 可直接引用的结论

【事实】Foundry Dataset 的官方模型是 backing filesystem 上的文件集合 wrapper，并通过 transaction、branch、view、schema 管理数据版本和结构解释。

【事实】Transaction 是 Dataset 内容的原子变化，生命周期为 `OPEN`、`COMMITTED`、`ABORTED`，类型为 `SNAPSHOT`、`APPEND`、`UPDATE`、`DELETE`。

【事实】Dataset view 是某 branch 在某时间点的有效文件集合，由最近 `SNAPSHOT` 和后续 transaction 序列计算得到；branch 是指向最新 transaction 的指针。

【事实】Schema 是 dataset view 上的元数据；官方 schema API 使用 `branchName`、`endTransactionRid`、`versionId` 定位 schema。

【事实】Incremental transforms 读取的是 input transaction range；只有 append-only 输入能稳定增量，`UPDATE`/非 retention `DELETE` 会破坏增量约束或导致失败/fallback；staleness 判断基于输入 Dataset 与 JobSpec 逻辑是否变化。

【建议】因此，Foundry Dataset 的主坐标应表述为：

```text
dataset + branch + transaction/view
```

而不是：

```text
table + dt
```

迁移或自建时应采用双坐标：`transaction/view` 管版本证据链，`business_date/data_interval/manifest` 管业务生产解释；Hive-style partitioning 只作为查询布局优化使用。

## 参考资料 URL

- Palantir Foundry Datasets: https://www.palantir.com/docs/foundry/data-integration/datasets
- Palantir Foundry Branching: https://www.palantir.com/docs/foundry/data-integration/branching
- Palantir Global Branching Overview: https://www.palantir.com/docs/foundry/global-branching/overview
- Palantir Data Lineage - Branching data lineage: https://www.palantir.com/docs/foundry/data-lineage/branching-data-lineage/
- Palantir API - Get Dataset Schema: https://www.palantir.com/docs/foundry/api/v2/datasets-v2-resources/datasets/get-dataset-schema
- Palantir API - Get Transaction: https://www.palantir.com/docs/foundry/api/datasets-v2-resources/transactions/get-transaction
- Palantir API - Commit Transaction: https://www.palantir.com/docs/foundry/api/datasets-v2-resources/transactions/commit-transaction
- Palantir API - Abort Transaction: https://www.palantir.com/docs/foundry/api/datasets-v2-resources/transactions/abort-transaction
- Palantir Builds core concepts: https://www.palantir.com/docs/foundry/data-integration/builds
- Palantir Incremental pipelines overview: https://www.palantir.com/docs/foundry/building-pipelines/incremental-overview
- Palantir Python incremental transforms usage: https://www.palantir.com/docs/foundry/transforms-python/incremental-usage
- Palantir Incremental transaction limits: https://www.palantir.com/docs/foundry/transforms-python-spark/incremental-transaction-limits
- Palantir File-based syncs: https://www.palantir.com/docs/foundry/data-connection/file-based-syncs
- Palantir Hive-style partitioning: https://www.palantir.com/docs/foundry/optimizing-pipelines/hive-style-partitioning/
- Palantir Data Lineage - Build datasets: https://www.palantir.com/docs/foundry/data-lineage/build-datasets/
- Palantir Scheduling troubleshooting: https://www.palantir.com/docs/foundry/building-pipelines/schedule-troubleshooting/
