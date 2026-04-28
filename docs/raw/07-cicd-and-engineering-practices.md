# Palantir Foundry CI/CD 与代码工程实践调研

**调研日期：** 2026-04-18
**调研方向：** Code Repository 工程实践 / 分支策略 / 依赖管理 / 多环境发布 / Code Checks

---

## 一、Code Repository 基础：Git-like 版本控制

Foundry Code Repository 使用 **基于 Git 的版本控制系统**，但与外部 Git 有重要差异：

| 特性 | Foundry Code Repo | 标准 Git |
|---|---|---|
| 分支操作 | 支持（branch/commit/tag） | 支持 |
| Pull Request | 支持（含代码审查） | 支持 |
| Merge 策略 | Squash-and-merge 或 Merge | 完整支持 |
| 外部 Git 托管 | 不需要（平台内置） | 独立工具 |
| Dataset 版本联动 | 内置（Build 写 Transaction） | 无概念 |
| CI 触发 | 内置（Check Runs 机制） | 需外部 CI 工具 |

**Branch Protection（分支保护）：**
- 关键分支（如 `master`）可配置保护规则：
  - 要求 CI Checks 全部通过
  - 要求至少 N 人 Code Review 通过
  - 禁止 Force Push

---

## 二、依赖管理：Hawk（Foundry 的 Conda 实现）

### 2.1 Hawk 是什么

**Hawk** 是 Palantir 自研的 Conda 兼容包管理工具，是 Foundry Python 环境的依赖管理核心：
- 完全兼容 Conda/Mamba 生态，但比官方 Conda 更快（内部称"活跃开发中的改进版"）
- 每个 Code Repository 有独立的 Conda 环境，包互不干扰

### 2.2 依赖声明：`meta.yaml`

```yaml
# conda_recipe/meta.yaml
package:
  name: my-transforms
  version: 1.0.0

requirements:
  host:
    - python 3.9.*
    - pip
  run:
    - pandas >=1.3,<2.0
    - scikit-learn >=0.24
    - transforms-api  # Palantir 内部包
```

### 2.3 Lock File（环境固化）

Foundry 从 `meta.yaml` 生成 **Conda Lock File**，确保所有人和所有环境的依赖版本完全一致：
- Lock File 提交到 Code Repository（类似 `package-lock.json`）
- Build 时使用 Lock File 中固化的版本，而非重新解析
- **关键实践**：Lock File 必须提交代码库，否则不同时间的 Build 可能使用不同版本依赖

### 2.4 Library Publishing（库发布机制）

当一个 Repository 的代码需要被其他 Repository 引用时（如共享工具函数），使用 Library Publishing：

```
工具库 Repository
    │ [发布为 Conda Package]
    ▼
Foundry Conda Channel（内部包仓库）
    │ [其他 Repository 在 meta.yaml 中声明依赖]
    ▼
业务 Repository（consume 工具库）
```

- 版本管理通过 semantic versioning（`1.0.0`）
- 上游库更新后，下游 Repository 需显式升级版本（非自动）

---

## 三、CI/CD：Checks 机制

### 3.1 Check Run 是什么

**Check Run** 是 Foundry Code Repository 内置的 CI 机制，类比 GitHub Actions：
- 在 Pull Request 创建 / 代码 push 时自动触发
- 可配置多个 Check（Build 验证、单元测试、Data Quality 检查等）
- 所有 Check 通过后，才允许合并到主分支（如果开启了 Branch Protection）

### 3.2 常见 Check 类型

| Check 类型 | 说明 |
|---|---|
| **Build Check** | 执行 Transform Build，验证代码可正常运行并生成输出 |
| **Unit Test Check** | 运行 `pytest`，基于 `InMemoryDatastore` 的隔离测试 |
| **Lint Check** | PEP8/flake8 代码风格检查 |
| **Data Quality Check** | 验证输出 Dataset 是否满足预定义的数据质量规则 |
| **Expectations Check** | 基于 Great Expectations 的数据断言（Foundry 集成版） |

### 3.3 Data Quality Checks（代码内嵌）

Foundry 支持在 Transform 内嵌 Data Quality Expectations（类似 Great Expectations）：

```python
from transforms.api import transform_df, Input, Output
from transforms.verbs.dataframes import DataQualityCheck

@transform_df(
    Output('/project/output/validated_events'),
    source=Input('/project/input/events'),
)
def compute(source):
    df = source.filter('event_type IS NOT NULL')
    # 输出时声明 Check：非空率 > 99%
    return df.with_check(
        DataQualityCheck.not_null('user_id', threshold=0.99)
    )
```

Build 时自动执行 Check，不满足则 Build 失败并记录违规率。

---

## 四、多环境发布策略

### 4.1 Spaces：环境抽象

Foundry 使用 **Space（空间）** 作为环境隔离单元，典型设置：

```
Development Space（开发环境）
    │ [Review + 测试通过]
    ▼
Testing / Staging Space（测试环境）
    │ [回归测试 + QA 验收]
    ▼
Production Space（生产环境）
```

每个 Space 可以有独立的：
- 数据源配置（开发用测试数据，生产用真实数据）
- Compute Profile 配置（生产环境用更大规格）
- 触发计划（Schedule）

### 4.2 Marketplace：跨环境资源发布

**Marketplace** 是 Foundry 的跨环境（跨 Space）资源打包发布机制：
- 将 Code Repository + Pipeline + Ontology 配置打包成"产品"
- 从 Dev Space 导出 → 在 Prod Space 导入
- 支持版本控制（每次发布生成版本快照）
- 参数化部署：不同环境的差异配置（如数据源路径）通过参数注入

### 4.3 分支策略最佳实践

Foundry 官方推荐的分支命名约定：
- **跨 Repository 一致的分支名**：同一产品内所有 Repository 使用相同的 feature branch 名
  - 原因：Pipeline Build 解析依赖时，会尝试同名分支，确保多 Repo 联合开发的一致性
- `master` / `main`：生产分支（受保护）
- `feature/xxx`：功能分支（短生命周期）
- `release/1.x`：发布分支（需要时）

---

## 五、本地开发与 Foundry 集成

### 5.1 Code Workspaces（云端 IDE）

Foundry 提供基于浏览器的 IDE 环境（集成 JupyterLab、RStudio、VS Code Server）：
- 完整访问 Foundry Dataset（受权限控制）
- 安装依赖自动同步到 Repository 的 Conda 环境
- 代码变更直接同步到 Code Repository（无需本地 Git 操作）

### 5.2 MCP Server 与本地 IDE 集成（2025）

Palantir 于 2025 年发布 **Foundry MCP Server**，连接本地 IDE（VS Code 等）与 Foundry：
- 本地 AI 助手（Copilot/Cursor）可读取 Foundry Ontology 上下文
- 可在本地 IDE 中直接触发 Build、查看 Dataset
- 安全：数据在 Foundry 侧，只传元数据到本地 IDE

---

## 六、关键结论

1. **Hawk 是 Conda 兼容的，但有 Foundry 专有包**（如 `transforms-api`），无法在纯 Conda 环境中运行 Transform [事实]
2. **Lock File 必须提交**：这是生产稳定性的最低要求，不能依赖 `meta.yaml` 动态解析 [事实]
3. **跨 Repo 分支名必须一致**：这是 Foundry 特有的工程约定，与外部 Git 经验不同 [事实]
4. **Marketplace 解决了跨环境发布的核心问题**，但参数化配置需要在设计阶段规划好（事后改造成本高） [推断]
5. **Data Quality Check 内嵌 Transform** 比独立检查脚本更可靠，推荐作为工程规范 [推断]

---

## 参考资料

- Palantir Foundry Documentation: Code Repositories
- Palantir Foundry Documentation: Environment Promotion and Marketplace
- Palantir Engineering Blog: Hawk Package Manager
