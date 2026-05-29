# Palantir 高码能力研究综合结论

**日期：** 2026-05-29
**来源：** `docs/raw/21-pro-code-capability-deep-dive.md` 与既有 Pipeline 调研材料
**可信度标签：** 【实时】=本轮官方资料查证；【推断】=基于事实的工程推导；【猜测】=待验证假设

---

## 一、它到底强在哪里

### 1. 强在平台契约，不强在“能写代码”

Palantir Code Repositories 支持 Git、PR、权限、IntelliSense、lint、error checking，并支持 Python、Java、SQL transform repositories。【实时】

但真正强点不是 Web IDE，而是代码被平台理解：Transform 的 `Input` / `Output` 声明把代码函数转成 Dataset 生产关系，后续调度、血缘、质量、权限和版本都能围绕这个关系工作。【推断】

### 2. 强在 Dataset 中心化，而不是任务中心化

Scheduling 能按时间、数据更新、逻辑更新触发，并可构建单个 Dataset、它的依赖、它的下游或两个 Dataset 之间的链路。【实时】

这说明 Foundry 的调度与依赖模型更接近“以 Dataset graph 为中心”，而不是传统 Airflow 式“以任务节点为中心”。【推断】

### 3. 强在增量语义由平台承载

官方 incremental transform 文档说明，能否增量运行取决于输入 Dataset 自上次运行后的事务变化：append-only 通常可增量，full rewrite、update/delete 文件等会导致 snapshot。【实时】

这比单纯 `updated_at` 增量更平台化，因为它把增量正确性绑定到 Dataset Transaction、输入 read mode、输出 write mode 和 retention 规则。【推断】

### 4. 强在低码/高码共用底层运行模型

Pipeline Builder 后端会写 transform code 并做 pipeline integrity checks；Pipeline Builder 还能导出到 Java transforms repository，但导出不可逆且部分转换无法导出。【实时】

这说明低码与高码不是完全割裂的两套系统，但也不是无损双向转换。【实时】

---

## 二、它怎么实现

```text
Code Repository
  -> Transform definition
    -> Input / Output contract
    -> Compute engine selection
    -> Incremental / quality / test metadata
      -> Build and schedule
        -> Dataset transaction
          -> Lineage / governance / Ontology consumption
```

### 1. Authoring 层

Code Repositories 把 Git、PR、检查、模板向导、preview/debug 放进 Foundry，使数据生产代码具备工程生命周期。【实时】

### 2. Transform 层

Python 是最完整路径，支持 batch、incremental、共享库、data expectations，以及 single-node/multi-node compute；Java 支持 batch、incremental、unit testing 和共享库；SQL 基于 Spark SQL，但不支持 incremental transforms。【实时】

### 3. Runtime 层

Python transforms 可选 DuckDB、pandas、Polars、Spark。轻量引擎适合单节点，Spark 适合分布式。不同引擎支持的特性不同，需要能力矩阵化。【实时】

### 4. Control Plane 层

Scheduling、repository upgrades、impact analysis、unit tests、data expectations 都不是外围工具，而是高码生命周期的一部分。【实时】

---

## 三、怎么借鉴

### 1. 第一优先级：做 Transform Contract

我们要先定义一个稳定的 transform contract：

- 输入 Dataset 引用
- 输出 Dataset 引用
- 参数定义
- Schema/质量规则
- 执行引擎选择
- 增量语义
- 运行身份与权限边界

没有 contract，代码只是脚本；有 contract，代码才能被平台索引、调度、治理和复用。【推断】

### 2. 第二优先级：做 Dataset Transaction

如果没有 Dataset transaction，增量、回滚、血缘、影响分析都会退化为任务日志和外部约定。【推断】

借鉴方向：

- Dataset 每次写入生成不可变版本。
- 写入模式区分 append、replace、modify/delete。
- Transform runtime 能读取 added/current/previous 视图。
- 调度器基于 Dataset graph 判断增量可行性。

### 3. 第三优先级：统一低码和高码底座

低码 Builder 应生成同一套 transform contract，而不是生成另一套不可治理配置。【推断】

代码导出可以作为升级路径，但不应承诺双向同步。Palantir 官方 export pipeline code 已明确不可逆，且部分转换不能转换。【实时】

### 4. 第四优先级：补齐工程治理

需要把以下能力纳入高码生命周期：

- PR/check/test
- data expectations
- build preview
- upgrade impact analysis
- schedule and data freshness
- lineage and owner notification

否则平台会停留在“可运行脚本集合”，无法达到 Foundry 的生产治理强度。【推断】

---

## 四、建议落地路线

| 阶段 | 目标 | 交付物 |
|---|---|---|
| P0 | 统一 Dataset/Transform 元模型 | Transform contract spec、Dataset version spec、最小 DAG 构建器 |
| P1 | 跑通高码生产链路 | Python/PySpark SDK、Spark runtime、build scheduler、transaction write |
| P2 | 做增量与质量 | added/current/previous read mode、data expectations、pytest/in-memory test harness |
| P3 | 做低码互操作 | Builder IR、低码算子映射、代码导出报告、语义差异标注 |
| P4 | 做平台闭环 | Ontology 绑定、writeback、impact analysis、AIP/code assistant |

---

## 五、当前结论边界

- Palantir 内部 transform 扫描、依赖索引、跨 repository 事件传播机制未公开，当前只能推断。【猜测】
- Pipeline Builder 的内部 IR 未公开，无法确认其与导出 Java code 的完整映射关系。【猜测】
- 复杂增量场景需要真实 Foundry 环境验证，尤其是 retention、schema evolution、UPDATE/DELETE 混合输入。【推断】
