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

## 11. Palantir Marking 实现机制口径

Palantir 没有公开 Foundry Marking 的内部表结构和代码实现。本节把公开文档/API 能确认的事实，与基于公开行为可合理推断的内部实现拆开描述。

### 11.1 公开事实：Marking 是 Access Requirement

Palantir 官方语义里，Marking 是应用在 files、folders、projects 等资源上的额外访问控制。用户必须满足资源上的 Markings 才能访问资源。它不是描述数据的普通 tag，而是平台强制执行的访问要求。

更合适的抽象是：

```text
AccessRequirement {
  type: MARKING
  id: PII
}
```

不是：

```text
Tag {
  name: PII
}
```

这一区别决定了实现方式：

- Marking 必须进入服务端鉴权链路。
- Marking 必须能被查询、解释、审计。
- Marking 变更必须能触发下游影响分析。
- Marking 不能只作为 Dataset metadata 展示。

### 11.2 公开事实：对象层分成 Marking、Member、Role Assignment

Palantir 公开 API 暴露了这些对象：

```text
MarkingCategory
Marking
MarkingMember
MarkingRoleAssignment
ResourceAccessRequirements
```

它至少表达了两组关系：

```text
MarkingMember
  谁具备访问该 Marking 数据的资格

MarkingRoleAssignment
  谁可以管理、应用、移除该 Marking
```

因此自建时不要把这几件事合并：

| 权限关系 | 含义 | 是否应自动互相包含 |
|---|---|---|
| Marking member | 用户具备访问该类敏感数据的资格 | 否 |
| Apply marking | 用户可以把 Marking 应用到资源 | 否 |
| Remove marking | 用户可以从资源或继承链路中移除 Marking 要求 | 否 |
| Manage marking | 用户可以管理 Marking metadata、members、roles | 否 |

这说明 Palantir 的 Marking 实现不是简单的 `marking_id -> users`，而是将“数据访问资格”和“治理操作权限”拆开。

### 11.3 公开事实：Marking 有两条传播路径

Palantir 文档明确说明 Markings 会通过 file hierarchy 和 direct dependencies 继承，并通过 transform / analysis logic 传播。

可以拆成两条路径：

```text
路径 A：资源层级传播
Project / Folder Marking
  -> Child Folder
  -> Dataset / Code Repository / Analysis / File

路径 B：数据依赖传播
Dataset A with PII
  -> Transform reads A
  -> Dataset B inherits PII
  -> Dataset C derived from B inherits PII
```

这也是 Foundry Marking 的关键点：敏感要求不仅跟着资源位置走，也跟着数据派生关系走。

### 11.4 公开事实：读取时区分 resource access 与 data access

Foundry 的 Data Lineage 权限排查区分两类访问：

```text
Resource access
  用户能否发现、打开、管理这个资源。

Data access
  用户能否读取 Dataset view 中的实际数据。
```

因此用户可能满足 Dataset resource 的 role 和 file requirements，但不满足上游继承来的 data requirements，结果是能看到 Dataset metadata，却不能读取数据内容。

这意味着内部实现不能只有一张资源 ACL。至少要能表达：

```text
resource requirements
data / transaction / view requirements
```

### 11.5 推断：内部大概率有 Requirement Service 和 Propagation Engine

基于公开 API 和行为，可以合理推断 Foundry 内部存在类似组件：

```text
Marking Service
  管 marking、category、members、role assignments

Resource Requirement Service
  管资源 direct / inherited access requirements

Dataset / Transaction Service
  管 dataset branch、transaction、view、schema、build metadata

Lineage Service
  管 transform input/output、analysis dependency、dataset-to-dataset graph

Propagation Engine
  在 build 和 marking change 时计算下游 effective requirements

Authorization Gateway / PDP
  在 preview、query、export、API、OSDK 等入口统一鉴权

Approval Service
  管 protected branch、required approver、remove marking / expand access 审批

Audit Service
  记录 apply、remove、member change、approval、read allowed/denied
```

这不是官方披露的内部模块名，而是从能力边界推出的工程分层。

### 11.6 推断：内部数据结构可能接近 requirement 图

为了支持直接应用、父级继承、血缘传播、停止传播、访问解释和影响模拟，内部数据结构大概率不是单个 `dataset.markings` 字段，而更像 requirement graph：

```text
resource_requirement
  resource_rid
  requirement_type        # MARKING / ORGANIZATION / CLASSIFICATION
  requirement_id
  source_type             # DIRECT / PARENT
  source_resource_rid

dataset_view_requirement 或 transaction_requirement
  dataset_rid
  transaction_rid / view_rid
  requirement_type
  requirement_id
  source_type             # LINEAGE / OUTPUT_DIRECT
  source_input_dataset_rid
  source_input_transaction_rid
```

是否真的叫 `transaction_requirement` 不确定，但必须存在某种等价机制，否则无法同时支持：

- 历史 transaction 保留旧访问要求。
- 新 transaction 应用 unmarking 后访问要求变化。
- Data Lineage 解释上游哪个 Dataset 限制了当前数据读取。
- Marking change simulation 判断哪些下游资源会受影响。

### 11.7 推断：Build-time propagation 的实现形态

Transform 构建输出 Dataset 时，Marking 传播大概率发生在 output transaction commit 前后：

```text
Build starts
  -> Resolve input dataset views / transactions
  -> Read input effective resource requirements
  -> Read input data requirements
  -> Read output resource requirements
  -> Apply approved stop_propagating / stop_requiring rules
  -> Commit output transaction
  -> Persist output data requirements
  -> Persist lineage edges
  -> Emit audit / lineage update events
```

抽象公式：

```text
output_requirements =
    output_resource_requirements
  ∪ input_1_requirements
  ∪ input_2_requirements
  ∪ ...
  - approved_removed_requirements
```

多输入场景是关键边界：

```text
A carries PII
B carries PII
Transform(A, B) -> C

Only A stop_propagating PII
=> B still contributes PII
=> C still requires PII
```

因此 Palantir 的 `stop_propagating` 从语义上更像“停止某个 input 对 output 的 requirement 贡献”，而不是“从 output 全局删除某个 Marking”。

### 11.8 公开事实：停止传播必须走受控审批

Palantir 支持：

```text
stop_propagating
  移除 inherited Markings

stop_requiring
  移除 inherited Organizations
```

但这类操作会扩大访问范围，所以不是普通代码变更。公开文档要求 protected branch、required approver，并且移除 Marking 需要 Remove marking 权限，移除 Organization 需要 Expand access 权限。

抽象流程：

```text
Engineer creates branch
  -> Declares stop_propagating / stop_requiring
  -> Opens PR or branch change
  -> Security approver reviews
  -> Approver permission checked
  -> Protected branch build runs
  -> New output transaction no longer inherits selected requirement
  -> Audit event recorded
```

### 11.9 推断：Query-time enforcement 读取物化结果

查询时不适合临时重算全量 lineage。更合理的实现是读取已物化的 requirements：

```text
required_for_read =
    resource_effective_requirements(dataset_resource)
  ∪ data_requirements(dataset_view)
```

然后和用户上下文比较：

```text
user_context =
    resource roles
  + marking memberships
  + group-derived marking memberships
  + organization memberships
  + classification clearance
  + scoped session
```

普通 Marking 判定可抽象为：

```text
required_markings ⊆ user_markings
```

完整读取判定：

```text
can_read =
    has_view_role
AND all_required_markings_satisfied
AND organization_requirement_satisfied
AND classification_requirement_satisfied
AND scoped_session_satisfied
```

### 11.10 设计启示

如果基于 Dataset 自己实现类似能力，核心不是照搬 Palantir 页面，而是复刻它的控制闭环：

```text
Marking 管理
  -> Apply Marking
  -> Resource requirement 物化
  -> Build-time lineage propagation
  -> Transaction / view requirement 持久化
  -> Query-time enforcement
  -> Unmarking approval
  -> Audit + WhyDenied + Impact Simulation
```

最低实现不要停在：

```text
dataset.markings = [...]
```

而要做到：

```text
resource_requirement + transaction_requirement + lineage propagation + query-time PDP
```

### 11.11 公开来源

- Palantir Markings: `https://www.palantir.com/docs/foundry/security/markings/`
- Manage markings: `https://www.palantir.com/docs/foundry/platform-security-management/manage-markings`
- Remove inherited Markings and Organizations: `https://www.palantir.com/docs/foundry/building-pipelines/remove-inherited-markings`
- Guidance on removing markings: `https://www.palantir.com/docs/foundry/building-pipelines/remove-markings`
- Data Lineage - Check resource permissions: `https://www.palantir.com/docs/foundry/data-lineage/check-permissions`
- API - Get Access Requirements: `https://www.palantir.com/docs/foundry/api/filesystem-v2-resources/resources/get-access-requirements`

---

## 12. Marking 传递与计算详细设计

### 12.1 三个计算时机

Marking 计算不要放进一个大函数里。更稳妥的拆法是按时机分成三类：

| 时机 | 输入 | 输出 | 是否持久化 | 目标 |
|---|---|---|---|---|
| Apply-time | 用户、资源、Marking | direct resource requirement | 是 | 记录资源被直接要求哪些 Marking |
| Build-time | input transactions、resource requirements、unmarking rules | output transaction requirements | 是 | 让敏感要求随数据血缘传播 |
| Query-time | 用户 entitlements、resource requirements、transaction requirements | allow / deny / missing requirements | 否，只写审计 | 快速判定用户能否读取 |

这三个时机对应三类问题：

```text
Apply-time：这个 Project / Dataset 被加了什么访问要求。
Build-time：这个 output transaction 从上游继承了什么访问要求。
Query-time：这个用户是否满足当前 resource + data requirements。
```

### 12.2 Apply-time：Marking 应用过程

给资源应用 Marking 时，本质是新增一条 direct requirement，而不是写普通标签。

```text
User apply marking
  -> 校验用户对 resource 有 Update Markings / Owner 类权限
  -> 校验用户对 marking 有 APPLY 权限
  -> 写 resource_direct_requirement
  -> 重算 resource_effective_requirement
  -> 触发 downstream impact simulation
  -> 写 audit log
```

伪代码：

```python
def apply_marking(user, resource_id, marking_id):
    if not resource_role_service.allows(user, resource_id, "UPDATE_MARKINGS"):
        raise Deny("missing resource permission")

    if not marking_role_service.allows(user, marking_id, "APPLY"):
        raise Deny("missing marking apply permission")

    requirement_service.add_direct_requirement(
        resource_id=resource_id,
        requirement_type="MARKING",
        requirement_id=marking_id,
        source_type="DIRECT",
        source_resource_id=resource_id,
    )

    requirement_service.recompute_resource_effective_requirements(resource_id)
    lineage_service.enqueue_downstream_impact_scan(resource_id)

    audit.log(
        event="resource_marking_added",
        actor=user.id,
        resource_id=resource_id,
        marking_id=marking_id,
    )
```

验收点：

- `APPLY` 权限和资源 `UPDATE_MARKINGS` 权限都必须满足。
- Marking member 不等于可以 apply marking。
- Marking admin 不等于自动拥有该 Marking 的数据访问资格。
- 变更后要能解释 direct requirement 和 inherited requirement 的来源。

### 12.3 Resource hierarchy：资源层传递

资源层传播沿 Project / folder / resource 父子树生效。

```text
Project: Finance
  direct requirement: FINANCE

Folder: raw/
  inherited requirement: FINANCE

Dataset: raw/customer
  inherited requirement: FINANCE
```

计算公式：

```text
effective_resource_requirements(resource) =
    direct_requirements(resource)
  ∪ effective_resource_requirements(parent(resource))
```

伪代码：

```python
def compute_effective_resource_requirements(resource_id):
    resource = resource_service.get(resource_id)
    direct = requirement_service.get_direct_requirements(resource_id)

    if resource.parent_resource_id is None:
        inherited = set()
    else:
        inherited = compute_effective_resource_requirements(resource.parent_resource_id)

    return normalize_requirements(direct | inherited)
```

工程实现上不建议查询时递归。更适合维护物化表：

```text
resource_effective_requirement
  resource_id
  requirement_type
  requirement_id
  source_type          # DIRECT / PARENT
  source_resource_id
  requirement_version
```

当 Project / folder 的 Marking 变化时：

```text
Parent requirement changed
  -> 找到所有 descendant resources
  -> 重算 descendant resource_effective_requirement
  -> 找到 descendant datasets
  -> 标记 downstream data requirements 需要 impact scan 或 rebuild
```

### 12.4 Build-time：数据血缘传递

数据血缘传播是防止下游绕权的核心。构建 output transaction 前，需要把每个 input 的访问要求合并到 output。

```text
BuildRun start
  -> resolve input dataset views
  -> resolve input transactions
  -> 读取 input resource effective requirements
  -> 读取 input transaction requirements
  -> 合并 carried requirements
  -> 应用 approved unmarking rules
  -> 执行 transform
  -> commit output transaction 前写 transaction_requirement
  -> 写 lineage_edge
  -> audit
```

关键公式：

```text
carried_requirements(input) =
    effective_resource_requirements(input.dataset_resource)
  ∪ transaction_requirements(input.transaction)

output_transaction_requirements =
    effective_resource_requirements(output.dataset_resource)
  ∪ union(carried_requirements(each_input) - approved_unmarking_rules)
```

伪代码：

```python
def compute_output_transaction_requirements(build_run):
    output = build_run.output_dataset
    branch = build_run.branch

    output_direct = requirement_service.get_effective_resource_requirements(
        output.resource_id
    )

    inherited = set()

    for input_ref in build_run.inputs:
        input_view = dataset_service.resolve_view(
            dataset_id=input_ref.dataset_id,
            branch=input_ref.branch,
            transaction_selector=input_ref.selector,
        )

        input_resource_reqs = requirement_service.get_effective_resource_requirements(
            input_view.dataset_resource_id
        )

        input_data_reqs = requirement_service.get_transaction_requirements(
            input_view.transaction_id
        )

        carried = input_resource_reqs | input_data_reqs

        approved_removals = unmarking_service.get_approved_rules(
            branch=branch,
            input_dataset_id=input_view.dataset_id,
            output_dataset_id=output.dataset_id,
        )

        filtered = remove_requirements(carried, approved_removals)

        inherited |= annotate_source(
            filtered,
            source_input_dataset_id=input_view.dataset_id,
            source_input_transaction_id=input_view.transaction_id,
        )

    return normalize_requirements(output_direct | inherited)
```

这里的 `normalize_requirements` 要保留来源，而不只是去重：

```python
def normalize_requirements(requirements):
    result = {}

    for req in requirements:
        key = (req.requirement_type, req.requirement_id)
        if key not in result:
            result[key] = req
        else:
            result[key].sources += req.sources

    return set(result.values())
```

否则 Access Debugger 无法回答“这个 PII requirement 是哪个 input 带来的”。

### 12.5 下游是否都被打上具体 Marking

结论：Marking 沿血缘传递时，每一个下游数据版本都会继承对应访问要求；但这不等于每个下游 Dataset 都被写入一条 direct marking。

正确拆法是：

```text
Direct marking
  人工或系统直接应用在 Project / Folder / Dataset 上的 Marking。

Inherited resource requirement
  从父级 Project / Folder 继承到资源上的要求。

Inherited data requirement
  从上游 Dataset / transaction 经 lineage 传播到下游 transaction / view 的要求。
```

例如：

```text
Dataset A: customer_raw
  direct marking: PII

Dataset B: customer_clean
  direct marking: none
  transaction requirement: PII
  source: A.transaction_001

Dataset C: customer_city_count
  direct marking: none
  transaction requirement: PII
  source: B.transaction_001
```

因此页面或 API 上应该能表达：

```text
B requires PII
source = lineage from A
direct = false
```

而不是把 B 简化成：

```text
B.direct_markings = [PII]
```

这样做有三个好处：

- 可以解释 Marking 来源。
- 可以区分资源直接打标和数据血缘继承。
- 可以让新 transaction 移除继承要求，而不改写历史 transaction。

### 12.6 案例一：普通血缘传播

数据链路：

```text
A: customer_raw
  direct marking: PII

B: customer_clean = clean(A)

C: customer_city_count = aggregate(B)
```

没有 `stop_propagating` 时：

```text
A.tx1 requires PII
B.tx1 inherits PII from A.tx1
C.tx1 inherits PII from B.tx1
```

结果：

| Dataset | Direct Marking | Transaction Requirement | 用户读取要求 |
|---|---|---|---|
| A | PII | PII 或 resource PII | Viewer + PII |
| B | 无 | PII | Viewer + PII |
| C | 无 | PII | Viewer + PII |

注意：即使 C 只是城市级聚合，如果没有显式声明并审批移除 PII，系统也应保守继承 PII。

### 12.7 案例二：多输入合并

数据链路：

```text
A: customer_raw
  Marking: PII

F: finance_raw
  Marking: FINANCE

J: customer_finance_join = join(A, F)
```

计算：

```text
carried(A) = {PII}
carried(F) = {FINANCE}

J.tx1 = {PII} ∪ {FINANCE}
      = {PII, FINANCE}
```

读取 J 需要：

```text
Viewer + PII + FINANCE
```

普通 Marking 按 all-of 处理，所以用户必须同时满足 PII 和 FINANCE。

### 12.8 案例三：脱敏后停止传播

数据链路：

```text
A: customer_raw
  Marking: PII

B: customer_deidentified = drop(name, phone, id_card) from A
  stop_propagating PII approved
```

计算：

```text
carried(A) = {PII}
approved_unmarking_rules(A -> B) = {PII}

B.tx1 = carried(A) - {PII}
      = {}
```

结果：

| Dataset / Transaction | Requirement |
|---|---|
| A.tx1 | PII |
| B.tx1 | 无 PII |

这只影响新 output transaction，不应改写 B 的旧 transaction。

### 12.9 案例四：多输入 stop 一个不够

数据链路：

```text
A: customer_raw
  Marking: PII

B: support_ticket_raw
  Marking: PII

C = transform(A, B)

只声明：
  stop_propagating PII on A -> C
```

计算：

```text
carried(A) = {PII}
carried(B) = {PII}

remove(A -> C) = {PII}
remove(B -> C) = {}

C.tx1 = (carried(A) - {PII})
      ∪ (carried(B) - {})
      = {}
      ∪ {PII}
      = {PII}
```

所以 C 仍然要求 PII。要让 C 不带 PII，必须对所有携带 PII 的 input 都声明并审批：

```text
stop_propagating PII on A -> C
stop_propagating PII on B -> C
```

### 12.10 示例代码：简化版 Marking 传播引擎

下面代码演示 resource requirement、transaction requirement、多输入合并和 input-specific unmarking 的计算方式：

```python
from dataclasses import dataclass, field
from typing import Dict, List, Set, Tuple


Requirement = str
DatasetId = str
TxId = str


@dataclass
class Dataset:
    id: DatasetId
    resource_requirements: Set[Requirement] = field(default_factory=set)


@dataclass
class Transaction:
    id: TxId
    dataset_id: DatasetId
    requirements: Set[Requirement] = field(default_factory=set)


@dataclass
class InputRef:
    dataset_id: DatasetId
    tx_id: TxId


@dataclass
class BuildRun:
    output_dataset_id: DatasetId
    output_tx_id: TxId
    inputs: List[InputRef]


class MarkingEngine:
    def __init__(self):
        self.datasets: Dict[DatasetId, Dataset] = {}
        self.transactions: Dict[Tuple[DatasetId, TxId], Transaction] = {}
        self.approved_unmarking_rules: Dict[
            Tuple[DatasetId, DatasetId],
            Set[Requirement],
        ] = {}

    def add_dataset(self, dataset_id: DatasetId, resource_requirements=None):
        self.datasets[dataset_id] = Dataset(
            id=dataset_id,
            resource_requirements=set(resource_requirements or []),
        )

    def add_transaction(self, dataset_id: DatasetId, tx_id: TxId, requirements=None):
        self.transactions[(dataset_id, tx_id)] = Transaction(
            id=tx_id,
            dataset_id=dataset_id,
            requirements=set(requirements or []),
        )

    def approve_unmarking(
        self,
        input_dataset_id: DatasetId,
        output_dataset_id: DatasetId,
        markings: Set[Requirement],
    ):
        self.approved_unmarking_rules[
            (input_dataset_id, output_dataset_id)
        ] = set(markings)

    def carried_requirements(self, input_ref: InputRef) -> Set[Requirement]:
        dataset = self.datasets[input_ref.dataset_id]
        tx = self.transactions[(input_ref.dataset_id, input_ref.tx_id)]
        return dataset.resource_requirements | tx.requirements

    def compute_output_requirements(self, build: BuildRun) -> Set[Requirement]:
        output_dataset = self.datasets[build.output_dataset_id]
        output_requirements = set(output_dataset.resource_requirements)

        for input_ref in build.inputs:
            carried = self.carried_requirements(input_ref)
            stopped = self.approved_unmarking_rules.get(
                (input_ref.dataset_id, build.output_dataset_id),
                set(),
            )
            output_requirements |= carried - stopped

        return output_requirements

    def commit_build(self, build: BuildRun):
        requirements = self.compute_output_requirements(build)
        self.add_transaction(
            dataset_id=build.output_dataset_id,
            tx_id=build.output_tx_id,
            requirements=requirements,
        )
        return requirements
```

运行普通传播：

```python
engine = MarkingEngine()

engine.add_dataset("customer_raw", resource_requirements={"PII"})
engine.add_transaction("customer_raw", "tx1")

engine.add_dataset("customer_clean")
build_clean = BuildRun(
    output_dataset_id="customer_clean",
    output_tx_id="tx1",
    inputs=[InputRef("customer_raw", "tx1")],
)

print(engine.commit_build(build_clean))
```

输出：

```text
{'PII'}
```

运行多输入合并：

```python
engine.add_dataset("finance_raw", resource_requirements={"FINANCE"})
engine.add_transaction("finance_raw", "tx1")

engine.add_dataset("customer_finance_join")
build_join = BuildRun(
    output_dataset_id="customer_finance_join",
    output_tx_id="tx1",
    inputs=[
        InputRef("customer_clean", "tx1"),
        InputRef("finance_raw", "tx1"),
    ],
)

print(engine.commit_build(build_join))
```

输出：

```text
{'PII', 'FINANCE'}
```

运行脱敏后停止传播：

```python
engine.add_dataset("customer_deidentified")
engine.approve_unmarking(
    input_dataset_id="customer_raw",
    output_dataset_id="customer_deidentified",
    markings={"PII"},
)

build_deid = BuildRun(
    output_dataset_id="customer_deidentified",
    output_tx_id="tx1",
    inputs=[InputRef("customer_raw", "tx1")],
)

print(engine.commit_build(build_deid))
```

输出：

```text
set()
```

运行多输入 stop 一个不够：

```python
engine.add_dataset("support_ticket_raw", resource_requirements={"PII"})
engine.add_transaction("support_ticket_raw", "tx1")

engine.add_dataset("combined_clean")
engine.approve_unmarking(
    input_dataset_id="customer_raw",
    output_dataset_id="combined_clean",
    markings={"PII"},
)

build_combined = BuildRun(
    output_dataset_id="combined_clean",
    output_tx_id="tx1",
    inputs=[
        InputRef("customer_raw", "tx1"),
        InputRef("support_ticket_raw", "tx1"),
    ],
)

print(engine.commit_build(build_combined))
```

输出：

```text
{'PII'}
```

读取时计算：

```python
def can_read(user_markings: Set[str], dataset: Dataset, tx: Transaction) -> bool:
    required = dataset.resource_requirements | tx.requirements
    return required.issubset(user_markings)


tx = engine.transactions[("customer_finance_join", "tx1")]

print(can_read({"PII"}, engine.datasets["customer_finance_join"], tx))
print(can_read({"PII", "FINANCE"}, engine.datasets["customer_finance_join"], tx))
```

输出：

```text
False
True
```

结论：

```text
每个下游数据版本都会继承 required markings，
但这些 markings 不一定是 direct markings。
```

实现上应落成：

```text
direct marking
  -> resource_direct_requirement

父级继承
  -> resource_effective_requirement

血缘继承
  -> transaction_requirement

读取判定
  -> resource_effective_requirement ∪ transaction_requirement
```

### 12.11 Unmarking：传播中断计算

传播中断不能设计成“从 output 上删除某个 Marking”。它必须是 input-specific 规则：

```text
unmarking_rule =
  branch
  input_dataset_id
  output_dataset_id
  requirement_type
  requirement_id
  status
  approved_by
```

原因是多输入场景里，一个 input 停止传播，不代表其他 input 不再携带同一个 Marking。

```text
Dataset A: PII
Dataset B: PII

Transform(A, B) -> Dataset C

只对 A stop_propagating PII
但 B 仍然贡献 PII
所以 C 仍然必须要求 PII
```

审批流程：

```text
Engineer declares stop_propagating
  -> 创建 unmarking_rule
  -> 校验目标 branch 是否 protected
  -> Security approver 审批
  -> 校验 approver 是否有该 Marking 的 REMOVE 权限
  -> rule APPROVED
  -> build-time propagation 生效
```

伪代码：

```python
def approve_unmarking_rule(approver, rule_id):
    rule = unmarking_service.get(rule_id)

    if not branch_service.is_protected(rule.branch):
        raise Deny("unmarking must target protected branch")

    if rule.requirement_type == "MARKING":
        if not marking_role_service.allows(approver, rule.requirement_id, "REMOVE"):
            raise Deny("missing marking remove permission")

    rule.status = "APPROVED"
    rule.approved_by = approver.id
    audit.log("unmarking_rule_approved", rule_id=rule_id, actor=approver.id)
```

Build-time 应用：

```python
def remove_requirements(carried, approved_rules):
    removed_keys = {
        (rule.requirement_type, rule.requirement_id)
        for rule in approved_rules
        if rule.status == "APPROVED"
    }

    return {
        req for req in carried
        if (req.requirement_type, req.requirement_id) not in removed_keys
    }
```

### 12.12 Query-time：读取时 Marking 计算

读取路径不要重新推导 lineage。读取时应只读取已经物化好的 requirements：

```text
required_for_read =
    effective_resource_requirements(dataset_resource)
  ∪ transaction_requirements(dataset_view.transaction)
```

用户拥有的 Marking：

```text
user_markings =
    direct_marking_memberships(user)
  ∪ marking_memberships_from_groups(user.groups)
```

普通 Marking 判定：

```text
missing_markings = required_markings - user_markings
```

完整伪代码：

```python
def authorize_dataset_read(user, dataset_view):
    dataset = dataset_service.get(dataset_view.dataset_id)

    if not role_service.allows(user, dataset.resource_id, "VIEW"):
        return deny("MISSING_RESOURCE_ROLE")

    resource_reqs = requirement_service.get_effective_resource_requirements(
        dataset.resource_id
    )

    data_reqs = requirement_service.get_transaction_requirements(
        dataset_view.transaction_id
    )

    required = normalize_requirements(resource_reqs | data_reqs)
    user_ctx = entitlement_service.resolve(user)

    missing_markings = required.markings - user_ctx.markings
    if missing_markings:
        return deny("MISSING_MARKINGS", missing_markings)

    if required.organizations:
        if not required.organizations & user_ctx.organizations:
            return deny("MISSING_ORGANIZATION", required.organizations)

    if required.classification:
        if not cbac_service.satisfies(user_ctx, required.classification):
            return deny("MISSING_CLASSIFICATION", required.classification)

    audit.log("dataset_read_allowed", user=user.id, dataset=dataset.id)
    return allow()
```

读取路径的验收点：

- Query engine、preview、export、API、OSDK、AIP 都必须走同一套 PDP。
- Deny 结果要返回可解释原因，而不是只返回 forbidden。
- 权限判定不能信任前端 UI 的显示状态。
- scoped session 只能收窄用户当前可用 Markings，不能扩大访问。

### 12.13 事件流

推荐把计算拆成事件驱动链路：

```text
MarkingApplied
  -> RecomputeResourceRequirements
  -> DownstreamImpactSimulation
  -> MarkDatasetsStaleForRequirementReview

BuildStarted
  -> ResolveInputTransactions
  -> ComputeOutputRequirements
  -> CommitOutputTransaction
  -> WriteLineageEdges
  -> EmitDatasetRequirementChanged

UnmarkingRuleApproved
  -> RebuildAffectedOutputs
  -> RecomputeDownstreamRequirements

DatasetReadRequested
  -> ResolveUserEntitlements
  -> LoadEffectiveRequirements
  -> PDPDecision
  -> Audit
```

### 12.14 容易做错的边界

| 错误设计 | 风险 | 正确做法 |
|---|---|---|
| 只在 Dataset 上存当前 Marking | 旧 transaction 和新 transaction 权限混淆 | requirement 绑定 transaction / view |
| 下游只继承 input transaction requirement | 上游 Project / folder Marking 可能被绕过 | carried requirements 同时包含 input resource + input transaction |
| unmarking 做成 output 全局删除 | 多输入场景误删其他 input 的 Marking | unmarking 绑定 input -> output -> requirement |
| 读取时重新计算全量 lineage | 查询慢且不稳定 | Build-time 物化，query-time 判定 |
| Marking admin 默认也是 member | 管理权限变成数据访问资格 | admin / apply / remove / member 分离 |
| 只返回 forbidden | 排障和权限申请困难 | 提供 whyDenied / missing requirements |

---

## 13. 自建平台成熟度分层

| 层级 | 能力 | 结果 |
|---|---|---|
| L0 | Dataset ACL | 只能控制资源访问，无法治理敏感数据传播 |
| L1 | Project role + group | 能做协作授权，但敏感数据资格仍不完整 |
| L2 | Marking 管理 + Dataset direct marking + query-time enforcement | 能限制带标资源，但没有血缘传播 |
| L3 | Lineage-aware propagation + data requirements | 能治理派生数据，是 Foundry 式权限的核心分水岭 |
| L4 | Protected branch unmarking + transaction-level requirements + Restricted View + SDS + Audit | 具备生产级治理闭环 |

最低可用目标不应停在 L2。否则下游 Dataset 很容易绕过上游敏感数据要求。

---

## 14. 常见误区

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

## 15. 对我们的建设建议

1. 先统一 Dataset、Resource、Branch、Transaction、Lineage 的元模型，再补 Marking。
2. Marking 不要做成普通标签字段，必须进入鉴权、构建、查询、审批和审计链路。
3. Resource requirement 和 Data requirement 要分开建模，否则无法解释“看得到资源但读不了数据”。
4. Lineage propagation 是核心分水岭，没有它就不是 Foundry 式治理。
5. 移除继承权限必须产品化为审批流程，而不是代码注释或人工约定。
6. 权限系统必须提供解释接口，例如 `getAccessRequirements`、`whyDenied`、`simulateMarkingImpact`。
7. SDS、Restricted View、Ontology property security 应作为 L4 能力逐步接入，而不是第一阶段全部堆上。

---

## 16. HTML 展示口径

站点页面应突出五个阅读重点：

1. Dataset 访问为什么是多层判定，而不是单一 RBAC。
2. Role、Organization、Marking、Data Requirement 的边界。
3. Marking 如何沿资源层级和数据血缘传播。
4. Marking 在 apply-time、build-time、query-time 三个时机如何计算。
5. 自建平台要如何落控制面、构建链路、查询链路、审批链路和审计链路。

页面不需要复刻原始调研的全部 API 和 SQL 模型，完整证据和实现细节继续指向 `docs/raw/30-dataset-permission-marking-architecture.md`。
