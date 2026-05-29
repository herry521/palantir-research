# Palantir Foundry Media Set 实现机制深度调研

**调研日期：** 2026-05-30  
**文件编号：** 31  
**主题：** Media Set 功能定义 / 实现架构 / Pipeline 与 Ontology 集成 / 自建落地设计 / 关键决策

---

## 0. 结论摘要

Palantir Foundry 的 Media Set 不是 Dataset 的一个文件列，也不是普通对象存储目录，而是面向非结构化数据的独立资产类型。它围绕 `Media Set -> Media Item -> Media Reference -> Dataset / Ontology / Application` 建立了一套闭环：文件按媒体 schema 存储，平台提供预览、转换、事务、版本、引用、增量、成本治理和 Ontology 展示能力。【事实】

对自建平台而言，Media Set 的核心价值不是“支持上传 PDF/图片”，而是解决四件事：【推断】

1. 非结构化文件如何成为可治理的数据资产。
2. 文件如何被 Pipeline 批量处理并与结构化 Dataset 合流。
3. 文件如何以轻量引用方式进入业务对象，而不是在各处复制。
4. OCR、转写、VLM、embedding 等 AI 能力如何被平台化、可审计、可计费地调用。

一个合理的自建目标是：

```text
Object Storage / External Source
  -> Media Set Service
  -> Media Reference / Metadata / Access Pattern
  -> Pipeline Builder / Code Transform
  -> Dataset rows / Output Media Set
  -> Ontology Object media property
  -> Workshop / OSDK / AIP / Search / AI Agent
```

---

## 1. 功能定义

### 1.1 Media Set 是什么

Palantir 官方定义中，Media Set 是一组具有共同 schema 的媒体文件集合，用于高规模非结构化数据，包括 audio、imagery、video、documents、spreadsheets、DICOM、email 等。Media Set 支持灵活存储、计算优化和按 schema 定制的转换能力。【事实】

官方资料：
- Media sets core concept: https://www.palantir.com/docs/foundry/data-integration/media-sets
- Media sets overview: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/media-overview

它和 Dataset 的区别：

| 维度 | Dataset | Media Set |
|---|---|---|
| 主要对象 | 表格 / 文件型数据集 | 非结构化媒体文件集合 |
| 数据模型 | schema、transactions、branches、files | media schema、media items、media references、transaction policy |
| 存储形态 | 结构化通常为 Parquet；文件型 Dataset 可存原始文件 | 原始媒体对象 + 媒体元数据 + 引用 |
| 计算方式 | Spark/Faster/Flink 等表格计算 | OCR、转写、图片处理、PDF render、DICOM render、access pattern |
| 消费方式 | SQL、Pipeline、Ontology 映射 | Preview、Map tile、Workshop widget、Ontology media property、OSDK |
| AI 价值 | 表格特征、文本列 | 文档/图像/音频/视频进入 LLM/VLM/embedding 的入口 |

### 1.2 支持的媒体类型

官方公开支持的 Media Set schema 包括：【事实】

| Schema | 格式示例 |
|---|---|
| Audio | WAV、FLAC、MP3、MP4、NIST SPHERE、WEBM |
| DICOM | DCM |
| Document | PDF，DOCX/PPTX/TXT 可作为 additional input format 转为主格式 |
| Email | EML |
| Image | PNG、JPEG、JP2K、BMP、TIFF、NITF |
| Spreadsheet | XLSX |
| Video | MP4、MOV、TS、MKV |
| Multimodal | 可上传多种格式，但预览和 access pattern 受格式支持范围限制 |

PDF 有限制：需要专有特性、密码保护、数字签名或加密的 PDF 不支持。XLSX 中复杂公式、嵌入文件和图片等高级能力也有限制。【事实】

### 1.3 Media Reference 是核心抽象

Media Reference 是 Media Set 的关键设计。它允许 Dataset 或 Ontology Object 引用媒体文件，而不是复制文件本体。官方说明中，Media Reference 可用于在表格数据中关联原始 PDF、文件名、页数、抽取文本等信息，也可作为 batch inference 的模型输入。【事实】

典型结构可抽象为：【推断】

```json
{
  "mimeType": "application/pdf",
  "reference": {
    "type": "mediaSetItem",
    "mediaSetItem": {
      "mediaSetRid": "ri.mio.main.media-set.xxx",
      "mediaItemRid": "ri.mio.main.media-item.yyy"
    }
  }
}
```

这解释了 Media Set 的产品边界：文件本体由 Media Set 管，业务语义由 Dataset / Ontology 管，二者通过 Media Reference 连接。【推断】

---

## 2. 数据模型与元数据设计

### 2.1 核心实体

基于官方 API、Python SDK 和 Pipeline Builder 行为，Media Set 至少包含以下概念：【事实 + 推断】

| 实体 | 说明 | 关键字段 |
|---|---|---|
| `MediaSet` | 一组同 schema 的媒体文件资产 | `rid`、`mediaSchema`、`defaultBranchName`、`transactionPolicy`、`pathsRequired` |
| `MediaSetBranch` | Media Set 的分支视图 | `branchName` / `branchRid` |
| `MediaSetView` | API 中出现的可读视图抽象 | `mediaSetViewRid` |
| `MediaItem` | 单个媒体文件版本 | `mediaItemRid`、`path`、`mediaType`、metadata |
| `MediaReference` | 可放入 Dataset / Ontology 的轻量引用 | `mediaSetRid`、`mediaItemRid`、`mimeType` |
| `MediaTransaction` | 事务型写入会话 | `transactionId`、branch、open/commit/abort |
| `AccessPattern` | 按需转换与缓存策略 | thumbnail、preview、waveform、tile 等 |
| `TransformationJob` | API 级异步媒体转换任务 | `jobId`、`PENDING/FAILED/SUCCESSFUL` |

官方 API 入口能侧面确认这些对象：`Get Media Set`、`Put Media Item`、`Register Media Item`、`Create/Commit/Abort Media Transaction`、`Get Media Item Reference`、`Transform Media Item`、`Get Transformation Job Status/Result` 等。【事实】

官方 API 参考：
- Media Set basics: https://www.palantir.com/docs/foundry/api/v2/media-sets-v2-resources/media-sets/media-set-basics
- Get Media Set: https://www.palantir.com/docs/foundry/api/v2/media-sets-v2-resources/media-sets/get-media-set
- Put Media Item: https://www.palantir.com/docs/foundry/api/media-sets-v2-resources/media-sets/put-media-item/
- Register Media Item: https://www.palantir.com/docs/foundry/api/v2/media-sets-v2-resources/media-sets/register-media-item/

### 2.2 Path 语义

Media Item 可以有用户指定 path。官方明确：如果上传文件路径与已有 item 相同，新 item 会覆盖旧 item，且不会弹出确认。默认读取路径时返回最新 item。【事实】

关键细节：

1. 被覆盖的旧 item 不会立即永久删除，仍可通过直接 Media Reference 或版本历史访问。【事实】
2. Transform 中如果希望列出同一路径下所有历史 item，需要设置 `deduplicate_by_path=False`。【事实】
3. path 长度不能超过 256 字符；超出会触发 `MediaSet:MediaItemPathInvalid`。【事实】

设计含义：【推断】

- `path` 是业务友好的定位键，不是不可变主键。
- `mediaItemRid` 才是稳定引用的不可变身份。
- `mediaReference` 应保存 RID，而不是只保存 path，否则路径覆盖会导致下游语义漂移。

### 2.3 Version History 与 Retention

Media Set 支持 path 级版本历史：同一路径多次上传时，UI 默认展示最新版本，但可查看该 path 下历史版本。【事实】

Retention policy 支持两类清理：【事实】

1. 按上传时间永久删除超过保留窗口的媒体 item。
2. 按覆盖/软删除时间永久删除 overwritten 或 deleted item。

保留窗口缩短会让超过新窗口的 item 立即不可访问；窗口再调长也不会恢复已过期 item。【事实】

关键决策：【推断】

- Media Set 默认选择“可追溯覆盖”而非“直接物理替换”。
- 存储成本通过 retention 控制，而不是通过上传时丢弃旧版本。
- Direct Media Reference 和 Path View 是两套读取语义：前者稳定，后者跟随最新。

---

## 3. 写入模型：Transactional vs Transactionless

### 3.1 Transactionless Media Set

官方说明 transactionless policy 的语义：【事实】

- 上传后立即可读。
- 不能回滚。
- 如果 build 写入中途失败，已成功写入的 items 会保留。
- 多个客户端可同时写。
- transactionless branch 不能 reset 到空视图。

适合场景：【推断】

- 用户交互式上传。
- 低风险、可重复写、可容忍部分成功的媒体采集。
- 外部事件流式进入，但不要求一次 build 原子可见。

### 3.2 Transactional Media Set

官方说明 transactional policy 的语义：【事实】

- 所有 item 必须在 transaction 内写入。
- 同一 branch 同时只能打开一个 transaction。
- commit 后 transaction 内 items 才可读。
- abort 后 transaction 内 items 会被删除。
- build 失败时不会更新 Media Set。
- 单个 transaction 最多写入 10,000 items。

适合场景：【推断】

- Pipeline 输出。
- 批量转换结果。
- 需要 all-or-nothing 的生产链路。
- 与 Dataset Build 形成一致的发布边界。

Pipeline Builder 的 Media Set output 是 transactional only。【事实】

官方资料：
- Advanced settings: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/media-set-settings
- Add media set output: https://www.palantir.com/docs/foundry/pipeline-builder/outputs-add-media-set-output/

### 3.3 Write Mode

Code Repository 中 Media Set output 支持两种写模式：【事实】

| 写模式 | 语义 |
|---|---|
| `modify` | 新写入 item 加到已有 branch 视图上 |
| `replace` | 用本次写入结果替换整个 branch 视图 |

Transactional Media Set 默认 `replace`；transactionless 只能 `modify`，不能 `replace`。【事实】

关键决策：【推断】

- `transactionPolicy` 解决“可见性和失败原子性”。
- `writeMode` 解决“本次输出与已有 branch 视图的关系”。
- 二者正交，但 transactionless 因为不能 reset 空视图，所以不能支持 `replace`。

---

## 4. 进入链路：Media 如何进入 Foundry

### 4.1 Direct Upload

用户可以在 Project / Folder 中创建 Media Set，然后拖拽上传文件。文件必须匹配创建时指定的 schema / format，否则上传失败或被忽略，具体取决于链路配置。【事实】

Direct Upload 适合小批量人工上传，不适合生产级持续同步。【推断】

### 4.2 Data Connection Media Sync

Media Set 可以通过 Data Connection 从外部源同步。官方公开支持的 media sync source 包括 Amazon S3 和 OneLake / Azure Blob Filesystem (ABFS)；官方也说明支持源在增长，如果目标文件源暂不支持，可先摄入到 Dataset，再用 Python transform 转成 Media Set。【事实】

Media Sync 配置包含：【事实】

- 选择媒体文件类型。
- build schedule。
- subfolder。
- filters：Exclude files already synced、Path matches、File size limit、Ignore items not matching schema。

官方资料：
- Media set syncs: https://www.palantir.com/docs/foundry/data-connection/media-set-sync/
- Importing media: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/importing-media

实现推断：

```text
Data Connection Source
  -> enumerate external files
  -> apply subfolder / path / size / schema filters
  -> open Media Transaction if transactional
  -> upload/register media item
  -> extract initial metadata
  -> commit transaction
  -> emit build / lineage / health status
```

### 4.3 Virtual Media Set

Virtual Media Set 不复制文件到 Foundry backing store，而是直接读取外部源系统中的媒体文件，同时保留 Media Set 接口。【事实】

官方限制：【事实】

- 支持 Amazon S3、OneLake / ABFS。
- S3 仅支持 access key / secret credential；不支持 STS roles。
- 不支持 agent connections 创建 virtual media set sync。
- 不感知源端更新和删除：源端文件删除后，Media Set 中仍保留 item 记录，但内容不可访问。
- 对 virtual item 做 transformation 时，转换结果会持久化到 Foundry backing store 并产生成本。
- 不支持 additional input formats。

关键决策：【推断】

- Virtual Media Set 是“引用外部对象”的成本优化，不是完整的数据一致性方案。
- 它适合大规模历史影像/文档湖的轻量接入，但不适合严格依赖源端 delete/update 同步的工作流。
- 生产系统应为 virtual item 建立可重扫、可修复的 manifest，而不能假设外部源状态自动同步到 Foundry。

### 4.4 Transform 写入

Code Repository 可以用 `MediaSetOutput` 写 Media Set：【事实】

- `put_media_item(file_like, path)`：上传单个文件。
- `fast_copy_media_item(input_media_set, media_item_rid, path)`：Media Set 间快速复制，避免下载再上传。
- `put_dataset_files(input_dataset, ignore_items_not_matching_schema=...)`：把普通 filesystem Dataset 中的文件批量导入 Media Set。

这条路径适合：【推断】

- REST API 下载文件后写入 Media Set。
- 复杂过滤逻辑决定哪些文件要注册进 Virtual Media Set。
- 先进入普通 file Dataset，再按类型拆分为多个 Media Set。

---

## 5. 处理链路：Media 如何被转换

### 5.1 Pipeline Builder 路径

Pipeline Builder 可以直接添加 Media Set 节点。官方明确：Media Set input 不必先转成 table；在 pipeline 中既可被当成 media set 处理，也可作为 tabular input 使用。【事实】

媒体处理分两类：【事实】

| 类型 | 输入 | 输出 | 示例 |
|---|---|---|---|
| Manipulate media | media | media | Slice PDF、resize image、crop image |
| Extract information | media reference | table column | PDF text extraction、OCR、layout extraction、audio transcription |

官方限制也很关键：【事实】

- 当前不能从“已经被转换过的 media”再抽取信息。
- 当前不能转换 Dataset 中引用的 media。
- 如果 media set input 在 changelog mode 中包含 deleted items，不能 transform media。

官方资料：
- Transform media: https://www.palantir.com/docs/foundry/pipeline-builder/transforms-transform-media

设计含义：【推断】

- Pipeline Builder 对 media 的 IR 可能区分 `MediaNode`、`MediaTransformNode`、`TabularExtractionNode`。
- 平台有意避免“媒体变换结果继续被信息抽取”这种组合爆炸，先保证常见链路稳定。
- Media Reference in Dataset 和 Media Set input 是不同执行入口；后者能被平台批量调度与优化，前者更偏消费层引用。

### 5.2 Code Repository 路径

Python transforms 使用 `transforms-media` 包。使用 Media Set 时必须走 `@transform`，不能用只接受 DataFrame 的 `@transform_df`。【事实】

典型 API：【事实】

```python
from transforms.api import transform, Output
from transforms.mediasets import MediaSetInput, MediaSetOutput

@transform(
    images=MediaSetInput("/examples/images"),
    listed=Output("/examples/listed_images"),
)
def compute(ctx, images, listed):
    df = images.list_media_items_by_path_with_media_reference(ctx)
    listed.write_dataframe(df, column_typeclasses={
        "mediaReference": [{"kind": "reference", "name": "media_reference"}]
    })
```

关键特性：【事实】

- 可通过 path 或 RID 读取单个 item。
- 单个 item 读取返回 Python file-like stream，不支持随机访问。
- 可不下载全文件而读取 metadata，如图像尺寸、音频长度等。
- 可 listing 为 DataFrame 后用 PySpark / pandas 继续处理。
- 可调用内置 media transformations，如 OCR、PDF render、image crop 等。
- Code Repository Preview 当前不支持 media transformations；含 Media Set 的 transform 可 build，但不可 preview。
- Lightweight transforms 也支持 Media Set，适合单节点 pandas 级处理。

官方资料：
- Use media sets with Python transforms: https://www.palantir.com/docs/foundry/transforms-python/media-sets/
- Media set transforms API: https://www.palantir.com/docs/foundry/transforms-python/media-set-transforms-api/

### 5.3 Access Patterns

Access Pattern 是 Media Set 的重要实现设计。官方说明它是预配置的按需转换，可配置持久化策略：每次请求重算、首次请求后永久保存、或缓存一段时间。【事实】

典型用途：【事实】

- Workshop 中 PDF 缩略图和预览。
- Preview 应用中的音频 waveform buffer。
- Map 中的卫星影像切片。

默认 Access Pattern 由 Media Set schema 决定；额外 transformation 只能通过 API 注册到 Media Set。【事实】

架构推断：

```text
Media Item
  -> Access Pattern Resolver
  -> Cache Lookup
  -> Transformation Worker
  -> Derived Object Store
  -> Preview / Workshop / Map
```

关键决策：【推断】

- 预览不是在上传时全部预生成，而是按需生成与缓存。
- Access Pattern 把 UI 性能问题从业务应用中抽离，变成 Media Set 服务的统一能力。
- 对大文件、大影像、音频波形这类高成本操作，必须有缓存策略和成本归因。

---

## 6. 增量 Media Set

Media Set 可以用于 incremental transforms，但必须设置 `@incremental(v2_semantics=True)`；否则 Media Set 不能增量使用。【事实】

### 6.1 增量可行性判断

Media Set output 会阻止增量的场景：【事实】

1. 多输出 build 中，该 output 最近一次不是由同一个 transform 与其他 outputs 一起构建。
2. transactional media set 自最近 build 后被修改过，包括用户上传和删除。

Media Set input 会阻止增量的场景：【事实】

1. input media set 内容被 `replace` 写模式替换。
2. 如果该 input 被声明为 `snapshot_input`，即使被替换也不会阻止增量。

与 Dataset 不同，path overwrite 和 media item deletion 不会自动阻止 Media Set 增量运行。【事实】

这点非常重要：如果业务认为 path 覆盖代表语义更新，就必须显式检测 `previous` 与 `added` 是否存在相同 path，并决定是否全量重算或 `replace` 输出。【推断】

### 6.2 Read Mode

增量 Media Set input 支持三种 listing mode：【事实】

| Mode | 语义 |
|---|---|
| `added` | 上次 build 后新增到 branch 的 items |
| `previous` | 上次 build 时 branch 中存在的 items |
| `current` | 当前 branch 中全部 items |

当增量运行时默认读 `added`；非增量运行时默认读 `current`。`added + previous = current`。【事实】

### 6.3 Branch 与 Transactionless 限制

官方限制：【事实】

- Media Set 不支持 incremental fallback branches。
- 新 branch 上运行 incremental transform 时，由于 output 为空，增量装饰器会建议 snapshot。
- Transactionless Media Set 只能 `modify`，不能 `replace`；如果作为增量 transform output 且本次无法增量，build 会失败。
- 单个 Media Set output 不能在 build 中单独 abort，推荐通过 `ctx.abort_job()` 终止整个 job。

官方资料：
- Incremental media sets: https://www.palantir.com/docs/foundry/transforms-python-spark/incremental-media-sets/

---

## 7. Ontology / Workshop / OSDK 集成

### 7.1 Ontologize Media

Foundry 用 media reference object property 把媒体放进 Ontology。官方说明这样可以在 Workshop、Object Explorer、Map 等应用中高效展示媒体，包含交互式预览和地理影像 tiling 优化。【事实】

在 object function 中，可读取 raw media item，也可执行常见类型相关操作：【事实】

- documents OCR。
- document text extraction。
- audio transcription。
- media item metadata 读取。

官方资料：
- Using media in the Ontology: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/media-in-ontology/

### 7.2 Action Upload

Ontology Action 支持 media reference 参数，Workshop 中可通过 file picker / drag-and-drop 上传。官方说明：action form 中上传的媒体文件只有在表单成功提交后才会写入 backing media set，避免取消或失败提交产生 orphaned media files。【事实】

限制：【事实】

- Object property 不支持 media reference list。
- 不建议一个 media reference property 由多个 Media Set backing；这种场景下 action upload 支持不完整。

官方资料：
- Upload media workflow: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/upload-media

### 7.3 DICOM 与 Audio 示例

DICOM 示例官方流程：【事实】

```text
Create DICOM Media Set
  -> upload .dcm
  -> Pipeline Builder: Convert media set to table rows
  -> Add Object type output
  -> use Media Item Rid as primary key
  -> view in Object Explorer / Ontology Manager / Workshop
```

Audio transcription 示例官方流程：【事实】

```text
Audio Media Set
  -> Pipeline Builder Transcribe audio
  -> output transcription string or segment array
  -> Explode segments into rows
  -> Ontologize segment objects
  -> Workshop Audio and Transcription Display widget
  -> Action can correct speaker property
```

官方资料：
- DICOM workflow: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/add-dicom-media-set
- Audio transcription workflow: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/add-audio-transcription

---

## 8. AI / VLM / 搜索集成

### 8.1 Media Set 是非结构化 AI 的入口

Media Set 和 AI 的典型关系不是“文件上传后问答”，而是如下链路：【推断】

```text
PDF / Image / Audio / Video / DICOM
  -> Media Set
  -> OCR / transcription / layout extraction / image transform / metadata extraction
  -> Dataset columns / segment objects / embeddings
  -> Ontology Object
  -> AIP Logic / Agent / Search / Workshop
```

Pipeline Builder 的 Use LLM expression 已支持 media items 作为 prompt 输入，官方说明 images 和 PDFs 支持作为 LLM prompt；PDF 会先转换成 images 再传给 LLM。【事实】

官方资料：
- Use LLM expression: https://www.palantir.com/docs/foundry/pb-functions-expression/useLlmV3

### 8.2 AI 能力分层

| 层次 | 能力 | 典型输出 |
|---|---|---|
| 基础媒体处理 | OCR、raw text extraction、audio transcription、metadata | 文本、segment、metadata |
| 结构理解 | layout-aware extraction、table extraction、form field extraction | block、table、bbox、confidence |
| 多模态模型 | image/PDF to LLM/VLM、caption、classification | label、summary、structured JSON |
| 检索增强 | text chunk、embedding、semantic search | vector、chunk、source reference |
| 业务对象化 | media reference property、document object、claim object、inspection object | Ontology objects / links |

### 8.3 自建时的关键问题

1. AI 输出必须结构化：否则无法进入 Dataset / Ontology。
2. AI 调用必须挂在 Transform / Action / Function 等可审计边界上。
3. OCR/VLM 成本必须计量到 media item、pipeline、owner。
4. 需要记录 prompt、model、version、input media reference、output schema、confidence，支持复跑和回溯。
5. 对敏感媒体，应先走权限和 marking 检查，再允许 AI 服务读取原文或图像。【推断】

---

## 9. 成本、规模与稳定性

官方限制和成本规则：【事实】

| 项 | 规则 |
|---|---|
| item 数量 | Media Set 中 item 数量无上限 |
| 单文件大小 | 每个 media item 最大 50 GB |
| 事务写入数量 | transactional Media Set 单 transaction 最多 10,000 items |
| path 长度 | media item path 不超过 256 字符 |
| 增量 batch limit | incremental transform 可限制每次读取的 media item 数量 |
| QoS throttle | 大规模上传/转换可能返回 429 / 503，需要 retry |
| 下载/stream 成本 | 按 Foundry compute-seconds per GB 计量 |
| OCR / render / resize 等转换 | 按 GB 和转换类型计量，OCR / embedding 等成本显著更高 |

官方资料：
- Media usage costs and limits: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/media-usage-limits/

实现启示：【推断】

- Media Set Service 必须有 backpressure、retry、幂等写入和批量限流。
- 大规模 OCR / VLM 不应默认全量处理，必须支持 sample、batch size、增量和 cache。
- 对虚拟媒体，读取源端失败应区分“item 不存在 / 源端不可达 / 权限失败 / schema 不匹配”。
- Access Pattern 结果应进入派生对象存储和 cache，不应让前端重复触发高成本转换。

---

## 10. 反推实现架构

Palantir 未公开底层完整实现，因此以下架构是基于官方 API、SDK、产品行为和已有 Foundry 体系的推断。【推断】

```text
                        ┌────────────────────────────┐
                        │  Project / Resource Layer   │
                        │  permissions / markings     │
                        └─────────────┬──────────────┘
                                      │
┌─────────────────────────────────────▼─────────────────────────────────────┐
│                           Media Set Control Plane                         │
│  MediaSet metadata  Branch/View  Transaction  Retention  Schema registry  │
└──────────────┬─────────────────────┬─────────────────────┬───────────────┘
               │                     │                     │
               ▼                     ▼                     ▼
┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────────┐
│ Object Store Adapter │   │ Federated Store     │   │ Media Item Index     │
│ managed bytes        │   │ virtual/register    │   │ path/RID/version     │
└──────────┬──────────┘   └──────────┬──────────┘   └──────────┬──────────┘
           │                         │                         │
           └──────────────┬──────────┴──────────────┬──────────┘
                          ▼                         ▼
              ┌─────────────────────┐   ┌─────────────────────┐
              │ Transform Service    │   │ Access Pattern Svc   │
              │ OCR/render/resize    │   │ preview/tile/cache   │
              └──────────┬──────────┘   └──────────┬──────────┘
                         │                         │
                         ▼                         ▼
              ┌─────────────────────┐   ┌─────────────────────┐
              │ Pipeline Bridge      │   │ App Consumption      │
              │ PB / Code Repo       │   │ Workshop/Map/OSDK    │
              └──────────┬──────────┘   └──────────┬──────────┘
                         │                         │
                         ▼                         ▼
              ┌─────────────────────┐   ┌─────────────────────┐
              │ Dataset Rows         │   │ Ontology Object      │
              │ media_reference cols │   │ media property       │
              └─────────────────────┘   └─────────────────────┘
```

### 10.1 组件职责

| 组件 | 职责 |
|---|---|
| Media Set Control Plane | 管理 Media Set 元数据、schema、branch/view、transaction、retention、policy |
| Object Store Adapter | 管理 Foundry backing store 中的媒体二进制对象 |
| Federated Store Adapter | 对 virtual media set 注册外部对象路径并读取外部源 |
| Media Item Index | 维护 path -> latest item、path version history、RID lookup、metadata |
| Transaction Manager | create/commit/abort，保证 transactional media set 的可见性与失败语义 |
| Transform Service | 执行 OCR、render、resize、crop、transcribe、metadata extraction 等 |
| Access Pattern Service | 面向预览/地图/音频波形的按需转换、缓存和持久化策略 |
| Pipeline Bridge | 将 Media Set 映射到 PB 节点、Python SDK input/output、DataFrame listing |
| Reference Resolver | 生成、解析、校验 media reference；供 Dataset/Ontology/OSDK 消费 |
| Governance Layer | 权限、marking、审计、成本、QoS、retention、生效范围 |

### 10.2 关键数据流

**Managed upload：**

```text
Client / Sync / Transform
  -> Create transaction (if transactional)
  -> Put media item bytes
  -> Validate schema / format
  -> Extract metadata
  -> Write object store
  -> Update path/RID index in pending transaction
  -> Commit
  -> Publish branch view
```

**Virtual register：**

```text
Data Connection / Python Transform
  -> Register physical item name
  -> Validate external item exists and matches schema
  -> Extract initial metadata
  -> Store external pointer in Media Item Index
  -> Media bytes remain in external system
```

**Pipeline extraction：**

```text
MediaSetInput
  -> list items (dedupe or all versions)
  -> produce DataFrame(mediaItemRid, path, mediaReference)
  -> call transform service per item / partition
  -> write Dataset columns or output Media Set
```

**Ontology consumption：**

```text
Dataset row / Object property
  -> mediaReference
  -> Reference Resolver
  -> permission + marking checks
  -> Access Pattern / Raw read / Transform
  -> Workshop / OSDK / Function result
```

---

## 11. 自建落地方案

### 11.1 最小功能定义

P0 不建议一次性复刻所有 Media Set。最小可用能力应覆盖：【推断】

1. 创建 Media Set：`name`、`media_schema`、`primary_format`、`transaction_policy`。
2. 上传 Media Item：`media_item_id`、`path`、`mime_type`、`size`、`checksum`、`metadata`。
3. 生成 Media Reference：可放入 Dataset / Object。
4. Media Set 转表：输出 `media_item_id`、`path`、`media_reference`、基础 metadata。
5. 基础预览：PDF/image thumbnail、音频基础 metadata。
6. Retention：按时间和 overwritten item 清理。
7. 权限：继承项目权限，下载/预览/转换均审计。

### 11.2 目标架构

```text
media_set_service
  ├── media_set_metadata
  ├── media_item_index
  ├── media_transaction
  ├── media_reference_resolver
  ├── retention_worker
  └── audit/cost events

media_storage_adapter
  ├── managed_object_store
  └── federated_external_store

media_transform_service
  ├── pdf_text
  ├── ocr
  ├── thumbnail
  ├── audio_transcription
  ├── image_resize_crop
  └── embedding/vlm hooks

pipeline_integration
  ├── media_set_input
  ├── media_set_output
  ├── media_to_rows operator
  ├── transform_media operator
  └── output media set operator

ontology_integration
  ├── media_reference property
  ├── action upload
  ├── function read/transform
  └── app preview widgets
```

### 11.3 分阶段路线

| 阶段 | 目标 | 关键交付 |
|---|---|---|
| P0 | 文件资产化 | Media Set / Media Item / Reference / Object Store / Direct Upload / 转表 |
| P1 | Pipeline 可用 | MediaSetInput/Output、OCR、PDF text、thumbnail、output Dataset |
| P2 | 生产语义 | transactional write、retention、incremental added/current、QoS retry、cost events |
| P3 | Ontology 闭环 | media reference property、Action upload、Workshop preview、OSDK read |
| P4 | AI 增强 | layout extraction、audio transcription、embedding、VLM prompt、semantic search |
| P5 | Virtual / 大规模 | external pointer、federated read、access pattern cache、raster tiling |

### 11.4 建议先做的 6 个算子

| 算子 | 输入 | 输出 | 原因 |
|---|---|---|---|
| `media.list_items` | Media Set | Dataset rows | 所有后续处理的桥 |
| `media.get_references` | Media Set | media_reference column | 连接 Dataset / Ontology |
| `media.extract_pdf_text` | PDF Media Set | text column | 文档类最高频 |
| `media.ocr_image` | Image/PDF | text / blocks | AI 与治理扫描入口 |
| `media.thumbnail` | Image/PDF/video | Output Media Set | 应用预览入口 |
| `media.copy_to_set` | Dataset files / Media Set | Media Set | 导入与清洗出口 |

---

## 12. 关键架构决策

### D1. Media Set 是否独立于 Dataset

建议：独立。

原因：【推断】

- Dataset 优势在表格事务和计算；Media Set 需要 path version、media preview、格式校验、OCR、thumbnail、streaming content、large object read。
- 如果把媒体塞进 Dataset file system，Ontology 和应用层会反复造“文件引用、预览、转换、权限”的轮子。

### D2. Reference 还是 Copy

建议：所有下游默认保存 Media Reference，不复制 bytes。

原因：【推断】

- 降低存储成本。
- 保证预览、权限、retention、审计由统一服务控制。
- 支持路径覆盖后旧引用仍稳定指向原始 item。

### D3. Path 是否作为主键

建议：path 只做业务定位键，不做不可变主键；主键必须是 `media_item_id`。

原因：【事实 + 推断】

- Palantir 允许同 path 覆盖。
- 读取 by path 返回最新 item，但 direct reference 可继续指向旧 item。
- 自建如果把 path 当主键，会在覆盖时破坏下游复现性。

### D4. 是否支持 Transactionless

建议：P0 可只做 transactional；P2 再引入 transactionless。

原因：【推断】

- Transactionless 带来部分成功和并发写问题，需要更强的幂等与补偿机制。
- 大部分生产 Pipeline 输出更需要 all-or-nothing。
- 交互式上传再引入 transactionless 更合理。

### D5. Output Media Set 默认 replace 还是 modify

建议：transactional output 默认 `replace`，增量链路显式 `modify`。

原因：【事实 + 推断】

- Palantir transactional Media Set 默认 replace，transactionless 只能 modify。
- 全量 pipeline 应输出完整视图；增量 pipeline 应只追加/修改新增 item。

### D6. 是否做 Virtual Media Set

建议：不要 P0 做。P3/P5 以后再做。

原因：【推断】

- Virtual 不是简单 URL 引用，需要外部源权限、可用性、metadata extraction、源端删除不一致、转换结果落本地等机制。
- 如果没有外部源 manifest 和一致性修复工具，会让用户误以为外部湖被完整纳管。

### D7. OCR/转写是在上传时做还是按需做

建议：预览类按需；生产抽取走 Pipeline。

原因：【推断】

- 上传时全量 OCR 成本不可控。
- Pipeline 处理可记录版本、参数、模型、质量和血缘。
- Access Pattern 适合缩略图/预览等 UI 优化，不适合替代生产数据抽取。

### D8. Media Transform 属于 Operator 还是 Service

建议：Operator 只是声明，真正执行应是 Media Transform Service。

原因：【推断】

- OCR、render、transcribe、tile 等都有统一缓存、限流、成本、重试需求。
- Pipeline Builder、Code Repo、Workshop Preview、OSDK 都可能调用同类能力。
- 做成统一服务更容易治理和复用。

### D9. Media Set 到 Ontology 是直接绑定还是经 Dataset

建议：经 Dataset rows / Object mapping。

原因：【推断】

- 业务对象通常需要文件 metadata、抽取文本、业务主键、关系链接。
- 直接把 Media Set 暴露为 Object Type 会缺少业务语义。
- DICOM 官方示例也是先 Convert media set to table rows，再输出 Object Type。【事实】

### D10. 增量语义是否把 path overwrite 视为阻断

建议：自建平台默认将 path overwrite 视为“可能语义更新”，至少提供策略开关。

原因：【事实 + 推断】

- Palantir 官方说明 path overwrite 不会阻止 Media Set 增量。
- 但很多企业场景中同名文件覆盖意味着内容修订，忽略会导致下游 OCR / embedding 不更新。

### D11. 成本如何治理

建议：每次 media transform 产生成本事件：`media_set_id`、`media_item_id`、`operation`、`bytes`、`model`、`pipeline_run_id`、`owner`。

原因：【推断】

- OCR/VLM/embedding 是高成本操作。
- 如果没有 item 级成本，平台无法解释“哪个 Pipeline 扫了多少 PDF”。

### D12. 安全扫描如何接入

建议：Media Set 进入平台后，支持异步 SDS 扫描：PDF/图片先 OCR，音频先转写，再跑敏感规则。

仓库已有 Marking 调研也提到：Media Set 可通过 OCR/转写后再做 regex，且应支持子集采样降低成本。【事实，来自 `docs/raw/13-marking-advanced-deep-dive.md`】

---

## 13. 与现有平台路线的关系

当前仓库路线中，EOS Dataset 已作为资产控制面 P0，Media Set 被放在 Dataset P2 / 非结构化能力中。结合本轮调研，建议调整认知：【推断】

1. Media Set 不应只是 Dataset 的 P2 扩展，而是和 Dataset 并列的资产类型。
2. P0 仍可以不做完整 Media Set，但数据模型要提前预留 `media_reference` 类型。
3. Pipeline Builder 的算子注册中心应把 `media.*` 作为独立 operator namespace。
4. Ontology Object property 类型应提前考虑 `media_reference`，否则后续文档/图片/音频应用会绕行附件系统。
5. AI 能力应优先落在 Media Set 之上，而不是直接让 LLM 读任意对象存储路径。

---

## 14. 自建风险清单

| 风险 | 表现 | 建议 |
|---|---|---|
| 把 path 当 ID | 覆盖文件导致下游引用漂移 | 使用 immutable `media_item_id` |
| 上传即 OCR | 成本爆炸、上传慢 | OCR 放 Pipeline 或按需缓存 |
| 没有事务 | Pipeline 失败产生半成品 | 生产输出先支持 transactional |
| 没有 reference 类型 | 应用到处复制文件 URL | 统一 `media_reference` |
| 没有 retention | 被覆盖文件长期堆积 | 支持 age 和 overwritten retention |
| 没有 QoS | 大批量处理压垮服务 | 429/503 + retry + batch limit |
| Virtual 过早 | 源端删除/权限/网络不一致 | P5 后做，配 manifest 校验 |
| AI 输出无 schema | 下游不能治理 | 强制 structured output |
| 没有审计 | 敏感文档被模型读取不可追溯 | 每次 read/transform 记录审计 |
| 没有增量策略 | 新增文件反复全量 OCR | 支持 added/current/previous |

---

## 15. 参考资料

Palantir 官方文档：

- Media sets core concept: https://www.palantir.com/docs/foundry/data-integration/media-sets
- Media sets overview: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/media-overview
- Advanced media set settings: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/media-set-settings
- Importing media: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/importing-media
- Media set syncs: https://www.palantir.com/docs/foundry/data-connection/media-set-sync/
- Virtual media sets: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/virtual-media-sets
- Transforming media: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/transforming-media
- Pipeline Builder Transform media: https://www.palantir.com/docs/foundry/pipeline-builder/transforms-transform-media
- Add media set output: https://www.palantir.com/docs/foundry/pipeline-builder/outputs-add-media-set-output/
- Python media sets: https://www.palantir.com/docs/foundry/transforms-python/media-sets/
- Media set transform API: https://www.palantir.com/docs/foundry/transforms-python/media-set-transforms-api/
- Incremental media sets: https://www.palantir.com/docs/foundry/transforms-python-spark/incremental-media-sets/
- Using media in Ontology: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/media-in-ontology/
- DICOM workflow: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/add-dicom-media-set
- Audio transcription workflow: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/add-audio-transcription
- Upload media workflow: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/upload-media
- Media usage limits: https://www.palantir.com/docs/foundry/media-sets-advanced-formats/media-usage-limits/
- Media Set API basics: https://www.palantir.com/docs/foundry/api/v2/media-sets-v2-resources/media-sets/media-set-basics
- Get Media Set API: https://www.palantir.com/docs/foundry/api/v2/media-sets-v2-resources/media-sets/get-media-set
- Put Media Item API: https://www.palantir.com/docs/foundry/api/media-sets-v2-resources/media-sets/put-media-item/
- Register Media Item API: https://www.palantir.com/docs/foundry/api/v2/media-sets-v2-resources/media-sets/register-media-item/
- Commit Media Transaction API: https://www.palantir.com/docs/foundry/api/v2/media-sets-v2-resources/media-sets/commit-media-transaction
- Use LLM expression: https://www.palantir.com/docs/foundry/pb-functions-expression/useLlmV3

仓库内资料：

- `docs/raw/05-testing-and-data-connection.md`
- `docs/raw/13-marking-advanced-deep-dive.md`
- `docs/raw/14-transform-operator-library.md`
- `docs/raw/21-pro-code-capability-deep-dive.md`
- `docs/raw/27-incremental-scheduling-transaction.md`
- `docs/raw/29-lineage-branch-version-pipeline-sync.md`
- `docs/synthesis/operator-platform-design.md`
- `docs/superpowers/specs/2026-04-09-platform-upgrade-design.md`
