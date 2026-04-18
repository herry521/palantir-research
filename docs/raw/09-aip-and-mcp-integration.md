# Palantir AIP 与 MCP 协议集成调研

**调研日期：** 2026-04-18
**调研方向：** AIP（AI Platform）架构 / LLM 辅助开发 / AIP Agent / MCP 协议与 Ontology 集成

---

## 一、AIP 整体架构

Palantir AIP（Artificial Intelligence Platform）是建立在 Foundry Ontology 之上的 AI 能力平台，核心设计原则是：**将 LLM 的通用能力与企业专有数据（Ontology）结合，实现有根基的（Grounded）AI 应用**。

### 1.1 AIP 核心组件

| 组件 | 定位 | 说明 |
|---|---|---|
| **AIP Logic** | AI 函数开发环境 | 无代码/低代码开发 LLM 逻辑函数，与 Ontology 深度绑定 |
| **AIP Agent Studio** | AI Agent 构建平台 | 构建可操作 Ontology、执行 Pipeline 的交互式 AI Agent |
| **AIP Assist** | 平台内 LLM 助手 | 自然语言问答、代码生成、文档查询 |
| **AI FDE**（2025 Q4） | 自然语言操作 Foundry | 用自然语言完成数据转换、Ontology 管理等操作 |
| **Pipeline Builder AI 节点** | Pipeline 内嵌 LLM | 在数据管道中直接调用 LLM 处理数据（如文本摘要、分类） |

---

## 二、Ontology Grounding：AIP 的核心差异点

### 2.1 为什么需要 Grounding

普通 LLM 的局限：
- 训练数据截止日期 → 不知道企业当前实际状态
- 无法访问私有数据 → 回答基于通用知识而非企业数据
- 无法执行操作 → 只能生成文字，不能触发实际变更

**Ontology Grounding 的解决方式：**
```
用户自然语言输入
    │
    ▼
AIP 提取语义意图
    │ [查询 Ontology]
    ▼
Ontology Object（企业真实数据 + 关系）
    │ [注入 LLM Context]
    ▼
LLM 基于真实数据生成回答 / 决策
    │ [通过 Ontology Action 执行操作]
    ▼
真实系统状态变更（Pipeline 触发 / 数据写入）
```

### 2.2 AIP Logic：Ontology 绑定函数

AIP Logic 是在 Ontology 上定义 AI 函数的环境：

```python
# AIP Logic 示例（概念性）
@function
def summarize_incident(incident: Incident) -> str:
    """接收 Ontology 中的 Incident 对象，返回 LLM 摘要"""
    prompt = f"""
    事件类型: {incident.type}
    影响范围: {incident.affected_systems}
    当前状态: {incident.status}
    请生成简洁的事件摘要和建议处置步骤。
    """
    return llm.complete(prompt)
```

- 函数的输入输出直接是 Ontology Object，确保数据有血缘和权限控制
- 函数可在 Workshop 应用中被调用，也可被 AIP Agent 调用

---

## 三、AIP Agent Studio：编排 Pipeline 的 AI Agent

### 3.1 Agent 能力范围

AIP Agent Studio 构建的 Agent 可执行的操作：
- **读取 Ontology**：查询对象、关系、属性值
- **执行 Ontology Actions**：修改 Object 属性、创建新 Object（触发 Writeback Pipeline）
- **触发 Build**：手动启动指定 Pipeline 的 Build
- **调用外部工具**：REST API、搜索引擎（Tool Use 模式）
- **多轮交互**：与用户确认后执行操作（支持人机协作循环）

### 3.2 授权与安全约束

**Agent 操作严格受 Foundry 权限体系约束：**
- Agent 以**发起用户身份**执行操作（不是服务账号），继承该用户的所有 Marking/Role 限制
- Agent 无法执行用户本人也无权执行的操作
- 所有 Agent 操作记录在 Foundry 审计日志（包括 LLM 调用的输入/输出）

### 3.3 回滚机制

**AIP Agent 的操作不自带原子回滚**，依赖 Foundry 底层机制：
- Ontology Object 修改通过 Writeback Dataset → Pipeline Build 实现
  - 回滚方式：在 Writeback Dataset 中插入"撤销记录"，重新触发 Build
- Dataset 写入操作通过 Transaction 隔离
  - 回滚方式：将 Dataset 指向上一个 Transaction（需管理员操作）
- **实践建议**：高风险操作需要在 Agent 流程中设计人工确认节点

---

## 四、Pipeline Builder 中的 LLM 节点

### 4.1 Use LLM Node

在 Pipeline Builder 中可以直接插入 **Use LLM Node**：
- 上游节点输出数据 → LLM Node 对每行/每批次调用 LLM
- 典型用例：
  - 文本字段分类（情感分析、主题分类）
  - 非结构化数据提取（从自由文本中提取结构化字段）
  - 批量摘要生成
- **强制输出类型**（2024 年 5 月）：为 LLM 输出配置 Schema，确保下游数据类型一致

### 4.2 调试支持（2024 年 11 月）

2024 年 11 月新增：Use LLM Node 支持查看每次执行的**原始 Prompt 和 LLM 响应**：
- 排查 LLM 输出质量问题（而非代码 Bug）
- 对比不同 Prompt 版本的输出差异
- 支持 Token 消耗统计

### 4.3 支持的 LLM 提供商

Foundry AIP 支持多家 LLM 提供商（需企业配置接入）：
- **Anthropic Claude**（Opus/Sonnet/Haiku）
- **OpenAI GPT**（GPT-4o 系列）
- **Meta LLaMA**（开源模型，私有部署）
- **Google Gemini**
- **xAI Grok**
- 企业私有模型（通过统一接口接入）

---

## 五、MCP 协议与 Foundry 集成

### 5.1 MCP 是什么（背景）

**Model Context Protocol（MCP）** 是 Anthropic 提出的开放协议，标准化 AI 应用（Host/Client）与数据服务（Server）的通信格式，灵感来自 Language Server Protocol（LSP）。

### 5.2 Palantir Foundry MCP Server（2025 年 3 月发布）

Palantir 实现了 Foundry 的 MCP Server，使外部 AI 开发工具（VS Code + Copilot/Cursor 等）可以：
- **读取 Foundry Ontology** → 获取对象类型、属性、关系的语义定义
- **管理 Dataset** → 查看 Schema、查询最近 Build 状态
- **触发操作** → 通过 MCP 工具调用启动 Build
- **修改 Ontology 类型**（受审批流控制）

### 5.3 两种 MCP 能力的区别

Foundry 提供了**两种不同定位**的 MCP 能力：

| 能力 | 目标用户 | 用途 |
|---|---|---|
| **Palantir MCP**（Ontology Builder MCP） | 数据工程师/平台建设者 | 在本地 IDE 中修改 Ontology 类型定义（需人工审批） |
| **Ontology MCP** | 应用开发者 / AI Agent | 暴露 Ontology 资源（Object Type、Action、Query）供 AI Agent 消费 |

### 5.4 MCP 数据流架构

```
本地 IDE（VS Code + Cursor/Copilot）
    │ [MCP Client]
    ▼
Foundry MCP Server（Foundry 侧部署）
    │
    ├── Ontology 查询 → 注入 IDE AI Context
    ├── Dataset Schema 获取 → 辅助代码补全
    └── Build 触发 → 远程执行
    │ [JSON-RPC 2.0 协议]
    ▼
Foundry 内部服务（权限验证 → 执行操作）
```

### 5.5 安全边界

- MCP 操作**完全受 Foundry 权限体系约束**（继承操作用户的 Marking + Role）
- 数据不离开 Foundry 环境（只传 Schema/元数据到本地 IDE）
- Ontology 修改类操作需要在 Foundry 侧进行**人工审批（Proposal Review）**，不允许 AI 直接写入

### 5.6 AI FDE（AI Forward Deployed Engineer，2025 Q4）

AI FDE 是比 MCP Server 更高层的自然语言 Foundry 操作能力：
- 用自然语言描述任务："帮我把 events 表的 user_id 字段与 users 表做 join，输出到 enriched_events"
- AI FDE 自动生成 PySpark 代码 + 配置 Transform + 触发 Build
- 覆盖范围：数据转换、Ontology 配置、Code Repository 操作

---

## 六、关键结论

1. **AIP 的核心价值是 Grounding，不是模型本身**：Foundry 不靠大模型能力出圈，而是靠将 LLM 与 Ontology 绑定，使 AI 操作有数据根基和权限约束
2. **AIP Agent 权限不高于操作用户**：这是 Foundry 安全设计的重要保证，Agent 无法通过 AI 手段提权
3. **MCP Server 是 IDE 与 Foundry 的桥接层**：2025 年发布后，Foundry 开发体验从"必须在浏览器里"转向"本地 IDE + AI 辅助"，工程师体验大幅提升
4. **两种 MCP 定位不同**：Palantir MCP 面向平台构建者（类比 `git`），Ontology MCP 面向应用消费者（类比 REST API）
5. **AI FDE 是 Foundry 的长期战略方向**：从"低代码"向"自然语言操作"进化，目标是大幅降低使用门槛

---

## 参考资料

- Palantir AIP Product Documentation
- Palantir Platform Updates: May 2024 (LLM Node Enforced Output Types)
- Palantir Platform Updates: November 2024 (LLM Node Debug)
- Palantir MCP Server Release Notes: March 2025
- Palantir AI FDE Announcement: Q4 2025
