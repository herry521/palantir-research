# Palantir Time Series 消费、派生序列与告警能力

**日期：** 2026-06-17
**所属 Epic：** #66

---

## 1. 摘要与洞察

1. 【事实】Foundry Time Series 的消费入口覆盖 Quiver、Vertex、Workshop、Map、Object Explorer、FoundryTS 和 Automate。
2. 【事实】Derived series 可把时序计算逻辑保存为 Palantir resource，并可回写到 Ontology 作为 TSP 暴露；进入 Ontology 后像 raw TSP 一样被应用消费，但按需计算。
3. 【事实】Workshop 支持 time series transforms，例如 aggregate、time shift、moving average 等，并可在 Chart XY、Map、Metric Card、Object Table 等 widget 中使用。
4. 【事实】Time series alerting automation 面向健康数据中的异常事件，不用于检查 pipeline volume/quality；后者应使用 Data Health 或 stream monitoring。
5. 【推断】Palantir 的特性重点不是单个图表控件，而是把同一 TSP 语义暴露给分析、应用、代码和自动化。

---

## 2. 消费入口矩阵

| 入口 | 能力 | 证据 |
|---|---|---|
| Quiver | TSP 可视化、time series operations、derived series logic 管理。 | <https://www.palantir.com/docs/foundry/time-series/derived-series-overview> |
| Workshop | Chart XY、Map、Metric Card、Object Table、Variables；可应用 transforms。 | <https://www.palantir.com/docs/foundry/workshop/time-series-properties> |
| Map | Selection panel Series tab、timeline、按当前 time selection 着色。 | <https://www.palantir.com/docs/foundry/map/time-series> |
| FoundryTS | Python 查询库，可直接过滤 time series 或从 Ontology property 查询。 | <https://www.palantir.com/docs/foundry/time-series/foundryts> |
| Automate | Time series condition 和 alerting automation。 | <https://www.palantir.com/docs/foundry/time-series/alerting-setup> |
| Time Series Catalog | 管理/发现 sync、time series object types、derived series。 | <https://www.palantir.com/docs/foundry/time-series/time-series-time-series-catalog> |

---

## 3. Derived Series

【事实】Derived series 允许用户保存和复制应用在 Ontology time series 上的计算和 transform；保存为 Palantir resource 后可共享，并保存回 Ontology 作为 TSP；进入 Ontology 后行为像普通 TSP，但按需计算，避免管理或存储派生数据。来源：<https://www.palantir.com/docs/foundry/time-series/derived-series-overview>

| 类型 | 特征 | 使用场景 |
|---|---|---|
| Templated derived series | 绑定 root object type，逻辑必须包含单个 root object；可复制到同类对象。 | 对每台设备都计算 rolling average、pressure delta 等。 |
| Single derived series | 不模板化，可作用于多个对象，逻辑不要求所有输入来自一个 object。 | 跨对象或专项分析计算。 |

【事实】Derived series 权限包括创建/更新 resource、查看包含 derived series 的 TSP、管理 Ontology saving。用户查看 derived TSP 时，必须能访问该逻辑引用的所有输入 TSP，并满足查看 TSP value 的要求。来源：<https://www.palantir.com/docs/foundry/time-series/derived-series-permissions>

---

## 4. Workshop Transforms

【事实】Workshop 中 time series transform 对输入 time series 执行数学操作，输出新 time series；输入可以是 TSP 或其他 transforms 输出，因此 transform 可链式组合。来源：<https://www.palantir.com/docs/foundry/workshop/time-series-properties>

| Transform 类别 | 说明 | 自研对应 |
|---|---|---|
| Aggregate | 对窗口内点值做汇总，可设置 window type、alignment timestamp 等。 | window aggregate operator。 |
| Moving / rolling | 用滚动窗口平滑或聚合。 | rolling function。 |
| Derivative / formula | 基于一个或多个序列做数学计算。 | expression engine + type checking。 |
| Time shift / resample | 对齐时间轴或移动序列。 | time alignment operator。 |

【推断】这些 transform 最终依赖同一套 TSP 查询和 Quiver/Workshop 逻辑卡片，而不是每个 widget 自行实现时序查询。

---

## 5. Time Series Alerting

```text
root object type scope
  -> object time series property card
  -> optional transforms
  -> time series search card
  -> alert object type / events
  -> automation schedule or stream evaluation
```

【事实】Time series alerting setup 支持选择 TSP 输入，raw 和 derived series 都可作为输入，并可应用 derivatives、rolling averages 等 Quiver transforms。来源：<https://www.palantir.com/docs/foundry/time-series/alerting-setup>

【事实】当前 alerting automation 只支持 basic time series searches；Multi time series search formula type 和 multiple conditions 不能保存，Defined search time range、minimum/maximum durations 会被忽略。来源：<https://www.palantir.com/docs/foundry/time-series/alerting-setup>

【事实】Palantir 明确 time series alerting 用于监控健康数据中的 anomalous events，不用于检查 pipeline volume/quality；后者推荐 Data Health 或 stream monitoring。来源：<https://www.palantir.com/docs/foundry/time-series/alerting-overview>

---

## 6. 自研特性清单

| 层级 | 必做能力 | 延后能力 |
|---|---|---|
| API | 按 TSP 查询 series、time range filter、latest point、multi-series fetch。 | 高级 time series search DSL。 |
| 应用 | sparkline、line chart、current selected time、单位展示。 | 完整 Quiver 类图形化逻辑编辑器。 |
| Transform | aggregate、rolling average、derivative、formula。 | 用户自定义复杂函数和跨对象模板化派生序列。 |
| Derived | 保存 derived definition、权限校验、按需计算。 | 自动回写 Ontology 和 Marketplace packaging。 |
| Alerting | 单条件 search、scope filter、事件对象输出。 | 多条件、多序列公式、复杂持续时长判断。 |

【建议】第一版自研产品应先保证 TSP 在对象详情、对象列表、地图/时间选择、代码 SDK 中共享同一语义，再建设高级分析和自动化。
