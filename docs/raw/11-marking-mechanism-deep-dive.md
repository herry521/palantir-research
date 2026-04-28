# Palantir Foundry Marking 机制深度调研

**调研日期：** 2026-04-18
**调研方向：** Marking 原理 / 传播机制 / 与 Ontology 的交互 / 代码实现 / 运维实践

---

## 一、Marking 的本质定位

### 1.1 MAC vs DAC

Foundry 的访问控制体系分两个正交维度：

```
资源访问 = MAC 门槛（必须满足）AND DAC 权限（角色授权）

MAC（强制访问控制）：Marking / Classification / Organization
    └── 平台强制执行，资源所有者无法绕过
    └── 管理员集中管控，用户无法自行修改

DAC（自主访问控制）：Role（Viewer/Editor/Manager 等）
    └── 资源所有者可自行授予
    └── 决定"可以做什么"（读/写/管理）
```

**核心规则**：用户必须同时满足 MAC 要求（持有所有相关 Marking）**且**持有 DAC 角色，才能访问资源。即便 Owner 角色也无法覆盖 Marking 限制。 [事实]

### 1.2 Marking 的关键特征

| 特征 | 说明 |
|---|---|
| **二元性** | 持有或不持有，无中间状态（不像角色可分级） |
| **全 AND 逻辑** | 资源有多个 Marking，用户必须持有全部才能访问 |
| **自动传播** | 数据流经 Transform，下游自动继承上游所有 Marking |
| **平台执行** | 无需应用层代码实现，平台 infra 层拦截 |
| **单向限制** | 只能限制访问，不能用于授予访问（这是 Role 的职责） |

---

## 二、Marking 分类体系

### 2.1 三类强制访问控制机制

Foundry 有三种并列的 MAC 机制，职责不同：

```
┌─────────────────────────────────────────────────────────────────┐
│                    强制访问控制（MAC）                            │
│                                                                 │
│  ┌───────────────────┐  ┌─────────────────┐  ┌──────────────┐  │
│  │     Markings      │  │  Organizations  │  │Classifications│  │
│  │                   │  │                 │  │              │  │
│  │ 数据敏感标签      │  │ 组织归属隔离    │  │ 层级密级管控 │  │
│  │ 如 PII、机密      │  │ 部门/公司隔离   │  │ 如保密/机密  │  │
│  │ 跨组织均可配置    │  │ 通常1用户1主组织│  │ 政府场景专用 │  │
│  └───────────────────┘  └─────────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Marking 内部逻辑：合取 vs 析取

**Marking Category（标记类别）** 是 Marking 的组织单元，决定访问逻辑：

| 类型 | 逻辑 | 场景 |
|---|---|---|
| **合取（Conjunctive，AND）** | 用户必须持有该类别下所有 Marking | 同时需要 PII 权限 AND 财务数据权限 |
| **析取（Disjunctive，OR）** | 用户持有该类别下任意一个 Marking 即可 | 属于国家 A OR 国家 B 的用户均可访问 |

**资源级别的逻辑**：
- 多个 Marking Category 之间：**AND**（每个类别必须满足）
- 单个 Category 内部：**AND 或 OR**（取决于 Category 类型配置）

**示例**：
```
资源 R 的 Marking 配置：
  Category 1（合取）：[PII, Finance]       → 用户必须同时持有 PII 和 Finance
  Category 2（析取）：[CountryA, CountryB]  → 用户持有 CountryA 或 CountryB 其一即可

访问判断：满足 Category 1 AND 满足 Category 2
```

### 2.3 Classification Marking（政府/军事场景）

Classification 是 Marking 的特殊形式，用于**层级化密级管控**：

```
UNCLASSIFIED（非密）
    │
    ▼
CONFIDENTIAL（秘密）
    │
    ▼
SECRET（机密）
    │
    ▼
TOP SECRET（绝密）
```

- 用户持有某层级 Clearance，可访问该层级及以下所有资源
- 需要 Palantir 侧专门配置，不是 Foundry 默认功能（需 CBAC 模块）
- 层级之间可叠加析取逻辑（如 TS/SCI 中的 Compartments）

---

## 三、Marking 传播机制（核心）

### 3.1 传播规则

**黄金法则：下游资源的数据分类 ≥ 所有上游资源分类的并集** [事实]

```
Dataset A（Marking: PII）
Dataset B（Marking: Finance）
         │
         ▼
    Transform T
         │
         ▼
Dataset C（自动继承 Marking: PII + Finance）
         │
         ▼
    Transform T2
         │
         ▼
Dataset D（自动继承 Marking: PII + Finance）
```

传播路径：
1. **血缘依赖传播**：Transform 读取有 Marking 的 Dataset，输出自动继承
2. **文件层级传播**：Folder/Project 上的 Marking 向下传给所有子资源
3. **不可逆（默认）**：传播后的 Marking 不会因下游 Transform 逻辑而自动消失

### 3.2 传播模拟（操作前必做）

在 **Data Lineage App** 中操作，避免意外锁定下游用户：

```
操作流程：
1. 打开 Data Lineage 应用，选中目标 Dataset
2. 开启「Simulate access requirements」模拟模式
3. 点击「Edit markings」→ 勾选/取消 Marking → 点击「Simulate changes」
4. 检查图中标色：
   - 蓝色：直接应用变更的节点
   - 橙色：受影响（访问权限变化）的下游节点
   - 灰色：未受影响的节点
5. 确认无误后再实际应用
```

**关键约束**：只有直接施加在 Dataset 上的 Marking 可以模拟移除，继承来的 Marking 不可模拟移除（因为源头在上游）。

### 3.3 停止传播：`stop_propagating`

当下游 Transform 对数据进行了脱敏处理（如 PII 字段已哈希化），可以在 Code Repository 中使用 `stop_propagating` 阻止上游 Marking 继续向下传播：

```python
from transforms.api import transform, Input, Output, Markings

@transform(
    output=Output('/project/output/anonymized_users'),
    raw=Input(
        '/project/input/users_with_pii',
        stop_propagating=Markings(['PII'])   # 阻止 PII 标记传播到输出
    ),
)
def compute(raw, output):
    df = raw.dataframe()
    # 哈希化 PII 字段，输出不含原始 PII
    df = df.withColumn('phone_hash', hash_udf(df['phone']))
    df = df.drop('phone', 'id_card')
    output.write_dataframe(df)
```

**重要限制**：
- `stop_propagating` 只能在**受保护分支（Protected Branch）** 上生效；未保护分支执行会导致 Build 失败 [事实]
- 执行人必须持有对应 Marking 的 **「Remove Marking」权限** [事实]
- 执行后需重新 Build 该 Dataset 及所有下游 Dataset，新的 Marking 状态才生效 [事实]

### 3.4 停止 Organization 继承：`stop_requiring`

类似地，当需要移除 Organization 要求（扩大跨组织访问）时：

```python
from transforms.api import transform, Input, Output, OrgMarkings

@transform(
    output=Output('/shared/cross_org_dataset'),
    source=Input(
        '/org_a/sensitive_data',
        stop_requiring=OrgMarkings(['OrgA'])  # 移除 OrgA 的访问要求
    ),
)
def compute(source, output):
    # 将 OrgA 的数据发布到跨组织共享空间
    output.write_dataframe(source.dataframe())
```

**权限要求**：执行人必须持有 **「Expand Access」** 权限（Organization 级别权限，非普通用户持有）。

---

## 四、Marking 与 Ontology 的交互

### 4.1 Dataset Marking 向 Ontology 的延伸

当 Dataset 绑定到 Ontology Object Type 后，Marking 控制延伸至 Object 层：

```
Dataset（Marking: PII）
    │ [Ontology Manager 配置绑定]
    ▼
Object Type（如 UserProfile）
    │
    ├── 无 PII Marking 用户：看不到 UserProfile 对象（整行不可见）
    └── 有 PII Marking 用户：正常访问对象及所有属性
```

### 4.2 Ontology 特有的细粒度控制（超越 Marking）

Ontology 层额外提供两种更细粒度的控制，作为 Marking 的补充：

**Object Security Policy（行级）**：
```
场景：不同销售人员只能看到自己负责的客户
策略：user.region == object.region → 对象可见
实现：在 Ontology Manager 对 Object Type 配置 ObjectSecurityPolicy
效果：同一 Dataset 的不同用户看到不同的对象子集
```

**Property Security Policy（列级/属性级）**：
```
场景：普通员工可见客户名称，但工资字段只有 HR 可见
策略：user.hasRole('HR') → salary 属性可见，否则返回 null
实现：在 Ontology Manager 对特定 Property 配置 PropertySecurityPolicy
效果：未授权用户访问对象时，受控属性自动返回 null（而非报错）
```

### 4.3 三层安全控制的叠加关系

```
访问 Ontology Object 的完整判断逻辑：

Step 1：Dataset Marking 检查（MAC）
    用户未持有 Dataset 的 Marking → 整个 Object Type 不可见
    
Step 2：Object Security Policy 检查（行级）
    用户持有 Marking，但不满足 Object 过滤条件 → 该 Object 实例不可见
    
Step 3：Property Security Policy 检查（列级）
    用户可见该 Object，但未满足某属性策略 → 该属性返回 null
    
最终效果：细胞级安全控制（行 × 列 = 精确控制每个数据点）
```

---

## 五、Marking 管理操作

### 5.1 Marking 的生命周期管理

```
创建 Marking
  ↓ [平台管理员在 Platform Settings > Markings]
分配用户/组为 Marking 成员
  ↓ [标记成员可访问带该 Marking 的资源]
应用 Marking 到资源
  ↓ [资源 Owner 操作 OR 平台管理员操作]
监控传播范围
  ↓ [Data Lineage 模拟模式确认]
需要移除时
  ↓ [在 Code Repository 中用 stop_propagating + 受保护分支]
重建下游 Dataset
  ↓ [使新 Marking 状态生效]
```

### 5.2 权限层次说明

| 操作 | 所需权限 |
|---|---|
| 创建/删除 Marking Category | 平台管理员 |
| 创建 Marking | 平台管理员 |
| 将用户加入 Marking 成员 | Marking 管理员（"Manage permissions" on Marking） |
| 将 Marking 应用到资源 | 资源 Owner + 持有该 Marking 成员资格 |
| stop_propagating（移除 Marking 传播） | 持有 Marking 的 "Remove marking" 权限 |
| stop_requiring（移除 Organization 要求） | 持有 "Expand Access" 权限（Organization 级别） |

### 5.3 Marking 成员资格 vs Marking 管理权

两个概念容易混淆：

| 概念 | 含义 |
|---|---|
| **Marking 成员（Member）** | 持有该 Marking，可以访问带该 Marking 的资源 |
| **Marking 管理员（Manage permissions）** | 可以修改 Marking 的成员列表，但不一定自己是成员 |

实践中建议：Marking 管理员角色与成员角色分离，避免管理员因操作便利而意外自己持有所有高敏感 Marking。

---

## 六、Marking 在 Pipeline 工程实践中的常见问题

### 6.1 问题一：意外锁定下游用户

**现象**：给某 Dataset 加了 PII Marking 后，下游 N 个依赖这个 Dataset 的用户全部报"访问被拒"。

**原因**：Marking 自动传播，所有下游 Dataset 都继承了 PII Marking，而这些用户并非 PII Marking 成员。

**预防**：加 Marking 前必须用 Data Lineage 的模拟模式预览影响范围。

**修复**：
1. 短期：将受影响用户临时加入 PII Marking 成员（不推荐）
2. 长期：在传播链的合适位置增加 `stop_propagating`（脱敏后阻断）

### 6.2 问题二：增量 Transform 与 Marking 变更

**现象**：对上游 Dataset 修改了 Marking 后，下游增量 Transform 的输出 Marking 状态不一致（部分数据有 Marking，部分没有）。

**原因**：增量 Transform 只处理新 Transaction，历史 Transaction 写入时的 Marking 状态已固化在旧文件。

**解决**：修改 Marking 后，需要触发下游增量 Transform 的**全量重算（SNAPSHOT Build）**，确保所有历史数据的 Marking 状态一致。

### 6.3 问题三：stop_propagating 在未保护分支上失效

**现象**：在 feature 分支上写了 `stop_propagating`，Build 失败，提示 "stop_propagating not allowed on unprotected branch"。

**原因**：Foundry 安全机制要求 `stop_propagating` 必须经过 Code Review 审批（保护分支机制确保至少 N 人审核），防止开发者随意移除 Marking。

**解决**：将代码合并到受保护的 master 分支后执行，或为该分支开启保护策略（要求安全审批）。

### 6.4 问题四：Cipher 加密列与 Marking 传播的协调

**场景**：源 Dataset 有 PII Marking，下游 Transform 对 PII 字段加密（Cipher），输出数据已无明文 PII。

**问题**：加密后是否应该 stop_propagating PII Marking？

**最佳实践**：
- 如果输出中 PII 字段已完全被 Cipher 加密（只有持 Key 用户才能解密），**可以**在该 Transform 上 stop_propagating PII Marking
- 如果只是哈希化（不可逆但仍具标识性），**不建议**移除 PII Marking

---

## 七、Marking 审计与合规

### 7.1 审计日志记录的 Marking 相关事件

Foundry 审计日志会自动记录：

| 事件 | 记录内容 |
|---|---|
| 用户访问带 Marking 资源 | 用户 ID、资源 RID、时间戳、结果（成功/拒绝） |
| 访问被拒绝（缺少 Marking） | 缺少哪个 Marking 的详细信息 |
| Marking 成员变更 | 谁被加入/移除，操作人，时间 |
| stop_propagating 代码合并 | 代码 Commit 信息、审批人记录 |
| Marking 施加/移除到资源 | 操作人、资源、时间 |

### 7.2 审计日志消费方式

- 审计日志可导出到 Foundry Dataset（结构化分析）
- 可对接外部 SIEM 系统（Splunk、Elastic 等）
- 支持 "audit category" 过滤（如只看 `dataLoad`、`dataExport` 类事件）

### 7.3 合规报告场景

| 合规需求 | 利用 Marking 审计的方式 |
|---|---|
| 谁访问了 PII 数据 | 过滤 `resource has PII Marking AND access=success` |
| 是否有未授权访问尝试 | 过滤 `access=denied AND marking=PII` |
| PII Marking 成员变更历史 | 过滤 `event=marking_membership_change AND marking=PII` |
| 高密级数据的传播路径 | 结合 Data Lineage + Marking 传播模拟图 |

---

## 八、Marking 实现方案总结（全景图）

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            Marking 全景架构                                   │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  配置层（平台管理员）                                                          │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  Marking Category（合取/析取）                                        │   │
│  │    └── Marking 实例（PII / Finance / CountryA...）                   │   │
│  │          └── 成员列表（User / Group）                                 │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  应用层（资源所有者）                                                          │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  资源（Dataset / Folder / Project）                                   │   │
│  │    └── 施加 Marking → 平台自动向下游传播                               │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  传播控制层（数据工程师）                                                      │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  Code Repository Transform                                            │   │
│  │    └── Input(..., stop_propagating=Markings(['PII']))                 │   │
│  │    └── Input(..., stop_requiring=OrgMarkings(['OrgA']))               │   │
│  │    └── 必须在受保护分支 + 经过 Security Review 才能生效               │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  细粒度控制层（Ontology 工程师）                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  Ontology Object Type                                                 │   │
│  │    ├── Object Security Policy（行级过滤）                              │   │
│  │    └── Property Security Policy（列/属性级掩码）                      │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│  监控层                                                                      │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │  Data Lineage（传播模拟）+ Audit Log（访问记录）                       │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 九、关键结论

1. **Marking 是平台级强制控制，无法被角色覆盖**：即便 Dataset Owner，没有 Marking 成员资格也无法访问，这与传统 RBAC 体系有根本不同 [事实]
2. **传播机制是双刃剑**：自动传播确保敏感数据无遗漏保护，但也极易意外锁定大量下游用户，**加 Marking 前必须模拟** [事实]
3. **stop_propagating 是唯一的传播中断手段，且受严格保护**：必须经过受保护分支 + Security Review，这本身就是一道合规审批流程 [事实]
4. **Marking 与 Ontology 安全策略正交叠加**：Marking 控制"能否进入数据"，Object Security Policy 控制"能看哪些行"，Property Security Policy 控制"能看哪些列"，三层叠加实现细胞级安全 [事实]
5. **Classification（CBAC）是 Marking 的政府特化版本**：层级制 + 析取 Compartments，用于机密等级管控，非默认功能 [事实]
6. **增量 Transform 与 Marking 变更需要全量重算**：增量 Transform 历史 Transaction 的 Marking 状态已固化，必须触发 SNAPSHOT Build 使变更生效 [事实]
7. **管理员与成员分离是安全最佳实践**：Marking 管理员负责管成员列表，不一定自己是成员，避免特权蔓延 [推断]

---

## 参考资料

- Palantir Foundry Documentation: Markings and Mandatory Access Controls
- Palantir Foundry Documentation: Data Lineage Simulation Mode
- Palantir Foundry Documentation: stop_propagating / stop_requiring API
- Palantir Foundry Documentation: Ontology Object and Property Security Policies
- Palantir Foundry Documentation: Audit Logs and Compliance
