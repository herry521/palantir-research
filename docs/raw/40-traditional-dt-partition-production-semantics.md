# 传统 `dt` 分区生产控制语义

关联 Issue：#32
日期：2026-05-30

## 总结与洞察

1. 【事实】在 DataWorks 中，`$bizdate` 表示业务日期/数据时间，日调度默认等于调度时间前一天；`$cyctime` 表示任务实例的理论调度时间，不随资源排队或实际启动延迟改变。
2. 【事实】Hive 和 MaxCompute/ODPS 都把分区写入作为 DML 的一等语义：`LOAD DATA ... PARTITION`、`INSERT OVERWRITE ... PARTITION` 可以定向写入或覆盖指定分区。
3. 【推断】传统离线数仓里的 `dt` 不只是查询字段，而是“生产控制面”：调度实例、补数据边界、幂等覆盖、质量阻断、SLA、生命周期和血缘排查都围绕同一个业务日期分区展开。
4. 【建议】日、周、月离线任务应把目标分区明确绑定到业务日期参数，而不是实际运行日期；补跑时以业务日期范围为边界，优先用 `INSERT OVERWRITE ... PARTITION(dt=...)` 保持幂等。
5. 【证据边界】MaxCompute 官方文档能证明分区 DDL、覆盖写、生命周期、分区操作等机制，但未找到官方直接把 `dt` 称为“生产控制面”的表述；本文对该概念的命名是基于 DataWorks 调度语义与 MaxCompute/Hive 分区语义的综合归纳。

## 1. 核心结论：`dt` 是调度和数据之间的契约

【事实】DataWorks 的调度参数会在每次任务运行时被替换为实例对应的时间值；`$bizdate` 等价于业务日期格式 `${yyyymmdd}`，`$cyctime` 等价于调度时间格式 `$[yyyymmddhh24miss]`。

当离线任务写出如下 SQL 时，`dt` 就不再只是表里的一个分区列，而是 DataWorks 实例和物理数据分区之间的契约：

```sql
INSERT OVERWRITE TABLE dwd_order_di PARTITION (dt='${bizdate}')
SELECT ...
FROM ods_order_di
WHERE dt='${bizdate}';
```

【推断】这个契约的含义是：某个调度实例负责生产某个业务日期的分区。实例的成功、失败、重跑、补数据、质量检查和 SLA 都最终落到“`table/dt=YYYYMMDD` 是否正确产出”这个问题上。

## 2. DataWorks：业务日期和调度时间不是同一件事

| 概念 | DataWorks 语义 | 常见用途 |
|---|---|---|
| 业务日期 | `$bizdate` / `${yyyymmdd}`，日调度默认等于调度时间前一天 | 选择要处理的数据分区，如 `dt=20260529` |
| 调度时间 | `$cyctime` / `$[yyyymmddhh24miss]`，实例配置中的理论运行时间 | 标识任务计划在何时运行，如 `20260530020000` |
| 实际运行时间 | 受上游完成、资源排队、实例状态影响 | 不应用作业务分区边界 |

【事实】典型 T+1 离线任务在今天凌晨运行，处理昨天发生的业务数据。例如任务在 2026-05-30 02:00 调度运行，则业务日期通常是 2026-05-29，目标分区应是 `dt=20260529`，而不是 `dt=20260530`。

SQL 中用于读写分区的参数应优先使用业务日期：

```sql
WHERE dt='${bizdate}'
```

【建议】只有当业务逻辑确实需要实例调度时刻时，才使用 `$cyctime`，例如小时级窗口、审计字段或运行批次标识。

## 3. 周期实例、补数据和业务日期输入

【事实】DataWorks 周期实例是根据任务调度周期生成的运行实体；实例承载执行状态、日志和运行操作。周期任务每次到期运行都会生成实例，例如小时任务每天生成多个实例，日任务每天生成一个实例。

【事实】DataWorks 补数据会为指定历史或未来时间范围生成补数据实例，并用所选业务时间替换任务代码中的调度参数，使代码写入对应时间分区。

【事实】DataWorks 文档明确说明，补数据的时间选择是业务日期；周/月任务补数据时需要选择实际调度日期的前一天作为业务时间，因为业务日期等于调度日期减一天。

因此补数据边界不是“今天我点了重跑”，而是“我要重算哪些业务日期的分区”。例如补跑一周：

```text
补跑范围：2026-05-18 到 2026-05-24
目标分区：dt=20260518 ... dt=20260524
实际提交日期：不应影响 dt
```

【事实】DataWorks 补数据默认可按业务日期串行执行；开启分组执行后，不同业务日期可并行分组执行。小时/分钟任务在同一天内是否串行，受自依赖配置影响。

【建议】对强依赖前后日期状态的任务，例如累计快照、余额、库存快照，应让补数据按业务日期顺序执行；对互不依赖的日分区聚合，可考虑分组并行补数。

## 4. Hive 分区写入语义

【事实】Hive 使用 `PARTITIONED BY` 创建分区表。分区列是虚拟列或伪列，不是原始数据文件中的普通字段，而是从数据被装载到的分区派生出来。每个分区值组合对应独立的数据目录。

```sql
CREATE TABLE page_view (
  viewTime INT,
  userid BIGINT,
  page_url STRING
)
PARTITIONED BY (dt STRING, country STRING);
```

【事实】Hive `LOAD DATA ... PARTITION` 可以把文件装载到指定分区；如果使用 `OVERWRITE`，目标表或分区原有内容会被删除并替换。

```sql
LOAD DATA LOCAL INPATH './kv2.txt'
OVERWRITE INTO TABLE invites
PARTITION (ds='2008-08-15');
```

【事实】Hive `INSERT OVERWRITE TABLE ... PARTITION` 会把查询结果写入指定表或分区，并覆盖已有数据；`INSERT INTO` 则追加数据。

```sql
INSERT OVERWRITE TABLE page_view PARTITION (dt='20260529')
SELECT viewTime, userid, page_url
FROM page_view_stg
WHERE dt='20260529';
```

【推断】这正是 `dt` 能成为幂等生产边界的原因：同一个业务日期重跑时，覆盖同一个分区，而不是追加重复数据。

## 5. MaxCompute/ODPS 分区写入和生命周期

【事实】MaxCompute 支持通过 `CREATE TABLE ... PARTITIONED BY` 创建普通分区表，分区表最多 6 级分区，默认最多 60,000 个分区。

```sql
CREATE TABLE IF NOT EXISTS sale_detail (
  shop_name STRING,
  customer_id STRING,
  total_price DOUBLE
)
PARTITIONED BY (dt STRING);
```

【事实】MaxCompute `INSERT INTO` 会向表或静态分区追加数据；`INSERT OVERWRITE` 会清空指定表或静态分区原有数据，再写入新数据。

```sql
INSERT OVERWRITE TABLE sale_detail PARTITION (dt='20260529')
SELECT shop_name, customer_id, total_price
FROM sale_detail_stg
WHERE dt='20260529';
```

【事实】MaxCompute 支持动态分区写入；如果目标分区不存在，写入时可自动创建分区。但官方也提示并发写入不存在分区时存在限制，必要时应提前 `ALTER TABLE ADD PARTITION`。

【事实】MaxCompute 生命周期按表或分区的 `LastModifiedTime` 计算。对分区表，系统会按分区回收过期数据，而不是删除整张表。

【推断】`dt` 与生命周期共同构成保留策略边界：一张表可以保留最近 N 天或 N 年的业务分区。但生命周期基于最后修改时间，不等同于 `dt` 字面日期；旧分区被补跑或 `touch` 后，可能延后回收。

## 6. `dt` 承载的生产控制语义

| 控制语义 | 结论 |
|---|---|
| 业务日期 | 【事实】DataWorks `$bizdate` 表示数据所属业务日期，常用于 `WHERE dt='${bizdate}'` 和 `PARTITION(dt='${bizdate}')`。 |
| 调度实例 | 【事实】周期实例按业务日期和调度配置生成，实例状态、日志、重跑操作挂在实例上。 |
| 补数边界 | 【事实】补数据按选择的业务时间替换参数；因此补跑范围天然映射为一组 `dt` 分区。 |
| 幂等覆盖 | 【事实】Hive/MaxCompute `INSERT OVERWRITE ... PARTITION` 覆盖指定分区；这使同一 `dt` 重跑可得到单一最终结果。 |
| SLA | 【推断】DataWorks 基线用优先级、承诺完成时间、预警余量监控任务产出；对离线数仓而言，SLA 实际落在某个业务日期分区何时可用。 |
| 数据质量 | 【事实】DataWorks Data Quality 可用分区表达式如 `dt=$[yyyymmdd-1]` 监控分区，强规则失败会阻断下游。 |
| 生命周期 | 【事实】MaxCompute 对分区表按分区 `LastModifiedTime` 回收过期数据；`dt` 是保留、清理和成本治理的自然粒度。 |
| 分区血缘 | 【推断】DataWorks Data Map 通过解析调度作业和同步作业生成表/字段血缘，并展示分区信息；当 SQL 使用 `dt=${bizdate}` 时，血缘排查可从“实例业务日期”定位到“输入/输出分区”。 |
| 证据缺口 | 【证据边界】DataWorks/MaxCompute 官方资料未证明其提供完整、统一的“分区级血缘图”语义；更稳妥的表述是：官方支持表/字段血缘、分区信息和调度参数，分区级因果关系需结合实例参数、SQL 和表分区共同确认。 |

## 7. 典型案例

### 7.1 T+1 日任务

T+1 表示今天调度处理昨天业务数据。

```text
调度时间：2026-05-30 02:00:00
$cyctime：20260530020000
$bizdate：20260529
目标分区：dt=20260529
```

```sql
INSERT OVERWRITE TABLE ads_order_1d PARTITION (dt='${bizdate}')
SELECT ...
FROM dwd_order_di
WHERE dt='${bizdate}';
```

【建议】SLA 应描述为“`ads_order_1d/dt=20260529` 在 2026-05-30 08:00 前产出”，而不是笼统描述为“今天的任务完成”。

### 7.2 补跑一周

```text
补跑业务日期：2026-05-18 到 2026-05-24
产生分区：dt=20260518 ... dt=20260524
```

DataWorks 会按补数据业务时间替换调度参数。目标 SQL 应覆盖对应分区：

```sql
INSERT OVERWRITE TABLE dws_user_1d PARTITION (dt='${bizdate}')
SELECT ...
FROM dwd_user_di
WHERE dt='${bizdate}';
```

【推断】如果使用追加写或实际运行日期作为分区，补跑会造成重复、错分区或污染当前分区。

### 7.3 跨周期依赖

【事实】DataWorks 支持不同调度周期之间的实例依赖，例如日任务依赖小时任务。日任务直接依赖小时任务时，可能等待当天所有小时实例完成；若要等待上一天小时实例，需要配置跨周期依赖或依赖检查。

日汇总任务 `dws_event_1d/dt=20260529` 应明确依赖 2026-05-29 的小时分区，例如：

```text
上游小时分区：ods_event_hi/dt=20260529/hh=00 ... hh=23
下游日分区：dws_event_1d/dt=20260529
调度运行日：2026-05-30
```

【推断】这里 `dt` 是跨周期对齐键：小时实例、日实例和数据分区用同一个业务日期对齐。

### 7.4 周任务

【事实】DataWorks 周任务在非调度日会生成 dry-run 实例以保证下游依赖可继续解析；补跑周任务时，应选择实际调度日前一天作为业务时间。

如果周任务每周一 03:00 处理上周一到周日数据，可把业务日期设为周日：

```text
调度日期：2026-06-01 周一
业务日期：2026-05-31 周日
目标分区：dt=20260531 或 week_end=20260531
```

【建议】周任务 SQL 不应简单使用实际运行日期推导周边界，而应从业务日期推导 `week_start` 和 `week_end`，确保补跑历史周时边界稳定。

### 7.5 月任务

【事实】DataWorks 月任务补数据同样遵循业务日期等于调度日期减一天。例如每月 1 日 00:00 运行的月任务，补数据时应选择上月最后一天作为业务时间。

```text
调度日期：2026-06-01
业务日期：2026-05-31
目标分区：dt=20260531 或 bizmonth=202605
```

【建议】月表如果使用 `dt`，应明确 `dt` 表示月末业务日期；如果使用 `bizmonth`，应避免和日表 `dt` 混淆。

## 8. 工程建议

1. 【建议】所有离线产出表都应在表注释或数据字典中说明 `dt` 的语义：是交易发生日、快照日、统计截止日、账期日，还是调度业务日期。
2. 【建议】生产 SQL 优先采用静态分区覆盖：

```sql
INSERT OVERWRITE TABLE target PARTITION (dt='${bizdate}')
SELECT ...
WHERE dt='${bizdate}';
```

3. 【建议】补数据前检查三类边界：业务日期范围、上游分区范围、下游覆盖范围。三者不一致时，不应启动批量补跑。
4. 【建议】对强 SLA 表配置 DataWorks 基线和 Data Quality 强规则，把“分区非空、主键唯一、波动阈值”等检查绑定到 `dt=${bizdate}` 对应分区。
5. 【建议】对 MaxCompute 分区生命周期要单独审查补跑影响：旧 `dt` 分区被覆盖后，`LastModifiedTime` 更新，可能改变自动回收时间。

## 参考资料 URL

- https://www.alibabacloud.com/help/en/dataworks/user-guide/supported-formats-of-scheduling-parameters
- https://www.alibabacloud.com/help/en/dataworks/data-backfilling
- https://www.alibabacloud.com/help/en/dataworks/user-guide/detailed-description-of-scheduling-cycle-of-data-studio
- https://www.alibabacloud.com/help/en/dataworks/user-guide/backfill-data-for-an-auto-triggered-node-and-view-data-backfill-instances-of-the-node
- https://www.alibabacloud.com/help/en/dataworks/scheduling-dependencies
- https://www.alibabacloud.com/help/en/dataworks/user-guide/configure-cross-cycle-scheduling-dependencies
- https://www.alibabacloud.com/help/en/dataworks/product-overview/terms
- https://www.alibabacloud.com/help/en/dataworks/user-guide/intelligent-baseline/
- https://www.alibabacloud.com/help/en/dataworks/user-guide/configure-rules-to-monitor-data-quality
- https://www.alibabacloud.com/help/en/dataworks/user-guide/datastudio-configuration-data-quality-monitoring
- https://www.alibabacloud.com/help/en/dataworks/user-guide/maxcompute-table-data
- https://www.alibabacloud.com/help/en/dataworks/user-guide/view-lineages
- https://hive.apache.org/docs/latest/language/languagemanual-ddl/
- https://hive.apache.org/docs/latest/language/languagemanual-dml/
- https://hive.apache.org/development/gettingstarted-latest/
- https://www.alibabacloud.com/help/en/maxcompute/user-guide/create-table
- https://www.alibabacloud.com/help/en/maxcompute/user-guide/insert-or-update-data-into-a-table-or-a-static-partition
- https://www.alibabacloud.com/help/doc-detail/73779.html
- https://www.alibabacloud.com/help/en/maxcompute/user-guide/partition-operation
- https://www.alibabacloud.com/help/en/maxcompute/product-overview/lifecycle
