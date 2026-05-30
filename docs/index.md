# Palantir Research 文档库入口

## 摘要与洞察

1. 【建议】先读 `docs/synthesis` 中的 canonical 结论，再回到 `docs/raw` 查证据；不要从 raw 编号顺序线性阅读。
2. 【事实】当前仓库保留三层主结构：`raw` 是证据层，`synthesis` 是结论层，`superpowers` 是计划与设计记录层。
3. 【推断】Data Quality、AI FDE、Dataset transaction、Pro-Code 和权限/Marking 是当前最适合直接服务自研平台设计的主题。
4. 【建议】新增 `docs/catalog.yml` 作为机器可读索引，后续主题页、阅读层和链接检查都应从 catalog 派生。

## 层级说明

| 层级 | 位置 | 职责 |
|---|---|---|
| 证据层 | `docs/raw/` | 保存官方资料、机制观察、矩阵、证据缺口和 Story 级调研。 |
| 结论层 | `docs/synthesis/` | 保存可复用综合判断、架构建议和自研平台启示。 |
| 计划/设计层 | `docs/superpowers/` | 保存研究计划、规格设计、执行拆解和评审记录。 |
| 元数据层 | `docs/catalog.yml` | 连接文档、主题、issue、canonical 状态和证据关系。 |
| 阅读层 | `docs/library/` | 规划中；用于“像书一样读”的导读和章节，不复制 raw 正文。 |
| 主题索引层 | `docs/topics/` | 规划中；用于按 Dataset、Pipeline、Data Quality 等主题聚合入口。 |

设计基线见 [调研文档库体系化组织设计](superpowers/specs/2026-05-31-research-doc-library-design.md)，父 issue 为 [#42](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/42)。

## 推荐阅读路径

### Dataset、事务与无 `dt` 分区

1. 先读 [Palantir Dataset 无默认 dt 分区模型的数据模型差异分析](synthesis/palantir-dataset-no-dt-partition-impact.md)。
2. 再查证据链：`docs/raw/39` 到 `docs/raw/43`。
3. 对比背景可读 [Palantir Dataset 与传统数据仓库建模对比](synthesis/palantir-dataset-vs-data-warehouse.md)。

### Pipeline 与执行体系

1. 先读 [Palantir Pipeline 技术实现深度分析](synthesis/palantir-pipeline-deep-dive.md)。
2. 再读 Pipeline 表达、执行、流批、增量和调度相关 raw：`docs/raw/01`、`02`、`03`、`06-incremental`、`15`、`27`。
3. 如果目标是自建算子平台，继续读 [算子平台建设方案](synthesis/operator-platform-design.md)。

### 安全、权限与 Marking

1. 先读 [Palantir Dataset 权限体系与 Marking 机制沉淀](synthesis/dataset-permission-marking-architecture-summary.md)。
2. 再读全量证据 [Dataset 权限体系与 Marking 架构](raw/30-dataset-permission-marking-architecture.md)。
3. 按需回查 Marking 机制、实现方案和进阶机制：`docs/raw/11`、`12`、`13`。

### Data Quality

1. 先读 [Palantir Data Quality 模块调研综合报告](synthesis/palantir-data-quality-module-research.md)。
2. 再按证据域读取 `docs/raw/44` 到 `docs/raw/49`。
3. 重点关注三层边界：Data Expectations 构建期门禁、Data Health/Health Checks 运行期监控、Monitoring Views 规模化告警。

### Pro-Code 与工程治理

1. 先读 [Palantir 高码能力研究综合结论](synthesis/palantir-pro-code-capability-research.md)。
2. 再读 `docs/raw/22` 到 `docs/raw/28`。
3. 对质量、测试、血缘和权限治理，结合 [高码质量、测试、血缘、权限与可观测性调研](raw/26-pro-code-governance-quality-observability.md)。

### AI FDE

1. 先读 [Palantir AI FDE 综合结论、证据校验与自建方案](synthesis/palantir-ai-fde-research.md)。
2. 再读 `docs/raw/32` 到 `docs/raw/37`。
3. 重点看功能边界、上下文/工具模型、治理分支和自建 PoC 路线。

### 自建平台路线

1. 从 [算子平台建设方案](synthesis/operator-platform-design.md) 和 [Data Quality 综合报告](synthesis/palantir-data-quality-module-research.md) 提取可落地模块。
2. 结合 Dataset、Pipeline、权限、AI FDE 四条阅读路径构建平台能力图。
3. 使用 `docs/catalog.yml` 查看 canonical 文档和对应证据层。

## 追踪与维护

- 当前文档库重组 Epic: [#42](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/42)
- 全局入口 Story: [#44](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/44)
- Catalog Story: [#45](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/45)

维护规则：

- 不移动 `docs/raw` 和 `docs/synthesis` 中的既有文件，除非有单独 issue、alias 和链接检查。
- 新增重要结论必须写入 `docs/raw` 或 `docs/synthesis`，不能只留在聊天中。
- `catalog.yml` 中的 `canonical: true` 只用于当前推荐引用的结论文档或设计基线。
- 提交前运行 `bash scripts/verify-doc-library.sh` 和 `git diff --check`；如需确认校验能发现缺失路径，运行 `bash scripts/verify-doc-library.sh --self-test`。
