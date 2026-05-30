# Foundry Schedule 模块运行模式深度调研

**日期：** 2026-05-30  
**类型：** 综合调研报告  
**输入：** 6 个并行 Agent 调研结果、Palantir 官方公开文档、既有 DataWorks 对照研究  
**关联计划：** `docs/raw/38-foundry-schedule-module-research-plan.md`  
**关联决策：** `docs/synthesis/dataworks-vs-palantir-integration.md`

---

## 核心结论

1. 【事实】Foundry Schedule 的主语是 Dataset graph build，不是业务周期实例。Schedule trigger 满足后，平台动态解析 build 范围、branch/scope、staleness、build locking，再决定是否真正创建 build。
2. 【事实+推断】Trigger 是状态机而不是业务时间 join。公开语义可推导为 trigger expression tree + event latch + run-boundary reset：Time trigger 是瞬时 wall-clock 条件；event trigger 是锁存 satisfied 状态；`AND/OR` 只组合 trigger satisfied 状态，不保证多个输入属于同一 `business_date/data_interval`。
3. 【事实】Schedule run 的 `Succeeded` 只表示 build 被成功发起，不代表 build/job 最终成功；`Ignored` 通常表示没有创建 build，多数情况下因为目标已 up-to-date。
4. 【事实】Data Connection sync 是特殊边界：外部源变化不被内部 staleness 可靠感知，sync 通常需要单独 schedule + force build；下游 Transform 再使用普通 freshness/staleness。
5. 【决策】自研平台必须把 business-cycle scheduling 和 freshness scheduling 拆开。Foundry 的 Schedule 能力可用于 Data Version Identity；任何声明业务日期或数据区间的输出，必须先经过 ready manifest / business-cycle scheduler。

---

## 术语来源澄清

| 术语 / 表达 | 归属 | 说明 |
|---|---|---|
| `schedule` / `trigger` / `time trigger` / `event trigger` | Palantir 官方术语 | Schedules 文档说明 trigger 定义 build 运行条件；Trigger Reference 分别定义 time/event trigger。 |
| `compound trigger` / `AND trigger` / `OR trigger` | Palantir 官方术语 | Trigger Reference 明确 compound trigger 由多个 component trigger 通过 `AND` / `OR` 组合而成，并支持嵌套。 |
| `event trigger remains satisfied` | Palantir 官方语义 | 官方说明 event 发生后保持 satisfied，直到整个 trigger 满足并 schedule run。 |
| “状态机”“锁存”“gate”“不是业务时间 join” | 本文解释性抽象 | 用来解释 Palantir 触发语义：它组合的是事件满足状态，不是 DataWorks 式业务日期依赖。 |
| `business_date` / `data_interval` / `ready manifest` / `business-cycle scheduler` | 自研平台设计概念 | 这些不是 Foundry Schedule 官方原生概念，是为承载业务周期对齐、补数、重跑和同周期依赖而引入。 |

因此，本文可以继续使用 `compound trigger`，但页面和设计文档必须明确：它是 Foundry 的 trigger expression 概念，不是业务周期调度模型。

---

## 一、调研拆分

| Agent | 主题 | 主要结论 |
|---|---|---|
| A | Trigger 语义与组合逻辑 | event trigger 是锁存 satisfied 状态；AND/OR 可嵌套；running 时再次触发会保持 triggered |
| B | Build 解析与 staleness | schedule 触发后动态解析 graph；fresh output 跳过；force build 绕过 staleness |
| C | Incremental 与追平 | transaction limit 会让成功 build 后仍 stale；re-trigger upon successful build 负责追平 |
| D | Data Connection / Sync | sync 输入在外部，Foundry 不知道源端是否变化；sync 层建议单独 force build |
| E | 运维治理 | project-scoped 优于 user-scoped；Succeeded 不等于 build 成功；重试、健康检查、资源队列需独立治理 |
| F | 业务时间边界 | Foundry trigger 不能表达 DataWorks 式业务日期配对；需要 ready manifest / partition manifest |

---

## 二、Foundry Schedule 的基本运行模型

Foundry Schedule 可以抽象为：

```text
Trigger satisfied
  -> Schedule run
    -> Dynamic graph resolution
      -> Build resolution
        -> Staleness / force-build decision
          -> Job execution
            -> Dataset transactions
```

关键点：

- Schedule 保存的是触发条件和 build 范围规则，不是固定 job 清单。【事实】
- 每次触发时会重新评估 included datasets，以适应 pipeline 变化。【事实】
- Build 范围受 target、excluded datasets、build type、scope、branch 和 fallback branch 影响。【事实】
- Fresh/stale 判断发生在 build resolution 阶段；fresh output 不重算，除非 force build。【事实】
- Build 写输出 Dataset 时会打开 transaction 并进行 build locking；同一 output 同时最多一个 job 写入。【事实】

---

## 三、Trigger 状态机

### 3.1 Time Trigger

Time trigger 是瞬时 wall-clock 条件：

- 按 cron + timezone 匹配。
- 匹配时刻满足，过后不再 satisfied。
- DST 春季跳过的本地时间不会触发；秋季重复出现的本地时间会触发两次。
- Foundry 使用 5-field Unix cron；若 Day-of-Month 和 Day-of-Week 都不是 `*`，任一匹配即可触发。

这意味着 time trigger 不能自然表达“业务日期”。`2026-05-30 02:00` 只是墙钟时刻，不等于 `business_date=2026-05-29`。

### 3.2 Event Trigger

Event trigger 是锁存状态：

```text
event happens
  -> trigger component becomes satisfied
  -> remains satisfied
  -> until the whole compound trigger is satisfied and schedule runs
```

常见 event：

| Event | 含义 |
|---|---|
| Data updated | Dataset 有 committed transaction |
| New logic | 计算 Dataset 的逻辑更新 |
| Job succeeded | 某个 job 成功 |
| Schedule ran successfully | 某个 schedule run 成功 |

关键限制：

- Data updated 不代表某个业务日期完成。
- New logic 不等价于任意文件改动；它与计算 Dataset 的逻辑有关。
- event trigger 是布尔 satisfied，不是事件队列，也不是计数器；公开文档没有说明多个同类 event 是否会排队生成多次 run。

### 3.3 Compound Trigger

Foundry 支持 `AND` / `OR` 组合，并可嵌套。

| 配置 | 行为 | 易误解点 |
|---|---|---|
| `AND(time, event)` | 到 time 的瞬间，如果 event 已 satisfied，则 run | event 不需要在固定窗口内发生 |
| `OR(time, event)` | time 到或 event 发生，任一满足即 run | 可能一天内多次触发 |
| `AND(A updated, B updated)` | 上次 run 后 A/B 都更新过，才 run | 不保证 A/B 是同一业务日期 |
| `OR(A updated, B updated)` | A 或 B 任一更新即 run | 不等待另一个输入 |
| `AND(time, OR(A,B))` | 到 time 时，A/B 任一此前更新即可 run | OR 子状态会锁存 |
| `OR(time, AND(A,B))` | time 到会 run；A/B 都更新也会 run | time 分支会绕过 A/B 到齐要求 |

官方排障文档中的关键语义是：如果一个 schedule 等多个输入都更新，且上次 run 在 `T1`，那么下一次 run 要求这些输入都在 `(T1, T2)` 期间更新。这是“上次 schedule run 后的事件窗口”，不是 `business_date` 配对。

### 3.4 多条件组合的内部判定模型推导

Palantir 没有公开 scheduler 源码，但公开文档已经暴露出足够多的外部语义，可以推导一个保守的内部模型：

```text
ScheduleVersion
  trigger_tree: Time | Event | AND(children) | OR(children)
  observed_events: Map<EventLeaf, satisfied_since>
  last_run_time: timestamp
  in_action: boolean
  pending_triggered: boolean
```

公开事实：

- Create Schedule 文档说明 advanced configuration 用 `AND` / `OR` 和括号组合 component triggers。【事实，[Create a schedule](https://www.palantir.com/docs/foundry/building-pipelines/create-schedule/)】
- Trigger Reference 说明 event trigger 在事件发生后保持 satisfied，直到整个 trigger satisfied 且 schedule run。【事实，[Trigger types reference](https://www.palantir.com/docs/foundry/building-pipelines/triggers-reference/)】
- Troubleshooting 文档说明：如果 schedule 上次 run 在 `T1`，下一次 `T2` 想等待 A1/A2 都更新，则 A1/A2 都要在 `(T1, T2)` 窗口内更新。【事实，[Schedule troubleshooting](https://www.palantir.com/docs/foundry/building-pipelines/schedule-troubleshooting/)】
- Schedules 文档说明：前一次 run 仍在 action 时再次触发，schedule 会保持 triggered，等前一次 finished 后再 run。【事实，[Schedules core concepts](https://www.palantir.com/docs/foundry/data-integration/schedules/)】
- Pause schedule 会 reset trigger state，并忘记 observed events。【事实，[Schedule troubleshooting](https://www.palantir.com/docs/foundry/building-pipelines/schedule-troubleshooting/)】

官方证据链：

| 结论 | 官方证据链接 | 证据边界 |
|---|---|---|
| Schedule trigger 是 build 运行条件，不是业务周期实例 | [Schedules core concepts](https://www.palantir.com/docs/foundry/data-integration/schedules/) | 官方只说 trigger 满足后 schedule run；没有 `$bizdate` / 周期实例概念。 |
| Advanced trigger 可表达为 `AND` / `OR` 布尔树 | [Create a schedule](https://www.palantir.com/docs/foundry/building-pipelines/create-schedule/)、[Trigger types reference](https://www.palantir.com/docs/foundry/building-pipelines/triggers-reference/) | “trigger tree” 是本文对官方 `component trigger + AND/OR + parenthesis` 的实现化抽象。 |
| Event leaf 是 latch，而不是瞬时事件 | [Trigger types reference](https://www.palantir.com/docs/foundry/building-pipelines/triggers-reference/) | 官方直接说明 event trigger remains satisfied；没有公开内部状态表结构。 |
| `Data updated` 的事件条件是 Dataset transaction committed | [Trigger types reference](https://www.palantir.com/docs/foundry/building-pipelines/triggers-reference/) | 只能证明数据版本变化，不证明业务日期完成。 |
| `AND(time, event)` 不限制事件发生窗口 | [Common scheduling configurations](https://www.palantir.com/docs/foundry/building-pipelines/common-schedules/)、[Trigger types reference](https://www.palantir.com/docs/foundry/building-pipelines/triggers-reference/) | 官方例子说明前一天 09:10 的 event 也可让次日 09:00 run。 |
| 多输入 AND 的窗口是上次 run 后到本次检查前 | [Schedule troubleshooting](https://www.palantir.com/docs/foundry/building-pipelines/schedule-troubleshooting/) | 官方用 `(T1, T2)` 解释 wait until all datasets update；不是业务日期配对。 |
| 运行中再次触发会保持 triggered，完成后再 run | [Schedules core concepts](https://www.palantir.com/docs/foundry/data-integration/schedules/) | 官方未说明多次 pending trigger 是否计数，因此本文按 pending bit 保守推断。 |
| OR 触发容易让 schedule 更频繁运行 | [Linter rules](https://www.palantir.com/docs/foundry/linter/rules) | Linter 给出两个输入每小时更新导致每小时跑两次的成本提示。 |
| Build/staleness 是真正去重与跳过重算的层 | [Builds core concepts](https://www.palantir.com/docs/foundry/data-integration/builds/)、[Schedule troubleshooting](https://www.palantir.com/docs/foundry/building-pipelines/schedule-troubleshooting/) | 官方说明 fresh output 不重算、all target up-to-date 时 schedule run 会 ignored。 |
| Force build 绕过 staleness，通常只适合外部依赖/ingest 边界 | [Schedule troubleshooting](https://www.palantir.com/docs/foundry/building-pipelines/schedule-troubleshooting/)、[Linter rules](https://www.palantir.com/docs/foundry/linter/rules) | 官方明确 force build 计算浪费，Data Connection/API 等外部依赖是例外。 |

因此，多条件组合更像下面这个判断过程：

```text
on_clock_tick(now):
  mark time leaves satisfied only for this tick
  evaluate_trigger_tree(now)

on_event(event):
  mark matching event leaves satisfied
  evaluate_trigger_tree(now)

evaluate_trigger_tree(now):
  root = eval(trigger_tree)
  if root == false:
    keep event leaves latched
    return

  if schedule is already in action:
    pending_triggered = true
    return

  start schedule run
  consume/reset observed event leaves for the satisfied trigger window
```

`eval(trigger_tree)` 的语义是普通布尔树，但叶子节点不是同一种时间模型：

| Leaf / Node | 判定语义 | 状态生命周期 |
|---|---|---|
| `time(cron, timezone)` | 当前墙钟时刻是否匹配 cron | 瞬时，过点即 false |
| `event(dataset updated)` | 对应 Dataset 是否发生 committed transaction | 锁存，直到 whole trigger satisfied and schedule run |
| `AND(children)` | 所有子节点当前 satisfied | 不做事件 payload join |
| `OR(children)` | 任一子节点当前 satisfied | 任一分支可释放整个 trigger |

这个模型解释了几个看似反直觉的行为：

1. `AND(time=09:00, A updated)` 不是“09:00 前固定窗口内 A 更新”。只要 A 的 event leaf 已经 latched，09:00 到来就会 run；Palantir common schedules 文档明确提示前一天 09:10 的更新也可能让第二天 09:00 条件成立。【事实】
2. `AND(A updated, B updated)` 不要求 A/B 同时到达。它要求上次 run 之后两个 event leaf 都变成 satisfied；Troubleshooting 文档的 `(T1, T2)` 例子正是这个窗口语义。【事实】
3. `OR(A updated, B updated)` 会在 A 或 B 任一更新时释放 trigger；如果 A/B 都每小时更新，可能导致 schedule 一小时跑两次，Linter 因此建议把某些 OR 改成 AND 或定时触发以降低成本。【事实】
4. `OR(time, AND(A,B))` 中 time 分支会绕过 A/B 到齐要求；这不是 bug，而是布尔树语义的自然结果。【推断】
5. 若 schedule 运行中又满足 trigger，公开文档只说保持 triggered，未说明多次 pending 是否计数。因此保守设计应把它视为“至少再跑一次”的 pending bit，而不是可靠事件队列。【事实+推断】

背后的设计思路不是 DataWorks 式“实例枚举 + 周期依赖判重”，而是：

- 用 trigger expression 做轻量 wake-up；
- 用 Dataset transaction / JobSpec / staleness 判断是否真的有 work；
- 用 build graph resolution 在运行时决定实际构建范围；
- 用 event latch 解决异步到达，不要求事件同时发生；
- 用 schedule run boundary 清空已观察事件，避免无限重复触发；
- 用 `Ignored` 和 staleness 抑制无效重算。

这套思路的优点是弹性高、对 pipeline 变化友好、成本可由 staleness 控制；代价是它不携带业务周期 identity，也不做业务日期 correlation。

### 3.5 Running 时再次触发

如果 schedule 前一次 run 仍在 action 中，再次满足 trigger：

- schedule 会保持 triggered；
- 等前一次 schedule finished 后再 run；
- 公开文档没有说明多个 pending triggers 是否逐条排队，还是合并成一个 pending triggered 状态。

这对高频 event 和长耗时 build 很重要：调度不会简单并发启动同一 schedule，但可能形成积压、延迟或重复 build 尝试。

---

## 四、Schedule Run 与 Build 的关系

Schedule run 状态不能直接等同于 build/job 状态。

| Schedule run 状态 | 含义 | 风险 |
|---|---|---|
| `Succeeded` | 成功发起 build | 不代表 build/job 最终成功 |
| `Ignored` | 尝试运行但未创建 build | 通常因为目标 up-to-date/no work |
| `Failed` | schedule 未能运行 | 需要看 schedule metrics / permissions / scope |

因此运维时要分层看：

```text
Schedule run history
  -> Build report
    -> Job logs
      -> Dataset transactions
```

只看 schedule `Succeeded` 会误判健康。生产场景应配置 schedule status health check 和 Data Health 通知。

---

## 五、Build Resolution、Staleness 与 Force Build

### 5.1 Dynamic Graph Resolution

Schedule 每次触发都会重新解析 graph：

- target datasets；
- excluded datasets；
- build type；
- project/user scope；
- branch 与 fallback branches；
- 当前可用 JobSpec path；
- 当前 Dataset staleness。

这说明 Foundry 的 schedule 更接近“graph selection rule”，不是 Airflow/DataWorks 式固定任务实例清单。

### 5.2 Build Type

| Build type | 行为 | 风险 |
|---|---|---|
| Single build | 只构建 target datasets | 不更新上游 |
| Full build / with upstream | 构建 target 及上游依赖，排除 excluded datasets | 范围过宽、成本高、权限复杂 |
| Connecting build | 构建 input datasets 到 target datasets 之间路径 | 需要同 branch 上存在 JobSpec path |
| Downstream build | 构建依赖某 Dataset 的下游范围 | 适合影响传播，但要控制范围 |

Excluded datasets 会截断 traversal；其 upstream 通常也不会被 build。

### 5.3 Staleness

公开语义：

```text
if input datasets unchanged
   and JobSpec logic unchanged:
       output dataset is fresh
       skip build
else:
       output dataset is stale
       build
```

证据缺口：官方没有公开底层 fingerprint 算法，例如输入事务、schema、JobSpec、branch/fallback 如何精确比较。

### 5.4 Force Build

Force build 会绕过 staleness，重算范围内 datasets。

适合：

- Data Connection sync；
- Object Storage V1 sync；
- 外部源变化无法被 Foundry 内部 graph 感知的 ingest 层。

不适合：

- derived dataset；
- 大范围 full build；
- 用来模拟业务日期补数；
- 与 transaction-limit re-trigger 同时使用。

Force build 是 freshness 层的强制重算，不是 business-cycle rerun。

### 5.5 Build Locking

Build resolution 会：

- 打开 output dataset transaction；
- 对 output 做 build locking；
- 检测其他可能改变当前 input 的 build；
- 同一 output 同时最多一个 job 写入；
- 写同一 output 的 job 会排队。

公开文档没有说明队列公平性、超时、优先级和跨 schedule 去重的完整算法。

---

## 六、Incremental、Transaction Limit 与 Re-trigger

### 6.1 Incremental 与 Schedule 的分工

Schedule 只触发 build。Transform 是否增量运行，由 `@incremental()` 逻辑决定。

典型 read/write mode：

| 模式 | 增量运行 | 非增量运行 |
|---|---|---|
| input `added` | 上次成功后新增事务/文件 | 读取完整输入 |
| input `previous` | 上次运行看到的完整输入 | 空 |
| input `current` | 本次完整输入 | 本次完整输入 |
| output `modify` | 默认增量写 | 非默认 |
| output `replace` | 可显式使用 | 默认全量写 |

### 6.2 Transaction Limit

启用 transaction limit 后，一次成功 build 可能只处理 backlog 的一部分：

```text
input processed: A-C
new backlog: D-J
transaction_limit = 3

build 1: D-F
build 2: G-I
build 3: J
```

每次 build 后 target 可能仍 stale，直到 backlog 被追平。

### 6.3 Re-trigger Upon Successful Build

`Re-trigger upon successful build` 用于追平 backlog：

- 要求至少一个 target 使用 incremental transaction limits；
- 不能与 Force build 同时启用；
- 每次成功 build 后，如果 target 仍 stale，继续触发；
- 直到输入处理完且 target 不再 stale。

这是一种 freshness catch-up 机制，不是业务补数机制。

### 6.4 Fallback 与失败边界

| 输入变化 | 增量影响 |
|---|---|
| `APPEND` | 增量友好 |
| `SNAPSHOT` | 常触发非增量 / 重置起点 |
| `UPDATE` 修改既有文件 | 破坏 append-only，可能 fallback snapshot 或失败 |
| `DELETE` | transaction-limit 输入通常不允许，retention 例外需单独配置 |
| `semantic_version` 变更 | 下一次非增量 / snapshot |
| `v2_semantics` 首次启用 | 下一次 snapshot 一次 |

---

## 七、Data Connection / Sync 的特殊性

Data Connection sync 的输入在 Foundry 外部，Foundry 不能天然知道外部源是否变化。

### 7.1 Sync Lifecycle

```text
Source / credentials / network
  -> Sync capability
    -> preview / validate
      -> manual run or schedule
        -> build reads external source
          -> write dataset transaction
```

Batch sync 是离散运行；streaming/CDC sync 是持续运行。

### 7.2 外部源 Freshness

普通 Transform：

```text
Foundry internal dataset updated
  -> lineage graph sees transaction
  -> staleness works
```

Data Connection sync：

```text
external source changed
  -> Foundry may not know
  -> sync appears up-to-date
  -> schedule needs force build to check/pull
```

Palantir 明确建议：

- Data Connection sync schedule 与 downstream transform schedule 分开；
- 只对 sync layer 使用 force build；
- 下游 transform 使用普通 staleness / dataset update trigger。

### 7.3 Sync 场景表

| 场景 | Foundry 是否感知外部变化 | 推荐方式 |
|---|---|---|
| 外部 DB 新增/更新，但 sync 未运行 | 否 | sync 单独时间 schedule + force build |
| sync 输出 Dataset 更新 | 是 | 下游用 dataset update/freshness |
| JDBC incremental sync | 只在 sync 运行时检查 cursor | 周期 force build sync，cursor 必须严格递增 |
| 文件增量 sync | 运行时识别未同步文件 | 周期 force build，必要时 batch limit |
| Streaming sync | 持续运行 | 不按 batch schedule 周期触发 |
| CDC sync | 持续 changelog | 注意 log retention、配置变更重启、历史 backfill |

---

## 八、运维、权限与治理

### 8.1 Scope 与运行身份

| Scope | 行为 | 建议 |
|---|---|---|
| Project-scoped | 不依赖单个用户权限，构建所选 Projects 内 datasets | 生产优先使用 |
| User-scoped | 以最后创建/编辑 schedule 的用户运行 | 避免绑定个人；必要时使用稳定服务用户 |

User-scoped 风险：

- 用户离职或停用；
- 用户权限被收回；
- 最后编辑者变化；
- schedule build fail to start。

### 8.2 Retry 与 Failure

Foundry 支持：

- failed job attempts；
- retry interval；
- abort build on failure；
- schedule status health check；
- Data Health notifications；
- 连续失败后的自动 pause。

建议：

- 生产 schedule 开启 fail fast / abort build on failure；
- 至少配置 schedule status health check；
- 不要只依赖 schedule run `Succeeded`；
- 对非幂等外部副作用慎用 retry。

### 8.3 Pause / Resume

Pause 的关键语义：

- 会重置 trigger state；
- 会忘记 observed events；
- paused 期间不会触发；
- resume 后不会自动补回 pause 期间事件。

因此维护窗口需要单独补数/重跑策略。

### 8.4 资源与成本

Schedule 本身不是资源隔离主对象。成本治理主要通过：

- Project；
- usage account；
- resource queue；
- priority branch；
- Spark / compute profile；
- schedule frequency；
- graph scope。

风险模式：

- 多个 schedule 管同一 Dataset；
- 大量 schedule 同一时间触发；
- 对 derived datasets 使用 force build；
- full build 范围过宽；
- user-scoped production schedule。

---

## 九、业务时间建模边界

### 9.1 Foundry Schedule 能表达什么

Foundry Schedule 能表达：

- 何时尝试 build；
- 哪些 Dataset graph 范围进入 build；
- 哪些输入 transaction / logic version 使输出 stale；
- 是否 force build；
- 如何追平 incremental backlog；
- 如何按 project/user scope 执行。

### 9.2 Foundry Schedule 不能表达什么

Foundry Schedule 不能天然表达：

- `$bizdate`；
- 业务日期与调度时间的默认偏移；
- 多输入同业务日期 ready；
- 周期实例；
- 补数据实例；
- 跨周期依赖；
- 某业务日期的 active output version；
- 同一业务日期多次重跑的 supersede 关系。

### 9.3 关键对照

| Foundry 能力 | 能表达 | 不能表达 | 自研平台补充 |
|---|---|---|---|
| Time trigger | 墙钟时间 | 业务日期推导 | business calendar |
| Data updated | Dataset transaction committed | 分区/账期 ready | ready manifest |
| AND/OR trigger | 事件 satisfied 布尔组合 | event correlation by business date | data_interval correlation |
| Staleness | 数据版本是否过期；归属 Data Version Identity / freshness scheduler | 业务周期是否 eligible | Business-cycle scheduler / Run Identity 补 business eligibility |
| Force build | 绕过 up-to-date | 历史业务日期重跑 | backfill/rerun policy |
| Build locking | 输出 transaction 并发控制 | 业务实例幂等 | run-to-transaction mapping |

### 9.4 已确认架构决策

```text
Business-cycle scheduler:
  owns Run Identity
  decides whether C(dt) is eligible to run
  based on business_date / data_interval / ready manifest / upstream run state

Freshness scheduler:
  owns Data Version Identity
  decides whether C output is stale
  based on input transaction set / logic version / force build / external unknown
```

执行顺序：

```text
1. ready manifest 判断 A/B 同一 data_interval ready
2. 创建 Run Identity
3. 解析 input transaction vector
4. freshness / staleness 判断是否需要 build
5. build 提交 output transaction
6. 更新 partition manifest
```

这条决策是本轮调研最重要的架构产出。

---

## 十、综合场景矩阵

| 场景 | Foundry 原生行为 | 业务时间风险 | 自研平台处理 |
|---|---|---|---|
| 单输入 latest view | dataset update 即 build | 低 | 只记录 input transaction vector |
| 单输入日分区 | dataset update 触发，但不知业务日期 | 中 | 从 partition manifest 解析 `dt` |
| 多输入 OR | 任一输入更新触发 | 高，半新半旧 | 仅用于 latest view，不用于账期输出 |
| 多输入 AND | 上次 run 后都更新过即触发 | 高，不保证同一 `dt` | ready manifest 按 `data_interval` 对齐 |
| time + event | time 到且事件发生过 | 中，不是业务窗口 | window close + watermark |
| Data Connection sync | sync 可能看起来 up-to-date | 高，外部源不可见 | sync 层单独 force build |
| incremental backlog | 成功 build 后仍可能 stale | 低到中 | transaction limit + re-trigger |
| force build derived dataset | 重算范围内所有 outputs | 成本高，仍无业务日期 | 只用于 ingest 或明确重算 |
| pause/resume | pause 清空 observed events | 可能漏掉期间事件 | resume 后手动补 run |
| user-scoped schedule | 用户权限变化会影响运行 | 生产风险 | project-scoped / service user |

---

## 十一、证据缺口

1. Staleness 的底层指纹/比较算法未公开：输入 transaction、schema、JobSpec、branch/fallback 的精确比较规则不可证。
2. 多个同类 event 在同一 satisfied 周期内是否计数未公开；只能确认 event satisfied 是锁存状态。
3. 前一 schedule run 仍在进行时，多次 pending trigger 是否合并或排队为多次后续 run，公开资料未说明。
4. Build locking 的队列公平性、超时、跨 schedule 去重策略未公开。
5. Data Connection sync schedule 的完整状态机、sync RID 与 schedule RID 映射未公开。
6. 自动 pause 的精确失败次数阈值未公开。
7. Palantir 公开文档未发现等价于 DataWorks `$bizdate` / 周期实例的 schedule 级概念；不能排除私有部署或内部功能。

---

## 十二、来源索引

- Palantir：[Trigger types reference](https://www.palantir.com/docs/foundry/building-pipelines/triggers-reference/)
- Palantir：[Schedules core concepts](https://www.palantir.com/docs/foundry/data-integration/schedules/)
- Palantir：[Common scheduling configurations](https://www.palantir.com/docs/foundry/building-pipelines/common-schedules/)
- Palantir：[Schedule troubleshooting](https://www.palantir.com/docs/foundry/building-pipelines/schedule-troubleshooting/)
- Palantir：[Create a schedule](https://www.palantir.com/docs/foundry/building-pipelines/create-schedule/)
- Palantir：[Scheduling best practices](https://www.palantir.com/docs/foundry/building-pipelines/scheduling-best-practices/)
- Palantir：[Builds core concepts](https://www.palantir.com/docs/foundry/data-integration/builds/)
- Palantir：[Datasets and transactions](https://www.palantir.com/docs/foundry/data-integration/datasets/)
- Palantir：[Incremental transaction limits](https://www.palantir.com/docs/foundry/transforms-python-spark/incremental-transaction-limits/)
- Palantir：[Incremental transforms usage](https://www.palantir.com/docs/foundry/transforms-python/incremental-usage/)
- Palantir：[Data Connection setup sync](https://www.palantir.com/docs/foundry/data-connection/set-up-sync/)
- Palantir：[Data Connection core concepts](https://www.palantir.com/docs/foundry/data-connection/core-concepts/)
- Palantir：[Change Data Capture](https://www.palantir.com/docs/foundry/data-integration/change-data-capture/)
- Palantir：[Data Health](https://www.palantir.com/docs/foundry/observability/data-health/)
- Palantir：[Resource queues](https://www.palantir.com/docs/foundry/resource-management/resource-queues/)
- Palantir：[Linter rules](https://www.palantir.com/docs/foundry/linter/rules/)
- DataWorks：[Supported formats of scheduling parameters](https://www.alibabacloud.com/help/doc-detail/2846748.html)
- DataWorks：[Data backfill](https://www.alibabacloud.com/help/en/dataworks/data-backfilling)
- DataWorks：[View auto-triggered instances](https://www.alibabacloud.com/help/en/dataworks/user-guide/view-auto-triggered-node-instances)
