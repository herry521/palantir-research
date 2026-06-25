# Pipeline Builder Transform 函数摘录

## Aggregate  【事实】

- Source: https://www.palantir.com/docs/foundry/pb-functions-transform
- Supported in: Batch, Faster
- Transform categories: Aggregate, Popular

Description:
Performs the specified aggregations on the input dataset grouped by a set of columns.

Declared arguments:
- Aggregations: List<Expression<AnyType>>
- Dataset: Table
- (optional) Group by columns: List<Column<AnyType>>

Example (excerpt from source):

Input dataset columns: `tail_number`, `airline`, `miles`, `factor`

Output (grouped by `tail_number`):

| tail_number | factor |
| --- | ---: |
| XB-123 | 10 |
| MT-222 | 9 |
| KK-452 | 1 |

Notes:
- 该条目直接来自官方文档，内容为【事实】。
- 后续可在本文件追加更多 transform 算子，按相同结构整理（来源、支持环境、分类、描述、参数、示例、结论类型）。

---

## Pivot  【事实】

- Source: https://www.palantir.com/docs/foundry/pb-functions-transform/pivotV1
- Supported in: Batch, Faster
- Transform categories: Aggregate, Popular

Description:
Performs the specified aggregations on the input dataset grouped by a set of columns. Unique values to pivot on must be provided such that the output schema is known ahead of runtime. This improves runtime stability over time.

Declared arguments:
- Aggregations: List<Expression<AnyType>>
- Dataset: Table
- Group by columns: List<Column<AnyType>>
- Pivot by column: Column<T> (T accepts Boolean | Byte | Integer | Long | Short | String)
- Pivot by values: List<Tuple<Literal<T>, Literal<String>>>
- (optional) Prefix or suffix alias: Enum<Prefix, Suffix>

Example: Example 1 (excerpt)

Notes:
- 内容直接来自官方文档，标注为【事实】。

---

## Window  【事实】

- Source: https://www.palantir.com/docs/foundry/pb-functions-transform/windowV1
- Supported in: Batch, Faster
- Transform categories: Aggregate, Popular

Description:
Performs the specified aggregations on the input dataset grouped by a set of columns.

Declared arguments:
- Dataset: Table
- Expressions: List<Expression<AnyType>>
- Window: Window

Notes:
- 内容直接来自官方文档，标注为【事实】。

---

## Extract rows from an Excel file  【事实】

- Source: https://www.palantir.com/docs/foundry/pb-functions-transform/parseExcelV2
- Supported in: Batch
- Transform categories: File

Description:
Reads a dataset of Microsoft Excel files and parses each file into rows. Supported formats: .xls, .xlt, .xltm, .xltx, .xlsx, .xlsm.

Declared arguments (highlights):
- Dataset: Files
- Rows to skip: Literal<Integer>
- Schema: List<Literal<String>>
- Source sheet pattern: Literal<String> (regex substring match by default)
- Optional output columns: file path, row number, sheet name (Literal<String>)
- Treat first row (after skipping) as header: Literal<Boolean> — when true, header strings are sanitized and disambiguated as documented:
  1. Remove leading characters from set `(),;{}\n\t=` (space first)
  2. Replace remaining `(),;{}\n\t=` with underscores
  3. Collapse consecutive underscores to one
  4. Remove trailing underscore
  5. If empty, use `_untitled_column`
  6. If duplicates, append `_2`, `_3`, ...

Notes:
- 对大文件请考虑本地 Spark 或者增加 executor/driver 内存，预览可能不可用。这些均为官方说明，标注为【事实】。

---

## Parse KML files into geometry lists  【事实】

- Source: https://www.palantir.com/docs/foundry/pb-functions-transform/parseKmlFilesV1
- Supported in: Batch
- Transform categories: File

Description:
Parses each raw KML file into a list of typed geometries.

Declared arguments:
- Dataset: Files
- (optional) Should prepare: Literal<Boolean> (default true) — whether to prepare geometry for Ontology ingest after parsing

Notes:
- 官方建议在非必要情况下保持默认的 prepare 为 true，以便后续地理空间处理；内容为【事实】。

---

## Mapping join  【事实】

- Source: https://www.palantir.com/docs/foundry/pb-functions-transform/mappingJoinV1
- Supported in: Batch, Faster
- Transform categories: Join

Description:
Replaces values from the target columns in the source dataset with values in the mapping dataset.

Declared arguments:
- Input dataset: Table
- Key column for mapping values: Column<T1>
- Mapping dataset: Table
- Target columns: List<Column<T1>>
- Values to use for mapping: Column<T2>
- (optional) Assume unique mappings: Literal<Boolean> (defaults to true)
- (optional) Default value: Expression<T2>

Example (excerpt):
- 将 mapping 表中的 flight_number 替换 source 的 flight_no/next_flight，若无匹配则使用 default value（示例中为 unknown）。

Notes:
- 官方示例与参数声明为事实；类型变量 T1/T2 接受 AnyType。

---

## Geometry intersection join  【事实】

- Source: https://www.palantir.com/docs/foundry/pb-functions-transform/geoIntersectionJoinV1
- Supported in: Batch
- Transform categories: Geospatial, Join

Description:
Inner joins left and right datasets together based on whether input geometries overlap. Returns rows containing columns from both datasets when geometries intersect.

Declared arguments:
- Join key: List<Tuple<Column<Geometry>, Column<Geometry>>>
- Left dataset: Table
- Right dataset: Table

Notes:
- 不支持在多个 join key 上同时 join；无效 GeoJSON 值会被静默置空；这些细节均来自官方，标注为【事实】。

---

## Key by  【事实】

- Source: https://www.palantir.com/docs/foundry/pb-functions-transform/keyByV3
- Supported in: Streaming
- Transform categories: Other

Description:
Keys (partitions) the input by the provided key by columns. Does not re-sort data; maintains per-key ordering from the point keys are set. If cdc mode enabled, sets primary key for deduplication and ordering semantics.

Declared arguments:
- Dataset: Table
- Enable cdc mode: Literal<Boolean>
- Key by columns: Set<Column<Binary | Boolean | Byte | Double | Float | Integer | Long | Short | String | Timestamp>>
- (optional) Primary key is deleted column: Column<Boolean>
- (optional) Primary key ordering columns: List<Column<Byte | Date | Decimal | Integer | Long | Short | String | Timestamp>>

Notes:
- 重要：重新 key 可能会改变 ordering 保证；该说明来自官方文档，标注为【事实】。

---

## Rollup  【待确认/已验证404】

- Source: https://www.palantir.com/docs/foundry/pb-functions-transform/rollUpV1
- Supported in: Batch, Faster
- Transform categories: Aggregate

Description:
（原始页面当前返回 404，无法直接抓取完整参数。以下内容基于 functions-index 摘录与示例，保留为推断/待确认；对应的临时渲染产物已清理，不再单独保留）
Performs the specified aggregations on the input dataset at different levels of granularity, providing both aggregated results and intermediate rollup levels (excerpt from page meta description).

Declared arguments (inferred / partial):
- Aggregations: List<Expression<AnyType>>  【推断 — 需确认】
- Dataset: Table  【推断 — 需确认】
- Rollup columns: List<Column<AnyType>>  【推断 — 需确认】
- (optional) Output projection / aliasing: inferred from examples, needs confirmation  【推断】

Notes:
- 已使用无头浏览器在本地渲染目标 URL，结果服务端返回 404（对应的临时渲染产物已清理，分支 codex/3-rollup-render 曾用于留存当时的证据）。因此原始参数与默认值尚无法从页面确认，应联系文档维护方或使用内部渲染/内容源继续提取（issue #12 已创建并记录此工作）。

---

## First union by name  【事实】

- Source: https://www.palantir.com/docs/foundry/pb-functions-transform/firstUnionByNameV1
- Supported in: Batch, Faster
- Transform categories: Join

Description:
Unions a set of datasets together on columns from the first dataset, adding nulls when columns are missing. Columns not present in the first dataset are removed.

Declared arguments:
- Datasets to union: List<Table>

Example (excerpt):
- 将多个 dataset 按第一个 dataset 的列集合 union，缺失列以 null 填充。

Notes:
- 官方页面包含多组示例（Base case, Null case, Edge case），以上为摘录，属【事实】。

---

## Outer caching join  【事实】

- Source: https://www.palantir.com/docs/foundry/pb-functions-transform/outerCachingJoinV3
- Supported in: Streaming
- Transform categories: Join

Description:
Joins left and right datasets together, caching the record with the highest event time from each side for use in subsequent joins. Processing time acts as a tiebreaker; optimistic emits occur when no matching join value exists.

Declared arguments:
- Default cache time unit: Enum<Days, Hours, Milliseconds, Minutes, Seconds, Weeks>
- Default cache time value: Literal<Long>
- Join key: List<Tuple<Column<...>, Column<...>>> (see source for full type)
- Left dataset: Table
- Right dataset: Table
- (optional) Rhs cache time override: Tuple<Literal<Long>, Enum<Days, Hours, Milliseconds, Minutes, Seconds, Weeks>>

Notes:
- 官方明确指出在 streaming 场景下使用缓存以提高 join 可用性；以上为【事实】。

---
