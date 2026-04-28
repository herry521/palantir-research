# Palantir Pipeline 执行引擎调研

**调研日期：** 2026-04-16  
**调研方向：** 执行引擎 / Spark 集成 / 增量计算 / 调度机制

---

## 核心发现

### 1. Spark 集成架构

**托管方式：**
- Foundry 对用户完全隐藏 Spark 集群管理细节，用户无需配置 YARN/K8s
- 底层为托管 Spark 集群（云原生，Palantir 自运维）
- 用户通过 **Compute Profile（计算规格）** 选择资源大小，而非直接配置集群

**预定义 Compute Profile：**
| 规格 | 适用场景 |
|---|---|
| Extra Small | 小数据集，快速验证 |
| Small | 常规转换任务 |
| Medium | 中等规模 Join/聚合 |
| Large | 大数据集处理 |
| Extra Large | 超大数据集 / 复杂 ML 特征工程 |

**核心 Spark 参数（可自定义）：**
```
spark.executor.memory       # Executor JVM 内存
spark.executor.memoryOverhead  # Executor 堆外内存
spark.driver.memory         # Driver JVM 内存
spark.driver.memoryOverhead # Driver 堆外内存
spark.executor.cores        # 每个 Executor 核数
```

**Foundry 的封装层：**
- `TransformInput` / `TransformOutput` 对象封装了对 Foundry Dataset 的读写
- 用户通过 `input.dataframe()` 获取 Spark DataFrame，无需处理底层存储路径
- 自动处理数据集的 Transaction 版本隔离（读取时锁定版本，写入时创建新 Transaction）

---

### 2. 增量计算（Incremental Transforms）

**核心机制：**

增量计算的本质是 **Transaction 级别的差量计算**。Foundry 将每次数据集变更记录为 Transaction，类型分为：

| Transaction 类型 | 含义 | 增量兼容性 |
|---|---|---|
| `APPEND` | 新增文件，不修改已有文件 | ✅ 完全兼容 |
| `UPDATE` | 修改已有数据（覆盖） | ⚠️ 可能触发全量重算 |
| `SNAPSHOT` | 全量替换整个数据集 | ❌ 触发全量重算 |

**`@incremental` 装饰器工作原理：**

```python
from transforms.api import transform_df, Input, Output
from transforms.api import incremental

@incremental(snapshot_inputs=['config'])  # config 表允许全量变化
@transform_df(
    Output('/project/output/events_enriched'),
    events=Input('/project/input/events'),
    config=Input('/project/input/config'),
)
def compute(events, config):
    # events 此时只包含上次运行后的新增数据
    # config 是完整快照（因为声明了 snapshot_inputs）
    return events.join(config, 'type_id')
```

**装饰器参数说明：**
- `snapshot_inputs`：声明哪些输入是"快照型"（如维表/配置表），允许其全量变化而不阻断增量运行
- `require_incremental=True`：强制要求增量执行，不满足条件时 Build 失败（初始 Build 除外）
- `semantic_version`：整数版本号，变更后强制全量重算（用于 Transform 逻辑变更时）
- `v2_semantics=True`：启用 v2 语义（推荐），兼容性更好

**增量 vs 全量的切换逻辑：**
```
输入数据集上次运行后只有 APPEND 事务？
  → 是：增量运行（只处理新增分区/文件）
  → 否（有 UPDATE/SNAPSHOT）：全量重算

require_incremental=True 且无法增量？
  → Build 失败（初始 Build 例外）
```

**性能隐患：**
- 长期增量运行会产生大量小文件（每次 APPEND 一批小 Parquet 文件）
- 建议定期执行 SNAPSHOT Build 来合并文件（类似 Delta Lake 的 `OPTIMIZE`）

**`IncrementalTransformInput` 关键 API：**
```python
# 仅获取新增数据
new_data = ctx.inputs['events'].dataframe(type='incremental')

# 获取完整历史数据（强制全量）
all_data = ctx.inputs['events'].dataframe(type='snapshot')
```

---

### 3. 调度与编排

**Build 触发机制：**

Foundry 使用 **Schedule（调度计划）** 驱动 Pipeline 执行：

```
触发方式：
├── 时间触发：每 N 分钟 / 每天 HH:MM / Cron 表达式
├── 事件触发：上游数据集更新后自动触发下游 Build
└── 手动触发：用户/API 手动发起 Build
```

**关键调度规则：**
- 同一 Schedule 如果上一次 Build 仍在运行，新触发的 Build 会**排队等待**（不并发）
- 每个数据集建议只由一个 Schedule 管理（避免多 Schedule 冲突写同一输出）
- DAG 级别的传播：若数据集 A 更新，所有依赖 A 的下游 Transform 按拓扑顺序依次触发

**并发执行：**
- DAG 中无相互依赖的兄弟节点（同层 Transform）**并行执行**
- Foundry 自动计算拓扑排序，无需用户手动指定执行顺序

**错误恢复：**
- Build 失败时输出数据集保持**上次成功的版本**（事务隔离保证）
- 支持手动重试或调度重试策略
- 提供 Build 历史视图，可追溯每次执行的输入版本、耗时、错误信息

---

### 4. 计算资源管理

**资源隔离：**
- 每个 Build 在独立的 Spark Application 中执行（隔离性强）
- 不同 Transform 可配置不同 Compute Profile（差异化资源）
- Spark 动态资源分配（Dynamic Allocation）支持，Executor 按需扩缩

**大作业优化配置参考：**
```python
@transform_df(
    Output('/project/output/large_result'),
    source=Input('/project/input/large_source'),
    profile=ComputeProfile('LARGE'),  # 显式指定计算规格
)
def compute(source):
    return source.repartition(200)  # 手动控制分区数
```

---

### 5. 性能优化机制

**分区策略：**
- 默认 Spark 分区（基于文件数/大小自动推断）
- 支持手动 `repartition()` / `coalesce()`
- Foundry 数据集存储为 Parquet（列存），天然支持谓词下推

**Predicate Pushdown：**
- Spark 读取 Foundry Dataset 时，过滤条件自动下推到 Parquet 文件扫描层
- 分区裁剪（Partition Pruning）减少 I/O

**缓存与物化：**
- 中间 Transform 输出自动持久化（Foundry Dataset），无需手动 `cache()`
- 下游 Transform 读取时直接消费已物化的 Parquet 文件，不重新计算上游

---

## 架构图解

```
用户代码 (@transform_df)
    │
    ▼
transforms.api 装饰器层
    │  - 解析 Input/Output 声明
    │  - 封装 TransformInput/Output 对象
    ▼
Foundry Build Service
    │  - 解析 DAG 拓扑
    │  - 检查 Transaction 类型（增量 or 全量）
    │  - 分配 Compute Profile
    ▼
托管 Spark 集群
    │  - 执行 PySpark 逻辑
    │  - 读取上游 Dataset（Parquet on 对象存储）
    │  - 写入输出 Dataset（新 Transaction）
    ▼
Foundry Dataset（新版本）
    │
    ▼
触发下游 Transform Build（事件传播）
```

---

## 关键结论

1. **Compute Profile 屏蔽集群复杂度**：用户只选规格，Foundry 负责 Spark 集群生命周期，降低数据工程门槛 [事实]
2. **增量计算基于 Transaction 类型**：APPEND → 增量可行；UPDATE/SNAPSHOT → 强制全量重算，这是理解增量 Transform 适用边界的关键 [事实]
3. **`semantic_version` 是逻辑变更的信号机制**：Transform 逻辑变更时必须手动递增，否则旧输出不会重算（数据质量风险） [事实]
4. **小文件问题是增量模式的主要运维负担**：长期 APPEND-only 累积大量 Parquet 小文件，需定期执行 SNAPSHOT Build 合并 [推断]
5. **DAG 同层并行**：无依赖关系的兄弟 Transform 并行执行，Foundry 自动调度，无需手工指定顺序 [事实]

---

## 待深挖问题

- Foundry 托管 Spark 集群的底层基础设施（K8s? YARN? 自研调度器？）
- 增量计算的状态存储位置（Build History Service？独立 KV 存储？）
- 跨 Code Repository 的 Build 触发传播机制（FDS 如何实现跨 Repo 事件通知）
- Dynamic Allocation 的具体配置方式与 Foundry 限制

---

## 参考来源

- Palantir Foundry 文档：Incremental Transforms、Compute Profiles
- 社区调研：@incremental decorator internals、Transaction types
- Spark 官方文档：Structured Streaming、Dynamic Allocation
