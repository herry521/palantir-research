# Paimon 轻量引擎 Scan Adapter 设计

**日期：** 2026-06-18
**关联 Issue：** #67
**状态：** 设计草案
**关联调研：** `docs/synthesis/paimon-lightweight-engine-research.md`

---

## 1. 总结与洞察

1. 【结论】“Paimon Java Scan Service + Arrow Flight/IPC + DataFusion/Polars/DuckDB”方向可行，但应收敛为“Paimon Scan Adapter sidecar + Arrow IPC/Flight + DataFusion 主执行器”。
2. 【风险】中心化 Scan Service 会引入跨网络数据搬运和多租户瓶颈，容易抵消轻量引擎收益；第一期应采用同 Pod/同节点 sidecar。
3. 【风险】第一期同时支持 DataFusion、Polars、DuckDB 三个一等执行内核会扩大接口、类型和测试矩阵；应先以 DataFusion 为主，Polars/DuckDB 后续消费同一 Arrow stream。
4. 【约束】Paimon 表语义必须由 Paimon Java reader 解释。禁止直接扫描底层 Parquet/ORC 作为生产路径，尤其是 Primary Key 表。
5. 【验收】可行性 POC 必须证明结果与 Spark/Flink Paimon connector 一致，并在 preview、小中规模 batch、append-only 增量读上获得可观启动和执行收益。

---

## 2. 背景

现有调研建议使用 Paimon Java API 保障 Paimon snapshot、split、projection/filter、Primary Key latest view、merge engine 和 compaction 语义，再通过 Arrow 把列式数据交给轻量执行器。用户进一步要求评估该决策是否有风险，并形成一个经过可行性分析的方案。

本设计只覆盖轻量读路径与第一阶段 batch/preview 能力，不覆盖流式 Flink 计算、PK upsert 写入、changelog 输出和大规模分布式 shuffle。

---

## 3. 设计目标

### 3.1 必须满足

- 读取必须绑定明确 Paimon snapshot、tag 或 build input version。
- Append 表支持 snapshot read 和 delta read。
- Primary Key 表第一期只支持 latest-view read，不支持 changelog 输出。
- Scan Adapter 支持 projection/filter 下推，但必须返回 `acceptedPredicates` 与 `residualPredicates`。
- DataFusion 执行 residual predicate、表达式、聚合、小表 join、排序和 limit。
- 每次执行记录用户、build、snapshot、列、谓词、文件数、bytes、耗时、峰值内存和 fallback 原因。

### 3.2 明确不做

- 不直接扫描 Paimon 底层 Parquet/ORC 作为生产路径。
- 不在第一期支持 PK upsert 写入。
- 不在第一期支持 changelog sink 或 streaming sink。
- 不承诺大表 join、大 shuffle、复杂窗口、复杂 UDF。
- 不把 Scan Adapter 做成共享中心化数据服务。

---

## 4. 架构选择

### 4.1 备选方案

| 方案 | 架构 | 优点 | 风险 | 结论 |
|---|---|---|---|---|
| A | Java Scan Adapter sidecar + Arrow + DataFusion | 正确性优先；复用 Paimon Java reader；执行链路仍轻 | Java row 到 Arrow 转换成本；需要定义 pushdown 子集 | 推荐 |
| B | Rust DataFusion 原生 Paimon `TableProvider` | 链路最短，性能潜力最高 | 需要重写 Paimon snapshot、LSM、merge、schema evolution、changelog 语义 | 后续评估 |
| C | PyPaimon + Polars/DuckDB | POC 快，贴近 Python 生态 | 生产成熟度、类型一致性、权限审计路径不稳定 | 仅 POC |
| D | 中心化 Scan Service + Arrow Flight | 治理、缓存和复用集中 | 网络搬运重，多租户瓶颈明显，轻量收益不确定 | 不推荐 |

### 4.2 推荐方案

采用方案 A：`Paimon Scan Adapter sidecar + Arrow IPC/Flight + DataFusion primary executor`。

```text
Transform / SQL / Preview Request
        |
        v
Engine Router
        |
        v
Lightweight Runtime Pod
  ├─ DataFusion Executor
  │   - SQL / logical plan
  │   - residual filter / expressions
  │   - aggregation / small join / sort / limit
  │   - memory limit / spill / metrics
  │
  └─ Paimon Scan Adapter sidecar
      - catalog/table/snapshot pin
      - Paimon Java API split planning
      - projection/filter pushdown
      - PK latest-view materialization
      - Arrow IPC / Flight stream
```

---

## 5. 组件设计

### 5.1 Engine Router

职责：

- 判断请求是否可以走轻量路径。
- 选择 `APPEND_SNAPSHOT`、`APPEND_DELTA` 或 `PK_LATEST_VIEW`。
- 给出 explainable routing reason。
- 在超出边界时路由 Spark/Flink。

轻量准入条件：

- 预计扫描量、输出量和 shuffle 在单节点资源限制内。
- 算子是 filter、projection、简单表达式、低基数 aggregation、小表 join、preview 或 sample。
- 输入是 Append 表，或 PK 表 latest view。
- 输出是只读、append 或 snapshot replace。

### 5.2 Paimon Scan Adapter

职责：

- 解析 Paimon catalog/database/table。
- 固定 snapshot/tag/branch。
- 将 DataFusion candidate predicates 翻译成 Paimon predicate 子集。
- 使用 Paimon Java API plan splits。
- 使用 Paimon reader 读取 split。
- 对 PK 表产出 latest view。
- 将 Paimon `InternalRow` 转为 Arrow RecordBatch。
- 通过 Arrow IPC 或 Flight stream 输出。

设计约束：

- Adapter 只下推能证明语义一致的谓词。
- Adapter 不执行业务表达式、不做复杂 join、不做全局聚合。
- Adapter 必须支持 cancellation 和 backpressure。
- Adapter 必须在任务结束后释放 reader、stream 和临时资源。

### 5.3 DataFusion Executor

职责：

- 接收 Arrow stream 并注册为 DataFusion table。
- 执行 residual predicates。
- 执行表达式、聚合、小表 join、排序、limit。
- 控制内存、spill、超时和取消。
- 输出 Arrow batch 或写入 Commit Adapter。

第一期只把 DataFusion 作为主路径。Polars/DuckDB 后续通过同一 Arrow stream 接入，不改变 Scan Adapter 接口。

---

## 6. 接口草案

### 6.1 ScanRequest

| 字段 | 类型 | 说明 |
|---|---|---|
| `catalog` | string | Paimon catalog 标识 |
| `database` | string | database |
| `table` | string | table |
| `branch` | string | 可选，分支 |
| `snapshotId` | long | 可选，优先使用的版本锚点 |
| `tag` | string | 可选，tag 版本 |
| `projection` | string[] | 需要读取的列 |
| `candidatePredicates` | expression[] | 尝试下推的谓词 |
| `limit` | long | preview/sample 场景可用 |
| `readMode` | enum | `APPEND_SNAPSHOT`、`APPEND_DELTA`、`PK_LATEST_VIEW` |
| `batchSize` | int | Arrow batch 目标大小 |
| `traceId` | string | 链路追踪 |
| `buildId` | string | 构建标识 |
| `user` | string | 审计用户 |

### 6.2 ScanResponse

| 字段 | 类型 | 说明 |
|---|---|---|
| `resolvedSnapshotId` | long | 实际读取 snapshot |
| `resolvedSchema` | ArrowSchema | Arrow schema |
| `acceptedPredicates` | expression[] | 已安全下推的谓词 |
| `residualPredicates` | expression[] | 必须由 DataFusion 再执行的谓词 |
| `splitCount` | long | split 数 |
| `estimatedBytes` | long | 估算扫描字节 |
| `streamTicket` | string | Arrow IPC/Flight stream 标识 |
| `scanMetrics` | object | 文件数、裁剪数、读 bytes、耗时 |

---

## 7. 数据流

1. Runtime 固定输入 dataset 的 branch、snapshot 或 build input version。
2. Engine Router 判断表类型、read mode、资源边界和 fallback 条件。
3. DataFusion planner 生成 candidate predicates 和 projection。
4. Scan Adapter 翻译可下推谓词，调用 Paimon Java API 生成 splits。
5. Scan Adapter 用 Paimon reader 读取 splits，输出 Arrow RecordBatch。
6. DataFusion 执行 residual predicates 和剩余计算。
7. 输出到 preview API，或进入后续 Commit Adapter。
8. Runtime 写入 metrics、lineage、build history 和审计事件。

---

## 8. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 直接读 Parquet/ORC 绕过 Paimon | PK 表结果错误 | 生产路径禁止；只允许 Paimon reader |
| 中心化 Scan Service 网络搬运 | 性能收益不稳定 | 同 Pod/同节点 sidecar；Flight 只做本地或近端流 |
| 谓词翻译不一致 | 漏读或误裁剪 | 返回 residual predicates；保守下推 |
| 类型映射错误 | 数据精度或时间语义错误 | decimal、timestamp、nested type 建专项一致性测试 |
| compaction 与 snapshot 并发 | 重复读或漏读 | 固定 snapshot；记录 resolvedSnapshotId |
| 内存失控 | 单节点稳定性风险 | memory limit、spill、timeout、cancellation |
| 多执行器扩张 | 测试矩阵失控 | 第一阶段只做 DataFusion 主路径 |

---

## 9. 可行性 POC

### 9.1 POC 范围

- Append 表 snapshot read。
- Append 表 delta read。
- PK 表 latest-view read。
- projection/filter/limit 下推。
- DataFusion residual filter、简单聚合、小表 join。
- Arrow IPC 优先；Flight 作为可选 transport 对比。

### 9.2 测试数据

- Append 表：1GB、10GB、50GB 三档。
- PK 表：包含 insert、update、delete、partial update、compaction 前后快照。
- Schema：覆盖 int、long、double、decimal、string、timestamp、array/map/row。

### 9.3 验收标准

- 正确性：同一 snapshot 下，与 Spark/Flink Paimon connector 查询结果一致。
- 一致性：compaction 前后、schema evolution 后、snapshot pin 后结果不变。
- 性能：10GB 以内裁剪友好任务端到端耗时明显低于 Spark；启动时间为秒级。
- 稳定性：内存限制、backpressure、任务取消和 reader 释放可验证。
- 治理：每次读取记录 snapshot、谓词、列、文件数、bytes、用户和 traceId。

---

## 10. 参考依据

- Apache Paimon Java API: <https://paimon.apache.org/docs/1.3/program-api/java-api/>
- Apache Arrow Flight RPC: <https://arrow.apache.org/docs/format/Flight.html>
- Apache DataFusion Custom Table Provider: <https://datafusion.apache.org/library-user-guide/custom-table-providers.html>
- Apache Paimon Releases: <https://paimon.apache.org/releases/>
- 调研文档：`docs/synthesis/paimon-lightweight-engine-research.md`
