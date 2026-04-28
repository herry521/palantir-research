# Palantir Foundry 作业运行保障体系调研

**调研日期：** 2026-04-28
**调研方向：** 作业运行保障 / 故障恢复 / 事务一致性 / 流处理保障 / 资源调度 / 数据质量门控 / 可观测性

---

## 一、体系全景

Foundry 的作业运行保障体系分为六个层次，从底层存储到上层运维形成纵深防御：

```
┌─────────────────────────────────────────────────────────────┐
│                  Palantir 作业运行保障体系                     │
├──────────────┬──────────────────────────────────────────────┤
│ 数据一致性层  │ ACID Transaction · 版本不可变 · 写失败回退      │
├──────────────┼──────────────────────────────────────────────┤
│ 批处理故障层  │ Build 事务隔离 · 自动重试 · 并发写保护          │
├──────────────┼──────────────────────────────────────────────┤
│ 流处理保障层  │ Flink Checkpoint · 2PC Exactly-once · 背压    │
├──────────────┼──────────────────────────────────────────────┤
│ 调度资源层   │ Warm Pool · 优先级队列 · 多租户隔离 · Heartbeat  │
├──────────────┼──────────────────────────────────────────────┤
│ 质量门控层   │ 内嵌 DataQualityCheck · CI Check · Data Health │
├──────────────┼──────────────────────────────────────────────┤
│ 可观测性层   │ Live Logs · Job Comparison · Linter · SLA 告警 │
└──────────────┴──────────────────────────────────────────────┘
```

---

## 二、数据一致性层：ACID 事务模型

这是整个保障体系的基石。

### 2.1 Transaction 三种写入类型

| 类型 | 行为 | 一致性特征 |
|---|---|---|
| `APPEND` | 追加新文件，不修改已有数据 | 最弱，但增量友好 |
| `UPDATE` | 覆盖写，修改已有数据 | 中等，触发下游全量重算 |
| `SNAPSHOT` | 原子替换全量数据集 | 最强，全量原子可见 |

### 2.2 核心保障机制

- **写时事务隔离**：Build 开始时锁定所有输入 Dataset 的版本（Transaction ID），读全程不受并发写影响[事实]
- **写失败不污染**：Build 失败时，输出 Dataset 保持上次成功版本不变，不写入中间态[事实]
- **版本历史不可变**：每次成功写入创建新 Transaction，历史版本永久可追溯[事实]
- **原子可见性**：新版本 Transaction 要么完整可见（成功），要么对下游完全不可见（失败）[事实]

---

## 三、批处理故障恢复层

### 3.1 Build 失败恢复流程

```
Build 失败
    │
    ├─ 输出 Dataset 自动回退到上次成功 Transaction
    │
    ├─ 手动重试 / 调度自动重试
    │       └─ 重试前重新检查输入 Transaction 版本
    │
    └─ 失败信息写入 Build History（可追溯）
```

**对于暂态错误（如外部 API 限流）：**
- Automate 功能支持配置自动重试次数与间隔
- 每次重试使用当时最新的输入 Transaction（非重试时的快照）

### 3.2 并发写保护

- 同一 Schedule 下若上一 Build 未完成，新触发排队等待，不并发执行
- 避免多个 Build 同时写同一输出 Dataset 造成事务冲突
- 每个数据集建议仅由一个 Schedule 管理

### 3.3 Managed Profile：自动容量调整

- 分析近期 Build 的实际资源消耗历史[事实]
- 若持续低于 Profile 上限，自动缩减资源规格（成本优化）[事实]
- **不会自动扩容**（超出原始上限），防止雪崩式资源消耗[事实]

---

## 四、流处理保障层：Flink 机制

流处理是保障复杂度最高的层次，Foundry 基于 Apache Flink 构建企业级流处理保障。

### 4.1 Flink Checkpoint 机制

```
Flink Job 运行中
    │
    每隔 N 秒触发 Checkpoint
    ├─ 快照所有算子 State（ValueState/ListState/MapState）
    ├─ 快照 Kafka Consumer Offset
    └─ 写入 Foundry 内部存储（用户透明）

故障发生
    │
    ├─ Job 自动从最近 Checkpoint 恢复
    ├─ 从保存的 Offset 重放 Kafka 消息
    └─ 继续处理，用户无感知
```

### 4.2 一致性级别选择

| 模式 | 语义 | 实现机制 | 代价 |
|---|---|---|---|
| `AT_LEAST_ONCE`（默认） | 至少一次，可能重复 | Checkpoint + Offset 恢复 | 低延迟 |
| `EXACTLY_ONCE` | 精确一次，无重复 | 两阶段提交（2PC）+ 事务性 Sink | 额外延迟开销 |

**EXACTLY_ONCE 适用场景：** 金融交易、计费系统、不可幂等处理的下游系统。[推断]

### 4.3 背压处理

- **Flink Credit-based 流量控制**：下游算子过载时，反压信号逐级向上游传播，上游自动减速
- **计算资源分类**：
  - **Live Processing Compute**：处理实时消息，独立计量
  - **Archiving Compute**：归档到持久化存储，独立计量
  - 两类资源独立，避免归档负载影响实时处理
- Foundry Compute Profile 的资源上限间接限制最大吞吐，防止单 Job 打满集群

---

## 五、调度资源层

### 5.1 Warm Pool（冷启动消除）

- Rubix/OpenShift 部署模式下，维持一批持续运行的 VM 实例池[事实]
- Build 触发时直接从池中分配，消除 JVM 启动 + Conda 环境初始化的 2-5 分钟冷启动时间[事实]
- 对有 Freshness SLA 的关键 Pipeline 效果显著[推断]
- 代价：持续运行有额外 Compute 成本[事实]

### 5.2 Build 优先级队列

- 支持按 Project/Branch 配置资源队列优先级
- 高优先级 Build 优先获得集群资源；低优先级排队等待
- **最佳实践**：关键路径 Pipeline 独立 Project + 高优先级队列；开发/测试环境使用共享低优先级队列

### 5.3 多租户资源隔离

```
Organization（机构）
    └── Space（环境空间，如 Dev / Staging / Prod）
            └── Project（项目）
                    └── Usage Account（计费 / 配额单元）
```

- 每层可独立配置资源限额（Resource Allocation 应用）
- Compute-seconds 作为统一计量单位，在 Project 维度计量
- 不同 Space 的 Compute Profile 配置完全独立（生产 L 级，开发 S 级）

### 5.4 Heartbeat 机制（防僵尸 Job）

- Job 通过心跳持续上报存活状态，而非固定 Timeout 截断[事实]
- 心跳中断 → Job 被标记失败 → 触发告警/重试[事实]
- CI Check 单次超时约 20 分钟，可通过 `JAVA_OPTS` 配置延长[事实]
- Serverless Function 默认 60 秒超时，Deployed Function 最长 280 秒[事实]

---

## 六、数据质量门控层

### 6.1 Build 内嵌质量检查（代码层）

```python
from transforms.verbs.dataframes import DataQualityCheck

@transform_df(
    Output('/project/output/validated_events'),
    source=Input('/project/input/events'),
)
def compute(source):
    df = source.filter('event_type IS NOT NULL')
    return df.with_check(
        DataQualityCheck.not_null('user_id', threshold=0.99),
        DataQualityCheck.schema_match(expected_schema),
    )
# 不满足阈值 → Build 失败，不写入新 Transaction
```

### 6.2 CI Check（合并前门控）

| Check 类型 | 触发时机 | 阻断能力 |
|---|---|---|
| Build Check | PR 创建/Push | 阻断 Merge |
| Unit Test Check | PR 创建/Push | 阻断 Merge |
| Data Quality Check | Build 执行后 | 阻断 Merge |
| Schema Expectations | 输出 Schema 验证 | 阻断 Merge |
| Lint Check | PR 创建/Push | 阻断 Merge |

### 6.3 Data Health 运行时监控规则

| 规则类型 | 触发时机 | 说明 |
|---|---|---|
| Build 连续失败 N 次 | 运行后 | 触发告警 |
| Freshness SLA 违反 | 未在 T 时前完成 | 触发告警 + 影响链分析 |
| 数据质量阈值违反 | 每次 Build 后检查 | 可配置为阻断下游触发 |
| Schema 变更检测 | 输出 Schema 变化 | 通知负责人 |
| Streaming Pipeline 失败 | 同步 Job 失败 | HIGH 级告警 |

**Schema 变更分类：**[事实]
- **Non-breaking**（非破坏性）：新增列、修改展示名 → 自动处理[事实]
- **Breaking**（破坏性）：修改主键、修改数据类型 → 走 Migration 框架，需人工确认[事实]

---

## 七、可观测性层

### 7.1 工具矩阵

| 工具 | 用途 | 典型场景 |
|---|---|---|
| **Builds App** | Build 状态 + 历史记录 | 日常运维巡检 |
| **Live Logs** | 正在运行 Job 的实时日志流 | 长 Job 中间状态调试 |
| **Job Comparison Tool** | 失败 vs 成功 Build 对比 | "代码未变但 Build 失败"排查 |
| **Data Health App** | 监控规则 + 告警 + SLA 管理 | 运营看板 |
| **Linter** | 主动扫描优化建议 | 月度运维 Review |

### 7.2 Job Comparison 对比维度

- 输入数据变化（哪些 Transaction 在两次 Build 之间新增）
- 代码 Commit 差异（两次 Build 使用的代码版本）
- Conda Lock 依赖版本差异（包版本是否变化）
- Compute Profile 变化（规格是否调整）

### 7.3 SLA 违反影响链

Data Health 提供 SLA 影响链可视化：
- 从违反 SLA 的 Dataset 向下游追溯
- 展示哪些应用/报表/Object Type 依赖了该 Dataset
- 评估业务影响范围，辅助优先级决策

### 7.4 告警渠道

- Foundry 内部通知（Bell 图标）
- Slack Webhook 集成
- PagerDuty（自动创建 Incident）
- 通用 Webhook（接入企业告警系统）
- Email

---

## 八、关键结论

1. **事务模型是基石**：Build 失败不污染输出，输出版本原子可见，这是整个体系可靠性的前提。Foundry Dataset 的 Transaction 机制相当于数据层的 ACID 保障。[事实]

2. **批流保障机制分离**：批处理依赖 Transaction 隔离，流处理依赖 Flink Checkpoint + 2PC，两套机制协同工作但实现完全不同，是 Foundry 保障体系最复杂的地方。[事实]

3. **Exactly-once 需主动开启**：默认 AT_LEAST_ONCE，选用 EXACTLY_ONCE 需权衡延迟代价（2PC 开销）；金融/计费场景强制开启。[事实]（前半句为官方文档直接支撑；"强制开启"为最佳实践推断）

4. **Warm Pool 解决冷启动的 SLA 痛点**：对于有严格 Freshness SLA 的关键 Pipeline，Warm Pool 是消除 5 分钟冷启动延迟的核心机制，但持续运行有额外成本。[事实]

5. **Job Comparison 是 Foundry 差异化工具**：对比两次 Build 的输入数据/代码/依赖/配置变化，能快速定位"代码未变但 Build 突然失败"类问题，无需手动排查。[事实]

6. **Data Health 配置是运维规范化的关键差距**：技术能力完备，但实际效果强依赖工程团队认真配置监控规则和 SLA，这是落地时最容易被忽略的环节。[推断]

7. **质量门控是双层设计**：Build 内嵌 DataQualityCheck（运行时门控）+ CI Check（合并前门控）双重保障，不满足质量要求的数据不会写入新 Transaction，也不会合并到主分支。[事实]

---

## 九、与自建平台的差距参考

| 保障能力 | Foundry 成熟度 | 自建难点 |
|---|---|---|
| 事务版本隔离 | ★★★★★ | 需要自研 Dataset 版本管理层 |
| Flink 故障恢复 | ★★★★★ | Flink 原生，需运维 Checkpoint 存储 |
| Exactly-once | ★★★★☆ | 需严格的 2PC + 幂等 Sink 设计 |
| Warm Pool | ★★★★☆ | 需要 K8s PreWarmed Pod 池管理 |
| Data Health 一体化 | ★★★★☆ | 通常需要独立监控系统（Prometheus + Grafana） |
| Job Comparison | ★★★☆☆ | 需自建 Build 元数据对比服务 |

---

## 参考来源

- Palantir Foundry 文档：Transactions、Incremental Transforms、Build Retries
- Palantir Foundry 文档：Flink Streaming Pipelines、Exactly-once semantics
- Palantir Platform Updates 2024 Q3（Live Logs、Linter GA）
- Palantir Resource Management 文档：Compute Profiles、Warm Pool、Priority Queues
- Apache Flink 官方文档：Checkpointing、Two-Phase Commit Sink
