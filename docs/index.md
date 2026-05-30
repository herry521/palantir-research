# Palantir Research 文档库入口

## 摘要与洞察

1. 【建议】先读 `docs/synthesis` 中的 canonical 结论，再回到 `docs/raw` 查证据；不要从 raw 编号顺序线性阅读。
2. 【事实】当前仓库保留三层主结构：`raw` 是证据层，`synthesis` 是结论层，`superpowers` 是计划与设计记录层。
3. 【推断】Data Quality、AI FDE、Dataset transaction、Pro-Code 和 Data Integration 权限体系是当前最适合直接服务自研平台设计的主题。
4. 【建议】新增 `docs/catalog.yml` 作为机器可读索引，后续主题页、阅读层和链接检查都应从 catalog 派生。

## 层级说明

| 层级 | 位置 | 职责 |
|---|---|---|
| 证据层 | `docs/raw/` | 保存官方资料、机制观察、矩阵、证据缺口和 Story 级调研。 |
| 结论层 | `docs/synthesis/` | 保存可复用综合判断、架构建议和自研平台启示。 |
| 计划/设计层 | `docs/superpowers/` | 保存研究计划、规格设计、执行拆解和评审记录。 |
| 元数据层 | `docs/catalog.yml` | 连接文档、主题、issue、canonical 状态和证据关系。 |
| 阅读层 | `docs/library/` | 规划中；用于“像书一样读”的导读和章节，不复制 raw 正文。 |
| 主题索引层 | `docs/topics/` | 已建立首批多轴入口；用于按 Dataset、Pipeline、Data Quality 等主题聚合结论和证据链。 |

设计基线见 [调研文档库体系化组织设计](superpowers/specs/2026-05-31-research-doc-library-design.md)，父 issue 为 [#42](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/42)。

## 主题索引

| 主题 | 入口 | 适合回答的问题 |
|---|---|---|
| Dataset | [docs/topics/dataset.md](topics/dataset.md) | Dataset、transaction/view、无 `dt` 分区、版本坐标和迁移风险。 |
| Pipeline | [docs/topics/pipeline.md](topics/pipeline.md) | Pipeline Builder、Transform、执行引擎、增量和算子平台。 |
| Scheduling | [docs/topics/scheduling.md](topics/scheduling.md) | Schedule trigger、graph build、staleness、freshness 与业务周期边界。 |
| Lineage and Catalog | [docs/topics/lineage-and-catalog.md](topics/lineage-and-catalog.md) | 血缘坐标、branch/version、catalog 元数据和文档库索引。 |
| Security and Marking | [docs/topics/security-and-marking.md](topics/security-and-marking.md) | Dataset/Data Integration 权限、Marking、Credential、传播、审计和外部通知安全。 |
| Ontology | [docs/topics/ontology.md](topics/ontology.md) | Object Type、Property、Link、Action、语义层和业务操作模型。 |
| Data Quality | [docs/topics/data-quality.md](topics/data-quality.md) | Data Expectations、Health Checks、Monitoring Views、告警和 issue 闭环。 |
| Pro-Code | [docs/topics/pro-code.md](topics/pro-code.md) | Code Repositories、Transform Contract、运行时、CI 和工程治理。 |
| AI FDE | [docs/topics/ai-fde.md](topics/ai-fde.md) | AI FDE 定位、context/tool/approval、branch、验证和自建边界。 |
| Self-build Roadmap | [docs/topics/self-build-roadmap.md](topics/self-build-roadmap.md) | 自研平台路线、能力优先级、双坐标迁移和 AI 工程执行面。 |

## 推荐阅读路径

### Dataset、事务与无 `dt` 分区

1. 先从 [Dataset 主题索引](topics/dataset.md) 明确核心坐标和开放问题。
2. 再读 [Palantir Dataset 无默认 dt 分区模型的数据模型差异分析](synthesis/palantir-dataset-no-dt-partition-impact.md)。
3. 对比背景可读 [Palantir Dataset 与传统数据仓库建模对比](synthesis/palantir-dataset-vs-data-warehouse.md)。

### Pipeline 与执行体系

1. 先从 [Pipeline 主题索引](topics/pipeline.md) 看表达、执行、流批、增量和互操作的证据分布。
2. 再读 [Palantir Pipeline 技术实现深度分析](synthesis/palantir-pipeline-deep-dive.md)。
3. 如果目标是自建算子平台，继续读 [算子平台建设方案](synthesis/operator-platform-design.md)。

### 安全、权限与 Marking

1. 先从 [Security and Marking 主题索引](topics/security-and-marking.md) 明确权限判定层次和待验证边界。
2. 再读 [Palantir Dataset 权限体系与 Marking 机制沉淀](synthesis/dataset-permission-marking-architecture-summary.md)。
3. 若目标是自研 Data Integration 权限控制面，继续读 [Data Integration 权限体系建设缺口与路线图](synthesis/data-integration-permission-system-roadmap.md)。
4. 按需回查 Marking 机制、实现方案、进阶机制和本轮 Data Integration Story：`docs/raw/11`、`12`、`13`、`50` 到 `56`。

### Data Quality

1. 先从 [Data Quality 主题索引](topics/data-quality.md) 明确构建期、运行期、监控视图和外部通知边界。
2. 再读 [Palantir Data Quality 模块调研综合报告](synthesis/palantir-data-quality-module-research.md)。
3. 按证据域读取 `docs/raw/44` 到 `docs/raw/49`。

### Pro-Code 与工程治理

1. 先从 [Pro-Code 主题索引](topics/pro-code.md) 看高码 Contract、工程入口和治理证据链。
2. 再读 [Palantir 高码能力研究综合结论](synthesis/palantir-pro-code-capability-research.md)。
3. 对质量、测试、血缘和权限治理，结合 [高码质量、测试、血缘、权限与可观测性调研](raw/26-pro-code-governance-quality-observability.md)。

### AI FDE

1. 先从 [AI FDE 主题索引](topics/ai-fde.md) 明确产品边界、治理门禁和未公开实现细节。
2. 再读 [Palantir AI FDE 综合结论、证据校验与自建方案](synthesis/palantir-ai-fde-research.md)。
3. 按需回查 `docs/raw/32` 到 `docs/raw/37`。

### 自建平台路线

1. 先从 [Self-build Roadmap 主题索引](topics/self-build-roadmap.md) 建立能力域优先级。
2. 从 [算子平台建设方案](synthesis/operator-platform-design.md)、[Data Quality 综合报告](synthesis/palantir-data-quality-module-research.md) 和 [Data Integration 权限体系路线图](synthesis/data-integration-permission-system-roadmap.md) 提取可落地模块。
3. 使用 `docs/catalog.yml` 查看 canonical 文档和对应证据层。

## 追踪与维护

- 当前文档库重组 Epic: [#42](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/42)
- 全局入口 Story: [#44](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/44)
- Catalog Story: [#45](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/45)
- Data Integration 权限体系 Epic: [#49](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/49)

维护规则：

- 不移动 `docs/raw` 和 `docs/synthesis` 中的既有文件，除非有单独 issue、alias 和链接检查。
- 新增重要结论必须写入 `docs/raw` 或 `docs/synthesis`，不能只留在聊天中。
- `catalog.yml` 中的 `canonical: true` 只用于当前推荐引用的结论文档或设计基线。
- 提交前运行 `bash scripts/verify-doc-library.sh` 和 `git diff --check`；如需确认校验能发现缺失路径，运行 `bash scripts/verify-doc-library.sh --self-test`。
