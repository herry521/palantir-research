# Palantir Data Integration 能力地图汇报页设计

**日期：** 2026-06-24  
**状态：** 设计待确认  
**范围：** 基于 Palantir 官方能力对象绘制 Data Integration 功能全景图，并支持现场配置已完成模块点亮状态。

## 摘要与洞察

1. 【事实】能力地图严格对齐 Palantir 官方术语，不纳入 `Run Identity`、`Active Pointer`、`Shared IR` 等自研架构抽象。
2. 【建议】页面采用“主链路 + 驱动观察层 + 支撑层”的结构，避免把所有模块画成同权功能清单。
3. 【建议】点亮状态配置在二级能力上，一级模块由二级能力自动汇总完成度和风险状态。
4. 【建议】页面默认可现场编辑；通过“演示模式”隐藏配置控件，保留干净的汇报视觉。
5. 【建议】状态存储使用浏览器 `localStorage`，并提供 JSON 导入/导出，便于用户自行维护进展。

## 1. 目标

构建一个静态 HTML 汇报页，用于展示 Palantir Data Integration 能力全景，并允许用户现场配置各能力完成状态。

页面要回答三个问题：

- Data Integration 的官方能力对象有哪些？
- 这些能力如何组成一条数据加工与对象化消费链路？
- 当前哪些能力已完成、进行中、未开始或存在风险？

## 2. 非目标

- 不重新定义自研平台架构抽象。
- 不把业务漏斗分析误写为 Palantir `Data Funnel`。
- 不实现后端服务、数据库或多人协作状态同步。
- 不做完整研究站点重构，只新增一个独立汇报页和必要样式/脚本。

## 3. 信息架构

页面分三层展示。

### 3.1 主链路

主链路表达数据从外部进入 Foundry，再进入加工、构建和对象化消费的过程。

```text
Data Connection / Connectivity
  -> Core Data Objects
  -> Pipeline Authoring + Pipeline Types
  -> Builds
  -> Ontology / Object Backend
```

中文解释：

- `Data Connection / Connectivity`：数据连接与接入。
- `Core Data Objects`：Dataset、Stream、View 等核心数据对象。
- `Pipeline Authoring + Pipeline Types`：Pipeline 开发入口与 Batch / Incremental / Streaming 类型。
- `Builds`：计算 Dataset 新版本的构建机制。
- `Ontology / Object Backend`：Object Type、Object Set、Object Data Funnel 和对象索引。

### 3.2 驱动与观察层

```text
Schedules
Data Lineage
```

`Schedules` 负责触发 Build；`Data Lineage` 负责理解 graph、发起 build、查看 stale 状态、权限和影响范围。

### 3.3 支撑层

```text
Health / Quality
Security / Governance
```

支撑层保障主链路可信、可治理、可观察。它们不放在主链路中央，但要出现在全景图下方。

## 4. 能力数据

能力数据以 JavaScript 对象维护在页面脚本中，后续可迁移到独立 JSON 文件。模块来自 `docs/synthesis/data-integration-palantir-aligned-capability-map.md`。

### 4.1 模块字段

```json
{
  "id": "data-connection",
  "name": "Data Connection / Connectivity",
  "zhName": "数据连接与接入",
  "zone": "main",
  "description": "连接外部系统、配置 source、执行 sync、接收 push stream，并把 Foundry 数据 export 到外部系统。",
  "capabilities": []
}
```

字段说明：

| 字段 | 含义 |
|---|---|
| `id` | 稳定模块 ID，用于状态存储 |
| `name` | Palantir 英文名 |
| `zhName` | 中文解释名 |
| `zone` | `main`、`driver`、`support` |
| `description` | 汇报页内短解释 |
| `capabilities` | 二级能力清单 |

### 4.2 二级能力字段

```json
{
  "id": "batch-sync",
  "name": "Batch sync",
  "zhName": "批量同步",
  "core": true,
  "children": ["Full sync", "File-based syncs"]
}
```

字段说明：

| 字段 | 含义 |
|---|---|
| `id` | 模块内稳定能力 ID |
| `name` | Palantir 能力名 |
| `zhName` | 中文解释名 |
| `core` | 是否参与一级模块完成度计算 |
| `children` | 可选三级能力，主要用于解释，不直接参与完成度 |

### 4.3 初始模块清单

```text
main:
  1. Data Connection / Connectivity
  2. Core Data Objects
  3. Pipeline Authoring
  4. Pipeline Types
  5. Builds
  6. Ontology / Object Backend

driver:
  7. Schedules
  8. Data Lineage

support:
  9. Health / Quality
  10. Security / Governance
```

说明：`Pipeline Authoring` 和 `Pipeline Types` 可以视觉上合并成一个主链路阶段，但数据上保持两个模块，方便分别点亮开发入口和执行类型。

## 5. 状态模型

每个二级能力有一个状态。

| 状态 | 中文 | 颜色 | 含义 |
|---|---|---|---|
| `not-started` | 未开始 | 灰色 | 尚未交付或未确认 |
| `in-progress` | 进行中 | 蓝色 | 已启动但未完成 |
| `done` | 已完成 | 绿色 | 可用于汇报点亮 |
| `risk` | 风险 | 红色 | 存在阻塞、偏差或待确认问题 |

一级模块状态由核心二级能力汇总：

```text
doneCore = done 的核心二级能力数量
totalCore = 核心二级能力总数
progress = doneCore / totalCore

如果任一核心能力为 risk：模块显示风险角标
如果 progress = 1：模块强点亮
如果 0 < progress < 1：模块半点亮
如果 progress = 0：模块未点亮
```

非核心能力显示状态，但不参与一级模块完成度。

## 6. 交互设计

### 6.1 现场配置

页面默认处于编辑状态。每个二级能力右侧显示状态按钮。

点击状态按钮按顺序循环：

```text
未开始 -> 进行中 -> 已完成 -> 风险 -> 未开始
```

每次切换后立即更新：

- 一级模块点亮状态。
- 顶部完成度指标。
- localStorage 中的状态配置。

### 6.2 演示模式

顶部提供 `演示模式` 开关。

开启后：

- 隐藏每个能力的状态按钮。
- 保留颜色、完成度、风险角标。
- 顶部只显示统计指标和图例。

### 6.3 导入 / 导出

页面提供：

- `导出 JSON`：下载或复制当前状态配置。
- `导入 JSON`：粘贴配置后恢复状态。
- `重置`：恢复全部 `not-started`。

JSON 格式：

```json
{
  "version": 1,
  "updatedAt": "2026-06-24T00:00:00.000Z",
  "statuses": {
    "data-connection.batch-sync": "done",
    "pipeline-types.streaming-pipelines": "in-progress"
  }
}
```

## 7. 页面布局

### 7.1 顶部摘要

顶部展示：

- 页面标题：`Palantir Data Integration 能力地图`
- 简短说明：严格对齐 Palantir 官方能力对象。
- 总完成率。
- 已完成、进行中、风险数量。
- 演示模式、导入、导出、重置按钮。

### 7.2 全景图

布局建议：

```text
┌────────────────────────────────────────────────────────────┐
│ Schedules                         Data Lineage             │
├────────────────────────────────────────────────────────────┤
│ Data Connection -> Core Data Objects -> Pipeline -> Builds │
│                                      -> Ontology Backend   │
├────────────────────────────────────────────────────────────┤
│ Health / Quality                 Security / Governance      │
└────────────────────────────────────────────────────────────┘
```

主链路用横向流程，驱动层在上方，支撑层在下方。

### 7.3 模块卡片

每张模块卡片包含：

- 英文模块名。
- 中文模块名。
- 简短定位。
- 完成度条。
- 二级能力列表。
- 三级能力小字说明。

卡片设计应偏汇报和架构图，不做过重装饰。

## 8. 视觉规则

- 主链路使用更强视觉权重。
- 驱动层和支撑层使用较轻背景和边框。
- 状态颜色全页面一致：
  - 绿色：已完成。
  - 蓝色：进行中。
  - 红色：风险。
  - 灰色：未开始。
- 避免使用大量渐变和装饰图形。
- 页面要适合 16:9 截图。
- 移动端只需可阅读，主要目标是桌面汇报。

## 9. 验证

实现后至少验证：

- 页面可直接通过本地 HTML 打开。
- 点击状态按钮后一级模块完成度正确变化。
- 刷新页面后状态不丢失。
- 演示模式能隐藏编辑控件。
- 导出 JSON 后可重新导入恢复。
- 页面在常见桌面宽度下文字不重叠。

## 10. 依赖文档

- `docs/synthesis/data-integration-palantir-aligned-capability-map.md`
- `docs/synthesis/data-integration-capability-panorama-term-alignment.md`
- Palantir Data Connection、Datasets、Builds、Pipeline types、Scheduling、Data Lineage、Object Backend、Object Types、Object Sets 官方文档。
