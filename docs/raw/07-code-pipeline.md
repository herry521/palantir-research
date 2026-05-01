# Foundry 高码 Pipeline 实现方案（Code-first Transform）

**调研日期：** 2026-05-01  
**关联 Issue：** #3

---

## 概述

Palantir Foundry 提供两条 Pipeline 开发路径：

- **低码 Pipeline Builder**：可视化拖拽，适合数据工程师及业务用户快速构建标准数据管道
- **高码 Code Repository（Code-first Transform）**：Git 托管代码库，Python/PySpark 全能力，适合复杂业务逻辑、ML 特征工程和深度平台集成

两者并非竞争关系，而是互补——Pipeline Builder 可编排整体流程，Code Repository 负责其中的自定义计算节点。

---

## Python Transform API 设计

### 核心装饰器体系

Foundry Python Transforms 提供四个核心装饰器，对应不同编程范式：

| 装饰器 | 输入类型 | 输出类型 | 适用场景 |
|---|---|---|---|
| `@transform` | `TransformInput` 对象 | 多输出支持 | 复杂逻辑、多输出、流式 |
| `@transform_df` | PySpark `DataFrame` | 单 DataFrame 输出 | 标准 Spark 批处理 |
| `@transform_pandas` | Pandas `DataFrame` | 单 DataFrame 输出 | 内存级中小数据集 |
| `@transform_polars` | Polars `DataFrame` | 单 DataFrame 输出 | 高性能列式计算 |

[事实] 以上装饰器均来自 `transforms.api` 模块，官方文档有明确说明。[ref](https://www.palantir.com/docs/foundry/transforms-python/overview/)

### @transform_df 示例（最常用）

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
    return raw.join(config, 'id').withColumn('ts', F.current_timestamp())
```

### @transform 低级接口（多输出场景）

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

### 辅助装饰器

- **`@configure`**：修改 Spark 执行配置，包括 profile 选择、运行超时、计算后端切换（Spark 集群 vs 单节点）[事实]
- **`@incremental`**：启用增量构建，仅处理新增/变更数据 [事实]
- **`@transform.using`**：轻量级单节点 Transform（无 Spark），适合小数据量场景，成本更低 [事实]

---

## @transform 装饰器语义

### 声明式依赖注入模型

`@transform_df` 与 `@transform` 本质是**声明式依赖注入**：

1. 装饰器参数（`Input()` / `Output()`）在 **静态分析阶段** 声明数据依赖
2. Foundry 调度系统扫描所有已注册 Transform，提取 Input/Output 路径，构建全局 DAG
3. 执行阶段由 Foundry 运行时负责**注入**实际的 DataFrame 对象，函数本身无需感知数据集路径

[事实] 这是 Foundry 区别于命令式 ETL 框架（如 Airflow Python Operator）的核心设计哲学。

**对比：命令式 vs 声明式**

```python
# 命令式（Airflow 风格）：手动读写，逻辑与 IO 耦合
def process():
    df = read_from_storage('/path/to/input')
    result = transform(df)
    write_to_storage(result, '/path/to/output')

# 声明式（Foundry 风格）：IO 由平台注入，函数只关注逻辑
@transform_df(Output('/path/to/output'), src=Input('/path/to/input'))
def process(src: DataFrame) -> DataFrame:
    return transform(src)
```

### 增量构建语义（@incremental）

`@incremental` 在 `@transform_df` 之上叠加增量处理能力：

- 默认读模式：`append`（仅读取自上次 build 后新增的行）
- `snapshot_inputs`：声明某个输入是快照语义（全量覆写），告知 Foundry 允许增量处理
- `semantic_version`：Transform 逻辑发生不兼容变更时手动递增，触发全量重算
- `require_incremental=True`：强制要求增量执行，非增量时直接失败（用于严格资源控制）

[事实] 以上参数均为官方文档明确说明的 `@incremental` 装饰器参数。

---

## 与 Ontology 集成

### 集成路径

高码 Transform 与 Ontology 的集成是 **间接路径**：

```
Python Transform
      ↓ 写入
  Output Dataset（数据集）
      ↓ 配置为
  Object Type Backing Dataset（Ontology 对象类型的底层数据源）
      ↓
  Ontology Object Type（业务实体）
```

[推断] Python Transform 本身不直接创建 Object Type，而是通过生产 Ontology-ready 的数据集（字段名、类型符合 Object Type schema）间接集成。

### 配置方式

- **Ontology Outputs**：在 Pipeline Builder 或 Ontology Manager 中将 Transform 的输出数据集配置为某个 Object Type 的 Backing Dataset [事实]
- **MediaSet 集成**：Transform 可生成 `mediaReference` 列，与 MediaSet 结合，支持 Object Type 带附件 [推断]
- **实时性**：数据集 Build 完成后，Ontology 自动读取最新版本，无需额外同步步骤 [推断]

### 典型场景

```python
# 生产 Ontology-ready 数据集（字段名与 Object Type schema 一致）
@transform_df(
    Output('/ontology/backing/employee'),
    src=Input('/raw/hr_data'),
)
def compute(src: DataFrame) -> DataFrame:
    return src.select(
        F.col('emp_id').alias('employeeId'),      # Object Type primary key
        F.col('name').alias('displayName'),
        F.col('dept').alias('department'),
    )
```

[推断] 实际字段映射规则由 Ontology Manager 中的 Object Type schema 定义决定，Python 代码只需输出结构一致的数据集。

---

## 与低码 Pipeline Builder 的边界

### 选用 Pipeline Builder 的场景

- 标准 ETL：解析 XML/JSON/PDF、JOIN/Union、字段重命名、类型转换 [事实]
- 用户群体为非工程师，需可视化协作 [事实]
- 需要内置安全检查（行列级权限）和健康检查（数据质量）[事实]
- 快速原型验证，无需写代码 [事实]

### 必须用高码 Code Repository 的场景

| 场景 | 原因 |
|---|---|
| 调用外部 API / HTTP 请求 | Pipeline Builder 无此能力 |
| 使用自定义 Python 库（如 scikit-learn、networkx）| Pipeline Builder 不支持第三方库 |
| 复杂统计/ML 特征工程 | PySpark 全能力 |
| 性能敏感的大规模批处理 | 精细控制 Spark 配置 |
| 需要增量构建优化 | `@incremental` 装饰器 |
| 多输出 / 副输出逻辑 | `@transform` 低级接口 |
| 单元测试与 CI 验证 | 代码库天然支持 pytest |

[事实] 以上来自官方对 Pipeline Builder 和 Code Repository 能力边界的描述。[ref](https://www.palantir.com/docs/foundry/pipeline-builder/overview/)

### 互补使用模式

Pipeline Builder 可将 Code Repository Transform 的输出作为输入节点，实现混合编排：

```
[外部数据源] → [Pipeline Builder: 清洗/JOIN] → [Code Repository: 复杂计算] → [Pipeline Builder: 输出路由]
```

[推断] 这是社区实践中常见的最佳模式，并非 Foundry 强制要求的架构。

---

## 测试体系

### 三层测试架构

```
本地单元测试（pytest + InMemoryDatastore）
         ↓ 通过
CI 检查（Code Repository 内置 checks，build.gradle 配置）
         ↓ 通过
Foundry Preview Build（沙箱执行，少量真实数据）
         ↓ 通过
Full Build（生产数据，全量计算）
```

[推断] 分层结构来自官方文档对开发流程的描述，具体 CI 集成细节基于 `build.gradle` pytest 插件机制推断。

### 本地单元测试

Foundry 提供 `TransformRunner` 和 `InMemoryDatastore` 两个测试工具类：

```python
# tests/test_my_transform.py
import pytest
from transforms.testing import TransformRunner, InMemoryDatastore
from myproject.datasets.examples import my_transform

def test_my_transform(spark_session):
    # 1. 准备 mock 输入数据
    input_df = spark_session.createDataFrame([
        ('user_1', 'active'),
        ('user_2', 'inactive'),
    ], ['user_id', 'status'])

    # 2. 配置内存数据存储
    datastore = InMemoryDatastore({
        '/project/input/raw_data': input_df,
    })

    # 3. 执行 Transform
    runner = TransformRunner(my_transform, datastore)
    output_df = runner.build_dataset('/project/output/result')

    # 4. 断言
    assert output_df.filter('status = "active"').count() == 1
```

[事实] `TransformRunner` 和 `InMemoryDatastore` 是官方测试工具。[ref](https://www.palantir.com/docs/foundry/transforms-python/unit-tests/)

### 注意事项

- 流式 Pipeline（Structured Streaming）**不支持**本地单元测试 [事实]
- 测试文件需放在 `src/` 下的 `test` 子包，文件名以 `test_` 开头 [事实]
- `build.gradle` 中需确认 pytest 插件已启用（部分模板中默认注释掉）[事实]
- Palantir VS Code 扩展支持本地 Preview，可直接在本地编辑器预览真实数据 [事实]

---

## Code Repository 与版本管理

### Git-backed 代码库结构

Code Repository 底层是标准 Git 仓库，Foundry 在其上封装了 Web IDE 和构建系统：

```
transforms-python/
├── conda_recipe/
│   └── meta.yaml          # Python 依赖声明（conda 格式）
├── src/
│   └── myproject/
│       ├── __init__.py
│       ├── pipeline.py    # Pipeline 注册入口
│       └── datasets/
│           └── examples.py
├── build.gradle           # JVM 依赖、pytest 配置、构建自动化
├── setup.cfg
└── setup.py
```

### 版本控制机制

- **标准 Git 操作**：branch、commit、tag、PR/Code Review 均通过 Foundry Web IDE 或 VS Code 扩展操作 [事实]
- **分支策略**：与 Pipeline Builder 分支同步，支持"main 生产分支 + feature 迭代分支"模式 [事实]
- **代码评审**：内置 PR 审批流，支持可配置的审批人权限 [事实]
- **数据集版本协同（Co-versioning）**：代码变更触发 Build 时，输出数据集生成新的不可变 Transaction 版本，代码版本与数据版本天然绑定 [事实]

### 函数与包版本

- Code Repository 中的共享库可通过 Semantic Versioning（X.Y.Z）发布 [事实]
- 其他 Repository 可通过 `build.gradle` 的 `sharedChannels` 引用特定版本的共享库 [事实]
- `@incremental` 的 `semantic_version` 参数用于标记 Transform 逻辑的不兼容变更版本 [事实]

### 发布管理

Foundry 支持结构化的 Release 流程：定义 Product Release，跨多个 Repository 统一管理分支与发布节奏，实现"快速迭代"与"稳定变更管控"的平衡。[推断] 具体机制未见公开文档详细说明，基于官方博客推断。

---

## 依赖图声明

### 路径即依赖（隐式 DAG）

Foundry DAG 的核心设计：**数据集路径是依赖关系的唯一声明方式**，无需显式 depends_on。

```python
# Transform A：生产 /project/intermediate
@transform_df(Output('/project/intermediate'), src=Input('/project/raw'))
def step_a(src): ...

# Transform B：消费 /project/intermediate → 自动成为 A 的下游
@transform_df(Output('/project/final'), mid=Input('/project/intermediate'))
def step_b(mid): ...
```

Foundry 扫描所有 Transform 后，自动推导出：`/project/raw → step_a → /project/intermediate → step_b → /project/final`

[事实] 这是 Foundry DAG 构建机制的核心，官方文档明确描述。

### pipeline.py 注册入口

```python
# transforms-python/src/myproject/pipeline.py
from transforms.api import Pipeline
from myproject.datasets import examples  # noqa: F401（触发模块加载）

my_pipeline = Pipeline()
my_pipeline.discover_transforms()  # 扫描当前包下所有 @transform 装饰的函数
```

[事实] `discover_transforms()` 是 Foundry 识别 Transform 的入口，必须存在。

### 跨 Repository 依赖

跨 Repository 依赖通过**共享数据集路径**隐式建立：

- Repository A 的 Transform 输出 `/shared/dataset_x`
- Repository B 的 Transform 以 `Input('/shared/dataset_x')` 消费
- Foundry Automation Dependencies 机制感知跨 Repository 的路径依赖，统一构建全局血缘图

[推断] 跨 Repository 依赖的具体触发调度机制（是否实时感知、延迟策略等）未见公开细节。

### 循环依赖检测

DAG 为有向无环图，Foundry 在 Build 阶段静态校验，发现循环依赖时拒绝执行并报错。[事实]

---

## 与开源方案对比（dbt / Spark / Flink）

| 维度 | Foundry Code Transform | dbt | 原生 Spark Job | Flink Job |
|---|---|---|---|---|
| **编程模型** | Python 装饰器 + DAG | SQL + Jinja 模板 | PySpark / Scala 全能力 | Java/Python DataStream/Table API |
| **依赖声明** | 路径隐式推导（无需 YAML） | `ref()` 函数 + YAML 显式声明 | 手动调度（Airflow 等） | 手动调度 |
| **执行引擎** | Spark（托管，无需运维） | 数仓原生 SQL 引擎 | 自管 Spark 集群 | 自管 Flink 集群 |
| **流处理** | 有限（Structured Streaming，Pipeline Builder） | 不支持 | 支持 | 原生批流统一 |
| **增量构建** | `@incremental` 装饰器，内置 | 增量模型（dbt incremental） | 手动实现 | 内置（State） |
| **血缘追踪** | 内置，自动捕获，平台级 | 内置，基于 SQL 解析 | 需外部集成（Atlas 等） | 需外部集成 |
| **Ontology 集成** | 原生，Transform 输出直接关联 Object Type | 无概念 | 无概念 | 无概念 |
| **测试体系** | pytest + InMemoryDatastore + Preview | `dbt test` + seed | 自行集成 pytest | 自行集成 |
| **本地开发** | VS Code 扩展 + 本地 Preview | CLI + Profile | 本地 Spark 环境 | 本地 Flink 环境 |
| **平台绑定** | 强绑定 Foundry | 数仓无关 | 开源，无绑定 | 开源，无绑定 |
| **运维负担** | 极低（Foundry 全托管） | 低（数仓负责运维） | 高（自管集群） | 高（自管集群） |
| **多输出** | 支持（`@transform`） | 不支持（1 Model = 1 输出） | 支持 | 支持 |

### 核心差异总结

1. **vs dbt**：Foundry Transform 支持任意 PySpark 代码（不限于 SQL），并拥有 Ontology 集成这一 dbt 没有的核心能力；但 dbt 数仓无关、开源，迁移成本低 [事实]
2. **vs 原生 Spark Job**：Foundry 全托管免运维，内置血缘/版本/测试体系，代价是强平台绑定；自管 Spark 灵活但运维复杂 [推断]
3. **vs Flink**：Foundry 的流处理能力（Structured Streaming）远弱于 Flink，复杂流场景（CEP、乱序处理、精确状态管理）仍需 Flink；Foundry 的优势在批处理和平台集成 [推断]

---

## 总结与可信度说明

### 关键结论

1. **装饰器即声明，路径即依赖**：Foundry Transform 的最大设计特点是通过 `@transform_df` 等装饰器静态声明 IO，由平台自动推导 DAG，函数只关注业务逻辑，与执行环境解耦 [事实]

2. **四级测试体系**：本地 pytest → CI checks → Preview Build → Full Build，其中本地单元测试通过 `TransformRunner` + `InMemoryDatastore` 实现，无需连接 Foundry 环境 [事实]

3. **Ontology 集成是间接路径**：Python Transform 生产符合 Object Type schema 的数据集，再通过 Ontology Manager 配置 Backing Dataset 完成关联，非直接写 Ontology API [推断]

4. **高码 vs 低码边界清晰**：凡需调用外部 API、使用三方 Python 库、ML 计算、精细 Spark 调优的场景必须用高码；标准 ETL、字段转换、JOIN 等用 Pipeline Builder 更高效 [事实]

5. **Git-backed 版本管理**：代码版本与数据集 Transaction 版本协同，是 Foundry "数据即代码"理念的体现；与 dbt 的纯代码版本管理相比，Foundry 多了数据层的不可变性保障 [推断]

6. **与开源方案的核心差异**：Foundry 的竞争优势不在于计算能力（Spark 本身是开源的），而在于全托管运维 + Ontology 语义层 + 内置血缘 + 平台级权限管控的整体集成 [推断]

### 可信度说明

- `[事实]`：来源于 Palantir 官方文档（palantir.com/docs）或官方博客，搜索结果中可验证
- `[推断]`：基于已知事实的合理外推，尚无直接官方文档引用
- `[猜测]`：本文未使用，无无根据猜测

### 待深挖问题

- Java/Scala Transform 的 API 体系（本次调研未获充分资料，需专项搜索）
- `@transform.using` 轻量级 Transform 与 Spark Transform 的切换条件和性能对比
- Ontology Output 配置的具体 UI/API 操作流程
- 跨 Repository 依赖的调度触发延迟机制
- Pipeline Builder 生成的底层代码与手写 Code Repository 的执行路径差异

---

## 参考来源

- [Palantir Foundry Python Transforms 官方文档](https://www.palantir.com/docs/foundry/transforms-python/overview/)
- [Palantir Foundry Pipeline Builder 官方文档](https://www.palantir.com/docs/foundry/pipeline-builder/overview/)
- [Palantir Foundry Unit Tests 官方文档](https://www.palantir.com/docs/foundry/transforms-python/unit-tests/)
- 本项目背景文档：`docs/raw/01-pipeline-expression-dsl.md`
