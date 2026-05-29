# 24 — Palantir 高码运行时、计算引擎与依赖管理

**日期：** 2026-05-29
**关联 Issue：** #8
**所属 Epic：** #4
**类型：** 调研记录 / 运行时能力矩阵 / Engine Router 设计输入

---

## 1. 背景

本文件基于 `docs/raw/22-pro-code-source-map.md` 中 #8 指定资料源 S04、S06、S09、S10、S14，并补充 Palantir 官方文档中与依赖管理、Artifact、Spark pin、外部系统扩展相关的资料源。

Palantir Foundry 的高码数据转换不应被简化为“写 Spark 作业”。Python transforms 明确支持 DuckDB、pandas、Polars、Spark 四类 query engine；Java 与 SQL transforms 也分别覆盖强类型/Java 生态与 Spark SQL 场景。【事实】

---

## 2. 可信度规则

| 标签 | 本文含义 | 使用边界 |
|---|---|---|
| 【事实】 | 本轮通过 Palantir 官方文档或当前仓库资料直接确认 | 可作为事实陈述 |
| 【推断】 | 多条【事实】事实组合出的工程判断，官方未直接用同一句话表达 | 可进入架构建议，但需保留推导链 |
| 【猜测】 | 公开资料未披露或证据不足 | 只能作为待验证风险 |

注意：本文使用“事实”标签表示“当前已验证事实”，不是“实时流式计算能力”。

---

## 3. 核心结论

1. Python transforms 是 Foundry 高码数据转换中公开资料最完整的路径，支持 batch、incremental、共享库、data expectations、外部系统访问、单节点与多节点 compute engines。【事实】
2. Python compute engine selection 明确包括 DuckDB、pandas、Polars、Spark；DuckDB/pandas/Polars 属于 single-node lightweight 路径，Spark 属于 distributed compute 路径。【事实】
3. Palantir 官方建议生产 Python transforms 默认优先考虑 Polars；pandas 偏快速迭代和小数据；DuckDB 偏 SQL API 与单节点低延迟；Spark 偏大规模分布式和关键组织级数据基础。【事实】
4. 官方规模建议是 pandas 小于 1GB/100 万行，Polars 与 DuckDB 约 1-50GB/1-2 亿行，PySpark 大于 50GB/2 亿行；同时官方强调这只是经验规则，具体取决于 query shape、schema、filter pushdown、Polars streaming 等因素。【事实】
5. Spark 不是默认更优路径：小中规模任务上 Spark 有启动、资源与调度开销；官方建议只有当数据规模要求，通常超过 50GB 且无法使用 filter pushdown 等优化时再迁移到 Spark。【事实】
6. SQL transforms 使用 Spark SQL，适合过滤、聚合、派生、窗口函数等声明式数据操作，但官方明确 SQL transforms 不支持 incremental transforms。【事实】
7. Java transforms 支持 batch 与 incremental pipelines，提供高层/低层 Dataset API，支持 Java 常用库、单元测试、非结构化文件、共享代码；适合需要 Java 生态、强类型或由 Pipeline Builder 导出到 Java 的场景。【事实】
8. 依赖管理不是裸 `pip install` 或任意 Maven 拉取：Python transforms 使用 `conda_recipe/meta.yaml` 描述 build/run/pip 依赖；推荐通过包面板自动添加可用包和 backing repository；共享 Python 库推荐发布为 Conda library。【事实】
9. Code Repositories 的 Libraries/Artifact settings 支持本地共享库、外部/公共 artifact repositories、Conda/Docker/Maven artifacts，以及依赖 repository 的权限与项目引用联动。【事实】
10. Spark module 可以在 Code Repositories 中按 repository/branch pin 到指定版本，但官方建议仅作为临时措施，最长 pin 期限 90 天，并鼓励使用最新 Spark 以获得性能和安全更新。【事实】
11. 外部系统扩展应优先采用 source-based external transforms；这些扩展支持 credentials/egress/source 配置集中治理、跨 repository 共享连接配置、部分 source 的 Python client、Data Lineage 可视化，并兼容 lightweight external transforms。【事实】
12. 自建 Engine Router 不应只做“数据量 -> Spark/非 Spark”二分，而应同时纳入计算语义、API 风格、增量能力、外部系统访问、依赖可解析性、治理约束、成本与可迁移性。【推断】

---

## 4. 运行时能力矩阵

| 路径 | 计算模型 | 适用场景 | 明确能力 | 明确限制/风险 | 可信度 |
|---|---|---|---|---|---|
| Python + pandas | single-node lightweight | 快速迭代、探索性分析、小数据、依赖 pandas 生态 | Python DataFrame API、启动开销低、生态丰富 | 单线程、内存效率差、官方建议小于 1GB/100 万行 | 【事实】 |
| Python + Polars | single-node lightweight | 生产默认、单节点中等规模数据、列式/lazy 优化友好任务 | lazy query optimization、多线程、列式内存、官方推荐生产默认 | 大规模能力取决于 query shape；memory spilling 标为 limited | 【事实】 |
| Python + DuckDB | single-node lightweight | SQL 风格处理、中等规模、低延迟、单节点性能优先 | SQL engine、lazy optimization、自动内存管理与 spill-to-disk | 无 Python DataFrame API，主要写 raw SQL；规模仍是单节点边界 | 【事实】 |
| Python + PySpark | distributed Spark | 大规模数据、组织级基础数据集、需要 Spark API/分布式可靠性 | 多节点分布式、spill-to-disk、Catalyst optimizer、Spark profiles | 小中数据启动和资源开销高；某些 feature 与 lightweight 差异明显 | 【事实】 |
| SQL transforms | Spark SQL | 声明式 SQL、过滤/聚合/派生/窗口函数、SQL 用户低门槛 | Spark SQL 表达能力、dataset preview、custom transforms profiles | 官方明确不支持 SQL incremental transforms；通用编程能力弱于 Python/Java | 【事实】 |
| Java transforms | Java transforms runtime / Dataset API | 强类型工程、Java 库、复杂工程结构、低码导出后的高码维护 | batch/incremental、Dataset 高低层 API、文件读写、共享代码、单元测试 | 公开资料未给出与 Python engines 等价的 pandas/Polars/DuckDB 选择矩阵 | 【事实】 |
| External transforms | Python transforms + Data Connection source | 访问公网、私网、on-prem、虚拟表或外部 API/DB | source-based 配置、凭据轮换、agent proxy、lineage 可视化、lightweight 兼容 | 需要 source/egress/marking 治理配置；旧 legacy decorator 不应新建依赖 | 【事实】 |

---

## 5. 引擎选择决策

### 5.1 决策优先级

1. 先判断语言与用户心智：纯 SQL 声明式任务优先 SQL transforms；需要 Java 生态或强类型时选 Java；需要最多平台能力与 Python 生态时选 Python。【推断】
2. Python 内部默认从 Polars 开始，除非存在明确 pandas 生态依赖、raw SQL 偏好、或 Spark 分布式需求。【事实】
3. 数据规模不是唯一条件。官方给出的 50GB/2 亿行 Spark 边界是经验值，仍需结合 query 是否可 streaming/lazy、是否 filter pushdown、是否需要全量 materialization、内存峰值和 schema 宽度判断。【事实】
4. 若计算可通过 Polars lazy/streaming、DuckDB spill-to-disk 或 filter pushdown 留在单节点，优先避免 Spark 的启动和资源开销。【推断】
5. 若任务要求 Spark-only 能力，例如完整 Data expectations、source unmarking、read output enforcing schema、allowed run duration、deprecated run-as-user 参数，或需要大规模 shuffle，则应路由到 Spark。【事实】
6. 若要求 SQL incremental transforms，应拒绝或改写为 Python/Java incremental，因为官方明确 SQL 不支持 incremental transforms。【事实】

### 5.2 推荐路由规则草案

| 条件 | 推荐引擎 | 原因 |
|---|---|---|
| 小于 1GB、探索分析、依赖 pandas-only 库 | pandas | 官方定位是快速迭代、小数据与熟悉生态。【事实】 |
| 1-50GB、生产 batch、DataFrame 风格、列式处理 | Polars | 官方推荐生产默认，性能和内存表现优于 pandas。【事实】 |
| 1-50GB、SQL 表达更自然、要求单节点低延迟或 spill | DuckDB | 官方定位为中大单节点 SQL analytical workload，自动 spill。【事实】 |
| 大于 50GB、超过单节点容量、关键基础数据集、大 shuffle | PySpark | 官方定位为 distributed compute at scale。【事实】 |
| 纯 SQL transform 且无需 incremental | SQL transforms | Spark SQL 覆盖常见高级数据操作，门槛低。【事实】 |
| 强类型、Java 库、Pipeline Builder 导出后维护 | Java transforms | Java transforms 官方支持 batch/incremental、Dataset API 和共享代码。【事实】 |
| 外部 API/DB/私网系统访问 | Python external transforms | source-based external transforms 支持连接治理、凭据轮换、agent proxy 和 lineage。【事实】 |

---

## 6. 依赖管理与扩展

### 6.1 Python 依赖

Python transforms 标准项目结构包含 `conda_recipe/meta.yaml`；运行依赖写入 `requirements.run`，默认包含 Python、transforms、transforms-expectations、transforms-verbs 等。【事实】

官方建议额外依赖优先通过 Code Repositories 的 package tab/Library search 自动添加；手动编辑 `requirements` 可能请求不可用版本并导致 Checks 失败。【事实】

若必须 pin 运行时库版本，可以在 `requirements.run` 中指定版本或 `<=` 上界；官方说明 `>=` 版本操作符尚不支持，且操作符后不能有空格。【事实】

若 Conda 不可用但 pip 可用，可以在 `requirements.pip` 中声明 pip dependency；这些依赖安装在 Conda run environment 之上，且 pip section 只适用于 Python transforms repositories，不适用于 Python libraries。【事实】

Foundry Python 版本跟随 Python Software Foundation EOL；截至官方表格，3.10/3.11/3.12 为 supported，3.9 正在 sunset，3.13 coming soon。【事实】

### 6.2 共享库与 Artifact

Code Repositories 允许使用 local/external libraries，并允许在 Foundry 环境内共享自己的代码；Python 与 Java 有不同共享步骤。【事实】

共享 Python 代码的推荐工作流是发布 Python library package，具体是 Conda library；library repository 被 tag 后 checks 通过才发布，消费者不会自动升级到新版本，需要手动升级并重新解析 Conda 环境。【事实】

Artifact repositories 可发布和管理 Conda、Docker、Maven artifacts；适合上传不是以 library authoring 方式产生、也不能通过 external URL 访问的 artifact。【事实】

Artifact settings 的 Libraries tab 可以添加 local repositories 或 external repositories 作为 backing repositories；跨项目 local repository 会增加 project reference，并要求对应 `compass:*` 权限。【事实】

删除或重排 backing repositories 可能破坏使用其中 package 的 transforms builds。【事实】

### 6.3 Spark 与运行时版本

Code Repositories 支持 pin Spark module 到 repository/branch，用于强制特定 Spark 版本；pin 过期最长 90 天，过期后 build 可能失败。【事实】

Spark pin 应被视为兼容性缓冲，而不是长期运行时治理策略；自建平台应提供“临时 pin + 到期提醒 + 升级验证”的闭环，而不是永久锁死 runtime。【推断】

### 6.4 外部系统扩展

source-based external transforms 是官方推荐的外部系统访问方式，相比 legacy external transforms 支持私网/on-prem、凭据轮换不改代码、跨 repository 共享连接配置、部分 source 的 Python client、简化治理与 Data Lineage 可视化。【事实】

External transforms 兼容 single-node lightweight compute；小中数据外部访问场景可以不用 Spark sidecar，除非需要私网 agent proxy 或更复杂连接形态。【事实】

---

## 7. 对自建 Engine Router 的建议

1. Router 输入必须包含：数据规模、行数、schema 宽度、预估 shuffle/聚合形态、是否需要全量加载、是否可 predicate/filter pushdown、是否可 lazy/streaming、增量语义、外部系统访问、依赖集合、治理/marking 操作、SLA/成本目标。【推断】
2. 默认策略建议是 `Polars -> DuckDB/pandas -> Spark`，其中 Polars 作为生产 DataFrame 默认，DuckDB 作为 SQL/低延迟单节点路径，pandas 作为探索和生态兼容路径，Spark 作为规模或 Spark-only feature 兜底。【推断】
3. Router 应把 SQL transforms 当作“Spark SQL 专用语言路径”，而不是与 DuckDB SQL 同级的本地 query engine；SQL transforms 缺少 incremental 能力，不能承诺所有 Dataset transform 语义。【推断】
4. Router 应支持“解释型决策”：输出为什么选该 engine、哪些官方能力/限制触发该选择、何时应重新路由，例如数据超过 50GB、出现 Spark-only feature、或依赖无法在 lightweight 环境解析。【推断】
5. Router 应实现依赖可解析性预检：Conda package 是否在 backing repository 中、pip 是否只用于 Python transforms、Java/Maven artifact 是否可访问、Spark pin 是否将过期。【推断】
6. Router 应保留迁移路径：官方建议可先用 DuckDB + SQLFrame 初步评估 Spark 到单节点迁移影响；自建系统可用影子运行/抽样 benchmark 验证迁移收益。【事实】
7. 对外部系统访问，Router 不应把 credential/egress 写入代码生成结果，而应抽象为 source reference 与 policy reference，并把 governance 生命周期交给平台资源管理。【推断】
8. 对 Java transforms，自建 Router 只能基于语言/生态/强类型/导出维护选择 Java；公开资料不足以建立 Java 内部多 engine 自动选择模型。【事实】

---

## 8. 证据缺口

1. Palantir 公开文档没有披露 Python lightweight 的底层容器调度实现、资源隔离细节、cache 策略、worker 生命周期或 engine 启动过程。【猜测】
2. 公开资料未给出 Java transforms 与 Spark/非 Spark 内部 runtime 的精确映射，也未给出 Java 侧等价于 pandas/Polars/DuckDB 的 engine selection 表。【猜测】
3. 公开资料没有披露 Code Repositories package tab 的完整 dependency solver、channel priority、lockfile 生成和冲突处理算法。【猜测】
4. SQL transforms 文档确认基于 Spark SQL且不支持 incremental，但未披露 SQL transform 与 Spark profile/runtime version 的全部配置边界。【猜测】
5. External transforms 的 source-based 治理能力已公开，但其运行时网络路径、agent proxy 细节与失败重试语义需要真实 Foundry 环境验证。【猜测】
6. 官方 engine 规模阈值是经验规则，不是严格 SLA；自建 Engine Router 仍需要在目标硬件、数据格式和 workload 上做 benchmark。【推断】

---

## 9. 参考来源

| 编号 | 来源 | URL | 本文使用点 |
|---|---|---|---|
| R01 | Python transforms Overview | https://www.palantir.com/docs/foundry/transforms-python/lightweight-overview | Python 是 full-featured transform 路径，支持 batch/incremental、共享库、expectations、compute engines、外部系统 |
| R02 | Python compute engine selection | https://www.palantir.com/docs/foundry/transforms-python/compute-engines | DuckDB/pandas/Polars/Spark、lightweight vs distributed、feature support、规模建议 |
| R03 | Python transforms basics | https://www.palantir.com/docs/foundry/transforms-python/transforms | Transform 三要素、single-node 默认、PySpark 适用边界、transactionality |
| R04 | Supported languages | https://www.palantir.com/docs/foundry/building-pipelines/supported-languages | SQL/Python/Java 能力比较、file access、TLLV、incremental、previews、profiles |
| R05 | Java transforms Overview | https://www.palantir.com/docs/foundry/transforms-java/overview | Java transforms batch/incremental、Dataset APIs、共享代码、Java 库 |
| R06 | SQL transforms Overview | https://www.palantir.com/docs/foundry/transforms-sql/overview | SQL 基于 Spark SQL，不支持 incremental transforms |
| R07 | Python project structure | https://www.palantir.com/docs/foundry/transforms-python/project-structure | `meta.yaml`、Conda dependencies、pip section、版本 pin 限制 |
| R08 | Python version support | https://www.palantir.com/docs/foundry/transforms-python/python-versions | Foundry Python 版本支持与 EOL |
| R09 | Code Repositories Libraries | https://www.palantir.com/docs/foundry/code-repositories/libraries | local/external libraries 与 Python/Java 共享入口 |
| R10 | Share Python libraries | https://www.palantir.com/docs/foundry/transforms-python/share-python-libraries | Conda library 发布、tag 发布、消费者手动升级、权限 |
| R11 | Artifact repositories Overview | https://www.palantir.com/docs/foundry/code-repositories/artifact-repositories-overview | Conda/Docker/Maven artifact 发布与管理 |
| R12 | Artifact settings | https://www.palantir.com/docs/foundry/code-repositories/artifact-settings | backing repositories、本地/外部 artifact、权限与 project references |
| R13 | Pin Spark modules in-platform | https://www.palantir.com/docs/foundry/code-repositories/module-pinning | Spark module pin、90 天限制、CI 版本选择 |
| R14 | External transforms | https://www.palantir.com/docs/foundry/data-connection/external-transforms | source-based external transforms、governance、lightweight compatibility、agent proxy |
