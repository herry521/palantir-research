# Foundry 增量链路（Incremental Pipeline）

**调研日期：** 2026-05-01  
**关联 Issue：** #2

---

## 概述

Foundry 增量链路是批处理与流处理之间的中间选项，核心目标是"只重算变化的部分"。它通过 `@incremental` 装饰器、Transaction History 机制和 Dataset 版本链路实现，在延迟（1-5 分钟级）和计算成本之间取得平衡。增量批处理（Incremental Batch Transform）是 Foundry 推荐的主要优化手段，适用于大多数需要近实时但不需要秒级响应的场景。

---

## 增量触发机制

### 触发条件

`@incremental` 装饰器使 Transform 具备感知输入 Dataset 变更的能力。每次 Transform 被调度执行时，Foundry 会检查输入 Dataset 自上次成功构建以来是否有新的 Transaction（事务），若有则触发增量执行，若无则跳过。[事实，来源：palantir.com 官方文档]

触发逻辑的核心依据是 **Transaction History**——Foundry 对每个 Dataset 记录完整的事务日志，每条记录对应一次数据变更操作（APPEND / UPDATE / SNAPSHOT）。增量 Transform 读取"上次运行成功时消费到的事务位置"，只处理之后的新事务。[事实，来源：palantir.com 官方文档]

### `semantic_version` 参数的作用

`@incremental` 装饰器支持 `semantic_version` 参数（默认值 1）。若开发者修改了 Transform 逻辑，可将此参数加 1，这会触发一次强制全量重算（full recompute），使历史增量结果失效并从头重建输出 Dataset。当前版本号与上次运行版本号不一致时，Transform 自动回退为非增量执行。[事实，来源：palantir.com 官方文档]

### `require_incremental` 参数

- `require_incremental=True`：若 Foundry 判断当前不满足增量执行条件，直接抛出异常终止（不自动 fallback）；首次构建除外。
- `require_incremental=False`（默认）：Foundry 尽力增量执行，不满足时自动 fallback 到全量重算。[事实，来源：palantir.com 官方文档]

---

## 增量计算粒度

Foundry 增量计算的粒度是**文件级（Transaction/File 级别）**，而非行级 changelog。

具体机制：
- Dataset 存储基于 Parquet 文件，每次 APPEND 事务写入一批新 Parquet 文件
- 增量 Transform 通过"read mode = added"只读取自上次运行以来新增的文件
- Foundry 不像 Apache Flink 那样维护行级 changelog（+I / -U / +U / -D），而是在文件层面做 diff

[事实，来源：palantir.com 官方文档；"added" read mode 机制]

对于 UPDATE 类型的事务（文件被覆盖而非追加），Foundry **可能破坏增量语义**，详见"失败回退策略"一节。

`v2_semantics` 标志对读写行为有影响：
- `v1_semantics`（默认）：即使只有少量变化，Transform 也可以读写所有数据
- `v2_semantics`（推荐）：更严格的增量语义，确保非 catalog 输入/输出资源也能增量处理 [事实，来源：palantir.com 官方文档]

---

## 与 Iceberg/Paimon 增量读取机制对比

| 维度 | Foundry Incremental | Apache Iceberg | Apache Paimon |
|---|---|---|---|
| 变更追踪粒度 | 文件级（Transaction/File diff） | Snapshot diff（文件级，manifests） | 行级 changelog（+I / -D / -U / +U） |
| 消费位点机制 | Transaction History 内部位点 | Snapshot ID（`startSnapshotId` / `endSnapshotId`） | consumer-id（持久化消费位点） |
| 行级 CDC | 不支持 | 通过 Equality Delete 支持有限 CDC | 原生支持（MergeOnRead / ChangelogProducer） |
| 跨系统消费 | 内部封闭（不暴露位点 API） | 开放，外部系统可直接读 snapshot | 开放，consumer-id 可被任意消费者使用 |
| 存储格式 | Parquet（Foundry 内部管理） | Parquet/ORC/Avro + Iceberg 元数据 | Parquet/ORC + Paimon 元数据 |

**核心差异分析：**

1. **Foundry 没有对外暴露的 Snapshot ID 机制**：Iceberg 提供 `startSnapshotId` / `endSnapshotId` 参数供外部系统精确指定读取范围，Paimon 提供 consumer-id 持久化消费位点，而 Foundry 的 Transaction History 位点是内部实现，用户无法直接操作。[推断，基于搜索结果中未发现公开的 snapshot ID API]

2. **Foundry 无行级 CDC**：批式增量 Transform 只能做 APPEND（新增文件），不能做行级 -D（物理删除行）操作。Paimon 的 Partial-Update、Sequence Field 等行级合并语义在 Foundry 批式层没有对应实现。[事实，来源：palantir.com 文档描述的 APPEND 约束]

3. **增量语义的封闭性**：Foundry 增量链路是平台内部特性，不像 Iceberg/Paimon 可以被 Flink/Spark/Trino 等多引擎共享消费。[推断]

---

## 失败回退策略

### 自动 fallback 触发条件

以下情况会导致 Foundry 自动从增量模式退回全量重算（SNAPSHOT 模式）：

1. **输入 Dataset 发生 UPDATE 事务**：UPDATE 事务会覆盖或删除已有文件，破坏 append-only 假设，Foundry 将触发全量重算。[事实，来源：palantir.com 官方文档]
2. **首次构建**：输出 Dataset 尚不存在，必须全量计算。[事实]
3. **`semantic_version` 被 bump**：版本号变更强制全量重算。[事实，来源：palantir.com 官方文档]
4. **历史增量产生性能退化**：随着 APPEND 事务积累，增量文件碎片增多，Foundry 官方建议定期对输入 Dataset 执行 SNAPSHOT build，以压缩历史文件，防止增量 Transform 越来越慢。[事实，来源：palantir.com 官方文档]

### `snapshot_inputs` 参数

对于某些输入 Dataset（如维表、配置表）会频繁更新但不应触发增量失效，可通过 `snapshot_inputs` 参数将其声明为"快照输入"。Foundry 会在每次增量执行时读取这些 Dataset 的完整最新快照，而不追踪其事务增量。[事实，来源：palantir.com 官方文档]

### 行为对比

| 场景 | `require_incremental=False`（默认） | `require_incremental=True` |
|---|---|---|
| 首次构建 | 全量执行 | 全量执行（豁免） |
| 输入有 UPDATE 事务 | fallback 全量 | 抛出异常 |
| `semantic_version` 变更 | 全量执行 | 全量执行 |
| 正常增量 | 仅处理新事务 | 仅处理新事务 |

---

## 流批差异

### 批式增量 Transform（`@incremental` + Spark）

| 特性 | 描述 |
|---|---|
| 执行引擎 | Apache Spark |
| 触发方式 | 调度触发（schedule）或上游 Dataset 更新驱动 |
| 延迟 | 1-5 分钟级 |
| 状态管理 | 通过 Transaction History 记录上次处理位点 |
| 一致性 | At-least-once（增量语义，不保证 exactly-once） |
| 主要工具 | `@incremental` 装饰器（Code Repository） |
| 输出操作 | 只能 APPEND 新文件，不能删除/修改已有行 |
| 资源消耗 | 按需消耗（运行时计费），空闲不计费 |

### 流式 Transform（Flink-based Streaming Pipeline）

| 特性 | 描述 |
|---|---|
| 执行引擎 | Apache Flink |
| 触发方式 | 持续运行，事件驱动 |
| 延迟 | < 15 秒（推荐配置下） |
| 状态管理 | Flink Checkpoint（周期性快照流位置 + 算子状态） |
| 一致性 | 支持 AT_LEAST_ONCE（默认）和 EXACTLY_ONCE（需显式配置） |
| 主要工具 | Pipeline Builder（Streaming Pipeline） |
| 输出操作 | 持续写入，支持 Ontology 实时更新 |
| 资源消耗 | 持续消耗（即使无新数据也占用 Compute），成本最高 |

**核心语义差异：**

1. **增量批处理的"增量"是离散的**：每次 Spark Job 运行处理一批新事务，两次运行之间有间隔（通常分钟级）。[事实]

2. **Flink 流处理的"增量"是连续的**：Flink 算子持续消费 Kafka/流数据，不存在"批次间隔"概念；每条消息到达即处理。[事实，来源：Foundry 官方文档]

3. **状态管理机制不同**：
   - 批式增量：状态 = Transaction History 中的"已处理位点"，存储在 Foundry Dataset 元数据层
   - 流式增量：状态 = Flink Checkpoint（含 Kafka Offset、算子内存状态），存储在 Foundry 内部 Checkpoint 存储

4. **回退语义不同**：批式增量可以 fallback 到全量 Spark 重算；流式 Pipeline 失败时 Flink 从最近 Checkpoint 恢复，没有"全量重跑"的概念（除非从头消费 Kafka）。[推断，基于 Flink Checkpoint 机制]

5. **输出写入方式不同**：增量批处理输出为 APPEND 事务到 Dataset（Parquet 文件）；流式处理输出为持续写入，可直接更新 Ontology Object Type（行级更新语义）。[推断，基于 Pipeline Builder 文档描述]

---

## Dataset 版本管理

### 版本控制模型（Git-like）

Foundry Dataset 的版本管理采用类 Git 模型：

- **每次数据写入生成一个新的不可变版本（Transaction）**，版本一旦创建不可修改
- **支持 Dataset Branching**：类比 Git branch，用于隔离实验性数据变更，防止并发操作互相污染
- **Diff-based 存储**：APPEND 类型的事务以"增量文件"形式存储（diff 文件夹），不复制全量数据，节省存储空间；SNAPSHOT 类型则替换全量文件

[事实，来源：palantir.com 官方文档，"Foundry treats datasets similarly to how Git versions code"]

### 消费位点机制（与 Paimon consumer-id 对比）

**Foundry 的位点实现：**
- 增量 Transform 内部记录"上次处理到的 Transaction ID"，作为下次运行的起始位点
- 此位点由 Foundry 平台自动管理，开发者无需手动指定
- **不对外暴露类似 Paimon consumer-id 的显式位点 API**，也没有 Iceberg 风格的 `startSnapshotId` 参数

[推断：基于文档中"Foundry analyzes changes in input datasets since the last successful run"的描述，以及搜索结果中未找到任何公开位点 API]

**与 Paimon consumer-id 的差异：**

| 维度 | Foundry Transaction History | Paimon consumer-id |
|---|---|---|
| 位点类型 | 内部 Transaction ID | 显式命名的消费者 ID |
| 对外可见 | 否（平台内部管理） | 是（多消费者可独立维护位点） |
| 多消费者支持 | 每个 Transform 独立维护位点 | 多个 consumer-id 独立读取同一 changelog |
| 手动控制 | 不支持（除 semantic_version 重置） | 支持手动 reset consumer offset |
| 跨引擎共享 | 不支持 | 支持（Flink/Spark 均可读） |

### 版本号与增量计算强绑定

`semantic_version` 参数本质上是一个"逻辑版本号"，用于将 Transform 代码逻辑版本与数据版本绑定。当代码逻辑变更时，通过 bump version 触发全量重算，确保输出 Dataset 与当前 Transform 逻辑一致。[事实，来源：palantir.com 官方文档]

---

## Lineage 中的体现

### Lineage 的可视化与追踪

Foundry 的 **Data Lineage** 工具提供交互式数据流向图，覆盖增量链路：

1. **增量 Transform 在 Lineage 图中与普通 Transform 无差异**：Lineage 图展示的是 Dataset 之间的逻辑依赖关系（哪个 Transform 以哪些 Dataset 为输入、输出哪些 Dataset），不区分全量还是增量执行模式。[推断，基于 Lineage 文档描述的节点为"artifact"和"ontology entity"]

2. **过期状态感知**：Lineage 图可以识别哪些 Dataset 已"过期"（输入已更新但下游还未重算），并支持直接从 Lineage 图发起构建触发。[事实，来源：palantir.com 官方文档]

3. **Build History 与版本关联**：平台记录每次构建使用的代码版本（Code Repository commit）和输出 Dataset 版本（Transaction ID），可追溯"哪个代码版本产出了哪个数据版本"。[事实，来源：palantir.com 官方文档]

4. **增量 vs 全量执行在 Lineage 中不可区分**：Lineage 层面不记录"本次是增量执行还是全量 fallback"，这一信息只在 Build Log 中可查。[猜测，基于 Lineage 工具定位于展示数据流向而非执行模式]

5. **Ontology 集成**：Lineage 图可展示 Dataset 到 Ontology Object Type 的映射关系，使流式增量（Flink 持续写入 Ontology）与批式增量（Spark APPEND 到 Dataset）的下游消费路径统一可见。[推断，基于 Lineage 文档描述"display artifacts and ontology entities"]

---

## 总结与可信度说明

### 核心结论

1. **增量触发基于 Transaction History**：`@incremental` 装饰器通过检测输入 Dataset 自上次成功构建以来的新事务来决定是否增量执行，位点由平台自动管理，对开发者透明。[事实，palantir.com]

2. **增量粒度是文件级而非行级**：Foundry 批式增量以 Parquet 文件为最小处理单位，APPEND 新文件，无行级 changelog；与 Paimon 的行级 CDC 语义有本质差异。[事实+推断]

3. **Fallback 全量重算是自动的**：输入有 UPDATE 事务、首次构建、或 semantic_version 变更时，Foundry 自动降级为全量 Spark 重算（除非 `require_incremental=True` 强制失败）。[事实，palantir.com]

4. **流批增量语义有本质不同**：批式增量是"离散事务驱动 + Spark 执行 + Transaction History 位点"；流式增量是"连续事件驱动 + Flink 执行 + Checkpoint 位点"，两者没有统一的位点模型。[事实+推断]

5. **无对外暴露的 Snapshot ID / consumer-id 机制**：Foundry 的消费位点是平台内部实现，不像 Iceberg/Paimon 提供开放的跨系统消费 API。[推断，基于文档无相关 API 描述]

6. **Lineage 层面流批一致**：无论批式还是流式增量，Lineage 图均以统一的 Dataset → Transform → Dataset 有向图展示，不感知执行模式差异。[推断]

### 可信度分布

| 内容 | 可信度 | 依据 |
|---|---|---|
| `@incremental` 装饰器机制、Transaction 类型 | [事实] | palantir.com 官方文档 |
| `semantic_version` / `require_incremental` / `snapshot_inputs` 参数 | [事实] | palantir.com 官方文档 |
| Fallback 触发条件（UPDATE 破坏增量） | [事实] | palantir.com 官方文档 |
| v2_semantics 行为差异 | [事实] | palantir.com 官方文档 |
| Flink Checkpoint 作为流式位点 | [事实] | palantir.com 官方文档（03 调研） |
| 内部位点不对外暴露 | [推断] | 文档中无公开 API，合理推断 |
| Lineage 不区分增量/全量执行模式 | [猜测] | 无直接证据，基于 Lineage 工具定位推测 |
| 批式增量无行级 CDC | [事实+推断] | APPEND-only 约束 + 无 changelog API 文档 |

---

## 参考来源

- Palantir Foundry 官方文档：Incremental Transforms（palantir.com）
- Palantir Foundry 官方文档：Dataset Versioning and Branching（palantir.com）
- Palantir Foundry 官方文档：Data Lineage（palantir.com）
- Palantir Foundry 官方文档：Streaming Pipelines / Pipeline Builder（palantir.com）
- 调研背景文档：`docs/raw/03-streaming-batch-architecture.md`（Flink 流处理引擎详情）
- Apache Iceberg 官方文档：Incremental Read（iceberg.apache.org）
- Apache Paimon 官方文档：consumer-id 机制（paimon.apache.org）
