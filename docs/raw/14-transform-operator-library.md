# 14 — Palantir Foundry 算子库深度调研

**日期：** 2026-04-28  
**类型：** 技术调研  
**覆盖方向：** 算子库构成 · 算子生态 · 技术架构

---

## 1. 总览

Palantir Foundry 的算子库（Transform/Operator Library）是整个数据处理体系的核心。它以两种面向不同受众的形态并行提供：

| 形态 | 入口 | 目标用户 | 底层 |
|------|------|---------|------|
| **Pipeline Builder**（可视化算子） | No-code / Low-code UI | 数据分析师、业务人员 | 后端自动生成 Spark/Flink 代码 |
| **Code Repository Transforms**（SDK 算子） | Python / Spark SDK | 数据工程师、开发者 | 直接编写 PySpark / Python |

两种形态共享同一套执行引擎（Spark / Lightweight / Flink），并统一接入 Foundry 的 Lineage、Ontology 和 Branch 管理体系。

---

## 2. 算子库构成

### 2.1 Pipeline Builder 可视化算子分类

Pipeline Builder 将算子分为两大层次：

#### 2.1.1 表达式（Expression）
> 以列为输入，输出单列。可嵌套在 Transform 内使用。

| 表达式 | 功能 |
|--------|------|
| Cast | 数据类型转换 |
| Split | 按分隔符拆分字符串列 |
| Concatenate | 字符串拼接 |
| Arithmetic | 四则运算 |
| Date Functions | 日期提取/格式化 |
| Geometry Buffer | 几何对象缓冲区（GIS） |
| Conditional (CASE) | 条件逻辑 |

#### 2.1.2 变换（Transform）
> 以整张表为输入，输出整张表。

| 算子 | 分类 | 说明 |
|------|------|------|
| **Filter** | 行处理 | 按条件过滤行 |
| **Select Columns** | 列处理 | 选取/重命名/删除列 |
| **Add Column** | 列处理 | 基于表达式新增列 |
| **Rename Columns** | 列处理 | 批量重命名 |
| **Join** | 多表 | Inner/Left/Right/Full Join，支持多键 |
| **Union** | 多表 | 按名称合并 / Union All |
| **Aggregate** | 聚合 | GROUP BY + SUM/COUNT/AVG/MIN/MAX |
| **Pivot** | 聚合 | 行转列 |
| **Unpivot** | 聚合 | 列转行 |
| **Window Functions** | 分析 | 分区内排名、滚动聚合 |
| **Rollup** | 聚合 | 多维度汇总 |
| **Case Transform** | 逻辑 | 多条件分支 |
| **Split (Table)** | 路由 | 按条件将一张表分成多输出 |
| **LLM Transform** | AI | 调用 LLM 对行级数据处理 |
| **Trained Model** | AI/ML | 引入 ML 模型进行批量推理 |
| **Geospatial Join** | GIS | 空间最近邻关联 |
| **Geometry Buffer** | GIS | 空间缓冲区计算 |

> 所有可视化算子在后端均由 Pipeline Builder 的代码生成器翻译为 PySpark / Spark SQL，并提交到执行引擎。

---

### 2.2 Code Repository SDK 算子体系

#### 2.2.1 核心 transforms.api 模块

```python
from transforms.api import (
    transform,           # 通用装饰器：@transform
    transform_df,        # Spark DataFrame 快捷装饰器
    transform_pandas,    # Pandas DataFrame 快捷装饰器
    transform_polars,    # Polars DataFrame 快捷装饰器
    Input,               # 声明输入数据集
    Output,              # 声明输出数据集
    incremental,         # 增量处理装饰器
    configure,           # Spark 资源配置装饰器
    Param,               # 参数基类
    BooleanParam,        # 布尔参数
    IntegerParam,        # 整型参数
    StringParam,         # 字符串参数（支持枚举约束）
    FloatParam,          # 浮点参数
)
```

#### 2.2.2 扩展算子库（可选依赖包）

| 包名 | 功能 | 核心 API |
|------|------|---------|
| `transforms-media` | 非结构化媒体处理 | OCR、图片缩放、音频转录、视频分帧、DICOM |
| `transforms-expectations` | 数据质量断言 | Schema 校验、列级断言、Pipeline 失败拦截 |
| `palantir_models.transforms` | AI/ML 模型推理 | `OpenAiGptChatLanguageModelInput` 等模型接入 |
| `geospatial-tools`（legacy） | GIS 空间分析 | 空间 Join、Buffer（已被 Pipeline Builder GIS 算子替代） |

---

## 3. 算子生态

### 3.1 三类 Pipeline 对应的算子能力集

```
┌─────────────────────────────────────────────────────────────┐
│                    Foundry Pipeline 类型                     │
├─────────────────┬───────────────────┬───────────────────────┤
│  Batch Pipeline │Incremental Pipeline│  Streaming Pipeline   │
│  全量重算每次    │ 仅处理新增/变更数据 │  持续处理实时数据      │
│  低复杂度        │ 低延迟·高弹性      │  超低延迟·高复杂度    │
│  Spark/Light    │ @incremental API  │  Flink Engine         │
└─────────────────┴───────────────────┴───────────────────────┘
```

### 3.2 增量算子（Incremental Transform）机制

增量处理是 Foundry 算子生态中最重要的差异化能力之一：

```python
from transforms.api import transform, Input, Output, incremental

@incremental(snapshot_inputs=["reference_table"])
@transform(
    output=Output("/data/output"),
    new_data=Input("/data/source"),
    reference_table=Input("/data/reference"),
)
def compute(new_data, reference_table, output):
    # new_data: 仅读取上次构建后新增的事务（增量读）
    # reference_table: 始终全量读取（snapshot_inputs 指定）
    # output: 支持 append / modify / replace 三种写入模式
    df = new_data.dataframe()
    output.set_mode("append")
    output.write_dataframe(df)
```

**写入模式对比：**

| 模式 | 行为 | 适用场景 |
|------|------|---------|
| `append` | 追加新行，不修改历史 | 日志类、事件流 |
| `modify` | 按主键 upsert | CDC、维度表更新 |
| `replace` | 全量覆盖 | 小维表、每次重算 |

**增量安全保障：**
- Foundry 追踪每个数据集的事务类型（APPEND / UPDATE / SNAPSHOT）
- `require_incremental=True` 强制校验，非增量时直接失败，防止生产误全量
- `v2_semantics=True` 推荐所有新代码启用

### 3.3 AI/ML 算子生态

```
┌──────────────────────────────────────────────────┐
│               AIP × Transform 集成                │
├──────────────────────────────────────────────────┤
│  Pipeline Builder                                 │
│    └── LLM Transform Node（可视化 LLM 调用节点）  │
│    └── Trained Model Node（批量 ML 推理节点）     │
├──────────────────────────────────────────────────┤
│  Code Repository                                  │
│    └── palantir_models.transforms                 │
│         ├── OpenAiGptChatLanguageModelInput       │
│         ├── 自定义容器模型（containerized model） │
│         └── AIP Model Catalog 集成               │
├──────────────────────────────────────────────────┤
│  AIP Logic（No-code LLM Function 编排）           │
│    └── 读写 Ontology 对象，LLM 驱动行级处理       │
└──────────────────────────────────────────────────┘
```

### 3.4 GIS 地理空间算子生态

| 算子/API | 提供方式 | 能力 |
|---------|---------|------|
| Geometry Buffer | Pipeline Builder Expression | 正/负缓冲区（支持自定义坐标系） |
| Geometry Nearest Neighbors Join | Pipeline Builder Transform | 空间最近邻 Join |
| Geometries Have Intersection | Pipeline Builder Filter | 空间相交过滤 |
| `geospatial-tools` (Python) | Code Repository 包 | 遗留 GIS 函数库，已进入维护模式 |

---

## 4. 技术架构

### 4.1 执行引擎分层

```
┌─────────────────────────────────────────────────────────┐
│                   Transform 调度层                       │
│         Foundry Scheduler（事务跟踪 · 依赖图 · 触发）    │
└────────────────────────┬────────────────────────────────┘
                         │ 按 Transform 类型路由
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
┌──────────────┐ ┌──────────────┐ ┌───────────────┐
│ Spark Engine │ │  Lightweight  │ │ Flink Engine  │
│ (分布式)     │ │  Single Node  │ │  (流式)       │
│ PySpark/SQL  │ │ DuckDB/Polars │ │  Streaming    │
│ Spark Profile│ │ Pandas        │ │  Pipeline     │
└──────┬───────┘ └──────────────┘ └───────────────┘
       │
       ├── Sidecar Container（自定义 Docker 容器与 Executor 并行运行）
       └── Custom JARs（平台管理员审核后注入）
```

### 4.2 Lightweight Transform 架构

**设计目标：** 针对中小数据集，跳过 Spark 启动开销，单节点高性能执行。

| 特性 | 说明 |
|------|------|
| 执行位置 | 单节点，无 Spark |
| 支持引擎 | DuckDB（SQL 优先）、Polars（DataFrame 优先）、Pandas |
| 适用规模 | 中小数据集（GB 级以内） |
| 成本 | 比 Spark Transform 低 3-5x |
| API 限制 | 支持 transforms.api 子集，不支持 SparkContext 直接操作 |
| 触发方式 | `@transform.using()` 装饰器声明为 lightweight |

**DuckDB vs Polars 选择建议：**

| 场景 | 推荐引擎 |
|------|---------|
| SQL 风格查询、on-disk 大文件 | DuckDB |
| 复杂多步 Python 逻辑 | Polars（Lazy/Streaming 模式） |
| 快速原型 / 兼容性优先 | Pandas |

### 4.3 Container Transform 架构

**两种容器化模式：**

```
模式一：Container Transform（完全替代 Spark）
  ┌─────────────────────────────────────┐
  │  用户 Docker 镜像                    │
  │  任意语言/依赖 + Foundry I/O SDK     │
  │  通过共享 Volume 与 Foundry 通信      │
  └─────────────────────────────────────┘

模式二：Spark Sidecar Transform（与 Spark 协同）
  ┌────────────────┐    ┌─────────────────────┐
  │  PySpark 主体  │◄──►│  Sidecar 容器        │
  │  @sidecar 装饰 │    │  每个 Executor 一个   │
  │                │    │  共享 Volume 通信     │
  └────────────────┘    └─────────────────────┘
  → 随数据规模线性扩展（Sidecar 与 Executor 1:1）
```

**Docker 镜像要求：**
- 平台：`linux/amd64`
- 运行用户：非 root，UID `5001`
- Tag：digest 或非 `latest`
- 端口范围：1024–65535
- 必须有 `/bin/sh`

### 4.4 Pipeline Builder 代码生成架构

```
用户可视化操作
    │
    ▼
Pipeline Builder Frontend（DAG 图 + 表单配置）
    │
    ▼
后端代码生成器
    ├── Schema 推导 & 完整性检查（build 前预校验）
    ├── 类型安全校验（强类型，不等到 build 才报错）
    ├── 生成 PySpark / Spark SQL Transform 代码
    └── 写入 Code Repository（可 export-to-code）
    │
    ▼
Foundry 调度器（与手写 Transform 统一调度）
    │
    ▼
Spark / Flink 执行引擎
```

**关键能力：**
- Join 键建议 & 列类型 cast 建议（智能提示）
- 严格输出检查，防止上游 schema 变更静默打破下游
- 支持 Export to Code（可视化 → 代码，便于迁移高级逻辑）

### 4.5 参数化算子（Param）机制

Transform 支持外部参数注入，实现运行时动态配置：

```python
from transforms.api import transform, Output, StringParam, IntegerParam

@transform(
    output=Output("/data/result"),
    env=StringParam(default="prod", allowed_values=["dev", "staging", "prod"]),
    limit=IntegerParam(default=1000),
)
def compute(output, env, limit):
    # env 和 limit 可在 Foundry UI 或 Schedule 配置中覆盖
    ...
```

| 参数类型 | 约束支持 | 典型用途 |
|---------|---------|---------|
| `StringParam` | `allowed_values` 枚举 | 环境选择、模式切换 |
| `IntegerParam` | `default` | 数量限制、批次大小 |
| `BooleanParam` | `default` | Feature flag |
| `FloatParam` | `default` | 阈值、比例系数 |

---

## 5. 算子库全景图

```
Palantir Foundry 算子库全景
─────────────────────────────────────────────────────────────

 ┌─────────────────────────────────────────────────────────┐
 │                   Pipeline Builder                       │
 │   (No-code 可视化算子，后端生成 Spark 代码)               │
 │                                                         │
 │  行列处理    多表操作    聚合分析    AI/ML      GIS       │
 │  Filter     Join       Aggregate  LLM Trans  Geo Join   │
 │  Select     Union      Pivot      ML Model   Geo Buffer │
 │  AddColumn  Split      Window     AIP Logic  Intersect  │
 │  Rename     Unpivot    Rollup                           │
 │  Case                                                   │
 └─────────────────────────────────────────────────────────┘

 ┌─────────────────────────────────────────────────────────┐
 │                 Code Repository SDK                      │
 │   (Pro-code Python 算子，直接操控引擎)                    │
 │                                                         │
 │  transforms.api         扩展库                           │
 │  ├── @transform         transforms-media                 │
 │  ├── @transform_df      transforms-expectations          │
 │  ├── @transform_pandas  palantir_models.transforms       │
 │  ├── @transform_polars  geospatial-tools (legacy)        │
 │  ├── @incremental                                       │
 │  ├── Input / Output     Param 参数化                     │
 │  └── @configure         BooleanParam / IntegerParam /   │
 │                         StringParam / FloatParam         │
 └─────────────────────────────────────────────────────────┘

 ┌─────────────────────────────────────────────────────────┐
 │                    执行引擎层                             │
 │                                                         │
 │  Spark（分布式）  Lightweight（单节点）  Flink（流式）    │
 │  PySpark/SQL      DuckDB / Polars        Streaming       │
 │  Sidecar容器      Pandas                                 │
 │  Custom JARs                                            │
 └─────────────────────────────────────────────────────────┘
```

---

## 6. 关键结论

1. **算子双轨制**：可视化算子（Pipeline Builder）与代码算子（Code Repository）共享执行引擎，前者自动生成后者代码，可 export-to-code 无缝迁移。

2. **轻量执行是重要趋势**：Lightweight Transform（DuckDB/Polars）针对中小数据集比 Spark 快 3–5x，成本更低，Palantir 持续投入该方向。

3. **增量算子是核心差异点**：`@incremental` 装饰器结合事务跟踪，提供了细粒度的增量处理语义（append/modify/replace），这是 Foundry 相比普通 Spark 框架的关键竞争力。

4. **容器化扩展机制**：Sidecar Container 允许任意语言/依赖与 Spark 协同，1:1 随 Executor 扩展；Container Transform 则完全替代 Spark，适合非 JVM 生态（如 R、Rust、C++）。

5. **AI 算子原生集成**：LLM Transform 和 Trained Model 算子已内置于 Pipeline Builder，AI/ML 推理被视为一等公民算子，而非外挂插件。

6. **GIS 算子向可视化迁移**：`geospatial-tools` Python 库进入维护模式，空间算子能力统一迁移至 Pipeline Builder GIS 算子，降低使用门槛。

7. **参数化算子**：`Param` 系列支持运行时参数注入，实现算子逻辑的动态配置，是构建可复用 Pipeline 模板的基础机制。

---

## 7. 参考

- `docs/raw/01-pipeline-expression-dsl.md` — Pipeline DSL 基础
- `docs/raw/02-execution-engine-spark.md` — Spark 执行引擎
- `docs/raw/03-streaming-batch-architecture.md` — 流批架构
- Palantir Foundry 官方文档：transforms.api / Pipeline Builder / AIP
