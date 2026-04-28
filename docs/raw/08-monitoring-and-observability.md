# Palantir Foundry 监控、可观测性与 SLA 管理调研

**调研日期：** 2026-04-18
**调研方向：** Build 监控 / 告警配置 / SLA 管理 / 性能指标 / 失败诊断 / 可观测性工具

---

## 一、核心可观测性工具体系

Foundry 提供多个内置工具构成完整的可观测性栈：

| 工具 | 用途 | 层次 |
|---|---|---|
| **Builds App** | Build 执行状态与历史记录 | 执行层 |
| **Data Health App** | 规则定义 + 告警配置 + 资源健康看板 | 治理层 |
| **Monitoring Views** | 聚合多资源的监控规则集合 | 运营层 |
| **Live Logs**（2024 Q3） | 正在运行的 Job 的实时日志流 | 调试层 |
| **Job Comparison Tool** | 当前失败 Build 与上次成功 Build 的对比 | 诊断层 |
| **Linter**（2024 Q3） | 主动推荐优化建议（成本/稳定性） | 优化层 |

---

## 二、Build 监控

### 2.1 Build 状态生命周期

```
PENDING（等待调度）
    │
    ▼
RUNNING（Spark Job 执行中）
    │
    ├──▶ SUCCESS（写入新 Transaction）
    │         │ [触发下游 FDS 事件]
    │         ▼
    │    下游 Build 自动触发
    │
    └──▶ FAILED（错误信息记录）
              │
              ▼
         告警触发（配置的渠道）
```

### 2.2 Build History 关键指标

Builds App 展示每次 Build 的：
- 执行时长（Duration）
- Spark 资源消耗（Compute Seconds / vCore-hours）
- 输出行数 / 文件数
- 错误栈追踪（Spark Driver Log）
- Transaction ID（用于数据版本追溯）

### 2.3 Live Logs（2024 年 9 月 GA）

**Live Logs** 在 Builds App 中提供正在运行的 Job 的实时日志流：
- 无需等待 Job 完成才能看日志
- 支持日志过滤（ERROR/WARN/INFO 级别）
- 对调试长时运行 Spark Job 的中间状态非常有价值

---

## 三、Data Health：告警配置中心

### 3.1 监控规则类型

Data Health 支持基于以下维度配置监控规则：

| 规则类型 | 说明 | 示例 |
|---|---|---|
| **Build 失败规则** | N 次连续失败触发告警 | "连续 3 次 Build 失败 → 发送 PagerDuty" |
| **延迟规则（SLA）** | Build 未在预期时间内完成触发告警 | "每日 6:00 前应完成，否则告警" |
| **数据质量规则** | 满足 DataQualityCheck 阈值 | "user_id 非空率低于 99% → 告警" |
| **Schema 变更规则** | 检测到输出 Schema 变化 | "新增/删除字段 → 通知负责人" |
| **活跃 Pipeline 失败** | Streaming Pipeline 同步 Job 失败 | "scroll job 失败 N 次 → HIGH 级告警" |

### 3.2 告警渠道

Foundry Data Health 支持的告警输出渠道：
- **Foundry 内通知**（用户界面 Bell 图标）
- **Slack**（Webhook 集成）
- **PagerDuty**（Incident 自动创建）
- **通用 Webhook**（接入企业告警系统）
- **Email**（基础通知）

### 3.3 告警严重级别

| 级别 | 触发条件示例 | 响应期望 |
|---|---|---|
| CRITICAL | 生产 Pipeline 连续失败 + SLA 违反 | 立即处理 |
| HIGH | 单次失败 / 延迟超阈值 | 1小时内 |
| MEDIUM | 数据质量下降但未完全失败 | 工作时间内 |
| LOW | 性能劣化趋势 / 非关键资源告警 | 下个迭代 |

---

## 四、SLA 管理

### 4.1 SLA 配置方式

在 Data Health 中为关键 Dataset 配置 SLA：
- **Freshness SLA**：数据必须在 X 时间前完成刷新
  - 例：`每日 06:00 前，/prod/orders/daily_summary 必须有新版本`
- **Build Duration SLA**：单次 Build 最大允许执行时长
  - 例：`orders_enrichment Transform 单次 Build 不超过 2 小时`

### 4.2 SLA 违反的影响链分析

Foundry 提供 SLA 影响链可视化：从违反 SLA 的 Dataset 向下游追溯，展示哪些应用/报表依赖了这个 Dataset，评估业务影响范围。

---

## 五、失败诊断工具

### 5.1 Job Comparison Tool

**Job Comparison** 是 Foundry 专为 Pipeline 调试设计的工具：
- 选取"当前失败的 Build"与"上次成功的 Build"进行比较
- 对比维度：
  - 输入数据变化（上游 Dataset 新增了哪些 Transaction）
  - 代码变更（两次 Build 使用的代码 commit 差异）
  - 依赖包版本变化（Conda Lock File 差异）
  - Spark 配置变化（Compute Profile 是否变更）
- 快速定位："代码没变但 Build 突然失败" → 大概率是上游数据变化（Schema 变更或数据异常）

### 5.2 Driver Log 下载

Spark Driver Log 包含完整的异常栈追踪，可直接从 Builds App 下载：
- 常见失败类型：
  - `AnalysisException`：Schema 不匹配（列名/类型错误）
  - `OutOfMemoryError`：数据量超过 Compute Profile 内存限制
  - `ClassNotFoundException`：依赖包缺失（Conda 环境问题）
  - `PermissionDeniedException`：权限不足（Marking 或 Dataset 权限）

### 5.3 LLM Debugging（2024 年 11 月）

Pipeline Builder 中的 **Use LLM Node** 支持查看原始 Prompt 和 LLM 输出：
- 调试 AI 节点时可查看实际发给 LLM 的完整 Prompt
- 对比输入输出，识别 Prompt 工程问题 vs 数据问题

---

## 六、Linter：主动优化建议

**Linter**（2024 年 9 月 GA）是 Foundry 的主动优化分析工具，扫描 Pipeline 并给出建议：

| 建议类别 | 示例 |
|---|---|
| **成本优化** | "这个 Transform 使用了 XL Compute Profile，但历史 Build 平均只用了 S 级别 20% 的资源" |
| **稳定性提升** | "这个 Dataset 有 50+ 下游依赖，但没有配置监控规则" |
| **Ontology 优化** | "这个 Object Type 有 30% 的属性从未被任何应用查询" |
| **增量优化** | "此 Transform 可以启用 @incremental，估算可减少 80% 计算时间" |

---

## 七、资源与成本管理

### 7.1 Compute Profile 选择指南

| Profile | 适用场景 | 注意 |
|---|---|---|
| XS（最小） | 开发调试 / 数据量 < 100MB | 内存限制严格 |
| S | 小规模转换 / < 1GB 数据 | 日常 ETL 默认 |
| M | 中等数据量 / < 10GB | 最常用生产规格 |
| L | 大规模聚合 / ML 特征工程 | 成本显著增加 |
| XL | 超大数据集 / 跨 Dataset Join | 按需使用 |

**Linter 建议**：实际资源消耗远低于 Profile 上限时，自动提示降级。

### 7.2 Job 优先级

Foundry 支持配置 Build 优先级：
- 高优先级 Build 优先获得集群资源
- 低优先级 Build 在资源不足时排队等待
- 实践：生产关键路径用高优先级，开发/测试环境用低优先级

---

## 八、关键结论

1. **Data Health 是运维中枢**：告警配置、SLA 管理、数据质量规则全部收口在此，监控规范化的前提是认真配置 Data Health [事实]
2. **Live Logs 是 2024 年最重要的调试改进**：历史上 Foundry Pipeline 调试体验较差（要等 Job 完成），实时日志大幅改善 [事实]
3. **Job Comparison 是 Foundry 特色工具**：定位"代码未变但 Build 失败"类问题效率极高，值得推广为标准排查流程 [事实]
4. **Linter 可自动发现成本浪费**：建议纳入月度运维 Review，而非被动等问题暴露 [事实]
5. **SLA 配置优先级高于事后告警**：有 SLA 的 Dataset 问题往往有业务影响，应作为工程交付标准之一 [推断]

---

## 参考资料

- Palantir Foundry Platform Updates: September 2024 (Live Logs, Linter GA)
- Palantir Foundry Platform Updates: November 2024 (LLM Node Debug)
- Palantir Foundry Documentation: Data Health and Monitoring
