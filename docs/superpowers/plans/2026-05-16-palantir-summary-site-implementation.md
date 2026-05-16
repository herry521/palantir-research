# Palantir Summary Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an offline static HTML site with one management summary page, one R&D overview page, and five technical detail pages based on the approved Palantir research design spec.

**Architecture:** Use a plain static site under `deliverables/` with shared `styles.css` and `app.js`, plus copied diagram assets. Keep the management homepage visually distinct with a deep-green editorial style, while detail pages share a lighter reading layout and consistent section system. Add a lightweight Node-free verification script that checks required files, links, and key content markers.

**Tech Stack:** HTML5, CSS3, vanilla JavaScript, local PNG assets, Bash verification script

---

## File Structure

**Create**
- `deliverables/index.html`
- `deliverables/styles.css`
- `deliverables/app.js`
- `deliverables/assets/diagrams/` (copied PNG assets)
- `deliverables/pages/overview.html`
- `deliverables/pages/expression-and-operators.html`
- `deliverables/pages/execution-and-incremental.html`
- `deliverables/pages/streaming-architecture.html`
- `deliverables/pages/lineage-ontology-governance.html`
- `deliverables/pages/engineering-and-ecosystem.html`
- `scripts/verify-summary-site.sh`

**Reference**
- `docs/superpowers/specs/2026-05-16-palantir-summary-site-design.md`
- `docs/synthesis/palantir-pipeline-deep-dive.md`
- `docs/synthesis/operator-platform-design.md`
- `docs/raw/*.md`
- `diagrams/*.png`

## Task 1: Add Verification Guardrails First

**Files:**
- Create: `scripts/verify-summary-site.sh`

- [ ] **Step 1: Write the failing verification script**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="deliverables"
required_files=(
  "$ROOT/index.html"
  "$ROOT/styles.css"
  "$ROOT/app.js"
  "$ROOT/pages/overview.html"
  "$ROOT/pages/expression-and-operators.html"
  "$ROOT/pages/execution-and-incremental.html"
  "$ROOT/pages/streaming-architecture.html"
  "$ROOT/pages/lineage-ontology-governance.html"
  "$ROOT/pages/engineering-and-ecosystem.html"
)

for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || { echo "Missing file: $file"; exit 1; }
done
```

- [ ] **Step 2: Run script to verify it fails**

Run: `bash scripts/verify-summary-site.sh`
Expected: FAIL with `Missing file: deliverables/index.html`

- [ ] **Step 3: Expand the verification script with content and link checks**

```bash
check_contains() {
  local file="$1"
  local pattern="$2"
  grep -q "$pattern" "$file" || { echo "Missing pattern '$pattern' in $file"; exit 1; }
}

check_contains "$ROOT/index.html" "Palantir"
check_contains "$ROOT/index.html" "三个管理判断"
check_contains "$ROOT/pages/overview.html" "技术总览"
check_contains "$ROOT/pages/expression-and-operators.html" "表达层"
check_contains "$ROOT/pages/execution-and-incremental.html" "增量"
check_contains "$ROOT/pages/streaming-architecture.html" "流式"
check_contains "$ROOT/pages/lineage-ontology-governance.html" "Ontology"
check_contains "$ROOT/pages/engineering-and-ecosystem.html" "工程化"

grep -R "href=\"pages/overview.html\"" "$ROOT/index.html" >/dev/null || {
  echo "Homepage must link to overview page"; exit 1;
}
```

- [ ] **Step 4: Keep script executable**

Run: `chmod +x scripts/verify-summary-site.sh`
Expected: command succeeds silently

## Task 2: Build Site Scaffold And Shared System

**Files:**
- Create: `deliverables/index.html`
- Create: `deliverables/styles.css`
- Create: `deliverables/app.js`

- [ ] **Step 1: Create the shared HTML shell**

Include:
- semantic header/nav structure
- shared footer
- page wrapper classes used by all pages
- local relative links only

- [ ] **Step 2: Create the visual system in CSS**

Include:
- deep-green homepage theme tokens
- light detail-page theme tokens
- hero, summary card, comparison grid, timeline, source list, section nav, and image frame components
- mobile breakpoints for stacked layout

- [ ] **Step 3: Add minimal shared JavaScript**

Include:
- current-nav highlighting based on pathname/hash
- optional sticky section nav enhancement
- no external dependencies

- [ ] **Step 4: Run verification and confirm it still fails for missing pages**

Run: `bash scripts/verify-summary-site.sh`
Expected: FAIL for the first missing page under `deliverables/pages/`

## Task 3: Implement Management Homepage And R&D Overview

**Files:**
- Modify: `deliverables/index.html`
- Create: `deliverables/pages/overview.html`
- Modify: `deliverables/styles.css`
- Modify: `deliverables/app.js`

- [ ] **Step 1: Implement the homepage**

Homepage must include:
- one-sentence conclusion hero
- three management judgment cards
- four-dimension capability gap section
- three-stage recommendation roadmap
- entry section linking into R&D pages

- [ ] **Step 2: Implement the overview page**

Overview must include:
- technical map intro
- topic cards for all five technical pages
- mapping back to homepage conclusions
- quick links into source-heavy topics

- [ ] **Step 3: Run verification and confirm it fails on missing topic pages**

Run: `bash scripts/verify-summary-site.sh`
Expected: FAIL for the first missing topic page

## Task 4: Implement Topic Pages

**Files:**
- Create: `deliverables/pages/expression-and-operators.html`
- Create: `deliverables/pages/execution-and-incremental.html`
- Create: `deliverables/pages/streaming-architecture.html`
- Create: `deliverables/pages/lineage-ontology-governance.html`
- Create: `deliverables/pages/engineering-and-ecosystem.html`

- [ ] **Step 1: Implement a shared topic-page pattern**

Each page must contain:
- topic hero
- 2 to 4 conclusion cards
- key mechanism section
- implications-for-us section
- related sources section

- [ ] **Step 2: Write the five topic pages with distinct content**

Use the approved source mapping:
- expression/operators
- execution/incremental
- streaming
- lineage/ontology/governance
- engineering/ecosystem

- [ ] **Step 3: Run verification and confirm all files now pass structural checks**

Run: `bash scripts/verify-summary-site.sh`
Expected: PASS with a success message

## Task 5: Wire Assets, Polish, And Final Review

**Files:**
- Modify: `deliverables/*.html`
- Modify: `deliverables/pages/*.html`
- Modify: `deliverables/styles.css`
- Modify: `scripts/verify-summary-site.sh`

- [ ] **Step 1: Copy selected local diagram PNGs into deliverable assets**

Run:

```bash
mkdir -p deliverables/assets/diagrams
cp diagrams/platform-architecture.drawio.png deliverables/assets/diagrams/
cp diagrams/dataworks-architecture.drawio.png deliverables/assets/diagrams/
cp diagrams/ontology-backend-architecture.drawio.png deliverables/assets/diagrams/
cp diagrams/roadmap-q2-q3-timeline.drawio.png deliverables/assets/diagrams/
```

Expected: command succeeds silently

- [ ] **Step 2: Reference the copied assets in the most relevant pages**

Use:
- platform/dataworks diagrams in overview or execution pages
- ontology diagram in governance page
- roadmap diagram in homepage recommendation section if visually helpful

- [ ] **Step 3: Run final verification**

Run: `bash scripts/verify-summary-site.sh`
Expected: PASS

- [ ] **Step 4: Manual browser review**

Open:
- `deliverables/index.html`
- `deliverables/pages/overview.html`

Check:
- homepage visual hierarchy is strong
- detail pages remain readable
- mobile-width layout does not overflow
- all local links work

- [ ] **Step 5: Commit**

```bash
git add deliverables scripts/verify-summary-site.sh docs/superpowers/plans/2026-05-16-palantir-summary-site-implementation.md
git commit -m "feat: build palantir summary site"
```

## Self-Review

- Spec coverage:
  - homepage structure is covered by Task 3
  - overview + five detail pages are covered by Tasks 3 and 4
  - visual system and shared interaction are covered by Task 2
  - offline verification and local links are covered by Tasks 1 and 5
- Placeholder scan:
  - no `TODO`, `TBD`, or deferred implementation markers remain
- Type consistency:
  - all page filenames and verification targets align with the approved design spec
