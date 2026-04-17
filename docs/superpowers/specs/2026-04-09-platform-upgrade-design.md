# 大数据平台升级设计文档
# 参照 Palantir Foundry 数据工程能力的迭代演进路线

> 创建日期：2026-04-09
> 背景：现有平台为 DolphinScheduler + Spark/Flink + Paimon/HDFS/Hologres/StarRocks
> 已有工作：EOS Dataset（数据资产控制面，P0 实现中）
> 数据工程边界：Sync 数据集成 → Dataset 数据加工 → Object Set 写入 + User Edit 变更合并

---

## 一、Palantir 数据工程能力全景

### 模块地图

Palantir Foundry 数据工程由 17 个核心模块组成，按职责分为 5 个层次：

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  可观测层  │ M11 监控与告警    │ M12 数据健康大盘                              │
├──────────────────────────────────────────────────────────────────────────────┤
│  治理层    │ M8  数据目录      │ M9  血缘追踪   │ M10 治理与访问控制            │
│            │ M15 数据测试框架  │ M16 环境管理   │ M17 资源管理                  │
├──────────────────────────────────────────────────────────────────────────────┤
│  加工层    │ M4  在线开发      │ M5  数据转换   │ M6  构建调度  │ M7  质量      │
│            │ M13 流式数据链路  │ M14 增量计算框架│                              │
├──────────────────────────────────────────────────────────────────────────────┤
│  资产层    │ M1  数据接入      │ M2  数据集管理 │ M3  对象集                    │
│            │ (Sync/Stream)    │ (Dataset)     │ (Object Set) │ M3b User Edit  │
└──────────────────────────────────────────────────────────────────────────────┘
```

> **批流关系说明**：M13（流式链路）不是 M5（数据转换）的子集，而是与批处理并列的独立计算范式。M14（增量计算）是连接批处理和流式处理的桥梁——增量批处理在延迟和成本之间取得平衡，适合 10 分钟以上时效的场景；流式处理适合秒级时效场景。

---

## 二、各模块能力分级（L1→L4）

每个模块定义 4 个能力等级：
- **L1（基础可用）**：核心场景跑通，手动操作为主
- **L2（生产就绪）**：自动化完善，支持日常生产
- **L3（能力增强）**：高级特性，深度集成，效率提升
- **L4（完整对标）**：全量对标 Palantir，AI 辅助，全自动化

---

### M1：数据接入（Sync / Data Connection）

**核心价值**：将外部异构数据源统一纳入数据工程链路，输出为受版本管控的 Dataset。

| 等级 | 能力内容 |
|------|---------|
| **L1** | 主流 JDBC 接入（MySQL/PG/Oracle）；全量同步；手动触发；输出原始 Dataset；基础连接配置 UI |
| **L2** | 增量同步（CDC/Watermark）；定时调度触发；Schema 自动推断；接入状态监控；同步任务版本化（配置可回滚）|
| **L3** | 对象存储接入（S3/OSS）；API 接入（REST/GraphQL）；消息队列接入（Kafka/Pulsar）；字段级脱敏配置；接入失败自动重试与告警 |
| **L4** | 100+ 预置连接器；SaaS 系统接入（Salesforce/SAP）；流批一体接入；AI 辅助 Schema 映射；接入质量自动评分 |

**与 EOS Dataset 集成点**：同步任务 = 特殊 Pipeline，输出通过 WriteSession 写入 Dataset，自动注册静态血缘（外部源 → Dataset）。

> **流式接入**（提前至 L2）：消息队列接入（Kafka/Pulsar）在本模块 L2 即启动，输出为 Stream Dataset（见 M13），不等到 L3。流批接入在 M1 统一管理，但输出目标不同：批量同步 → 批处理 Dataset，流式接入 → Stream Dataset。

---

### M2：数据集管理（Dataset Service）

**核心价值**：数据资产的版本化、可信化管理，是整个平台的数据可信基础。

> ⚠️ **当前状态**：EOS Dataset 已有完整设计，P0 实现中，P1 待实现。以下直接映射到现有规划。

| 等级 | 能力内容 | EOS 现有规划 |
|------|---------|------------|
| **L1** | 版本/分支/Snapshot；WAP 基础流程；静态血缘；基础 RBAC；事件通知 | P0 M1 |
| **L2** | 动态血缘（Version 级）；Schema 管理；质量门禁；SQL Console；增量读；Schema Diff | P0 M2 + P1 M2 |
| **L3** | 字段级血缘；标记传播（PII 随血缘流动）；多引擎读写（Flink+Spark）；Files 管理 | P1 M3 |
| **L4** | 非结构化数据（Media Set）；外部表纳管；AI 辅助 SQL；高级列统计 | P2 待规划 |

> **Stream Dataset 补充**：流式数据集是批处理 Dataset 的特殊变体，在 M13 独立定义。Stream Dataset 与批处理 Dataset 共用 EOS Dataset 的元数据模型（datasetId/Branch/Schema），但版本化语义不同——流式数据以 offset/checkpoint 而非 Snapshot 作为版本锚点，WAP 流程对流式数据集做适配（Write=流式写入检查点，Audit=流式质量检测，Publish=冻结 checkpoint 生成发布版本）。

---

### M3：对象集（Object Set）+ M3b：用户变更（User Edit）

**核心价值**：Dataset 是数据工程师的世界，Object Set 是业务用户的世界——Object Set 将加工后的 Dataset 转化为可查询、可操作的业务对象集合；User Edit 则将用户在业务层的修改回写并合并到数据链路。

#### M3：Object Set

| 等级 | 能力内容 |
|------|---------|
| **L1** | Object Type 定义（字段映射关系）；Object Set Writer Pipeline（Dataset → 对象存储）；基础对象查询 API |
| **L2** | 增量写入（只更新变更对象）；对象版本管理（与 Dataset Version 关联）；对象血缘注册；多 Dataset 合并为一个 Object Type |
| **L3** | 对象索引与全文检索；Object Set 过滤/聚合 API；对象变更事件通知；跨 Object Type 关联查询 |
| **L4** | 动态 Object Set（基于实时查询生成）；对象图谱（Object Graph）；AI 辅助对象关系推断 |

#### M3b：User Edit

| 等级 | 能力内容 |
|------|---------|
| **L1** | 用户变更采集接口；变更写入专属 Dataset（user_edit branch）；手动触发 Edit Merge Pipeline |
| **L2** | 变更校验（格式、业务规则）；冲突检测（user_edit 与主链路数据冲突）；审计日志（谁改了什么）；定时/触发式合并调度 |
| **L3** | 冲突解决策略配置（user 优先 / 系统优先 / 人工审批）；变更影响分析（合并后影响哪些下游 Dataset）；变更回撤 |
| **L4** | 批量变更操作；变更聚合（多用户变更合并为一次提交）；AI 辅助冲突解决建议 |

---

### M4：在线开发（Code Repository / Jupyter）

**核心价值**：让工程师/分析师在平台内完成从开发到验证到发布的完整闭环，不再依赖本地环境。

> **选型**：JupyterHub（多租户）+ 平台 SDK（eos-dataset-sdk），不自研 IDE。

| 等级 | 能力内容 |
|------|---------|
| **L1** | JupyterHub 多用户部署；平台 SDK 预装（dataset.read/write/publish）；基础沙箱（Kernel 内小数据执行）；Notebook 与 Git 同步 |
| **L2** | 大数据沙箱（提交 Spark 集群，资源限额隔离）；ReadSession 自动版本锁定；Pipeline Snapshot（Notebook + 依赖 Dataset 版本三元组）；一键触发 WAP 发布；协作开发（PR/Code Review） |
| **L3** | 本地开发工具链（SDK CLI，本地预览 transforms）；自定义内核环境（conda/pip 隔离）；Notebook 执行历史与对比；沙箱数据采样策略（按比例/按条件） |
| **L4** | AI 辅助代码生成（自然语言→PySpark/SQL）；代码质量检查（自动 lint + 安全扫描）；可视化调试（数据流可视化）；VS Code 插件集成 |

**与调度系统（DolphinScheduler）的分工**：
- JupyterHub = **开发态**（在线写、调试、验证，资源受限）
- DolphinScheduler = **生产态**（定时调度、依赖编排，全量资源）
- Notebook 导出为生产 Pipeline 代码，两侧共用 EOS Dataset API

---

### M5：数据转换（Transforms / Pipeline Builder）

**核心价值**：为不同技术水平的用户提供分层的数据转换工具——从拖拽配置到代码编写，统一输入输出为 Dataset。

| 等级 | 能力内容 |
|------|---------|
| **L1** | Spark SQL Pipeline（代码方式）；Python Transform（PySpark）；全量模式；Pipeline 依赖声明（输入/输出 Dataset 注册）|
| **L2** | 可视化 Pipeline Builder（低代码拖拽，面向分析师）；内置算子库（清洗/聚合/Join/Union/Pivot）；Transform 可复用组件；参数化 Pipeline（运行时注入参数）|
| **L3** | Pipeline 依赖图可视化；跨 Pipeline 公共逻辑提取（Library）；批流 Join（批量 Dataset Lookup + 流式数据关联）|
| **L4** | AI 辅助转换逻辑生成；KNN Join 等高级算子；多语言 Transform（Java/Scala）；Transform 性能分析与优化建议 |

> **注**：增量计算（`@incremental`）独立为 M14；Flink 流式 Transform 独立为 M13。M5 专注于批处理转换能力。

---

### M6：构建调度（Build System / Scheduling）

**核心价值**：自动化管理 Pipeline 的执行计划，保证数据按时、按依赖顺序、高效地产出。

| 等级 | 能力内容 |
|------|---------|
| **L1** | 手动触发构建（Force Build）；构建历史（状态/耗时/日志）；基础依赖声明（输入 Dataset 就绪才执行） |
| **L2** | 定时调度（Cron）；事件触发（上游 Dataset 新版本发布 → 自动触发下游 Build）；构建依赖图（自动推导拓扑顺序）；构建失败重试与告警 |
| **L3** | 并发控制（同一 Dataset 串行写入）；回填（Backfill，补跑历史数据）；构建范围选择（仅选中/含上游/含下游）；资源规格配置（预设/自定义） |
| **L4** | 跨引擎统一调度（Spark + Flink + 流式 Pipeline 统一编排）；成本感知调度（低峰期执行大作业）；AI 调度优化；SLA 驱动调度 |

> **流式 Pipeline 生命周期**（补充）：流式 Pipeline 不同于批处理——它是持续运行的常驻进程，调度语义为"启动/停止/暂停/恢复"而非"触发一次"。L2 起支持流式 Pipeline 的状态管理：`RUNNING` / `PAUSED` / `STOPPED` / `FAILED`；L3 支持流式 Pipeline 滚动升级（不停机更新逻辑）和 Savepoint 恢复（从 Flink Savepoint 恢复处理进度）。流式调度细节见 M13。

---

### M7：数据质量（Checks / Data Health）

**核心价值**：在数据流动的每个关键节点设置质量门禁，阻断坏数据向下游传播。

| 等级 | 能力内容 |
|------|---------|
| **L1** | Schema 校验（字段存在性、类型校验）；空值率检查；基础规则配置 UI；WAP 发布前质量门控 |
| **L2** | 唯一性检查；自定义 SQL 规则；行数变化率异常检测；检查结果历史追踪；质量分数；**流式数据延迟检测**（消息堆积/处理延迟超阈值告警）|
| **L3** | 列级统计（分布/异常值检测）；跨 Dataset 一致性检查；质量规则模板库；检查与血缘联动；**流式乱序/重复数据检测** |
| **L4** | AI 辅助规则生成；**流式实时质量监控**（窗口级质量评分，秒级反馈）；质量 SLA 告警；数据漂移检测 |

---

### M8：数据目录（Catalog / Compass / Discovery）

**核心价值**：让数据可被发现、可被理解，解决"数据存在但找不到、找到但看不懂"的问题。

| 等级 | 能力内容 |
|------|---------|
| **L1** | Dataset 列表（按域/Owner/标签过滤）；基础搜索（名称/描述全文）；Schema 浏览；Owner/SLA/分级元数据展示 |
| **L2** | 标签体系（多维度分类）；收藏与订阅；使用频率统计（热门 Dataset）；相似 Dataset 推荐；字段级描述编辑 |
| **L3** | 血缘可视化（交互式血缘图）；数据地图（domain 维度全局视图）；变更影响分析入口；Dataset 质量健康度展示；数据字典（业务术语与字段关联） |
| **L4** | AI 辅助数据发现（自然语言搜索）；自动摘要生成（AI 描述 Dataset 内容）；数据推荐引擎（基于使用模式推荐相关数据）；外部 Catalog 联邦查询 |

---

### M9：血缘追踪（Lineage）

> ⚠️ **注意**：M9 与 EOS Dataset（M2）高度重叠，EOS Dataset 已覆盖 L1-L2 血缘能力。此处聚焦于独立于 Dataset 的血缘服务扩展。

| 等级 | 能力内容 |
|------|---------|
| **L1** | 任务级/表级静态血缘；Pipeline → Dataset 依赖关系；基础上下游影响查询 |
| **L2** | 动态血缘（Version 级，精确到某次 Build 读了哪个版本产出哪个版本）；跨 Pipeline 全链路血缘；血缘存储与分页检索（支持 1M+ 血缘边）|
| **L3** | 字段级血缘（Column Lineage）；血缘与 Schema 变更联动（字段重命名自动追踪）；血缘健康检查（孤立 Dataset 检测）；血缘 API（供外部系统消费）|
| **L4** | 跨系统血缘（打通外部 BI/数仓的血缘）；血缘影响分析自动化（Schema 变更前自动评估影响范围）；AI 辅助血缘修复（断裂血缘自动推断） |

---

### M10：治理与访问控制（Governance / Markings / RBAC / PBAC）

| 等级 | 能力内容 |
|------|---------|
| **L1** | 基础 RBAC（角色：Owner/Editor/Viewer）；Dataset 级权限控制；敏感标记（PII 等）手动打标 |
| **L2** | 标记随血缘传播（上游打 PII 标记，下游衍生 Dataset 自动继承）；数据脱敏（标记 + 读取时脱敏）；权限申请流程（PBAC 基础：申请目的 → 审批 → 临时授权） |
| **L3** | 字段级权限控制（Restricted View，列级可见性）；数据生命周期管理（保留策略 + 定时清理）；合规报告（谁访问了什么敏感数据）；敏感数据扫描器（自动识别 PII 字段） |
| **L4** | 目的驱动访问控制（PBAC 完整实现）；隐私计算支持（联邦学习/安全多方计算）；跨组织数据共享治理；AI 辅助权限审计 |

---

### M11：监控与告警（Monitoring / Alerting）

| 等级 | 能力内容 |
|------|---------|
| **L1** | 构建失败告警（邮件/IM）；基础指标采集（构建耗时/成功率）；手动查看 Pipeline 状态 |
| **L2** | SLA 监控（数据新鲜度告警）；构建依赖链路状态大盘；告警规则配置（阈值/频率）；告警收敛（防重复骚扰）|
| **L3** | 端到端数据时效监控（从接入到产出全链路延迟）；资源使用率监控（Spark/Flink 资源利用率）；异常检测（构建时间突增告警）；告警与血缘联动（定位影响范围）|
| **L4** | 预测性告警（AI 预测潜在 SLA 违规）；成本监控与优化建议；多维度 SLA 报告（按 Domain/Owner/优先级） |

---

### M12：数据健康大盘（Data Health Dashboard）

| 等级 | 能力内容 |
|------|---------|
| **L1** | 单 Dataset 健康状态（最新版本时间、质量分数、构建状态）；手动刷新 |
| **L2** | 全平台数据健康总览（按 Domain 汇总）；不健康 Dataset 列表与优先级排序；健康趋势历史 |
| **L3** | 数据健康与 SLA 联动；自动化健康修复建议；Owner 视角个性化大盘；健康评分维度自定义 |
| **L4** | AI 驱动数据健康诊断（根因分析）；预测性健康评估；跨组织数据健康对比 |

---

### M13：流式数据链路（Stream Pipeline）

**核心价值**：将数据时效从分钟级压缩到秒级（< 15 秒），实现实时 Object Set 更新和流式事件驱动决策。

#### 流式数据模型

Palantir Foundry 的流式链路围绕 **Stream Dataset** 这一核心抽象构建：

```
外部流源（Kafka/Pulsar/Kinesis）
    ↓  流式接入（Source Connector）
Stream Dataset（hot buffer + cold storage 双层）
    │  ├── hot buffer：内存级低延迟访问，保留最近 N 秒/分钟数据
    │  └── cold storage：历史数据持久化（Paimon/对象存储），可 Time Travel
    ↓  流式 Transform（Flink Job）
Stream Dataset（加工后）
    ↓  流式 Object Set Writer
Object Set（< 15 秒延迟更新）
```

**Stream Dataset 与批处理 Dataset 的关键区别**：

| 维度 | 批处理 Dataset | Stream Dataset |
|------|--------------|----------------|
| 版本锚点 | Snapshot ID（原子提交） | Checkpoint ID / Offset（连续推进） |
| WAP 语义 | Write → Audit → Publish（离散） | 持续写入 → 周期性 Checkpoint 校验 → 发布冻结版本 |
| 读取语义 | 按版本读取历史快照 | 订阅消费 / 按时间窗口读取 |
| GC 策略 | 基于保留天数 | 基于 hot buffer 时间窗口 + cold 保留策略 |
| 血缘粒度 | Version 级（精确到某次 Build） | Checkpoint 级（精确到某个处理进度） |

#### 能力分级

| 等级 | 能力内容 |
|------|---------|
| **L1** | Kafka/Pulsar Source Connector；Stream Dataset 基础写入（hot buffer）；Flink Job 基础框架（启动/停止）；流式 Pipeline 生命周期管理（RUNNING/PAUSED/FAILED 状态） |
| **L2** | hot buffer + cold storage 双层存储；流式 Checkpoint 管理（Flink Savepoint 集成）；流式 Schema 推断与校验；流式 Object Set 写入（低延迟更新）；流式血缘注册（Checkpoint 级）；流式 Pipeline 失败自动重启与告警 |
| **L3** | 流式滚动升级（不停机更新 Flink 逻辑，基于 Savepoint 恢复）；窗口操作算子（Tumbling/Sliding/Session Window）；流批 Join（流式数据与批量 Dataset Lookup）；流式数据 Time Travel（按时间戳查询历史流数据）；多流 Join（两条流的事件关联） |
| **L4** | Exactly-once 端到端语义（Source → Sink）；动态 Schema 演进（流式数据 Schema 变更无停机处理）；流式 ML 推理集成（实时特征计算 + 模型推断）；流式复杂事件处理（CEP，Pattern Detection） |

#### 与批处理的协同

```
批处理链路（分钟级/小时级）：
  M1 Sync → 批 Dataset → M5 Transform → 批 Dataset → M3 Object Set

流式链路（秒级）：
  M13 Stream Source → Stream Dataset → Flink Transform → Stream Dataset → M3 Stream Object Set

流批融合（M13 L3）：
  Stream Dataset（实时特征）
       +                      →  Flink Lookup Join  → 增强 Stream Dataset
  批 Dataset（历史维度表）
```

---

### M14：增量计算框架（Incremental Compute）

**核心价值**：批处理 Pipeline 的效率倍增器——不重算没变化的部分，将大数据量 Pipeline 的执行时间从小时级压缩到分钟级，同时降低计算成本。

#### 核心概念

增量计算是批处理和流式处理之间的"中间地带"：适合 **延迟 10 分钟~1 小时**、**数据量大但每次变化比例小**的场景。

```
全量计算（当前）：
  每次运行 = 读取全量输入 → 计算全量 → 覆写全量输出
  成本：O(全量数据)，每次都一样贵

增量计算（目标）：
  首次运行 = 全量计算（建立基线）
  后续运行 = 读取变化部分 → 增量计算 → Append/Upsert 到输出
  成本：O(变化数据)，数据稳定后接近零成本
```

#### 事务类型与增量安全性

Palantir 定义了 4 种写入事务类型，增量计算必须感知并正确处理：

| 事务类型 | 语义 | 增量处理策略 |
|---------|------|------------|
| `APPEND` | 只追加新记录，不修改历史 | 安全增量：只处理新增 Snapshot 的 delta 文件 |
| `UPDATE` | 修改存在记录（Upsert） | 需 Upsert 算子；必须处理 +I/+U/-U 变更记录 |
| `SNAPSHOT` | 全量覆写（输入被完全替换） | 强制触发全量重算，不可增量 |
| `DELETE` | 行级删除 | 需感知 -D 标记；Paimon changelog 原生支持 |

#### 能力分级

| 等级 | 能力内容 |
|------|---------|
| **L1** | 增量模式声明（Pipeline 标记为 incremental）；APPEND 事务类型的基础增量读（只读 delta）；首次全量建基线；增量 Build 历史记录（记录每次增量的输入 offset 范围）|
| **L2** | 增量安全性自动判断（分析输入事务类型，自动决定是否可增量）；SNAPSHOT 输入触发强制全量回退；UPDATE 事务增量 Upsert 支持；增量 Build 与 EOS Dataset ReadSession 协同（版本锁定输入 delta 范围）|
| **L3** | 依赖感知增量（Build Graph 中只重算受影响的子图）；增量 Join 优化（一侧全量 + 另一侧增量的 Lookup Join）；增量聚合（SUM/COUNT 等聚合算子的增量维护）；增量失败降级（增量失败自动回退全量重算）|
| **L4** | 增量代价估算（预判增量 vs 全量哪个更划算，自动选择）；细粒度增量（分区级增量，只处理变化的分区）；跨引擎增量协同（Spark 增量结果输入到 Flink 流式处理）；AI 辅助增量优化建议 |

#### 与 EOS Dataset 的集成

```
增量 Build 执行时序：
1. Pipeline 框架层 → ReadSession.resolve(inputDataset, branch, "LATEST")
   → 返回 currentSnapshotId
2. 框架层查询上次成功 Build 的 snapshotId（lastSuccessSnapshotId）
3. 计算 delta = currentSnapshotId - lastSuccessSnapshotId
   （通过 Paimon 的 Consumer ID + increment scan 实现）
4. 仅读取 delta 范围的数据文件
5. 增量计算 → WriteSession.complete() → 登记新 Version
6. 下次 Build 的 lastSuccessSnapshotId = 本次 outputSnapshotId
```

---

### M15：数据测试框架（Data Testing / Expectations）

**核心价值**：让数据工程师像测试代码一样测试数据转换逻辑——在开发阶段发现问题，而不是在生产数据质量门禁时才暴露。

> **与 M7（质量门禁）的区别**：M7 是运营态的数据质量检查（数据产出后检查），M15 是开发态的测试断言（Transform 逻辑的单元/集成测试，在 CI/CD 阶段执行）。

| 等级 | 能力内容 |
|------|---------|
| **L1** | Transform 输出断言（assert 输出 Schema 符合预期）；基于样本数据的本地测试（小数据集验证 Transform 逻辑）；测试失败阻断 Pipeline 发布 |
| **L2** | 参数化测试（多组输入/输出对验证同一 Transform）；增量 Transform 测试（验证增量逻辑的正确性，含边界 Case）；测试报告（覆盖率、失败详情）；测试与 CI/CD 集成（PR 合并前自动执行） |
| **L3** | 数据契约（Data Contract）：上下游 Pipeline 之间的 Schema + 语义约定，变更时自动检查是否破坏契约；跨 Pipeline 集成测试；Fixture 管理（测试用样本数据集版本化管理）|
| **L4** | AI 辅助测试用例生成（从 Transform 逻辑自动生成边界 Case）；变异测试（Mutation Testing，验证测试充分性）；生产数据回放测试（用生产 Snapshot 跑历史 Transform 验证回归）|

---

### M16：环境管理（Environment Management）

**核心价值**：统一管理 dev/staging/prod 三套环境的配置、数据、Pipeline 版本，让环境切换安全、可审计、一键完成。

> **与 EOS Dataset Branch 的关系**：Branch 解决了数据的环境隔离，M16 在此基础上统一管理数据 + Pipeline 代码 + 计算资源配置的整体环境状态。

| 等级 | 能力内容 |
|------|---------|
| **L1** | 环境定义（dev/prod 两套）；Pipeline 代码与环境绑定（dev 分支代码 ↔ dev 环境）；环境配置差异展示（哪些配置不同）|
| **L2** | 三套环境（dev/staging/prod）；环境晋级（dev → staging → prod 的标准化流程）；环境配置版本化（配置变更可回滚）；环境间数据同步（将 prod 数据的一个 Snapshot 同步到 staging 用于测试）|
| **L3** | 多人并发开发（每人独立 feature 环境，类 Git Branch）；环境间 diff（代码+数据+配置的全维度对比）；临时环境（按需创建/销毁，节省资源）|
| **L4** | 环境蓝绿切换（零停机切换 prod 环境）；环境模板（标准化新环境创建）；AI 辅助环境问题诊断 |

---

### M17：资源管理（Compute Resource Management）

**核心价值**：保证关键 Pipeline 按时完成，同时控制计算成本，避免资源竞争导致的 SLA 违规。

| 等级 | 能力内容 |
|------|---------|
| **L1** | 基础资源规格配置（CPU/内存预设档位）；Pipeline 资源申报（声明预期资源需求）；资源使用记录（每次 Build 的实际消耗）|
| **L2** | 资源配额管理（Domain/Team 级资源限额）；优先级队列（高优先级 Pipeline 优先获取资源）；资源超用告警；批流资源池隔离（流式 Pipeline 占用独立资源池，不影响批处理）|
| **L3** | 动态资源调整（Build 执行中按需扩缩 Executor）；成本归因（按 Domain/Owner/Pipeline 分摊计算成本）；资源使用趋势分析；空闲资源回收策略|
| **L4** | 成本感知调度（低优先级 Job 在低峰期执行）；Spot 实例支持（利用低成本抢占式资源）；AI 资源需求预测（根据输入数据量自动推荐资源规格）|

---

## 三、迭代节奏设计

### 设计原则

> **每一个迭代都覆盖全量模块，从最简版（L1）开始建设，逐步推进到完整能力（L4）。**
> 每次迭代交付一个"端到端可用"的数据工程闭环，而非单模块的深度堆砌。

### 迭代 I1：基础闭环（全模块 L1）

**目标**：数据从外部源流入、经过加工、产出到对象层，全链路可追踪、可审计。

| 模块 | I1 交付内容 | 依赖 |
|------|-----------|------|
| M1 Sync | JDBC 全量接入；手动触发；输出批处理 Dataset | M2 L1 |
| M2 Dataset | EOS Dataset P0（版本/分支/WAP/基础血缘/RBAC） | - |
| M3 Object Set | Object Type 定义；Object Set Writer Pipeline；基础查询 API | M2 L1 |
| M3b User Edit | 变更采集接口；写入 user_edit Dataset；手动触发合并 | M2 L1 |
| M4 在线开发 | JupyterHub 部署；平台 SDK 预装；基础沙箱执行 | M2 L1 |
| M5 Transforms | Spark SQL/PySpark Pipeline；全量模式；依赖声明 | M2 L1 |
| M6 调度 | 手动触发；构建历史；基础依赖声明 | M5 L1 |
| M7 质量 | Schema 校验；空值率；WAP 门控（批处理） | M2 L1 |
| M8 目录 | Dataset 列表；基础搜索；Schema 浏览 | M2 L1 |
| M9 血缘 | 任务级静态血缘（含 M2 L1 能力） | M2 L1 |
| M10 治理 | 基础 RBAC；敏感标记手动打标 | M2 L1 |
| M11 监控 | 构建失败告警；基础指标（批处理） | M6 L1 |
| M12 健康大盘 | 单 Dataset 健康状态 | M7 L1 |
| M13 流式链路 | Kafka Source；Stream Dataset 基础写入；Flink Job 启停 | M2 L1 |
| M14 增量计算 | APPEND 增量读；首次全量基线；增量 Build 历史 | M2 L1, M5 L1 |
| M15 数据测试 | Transform 输出断言；样本数据本地测试 | M5 L1 |
| M16 环境管理 | dev/prod 环境定义；Pipeline 与环境绑定 | M2 L1 |
| M17 资源管理 | 基础资源规格配置；资源使用记录 | M6 L1 |

**验收标准**：
- 批处理：外部 DB → 原始 Dataset → 加工 Dataset → Object Set，端到端血缘可追踪
- 流式：Kafka → Stream Dataset → Flink Transform → Stream Object Set，延迟 < 1 分钟（I1 不要求 < 15 秒）
- 增量：同一批处理 Pipeline 支持全量/增量两种模式切换

---

### 迭代 I2：生产就绪（全模块 L2）

**目标**：平台从"能跑"升级为"可靠地跑"，自动化替代手动操作，支持日常生产使用。

| 模块 | I2 核心增量 |
|------|-----------|
| M1 Sync | 增量同步（CDC）；定时调度；Schema 推断；**Kafka 流式接入** |
| M2 Dataset | EOS Dataset P1（动态血缘/Schema Diff/增量读/SQL Console） |
| M3 Object Set | 增量写入；对象版本管理；对象血缘注册 |
| M3b User Edit | 变更校验；冲突检测；审计日志；定时合并调度 |
| M4 在线开发 | 大数据沙箱（Spark 集群）；Pipeline Snapshot；WAP 一键发布；协作 PR |
| M5 Transforms | 低代码 Pipeline Builder；内置算子库；可复用组件 |
| M6 调度 | 事件触发调度；依赖图自动推导；失败重试；**流式 Pipeline 状态管理** |
| M7 质量 | 唯一性检查；自定义 SQL 规则；质量历史追踪；**流式延迟检测** |
| M8 目录 | 标签体系；收藏订阅；使用频率统计 |
| M9 血缘 | 动态血缘（Version 级）；全链路血缘；**流式 Checkpoint 级血缘** |
| M10 治理 | 标记传播；数据脱敏；权限申请流程 |
| M11 监控 | SLA 监控；状态大盘；**流式 Pipeline 监控**；告警规则配置 |
| M12 健康大盘 | 全平台健康总览；不健康 Dataset 优先级列表 |
| M13 流式链路 | hot buffer + cold 双层；Checkpoint 管理；流式 Schema 校验；流式 Object Set 写入（< 15s）|
| M14 增量计算 | 增量安全性自动判断；SNAPSHOT 触发全量回退；UPDATE 事务 Upsert |
| M15 数据测试 | 参数化测试；增量逻辑测试；CI/CD 集成 |
| M16 环境管理 | 三套环境（dev/staging/prod）；环境晋级流程；数据同步 |
| M17 资源管理 | 资源配额；优先级队列；批流资源池隔离 |

---

### 迭代 I3：能力增强（全模块 L3）

**目标**：提升效率、深化治理，服务更大规模的数据工程团队。

| 模块 | I3 核心增量 |
|------|-----------|
| M1 Sync | 对象存储/API 接入；字段级脱敏 |
| M2 Dataset | EOS Dataset P1 收尾（字段级血缘/标记传播/多引擎读写） |
| M3 Object Set | 对象检索；Object Set 过滤聚合 API；跨 Object Type 关联 |
| M3b User Edit | 冲突解决策略配置；变更影响分析；变更回撤 |
| M4 在线开发 | 本地开发工具链；自定义内核环境；Notebook 执行历史对比 |
| M5 Transforms | Pipeline 依赖图可视化；批流 Join；公共 Library 提取 |
| M6 调度 | 回填（Backfill）；构建范围选择；**流式 Pipeline 滚动升级** |
| M7 质量 | 列级统计；跨 Dataset 一致性；规则模板库；**流式乱序/重复检测** |
| M8 目录 | 血缘可视化；数据地图；数据字典 |
| M9 血缘 | 字段级血缘；血缘 API；血缘健康检查 |
| M10 治理 | 字段级权限控制；数据生命周期管理；合规报告 |
| M11 监控 | 端到端时效监控；资源使用率监控；异常检测 |
| M12 健康大盘 | 健康与 SLA 联动；Owner 个性化大盘 |
| M13 流式链路 | 窗口算子；流批 Join；流式 Time Travel；多流 Join |
| M14 增量计算 | 依赖感知增量（子图重算）；增量 Join；增量聚合；失败降级 |
| M15 数据测试 | 数据契约；跨 Pipeline 集成测试；Fixture 管理 |
| M16 环境管理 | feature 环境（多人并发开发）；环境 diff；临时环境 |
| M17 资源管理 | 动态调整；成本归因；使用趋势分析 |

---

### 迭代 I4：完整对标（全模块 L4）

**目标**：全量对标 Palantir，引入 AI 辅助，实现平台智能化自运营。

| 模块 | I4 核心增量 |
|------|-----------|
| M1 Sync | 100+ 连接器；SaaS 接入；AI 辅助 Schema 映射 |
| M2 Dataset | EOS Dataset P2（非结构化/外部表/AI 辅助 SQL） |
| M3 Object Set | 动态 Object Set；对象图谱 |
| M3b User Edit | 批量变更；AI 辅助冲突解决 |
| M4 在线开发 | AI 代码生成；可视化调试；VS Code 插件 |
| M5 Transforms | AI 辅助转换逻辑生成；高级算子；性能分析 |
| M6 调度 | 跨引擎统一调度（批+流）；成本感知调度；AI 调度优化 |
| M7 质量 | AI 规则生成；流式实时质量监控（窗口级）；数据漂移检测 |
| M8 目录 | AI 辅助数据发现；自动摘要生成；推荐引擎 |
| M9 血缘 | 跨系统血缘；AI 辅助血缘修复 |
| M10 治理 | PBAC 完整实现；隐私计算支持 |
| M11 监控 | 预测性告警；成本监控 |
| M12 健康大盘 | AI 驱动根因分析；预测性健康评估 |
| M13 流式链路 | Exactly-once 端到端；动态 Schema 演进；流式 ML 推理；CEP |
| M14 增量计算 | 增量代价估算；细粒度分区级增量；跨引擎增量协同；AI 优化建议 |
| M15 数据测试 | AI 测试用例生成；变异测试；生产数据回放测试 |
| M16 环境管理 | 环境蓝绿切换；环境模板；AI 问题诊断 |
| M17 资源管理 | 成本感知调度；Spot 实例；AI 资源需求预测 |

---

## 四、迭代交付时间轴

```
当前          I1（基础闭环）        I2（生产就绪）        I3（能力增强）        I4（完整对标）
  │                │                    │                    │                    │
  ▼                ▼                    ▼                    ▼                    ▼
EOS Dataset     2026 Q2-Q3           2026 Q4-2027 Q1      2027 Q2-Q3           2027 Q4+
P0 收尾         全模块 L1             全模块 L2             全模块 L3             全模块 L4
                端到端链路打通         自动化替代手动         效率与规模升级         AI 智能化
```

### 关键里程碑

| 里程碑 | 时间（参考） | 标志性验收 |
|--------|------------|----------|
| **EOS P0 上线** | 2026 Q2 | 第一条 Pipeline 完整走通 WAP 流程 |
| **I1 完成** | 2026 Q3 | 外部数据→加工数据→对象集，全链路端到端可追踪 |
| **I2 完成** | 2027 Q1 | 自动化调度+事件驱动，团队日常生产完全基于新平台 |
| **I3 完成** | 2027 Q3 | 字段级血缘、流批一体、Backfill 全部具备 |
| **I4 完成** | 2028+ | AI 辅助全面接入，平台自运营 |

---

## 五、优先级矩阵

### 模块间依赖关系

```
M2 Dataset（核心基础）
    ├── M1 Sync（批量写入端）
    ├── M13 流式链路（流式写入端）── M14 增量计算（批流桥梁）
    ├── M5 Transforms（批处理加工）── M6 调度（执行驱动）
    ├── M3 Object Set（消费端）── M3b User Edit（回写端）
    ├── M4 在线开发（开发端）── M15 数据测试（测试保障）
    ├── M9 血缘（自动采集，批+流）
    ├── M7 质量（批+流质量门禁）
    │     └── M12 健康大盘（可视化）
    ├── M8 目录（发现与理解）
    ├── M10 治理（权限与合规）
    ├── M11 监控（批+流告警）
    ├── M16 环境管理（横切关注点）
    └── M17 资源管理（横切关注点）
```

### 关键路径

1. **M2（Dataset）** 是所有模块的基础，必须优先交付
2. **M5 + M6（Transforms + 调度）** 是批处理数据流动的驱动力
3. **M13（流式链路）+ M14（增量计算）** 是实时/近实时能力的核心，I1 即启动
4. **M4（在线开发）** 是工程效率的核心，影响所有开发者体验
5. **M3（Object Set）** 是数据从工程层到业务层的桥梁
6. **M9（血缘）+ M7（质量）** 是平台可信度的保障，批流均需覆盖

---

## 六、当前 EOS Dataset 与本规划的对应关系

| EOS Dataset 模块 | 本规划对应 | 覆盖等级 |
|----------------|-----------|---------|
| 版本/分支/WAP/Snapshot | M2 Dataset | I1→L1 |
| 静态血缘 | M9 Lineage | I1→L1 |
| 动态血缘（Version 级） | M9 Lineage | I2→L2 |
| WAP 质量门禁 | M7 Quality | I1→L1 |
| 基础 RBAC + Markings | M10 Governance | I1→L1 |
| 标记随血缘传播 | M10 Governance | I2→L2 |
| 字段级血缘 | M9 Lineage | I3→L3 |
| SQL Console | M4 在线开发（部分）| I2→L2 |
| 事件通知 | M6 调度（事件触发）| I2→L2 |
| 增量读 | M5 Transforms（增量计算）| I2→L2 |

---

---

## 七、v1.1 补充说明：流式与增量能力完整性说明

### 原 v1.0 缺失内容汇总

| 类别 | 缺失点 | v1.1 修复位置 |
|------|--------|-------------|
| **新增模块** | 流式数据链路（Stream Dataset + Flink Transform）| M13 |
| **新增模块** | 增量计算框架（@incremental 机制、Build Graph 优化）| M14 |
| **新增模块** | 数据测试框架（开发态断言，区别于质量门禁）| M15 |
| **新增模块** | 环境管理（dev/staging/prod 统一管理）| M16 |
| **新增模块** | 资源管理（配额、优先级、批流隔离）| M17 |
| **M1 修正** | 流式接入从 L3 提前到 L2 | M1 说明 |
| **M2 补充** | Stream Dataset 版本化语义（offset/checkpoint）| M2 说明 |
| **M5 修正** | 将 Flink Transform 和增量计算从 M5 拆出独立 | M5 说明 |
| **M6 补充** | 流式 Pipeline 生命周期（持续运行、滚动升级）| M6 说明 |
| **M7 修正** | 流式质量检测从 L4 提前到 L2/L3 | M7 |
| **各迭代** | I1-I4 全部加入流式/增量/测试/环境/资源新模块 | 迭代表 |

*文档版本：v1.1 | 更新：2026-04-09 | 下一步：调用 writing-plans skill 创建实施计划*
