# Palantir AI FDE 交互、上下文、模式与工具模型调研

**调研日期：** 2026-05-30
**文件编号：** 34
**主题：** AI FDE session lifecycle / context sources / modes / skills / tools / approval / observe-act loop
**对应 issue：** #23

---

## 0. 结论摘要

AI FDE 的交互模型不是“给一个全能聊天机器人接入所有 Foundry API”，而是“由用户显式控制上下文和工具边界，再让 agent 在模式、技能、审批和分支提案约束内执行 Foundry 操作”。官方文档明确说明：AI FDE 初始只加载最小 Foundry 概念上下文，不访问用户数据；用户通过 mode、context ribbon、拖拽链接、搜索工具、tool menu 和审批来逐步扩大可见资源与可调用能力。【事实】

核心闭环可以抽象为：【推断】

```text
Intent
  -> Mode
  -> Context
  -> Tool plan
  -> Approval
  -> Execute
  -> Observe
  -> Validate
  -> Proposal
```

其中 Mode 决定任务域、文档集和可用工具范围；Skills 是可跨 Mode 复用的细粒度能力，每个 Skill 映射到一个或多个具体工具；Tool Gateway 则在执行前叠加用户权限、工具配置、分支/项目 allowlist、审批策略和审计记录。【事实 + 推断】

自建最小可复刻模块不是先做“大模型智能”，而是先做六个边界组件：`context registry`、`mode router`、`skill registry`、`tool gateway`、`session outline`、`approval UI`。【推断】这些模块共同解决三类关键风险：上下文污染、工具误用、越权写入。【推断】

---

## 1. 官方证据索引

| 来源 | URL | 覆盖内容 | 本文使用方式 |
|---|---|---|---|
| AI FDE Overview | https://www.palantir.com/docs/foundry/ai-fde/overview | AI FDE 定义、工作步骤、最小上下文、可定制工具、闭环执行、验证方式、默认分支提案 | 主证据 |
| AI FDE Navigation | https://www.palantir.com/docs/foundry/ai-fde/navigation | session 管理、context sources、chat outline、token 显示、摘要/删除、tool menu、approval 触发条件 | 主证据 |
| AI FDE Modes and skills | https://www.palantir.com/docs/foundry/ai-fde/modes-and-skills | Mode 列表、Mode 配置、Skills 类型、Manage context/skills | 主证据 |
| AI FDE Security and governance | https://www.palantir.com/docs/foundry/ai-fde/security-and-governance | 当前用户身份、权限约束、审批系统、session access、markings、审计、LLM 归因 | 主证据 |
| AI FDE Best practices | https://www.palantir.com/docs/foundry/ai-fde/best-practices | 限制上下文/工具、验证生产资源、迭代开发、AIP Evals、基础设施压力 | 主证据 |
| AIP Architecture | https://www.palantir.com/docs/foundry/architecture-center/aip-architecture | AIP 端到端能力、context engineering、tool services、observability、agent lifecycle、enterprise automation | 辅助架构证据 |

---

## 2. Session lifecycle 与 chat outline

### 2.1 会话启动

用户进入 AI FDE 应用后，通过底部输入框提问或发起请求；顶部工具栏可创建新 session 和管理已有 session。【事实】官方未公开 session 对象的数据结构、生命周期状态机或持久化 schema。【事实】

AI FDE 初始状态只加载最小上下文，用于提供 Foundry 概念知识，不访问用户数据；每次交互从受控基线开始，以减少 irrelevant context 对模型推理的干扰。【事实】

自建时可以把 session lifecycle 拆为四个显式状态：【推断】

```text
new_session
  -> context_configured
  -> running_turns
  -> proposed_or_closed
```

其中 `context_configured` 不要求用户手动选择所有内容，因为 AI FDE 可以从自然语言 prompt 自动选择 mode 并据此确定可用 context 和 tools。【事实】

### 2.2 Session 访问控制

AI FDE session 只对创建者可见，不能被其他用户共享或访问；创建新 session 时会应用用户可访问的 markings；如果用户失去某个 applied marking 的访问权，也会失去该 session 的访问权，恢复 marking 权限后恢复 session 访问。【事实】

这说明 AI FDE 的 session 不是普通聊天记录，而是带有 Foundry governance 语义的安全对象。【推断】自建系统不能只用“用户 id + conversation id”做访问控制，还需要把 session 绑定到数据分级、租户、项目、branch、resource marking 或等价标签集合。【推断】

### 2.3 Chat outline、token 管理、摘要与移除

AI FDE 右侧 collapsible chat outline 记录 session 内的 prompts、responses 和使用过的 tools；outline 会展示每条 message 使用的 token 数。【事实】用户可以在主聊天区或 outline 中对 message 执行 summary 或 complete removal，以避免长会话触及模型 context window。【事实】

官方说明了“可摘要/可删除”和“显示每条 token”，但没有公开摘要算法、摘要后的可追溯性策略、删除是否保留审计摘要、token budget 阈值或自动压缩策略。【事实】

对自建系统，chat outline 至少要承担三种职责：【推断】

| 职责 | 说明 | 关键控制 |
|---|---|---|
| 操作透明 | 展示 prompt、response、tool call、tool result、approval decision | 每次 tool call 可追溯到用户 turn |
| token 预算 | 统计每条消息和每类 context 的 token 占用 | 超预算前提示摘要、移除或降采样 |
| 上下文治理 | 支持 summary、remove、pin、unpin、scope 切换 | 被移除内容不能继续进入模型输入 |

摘要本身应视为新的上下文资产，而不是原消息的无损替代。【推断】如果摘要进入后续模型输入，应记录摘要来源、摘要时间、摘要模型、摘要者、覆盖的原消息范围和置信风险。【推断】

---

## 3. Context sources

### 3.1 上下文来源清单

官方公开的 AI FDE context source 包括：【事实】

| Context source | 添加方式 | 作用 |
|---|---|---|
| 自然语言任务描述 | 输入框 prompt | 让 agent 自动选择 mode，并据此确定上下文与工具范围 |
| Mode 选择 | 输入框上方 Modes menu | 手动约束任务域；部分 mode 有额外配置 |
| 文档包 | prompt input 上方 ribbon | 向 agent 提供任务相关 Foundry 文档 |
| 上传媒体 | context ribbon | 向会话附加用户上传材料 |
| Datasets | context ribbon | 提供数据资产上下文 |
| Functions | context ribbon | 提供 Foundry Functions / Logic / TypeScript / Python function 上下文 |
| Branches | context ribbon | 指定分支语境，影响读取、写入和审批 |
| Interfaces | context ribbon | 提供接口定义上下文 |
| Action types | context ribbon | 提供 Ontology action 语义 |
| Object types | context ribbon | 提供 Ontology object schema 和业务语义 |
| Foundry 应用链接 | 拖拽其他 Foundry 应用链接到 AI FDE | 快速引用平台资源 |
| 搜索工具 | 启用 search tools | 允许 AI FDE 查找相关资源 |

AI FDE 只访问被添加到 chat 的 context；这是一条重要边界，不是 UI 细节。【事实】

### 3.2 Context registry 抽象

自建 `context registry` 应把所有上下文统一建模为带作用域和生命周期的引用，而不是直接拼接进 prompt。【推断】

```text
ContextItem {
  id
  type: documentation_bundle | dataset | function | branch | interface | action_type | object_type | uploaded_media | dragged_link | search_result | message_summary
  source_uri
  owner_user
  tenant_or_project
  markings_or_labels
  branch_scope
  token_estimate
  retrieval_policy
  permission_snapshot
  added_by: user | agent | search_tool | mode_default
  status: active | summarized | removed | expired
}
```

`permission_snapshot` 不能替代执行时的实时权限校验，因为官方明确 AI FDE 所有操作仍使用当前用户 session 并受服务器端权限约束。【事实】它的价值是解释“为什么当时把这个 context 放进 prompt”。【推断】

### 3.3 上下文污染控制

Palantir 官方把最小初始上下文和用户可控上下文称为避免 context pollution 的机制，并建议只提供任务必要的 context 和 tools。【事实】

自建控制点：【推断】

| 风险 | 控制点 |
|---|---|
| 无关文档稀释推理 | Mode 默认只加载该 mode 的文档包；其他文档需要用户或 agent 明确添加 |
| 搜索结果误注入 | 搜索结果先进入候选池，用户或 agent plan 明确选择后才进入 active context |
| 长会话旧事实污染 | session outline 支持 per-message remove、summary、pin；每轮 prompt 构造只读取 active context |
| branch 语义混乱 | 所有资源 context 带 branch scope；跨 branch 读写要在 plan 和 approval 中显式展示 |
| 摘要丢失约束 | 摘要保留来源、范围和未解决问题；高风险约束不只存在于摘要文本中 |
| 敏感资源过曝 | context registry 对每个 item 做权限和 marking 校验；模型输入前再次过滤 |

---

## 4. Modes 与 Skills

### 4.1 Mode 是任务域路由

官方说明 Modes 表示当前任务类型，用户可手选，也可只输入任务让 agent 自动选择；agent 也可以在任务演化时切换 mode。【事实】

AI FDE 公开 mode 包括：【事实】

| Mode | 官方范围 |
|---|---|
| Data integration | 构建或修改 Python transforms / Pipeline Builder 数据管道 |
| Data connection | 创建、管理、调试 Data Connection sources、egress policies 等 |
| Ontology editing | 创建或更新 ontology objects、links、actions |
| Functions editing | 编写 Logic、TypeScript 或 Python functions |
| Exploration | 只读探索，理解平台现状 |
| Governance | 审计 permissions、access control、markings、data protection |
| Machine learning | 训练、评估、部署和调优机器学习模型 |
| OSDK React | 构建连接 Foundry 数据的 React 应用或 custom widgets |
| Platform Q&A | 询问 Foundry 工作方式 |

部分 mode 支持额外配置：Data integration 可选 Python transforms 或 Pipeline Builder；Function editing 可选语言；Machine learning 可选 Model Studio/no-code 或 pro-code development 以及 preferred code editing environment。【事实】

Mode 的主要作用是聚焦 agent：加载合适文档、开放相关工具、调整解决问题方式，从而降低分心和误用工具概率。【事实】

### 4.2 Skills 是可复用能力单元

官方说明 Skills 是可跨 mode 使用的细粒度能力，每个 skill 映射到一个或多个具体 tools；Skills 分为 agent skills 和 domain skills。【事实】

公开 agent skills 包括：Change mode、Request clarification、Generate plan、Load documentation、Manage context/Manage skills。【事实】公开 domain skills 示例包括：Filesystem、Notepad、Solution design、Execute actions。【事实】

Mode 和 Skill 的关系可以这样建模：【推断】

```text
Mode = task-domain policy bundle
  - default documentation
  - default tool groups
  - allowed resource types
  - validation expectations
  - proposal target type

Skill = callable capability bundle
  - tool mappings
  - preconditions
  - approval class
  - observable outputs
  - failure handling hints
```

Skills 可以启用或禁用；agent 也可以在任务中途借助 Manage skills 自行开关 skills。【事实】因此自建系统需要把“skill activation”纳入 session outline 和 approval/audit，而不是把它隐藏在模型内部。【推断】

### 4.3 Mode router 与 Skill registry

最小 `mode router` 应支持四类输入：【推断】

1. 用户显式选择的 mode。
2. 从 prompt 分类得到的候选 mode。
3. 当前 active context 中资源类型暗示的 mode。
4. agent 中途申请切换 mode 的理由。

最小 `skill registry` 应包含：【推断】

| 字段 | 说明 |
|---|---|
| `skill_id` | 稳定标识 |
| `skill_type` | agent skill / domain skill |
| `supported_modes` | 可在哪些 mode 下启用 |
| `tool_refs` | 映射工具列表 |
| `approval_category` | read-only / branch-aware / always-approve-required |
| `context_requirements` | 必要 context 类型 |
| `side_effects` | 是否写入、发布、构建、执行业务 action |
| `observability_contract` | tool result 需要返回哪些可观察信息 |

---

## 5. Tool configuration 与 approval

### 5.1 工具选择

AI FDE 的 tools menu 位于 request input 下方，用户可选择启用哪些工具；官方说明模型在只启用任务所需工具子集时表现更好。【事实】

AI FDE 可使用与 Foundry 用户平台操作匹配的工具，例如创建 object types、写 transforms、运行 builds；它会展示执行动作所用工具，并在 active session 的 chat outline 中保留 prompts 和 tools 记录。【事实】

### 5.2 Approval 触发条件

Navigation 文档列出的默认审批触发包括：工具在 default branch 上做改动、工具做 unbranched change 例如创建 code repository、工具可能有副作用例如 dataset builds。【事实】

Security 文档进一步给出三类审批策略：【事实】

| 类别 | 示例 |
|---|---|
| 每次都需要 approval | 执行 ontology actions、创建 applications/widgets、publishing、创建 tags |
| Branch-aware approval | feature branch 上 file edits 和 dataset builds 可 auto-approve；protected branch 需要 approval |
| Auto-approved | 搜索、读取 definitions 等只读操作 |

工具审批可在 tool selection panel 中自定义，相关工具可被设置为在 allowlisted branches 和 projects 上自动执行。【事实】

### 5.3 Tool gateway 抽象

自建 `tool gateway` 至少要在每次 tool call 前执行以下检查：【推断】

```text
tool_call_request
  -> schema validation
  -> mode/skill allowed?
  -> context/resource scope allowed?
  -> user permission check
  -> branch/protected-resource check
  -> side-effect classification
  -> approval decision
  -> execution
  -> result observation
  -> audit append
```

重要的是，approval 不是 permission 的替代。官方明确所有操作仍受当前用户权限约束，且 AI FDE 没有独立 service account 或额外权限；approval 是在服务器端权限之外叠加的人机确认层。【事实】

### 5.4 工具误用控制

| 风险 | 控制点 |
|---|---|
| mode 错误导致工具集合过宽 | mode router 只开放 mode 对应工具组；跨 mode 工具需要 Change mode 或显式 plan |
| read tool 与 write tool 混淆 | tool registry 标注 side effect、branch requirement、approval category |
| 模型构造危险参数 | tool gateway 做参数 schema、资源 scope、branch scope 和 dry-run preview 校验 |
| 用户盲批 | approval UI 展示 tool name、参数摘要、影响资源、branch、side effects、可回滚性、验证计划 |
| session 级 allowlist 滥用 | allowlist 限定 branch/project/tool/resource type，设置 TTL，并在 outline 中持续可见 |
| 高频并发执行压垮平台 | per-session/per-user rate limit、build queue quota、GPU/compute/storage 预算控制 |

Palantir 官方特别提醒 AI FDE 可在短时间内连续执行大量操作，多个 session 并行会放大存储、计算、网络和容量压力。【事实】

---

## 6. Closed-loop observe-act feedback

### 6.1 官方闭环

AI FDE 在收到自然语言请求后会分析 intent 和 context、确定 Foundry operations、使用 native tools 执行动作、返回 contextual explanations 和 documentation。【事实】

官方还说明 AI FDE 采用 closed-loop operation model：模型执行 action、观察 result，并使用反馈决定下一步 action；前一个操作的输出会成为后续决策输入。【事实】

官方列出的验证动作包括：运行 transform preview 验证 transform code、运行 function preview 验证 function behavior、查看 Code Repositories 中代码的 CI checks。【事实】Best practices 还建议生产前人工验证生成资源、用代表性样本测试 transform logic，并用 AIP Evals 跟踪 AI FDE 创建或修改 functions 的性能。【事实】

### 6.2 文字流程图

```text
Intent
  用户用自然语言描述目标，或继续 long-running session 中的上一阶段任务。

-> Mode
  系统根据用户手选 mode 或 prompt 自动路由到 Data integration / Ontology editing /
  Functions editing / Exploration / Governance / Machine learning / OSDK React /
  Platform Q&A 等任务域；必要时由 Change mode skill 中途切换。

-> Context
  从 mode 默认文档、用户添加的 documentation bundles、Datasets、Functions、
  Branches、Interfaces、Action types、Object types、上传媒体、拖拽链接、
  search tools 和 chat outline active messages 中构造本轮上下文。

-> Tool plan
  agent 根据 mode、active skills、context 和用户目标生成操作计划；
  ambiguous 或 multi-step 任务可先用 Generate plan skill 给用户审阅。

-> Approval
  tool gateway 对每个 tool call 做权限、branch、side effect、allowlist 和审批判断；
  mutating 或敏感操作进入 approval UI，只读搜索/读取可自动通过。

-> Execute
  使用当前用户 Foundry session 调用 native tools；不使用额外 service account；
  tool call、参数摘要、结果和审批决策写入 session outline/audit。

-> Observe
  agent 读取 tool result、错误、preview 输出、build 状态、CI 状态、资源定义变化；
  失败信息进入下一步推理，而不是简单结束。

-> Validate
  对 transform/function/code/ontology 等变更运行 preview、eval、CI 或人工检查计划；
  生产前要求用户理解并确认 tool action 与结果。

-> Proposal
  默认在 branch 上工作，将变更作为 Global Branch proposal 或 Code Repository pull request
  提交给用户和既有治理流程审查；未验证或高风险项保留为待办/证据缺口。
```

上述流程图中 `Mode -> Context -> Tool plan` 是模型推理入口，`Approval -> Execute -> Observe` 是工具闭环入口，`Validate -> Proposal` 是从 agent 行为回到工程治理的边界。【推断】

---

## 7. 最小可复刻模块

| 模块 | 最小职责 | 必要数据结构 | 关键验收 |
|---|---|---|---|
| `context registry` | 管理 active/summarized/removed context，维护来源、权限、token、branch scope | `ContextItem`、`ContextSet`、`ContextPolicy` | 被移除 context 不再进入 prompt；每项 context 可追溯来源 |
| `mode router` | 根据 prompt、用户选择和当前 context 选择/切换 mode | `ModeDefinition`、`ModeSelection`、`ModeSwitchRequest` | 每轮输出当前 mode 和理由；跨 mode 需记录 |
| `skill registry` | 定义 agent/domain skills、tool mappings、preconditions、approval category | `SkillDefinition`、`SkillActivation` | skill 启停在 outline 中可见；只允许 mode 支持的 skill |
| `tool gateway` | 统一 tool schema、权限、审批、执行、观察和审计 | `ToolDefinition`、`ToolCall`、`ToolResult`、`ApprovalPolicy` | 所有写操作先过 gateway；无绕过路径 |
| `session outline` | 展示 prompts、responses、tools、token、summary/remove 操作 | `SessionTurn`、`OutlineNode`、`TokenUsage` | 用户能定位每次操作的前因后果 |
| `approval UI` | 让用户确认 mutating/sensitive tool call，并支持 session 级 scoped allowlist | `ApprovalRequest`、`ApprovalDecision`、`AllowlistRule` | 展示影响范围、branch、side effect、回滚/验证方式 |

### 7.1 模块依赖关系

```text
User Prompt
  -> Session Outline
  -> Mode Router
  -> Context Registry
  -> Skill Registry
  -> Tool Gateway
  -> Approval UI
  -> Native Platform Tools
  -> Tool Gateway
  -> Session Outline
```

`session outline` 同时在链路开头和结尾出现，因为它既是模型上下文来源之一，也是用户审计和 token 管理界面。【推断】

---

## 8. 越权与治理风险控制点

### 8.1 权限与身份

AI FDE 使用当前用户的 authenticated Foundry session 执行操作，没有独立 bot/service account，也没有 escalated privilege；用户没有的权限，AI FDE 也没有。【事实】

自建系统必须避免把 agent tool service 做成“高权限平台服务代替用户执行”。【推断】如果因技术原因需要后端服务账号调用底层 API，也必须实现 on-behalf-of 授权、细粒度资源校验、审计归因和用户可见 approval，而不能让服务账号权限变成 agent 权限上限。【推断】

### 8.2 分支与发布

AI FDE 默认跨 workflow 使用 branching，并把变更作为 Global Branch proposal 或 Code Repository pull request 供审查。【事实】这说明 agent 的默认产物是“可审查提案”，不是直接生产写入。【推断】

自建系统的高风险写入应默认落到 branch/sandbox/draft，不直接改 default/protected branch。【推断】default branch、unbranched change、publishing、tagging、ontology action execution、application creation 等都应进入强审批。【推断】

### 8.3 审计与归因

AI FDE 活动通过标准 Foundry audit logs 完全可审计；每个 API call 携带用户身份，LLM usage 也归因到个人用户，用于 usage tracking 和 rate limiting。【事实】

自建 audit ledger 至少记录：【推断】

- user identity、session id、turn id、mode、active skills。
- context ids 和 token usage。
- tool call name、参数摘要、资源 scope、branch、side effect class。
- approval request、approval decision、allowlist rule。
- tool result、validation result、proposal target。
- model id、prompt/context版本、usage、失败重试。

---

## 9. 自建实施优先级

### P0：只读探索闭环

实现 `session outline + mode router + context registry + read-only tool gateway`。【推断】只支持 Exploration、Platform Q&A、Governance read-only 子集；tool 仅允许 search/read definitions/list resources；所有 context 可见、可删除、可摘要。【推断】

### P1：branch-local 变更

加入 `approval UI + branch-aware tool policy`，支持在非 protected feature branch 上做文件编辑、transform preview、function preview。【推断】目标是把 agent 输出限制为 branch proposal 或 PR，而不是生产发布。【推断】

### P2：验证与提案

把 preview、CI checks、AIP Evals 或等价 eval runner 作为 validate step 固化；proposal 必须包含验证证据和未验证缺口。【推断】

### P3：跨域技能扩展

在已有 gateway 上扩展 Ontology action、application/widget creation、dataset build、publishing 等高风险 domain skills；这些默认逐次审批，不继承低风险 allowlist。【推断】

---

## 10. 证据缺口

以下内容公开文档未验证，不能在后续 synthesis 中当作事实使用：【事实】

| 缺口 | 影响 | 暂定处理 |
|---|---|---|
| AI FDE session 数据模型和持久化 schema | 难以复刻 session/outline 精确行为 | 用自建抽象替代，标为推断 |
| 自动摘要算法和 token budget 阈值 | 无法判断 summary 何时触发、如何保真 | 只要求可见 token、手动摘要/删除和可追溯 |
| Mode router 的真实分类器/提示词 | 无法复刻 Palantir 内部路由准确率 | 用规则 + LLM 分类 + 用户确认 |
| Skill 到 Tool 的完整映射 | 只能看到公开示例 | 建立 registry，逐步补工具 |
| Tool approval policy 的内部配置 schema | 无法复刻 exact allowlist 语义 | 用 branch/project/tool/resource scope 模型 |
| Search tools 的检索范围和排序策略 | 影响 context recall/precision | 搜索结果先进入候选，不自动污染 active context |
| Global Branch proposal 和 Code Repository PR 的 AI FDE 具体模板 | 影响 proposal UI 复刻 | 只要求变更、验证、风险和缺口可审查 |

---

## 11. 可粘贴 issue #23 评论草稿

```markdown
Agent C 已完成 raw 调研文档：

- 文档：`docs/raw/34-ai-fde-context-tools-skills.md`
- 核心流程：Intent -> Mode -> Context -> Tool plan -> Approval -> Execute -> Observe -> Validate -> Proposal
- 最小可复刻模块：context registry、mode router、skill registry、tool gateway、session outline、approval UI
- 核心结论：AI FDE 的关键不是全量开放工具，而是用 mode/skill/context/tool approval 把 agent 限定在当前用户权限、分支、可见上下文和可审计闭环内。
- 主要证据：Palantir AI FDE Overview、Navigation、Modes and skills、Security and governance、Best practices、AIP Architecture。
- 证据缺口：官方未公开 session schema、摘要算法、token budget 阈值、mode router 内部逻辑、完整 skill-tool 映射、tool approval policy schema、search ranking、proposal 模板。
```
