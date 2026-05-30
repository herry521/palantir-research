# 35 - Palantir AI FDE 安全治理、审批与分支变更模型调研

**调研日期：** 2026-05-30
**关联 Issue：** #26
**负责 Agent：** Agent D
**调研范围：** AI FDE 身份与会话、权限与 markings、mutating tool approval、Global Branching、Code Repository PR/protected branches/CI/fallback branches、审计与 LLM usage attribution、自建 AI FDE 安全门槛。

---

## 1. 口径与可信度

本文件优先使用 Palantir 官方公开文档，并参考仓库内已有治理调研：

- `docs/raw/26-pro-code-governance-quality-observability.md`
- `docs/raw/30-dataset-permission-marking-architecture.md`

可信度标签沿用本轮 AI FDE 总计划：

| 标签 | 含义 |
|---|---|
| 【事实】 | Palantir 官方公开文档明确说明，或本仓库已有调研已由官方资料支撑。 |
| 【推断】 | 由多个事实组合得到的工程判断，公开资料没有用同一句话直接确认。 |
| 【猜测】 | 公开资料未披露，仅作为待验证实现假设或产品解释。 |

---

## 2. 核心结论

1. 【事实】AI FDE 不使用单独 bot/service account；它在当前用户的 Foundry authenticated session 下执行，权限错误与用户手工操作一致。
2. 【事实】AI FDE 的所有操作受现有 Foundry 权限、application/data access、branching controls 和 audit logging 约束；它不能越权创建 repository、编辑 ontology object type、执行 action、构建 dataset 或操作 Code Repository。
3. 【事实】AI FDE 额外实现 tool approval：写操作默认保守，敏感 mutating 操作需要用户确认；read-only 搜索和读取定义可自动批准；file edits 和 dataset builds 对 feature branch 与 protected/default branch 采用不同审批策略。
4. 【事实】AI FDE session 仅创建者可访问；session 会应用用户可访问的 markings，用户失去某个 session marking 后会失去该 session 访问，重新获得 marking 后恢复。
5. 【事实】Foundry 的 resource permission、Project roles、Organizations、Markings、application access、AIP enablement、model enablement、rate limits 和 audit logs 是 AI FDE 继承的平台机制，不是 AI FDE 独有发明。
6. 【事实】Global Branching 将跨应用修改放在同一 branch 中隔离，支持 end-to-end 测试后通过 proposal 合并；AI FDE 默认跨 workflow 使用 branching，并通过 Global Branch proposal 或 Code Repository pull request 提交 review。
7. 【事实】Global Branching 的 branch access 主要由 branch roles 和 organizations 控制；branch roles 只控制 branch 管理动作，不授予资源编辑权限，资源修改仍需要 project/resource level permissions。
8. 【事实】Global Branching protected resources 必须通过 branch 修改并按项目或资源 approval policy 审批后才能合并；Code Repositories 和 Pipeline Builder 仍保留各自 local branch protection 和 approval policy。
9. 【事实】Code Repository protected branch 只能通过 PR 修改，并可要求 `ci/foundry-publish` 成功、code review、specific reviewers、security approval、Functions stable tag restrictions。
10. 【事实】Code Repository fallback branches 只影响该 repository 内的 builds/actions；如果当前 branch 没有构建输入 dataset，会按 fallback branch 列表查找已构建版本，默认 branch 自动作为 fallback。
11. 【事实】AI FDE 活动既进入 AI FDE session logs，也进入标准 Foundry audit logs；LLM usage 归因到用户身份，AIP 也提供 enrollment/model rate limits 与 token/compute usage 归因机制。
12. 【推断】AI FDE 的安全模型是“双层门禁”：服务端强制执行 Foundry/branch/repository 权限，客户端或 agent 编排层再用 tool approval 限制 LLM 触发的 mutating actions。
13. 【推断】自建 AI FDE 的最小安全门槛不是“加一个确认弹窗”，而是身份透传、服务端权限重检、branch sandbox、mutating tool policy、审计归因、LLM 使用限额和敏感数据上下文隔离的组合。

---

## 3. 治理控制矩阵

| 控制点 | 来源归属 | 触发条件 | 用户体验 | 服务端约束 | 自建借鉴 |
|---|---|---|---|---|---|
| 用户身份透传 | AI FDE + Foundry | 用户启动 AI FDE session 并调用 Foundry operation | 用户以自己的 Foundry 身份工作，不看到 bot 身份切换 | 所有 API call 使用用户 authenticated session；无 service account、无 privilege escalation【事实】 | 代理必须使用用户 OAuth/session token 或 delegated token；禁止共享超级 token【推断】 |
| Resource roles / Project roles | Foundry | 读取、编辑、创建、移动、构建资源 | 与手工 Foundry 操作相同，缺权限返回相同错误 | Project 是主要安全边界；roles/operations 决定用户可执行的 workflow【事实】 | 工具网关在执行前后都重检资源级权限，LLM 规划结果不能直接落库【推断】 |
| Markings | Foundry | 访问带敏感 marking 的 Project/folder/file/resource/data | 不满足 marking 时资源不可见，或只能看到 metadata 但不能读取 data | 用户必须满足资源上所有普通 markings；role 不能绕过 mandatory controls；markings 沿层级和数据依赖传播【事实】 | 上下文检索、prompt 注入、工具输出都必须执行 mandatory label 检查；不要只保护最终 API【推断】 |
| Organizations | Foundry | branch、Project、resource 位于组织边界下 | 用户只能访问自己 organization 或 guest access 覆盖的工作区 | Organizations 作为 mandatory control 形成组织隔离；Global Branching branch access 也受 organizations gate 控制【事实】 | 多租户 AI agent 必须把 tenant/org 作为不可由 prompt 改写的硬约束【推断】 |
| Application access | Foundry Control Panel | 管理员限制某类用户进入 Foundry 应用或 AI/AIP 入口 | 用户看不到应用，或通过 URL 访问收到 403 | 官方说明 application access 主要简化前端体验，不应作为安全边界；真实安全依赖 resource permissions【事实】 | 可用作产品入口开关，但不能替代后端鉴权【推断】 |
| AIP enablement / model enablement | Foundry AIP | 使用 AI FDE、AIP Assist、custom AIP workflows 或具体模型族 | 管理员启用 AIP、custom workflow capabilities、模型族；用户只看到被允许的能力 | Enrollment/organization/user group 层面可限制 AIP；模型族需管理员接受条款并启用；部分模型可能 disallowed【事实】 | 模型白名单、组织级模型策略和法律/地域策略必须在模型网关强制执行【推断】 |
| Context allowlist | AI FDE | 用户添加 datasets、functions、branches、interfaces、action types、object types、docs、media 或开启 search tools | 用户手动添加上下文，或由模式决定可用上下文和工具；chat outline 展示 prompts/responses/tools/token usage | AI FDE 初始只加载最小 Foundry 概念上下文；只访问已加入 chat 或启用搜索后可找到的上下文【事实】 | 默认空上下文；每条 retrieval 结果都记录来源、权限检查和可见范围【推断】 |
| Mode / skill scoped tools | AI FDE | 用户选择 data integration、ontology editing、governance、exploration 等 mode | 只启用与任务相关的 tools/docs；可手动开关 tools | 工具调用仍受 Foundry 权限和 tool approval 约束【事实】 | 用 mode 缩小工具面，减少 prompt injection 后可触达的高危工具【推断】 |
| Read-only auto approval | AI FDE | 搜索、读取定义、平台问答、exploration 等非写操作 | 通常无需弹审批，降低交互摩擦 | 仍受 data/resource permissions、markings、session access 约束【事实】 | 只把幂等、无副作用、不可导出敏感数据的 read 操作列入 auto approve【推断】 |
| 每次审批 | AI FDE | 执行 ontology actions、创建 applications/widgets、publishing、creating tags 等敏感 mutating 操作 | 用户看到工具使用审批，可 reject 或 allow | AI FDE 不能在没有用户 consent 的情况下执行写操作；服务端权限仍独立执行【事实】 | 高危工具每次展示 diff、目标资源、branch、影响范围、执行身份和回滚方式【推断】 |
| Branch-aware approval | AI FDE + Branching | file edits、dataset builds、default/protected branch 修改、unbranched repo creation、有副作用 build | feature branch 可自动执行部分 file edits/builds；default/protected branch 或 unbranched change 需要批准 | allowlist 可按 branch/project 配置；protected/default branch 仍受 branch policy 和 server-side permission 控制【事实】 | 审批策略必须读取 branch classification；生产/main/protected 默认需要显式确认【推断】 |
| Session-level pre-approval | AI FDE | 用户允许某些 tools 在 session 期间执行 | 用户可对 session 内特定 tool、branch、project 给一次性授权 | 授权 scope 到 branch/project 等相关边界；不能越过 Foundry permission checks【事实】 | 预批准必须可撤销、有限时、有限 scope，并完整审计【推断】 |
| Global Branch workspace | Global Branching + AI FDE | 跨 Ontology、Pipeline Builder、Workshop、Code Repositories、actions 等 end-to-end 修改 | 用户在 branch 中测试，不直接影响 main；AI FDE 默认用 branching 并提出 proposal | Branch 隔离 main；修改范围受 branch ontology/space/org、resource permissions 和 merge checks 控制【事实】 | AI agent 写操作默认落到隔离 branch/sandbox，不直接写生产【推断】 |
| Branch roles | Global Branching | 创建 proposal、管理 branch metadata、管理 roles/orgs、close branch、do not merge | branch owner/space admin 可管理 branch；普通用户按角色看到可执行动作 | Branch roles 只管 branch 管理，不授予资源编辑；修改资源仍需 project/resource 权限【事实】 | 分离“管理变更请求”和“编辑业务资源”的权限【推断】 |
| Branch organizations | Global Branching | 访问 Global Branch | 用户必须属于 branch 上至少一个 organization | Branch organizations 必须是 space organizations 子集；branch name metadata 可能外泄，官方建议不要写敏感信息【事实】 | branch 名称、PR 标题、agent session 名称也要做敏感信息约束【推断】 |
| Resource protection / project approval policy | Global Branching | protected resource 在 branch 上变更后准备 merge | proposal 显示 required reviewers/approval policies；reviewer approve/reject | Protected resource 不可直接改 main；需 branch + approval policy；unprotected resource 仍可能需 editor approval【事实】 | 数据/ontology/应用配置等关键资源都要有受保护主线和审批策略【推断】 |
| Do not merge | Global Branching | branch owner 阻止 proposal 合并 | proposal 被显式阻断，直到 owner 移除 | 只有 branch owner 可设置/移除 Do not merge【事实】 | 提供人工冻结开关，用于事故、争议或合规暂停【推断】 |
| Rebase / conflict / merge checks | Global Branching | main 与 branch 存在差异或同一资源属性冲突 | taskbar / merge checks 提示需要 rebase 或手动解决冲突 | 对真正冲突不自动解决；必须人工选择版本后 rebase/merge【事实】 | LLM 可建议冲突解决，但合并前必须有确定性 diff 与人工确认【推断】 |
| Branch retention | Global Branching | branch 长期无活动 | 用户收到 inactive/closed 通知；closed 后当前公开文档称不能 reopen | Control Panel 可配置 inactive/closed 时间；closed/merged 后残留数据会被 retention job 删除【事实】 | sandbox 要有生命周期、成本治理和自动清理；保留合规窗口【推断】 |
| Code Repository sandbox branch | Code Repositories | 编辑 code repository | 用户必须在 sandbox branch 编辑；protected branches 不能直接编辑 | 受 repository branch settings 和 permissions 控制【事实】 | 代码 agent 永远在 topic branch 修改，再提交 PR【推断】 |
| Code Repository PR | Code Repositories + AI FDE | branch 改动准备进入 main/default/protected branch | 用户创建 PR，reviewer 逐行 review；AI FDE 可提出 PR | PR 合并受 protected branch policy、review、checks、permission 约束【事实】 | agent 输出必须转为 PR/diff，而非直接 push main【推断】 |
| Protected branch requirements | Code Repositories | 合并到 protected branch | PR 显示缺失 approvals/checks/security approval | 可要求 `ci/foundry-publish` 成功、code review、specific reviewers、security approval、stable tag restrictions【事实】 | 生产分支要求 CI、review、owner/security approval，不能被 agent 预批准绕过【推断】 |
| Security approval for markings changes | Code Repositories + Security | 停止传播 security markings 或 active security changes | PR 需要安全检查/审批；有 active security changes 的 branch 不能直接 unprotect | Security changes 自动且不可变地要求 security checks/approval；移除 inherited markings 只能通过 PR 清理【事实】 | 敏感标签降级/移除必须单独审批并纳入安全审计【推断】 |
| CI / checks | Code Repositories + AI FDE | commit、build、PR、publish | 用户在 status bar / Checks tab / PR 中查看 checks；AI FDE 可阅读 CI checks 验证代码 | Protected branch 可强制 `ci/foundry-publish` 通过；自动 checks 在 commit 后运行【事实】 | agent 必须把验证结果作为合并前 evidence，而非只报告“已修改”【推断】 |
| Fallback branches | Code Repositories | 当前 branch build 缺少 input dataset 构建版本 | 用户可在 branch 上 build 并查看 transform 对数据影响 | 按 repository fallback branch 列表找 built input；默认 branch 自动 fallback；只影响该 Code Repository 内 build/actions【事实】 | branch sandbox 要明确数据版本回退规则，避免 agent 在脏数据/缺数据上误判【推断】 |
| Audit logs | AI FDE + Foundry | AI FDE 触发 repository、ontology、dataset build、actions、权限修改、LLM inference 等 | 安全团队通过 Foundry audit logs、AI FDE session logs、SIEM/Foundry export 排查 | Audit logs 记录 who/what/when/where；audit.3 用标准 categories，如 dataLoad、dataExport、authorizationCheck、managementPermissions、managementMarkings、llmInference【事实】 | 每个 tool call 记录 user、session、prompt/tool id、resource ids、branch、approval decision、request/result hash【推断】 |
| LLM usage attribution / rate limits | AI FDE + AIP | AI FDE 调用模型、AIP token 使用、模型路由 | chat outline 显示 message token usage；管理员可看资源/用户/模型相关 usage | AI FDE 文档说明 LLM usage 归因到个人用户；AIP 有 enrollment/model TPM/RPM limits，usage 可归因到 resource 或 initiating user folder【事实】 | 模型网关必须按用户/项目/组织限额、计费归因、prompt size 预算和滥用保护限流【推断】 |

---

## 4. 控制归属：AI FDE 自身 vs 平台继承

### 4.1 AI FDE 自身控制

| 控制 | 说明 |
|---|---|
| 【事实】Tool approval system | AI FDE 对 mutating operations 增加用户确认，支持每次审批、session-level pre-approval、branch/project scoped approval。 |
| 【事实】Branch-aware approval defaults | AI FDE 根据 feature branch、default/protected branch、unbranched change、side-effecting build 等条件触发不同审批体验。 |
| 【事实】Read-only auto approval category | AI FDE 将搜索、读取定义等低风险 read-only operations 归入 auto-approved 类别。 |
| 【事实】Context and tool selection UI | AI FDE 让用户控制添加哪些资源、docs、media、search tools，以及启用哪些 tools。 |
| 【事实】Chat outline / session record | AI FDE session outline 记录 prompts、responses、tools used，并展示 token usage。 |
| 【事实】Session access boundary | AI FDE session 只允许创建者访问，并绑定用户 markings。 |

### 4.2 Foundry / Security 既有机制

| 控制 | 说明 |
|---|---|
| 【事实】Authenticated user session | AI FDE 复用用户 Foundry session；服务端以用户身份做权限检查。 |
| 【事实】Project/resource roles and operations | Projects 是主要安全边界，roles/operations 决定资源操作能力。 |
| 【事实】Markings and Organizations | Mandatory controls 限制敏感数据和组织边界；markings 可沿文件层级和数据依赖传播。 |
| 【事实】Application access | Control Panel 可限制用户/组看到哪些 Foundry 应用；官方明确它不是安全功能本身。 |
| 【事实】AIP enablement and model enablement | AIP、custom AIP workflows、model families 可按 enrollment、organization、user groups 管理。 |
| 【事实】Audit logs / audit categories | Foundry audit logs 记录平台动作，并支持 audit.3 categories 和 SIEM/Foundry export。 |

### 4.3 Global Branching 既有机制

| 控制 | 说明 |
|---|---|
| 【事实】Branch isolation | 在 branch 中修改跨应用资源，不影响 main；合并前可端到端测试。 |
| 【事实】Branch roles and organizations | branch 访问和管理由 roles + organizations 控制，但资源编辑仍靠 project/resource permissions。 |
| 【事实】Protected resources and approval policies | protected resources 必须通过 branch 变更并满足 approval policies 后 merge。 |
| 【事实】Proposal review / merge checks / Do not merge | proposal 合并受 approvals、checks、conflict/rebase 状态和 owner 人工阻断控制。 |
| 【事实】Branch retention | inactive/closed 生命周期由 Control Panel policy 管理，控制成本和长期残留数据。 |

### 4.4 Code Repositories 既有机制

| 控制 | 说明 |
|---|---|
| 【事实】Sandbox branches | 编辑代码必须在 sandbox branch；protected branch 不能直接编辑。 |
| 【事实】Pull requests | PR 用于 review branch diff 并合并到 main/default branch。 |
| 【事实】Protected branch policy | protected branches 可要求 CI、review、specific reviewers、security approval 和 stable tag restrictions。 |
| 【事实】Checks / CI | commit 后自动 checks；Checks tab 和 PR 暴露检查状态。 |
| 【事实】Fallback branches | branch builds/actions 在缺少当前 branch input build 时按 fallback branches 找输入数据。 |

关键边界：【推断】AI FDE 把 LLM agent 的行为纳入这些既有平台机制，而不是替代它们。真正的安全强制点仍在 Foundry、Global Branching、Code Repositories 和 AIP 服务端；AI FDE 的独有价值是把 agent tool use 的风险用上下文、模式和审批策略显式化。

---

## 5. Mutating tool approval 模型

### 5.1 审批分类

| 类型 | 官方示例 | 判断 |
|---|---|---|
| 【事实】Requires approval every time | Executing ontology actions、creating applications/widgets、publishing、creating tags | 这些动作可能立即影响生产工作流、发布物或对象状态，因此不应被 session 预批准无限放大【推断】 |
| 【事实】Branch-aware approval | File edits、dataset builds | feature branch 可自动化以保持开发效率；protected/default branch 或 side-effecting build 需要更强确认【推断】 |
| 【事实】Auto-approved | Searching、reading definitions | read-only 仍需权限过滤，但交互上不弹窗【事实】 |

### 5.2 审批触发条件

1. 【事实】Tool 正在修改 default branch。
2. 【事实】Tool 正在执行 unbranched change，例如创建 Code Repository。
3. 【事实】Tool 可能有 side effects，例如 dataset builds。
4. 【事实】Tool 属于每次都需要批准的敏感 mutating category。
5. 【推断】Tool 目标资源存在 protected branch / protected resource / security approval requirement 时，AI FDE 即使已经获得 tool approval，也仍必须等待平台 approval policy 或 PR policy。

### 5.3 审批不是权限

【事实】AI FDE 文档明确 tool approval 是在 server-side permission enforcement 之外的额外控制。
【推断】因此 `user approves tool` 只能表示“用户同意 agent 代表自己尝试执行”，不能表示“用户获得了执行该操作的权限”。真正是否执行成功必须由 Foundry 权限、markings、branch policy、repository policy 再判定。

---

## 6. Branching 与变更落地模型

### 6.1 Global Branching

【事实】Global Branching 用于在 Palantir 平台内开发和测试端到端工作流，避免直接冲击 live production environment。它提供跨多个 applications 的统一 branch，用于修改、测试并通过 proposal merge 回 main。

典型 AI FDE 流程可抽象为：

```text
request
 -> select mode/tools/context
 -> plan tool calls
 -> create/use branch
 -> edit resources / run builds / run previews
 -> observe checks/results
 -> create Global Branch proposal
 -> reviewers approve and checks pass
 -> merge to main
```

【事实】AI FDE overview 明确默认跨 workflows 使用 branching，并会用 Global Branch proposal 或 Code Repository PR 提交 review。

### 6.2 Code Repository PR

【事实】Code Repositories 提供 web IDE、sandbox branches、pull requests、checks 和 protected branch policies。编辑代码必须在 sandbox branch；protected branch 只能通过 PR 修改。

典型 AI FDE code path：

```text
request
 -> add repository/branch/dataset context
 -> create or select sandbox branch
 -> edit files
 -> run preview/tests/checks/builds
 -> create PR
 -> protected branch policy gates merge
```

### 6.3 Fallback branches 的治理含义

【事实】Code Repository fallback branches 让 branch build 在当前 branch 找不到 input dataset build 时回退到指定 branch 的已构建版本；默认 branch 自动作为 fallback。
【推断】这对 AI FDE 的验证结论很重要：如果 transform preview/build 成功，必须记录输入来自当前 branch 还是 fallback branch；否则 agent 可能把“用 main 输入验证通过”误解为“当前 branch 全量端到端验证通过”。

---

## 7. Session access、审计与 LLM 使用归因

### 7.1 Session access

1. 【事实】AI FDE session 只允许创建者访问，不能分享给其他用户。
2. 【事实】创建 session 时会应用用户有权访问的 markings。
3. 【事实】如果用户失去 session 上某个 marking 的访问权，将失去该 session access；重新获得 marking 后恢复。
4. 【推断】AI FDE session 本身可视为含敏感上下文的资源，必须按 prompt、tool output、resource links 和 markings 共同保护。

### 7.2 Audit logging

1. 【事实】AI FDE 活动受标准 Foundry audit logs 约束，并且 AI FDE session logs 也生效。
2. 【事实】Foundry audit logs 用于回答 who/what/when/where；audit.3 categories 可覆盖 dataLoad、dataExport、authorizationCheck、codeExecution、dataTransform、logicUpdate、managementPermissions、managementMarkings、llmInference 等事件类别。
3. 【事实】Audit logs 可供外部 SIEM 通过 audit API 消费，也可 export 到 Foundry dataset；audit logs 本身含敏感信息，应限制访问。
4. 【推断】AI FDE 自建实现应把“用户批准了什么”和“服务端实际执行了什么”分开记录，因为 approval intent 与 execution result 不总是一致。

### 7.3 LLM usage attribution and rate limits

1. 【事实】AI FDE 文档说明 LLM usage attributed to individual user identity，并且 usage tracking/rate limiting apply per user。
2. 【事实】AIP capacity management 以 model 维度管理 enrollment-level TPM/RPM rate limits，并展示 enrollment limits；模型 capacity 受 provider market-level constraints 影响。
3. 【事实】AIP compute usage 文档说明 LLM token usage 通常归因到请求该 usage 的 application resource；无法归因到单一 resource 的场景会归因到 initiating user folder。
4. 【推断】AI FDE 的“用户归因”与 AIP 的“resource/user folder 归因”共同构成成本治理：需要能按 user、resource、model、tool/session 追踪消耗。

---

## 8. 自建 AI FDE 的最小安全门槛

以下是可上线内测的最低门槛，不是理想终态。

| 门槛 | 必须能力 | 验收标准 |
|---|---|---|
| 1. 身份透传 | 使用用户已有 session/delegated token，不使用万能 service account | 每个 tool call 的 subject 都是发起用户；后端可拒绝越权请求【推断】 |
| 2. 服务端权限重检 | 工具执行端重新检查 resource role、tenant/org、sensitivity label、action permission | 修改 prompt 或前端状态不能绕过权限【推断】 |
| 3. 敏感标签传播 | 上下文检索、数据预览、生成 artifact、tool output 都继承或携带 sensitivity labels | 用户无标签资格时，agent 不能读取、总结或泄露内容【推断】 |
| 4. 默认 branch sandbox | 所有写操作默认进入 feature branch/sandbox；main/prod/protected 禁止直接写 | 没有 branch 的 mutating operation 默认 require approval 或 deny【推断】 |
| 5. Mutating tool approval | 对 tool 建立 read-only、branch-aware、always-approve-per-action 三类策略 | 审批 UI 展示 tool、资源、branch、diff/side effects、执行身份【推断】 |
| 6. PR/proposal gate | 代码、ontology、数据管道、应用配置等变更通过 PR/proposal 合并 | 合并前必须满足 review、CI/checks、安全审批和冲突检查【推断】 |
| 7. Verification evidence | agent 运行 preview/test/build/check 并保存结果 | 最终回答和 PR 描述引用具体 check/build/test id 或失败原因【推断】 |
| 8. Audit ledger | prompt、context、tool plan、approval decision、tool execution、result、diff、usage 全链路审计 | 安全团队可按 user/session/resource/branch/tool/model 查询【推断】 |
| 9. LLM gateway governance | 模型白名单、TPM/RPM/user quota、cost attribution、prompt size budget | 用户/组织超限时 fail closed；模型选择受管理员策略限制【推断】 |
| 10. Session security | session 只给创建者访问，绑定当前 sensitivity labels，支持失权即断 | 权限变化后旧 session 不能继续读取已失权内容【推断】 |
| 11. Human override | do-not-merge/freeze、revoke pre-approval、kill running tool、rollback branch | 事故时无需改代码即可阻断 agent 继续写入【推断】 |
| 12. Evidence gap handling | 对未验证机制显式标注，不允许 agent 把猜测写成事实 | 输出文档和 PR 自动区分 fact/inference/guess【推断】 |

最低发布策略：

1. 【推断】P0 只开放 read-only exploration，禁止 mutating tools；验证身份、权限、marking/context isolation、audit。
2. 【推断】P1 开放 branch-local file edits 和 non-production builds，要求每次或 branch-scoped approval。
3. 【推断】P2 接入 PR/proposal、CI checks、preview/build evidence，禁止直接合并 production。
4. 【推断】P3 开放 ontology actions、publishing、tagging、marking/security changes，但必须每次审批并接入安全 reviewer。

---

## 9. 证据缺口

1. 【猜测】公开文档没有披露 AI FDE tool approval 的内部 policy schema、默认 allowlist 具体字段、审批记录持久化格式、撤销语义和超时策略。
2. 【猜测】公开文档没有披露 AI FDE session logs 的完整 schema，以及它与 Foundry audit logs 的 traceId/sessionId 关联方式。
3. 【猜测】公开文档没有披露 AI FDE 对 prompt/tool output 中 markings 的内部存储模型，只能确认 session access 受 markings 保护。
4. 【猜测】公开文档没有披露 AI FDE 如何在不同 Foundry applications 间选择 Global Branch proposal vs Code Repository PR，以及失败时是否自动创建 fallback branch。
5. 【猜测】公开文档没有披露 branch-aware approval 对“feature branch auto-approve”的完整边界，例如哪些 dataset builds 被视为 side-effecting、是否按 project allowlist 覆盖。
6. 【猜测】公开文档没有披露 LLM usage 在 AI FDE session、AIP resource attribution、user folder attribution 之间的精确账务映射。
7. 【事实】AI FDE feature availability may change and may differ between customers；因此公开文档结论需要在目标 Foundry enrollment 中复核。

---

## 10. 参考来源

### 官方 Palantir 文档

- AI FDE Overview: https://www.palantir.com/docs/foundry/ai-fde/overview
- AI FDE Navigation: https://www.palantir.com/docs/foundry/ai-fde/navigation
- AI FDE Modes and skills: https://www.palantir.com/docs/foundry/ai-fde/modes-and-skills
- AI FDE Security and governance: https://www.palantir.com/docs/foundry/ai-fde/security-and-governance
- AIP Architecture overview: https://www.palantir.com/docs/foundry/architecture-center/aip-architecture
- Enable AIP features: https://www.palantir.com/docs/foundry/aip/enable-aip-features
- AIP compute usage: https://www.palantir.com/docs/foundry/aip/aip-compute-usage
- LLM capacity management: https://www.palantir.com/docs/foundry/aip/llm-capacity-management
- Security overview: https://www.palantir.com/docs/foundry/security/overview
- Projects and roles: https://www.palantir.com/docs/foundry/security/projects-and-roles
- Markings: https://www.palantir.com/docs/foundry/security/markings
- Configure application access: https://www.palantir.com/docs/foundry/administration/configure-application-access
- Requesting justification for sensitive actions: https://www.palantir.com/docs/foundry/security/requesting-justification-for-sensitive-actions
- Audit logs: https://www.palantir.com/docs/foundry/security/audit-logs-overview
- Audit log categories: https://www.palantir.com/docs/foundry/security/audit-log-categories
- Monitor audit logs: https://www.palantir.com/docs/foundry/security/monitor-audit-logs
- Global Branching Overview: https://www.palantir.com/docs/foundry/global-branching/overview
- Global Branching Branch security: https://www.palantir.com/docs/foundry/global-branching/branch-security
- Global Branching Resource protection and approval policies: https://www.palantir.com/docs/foundry/global-branching/resource-protection-and-approval-policies
- Global Branching Branch retention: https://www.palantir.com/docs/foundry/global-branching/branch-retention
- Global Branching Branching functions: https://www.palantir.com/docs/foundry/global-branching/branching-functions
- Code Repositories Overview: https://www.palantir.com/docs/foundry/code-repositories/overview/index.html
- Code Repositories Navigation: https://www.palantir.com/docs/foundry/code-repositories/navigation
- Code Repositories Branch settings: https://www.palantir.com/docs/foundry/code-repositories/branch-settings

### 仓库内参考

- `docs/superpowers/plans/2026-05-30-palantir-ai-fde-research-plan.md`
- `docs/raw/26-pro-code-governance-quality-observability.md`
- `docs/raw/30-dataset-permission-marking-architecture.md`
