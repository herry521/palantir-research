# AI FDE

## 摘要与洞察

1. 【事实】AI FDE 是 Foundry 内的交互式工程 agent，通过自然语言驱动 Foundry 原生操作，覆盖数据转换、Code Repositories、Ontology、Functions、Governance、ML、OSDK React 和 Platform Q&A。
2. 【事实】AI FDE 不使用独立 bot/service account；它在当前用户 Foundry session 下执行，继承用户权限、markings、session access、audit logging 和 LLM usage attribution。
3. 【推断】AI FDE 的可信边界来自 mode/skill、显式 context、tool selection、tool approval、branch/proposal/PR、preview/CI/evals、audit logs 的组合，不是来自 LLM 自身可靠性。
4. 【推断】自建类 AI FDE 的首要任务不是聊天 UI，而是可审计、可审批、可回滚、可验证的平台工具执行面。
5. 【边界】内部 agent orchestrator、tool manifest schema、context bundle schema、approval policy schema、correlation id 等未公开，只能作为自建设计接口。

## Canonical Documents

| 文档 | 用途 |
| --- | --- |
| [docs/synthesis/palantir-ai-fde-research.md](../synthesis/palantir-ai-fde-research.md) | AI FDE 主题主结论，覆盖定位、流程、治理、架构推断、自建方案和证据缺口。 |

## Supporting Evidence

| 证据 | 精简说明 |
| --- | --- |
| [docs/raw/32-ai-fde-source-map.md](../raw/32-ai-fde-source-map.md) | 官方资料源、术语边界、AI FDE 与 AIP Assist/Analyst/MCP 的区分。 |
| [docs/raw/33-ai-fde-product-positioning.md](../raw/33-ai-fde-product-positioning.md) | 功能定位、产品边界、适用/不适用场景和设计原则。 |
| [docs/raw/34-ai-fde-context-tools-skills.md](../raw/34-ai-fde-context-tools-skills.md) | Session、context、modes、skills、tool approval、closed-loop 流程。 |
| [docs/raw/35-ai-fde-governance-branching.md](../raw/35-ai-fde-governance-branching.md) | 身份、权限、markings、approval、Global Branching、PR、audit。 |
| [docs/raw/36-ai-fde-architecture-design.md](../raw/36-ai-fde-architecture-design.md) | AIP/Foundry 架构映射、tool gateway、permission proxy、validation runner 推断。 |
| [docs/raw/37-ai-fde-self-build-implementation-blueprint.md](../raw/37-ai-fde-self-build-implementation-blueprint.md) | 自建参考架构、平台原生能力边界、90 天 PoC、风险清单。 |
| [docs/superpowers/plans/2026-05-30-palantir-ai-fde-research-plan.md](../superpowers/plans/2026-05-30-palantir-ai-fde-research-plan.md) | #20-#27 调研分工与 issue 映射。 |

## Related Issues

#20、#21、#22、#23、#24、#25、#26、#27、#46

## Open Questions

- AI FDE 内部是否存在统一 agent state machine、planner/replanner、memory schema 或 retry budget？
- Tool manifest、risk class、approval policy、tool result schema 是否有统一内部规范？
- AI FDE session logs、Foundry audit logs、AIP traces、CI checks、PR/proposal 是否存在统一 correlation id？
- Global Branch、Dataset Branch、Code Repository branch、fallback branch 在 AI FDE 内部如何绑定？
- 自建 PoC 的 golden tasks、目标平台 API inventory、权限模型、CI/eval adapter 需要补齐。
