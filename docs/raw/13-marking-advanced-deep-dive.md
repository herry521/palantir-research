# Palantir Foundry Marking 机制进阶调研

**调研日期：** 2026-04-21
**调研方向：** SDS 自动打标 / Branch & Transaction 交互 / AIP & LLM 场景 / Marking Category 企业设计 / 规模性能

> 本文是 `11-marking-mechanism-deep-dive.md` 和 `12-dataset-marking-implementation.md` 的进阶补充，
> 聚焦五个前两篇未深入的方向。

---

## 一、SDS（Sensitive Data Scanner）自动打标机制

### 1.1 SDS 的定位

SDS 是 Foundry 的数据敏感扫描应用，核心价值在于：**将手动给 Dataset 打 Marking 的工作自动化**。
治理团队定义扫描规则，SDS 发现敏感数据后自动触发 Apply Marking、创建审查 Issue、或启动 Cipher 加密。

```
数据进入 Foundry（边界 Dataset）
    │
    ▼
SDS 扫描（按规则检测）
    │
    ├── 命中规则 → 触发 Match Action
    │       ├── Apply Marking（自动施加 Marking）
    │       ├── Create Issue（创建治理 Issue 供人工审查）
    │       └── Obfuscate Data（调用 Cipher 加密/哈希匹配字段）
    │
    └── 未命中 → 无动作
```

### 1.2 Match Condition（匹配条件）

SDS 支持两类匹配条件：

#### 正则表达式匹配（Regex Match Condition）

```
匹配维度：
  - 内容匹配（Content Regex）：匹配列的值内容
  - 列名匹配（Column Name Regex）：匹配列名模式

示例规则：
  列名 regex：(?i)(phone|mobile|tel)
  内容 regex：^1[3-9]\d{9}$          → 匹配中国手机号
  内容 regex：\d{17}[\dXx]           → 匹配身份证号
  内容 regex：[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,} → 邮箱
```

Foundry AIP（内置 LLM）可以辅助生成有效的 regex 表达式，降低规则编写门槛。

#### 重叠匹配（Overlap Match Condition）

```
机制：将目标列的值与一个"已知敏感数据集"的值取交集
适用场景：
  - 人名、地名等难以用 regex 精确描述的数据
  - 内部员工 ID 列表、高管姓名等需要精确比对的场景

示例：
  参考 Dataset：/governance/known_executive_names（高管名单）
  扫描目标：订单表的 customer_name 列
  规则：若 customer_name ∈ known_executive_names → 触发 Action
```

### 1.3 Match Action（匹配动作）

| 动作 | 说明 | 适用场景 |
|---|---|---|
| **Apply Marking** | 自动对 Dataset 施加指定 Marking | 边界数据入湖时自动分类 |
| **Create Issue** | 在 Foundry Issue Tracker 创建待处理 Issue | 需人工审查确认后再打标 |
| **Obfuscate Data** | 调用 Cipher 对匹配字段执行加密/哈希 | 直接在源头脱敏 |

多个动作可组合使用：如"同时创建 Issue + 自动 Apply Marking"，既保证立即访问控制，又保留人工复核记录。

### 1.4 扫描配置与调度

```
扫描触发方式：
  1. 一次性扫描（One-time Scan）：手动触发，用于历史数据盘查
  2. 定时扫描（Scheduled Scan）：配置 cron 表达式，如每天 2:00 AM 扫描边界数据集

扫描范围最佳实践：
  - 优先扫描"边界数据集"（数据进入 Foundry 的第一层 Dataset）
  - 跳过已打 Marking 的派生数据（避免重复扫描，降低计算成本）
  - 跳过已知安全的内部生成数据

扫描 Media Set（非结构化数据）：
  - 图片/PDF → OCR 转文本 → 再跑 regex
  - 音频 → 转录为文本 → 再跑 regex
  - 性能优化：对 Media Set 启用子集采样（Subset Sampling），不必全量扫描
```

### 1.5 SDS 的权限与启用

```
启用路径：Control Panel → Organization → Application Access → SDS（Security & Governance 分区）

操作权限：
  - 配置扫描规则：治理管理员（Organization Admin）
  - 查看扫描结果：Marking 成员 + 有资源只读权限的用户
  - Apply Marking 动作的执行身份：SDS 服务账号（需预授权为 Marking 管理员）
```

### 1.6 SDS 与手动打标的协作模式

```
推荐工作流（分层防御）：

第一层（SDS 自动）：
  边界 Dataset 进入 → SDS 扫描 → 命中则自动 Apply Marking
  → 同时 Create Issue 通知治理团队

第二层（人工确认）：
  治理团队处理 Issue：
    ① 确认打标正确 → 关闭 Issue
    ② 误报 → 在 Issue 中记录原因 → 手动移除 Marking

第三层（stop_propagating 管控）：
  数据工程师对已脱敏的下游数据通过受保护分支 + stop_propagating 阻断传播
```

---

## 二、Marking 与 Branch/Transaction 的交互

### 2.1 Foundry 数据版本化基础

Foundry 的 Dataset 存储本质上是**不可变 Transaction 序列**，类比 Git commit 历史：

```
Dataset 版本模型：
  Transaction T1（Snapshot）  ← 初始写入
  Transaction T2（Append）    ← 增量追加
  Transaction T3（Snapshot）  ← 全量重刷
  Transaction T4（Append）    ← 增量追加
       │
       ▼
  "当前视图" = 最新有效 Transaction 所指向的数据
```

Branch 是对 Transaction 序列的分叉，不触发数据复制（写时复制语义）：

```
main branch:    T1 → T2 → T3 ← 当前 HEAD
                              \
feature branch:                → T4(feature) → T5(feature)
```

### 2.2 Marking 在不同 Transaction 类型下的行为

| Transaction 类型 | Marking 继承行为 |
|---|---|
| **Snapshot（全量）** | 每次 Build 重新从当前上游计算全量继承 Marking，状态最干净 |
| **Append（增量追加）** | 新 Transaction 继承当前上游 Marking，历史 Transaction 的 Marking 已固化 |
| **Update（更新事务）** | 同 Append，新写入的分区 Marking 更新，旧分区状态不变 |

**关键风险：增量 Transform + 上游 Marking 变更**

```
场景：
  Dataset A 原无 Marking → 增量 Transform 产出 Dataset B 历史数据（无 Marking）
  Dataset A 加了 PII Marking → 新增量只处理新 Transaction
  
结果：
  Dataset B 历史数据（旧 Transaction）：无 Marking
  Dataset B 新数据（新 Transaction）：  有 PII Marking（继承）
  
  → 同一 Dataset 的不同 Transaction 呈现不一致的 Marking 状态！
  
解决方案：
  对 Dataset B 触发 SNAPSHOT Build（全量重算），统一 Marking 状态
```

### 2.3 Branch 上的 Marking 行为

```
Branch 切换时 Marking 的状态：

场景：
  main branch：Dataset A（Marking: PII）
  feature branch：Dataset A（同一来源，无额外 Marking）

规则：
  1. Branch 上的 Dataset 继承其所在 Branch HEAD Transaction 的 Marking
  2. 不同 Branch 的同一 Dataset 路径，Marking 状态可以不同
  3. Branch 合并（Merge）时，目标 Branch 重新计算 Marking

受保护分支与 stop_propagating：
  - stop_propagating 只在受保护分支（Protected Branch）上有效
  - feature branch（非受保护）执行 stop_propagating → Build 失败
  - 必须将代码 PR merge 到受保护分支后，在受保护分支执行 Build 才生效
```

### 2.4 Branch 保护策略中的安全配置

```
受保护分支配置项（Branch Protection Rules）：

必须 Approve 人数：≥ 1（建议 ≥ 2 用于 stop_propagating 涉及的分支）
必须包含的 Reviewer 角色：Security Team
自动触发的 CI 检查：stop_propagating 使用检测脚本（见 12 文档的 GitHub Actions 示例）
合并方式：Squash Merge（保留完整审批记录）

推荐分支策略：
  main（受保护）← PR with Security Review
  staging（受保护）← PR from feature
  feature/*（非受保护）← 开发分支
```

---

## 三、Marking 在 AIP（AI Platform）和 LLM 场景的访问控制

### 3.1 AIP 的安全架构原则

AIP 在设计上遵循 **"AI 继承调用者身份"** 原则：
LLM Agent 的数据访问权限 **绝不超过** 触发该 Agent 的人类用户的权限。

```
用户（持有 Marking M1，不持有 M2）
    │
    ▼
调用 AIP Agent（基于 Ontology 的自然语言交互）
    │
    ▼
Agent 访问 Dataset X（需要 M1 + M2）
    │
    ▼
Foundry Marking Service 校验：
  用户持有 M1（通过）
  用户不持有 M2（拒绝）
    │
    ▼
Agent 仅能看到满足用户权限的数据子集
（不会因为"是 AI" 而绕过 Marking 检查）
```

### 3.2 AIP Logic 中的 Marking 行为

AIP Logic（无代码 LLM 流水线）在执行时的安全上下文：

```python
# AIP Logic 伪代码：展示安全上下文传播
def aip_logic_function(user_context: UserContext, query: str):
    # AIP Logic 自动使用 user_context 的权限执行 Ontology 查询
    # 结果集自动过滤为 user_context 有权访问的对象
    results = ontology.search(
        object_type="CustomerProfile",
        query=query,
        security_context=user_context  # 框架自动注入，不可绕过
    )
    # results 中不会出现 user_context 无 Marking 的对象
    return llm.summarize(results)
```

**关键机制**：OSDK（Ontology SDK）在所有数据访问路径上强制注入调用者的 `UserContext`，Marking 鉴权在 Ontology 层执行，LLM 的 Prompt 上下文中永远不会出现用户无权访问的数据。

### 3.3 AIP 的多层 Marking 策略（与传统场景的差异）

AIP 场景下 Foundry 支持将 Marking、用途、角色三类策略混合：

| 策略层 | 控制维度 | 场景 |
|---|---|---|
| **Marking-based**（MAC） | 用户必须持有所有 Marking | 数据分类（PII/机密等） |
| **Purpose-based** | 数据只能用于指定用途 | 仅允许"客户服务"用途访问客户数据 |
| **Role-based**（RBAC） | 角色权限 | 只有 Analyst 角色可见财务数据 |

三层策略叠加，在 AIP 场景中任一层拒绝即整体拒绝。

### 3.4 LLM 上下文注入的安全边界

```
AIP Agent 工作流中 Marking 安全边界：

阶段 1：用户输入（自然语言）
  → Agent 解析意图
  → 确定需要访问的 Ontology Object Types

阶段 2：数据检索（Retrieval）
  → Ontology API 按 UserContext 过滤
  → 只有用户有权访问的 Objects 进入 Prompt 上下文
  → Marking 不足的数据：对象不可见（行级）或属性返回 null（列级）

阶段 3：LLM 处理（Generation）
  → LLM 只能基于已过滤的数据生成回答
  → 无法"猜测"或"推断"无权限数据的内容

阶段 4：动作执行（Action）
  → Agent 执行写操作（Ontology Edit）时同样受 UserContext 约束
  → 不能写入用户无 Marking 的资源

审计：
  → 所有 AIP Agent 执行留下完整审计轨迹，包括调用的数据集、Marking 状态、执行结果
```

### 3.5 AIP 服务账号的 Marking 管理

当 AIP Agent 以**服务账号**（而非人类用户）身份运行时：

```
服务账号的 Marking 策略（最小权限原则）：

推荐做法：
  1. 为每个 AIP Agent 创建专属服务账号
  2. 只授予该 Agent 完成任务必需的 Marking 成员资格
  3. 定期审计服务账号的 Marking 持有情况
  4. 服务账号不授予 "Remove Marking" 权限（只有人类安全团队持有）

反模式（避免）：
  - 为服务账号授予所有 Marking → AI 可访问全量敏感数据
  - 多个 Agent 共享同一服务账号 → 无法区分各 Agent 的行为审计
```

---

## 四、Marking Category 企业级设计

### 4.1 Category 设计原则

Marking Category 是 Marking 的组织单元，决定该类别内的访问逻辑（AND / OR）。

**设计原则**：

```
1. 一个 Category 对应一个独立的访问维度
   ✓ 数据敏感度 Category（PII / PHI / Financial）
   ✓ 地理合规 Category（CN-Only / EU-Only / US-Only）
   ✓ 业务条线 Category（Sales / HR / Finance）
   ✗ 错误：把"数据敏感度"和"地理合规"混在同一 Category

2. 合取（AND）Category：同一维度内需要同时满足多条件
   场景：系统集成账号需要同时通过"PII 授权"AND"安全培训认证"
   
3. 析取（OR）Category：同一维度内满足其一即可
   场景：跨国数据共享，美国用户 OR 欧盟用户均可访问
```

### 4.2 典型企业 Category 配置方案

```
Category 1：数据敏感级别（合取，CONJUNCTIVE）
  ├── Marking: PII（个人身份信息）
  ├── Marking: PHI（受保护健康信息）
  ├── Marking: PCI（支付卡信息）
  └── Marking: Financial（财务敏感数据）
  逻辑：一个 Dataset 可同时有 PII + Financial，用户必须同时持有两者

Category 2：地理合规（析取，DISJUNCTIVE）
  ├── Marking: GDPR-EU（欧盟合规授权用户）
  ├── Marking: PIPL-CN（中国个人信息保护法授权用户）
  └── Marking: CCPA-US（加州消费者隐私法授权用户）
  逻辑：跨国数据集，持有任一地区授权即可访问对应地区数据

Category 3：机密等级（Classification，层级制）
  └── UNCLASSIFIED → CONFIDENTIAL → SECRET → TOP SECRET
  逻辑：持有高级别 Clearance 自动获得低级别访问权

Category 4：业务条线隔离（合取，CONJUNCTIVE）
  ├── Marking: BU-Sales（销售业务线）
  ├── Marking: BU-HR（人力资源业务线）
  └── Marking: BU-Finance（财务业务线）
  逻辑：跨条线访问需同时持有多个 BU Marking
```

### 4.3 多 Category 叠加的访问判断示例

```
Dataset D 的 Marking 配置：
  Category 1（合取）：[PII, Financial]
  Category 2（析取）：[GDPR-EU, CCPA-US]

用户 A（PII + Financial + GDPR-EU）：
  Category 1：PII ✓, Financial ✓ → 满足
  Category 2：GDPR-EU ✓ → 满足
  结论：允许访问 ✓

用户 B（PII + GDPR-EU）：
  Category 1：PII ✓, Financial ✗ → 不满足
  结论：拒绝访问 ✗

用户 C（PII + Financial）：
  Category 1：满足
  Category 2：GDPR-EU ✗, CCPA-US ✗ → 不满足
  结论：拒绝访问 ✗
```

### 4.4 企业 Marking 治理最佳实践

| 实践 | 说明 |
|---|---|
| **数据所有者单一对应** | 每个 Marking 对应一个敏感数据所有者（如 HR 负责 PHI），避免职责混乱 |
| **Marking 数量控制** | 不超过 20 个活跃 Marking，过多导致治理复杂度爆炸 |
| **成员列表用 Group 管理** | Marking 成员加 Group（如 PII-Approved-Users），不直接加个人，减少成员变更频率 |
| **管理员与成员分离** | Marking Admin 负责成员列表管理，不一定自己是成员 |
| **定期成员审查** | 每季度审计 Marking 成员列表，清理离职人员 |
| **Marking 命名规范** | `<大类>.<子类>.<版本>`，如 `sensitivity.pii.v1`，便于程序化管理 |

### 4.5 常见错误配置与修正

| 错误模式 | 风险 | 修正 |
|---|---|---|
| 将 Marking 用于授权（而非限制） | Marking 是单向限制工具，无法用来"给予"访问 | 用 Role 做授权，Marking 只做访问限制 |
| 单一"超级 Marking"覆盖所有敏感数据 | 过于粗粒度，无法区分不同敏感类型 | 按数据类型拆分多个细粒度 Marking |
| Organization 与 Marking 职责混淆 | Organization 控制组织归属（部门隔离），不是数据分类工具 | 用 Marking 做数据分类，Organization 做部门隔离 |
| 在个人账号而非 Group 管理 Marking 成员 | 人员变动时需手动更新每个 Marking 的成员列表 | 用 Group 作为成员，人员变动只改 Group |

---

## 五、Marking 传播的性能与规模特性

### 5.1 Marking 元数据传播 vs 数据重算的区别

这是理解 Foundry Marking 性能的关键：

```
Marking 变更（加/移除）触发的是：
  ✓ Marking 元数据刷新（仅更新 resource_markings 表，极快）
  ✗ 不触发数据文件重算（数据不变，只是访问权限元数据变化）

例外：
  stop_propagating 变更需要数据重算：
    原因：stop_propagating 是在 Build 时的代码逻辑，只有重新 Build 才能让新的
          阻断规则生效并写入新的继承 Marking 元数据
    影响：需要触发下游所有 Dataset 的 SNAPSHOT Build（最耗时）
```

### 5.2 级联刷新的工程优化

```
FDS（Foundry Dependency Service）的级联刷新机制：

朴素实现（广度优先传播）：
  Layer 0：变更源 Dataset（1个）
  Layer 1：直接下游（可能数百个）
  Layer 2：二级下游（可能数千个）
  ...
  问题：深度血缘图中，一个 Marking 变更可能触发百万次元数据更新

Foundry 的优化策略：
  1. 批量化（Batching）：同一时间窗口内多个 Marking 变更合并为一次传播
  2. 版本化（Versioning）：Marking 状态有版本号，下游只处理比自身版本号高的变更
  3. 幂等性（Idempotency）：重复收到相同 Marking 状态不触发重复刷新
  4. 异步刷新：元数据刷新异步进行，用户操作不被阻塞（可能有短暂不一致窗口）
```

### 5.3 Query Time 的性能保障

```
Query Time Marking 鉴权的性能路径：

请求 → Query Engine → Marking Service.checkAccess(userId, resourceRid)
    → 读取 resource_markings（索引查询，O(1)）
    → 读取 user_markings（缓存命中）
    → 集合差运算（内存操作）
    → 返回结果

关键优化：
  1. user_markings 缓存（TTL 约 5 分钟）：用户 Marking 成员资格不频繁变化，缓存命中率高
  2. resource_markings 本地缓存：Query Engine 节点缓存热点资源的 Marking 列表
  3. 提前拒绝（Fast Fail）：只要发现用户缺少任一 Marking，立即返回 403，无需继续计算
```

### 5.4 大规模场景的工程约束

| 场景 | 约束 | 建议 |
|---|---|---|
| 为血缘根节点 Dataset 加 Marking | 触发全链路级联刷新，下游数十万 Dataset 元数据更新 | 在业务低峰期操作，提前用 Lineage 模拟评估影响范围 |
| 一次性批量给大量 Dataset 加 Marking | API 并发写入对 Marking Service 压力大 | 使用 Foundry 提供的批量 API，或分批次操作（每批 ≤ 100） |
| 增量 Transform + Marking 变更后的全量重算 | SNAPSHOT Build 全量重算成本高 | 在非工作时间触发，利用 Foundry 的优先级队列降低对在线 Build 的影响 |
| 多层 Marking Category 交叉查询 | 每次 Query 需要评估多个 Category 的逻辑 | 控制活跃 Marking 总数（建议 ≤ 20），避免过度细粒度拆分 |

### 5.5 Marking 传播延迟窗口

```
典型传播延迟（Foundry 官方参考值不公开，业界经验值）：

直接下游（1跳）：     毫秒~秒级（元数据写入）
二级下游（2跳）：     秒~分钟级（异步广播）
深度血缘（10+跳）：  分钟~十分钟级（队列积压时更慢）

实践意义：
  加 Marking 后，下游用户可能有短暂的"还能访问"窗口
  → 对于高敏感数据，建议先在所有受影响资源上手动加 Marking，再开放数据
  → 不能依赖"等传播完成"，时间不可预测
```

---

## 六、关键结论（进阶部分）

1. **SDS 是 Marking 的自动化入口，但不能替代人工治理**：SDS 负责边界数据的自动发现和打标，人工负责误报处理和 stop_propagating 的合规审批，两者协作才构成完整的 Marking 生命周期管理

2. **增量 Transform 是 Marking 一致性的最大隐患**：上游 Marking 变更后，增量 Transform 的历史 Transaction 不会自动更新，必须触发 SNAPSHOT Build 全量重算，这是 Foundry 数据架构中需要特别关注的运维盲区

3. **AIP 场景下 Marking 完全透明传递**：LLM Agent 的数据访问权限严格等于触发该 Agent 的用户权限，AI 不存在"绕过" Marking 的机制，这是 Foundry 在企业 AI 合规场景的核心竞争力

4. **Marking Category 的 AND/OR 设计决定了治理粒度**：合取用于"必须同时满足多条件"（数据敏感度维度），析取用于"满足其一即可"（地理合规维度），混淆两者会导致不合理的访问控制策略

5. **Marking 传播只更新元数据，不触发数据重算**：除非涉及 stop_propagating 变更，Marking 的加减只是权限元数据更新，对数据文件和 Build 计算无影响，性能开销远低于直觉预期

6. **传播延迟不可预测，高敏感数据应主动管理**：不能依赖"等级联传播完成"作为安全保障，应在数据公开前主动确认所有关键资源的 Marking 状态

---

## 参考资料

- Palantir Foundry Documentation: Sensitive Data Scanner（SDS）
- Palantir Foundry Documentation: Marking Categories（Conjunctive / Disjunctive）
- Palantir Foundry Documentation: AIP Security and Data Governance
- Palantir Foundry Documentation: Dataset Transactions and Branching
- Palantir Foundry Documentation: OSDK User Context Propagation
- Palantir AIP Logic: Security Context and Permission Inheritance
