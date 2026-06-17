# Palantir Time Series Ontology 建模机制

**日期：** 2026-06-17
**所属 Epic：** #66

---

## 1. 摘要与洞察

1. 【事实】Foundry 使用两种 Ontology 建模方式承载时序：直接在 root object type 上添加 TSP，或创建 linked sensor object type。
2. 【事实】TSP 配置时选择一个保存 series ID 的 `string` property，再绑定一个或多个 time series sync；多个 sync 时需要 qualified series ID。
3. 【事实】Sensor object type 适合只有部分 root objects 拥有某些时序的场景，要求 sensor name 在同一 root object 下唯一，并至少有一个 link type 连接 root object。
4. 【推断】这套模型本质是“业务对象行保存时序引用，点值表独立索引”，减少对象表宽度和稀疏列问题。
5. 【建议】自研平台应把 TSP 建成一种语义属性类型，而不是把时序点值直接塞进对象宽表或 JSON 列。

---

## 2. 两种建模路径

| 路径 | 使用场景 | 数据形态 | 优点 | 风险 |
|---|---|---|---|---|
| Root object TSP | 几乎所有对象都有同一类时序，例如每台设备都有 temperature。 | root object backing dataset 中有 `temperature_series_id` 等属性。 | 对用户简单，TSP 直接显示在对象上。 | 传感器类别过多时对象表变宽，稀疏属性增加。 |
| Sensor object type | 只有部分对象有某些传感器，或传感器类别/单位/类型差异大。 | sensor object backing dataset 每行表示一个传感器，带 series ID、sensor name、foreign key。 | 可用行扩展表达多传感器，避免 root object 上大量 null。 | 需要 link、sensor name 唯一性和 root/sensor 权限协同。 |

官方概览说明，最常见方式是在 object type 上直接添加 TSP；更高级配置是建立 sensor object type 并链接到 root object type。来源：<https://www.palantir.com/docs/foundry/time-series/time-series-overview>

---

## 3. TSP 配置字段

| 配置项 | 公开事实 | 自研含义 |
|---|---|---|
| Series ID property | TSP 选择一个 `string` property 保存 series IDs。 | 对象表必须保存稳定 series key，不能只靠对象 primary key 隐式推导。 |
| Time series sync(s) | TSP 可绑定一个或多个 sync；多个 sync 时使用 qualified series ID。 | TSP 到 sync 是显式 datasource 绑定关系。 |
| Units | 可配置固定 units，或指向 object 上的 string property。 | 单位是 metadata，应与数值点值分离。 |
| Interpolation | 可配置内部 interpolation，Quiver 等应用会尊重该格式。 | 插值策略是消费侧语义，不只是图表参数。 |
| Default TSP | object type 可有一个 default time series property；sensor object type 的单个 TSP 必须是 default。 | 默认属性影响应用无参数展示，属于 UX/语义契约。 |

来源：<https://www.palantir.com/docs/foundry/time-series/time-series-properties>

---

## 4. Sensor Object Type Schema

| 字段 | 类型 | 要求 | 作用 |
|---|---|---|---|
| Primary key | `String` | Required | 唯一标识 sensor object。 |
| Series ID | `String` | Required | 指向 sync 中的 series。 |
| Sensor name | `String` | Required | 标识传感器含义；同一 root object 下唯一。 |
| Foreign key | `String` | Required | 连接 root object type。 |
| Is categorical | `Boolean` | 混合 numerical/categorical sync 时 required | 标识 categorical series。 |
| Units | `String` | Optional | 展示单位。 |

来源：<https://www.palantir.com/docs/foundry/time-series/create-sensor-ot>

---

## 5. Qualified Series ID

【事实】当一个 TSP 由多个 time series sync 支撑时，TSP 的值必须使用 qualified series ID，其 JSON 字符串包含 `seriesId` 和 `syncRid`，并且格式不含换行或空格。来源：<https://www.palantir.com/docs/foundry/time-series/time-series-concepts-glossary>

```json
{"seriesId":"<series-id>","syncRid":"<sync-rid>"}
```

【推断】这个设计说明 Palantir 并不要求全平台 series ID 全局唯一；唯一性可以提升到 `(syncRid, seriesId)`。自研平台应同样避免把设备号、测点号等业务 key 直接当全局唯一主键。

---

## 6. 建模启示

1. 【建议】把 `TimeSeriesPropertyDefinition` 设计为 Ontology 元数据：包含 object_type、property_name、series_id_property、sync_refs、unit_strategy、interpolation_strategy、default_flag。
2. 【建议】把 `SensorObjectTypeDefinition` 设计为 root/sensor link 模式：包含 root_object_type、sensor_object_type、sensor_name_property、series_id_property、categorical_flag_property。
3. 【建议】所有时序值查询都通过 TSP definition 解析到 sync，再查点值；不要允许应用绕过语义层直接扫 raw dataset。
4. 【建议】如果同一个 TSP 允许多个 sync，API 和数据模型必须显式支持 qualified series ID。
