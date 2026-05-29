# 26 — Palantir 高码质量、测试、血缘、权限与可观测性调研

**日期：** 2026-05-29
**关联 Issue：** #10
**所属 Epic：** #4
**类型：** Story 调研 / 高码治理能力分析

---

## 1. 背景

本文件聚焦 Palantir Foundry 高码开发中的工程治理闭环：Transform unit tests、repository checks、data expectations、build abort/quality gate、lineage、marking/permission、data health、monitoring/observability 如何共同约束生产级代码与数据资产。

本轮调研基于 `docs/raw/22-pro-code-source-map.md` 中 #10 对应资料源，并复核已有 `docs/raw/05-testing-and-data-connection.md`、`docs/raw/08-monitoring-and-observability.md`、`docs/raw/11-marking-mechanism-deep-dive.md`。新增资料优先使用 Palantir 官方文档 URL。

---

## 2. 可信度规则

| 标签 | 判定标准 | 使用边界 |
|---|---|---|
| 【事实】 | 本轮调研已通过 Palantir 官方文档或当前仓库资料直接确认 | 可作为事实陈述进入结论 |
| 【推断】 | 由多个【事实】事实组合得出的工程判断，逻辑链明确，但官方没有直接给出同一句结论 | 可作为架构建议，但需要说明推导依据 |
| 【猜测】 | 公开资料未披露，或只有间接迹象，尚不能形成稳定判断 | 只能作为待验证问题，不应直接进入设计决策 |

说明：这里使用“事实”标签表示“当前已验证事实”，不是实时数据流能力。

---

## 3. 核心结论

1. Code Repositories 不只是代码编辑器，而是把 Git、PR、权限、lint/error checking、preview/debug 和 repository checks 纳入 Foundry 内部工程入口的高码治理面。【事实】
2. Python transform unit tests 使用 pytest，并可通过 Gradle 插件纳入 repository checks；测试输出会显示在 Checks tab，失败测试会使 checks 失败。【事实】
3. Python repository unit tests 官方明确只适用于 batch pipelines，不支持 streaming pipelines；因此高码测试能力不能无条件覆盖所有 pipeline 类型。【事实】
4. Data Expectations 是定义在 dataset input/output 上的代码化数据要求，可作为 build-time check；失败时可配置 abort build，避免坏数据继续传播。【事实】
5. Data Expectations 与 Code Repositories、protected branch PR review、Data Health 连接在一起，形成“代码变更审查 -> 构建期质量门禁 -> 运行期监控”的闭环。【推断】
6. Data Lineage 可展示 dataset 的祖先/后代、schema、最近 build 时间以及生成数据的代码，是高码 transform 被平台理解和治理的关键索引面。【事实】
7. Markings 是 Foundry 的强制访问控制机制；用户必须满足资源上所有 Marking 要求，角色权限不能绕过 Marking。【事实】
8. `stop_propagating` 和 `stop_requiring` 允许在派生数据已移除或混淆受限内容后停止继承 Markings/Organizations，但只能在受保护分支上生效，并需要特殊审批权限。【事实】
9. Observability 官方定位覆盖 monitor、debug、trace、analyze；Data Health 是主要监控应用，Workflow Lineage 支持执行历史和日志检索，trace views 支持跨 functions/actions/LLM calls 的请求路径分析。【事实】
10. 对自建高码平台而言，单独实现 transform runner 或 DAG 调度远远不够；质量门禁、权限传播、血缘索引、可观测性和告警必须在平台元数据层联动。【推断】

---

## 4. 测试与质量矩阵

| 能力 | Foundry 官方能力 | 与高码开发的关系 | 可信度 |
|---|---|---|---|
| Unit tests | Python transforms 使用 pytest；通过 `com.palantir.transforms.lang.pytest-defaults` 启用测试；测试结果在 Checks tab 展示 | 把高码逻辑的函数级/DataFrame 级验证前移到 repository checks | 【事实】 |
| Repository style checks | PEP8/Pylint 可通过 `com.palantir.conda.pep8`、`com.palantir.conda.pylint` Gradle 插件启用 | 将代码风格和静态质量纳入代码库检查，而非仅靠人工 review | 【事实】 |
| Coverage gate | 官方说明可用 pytest-cov 并通过 `--cov-fail-under` 配置最低覆盖率 | 可把测试覆盖率变成 repository checks 的硬门槛 | 【事实】 |
| Batch pipeline boundary | Python repository unit tests 只适用于 batch pipelines，不支持 streaming pipelines | 自建平台不能把 batch transform 测试模式直接外推到流式作业 | 【事实】 |
| Data expectations | Expectations 可定义在 dataset inputs/outputs 上，作为 strongly typed requirement/check | 数据质量规则成为 transform contract 的一部分 | 【事实】 |
| Build abort | Expectation 失败可配置 fail/abort；失败结果会出现在 Builds application、History tab 和 Data Health | 质量规则从“监控告警”提升为“构建断路器” | 【事实】 |
| Protected branch review | 改动 protected branch 上的 expectations 需要走 PR review；开发分支可先 build 验证 | 数据质量规则本身被当作代码治理对象 | 【事实】 |
| Incremental expectation behavior | 官方说明所有 checks 都在 full datasets 上运行，即使 transform 是 incremental | 增量计算不意味着只校验增量片段；质量门槛仍以完整输出资产为对象 | 【事实】 |

关键判断：Foundry 的质量体系至少有三层：repository checks 管代码，data expectations 管数据契约，Data Health 管运行期健康。【推断】

---

## 5. 血缘与权限机制

### 5.1 Data Lineage

Data Lineage 是 Foundry 中用于观察数据如何流经平台的交互式工具，支持查找 datasets、展开 ancestors/descendants、查看 schema、最近 build 时间和生成数据的代码。【事实】

Data Lineage 支持从图中查看 dataset 的代码并跳转到 code workbook 或 repository；这说明高码 transform 与平台血缘不是分离系统，而是通过 repository/dataset 元数据形成可导航关系。【事实】

Branching Data Lineage 支持在 global branch 上查看 branch-aware 的 dataset、ontology entity、link、build history 和 staleness；这使开发分支上的高码变更具备影响观察能力。【事实】

对自建平台的含义：血缘不应只是运行后记录 edges，还应能从资源节点反查生成代码、构建历史、schema、分支状态和权限影响。【推断】

### 5.2 Markings 与 Roles

Markings 为 files、folders、Projects 提供额外访问控制；用户必须是资源上所有 Markings 的成员才能访问；Marking 访问是二元的，角色不能绕过 Marking。【事实】

Palantir 官方把 Markings 定义为 mandatory control，把 roles 定义为 discretionary control；Markings 限制访问资格，roles 决定在资源上可执行的工作流。【事实】

Markings 不应被用来授予访问；即使用户满足 Marking eligibility，仍需通过 Project/resource role 获得实际访问权限。【事实】

### 5.3 停止继承与安全审批

当派生资源中受限内容已被移除或混淆时，可用 `stop_propagating` 移除继承 Markings，用 `stop_requiring` 移除继承 Organizations。【事实】

官方要求 repository 至少有一个 protected branch，并且受保护分支必须 enforce 至少一个 required approver；只能在 protected branches 上移除 Organizations/Markings，未保护分支会导致 build fail。【事实】

移除 Markings 需要 `Remove marking` 权限，移除 Organizations 需要 `Expand access` 权限；PR 可由持有相应权限的用户 approve/reject。【事实】

关键判断：高码中的权限治理不是在 transform 代码里手写 ACL，而是由平台基于 lineage、branch protection、security approval 和 Marking propagation 强制执行。【推断】

---

## 6. 可观测性闭环

| 阶段 | Foundry 能力 | 高码关系 | 可信度 |
|---|---|---|---|
| 开发前/开发中 | Branch build、Data Lineage branch-aware view、repository checks | 在合并前检查代码质量、数据输出和影响范围 | 【推断】 |
| 构建期 | Builds application、Data Expectations indicator、History tab | 把 transform build、quality gate、失败明细连接到同一执行记录 | 【事实】 |
| 运行监控 | Data Health monitoring views、health checks | 对 datasets、schedules、streaming datasets、functions、actions 等资源配置监控与告警 | 【事实】 |
| 告警通知 | Foundry notifications、email、PagerDuty、Slack、webhooks | 把高码 pipeline 的失败、延迟、质量问题推送到运维渠道 | 【事实】 |
| 调试诊断 | Workflow Lineage execution history、log search、trace views | 从失败资源追到执行、日志、服务调用和错误信息 | 【事实】 |
| 二次分析 | Export logs/metrics/traces to streaming dataset | 可把平台遥测变成自定义 dashboard/pipeline 的输入 | 【事实】 |

Observability 官方把能力分为 Monitor、Debug、Trace、Analyze：Data Health 用于监控和规则阈值，Workflow Lineage 用于历史与日志排查，trace views 用于跨服务请求旅程，日志/指标/trace 可导出到 streaming dataset 做进一步分析。【事实】

Data Health 提供两组核心能力：Monitoring views 用 scope-based rules 做规模化监控，Health checks 用于单个资源的细粒度检查，包括 dataset 的 content/schema validation。【事实】

关键判断：Data Expectations 的 check result 上报 Data Health，说明数据质量不是孤立的 transform API，而是进入统一健康监控和告警体系。【推断】

---

## 7. 内置能力 vs 平台依赖

| 维度 | 内置能力 | 平台依赖 | 可信度 |
|---|---|---|---|
| 高码编辑与协作 | Web IDE、Git、PR、lint/error checking、repository checks | Code Repositories 权限模型、protected branch、CI/checks 基础设施 | 【事实】 |
| 单元测试 | pytest、pytest-cov、DataFrame test examples | Foundry repository checks、conda environment、Gradle plugins | 【事实】 |
| 数据质量 | Data Expectations API、pre/post-condition、build abort | Builds application、History tab、Data Health、protected branch review | 【事实】 |
| 血缘 | Ancestor/descendant graph、code navigation、branch-aware lineage | Dataset metadata、repository metadata、branch metadata、ontology links | 【事实】 |
| 权限 | Markings、Organizations、roles、stop_propagating、stop_requiring | Mandatory access control service、security approval、protected branch enforcement | 【事实】 |
| 可观测性 | Data Health、Workflow Lineage、trace views、metrics/logs/traces export | 平台遥测采集、资源图、告警集成、日志权限 | 【事实】 |

关键判断：Foundry 高码治理的强项不在某一个 SDK，而在代码仓库、构建系统、数据资产、权限系统、血缘图和运维遥测共用平台身份与元数据。【推断】

---

## 8. 对自建平台建议

1. 把 transform repository 作为一等资源，而不是把代码当作任务脚本附件；repository 应内置 PR、protected branch、checks、review policy、release/tag 策略。【推断】
2. 设计三类质量门禁：代码门禁（lint/test/coverage）、数据契约门禁（schema/null/uniqueness/range/custom expectations）、运行健康门禁（freshness/failure/latency/SLA）。【推断】
3. Data Expectations 应支持 fail/abort 与 warn 两种处理方式，并将 check result 写入统一健康模型，避免质量规则只存在于日志里。【推断】
4. 血缘模型至少要关联 dataset、transform code version、input/output contract、build transaction、branch、owner、permission/marking 状态。【推断】
5. 权限传播要平台化；敏感标签应默认沿血缘向下游传播，任何停止传播都必须要求受保护分支、审批、审计和重新构建策略。【推断】
6. 不要把可观测性限定为任务日志；需要统一支持资源健康、执行历史、日志搜索、指标、trace、告警渠道和遥测数据再分析。【推断】
7. 对 streaming pipeline 要单独设计测试与质量策略，因为 Palantir 官方对 Python repository unit tests 明确标注不支持 streaming pipelines。【事实】
8. 若实现增量 transform，应明确 quality checks 是校验增量片段还是完整输出；Foundry 官方 Data Expectations 在 incremental 场景下仍运行在 full dataset 上。【事实】

---

## 9. 证据缺口

1. 官方公开文档未完整披露 repository checks 的底层 CI 编排、任务图和缓存策略；只能确认插件、Checks tab 与 protected branch 要求，不能断言内部实现。【猜测】
2. 官方公开文档未完整披露 Marking propagation 的底层索引一致性、异步传播延迟和历史 transaction 重算策略；已有本地文档给出工程判断，但仍需真实环境验证。【猜测】
3. Data Health 对每类资源的完整 rule schema、SLA 表达能力和告警去重/升级策略未在本轮资料中完全展开。【猜测】
4. Workflow Lineage、Data Lineage、Builds application 之间共享哪些内部事件模型和 ID 体系未公开；只能从功能联动推断其存在统一资源/执行元数据。【猜测】
5. Java/SQL transform 的 unit tests、data expectations 与 Python 的功能等价性未在本轮逐页核验，不能把 Python 结论无条件外推到所有语言。【猜测】

---

## 10. 参考来源

### 官方 Palantir 文档

- Code Repositories Overview: https://www.palantir.com/docs/foundry/code-repositories/overview/index.html
- Code Repositories Branch settings: https://www.palantir.com/docs/foundry/code-repositories/branch-settings
- Code Repositories Administer repositories: https://www.palantir.com/docs/foundry/code-repositories/admin-overview
- Python transforms Overview: https://www.palantir.com/docs/foundry/transforms-python/lightweight-overview
- Python transforms Unit tests: https://www.palantir.com/docs/foundry/transforms-python/unit-tests/
- Python transforms Data expectations reference: https://www.palantir.com/docs/foundry/transforms-python/data-expectations-reference
- Maintaining pipelines Define data expectations: https://www.palantir.com/docs/foundry/maintaining-pipelines/define-data-expectations
- Pipeline Builder Data expectations Overview: https://www.palantir.com/docs/foundry/pipeline-builder/dataexpectations-overview/
- Data Lineage Overview: https://www.palantir.com/docs/foundry/data-lineage/overview/
- Data Lineage Explore lineage: https://www.palantir.com/docs/foundry/data-lineage/explore-lineage/index.html
- Data Lineage Branching data lineage: https://www.palantir.com/docs/foundry/data-lineage/branching-data-lineage/
- Data Lineage See impact of Marking changes: https://www.palantir.com/docs/foundry/data-lineage/see-impact-marking-changes
- Security Markings: https://www.palantir.com/docs/foundry/security/markings/
- Remove inherited Markings and Organizations: https://www.palantir.com/docs/foundry/building-pipelines/remove-inherited-markings
- Observability Overview: https://www.palantir.com/docs/foundry/observability/overview
- Data Health: https://www.palantir.com/docs/foundry/observability/data-health/
- Monitoring views Overview: https://www.palantir.com/docs/foundry/data-health/monitoring-views-overview
- Health checks Overview: https://www.palantir.com/docs/foundry/data-health/overview/
- Python transforms Metrics: https://www.palantir.com/docs/foundry/transforms-python/metrics/
- AIP Observability Trace views: https://www.palantir.com/docs/foundry/aip-observability/trace-view

### 仓库内参考

- `docs/raw/22-pro-code-source-map.md`
- `docs/raw/05-testing-and-data-connection.md`
- `docs/raw/08-monitoring-and-observability.md`
- `docs/raw/11-marking-mechanism-deep-dive.md`
