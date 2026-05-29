# 增量计算、调度与 Dataset Transaction

**调研日期：** 2026-05-29
**关联 Issue：** #11
**资料范围：** `docs/raw/22-pro-code-source-map.md` 中 #11 指向的 S05、S13；既有 `docs/raw/06-incremental-pipeline.md`、`docs/raw/15-job-execution-guarantee.md`；Palantir 官方公开文档。

---

## 背景

Issue #11 关注 Foundry 中三件互相耦合的事：增量 transform 如何确定读写范围，schedule 如何触发和选择 Dataset graph 上的构建范围，以及 Dataset Transaction 如何支撑版本、回滚、retention 和重算边界。【事实】

`docs/raw/22-pro-code-source-map.md` 将本议题对应到 Palantir 官方 S05 `Python incremental transforms` 和 S13 `Scheduling Overview`，并指出增量语义依赖 Dataset 变化历史与 transform read/write mode，而调度心智更接近 Dataset graph，而非传统任务 DAG。【事实】

既有 `docs/raw/06-incremental-pipeline.md` 已整理出 `@incremental`、Transaction History、`semantic_version`、`require_incremental`、`snapshot_inputs`、fallback 等机制；`docs/raw/15-job-execution-guarantee.md` 已整理出 APPEND/UPDATE/SNAPSHOT、事务隔离、失败不污染输出、Build History 和调度重试等保障模型。【事实】

---

## 可信度规则

- 【事实】：来自本次服务器侧检索/抓取的 Palantir 官方文档，或来自用户指定的本地既有资料且与官方资料一致。
- 【推断】：官方文档没有直接给出完整架构图，但由多个官方事实可以稳定推导出的模型。
- 【猜测】：官方公开资料未覆盖，只能作为产品实现假设或自建平台设计启发，必须进入证据缺口或风险项。

---

## 核心结论

1. Foundry Dataset Transaction 是增量计算和调度判断的共同底座：事务是 Dataset 内容的一次原子变化，事务状态可为 open、committed、aborted，committed 后写入文件进入最新 Dataset view，aborted 后写入文件被忽略。【事实】

2. Dataset transaction 类型至少包括 `SNAPSHOT`、`APPEND`、`UPDATE`、`DELETE`；其中 `APPEND` 是 incremental pipelines 的基础，`UPDATE` 会破坏 append-only 要求并迫使下游回落到 `SNAPSHOT` batch processing，`DELETE` 主要服务 retention 工作流。【事实】

3. Incremental transform 的核心不是简单的装饰器，而是“输入 read mode + 输出 write mode + Dataset transaction history + 上次成功构建位点 + fallback 规则”的组合语义。【推断】

4. Incremental input read mode 包括 `added`、`previous`、`current`：增量运行时 `added` 读取上次运行后追加的新数据，`previous` 读取上次运行看到的完整输入，`current` 读取本次完整输入；非增量运行时 `added` 与 `current` 都视为完整输入，`previous` 为空。【事实】

5. Incremental output 的写入模式包括 `modify` 和 `replace`：增量运行默认 `modify`，非增量运行默认 `replace`；这让同一段 transform 逻辑在增量和全量 fallback 下尽量保持可运行。【事实】

6. 官方要求一个 transform 能增量运行，当且仅当所有 incremental inputs 只追加了文件；若文件删除只来自 retention 且 `allow_retention=True`，可以例外；snapshot inputs 不参与该检查。【事实】

7. 官方文档明确说 incremental transform 会加载输入 Dataset 从上一个 `SNAPSHOT` transaction 之后的历史事务来构建输入 view；如果逐渐变慢，建议对 incremental input dataset 运行 `SNAPSHOT` build。【事实】

8. `snapshot_inputs` 适合维表、配置表、参考表：它们在每次运行时按完整快照读取，不作为增量输入参与 append-only 检查。【事实】

9. Scheduling 的触发条件可按时间、数据更新、逻辑更新，或这些条件组合；构建范围可选择单个 Dataset、单个 Dataset 及依赖、某 Dataset 的所有下游、两个 Dataset 之间的连接路径，或组合配置。【事实】

10. Foundry schedule 的 build type 明确体现 Dataset graph build 语义：single build 只构建目标 Dataset；full build 包含目标及上游；connecting build 构建输入 Dataset 与目标 Dataset 之间的可达路径。【事实】

11. Schedule 内容不是一次性静态任务列表：官方说明为适应 pipeline 动态变化，每次 schedule 触发时都会重新评估要包含的 Dataset 集合；build scope 只定义边界。【事实】

12. Dataset Transaction 推断模型可以理解为“Git for data”：每次 committed transaction 改变某个 branch 上的 Dataset view；Dataset view 从最近的 `SNAPSHOT` 开始，依次应用 APPEND、UPDATE、DELETE 得到当前文件集合。【事实】

13. 自建平台若要复制 Foundry 体验，不能只实现 cron + Spark job；需要先实现 Dataset 版本图、事务提交协议、增量位点、Dataset graph traversal、staleness 判断、fallback 与 retention 协同。【推断】

---

## 增量语义模型

### 1. 运行模式

`@incremental` 只是让 transform 具备增量能力，不保证每次实际都增量运行；官方文档将“使用 incremental decorator”和“本次 build 是否实际以增量模式运行”区分开来。【事实】

第一次构建、semantic version 提升、输入不满足 append-only、或平台选择 fallback 时，transform 会以非增量方式运行；此时输入默认读完整数据，输出默认替换结果。【推断】

`require_incremental=True` 可用于阻止自动 fallback，但既有资料显示首次构建是例外；该行为来自 `docs/raw/06-incremental-pipeline.md`，本次未在抓取页逐行复核到完整参数段落。【推断】

### 2. 输入 read mode

| read mode | 增量运行行为 | 非增量运行行为 | 适用场景 |
|---|---|---|---|
| `added` | 读取上次 transform 运行后追加的新数据 | 读取完整 Dataset，因为所有行都被视为未见过 | append-only 过滤、轻加工、仅由新增输入决定新增输出的逻辑【事实】 |
| `previous` | 读取上次运行时看到的完整输入 | 空 DataFrame | 需要比较上次输入与当前输入的逻辑【事实】 |
| `current` | 读取本次完整输入 | 读取本次完整输入，通常等价于 `added` | 需要完整上下文的 join、去重、聚合或审计逻辑【事实】 |

默认 input read mode 是 `added`。【事实】

`snapshot_inputs` 中的输入每次都读取完整快照；它适合小型参考表，避免参考表更新破坏主事实表的增量处理。【事实】

### 3. 输出 read/write mode

Incremental output 的写模式有 `modify` 与 `replace`；`modify` 表示用本次 build 写出的数据修改已有输出，典型效果是追加到既有输出，`replace` 表示用本次 build 的结果完全替换输出。【事实】

增量运行默认 output write mode 为 `modify`，非增量运行默认 output write mode 为 `replace`。【事实】

output 也可以用 `added`、`previous`、`current` 读取；官方提示多数情况下应读取 `previous`，尤其是在需要基于旧输出合并新结果时。【事实】

复杂逻辑如 join、aggregation、distinct 通常不能只依赖 `transform_df()`/`transform_pandas()` 的默认模式，官方建议使用 `incremental()` 与 `transform()`，从而显式设置 read/write mode。【事实】

### 4. APPEND/UPDATE/SNAPSHOT/DELETE 与增量

`SNAPSHOT` 用一组全新文件替换 Dataset 当前 view，是 batch pipelines 的基础。【事实】

`APPEND` 只向当前 view 增加新文件，不能修改已有文件；若 APPEND 事务覆盖既有文件，提交会失败；APPEND 是 incremental pipelines 的基础。【事实】

`UPDATE` 可以增加新文件，也可以覆盖已有文件；官方明确说 UPDATE 会破坏 incremental pipelines 的 append-only requirement，下游必须 fallback 到 SNAPSHOT batch processing。【事实】

`DELETE` 从 Dataset view 中移除文件引用，但不等于从底层文件系统删除文件；实践上主要用于 retention workflow。【事实】

官方 incremental usage 页又补充：如果文件删除来自 retention 且 transform 配置 `allow_retention=True`，仍可能满足增量条件。【事实】

### 5. Snapshot 与 retention 的作用

Dataset view 的计算从最近的 `SNAPSHOT` transaction 开始，因此 SNAPSHOT 不只是“全量写入”，也是重置后续 view 计算起点的边界。【事实】

增量 transform 会加载从上一个 SNAPSHOT 之后的历史事务来构建输入 view；事务积累太多会让增量任务逐渐变慢，官方建议对 incremental input dataset 执行 SNAPSHOT build 来压缩历史视图计算成本。【事实】

Retention policy 通过 DELETE transaction 移除当前 view 中的文件引用，并用于减少存储成本或满足治理要求；公开文档显示查看 retention policy 仍处于 Beta，可能并非所有 enrollment 可用。【事实】

---

## 调度触发模型

### 1. 触发条件

Schedule 的基本目标是让 pipeline 对终端用户保持最新，触发条件可配置为：某些时间点、数据已更新、逻辑已更新，或这些条件的组合。【事实】

Trigger reference 将 event trigger 分为 New logic、Data updated、Job succeeded、Schedule ran successfully；其中 Data updated 指 Dataset 有 transaction committed，New logic 指计算 Dataset 的逻辑更新。【事实】

Time trigger 使用 cron expression 与时区，在指定墙钟时间满足；夏令时或时间调整会影响触发，时间前跳可能跳过触发点，时间后退可能触发两次。【事实】

Event trigger 在事件发生后保持 satisfied，直到整个 compound trigger 满足并运行 schedule。【事实】

Compound trigger 支持 AND/OR 任意嵌套；`AND(time, event)` 表示在时间点到来且事件此前发生过时触发，`OR(time, event)` 表示任一条件满足即触发。【事实】

### 2. 常见触发组合

按固定时间构建适合日报、小时报、稳定批处理窗口等场景；可配合 full build 包含上游依赖。【推断】

按 Dataset update 构建适合上游不定时到数、希望下游尽快响应的场景；event trigger 需要选择 graph 上要监听的 Dataset。【事实】

“固定时间且上游已更新”适合控制业务时点，例如每天 9 点只在上游曾更新时构建；官方提醒该配置不限制上游更新时间窗口，若上游每天 9:10 更新，下游 9:00 构建会持续使用约 23 小时 50 分钟前的数据。【事实】

逻辑更新触发适合 transform 代码或 job spec 变化后自动重建相关 Dataset；公开资料没有说明其与代码分支、PR 合并、semantic version 的完整耦合细节。【推断】

### 3. Build 范围和 Dataset graph 语义

Schedule 可构建单个 Dataset、单个 Dataset 及其全部依赖、依赖某 Dataset 的全部下游、两个 Dataset 之间的连接路径，或组合配置。【事实】

Create schedule 页将 build type 细化为 single build、full build 和 connecting build：single build 只构建 target datasets；full build 构建 target 及其上游，排除显式 excluded datasets；connecting build 构建 input datasets 与 target datasets 之间的路径。【事实】

Connecting build 依赖同一 branch 上存在 job spec path；如果中间路径跨 branch 断开，目标 Dataset 可能不会被纳入 scheduled build。【事实】

每次 schedule 触发时都会重新评估 Dataset 集合，说明 Foundry 保留的是 graph 选择规则和边界，而不是固定 job ID 列表。【事实】

Build scope 可按 Projects 或 user account 限定；Project scoping 更适合权限稳定、生产化 pipeline，user scoping 在用户失活或失权时可能导致 schedule build 无法启动。【事实】

### 4. Incremental transaction limits 与反复触发

官方支持为 incremental input 配置 transaction limit，限制单个 job 读取的未处理事务数量；当只处理了一部分事务后，输出 Dataset 可能在成功 build 后仍落后于最新上游数据。【事实】

Create schedule 的 advanced settings 提供 “Re-trigger upon successful build”：在目标资源使用 incremental transaction limits 或 media set batch limits 且未开启 Force build 时，schedule 可在成功后反复触发，直到输入处理完且目标不再 stale。【事实】

Spark details 的 Snapshot/Incremental tab 可查看每个 incremental job 的 transaction ranges，包括 current view range、processed batch range、previous end transaction、last read transaction。【事实】

---

## Dataset Transaction 推断模型

### 1. 基本对象

Dataset transaction 是一次原子数据变更，类似 Git commit；Dataset branch 上的 transaction history 决定该 branch 在某时刻的 Dataset view。【事实】

事务生命周期可抽象为：OPEN 写文件，COMMITTED 后文件进入最新 view，ABORTED 后写入文件被忽略。【事实】

Dataset view 是某个 branch 在某个时间点的有效文件集合：从最近 SNAPSHOT 或最早事务开始，按顺序应用 APPEND、UPDATE、DELETE，得到最终文件集合。【事实】

### 2. 增量位点

官方 transaction limits 页暴露了 `Previous end transaction` 和 `Last read transaction` 等 job 观测字段，说明平台至少在 job 元数据中记录上次输入 view 末端与上次实际处理到的事务位置。【事实】

增量 transform 的消费位点可推断为“按 transform output/job history 维度维护的每个输入 Dataset 的已处理 transaction range”，而不是用户显式管理的 consumer group offset。【推断】

公开资料未发现类似 Iceberg `startSnapshotId/endSnapshotId` 或 Paimon consumer-id 的用户可控开放位点 API；因此外部系统复用 Foundry 增量位点的能力暂不可证。【推断】

### 3. 事务一致性与失败边界

既有 `docs/raw/15-job-execution-guarantee.md` 归纳：Build 开始时锁定输入 Dataset 版本，失败时输出保持上次成功 transaction，不暴露中间态；这些结论与 Dataset transaction 原子提交模型一致。【推断】

官方 datasets 页明确 aborted transaction 的写入文件会被忽略，因此失败或主动 abort 不应污染 Dataset view。【事实】

“同一 build 内多个输出 Dataset 是否具备跨 Dataset 原子提交”未在公开资料中找到直接证据；谨慎起见，应只认为单 Dataset transaction 原子性有公开依据。【推断】

---

## 失败/降级/重算边界

1. 输入 Dataset 出现覆盖/删除既有文件的变化时，增量 transform 不能安全只读新增数据；UPDATE 会破坏 append-only requirement，下游必须回落 SNAPSHOT batch processing。【事实】

2. 如果删除来自 retention 且 transform 显式允许 retention，则官方 summary 表示仍可满足增量条件；这意味着 retention 需要进入增量正确性模型，而不是被视为普通删除。【事实】

3. 首次构建没有 previous view 或 previous output，可推断必须按全量语义运行；此点由既有文档和 incremental read mode 的非增量行为共同支撑。【推断】

4. `semantic_version` 提升会导致后续 build 以 SNAPSHOT 方式重新处理输入；transaction limits 页也以 semantic version changed 作为 output snapshotted、输入从 start transaction 重新处理的例子。【事实】

5. 开启 `v2_semantics` 是使用 transaction limits 的前提之一；官方说明在已有 incremental transform 上启用 `v2_semantics` 会导致下一次 build 运行为 SNAPSHOT，且只发生一次。【事实】

6. 如果使用 transaction limit，单次成功 build 可能只处理部分未处理事务，Dataset 仍然 stale；需要 schedule re-trigger 或多次运行追平。【事实】

7. Force build 会忽略 staleness 信息并构建所有 Dataset；官方称几乎不需要，典型例外是 Data Connection sync 等外部来源，因为 Foundry 不知道外部数据是否更新。【事实】

8. Schedule job retry 是同一个 scheduled build 的一部分；Create schedule 页允许自定义失败 job 的 attempts，但并非所有 failure 都可 retry，且重试数受管理员上限约束。【事实】

---

## 对自建平台建议

1. 先建 Dataset Transaction 层，再谈增量调度：至少需要 transaction type、transaction state、branch/view 计算、文件集合变更、commit/abort 原子性、retention 删除语义。【推断】

2. 增量 API 应显式区分 input read mode：`added`、`previous`、`current` 三种模式可以覆盖多数增量 transform；默认 `added` 能降低简单 append-only 逻辑门槛。【推断】

3. 输出应同时支持 append/modify 与 replace，并让平台根据“本次是否实际增量运行”设置默认写模式；否则 fallback 到全量时容易把增量追加逻辑写错。【推断】

4. 调度系统不要只保存 job 列表，应保存 Dataset graph selection rule：target、upstream/downstream/connecting、excluded datasets、branch、scope、权限主体，并在每次触发时重新解析。【推断】

5. Staleness 应基于 Dataset transaction 与 transform logic version 共同判断：数据更新、逻辑更新都可能让 Dataset 过期。【推断】

6. 对大流量增量链路，应提供 transaction batch limit 与自动 re-trigger，避免单次 job 被历史 backlog 打爆，同时让 schedule 能追平 backlog。【推断】

7. Retention 不能只做物理清理；必须在 transaction/view 层表达删除，并提供 `allow_retention` 类似开关，否则会误判增量正确性。【推断】

8. 运维界面应直接展示本次 job 的 current view range、processed batch range、previous end transaction、last read transaction；这是排查“为什么没追平/为什么 fallback”的关键证据。【推断】

9. 自建平台如果用 Iceberg/Paimon，可把 Dataset transaction 映射到 table snapshot/changelog，但要明确 Foundry 公开语义更偏文件级 transaction view，不等价于行级 CDC。【推断】

---

## 证据缺口

1. 官方公开资料没有完整说明 Dataset Transaction 的内部隔离级别，例如同一个 build 写多个输出 Dataset 时是否跨 Dataset 原子提交。【推断】

2. 官方公开资料没有发现用户可直接操作的增量 consumer offset API；“位点完全由平台内部管理”仍是基于缺失证据的推断。【推断】

3. `require_incremental`、`strict_append`、`allow_retention` 的所有参数组合和异常行为，需要继续查官方 API reference 或真实 Foundry 环境验证。【推断】

4. Scheduling 的 New logic trigger 与 Code Repository commit、job spec、semantic version、branch merge 的精确关系，本次只验证到“logic updated”事件类型，未验证具体实现边界。【推断】

5. Schedule 的 staleness 判定算法未公开：已知 Force build 可忽略 staleness，re-trigger 可追平 stale target，但何时标记 stale、如何跨 branch 传播仍需实测。【推断】

6. Dataset retention policy 的查看能力标注 Beta，且可能需要联系 Palantir Support；不同 enrollment 可用性存在风险。【事实】

7. 已有 `docs/raw/06-incremental-pipeline.md` 中“批式增量 at-least-once 不保证 exactly-once”等一致性表述，本次未找到官方页逐字支撑，需要后续单独验证。【推断】

---

## 参考来源

### 官方 Palantir 文档

- Palantir Foundry - Python incremental transforms overview: https://www.palantir.com/docs/foundry/transforms-python/incremental-overview
- Palantir Foundry - Python incremental transforms usage guide: https://www.palantir.com/docs/foundry/transforms-python/incremental-usage
- Palantir Foundry - Limit batch size of incremental inputs: https://www.palantir.com/docs/foundry/transforms-python-spark/incremental-transaction-limits
- Palantir Foundry - Core concepts: Datasets: https://www.palantir.com/docs/foundry/data-integration/datasets
- Palantir Foundry - Scheduling overview: https://www.palantir.com/docs/foundry/building-pipelines/scheduling-overview
- Palantir Foundry - Create a schedule: https://www.palantir.com/docs/foundry/building-pipelines/create-schedule
- Palantir Foundry - Common scheduling configurations: https://www.palantir.com/docs/foundry/building-pipelines/common-schedules
- Palantir Foundry - Trigger types reference: https://www.palantir.com/docs/foundry/building-pipelines/triggers-reference
- Palantir Foundry - Scheduling best practices: https://www.palantir.com/docs/foundry/building-pipelines/scheduling-best-practices
- Palantir Foundry - Iceberg tables transactions: https://www.palantir.com/docs/foundry/iceberg/transactions

### 本地既有资料

- `docs/raw/22-pro-code-source-map.md`
- `docs/raw/06-incremental-pipeline.md`
- `docs/raw/15-job-execution-guarantee.md`
