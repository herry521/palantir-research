# 湖仓布局、分区裁剪与成本模型对比

关联 Issue：#34
日期：2026-05-30

## 总结与洞察

1. 【事实】传统 `dt` 分区和 Foundry Hive-style partitioning 本质上是目录级物理布局：把分区值编码到路径和元数据中，查询过滤命中分区列时跳过目录/文件。
2. 【事实】Iceberg 把分区从用户 SQL 中隐藏，通过 partition transforms、manifest list、manifest file 与文件级统计做裁剪，并支持 partition evolution。
3. 【事实】BigQuery 的成本模型直接绑定 bytes processed；partition pruning 和 clustering block pruning 会减少扫描字节，聚簇表的预估字节数通常只是上界。
4. 【事实】Snowflake 不暴露 Hive 式目录分区，而是自动写入 micro-partitions，并用 min/max、distinct、overlap/depth 等元数据在运行时自动 pruning。
5. 【建议】不要把 table partition、projection、stream partition、compute partition 混用：它们分别服务于存储裁剪、二级物化布局、流式顺序/并行、执行并行度，设计目标和成本含义不同。

## 1. 概念边界

本文把“partition”拆成四层：

| 名称 | 所在层 | 主要目的 | 是否持久化为表布局 | 典型例子 |
|---|---|---:|---:|---|
| Table/layout partition | 存储布局 | 查询裁剪、生命周期管理 | 是 | Hive `dt=.../`、BigQuery partition |
| Projection | 二级物化/索引布局 | 针对过滤、join、聚合优化 | 是，但通常独立于 canonical table | Foundry dataset projection |
| Stream partition | 流日志分片 | 顺序保证、消费者并行 | 是，但属于消息日志，不等于湖仓表布局 | Kafka topic partition、Foundry stream partition key |
| Compute partition | 执行计划分片 | 任务并行、shuffle、内存控制 | 否，通常是临时执行状态 | Spark RDD/DataFrame partition |

【推断】同一个词在这些层里含义不同。一个 Kafka partition 不会天然变成 Hive `dt` 分区；一次 Spark `repartition(200)` 也不会定义表的分区规范；Foundry projection 也不是目录分区，而是附加的优化表示。

## 2. 传统 `dt` 分区与 Hive Partition Pruning

【事实】Hive 分区表通过 `PARTITIONED BY` 定义一个或多个分区列；每组分区值会对应独立数据目录，例如 `dt=2026-05-30/country=US/`。分区列像伪列一样参与查询，但值主要来自路径和 metastore，而不一定存在于数据文件内部。

【事实】Hive partition pruning 的核心是：优化器根据 `WHERE dt = ...`、`WHERE dt BETWEEN ...` 等分区列谓词，只枚举和读取匹配分区，跳过其他目录。它先减少目录/文件集合，再由 Parquet/ORC 的列裁剪、谓词下推、row group 统计继续减少实际读取。

【事实】静态分区裁剪发生在编译/规划阶段；动态分区裁剪可在 join 等场景下利用运行时产生的小表值集合裁剪大表分区，但要求谓词能映射到大表分区列，且不能被函数或表达式破坏。

【推断】传统 `dt` 分区的成本收益主要来自“少列目录、少读文件、少启动 task”。在自建 Hive/Spark 集群里，它通常体现为更低 I/O、调度和运行时间；在按扫描计费的引擎里，则进一步体现为 bytes scanned 降低。

【建议】`dt` 适合低到中等基数、访问模式稳定、常按日期过滤的数据。不要把用户 ID、订单 ID、毫秒级时间戳等高基数字段直接做 Hive 目录分区，否则会产生大量小文件、metastore 压力和目录枚举开销。

## 3. Spark Partition 与 Hive Partition 的差异

【事实】Spark compute partition 是执行并行度单位：RDD/DataFrame 被切成多个 partition，每个 partition 通常对应 task 的输入单位；`repartition` 会通过 shuffle 重新分布数据，`coalesce` 常用于减少 partition 数。

【事实】Spark `DataFrameWriter.partitionBy(...)` 是另一回事：它把输出按列值写成类似 Hive 的文件系统布局。Spark 文档明确说明该输出按给定列在文件系统上 partition，布局类似 Hive partitioning scheme。

【事实】Spark 读取 Parquet/ORC/CSV/JSON 等文件源时可以自动发现 Hive-style 路径中的分区列，例如 `gender=male/country=US/`，并把这些路径值变成 DataFrame 列，用于 partition pruning。

【建议】写入 Hive-style 数据前，通常需要先用 `repartitionByRange`、`repartition` 或排序控制 Spark 执行分布，否则每个 task 可能为每个分区值写文件，导致“task 数 × 分区值数”的小文件爆炸。

## 4. Foundry Hive-style Partitioning、Projection 与增量小文件治理

【事实】Foundry Hive-style partitioning 在 Spark transform 写出时执行：对 Spark DataFrame 的每个 partition 以及指定 partition columns 的每组唯一值写独立文件，把分区值写入文件路径，并在 transaction metadata 记录分区列。Spark、Polars 等读取器可利用路径和 transaction metadata 缩小读取文件集合。

【事实】Foundry 官方文档指出 Hive-style partitioning 至少会为每组分区值写一个文件，因此不适合高基数字段；文档也建议写出前按分区列 `repartitionByRange`，避免每个输入 Spark partition 都为同一分区值产生额外文件。

【事实】Foundry dataset projection 是 canonical dataset 之外的优化表示。一个 projection 通常针对单一查询模式，例如按一组列过滤、按 join key join、按聚合 key 聚合。projection 可加在 snapshot 或 incremental dataset 上，但受 append-only 等约束影响。

【推断】projection 和 Hive-style partitioning 的差异：projection 会自动 compact，适合治理 incremental pipeline 的小文件积累；Hive-style partitioning 立即生效、使用开放 Parquet 布局、更多读取器可利用，但没有自动 compaction。

【推断】Foundry 的 projection 更像受平台管理的二级访问路径，而不是用户可直接枚举的目录分区。它用额外存储和异步维护成本换取稳定读取性能，尤其适合频繁增量写入造成的文件/transaction 堆积。

【建议】在 Foundry 中：低基数、明确过滤列、需要多引擎可见时优先 Hive-style partitioning；高基数过滤、join 优化、增量小文件治理时优先考虑 projection；长期 append-only 数据仍需监控 projection lag、存储放大和 schema evolution 限制。

## 5. Iceberg Hidden Partition、Manifest Pruning 与 Partition Evolution

【事实】Iceberg 支持 hidden partitioning：用户按逻辑列查询，例如 `event_time`，表规范中可定义 `date(event_time)`、`bucket(id)`、`truncate(col)` 等 transform；查询引擎自动把逻辑谓词转换成分区谓词，用户不需要显式过滤 `event_date`。

【事实】Iceberg 的裁剪不是只看目录。扫描规划先用 manifest list 中的分区值范围过滤 manifest，再读取剩余 manifest；manifest 记录数据文件、文件分区值和列级统计，继续用 lower/upper bounds、null counts 等跳过不可能命中的数据文件。

【事实】Iceberg 支持 partition evolution：分区规范可以增加、删除、重命名或重排字段，历史文件保留原 spec，新写入使用新 spec，查询引擎通过 metadata 同时理解多个 spec，而不是要求重写整张表。

【推断】Iceberg 把“分区列是否写在 SQL 里”的风险转移到表格式和引擎适配层。收益是 SQL 更稳定、布局可演进；代价是 metadata 规模、manifest 维护、小文件治理、引擎版本兼容变得更重要。

【建议】Iceberg 表不应只讨论“按什么目录分区”，还要同时讨论 sort order、目标文件大小、manifest rewrite、compaction、snapshot expiration，以及各查询引擎是否完整支持 hidden partition 和 partition evolution。

## 6. BigQuery Partitioned/Clustered Tables 与 Bytes Scanned

【事实】BigQuery partitioned table 把表分成 partitions。查询如果对 partitioning column 使用可裁剪谓词，BigQuery 只扫描匹配分区并跳过其余分区，从而减少 bytes read 和 on-demand 查询费用。

【事实】BigQuery clustered table 按最多四个 clustering columns 对存储 block 排序和组织。查询过滤 clustering columns 时，BigQuery 用 block metadata 做 block pruning；被裁剪 block 不计入 processed bytes。

【事实】BigQuery on-demand 成本按逻辑未压缩 bytes processed 计算。partitioned table 的 dry run 成本估算较可预测；clustered table 的预估通常是上界，因为 block pruning 在执行期进一步减少实际扫描。

【建议】BigQuery 中常见组合是“按日期 partition，按高频过滤/join 维度 cluster”。过细 partition 会增加 metadata 和分区维护开销；仅依赖 `LIMIT` 不能降低非 clustered 表的扫描成本。

## 7. Snowflake Micro-partition、Clustering Metadata 与 Automatic Pruning

【事实】Snowflake 自动把表数据切成 micro-partitions，通常是 50 MB 到 500 MB 未压缩数据范围，并以列式方式存储。用户通常不定义 Hive 风格目录分区。

【事实】Snowflake 为 micro-partitions 维护元数据，包括列值范围、distinct 信息和 clustering 相关统计。查询运行时根据谓词和元数据自动 pruning micro-partitions，并在剩余 micro-partitions 内做列裁剪。

【事实】Snowflake clustering key 用来让相关记录更集中到相同 micro-partitions，提高 pruning 效果。Automatic Clustering 会在后台维护 clustered table，但会消耗 Snowflake credits，并可能带来 Time Travel/Fail-safe 期间的额外存储占用。

【推断】Snowflake 的成本模型不是 BigQuery 式“每次查询按 scanned bytes 收费”，而是仓库运行 credits、serverless clustering credits 和存储成本的组合。Pruning 的价值主要体现在减少执行时间、减少仓库占用和提升并发余量。

【建议】Snowflake clustering key 应优先服务高频 filter/join 谓词，避免把随机高基数字段直接放在最前；对 timestamp 可考虑按 date 或 truncate 表达式聚类，以降低 overlap 并保留 min/max 裁剪能力。

## 8. 横向对比

| 机制 | 抽象层 | 裁剪依据 | 成本模型重点 | 主要风险 |
|---|---|---|---|---|
| Hive `dt` 分区 | 用户可见目录分区 | metastore 分区值、路径 | 少枚举目录、少读文件、少 task | 高基数、小文件、忘写 `dt` 谓词 |
| Spark compute partition | 执行并行度 | task/input split/shuffle plan | task 数、shuffle、executor 内存 | 误以为等于表分区 |
| Foundry Hive-style | Foundry dataset 文件布局 | 路径值、transaction metadata | 减少读取文件；写出文件数受 Spark 分布影响 | 高基数、无自动 compaction |
| Foundry projection | 二级优化表示 | projection 内部布局/索引 | 额外存储和异步构建换读取性能 | append-only/schema 限制、lag、消费者支持差异 |
| Iceberg | 表格式 metadata | partition transforms、manifest list、manifest、文件统计 | metadata 规划成本 + 数据文件扫描成本 | manifest 膨胀、小文件、引擎兼容 |
| BigQuery partition/cluster | 托管仓库存储布局 | partition filter、block metadata | on-demand bytes processed；cluster 估算为上界 | 过细 partition、聚簇列顺序错误 |
| Snowflake micro-partition | 自动物理存储单元 | micro-partition metadata、clustering metadata | warehouse credits、serverless clustering credits、存储 | clustering 维护成本、overlap 高导致 pruning 弱 |

## 9. 为什么不能混用这些概念

【事实】Table partition 是查询表时的持久化存储布局；stream partition 是流日志的顺序和并行单位；compute partition 是一次作业里的临时执行分片；projection 是另一个可被平台透明选择的优化副本。

【风险】把 stream partition key 直接当 Hive partition key，常会把高基数业务主键落成海量目录和文件；把 Spark `repartition` 当作表分区，常会得到正确并行度但错误文件布局；把 Snowflake micro-partition 当手工分区，会误判其自动 pruning 和 clustering 成本。

【建议】设计湖仓布局时应先问四个问题：查询是否经常按该字段过滤；该字段基数和每分区数据量是否稳定；引擎成本按 bytes、credits 还是集群时间计；写入频率是否会造成小文件或 reclustering 成本。只有 table/layout partition 适合回答“查询能否跳过哪些数据文件/blocks”。

## 参考资料 URL

- https://hive.apache.org/docs/latest/language/languagemanual-ddl/
- https://hive.apache.org/development/desingdocs/dynamicpartitions/
- https://hive.apache.org/development/desingdocs/mapjoin-and-partition-pruning/
- https://spark.apache.org/docs/latest/sql-data-sources-parquet.html
- https://spark.apache.org/docs/3.5.6/api/python/reference/pyspark.sql/api/pyspark.sql.DataFrameWriter.partitionBy.html
- https://spark.apache.org/docs/latest/api/python/reference/api/pyspark.RDD.repartition.html
- https://www.palantir.com/docs/foundry/optimizing-pipelines/hive-style-partitioning/
- https://www.palantir.com/docs/foundry/optimizing-pipelines/projections-overview
- https://www.palantir.com/docs/foundry/optimizing-pipelines/projections-vs-hive-style-partitioning
- https://www.palantir.com/docs/foundry/building-pipelines/maintaining-incremental-performance/
- https://www.palantir.com/docs/foundry/building-pipelines/streaming-keys
- https://iceberg.apache.org/docs/latest/partitioning/
- https://iceberg.apache.org/docs/latest/performance/
- https://iceberg.apache.org/docs/latest/evolution/
- https://apache.github.io/iceberg/spec/
- https://docs.cloud.google.com/bigquery/docs/partitioned-tables
- https://docs.cloud.google.com/bigquery/docs/clustered-tables
- https://docs.cloud.google.com/bigquery/docs/best-practices-costs
- https://docs.snowflake.com/en/user-guide/tables-clustering-micropartitions
- https://docs.snowflake.com/en/user-guide/tables-clustering-keys
- https://docs.snowflake.cn/en/user-guide/tables-auto-reclustering
- https://kafka.apache.org/0100/documentation/
