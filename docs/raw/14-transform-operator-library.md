# 14 — Palantir Foundry 算子库深度调研（全量版）

**日期：** 2026-04-28  
**类型：** 技术调研  
**覆盖方向：** 全量算子穷举 · 算子支撑体系 · 稳定性与扩展性建设 · 官方 vs 自定义边界

---

## 1. 总览

Palantir Foundry 的算子库以"双轨制"面向不同受众：

| 轨道 | 入口 | 受众 | 后端 |
|------|------|------|------|
| **Pipeline Builder 可视化算子** | No-code / Low-code UI | 分析师、业务人员 | 后端自动生成 Spark/Flink 代码 |
| **Code Repository SDK 算子** | Python SDK（transforms.api） | 数据工程师、开发者 | 直接编写 PySpark / Python |

两轨共享同一执行引擎体系，统一接入 Lineage、Ontology、Branch、Data Health 管理。

---

## 2. 全量算子穷举

### 2.1 Pipeline Builder：表达式（Expression）

> 以**列**为处理单元，输出单列，可嵌套在任意 Transform 内使用。

#### 字符串表达式

| 表达式 | 功能描述 |
|--------|---------|
| Concatenate Strings | 多列/字面量拼接，支持自定义分隔符 |
| String Contains | 子串包含判断，支持大小写不敏感 |
| String Length | 返回字符串字符数 |
| Split String | 按分隔符拆分，返回数组或指定索引元素 |
| Format String | printf 风格模板格式化 |
| Trim / LTrim / RTrim | 去除首尾/左侧/右侧空白 |
| Upper / Lower | 大小写转换 |
| Substring | 子串截取（起止索引） |
| Replace | 字符串替换（字面量或正则） |
| Regex Extract | 正则提取第一个匹配组 |
| Regex Match | 正则匹配，返回布尔值 |

#### 数值表达式

| 表达式 | 功能描述 |
|--------|---------|
| Add / Subtract / Multiply / Divide | 四则运算 |
| Absolute Value | 绝对值 |
| Round / Floor / Ceil | 取整系列 |
| Modulo | 取余 |
| Power | 幂运算 |
| Log / Ln | 对数（自然对数/常用对数） |
| Sqrt | 平方根 |
| Convert Distance | 距离单位换算（英里/公里/海里等） |

#### 日期/时间表达式

| 表达式 | 功能描述 |
|--------|---------|
| Extract Date Part | 提取年/月/日/时/分/秒/季度/周数/星期几 |
| Add Value to Date | 日期加减（天/小时/分钟/月/年） |
| Convert String to Date | 字符串→日期，支持自定义格式 |
| Format Date as String | 日期→字符串，ISO8601 默认，支持自定义 |
| Last Day of Week/Month/Quarter/Year | 计算指定单位的最后一天 |
| Date Difference | 两个日期之间的差值（指定单位） |
| Current Timestamp | 获取当前时间戳（构建时） |

#### 布尔/条件表达式

| 表达式 | 功能描述 |
|--------|---------|
| And / Or / Not | 逻辑运算 |
| Is Null / Is Not Null | 空值判断 |
| Case (Inline) | 行级 CASE WHEN 分支，返回单列 |
| Coalesce | 返回首个非空值 |
| If / Else | 简单二分支条件 |

#### 类型转换表达式

| 表达式 | 功能描述 |
|--------|---------|
| Cast | 类型强制转换（string/int/long/double/date/timestamp/boolean） |
| Try Cast | 安全转换，失败返回 null 而非报错 |
| Parse JSON | JSON 字符串→结构体 |
| To JSON String | 结构体→JSON 字符串 |

#### 地理空间表达式

| 表达式 | 功能描述 |
|--------|---------|
| Geometry Buffer | 几何对象外扩/内缩缓冲区（支持指定坐标系） |
| Geometry Distance | 两个几何对象间球面最短距离（重叠时为 0） |
| Geometries Have Intersection | 空间相交判断，返回布尔值 |
| Construct Geo-point | 经纬度列→Geo-point 类型 |
| Parse WKT | Well-Known Text 字符串→Geometry |
| Normalize Geometry | 几何标准化（修复无效几何） |
| H3 Index Operations | H3 六边形索引计算（索引/边界/邻居） |

---

### 2.2 Pipeline Builder：变换（Transform）

> 以**整张表**为输入/输出，是 Pipeline 的基本节点单元。

#### 行过滤与选择

| 变换 | 功能描述 |
|------|---------|
| **Filter** | 按表达式条件过滤行，支持 AND/OR 组合 |
| **Deduplicate** | 按指定列组合去重，保留 first/last/any |
| **Limit** | 截取前 N 行（开发/调试用） |
| **Sample** | 按比例随机采样 |

#### 列操作

| 变换 | 功能描述 |
|------|---------|
| **Select Columns** | 选取指定列，可同时重命名 |
| **Add Column** | 基于表达式新增一列 |
| **Rename Columns** | 批量重命名（支持正则映射） |
| **Drop Columns** | 删除指定列 |
| **Reorder Columns** | 调整列顺序 |
| **Cast Columns** | 批量类型转换 |
| **Explode Array** | 数组列展开为多行 |
| **Flatten Struct** | 嵌套结构体展平为扁平列 |

#### 多表操作

| 变换 | Join 类型/说明 |
|------|--------------|
| **Join** | Inner / Left / Right / Full Outer / Left Semi / Left Anti |
| **Union by Name** | 按列名合并多表（UNION ALL） |
| **Union by Position** | 按列顺序合并（要求列数一致） |
| **Union Files** | 合并文件型数据集（非结构化） |
| **Cross Join** | 笛卡尔积（配合 Filter 实现复杂空间关联） |

#### 聚合与统计

| 变换 | 功能描述 |
|------|---------|
| **Aggregate** | GROUP BY + 多种聚合函数（SUM/COUNT/AVG/MIN/MAX/STDDEV/VARIANCE/FIRST/LAST/COLLECT_LIST） |
| **Pivot** | 行转列，指定行键、列键、值列和聚合函数 |
| **Unpivot** | 列转行（Pivot 的逆操作） |
| **Rollup** | 多层级汇总（生成小计/合计行） |
| **Cube** | 全维度组合聚合 |

#### 分析函数（窗口）

| 变换/函数 | 功能描述 |
|----------|---------|
| **Window Functions** | 统一窗口变换节点，内含以下函数： |
| └ `row_number()` | 分区内唯一顺序编号 |
| └ `rank()` | 分区内排名（有并列时跳号） |
| └ `dense_rank()` | 密集排名（并列不跳号） |
| └ `percent_rank()` | 百分比排名 |
| └ `lag(col, n)` | 向前偏移 n 行取值 |
| └ `lead(col, n)` | 向后偏移 n 行取值 |
| └ `cumulative_sum()` | 累计求和 |
| └ `moving_average(n)` | 滑动平均（窗口大小 n） |
| └ `first_value / last_value` | 窗口首行/末行值 |
| └ `nth_value(n)` | 窗口第 n 行值 |
| └ `sum/avg/min/max` over window | 聚合函数窗口版 |

#### 数据整形

| 变换 | 功能描述 |
|------|---------|
| **Case (Table)** | 表级多分支条件列生成 |
| **Split Dataset** | 按条件将一张表路由到多个输出数据集 |
| **Parse JSON** | JSON 字符串列解析为结构化列 |
| **Parse XML** | XML 列解析 |
| **Parse CSV** | 内嵌 CSV 字符串解析 |
| **Transpose** | 行列互换（小规模数据适用） |

#### 非结构化与媒体

| 变换 | 功能描述 |
|------|---------|
| **Transform Media** | 媒体集处理：OCR 文字提取、图片缩放、PDF→文本、音频转录、DICOM 解析 |
| **Parse PDF** | 抽取 PDF 文档文本/表格结构 |
| **Parse Document** | 通用文档解析（Word/Excel/HTML 等） |

#### AI / ML 算子

| 变换 | 功能描述 |
|------|---------|
| **LLM Transform (Use LLM)** | 按行调用 LLM（配置 prompt + 模型），支持 AIP 管理的所有模型 |
| **Trained Model Node** | 引入 Model Catalog 中的 ML 模型进行批量推理 |
| **Pattern Mining** | 数据模式识别（关联规则、频繁项集） |
| **Embed Text** | 文本→向量 Embedding（对接向量检索） |

#### 地理空间变换

| 变换 | 功能描述 |
|------|---------|
| **Geometry KNN Inner Join** | 空间 K 最近邻 Join（基于球面距离，整个邻居集须能装入内存，3GB executor ≈ 100 万点） |
| **Geo Distance Inner Join** | 按球面距离 Join（两点间距离 ≤ 阈值） |
| **Geometry Nearest Neighbor** | 单对多的最近邻匹配 |
| **Load Shapefile / GeoJSON** | 从文件加载矢量地理数据 |
| **Project Coordinate System** | 坐标系投影转换（WGS84、UTM 等） |
| **H3 Index Join** | 基于 H3 六边形索引的空间 Join |

#### 输出与导出

| 变换 | 功能描述 |
|------|---------|
| **Write to Ontology** | 将数据集变更同步写入 Ontology 对象（Object Type） |
| **Sync to External** | 导出至外部系统（S3/数据库/API） |
| **Stream Output** | 写入 Foundry Stream（供下游流式消费） |

---

### 2.3 Code Repository SDK：transforms.api 全量 API

#### 核心装饰器

| 装饰器 | 用途 | 执行引擎 |
|--------|------|---------|
| `@transform` | 通用 Transform，完整控制 I/O 和执行 | Spark / Lightweight |
| `@transform_df` | PySpark DataFrame 快捷模式 | Spark |
| `@transform_pandas` | Pandas DataFrame 模式 | Lightweight（单节点） |
| `@transform_polars` | Polars DataFrame 模式（`@lightweight` 的封装） | Lightweight（单节点） |
| `@incremental` | 增量处理装饰器，叠加在其他装饰器之上 | Spark / Lightweight |
| `@configure` | Spark 资源配置（profiles/timeout/retries） | Spark |
| `@transform.using()` | 声明 Lightweight 模式（替代 `@lightweight`） | Lightweight |
| `@sidecar` | 声明 Spark Sidecar 容器（与 Executor 协同） | Spark + 容器 |

#### 核心类

| 类 | 功能描述 |
|----|---------|
| `Input(dataset_path)` | 声明输入数据集，支持 `branch`、`stop_propagating_exceptions` 参数 |
| `Output(dataset_path)` | 声明输出数据集，支持 `incremental` 模式 |
| `TransformInput` | 运行时输入对象，方法：`dataframe()` / `pandas()` / `polars()` / `filesystem()` |
| `TransformOutput` | 运行时输出对象，方法：`write_dataframe()` / `set_mode()` / `filesystem()` |
| `IncrementalTransformOutput` | 增量输出对象，额外支持 `set_mode("append"/"modify"/"replace")` |
| `TransformContext` | 可选上下文注入，提供 `spark_session` / `parameters` / `auth_header` |
| `FileSystem` | 原始文件 I/O（非结构化数据），提供 `ls()` / `open()` / `put()` 等文件系统接口 |
| `ContainerTransform` | 声明容器化 Transform（BYOC 模式） |
| `ContainerTransformsConfiguration` | 容器 Transform 配置（镜像、资源、卷映射） |

#### 参数类（Param 体系）

| 类 | 类型约束 | 支持约束项 |
|----|---------|-----------|
| `StringParam` | 字符串 | `default` / `allowed_values`（枚举） |
| `IntegerParam` | 整型 | `default` / `min` / `max` |
| `FloatParam` | 浮点 | `default` / `min` / `max` |
| `BooleanParam` | 布尔 | `default` |
| `DateParam` | 日期 | `default` |
| `ListParam` | 列表 | `element_type` / `default` |

#### 扩展 SDK 包

| 包 | 提供算子/API | 典型使用场景 |
|----|------------|------------|
| `transforms-media` | `MediaSetInput` / `MediaSetOutput` / OCR / Resize / Transcribe / DICOM | 非结构化媒体 ETL |
| `transforms-expectations` | `column_not_null` / `primary_key` / `numeric_range` / `schema_subset` / `schema_exact` / `column_unique` | Pipeline 数据质量门禁 |
| `palantir_models.transforms` | `ModelInput` / `ModelOutput` / `OpenAiGptChatLanguageModelInput` | AI/ML 推理集成 |
| `foundry-dev-tools` | 本地 Transform 调试工具链 | 本地开发测试 |

---

## 3. 算子支撑体系

算子能够稳定运行依赖一套完整的支撑基础设施，涵盖执行、调度、数据质量、可观测性四层。

### 3.1 执行引擎支撑层

```
┌───────────────────────────────────────────────────────────────┐
│                    算子调度与路由                               │
│         Foundry Scheduler（依赖图解析 · 事务跟踪 · 触发机制）   │
└────────────────────────┬──────────────────────────────────────┘
                         │ 按 Transform 元数据路由到对应引擎
         ┌───────────────┼────────────────┐
         ▼               ▼                ▼
┌──────────────┐  ┌───────────────┐  ┌──────────────┐
│ Spark Engine │  │  Lightweight   │  │ Flink Engine │
│  分布式集群  │  │   单节点高性能 │  │  持续流处理  │
│  PySpark     │  │  DuckDB/Polars │  │  Streaming   │
│  SparkSQL    │  │  Pandas        │  │  Pipeline    │
│  Sidecar容器 │  │               │  │              │
└──────┬───────┘  └───────────────┘  └──────────────┘
       │
       ├── Spark Profile（CPU/Memory 资源配置文件）
       ├── Sidecar Container（linux/amd64, UID 5001, 端口 1024-65535）
       └── Custom JARs（平台管理员审核注入）
```

**Spark Profile 参数体系：**

| 参数 | 说明 |
|------|------|
| `spark.driver.cores` | Driver CPU 核数 |
| `spark.driver.memory` | Driver 内存 |
| `spark.executor.cores` | 每 Executor CPU 核数 |
| `spark.executor.memory` | 每 Executor 内存 |
| `spark.executor.memoryOverhead` | 堆外内存（JVM overhead） |
| `spark.executor.instances` | Executor 数量（静态分配） |
| `spark.dynamicAllocation.*` | 动态分配配置 |

### 3.2 依赖与包管理支撑

Code Repository 使用 Conda 作为包管理器，结构如下：

```
myproject/
├── conda_recipe/
│   └── meta.yaml          # Conda 包定义：依赖、版本约束
├── src/
│   └── myproject/
│       ├── __init__.py
│       ├── pipeline.py    # Foundry 自动发现 Transform 的入口
│       └── datasets/      # Transform 实现模块
├── setup.cfg
└── setup.py
```

依赖版本管理三种策略：

| 策略 | 机制 | 适用场景 |
|------|------|---------|
| **自动升级** | Transforms 库后台静默升级（安全/性能 patch） | 无特殊依赖约束 |
| **Module Pinning** | 固定 Spark 版本，防止自动升级打破兼容性 | 生产环境稳定性优先 |
| **Adjudication** | Foundry 内置系统校验，若版本不兼容则自动回退 | 平台级保障 |

### 3.3 数据质量支撑层（transforms-expectations）

`transforms-expectations` 是内置的数据质量门禁系统，与 Pipeline 生命周期强绑定：

```python
from transforms.expectations import (
    column_not_null,      # 列不含空值
    primary_key,          # 列组合唯一且非空
    numeric_range,        # 数值在 [min, max] 范围内
    schema_subset,        # 输出 schema 是期望 schema 的子集
    schema_exact,         # 输出 schema 与期望完全一致
    column_unique,        # 列值全局唯一
    row_count_gt,         # 行数大于阈值（防止空输出）
    row_count_lt,         # 行数小于阈值（防止数据爆炸）
    column_values_in_set, # 列值枚举约束
)
```

执行语义：Expectation 在 Transform 完成后、数据集提交前执行。失败时：
1. 构建标记为失败
2. 输出数据集**不写入**（保持上一版本）
3. 下游依赖 Transform 不触发（断路保护）

### 3.4 可观测性支撑层

**Data Health Application** 是平台级健康监控入口：

| 健康检查类型 | 触发条件 | 通知渠道 |
|------------|---------|---------|
| Job Status | 构建失败/超时 | In-platform / Email / PagerDuty / Slack |
| Data Freshness | 数据集超过阈值未更新 | 同上 |
| Schema Drift | 输出 schema 与历史版本不一致 | 同上 |
| Sync Status | 外部同步失败 | 同上 |
| Row Count Anomaly | 行数异常波动 | 同上 |
| Build Success Rate | N 次构建中失败率超阈值 | 同上 |

**Upgrade Assistant（升级助手）：**

平台提供专项工具管理 Transform SDK 升级，主动感知而非被动故障：
- 扫描全平台受影响资源，列出影响清单
- 按 Owner 分配整改任务
- 设置 Deadline，临近时自动推送提醒
- 提供逐资源修复建议

---

## 4. 稳定性建设

### 4.1 版本稳定性机制

Foundry 的算子稳定性通过三层版本管控实现：

```
层级 1：API 语义版本
    transforms.api 遵循 Semantic Versioning
    ├── Major 版本变更 = Breaking Change（URL 升版 v1→v2）
    ├── Minor 版本变更 = 新增功能（向后兼容）
    └── Patch 版本变更 = 安全/Bug 修复（静默升级）

层级 2：Function 向后兼容检查
    Functions 发布前自动运行兼容性扫描：
    ├── 警告：删除函数、移除必填输入、修改输入类型
    └── 允许：新增可选输入、性能优化、内部实现变更

层级 3：Dataset 不可变性（Immutability）
    数据集每个版本不可变（类 Git commit）：
    ├── 并发读不阻塞
    ├── 新版本生成后旧版本仍可访问
    └── Branch 机制：实验分支不影响 main
```

### 4.2 增量稳定性机制

增量 Transform 是高风险场景（部分处理 + 状态依赖），Foundry 专门设计了安全保障：

```python
@incremental(
    require_incremental=True,   # 强制：无法增量时直接失败，不降级为全量
    snapshot_inputs=["ref"],    # 显式声明快照输入，避免增量误读
    v2_semantics=True,          # 启用 v2 语义（所有新代码推荐）
)
@transform(output=Output("/out"), src=Input("/src"), ref=Input("/ref"))
def compute(src, ref, output):
    ...
```

**事务跟踪机制：**  
Foundry 记录每个数据集的所有事务类型（APPEND / UPDATE / SNAPSHOT），在增量 Transform 启动前自动评估当前输入是否满足增量条件，不满足时：
- `require_incremental=False`（默认）：降级为全量构建
- `require_incremental=True`：构建直接失败，不产生错误输出

### 4.3 Pipeline Builder 稳定性机制

| 机制 | 描述 |
|------|------|
| **Build 前预校验** | 代码生成器在 Build 前执行完整性检查（Schema 推导、Join 键类型匹配、列存在性验证） |
| **强类型校验** | 所有表达式强类型，类型不匹配在配置期即报错，不等到运行时 |
| **严格输出检查** | 下游 Schema 期望与当前输出 Schema 比对，主动阻断静默破坏 |
| **Join 键建议** | 智能推荐潜在 Join 键（基于列名/类型相似度），减少用户配置错误 |

---

## 5. 扩展性建设

### 5.1 官方算子 vs 用户自定义：边界划分

```
┌─────────────────────────────────────────────────────────────────┐
│                    官方支持算子（Palantir 维护）                   │
│                                                                 │
│  Pipeline Builder 全量内置算子（第 2 节列举）                      │
│  transforms.api 核心 SDK                                        │
│  transforms-media / transforms-expectations                     │
│  palantir_models.transforms                                     │
│                                                                 │
│  特点：有文档、有版本保证、自动接收安全 patch、平台统一升级          │
│        稳定性高、开箱即用、不需用户维护                            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   用户自定义算子（用户维护）                        │
│                                                                 │
│  Python UDF（sidecar 模式，随 Executor 动态扩展）                 │
│  Java UDF（支持 Java 库集成，可定义 nullable 输出 schema）         │
│  Custom Expression（可复用的表达式封装）                           │
│  Custom Transform（可复用的多步 Transform 序列）                  │
│  Container Transform（完全自定义容器，BYOC 模式）                  │
│  Spark Sidecar Transform（容器与 Spark Executor 1:1 协同）       │
│                                                                 │
│  特点：灵活性最高、可引入任意外部依赖、用户负责版本和兼容性维护        │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 用户自定义算子的四种模式

#### 模式 A：Python UDF（Pipeline Builder 直接使用）

```python
# 在 Code Repository 定义
from pyspark.sql.functions import udf
from pyspark.sql.types import StringType

@udf(returnType=StringType())
def my_custom_logic(value: str) -> str:
    return value.upper().strip()

# Pipeline Builder 中通过 Reusables > User-defined functions 导入
# 运行时以 Sidecar 容器方式随 Spark Executor 扩展
```

**关键约束：**
- Python UDF 因序列化开销比 Spark 内置函数慢，尽量用内置函数替代
- Sidecar 与主进程共享资源，不能独立扩容
- 不支持 `print()` 调试，需用 `logging`

#### 模式 B：自定义表达式（Custom Expression）

在 Pipeline Builder 中通过 `Reusables > Custom functions > Add custom expression` 创建：
- 封装一个带可选参数的表达式逻辑
- 存储在 Foundry 资源系统中，可跨 Pipeline 复用
- 版本化管理，更新后各引用点自动继承

#### 模式 C：自定义变换（Custom Transform）

将多个 Transform Board 序列封装为单一可复用节点：
- 适合复杂、重复的多步处理流程（如标准化清洗流程）
- 参数化接口对外暴露，内部实现封装

#### 模式 D：Container Transform（BYOC）

```python
from transforms.api import ContainerTransform, ContainerTransformsConfiguration

container_config = ContainerTransformsConfiguration(
    image="registry.example.com/my-transform:sha256-abc123",
    # 必须: linux/amd64, 非 root UID 5001, 端口 1024-65535
    resources={"cpu": "2", "memory": "4Gi"},
    volume_mounts=["/input", "/output"],
)

my_transform = ContainerTransform(
    inputs=[Input("/data/source")],
    outputs=[Output("/data/result")],
    configuration=container_config,
)
```

适合场景：
- R / Rust / C++ / Julia 等非 JVM/Python 生态
- 需要 GPU 加速（深度学习推理）
- 强依赖特定系统库（如 GDAL、OpenCV 完整版）

### 5.3 自定义算子的扩展性保障机制

| 保障机制 | 描述 |
|---------|------|
| **UDF 版本化** | UDF 作为 Foundry 资源纳入版本管理，Pipeline 引用特定版本，升级可控 |
| **Sidecar 动态扩展** | Python/Java UDF 以 Sidecar 方式部署，随 Spark Executor 数量线性扩展 |
| **Container 隔离** | BYOC 容器完全隔离依赖环境，不影响平台其他 Transform |
| **Conda 依赖锁定** | `meta.yaml` 锁定所有依赖版本，构建可复现 |
| **本地调试链路** | `foundry-dev-tools` 支持本地运行 Transform，不用推送到平台即可验证 |

---

## 6. 算子规划视角：官方扩张路线

基于 Palantir 近期动态，算子库的官方扩张方向集中在三条主线：

### 主线 1：AI 算子原生化
- LLM Transform 已内置（配置 prompt + 模型即用）
- Embed Text（文本向量化）算子，接入向量检索
- AIP Evals 算子（人机反馈回路，评估结果写回数据集）
- 趋势：AI 算子从"插件"升级为"一等公民"，与普通数据算子统一编排

### 主线 2：Lightweight 算子能力对齐 Spark
- DuckDB/Polars 算子能力集持续扩充，追赶 PySpark
- Accelerated Pipeline（加速批处理）原生支持（2024-04 上线）
- 目标：中小数据集场景完全不需要启动 Spark

### 主线 3：GIS 算子可视化下沉
- `geospatial-tools` Python 库进入维护模式
- 空间算子能力统一迁移至 Pipeline Builder GIS 节点
- H3 Index 支持、球面距离计算、坐标系转换已完成下沉

---

## 7. 全景架构图

```
Palantir Foundry 算子库全景（完整版）
══════════════════════════════════════════════════════════════════

【用户入口层】
  ┌──────────────────────────────┐  ┌──────────────────────────┐
  │     Pipeline Builder         │  │   Code Repository        │
  │     (No-code / Low-code)     │  │   (Pro-code Python)      │
  │                              │  │                          │
  │  Expression（列级）           │  │  transforms.api          │
  │  ├─ 字符串 (11种)             │  │  ├─ @transform           │
  │  ├─ 数值   (10种)             │  │  ├─ @transform_df        │
  │  ├─ 日期   (7种)              │  │  ├─ @transform_pandas    │
  │  ├─ 布尔   (6种)              │  │  ├─ @transform_polars    │
  │  ├─ 类型转换(4种)             │  │  ├─ @incremental         │
  │  └─ GIS    (7种)              │  │  ├─ @configure           │
  │                              │  │  └─ @sidecar             │
  │  Transform（表级）            │  │                          │
  │  ├─ 行列操作 (12种)           │  │  扩展包                   │
  │  ├─ 多表操作 (5种)            │  │  ├─ transforms-media     │
  │  ├─ 聚合    (5种)             │  │  ├─ transforms-expect.   │
  │  ├─ 窗口函数(11种)            │  │  └─ palantir_models      │
  │  ├─ 数据整形(8种)             │  │                          │
  │  ├─ 媒体    (3种)             │  │  UDF 扩展                 │
  │  ├─ AI/ML  (4种)              │  │  ├─ Python UDF           │
  │  ├─ GIS    (7种)              │  │  ├─ Java UDF             │
  │  └─ 输出   (3种)              │  │  └─ Container Transform  │
  └──────────────────────────────┘  └──────────────────────────┘

【支撑体系层】
  ┌───────────┐ ┌─────────────┐ ┌──────────────┐ ┌───────────┐
  │ 执行引擎  │ │ 数据质量    │ │ 版本稳定性   │ │ 可观测性  │
  │ Spark     │ │ Expectations│ │ SemVer       │ │ Data      │
  │ Lightweight│ │ Schema校验  │ │ Adjudication │ │ Health    │
  │ Flink     │ │ 行级断言    │ │ Pinning      │ │ Upgrade   │
  │ Container │ │ Pipeline    │ │ 不可变Dataset│ │ Assistant │
  │ Sidecar   │ │ 断路保护    │ │ 兼容性扫描   │ │ Alert     │
  └───────────┘ └─────────────┘ └──────────────┘ └───────────┘
```

---

## 8. 关键结论

1. **算子数量级**：Pipeline Builder 内置 Expression 约 46 种、Transform 约 63 种；SDK 侧 transforms.api 提供 8 个核心装饰器、10 个运行时类、6 种参数类型，另有 3 个扩展包。

2. **稳定性三支柱**：API SemVer 契约 + Adjudication 自动回退 + Dataset 不可变性，共同保证算子升级不打破已有 Pipeline。

3. **扩展性四模式**：Python UDF（Sidecar 扩展）→ Custom Expression/Transform（封装复用）→ Container Transform（BYOC 全自定义），按复杂度梯度选择。

4. **官方 vs 自定义的核心边界**：官方算子覆盖 80% 通用场景，保证稳定性；用户自定义覆盖剩余 20%，灵活性换维护责任——Foundry 明确不鼓励在有内置算子时写 UDF。

5. **数据质量是算子的隐形护城河**：`transforms-expectations` 与 Pipeline 生命周期强绑定，失败即断路，这比事后监控早介入一个量级，是 Foundry 算子体系有别于裸 Spark 的关键设计。

6. **AI 算子是下一代核心差异**：LLM Transform、Embed Text、Trained Model Node 已原生内置，不是外挂，这意味着 AI 处理与结构化数据处理在同一个 DAG 编排，无需跨系统跳转。

---

## 9. 参考

- `docs/raw/01-pipeline-expression-dsl.md`
- `docs/raw/02-execution-engine-spark.md`
- `docs/raw/03-streaming-batch-architecture.md`
- `docs/raw/11-marking-mechanism-deep-dive.md`
- Palantir Foundry 官方文档：transforms.api / Pipeline Builder / Data Health / Upgrade Assistant
