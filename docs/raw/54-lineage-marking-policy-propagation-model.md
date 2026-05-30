# 54 - 权限传播、血缘、Marking 与细粒度策略落地模型

**所属 Epic：** #49
**对应 Story：** #54
**类型：** Story 调研 / Lineage-derived Requirements 与 Policy Propagation
**调研日期：** 2026-05-31

## 摘要与洞察

1. 【事实】Dataset 权限不是单一 ACL/RBAC，而是 `resource role + Organization + Marking + Classification + lineage-derived data requirements + optional row/property policy` 的组合；role 不能绕过 Marking。
2. 【事实】Marking/Organization 会沿文件层级和直接数据血缘传播；`stop_propagating` / `stop_requiring` 只适用于 Marking/Organization，不适用于 roles。
3. 【推断】自研平台的核心分水岭不是“能给 Dataset 打标签”，而是能把 access requirements 绑定到 transaction/view，在 build-time 物化传播结果，在 query-time 快速鉴权并解释拒绝原因。
4. 【建议】细粒度策略应作为 Dataset 级 requirements 的补充；Restricted View、row policy、property security 解决行列级可见性，但不能替代上游 Dataset/data requirement 的强制传播。
5. 【待验证】Palantir 未公开 propagation engine 的内部数据结构；本文模型是基于公开行为和自研工程需求的架构推断。

## 1. 全链路传播模型

```text
Source system
  -> Connection / credential / sync config
  -> Sync task or transform run
  -> Output dataset / stream transaction
  -> Dataset view / active pointer
  -> Restricted view / ontology / API / BI / AIP consumption
```

建议把 access requirements 拆成四层：

| 层级 | 应携带的 access requirements | 快照点 |
|---|---|---|
| Source / Connection | 源系统 owner、数据域、组织边界、敏感分类、连接凭据可用范围 | connection policy version |
| Sync / Transform | input Dataset/view/transaction requirements、unmarking intent、执行账号 | run input snapshot |
| Dataset / Stream | direct resource requirement + lineage-derived data requirement + branch/view pointer | committed transaction requirement |
| Downstream consumption | 用户 role、Marking membership、Organization、session scope、row/property policy | access decision snapshot |

传播计算可抽象为：

```text
output_requirement =
  output_direct_resource_requirement
  + union(input_resource_requirements)
  + union(input_transaction_requirements)
  - approved_input_specific_stop_rules
```

## 2. 落地边界

| 边界 | 建议 |
|---|---|
| input-specific unmarking | `stop_propagating` 必须绑定 input -> output -> requirement_id -> protected_branch -> approval_id |
| 多输入相同 Marking | 只 stop 一个 input 不会删除其他 input 继续传播的相同 requirement |
| 历史 transaction | unmarking 只影响新 output transaction，历史 transaction 不应被静默改写 |
| rebuild | 普通 requirement 元数据变化未必重算数据；若旧 marked transaction 仍被下游增量依赖，需要 SNAPSHOT/full rebuild guidance |
| query-time | 读取时基于已物化 transaction/view requirements，不实时遍历全 lineage |
| debug | whyDenied 必须能定位到 source/input transaction/branch/fallback/requirement 来源 |

## 3. 关键事件建议

| 事件 | 触发 | 下游动作 |
|---|---|---|
| `ConnectionPolicyChanged` | source/connection policy、owner、credential scope 变化 | 标记相关 sync outputs stale，重算 requirements |
| `SyncOutputCommitted` | batch sync / stream micro-batch 写入 Dataset | 写 transaction_requirement、lineage edge |
| `TransformBuildStarted` | 构建开始 | Resolve input branch/view/transaction 和 entitlement context |
| `OutputRequirementComputed` | output commit 前 | 持久化 transaction/view requirements |
| `RequirementChanged` | direct marking、membership、org、classification 变化 | downstream impact scan、simulation cache invalidation |
| `UnmarkingRuleProposed` | PR/Pipeline Builder 声明停止传播 | 触发 security approval |
| `UnmarkingRuleApproved/Rejected` | 审批完成 | approved 才允许 protected branch build 生效 |
| `DatasetReadRequested` | preview/API/BI/export/AIP 读取 | PDP 决策，写 allow/deny audit |
| `AccessRequestSubmitted` | 用户缺 role/Marking/org | 路由到 owner / marking admin / org admin |
| `RequirementDriftDetected` | actual requirement 与 desired policy 不一致 | 阻断发布或创建治理 issue |

## 4. 与 Apache Atlas 的对照启示

Apache Atlas classification propagation 证明了一类关键设计：classification/tag 可以沿 lineage 自动传播，也可以通过 entity association、lineage edge propagation flag、blocked classifications 控制传播。Atlas 在 propagated classification add/update/delete 时向 `ATLAS_ENTITIES` topic 发通知。

自研平台可借鉴：

- tag/classification propagation 与 lineage edge 解耦。
- edge-level block propagation 支持脱敏场景。
- 传播变化发事件，供权限缓存、impact simulation、audit pipeline 消费。

不宜直接照搬：

- Atlas classification 本身不等于 query-time enforcement。
- Atlas propagation flag 不包含 Palantir 式 protected branch + marking-specific approver。
- Atlas 不解决 Dataset transaction/view 的历史 requirement 快照。

## 5. 自研平台建设建议

| 优先级 | 能力 | 说明 |
|---|---|---|
| P0 | Resource、Dataset、Branch、Transaction、Lineage、Principal、Role、Marking、Organization 分开建模 | 支撑 requirement 来源解释 |
| P0 | Build-time requirement propagation | 每次 sync/transform output commit 前 resolve branch/view/input transaction，计算 inherited requirements，写入 `transaction_requirement`；无法计算时 fail closed |
| P0 | query-time PDP | 所有 preview/API/export/BI/AIP 入口统一鉴权 |
| P0 | whyDenied | 返回缺 role、marking、organization、classification、row policy 或 export policy |
| P1 | Access debugger | getAccessRequirements、lineage permission coloring、resolved branch/transaction 展示 |
| P1 | Protected unmarking | stop propagation 绑定 branch、input、output、approver 权限 |
| P1 | Rebuild guidance | 检测旧 marked transaction 和下游增量依赖 |
| P2 | Restricted View / row policy | 行级/属性级策略，明确不能替代 Dataset-level requirements |
| P2 | SDS 自动治理 | 扫描 source boundary，自动 apply marking/create issue/obfuscate |
| P2 | Policy drift detection | desired policy、code declaration、effective requirement、audit reality 四方比对 |

## 6. P0 propagation contract

最小 P0 不要求完成复杂 impact simulation 或大规模重算优化，但必须满足以下硬约束：

1. Sync/Transform output commit 前必须解析实际 input branch、fallback branch、view 和 transaction range。
2. 对每个 input 读取已物化的 resource/data requirements；若缺失、过期或不可解释，应 fail closed，而不是写出无 requirements 的 output。
3. 计算结果写入 `transaction_requirement`，并记录 `requirement_source`：source/input dataset、input transaction、resource hierarchy、direct marking、approved stop rule。
4. Query-time PDP 只能消费已提交的 `transaction_requirement` / `view_effective_requirement`，不能临时全图遍历并猜测 lineage。
5. 复杂能力如 downstream impact simulation、历史大规模重算、cache invalidation 优化可以留到 P1/P2。

## 7. 证据缺口

1. 【待验证】Palantir Propagation Engine 的持久化结构、重算算法、缓存失效机制未公开。
2. 【待验证】多 branch、多 fallback branch、stream replay 下 transaction requirements 的精确选择需要实测。
3. 【待验证】row/property policy 与 Dataset requirements 的统一 whyDenied 输出没有公开 schema。
4. 【待验证】大规模 Marking 变更的 downstream impact simulation 性能和一致性机制未公开。

## 8. 来源

- Palantir Markings: <https://www.palantir.com/docs/foundry/security/markings/>
- Palantir Remove inherited Markings: <https://www.palantir.com/docs/foundry/building-pipelines/remove-inherited-markings>
- Palantir Checking Permissions: <https://www.palantir.com/docs/foundry/security/checking-permissions>
- Apache Atlas Classification Propagation: <https://atlas.apache.org/1.1.0/ClassificationPropagation.html>
- Apache Atlas PropagateTags: <https://atlas.apache.org/1.1.0/api/v2/json_PropagateTags.html>
- `docs/raw/11-marking-mechanism-deep-dive.md`
- `docs/raw/12-dataset-marking-implementation.md`
- `docs/raw/13-marking-advanced-deep-dive.md`
- `docs/raw/30-dataset-permission-marking-architecture.md`
- `docs/raw/42-governance-lineage-audit-contracts.md`
