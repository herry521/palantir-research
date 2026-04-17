# Palantir Foundry Ontology 核心业务对象与数据模型调研

> **创建日期**：2026-04-15
> **调研范围**：Palantir Foundry Ontology 层核心业务对象体系与数据模型设计
> **目标**：为现有平台 M3（Object Set）模块对标提供精准的参照基线
> **参考文档**：[Palantir Foundry 官方文档](https://www.palantir.com/docs/foundry/ontology/overview/)

---

## 一、Ontology 概述

Palantir Ontology 是组织的 **运营层**（Operational Layer），坐落在集成到平台的数据资产（Dataset、Virtual Table、Model）之上，将它们连接到真实世界的对应物——从工厂、设备、产品等物理资产，到客户订单、金融交易等业务概念。

Ontology 的核心价值：
- **连接性**（Connectivity at Scale）：统一的数据访问与决策语言
- **可理解性**（Interpretability）：业务用户无需理解 Dataset/Join 等技术概念
- **规模经济**（Economies of Scale）：新用例复用已有 Ontology，无需重新集成数据
- **决策捕获**（Decision Capture）：通过 Action 将用户决策回写到 Ontology
- **AI/ML 运营化**（Powering Operational AI/ML）：模型直接绑定到 Ontology 对象

Ontology 由两类元素构成：

| 元素分类 | 包含类型 | 职责 |
|---------|---------|------|
| **语义元素**（Semantic） | Object Type, Property, Shared Property, Link Type, Interface, Value Type | 定义组织的"是什么" |
| **动力学元素**（Kinetic） | Action Type, Function | 定义组织的"怎么变" |

---

## 二、核心业务对象详解

### 2.1 Object Type（对象类型）

**定义**：真实世界实体或事件的 Schema 定义。一个 Object Type 对应一组具有相同结构的对象实例。

> **参考**：https://www.palantir.com/docs/foundry/object-link-types/object-types-overview/

#### 2.1.1 元数据结构

| 字段 | 说明 | 约束 |
|------|------|------|
| `id` | 全局唯一标识 | 小写字母+数字+短横线，字母开头 |
| `displayName` | 用户可见名称 | 在搜索和应用中展示 |
| `pluralDisplayName` | 复数名称 | |
| `description` | 描述文本 | Object Explorer 搜索可见 |
| `apiName` | 编程接口名称 | PascalCase，全局唯一，1-100 字符 |
| `icon` | 图标 + 颜色 | 用户应用中展示 |
| `groups` | 分类标签 | 支持搜索和过滤 |
| `aliases` | 别名 | 搜索时的额外匹配词 |
| `backingDatasource` | 绑定的 Foundry Dataset | **一个 Dataset 只能 back 一个 Object Type** |

#### 2.1.2 核心约束

- **Primary Key**（必须）：唯一标识每个对象实例，**必须确定性**——不能随 Build 变化（禁止自增行号/随机 ID）
- **Title Key**（必须）：显示名称属性
- 不支持 `MapType` 或 `StructType` 列作为 Backing Datasource
- Object Storage V2 支持最多 **2000 个属性 / Object Type**
- **API Name 保留字**：`ontology`, `object`, `property`, `link`, `relation`, `rid`, `primaryKey`, `typeId`, `ontologyObject`

#### 2.1.3 与 Dataset 的映射关系

```
┌─────────────────────────────────────────────────────────┐
│                  Ontology 概念映射                        │
├─────────────────┬───────────────────────────────────────┤
│  Ontology       │  Dataset 类比                          │
├─────────────────┼───────────────────────────────────────┤
│  Object Type    │  Dataset                              │
│  Object（实例）  │  Row                                  │
│  Property       │  Column                               │
│  Property Value │  Field（单元格值）                      │
│  Object Set     │  过滤后的行集合                         │
│  Link Type      │  Join                                 │
└─────────────────┴───────────────────────────────────────┘
```

#### 2.1.4 Backing Datasource 映射机制

Object Type 不直接存储数据，而是通过 **Backing Datasource** 映射到 Foundry Dataset：

```
Foundry Dataset（实际存储）
    │
    ▼  列映射（Column → Property）
Object Type（Schema 定义）
    │
    ▼  索引（Funnel Pipeline）
Object Database（查询优化存储）
    │
    ▼  查询（OSS）
用户应用（Workshop / Object Explorer / OSDK）
```

关键规则：
1. 一个 Dataset 只能 back 一个 Object Type
2. Dataset 的每一列映射到一个 Property
3. Property 的 `backingColumn` 指定具体映射的列名
4. Primary Key 列的值必须在 Dataset 中全局唯一

---

### 2.2 Property（属性）

**定义**：Object Type 的特征 Schema，描述真实世界实体的某个维度。

> **参考**：https://www.palantir.com/docs/foundry/object-link-types/properties-overview/

#### 2.2.1 属性元数据

| 字段 | 说明 | 约束 |
|------|------|------|
| `propertyId` | 类型内唯一标识 | 字母+数字+短横线+下划线 |
| `displayName` | 用户可见名称 | |
| `apiName` | 编程接口名称 | camelCase，类型内唯一，1-100 字符 |
| `backingColumn` | 映射到 Backing Datasource 的列 | |
| `baseType` | 基础数据类型 | 见下表 |

#### 2.2.2 支持的属性类型

| 分类 | 类型 | 可做 Primary Key | 可做 Title Key | 备注 |
|------|------|:---:|:---:|------|
| 通用 | String, Integer, Short | ✅ | ✅ | |
| 时间 | Date, Timestamp | ✅ | 不推荐 | 存储格式可能导致唯一性冲突 |
| 数值 | Boolean, Byte, Long | ✅ | 不推荐 | Boolean 限制仅 2 个实例；Long > 1e15 在 JS 中有精度问题 |
| 浮点 | Float, Double, Decimal | ✅ | ❌ | |
| 集合 | Array | ✅ | ❌ | 不可含 null 元素；V2 不支持嵌套 Array |
| 结构 | Struct | ❌ | ❌ | 不支持嵌套；字段不可为 Array |
| 向量 | Vector | ❌ | ❌ | |
| 媒体 | Media Reference, Time Series, Attachment | ❌ | ❌ | |
| 地理 | Geopoint | ✅ | ❌ | |
| 地理 | Geoshape | ❌ | ❌ | |
| 标记 | Marking | ❌ | ❌ | |
| 加密 | Cipher | ✅ | ❌ | |

---

### 2.3 Shared Property（共享属性）

**定义**：可在多个 Object Type 上复用的属性，统一管理属性元数据。

> **参考**：https://www.palantir.com/docs/foundry/object-link-types/shared-property-overview/

**核心特点**：
- **元数据共享，数据不共享**——多个 Object Type 共用同一个属性定义（名称、类型、描述等），但底层数据各自独立
- 修改共享属性的元数据（如描述、显示名称），会同步到所有使用它的 Object Type
- 在 Ontology Manager 中以 🌐 图标标识
- 既可直接创建，也可由已有普通属性转换生成

**典型场景**：
- `Employee` 和 `Contractor` Object Type 共用 `startDate` 共享属性
- `Airport` 和 `TrainStation` 共用 `location` 共享属性

---

### 2.4 Link Type（关联类型）

**定义**：两个 Object Type 之间关系的 Schema 定义。Link 是 Link Type 的单个实例。

> **参考**：https://www.palantir.com/docs/foundry/object-link-types/link-types-overview/

#### 2.4.1 基数类型

| 基数 | 说明 | 示例 |
|------|------|------|
| One-to-One | 一对一 | `Aircraft` ↔ 单一 `Registration` |
| One-to-Many / Many-to-One | 一对多 | 一个 `Aircraft` → 多个 `Flight` |
| Many-to-Many | 多对多 | 多个 `Aircraft` ↔ 多个 `Flight` |

**自引用 Link**：同一 Object Type 之间也可建立 Link（如 `Employee` 的 `Direct Report ↔ Manager`）。

#### 2.4.2 三种实现方式

| 实现方式 | 适用基数 | 数据来源 | 特点 |
|---------|---------|---------|------|
| **Foreign Key** | 1:1 / N:1 | Object Type 自身属性 | 一方 FK 属性指向另一方 PK；自动检测匹配的 FK |
| **Join Table Dataset** | M:N | 独立 Dataset（含双方 PK 列） | 支持 Writeback；可自动生成 Join Table |
| **Object-Backed** | 扩展 N:1 | 中间 Object Type 作为连接体 | 可携带额外属性（如 `FlightManifest` 连接 `Aircraft`↔`Flight`，同时携带 `Pilot`、`FirstMate`） |

```
Foreign Key 示例：
┌──────────────┐          FK: flight_tail_number          ┌──────────────┐
│   Flight     │ ─────────────────────────────────────── │   Aircraft    │
│  tail_number │──────── matches ──────────────────────▶ │  tail_number  │
│  (FK)        │                                         │  (PK)        │
└──────────────┘                                         └──────────────┘

Object-Backed 示例：
┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│   Flight     │ ◀── │ Flight Manifest   │ ──▶│   Aircraft    │
│              │     │  pilot            │     │              │
│              │     │  first_mate       │     │              │
└──────────────┘     └──────────────────┘     └──────────────┘
                     （中间对象，携带关系元数据）
```

#### 2.4.3 Link Type 元数据

| 字段 | 说明 |
|------|------|
| Display Name（每侧） | 描述从一侧到另一侧的关系（如 `Assigned Aircraft`） |
| API Name（每侧） | 编程使用（如 `assignedAircraft`），camelCase，类型内唯一 |

**代码遍历示例**：`Flight.assignedAircraft.get()` → 返回关联的 `Aircraft` 对象。

**约束**：不支持跨 Ontology 的 Link Type。

---

### 2.5 Action Type（动作类型）

**定义**：对 Object、Property 和 Link 的一组变更的 Schema 定义。Action 是 Ontology 的**动力学元素**（Kinetic），让用户在思考业务目标而非具体属性编辑的层面操作数据。

> **参考**：https://www.palantir.com/docs/foundry/action-types/overview/

#### 2.5.1 核心构成

| 组成部分 | 说明 |
|---------|------|
| **Parameters** | 用户输入的参数，带标准化校验（如下拉选择新角色） |
| **Rules** | 业务规则与权限校验（如限制只有 HR 能执行） |
| **Side Effects** | 附带行为（如通知旧&新 Manager） |
| **Submission Criteria** | 执行前必须满足的条件 |

#### 2.5.2 事务模型

```
用户提交 Action
    │
    ▼  参数校验 + 规则检查
Action Service
    │
    ▼  原子事务（单次 Action = 一个事务）
Writeback Dataset（变更持久化）
    │
    ▼  Funnel 索引
Object Database（更新索引）
    │
    ▼  实时可见
所有用户应用（Workshop / Object Explorer 等）
```

**关键约束**：
- Object Storage V2 支持单次 Action 编辑最多 **10,000 个对象**
- 变更写入 Object Type 的 **Writeback Dataset**
- 同一 Action 逻辑和校验在所有应用中一致

#### 2.5.3 典型示例

`Assign Employee` Action：
1. 参数：新角色（下拉选择）
2. 规则：检查执行者是否为 HR
3. 变更：修改 `Employee.role` 属性
4. 副作用：创建 `Employee → Manager` Link + 通知旧&新 Manager

---

### 2.6 Interface（接口）

**定义**：描述 Object Type 形状和能力的抽象类型，提供 Ontology 级别的**多态性**。

> **参考**：https://www.palantir.com/docs/foundry/interfaces/interface-overview/

#### 2.6.1 与 Object Type 的对比

| 维度 | Object Type | Interface |
|------|-------------|-----------|
| 具体性 | 具体——有 Backing Dataset，可实例化 | 抽象——无 Backing Dataset，不可直接实例化 |
| Schema 来源 | Local Properties / Shared Properties | Interface Properties（推荐本地定义） |
| 视觉标识 | 实线图标 | 虚线图标 |
| 数据存储 | 有实际数据 | 无数据，借助实现它的 Object Type |

#### 2.6.2 核心机制

- **继承**（extend）：子 Interface 继承父 Interface 的所有属性，再添加新属性；支持多层继承
- **多实现**（implement）：一个 Object Type 可实现多个 Interface
- **Link Type Constraints**：Interface 可定义关联约束
- **多继承**：Interface 可 extend 多个父 Interface

#### 2.6.3 典型示例

```
Interface: Facility
├── Properties: facilityName, location
│
├── implements: Airport（+ runwayCount, iataCode）
├── implements: ManufacturingPlant（+ productionCapacity）
└── implements: MaintenanceHangar（+ maxAircraftSize）
```

基于 `Facility` Interface 的 Workflow 可以同时操作 `Airport`、`ManufacturingPlant`、`MaintenanceHangar`，无需关心具体类型。新增实现 `Facility` 的 Object Type 时，Workflow 自动兼容。

#### 2.6.4 平台支持现状

| 应用 | 支持程度 |
|------|---------|
| Ontology Manager | 完全支持 |
| Functions（TypeScript v2） | 完全支持 |
| Actions | 部分支持（不能直接引用 Interface Link Type） |
| OSS（Object Set Service） | 部分支持（Search/Sort 可用，Aggregation 开发中） |
| OSDK（TypeScript） | 支持 |
| OSDK（Java/Python） | 开发中 |
| Workshop | 尚未支持 |

---

### 2.7 Value Type（值类型）

**定义**：Field Type 的语义包装器，附加元数据和约束，增强类型安全与表达力。

> **参考**：https://www.palantir.com/docs/foundry/object-link-types/value-types-overview/

#### 2.7.1 与 Base Type 的区别

| 维度 | Base Type | Value Type |
|------|-----------|------------|
| 来源 | 静态预定义 | 用户动态创建 |
| 语义 | 无（仅数据类型） | 有（携带业务含义） |
| 约束 | 无 | 支持正则、枚举等 |
| 复用 | 内置 | 跨 Object Type + Pipeline 复用 |
| 范围 | 全平台 | 关联到 Space（不可跨 Space） |

#### 2.7.2 核心特点

- 不可用于 Default Ontology
- 支持版本化管理（区分 breaking / non-breaking 变更）
- 独立权限管理
- 在 Builder Pipeline 和 Ontology 中均可强制执行约束

#### 2.7.3 典型示例

| Value Type | Base Type | 约束 | 用途 |
|-----------|-----------|------|------|
| `Email` | String | 正则：`^[a-zA-Z0-9+_.-]+@[a-zA-Z0-9.-]+$` | 标准化邮箱地址 |
| `URL` | String | 正则：URL 格式 | Web 链接 |
| `UUID` | String | 正则：UUID 格式 | 唯一标识符 |
| `OrderStatus` | String | 枚举：`PENDING`, `SHIPPED`, `DELIVERED` | 订单状态 |

---

### 2.8 Function（函数）

**定义**：代码编写的业务逻辑，在服务端隔离环境执行，原生集成 Ontology。

> **参考**：https://www.palantir.com/docs/foundry/functions/overview/

#### 2.8.1 支持语言

| 语言 | 版本 |
|------|------|
| TypeScript | v1, v2 |
| Python | - |

#### 2.8.2 Ontology 集成能力

| 能力 | 说明 |
|------|------|
| 读取 Object 属性 | 直接访问 Object Type 的 Property 值 |
| 遍历 Link | 通过 Link Type 导航到关联对象 |
| 编辑 Object | 通过 Function-Backed Action 批量修改对象 |
| 接入外部系统 | External Function（Webhook）调用外部 API |
| 模型推理 | 调用 Foundry 中的 ML 模型 |

#### 2.8.3 典型使用场景

| 场景 | 具体用法 |
|------|---------|
| Workshop 变量计算 | 返回 Object Set 或聚合值 |
| Workshop 表格列 | Function-Backed Columns（派生列） |
| Workshop 图表 | Function-Backed Chart Aggregations |
| 复杂 Action | Function-Backed Action（更新多对象） |
| 自定义指标 | Quiver 中计算自定义指标 |
| Pipeline Builder | Python Function 作为 Sidecar Container |

---

## 三、Ontology 后端架构（Object Storage V2）

> **参考**：https://www.palantir.com/docs/foundry/object-backend/overview/

Object Storage V2 是 Foundry Ontology 的下一代架构（V1 Phonograph 将于 2026-06-30 废弃）。

### 3.1 架构组件

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Ontology Backend                             │
│                                                                     │
│  ┌─────────────────────┐     ┌──────────────────────────────────┐  │
│  │ OMS                 │     │ Object Data Funnel               │  │
│  │ (Ontology Metadata  │     │ (数据写入编排)                    │  │
│  │  Service)           │     │                                  │  │
│  │ · Object Type 定义  │     │ · 读取 Dataset / Streaming       │  │
│  │ · Link Type 定义    │     │ · 合并 User Edit                 │  │
│  │ · Action Type 定义  │     │ · 索引到 Object DB               │  │
│  └─────────┬───────────┘     └──────────┬───────────────────────┘  │
│            │                            │                           │
│            ▼                            ▼                           │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │               Object Database（索引存储）                     │  │
│  │  · 增量索引（默认开启）                                        │  │
│  │  · 支持数百亿对象 / 单 Object Type                            │  │
│  │  · 低延迟 Streaming 索引                                      │  │
│  │  · 最多 2000 Properties / Object Type                        │  │
│  └──────────────────────────────────────────────────────────────┘  │
│            │                            │                           │
│            ▼                            ▼                           │
│  ┌─────────────────────┐     ┌──────────────────────────────────┐  │
│  │ OSS                 │     │ Actions Service                  │  │
│  │ (Object Set Service)│     │ (用户编辑)                       │  │
│  │ · 搜索 / 过滤       │     │ · 结构化修改                     │  │
│  │ · 聚合              │     │ · 权限 + 条件校验                │  │
│  │ · 对象加载          │     │ · Action 历史日志                │  │
│  │ · Search Around     │     │ · 单次最多 10K 对象              │  │
│  └─────────────────────┘     └──────────────────────────────────┘  │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ Functions on Objects                                         │  │
│  │ · TypeScript / Python 业务逻辑                                │  │
│  │ · 原生读取 Object + Link                                     │  │
│  │ · Function-Backed Action                                     │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.2 Object Storage V2 核心能力

| 能力 | 说明 |
|------|------|
| 增量对象索引 | 默认开启，大幅提升索引性能 |
| 超大规模 | 单 Object Type 支持数百亿对象 |
| 多数据源 Object Type | 列/属性级权限控制 |
| 高吞吐 User Edit | 单次 Action 最多编辑 10,000 对象 |
| 低延迟 User Edit | 编辑后快速可见 |
| Schema 变更后编辑迁移 | Breaking Schema Change 后仍可迁移历史编辑 |
| Streaming 数据源 | 低延迟流式索引 |
| Spark 查询层 | 高规模 Search Around（默认限制 100K 对象）+ 精确聚合 |

### 3.3 Object Set 四种类型

| 类型 | 定义方式 | 生命周期 | 数据变化响应 |
|------|---------|---------|------------|
| **Static** | PK 列表 | 持久 | 不变 |
| **Dynamic** | 过滤器定义 | 持久 | 新数据匹配时自动更新 |
| **Temporary** | 运行时生成 | 24h 过期 | - |
| **Permanent** | 显式保存 | 持久 | 取决于 Static/Dynamic |

---

## 四、OSDK（Ontology SDK）

> **参考**：https://www.palantir.com/docs/foundry/ontology-sdk/overview/

OSDK 将 Ontology 暴露为开发者友好的 SDK，支持 TypeScript（NPM）、Python（Pip/Conda）、Java（Maven）、以及通过 OpenAPI Spec 生成的其他语言绑定。

### 4.1 核心特性

| 特性 | 说明 |
|------|------|
| **代码生成** | 从 Ontology 元数据自动生成类型安全的 SDK 代码 |
| **强类型** | 所有 Object Type、Property、Link 都有编译时类型检查 |
| **集中维护** | Ontology 变更自动同步到 SDK |
| **安全** | Token scoped 到特定 Ontology 实体 + 用户权限 |

### 4.2 开发流程

```
1. Developer Console 创建应用
2. 选择需要访问的 Ontology 实体（Object Type / Action Type 等）
3. 生成 OSDK（TypeScript / Python / Java）
4. 使用生成的代码读写 Ontology
5. 可选：部署到 Foundry Hosting
```

---

## 五、对标分析：现有 M3 设计 vs Palantir Ontology

现有设计文档（[2026-04-09-platform-upgrade-design.md](2026-04-09-platform-upgrade-design.md)）中 M3（Object Set）和 M3b（User Edit）的能力定义，与 Palantir Ontology 实际模型的对标分析。

### 5.1 能力覆盖对比

| Palantir Ontology 概念 | 现有 M3 设计覆盖 | 差距说明 |
|----------------------|:---:|----------|
| Object Type 定义 | ✅ L1 | M3 L1 含 Object Type 定义（字段映射关系） |
| Property 类型系统 | ⚠️ 隐含 | 未明确定义支持的属性类型清单和约束 |
| Primary Key / Title Key | ⚠️ 隐含 | 未显式提出 PK 确定性要求 |
| Shared Property | ❌ 未覆盖 | 跨 Object Type 的属性复用机制未提及 |
| Link Type（FK） | ⚠️ L3 | L3 提到"跨 Object Type 关联查询"，但未细化 FK 实现 |
| Link Type（Join Table） | ❌ 未覆盖 | M:N 关联的 Join Table 机制未提及 |
| Link Type（Object-Backed） | ❌ 未覆盖 | 携带元数据的关联未提及 |
| Action Type | ❌ 未覆盖 | 用户编辑通过 M3b User Edit 实现，但未对标 Action Type 的完整模型（Parameters/Rules/Side Effects） |
| Action 事务模型 | ⚠️ 部分 | M3b L1 有"手动触发合并"但无原子事务语义 |
| Interface（多态） | ❌ 未覆盖 | Ontology 多态机制未提及 |
| Value Type（约束） | ❌ 未覆盖 | 属性级语义约束未提及 |
| Function | ❌ 未覆盖 | 服务端业务逻辑 + Ontology 原生集成未提及 |
| Object Set（Static/Dynamic） | ⚠️ L1 | M3 L1 有基础查询 API，但未区分 Static/Dynamic Object Set |
| OSDK | ❌ 未覆盖 | Ontology 的外部 SDK 消费方式未提及 |
| Object Storage V2 架构 | ❌ 未覆盖 | 索引/查询/编辑的后端架构未涉及 |

### 5.2 关键差距总结

1. **数据模型深度不足**：M3 定义了"做什么"（Object Type 定义、增量写入、对象查询），但缺少"怎么做"的数据模型——Property 类型系统、PK 确定性约束、Backing Datasource 映射机制
2. **关联模型缺失**：仅在 L3 提到"跨 Object Type 关联查询"，未对标 Palantir 的三种 Link Type 实现方式
3. **写回模型简化**：M3b User Edit 聚焦于"变更采集→合并"的 Pipeline 思路，而 Palantir 的 Action Type 是完整的事务模型（参数校验 + 规则 + 副作用 + 原子提交）
4. **缺少抽象机制**：Interface 和 Value Type 这两个高级建模能力在现有设计中完全缺失
5. **缺少编程接口**：OSDK 作为 Ontology 对外暴露的核心 API 层未被规划

### 5.3 建议补充方向

| 优先级 | 补充方向 | 对应迭代 |
|---------|---------|---------|
| **P0** | Property 类型系统 + PK/Title Key 约束 + Backing Datasource 映射 | I1（基础闭环） |
| **P0** | Link Type（至少 FK 方式）| I1 |
| **P1** | Action Type 事务模型（替代当前 M3b 的 Pipeline 合并方式）| I2 |
| **P1** | Object Set Static/Dynamic 区分 | I2 |
| **P2** | Link Type（Join Table + Object-Backed）| I3 |
| **P2** | Interface（多态）| I3 |
| **P3** | Value Type（约束系统）| I3-I4 |
| **P3** | OSDK（外部 SDK）| I3-I4 |
| **P3** | Function（服务端逻辑执行）| I4 |

---

## 六、核心对象关系图

> 见 `diagrams/ontology-data-model.drawio` 及导出的 PNG。

该图展示 8 类核心业务对象之间的关系：
- Object Type 拥有 Property，可使用 Shared Property
- Object Type 之间通过 Link Type 关联
- Object Type 实现 Interface
- Property 可使用 Value Type 约束
- Action Type 操作 Object / Property / Link
- Function 驱动 Action 和应用逻辑

---

## 七、后端架构图

> 见 `diagrams/ontology-backend-architecture.drawio` 及导出的 PNG。

该图展示 Object Storage V2 的六大组件及数据流：
- OMS 管理元数据
- Funnel 从 Dataset / Streaming / User Edit 索引数据到 Object Database
- OSS 提供查询服务
- Actions Service 处理编辑
- Functions 执行业务逻辑

---

## 八、Dataset vs Stream：数据源能力深度对比

> **参考**：
> - https://www.palantir.com/docs/foundry/data-integration/datasets/
> - https://www.palantir.com/docs/foundry/data-integration/streams/
> - https://www.palantir.com/docs/foundry/building-pipelines/pipeline-types/
> - https://www.palantir.com/docs/foundry/building-pipelines/stream-vs-batch/
> - https://www.palantir.com/docs/foundry/object-indexing/funnel-streaming-pipelines/

### 8.1 本质定义

| 维度 | Foundry Dataset | Foundry Stream |
|------|----------------|----------------|
| **本质** | 文件集合的包装器，存储在 Backing File System（S3/HDFS） | 行集合的包装器，持久化于 Hot Buffer + Cold Storage |
| **数据结构** | 结构化（Parquet/Avro）、半结构化（JSON/XML）、非结构化（PDF/图片） | 仅结构化（必须有 Schema，Avro 格式存储） |
| **更新粒度** | 事务级（Transaction = 一批文件的原子变更） | 行级（每行是独立的"事务"，无批次边界） |
| **Schema** | 可选（非结构化数据集无 Schema） | 必须（Stream 天然是表格化的） |
| **版控机制** | 事务历史 + 分支（"Git for Data"） | 同样支持分支和版控，但事务边界为行级 |

### 8.2 存储架构

#### Dataset 存储

```
Dataset
├── Transaction 1 (SNAPSHOT) → Files: A, B
├── Transaction 2 (APPEND)   → Files: C
├── Transaction 3 (UPDATE)   → Files: A' (覆盖 A)
└── Transaction 4 (DELETE)   → 移除 B
    └── 当前视图：A', C
```

Dataset 的四种事务类型：

| 事务类型 | 行为 | Pipeline 影响 |
|---------|------|-------------|
| **SNAPSHOT** | 用全新文件集合替换当前视图 | 批处理管道的基础 |
| **APPEND** | 向当前视图添加新文件，不允许修改已有文件 | 增量管道的基础，支持端到端增量处理 |
| **UPDATE** | 添加新文件 + 可覆盖已有文件 | 会打破增量管道的 append-only 前提，下游需回退到 SNAPSHOT |
| **DELETE** | 从当前视图移除文件引用（底层文件不删） | 用于数据保留策略（合规/成本） |

#### Stream 存储（双层架构）

```
Stream
├── Hot Buffer（热存储）
│   ├── 低延迟可用，秒级
│   ├── 至少一次语义（AT_LEAST_ONCE）
│   └── 可选精确一次（EXACTLY_ONCE，默认 2s checkpoint 间隔）
│
└── Cold Storage（冷存储）
    ├── 每隔数分钟从 Hot Buffer 归档
    ├── 表现为标准 Foundry Dataset
    └── 任何 Foundry 应用均可读取
```

关键设计：**Stream 的 Cold Storage 就是一个标准 Dataset**。这意味着即使应用不支持低延迟读取，也能通过 Cold Storage 获取流数据（只是有数分钟延迟）。

### 8.3 管道类型与适用场景

| 维度 | Batch Pipeline | Incremental Pipeline | Streaming Pipeline |
|------|---------------|---------------------|-------------------|
| **数据源** | Dataset | Dataset | Stream |
| **延迟** | 高（全量重算） | 低（分钟级） | 极低（< 15 秒端到端） |
| **复杂度** | 低 | 中 | 高 |
| **计算成本** | 中（重复计算） | 低（仅处理增量） | 高（持续运行） |
| **数据规模弹性** | 低（规模增大 → 不可控） | 高 | 高 |
| **支持语言** | Python, Java, SQL, Pipeline Builder | Python, Java, Pipeline Builder | Java, Pipeline Builder（**不支持 Python**） |
| **运行引擎** | Spark | Spark | **Apache Flink** |
| **适用数据量** | < 数千万行 | 任意规模 | 任意规模 |
| **推荐起步** | ✅ 最佳起步选择 | 验证用例后升级 | 仅低延迟刚需时使用 |

Foundry 还提供 **Faster Pipeline**（基于 DataFusion/Rust），可加速中小数据集的 Batch/Incremental 处理，但不支持所有表达式。

### 8.4 Ontology 集成差异

这是两种数据源接入 Ontology 时最关键的能力差异：

| 能力 | Dataset-Backed Object Type | Stream-Backed Object Type |
|------|:---:|:---:|
| **Funnel 索引方式** | Batch（定时/触发） | Streaming（持续、秒级） |
| **端到端延迟** | 分钟~小时（取决于 Pipeline 类型） | **< 15 秒**（exactly-once），**< 5 秒**（at-least-once） |
| **User Edit（Action）** | ✅ 完全支持 | ❌ **不支持**（需创建辅助非流式 Object Type 或将编辑推入上游 Stream） |
| **多数据源对象（MDO）** | ✅ 支持 | ❌ 不支持 |
| **最大 Properties / Type** | ≤ 2000 | **≤ 250** |
| **最大单行大小** | 无硬限制（受 Parquet 块大小约束） | **≤ 1MB** |
| **Workshop 实时刷新** | ❌ 需手动刷新 | ✅ **Workshop 支持 Live Data Refresh** |
| **其他前端应用实时刷新** | ❌ | ❌（Workshop 之外需手动刷新） |
| **更新策略** | Transaction 控制（SNAPSHOT/APPEND/UPDATE/DELETE） | "最新更新覆盖"（changelog 模式，要求输入有序） |
| **乱序处理** | N/A（批处理无序概念） | ⚠️ 不处理乱序——要求上游保证顺序，否则产生脏数据 |
| **Pipeline 监控** | 完善（Health Check / Build 状态） | ⚠️ 开发中（暂无 Funnel Streaming 指标监控） |

### 8.5 一致性语义

Stream 提供两种一致性保证，而 Dataset 天然是事务性的：

| 语义 | 适用于 | 保证 | 延迟影响 | 复杂度 |
|------|-------|------|---------|-------|
| **Dataset 事务** | Dataset | 事务原子性（全部成功或全部回滚） | N/A | 低 |
| **AT_LEAST_ONCE** | Stream | 消息至少投递一次，可能重复 | 低（无额外阻塞） | 下游需幂等处理 |
| **EXACTLY_ONCE** | Stream | 消息精确投递一次（通过 Checkpoint 实现） | 较高（默认 2s checkpoint 间隔，记录在 checkpoint 完成后才可见） | 低（系统保证） |

> **关键设计决策**：AT_LEAST_ONCE 延迟更低但下游需处理重复；EXACTLY_ONCE 更安全但 Checkpoint 间隔引入额外延迟。Source 层（Extract/Export）目前仅支持 AT_LEAST_ONCE。

### 8.6 吞吐与性能

| 指标 | Dataset | Stream |
|------|---------|--------|
| **水平扩展** | Spark Executor 数量 | Flink Task Manager 数量 + 分区数 |
| **分区** | 由 Parquet/文件结构决定 | 用户可控（每增加 1 分区 ≈ +5MB/s 吞吐） |
| **状态管理** | 无（Batch 每次全量计算） | Flink 有状态操作（需警惕无界状态增长 → OOM） |
| **典型端到端延迟** | 分钟~小时 | Ingestion ~1-2s → Transform ~1-5s → Sync ~1-5s |
| **容错** | Build 失败可重试 | Checkpoint 恢复（从最近检查点续跑，不重复已处理数据） |

### 8.7 连接器生态

**Stream 数据源连接器**（pull 或 push 模式）：

| 连接器 | 说明 |
|--------|------|
| Apache Kafka | 专用连接器 |
| Amazon Kinesis | 专用连接器 |
| Amazon SQS | 专用连接器 |
| Aveva PI | 专用连接器 |
| Google Pub/Sub | 专用连接器 |
| ActiveMQ / IBM MQ / RabbitMQ / MQTT / Solace | 通过 External Transform |
| HTTP Push | Stream Proxy 直接推送 |

**Dataset 数据源**：几乎支持所有 Foundry Data Connection 连接器（JDBC、文件、API 等），远多于 Stream 连接器。

### 8.8 使用场景选择指南

```
需要 < 1 分钟端到端延迟？
  ├─ 是 → Stream + Streaming Pipeline
  │         ├─ 需要 User Edit？→ 创建辅助 Dataset-Backed Object Type
  │         └─ Properties > 250？→ 拆分为多个较小 Object Type
  │
  └─ 否 → Dataset
           ├─ 数据量 < 数千万行？→ Batch Pipeline
           ├─ 数据量大且大部分不变？→ Incremental Pipeline
           └─ 需要中小数据集加速？→ Faster Pipeline (DataFusion)
```

### 8.9 关键设计启示

1. **Stream Cold Storage = Dataset**：Palantir 的设计精妙之处在于 Stream 数据会自动归档为标准 Dataset，避免了"流/批两套系统"的割裂。任何不支持低延迟的应用都可以透明地通过 Cold Storage 使用流数据。

2. **Ontology 统一抽象**：无论底层是 Dataset 还是 Stream，对上层 Ontology 应用（OSS 查询、Workshop 展示等）来说，Object Type 的接口是统一的。差异仅在于索引延迟和部分功能限制（User Edit、MDO、Property 上限）。

3. **流式 Object Type 的限制是有意的**：250 Properties / 1MB 行大小 / 不支持 User Edit 等限制，本质上是为了保证低延迟的吞吐性能。这些约束推动用户正确建模——流式对象应该小而精，代表实时状态快照而非完整实体。

4. **渐进式升级路径**：Palantir 明确建议 Batch → Incremental → Streaming 的渐进路径，而非一步到位。Streaming 的复杂度和成本容易被低估。

---

*文档版本：v1.1 | 调研日期：2026-04-15 | 新增：第八章 Dataset vs Stream 深度对比*
