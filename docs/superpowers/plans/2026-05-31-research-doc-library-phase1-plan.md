# Research Doc Library Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first operational layer of the research document library: global entry page, catalog metadata, topic indexes, and local reference validation.

**Architecture:** Keep existing `docs/raw` and `docs/synthesis` paths stable. Add navigation and metadata beside them: `docs/index.md` for human entry, `docs/catalog.yml` for machine-readable inventory, `docs/topics/*.md` for cross-topic indexes, and `scripts/verify-doc-library.sh` for local validation. Phase 1 does not create the long-form `docs/library` reading layer; it only prepares the infrastructure that makes Phase 2 safe.

**Tech Stack:** Markdown, YAML, POSIX shell, Ruby standard-library YAML parser, GitLab issues.

---

## Summary & Insights

1. Phase 1 is an information architecture change, not a content migration; the safest implementation is additive.
2. `docs/catalog.yml` is the coordination point: if it is complete and validated, topic pages and future library chapters can be generated or audited consistently.
3. Topic pages should expose current conclusions and evidence links, not duplicate raw or synthesis content.
4. Local validation must start lightweight: verify YAML, file existence, catalog coverage, and repository-local Markdown links before introducing heavier documentation tooling.
5. Phase 1 completion should remain gated by expert review before any Phase 2 reading-layer work begins.

## Issue Map

| Issue | Role | Deliverable |
| --- | --- | --- |
| [#42](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/42) | Epic | Overall document-library reorganization tracking |
| [#44](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/44) | Story | `docs/index.md` global entry and reading paths |
| [#45](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/45) | Story | `docs/catalog.yml` metadata inventory |
| [#46](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/46) | Story | Initial `docs/topics/*.md` topic indexes |
| [#47](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/47) | Story | Local reference validation |
| [#48](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/48) | Story | Phase 1 integration review and expert-panel handoff |

## File Structure

Create:

- `docs/index.md`: human-facing documentation-library homepage.
- `docs/catalog.yml`: machine-readable document inventory.
- `docs/topics/dataset.md`: Dataset, storage, transaction, view, and no-`dt` analysis index.
- `docs/topics/pipeline.md`: Pipeline expression, transform, code, execution, and interop index.
- `docs/topics/scheduling.md`: Schedule, trigger, dependency, SLA, and execution-control index.
- `docs/topics/lineage-and-catalog.md`: lineage, metadata, branch, version, and catalog index.
- `docs/topics/security-and-marking.md`: permission, Marking, policy, propagation, and audit index.
- `docs/topics/ontology.md`: Ontology, object model, relationship, action, and semantic layer index.
- `docs/topics/data-quality.md`: expectations, health checks, monitoring, and issue-loop index.
- `docs/topics/pro-code.md`: Code Repositories, runtime, CI/CD, SDK, and developer-experience index.
- `docs/topics/ai-fde.md`: AI FDE source, positioning, context, governance, architecture, and self-build index.
- `docs/topics/self-build-roadmap.md`: self-build capability map, migration risk, and roadmap index.
- `scripts/verify-doc-library.sh`: local validation command.

Do not move or rename:

- `docs/raw/*.md`
- `docs/synthesis/*.md`
- `docs/superpowers/plans/*.md`
- `docs/superpowers/specs/*.md`

## Catalog Vocabulary

Use these exact controlled values:

```yaml
type:
  - raw
  - synthesis
  - topic
  - plan
  - spec
  - index
status:
  - intake
  - draft
  - reviewed
  - canonical
  - superseded
  - archived
source_layer:
  - raw
  - synthesis
  - topic
  - planning
  - specification
  - navigation
confidence:
  - low
  - medium
  - high
evidence_strength:
  - weak
  - medium
  - strong
```

Each catalog document entry must contain:

```yaml
- id: stable-slug
  path: docs/example.md
  title: Human Readable Title
  type: synthesis
  status: reviewed
  topics:
    - dataset
  source_layer: synthesis
  issue_refs:
    - 42
  source_refs: []
  related_docs: []
  canonical: false
  supersedes: []
  superseded_by: null
  created: 2026-05-31
  updated: 2026-05-31
  last_reviewed: 2026-05-31
  confidence: medium
  evidence_strength: medium
  owner: codex
  reviewers: []
```

## Task 1: Global Entry Page

**Issue:** #44
**Files:**

- Create: `docs/index.md`
- Read: `docs/superpowers/specs/2026-05-31-research-doc-library-design.md`
- Read: `docs/synthesis/*.md`

- [ ] **Step 1: Reconfirm current synthesis files**

Run:

```bash
find docs/synthesis -maxdepth 1 -type f -name '*.md' | sort
```

Expected output includes:

```text
docs/synthesis/dataset-permission-marking-architecture-summary.md
docs/synthesis/dataworks-vs-palantir-integration.md
docs/synthesis/foundry-schedule-module-deep-dive.md
docs/synthesis/operator-platform-design.md
docs/synthesis/palantir-ai-fde-research.md
docs/synthesis/palantir-data-quality-module-research.md
docs/synthesis/palantir-dataset-no-dt-partition-impact.md
docs/synthesis/palantir-dataset-vs-data-warehouse.md
docs/synthesis/palantir-pipeline-deep-dive.md
docs/synthesis/palantir-pro-code-capability-research.md
```

- [ ] **Step 2: Create `docs/index.md`**

Use this structure and keep links repository-relative:

```markdown
# Palantir Research 文档库

## 摘要与洞察

1. 本文档库采用证据层、结论层、主题索引层和阅读层分离的组织方式。
2. `docs/raw` 与 `docs/synthesis` 是稳定引用坐标，Phase 1 不移动、不重命名。
3. `docs/catalog.yml` 是跨文档追踪的主索引，主题页和后续阅读层都应以 catalog 为准。
4. 新读者应先阅读主题索引，再进入 synthesis 结论文档，最后按需追溯 raw 证据。

## 文档层级

| 层级 | 路径 | 用途 |
| --- | --- | --- |
| 全局入口 | `docs/index.md` | 解释结构、入口和阅读路径 |
| 元数据 | `docs/catalog.yml` | 维护文档、主题、issue、证据和 canonical 状态 |
| 主题索引 | `docs/topics/*.md` | 聚合主题结论、证据、issue 和开放问题 |
| 结论层 | `docs/synthesis/*.md` | 保存经过整理的分析结论 |
| 证据层 | `docs/raw/*.md` | 保存来源、机制观察和原始分析记录 |
| 计划与规格 | `docs/superpowers/**` | 保存计划、设计和执行过程 |

## 推荐阅读路径

| 目标 | 起点 | 结论文档 |
| --- | --- | --- |
| 理解 Dataset 与传统数仓差异 | `docs/topics/dataset.md` | `docs/synthesis/palantir-dataset-vs-data-warehouse.md` |
| 理解无 `dt` 分区影响 | `docs/topics/dataset.md` | `docs/synthesis/palantir-dataset-no-dt-partition-impact.md` |
| 理解 Pipeline 能力 | `docs/topics/pipeline.md` | `docs/synthesis/palantir-pipeline-deep-dive.md` |
| 理解调度模块 | `docs/topics/scheduling.md` | `docs/synthesis/foundry-schedule-module-deep-dive.md` |
| 理解权限与 Marking | `docs/topics/security-and-marking.md` | `docs/synthesis/dataset-permission-marking-architecture-summary.md` |
| 理解 Pro-Code 能力 | `docs/topics/pro-code.md` | `docs/synthesis/palantir-pro-code-capability-research.md` |
| 理解 AI FDE | `docs/topics/ai-fde.md` | `docs/synthesis/palantir-ai-fde-research.md` |
| 理解数据质量模块 | `docs/topics/data-quality.md` | `docs/synthesis/palantir-data-quality-module-research.md` |
| 理解自研路线 | `docs/topics/self-build-roadmap.md` | `docs/synthesis/operator-platform-design.md` |

## 当前设计基线

- 文档库组织设计：`docs/superpowers/specs/2026-05-31-research-doc-library-design.md`
- Phase 1 实施计划：`docs/superpowers/plans/2026-05-31-research-doc-library-phase1-plan.md`
- 跟踪 Epic：#42

## 维护规则

1. 所有重要研究结论必须落库，不能只停留在聊天记录中。
2. 所有研究输出必须在开头提供 3 到 5 条摘要或洞察。
3. 新增文档后必须更新 `docs/catalog.yml` 和相关 `docs/topics` 页面。
4. 提交前运行 `bash scripts/verify-doc-library.sh` 与 `git diff --check`。
```

- [ ] **Step 3: Verify local links after topic pages exist**

Run after Task 3 and Task 4:

```bash
bash scripts/verify-doc-library.sh
```

Expected: exit code 0.

- [ ] **Step 4: Commit Task 1 only if implemented independently**

```bash
git add docs/index.md
git commit -m "docs(library): add research docs index" -m "Refs #44"
```

## Task 2: Catalog Metadata

**Issue:** #45
**Files:**

- Create: `docs/catalog.yml`
- Read: all tracked Markdown files under `docs/raw`, `docs/synthesis`, and `docs/superpowers`

- [ ] **Step 1: Enumerate tracked Markdown files**

Run:

```bash
git ls-files 'docs/**/*.md' | sort
```

Expected: output includes all current tracked Markdown files, including data-quality files added in commit `e239836`.

- [ ] **Step 2: Create `docs/catalog.yml` skeleton**

Use this top-level shape:

```yaml
version: 1
updated: 2026-05-31
documents:
```

- [ ] **Step 3: Add one document entry per tracked Markdown file**

For each file from Step 1:

- `path`: exact file path.
- `id`: filename without extension, lower-case, keeping existing hyphenated slug.
- `title`: first Markdown H1 without the leading `#`; if a file has no H1, use the filename stem in title case.
- `type`: `raw` for `docs/raw`, `synthesis` for `docs/synthesis`, `plan` for `docs/superpowers/plans`, `spec` for `docs/superpowers/specs`, `topic` for `docs/topics`, `index` for `docs/index.md`.
- `status`: `canonical` for current final synthesis documents, `reviewed` for raw evidence used by canonical synthesis, `draft` for plans and specs, `intake` for newly added evidence that has not been expert reviewed.
- `topics`: infer from filename and synthesis theme using the topic vocabulary in the design spec.
- `source_layer`: map from directory using the Catalog Vocabulary section.
- `issue_refs`: include known issue numbers from plans and commit history; include #42 for Phase 1 files.
- `source_refs`: use raw evidence paths for synthesis documents when known.
- `related_docs`: use synthesis paths or topic paths that support navigation.
- `canonical`: `true` only for current synthesis conclusions selected as source-of-truth for a topic.
- `supersedes`: empty list unless a document explicitly replaces another document.
- `superseded_by`: null unless a replacement is explicit.
- `created`, `updated`, `last_reviewed`: use the best known date from the document title, plan date, or commit date.
- `confidence`: `medium` unless a document has strong source coverage and expert review, then `high`.
- `evidence_strength`: `medium` for most files, `strong` for synthesis supported by multiple raw files.
- `owner`: `codex`.
- `reviewers`: include `expert-panel` when expert review is recorded.

- [ ] **Step 4: Validate YAML syntax**

Run:

```bash
ruby -e 'require "yaml"; data = YAML.load_file("docs/catalog.yml"); abort("missing documents") unless data.is_a?(Hash) && data["documents"].is_a?(Array); puts data["documents"].length'
```

Expected: prints a positive integer and exits 0.

- [ ] **Step 5: Commit Task 2 only if implemented independently**

```bash
git add docs/catalog.yml
git commit -m "docs(library): add document catalog metadata" -m "Refs #45"
```

## Task 3: Topic Indexes

**Issue:** #46
**Files:**

- Create: `docs/topics/dataset.md`
- Create: `docs/topics/pipeline.md`
- Create: `docs/topics/scheduling.md`
- Create: `docs/topics/lineage-and-catalog.md`
- Create: `docs/topics/security-and-marking.md`
- Create: `docs/topics/ontology.md`
- Create: `docs/topics/data-quality.md`
- Create: `docs/topics/pro-code.md`
- Create: `docs/topics/ai-fde.md`
- Create: `docs/topics/self-build-roadmap.md`
- Modify: `docs/catalog.yml`

- [ ] **Step 1: Create `docs/topics` directory**

```bash
mkdir -p docs/topics
```

- [ ] **Step 2: Use this topic page contract for every file**

Each topic page must use this section order:

```markdown
# Topic Title

## 摘要与洞察

1. 第一条结论必须来自本主题已有 synthesis 或 raw 证据。
2. 第二条结论必须说明该主题对自研平台设计的影响。
3. 第三条结论必须标注当前仍需后续研究或专家复核的边界。

## Canonical Documents

| 文档 | 用途 |
| --- | --- |

## Supporting Evidence

| 证据 | 用途 |
| --- | --- |

## Related Issues

| Issue | 用途 |
| --- | --- |

## Open Questions

- 本主题仍缺少哪类证据，或哪项判断需要在 Phase 2 前复核。
```

Replace the three summary bullets and open question with concrete statements from the existing synthesis and raw documents before committing.

- [ ] **Step 3: Create `dataset.md`**

Minimum links:

```text
docs/synthesis/palantir-dataset-vs-data-warehouse.md
docs/synthesis/palantir-dataset-no-dt-partition-impact.md
docs/synthesis/dataset-permission-marking-architecture-summary.md
docs/raw/39-foundry-dataset-transaction-view-evidence.md
docs/raw/40-traditional-dt-partition-production-semantics.md
docs/raw/41-lakehouse-layout-partition-cost-model.md
docs/raw/42-governance-lineage-audit-contracts.md
docs/raw/43-migration-risk-dual-coordinate-patterns.md
```

- [ ] **Step 4: Create `pipeline.md`**

Minimum links:

```text
docs/synthesis/palantir-pipeline-deep-dive.md
docs/raw/01-pipeline-expression-dsl.md
docs/raw/02-execution-engine-spark.md
docs/raw/14-transform-operator-library.md
docs/raw/25-transform-contract-dag.md
docs/raw/28-pipeline-builder-pro-code-interop.md
```

- [ ] **Step 5: Create `scheduling.md`**

Minimum links:

```text
docs/synthesis/foundry-schedule-module-deep-dive.md
docs/raw/15-job-execution-guarantee.md
docs/raw/27-incremental-scheduling-transaction.md
docs/raw/38-foundry-schedule-module-research-plan.md
```

- [ ] **Step 6: Create `lineage-and-catalog.md`**

Minimum links:

```text
docs/raw/04-lineage-ontology-integration.md
docs/raw/29-lineage-branch-version-pipeline-sync.md
docs/raw/42-governance-lineage-audit-contracts.md
```

- [ ] **Step 7: Create `security-and-marking.md`**

Minimum links:

```text
docs/synthesis/dataset-permission-marking-architecture-summary.md
docs/raw/06-security-and-permissions.md
docs/raw/11-marking-mechanism-deep-dive.md
docs/raw/12-dataset-marking-implementation.md
docs/raw/13-marking-advanced-deep-dive.md
docs/raw/30-dataset-permission-marking-architecture.md
```

- [ ] **Step 8: Create `ontology.md`**

Minimum links:

```text
docs/raw/04-lineage-ontology-integration.md
docs/superpowers/specs/2026-04-15-ontology-data-model-research.md
```

- [ ] **Step 9: Create `data-quality.md`**

Minimum links:

```text
docs/synthesis/palantir-data-quality-module-research.md
docs/raw/44-data-quality-source-map.md
docs/raw/45-data-expectations-build-gates.md
docs/raw/46-data-health-health-checks.md
docs/raw/47-monitoring-views-alert-issue-loop.md
docs/raw/48-data-quality-governance-lifecycle.md
docs/raw/49-data-quality-external-notification-security.md
```

- [ ] **Step 10: Create `pro-code.md`**

Minimum links:

```text
docs/synthesis/palantir-pro-code-capability-research.md
docs/raw/21-pro-code-capability-deep-dive.md
docs/raw/22-pro-code-source-map.md
docs/raw/23-code-repositories-engineering-entry.md
docs/raw/24-pro-code-runtime-compute-engines.md
docs/raw/26-pro-code-governance-quality-observability.md
```

- [ ] **Step 11: Create `ai-fde.md`**

Minimum links:

```text
docs/synthesis/palantir-ai-fde-research.md
docs/raw/32-ai-fde-source-map.md
docs/raw/33-ai-fde-product-positioning.md
docs/raw/34-ai-fde-context-tools-skills.md
docs/raw/35-ai-fde-governance-branching.md
docs/raw/36-ai-fde-architecture-design.md
docs/raw/37-ai-fde-self-build-implementation-blueprint.md
```

- [ ] **Step 12: Create `self-build-roadmap.md`**

Minimum links:

```text
docs/synthesis/operator-platform-design.md
docs/synthesis/dataworks-vs-palantir-integration.md
docs/raw/10-opensource-alternative-stack.md
docs/raw/20-stream-self-build-architecture.md
docs/raw/37-ai-fde-self-build-implementation-blueprint.md
docs/raw/43-migration-risk-dual-coordinate-patterns.md
```

- [ ] **Step 13: Add topic pages to `docs/catalog.yml`**

Each topic page entry:

```yaml
  type: topic
  status: draft
  source_layer: topic
  issue_refs:
    - 42
    - 46
  canonical: false
  confidence: medium
  evidence_strength: medium
  owner: codex
  reviewers: []
```

- [ ] **Step 14: Commit Task 3 only if implemented independently**

```bash
git add docs/topics docs/catalog.yml
git commit -m "docs(library): add initial topic indexes" -m "Refs #46"
```

## Task 4: Reference Validation

**Issue:** #47
**Files:**

- Create: `scripts/verify-doc-library.sh`
- Read: `docs/catalog.yml`
- Read: Markdown files under `docs`

- [ ] **Step 1: Create validation script**

Create `scripts/verify-doc-library.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

ruby <<'RUBY'
require "yaml"
require "set"

catalog_path = "docs/catalog.yml"
abort("missing #{catalog_path}") unless File.exist?(catalog_path)

catalog = YAML.load_file(catalog_path)
abort("catalog must be a mapping") unless catalog.is_a?(Hash)
documents = catalog["documents"]
abort("catalog documents must be a list") unless documents.is_a?(Array)

required = %w[
  id path title type status topics source_layer issue_refs source_refs
  related_docs canonical supersedes superseded_by created updated
  last_reviewed confidence evidence_strength owner reviewers
]

valid_types = Set.new(%w[raw synthesis topic plan spec index])
valid_statuses = Set.new(%w[intake draft reviewed canonical superseded archived])
valid_layers = Set.new(%w[raw synthesis topic planning specification navigation])
valid_confidence = Set.new(%w[low medium high])
valid_evidence = Set.new(%w[weak medium strong])

paths = Set.new
ids = Set.new

documents.each_with_index do |doc, index|
  abort("document #{index} must be a mapping") unless doc.is_a?(Hash)
  missing = required.reject { |key| doc.key?(key) }
  abort("#{doc["id"] || "document #{index}"} missing fields: #{missing.join(", ")}") unless missing.empty?

  id = doc["id"]
  path = doc["path"]
  abort("document #{index} id must be a non-empty string") unless id.is_a?(String) && !id.empty?
  abort("#{id} duplicated id") if ids.include?(id)
  ids.add(id)

  abort("#{id} path must be a non-empty string") unless path.is_a?(String) && !path.empty?
  abort("#{id} duplicated path #{path}") if paths.include?(path)
  paths.add(path)
  abort("#{id} missing local file #{path}") unless File.exist?(path)

  abort("#{id} invalid type #{doc["type"]}") unless valid_types.include?(doc["type"])
  abort("#{id} invalid status #{doc["status"]}") unless valid_statuses.include?(doc["status"])
  abort("#{id} invalid source_layer #{doc["source_layer"]}") unless valid_layers.include?(doc["source_layer"])
  abort("#{id} topics must be a list") unless doc["topics"].is_a?(Array)
  abort("#{id} issue_refs must be a list") unless doc["issue_refs"].is_a?(Array)
  abort("#{id} source_refs must be a list") unless doc["source_refs"].is_a?(Array)
  abort("#{id} related_docs must be a list") unless doc["related_docs"].is_a?(Array)
  abort("#{id} supersedes must be a list") unless doc["supersedes"].is_a?(Array)
  abort("#{id} canonical must be boolean") unless doc["canonical"] == true || doc["canonical"] == false
  abort("#{id} invalid confidence #{doc["confidence"]}") unless valid_confidence.include?(doc["confidence"])
  abort("#{id} invalid evidence_strength #{doc["evidence_strength"]}") unless valid_evidence.include?(doc["evidence_strength"])

  (doc["source_refs"] + doc["related_docs"] + doc["supersedes"]).each do |ref|
    abort("#{id} reference must be a string: #{ref.inspect}") unless ref.is_a?(String)
    abort("#{id} references missing path #{ref}") unless File.exist?(ref)
  end
  superseded_by = doc["superseded_by"]
  abort("#{id} superseded_by must be null or string") unless superseded_by.nil? || superseded_by.is_a?(String)
  abort("#{id} superseded_by missing path #{superseded_by}") if superseded_by && !File.exist?(superseded_by)
end

tracked_core = `git ls-files 'docs/raw/*.md' 'docs/synthesis/*.md'`.split("\n")
missing_catalog = tracked_core.reject { |path| paths.include?(path) }
abort("catalog missing tracked core docs: #{missing_catalog.join(", ")}") unless missing_catalog.empty?

markdown_files = `git ls-files 'docs/**/*.md'`.split("\n")
markdown_files.each do |file|
  content = File.read(file)
  content.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each do |target|
    next if target.start_with?("http://", "https://", "mailto:", "#")
    next if target.start_with?("gitlabee.chehejia.com")
    clean = target.split("#", 2).first
    next if clean.empty?
    resolved = File.expand_path(clean, File.dirname(file))
    abort("#{file} links to missing local path #{target}") unless File.exist?(resolved)
  end
end

puts "Verified #{documents.length} catalog entries and #{markdown_files.length} markdown files."
RUBY
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x scripts/verify-doc-library.sh
```

- [ ] **Step 3: Run validation**

```bash
bash scripts/verify-doc-library.sh
```

Expected output:

```text
Verified N catalog entries and M markdown files.
```

The exact values of N and M depend on files added by Tasks 1 through 3.

- [ ] **Step 4: Run Markdown whitespace check**

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 5: Commit Task 4 only if implemented independently**

```bash
git add scripts/verify-doc-library.sh
git commit -m "docs(library): add document library validation" -m "Refs #47"
```

## Task 5: Integration Review

**Issue:** #48
**Files:**

- Modify: `docs/superpowers/plans/2026-05-31-research-doc-library-phase1-plan.md`
- Read: `docs/index.md`
- Read: `docs/catalog.yml`
- Read: `docs/topics/*.md`
- Read: `scripts/verify-doc-library.sh`

- [ ] **Step 1: Run final validation commands**

```bash
bash scripts/verify-doc-library.sh
git diff --check
rg -n "TO""DO|T""BD|待""补|FIX""ME" docs/index.md docs/catalog.yml docs/topics scripts/verify-doc-library.sh
```

Expected:

- `bash scripts/verify-doc-library.sh` exits 0.
- `git diff --check` exits 0.
- `rg` exits 1 because no placeholder terms are found.

- [ ] **Step 2: Confirm no forbidden movement occurred**

Run:

```bash
git status --short
git diff --name-status HEAD
```

Expected:

- No `R` rename records for `docs/raw/*.md` or `docs/synthesis/*.md`.
- No `D` deletion records for `docs/raw/*.md` or `docs/synthesis/*.md`.

- [ ] **Step 3: Record expert-panel review**

Add an issue #42 comment with:

```markdown
Phase 1 expert review summary:

1. Information architecture: index, catalog and topics provide separate human and machine navigation paths.
2. Traceability: catalog links documents to topics, issues, source references and canonical status.
3. Stability: raw and synthesis paths were not moved or renamed.
4. Maintenance: validation checks YAML shape, local paths, catalog coverage and local Markdown links.
5. Next decision: start Phase 2 library reading layer only after user approval.
```

- [ ] **Step 4: Close completed Phase 1 story issues**

Close #44 through #48 only after their acceptance criteria are met and referenced in the final review comment.

- [ ] **Step 5: Commit integrated Phase 1 package**

If Tasks 1 through 4 were implemented in one batch, commit all Phase 1 files together:

```bash
git add docs/index.md docs/catalog.yml docs/topics scripts/verify-doc-library.sh docs/superpowers/plans/2026-05-31-research-doc-library-phase1-plan.md
git commit -m "docs(library): add phase 1 document library structure" -m "Refs #42" -m "Refs #44" -m "Refs #45" -m "Refs #46" -m "Refs #47" -m "Refs #48"
```

## Self-Review Checklist

- Spec coverage: #44 maps to global entry, #45 maps to catalog, #46 maps to topics, #47 maps to validation, #48 maps to integration review.
- Migration safety: no task moves, renames, deletes, or rewrites existing `docs/raw` and `docs/synthesis` files.
- Research output rule: all new Markdown documents start with 3 to 5 summary points or insights.
- Verification: Phase 1 has explicit commands for YAML validation, local path validation, Markdown link validation, whitespace checking, and placeholder scanning.
- Handoff: Phase 2 `docs/library` work remains outside this plan and requires user approval after #48.
