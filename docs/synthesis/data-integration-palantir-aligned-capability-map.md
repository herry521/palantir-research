# Data Integration 功能全景：Palantir 严格对齐版

**日期：** 2026-06-24  
**用途：** 支撑“Data Integration 全功能模块图 + 已完成模块点亮”汇报材料。本文只保留 Palantir 官方文档中可找到直接对应的产品、对象或能力，不纳入自研架构抽象。

## 摘要与洞察

1. 【事实】Palantir Data Integration 的主链路可以严格表达为：`Data Connection / Source / Sync -> Dataset / Stream / View -> Pipeline Builder / Code Repositories / Transform -> Build / Schedule / Data Lineage -> Ontology / Object Type / Object Set / Object Data Funnel`。
2. 【事实】Pipeline 官方类型只有三类主型：Batch、Incremental、Streaming；Faster 是 Batch / Incremental 的变体，不是单独 pipeline 类型。
3. 【事实】Dataset 的核心版本语义来自 transaction、view 和 branch；transaction 类型包括 `SNAPSHOT`、`APPEND`、`UPDATE`、`DELETE`。
4. 【事实】Build 是计算 Dataset 新版本的机制；Schedule 是让 Build 随时间、数据更新或逻辑更新持续运行的触发机制。
5. 【事实】Object Data Funnel 属于 Ontology backend / Object Storage V2，负责把 Foundry datasources 与 user edits 写入并索引到 object databases；不是业务漏斗分析。

## 1. 不纳入本版的自研抽象

以下名词不进入“严格 Palantir 对齐版”能力地图：

| 剔除名词 | 原因 | 若后续需要可如何表达 |
|---|---|---|
| Dataset Control Plane | 不是 Palantir 官方模块名 | 用 `Dataset`、`Transaction`、`Branch`、`View` 拆开表达 |
| Serving Dataset | 不是 Data Integration 官方对象 | 用 `Dataset`、`View`、`Virtual Table`、`Ontology datasource`、`Export` 按场景表达 |
| Active Pointer / Release Pointer | 未找到 Palantir 官方对应对象 | 不放入本版；自研发布语义另开图 |
| Run Identity | DataWorks 融合自研概念 | 不放入本版；Palantir 侧用 `Build`、`Job`、`Schedule`、`Build timeline` 表达 |
| Data Version Identity | 自研解释性概念 | 用 `Dataset branch + transaction/view + Build/Sync producer` 表达 |
| Shared IR | Palantir 未公开统一 IR | 用 `Input / Output`、`Transform`、`Pipeline Builder`、`Code Repositories`、`Export pipeline code` 表达 |
| Data Product | 不是 Data Integration 主链路官方模块 | 若需要产品化分发，用 `Marketplace product` 单独说明 |
| Business Funnel / Metrics Funnel | 不是 Palantir Data Funnel | 若要讲业务漏斗，另称“业务漏斗分析”，不要叫 Data Funnel |

## 2. 严格 Palantir 能力地图

### 2.1 Data Connection / Connectivity

**中文名：数据连接与接入。**

定位：负责连接外部系统、配置 source、执行 sync、接收 push stream、配置 webhooks/listeners，并可把 Foundry 数据 export 到外部系统。

```text
Data Connection / Connectivity
├── Agents
├── Sources
│   └── Source exploration
├── Syncs
│   ├── Batch sync
│   ├── Streaming sync
│   ├── File-based sync
│   ├── Media set sync
│   └── Incremental sync / CDC-related ingestion
├── Push data into a stream
├── Exports
├── Webhooks
├── Listeners
│   ├── HTTPS listeners
│   ├── WebSocket listeners
│   └── Email listeners
└── External connections from code
    ├── External transforms
    ├── External functions
    └── Sources in Python environments
```

中文解读：这一层不是单纯“连接器列表”，而是 Foundry 里外部数据进入和流出平台的入口。`Source` 表示外部数据源配置，`Sync` 表示把外部数据写入 Foundry Dataset / Stream / Media set 的同步任务，`Export` 则是把 Foundry 内部数据送出到外部系统。

### 2.2 Core Data Objects

**中文名：核心数据对象。**

定位：Data Integration 中承载数据状态、版本和存储形态的官方核心对象。

```text
Core Data Objects
├── Datasets
│   ├── Transactions
│   │   ├── SNAPSHOT
│   │   ├── APPEND
│   │   ├── UPDATE
│   │   └── DELETE
│   ├── Views
│   ├── Branches
│   ├── Schema
│   └── Retention
├── Streams
├── Media sets
├── Iceberg tables
├── Virtual tables
└── Change data capture (CDC)
```

中文解读：`Dataset` 是 Foundry 数据进入平台后的核心表示之一。它不是普通文件夹，也不只是传统表，而是由 files + schema + permissions + transactions + branches/views 等共同组成的数据资产。`Stream`、`Media set`、`Virtual table`、`Iceberg table` 是不同数据形态或接入/消费形态，主图里可按重要性弱化。

### 2.3 Pipeline Authoring

**中文名：Pipeline 开发入口。**

定位：定义数据转换逻辑的官方开发入口，包括低码 Pipeline Builder 与高码 Code Repositories。

```text
Pipeline Authoring
├── Pipeline Builder
│   ├── Graph and form-based authoring
│   ├── Transforms
│   ├── Expressions
│   ├── Outputs
│   ├── Branches
│   ├── Health checks
│   ├── Faster pipelines
│   └── External pipelines
└── Code Repositories
    ├── Python transforms
    ├── SQL transforms
    ├── Java transforms
    ├── Repository / Git workflow
    ├── Pull requests / code review
    ├── Preview / debug
    └── Unit tests / repository checks
```

中文解读：Pipeline Builder 和 Code Repositories 是两种互补的 pipeline authoring surface。Pipeline Builder 面向低码图形和表单协作；Code Repositories 面向代码工程、Git、PR、测试和复杂逻辑。二者都以 Foundry datasets 作为输入输出，因此可以进入同一 Data Lineage、Schedule 和 Health Check 体系。

### 2.4 Pipeline Types

**中文名：Pipeline 类型。**

定位：Foundry 官方定义的 pipeline 执行范式。

```text
Pipeline Types
├── Batch pipelines
│   └── Fully recompute changed datasets on each run
├── Incremental pipelines
│   └── Process new data changed since last run
├── Streaming pipelines
│   └── Run continuously and process new data as it arrives
└── Faster versions of batch and incremental pipelines
```

中文解读：

- `Batch`：批处理，变化后重新计算相关 Dataset，复杂度低但延迟和成本较高。
- `Incremental`：增量处理，只处理上次运行后的变化数据，依赖 Dataset transaction / append-only 等语义。
- `Streaming`：持续运行，数据到达平台时立即处理，延迟最低但复杂度最高。
- `Faster`：Batch / Incremental 的更快版本，不是第 4 类 Pipeline。

### 2.5 Builds

**中文名：构建。**

定位：计算 Dataset 新版本的官方机制。

```text
Builds
├── Build
├── Jobs
├── JobSpec
├── Build lifecycle
│   ├── Build resolution
│   ├── Job execution
│   └── Staleness
├── Build locking
├── Force build
├── Build timeline
└── Builds application / Builds helper
```

中文解读：`Build` 不是普通任务运行记录，而是 Foundry 计算 Dataset 新版本的核心机制。Build 会解析输入 Dataset、校验 schema、打开输出 transaction、执行 jobs，并根据 staleness 判断哪些输出需要重算。Data Lineage 中的 Builds helper 可以围绕 lineage graph 发起构建。

### 2.6 Schedules

**中文名：调度。**

定位：让 Build 随时间和事件持续运行的官方机制。

```text
Schedules
├── Schedule
├── Trigger types
│   ├── Time trigger
│   ├── Data updated trigger
│   ├── Logic updated trigger
│   └── AND / OR trigger composition
├── Create / view / modify schedules
├── Schedule parameterization
├── Schedule troubleshooting
└── Scheduling best practices
```

中文解读：Schedule 不是数据状态对象，而是驱动 Build 的自动化机制。Foundry 支持时间触发、数据更新触发、逻辑更新触发，以及 AND/OR 组合触发。Schedule 的配置和管理也与 Data Lineage graph 深度相关。

### 2.7 Data Lineage

**中文名：数据血缘。**

定位：理解、构建、排查和管理 Dataset pipeline graph 的官方应用。

```text
Data Lineage
├── Explore lineage graph
├── Search datasets / artifacts / ontology entities
├── Expand ancestors / descendants
├── View dataset preview and logic
├── Build datasets from lineage graph
│   ├── Build all ancestors
│   ├── Build transforms between selected datasets
│   └── Build selected datasets
├── Build timeline
├── Manage schedules
├── Check permissions
├── See impact of Marking changes
└── Out-of-date / stale dataset analysis
```

中文解读：Data Lineage 不只是画血缘图。它也是查看 Dataset 上下游、发起 Build、查看 Build timeline、管理 Schedule、检查权限、分析 Marking 影响和识别 stale datasets 的工作台。

### 2.8 Health Checks / Data Quality

**中文名：健康检查与数据质量。**

定位：对 Dataset / Pipeline 产出进行质量、状态和健康判断。

```text
Health / Quality
├── Health checks
├── Pipeline Builder health checks
├── Data Expectations
├── Output checks
├── Data Health
├── Monitoring views
└── Issue / alert workflows
```

中文解读：Palantir 里质量能力不是单一“规则引擎”。构建前后会有 Pipeline Builder health checks、Data Expectations / output checks；运行和运营视角还有 Data Health、monitoring views、alerts 等能力。

### 2.9 Security / Governance

**中文名：安全与治理。**

定位：围绕 Dataset、Pipeline、Ontology 对象和数据访问路径执行权限、标记、策略和审计。

```text
Security / Governance
├── Roles / resource permissions
├── Organizations
├── Markings
├── Pipeline security
│   ├── Guidance on removing markings
│   └── Remove inherited markings and organizations
├── Data Lineage permission coloring
├── Object security policies
├── Property security policies
└── Audit-related capabilities
```

中文解读：Marking 是 Palantir 治理的关键概念。Dataset 上的 Marking / Organization 能沿下游数据派生传播，Ontology 层还有 Object / Property security 进一步控制对象和属性可见性。

### 2.10 Ontology / Object Backend

**中文名：Ontology 与对象后端。**

定位：把 Dataset 等 Foundry datasources 映射为业务对象、对象集合、动作和应用可消费的对象查询能力。

```text
Ontology / Object Backend
├── Ontology Metadata Service (OMS)
├── Object types
├── Link types
├── Properties
├── Object Set Service (OSS)
│   ├── Object sets
│   ├── Static object sets
│   ├── Dynamic object sets
│   ├── Temporary object sets
│   └── Permanent object sets
├── Actions
├── Object Data Funnel
├── Object databases
├── Object indexing
├── User edits
└── Functions on Objects
```

中文解读：Ontology 是 Palantir 把数据变成业务对象和业务动作的核心层。`Object Type` 定义现实实体/事件的 schema；`Object Set` 是对象实例集合；`OSS` 负责对象读取；`Actions` 处理用户编辑；`Object Data Funnel` 负责把 datasets、restricted views、streaming datasources 和 user edits 写入并索引到 object databases。

## 3. 建议用于汇报 HTML 的一级模块

若目标是“功能全景 + 点亮已完成模块”，建议一级模块只放官方可对齐域：

```text
1. Data Connection / Connectivity
2. Core Data Objects
3. Pipeline Authoring
4. Pipeline Types
5. Builds
6. Schedules
7. Data Lineage
8. Health / Quality
9. Security / Governance
10. Ontology / Object Backend
```

如果目标是“数据加工链路核心完备性”，可以把它们视觉上排成主链路和支撑层：

```text
主链路：
Data Connection / Connectivity
  -> Core Data Objects
  -> Pipeline Authoring + Pipeline Types
  -> Builds
  -> Ontology / Object Backend

驱动与观察：
Schedules
Data Lineage

支撑：
Health / Quality
Security / Governance
```

## 4. 建议用于 HTML 的严格数据模型

```json
[
  {
    "id": "data-connection",
    "name": "Data Connection / Connectivity",
    "zhName": "数据连接与接入",
    "palantirAligned": true,
    "capabilities": [
      { "name": "Agents", "zhName": "连接代理", "core": true },
      { "name": "Sources", "zhName": "数据源", "core": true },
      { "name": "Batch sync", "zhName": "批量同步", "core": true },
      { "name": "Streaming sync", "zhName": "流式同步", "core": true },
      { "name": "File-based syncs", "zhName": "文件同步", "core": false },
      { "name": "Exports", "zhName": "数据外发", "core": false },
      { "name": "Webhooks / Listeners", "zhName": "Webhook 与监听器", "core": false }
    ]
  },
  {
    "id": "core-data-objects",
    "name": "Core Data Objects",
    "zhName": "核心数据对象",
    "palantirAligned": true,
    "capabilities": [
      { "name": "Datasets", "zhName": "数据集", "core": true },
      { "name": "Transactions", "zhName": "事务", "core": true },
      { "name": "Views", "zhName": "视图", "core": true },
      { "name": "Branches", "zhName": "分支", "core": true },
      { "name": "Streams", "zhName": "流", "core": true },
      { "name": "Media sets", "zhName": "媒体集", "core": false },
      { "name": "Virtual tables", "zhName": "虚拟表", "core": false },
      { "name": "Change data capture", "zhName": "CDC", "core": false }
    ]
  }
]
```

后续实现 HTML 时，状态配置只应挂在这些官方模块和官方能力上，不再挂自研抽象。

## 5. 官方来源

- Data Connection overview: <https://www.palantir.com/docs/foundry/data-connection/overview/>
- Datasets: <https://www.palantir.com/docs/foundry/data-integration/datasets/>
- Builds: <https://www.palantir.com/docs/foundry/data-integration/builds/>
- Pipeline Builder and Code Repositories: <https://www.palantir.com/docs/foundry/building-pipelines/considerations-pb-cr/>
- Pipeline types: <https://www.palantir.com/docs/foundry/building-pipelines/pipeline-types/>
- Data Lineage build datasets: <https://www.palantir.com/docs/foundry/data-lineage/build-datasets/>
- Scheduling trigger types: <https://www.palantir.com/docs/foundry/building-pipelines/triggers-reference/>
- Scheduling best practices: <https://www.palantir.com/docs/foundry/building-pipelines/scheduling-best-practices/>
- Object backend overview: <https://www.palantir.com/docs/foundry/object-backend/overview/>
- Object types overview: <https://www.palantir.com/docs/foundry/object-link-types/object-types-overview/>
- Ontology Object Set basics: <https://www.palantir.com/docs/foundry/api/ontologies-v2-resources/ontology-object-sets/ontology-object-set-basics/>
