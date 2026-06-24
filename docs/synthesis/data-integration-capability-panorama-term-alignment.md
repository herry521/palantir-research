# Data Integration 功能全景术语核对与中文解读

**日期：** 2026-06-24  
**用途：** 为“Data Integration 全功能模块图 + 已完成模块点亮”汇报材料校准 Palantir 对应术语，避免把自研抽象误写成 Palantir 官方模块。

## 摘要与洞察

1. 【事实】Palantir 官方主链路更接近 `Data Connection / Sync -> Dataset -> Pipeline / Transform -> Build / Schedule -> Ontology / Object Type / Object Set`，不是传统数仓式“任务 DAG + 表分区”模型。
2. 【事实】`Data Funnel` 在 Palantir 语境里应理解为 **Object Data Funnel / Funnel**，是 Object Storage V2 中负责对象写入、索引和保鲜的服务，不是业务漏斗分析。
3. 【修正】`Dataset Control Plane`、`Serving Dataset`、`Active Pointer`、`Run Identity`、`Data Version Identity`、`Shared IR / Contract` 都不是 Palantir 官方产品名，应在图中标注为“自研抽象 / 架构解释”，或换成更贴近官方的表达。
4. 【建议】汇报图的一级主链路应使用“中文业务解释 + Palantir 对应术语”双命名，例如“数据接入 Data Connection / Sync”“数据资产 Dataset”“对象消费 Ontology / Object Set”。
5. 【建议】旁路能力不要与主链路同权展示；Schedule、Quality、Lineage、Governance、Observability 更适合作为驱动层和支撑层，服务于 Build 和 Dataset graph。

## 1. 总体修正口径

上一版“功能全景”从数据平台自研视角是合理的，但其中混合了三类名词：

| 类型 | 示例 | 使用方式 |
|---|---|---|
| Palantir 官方术语 | Data Connection、Sync、Dataset、Pipeline Builder、Code Repositories、Build、Schedule、Ontology、Object Type、Object Set、Object Data Funnel | 可以作为图中英文标注 |
| 基于 Palantir 能力抽象出的架构概念 | Dataset Control Plane、Run Identity、Data Version Identity、Transform Contract、Serving Dataset | 可以保留，但必须标注为自研抽象 |
| 容易误导的泛化术语 | Data Funnel = 业务漏斗、Active Pointer = Palantir 官方发布指针、Data Product = Foundry 产品模块 | 应改名或降级为中文解释 |

官方资料确认的关键事实包括：

- Data Connection 用于把外部系统和其他 Foundry 实例的数据同步进 Foundry，也支持对外连接、webhook 和 data exports。来源：<https://palantir.com/docs/foundry/data-connection/overview/>
- Dataset 是 Foundry 中数据落地后到映射进 Ontology 之前的核心表示，封装文件集合，并集成权限、schema、版本控制和更新能力。来源：<https://palantir.com/docs/foundry/data-integration/datasets/>
- Pipeline 类型包括 Batch、Incremental、Streaming。来源：<https://palantir.com/docs/foundry/building-pipelines/pipeline-types/>
- Build 是 Foundry 中计算 Dataset 新版本的机制，提供编排和计算协调。来源：<https://palantir.com/docs/foundry/data-integration/builds/>
- Schedule 支持按时间、数据更新、逻辑更新或组合条件触发 scheduled builds。来源：<https://palantir.com/docs/foundry/building-pipelines/scheduling-overview/>
- Object Type 是现实实体或事件的 schema 定义；Object Set 是多个 object instances 的集合。来源：<https://palantir.com/docs/foundry/object-link-types/object-types-overview/>、<https://palantir.com/docs/foundry/api/ontologies-v2-resources/ontology-object-sets/ontology-object-set-basics//>
- Object Data Funnel 是 Object Storage V2 架构中负责把 Foundry datasources 和 user edits 写入并索引到 Ontology object databases 的服务。来源：<https://palantir.com/docs/foundry/object-backend/overview/>

## 2. 术语核对表

| 上一版名词 | Palantir 对应 | 判断 | 中文解读与修正建议 |
|---|---|---|---|
| Source & Sync | Data Connection、Source、Sync、Batch sync、Streaming sync、Export | 基本正确 | 建议中文名用“数据接入与同步”。这里不是简单连接器市场，而是把外部源、同步配置、同步运行和输出 Dataset 纳入 Foundry 数据集成链路。 |
| Source Registry | Source / Data Connection source | 非官方泛化 | 可以改成“数据源 Source 管理”。不要写成 Palantir 有一个独立 Source Registry 产品。 |
| Connector & Agent | Data Connection connector、agent、plugin 等 | 大体可用 | 建议中文解释为“连接器与部署代理”，用于访问 SaaS、数据库、文件、私网/on-prem source。 |
| Batch Sync | Batch sync | 正确 | 官方明确 batch sync 将外部系统数据同步进 Foundry dataset，是最广泛支持的 sync 能力。 |
| Incremental Sync | Incremental sync、CDC connector、水位/ID 增量等 | 基本正确 | “CDC / Watermark / Cursor”是实现模式，不一定都是官方统一术语。建议写成“增量同步：CDC、水位、cursor/offset 等”。 |
| Stream Ingestion | Streaming sync、push data into a stream、Streaming pipelines | 基本正确 | 不要把它画成 Batch Sync 子能力；应与批量/增量接入并列，输出可进入 Stream / streaming dataset 语义。 |
| Dataset Control Plane | Dataset + transactions + branches + views + schema + permissions | 自研抽象 | Palantir 官方叫 Dataset，不叫 Dataset Control Plane。汇报中可写“数据资产控制面 Dataset（自研控制面抽象）”。 |
| Raw Dataset | Dataset | 架构分层术语 | Raw / Curated / Serving 是数仓/平台分层，不是 Palantir 官方固定产品名。可作为中文链路状态保留。 |
| Serving Dataset | Dataset、View、Virtual Table、Dataset Preview / Query / Export / Ontology backing datasource | 非官方 | 建议改成“可消费数据资产 / Published Dataset View”。注意 Palantir 官方 `View` 是不持有文件、由 backing datasets 组成的资源，不等于 active pointer。 |
| Active Pointer / Release Pointer | 无明确官方对应；接近 production branch/latest successful transaction/发布视图的自研概念 | 偏差较大 | 不建议作为 Palantir 对应术语。中文解释可写“生产可消费指针”，但标注为自研设计，用于避免 transaction commit 立即被消费。 |
| Transaction & Version | Dataset transaction、transaction history | 正确 | Palantir Dataset transaction 类似 Git commit，是 Dataset 版本控制基础。中文解释：一次原子数据变更，支撑版本、增量、回滚和审计。 |
| Branch & View | Dataset branch、build branch、fallback branch、View | 基本正确但要拆开 | Branch 是分支；View 是特殊资源或读取视图语义。不要把 branch/view/fallback 混成一个单一“视图指针”。 |
| Pipeline Authoring & Transform | Pipeline Builder、Code Repositories、Transforms | 正确 | 建议中文名用“加工逻辑开发与转换”。Pipeline Builder 是低码图形入口，Code Repositories 是高码工程入口，Transform 是实际转换逻辑。 |
| Batch Pipeline | Batch pipeline | 正确 | 官方 pipeline 类型之一：每次 run 对变化的 Dataset 做完整重算。 |
| Incremental Pipeline | Incremental pipeline | 正确 | 官方 pipeline 类型之一：只处理上次 run 后变化的数据。中文解释要强调依赖 Dataset transaction/append-only 语义，不只是 where updated_at。 |
| Stream Pipeline | Streaming pipeline | 正确 | 官方 pipeline 类型之一：持续运行，新数据到达平台时处理。 |
| Pipeline Builder | Pipeline Builder | 正确 | 可支持 batch、incremental、streaming、faster 等路径；不要只等同于 Batch。 |
| Pro-code Contract / Shared IR | 无公开官方产品名；接近 Input/Output transform contract、repository checks、Pipeline Builder export | 自研抽象 | 建议改成“统一 Transform Contract（自研抽象）”。Palantir 官方可验证的是 Input/Output、Code Repositories、Pipeline Builder 导出到 Java repository，不是公开的统一 IR。 |
| Build / Run Execution | Build、Builds helper、Build timeline、Build history | 基本正确 | 官方叫 Build，不一定叫 Run Execution。中文解释：执行 pipeline 逻辑并产出 Dataset 新版本的计算与编排过程。 |
| Run Identity | 无官方对应；DataWorks 融合自研概念 | 自研抽象 | 建议保留但标注“自研：业务周期运行身份”。用于表达 business_date、data_interval、attempt、backfill 等 DataWorks 式生产语义。 |
| Data Version Identity | 无官方对应；接近 Dataset branch + transaction/view + producer build | 自研抽象 | 建议保留但改名为“数据版本身份（自研）”。中文解释：说明一次产出对应哪些输入 transaction、逻辑版本和输出 transaction。 |
| Build Resolution | build resolution、staleness、input/output transaction locking | 基本正确 | 可用作英文技术标签，但中文应解释为“构建解析：确定本次要构建哪些 Dataset、锁定哪些输入版本、是否 stale”。 |
| Backfill / Replay | Force build、build scope、incremental replay、stream checkpoint reset 等 | 部分对应 | Palantir 有 build/rebuild/force/schedule 范围选择等能力，但 DataWorks 式业务日期 backfill 不是 Foundry 默认全局语义。 |
| Schedule & Automation | Scheduling、schedule editor、triggers | 基本正确 | 建议作为 Build 的驱动层，不作为数据状态主链路一级对象。 |
| Time Trigger / Data Event Trigger / Logic Trigger | time trigger、data updated、logic updated | 正确 | 官方 schedule 支持时间、数据更新、逻辑更新及组合条件。 |
| Graph Build Scope | Data Lineage graph build workflow、build all ancestors / selected / between datasets | 正确 | 中文解释：调度和手动 build 常围绕 Dataset lineage graph 选择范围，而不是孤立任务节点。 |
| SLA / Freshness | Freshness / stale datasets / health / schedules | 大体正确 | 注意 freshness 是 Dataset 是否 up-to-date 的平台概念，不等价于业务日期 SLA。 |
| Serving Dataset & Data Product | Dataset、Marketplace product、Analytics output、Ontology datasource | 偏自研/泛化 | Palantir 有 Marketplace products、Analytics、Dataset 等，但“Data Product”不是 Data Integration 主链路官方模块。建议中文写“数据产品化消费”，不作为 Palantir 官方英文模块。 |
| Query / SQL Serving | Dataset Preview、SQL Console、Query APIs、Contour/Code Workbook 等 | 泛化可用 | 建议写成“查询与分析消费”，不要暗示有一个统一官方 Query Serving 模块。 |
| Export / Delivery | Data Connection Exports | 正确 | 官方 Data Connection 支持将 datasets 和 streams export 到外部系统。 |
| OSet / Ontology / App Consumption | Ontology、Object Type、Object Set、OSDK、Workshop、Functions | 基本正确 | “OSet”可作为 Object Set 缩写，但图中建议写全称 Object Set，避免读者不熟。 |
| Object Type Mapping | Object Type、backing datasource、property mapping、link type | 正确 | 中文解释：把 Dataset/其他 datasource 映射成业务对象、属性和关系。 |
| Object Set Writer | Object Data Funnel / indexing pipeline / Ontology sync | 需修正 | 不建议自造 Object Set Writer 作为 Palantir 官方名。更准确是 Object Data Funnel / Indexing，把 backing data 和 user edits 索引到对象数据库。 |
| Branch View | Global Branch、Object Type branch metadata、Dataset branch、Data Lineage branch view | 复杂但可用 | 必须解释：Object Type branch 管 metadata，Dataset branch 管数据版本，Build fallback 与 Lineage/Ontology branch view 不是同一件事。 |
| User Edit / Writeback | Actions、User edits、Writeback Dataset、Object Data Funnel | 基本正确 | 中文解释：业务用户通过 Actions 修改对象，变更进入 user edits/writeback 路径，再通过 Funnel 或 pipeline 合并到对象/数据链路。 |
| Data Funnel / Metrics | Object Data Funnel；不是业务漏斗 | 明显偏差 | 必须改。若你要讲业务漏斗分析，应叫“Funnel Analytics / 指标分析”，不要用 Palantir Data Funnel。若要对齐 Palantir，Data Funnel 应放在 OSet/Ontology indexing 下。 |
| Data Quality | Data Expectations、Data Health、Monitoring views、Health Checks | 正确 | 作为支撑层。中文解释：构建期门禁 + 运行期健康监控，不要压成一种规则。 |
| Lineage | Data Lineage | 正确 | 中文解释：不只是画 DAG，还要能解释 Dataset branch、transaction/view、build run 和 object mapping。 |
| Permission & Marking | Roles、Organizations、Markings、Object/Property security | 正确 | 作为支撑层。中文解释：Dataset 权限和 Ontology 对象/属性策略是叠加关系。 |
| Observability | Build timeline、Data Health、Monitoring / alerting | 基本正确 | 作为支撑层，不建议抢主链路一级位置。 |
| Resource Management | Resource Management、Resource Queues、compute-seconds | 正确 | 作为支撑层。 |

## 3. 需要修正的主要偏差

### 3.1 `Data Funnel` 不能解释成业务漏斗

上一版把 `Data Funnel / Metrics` 写成：

```text
funnel definition
stage conversion
cohort / segment
metric materialization
app / dashboard serving
```

这更像业务分析里的“漏斗分析”，不是 Palantir 的 Data Funnel。

官方语境中，Object Data Funnel 是 Ontology Object Storage V2 架构中的服务，负责读取 Foundry datasources 和 user edits，并把它们索引进 object databases，使对象数据保持更新。它应放在 `Ontology / Object Type / Object Set` 的对象写入与索引链路下。

建议改成：

```text
Object Data Funnel / Indexing
  - read backing datasets / restricted views / streaming datasources
  - ingest user edits from Actions
  - create / update object instances
  - index object data into object databases
  - keep object indexes up to date
```

如果汇报确实要表达“业务漏斗指标”，建议另设中文名：

```text
业务指标与漏斗分析（非 Palantir Data Funnel）
  - funnel metric
  - cohort / segment
  - conversion analysis
  - dashboard / app serving
```

### 3.2 `Active Pointer / Serving Dataset` 是自研发布语义，不是 Palantir 官方模块

Palantir 有 Dataset transactions、branches、views、staleness、builds、Dataset Preview、Query/Export/Ontology mapping 等能力，但公开资料没有确认一个叫 `Active Pointer` 的官方对象。

这个概念对自研平台有价值：它表达“transaction commit 只说明写入成功，不等于生产可消费”。但图上应写成：

```text
可消费版本发布（自研发布语义）
  - committed transaction
  - quality-passed view
  - production pointer / active view pointer
```

不要写成：

```text
Palantir Active Pointer
```

### 3.3 `Run Identity / Data Version Identity` 是融合 DataWorks 与 Foundry 的自研设计

Palantir 的 Build / Schedule 语义围绕 Dataset graph、transaction、staleness、build range；DataWorks 的强项是 business_date / data_interval / cycle instance。

因此：

- `Run Identity` 应解释为自研补充，用来承载业务日期、调度周期、补数和重跑语义。
- `Data Version Identity` 应解释为自研补充，用来承载 output dataset、branch、input transaction set、logic version、output transaction。

这组概念不应写成 Palantir 官方名，但适合用于“我们设计的数据平台为什么比单纯 cron + 表更完整”。

### 3.4 `Shared IR / Contract` 要降调

Palantir 官方可以确认的是：

- Code Repositories / Transforms 通过 Input / Output 声明 Dataset 依赖。
- Pipeline Builder 是低码开发入口。
- Pipeline Builder 可导出到 Java transforms repository，但导出不可逆且存在转换限制。

公开资料不能证明 Palantir 暴露了一个统一的 `Shared IR`。因此建议图中写：

```text
Transform Contract（自研抽象）
  - Input / Output
  - schema contract
  - runtime profile
  - incremental semantics
  - quality expectations
```

不要写：

```text
Palantir Shared IR
```

## 4. 建议后的汇报图一级结构

推荐最终图使用以下一级结构：

```text
数据核心链路
1. 数据接入与同步
   Palantir: Data Connection / Source / Sync / Export

2. 数据资产与版本控制
   Palantir: Dataset / Transaction / Branch / View

3. 加工逻辑开发
   Palantir: Pipeline Builder / Code Repositories / Transforms

4. 构建执行与版本产出
   Palantir: Build / Build history / Build timeline / Staleness

5. 调度与自动化驱动
   Palantir: Schedule / Triggers / Data Lineage schedule editor

6. 对象化消费与应用层
   Palantir: Ontology / Object Type / Object Set / Actions / OSDK

7. 对象索引与数据漏斗
   Palantir: Object Data Funnel / Object indexing

支撑层
8. 质量、血缘、权限、审计、监控、资源
   Palantir: Data Expectations / Data Health / Data Lineage / Markings / Audit / Resource Management
```

如果要严格聚焦“数据加工链路核心能力完备性”，主图可以把第 5、7、8 降为驱动层/支撑层，视觉中心保留：

```text
Data Connection / Sync
  -> Dataset
  -> Pipeline Builder / Code Repositories / Transforms
  -> Build
  -> Ontology / Object Type / Object Set
```

中文解释：

```text
外部数据进入平台
  -> 形成可版本化的数据资产
  -> 通过低码或高码定义加工逻辑
  -> 构建产生新的数据版本
  -> 映射成业务对象和对象集合供应用消费
```

## 5. 建议用于 HTML 配置的数据字段

为了避免把“官方术语”和“自研解释”混淆，HTML 的模块数据建议包含：

```json
{
  "id": "dataset",
  "zhName": "数据资产与版本控制",
  "palantirTerms": ["Dataset", "Transaction", "Branch", "View"],
  "role": "把同步或加工产出的数据变成可版本化、可治理、可发布的数据资产。",
  "termType": "official-plus-architecture",
  "capabilities": [
    {
      "name": "Dataset Identity",
      "zhName": "数据资产身份",
      "palantirTerm": "Dataset",
      "isCore": true,
      "interpretation": "Dataset 是 Foundry 中从数据落地到映射进 Ontology 前的核心表示。"
    }
  ]
}
```

`termType` 建议取值：

| 值 | 含义 |
|---|---|
| `official` | Palantir 官方术语，可直接展示 |
| `official-plus-architecture` | 官方能力 + 自研架构解释 |
| `self-build` | 自研设计概念，必须明确标注 |
| `avoid-or-rename` | 容易误导，应改名或降级 |

## 6. 参考来源

- Data Connection overview: <https://palantir.com/docs/foundry/data-connection/overview/>
- Batch sync: <https://palantir.com/docs/foundry/data-connection/set-up-sync/>
- Data Connection exports: <https://palantir.com/docs/foundry/data-connection/export-overview/>
- Datasets core concepts: <https://palantir.com/docs/foundry/data-integration/datasets/>
- Views core concepts: <https://palantir.com/docs/foundry/data-integration/views/>
- Branching core concepts: <https://palantir.com/docs/foundry/data-integration/branching/>
- Builds core concepts: <https://palantir.com/docs/foundry/data-integration/builds/>
- Pipeline types: <https://palantir.com/docs/foundry/building-pipelines/pipeline-types/>
- Scheduling overview: <https://palantir.com/docs/foundry/building-pipelines/scheduling-overview/>
- Build datasets from Data Lineage: <https://palantir.com/docs/foundry/data-lineage/build-datasets/>
- Pipeline Builder outputs, deploy vs build: <https://palantir.com/docs/foundry/pipeline-builder/outputs-deliver-pipeline/>
- Object types overview: <https://palantir.com/docs/foundry/object-link-types/object-types-overview/>
- Object Set basics: <https://palantir.com/docs/foundry/api/ontologies-v2-resources/ontology-object-sets/ontology-object-set-basics//>
- Object backend / Object Data Funnel: <https://palantir.com/docs/foundry/object-backend/overview/>
- Object indexing overview: <https://palantir.com/docs/foundry/object-indexing/overview/>
