# Palantir Pipeline 表达层 DSL 调研

**调研日期：** 2026-04-16  
**调研方向：** Pipeline 表达层 / Transform 抽象 / DAG 构建

---

## 核心发现

### 1. Transform 装饰器体系

Foundry 提供三种核心 Transform 装饰器，对应不同的编程范式：

| 装饰器 | 输入类型 | 输出约束 | 适用场景 |
|---|---|---|---|
| `@transform` | `TransformInput` 对象 | 多输出支持 | 复杂逻辑、多输出 |
| `@transform_df` | PySpark `DataFrame` | 单输出 | 标准 Spark 转换 |
| `@transform_pandas` | Pandas `DataFrame` | 单输出 | 中小数据集 |

**`@transform_df` 详解（最常用）：**
- 装饰器直接注入 PySpark DataFrame，无需手动调用 `.dataframe()`
- 函数参数名必须与装饰器中 `Input()` 的关键字名称一致
- 返回值自动写入 `Output()` 指定的数据集路径

**代码示例：**
```python
from transforms.api import transform_df, Input, Output
from pyspark.sql import DataFrame
import pyspark.sql.functions as F

@transform_df(
    Output('/project/output/processed_data'),
    raw=Input('/project/input/raw_data'),
    config=Input('/project/input/config_table'),
)
def compute(raw: DataFrame, config: DataFrame) -> DataFrame:
    # 标准 PySpark 逻辑
    return raw.join(config, 'id').withColumn('ts', F.current_timestamp())
```

**`@transform` 低级接口（多输出场景）：**
```python
from transforms.api import transform, Input, Output

@transform(
    output_a=Output('/project/output/a'),
    output_b=Output('/project/output/b'),
    source=Input('/project/input/source'),
)
def compute(source, output_a, output_b):
    df = source.dataframe()  # 需手动获取 DataFrame
    output_a.write_dataframe(df.filter('status = "active"'))
    output_b.write_dataframe(df.filter('status = "inactive"'))
```

---

### 2. DAG 构建原理

**依赖推导机制：**
- Foundry 通过扫描 `pipeline.py` 中注册的所有 Transform 对象，静态分析每个 Transform 的 `Input()` / `Output()` 路径
- 将数据集路径作为节点，Transform 作为边，构建全局 DAG
- Foundry 使用平台级依赖管理（官方称 **Automation dependencies**）作为中心化注册中心，跨 Code Repository 统一管理（注：部分资料中出现的"FDS/Foundry Dependency Services"为非官方术语）

**`pipeline.py` 的作用：**
```python
# transforms-python/src/myproject/pipeline.py
from transforms.api import Pipeline
from myproject.datasets import examples

my_pipeline = Pipeline()
my_pipeline.discover_transforms()  # 自动扫描注册所有 @transform 装饰的函数
```

**循环依赖检测：** DAG 是有向无环图，Foundry 在 Build 阶段校验，发现循环依赖时拒绝执行并报错。

---

### 3. Code Repository 项目结构

```
transforms-python/
├── conda_recipe/
│   └── meta.yaml          # conda 包元数据（Python 依赖声明）
├── src/
│   └── myproject/
│       ├── __init__.py
│       ├── pipeline.py    # Pipeline 注册入口（核心）
│       └── datasets/
│           ├── __init__.py
│           └── examples.py  # Transform 函数定义
├── setup.cfg              # Python 包配置
├── setup.py
└── build.gradle           # 构建自动化（JVM 依赖、Spark NLP JAR 等）
```

**关键配置文件：**
- `build.gradle`：用于添加 JVM 依赖（如 Spark NLP），配置 `transformsPython { sharedChannels "libs" }` 引入共享库
- `conda_recipe/meta.yaml`：声明 Python 包依赖（等价于 `requirements.txt` 但用于 conda 环境）
- `setup.cfg`：标准 Python 包配置

**开发流程：**
1. **Preview Build**：在 Foundry IDE 中预览少量数据，快速验证逻辑（不写入正式输出）
2. **Full Build**：触发完整计算，结果写入输出数据集
3. 支持 VS Code 本地开发（Palantir VS Code 扩展），可本地 Preview 完整数据集

---

### 4. SQL Transform

Foundry 支持在 Code Repository 中使用 Spark SQL：

```python
from transforms.api import transform, Input, Output

@transform(
    output=Output('/project/output/result'),
    source=Input('/project/input/events'),
)
def compute(source, output):
    source.dataframe().createOrReplaceTempView('events')
    result = source.spark_session().sql("""
        SELECT user_id, COUNT(*) as cnt
        FROM events
        WHERE dt >= '2026-01-01'
        GROUP BY user_id
    """)
    output.write_dataframe(result)
```

Pipeline Builder（低代码界面）支持 SQL 表达式，AIP 可通过自然语言生成 SQL，底层编译为 Spark SQL 执行。

---

### 5. 与业界方案对比

| 维度 | Palantir Foundry Transforms | dbt | Apache Beam |
|---|---|---|---|
| 执行引擎 | Spark（托管） | 各数据仓库原生 SQL | Runner 可插拔（Flink/Spark/Dataflow） |
| 编程模型 | Python 装饰器 + DAG | SQL + Jinja 模板 | 统一批流 API |
| 血缘追踪 | 内置，自动捕获 | 内置，基于 SQL 解析 | 需外部集成 |
| 多输出支持 | 支持（`@transform`） | 不支持（1 Model = 1 输出） | 支持 |
| 测试机制 | 内置 Preview / Unit Test | `dbt test` | 需自行集成 |
| 流处理 | Pipeline Builder（Structured Streaming） | 不支持 | 原生支持 |
| 数据集版本 | 内置 Transaction/Branch | 无 | 无 |
| 平台绑定 | 强绑定 Foundry | 数仓无关 | Runner 无关 |

**核心差异：** Foundry Transforms 最大的优势是与 Ontology 的深度集成，Transform 输出可直接成为 Ontology Object Type 的数据源，实现"数据→业务实体"的语义提升。dbt 专注 SQL 转换，无 Ontology 概念。

---

## 关键结论

1. **装饰器即声明**：`@transform_df` 通过装饰器静态声明输入输出，Foundry 运行时基于此构建 DAG，函数本身只关注业务逻辑
2. **`pipeline.py` 是 DAG 注册入口**：所有 Transform 必须通过 Pipeline 对象注册才能被 Foundry 调度系统感知
3. **路径即依赖**：Foundry DAG 以数据集路径为节点，两个 Transform 共享同一路径即建立依赖关系，无需显式声明
4. **平台级依赖管理统一血缘**：Foundry Automation dependencies 机制跨 Repository 统一管理依赖，是平台实现全局血缘图的基础（注："FDS/Foundry Dependency Services"为非官方术语，避免使用）
5. **与 dbt 的本质区别**：Foundry Transforms 是 Spark 原生执行（支持任意 PySpark 代码），dbt 仅处理 SQL；Foundry 的 Ontology 集成是 dbt 没有的核心差异

---

## 待深挖问题

- `pipeline.py` 中 `discover_transforms()` 的扫描范围规则（是否支持跨 Python 包）
- 跨 Code Repository 的 Transform 依赖如何建立（通过共享数据集路径？）
- `@transform_df` vs `@transform` 在增量模式下的行为差异
- Pipeline Builder 生成的代码与手写 Code Repository 的执行路径是否完全一致

---

## 参考来源

- Palantir Foundry 官方文档（transforms.api 模块）
- 社区调研：transform_df/Input/Output 使用模式
- 技术对比：Foundry Transforms vs dbt vs Apache Beam
