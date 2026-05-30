# Foundry Schedule 模块运行模式调研计划

**日期：** 2026-05-30  
**类型：** 调研计划 / 场景脑暴 / 并行任务拆解  
**背景决策：** 业务周期对齐调度与 freshness 调度完全拆开，不混为一谈。  
**关联文档：** `docs/synthesis/dataworks-vs-palantir-integration.md`

---

## 核心判断

1. 【决策】本轮调研只研究 Foundry schedule / build / trigger 的真实运行模式，不再把它等同于 DataWorks 的业务周期实例调度。
2. 【推断】Foundry schedule 的核心问题域至少包括 trigger state、build range、staleness、branch、Data Connection sync、incremental catch-up 和运维治理。
3. 【风险】复合触发器的 `AND/OR` 组合容易被误解为业务时间对齐；本轮必须重点核实 event satisfied 状态、schedule run 窗口和多输入组合行为。
4. 【计划】调研拆成 6 个并行 Agent 任务，分别核实触发器、build 解析、增量追平、Data Connection sync、运维治理、业务时间边界。
5. 【输出】最终综合报告应落到 `docs/synthesis/foundry-schedule-module-deep-dive.md`，并反向更新本计划中被证实或证伪的假设。

---

## 一、脑暴场景总表

### 1. Trigger 类型与组合

| 场景 | 要核实的问题 |
|---|---|
| time trigger 单独使用 | cron、timezone、DST、错过时间点、重复时间点如何处理 |
| data updated event 单独使用 | Dataset transaction commit 是否就是 event 满足条件 |
| logic updated event 单独使用 | JobSpec / transform logic / code change 如何形成 logic event |
| job succeeded event | job 成功事件是否可作为另一个 schedule 触发条件 |
| schedule succeeded event | schedule 成功事件如何串联 pipeline |
| AND(time, event) | event 先到、time 后到时是否触发；time 先到、event 后到时是否等下一个 time |
| OR(time, event) | 任一条件满足是否立即触发；是否可能一天内多次触发 |
| AND(A updated, B updated) | 两个事件不同时到达时如何累计 satisfied 状态 |
| OR(A updated, B updated) | 任一输入更新是否触发；后续另一个输入更新是否再次触发 |
| AND(time, OR(A, B)) | 到时点时只要 A/B 任一发生是否触发 |
| OR(time, AND(A, B)) | 到时点触发与双输入到齐触发是否都会产生 run |
| 多层嵌套 trigger | 官方是否支持任意嵌套，是否有限制 |
| event state reset | schedule run 后 event satisfied 状态是否被消费/reset |
| running 时再触发 | 前一次 run 未结束时，后续 trigger 是否排队或保持 triggered |

### 2. Build 解析与执行范围

| 场景 | 要核实的问题 |
|---|---|
| schedule run 与 build | schedule run 是否一定创建 build；什么情况下 ignored |
| target dataset fresh | 输入和 logic 未变时是否跳过 |
| target dataset stale | 输入 transaction 或 logic version 变化如何触发重算 |
| force build | 是否绕过 staleness；是否会强制构建所有范围内 Dataset |
| single build | 只构建 target 本身的准确含义 |
| full build | target 及 upstream 依赖如何展开 |
| connecting build | input 到 target 的路径如何确定 |
| downstream build | 是否支持从某 Dataset 向下游构建 |
| excluded datasets | 排除节点对 graph traversal 的影响 |
| dynamic graph evaluation | schedule 每次是否重新解析 graph，而不是保存静态 job 列表 |
| branch selection | schedule 所在 branch、fallback branch、target branch 如何作用 |
| build locking | output transaction lock、并发写、输入正在被其他 build 改变时如何处理 |

### 3. Incremental 与追平

| 场景 | 要核实的问题 |
|---|---|
| incremental input added/current/previous | scheduled build 时每种 read mode 如何取数 |
| transaction limit | 单次 build 只处理部分 backlog 时输出是否仍 stale |
| re-trigger upon successful build | 如何多次触发直到目标不再 stale |
| APPEND input | 正常增量路径 |
| UPDATE input | 是否破坏 append-only 并 fallback snapshot |
| SNAPSHOT input | 是否触发全量或重置事务历史起点 |
| semantic_version change | logic version 变化如何触发 full recompute |
| force build + incremental | force 是否改变增量/全量选择 |
| schedule 高频触发 | 是否会重复处理、排队、ignored 或触发 build storm |

### 4. Data Connection / Sync

| 场景 | 要核实的问题 |
|---|---|
| external source change | Foundry 是否能感知外部源变化 |
| sync schedule | sync 如何通过 schedule/manual run/build system 执行 |
| force build sync | 为什么 sync 常需要 force build |
| incremental sync | cursor/watermark/CDC 与 schedule 的关系 |
| batch sync limits | media/batch limits 与 re-trigger 的关系 |
| sync output transaction | sync 产出的 transaction 类型与 lineage 可见性 |
| sync 与 transform schedule 分离 | raw ingestion 与 downstream transform 是否应独立调度 |
| connector failure/retry | 凭证、网络、源不可用对 schedule run 的影响 |

### 5. 运维、权限与治理

| 场景 | 要核实的问题 |
|---|---|
| schedule owner | user scope 和 project scope 的区别 |
| user disabled / lost permission | schedule 是否还能运行 |
| usage account | 计费与资源归属如何绑定 |
| compute profile | schedule 是否指定 compute profile 或由 job 决定 |
| priority queue | 资源队列、优先级、排队行为 |
| retry attempts | failed job retry 与 failed schedule run 的关系 |
| pause/disable schedule | 暂停后 event state 是否保留 |
| notifications | 成功/失败/健康告警如何配置 |
| troubleshooting | ignored / failed / succeeded 如何排查 |
| best practices | 避免多 schedule 管理同一 Dataset、避免过宽 graph、force build 风险 |

### 6. 业务时间建模边界

| 场景 | 要核实的问题 |
|---|---|
| latest view 输出 | 是否可直接使用 freshness trigger |
| 单事实表 + snapshot 维表 | 业务日期是否可由事实表主时钟决定 |
| 多事实表同账期汇总 | Foundry trigger 是否无法保证 business_date 对齐 |
| time trigger + data updated | 是否只是 freshness 条件，不是业务窗口 |
| backfill / rerun | Foundry build/force build 与 DataWorks 补数/重跑的差异 |
| ready manifest | 自研平台是否必须补充 business-date ready barrier |
| partition manifest | 同一业务日期多次 transaction 如何决定 active version |
| run-to-transaction mapping | 业务 run 与 Dataset transaction 如何关联 |

---

## 二、并行 Agent 任务拆解

| Agent | 主题 | 核实边界 | 预期输出 |
|---|---|---|---|
| A | Trigger 语义与组合逻辑 | time/event/AND/OR/satisfied state/timezone/DST/running re-trigger | 触发器场景表、状态语义、来源 |
| B | Build 解析与 staleness | schedule run、ignored、fresh/stale、force build、build range、branch、locking | build lifecycle、场景表、来源 |
| C | Incremental 与追平 | transaction ranges、limits、re-trigger、semantic version、snapshot fallback | 增量追平流程、风险表、来源 |
| D | Data Connection / Sync | 外部源 freshness、sync schedule、force build sync、incremental sync | sync lifecycle、推荐调度边界、来源 |
| E | 运维治理 | 权限主体、scope、retry、notification、health、resource、best practices | 运维风险表、治理建议、来源 |
| F | 业务时间边界 | Foundry 能力与 DataWorks 业务周期调度对照 | 能力缺口表、自研平台建议、来源 |

---

## 三、本轮待证伪假设

1. Foundry compound trigger 是有状态布尔闩锁，不是事件时间 join。
2. `AND(A updated, B updated)` 只表示上次 run 后 A/B 都更新过，不表示同一 `business_date` 到齐。
3. schedule run 可以被 ignored，因为目标 Dataset 已 up-to-date。
4. force build 绕过 staleness，但不解决业务时间对齐。
5. Data Connection sync 与普通 Transform 在 staleness 上不同，因为外部源变化不一定被 Foundry 内部 graph 感知。
6. incremental transaction limit + re-trigger 是 Foundry 追平 backlog 的关键机制。
7. 多个 schedule 管理同一 target Dataset 可能造成运行理解复杂，后触发 schedule 可能因为 freshness 被 ignored。

---

## 四、综合报告结构草案

1. 核心结论：Foundry schedule 的真实主语是 Dataset graph freshness，不是业务周期实例。
2. Trigger 模型：trigger state、AND/OR、time/event 组合、运行中再触发。
3. Build 模型：schedule run、build resolution、staleness、force、build range、branch。
4. Incremental 模型：transaction ranges、limits、re-trigger、fallback。
5. Data Connection 模型：外部源、sync、force build、downstream separation。
6. 运维模型：权限、scope、retry、notifications、health、best practices。
7. 与 DataWorks 的边界：business-cycle scheduler 与 freshness scheduler 的拆分。
8. 自研平台设计：Run Identity、Data Version Identity、ready manifest、partition manifest、run-to-transaction mapping。

