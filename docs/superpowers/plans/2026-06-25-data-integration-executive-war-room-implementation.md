# Data Integration Executive War Room Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the existing Data Integration capability map page into an executive war-room report page while preserving configurable capability statuses.

**Architecture:** Keep the implementation static and dependency-free inside `deliverables/pages/data-integration-capability-map.html` plus scoped styles in `deliverables/styles.css`. Add a report-node mapping layer on top of the existing Palantir-aligned capability data, render the executive summary and Palantir object chain from that mapping, and retain the detailed capability list as a secondary section.

**Tech Stack:** Static HTML, vanilla JavaScript, CSS, localStorage, Playwright via local Chrome for visual verification.

---

## Summary Insights

1. [Decision] The existing capability data remains the source of truth; the new war-room view is a presentation layer over that data.
2. [Decision] The six report nodes are `Connectivity`, `Datasets`, `Pipeline`, `Builds`, `Lineage & Schedules`, and `Ontology`, matching the approved design.
3. [Decision] Status configuration remains per capability, but executive metrics aggregate those capability statuses into report-node readiness.
4. [Decision] The detailed module view stays on the page as the operational appendix, visually below the executive war-room view.
5. [Risk] The page is currently a large single HTML file; keep edits tightly scoped and verify render behavior after each JavaScript change.

## File Structure

- Modify: `deliverables/pages/data-integration-capability-map.html`
  - Replace the current hero/control/map sections with an executive report shell.
  - Keep `DI_MAP_MODULES` as-is.
  - Add `DI_REPORT_CONTENT` and `DI_REPORT_NODES`.
  - Add helpers for capability lookup, report-node stats, executive metrics, insight rendering, and appendix rendering.
  - Rewire `diRenderCapabilityMap()` so all report and appendix areas update together.
- Modify: `deliverables/styles.css`
  - Replace or extend the `.di-map-*` styles at the end of the file.
  - Add the war-room layout, executive metric cards, Palantir object node cards, bottom insight cards, low-emphasis config controls, appendix styles, and presentation-mode behavior.
- No new runtime dependencies.
- No changes to `deliverables/app.js` are required.

## Implementation Tasks

### Task 1: Replace Page Shell With Executive War-Room Sections

**Files:**
- Modify: `deliverables/pages/data-integration-capability-map.html`

- [ ] **Step 1: Update the page title and hero copy**

Replace:

```html
<title>Palantir Data Integration 能力地图</title>
```

with:

```html
<title>Palantir Data Integration 战情图</title>
```

In the `.topic-header.di-map-header` section, replace the existing `h1`, intro, and tags with:

```html
<p class="eyebrow">Palantir Data Integration Readiness</p>
<h1>Data Integration 战情图</h1>
<p class="intro-note">
  面向领导汇报的 Data Integration 能力完备性视图：基于 Palantir 官方对象链路展示主链路成熟度、关键缺口、风险和下一步动作。
</p>
<div class="topic-meta">
  <span class="tag">Executive War Room</span>
  <span class="tag">Palantir Objects</span>
  <span class="tag">Configurable Status</span>
</div>
```

- [ ] **Step 2: Replace the control and map sections with the new executive layout**

Replace the current sections from:

```html
<section class="page-section di-map-control-section" aria-label="能力地图控制台">
```

through the closing `</section>` of:

```html
<section class="page-section di-map-stage" aria-label="Palantir Data Integration 能力地图">
```

with:

```html
<section class="page-section di-map-report" aria-label="Data Integration 战情图">
  <div class="di-map-report-hero">
    <div>
      <p class="di-map-report-kicker">Palantir Data Integration Readiness</p>
      <h2 id="di-report-title"></h2>
      <p id="di-report-subtitle"></p>
    </div>
    <div class="di-map-summary-grid" id="di-map-summary"></div>
  </div>

  <div class="di-map-toolbar di-map-report-toolbar" aria-label="能力地图操作">
    <button class="di-map-action" type="button" id="di-toggle-presentation">演示模式</button>
    <button class="di-map-action" type="button" id="di-export-json">导出 JSON</button>
    <button class="di-map-action" type="button" id="di-import-json">导入 JSON</button>
    <button class="di-map-action danger" type="button" id="di-reset-status">重置</button>
  </div>

  <div class="di-map-legend" aria-label="状态图例">
    <span><i class="status-dot status-not-started"></i>未开始</span>
    <span><i class="status-dot status-in-progress"></i>进行中</span>
    <span><i class="status-dot status-done"></i>已完成</span>
    <span><i class="status-dot status-risk"></i>风险</span>
  </div>

  <div class="di-report-chain" id="di-report-chain" aria-label="Palantir 官方对象主链路"></div>
  <div class="di-report-insights" id="di-report-insights" aria-label="汇报洞察"></div>
</section>

<section class="page-section di-map-appendix" aria-label="能力明细">
  <div class="section-head">
    <div>
      <p class="section-kicker">Capability Appendix</p>
      <h2>能力明细与状态配置</h2>
    </div>
    <p>完整二级能力保留在明细区，用于配置状态和核对 Palantir 对齐口径。</p>
  </div>
  <div class="di-map-stage">
    <div class="di-map-zone di-map-zone-driver">
      <div class="di-map-zone-label">驱动与观察</div>
      <div class="di-map-zone-grid" id="di-map-driver"></div>
    </div>

    <div class="di-map-zone di-map-zone-main">
      <div class="di-map-zone-label">主链路明细</div>
      <div class="di-map-flow" id="di-map-main"></div>
    </div>

    <div class="di-map-zone di-map-zone-support">
      <div class="di-map-zone-label">支撑层</div>
      <div class="di-map-zone-grid" id="di-map-support"></div>
    </div>
  </div>
</section>
```

- [ ] **Step 3: Verify static HTML structure**

Run:

```bash
rg -n "di-map-report|di-report-chain|di-map-appendix|di-report-title" deliverables/pages/data-integration-capability-map.html
```

Expected: matches for all four ids/classes.

- [ ] **Step 4: Commit**

```bash
git add deliverables/pages/data-integration-capability-map.html
git commit -m "feat: add executive report shell"
```

Expected: commit succeeds and only `deliverables/pages/data-integration-capability-map.html` is included.

### Task 2: Add Report Content, Node Mapping, and Aggregation Helpers

**Files:**
- Modify: `deliverables/pages/data-integration-capability-map.html`

- [ ] **Step 1: Add report content constants after `DI_MAP_MODULES`**

Immediately after the closing `];` of `DI_MAP_MODULES`, insert:

```js
const DI_REPORT_CONTENT = {
  title: "主链路已形成端到端闭环，下一阶段聚焦实时链路与对象服务补强",
  subtitle:
    "基于 Palantir 官方能力对象组织，从 Connectivity、Datasets、Pipeline、Builds 到 Lineage / Schedules 与 Ontology，展示能力完备性、风险和下一步动作。",
  insights: [
    {
      id: "progress",
      label: "关键进展",
      tone: "done",
      text: "Connectivity、Datasets、Builds 支撑核心链路闭环，具备从接入到构建的基础完备性。"
    },
    {
      id: "gap",
      label: "主要缺口",
      tone: "risk",
      text: "Streaming Pipeline、Schedules 编排、Ontology serving freshness 是规模化落地风险集中区。"
    },
    {
      id: "next",
      label: "下一步动作",
      tone: "in-progress",
      text: "按主链路补齐实时处理、调度治理和对象新鲜度验证，形成可复制的业务接入模板。"
    }
  ]
};
```

- [ ] **Step 2: Add Palantir report-node mapping after `DI_REPORT_CONTENT`**

Insert:

```js
const DI_REPORT_NODES = [
  {
    id: "connectivity",
    name: "Connectivity",
    zhName: "数据连接与同步",
    summary: "外部系统连接、数据源探索、批量/流式同步与数据外发。",
    capabilityRefs: [
      "data-connection.agents",
      "data-connection.sources",
      "data-connection.batch-sync",
      "data-connection.streaming-sync",
      "data-connection.exports"
    ]
  },
  {
    id: "datasets",
    name: "Datasets",
    zhName: "数据集与事务版本",
    summary: "承载数据状态、事务、分支和流式数据的核心对象层。",
    capabilityRefs: [
      "core-data-objects.datasets",
      "core-data-objects.transactions",
      "core-data-objects.branches",
      "core-data-objects.streams"
    ]
  },
  {
    id: "pipeline",
    name: "Pipeline",
    zhName: "数据加工开发",
    summary: "Pipeline Builder、Code Repositories 与批/增/流加工形态。",
    capabilityRefs: [
      "pipeline-authoring.pipeline-builder",
      "pipeline-authoring.code-repositories",
      "pipeline-types.batch-pipelines",
      "pipeline-types.incremental-pipelines",
      "pipeline-types.streaming-pipelines"
    ]
  },
  {
    id: "builds",
    name: "Builds",
    zhName: "构建执行与新鲜度",
    summary: "通过 Build、Jobs、Build resolution 和 Staleness 计算数据集新版本。",
    capabilityRefs: [
      "builds.build",
      "builds.jobs",
      "builds.build-resolution",
      "builds.staleness"
    ]
  },
  {
    id: "lineage-schedules",
    name: "Lineage & Schedules",
    zhName: "血缘观测与调度",
    summary: "血缘图、构建时间线、过期分析和调度触发机制。",
    capabilityRefs: [
      "data-lineage.lineage-graph",
      "data-lineage.build-timeline",
      "data-lineage.stale-analysis",
      "schedules.schedule",
      "schedules.time-trigger",
      "schedules.data-updated-trigger"
    ]
  },
  {
    id: "ontology",
    name: "Ontology",
    zhName: "对象服务",
    summary: "将 Foundry 数据源映射为业务对象、对象集合、动作和对象索引。",
    capabilityRefs: [
      "ontology-object-backend.object-types",
      "ontology-object-backend.object-sets",
      "ontology-object-backend.actions",
      "ontology-object-backend.object-data-funnel",
      "ontology-object-backend.object-indexing"
    ]
  }
];
```

- [ ] **Step 3: Add capability lookup helpers after `diGetStatus()`**

Insert:

```js
function diFindCapability(ref) {
  const [moduleId, capabilityId] = ref.split(".");
  const module = DI_MAP_MODULES.find((item) => item.id === moduleId);
  if (!module) return null;
  const capability = module.capabilities.find((item) => item.id === capabilityId);
  if (!capability) return null;
  return { module, capability };
}

function diStatusFromProgress(progress, hasRisk, hasInProgress) {
  if (hasRisk) return "risk";
  if (progress === 100) return "done";
  if (progress > 0 || hasInProgress) return "in-progress";
  return "not-started";
}
```

- [ ] **Step 4: Add report-node stats after `diModuleStats()`**

Insert:

```js
function diReportNodeStats(node) {
  const entries = node.capabilityRefs.map(diFindCapability).filter(Boolean);
  const statuses = entries.map((entry) => diGetStatus(entry.module.id, entry.capability.id));
  const total = statuses.length || 1;
  const done = statuses.filter((status) => status === "done").length;
  const inProgress = statuses.filter((status) => status === "in-progress").length;
  const risk = statuses.filter((status) => status === "risk").length;
  const progress = Math.round((done / total) * 100);
  return {
    total,
    done,
    inProgress,
    risk,
    progress,
    status: diStatusFromProgress(progress, risk > 0, inProgress > 0),
    capabilities: entries
  };
}
```

- [ ] **Step 5: Replace `diOverallStats()` with report-aware metrics**

Replace the full existing `diOverallStats()` function with:

```js
function diOverallStats() {
  const capabilities = DI_MAP_MODULES.flatMap((module) => module.capabilities.map((capability) => ({ module, capability })));
  const coreCapabilities = capabilities.filter((item) => item.capability.core);
  const statusCounts = capabilities.reduce(
    (acc, item) => {
      const status = diGetStatus(item.module.id, item.capability.id);
      acc[status] += 1;
      return acc;
    },
    { "not-started": 0, "in-progress": 0, done: 0, risk: 0 }
  );
  const coreDone = coreCapabilities.filter((item) => diGetStatus(item.module.id, item.capability.id) === "done").length;
  const coreTotal = coreCapabilities.length || 1;
  const reportNodeStats = DI_REPORT_NODES.map((node) => ({ node, stats: diReportNodeStats(node) }));
  const litNodes = reportNodeStats.filter((item) => item.stats.status === "done" || item.stats.status === "in-progress").length;
  const riskNodes = reportNodeStats.filter((item) => item.stats.status === "risk").length;
  const criticalGaps = coreCapabilities.filter((item) => {
    const status = diGetStatus(item.module.id, item.capability.id);
    return status === "not-started" || status === "in-progress";
  }).length;
  return {
    ...statusCounts,
    completion: Math.round((coreDone / coreTotal) * 100),
    total: capabilities.length,
    coreTotal,
    coreDone,
    litNodes,
    reportNodeTotal: DI_REPORT_NODES.length,
    riskNodes,
    criticalGaps
  };
}
```

- [ ] **Step 6: Extract and check inline script syntax**

Run:

```bash
node - <<'NODE'
const fs = require('fs');
const html = fs.readFileSync('deliverables/pages/data-integration-capability-map.html', 'utf8');
const script = html.match(/<script>([\s\S]*)<\/script>/)[1];
new Function(script);
console.log('inline script syntax ok');
NODE
```

Expected output:

```text
inline script syntax ok
```

- [ ] **Step 7: Commit**

```bash
git add deliverables/pages/data-integration-capability-map.html
git commit -m "feat: add report node metrics"
```

Expected: commit succeeds.

### Task 3: Render Executive Summary, Palantir Chain, and Insights

**Files:**
- Modify: `deliverables/pages/data-integration-capability-map.html`

- [ ] **Step 1: Replace `diRenderSummary()`**

Replace the full existing `diRenderSummary()` function with:

```js
function diRenderSummary() {
  const stats = diOverallStats();
  const summary = document.getElementById("di-map-summary");
  summary.innerHTML = [
    ["核心能力成熟度", `${stats.completion}%`, `${stats.coreDone}/${stats.coreTotal} 个核心能力已完成`, "neutral"],
    ["对象域点亮", `${stats.litNodes}/${stats.reportNodeTotal}`, "Palantir 主链路对象域", "neutral"],
    ["关键能力缺口", stats.criticalGaps, "核心能力未完成或进行中", "warning"],
    ["需关注风险", stats.risk + stats.riskNodes, "风险能力与风险对象域", "risk"]
  ]
    .map(
      ([label, value, note, tone]) => `
        <article class="di-map-stat tone-${tone}">
          <span>${label}</span>
          <strong>${value}</strong>
          <small>${note}</small>
        </article>
      `
    )
    .join("");
}
```

- [ ] **Step 2: Add report hero renderer after `diRenderSummary()`**

Insert:

```js
function diRenderReportHero() {
  document.getElementById("di-report-title").textContent = DI_REPORT_CONTENT.title;
  document.getElementById("di-report-subtitle").textContent = DI_REPORT_CONTENT.subtitle;
}
```

- [ ] **Step 3: Add report-node renderer after `diRenderReportHero()`**

Insert:

```js
function diReportNodeHtml(node) {
  const stats = diReportNodeStats(node);
  const capabilityHtml = stats.capabilities
    .slice(0, 5)
    .map((entry) => `<li>${entry.capability.name}</li>`)
    .join("");
  return `
    <article class="di-report-node status-${stats.status}">
      <div class="di-report-node-topline"></div>
      <div class="di-report-node-head">
        <div>
          <span class="di-report-node-kicker">${DI_STATUS_LABELS[stats.status]}</span>
          <h3>${node.name}</h3>
          <p>${node.zhName}</p>
        </div>
        <strong>${stats.progress}%</strong>
      </div>
      <p class="di-report-node-summary">${node.summary}</p>
      <ul class="di-report-node-capabilities">${capabilityHtml}</ul>
      <div class="di-map-progress-bar"><span style="width:${stats.progress}%"></span></div>
    </article>
  `;
}

function diRenderReportChain() {
  document.getElementById("di-report-chain").innerHTML = DI_REPORT_NODES.map(diReportNodeHtml).join("");
}
```

- [ ] **Step 4: Add insight renderer after `diRenderReportChain()`**

Insert:

```js
function diRenderInsights() {
  document.getElementById("di-report-insights").innerHTML = DI_REPORT_CONTENT.insights
    .map(
      (item) => `
        <article class="di-report-insight tone-${item.tone}">
          <span>${item.label}</span>
          <p>${item.text}</p>
        </article>
      `
    )
    .join("");
}
```

- [ ] **Step 5: Update `diRenderCapabilityMap()`**

Replace the first line inside `diRenderCapabilityMap()`:

```js
diRenderSummary();
```

with:

```js
diRenderReportHero();
diRenderSummary();
diRenderReportChain();
diRenderInsights();
```

Keep the existing zone rendering and event binding below those calls.

- [ ] **Step 6: Run inline script syntax verification**

Run:

```bash
node - <<'NODE'
const fs = require('fs');
const html = fs.readFileSync('deliverables/pages/data-integration-capability-map.html', 'utf8');
const script = html.match(/<script>([\s\S]*)<\/script>/)[1];
new Function(script);
console.log('inline script syntax ok');
NODE
```

Expected output:

```text
inline script syntax ok
```

- [ ] **Step 7: Commit**

```bash
git add deliverables/pages/data-integration-capability-map.html
git commit -m "feat: render executive report view"
```

Expected: commit succeeds.

### Task 4: Apply Executive War-Room Styling

**Files:**
- Modify: `deliverables/styles.css`

- [ ] **Step 1: Add report layout styles after `.di-map-header .intro-note`**

Insert:

```css
.di-map-report {
  border: 1px solid rgba(31, 41, 55, 0.12);
  border-radius: 16px;
  background:
    linear-gradient(135deg, rgba(20, 184, 166, 0.08), transparent 36%),
    linear-gradient(180deg, rgba(255, 255, 255, 0.96), rgba(248, 250, 252, 0.92));
  box-shadow: 0 24px 60px rgba(15, 23, 42, 0.08);
  display: grid;
  gap: 18px;
}

.di-map-report-hero {
  align-items: start;
  display: grid;
  gap: 22px;
  grid-template-columns: minmax(0, 1.7fr) minmax(360px, 0.9fr);
}

.di-map-report-kicker {
  color: #0f766e;
  font-size: 12px;
  font-weight: 900;
  letter-spacing: 0.16em;
  margin: 0 0 10px;
  text-transform: uppercase;
}

.di-map-report h2 {
  color: #0f172a;
  font-size: clamp(32px, 4vw, 54px);
  line-height: 1.06;
  margin: 0;
  max-width: 980px;
}

.di-map-report h2 + p {
  color: #475569;
  font-size: 16px;
  line-height: 1.7;
  margin: 14px 0 0;
  max-width: 920px;
}
```

- [ ] **Step 2: Update summary card visual states**

Append after the existing `.di-map-stat strong` rule:

```css
.di-map-stat.tone-warning {
  background: #fffbeb;
  border-color: rgba(217, 119, 6, 0.28);
}

.di-map-stat.tone-risk {
  background: #fff7ed;
  border-color: rgba(194, 65, 12, 0.3);
}

.di-map-stat.tone-risk strong {
  color: var(--di-risk);
}
```

- [ ] **Step 3: Add report chain and node styles before `.di-map-stage`**

Insert:

```css
.di-report-chain {
  display: grid;
  gap: 12px;
  grid-template-columns: repeat(6, minmax(0, 1fr));
}

.di-report-node {
  border: 1px solid var(--di-border);
  border-radius: 12px;
  background: #fff;
  box-shadow: 0 14px 34px rgba(15, 23, 42, 0.07);
  min-width: 0;
  overflow: hidden;
  padding: 0 13px 13px;
}

.di-report-node-topline {
  height: 5px;
  margin: 0 -13px 12px;
}

.di-report-node.status-done {
  background: #ecfdf5;
  border-color: rgba(22, 163, 74, 0.34);
}

.di-report-node.status-done .di-report-node-topline,
.di-report-node.status-done .di-map-progress-bar span {
  background: var(--di-done);
}

.di-report-node.status-in-progress {
  background: #eff6ff;
  border-color: rgba(37, 99, 235, 0.34);
}

.di-report-node.status-in-progress .di-report-node-topline,
.di-report-node.status-in-progress .di-map-progress-bar span {
  background: var(--di-progress);
}

.di-report-node.status-risk {
  background: #fff7ed;
  border-color: rgba(194, 65, 12, 0.38);
}

.di-report-node.status-risk .di-report-node-topline,
.di-report-node.status-risk .di-map-progress-bar span {
  background: var(--di-risk);
}

.di-report-node.status-not-started {
  background: #f8fafc;
  opacity: 0.78;
}

.di-report-node.status-not-started .di-report-node-topline,
.di-report-node.status-not-started .di-map-progress-bar span {
  background: #94a3b8;
}

.di-report-node-head {
  align-items: flex-start;
  display: flex;
  gap: 10px;
  justify-content: space-between;
}

.di-report-node-kicker {
  color: #64748b;
  display: block;
  font-size: 11px;
  font-weight: 900;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.di-report-node h3 {
  color: #0f172a;
  font-size: 18px;
  line-height: 1.15;
  margin: 5px 0 4px;
}

.di-report-node-head p {
  color: #475569;
  font-size: 12px;
  margin: 0;
}

.di-report-node-head strong {
  color: #0f172a;
  font-size: 18px;
  line-height: 1;
}

.di-report-node-summary {
  color: #334155;
  font-size: 12px;
  line-height: 1.5;
  margin: 11px 0;
}

.di-report-node-capabilities {
  display: grid;
  gap: 5px;
  list-style: none;
  margin: 0 0 12px;
  padding: 0;
}

.di-report-node-capabilities li {
  color: #475569;
  font-size: 11px;
  line-height: 1.25;
}
```

- [ ] **Step 4: Add insight and appendix styles before media queries**

Insert:

```css
.di-report-insights {
  display: grid;
  gap: 12px;
  grid-template-columns: repeat(3, minmax(0, 1fr));
}

.di-report-insight {
  border: 1px solid var(--di-border);
  border-radius: 12px;
  background: #fff;
  padding: 14px;
}

.di-report-insight span {
  display: block;
  font-size: 12px;
  font-weight: 900;
  margin-bottom: 7px;
}

.di-report-insight p {
  color: #334155;
  font-size: 13px;
  line-height: 1.65;
  margin: 0;
}

.di-report-insight.tone-done {
  background: #ecfdf5;
  border-color: rgba(22, 163, 74, 0.34);
}

.di-report-insight.tone-done span {
  color: #166534;
}

.di-report-insight.tone-risk {
  background: #fff7ed;
  border-color: rgba(194, 65, 12, 0.34);
}

.di-report-insight.tone-risk span {
  color: #9a3412;
}

.di-report-insight.tone-in-progress {
  background: #eff6ff;
  border-color: rgba(37, 99, 235, 0.34);
}

.di-report-insight.tone-in-progress span {
  color: #1d4ed8;
}

.di-map-report-toolbar {
  justify-content: flex-end;
}

.di-map-presentation-mode .site-nav,
.di-map-presentation-mode .topic-header,
.di-map-presentation-mode .di-map-report-toolbar,
.di-map-presentation-mode .di-map-appendix,
.di-map-presentation-mode .page-section:last-of-type {
  display: none;
}

.di-map-presentation-mode .site-shell {
  padding-top: 18px;
}
```

- [ ] **Step 5: Extend responsive rules**

Inside `@media (max-width: 1180px)`, add:

```css
.di-map-report-hero {
  grid-template-columns: 1fr;
}

.di-report-chain {
  grid-template-columns: repeat(3, minmax(220px, 1fr));
}
```

Inside `@media (max-width: 760px)`, add:

```css
.di-report-chain,
.di-report-insights {
  grid-template-columns: 1fr;
}

.di-map-report {
  border-radius: 12px;
  padding: 18px;
}

.di-map-report h2 {
  font-size: 30px;
}
```

- [ ] **Step 6: Run CSS selector smoke check**

Run:

```bash
rg -n "di-map-report|di-report-chain|di-report-node|di-report-insights|di-map-presentation-mode" deliverables/styles.css
```

Expected: matches for all five selector groups.

- [ ] **Step 7: Commit**

```bash
git add deliverables/styles.css
git commit -m "style: add executive war room layout"
```

Expected: commit succeeds.

### Task 5: Browser Verification and Interaction Checks

**Files:**
- Test only; no planned file edits.

- [ ] **Step 1: Run inline script syntax verification**

Run:

```bash
node - <<'NODE'
const fs = require('fs');
const html = fs.readFileSync('deliverables/pages/data-integration-capability-map.html', 'utf8');
const script = html.match(/<script>([\s\S]*)<\/script>/)[1];
new Function(script);
console.log('inline script syntax ok');
NODE
```

Expected output:

```text
inline script syntax ok
```

- [ ] **Step 2: Run Playwright DOM verification**

Run:

```bash
NODE_PATH=/Users/huyongqiang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules \
  /Users/huyongqiang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node - <<'NODE'
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  await page.goto('file://' + process.cwd() + '/deliverables/pages/data-integration-capability-map.html');
  await page.waitForLoadState('networkidle');
  const result = await page.evaluate(() => ({
    title: document.querySelector('#di-report-title')?.textContent.trim(),
    stats: [...document.querySelectorAll('.di-map-stat')].map((item) => item.textContent.trim()),
    nodes: [...document.querySelectorAll('.di-report-node h3')].map((item) => item.textContent.trim()),
    insights: [...document.querySelectorAll('.di-report-insight span')].map((item) => item.textContent.trim()),
    statusButtons: document.querySelectorAll('.di-map-status-button').length
  }));
  console.log(JSON.stringify(result, null, 2));
  await browser.close();
})();
NODE
```

Expected output contains:

```json
{
  "title": "主链路已形成端到端闭环，下一阶段聚焦实时链路与对象服务补强",
  "nodes": ["Connectivity", "Datasets", "Pipeline", "Builds", "Lineage & Schedules", "Ontology"],
  "insights": ["关键进展", "主要缺口", "下一步动作"]
}
```

`statusButtons` should be greater than `0`.

- [ ] **Step 3: Verify status import updates report nodes**

Run:

```bash
NODE_PATH=/Users/huyongqiang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules \
  /Users/huyongqiang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node - <<'NODE'
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  await page.goto('file://' + process.cwd() + '/deliverables/pages/data-integration-capability-map.html');
  await page.waitForLoadState('networkidle');
  await page.evaluate(() => {
    localStorage.setItem('palantir-di-capability-map-statuses-v1', JSON.stringify({
      'data-connection.agents': 'done',
      'data-connection.sources': 'done',
      'data-connection.batch-sync': 'done',
      'data-connection.streaming-sync': 'done',
      'data-connection.exports': 'done',
      'ontology-object-backend.object-indexing': 'risk'
    }));
  });
  await page.reload();
  await page.waitForLoadState('networkidle');
  const result = await page.evaluate(() => ({
    connectivity: document.querySelector('.di-report-node.status-done h3')?.textContent.trim(),
    riskNodes: [...document.querySelectorAll('.di-report-node.status-risk h3')].map((item) => item.textContent.trim()),
    stats: [...document.querySelectorAll('.di-map-stat')].map((item) => item.textContent.trim())
  }));
  console.log(JSON.stringify(result, null, 2));
  await browser.close();
})();
NODE
```

Expected:

- `connectivity` is `Connectivity`.
- `riskNodes` includes `Ontology`.
- `stats` includes a risk count greater than zero.

- [ ] **Step 4: Verify presentation mode hides editing affordances**

Run:

```bash
NODE_PATH=/Users/huyongqiang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules \
  /Users/huyongqiang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node - <<'NODE'
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
  await page.goto('file://' + process.cwd() + '/deliverables/pages/data-integration-capability-map.html');
  await page.waitForLoadState('networkidle');
  await page.click('#di-toggle-presentation');
  const result = await page.evaluate(() => ({
    bodyMode: document.body.classList.contains('di-map-presentation-mode'),
    toolbarDisplay: getComputedStyle(document.querySelector('.di-map-report-toolbar')).display,
    appendixDisplay: getComputedStyle(document.querySelector('.di-map-appendix')).display
  }));
  console.log(JSON.stringify(result, null, 2));
  await browser.close();
})();
NODE
```

Expected:

```json
{
  "bodyMode": true,
  "toolbarDisplay": "none",
  "appendixDisplay": "none"
}
```

- [ ] **Step 5: Capture desktop and mobile screenshots for visual inspection**

Run:

```bash
NODE_PATH=/Users/huyongqiang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules \
  /Users/huyongqiang/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node - <<'NODE'
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });
  for (const [name, viewport] of Object.entries({ desktop: { width: 1440, height: 1000 }, mobile: { width: 390, height: 1000 } })) {
    const page = await browser.newPage({ viewport });
    await page.goto('file://' + process.cwd() + '/deliverables/pages/data-integration-capability-map.html');
    await page.waitForLoadState('networkidle');
    await page.screenshot({ path: `/tmp/di-war-room-${name}.png`, fullPage: false });
    await page.close();
  }
  await browser.close();
  console.log('/tmp/di-war-room-desktop.png');
  console.log('/tmp/di-war-room-mobile.png');
})();
NODE
```

Expected: both screenshots are created. Inspect them with the local image viewer if any layout overlap is suspected.

- [ ] **Step 6: Run final git status**

Run:

```bash
git status --short --branch
```

Expected: either clean except unrelated `.idea/`, or only intended files modified.

### Task 6: Final Commit

**Files:**
- Modify: `deliverables/pages/data-integration-capability-map.html`
- Modify: `deliverables/styles.css`

- [ ] **Step 1: Review final diff**

Run:

```bash
git diff -- deliverables/pages/data-integration-capability-map.html deliverables/styles.css
```

Expected: diff only contains the executive war-room page structure, report-node JavaScript, and scoped `.di-*` styles.

- [ ] **Step 2: Commit final verification adjustments when files changed**

Run:

```bash
git diff --quiet -- deliverables/pages/data-integration-capability-map.html deliverables/styles.css || \
  (git add deliverables/pages/data-integration-capability-map.html deliverables/styles.css && git commit -m "fix: polish executive war room report page")
```

Expected: if there are no final adjustments, the command exits without a commit; if verification produced final CSS or JavaScript fixes, the command creates this commit.

## Final Verification Checklist

- [ ] `node` inline script syntax check prints `inline script syntax ok`.
- [ ] Playwright DOM verification finds six report nodes.
- [ ] Status changes alter executive metrics and report-node styles.
- [ ] Presentation mode hides nav, toolbar, appendix, and status buttons.
- [ ] Desktop screenshot shows headline, metrics, Palantir object chain, and insights without overlap.
- [ ] Mobile screenshot stacks content without clipped text.
- [ ] `git status --short --branch` shows only unrelated `.idea/` if it remains untracked.
