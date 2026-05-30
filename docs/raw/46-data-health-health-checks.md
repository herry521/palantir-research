# Palantir Data Health 与 Health Checks 运行期监控调研

> Agent C 输出。采集日期：2026-05-30。  
> 术语基线状态：已补读 `docs/raw/44-data-quality-source-map.md`；本文沿用其对 Data Health、Health Checks、Monitoring Views、Data Expectations 的边界定义。

## 总结与洞察

1. 【事实】Data Health 是 Foundry 的资源健康监控应用，核心能力分为 Monitoring views 和 Health checks；前者用于按范围规模化监控资源，后者用于对单个 dataset、schedule、table 做细粒度检查。来源：https://www.palantir.com/docs/foundry/observability/data-health
2. 【事实】Health checks 覆盖状态、时间、大小、内容、schema 等类别；其中 schedule status、build status、job status 分别代表调度、构建整体、单 dataset job 的不同粒度，不能互相混用。来源：https://www.palantir.com/docs/foundry/data-health/checks-reference/
3. 【事实】time-based checks 可配置自动或手动调度；自动模式在 dataset 更新和达到阈值时评价，dataset update transaction 会同时触发评价并重置下一次阈值窗口。来源：https://www.palantir.com/docs/foundry/data-health/check-evaluation
4. 【推断】Health checks 默认更像运行期监控与告警规则，而非构建期门禁；可构建期阻断的是 Data Expectations 中定义的 FAIL/abort 语义，其结果进入 Data Health 展示和通知，但不应与 Health checks 混写。来源：https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations
5. 【建议】自建平台应把“构建期阻断规则”和“运行期健康监控规则”做成两套生命周期但统一结果视图：阻断规则绑定 CI/build job，健康规则绑定资源状态流、transaction 事件、定时评价和告警订阅。

## 1. 调研范围与来源

本文件聚焦 Palantir Foundry Data Health 与 Health checks 的运行期监控机制，覆盖 datasets、schedules、tables，以及 job-level、build-level、schedule-level、freshness、content、schema checks 的分类边界。

优先资料源：

| 编号 | 来源 | 用途 |
|---|---|---|
| S05 | https://www.palantir.com/docs/foundry/observability/data-health | Data Health 顶层能力、Monitoring views vs Health checks、观察入口 |
| S06 | https://www.palantir.com/docs/foundry/data-health/overview/ | Health checks 资源类型、创建入口、平台级与 pipeline 级观察 |
| S07 | https://www.palantir.com/docs/foundry/data-health/check-types/ | 检查类型说明 |
| S08 | https://www.palantir.com/docs/foundry/data-health/check-evaluation | automatic/manual schedule、transaction update、threshold reset |
| S09 | https://www.palantir.com/docs/foundry/data-health/checks-reference/ | 可用检查类型、资源支持范围、参数 |
| 补充 | https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations | 与 Data Expectations 构建期阻断边界对齐 |

## 2. Data Health 与 Health Checks 的职责边界

【事实】Palantir 将 Data Health 定义为用于监控平台资源健康的 Foundry 应用，可监控 datasets、builds、functions、actions、automates 等资源，并通过平台内通知、邮件摘要、PagerDuty、Slack 等方式发送问题提醒。Data Health 提供两类主要功能：

- Monitoring views：用 scope-based monitoring rules 在 project、folder 或单资源范围内规模化监控，适合资源随范围自动增长的场景。
- Health checks：对单个资源配置详细检查，包括 dataset 的 content 和 schema validation，适合 workflow 无关的细粒度数据质量验证。

来源：https://www.palantir.com/docs/foundry/observability/data-health

【事实】Health checks 可创建在 datasets、schedules、tables 上。Dataset 和 table 的 Health tab 位于 Dataset Preview；schedule 的 Health 入口位于 Data Lineage 中打开 schedule 后的 Metrics > Health。来源：https://www.palantir.com/docs/foundry/data-health/overview/

【推断】Health checks 的设计重心是“某个资源现在是否健康”，不是“代码变更是否允许合入”或“当前 build 是否必须中止”。它可以消费 build/job/transaction/schema/content 等结果并触发告警，但构建阻断语义应由 Data Expectations 或构建系统承载。

## 3. 资源与检查类型矩阵

【事实】Checks reference 列出的 Health checks 大类包括 Status、Time、Size、Content、Schema。支持资源范围如下：

| 类别 | Check type | 支持资源 | 监控含义 |
|---|---|---|---|
| Status | Schedule status | Datasets | 最近一次 schedule build 成功或失败 |
| Status | Build status | Datasets、Iceberg tables、Virtual tables | 最近一次 dataset build 成功或失败 |
| Status | Job status | Datasets、Iceberg tables、Virtual tables | 最近一次针对该 dataset 的 job run 成功或失败 |
| Status | Sync status | Datasets | 最近一次同步到外部数据库成功或失败 |
| Time | Build duration | Datasets | build 总耗时是否满足阈值或偏离历史中位数 |
| Time | Data freshness | Datasets | 最新 transaction 时间与某个 timestamp 列最大值的差距 |
| Time | Sync duration | Datasets | sync 总耗时是否满足阈值或偏离历史中位数 |
| Time | Sync freshness | Datasets | 最新 sync 时间与 datetime 列最大值的差距 |
| Time | Time since last updated | Datasets、Iceberg tables、Virtual tables | 距离 dataset 上次产生新 transaction 的时间 |
| Time | Time since sync last updated | Datasets | 距离上次同步到某目的地的时间 |
| Size | Dataset file count / partition / row count | Datasets | 最新 view 文件数、分区表现、行数 |
| Size | Transaction file count / file size | Datasets | 单次 transaction 提交的文件数或大小 |
| Content | Allowed column values、regex、date/numeric range、null percentage、primary key 等 | Datasets，Primary key 也支持 Iceberg/Virtual tables | 数据内容值域、格式、唯一性、统计特征 |
| Schema | Column、Column count、Schema | Datasets；Column/Schema 也支持 Iceberg/Virtual tables | 列存在性、列数量、schema 匹配 |

来源：https://www.palantir.com/docs/foundry/data-health/checks-reference/

## 4. Job-level、Build-level、Schedule-level 边界

【事实】Schedule status 检查最近一次 schedule build 是否成功。Palantir 文档说明它代表总是一起构建的 pipeline 或 dataset 集合状态，因此能给出通向最终 dataset 的各步骤整体状态。来源：https://www.palantir.com/docs/foundry/data-health/checks-reference/

【事实】Build status 检查 dataset 最近一次 build 是否成功，代表为了构建最终 dataset 的整个过程。若 build 中间 dataset 也配置了 build status，文档说明这些中间 dataset 的 build status 不会更新，但 job status 会为这些中间 dataset 更新。来源：https://www.palantir.com/docs/foundry/data-health/checks-reference/

【事实】Job status 检查最近一次在 dataset 上运行的 job 是否成功，并独立于导致 dataset 刷新或创建的 build 触发。只要是某 dataset 的每一次 build，job status 都会运行，不论该 dataset 是否是最终输出。来源：https://www.palantir.com/docs/foundry/data-health/checks-reference/

【事实】Palantir 建议通常给所有 schedules 配置 schedule status checks；如果 schedule 已有 schedule status，则不建议对同一 schedule 构建的其他 datasets 再安装 job status checks，因为 schedule 中任意 job 失败都会触发 schedule status check。若想关注 intermediate dataset 是否更新，可用 job status；若 dataset 是 build output 且要确认整个 build 和所有 dataset 成功，可用 build status。来源：https://www.palantir.com/docs/foundry/data-health/checks-reference/

【推断】三者边界可抽象为：

- schedule-level：关注“这一组被调度联动的 pipeline 是否整体成功”。
- build-level：关注“以某个最终 output 为目标的 build 整体是否成功”。
- job-level：关注“某个 dataset 参与的一次 job 是否成功”，尤其适合中间节点或多输出 build 的局部诊断。

## 5. Freshness、Content、Schema Checks 边界

### 5.1 Freshness

【事实】Data freshness 检查 dataset 最新 transaction 时间与某 timestamp 列最大值的关系；如果 timestamp 表示行加入时间，该检查可用于衡量精确数据新鲜度。Time since last updated 则检查 dataset 自上次产生新 transaction 以来的时间是否满足阈值，并可配置是否忽略 empty transactions。来源：https://www.palantir.com/docs/foundry/data-health/checks-reference/

【推断】二者语义不同：

- Data freshness 是“数据内容中的业务时间是否新”，依赖 timestamp 列。
- Time since last updated 是“Foundry dataset 最近是否有 transaction”，依赖存储/提交事件。

### 5.2 Content

【事实】Content checks 包括 allowed column values、approximate unique percentage、column regex、approximate column relation、date range、null percentage、numeric mean、numeric median、numeric range、primary key 等。来源：https://www.palantir.com/docs/foundry/data-health/checks-reference/

【推断】Content checks 属于运行期数据质量监控，适合发现生产数据漂移、异常值、主键重复、空值比例变化等问题。它们和 Data Expectations 的内容断言在表达能力上可能重叠，但生命周期不同：Health checks 由 Data Health 配置和告警，Data Expectations 在代码中定义并在 build 中运行。

### 5.3 Schema

【事实】Schema checks 包括 Column、Column count、Schema。Column 和 Schema 支持 Datasets、Iceberg tables、Virtual tables；Column count 支持 Datasets。来源：https://www.palantir.com/docs/foundry/data-health/checks-reference/

【推断】Schema checks 适合运行期发现上游 schema 漂移；若 schema 变化必须阻断生产构建，应在 Data Expectations 或 pipeline 构建逻辑中表达为 pre/post-condition，而不是仅依赖运行期 health alert。

## 6. Check Evaluation：automatic/manual、transaction update、threshold reset

【事实】时间类 checks 可配置为 automatic 或 manual schedule。来源：https://www.palantir.com/docs/foundry/data-health/check-evaluation

【事实】Automatic 模式下，check 在两个时点运行：

1. dataset 更新时。
2. dataset 超过已配置阈值时。

来源：https://www.palantir.com/docs/foundry/data-health/check-evaluation

【事实】dataset update transaction 会触发 check 评价两件事：一是按配置检查 dataset；二是计算当前时间与上一次已提交 transaction 之间的 elapsed time。该 transaction 还会通过“当前时间 + time threshold minimum”重置下一次检查阈值。来源：https://www.palantir.com/docs/foundry/data-health/check-evaluation

【事实】Palantir 文档用 Time Since Last Updated 小于等于 1 小时举例：如果 dataset 在 58 分钟更新，则更新时评价为 Passed，并把下一次自动运行时间重置为 60 分钟后；如果 60 分钟未更新，则到阈值时评价失败，62 分钟更新时再次运行并通过，watchers 会收到通知。来源：https://www.palantir.com/docs/foundry/data-health/check-evaluation

【事实】Manual schedule 按固定频率运行，不管 dataset 何时 build；可按分钟、小时、天、周或 custom schedule 配置。来源：https://www.palantir.com/docs/foundry/data-health/check-evaluation

【推断】automatic 适合 freshness / time-since-update 这类与 transaction 节奏绑定的 SLA；manual 适合希望固定巡检、与 build 节奏解耦的规则，例如每日固定时间检查 row count、schema 或内容统计。

## 7. 观察入口：Dataset Preview、Data Lineage、Data Health

【事实】Dataset Preview：打开 dataset 或 table 后进入 Health tab，可新增 checks、修改已有 checks、查看历史 check results。来源：https://www.palantir.com/docs/foundry/data-health/overview/

【事实】Data Lineage：打开 schedule 后选择 Metrics > Health，可查看 health checks 和 monitoring views；在 lineage graph 上可按 health check status 给 datasets 着色，也可在底部 Data Health tab 查看 lineage graph 中所有 datasets 的 checks 与状态。来源：https://www.palantir.com/docs/foundry/observability/data-health 与 https://www.palantir.com/docs/foundry/data-health/overview/

【事实】Data Health 应用：可从 Foundry sidebar 进入，用于平台级查看 health checks；可按 status 或 name 过滤/排序 datasets，也可只显示用户正在 watching 的 datasets，并可从右上角 Add health check 新增检查。来源：https://www.palantir.com/docs/foundry/data-health/overview/

【推断】三个入口对应三种运维动作：

- Dataset Preview：资源 owner 对单个 dataset/table 配置与复盘。
- Data Lineage：pipeline owner 从上下游关系定位健康状态传播和影响范围。
- Data Health：平台或值班视角跨资源筛选、订阅和告警响应。

## 8. 运行期监控 vs 构建期阻断

【事实】Data Expectations 是定义在 dataset input 或 output 上的一组代码化要求；当 Data Expectation check 在 dataset build 中失败时，build 可以被自动 abort，以节省时间和资源并避免坏数据下游传播。Data Expectations 结果集成到 Data Health 监控。来源：https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations

【事实】Data Expectations 的 check 可定义失败处理方式：失败时 build 可 abort，也可 warning 后继续。注册发生在相关 branch 的 CI 中；受保护分支上的 expectation 变更需要 pull request。运行时，注册的 checks 作为 build job 的一部分运行，FAIL 会使 job status 变为 Aborted。来源：https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations

【事实】Data Expectations 每次运行都会产生结果并报告到 Data Health；最新结果在 Dataset Preview 的 Health tab 展示，也可设置通知和 issue triggers。来源：https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations

【推断】因此应区分：

| 能力 | 主要阶段 | 规则载体 | 失败后果 | Data Health 角色 |
|---|---|---|---|---|
| Health checks | 运行期监控 / 资源健康巡检 | Data Health Health tab / health check 配置 | 产生 failed health result、通知、issue；公开文档未表明可直接 abort build | 原生配置、评价、展示、告警入口 |
| Data Expectations | 构建期检查 / 质量门禁 | Code Repositories 中 transform input/output check | FAIL 可 abort build，WARN 可继续 | 展示 check result、通知、issue |
| Monitoring views | 规模化运行期监控 | scope-based monitoring rules | 产生 alerts，适合跨项目/文件夹资源覆盖 | 平台级监控视图和订阅 |

【建议】文档和产品设计中不要把 Health checks 直接称为“构建阻断规则”。如果某项 schema/content 约束必须阻断构建，应实现为 Data Expectations；如果只需监控生产资源状态、触发告警或 issue，则实现为 Health checks 或 Monitoring views。

## 9. 关键流程

### 9.1 Dataset freshness automatic check

1. 用户在 dataset Health tab 配置 Time since last updated，例如小于等于 1 小时。
2. 系统根据最近一次 transaction 设置下一次 threshold evaluation 时间。
3. 若 dataset 在阈值前产生 update transaction，check 立即评价 elapsed time。
4. 通过后，系统以当前时间加阈值最小值重置下一次检查时间。
5. 若到达阈值仍无新 transaction，check 评价失败并通知 watchers。
6. 后续新 transaction 到来时再次评价，可能恢复为 Passed。

### 9.2 Pipeline health observation

1. 在 Data Lineage 打开 pipeline 或 schedule。
2. 对 datasets 按 health check status 着色。
3. 在底部 Data Health tab 查看 lineage graph 内所有 checks。
4. 对异常 dataset 切到 Dataset Preview Health tab 查看历史结果。
5. 若涉及整组 schedule 失败，优先看 schedule status；若涉及中间 dataset 局部失败，再看 job status。

## 10. 证据缺口

1. 【待验证】公开文档没有展开 Health checks 的底层执行引擎、结果存储模型、保留周期、幂等策略和重试策略。
2. 【待验证】公开文档未说明每类 content/schema health check 的精确扫描范围、采样策略、性能上限或超时行为；仅能从参数说明推断运行期评价语义。
3. 【待验证】公开文档未证明 Health checks 本身可作为 build abort 门禁；当前证据只支持 Data Expectations 具备构建期 FAIL/abort 语义。
4. 【待验证】Health checks 的权限模型、审计记录、批量变更治理、Marketplace 分发限制需要结合 notifications、marketplace、FAQ 等文档由后续 agent 补充。
5. 【已处理】本文已补读 `docs/raw/44-data-quality-source-map.md` 并统一术语；后续仍需在综合文档中复核各 Story 对 Data Expectations、Health Checks、Monitoring Views 的边界是否一致。

## 11. 自建平台启示

1. 【建议】将规则拆成三层：构建期 expectations、单资源 health checks、范围化 monitoring rules；三者共享结果模型、告警和 issue 闭环，但保留不同触发器和失败语义。
2. 【建议】运行期 Health checks 至少需要四类触发器：resource status event、dataset transaction event、threshold timer、manual/custom schedule。
3. 【建议】freshness 要同时支持 transaction freshness 和 business timestamp freshness；前者解决“平台多久没更新”，后者解决“业务数据是否陈旧”。
4. 【建议】状态类检查要明确 schedule/build/job 的粒度，避免同一失败在多个层级重复告警；可以采用 Palantir 的建议：schedule 默认配 schedule status，中间 dataset 按需配 job status，最终 output 按需配 build status。
5. 【建议】观察入口应按角色分层：单资源 Health tab 给 owner 配置与复盘，lineage 视图给 pipeline owner 定位影响，平台 Data Health 给值班和治理团队做筛选、订阅和升级。
6. 【建议】若要实现构建阻断，不要复用运行期 health alert 的失败状态直接 abort；应在 build job 内执行规则并产出明确的 FAIL/WARN/ABORT 结果，再同步到统一健康中心展示。
