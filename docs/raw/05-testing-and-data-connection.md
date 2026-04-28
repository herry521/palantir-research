# Palantir Pipeline 测试框架与数据接入层调研

**调研日期：** 2026-04-17  
**调研方向：** Transform 测试框架 / Data Connection 数据接入层 / 存储格式  
**补充原因：** 原调研遗漏的工程实践关键方向

---

## 一、Transform 单元测试框架

### 1.1 测试工具链

Foundry Python transforms 使用 **pytest** 作为测试框架，配合两个核心测试工具类：

| 工具类 | 包路径 | 作用 |
|---|---|---|
| `TransformRunner` | `transforms.verbs.testing.TransformRunner` | 执行 Transform 函数，注入测试数据 |
| `InMemoryDatastore` | `transforms.verbs.testing.datastores` | 内存数据存储，替代真实 Foundry Dataset |

### 1.2 测试项目结构

```
transforms-python/
└── src/
    ├── myproject/
    │   └── datasets/
    │       └── my_transform.py    # 被测 Transform
    └── test/                      # 测试目录（需在 src/ 下）
        └── test_my_transform.py   # 测试文件（test_ 前缀）
```

测试文件命名规则：
- 文件名：`test_*.py` 前缀
- 函数名：`test_*` 前缀
- 断言：使用 Python 原生 `assert` 语句

### 1.3 典型测试写法

```python
from transforms.api import Input, Output, transform_df, Pipeline
from transforms.verbs.testing.TransformRunner import TransformRunner
from transforms.verbs.testing.datastores import InMemoryDatastore
from pyspark.sql import SparkSession
import pyspark.sql.functions as F

# ---- 被测 Transform（src/myproject/datasets/enrich.py）----
@transform_df(
    Output('/project/output/enriched'),
    events=Input('/project/input/events'),
    config=Input('/project/input/config'),
)
def enrich_events(events, config):
    return events.join(config, 'type_id').withColumn('ts', F.current_timestamp())

# ---- 测试文件（src/test/test_enrich.py）----
def test_enrich_events(spark_session: SparkSession):
    # 1. 准备测试数据
    df_events = spark_session.createDataFrame(
        [(1, 'A'), (2, 'B')], ['id', 'type_id']
    )
    df_config = spark_session.createDataFrame(
        [('A', 'Alpha'), ('B', 'Beta')], ['type_id', 'label']
    )

    # 2. 配置 InMemoryDatastore
    store = InMemoryDatastore()
    store.store_dataframe('/project/input/events', df_events)
    store.store_dataframe('/project/input/config', df_config)

    # 3. 构建 Pipeline 并运行
    pipeline = Pipeline()
    pipeline.add_transforms(enrich_events)
    runner = TransformRunner(pipeline, datastore=store)

    # 4. 执行并断言
    result = runner.build_dataset(spark_session, '/project/output/enriched')
    assert result.count() == 2
    assert set(result.columns) >= {'id', 'type_id', 'label', 'ts'}
```

### 1.4 增量 Transform 测试

`InMemoryDatastore` 同样支持增量 Transform 的测试，可模拟 APPEND 事务：

```python
# 模拟增量：先存第一批，再存第二批，验证只处理新增数据
store.store_dataframe('/input/events', df_batch_1)
runner.build_dataset(spark, '/output/result')  # 第一次 Build

store.store_dataframe('/input/events', df_batch_2, append=True)  # APPEND
runner.build_dataset(spark, '/output/result')  # 第二次 Build（应只处理 batch_2）
```

### 1.5 关键限制

- CI 环境中无法访问真实 Foundry Dataset，**必须使用 InMemoryDatastore 提供测试数据**
- 测试数据应硬编码在 Repository 中或作为 CSV 文件存储，不依赖生产数据
- `build.gradle` 中可配置 `com.palantir.conda.pep8` / `com.palantir.conda.pylint` 启用代码质量检查

---

## 二、Data Connection：数据接入层

### 2.1 定位

Data Connection 是 Pipeline 的**数据入口**，负责将外部数据源接入 Foundry Dataset，是 Pipeline 的上游。

### 2.2 Schema 推断机制

**自动推断：**
- 对 CSV / JSON 等半结构化数据，Foundry 可基于数据子集自动推断 Schema
- Spark 也支持在 Transform 内动态推断 Schema（`inferSchema=True`），但有性能开销

**Schema 推断的注意事项：**
- **静态 Schema 会过时**：源系统 Schema 变更后，已固化的 Schema 需手动更新
- **增量 Pipeline 慎用动态推断**：批次间 Schema 不一致会导致合并失败（列类型不匹配等）
- 推荐：接入时固化 Schema，在 Transform 层做 Schema 演化处理

### 2.3 增量同步策略

Data Connection 支持两种同步模式：

| 模式 | 机制 | 适用场景 |
|---|---|---|
| **全量同步** | 每次全量拉取源数据 | 源系统不支持变更追踪、数据量小 |
| **增量同步** | 维护同步状态，只拉取新增/变更 | 大数据量、频繁更新 |

增量同步原理：
- 第一次运行：全量拉取，记录同步状态（如时间戳、游标）
- 后续运行：只拉取上次同步点之后的数据
- 同步状态存储在 Foundry 内部（用户透明）

### 2.4 Magritte 连接器说明

`magritte-rest-v2` 是早期 REST API 插件，属于**遗留组件，不再主动开发**。官方建议迁移到新版 REST API 数据源类型。通用连接器框架是 Data Connection 应用，支持数据库、文件系统、API 等多种数据源类型。

---

## 三、底层存储格式与参数类型核实

### 3.1 Dataset 存储格式

**核实结论：**
- Foundry Dataset 的主要存储格式是 **Apache Parquet**（列存，默认）
- Dataset 是"文件包装器"：Parquet 文件 + Foundry 元数据（Schema 定义、Transaction 记录、权限信息等）
- 元数据通过 Transaction API（RID + Branch ID）管理，与数据文件分离存储
- 支持非结构化数据（图像、视频、PDF 等）以"Media Set"形式存储（非 Parquet）
- 支持半结构化数据（XML/JSON）通过 Schema 推断后转为 Parquet

**Parquet 选择的意义：**
- 列存压缩，大数据集 I/O 效率高
- 谓词下推（Predicate Pushdown）原生支持
- Spark 原生读写，零适配开销

### 3.2 `semantic_version` 参数类型核实

**核实结论：** `semantic_version` 参数类型为**整数（int）**，默认值为 `1`。

```python
@incremental(
    semantic_version=1,  # int，默认值
    # 修改 Transform 逻辑后改为 2，触发全量重算
)
@transform_df(...)
def compute(...):
    ...
```

触发时机：
- 仅在 Transform 逻辑实质性变更（旧输出数据不再有效）时递增
- 列顺序变更等不影响语义的修改**不需要**递增

### 3.3 Compute Profile 名称核实

官方文档列出的预定义 Compute Profile 描述为 Extra Small / Small / Medium / Large / Extra Large，简写约定（XS/S/M/L/XL）为行业通用表述，不是 Palantir 的官方 API 名称。实际名称可能因版本和环境而异，使用时应以平台界面显示的选项为准。

---

## 关键结论

1. **测试工具链完整但需手工搭建**：`TransformRunner + InMemoryDatastore + pytest` 体系成熟，但没有开箱即得的 Mock 框架，测试数据需开发者自行准备 [事实]
2. **增量 Transform 测试是难点**：需模拟 APPEND 事务的顺序执行，逻辑较批处理测试复杂 [推断]
3. **Data Connection 增量同步与 Transform 增量计算是两个独立的增量机制**：前者解决"数据怎么进 Foundry"，后者解决"进来的数据怎么高效处理"，需配合使用 [推断]
4. **Schema 演化是接入层最常见痛点**：静态 Schema + 源系统变更 = 接入失败，需在 Pipeline 中增加容错处理 [推断]
5. **`semantic_version` 是整数，默认 1**：这个参数设计的本质是"语义版本控制"，强制让开发者在逻辑变更时做出显式声明 [事实]

---

## 参考来源

- Palantir Foundry 文档：Python Unit Tests、TransformRunner、InMemoryDatastore
- Data Connection：Schema Inference、Incremental Sync
- Dataset Storage：Parquet format、Transaction API
- Incremental Transforms：semantic_version 参数文档
