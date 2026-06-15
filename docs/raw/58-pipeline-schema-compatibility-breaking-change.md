# 58 — Pipeline Output Dataset Schema 兼容性、破坏性变更与 Rename 判定调研

**日期：** 2026-06-15  
**关联 Issue：** #64  
**所属 Epic：** #63  
**类型：** 技术调研 / Pipeline output schema / Compatibility / Breaking change / Rename detection  
**可信度原则：** 以 Palantir 官方文档为可信事实来源；非官方材料不作为本文事实依据。  

---

## 1. 总结与洞察

1. 【事实】Foundry 对 output dataset schema 变更的“兼容性”判断不是单一静态规则，而是落在多个执行面：Dataset view schema 是否可成立、Pipeline Builder proposal 是否有 schema errors、incremental build 是否还能继续、以及旧数据是否仍能被新 schema 安全解释。
2. 【事实】官方已明确的低风险变更是“新增输出列”；在 Pipeline Builder streaming/incremental output 语义里，加列不要求 replay，而删列属于 state break，要求 replay。对 Python incremental transform，如果只新增列，旧行该列会保留为 `null`，若要回填历史则需触发一次非增量重算。
3. 【事实】官方已明确的高风险或破坏性变更包括：删列、导致 `previous` schema 校验失败的列类型/nullability/顺序变化、以及 append ingest 中真实 schema drift。后两类官方分别给出“触发 snapshot/full rebuild”与“新建 dataset 承接新 schema”的处置路径。
4. 【事实 + 推断】Palantir 官方文档没有给出“仅凭最终 schema diff 自动判定 rename”的通用机制。相反，官方一方面提供显式 Rename Columns / Replace columns 入口，另一方面又明确 PySpark rename 可以表达成 `withColumn(new).drop(old)`；因此只看前后 schema，不能可靠区分 rename 和 drop+add。
5. 【建议】自建平台应把 schema 变更治理拆成三层：`compatibility classification`、`breaking-change handling policy`、`operation provenance`。其中 rename 识别必须优先依赖操作 provenance（显式 rename 节点、代码 diff、lineage/code preview），不能只依赖列名 diff。

---

## 2. 问题与结论边界

本文回答三个问题：

1. Pipeline 变更导致 output dataset schema 变化时，兼容性如何判定。
2. 破坏性变更如何处理。
3. 一个新列名对应的操作，如何识别是 rename，还是 drop+add。

本文只把 Palantir 官方文档直接支持的内容记为【事实】；基于多条官方事实拼接出的工程判断记为【推断】；官方没有公开答案的地方明确标为【待验证】。

---

## 3. 官方资料基线

| 编号 | 官方来源 | 本文用途 |
|---|---|---|
| S01 | https://www.palantir.com/docs/foundry/data-integration/datasets/ | schema 存在于 dataset view、schema 可随时间变化 |
| S02 | https://www.palantir.com/docs/foundry/api/datasets-v2-resources/datasets/get-dataset-schema | schema 查询坐标：branch、transaction、schema version |
| S03 | https://www.palantir.com/docs/foundry/pipeline-builder/breaking-changes | output schema 变更何时需要 replay；input schema pinning |
| S04 | https://www.palantir.com/docs/foundry/pipeline-builder/branches-approve-a-change/ | proposal 中 schema errors 必须修复后才能 merge |
| S05 | https://www.palantir.com/docs/foundry/transforms-python/incremental-usage/ | `previous` schema 校验边界：类型、nullability、列顺序 |
| S06 | https://www.palantir.com/docs/foundry/transforms-python-spark/incremental-examples/ | 加列后旧行补 `null`；`semantic_version` 触发非增量重算 |
| S07 | https://www.palantir.com/docs/foundry/transforms-java/incremental-transforms/ | Java low-level `SchemaModificationType.NEW_SCHEMA` 与 snapshot 要求 |
| S08 | https://www.palantir.com/docs/foundry/data-connection/faq/ | append ingest 遇到真实 schema drift 时建议新建 dataset |
| S09 | https://www.palantir.com/docs/foundry/pb-functions-transform/renameColumnsV1/ | Pipeline Builder 中 rename 是显式一等操作 |
| S10 | https://www.palantir.com/docs/foundry/pipeline-builder/management-find-and-replace/ | 列名替换入口，表明平台支持显式 rename/refactor |
| S11 | https://www.palantir.com/docs/foundry/data-lineage/dataset-preview-logic/ | 可在 lineage 中看 code logic，用于识别 rename provenance |
| S12 | https://www.palantir.com/docs/foundry/transforms-python-spark/pyspark-columns/ | 官方明确 rename 也可视作 `withColumn(new).drop(old)` |

---

## 4. 兼容性如何判定

### 4.1 先看 Foundry 的稳定对象：schema 绑定在 dataset view 上

【事实】Dataset 文档说明，schema 是 dataset view 上的元数据，schema 会随着时间变化；例如新 transaction 可以引入新列或变更字段类型。  
【事实】`Get Dataset Schema` API 支持按 `branchName`、`endTransactionRid`、`versionId` 查询 schema。

这意味着兼容性判断不能脱离“哪个 branch / 哪个 transaction view / 哪个 schema version”来谈。【推断】

### 4.2 兼容性不是一个布尔值，而是四道关卡

结合官方文档，schema 变更至少经过四类判断：

1. **Schema 能否在目标 view 上成立**  
   【事实】schema 本身是 view 元数据，可随 transaction 变化。
2. **Proposal / branch merge 能否通过**  
   【事实】Pipeline Builder proposal 若出现 schema 或 edit errors，必须先 `Fix schemas`，否则不能成功 build 和 merge。
3. **Incremental execution 能否继续**  
   【事实】Python `previous` 模式会把给定 schema 与上一版实际输出 schema 比较；若列类型、nullability 或列顺序不匹配，会抛异常。  
   【事实】Java low-level incremental transform 在 schema change 下是否继续成功，取决于 transform 是否依赖被改动列；依赖则失败并要求新的 snapshot。
4. **历史数据是否仍可被新 schema 安全解释**  
   【事实】Pipeline Builder output schema 删列要求 replay；Python incremental 加列时旧行保留 `null`，若要统一回填需非增量重算；Data Connection append ingest 真实 drift 时建议新建 dataset。

所以更准确的判定框架是：

| 判定层 | 兼容标准 | 结果 |
|---|---|---|
| Proposal/graph 层 | 没有 schema error，能修复后合并 | 可 merge |
| Incremental runtime 层 | 不破坏已有 incremental 语义与 `previous` schema 校验 | 可继续 incremental |
| Historical view 层 | 旧数据仍能被新 schema 解释，或允许通过 replay/full rebuild 统一 | 可在原 dataset 延续 |
| Dataset contract 层 | 若新旧 contract 已本质不同 | 应切新 dataset 版本 |

### 4.3 可直接视为“兼容”或“低风险”的官方场景

#### 场景 A：新增输出列

【事实】Pipeline Builder 文档明确：对 output schema 来说，adding new columns does not require a replay。  
【事实】Python incremental 示例明确：新增一列不会使 `is_incremental` 失效；下一次运行会把新列写入新行，而历史行该列为 `null`。

因此，“加列”是官方最明确的兼容性正例，但它只是“可继续运行/可不 replay”，不等于“历史数据自动完成语义迁移”。【推断】

#### 场景 B：输入 schema 变化但 pipeline 尚未 redeploy

【事实】Pipeline Builder 文档说明 input schemas are pinned when you deploy；若 input schema 变化，pipeline 继续按旧 schema 读取，直到手动 redeploy。

这类变化不是“自动兼容”，而是“先冻结旧 contract，再由 redeploy 显式接受新 contract”。【推断】

### 4.4 应直接视为高风险或破坏性的官方场景

#### 场景 A：删列

【事实】Pipeline Builder 文档明确：removing columns from an output schema is a state break that requires a replay。

#### 场景 B：`previous` schema 校验失败

【事实】Python incremental `previous` 读取时，如果提供的 schema 与上一版实际输出在列类型、nullability 或列顺序上不匹配，会抛异常；若 schema 中字段标成 non-nullable，也会因 Foundry 保存为 nullable 而报 `SchemaMismatchError`。

这说明只要 schema 变化触碰这些维度，就不应再被视作“天然兼容”。【推断】

#### 场景 C：依赖被改动列的 Java incremental transform

【事实】Java low-level incremental 文档明确：若 transform 依赖 schema 变化涉及的列，增量构建会失败；这种情况下需要先做新的 snapshot，之后才能恢复 incremental。

#### 场景 D：append ingest 中的真实 schema drift

【事实】Data Connection FAQ 明确：若 file 或 JDBC table 在 incremental `APPEND` transactions 之间真实发生 schema 变化，则需要 new dataset for the new schema。

这说明官方并不把所有 schema evolution 都视为“同一 dataset 内兼容演进”；至少在 append ingest 场景下，真实 drift 的官方建议是版本化 dataset，而不是强行续写。【事实 + 推断】

### 4.5 可执行的兼容性判定准则

基于以上官方材料，建议把 output schema 变更判成三类：

| 分类 | 判定条件 | 官方依据 | 处置 |
|---|---|---|---|
| 兼容演进 | 加列；不破坏 proposal；不破坏 incremental 语义 | S03, S06 | 可继续 incremental；必要时后补历史 |
| 破坏性但可重建 | 删列；类型/nullability/顺序变化；列依赖导致 incremental 失败 | S03, S05, S07 | replay 或 snapshot/full rebuild |
| 破坏性且应切版本 | 真实 schema drift 代表新的数据 contract | S08 | 新建 dataset 版本 |

---

## 5. 破坏性变更如何处理

### 5.1 官方已经给出的处理手段

#### 手段 A：先修 schema errors，再 merge

【事实】proposal 中若有 schema errors，必须 `Fix schemas` 后才能成功 build 和 merge。

#### 手段 B：replay

【事实】删列属于 output schema state break，要求 replay。  
【事实】Pipeline Builder 允许 replay 时配置 selective data re-ingestion，并可选择不 reset outputs。

#### 手段 C：触发一次非增量重算

【事实】Python incremental 示例说明，若希望给历史数据补上新增列，应提升 `semantic_version`，让 transform 非增量运行一次。  
【事实】Java incremental 文档说明，列依赖导致 schema change 影响增量时，需要新 snapshot。

#### 手段 D：新建 dataset

【事实】Data Connection append ingest 遇到真实 drift 时，官方建议新建 dataset 承接新 schema。

### 5.2 官方没有承诺的“自动魔法迁移”

公开资料没有显示 Foundry 会自动把以下情况一律无损迁移：

- 删列后的历史视图重写
- 类型变化后的历史数据重解释
- 把 rename 自动识别并迁移为历史别名

因此更稳妥的工程结论是：**破坏性 schema 变更必须显式选择 replay / snapshot rebuild / new dataset version 中的一种，而不是期待平台自动判定并无损修复。**【推断】

### 5.3 推荐的处理顺序

1. **先分类**：兼容演进、破坏性但可重建、破坏性且应切版本。  
2. **再选策略**：  
   - replay  
   - bump `semantic_version` / snapshot rebuild  
   - new dataset version  
3. **最后再 merge**：proposal 层 schema errors 清零后再合主分支。

---

## 6. 如何识别新列名是 rename 还是 drop+add

### 6.1 官方给出的关键事实：只看最终 schema 不够

【事实】Pipeline Builder 有显式的 Rename Columns transform，输入是“旧列名 -> 新列名”的 rename 列表。  
【事实】Pipeline Builder 也有 Replace columns 功能，用于把某个列名在 pipeline 中批量替换。  
【事实】Data Lineage 支持查看 dataset 的 code logic。  
【事实】PySpark 官方参考明确写出：`withColumnRenamed("old_name", "new_name")` 也可以理解为 `withColumn("new_name", F.col("old_name")).drop("old_name")`。

最后这一点很关键：**同一个语义上的 rename，可以被表达成 add+drop 的代码形态。**【事实】

因此：

- 仅凭“旧 schema 少了 `old_name`，新 schema 多了 `new_name`”  
- 或仅凭“数据值看起来很像”  

都不能形成 Palantir 官方语义下的确定性 rename 结论。【推断】

### 6.2 可依赖的识别顺序

#### 第一优先级：操作 provenance

满足任一条件，可高置信度判定为 rename：

1. 【事实】Pipeline Builder diff 或 node 配置里存在显式 Rename Columns transform。  
2. 【事实】Pipeline Builder 使用了 Replace columns，并且 code/graph 反映是名称替换而不是业务重算。  
3. 【事实】Data Lineage / code preview 显示代码明确调用 rename 语义。

#### 第二优先级：代码级等价关系

若代码不是显式 rename，而是：

```python
df = df.withColumn("new_name", F.col("old_name")).drop("old_name")
```

那么从最终 schema 看它像 drop+add，但从业务语义看更接近 rename。  
不过这是**代码语义推断**，不是 schema diff 自身能证明的事实。【事实 + 推断】

#### 第三优先级：统计和内容相似性

【事实】proposal 界面可以比较列统计；Data Lineage 也能看 preview/code。  
这可以作为辅助信号，例如：

- 新旧列类型一致
- null 分布、distinct count、高频值接近
- 只有列名变、下游表达式引用整体替换

但这些都只能算“高度疑似 rename”，不能替代 provenance。【推断】

### 6.3 不应采用的判定方法

以下方法单独使用都不可靠：

1. 只看前后 schema diff。  
2. 只看列名相似度。  
3. 只看样本值相似。  
4. 只看某次 build 后是否还能跑通。

原因是官方已经明确 rename 与 add+drop 在代码层可以等价表达；既然表达方式可坍缩，schema 结果本身就不足以反推出唯一意图。【事实 + 推断】

### 6.4 实用判定规则

建议按下面顺序落地：

| 证据 | 判定 |
|---|---|
| 显式 Rename Columns / code rename 调用 | 认定为 rename |
| `new = old` 后立即 `drop old`，且无其他逻辑 | 认定为 rename-like rewrite，按 rename 治理 |
| 只有 schema diff，没有 provenance | 只能判为 unresolved schema change，不要自动当 rename |
| 新列是重算表达式、旧列被删除 | 判为 drop+add / recompute |

---

## 7. 对自建平台的直接启示

1. 【建议】兼容性判定不要只做 schema diff，要同时接 proposal/build/runtime/history 四个面。
2. 【建议】把 replay、full rebuild、new dataset version 设计成一等处置策略，并强制在 merge 前声明。
3. 【建议】rename 检测必须依赖稳定的操作 provenance：算子类型、代码 AST、lineage/code preview、变更 diff。
4. 【建议】如果系统无法证明是 rename，就不要自动迁移历史或下游依赖；默认按 breaking change 流程处理更稳。
5. 【建议】新增一层 `schema_change_policy` 元数据，至少记录：`classification`、`handling_strategy`、`requires_rebuild`、`new_dataset_version`、`rename_evidence`。

---

## 8. 仍待验证的问题

1. 【待验证】Foundry 是否存在未公开的字段级 lineage / refactor API，可把 rename 从代码层稳定映射到 schema change event。
2. 【待验证】Pipeline Builder proposal 的 schema compare 能否在 UI 或 API 中直接输出字段级 rename 语义，而不是只给 schema errors。
3. 【待验证】不同 compute engine（Spark、Faster、Streaming）对 rename-like rewrite 的内部 lineage 表达是否完全一致。

---

## 9. 参考来源

- Palantir Foundry - Core concepts / Datasets: https://www.palantir.com/docs/foundry/data-integration/datasets/
- Palantir Foundry API - Get Dataset Schema: https://www.palantir.com/docs/foundry/api/datasets-v2-resources/datasets/get-dataset-schema
- Palantir Foundry - Pipeline Builder / Breaking changes: https://www.palantir.com/docs/foundry/pipeline-builder/breaking-changes
- Palantir Foundry - Pipeline Builder / Approve a change: https://www.palantir.com/docs/foundry/pipeline-builder/branches-approve-a-change/
- Palantir Foundry - Python incremental usage: https://www.palantir.com/docs/foundry/transforms-python/incremental-usage/
- Palantir Foundry - Python incremental examples: https://www.palantir.com/docs/foundry/transforms-python-spark/incremental-examples/
- Palantir Foundry - Java incremental transforms: https://www.palantir.com/docs/foundry/transforms-java/incremental-transforms/
- Palantir Foundry - Data Connection FAQ: https://www.palantir.com/docs/foundry/data-connection/faq/
- Palantir Foundry - Rename columns transform: https://www.palantir.com/docs/foundry/pb-functions-transform/renameColumnsV1/
- Palantir Foundry - Find and replace in Pipeline Builder: https://www.palantir.com/docs/foundry/pipeline-builder/management-find-and-replace/
- Palantir Foundry - Data Lineage / Preview and logic: https://www.palantir.com/docs/foundry/data-lineage/dataset-preview-logic/
- Palantir Foundry - PySpark reference / Concept: Columns: https://www.palantir.com/docs/foundry/transforms-python-spark/pyspark-columns/
