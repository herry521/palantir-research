# 49 — Palantir Data Quality 外部通知安全边界补充调研

**日期：** 2026-05-30  
**关联 Issue：** #43  
**所属 Epic：** #35  
**类型：** 第二轮专家评审补充 / Monitoring Views 外部通知安全边界  

---

## 1. 总结与洞察

1. 【事实】Monitoring Views 的 `Viewer` permission 要求约束的是 Foundry 内监控资源与接收 Monitoring View alert 的用户：用户需要对被监控资源和 monitoring view 都有 `Viewer` permission 才能接收该 view 的 alert。来源：<https://www.palantir.com/docs/foundry/monitoring-views/overview>
2. 【事实】外部系统是另一条通知通道：Monitoring Views 可把 monitors fire 或 resolve 的 alerts 发送到 PagerDuty、Slack 和 webhooks，并且外部集成按 severity 绑定。来源：<https://www.palantir.com/docs/foundry/monitoring-views/external-systems>
3. 【事实】Slack human-readable resource name 不是默认无条件外发；只有资源上的所有 Markings 和 Organizations 都包含在 Slack source 的 exportable markings list 中时才显示名称，否则显示 RID。来源：<https://www.palantir.com/docs/foundry/monitoring-views/external-systems>
4. 【推断】不能把 Foundry `Viewer` permission 写成外部通道泄露防线。外部接收者是否具备 Foundry Viewer 未由官方文档逐一校验；Slack 通过 exportable markings/organizations 控制名称可见性，PagerDuty/webhook/email 的 payload 脱敏边界仍需单独验证。
5. 【建议】自建平台需要把外部通知建模为独立的 export/redaction policy：route severity、payload template、resource-name redaction、RID policy、marking/organization export list、secret handling、receiver/channel ownership、retry/dedupe 和 audit 都应独立于普通 Viewer permission。

---

## 2. 资料源

| 编号 | 来源 | 用途 |
|---|---|---|
| E01 | <https://www.palantir.com/docs/foundry/monitoring-views/overview> | Monitoring Views scope、subscription、Viewer permission、Troubleshoot alerts、snooze、lineage navigation |
| E02 | <https://www.palantir.com/docs/foundry/monitoring-views/external-systems> | PagerDuty、Slack、webhook 外部通知、severity integration、Slack exportable markings |
| E03 | <https://www.palantir.com/docs/foundry/monitoring-views/core-concepts> | Monitoring View、subscriber、alert、severity 等概念 |
| E04 | <https://www.palantir.com/docs/foundry/monitoring-views/rules-reference> | Monitoring rules 与 severity 字段 |
| E05 | <https://www.palantir.com/docs/foundry/data-health/notifications/> | Health Checks 的 Foundry notifications、email 和自动 Foundry Issue |
| E06 | `docs/raw/47-monitoring-views-alert-issue-loop.md` | 第一轮告警/issue 闭环文档；本文件修正其外部通知安全边界表述 |

---

## 3. Viewer Permission 的边界

【事实】Monitoring Views overview 说明：用户必须有被监控资源的 `Viewer` permission 才能监控这些资源；若要接收 Monitoring View 触发的 alerts，用户必须同时有被监控资源和 monitoring view 的 `Viewer` permission。来源：<https://www.palantir.com/docs/foundry/monitoring-views/overview>

【推断】这条规则可以支持两个结论：

- Foundry 内部的 Monitoring View 订阅和 alert 接收不是任意广播，至少会检查资源与 view 的 Viewer 权限。
- 在 Foundry 内部 UI / email / notification 语境中，alert 可见性与资源可见性存在绑定关系。

【待验证】但这条规则不能直接外推到所有外部系统接收者。PagerDuty service、Slack channel、webhook endpoint 的实际阅读者未必逐一拥有 Foundry Viewer；官方文档也没有说明 Foundry 会对外部系统的每个最终接收人做 Foundry 权限校验。

---

## 4. Slack 外部通知安全边界

【事实】Monitoring Views 的 Slack integration 需要先在 Data Connection 中创建 Slack source，并配置 bearer token；官方列出 `channels:join`、`channels:read`、`chat:write`，以及私有频道可选的 `groups:read` scope。来源：<https://www.palantir.com/docs/foundry/monitoring-views/external-systems>

【事实】Slack integration 在 Monitoring View 的 Manage subscriptions tab 配置，并绑定 severity level；每个额外 severity 需要按需重复配置。来源：同上。

【事实】Slack notifications 可以显示 human-readable resource name，也可以只显示 RID。显示名称的条件是：资源上的所有 Markings 和 Organizations 都包含在 Slack source 的 exportable markings list 中；如果任一 marking 或 organization 缺失，则显示 RID。来源：同上。

【事实】配置 Slack source 的 exportable markings 需要 `Information Security Officer` role；添加每个 marking 或 organization 时需要对应 unmarking permission。来源：同上。

【推断】Slack 的安全边界不是简单的 “订阅者有 Viewer 即可”。它至少包含：

- Monitoring View 订阅与 alert 触发侧的 Foundry Viewer permission。
- Slack source 的 bot token scopes 和 channel 可达性。
- Slack source exportable markings/organizations 对资源名称的脱敏控制。
- 外部 Slack channel 成员管理，这部分公开文档没有说明由 Foundry 强制同步 Viewer permission。

【待验证】官方公开文档只证明名称与 RID 的 redaction 行为，没有证明 RID 在所有组织中都被视为非敏感，也没有披露 Slack message 的完整字段、附件、重试、失败告警和审计保留模型。

---

## 5. PagerDuty 与 Webhook 边界

### 5.1 PagerDuty

【事实】PagerDuty integration 使用 PagerDuty Events API V2；一个 integration 将某个 Monitoring View 中某个 severity 的 alerts 映射到 PagerDuty service 的 Events V2 API integration。来源：<https://www.palantir.com/docs/foundry/monitoring-views/external-systems>

【事实】创建 PagerDuty integration 需要 integration name、PagerDuty integration key 和 severity level；不同 severity 可重复配置。来源：同上。

【事实】Monitoring Views created before v1.860.0 release（2024-02）默认不会为 health checks 产生 PagerDuty alerts，需要手动启用；启用后低/中/高 health check severity 分别映射到 `LOW`/`MEDIUM`/`HIGH` integrations。来源：同上。

【待验证】公开文档没有展开 PagerDuty payload 字段、dedup key、resolve/reopen 映射、acknowledge 是否回写 Foundry、PagerDuty 接收者是否具备 Foundry 权限等行为。

### 5.2 Webhook

【事实】Webhook integration 触发 Data Connection 中配置的 Webhooks；webhook 必须有一个 string input parameter，官方称为 `Message` parameter；Monitoring View 会把 notification 内容填入该参数，且当前内容不可自定义。来源：<https://www.palantir.com/docs/foundry/monitoring-views/external-systems>

【事实】Webhook integration 同样在 Manage subscriptions tab 配置，并绑定 severity level。来源：同上。

【待验证】公开文档没有披露 webhook `Message` 的完整 payload 内容、是否签名、重试策略、失败告警、endpoint 权限模型、消息保留与脱敏策略。

---

## 6. Health Checks Issue 与外部通知的边界

【事实】Data Health 可在 Health Check 失败时自动 report/create Foundry Issue，并可指定 assignee；check resolves 后可自动 close issue。来源：<https://www.palantir.com/docs/foundry/data-health/notifications/>

【事实】Data Health 会向 failed check 的 watchers 发送 Foundry in-platform notification；watcher 也可启用 email notifications。来源：同上。

【待验证】官方 notifications 页面确认的是 Health Checks 的 issue 创建/关闭；本轮没有找到 Monitoring Rule alert 直接自动创建 Foundry Issue 的同等官方说明。

【待验证】email notification 的 payload 字段、摘要频率、去重、外部邮箱接收者权限变化处理、是否隐藏敏感 resource name 未在当前公开页面中展开。

---

## 7. 修正第一轮结论

第一轮 `docs/raw/47-monitoring-views-alert-issue-loop.md` 中 “Viewer permission 避免通过 Slack/email 等通道泄露用户无权查看的资源上下文” 表述过强，应修正为：

1. 【事实】Viewer permission 限制 Foundry 内监控和 alert 接收资格。
2. 【事实】Monitoring Views 可把 alerts 发送到外部系统，外部系统集成按 severity 配置。
3. 【事实】Slack 通过 exportable markings/organizations 控制 human-readable resource name 是否可外显；缺失时显示 RID。
4. 【推断】外部通道需要独立 export/redaction policy，不能只依赖 Viewer permission。
5. 【待验证】PagerDuty、webhook、email 的完整 payload 脱敏、重试、签名、dedupe 和接收者权限边界仍未由公开文档披露。

---

## 8. 自建平台启示

| 设计项 | 最小要求 |
|---|---|
| ExternalRoutePolicy | route id、channel type、severity、resource type、scope、enabled state |
| ExportPolicy | allowed markings、allowed organizations、field-level redaction、RID/name display policy |
| PayloadSchema | channel-specific payload fields、customization flag、schema version、sensitive fields |
| ReceiverControl | external channel owner、approval owner、last verification time、membership audit link |
| SecretHandling | token/key reference、rotation policy、least-privilege scopes |
| DeliverySemantics | fire/resolve mapping、retry、dedupe key、failure alert、dead letter handling |
| IssueLinkage | which check/alert can create issue、assignee binding、auto-close condition、reopen behavior |
| Audit | who configured route、what markings are exportable、which alert was sent, to where, with what redaction |

【建议】外部通知安全设计的核心不是“是否能发到 Slack/PagerDuty/webhook”，而是“可发什么字段、什么资源名、基于什么敏感标签、由谁批准、失败如何处理、事后如何审计”。

---

## 9. 证据缺口

1. 【待验证】PagerDuty payload、dedup key、resolve/reopen、acknowledge 回写 Foundry 的行为。
2. 【待验证】Webhook payload 完整字段、签名、重试、失败告警、endpoint 权限模型。
3. 【待验证】Email notification 的字段、摘要频率、去重、敏感字段脱敏和接收者权限变化处理。
4. 【待验证】RID 是否在所有租户中可视为低敏信息；官方只说明 RID 会替代 human-readable name，没有说明 RID 的组织安全分类。
5. 【待验证】外部 channel 成员管理是否可与 Foundry user/group 自动同步；公开文档只说明 Slack source 和 channel 配置。
6. 【待验证】Health Check 自动 issue 的 dedupe、reopen、rename/delete 后绑定、跨 Marketplace 安装迁移仍未公开。
