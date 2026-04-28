# Palantir Foundry 安全与权限模型调研

**调研日期：** 2026-04-18
**调研方向：** 安全体系 / 权限模型 / Marking 系统 / 数据分类与传播 / 审计

---

## 一、整体安全架构概述

Foundry 的安全模型分为两大类控制机制：

| 类型 | 机制 | 说明 |
|---|---|---|
| **强制访问控制（MAC）** | Markings / Classifications / Organizations | 平台级强制执行，用户无法绕过 |
| **自主访问控制（DAC）** | 角色（Roles）/ 权限组 | 资源所有者自主授予的权限 |

企业级场景通常是 MAC + DAC 叠加使用：MAC 保证数据安全底线，DAC 提供业务灵活性。

---

## 二、Marking 系统：强制访问控制核心

### 2.1 Marking 是什么

**Marking 是 Foundry 最核心的 MAC 机制**，用于限制特定资源（Dataset、Code Repository、分析结果等）只对持有该 Marking 的用户可见。

关键特性：
- Marking 是**双向匹配**：资源需标记 Marking，用户账号也必须持有对应 Marking 才能访问
- 平台自动执行，无需开发者在代码里手工实现权限检查
- 适用对象：Dataset、Code Repository、工作空间资源、应用等几乎所有 Foundry 资源类型

### 2.2 Marking 的传播机制

**关键设计：Marking 会自动向下游传播**

```
源 Dataset（标记 Marking A）
    │ [Transform：读取后处理]
    ▼
下游 Dataset（自动继承 Marking A）
    │ [再次转换]
    ▼
更下游 Dataset（仍然继承 Marking A）
```

规则：
- **数据分类继承原则**：下游数据集的分类等级永远 ≥ 所有上游数据集的最高分类等级
- 开发者**无法在代码层面移除** Marking，只能通过平台管理员配置"停止传播点"
- 实践建议：在修改 Marking 前，务必先通过 Lineage 视图的"模拟模式"预览影响范围，避免意外锁定下游用户

### 2.3 Classification-Based Access Control（CBAC）

CBAC 是 Marking 的一种变体，主要面向**政府/军事客户**的层级化数据保密需求：
- 支持 UNCLASSIFIED → SECRET → TOP SECRET 等层级
- 用户持有某级别 Clearance 后，可访问该级别及以下的所有数据
- 与 Marking 的区别：CBAC 是层级制，Marking 是标签制（非层级）

### 2.4 Organizations（多组织隔离）

Organizations 是另一种 MAC 机制，用于**多组织/多租户场景的数据隔离**：
- 一个 Foundry 部署可以托管多个 Organization
- 默认情况下，Organization 间数据完全隔离
- 跨 Organization 的数据共享需要显式授权配置

---

## 三、行级安全（Row-Level Security）

### 3.1 实现路径

Foundry 的行级安全通过两种方式实现：

**方式一：Restricted Views（数据集层面）**
- 在 Dataset 上定义行过滤规则（基于用户属性/组）
- 不同用户查询同一 Dataset，自动返回过滤后的子集
- Transform 读取 Restricted View 时，也只读取当前执行身份有权限的行

**方式二：Ontology 对象安全策略（Object Security Policy）**
- 在 Ontology Object Type 层面定义行级可见性规则
- 策略基于用户属性（部门、角色、地区等）动态过滤对象实例
- 应用层（Workshop/Slate）消费 Ontology 时，天然继承该过滤

### 3.2 行级安全 vs Marking 的区别

| 维度 | Marking | Row-Level Security |
|---|---|---|
| 粒度 | 整个资源（Dataset 级） | 行级（记录级） |
| 控制层 | 平台 MAC | 数据层 DAC |
| 典型场景 | 机密数据隔离 | 多租户数据共享（A 只看 A 的数据） |

---

## 四、列级安全（Column Masking）

### 4.1 Property Security Policy（Ontology 层）

通过 Ontology 的 **Property Security Policy** 实现列掩码：
- 针对特定 Object Type 的某个属性（Property），定义谁可以看到原始值
- 未授权用户看到的是掩码值（如 `***`、`[REDACTED]`）或 null
- 配置位于 Ontology Manager，无需修改 Pipeline 代码

### 4.2 Cipher 服务（数据集层面的列加密）

**Cipher** 是 Foundry 提供的列级加密/解密/哈希服务：
- 在 Dataset 中对特定列进行加密存储（AES 等算法）
- 解密操作需要用户持有对应 Cipher Key 权限
- 支持**单向哈希**（用于假名化，如手机号哈希）
- Transform 中可调用 Cipher API 对列加密后输出，下游只看到密文

### 4.3 Sensitive Data Scanner（SDS）

**2024 年 GA 发布**的自动化敏感数据发现工具：
- 定义正则表达式模式（身份证号、信用卡号、手机号等）
- SDS 扫描 Foundry 内的 Dataset，匹配后自动执行预设动作（打标记、告警、自动加 Masking）
- 解决了"不知道哪里有敏感数据"的治理盲区

---

## 五、Workspace 与 Dataset 访问控制（DAC）

### 5.1 Workspace 权限层次

```
Foundry 实例（Enrollment）
    └── Organization
          └── Workspace（工作空间）
                ├── Project（项目）
                │     └── Folder → Resource
                └── 成员管理（Viewer / Editor / Manager）
```

权限从上到下继承，子层级可以设置比父层级更严格的权限（不能放宽）。

### 5.2 Dataset 权限角色

| 角色 | 权限 |
|---|---|
| Viewer | 只读（查看数据、下载） |
| Editor | 可写入新版本（触发 Build 写入） |
| Manager | 完整控制（含分享、修改权限） |
| Discoverer | 可发现资源存在（但不可读取内容） |

### 5.3 Project Classification（项目分类）

- 项目必须在创建时设置 Project Classification（在使用 CBAC 的部署中）
- 注意：Project Classification **不传播**到项目内 Dataset 的数据分类
  - 项目分类控制"谁能发现/进入这个项目"
  - Dataset 的数据分类由血缘上游决定（见第二节）

---

## 六、Checkpoints：操作审计与合规

**Checkpoint** 是 Foundry 的操作问责机制：
- 对敏感操作（如解密、下载、导出）设置 Checkpoint 拦截点
- 用户触发操作时，系统弹出确认框，要求填写操作理由
- 理由记录在审计日志中，供合规审查
- 典型应用：Cipher 解密时要求填写业务理由

---

## 七、Code Workspaces 安全

Code Workspaces（集成 JupyterLab / RStudio 等 IDE）的安全设计要点：
- Code Workspace 中的代码执行继承用户的 Foundry 权限（不能越权读取数据）
- Workspace 内的 Dataset 访问经过与 Code Repository 相同的 Marking + 角色检查
- 不支持在 Code Workspace 中绕过 Cipher 加密（必须持有 Key 权限）

---

## 八、安全模型全景图

```
┌─────────────────────────────────────────────────────────┐
│                  强制访问控制 (MAC)                        │
│  ┌──────────────┐  ┌────────────────┐  ┌─────────────┐  │
│  │   Markings   │  │ Classifications│  │ Organizations│  │
│  │ (标签制隔离)  │  │  (层级制密级)  │  │  (组织隔离) │  │
│  └──────────────┘  └────────────────┘  └─────────────┘  │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│                  自主访问控制 (DAC)                        │
│  ┌──────────────┐  ┌────────────────┐  ┌─────────────┐  │
│  │  Workspace   │  │  Dataset 角色  │  │  Ontology   │  │
│  │  项目权限组   │  │ (Viewer/Editor)│  │  安全策略   │  │
│  └──────────────┘  └────────────────┘  └─────────────┘  │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│                  数据级细粒度控制                          │
│  ┌──────────────┐  ┌────────────────┐  ┌─────────────┐  │
│  │  行级安全    │  │  列级 Masking  │  │  Cipher 加密│  │
│  │(RLS/对象策略)│  │(Property Policy│  │  (列加密)   │  │
│  └──────────────┘  └────────────────┘  └─────────────┘  │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│                  审计与合规                               │
│  ┌──────────────┐  ┌────────────────┐                   │
│  │  Checkpoints │  │  Audit Logs    │                   │
│  │ (操作问责)   │  │  (审计日志)    │                   │
│  └──────────────┘  └────────────────┘                   │
└─────────────────────────────────────────────────────────┘
```

---

## 九、关键结论

1. **Marking 传播是最容易踩的坑**：上游数据集加了 Marking，所有下游都会继承，需提前用 Lineage 模拟影响范围 [事实]
2. **行级安全优先用 Ontology 对象策略**：比 Restricted View 更灵活，且与应用层无缝集成 [推断]
3. **Cipher 解决了"数据必须加密存储"的合规需求**：但增加了 Pipeline 编写复杂度 [推断]
4. **SDS（2024）填补了敏感数据发现盲区**：对于大型组织，自动扫描比手工分类更可靠 [推断]
5. **Foundry 安全模型强绑定平台**：无法用标准 RBAC 框架（如 OPA）替代，是平台锁定成本的组成部分 [推断]

---

## 参考资料

- Palantir Foundry Documentation: Security & Access Controls
- Foundry Platform Updates 2024: Sensitive Data Scanner GA
- Palantir Classification-Based Access Controls (CBAC) Guide
