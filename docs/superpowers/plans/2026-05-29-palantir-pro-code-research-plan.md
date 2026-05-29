# Palantir Pro-Code Research Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a traceable research artifact and human-readable HTML page explaining where Palantir's pro-code capability is strong, how it is implemented, and what can be borrowed.

**Architecture:** Keep raw research in `docs/raw`, synthesis in `docs/synthesis`, and user-facing presentation in `deliverables/pages`. Use confidence labels requested by the user: 【事实】 for officially verified/currently checked facts, 【推断】 for reasoned conclusions from facts, and 【猜测】 for low-evidence hypotheses.

**Tech Stack:** Markdown research documents, static HTML/CSS site, shell verification script.

---

### Task 1: Research Evidence Baseline

**Files:**
- Create: `docs/raw/21-pro-code-capability-deep-dive.md`

- [x] **Step 1: Collect official sources**

Use Palantir official docs for Code Repositories, Python transforms, Java transforms, SQL transforms, incremental transforms, Pipeline Builder, export pipeline code, scheduling, repository upgrades, unit tests, data expectations, and compute engines.

- [x] **Step 2: Define confidence labels**

Document the labels exactly:
- 【事实】: official/currently verified by this research pass.
- 【推断】: derived from multiple verified facts or existing repository analysis.
- 【猜测】: plausible but not directly verified.

### Task 2: Raw Research Document

**Files:**
- Create: `docs/raw/21-pro-code-capability-deep-dive.md`

- [x] **Step 1: Write capability taxonomy**

Cover development entry points, transform DSL, compute/runtime model, incrementality, quality/testing, governance, low-code interop, and platform lock-in.

- [x] **Step 2: Write conclusion matrix**

Each important conclusion must include one of the requested confidence labels.

### Task 3: Synthesis Document

**Files:**
- Create: `docs/synthesis/palantir-pro-code-capability-research.md`

- [x] **Step 1: Condense into decision-ready form**

Organize around three user questions: where it is strong, how it works, and what to borrow.

- [x] **Step 2: Add borrowing roadmap**

Split recommendations into platform contract, execution/runtime, governance, and product experience.

### Task 4: HTML Delivery

**Files:**
- Create: `deliverables/pages/pro-code-capability.html`
- Modify: `deliverables/index.html`
- Modify: `deliverables/styles.css`
- Modify: `scripts/verify-summary-site.sh`

- [x] **Step 1: Add standalone HTML page**

Use the existing static site style and classes, with a readable structure and source links.

- [x] **Step 2: Add homepage entry**

Link the new page from the existing "Dive Deeper" section.

- [x] **Step 3: Extend verification**

Add the new page to required files and add content checks for the confidence labels.

### Task 5: Verification

**Files:**
- Run: `bash scripts/verify-summary-site.sh`

- [ ] **Step 1: Run site verification**

Expected: `Summary site verification passed.`
