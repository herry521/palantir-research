# Palantir Dataset 权限体系与 Marking 机制沉淀

**沉淀日期：** 2026-05-30
**关联原始调研：** `docs/raw/30-dataset-permission-marking-architecture.md`
**适用读者：** 数据平台架构、权限治理、Dataset 控制面、Pipeline / Lineage 平台建设团队

---

## 1. 一句话结论

Palantir Foundry 的 Dataset 权限不是单一 RBAC，也不是普通标签系统，而是把 `Project / Resource Role`、`Organization`、`Marking`、`Classification`、`Lineage-derived data requirements`、`Restricted View`、`Ontology policy`、`SDS` 和 `Audit` 放进同一个访问控制闭环。

更准确地说：

```text
Dataset 访问 = 资源角色能力
           AND 组织边界资格
           AND 敏感 Marking 资格
           AND 上游血缘继承的数据访问要求
           AND 可选行级 / 属性级策略
           AND 审计、审批、会话范围控制
```

这套机制的本质不是“给 Dataset 打标签”，而是把敏感数据资格变成平台强制执行的访问要求，并让这些要求随资源层级和数据血缘自动传播。

---

## 2. Dataset 为什么不能只看 ACL

Foundry Dataset 同时有三种身份：

| 身份 | 含义 | 权限含义 |
|---|---|---|
| Filesystem Resource | 位于 Foundry 文件系统和 Project / folder 结构中的资源 | 受 Project role、folder inheritance、resource marking、organization 控制 |
| Data Asset | 由 transaction、branch、schema、view 组成的数据资产 | 受 data requirement、上游 Marking / Classification 继承影响 |
| Pipeline Node | Transform / Sync 的输入或输出节点 | 参与 Marking、Organization、Classification 的血缘传播 |

因此 Dataset 访问必须拆成两类：

```text
Resource access：用户能否发现、打开、管理这个 Dataset 资源。
Data access：用户能否读取 Dataset view 中的实际数据。
```

用户可能有 Dataset 的 Viewer role，也能看到 metadata，但因为不满足上游 data marking 而不能读数据。这是 Foundry 权限模型和普通资源 ACL 最大的差异之一。

---

## 3. 权限体系全景

| 权限体系 | 类型 | 作用对象 | 主要用途 | 是否随血缘传播 |
|---|---|---|---|---|
| Project / Resource Roles | DAC | Project、folder、file、Dataset | 授予 Owner、Editor、Viewer、Discoverer 等操作能力 | 否 |
| Organizations | MAC | Space / Project 及其资源 | 组织边界、跨组织协作 | 是 |
| Markings | MAC | Project、folder、resource、Dataset data | PII、PHI、Finance 等敏感数据资格控制 | 是 |
| Classifications / CBAC | MAC | Project、file、Dataset data | 高密级 / 政府敏感信息控制 | Data classification 会继承 |
| Restricted Views | 行级策略 | Dataset 下游视图 | 控制用户只能看到部分行 | 不是 transform input |
| Marking-backed Restricted Views | 行级策略 + Marking | 带 Marking ID 列的 Dataset | 每行要求不同 Marking | 由策略判断 |
| Ontology Object / Property Security | 对象 / 属性策略 | Object Type、Object Set、Property | 业务对象和字段可见性 | 依赖 backing source |
| SDS / Cipher | 治理和保护 | Dataset、virtual table、media set、列值 | 敏感发现、自动打标、加密、哈希 | 可触发 Marking |
| Audit Logs | 审计 | 平台动作 | 权限变更、读取、审批、解密审计 | 不适用 |

---

## 4. 访问判定模型

一个 Dataset view 的读取判定可以抽象为：

```text
can_read_dataset_view(user, dataset_view) =
    has_resource_role(user, dataset, "view")
AND satisfies_organization_requirements(user, dataset.resource_requirements)
AND satisfies_file_markings(user, dataset.file_requirements)
AND satisfies_file_classification(user, dataset.file_classification)
AND satisfies_data_markings(user, dataset_view.data_requirements)
AND satisfies_data_classification(user, dataset_view.data_classification)
AND satisfies_scoped_session(user, active_session, required_markings)
AND satisfies_granular_policy_if_applicable(user, row_or_property)
```

关键边界：

- Role 授权操作能力，但不能绕过 Marking。
- Marking 表示敏感数据资格，但不会自动授予资源访问权。
- Organization 是组织边界资格，普通 Marking 是敏感数据资格。
- Resource requirement 和 data requirement 要分开存储、分开解释、统一判定。
- Restricted View / Ontology policy 只在对应访问路径中追加细粒度策略，不能替代 Dataset 本身的访问控制。

---

## 5. Role、Organization、Marking 的语义差异

### 5.1 Role：资源操作能力

Project 和 Resource Roles 属于自主访问控制。它回答的是“用户在这个资源上能做什么”。

| Role | 典型含义 |
|---|---|
| Owner | 管理资源、授权、修改 marking、移动资源 |
| Editor | 编辑资源、修改 pipeline、构建数据 |
| Viewer | 查看资源和读取数据，前提是满足所有 access requirements |
| Discoverer | 发现资源存在，但不能读取内容 |

### 5.2 Organization：组织边界资格

Organization 是应用在 Project / Space 级别的组织隔离要求。用户需要属于至少一个相关 Organization，才能满足组织边界要求。

```text
organization_ok = user belongs to at least one required organization
```

### 5.3 Marking：敏感数据资格

Marking 是 Foundry 的强制访问控制核心。它回答的是“用户有没有资格接触某类敏感数据”。

普通 Marking 的保守语义是合取：

```text
marking_ok = user has every required marking
```

也就是说，如果 Dataset 同时要求 `PII`、`Finance`、`HR`，用户必须同时拥有三个 Marking 资格。

---

## 6. Marking 的对象模型

从公开 API 和功能语义看，自建平台可以参考下面的对象模型：

```text
MarkingCategory
  id
  name
  categoryType
  markingType: MANDATORY | CBAC
  administrators
  viewers

Marking
  id
  categoryId
  name
  description
  organization?
  createdTime

MarkingMember
  markingId
  principalId
  principalType: user | group

MarkingRoleAssignment
  markingId
  principalId
  role: manage | apply | remove | view

ResourceRequirement
  resourceRid
  requirementType: marking | organization | classification
  requirementId
  sourceType: direct | inherited_from_parent
  sourceRid

DataRequirement
  datasetRid
  transactionRid | branch | view
  requirementType: marking | organization | classification
  requirementId
  sourceInputDatasetRid
  sourceTransactionRid
```

这里最重要的是把 `MarkingMember` 和 `MarkingRoleAssignment` 分开。管理某个 Marking 的人，不应天然拥有读取该类敏感数据的资格。

---

## 7. Marking 传播机制

Marking 有两条传播路径。

### 7.1 文件层级传播

```text
Project 加 PII Marking
  -> folder 继承 PII
  -> Dataset resource 继承 PII
```

这保护的是资源层级，用户不满足要求时可能看不到资源，或无法进入资源。

### 7.2 数据血缘传播

```text
Raw Dataset A 带 PII Marking
  -> Transform 读取 A
  -> Curated Dataset B 继承 PII data requirement
  -> Downstream Dataset C 继续继承
```

这保护的是数据内容本身。即使 B 放在另一个 Project，只要数据来自 A，B 的数据访问也要继承 A 的敏感要求。

---

## 8. Marking 移除与传播中断

Foundry 支持在受控条件下中断继承的 Marking / Organization，常见场景是脱敏、聚合、匿名化后，下游数据不再包含原始敏感内容。

典型链路：

```text
上游 Dataset 有 PII
  -> Transform 执行脱敏
  -> 代码声明 stop_propagating / stop_requiring
  -> Protected branch 触发审批
  -> 具备 Remove marking / Expand access 权限的审批人复核
  -> 新 output transaction 不再继承该 requirement
  -> 审计记录 unmarking decision
```

关键原则：

- 传播中断不能只靠 transform 作者自证。
- 审批人权限必须与具体 Marking / Organization 绑定。
- 规则应绑定 branch、input、output 和 requirement ID。
- 移除 inherited marking 通常只影响新 output transaction，不应默认改写历史 transaction。

---

## 9. 架构设计参考

自建类似能力时，建议拆成下面几层：

```text
Identity / IAM
  -> Entitlement Resolver
  -> Resource Catalog
  -> Dataset Version Store
  -> Marking Admin Service
  -> Access Requirement Service
  -> Lineage Graph
  -> Propagation Engine
  -> Policy Decision Point
  -> Query / Build Enforcement
  -> Approval Workflow
  -> Audit / SIEM
  -> Access Debugger / Impact Simulator
```

核心职责：

| 模块 | 职责 |
|---|---|
| Entitlement Resolver | 解析用户、组、组织、Marking membership、CBAC clearance、session scope |
| Resource Catalog | 管理 Project、folder、Dataset、file、RID、父子关系和 roles |
| Dataset Version Store | 管理 branch、transaction、view、schema version 和 producer run |
| Marking Admin Service | 管理 category、marking、members、apply/remove/manage 权限 |
| Access Requirement Service | 存储 direct / inherited resource requirement 和 data requirement |
| Lineage Graph | 记录 Dataset、Transform、Sync、Ontology 的资源级和版本级依赖 |
| Propagation Engine | 在 build 和 marking 变更时计算 effective requirements |
| Policy Decision Point | 统一做访问判定，输出 allow / deny / missing requirements |
| Approval Workflow | 处理 unmarking、expand access、branch protection 和 reviewer 权限 |
| Audit / SIEM | 记录权限变更、读取、审批、扫描、解密等事件 |
| Access Debugger | 解释为什么不能访问，以及变更 Marking 会影响哪些资源和用户 |

---

## 10. 实现链路

### 链路 A：创建 Marking

```text
DPO / Platform Admin
  -> 创建 Marking Category
  -> 创建 Marking
  -> 分配 Marking members
  -> 分配 apply / remove / manage 权限
  -> 写入 audit log
```

### 链路 B：给 Dataset 加 Marking

```text
Resource Owner + Apply Marking 权限用户
  -> 调用 add markings / UI apply
  -> 校验 resource role 与 marking apply 权限
  -> 记录 ResourceRequirement
  -> 下游影响分析
  -> 写入 audit log
```

### 链路 C：Pipeline 构建时继承 Marking

```text
BuildRun 启动
  -> 解析 input datasets 和具体 transactions
  -> 读取 input data requirements
  -> 合并 Project / resource requirements
  -> 应用已批准的 unmarking rule
  -> 写 output transaction
  -> 记录 output data requirements
  -> 更新 lineage graph
```

### 链路 D：用户读取 Dataset

```text
Read request
  -> 解析用户角色、组、组织、Marking membership
  -> 加载 resource requirements
  -> 加载 dataset view / transaction data requirements
  -> 执行 PDP 判定
  -> 通过则读取数据
  -> 拒绝则返回 missing role / marking / organization / classification
  -> 写入访问审计
```

### 链路 E：脱敏后移除 inherited Marking

```text
Transform 声明 stop_propagating
  -> Branch protection 检查
  -> Security reviewer 审批
  -> 校验 reviewer 对该 Marking 有 remove 权限
  -> 生成 approved unmarking rule
  -> 新 build 生效
  -> 旧 transactions 保持原 requirement
```

---

## 11. 自建平台成熟度分层

| 层级 | 能力 | 结果 |
|---|---|---|
| L0 | Dataset ACL | 只能控制资源访问，无法治理敏感数据传播 |
| L1 | Project role + group | 能做协作授权，但敏感数据资格仍不完整 |
| L2 | Marking 管理 + Dataset direct marking + query-time enforcement | 能限制带标资源，但没有血缘传播 |
| L3 | Lineage-aware propagation + data requirements | 能治理派生数据，是 Foundry 式权限的核心分水岭 |
| L4 | Protected branch unmarking + transaction-level requirements + Restricted View + SDS + Audit | 具备生产级治理闭环 |

最低可用目标不应停在 L2。否则下游 Dataset 很容易绕过上游敏感数据要求。

---

## 12. 常见误区

| 误区 | 风险 | 修正 |
|---|---|---|
| 把 Marking 当普通 tag | 标签只描述数据，不能强制访问控制 | Marking 必须进入服务端鉴权 |
| 把 Role 当敏感资格 | Viewer / Owner 绕过敏感数据要求 | Role 和 Marking 分离 |
| 只做资源 ACL | 下游派生数据绕过上游限制 | 增加 lineage-aware data requirement |
| Marking admin 默认也是 member | 管理者自动获得数据读取资格 | admin / member 分离 |
| stop_propagating 不走审批 | 工程师可单独扩大访问 | protected branch + required approver |
| 只存当前权限，不存 transaction requirement | 历史数据和新数据权限混淆 | requirement 绑定 transaction / view |
| 缺 access debugger | 权限问题无法解释 | 提供 missing requirement 和影响分析 |

---

## 13. 对我们的建设建议

1. 先统一 Dataset、Resource、Branch、Transaction、Lineage 的元模型，再补 Marking。
2. Marking 不要做成普通标签字段，必须进入鉴权、构建、查询、审批和审计链路。
3. Resource requirement 和 Data requirement 要分开建模，否则无法解释“看得到资源但读不了数据”。
4. Lineage propagation 是核心分水岭，没有它就不是 Foundry 式治理。
5. 移除继承权限必须产品化为审批流程，而不是代码注释或人工约定。
6. 权限系统必须提供解释接口，例如 `getAccessRequirements`、`whyDenied`、`simulateMarkingImpact`。
7. SDS、Restricted View、Ontology property security 应作为 L4 能力逐步接入，而不是第一阶段全部堆上。

---

## 14. HTML 展示口径

站点页面应突出四个阅读重点：

1. Dataset 访问为什么是多层判定，而不是单一 RBAC。
2. Role、Organization、Marking、Data Requirement 的边界。
3. Marking 如何沿资源层级和数据血缘传播。
4. 自建平台要如何落控制面、构建链路、查询链路、审批链路和审计链路。

页面不需要复刻原始调研的全部 API 和 SQL 模型，完整证据和实现细节继续指向 `docs/raw/30-dataset-permission-marking-architecture.md`。
