# Pro-Code

## 摘要与洞察

1. 【推断】Palantir 高码能力的核心不是“能写代码”，而是把代码变成平台可理解的 `Transform Contract`：输入、输出、参数、运行时、质量规则、增量语义和权限边界都能被调度、血缘、质量和治理系统消费。
2. 【事实】Code Repositories 是平台内工程入口，覆盖 Git、分支、PR/code review、protected branch、lint/error checking、preview/debug、impact analysis、repository upgrade 等能力。
3. 【推断】Dataset Transaction 是高码增量、回滚、可重复构建和失败隔离的关键底座；不能只用任务级 `updated_at` 或业务字段模拟。
4. 【推断】低码 Pipeline Builder 与高码 Code Repositories 应共享同一套 Contract/IR；现有资料支持“低码导出高码”的单向升级路径，但不支持无损双向同步。
5. 【边界】跨 repository 依赖索引、内部 DAG 生成、Pipeline Builder 内部 IR、复杂增量边界仍缺真实环境验证。

## Canonical Documents

| 文档 | 用途 |
| --- | --- |
| [docs/synthesis/palantir-pro-code-capability-research.md](../synthesis/palantir-pro-code-capability-research.md) | Pro-Code 主题主结论，覆盖能力强点、实现模型、借鉴方案、PoC 和证据缺口。 |

## Supporting Evidence

| 证据 | 精简说明 |
| --- | --- |
| [docs/raw/21-pro-code-capability-deep-dive.md](../raw/21-pro-code-capability-deep-dive.md) | 早期全景调研，提出高码强点、Dataset graph、运行时分层和自建借鉴。 |
| [docs/raw/22-pro-code-source-map.md](../raw/22-pro-code-source-map.md) | 资料源与可信度矩阵，映射 #6-#11/#14 研究 story。 |
| [docs/raw/23-code-repositories-engineering-entry.md](../raw/23-code-repositories-engineering-entry.md) | Code Repositories 工程入口、PR、preview/debug、impact analysis、protected branch。 |
| [docs/raw/24-pro-code-runtime-compute-engines.md](../raw/24-pro-code-runtime-compute-engines.md) | Python/Java/SQL、Spark/lightweight runtime、依赖与计算引擎边界。 |
| [docs/raw/25-transform-contract-dag.md](../raw/25-transform-contract-dag.md) | Input/Output contract、DAG 推导、Dataset graph、SQL/Java/Python 边界。 |
| [docs/raw/26-pro-code-governance-quality-observability.md](../raw/26-pro-code-governance-quality-observability.md) | 测试、Data Expectations、Data Lineage、Markings、observability 治理闭环。 |
| [docs/raw/27-incremental-scheduling-transaction.md](../raw/27-incremental-scheduling-transaction.md) | Dataset Transaction、增量 read/write mode、调度和 staleness 语义。 |
| [docs/raw/28-pipeline-builder-pro-code-interop.md](../raw/28-pipeline-builder-pro-code-interop.md) | Pipeline Builder 与高码互操作、导出限制和语义差异风险。 |
| [docs/superpowers/plans/2026-05-29-palantir-pro-code-research-plan.md](../superpowers/plans/2026-05-29-palantir-pro-code-research-plan.md) | Pro-Code 调研计划与交付拆解。 |

## Related Issues

#4、#6、#7、#8、#9、#10、#11、#12、#14、#46

## Open Questions

- Palantir 内部 transform 扫描、跨 repository 依赖索引和事件传播机制是否有统一索引服务？
- Pipeline Builder 内部 IR 与导出 Java transforms 的字段映射是否能稳定复刻？
- 复杂增量场景下，`UPDATE`/`DELETE`、retention、schema evolution、snapshot fallback 的真实边界是什么？
- Java/SQL 与 Python 在 unit tests、Data Expectations、incremental、lightweight engine 上是否具备等价能力？
- 自建平台第一阶段应优先做 Code Repository 工程入口，还是先固化 Transform Contract 与 Dataset Transaction？
