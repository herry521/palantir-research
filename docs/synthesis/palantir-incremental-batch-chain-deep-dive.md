# Palantir 增量批链路能力与实现深度调研

**日期：** 2026-06-15  
**类型：** 综合调研报告  
**事实依据优先级：** Palantir 官方公开文档 > 仓库既有 raw/synthesis 证据层 > 本文推断  
**关联 Issue：** #11

---

## 摘要与洞察

1. 【事实】Palantir Foundry 的增量批链路底座不是行级 CDC，而是 `Dataset transaction + transform build history + schedule/staleness` 的组合；其中 `APPEND` transaction 是端到端增量的基础，`UPDATE` 会破坏 append-only 要求并迫使下游回落到 `SNAPSHOT` 批处理。[S1][S2]
2. 【事实】增量 job 真正处理的不是输入 dataset 的完整 view，而是“自上次处理后尚未消费的 transaction range”；默认输入读模式是 `added`，默认输出写模式是 `modify`，这决定了增量链路的核心语义是“处理新增、修改输出”。[S3][S4]
3. 【事实】Foundry 把“增量失败时如何退回全量”设计成内建主路径，而不是异常路径：首次构建、`semantic_version` 变化、输入被整体重写、输入存在非 retention 删除或覆盖修改时，都会转成 `SNAPSHOT` 语义运行。[S3][S5]
4. 【事实+推断】开发者能控制的关键旋钮主要是 `require_incremental`、`semantic_version`、`snapshot_inputs`、`allow_retention`、`strict_append`、`v2_semantics` 和 `transaction_limit`；它们分别对应“是否允许 fallback”“何时逻辑失效”“哪些输入不参与增量判定”“是否容忍 retention 删除”“输出是否强制 APPEND”“是否启用新语义”和“单次追平上限”。[S3][S5]
5. 【推断】如果要自研 Foundry 风格增量批链路，不能只实现 Spark + cron；至少要有 transaction/view 层、增量资格判定器、双模式读写语义、staleness-aware 调度，以及 transaction-range 可观测性。

---

## 可信度规则

- 【事实】：能被本次检索到的 Palantir 官方文档直接支持。
- 【推断】：由多个官方事实稳定推导，但官方没有直接把完整结论写出来。
- 【猜测】：官方公开材料未覆盖，只能作为实现假设或验证线索。

---

## 一、增量批链路到底提供了什么能力

| 能力 | 结论 | 可信度 |
| --- | --- | --- |
| 低延迟批更新 | Foundry 通过 incremental transform 避免每次重算完整输出，适合分钟级追新，而不是秒级持续流处理。 | 【事实】 |
| 端到端增量传播 | 只有当上游以 `APPEND` 方式持续引入新文件时，增量链路才能稳定向下游传播。 | 【事实】 |
| 复杂 transform 兼容 | 增量不是只支持 filter/append；复杂 join、aggregation、distinct 也能做，但通常需要改用 `transform()` 显式控制读写模式。 | 【事实】 |
| 小步追平 backlog | `transaction_limit` 允许把一次大 backlog 拆成多次 job 追平。 | 【事实】 |
| 运维可观察 | Spark details 的 Snapshot/Incremental 视图会暴露 current view range、processed batch range、previous end transaction 等 transaction 范围指标。 | 【事实】 |
| 对业务周期建模 | Foundry schedule/stale 语义面向 dataset graph build，不是业务日期实例调度。 | 【事实+推断】 |

【事实】官方把 incremental computation 定义为“利用 transform 的 build history，避免每次都重算整个输出”；同时要求输入和输出不能是同一个 dataset，以避免循环依赖。[S2]

【事实】官方 datasets 文档明确说明：`SNAPSHOT` 是 batch pipeline 的基础，`APPEND` 是 incremental pipeline 的基础，`UPDATE` 会打破 append-only 要求，导致下游必须回落到 `SNAPSHOT` 处理。[S1]

【推断】因此，Foundry 的“增量批链路”本质上不是一个单独模块，而是五个子系统的组合：

1. `Dataset transaction/view`。
2. `Incremental transform runtime`。
3. `Build history / processed range tracking`。
4. `Schedule + stale detection`。
5. `Job-level observability`。

---

## 二、增量批链路的实现主链路

### 1. 上游先把数据变成 transaction history

【事实】Foundry dataset 在底层通过 transaction 演进；transaction 生命周期有 `OPEN`、`COMMITTED`、`ABORTED` 三种关键状态，只有 committed 后写入文件才会进入最新 dataset view，aborted 写入会被忽略。[S1]

【事实】transaction 类型有四种：`SNAPSHOT`、`APPEND`、`UPDATE`、`DELETE`。[S1]

【事实】其中：

- `SNAPSHOT` 会用一组全新文件替换当前 view，是 batch pipeline 的基础。[S1]
- `APPEND` 只增加新文件，不能覆盖旧文件，是 incremental pipeline 的基础。[S1]
- `UPDATE` 既可加新文件，也可覆盖现有文件，会破坏下游增量要求。[S1]
- `DELETE` 从当前 view 中移除文件引用，常见于 retention 场景。[S1]

【推断】所以增量链路的第一性前提不是“下游代码写了 `@incremental`”，而是“上游 transaction 模式长期满足 append-only 数据契约”。

### 2. 调度或人工 build 负责把“有变化”转成一次构建尝试

【事实】Schedules 定义的是“什么时候跑 build”；当 trigger 满足时，schedule 会运行。如果前一次 run 还没结束，新触发会保持触发态，等前一次完成后再运行。[S6]

【事实】在 schedule editor 中，build type 可以是 `Single build`、`Full build (include upstream)` 或 `Connecting build`，并且默认只会真正构建 stale 的 job specs / datasets；如果目标都 up-to-date，schedule run 会被忽略。[S7][S8]

【事实】Data Lineage 可以按 out-of-date/stale 视角看哪些节点需要构建，并直接从 lineage 里发起 build。[S9]

【推断】这意味着 Foundry 的增量链路不是“每次上游一更新，下游 job 必定立即执行”，而是“先由 schedule/build system 判断 graph 上哪些节点 stale，再决定是否创建 job”。

### 3. Incremental runtime 先做资格判定，再决定本次是否真增量

【事实】`@incremental` 装饰器参数包括：

- `require_incremental=False`
- `semantic_version=1`
- `snapshot_inputs=None`
- `allow_retention=False`
- `strict_append=False`
- `v2_semantics=False`[S3]

【事实】`require_incremental=True` 时，如果 transform 不能增量运行会失败；但有两个例外仍允许 snapshot 运行：输出从未 build 过，以及 `semantic_version` 发生变化。[S3]

【事实】`semantic_version` 变化会强制下一次 run 变成非增量；若当前 run 的 semantic version 与前一次不同，本次就按非增量处理。[S3]

【事实】一个 transform 能否增量运行，取决于其 incremental inputs 自上次运行以来是否“只有文件被加入”。官方明确列出不能增量的情况：

- incremental inputs 被整体重写，例如出现 `SNAPSHOT`；
- incremental inputs 通过 `UPDATE` 或 `DELETE` 修改或删除了文件。[S3]

【事实】官方错误文档还说明，job 开始时会校验 unprocessed transaction range 是否“strictly incremental”；若 branch HEAD 与已处理 transaction 范围不再一致，会抛出 `Catalog:TransactionsNotInView` 或相关错误。[S4]

【推断】因此，实现上至少存在一个“增量资格判定器”，它会综合：

1. 上次成功处理到哪里。
2. 当前 branch HEAD 指到哪里。
3. 中间未处理 transaction range 是否仍满足 append-only。
4. 本次是否因为 semantic version 或首次构建而强制 snapshot。

### 4. 真正增量时，输入不是完整 view，而是未处理 transaction range

【事实】官方增量错误文档明确说：当 job 增量运行时，incremental input dataset “only consist of the unprocessed transactions range, not the full dataset view”。[S4]

【事实】官方示例把 transaction history 解释为：如果上次处理到 transaction (3)，现在 HEAD 到了 (5)，那么未处理范围就是 (4) 到 (5)；而完整 dataset view 则是从上一个 `SNAPSHOT` 起一路叠加到当前 HEAD。[S4]

【事实】默认 input read mode 是 `added`；`ctx.is_incremental=True` 时，默认输入读模式为 `added`，默认输出写模式为 `modify`。[S3]

【事实】官方还给出 read/write mode 心智：

- `added`：看新增输入；
- `previous`：看上次见过的输入/输出；
- `current`：看本次完整视图；
- 常见默认组合是输入 `added` + 输出 `modify`。[S3]

【推断】这说明 Foundry 的增量实现不是通过“对完整表做谓词裁剪”来模拟增量，而是通过 transaction-range 解析直接改变 transform 看见的数据窗口。

### 5. 复杂逻辑要显式处理双模式语义

【事实】官方明确要求：被 `incremental()` 包裹的 compute function 必须同时支持 incremental 和 non-incremental 两种运行方式。[S3]

【事实】如果逻辑只是“新增输入决定新增输出”，`transform_df()` / `transform_pandas()` 的默认模式通常就够；但如果 transform 包含 join、aggregation、distinct 等复杂逻辑，需要改用 `transform()` 来显式设置输入 read mode 或输出 write mode。[S3]

【推断】这意味着 Foundry 的增量编程模型不是“平台自动把任意 SQL/PySpark 改写成增量计划”，而是“平台提供 transaction-aware IO 语义，开发者需要把业务逻辑写成可同时接受增量和全量 fallback 的形式”。

### 6. 特殊输入和特殊删除靠显式声明进入正确语义

【事实】`snapshot_inputs` 用来声明某些输入即使被整体重写，也不应破坏 transform 的增量性；官方例子是国家码映射表之类的 reference dataset。snapshot input 会被排除在“输入是否被重写”的检查之外，其 start transaction 允许和其他输入不同。[S3]

【事实】`allow_retention=True` 只对 retention policy 产生的删除生效：如果只有 `added` 变化和 retention 造成的 `removed` 变化，transform 仍可增量运行；其他删除仍会触发 snapshot。[S3]

【推断】这两个参数实质上是在告诉平台：“某些输入变化不需要重放历史结果”，以及“某些删除不是业务语义删除，只是生命周期治理删除”。

### 7. 输出写入不是固定 append，而是依赖本次运行模式

【事实】当 `ctx.is_incremental=True` 时，默认输出写模式是 `modify`；当非增量运行时，默认会替换输出。[S3]

【事实】如果设置 `strict_append=True` 且输入确实是 incremental，底层 Foundry transaction type 会被设为 `APPEND`，覆盖已有文件会报错；若输入并不 incremental，`strict_append` 会按 `SNAPSHOT` 运行，官方建议配合 `require_incremental=True` 保证真正的 APPEND 语义。[S3]

【推断】因此输出层实际上存在“两层语义”：

1. transform 代码层的 `modify` / `replace`。
2. dataset transaction 层的 `APPEND` / `SNAPSHOT`。

Foundry 通过二者配合，把“增量追加”和“全量重算替换”统一在同一个 transform 定义里。

### 8. Backlog 过大时，用 transaction_limit + re-trigger 追平

【事实】官方允许在 incremental input 上配置 `transaction_limit`，限制单个 job 读取的 transaction 数量。[S5]

【事实】开启 transaction limit 后，一次成功 build 之后，输出 dataset 仍可能落后于最新上游，因为该次 build 只处理了部分数据；官方建议配 schedule 的 “Re-trigger schedule upon completion of a successful build” 持续追平，直到 dataset 不再 stale。[S5]

【事实】这个开关不能和 `Force build` 同时启用，因为一个基于 stale 停止，一个无论 stale 与否都强制重建，会形成冲突。[S5]

【推断】这相当于给增量批链路加了一个“批量阀门”：平台承认 backlog 追平本身也是一个调度问题，而不是单个 Spark job 的内部问题。

### 9. 长期性能靠定期 snapshot 重置 transaction/view 成本

【事实】官方说明：增量 transform 为了构建输入 view，需要从上一个 `SNAPSHOT` transaction 之后加载历史 transaction；如果看到 progressive slowness，建议对 incremental input dataset 运行 `SNAPSHOT` build。[S3]

【事实】官方专门有“Maintaining high performance”页面，明确建议定期 snapshot；因为 snapshot 会重处理全量并生成更高效的新 view，防止同一 view 中堆积过多文件或 transactions。并且上游 snapshot 会级联影响下游 incremental transform，让其也 snapshot 一次。[S10]

【推断】Foundry 的增量不是“永远只增量、永远不回扫历史”，而是“以 transaction/view 为单位做阶段性压缩与重置”。这和 LSM/Delta/Iceberg 中定期 compact/optimize 的运营思路相近，但 Foundry 对外暴露的是 snapshot 语义，不是底层文件整理 API。

### 10. 可观测性围绕 transaction range，而不是 offset group

【事实】Spark details 的 Snapshot/Incremental 页会展示：

- `Range of current view`
- `Range of processed batch`
- `Previous end transaction`[S5]

【推断】这说明 Foundry 对增量位点的公开观察窗口是“每次 job 读了哪段 transaction range”，而不是 Kafka/Paimon 那样可直接操作的 consumer group offset。

【推断】官方公开文档没有发现用户可直接管理的增量消费位点 API，因此“位点由平台内部托管”是一个较强但仍需保守表述的推断。

---

## 三、关键实现点与设计抓手

### 1. append-only 不是优化建议，而是正确性约束

【事实】官方反复把 `APPEND` 定义为 incremental pipeline 的基础，把 `UPDATE` 定义为破坏 append-only requirement 的行为。[S1][S3]

【推断】这意味着链路设计的关键不在下游 compute，而在上游 ingestion contract。只要上游源端会回写旧文件，增量批链路就会频繁退化成 snapshot。

### 2. 增量能力建立在“历史结果可复用”前提上

【事实】官方要求 compute function 同时支持 incremental 和 non-incremental 两种模式，并提供 `previous`/`current`/`added` 三种读模式与 `modify`/`replace` 写模式帮助开发者组织逻辑。[S3]

【推断】换句话说，Foundry 没有承诺“平台自动推导你这段业务逻辑的增量 algebra”；真正被复用的是历史数据和历史 transaction 位置，而不是 SQL 优化器级别的全自动增量重写。

### 3. `snapshot_inputs` 是维表/参考表的重要设计接口

【事实】官方直接把“周期性整体重写但不应破坏增量”的 reference dataset 作为 `snapshot_inputs` 的典型例子。[S3]

【推断】对于事实表 append、维表 snapshot 的常见建模，`snapshot_inputs` 是 Foundry 官方语义里最接近“事实流 + 维表快照 join”的标准做法。

### 4. retention 被当成治理删除，而不是业务删除

【事实】`allow_retention=True` 只豁免 retention policy 引起的 `removed` 变化；普通 delete 仍然会触发 snapshot。[S3]

【推断】这说明 Foundry 在增量语义上区分了“治理导致的数据老化清理”和“业务意义上的数据撤回/修正”，这两类删除不能混为一谈。

### 5. 调度系统的主语是 stale graph，不是 transaction queue

【事实】schedule 只构建 stale 节点；当所有目标都 up-to-date 时，run 会被 ignored。[S9]

【事实】transaction limit 场景下，平台通过 re-trigger 持续构建直到不再 stale。[S5]

【推断】所以 Foundry 的调度层关心的是“图上哪些目标还没追平”，而不是“维护一条显式的消费队列”。这是它和典型消息流处理框架的根本差异。

---

## 四、能力边界与不适用场景

1. 【事实】如果上游是 `UPDATE` 型增量镜像，Foundry 官方明确说它会阻断下游 incremental processing。[S1]
2. 【事实】如果 transform 需要 transaction limits，输入 dataset 当前 view 里必须只有 `APPEND` 事务，不能有 `DELETE` 或 `UPDATE`，否则 job 会失败。[S5]
3. 【推断】频繁更正历史、频繁删除旧数据、或依赖行级撤回/重放的业务，不适合把 Foundry incremental batch 当成 CDC 引擎来使用。
4. 【推断】当业务真正需要秒级、持续状态、事件级 exactly-once 语义时，应该转向 Foundry 的 streaming/Flink 能力，而不是继续强化 incremental batch。
5. 【猜测】对于跨多个输出 dataset 的原子提交边界，官方公开资料仍不足，不能假设一次 build 对多个输出具备跨 dataset 的统一原子事务。

---

## 五、对自研平台的实现启示

1. 【推断】优先建设 `dataset transaction/view`，再建设增量 transform；没有 transaction view，就无法稳定表达“added / previous / current”。
2. 【推断】增量运行时必须保存“上次成功处理到哪里”的结构化元数据，并能在每次运行前做 append-only 校验。
3. 【推断】调度层必须内建 stale 判断和追平逻辑，否则 transaction limit 只会把大任务切碎，却没有机制自动追平 backlog。
4. 【推断】需要给开发者明确暴露“双模式编程接口”：同一段逻辑既能在增量跑，也能在全量 fallback 跑。
5. 【推断】运维面不能只暴露 job 成败；至少要暴露 previous end、current view、processed batch 三段 transaction range，才能排查“为什么没有追平”“为什么 fallback”“为什么 branch 不一致”。

---

## 六、证据缺口

1. 【推断】官方公开材料没有给出用户可控的 incremental cursor / consumer offset API；“位点完全平台内管”目前仍是缺失证据上的强推断。
2. 【推断】官方没有公开 stale 传播算法的完整实现，只能从 schedule ignored、re-trigger 和 lineage out-of-date 这些外部行为反推。
3. 【推断】官方没有公开“复杂 transform 在内部如何把 `modify/replace` 映射到物理文件写入计划”的底层执行细节。
4. 【猜测】如果要继续深挖，可在真实 Foundry 环境中验证 `strict_append + require_incremental + transaction_limit` 的异常组合行为，以及多输出 transform 的提交边界。

---

## 七、如何识别什么样的 dataset 和 pipeline 支持 incremental

### 1. 先判断 dataset 是否具备增量输入资格

满足下面三条，才值得继续看 pipeline 逻辑：【事实+推断】

1. 输入 dataset 的新变更主要来自 `APPEND`，或来自“不修改已有文件”的 additive `UPDATE`。【事实，[S1][S3]】
2. 输入 dataset 不会频繁出现 `SNAPSHOT`、覆盖式 `UPDATE` 或普通 `DELETE`。【事实，[S1][S3]】
3. 数据规模足够大，且每次新增只占全量的一部分；否则 snapshot 重算也许更简单，收益不高。【事实+推断，[S7][S8]】

如果不满足第 1 条或第 2 条，这个 dataset 通常就不适合作为 incremental input。【事实】

Palantir build 不会自动理解“事实表”“维表”“配置表”这些业务分类；这些是开发者或建模者给输入赋予的语义。【推断】在官方公开机制里，build/runtime 区分输入角色的方式是 transform 定义：未列入 `snapshot_inputs` 的输入按 incremental input 处理，需要满足 append-only / retention 规则；列入 `snapshot_inputs` 的输入按当前完整 view 读取，并从普通 incremental input 的 start transaction 一致性检查中排除。【事实，[S2][S3]】

因此，“事实表 append、维表 snapshot”不是 Foundry 自动推断出来的表类型规则，而是通过 `@incremental(snapshot_inputs=[...])` 或等价 pipeline 配置表达出来的运行契约。【事实+推断】官方示例中，`phone_numbers` 是增量输入，只读上次运行后未见过的电话号码；`country_codes` 被声明为 snapshot input，每次读完整国家码映射表，即使它被周期性整体重写也不阻断增量运行。【事实，[S3]】

### 2. 再判断 pipeline 逻辑是否“只需要处理新增交易”

最核心的问题只有一个：

> 本次新增输入到来时，是否需要改写历史已经输出的数据？

如果答案是“不会”，通常可以 incremental；如果答案是“会”，默认就应该按 snapshot 看待。【推断】

#### 通常支持 incremental 的逻辑

- 纯过滤、映射、列派生、格式转换。【事实+推断，[S3][S7]】
- 对新增事实数据做 append-only enrich，例如和稳定维表做 join。【事实+推断，[S3]】
- 历史输出一旦写出就不需要再修改，只需要继续追加新结果。【事实+推断，[S3][S7]】
- 聚合只针对“当前 transaction 批次”本身，而不是要求重算全历史窗口。【事实，[S7]】

#### 默认不支持或要非常谨慎的逻辑

- 新数据到来后会改变历史输出结论的全局聚合。【推断】
  例如“全表 topN”“全量去重后再计数”“累计唯一用户数但不维护历史状态表”。
- 依赖全历史重排的窗口函数、pivot、rank、全局 distinct。【事实+推断，[S7]】
- 迟到数据会回补并改变历史分组结果，但输出又不能安全 merge/replace 对应历史分区。【推断】
- 任何要求“修改已有输出文件/已有历史结果”的逻辑。【事实+推断，[S3][S7]】

### 3. 聚合不等于一定不能 incremental

这是最容易误判的点。

【事实】Palantir 官方在 Pipeline Builder 文档里没有说“aggregation 一定不能 incremental”，而是说如果 pipeline 包含 `window functions, aggregations, or pivots`，需要确认它们“meant to operate on the current transaction only”。[S7]

【事实】Palantir 官方代码示例还专门给了 `Incremental sum aggregation`，说明“聚合可以 incremental”，前提是你把逻辑写成“增量输入 + 历史输出/状态”的模式，而不是每次只对新增做一个局部 group by 就假装它等于全局结果。[S11]

所以更准确的判断是：

- “只对新增批次做局部聚合，然后追加一行结果”可能支持 incremental。【事实+推断】
- “每来一批都要重算全历史聚合结果”默认不支持 append-only incremental。【推断】
- “可以把历史结果当状态读出来，再和本批增量合并写回”则有机会支持，但通常需要显式设计 read/write mode 和状态表结构。【事实+推断，[S3][S11]】

### 4. 可以用一个五步 checklist 快速判定

1. 输入 dataset 最近的 transaction 类型是不是以 `APPEND` 为主。
2. 新数据到来后，旧输出是否仍然保持正确。
3. 如果逻辑里有 join / aggregation / window / distinct / pivot，它们是否只作用于本批新增，或者是否有明确的历史状态合并方案。
4. 输出是否可以自然 append，或至少可以在非增量时安全 fallback 到 snapshot。
5. 如果上游偶发 snapshot / retention / schema 变化，代码是否仍能正确运行。

五步里只要第 2、3、4 任一明显失败，就不要把它当“天然 incremental pipeline”。【推断】

### 5. 一个实用的分类法

#### A 类：天然支持 incremental

- append-only 明细表
- append-only 事实表上的过滤、轻转换、稳定维表 enrich
- “新增输入只产生新增输出”的链路

这类最适合直接 incremental。【推断】

#### B 类：可改造成 incremental

- 日粒度/批次粒度聚合
- 可维护状态表的累计指标
- 可按分区 replace 或 merge 的局部重算链路

这类不是“天然 incremental”，但通过显式状态管理、分区化输出、历史结果回读，通常能做成 incremental。【事实+推断】

#### C 类：优先保持 snapshot

- 全局排序 / 全局 topN
- 强依赖全历史窗口重算
- 高频历史修正、撤回、覆盖更新
- 输入源天然不是 append-only

这类强行 incremental，复杂度和正确性风险通常高于收益。【推断】

---

## 参考来源

- [S1] Palantir Foundry, Core concepts: Datasets: https://www.palantir.com/docs/foundry/data-integration/datasets
- [S2] Palantir Foundry, Python incremental transforms overview: https://www.palantir.com/docs/foundry/transforms-python/incremental-overview
- [S3] Palantir Foundry, Python incremental transforms usage guide: https://www.palantir.com/docs/foundry/transforms-python/incremental-usage
- [S4] Palantir Foundry, Incremental transforms examples and errors: https://www.palantir.com/docs/foundry/transforms-python-spark/incremental-examples
- [S5] Palantir Foundry, Limit batch size of incremental inputs: https://www.palantir.com/docs/foundry/transforms-python-spark/incremental-transaction-limits
- [S6] Palantir Foundry, Schedules core concepts: https://www.palantir.com/docs/foundry/data-integration/schedules
- [S7] Palantir Foundry, Create a schedule: https://www.palantir.com/docs/foundry/building-pipelines/create-schedule
- [S8] Palantir Foundry, Schedule troubleshooting: https://www.palantir.com/docs/foundry/building-pipelines/schedule-troubleshooting
- [S9] Palantir Foundry, Data Lineage build datasets: https://www.palantir.com/docs/foundry/data-lineage/build-datasets
- [S10] Palantir Foundry, Maintaining incremental performance: https://www.palantir.com/docs/foundry/building-pipelines/maintaining-incremental-performance
- [S11] Palantir Foundry, Code examples: Incremental sum aggregation: https://www.palantir.com/docs/foundry/code-examples/incremental-transforms-transforms
- [S12] 仓库既有证据：`docs/raw/06-incremental-pipeline.md`
- [S13] 仓库既有证据：`docs/raw/27-incremental-scheduling-transaction.md`
