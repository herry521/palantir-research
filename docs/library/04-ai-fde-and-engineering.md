# AI FDE and Engineering

## 摘要与洞察

1. 【结论】Pro-Code 和 AI FDE 的共同前提是平台先能理解工程动作、数据契约、权限边界和验证结果。
2. 【事实】Code Repositories 提供 Git、分支、PR/code review、protected branch、preview/debug、impact analysis 和 repository upgrade 等平台内工程入口。
3. 【事实】AI FDE 在当前用户 Foundry session 下执行，继承用户权限、markings、audit logging 和 LLM usage attribution，不是独立 bot/service account。
4. 【推断】AI FDE 的可信边界来自 mode/skill、explicit context、tool approval、branch/proposal/PR、preview/CI/evals 和 audit logs 的组合。
5. 【建议】自建类 AI FDE 的第一阶段应优先做只读或 branch-scoped 的受控工具执行面，而不是直接做生产写入自动化。

## Pro-Code 的平台意义

高码能力的价值不只是允许用户写 Python、Java 或 SQL。更重要的是代码进入平台后变成 `Transform Contract`：

- 输入、输出、参数和运行时可以被调度系统解析。
- 依赖、下游和影响范围可以进入 Data Lineage。
- 质量规则、增量语义和权限要求可以进入构建与治理链路。
- PR、protected branch、CI、preview 和 debug 可以在数据资产上下文中运行。

这解释了为什么“外部 Git + 外部 CI + Spark 作业”无法自动获得 Foundry 级体验。

## AI FDE 的正确定位

AI FDE 不应被理解成通用聊天助手。它更像“平台内受治理约束的工程执行入口”：

```text
User session
  -> selected context / mode / skills
  -> Foundry tool gateway
  -> permission and approval checks
  -> branch / PR / proposal / preview
  -> CI / eval / audit evidence
```

自建时，LLM 只是入口。真正决定可靠性的，是工具权限、上下文边界、审批、验证和回滚机制。

## 分阶段建议

| 阶段 | 范围 | No-go 条件 |
| --- | --- | --- |
| P0 Read-only assistant | 查询资源、解释 lineage、总结 build/quality/audit 状态。 | 无权限过滤、无审计、无法解释来源。 |
| P1 Branch-scoped executor | 在 branch 上生成 transform、配置检查、打开 PR。 | 直接改 main、绕过 owner review。 |
| P2 Controlled production workflow | 经 approval、CI/eval、proposal 合并后进入生产。 | 无回滚、无验证证据、无 access decision snapshot。 |

## 主要证据

- [Palantir 高码能力研究综合结论](../synthesis/palantir-pro-code-capability-research.md)
- [Palantir AI FDE 综合结论、证据校验与自建方案](../synthesis/palantir-ai-fde-research.md)
- [Transform Contract 与 DAG 推导机制调研](../raw/25-transform-contract-dag.md)
- [AI FDE 交互、上下文、模式与工具模型](../raw/34-ai-fde-context-tools-skills.md)
- [AI FDE 安全治理、审批与分支变更模型](../raw/35-ai-fde-governance-branching.md)
- [AI FDE 自建实现方案与 PoC 路线](../raw/37-ai-fde-self-build-implementation-blueprint.md)
