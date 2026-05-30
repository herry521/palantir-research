# 32 — Palantir AI FDE 资料源与术语基线

**采集日期：** 2026-05-30
**关联 Issue：** #22
**所属计划：** `docs/superpowers/plans/2026-05-30-palantir-ai-fde-research-plan.md`
**类型：** 资料源索引 / 术语边界 / 可信度基线

---

## 0. 目的

本文件为 Palantir AI FDE 调研建立可追溯资料源和术语边界。后续 Agent 应优先引用本文件中的官方资料源；如新增来源，需要在对应 raw 文档中写明新增依据、采集日期和可信度标签。

---

## 1. 可信度标签

| 标签 | 判定标准 | 使用边界 |
|---|---|---|
| 【事实】 | 官方 Palantir 文档、Palantir 官方公告/活动页，或本仓库已核对材料直接支持 | 可作为事实陈述进入后续 raw 文档和综合结论 |
| 【推断】 | 多个【事实】组合出的工程判断，且必须写出推理链 | 可用于架构、产品定位或实现建议，但不能伪装成官方披露 |
| 【猜测】 | 公开资料无法验证的合理假设，或只来自非官方/社区反馈的现象 | 必须隔离为待验证问题，不应作为高置信设计前提 |

注意：标签表示“截至 2026-05-30 本轮公开资料核对结果”，不是对 Palantir 内部实现或客户环境可用性的承诺。Palantir 官方文档多处提示 AIP/AI FDE 功能可用性可能随客户和时间变化。

---

## 2. 官方资料源矩阵

| 编号 | URL | 来源类型 | 覆盖主题 | 可信度 | 采集日期 | 给哪个后续 Agent 使用 |
|---|---|---|---|---|---|---|
| S01 | https://www.palantir.com/docs/foundry/ai-fde/overview | Palantir 官方产品文档 | AI FDE 定义、启用要求、自然语言到 Foundry 操作、闭环执行、默认分支/PR/Proposal、模型支持 | 【事实】 | 2026-05-30 | Agent B/C/D/E/F/G |
| S02 | https://www.palantir.com/docs/foundry/ai-fde/navigation | Palantir 官方产品文档 | AI FDE 会话、上下文添加、工具配置、工具审批默认场景、chat outline | 【事实】 | 2026-05-30 | Agent C/D/E/F/G |
| S03 | https://www.palantir.com/docs/foundry/ai-fde/modes-and-skills | Palantir 官方产品文档 | modes、skills、agent skills、domain skills、模式切换、工具/文档按任务收敛 | 【事实】 | 2026-05-30 | Agent B/C/E/F/G |
| S04 | https://www.palantir.com/docs/foundry/ai-fde/security-and-governance | Palantir 官方产品文档 | 用户身份执行、权限继承、审批、session access、audit logging、LLM usage attribution | 【事实】 | 2026-05-30 | Agent D/E/F/G |
| S05 | https://www.palantir.com/docs/foundry/ai-fde/best-practices | Palantir 官方产品文档 | 生产前验证、限制工具和上下文、迭代开发、AIP Evals、AI FDE 高频并发操作的基础设施影响 | 【事实】 | 2026-05-30 | Agent C/D/F/G |
| S06 | https://www.palantir.com/docs/foundry/architecture-center/aip-architecture | Palantir 官方架构文档 | AIP 12 类能力、模型接入、观测、上下文工程、Ontology、tool services、治理、agent lifecycle、developer environments、enterprise automation | 【事实】 | 2026-05-30 | Agent E/F/G |
| S07 | https://www.palantir.com/docs/foundry/aip/overview | Palantir 官方产品文档 | AIP 总体定位、AIP Logic、AIP Chatbot Studio、AIP Evals、Ontology 与开发工具链之上的 AI workflow/agent/function | 【事实】 | 2026-05-30 | Agent B/E/F/G |
| S08 | https://www.palantir.com/docs/foundry/aip/aip-features | Palantir 官方产品文档 | AIP 应用参考：AIP Assist、AIP Logic、AIP Chatbot Studio、AIP Evals、AIP Threads、Palantir MCP；平台应用内 AIP 能力 | 【事实】 | 2026-05-30 | Agent B/C/F/G |
| S09 | https://www.palantir.com/docs/foundry/assist/overview | Palantir 官方产品文档 | AIP Assist 的平台内帮助、文档问答、上下文感知、不访问用户数据、自定义内容源和 Assist chatbot | 【事实】 | 2026-05-30 | Agent B/C/G |
| S10 | https://www.palantir.com/docs/foundry/chatbot-studio/overview | Palantir 官方产品文档 | AIP Chatbot Studio 以前称 AIP Agent Studio；构建可部署的 AIP Chatbots，使用 Ontology、documents、custom tools 支持读写 workflow | 【事实】 | 2026-05-30 | Agent B/C/F/G |
| S11 | https://www.palantir.com/docs/foundry/aip-analyst/overview | Palantir 官方产品文档 | AIP Analyst 的 ontology-first ad-hoc analysis、工具类别、SQL/aggregation/visualization/action execution、session persistence 限制 | 【事实】 | 2026-05-30 | Agent B/C/G |
| S12 | https://www.palantir.com/docs/foundry/palantir-mcp/overview | Palantir 官方产品文档 | Palantir MCP 定义、外部 AI IDE/agent 连接 Foundry、上下文与工具、和 AI FDE 的类比、ontology builder 定位 | 【事实】 | 2026-05-30 | Agent B/C/E/F/G |
| S13 | https://www.palantir.com/docs/foundry/palantir-mcp/available-tools | Palantir 官方产品文档 | Palantir MCP 工具清单：Compass、Dataset、Lineage、Ontology、Object set、OSDK、Platform SDK、Code Repository、Global Branching、Developer Console、Compute Module、Data Connection、Documentation search | 【事实】 | 2026-05-30 | Agent C/E/F/G |
| S14 | https://www.palantir.com/docs/foundry/palantir-mcp/security | Palantir 官方产品文档 | Palantir MCP 的 in-platform/local 数据流差异、local 默认禁用、写入限制、human approval/proposal review | 【事实】 | 2026-05-30 | Agent D/E/F/G |
| S15 | https://www.palantir.com/docs/foundry/ontology-mcp/overview | Palantir 官方产品文档 | Ontology MCP 与 Palantir MCP 的边界：Ontology consumer vs builder、数据读写 vs ontology structure 修改、外部 MCP client 风险 | 【事实】 | 2026-05-30 | Agent B/D/F/G |
| S16 | https://www.palantir.com/docs/foundry/announcements/2025-11 | Palantir 官方公告 | AI FDE 与 AIP Analyst beta 发布时间、关键能力、Foundry Branching 建议、透明工具使用和安全可见性 | 【事实】 | 2026-05-30 | Agent B/G |
| S17 | https://www.palantir.com/docs/foundry/architecture-center/overview | Palantir 官方架构文档 | human Forward Deployed Engineering 方法论：工程团队贴近客户问题，与核心工程团队反馈闭环并持续发版 | 【事实】 | 2026-05-30 | Agent B/E/G |
| S18 | https://www.palantir.com/docs/foundry/architecture-center/platforms | Palantir 官方架构文档 | AIP/Foundry/Apollo 与 Forward Deployed Engineering；human FDE 是产品开发范式，不是单一软件功能 | 【事实】 | 2026-05-30 | Agent B/E/G |
| S19 | https://www.palantir.com/devcon3/ | Palantir 官方活动页 | DevCon3 对 AI FDE 的产品发布表述：agentic system 可构建 transforms、ontology、functions、applications；MCP 与 Foundry/AIP 开发者自动化 | 【事实】 | 2026-05-30 | Agent B/C/G |
| S20 | `docs/superpowers/plans/2026-05-30-palantir-ai-fde-research-plan.md` | 本仓库计划文件 | 本轮协作分工、初始事实基线、可信度标签、各 Agent 输出要求 | 【事实】 | 2026-05-30 | Agent A/B/C/D/E/F/G |

---

## 3. 资料源到后续 Agent 的使用建议

| 后续 Agent | 主要使用来源 | 使用边界 |
|---|---|---|
| Agent B：功能定位与产品边界 | S01、S03、S08-S12、S15-S19 | 比较 AI FDE、AIP Assist、AIP Chatbot Studio、AIP Analyst、Palantir MCP、human FDE；不要把所有 AIP agent/chat 产品混称为 AI FDE |
| Agent C：交互、上下文、modes、skills、tools | S01-S05、S10-S13 | 聚焦 intent -> mode -> context -> tool plan -> approval -> execute -> observe -> validate；Palantir MCP 可作为外部 agent/tool 参照 |
| Agent D：安全、治理、审批、分支 | S02、S04、S05、S14、S15、S20 | 区分 AI FDE 自身审批 UI、Foundry 权限继承、Global Branching/Code Repository 评审、MCP local 数据外流风险 |
| Agent E：架构设计推断 | S01-S06、S12-S15、S17-S18 | 官方未披露 AI FDE 内部 orchestrator；只能从 AIP 架构、tool services、permissions、branching、audit 组合推断 |
| Agent F：自建实现蓝图 | S01-S06、S12-S15 | 区分平台原生能力和外部 agent 框架能力；不要假设外部 coding agent 能复制 Foundry 身份、权限、分支和审计 |
| Agent G：综合与证据审查 | S01-S20 | 检查每个 raw 文档是否沿用本文件标签和术语边界，尤其是【推断】是否写出推理链 |

---

## 4. 术语边界

### 4.1 AI FDE

【事实】AI FDE 是 Palantir 文档定义的 “AI-powered forward deployed engineer”：一个通过对话命令操作 Foundry 的交互式 agent，可把自然语言请求转换成 Foundry 操作，包括 data transformations、code repositories、ontology、functions 等。

【事实】AI FDE 依赖 AIP enabled enrollment；官方建议启用 Global Branching 以支持 AI FDE 的 ontology edits。默认工作方式包含分支、Global Branch proposal 或 Code Repository pull request 评审。

【事实】AI FDE 的关键边界是：上下文由用户显式添加或由 mode/tool 配置限定；工具执行遵循当前用户 Foundry session、权限、审批、audit logging 和 LLM usage attribution；它不是独立 service account 或提权 bot。

【推断】AI FDE 应被定义为“平台内 Foundry 操作 agent”，而不是通用聊天机器人。推理链：S01 明确其执行 Foundry operations；S02/S03 说明上下文、modes、skills 和 tools 绑定 Foundry 资源；S04 说明它在用户 Foundry session 下受权限和审计控制。因此后续架构分析应围绕 Foundry tool gateway、context registry、approval、branching、validation，而不是围绕纯 RAG chatbot。

### 4.2 human FDE

【事实】Palantir Architecture Center 把 Forward Deployed Engineering 描述为一种产品开发方法论：工程团队贴近客户任务，与核心工程团队协同，把现场反馈持续转化为产品能力。

【事实】human FDE 是人的组织角色/工程方法，不是 AIP 应用或 Foundry 内的一个 agent 产品。

【推断】AI FDE 的命名是在产品体验上模拟 human FDE 的“贴近问题、操作平台、反馈闭环”能力，但不能推断 AI FDE 拥有 human FDE 的跨组织沟通、需求判断、客户现场知识或 Palantir 内部工程权限。推理链：S17/S18 说明 human FDE 方法论；S01/S04 说明 AI FDE 是受用户 session 和工具权限约束的软件 agent；两者共享“forward deployed engineering”语义，但执行主体和权限边界不同。

### 4.3 AIP Assist

【事实】AIP Assist 是 LLM-powered support tool，帮助用户在 Palantir 平台内用自然语言获得实时帮助。它面向平台导航、文档/开发者帮助、上下文感知支持，并可接入自定义内容源或 AIP Chatbots。

【事实】AIP Assist 官方文档明确说明其 Foundry-grade security 边界包含“不访问你的数据”。因此它的默认定位不是操作 Foundry 资源或修改 ontology/code 的 agent。

【推断】AIP Assist 与 AI FDE 的边界是“帮助/解释/支持” vs “受控执行 Foundry 操作”。推理链：S09 将 AIP Assist 描述为 support tool；S01/S02/S04 将 AI FDE 描述为执行 Foundry operations、工具审批和审计；两者同属 AIP 生态但默认任务面不同。

### 4.4 AIP Chatbot Studio

【事实】AIP Chatbot Studio 以前称 AIP Agent Studio，用于构建可部署的 AIP Chatbots。Chatbots 可由 LLMs、Ontology、documents、custom tools 驱动，嵌入应用中执行动态、上下文感知的读写 workflows。

【事实】AIP Chatbot Studio 是“构建 chatbot/assistant 的平台”，AI FDE 是 Palantir 提供的面向 Foundry 开发/运维任务的专用 agent 应用。

【推断】AIP Chatbot Studio 更像 agent/chatbot builder，AI FDE 更像 Palantir 预置的 specialist enterprise automation agent。推理链：S10 定义 Chatbot Studio 的 builder 属性；S06 把 AI FDE 与 AIP Analyst 归入 specialized AI agents；S01 展示 AI FDE 的固定 Foundry 操作模式、工具和分支评审约束。

### 4.5 AIP Analyst

【事实】AIP Analyst 是面向 ontology 的 ad-hoc analysis 交互界面。它可通过自然语言自主搜索 ontology、创建 object sets、transform data、生成 summaries/visualizations，并支持 SQL、aggregation、function/action execution、visualization、file/media context。

【事实】AIP Analyst 当前文档说明 session 关闭后不保留 conversation history；它也强调 analysis 过程的 transparency、intermediate results、dependency graph 和手工调整。

【推断】AIP Analyst 与 AI FDE 的边界是“分析/探索/可视化优先” vs “构建/修改平台资产优先”。推理链：S11 的工具集中在 discovery、selection、aggregation、SQL、visualization；S01 的 AI FDE 能力集中在 transforms、code repositories、ontology editing、functions editing、governance 和 application/widget building。

### 4.6 Palantir MCP

【事实】Palantir MCP 是 Palantir 对 Model Context Protocol 的实现，使外部 AI IDEs 和 AI agents 能连接 Palantir 平台，获得 Ontology/Foundry 工具上下文，查询文档、metadata、data，并执行高层平台任务。

【事实】Palantir MCP 面向 ontology builders 和开发者工作流，可修改 ontology types、操作 datasets/transforms/code repositories/Global Branching/Developer Console 等，但不能写实际 ontology data；Ontology MCP 则面向 ontology consumers，使外部 agents 受限制地读 objects、执行 predefined actions、query data 和写 ontology data。

【事实】Palantir MCP local development 默认禁用；local 场景下 MCP tool outputs 会发送到对应第三方 LLM provider，数据治理取决于该 provider 合同。Palantir MCP 不提供 destructive write tools；ontology modifications 必须通过 proposal review 并由人批准合并。

【推断】Palantir MCP 是 AI FDE 的外部开发者工具链近邻，而不是 AI FDE 本身。推理链：S12 明确 Palantir MCP 用于 external AI IDEs/agents，并称其提供与 AI FDE 类似的 secure interface；S04 说明 AI FDE 在 Foundry session 内运行；S14 说明 MCP local 数据流和治理模型可能离开 Palantir AIP。

### 4.7 外部 coding agent

【事实】Palantir 文档提到 Claude Code、VS Code Copilot、Windsurf、Cursor、Continue 等第三方/外部 AI IDE 或 coding agent 可通过 Palantir MCP local 或 in-platform VS Code workspace 接入 Foundry 资源。

【事实】外部 coding agent 的模型提供商、数据流和治理取决于所在界面和组织合同；Palantir MCP local 场景下 tool outputs 会发送给相应 LLM provider。

【推断】外部 coding agent 可复用 Palantir MCP 提供的 Foundry context/tools，但其默认不等同于 AI FDE 的平台内身份、session isolation、tool approval、Global Branching/PR proposal UX 和 audit attribution。推理链：S12/S13 说明外部 agent 可调用 MCP tools；S14 说明 local 安全模型不同；S04 说明 AI FDE 的 session、身份和审计强绑定 Foundry。

【猜测】外部 coding agent 能否在某个客户环境中达到接近 AI FDE 的端到端体验，取决于该环境是否启用 Palantir MCP、Global Branching、Code Repository 权限、AIP 模型、审批策略和本地 LLM 合规配置。公开资料不能验证所有客户环境的可用性。

---

## 5. 第一批稳定结论

1. 【事实】AI FDE 是 Palantir 官方提供的 Foundry 操作 agent，核心能力不是“回答问题”，而是通过自然语言驱动 Foundry tools 执行、观察和验证平台操作。
2. 【事实】AI FDE 的安全边界继承当前用户身份、权限、session、markings、audit logs 和 LLM usage attribution；它不是 service account，也没有超越用户的权限。
3. 【事实】AI FDE 的交互模型包含显式上下文管理、mode/skill 选择、工具开关、工具审批、chat outline、branch/PR/proposal review、preview/CI validation。
4. 【事实】AIP Assist、AIP Chatbot Studio、AIP Analyst、Palantir MCP 都属于 AIP/Foundry AI 生态，但分别对应帮助入口、chatbot builder、ontology analysis app、外部 agent/IDE tool interface，不应混称为 AI FDE。
5. 【事实】Palantir MCP 与 Ontology MCP 是不同能力：Palantir MCP 面向 builder 和 ontology structure/platform development；Ontology MCP 面向 consumer 和受限制 ontology data interaction。
6. 【推断】自建 AI FDE 的最小复刻目标不应从“接一个 LLM 聊天窗口”开始，而应从 context registry、mode router、tool gateway、permission proxy、approval engine、branch workspace、validation runner、audit ledger 这些平台约束开始。推理链：S01-S05 定义 AI FDE 的操作/审批/验证闭环；S06 定义 AIP 需要 model access、context engineering、tool services、security governance、agent lifecycle、observability。
7. 【推断】human FDE 与 AI FDE 的共同点是贴近任务并形成反馈闭环；关键差异是 human FDE 是组织和工程方法，AI FDE 是受 Foundry 权限与工具约束的软件 agent。推理链：S17/S18 与 S01/S04 的定义主体不同。

---

## 6. 当前证据缺口

1. AI FDE 内部 agent orchestrator、planner、memory、tool selection policy、prompt/runtime 架构未在公开文档中披露，只能由 AIP 架构和 AI FDE 行为边界做【推断】。
2. AI FDE 各 mode 具体启用哪些 internal tools、工具参数 schema、失败重试策略、并发限制和 rate limits 未公开。
3. AI FDE 与 Global Branching、Code Repository PR、CI checks、AIP Evals 之间的具体 API 调用链和事务边界未公开。
4. AI FDE 的 session logs、chat outline、standard Foundry audit logs、LLM provider logs 之间的保留期、查询接口和关联键未公开。
5. AI FDE 对不同模型提供商的 tool API 适配层、模型选择策略、模型能力降级策略未公开。
6. AIP Assist “不访问你的数据”的边界与 custom content sources / AIP Chatbots 组合时的完整治理细节，需要 Agent B/C 在官方子页中继续核对。
7. Palantir MCP local 场景下第三方 LLM provider 的合同、保留、训练、区域和审计能力取决于客户配置，公开 Palantir 文档无法替代组织合规审查。
8. Ontology MCP 目前官方标注 beta，功能可用性和 API/工具形态可能变化；后续引用时需保留时间戳。
9. human FDE 的岗位职责、交付范围、客户现场工作方式在官方架构文档中只有方法论层面的表述，不能据此推断具体组织流程或权限。
10. DevCon3 视频/活动页能补充产品叙事，但不能替代产品文档作为精确能力边界；后续若引用演示细节需单独核对视频内容和发布日期。

---

## 7. 后续引用规则

1. 后续 raw 文档中的关键结论必须带【事实】、【推断】或【猜测】。
2. 使用【推断】时必须写出“事实 A + 事实 B -> 判断 C”的推理链。
3. 使用【猜测】时必须放在待验证或风险小节，不得作为方案前提。
4. 引用 AI FDE 能力时优先引用 S01-S05；引用底层 AIP 架构时引用 S06-S08；引用 MCP/外部 agent 边界时引用 S12-S15。
5. 当 Palantir 官方文档和社区反馈冲突时，以官方文档为事实来源，社区反馈只能作为线索或待验证缺口。
