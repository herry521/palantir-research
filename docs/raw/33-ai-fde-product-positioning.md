# Palantir AI FDE 功能定位与产品边界

**Issue:** #21
**Agent:** B
**采集日期:** 2026-05-30
**输出:** `docs/raw/33-ai-fde-product-positioning.md`

## 1. 结论摘要

- 【事实】Palantir 将 AI FDE 定义为 "AI-powered forward deployed engineer"，即通过对话命令操作 Foundry 的交互式 agent；它把自然语言请求转成 Foundry 操作，覆盖数据转换、代码仓库管理、Ontology 构建与维护、Functions 编辑等任务。[AI FDE overview](https://www.palantir.com/docs/foundry/ai-fde/overview)
- 【事实】AI FDE 依赖 AIP 在 enrollment 上启用；Palantir 还建议启用 Global Branching 来支持 AI FDE 的 Ontology 编辑。[AI FDE overview](https://www.palantir.com/docs/foundry/ai-fde/overview)
- 【事实】AI FDE 的公开 modes 覆盖 Data integration、Data connection、Ontology editing、Functions editing、Exploration、Governance、Machine learning、OSDK React、Platform Q&A。[Modes and skills](https://www.palantir.com/docs/foundry/ai-fde/modes-and-skills)
- 【事实】AI FDE 默认跨工作流使用 branching，并通过 Global Branch proposal 或 Code Repository pull request 提交变更供审查。[AI FDE overview](https://www.palantir.com/docs/foundry/ai-fde/overview)
- 【推断】AI FDE 的产品边界不是 "通用聊天助手"，而是 "带 Foundry 原生工具、权限、分支、预览/CI 校验的工程执行入口"。推理链：AI FDE 文档强调 native tool support、tool approval、branch proposals/PRs、transform/function preview 和 CI checks；这些都是工程执行闭环，不是单纯问答能力。
- 【推断】AI FDE 与人类 FDE 的关系更接近 "把部分可工具化的 FDE 工作流产品化"，而不是替代人类 FDE。推理链：Palantir 将人类 Forward Deployed Engineering 描述为贴近客户问题、综合反馈并推动产品交付的方法论；AI FDE 只能在用户权限和工具边界内执行平台操作，公开资料没有显示它能承担需求澄清、组织协调、架构取舍或跨团队交付责任。[Architecture center overview](https://www.palantir.com/docs/foundry/architecture-center/overview)

## 2. 官方资料基线

| 资料 | 覆盖内容 | 本文用途 |
|---|---|---|
| [AI FDE overview](https://www.palantir.com/docs/foundry/ai-fde/overview) | 定义、要求、闭环工作方式、能力范围、分支/PR、模型支持 | 产品定义、用户价值、默认边界 |
| [AI FDE modes and skills](https://www.palantir.com/docs/foundry/ai-fde/modes-and-skills) | modes、skills、mode 配置、agent skills/domain skills | 任务域矩阵 |
| [AI FDE navigation](https://www.palantir.com/docs/foundry/ai-fde/navigation) | session、context、tools、approval、chat outline | 上下文和控制面设计 |
| [AI FDE security and governance](https://www.palantir.com/docs/foundry/ai-fde/security-and-governance) | 用户身份、权限、approval、session 访问、audit、LLM attribution | 风险边界 |
| [AIP features](https://www.palantir.com/docs/foundry/aip/aip-features) | AIP 应用参考、AIP Assist、Chatbot Studio、MCP、Pipeline Builder AIP 能力 | 产品边界比较 |
| [AIP architecture](https://www.palantir.com/docs/foundry/architecture-center/aip-architecture) | LLM 接入、context engineering、Ontology、tool services、security/governance、agent lifecycle、evals | Foundry/AIP 依赖 |
| [AIP Assist overview](https://www.palantir.com/docs/foundry/assist/overview) | 平台支持助手、文档/开发者/custom content modes | 与 AI FDE 的边界 |
| [AIP Chatbot Studio overview](https://www.palantir.com/docs/foundry/chatbot-studio/overview) | 构建可部署 chatbot、Ontology/documents/custom tools、应用集成 | 与业务 agent 构建器的边界 |
| [AIP Analyst overview](https://www.palantir.com/docs/foundry/aip-analyst/overview) | 基于 Ontology 的 ad-hoc analysis、object sets、SQL、visualization、action approval | 与分析型 agent 的边界 |
| [Palantir MCP overview](https://www.palantir.com/docs/foundry/palantir-mcp/overview) | 外部 AI IDE/agent 接入 Foundry context/tools、Ontology/OSDK/transforms | 与外部 agent bridge 的边界 |
| [Pipeline Builder overview](https://www.palantir.com/docs/foundry/pipeline-builder/overview) | 数据集成主应用、可视化 pipeline、preview/build/output、版本控制 | 与底层数据集成工具的边界 |
| [Code Repositories overview](https://www.palantir.com/docs/foundry/code-repositories/overview/index.html) | Web IDE、Git、PR、lint/check、transforms/functions/model repositories | 与底层 pro-code 工具的边界 |
| [Global Branching overview](https://www.palantir.com/docs/foundry/global-branching/overview) | 跨应用统一分支、端到端测试、合并 | 安全变更通道 |

## 3. 产品定义与用户价值

【事实】AI FDE 是 Foundry 内的交互式 agent，用户通过自然语言发起请求，AI FDE 会分析意图和上下文、选择 Foundry 操作、用原生工具执行，并返回上下文解释和文档。[AI FDE overview](https://www.palantir.com/docs/foundry/ai-fde/overview)

【事实】AI FDE 可由用户选择模型、工具和数据访问范围；初始状态只加载最小 context，用户可以通过 Foundry 资源、文档 bundle、上传媒体、拖拽链接和 search tools 扩展 context。[AI FDE overview](https://www.palantir.com/docs/foundry/ai-fde/overview), [Navigation](https://www.palantir.com/docs/foundry/ai-fde/navigation)

【事实】AI FDE 采用 closed-loop operation：执行动作、观察结果、用反馈决定下一步；公开示例包括 transform preview、function preview、review Code Repositories CI checks。[AI FDE overview](https://www.palantir.com/docs/foundry/ai-fde/overview)

【推断】AI FDE 的核心用户价值是把 "知道 Foundry 怎么做"、"知道在哪里做"、"知道如何验证" 三类隐性工程知识压缩进一个对话式执行面。推理链：AI FDE modes 加载相关文档和工具，navigation 允许手动或自动选择 context/tools，overview 明确它会执行和验证 Foundry 原生操作。

【推断】AI FDE 最适合用于已有 Foundry/AIP 治理体系内的增量工程任务，而不是用于无平台资产、无权限模型、无可验证工具的开放式代理自动化。推理链：AI FDE 的所有能力都依赖 Foundry native tools、permissions、branching、audit、preview/CI；这些依赖同时也是它可信边界的来源。

## 4. 定位矩阵

| Persona | Job-to-be-done | AI FDE 能力 | 依赖的 Foundry/AIP 能力 | 风险边界 |
|---|---|---|---|---|
| 【事实】数据工程师 / Analytics Engineer | 【事实】构建或修改数据 pipeline，选择 Python transforms 或 Pipeline Builder。 | 【事实】Data integration mode 可构建/修改 Python transforms 或 Pipeline Builder pipeline；closed-loop 可运行 transform preview。 | 【事实】Pipeline Builder、Code Repositories transforms、dataset build、preview、AIP 模型/tool APIs。 | 【事实】写入、build、默认分支或副作用操作需要 approval；【推断】生产 pipeline 仍需 code review、branch proposal/PR 和数据质量检查。 |
| 【事实】数据连接 / 平台集成工程师 | 【事实】创建、管理、调试 Data Connection sources、egress policies 等。 | 【事实】Data connection mode 覆盖 data connection source、egress policy 和相关能力。 | 【事实】Foundry Data Connection、connector、egress、permission/audit。 | 【推断】连接凭证、外部系统副作用和数据外发策略是高风险边界；AI FDE 不能绕过用户权限或管理员策略。 |
| 【事实】Ontology builder / 业务建模工程师 | 【事实】创建或更新 object types、links、actions。 | 【事实】Ontology editing mode 覆盖 objects、links、actions；overview 建议为 Ontology edits 启用 Global Branching。 | 【事实】Ontology、Global Branching、branch proposal、permissions、audit logs。 | 【事实】AI FDE 在用户身份下运行且不能超权；【推断】Ontology schema/action 变更影响下游应用，必须经 proposal review 与 merge checks。 |
| 【事实】Functions / 业务逻辑开发者 | 【事实】编写 Logic、TypeScript 或 Python Functions，并验证行为。 | 【事实】Functions editing mode 覆盖 Logic、TypeScript、Python；overview 提到 function preview 和 AIP Evals。 | 【事实】AIP Logic、Code Repositories Functions、Ontology access、function preview、AIP Evals。 | 【推断】低延迟业务逻辑可能影响 operational workflows；AI FDE 应只提出可验证版本，不应直接替代发布审批。 |
| 【事实】探索型用户 / 新加入项目成员 | 【事实】先理解平台里已有资源，再决定是否修改。 | 【事实】Exploration mode 是 read-only investigation，用于理解平台现状。 | 【事实】Search tools、resource lookup、chat outline、user-scoped context。 | 【事实】只读操作低风险并可自动批准；【推断】探索结论仍可能受用户加入 context 不完整影响。 |
| 【事实】Governance / Data Steward / 安全管理员 | 【事实】审计权限、访问控制、markings、data protection。 | 【事实】Governance mode 覆盖 permissions、access control、markings、data protection auditing。 | 【事实】Foundry permissions、markings、audit logs、security governance、session access controls。 | 【事实】AI FDE 不能超过当前用户权限；【推断】治理诊断可辅助发现问题，但策略解释和整改责任仍在人类 owner。 |
| 【事实】ML Engineer / Data Scientist | 【事实】训练、评估、部署、调优模型，覆盖分类、回归、时序预测和自定义预测建模。 | 【事实】Machine learning mode 覆盖 training/evaluation/deployment/tuning，可配置 Model Studio no-code 或 pro-code development 及代码编辑环境。 | 【事实】Model Studio、Code Repositories model development、AIP model access、compute、eval/observability。 | 【推断】模型质量、训练数据偏差、上线影响和算力成本不能由 AI FDE 自身保证；需要实验追踪、评估和发布门禁。 |
| 【事实】OSDK / 前端应用开发者 | 【事实】构建连接 Foundry 数据的 React 应用或 custom widgets。 | 【事实】OSDK React mode 覆盖 React applications 和 custom widgets。 | 【事实】Ontology SDK、Developer Console、Code Repositories、application permissions、AIP/Foundry APIs。 | 【推断】前端生成代码仍需安全审查、权限限制、用户体验验证和部署流程；AI FDE 不应承诺自动完成端到端产品设计。 |
| 【事实】平台使用者 / Builder | 【事实】询问 Foundry 如何工作，获得平台知识。 | 【事实】Platform Q&A mode 覆盖关于 Foundry 工作方式的一般问题。 | 【事实】Foundry documentation bundles、AIP 模型、AIP Assist 相邻能力。 | 【推断】Platform Q&A 与 AIP Assist 重叠；需要把 "解释/引导" 与 "执行工具操作" 清晰分开。 |
| 【推断】人类 FDE / 交付负责人 | 【推断】把客户现场需求转成可交付的平台资产，并把反馈带回产品工程。 | 【推断】AI FDE 可承担部分可工具化、可审查、可验证的 Foundry 操作，但不能承担客户关系、需求优先级、架构 trade-off 和组织协同。 | 【事实】Palantir FDE 方法论、人类工程团队、Foundry/AIP/Apollo 共同平台。 | 【推断】AI FDE 是人类 FDE 的执行放大器，不是责任主体；最终方案边界、验收标准和风险接受仍由人类决定。 |

## 5. Modes 覆盖的任务域与边界

| Mode | 【事实】公开任务域 | 【推断】产品定位 | 【推断】边界 |
|---|---|---|---|
| Data integration | Python transforms 或 Pipeline Builder pipeline 的构建/修改。 | 将自然语言需求转成可预览、可 build、可 review 的数据转换资产。 | 不替代数据建模目标、SLA、质量规则和生产发布责任。 |
| Data connection | 创建、管理、调试 Data Connection sources、egress policies 等。 | 降低连接配置和故障定位门槛。 | 不能绕过 credential、network、egress 和管理员授权。 |
| Ontology editing | 创建/更新 objects、links、actions。 | 把语义建模操作纳入 branch proposal 的 agent 协作流。 | 不应直接在生产语义层做不可审查变更。 |
| Functions editing | 写 Logic、TypeScript、Python functions。 | 让业务逻辑从自然语言需求进入可预览/评估的 function artifact。 | 不保证业务规则正确，需要 tests/evals 和 owner review。 |
| Exploration | 只读调查，理解平台现状。 | 作为低风险 discovery mode，为后续 mutating modes 准备 context。 | 结论依赖用户权限和添加的 context，不能当作全局资产目录。 |
| Governance | 审计权限、访问控制、markings、data protection。 | 把治理排查变成对话式和证据驱动的 workflow。 | 治理建议不能替代 policy owner 的批准和合规解释。 |
| Machine learning | 训练、评估、部署、调优 ML 模型；覆盖分类、回归、时序预测和自定义预测建模。 | 连接 Model Studio/no-code 与 pro-code model development。 | 不保证模型适用性、公平性、成本或上线风险。 |
| OSDK React | 构建 React app 或 custom widgets 连接 Foundry 数据。 | 将 Ontology SDK 应用搭建纳入 agentic 工程流。 | 不替代产品体验设计、安全限制和应用发布审批。 |
| Platform Q&A | 询问 Foundry 工作方式。 | 作为平台知识入口，也为 task routing 提供自然语言前门。 | 与 AIP Assist 明显重叠；应避免把问答误包装成自动执行能力。 |

## 6. 与相邻产品/角色的关系和边界

| 对象 | 【事实】官方定位 | 【推断】与 AI FDE 的关系 | 【推断】边界判断 |
|---|---|---|---|
| AIP Assist | LLM-powered support tool，帮助用户理解和使用 Palantir 平台；可基于平台文档、开发者文档和 custom content source 回答问题；文档说明 AIP Assist 不访问用户数据。 | AI FDE 可覆盖问答，但更强调执行 Foundry 原生操作、工具调用、branch/PR 和 validation。 | AIP Assist 是 "帮助/解释/导航"；AI FDE 是 "工程执行 + 验证 + 审查通道"。自建平台不应把普通知识问答宣传成 AI FDE。 |
| AIP Chatbot Studio / AIP Agent Studio | AIP Chatbot Studio 原名 AIP Agent Studio；用于构建可部署的 AIP Chatbots，配备 enterprise-specific information 和 tools，可集成到应用中支持 read/write workflows。 | Chatbot Studio 是业务 agent 构建器；AI FDE 是 Palantir 平台工程 agent。两者都用 Ontology、LLMs 和 tools，但目标用户和默认任务不同。 | Chatbot Studio 面向 "给业务应用造 agent"；AI FDE 面向 "让 agent 帮用户改平台资产"。 |
| AIP Analyst | 用自然语言在 Ontology 上做 ad-hoc analysis，可搜索 ontology、创建 object sets、转换数据、生成总结和可视化；可执行 functions 和 action types，其中 actions 需要 approval。 | 与 AI FDE 的 Exploration/Governance 有交集，但 AIP Analyst 主要产出分析回答、图表和 session；AI FDE 主要产出工程变更 proposal/PR 或平台操作结果。 | AIP Analyst 是 "分析问题"；AI FDE 是 "改造平台资产/工作流"。 |
| Palantir MCP | Model Context Protocol 实现，使外部 AI IDE/agents 获取 Foundry context/tools，可设计、构建、编辑、审查端到端应用；Palantir MCP 面向 ontology builders，可修改 ontology types，但不能写 ontology data；Ontology MCP 面向 consumers 可安全读写数据。 | Palantir MCP 是外部 agent 接入 Foundry 的协议/工具桥；AI FDE 是 Foundry 内置的 agent 应用。 | MCP 不等于 AI FDE：MCP 提供 context/tools 给外部 agent，AI FDE 提供内置 UX、session、approval、branching 和审计集成。 |
| Pipeline Builder | Foundry 的主要数据集成应用；通过图形/表单界面构建 pipeline，提供 preview、build、outputs、严格输出检查、版本控制和 AIP/LLM 能力。 | AI FDE 可在 Data integration mode 中使用或修改 Pipeline Builder pipeline。 | Pipeline Builder 是底层确定性工作台；AI FDE 是其上方的自然语言协调/执行层。不能把 AI FDE 看成替代 Pipeline Builder 的运行时。 |
| Code Repositories | Foundry Web IDE，用于生产级代码编写与协作，提供 Git、branching、commits、tags、PR、权限、IntelliSense、lint/error checking；支持 transforms、functions、model development。 | AI FDE 可管理 code repositories、写 code、review CI checks，并通过 PR 提交审查。 | Code Repositories 是源代码和工程治理系统；AI FDE 是代码变更生成与迭代者，仍依赖 PR 和 CI。 |
| 人类 FDE | Palantir 将 Forward Deployed Engineering 描述为贴近客户问题、与核心工程协作、综合反馈并交付新功能的方法论。 | AI FDE 借用了 "FDE" 名称和部分任务形态，但公开能力集中在可工具化平台操作。 | 人类 FDE 负责问题定义、组织协同、风险接受和业务交付；AI FDE 只应承担可追踪、可审查、可回滚的执行子任务。 |

## 7. 适用与不适用场景

### 适用场景

- 【推断】已有 Foundry/AIP 资产、用户权限清晰、目标可由 Foundry 工具执行，并可通过 preview、CI、eval、branch proposal 或 PR 验证的工程任务。
- 【推断】探索现有资源、生成初始方案、修复 transform/function 编译或预览错误、创建可审查的 ontology/pipeline/code 变更。
- 【推断】需要把用户的自然语言意图快速转成平台资产草案，但仍保留人类审批、审查和发布门禁的场景。

### 不适用场景

- 【事实】AI FDE 不能超过当前用户权限，没有单独 service account 或提升权限。[Security and governance](https://www.palantir.com/docs/foundry/ai-fde/security-and-governance)
- 【推断】没有明确工具 API、没有审计、没有分支/回滚、没有验证反馈的系统，不适合承诺 AI FDE 级别的 agentic execution。
- 【推断】跨组织需求定义、业务目标冲突、合规解释、生产事故责任归属等问题，不应交给 AI FDE 自动决策。
- 【猜测】公开资料未说明 AI FDE 是否支持客户自定义新 mode 或深度定制系统 prompt；在没有私有文档验证前，自建规划不应假设这一点。

## 8. 可借鉴的产品设计原则

1. 【推断】先做 mode router，再做全能 agent。AI FDE 用 modes 限定任务域、加载相关文档和工具、收窄上下文；自建平台应优先按 Data integration、Governance、Exploration 等任务面拆分，而不是让一个 agent 直接拿全量工具。
2. 【推断】context 必须显式、可见、可裁剪。AI FDE 默认最小 context，用户主动添加资源，chat outline 显示 prompts/responses/tools 和 token 使用；自建平台应把 "模型看到了什么" 做成可审计对象。
3. 【推断】高风险动作必须走 branch/approval/review。AI FDE 对敏感工具有 approval，默认使用 branch，并通过 proposal/PR 提交；自建平台应把 agent 输出落在 reviewable artifact 上，而不是直接写生产。
4. 【推断】agent 必须有闭环验证工具。AI FDE 可运行 transform preview、function preview、查看 CI checks；自建平台应先建设预览、dry-run、CI/eval、回归检查，再扩大可写工具。
5. 【推断】把产品边界讲清楚比承诺 "自动化一切" 更重要。AI FDE 文档明确权限、session access、audit、LLM attribution、feature availability；自建平台也应公开说明不能超权、不能替代 owner 审批、不能保证业务正确性。

## 9. 不应过度承诺的能力

- 【事实】Palantir 文档说明 AIP feature availability 可能变化且不同客户可用性不同。[AI FDE overview](https://www.palantir.com/docs/foundry/ai-fde/overview), [AIP features](https://www.palantir.com/docs/foundry/aip/aip-features)
- 【推断】不能承诺 "自然语言直达生产"，因为 AI FDE 的可信路径依赖 approval、branching、proposal/PR、preview/CI 和 audit。
- 【推断】不能承诺 "替代数据工程师/平台工程师/FDE"，因为 AI FDE 文档只证明其能执行部分平台操作，没有证明其能承担系统设计、业务取舍、运营责任。
- 【推断】不能承诺 "任意系统都可复刻"，因为 AI FDE 的能力来自 Foundry/AIP 的 Ontology、permission、tool services、Code Repositories、Pipeline Builder、Global Branching、audit 和 eval/observability 组合。
- 【猜测】公开资料未验证 AI FDE 内部 planner、prompt、tool schema、状态存储和 mode-selection 细节；自建平台可以借鉴公开产品原则，但不应假设 Palantir 的内部实现。

## 10. 证据缺口

- 【事实】公开文档说明 AI FDE modes 和 skills，但未公开完整 tool schema、tool permission policy 配置模型、planner 实现或 prompt 结构。
- 【事实】公开文档说明 tool approval、branch-aware approval 和 session-level pre-approval，但没有提供所有 mutating tool 的完整风险分级清单。
- 【事实】公开文档说明 AI FDE 可查看 CI checks、运行 transform/function preview，但没有说明 validation failure 的自动修复策略上限。
- 【事实】公开文档说明 Palantir MCP 可让外部 AI IDE/agents 设计、构建、编辑和审查应用，但没有公开 AI FDE 是否复用 MCP 协议或内部 tool gateway。
- 【推断】AI FDE 与 AIP Analyst、AIP Chatbot Studio 在底层可能共享 AIP 模型接入、工具、Ontology 和 observability 基础设施；公开资料只证明它们都建立在 AIP/Foundry 能力上，不能证明共享同一 agent runtime。

## 11. 面向自建平台的最小定位建议

【推断】如果要自建 "类 AI FDE"，第一阶段应定位为 "受控工程副驾驶"，而不是 "自治平台工程师"：

- 【推断】P0：只读 Exploration + Platform Q&A，接入资源搜索、文档检索、权限内元数据读取，完整记录 context 和 tool calls。
- 【推断】P1：Data integration / Functions 的 branch-local 代码修改，所有输出进入 PR 或 proposal，必须有 preview/CI。
- 【推断】P2：Ontology/Governance 只做诊断和草案，不直接合并；所有 schema/action/permission 变更由 owner 审批。
- 【推断】P3：再扩展到 ML、OSDK React、Data connection 等高风险 mode，并按 mode 配置工具、审批、审计和回滚策略。

【推断】最低可用边界：当前用户身份执行、最小 context、mode-scoped tools、mutating approval、branch/PR/proposal、preview/CI/eval、audit/usage attribution。缺少任一项，都不应宣称达到 AI FDE 的产品级边界。
