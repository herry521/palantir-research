# 算子平台建设方案：Palantir 级别算子能力设计与规划

**日期：** 2026-04-28  
**类型：** 系统设计 · 可落地方案  
**目标：** 指导从零构建具备 Palantir Foundry 级别算子能力的数据处理平台

> **文档性质说明：** 本文为基于 Palantir Foundry 调研的**架构设计建议**，接口定义、类名、方法名均为作者自行设计（参考 Apache Beam 等开源框架），**不代表 Palantir 的真实内部实现**。涉及 Palantir 现状的描述已标注 [事实]/[推断]/[猜测]。

---

## 0. 阅读指引

本文分为五个层次，依次解决：

| 章节 | 问题 |
|------|------|
| 1. 核心抽象设计 | 算子是什么、接口契约如何定义 |
| 2. 算子注册与发现 | 算子如何被平台感知和管理 |
| 3. 执行引擎路由 | 算子在哪里运行、如何选择 |
| 4. 支撑体系建设 | Schema 传播、质量门禁、可观测性 |
| 5. 算子规划路线图 | 优先造哪些算子、谁负责维护 |

---

## 1. 核心抽象设计

### 1.1 算子的本质定义

算子（Operator）= **有契约的计算单元**。  
契约包含三部分：输入声明、输出声明、执行逻辑。  
平台在 **编译期** 验证契约，在 **运行时** 履行契约。

```
              ┌──────────────────────┐
              │     Operator         │
              │                      │
  Input Ports ►  Schema Contract     ► Output Ports
  (N个,有类型) │  Param Declarations  │ (M个,有类型)
              │  Execution Logic     │
              │  Resource Hints      │
              └──────────────────────┘
```

### 1.2 算子接口契约（核心抽象）

每一个算子必须实现以下契约，无论是官方内置还是用户自定义：

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Any
from enum import Enum

# ── 类型系统 ──────────────────────────────────────────────────────

class ColumnType(Enum):
    """平台原生类型系统，所有算子使用此类型，与底层引擎解耦"""
    STRING    = "string"
    INTEGER   = "integer"
    LONG      = "long"
    DOUBLE    = "double"
    BOOLEAN   = "boolean"
    DATE      = "date"
    TIMESTAMP = "timestamp"
    ARRAY     = "array"
    STRUCT    = "struct"
    BINARY    = "binary"
    GEOMETRY  = "geometry"   # GIS 扩展
    EMBEDDING = "embedding"  # AI 扩展

@dataclass
class ColumnSchema:
    name: str
    type: ColumnType
    nullable: bool = True
    metadata: Dict[str, Any] = field(default_factory=dict)  # 语义标签、安全标记

@dataclass
class TableSchema:
    columns: List[ColumnSchema]

    def column(self, name: str) -> Optional[ColumnSchema]:
        return next((c for c in self.columns if c.name == name), None)

    def merge(self, other: "TableSchema") -> "TableSchema":
        """Union 算子使用：按名称合并两张表的 schema"""
        ...

# ── 参数系统 ──────────────────────────────────────────────────────

@dataclass
class ParamSpec:
    name: str
    type: str                        # "string" | "integer" | "boolean" | "float" | "enum"
    required: bool = True
    default: Any = None
    allowed_values: List[Any] = field(default_factory=list)
    description: str = ""

# ── 端口声明 ──────────────────────────────────────────────────────

@dataclass
class InputPort:
    name: str
    required: bool = True
    accepts_stream: bool = False     # 是否接受流式数据集

@dataclass
class OutputPort:
    name: str
    is_primary: bool = True

# ── 资源申报 ──────────────────────────────────────────────────────

class EngineHint(Enum):
    LIGHTWEIGHT = "lightweight"      # 单节点，DuckDB/Polars
    SPARK       = "spark"            # 分布式 Spark
    FLINK       = "flink"            # 流式 Flink
    CONTAINER   = "container"        # 任意容器

@dataclass
class ResourceHint:
    preferred_engine: EngineHint = EngineHint.LIGHTWEIGHT
    min_memory_gb: float = 1.0
    max_input_rows_for_lightweight: int = 50_000_000  # 超过此值自动升级到 Spark

# ── 算子核心契约 ──────────────────────────────────────────────────

class OperatorSpec(ABC):
    """每个算子必须实现的静态契约，平台在编译期调用"""

    @property
    @abstractmethod
    def operator_id(self) -> str:
        """全局唯一标识，格式：namespace.operator_name，如 core.filter / user.my_udf"""
        ...

    @property
    @abstractmethod
    def version(self) -> str:
        """SemVer，如 1.2.0"""
        ...

    @property
    def input_ports(self) -> List[InputPort]:
        """默认单输入，算子可重写"""
        return [InputPort(name="input")]

    @property
    def output_ports(self) -> List[OutputPort]:
        """默认单输出，算子可重写"""
        return [OutputPort(name="output")]

    @property
    def params(self) -> List[ParamSpec]:
        return []

    @property
    def resource_hint(self) -> ResourceHint:
        return ResourceHint()

    @abstractmethod
    def infer_output_schema(
        self,
        input_schemas: Dict[str, TableSchema],
        param_values: Dict[str, Any],
    ) -> Dict[str, TableSchema]:
        """
        编译期 Schema 推导。
        平台在用户配置算子时实时调用，用于：
          1. 向下游算子传播输出 schema
          2. 检测类型错误（如 Join 键类型不匹配）
          3. 驱动 UI 自动补全列名
        必须是纯函数，不能有副作用。
        """
        ...

    def validate_params(self, param_values: Dict[str, Any]) -> List[str]:
        """
        编译期参数校验，返回错误信息列表（空 = 校验通过）。
        基类提供通用校验（required/allowed_values），算子可 override 添加自定义校验。
        """
        errors = []
        for spec in self.params:
            val = param_values.get(spec.name)
            if spec.required and val is None:
                errors.append(f"参数 '{spec.name}' 不能为空")
            if val is not None and spec.allowed_values and val not in spec.allowed_values:
                errors.append(f"参数 '{spec.name}' 的值 '{val}' 不在允许列表 {spec.allowed_values} 中")
        return errors


class OperatorExecutor(ABC):
    """算子运行时执行逻辑，与 OperatorSpec 分离，支持多引擎实现"""

    @abstractmethod
    def execute(
        self,
        inputs: Dict[str, Any],          # key = port name, value = DataFrame（引擎相关）
        outputs: Dict[str, Any],          # key = port name, value = OutputWriter
        params: Dict[str, Any],
        context: "ExecutionContext",
    ) -> None:
        ...
```

### 1.3 为什么 Spec 与 Executor 分离

| 职责 | OperatorSpec | OperatorExecutor |
|------|-------------|-----------------|
| 调用时机 | 编译期（配置时） | 运行时（执行时） |
| 调用者 | Schema 推导引擎 / UI / 校验器 | 执行引擎（Spark/DuckDB/Flink） |
| 引擎依赖 | 无（纯 Python） | 强依赖（PySpark/Polars/Flink API） |
| 测试方式 | 单元测试，毫秒级 | 集成测试，需要引擎环境 |
| 核心价值 | 编译期类型安全 | 运行时正确性 |

同一个 OperatorSpec 可以有多个 Executor 实现（Spark 版 / Polars 版），平台根据数据规模路由。[推断]

---

## 2. 算子注册与发现

### 2.1 算子注册表（Operator Registry）

注册表是平台感知所有算子的中枢，提供三种视图：

```
Operator Registry
├── 静态元数据视图（配置时）
│   ├── operator_id / version / category / description
│   ├── input_ports / output_ports / params
│   └── 用于 UI 渲染算子面板、参数表单
│
├── Schema 契约视图（编译时）
│   ├── infer_output_schema(input_schemas, params) → output_schemas
│   ├── validate_params(params) → errors
│   └── 用于 DAG 节点间 schema 传播和类型检查
│
└── 执行绑定视图（运行时）
    ├── executor_for(engine: EngineHint) → OperatorExecutor
    └── 用于调度器选择对应引擎实现
```

**注册表实现：**

```python
class OperatorRegistry:
    _specs: Dict[str, OperatorSpec] = {}
    _executors: Dict[str, Dict[EngineHint, OperatorExecutor]] = {}

    @classmethod
    def register(
        cls,
        spec: OperatorSpec,
        executors: Dict[EngineHint, OperatorExecutor],
    ):
        key = f"{spec.operator_id}@{spec.version}"
        cls._specs[key] = spec
        cls._executors[key] = executors

    @classmethod
    def get_spec(cls, operator_id: str, version: str = "latest") -> OperatorSpec:
        ...

    @classmethod
    def get_executor(cls, operator_id: str, engine: EngineHint) -> OperatorExecutor:
        ...

    @classmethod
    def list_all(cls, category: str = None) -> List[OperatorSpec]:
        ...
```

### 2.2 算子发现机制（SPI）

参考 Java SPI，通过 Python entry_points 实现插件自动发现：

```toml
# 算子包的 pyproject.toml
[project.entry-points."dataplatform.operators"]
core_filter   = "dataplatform.operators.core.filter:FilterOperatorPlugin"
core_join     = "dataplatform.operators.core.join:JoinOperatorPlugin"
my_custom_udf = "mycompany.operators.custom:MyCustomPlugin"
```

```python
# 平台启动时自动扫描所有已安装包的算子
from importlib.metadata import entry_points

def discover_and_register_all():
    for ep in entry_points(group="dataplatform.operators"):
        plugin = ep.load()
        OperatorRegistry.register(plugin.spec(), plugin.executors())
```

**三种注册方式对比：**（本表为本文设计建议，非 Palantir 真实实现）

| 方式 | 适用场景 | 生效时机 |
|------|---------|---------|
| entry_points（包级） | 官方算子、团队共享算子 | 平台启动时 |
| `@operator` 装饰器（代码级） | Code Repository 内算子 | 仓库 Build 时 |
| API 动态注册 | 实验性算子、测试 | 运行时动态注入 |

### 2.3 算子版本化与兼容性管理

```
算子版本管理策略
─────────────────────────────────────────────

版本格式：MAJOR.MINOR.PATCH

MAJOR 变更 = Breaking Change：
  - 删除 param / 修改 param 类型
  - 修改 output schema 结构
  - 修改 operator_id
  → 必须同时保留旧版本，设置 deprecated=True + sunset_date
  → Pipeline 配置文件锁定算子版本，不自动升级 MAJOR

MINOR 变更 = 向后兼容新增：
  - 新增可选 param（有 default）
  - 新增 output 列（下游算子不使用则无影响）
  → 静默自动升级

PATCH 变更 = 安全/Bug 修复：
  - 不改变 schema 契约
  → 后台自动升级，用户无感
```

**兼容性扫描（发布前自动运行）：**

```python
class CompatibilityChecker:
    def check(self, old: OperatorSpec, new: OperatorSpec) -> CompatibilityReport:
        breaking = []
        # 检查 param 删除
        old_params = {p.name for p in old.params}
        new_params = {p.name for p in new.params}
        for removed in old_params - new_params:
            breaking.append(f"Breaking: 删除了 param '{removed}'")
        # 检查 output schema 结构变化
        # ...
        return CompatibilityReport(breaking_changes=breaking)
```

---

## 3. 执行引擎路由

### 3.1 引擎路由决策树

```
收到 Build 请求
    │
    ▼
读取算子 resource_hint.preferred_engine
    │
    ├─ FLINK ──────────────────► 提交到 Flink Job Manager
    │
    ├─ CONTAINER ──────────────► 启动 Docker 容器执行
    │
    ├─ SPARK（显式指定）────────► 提交到 Spark Cluster
    │
    └─ LIGHTWEIGHT / AUTO
          │
          ▼
        评估数据规模
          │
          ├─ 输入行数 ≤ 5000万 且 输入大小 ≤ 50GB
          │       → Lightweight（DuckDB 或 Polars）
          │
          ├─ 输入行数 > 5000万 或 输入大小 > 50GB
          │       → 自动升级到 Spark
          │
          └─ 无法预估（流式/外部源）
                  → 按算子默认引擎
```

### 3.2 多引擎 Executor 注册模式

一个算子提供多套执行实现，平台自动路由：

```python
# core/filter.py 示例

class FilterSpec(OperatorSpec):
    @property
    def operator_id(self): return "core.filter"

    @property
    def version(self): return "2.1.0"

    @property
    def params(self):
        return [
            ParamSpec("condition", type="expression", required=True,
                      description="过滤条件表达式，如 age > 18 AND status = 'active'"),
        ]

    def infer_output_schema(self, input_schemas, param_values):
        # Filter 不改变 schema，原样传递
        return {"output": input_schemas["input"]}


class FilterPolarsExecutor(OperatorExecutor):
    def execute(self, inputs, outputs, params, context):
        import polars as pl
        df: pl.DataFrame = inputs["input"]
        result = df.filter(pl.Expr.from_json(params["condition"]))
        outputs["output"].write(result)


class FilterSparkExecutor(OperatorExecutor):
    def execute(self, inputs, outputs, params, context):
        df = inputs["input"]  # PySpark DataFrame
        result = df.filter(params["condition"])
        outputs["output"].write(result)


# 注册时同时提供两种实现
OperatorRegistry.register(
    spec=FilterSpec(),
    executors={
        EngineHint.LIGHTWEIGHT: FilterPolarsExecutor(),
        EngineHint.SPARK:       FilterSparkExecutor(),
    }
)
```

### 3.3 执行上下文（ExecutionContext）

算子 Executor 通过 Context 获取平台能力，而非直接依赖平台内部：

```python
@dataclass
class ExecutionContext:
    build_id: str
    branch: str
    spark_session: Optional[Any]        # 仅 Spark 引擎可用
    auth_header: str                    # 调用外部服务用
    params: Dict[str, Any]
    lineage_emitter: "LineageEmitter"   # 注入 Lineage 采集
    metrics_emitter: "MetricsEmitter"   # 注入 Metrics 上报
    logger: "Logger"
```

---

## 4. 支撑体系建设

### 4.1 Schema 传播引擎（编译期类型系统）

这是整个平台最重要的支撑能力，解决"配置时发现问题而非运行时"。

```
Pipeline DAG 的 Schema 传播过程：

Source Node          Filter Node           Join Node
(已知 schema)    →   调用 infer_output   →  调用 infer_output
                     _schema()              _schema()
                     返回新 schema          检测 Join 键类型
                                            若不匹配 → 立即报错
                                            若匹配   → 合并 schema
                                            传给下游
```

**实现：拓扑排序 + 逐节点推导**

```python
class SchemaPropagationEngine:
    def propagate(self, dag: "PipelineDag") -> Dict[str, TableSchema]:
        """
        返回 DAG 中每个节点每个输出 Port 的 schema。
        在用户每次修改算子配置时调用（增量计算，非全量）。
        """
        schemas: Dict[str, TableSchema] = {}
        errors: List[SchemaError] = []

        for node in dag.topological_sort():
            spec = OperatorRegistry.get_spec(node.operator_id)
            input_schemas = {
                port: schemas[upstream_node_id]
                for port, upstream_node_id in node.input_connections.items()
                if upstream_node_id in schemas
            }

            # 参数校验
            param_errors = spec.validate_params(node.param_values)
            if param_errors:
                errors.append(SchemaError(node_id=node.id, messages=param_errors))
                continue

            # Schema 推导
            try:
                output_schemas = spec.infer_output_schema(input_schemas, node.param_values)
                for port, schema in output_schemas.items():
                    schemas[f"{node.id}.{port}"] = schema
            except SchemaInferenceError as e:
                errors.append(SchemaError(node_id=node.id, messages=[str(e)]))

        return schemas, errors
```

**典型 Schema 推导实现（Join 算子）：**

```python
class JoinSpec(OperatorSpec):
    def infer_output_schema(self, input_schemas, param_values):
        left  = input_schemas["left"]
        right = input_schemas["right"]
        join_keys: List[str] = param_values["join_keys"]
        join_type: str = param_values["join_type"]  # inner/left/right/full

        # 校验 Join 键存在
        for key in join_keys:
            if not left.column(key):
                raise SchemaInferenceError(f"左表不存在列 '{key}'")
            if not right.column(key):
                raise SchemaInferenceError(f"右表不存在列 '{key}'")
            # 校验 Join 键类型兼容
            l_type = left.column(key).type
            r_type = right.column(key).type
            if not types_compatible(l_type, r_type):
                raise SchemaInferenceError(
                    f"Join 键 '{key}' 类型不兼容：左表 {l_type}，右表 {r_type}"
                )

        # 构建输出 schema（右表 Join 键列不重复输出）
        output_cols = list(left.columns)
        for col in right.columns:
            if col.name not in join_keys:
                output_cols.append(col)

        # Full/Right Join 时左表列可能为 null
        if join_type in ("full", "right"):
            output_cols = [
                ColumnSchema(c.name, c.type, nullable=True) if c in left.columns else c
                for c in output_cols
            ]

        return {"output": TableSchema(columns=output_cols)}
```

### 4.2 数据质量门禁体系

数据质量检查分三层，与算子生命周期绑定：

```
┌───────────────────────────────────────────────────────┐
│  Layer 1：Schema Gate（编译期，0 成本）                 │
│  由 SchemaPropagationEngine 驱动                       │
│  检查：列存在性 / 类型兼容性 / 必填参数                  │
└───────────────────────────────────────────────────────┘
              ↓ 编译通过才允许 Build

┌───────────────────────────────────────────────────────┐
│  Layer 2：Input Expectation（运行时，读取前）           │
│  在 Executor.execute() 入口前自动注入                   │
│  检查：行数 / 关键列非空 / 值域范围 / 主键唯一性         │
│  失败时：Build 失败，输出不写入，下游不触发（断路）       │
└───────────────────────────────────────────────────────┘
              ↓ 输入校验通过才执行

┌───────────────────────────────────────────────────────┐
│  Layer 3：Output Expectation（运行时，写入后）          │
│  在 Executor.execute() 完成后自动注入                   │
│  检查：输出行数合理性 / 空值比例 / 输出 schema 完整性   │
│  失败时：回滚本次写入，保留上一个成功版本               │
└───────────────────────────────────────────────────────┘
```

**Expectation DSL（内置算子，不是外挂）：**

```python
# 在 Pipeline 配置中声明，与算子节点平级
expectations = [
    # 输入期望（在 node_id=join_customers 执行前校验）
    InputExpectation(
        target_node="join_customers",
        port="left",
        checks=[
            column_not_null("user_id"),
            primary_key("user_id"),
            row_count_between(min=1000, max=100_000_000),
        ]
    ),
    # 输出期望（在 node_id=agg_daily_revenue 执行后校验）
    OutputExpectation(
        target_node="agg_daily_revenue",
        checks=[
            column_not_null("revenue"),
            numeric_range("revenue", min=0),
            schema_contains(["date", "revenue", "order_count"]),
        ]
    ),
]
```

### 4.3 算子稳定性运行机制

**重试与熔断：**

```python
@dataclass
class RetryPolicy:
    max_attempts: int = 3
    backoff_seconds: List[int] = field(default_factory=lambda: [30, 120, 300])
    retryable_exceptions: List[str] = field(
        default_factory=lambda: ["SparkDriverOOM", "NetworkTimeout"]
    )
    # 不可重试：SchemaError / DataQualityFailure（幂等性无意义）

@dataclass
class CircuitBreakerPolicy:
    failure_threshold: int = 3         # N 次连续失败后熔断
    reset_timeout_minutes: int = 30    # 熔断后等待时间
    # 熔断时：下游 Pipeline 收到 STALE 而非持续触发失败
```

**资源隔离（Bulkhead）：**

```
算子执行队列按优先级隔离
├── P0 Queue（生产关键）：专用 Spark Cluster Pool，不与其他共享
├── P1 Queue（业务重要）：共享 Spark Cluster，有资源上限
└── P2 Queue（开发调试）：Lightweight 池，不占用 Spark 资源
```

### 4.4 Lineage 自动采集

每个算子执行完毕，平台自动 emit OpenLineage 事件：

```python
class LineageEmitter:
    def emit(self, event: OpenLineageEvent):
        """算子平台自动调用，算子开发者无需感知"""
        ...

# 平台在 Executor 外层包装，算子开发者写纯业务逻辑
class LineageWrappedExecutor(OperatorExecutor):
    def __init__(self, inner: OperatorExecutor, emitter: LineageEmitter):
        self._inner = inner
        self._emitter = emitter

    def execute(self, inputs, outputs, params, context):
        self._emitter.emit_start(context.build_id, inputs)
        try:
            self._inner.execute(inputs, outputs, params, context)
            self._emitter.emit_complete(context.build_id, outputs)
        except Exception as e:
            self._emitter.emit_fail(context.build_id, error=e)
            raise
```

### 4.5 可观测性指标体系

每个算子自动上报以下指标（平台注入，算子无需手写）：

| 指标 | 类型 | 说明 |
|------|------|------|
| `operator.build.duration_ms` | Histogram | 构建耗时，按算子/引擎分维度 |
| `operator.build.input_rows` | Gauge | 输入行数 |
| `operator.build.output_rows` | Gauge | 输出行数，异常波动告警 |
| `operator.build.status` | Counter | success / failure / skipped |
| `operator.expectation.failure` | Counter | 数据质量失败次数，按 check 类型 |
| `operator.schema.drift` | Counter | schema 与上次不一致次数 |
| `operator.engine.selection` | Counter | lightweight vs spark 选择分布 |

---

## 5. 算子规划路线图

### 5.1 官方算子 vs 用户自定义：决策原则

```
官方算子（platform.* namespace）：（以下为本文设计建议，参考了 Palantir 官方/自定义边界原则[推断]）
  判断标准：
  ✓ 使用频率 ≥ 30%（超过 30% 的 Pipeline 需要）
  ✓ 可标准化：不依赖业务特定语义
  ✓ 有 Schema 推导逻辑（能编译期校验）
  ✓ 可多引擎实现（Lightweight + Spark 双版本）
  责任：平台团队维护，SLA 保证，自动升级

用户自定义算子（user.* 或 team.* namespace）：
  判断标准：
  ✓ 业务特定逻辑（如公司特有的数据清洗规则）
  ✓ 依赖特殊外部库或系统
  ✓ 使用频率 < 30%
  责任：开发团队自维护，平台提供框架和 CI 工具
```

### 5.2 算子建设优先级矩阵

#### P0：必须首批交付（平台上线前）

这些算子覆盖 ~70% 的真实 Pipeline 需求，没有它们平台无法使用。

**行列基础算子（P0）**

| 算子 ID | 名称 | 核心难点 |
|---------|------|---------|
| `core.filter` | 条件过滤 | 表达式 DSL 解析，Schema 原样传递 |
| `core.select` | 选择/重命名列 | 输出 schema = 用户选定列 |
| `core.add_column` | 新增列 | 表达式求值 → 输出 schema 追加新列 |
| `core.drop_columns` | 删除列 | 输出 schema 移除指定列 |
| `core.cast` | 类型转换 | 输出 schema 中目标列类型变更 |
| `core.rename` | 批量重命名 | 输出 schema 名称映射 |

**多表操作算子（P0）**

| 算子 ID | 名称 | 核心难点 |
|---------|------|---------|
| `core.join` | Join | Join 键类型校验；6 种 Join 类型；nullable 语义 |
| `core.union` | Union | 列名对齐；类型提升（int → long） |

**聚合算子（P0）**

| 算子 ID | 名称 | 核心难点 |
|---------|------|---------|
| `core.aggregate` | 分组聚合 | GROUP BY + 多聚合函数；输出 schema = key列 + 聚合列 |

**I/O 算子（P0）**

| 算子 ID | 名称 | 核心难点 |
|---------|------|---------|
| `io.read_dataset` | 读数据集 | schema 从数据集元数据加载 |
| `io.write_dataset` | 写数据集 | 增量/全量写入，事务提交 |

#### P1：第二批交付（上线后 3 个月内）

覆盖高频分析场景，提升平台竞争力。

**分析算子（P1）**

| 算子 ID | 名称 | 核心难点 |
|---------|------|---------|
| `core.window` | 窗口函数 | 窗口帧规范；rank/lag/lead/cumsum；分区+排序 schema 校验 |
| `core.pivot` | 行转列 | 列键值动态展开，输出 schema 运行时才知 → 提供 preview 机制 |
| `core.unpivot` | 列转行 | 输出 schema 固定为 key+variable+value 三列 |
| `core.deduplicate` | 去重 | 窗口排序去重；Schema 原样传递 |

**数据整形算子（P1）**

| 算子 ID | 名称 | 核心难点 |
|---------|------|---------|
| `core.case` | Case/When | 多分支表达式；输出列类型推断 |
| `core.split_dataset` | 数据集分流 | 多输出 port；路由条件互斥性校验 |
| `core.flatten` | 结构体展平 | 嵌套 STRUCT 类型展开；列名冲突处理 |
| `core.explode` | 数组展开 | ARRAY 类型展开为多行；Schema 中数组列 → 元素类型 |

**字符串表达式（P1，作为 add_column 的子能力）**

| 表达式 ID | 功能 |
|----------|------|
| `expr.str.concat` | 拼接 |
| `expr.str.contains` | 包含 |
| `expr.str.split` | 分割 |
| `expr.str.regex_extract` | 正则提取 |
| `expr.str.upper/lower` | 大小写 |
| `expr.str.trim` | 去空白 |
| `expr.str.length` | 长度 |
| `expr.str.replace` | 替换 |

**日期表达式（P1）**

| 表达式 ID | 功能 |
|----------|------|
| `expr.date.extract` | 提取年/月/日/时/分/秒/季度/周 |
| `expr.date.add` | 日期加减 |
| `expr.date.diff` | 日期差 |
| `expr.date.format` | 日期→字符串 |
| `expr.date.parse` | 字符串→日期 |
| `expr.date.truncate` | 截断到月/周/天 |

**数值表达式（P1）**

| 表达式 ID | 功能 |
|----------|------|
| `expr.num.round/ceil/floor` | 取整 |
| `expr.num.abs` | 绝对值 |
| `expr.num.power/sqrt/log` | 数学函数 |
| `expr.num.coalesce` | 空值替换 |

#### P2：第三批交付（上线后 6 个月内）

差异化竞争能力，覆盖特殊场景。

**AI/ML 算子（P2）**

| 算子 ID | 名称 | 核心难点 |
|---------|------|---------|
| `ai.llm_transform` | LLM 逐行处理 | prompt 模板 + 并发控制；输出列类型为 STRING |
| `ai.embed_text` | 文本向量化 | 输出列类型为 EMBEDDING（ARRAY<FLOAT>） |
| `ai.model_inference` | ML 模型推理 | Model 元数据读取；输出 schema 由模型 signature 决定 |

**GIS 算子（P2）**

| 算子 ID | 名称 | 核心难点 |
|---------|------|---------|
| `gis.buffer` | 几何缓冲区 | 坐标系选择；距离单位换算 |
| `gis.spatial_join` | 空间 Join | KNN / 相交 / 距离三种模式；内存限制（1M 点需 3GB） |
| `gis.h3_index` | H3 索引 | 分辨率参数；输出 schema 追加 h3_index:STRING 列 |
| `gis.parse_wkt` | WKT 解析 | STRING → GEOMETRY 类型 |

**媒体算子（P2）**

| 算子 ID | 名称 | 核心难点 |
|---------|------|---------|
| `media.ocr` | 图片/PDF 文字提取 | Container 执行；输出 schema 固定为 file_id + text |
| `media.transcribe` | 音频转文字 | 同上 |
| `media.resize_image` | 图片缩放 | Binary 列处理 |

**数据质量算子（P2，内置为平台能力）**

| 算子 ID | 名称 |
|---------|------|
| `quality.column_not_null` | 非空检查 |
| `quality.primary_key` | 主键唯一性 |
| `quality.numeric_range` | 值域检查 |
| `quality.schema_exact` | Schema 精确匹配 |
| `quality.row_count_between` | 行数范围检查 |
| `quality.value_in_set` | 枚举值检查 |

#### P3：按需建设（由业务方提出）

以下算子业务特异性强，由业务团队自定义，平台提供框架：

| 类型 | 示例 | 建设方式 |
|------|------|---------|
| 业务清洗逻辑 | 手机号脱敏、身份证校验 | Python UDF / Custom Expression |
| 特定系统集成 | SAP 数据拉取、CRM 同步 | Container Transform |
| 特殊算法 | 公司专有评分模型 | Code Repository Transform |
| 行业特定算子 | 金融 XBRL 解析 | Container + 专有 JAR |

---

## 6. 用户自定义算子扩展框架

为保证自定义算子与平台无缝集成，提供标准脚手架：

### 6.1 自定义算子开发模板

```python
# my_operators/phone_mask.py

from dataplatform.sdk import OperatorSpec, OperatorExecutor, OperatorRegistry
from dataplatform.sdk import TableSchema, ColumnSchema, ColumnType, ParamSpec, ResourceHint, EngineHint

class PhoneMaskSpec(OperatorSpec):
    """手机号脱敏算子：将指定列的手机号替换为 138****5678 格式"""

    @property
    def operator_id(self): return "company.phone_mask"

    @property
    def version(self): return "1.0.0"

    @property
    def params(self):
        return [
            ParamSpec("column", type="string", required=True, description="要脱敏的列名"),
            ParamSpec("mask_char", type="string", default="*", description="掩码字符"),
        ]

    @property
    def resource_hint(self):
        return ResourceHint(preferred_engine=EngineHint.LIGHTWEIGHT)

    def infer_output_schema(self, input_schemas, param_values):
        # 脱敏不改变 schema 结构，列类型仍为 STRING
        schema = input_schemas["input"]
        col = param_values.get("column")
        if col and not schema.column(col):
            raise SchemaInferenceError(f"列 '{col}' 不存在")
        return {"output": schema}


class PhoneMaskPolarsExecutor(OperatorExecutor):
    def execute(self, inputs, outputs, params, context):
        import polars as pl
        col = params["column"]
        mask = params["mask_char"]
        df = inputs["input"]
        result = df.with_columns(
            pl.col(col).str.replace(r"(\d{3})\d{4}(\d{4})", f"$1{mask*4}$2")
        )
        outputs["output"].write(result)


# 注册
OperatorRegistry.register(
    spec=PhoneMaskSpec(),
    executors={EngineHint.LIGHTWEIGHT: PhoneMaskPolarsExecutor()}
)
```

### 6.2 自定义算子 CI/CD 流水线

```yaml
# .github/workflows/operator-publish.yml
steps:
  - name: 运行算子单元测试
    run: pytest tests/operators/ -v

  - name: 编译期 Schema 推导测试
    run: python -m dataplatform.ci.schema_test tests/schema_cases/

  - name: 兼容性扫描（对比上一版本）
    run: dataplatform-cli operator check-compat --prev v1.0.0 --next v1.1.0

  - name: 发布到算子注册表
    run: dataplatform-cli operator publish --registry internal
```

---

## 7. 平台建设优先级与里程碑

```
Phase 0（第 1 个月）：基础框架
  ├── OperatorSpec / OperatorExecutor 接口定义
  ├── OperatorRegistry 实现（静态注册）
  ├── Schema 传播引擎（核心）
  └── 执行引擎路由（Lightweight 优先）

Phase 1（第 2-3 个月）：P0 算子 + 基础支撑
  ├── 全部 P0 算子（filter/select/add_column/join/union/aggregate/IO）
  ├── Layer 1-2 数据质量门禁
  ├── Lineage 自动采集
  └── 基础可观测性指标

Phase 2（第 4-6 个月）：P1 算子 + 稳定性
  ├── 全部 P1 算子（window/pivot/case/split 等）
  ├── P1 表达式库（字符串/日期/数值）
  ├── 重试 + 熔断机制
  ├── 版本兼容性扫描 CI
  └── Spark 引擎对接（P0/P1 算子双引擎实现）

Phase 3（第 7-12 个月）：P2 算子 + 扩展生态
  ├── AI/ML 算子（LLM/Embed/ModelInference）
  ├── GIS 算子（SpatialJoin/H3/Buffer）
  ├── 媒体算子（Container 模式）
  ├── 用户自定义算子框架 + CI 工具
  ├── 算子 Marketplace（内部注册表 + 搜索）
  └── Flink 流式算子接入
```

---

## 8. 关键设计决策与权衡

| 决策点 | 推荐方案 | 原因 | 替代方案及风险 |
|--------|---------|------|--------------|
| Schema 推导时机 | 编译期（配置时） | 早发现，0 运行成本 | 运行期推导：快速开发但问题晚暴露 |
| Spec/Executor 分离 | 是 | 单元测试 Spec 不需要引擎 | 合并：实现简单但测试成本高 |
| 多引擎策略 | 按规模自动路由 | 降本增效，DuckDB 比 Spark 快 3-5x[推断] | 只用 Spark：稳定但成本高 |
| 算子版本锁定 | Pipeline 配置锁定 MAJOR 版本 | 升级不打破存量 Pipeline | 不锁定：灵活但升级风险大 |
| 自定义算子注册 | entry_points（Python SPI） | 标准生态，无需修改平台代码 | 中心化注册 API：更可控但耦合高 |
| 数据质量失败处理 | 断路（不写入 + 下游不触发） | 防止坏数据传播 | 警告不失败：容错但掩盖问题 |
| Lineage 采集 | 平台层透明注入（装饰器模式） | 算子开发者零感知 | 算子内手动 emit：灵活但容易遗漏 |

---

## 9. 参考资料

- `docs/raw/14-transform-operator-library.md` — Palantir 算子库现状分析
- Apache Beam PTransform 设计：Spec/Executor 分离的标准参考
- Spark Catalyst：类型系统与编译期优化的工程实践
- OpenLineage 规范：Lineage 采集标准
- Python entry_points：SPI 机制参考实现
