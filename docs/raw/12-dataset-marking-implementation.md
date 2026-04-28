# Dataset Marking 实现方案深度调研

**调研日期：** 2026-04-18
**调研方向：** Foundry Marking 内部实现 / REST API / 传播算法 / 自建平台设计 / 横向对比

---

## 一、Foundry Dataset Marking 的内部架构

### 1.1 核心服务分层

Foundry 的 Dataset Marking 由三个内部服务协作实现：

```
┌─────────────────────────────────────────────────────────┐
│  Compass（文件系统服务）                                   │
│  负责资源（Dataset/Folder/Project）的存储与元数据管理      │
│  Marking 作为资源的元数据属性附着在 RID 上                 │
├─────────────────────────────────────────────────────────┤
│  Marking Service（标记服务）                              │
│  负责 Marking 定义、成员管理、访问鉴权                     │
│  维护 (resourceRid → [markingId]) 映射                   │
├─────────────────────────────────────────────────────────┤
│  Build Service / Query Engine                           │
│  在 Build 写入和数据查询时调用 Marking Service 鉴权         │
│  Build 时：传播计算；Query 时：访问拦截                    │
└─────────────────────────────────────────────────────────┘
```

### 1.2 Marking 的存储模型

每个 Dataset（通过 RID 标识）在 Compass 元数据层维护两类 Marking 属性：

| 属性 | 含义 | 来源 |
|---|---|---|
| **直接 Marking（Direct Marking）** | 管理员/Owner 显式施加在该 Dataset 上的 Marking | 手动操作或 API 调用 |
| **继承 Marking（Inherited Marking）** | 从上游 Dataset 血缘传播而来的 Marking | Build Service 在 Build 时自动计算 |

**数据分类（Data Classification）= 直接 Marking ∪ 继承 Marking 的并集**，且永远 ≥ 所有上游资源的数据分类。 [事实]

### 1.3 Build Time vs Query Time 双重执行

Marking 在两个阶段都有执行，各自职责不同：

```
Build Time（写入阶段）：
  Transform 完成 → Build Service 读取所有 Input Dataset 的 Marking
      → 计算 Output Dataset 的继承 Marking（取并集）
      → 写入 Compass 元数据
      → 下游自动继承（FDS 事件触发下游 Marking 刷新）

Query Time（读取阶段）：
  用户发起读取请求 → Query Engine 调用 Marking Service
      → 校验用户是否持有 Dataset 所有 Marking 的成员资格
      → 通过：返回数据；拒绝：返回 403 PermissionDenied
```

两阶段的分工：**Build Time 负责 Marking 传播计算**（写入元数据），**Query Time 负责访问拦截**（查权限）。两者都不可缺少。 [推断]

---

## 二、Foundry Dataset Marking REST API

Palantir Foundry 暴露了完整的 REST API 用于 Marking 的程序化管理。

### 2.1 核心 API 端点

#### 查询资源的 Marking

```http
GET /api/v2/filesystem/resources/{resourceRid}
Authorization: Bearer <token>
Scope: api:filesystem-read
```

响应示例（含 Marking 信息）：
```json
{
  "rid": "ri.compass.main.resource.xxxx",
  "name": "user_events",
  "type": "dataset",
  "markings": [
    { "markingId": "marking.pii", "type": "DIRECT" },
    { "markingId": "marking.finance", "type": "INHERITED" }
  ]
}
```

#### 向资源施加 Marking

```http
POST /api/v2/filesystem/resources/{resourceRid}/addMarkings?preview=true
Authorization: Bearer <token>
Scope: api:filesystem-write
Content-Type: application/json

{
  "markingIds": ["marking.pii", "marking.internal"]
}
```

**注意**：该端点目前为 Preview 状态（`preview=true` 必传），API 设计可能变化。 [事实]

#### 移除资源上的 Marking

```http
POST /api/v2/filesystem/resources/{resourceRid}/removeMarkings?preview=true
Authorization: Bearer <token>
Scope: api:filesystem-write
Content-Type: application/json

{
  "markingIds": ["marking.internal"]
}
```

**权限约束**：调用方必须持有该 Marking 的 "Remove marking" 权限，否则返回 403。

#### 查询 Marking 定义

```http
GET /api/v2/admin/markings/{markingId}
Authorization: Bearer <token>
Scope: api:admin-read
```

响应：
```json
{
  "markingId": "marking.pii",
  "displayName": "PII - 个人身份信息",
  "description": "含有手机号、身份证号、真实姓名等个人信息的数据",
  "categoryId": "category.data-sensitivity",
  "conjunctive": true
}
```

#### 创建新 Marking

```http
POST /api/v2/admin/markings
Authorization: Bearer <token>
Scope: api:admin-write
Content-Type: application/json

{
  "displayName": "财务数据",
  "categoryId": "category.data-sensitivity",
  "description": "含有财务敏感字段的数据集"
}
```

### 2.2 RID 格式

Foundry 所有资源通过 RID（Resource Identifier）唯一标识，格式：

```
ri.<service>.<instance>.<type>.<locator>

示例：
ri.compass.main.resource.abc123def456    → Dataset/Folder/Project
ri.foundry.main.dataset.xyz789          → Dataset（数据集特化）
ri.foundry.main.marking.pii-001         → Marking 定义
```

### 2.3 OSDK（Ontology SDK）中的 Marking 属性类型

OSDK v2 引入了 `Markings` 属性类型，可直接在 Object Type 上声明哪些属性是 Marking 控制的：

```python
# OSDK v2 Python 示例
from foundry.ontology import ObjectType, Property, Markings

class UserProfile(ObjectType):
    user_id: str
    name: str
    phone: str  # 被 PII Marking 控制的属性（Property Security Policy 层面）
    markings: Markings  # 对象级 Marking 声明
```

---

## 三、传播算法的实现逻辑

### 3.1 传播计算的触发时机

Marking 传播**在 Build 写入时同步计算**，不是异步或懒计算：

```
触发条件：
  1. Output Dataset 的新 Transaction 写入完成
  2. 上游 Dataset Marking 发生变更（通过 FDS 事件广播）

计算过程：
  new_output_marking = (
      direct_markings(output)                      # 直接施加的 Marking
      ∪ ⋃ inherited_markings(input_i)              # 所有 Input 的继承 Marking
      ∪ ⋃ direct_markings(input_i)                 # 所有 Input 的直接 Marking
  )
  - stop_propagating 列表中的 Marking             # 减去被阻断的 Marking
```

### 3.2 stop_propagating 的处理节点

当 Transform 代码声明 `stop_propagating` 后，Build Service 在计算继承 Marking 时，从该 Input 的贡献集合中移除被阻断的 Marking：

```python
# Transform 代码
Input('/pii_data', stop_propagating=Markings(['PII']))

# Build Service 处理逻辑（伪代码）
def compute_output_markings(inputs, direct_markings, stop_propagating_rules):
    inherited = set()
    for inp in inputs:
        contributed = inp.all_markings
        # 应用 stop_propagating 规则
        blocked = stop_propagating_rules.get(inp.path, set())
        contributed -= blocked
        inherited |= contributed
    return inherited | direct_markings
```

**安全保障**：`stop_propagating` 只能在受保护分支（Protected Branch）上执行，因为 Foundry 在 Branch Protection 规则中可以强制要求 "Security Review"（指定安全团队成员必须 Approve），防止开发者随意移除 Marking。

### 3.3 上游 Marking 变更的下游刷新

当某个 Dataset 的 Marking 被修改（加/减），**FDS（Foundry Dependency Service）广播事件**，触发所有直接下游 Dataset 重新计算其继承 Marking。这是一个**递归传播**过程：

```
Dataset A（加了新 Marking M）
  → FDS 通知直接下游 B、C
      → B 重计算：inherited_markings = ... ∪ {M}
      → FDS 通知 B 的下游 D
          → D 重计算：inherited_markings = ... ∪ {M}
          → ...（递归到所有传递下游）
```

注意：这个传播**只更新 Marking 元数据**，不触发 Build 重算数据。数据文件不变，只是访问权限改变了。 [推断]

---

## 四、横向对比：其他平台的 Dataset Marking 实现

### 4.1 Apache Ranger（Tag-based Policy）

Apache Ranger 通过 **Atlas 标签（Tag）+ TagSync** 实现类似 Marking 的功能：

```
标签定义（Atlas）：
  PII_TAG → 关联 Hive 表 / 列

Ranger Policy：
  IF resource has tag PII_TAG
  AND user NOT IN group {pii_approvers}
  THEN DENY / MASK

标签传播：
  Hive 视图（View）继承底层表的 Tag
  但跨引擎传播需要 Atlas Lineage Hook 支持，不自动
```

**与 Foundry 的差距**：
- 跨引擎传播不自动（Foundry 平台内全自动）
- 无 stop_propagating 等精细阻断机制
- Hive/Spark 之外的传播需手工配置

### 4.2 Databricks Unity Catalog（Tag-based ABAC）

Unity Catalog 的数据分类实现：

```
AI 自动扫描 → 打 Tag（PII/PHI/PCI）
    ↓
Tag 作为 ABAC 策略属性
    ↓
列级 Masking Policy：
  IF column.tag = 'PII' AND user.role != 'data_analyst'
  THEN MASK(column, 'REDACT')

传播：
  Delta Table 的列 Tag 不自动传播到下游衍生表
  需要手动配置或依赖 Unity Catalog Lineage + 自定义策略
```

**与 Foundry 的差距**：
- 传播不自动（Foundry 是平台级自动传播）
- ABAC 策略更灵活，但需要手写策略表达式
- 有 AI 辅助自动打标（Foundry 的 SDS 类似，但规则驱动）

### 4.3 三平台对比矩阵

| 特性 | Foundry Marking | Apache Ranger + Atlas | Databricks Unity Catalog |
|---|---|---|---|
| **传播机制** | 平台级自动传播（血缘感知） | 需 Atlas Lineage Hook，跨引擎不自动 | 不自动传播，需手工 |
| **强制性（MAC）** | 是（平台强制，Owner 无法绕过） | 是（Ranger 强制） | 部分（Row Filter/Column Mask 可绕过 Admin） |
| **访问逻辑** | AND（所有 Marking 必须满足） | AND（多 Tag 策略叠加） | ABAC（灵活表达式） |
| **传播阻断** | stop_propagating（代码级，需 Security Review） | 无标准机制 | 无 |
| **AI 自动打标** | SDS（规则驱动，2024 GA） | 无 | AI Agent（LLM 驱动，更准确） |
| **跨引擎一致性** | 平台内一致（单一 Foundry 平台） | 多引擎但需逐个配置 | Databricks 生态内一致 |
| **审计** | 完整（Foundry 审计日志） | Ranger Audit Log | Unity Catalog Audit Log |

---

## 五、自建平台的 Dataset Marking 实现方案

如果需要在开源栈上复刻 Foundry 的 Dataset Marking 能力，以下是完整设计方案：

### 5.1 核心数据模型

```sql
-- Marking 定义表
CREATE TABLE markings (
    marking_id   VARCHAR PRIMARY KEY,   -- e.g., 'marking.pii'
    display_name VARCHAR NOT NULL,
    category_id  VARCHAR NOT NULL,
    logic_type   ENUM('CONJUNCTIVE', 'DISJUNCTIVE') DEFAULT 'CONJUNCTIVE',
    description  TEXT
);

-- Marking 成员表（用户/组 → Marking 的持有关系）
CREATE TABLE marking_members (
    marking_id   VARCHAR REFERENCES markings(marking_id),
    principal_id VARCHAR NOT NULL,       -- user_id 或 group_id
    principal_type ENUM('USER', 'GROUP'),
    granted_by   VARCHAR NOT NULL,
    granted_at   TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (marking_id, principal_id)
);

-- 资源 Marking 表（Dataset → Marking 的关联）
CREATE TABLE resource_markings (
    resource_id    VARCHAR NOT NULL,     -- Dataset RID / 路径
    marking_id     VARCHAR REFERENCES markings(marking_id),
    marking_source ENUM('DIRECT', 'INHERITED'),
    PRIMARY KEY (resource_id, marking_id)
);
```

### 5.2 传播引擎设计

传播引擎在数据写入时触发，核心逻辑：

```python
class MarkingPropagationEngine:

    def on_dataset_written(self, output_rid: str, input_rids: list[str],
                           stop_propagating: dict[str, list[str]]):
        """在 Pipeline Build 写入输出 Dataset 时调用"""
        
        # 1. 收集所有 Input 的 Marking（直接 + 继承）
        inherited = set()
        for inp_rid in input_rids:
            inp_markings = self.get_all_markings(inp_rid)       # 直接 + 继承
            blocked = set(stop_propagating.get(inp_rid, []))    # 阻断列表
            inherited |= (inp_markings - blocked)

        # 2. 合并直接 Marking（管理员手动施加的不删除）
        direct = self.get_direct_markings(output_rid)
        new_markings = direct | inherited

        # 3. 更新资源 Marking 表
        self.update_inherited_markings(output_rid, inherited)

        # 4. 广播事件：通知直接下游重新计算
        downstream = self.lineage_service.get_direct_downstream(output_rid)
        for ds_rid in downstream:
            self.trigger_marking_refresh(ds_rid)

    def get_all_markings(self, resource_id: str) -> set[str]:
        """返回该资源的所有 Marking（直接 + 继承）"""
        rows = db.query(
            "SELECT marking_id FROM resource_markings WHERE resource_id = %s",
            resource_id
        )
        return {r.marking_id for r in rows}
```

### 5.3 访问控制拦截器

在数据读取路径上实现 Marking 鉴权拦截：

```python
class MarkingAccessInterceptor:

    def check_access(self, user_id: str, resource_id: str) -> bool:
        """
        Query Time 访问鉴权：
        用户必须持有资源所有 Marking 的成员资格
        """
        # 获取资源的所有 Marking
        required_markings = self.get_all_markings(resource_id)
        if not required_markings:
            return True   # 无 Marking 约束，允许访问

        # 获取用户持有的所有 Marking（含通过 Group 继承的）
        user_markings = self.get_user_markings(user_id)

        # AND 逻辑：用户必须持有全部 Marking
        missing = required_markings - user_markings
        if missing:
            self.audit_log(user_id, resource_id, 'DENIED', missing)
            return False

        self.audit_log(user_id, resource_id, 'ALLOWED', set())
        return True

    def get_user_markings(self, user_id: str) -> set[str]:
        """返回用户持有的所有 Marking（含通过 Group 间接持有）"""
        groups = self.group_service.get_user_groups(user_id)
        principals = {user_id} | set(groups)
        rows = db.query(
            "SELECT DISTINCT marking_id FROM marking_members "
            "WHERE principal_id = ANY(%s)",
            list(principals)
        )
        return {r.marking_id for r in rows}
```

### 5.4 集成到 Pipeline 框架（以 Airflow/Dagster 为例）

```python
# Dagster Asset 装饰器集成示例
from dagster import asset, AssetIn
from marking_sdk import MarkingContext, Markings

@asset(
    ins={
        "pii_events": AssetIn(
            key="raw/user_events_pii",
            metadata={
                "stop_propagating": ["marking.pii"]   # 阻断 PII 传播
            }
        )
    },
    required_resource_keys={"marking_context"}
)
def anonymized_events(context, pii_events):
    marking_ctx: MarkingContext = context.resources.marking_context
    
    # 框架自动校验：执行人是否持有 stop_propagating 所需权限
    marking_ctx.assert_can_stop_propagating(
        context.run.run_id, ["marking.pii"]
    )
    
    df = pii_events.copy()
    df['phone'] = df['phone'].apply(hash_phone)
    df = df.drop(columns=['id_card', 'real_name'])
    return df

# Dagster Sensor 监听 Marking 变更事件，触发下游 Asset 重计算 Marking 元数据
@sensor(job=refresh_marking_metadata_job)
def marking_change_sensor(context):
    events = marking_event_store.get_unprocessed()
    for event in events:
        yield RunRequest(run_key=event.id, run_config={
            "resource_id": event.resource_id
        })
```

### 5.5 受保护分支保障（工程约束）

与 Foundry 一样，`stop_propagating` 应通过 CI/CD 流程强制审核：

```yaml
# GitHub Actions：检测 stop_propagating 的使用，强制安全审查
name: Security Review Gate

on:
  pull_request:
    branches: [main, production]

jobs:
  marking-security-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Detect stop_propagating usage
        run: |
          if grep -r "stop_propagating" --include="*.py" .; then
            echo "::warning::检测到 stop_propagating 使用"
            echo "NEEDS_SECURITY_REVIEW=true" >> $GITHUB_ENV
          fi
      - name: Require security team approval
        if: env.NEEDS_SECURITY_REVIEW == 'true'
        uses: actions/github-script@v6
        with:
          script: |
            // 自动添加 security-review 标签，触发安全团队 Review 流程
            await github.rest.issues.addLabels({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              labels: ['security-review-required']
            });
            core.setFailed('需要安全团队 Review stop_propagating 使用');
```

---

## 六、关键设计决策分析

### 6.1 为什么传播在 Build Time 而非 Query Time？

| 时机 | 优点 | 缺点 |
|---|---|---|
| **Build Time（Foundry 选择）** | 查询时无额外计算，性能好；Marking 状态持久化便于审计 | 上游 Marking 变更需触发下游刷新，有延迟 |
| **Query Time** | Marking 变更立即生效，无刷新延迟 | 每次查询都要遍历血缘计算，性能差；血缘图大时延迟高 |

Foundry 选择 Build Time 传播是正确的工程权衡：数据平台的 Dataset 数量巨大，Query Time 遍历血缘不可行。 [推断]

### 6.2 为什么 stop_propagating 必须走受保护分支？

核心是**防止特权滥用**：若任意开发者可以随意移除 Marking 传播，意味着任意人可以在代码里把 PII 数据"洗白"后输出给无权限用户。受保护分支 + Security Review 将"移除 Marking"这一高风险操作强制纳入审批流，确保：
1. 有人审核：数据确实已经脱敏
2. 有人承担责任：Approve 人留下审计记录

### 6.3 自建方案的最大挑战

开源栈复刻 Foundry Marking 的核心难点**不是代码逻辑，而是两点**：

1. **血缘与 Marking 的深度集成**：传播引擎依赖实时、准确的跨系统血缘图（Spark/dbt/Flink 都要有），OpenLineage 是目前最好的标准，但跨引擎的实时传播仍有 Gap [推断]
2. **全链路拦截点的覆盖**：Foundry 是闭合平台，只有一个数据访问入口；自建开放栈中，Spark/Trino/Jupyter/BI 工具都是访问入口，每个都需要部署 Marking 鉴权拦截器 [推断]

---

## 七、关键结论

1. **Foundry Marking 本质是元数据 + 传播引擎 + 访问拦截器的组合**：三者缺一不可，单独实现任一都不能达到 Foundry 的效果 [推断]
2. **传播算法的核心是"取上游 Marking 并集，减去 stop_propagating 列表"**：逻辑简单，挑战在于工程上保证所有写入路径都触发传播计算 [推断]
3. **Build Time 传播 + Query Time 拦截是正确的双重保障**：前者保证元数据正确，后者保证访问安全 [推断]
4. **stop_propagating 必须走审批流**：这是安全设计的关键，不能因为方便而省略 [事实]
5. **Databricks Unity Catalog 最接近但有根本差距**：ABAC 更灵活，但传播不自动，需要手工维护标签传播关系 [推断]
6. **自建方案的可行性**：数据模型和算法完全可以开源实现，真正的挑战是覆盖所有数据访问路径的拦截点，以及与各引擎血缘系统的深度集成 [推断]

---

## 参考资料

- Palantir Foundry REST API v2: `/api/v2/filesystem/resources/{resourceRid}/addMarkings`
- Palantir Foundry REST API v2: `/api/v2/admin/markings`
- Apache Ranger Documentation: Tag-Based Policies
- Databricks Unity Catalog: Data Classification and ABAC
- OpenLineage Spec: https://openlineage.io
