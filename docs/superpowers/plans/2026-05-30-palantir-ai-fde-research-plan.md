# Palantir AI FDE Research Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a traceable research package explaining Palantir AI FDE from functional positioning, to architecture design, to a self-build implementation plan.

**Architecture:** Use GitLab issues as the coordination layer, one issue per independent research domain. Keep raw evidence in `docs/raw`, final synthesis in `docs/synthesis`, and this execution plan in `docs/superpowers/plans`; every conclusion must be traceable to a source URL or explicitly marked as an inference.

**Tech Stack:** Markdown research documents, GitLab issues, Palantir official documentation, optional static HTML delivery only after the synthesis is accepted.

---

## Coordination Issue Map

| Issue | Agent | Research Domain | Primary Output |
|---|---|---|---|
| [#20](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/20) | Coordinator | AI FDE research parent tracking | This plan plus final cross-issue status |
| [#22](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/22) | Agent A | Source map and terminology baseline | `docs/raw/32-ai-fde-source-map.md` |
| [#21](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/21) | Agent B | Functional positioning and product boundary | `docs/raw/33-ai-fde-product-positioning.md` |
| [#23](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/23) | Agent C | Interaction, context, modes, skills, tools | `docs/raw/34-ai-fde-context-tools-skills.md` |
| [#26](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/26) | Agent D | Security, governance, approvals, branching | `docs/raw/35-ai-fde-governance-branching.md` |
| [#25](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/25) | Agent E | Architecture design inference | `docs/raw/36-ai-fde-architecture-design.md` |
| [#24](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/24) | Agent F | Self-build implementation blueprint and PoC route | `docs/raw/37-ai-fde-self-build-implementation-blueprint.md` |
| [#27](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/27) | Agent G | Synthesis, evidence review, final delivery | `docs/synthesis/palantir-ai-fde-research.md` |

## Starting Evidence Baseline

The following facts are the initial shared baseline for all agents:

- 【事实】AI FDE is described by Palantir as an AI-powered forward deployed engineer: an interactive agent that operates Foundry through conversational commands and translates natural language into Foundry operations such as data transformations, code repository management, ontology work, and function editing. Source: <https://www.palantir.com/docs/foundry/ai-fde/overview>
- 【事实】AI FDE requires AIP to be enabled, and Palantir recommends Global Branching for ontology edits. Source: <https://www.palantir.com/docs/foundry/ai-fde/overview>
- 【事实】AI FDE uses a closed-loop operation model: analyze intent and context, choose Foundry operations, execute with native tools, observe results, and validate through previews or CI checks. Source: <https://www.palantir.com/docs/foundry/ai-fde/overview>
- 【事实】AI FDE exposes modes including data integration, data connection, ontology editing, functions editing, exploration, governance, machine learning, OSDK React, and platform Q&A. Source: <https://www.palantir.com/docs/foundry/ai-fde/modes-and-skills>
- 【事实】AI FDE context is explicitly user-controlled through added resources such as datasets, functions, branches, interfaces, action types, object types, documentation bundles, uploaded media, drag-and-drop links, and search tools. Source: <https://www.palantir.com/docs/foundry/ai-fde/navigation>
- 【事实】AI FDE acts under the current user's Foundry session, not a separate bot or service account; permission checks, audit logs, and model usage attribution apply to the user identity. Source: <https://www.palantir.com/docs/foundry/ai-fde/security-and-governance>
- 【事实】Mutating operations use tool approval, with conservative defaults, branch-aware approval behavior, and read-only operations as the low-risk category. Source: <https://www.palantir.com/docs/foundry/ai-fde/security-and-governance>
- 【事实】AIP architecture includes secure model access, observability, context engineering, Ontology, vector/compute/tool services, security governance, agent lifecycle, developer environments, package/release/deploy, and enterprise automation; Palantir positions AI FDE as a specialized enterprise automation agent operating on the same foundation as human users. Source: <https://www.palantir.com/docs/foundry/architecture-center/aip-architecture>

## Confidence Labels

Use these labels exactly in every raw document and synthesis:

- 【事实】: Directly supported by official Palantir documentation or a checked repository artifact in this workspace.
- 【推断】: Reasoned conclusion from multiple facts or from a fact combined with established platform behavior. The reasoning chain must be written down.
- 【猜测】: Plausible implementation detail or product interpretation that public documentation does not verify. It must be isolated from recommendations that require high confidence.

## Execution Waves

### Wave 0: Evidence Baseline

**Issue:** [#22](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/22)

- [ ] Create `docs/raw/32-ai-fde-source-map.md`.
- [ ] Catalog official sources by URL, source type, coverage area, confidence, and collection date `2026-05-30`.
- [ ] Define terminology boundaries for AI FDE, human FDE, AIP Assist, AIP Chatbot Studio, AIP Analyst, Palantir MCP, and external coding agents.
- [ ] Record evidence gaps that cannot be verified from public docs.
- [ ] Comment on #22 with the raw document path and the top five source URLs.

### Wave 1: Parallel Domain Research

These issues can run in parallel after this plan is available. Agents should not wait for each other, but they must reference Agent A's labels and terminology once #22 lands.

**Issue:** [#21](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/21)

- [ ] Create `docs/raw/33-ai-fde-product-positioning.md`.
- [ ] Build a positioning matrix with persona, job-to-be-done, AI FDE capability, Foundry dependency, and risk boundary.
- [ ] Compare AI FDE with AIP Assist, AIP Chatbot Studio, AIP Analyst, Palantir MCP, Pipeline Builder, Code Repositories, and human FDE.
- [ ] Extract three to five product design principles that are safe to borrow.
- [ ] Comment on #21 with the matrix summary and document path.

**Issue:** [#23](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/23)

- [ ] Create `docs/raw/34-ai-fde-context-tools-skills.md`.
- [ ] Document the flow: intent -> mode -> context -> tool plan -> approval -> execute -> observe -> validate -> proposal.
- [ ] List context sources, tool configuration controls, chat outline behavior, session memory behavior, and closed-loop validation methods.
- [ ] Identify the minimum reproducible modules: context registry, mode router, skill registry, tool gateway, session outline, approval UI.
- [ ] Comment on #23 with the flow summary and document path.

**Issue:** [#26](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/26)

- [ ] Create `docs/raw/35-ai-fde-governance-branching.md`.
- [ ] Build a governance control matrix covering identity, permissions, markings, session access, approval, audit, LLM usage attribution, Global Branching, Code Repository PRs, protected branches, CI checks, and fallback branches.
- [ ] Separate controls owned by AI FDE from controls inherited from Foundry, Global Branching, and Code Repositories.
- [ ] Define the minimum security gate for a self-built AI FDE.
- [ ] Comment on #26 with the matrix summary and document path.

**Issue:** [#25](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/25)

- [ ] Create `docs/raw/36-ai-fde-architecture-design.md`.
- [ ] Produce an architecture diagram covering AIP model gateway, agent orchestrator, context layer, tool services, permission proxy, branch workspace, validation runners, audit ledger, observability/evals, Foundry resources, and Ontology.
- [ ] Mark each module as 【事实】, 【推断】, or 【猜测】 with source or reasoning.
- [ ] Identify at least five implementation interfaces that public docs imply but do not expose.
- [ ] Comment on #25 with the diagram summary and document path.

### Wave 2: Implementation Blueprint

**Issue:** [#24](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/24)

- [ ] Create `docs/raw/37-ai-fde-self-build-implementation-blueprint.md`.
- [ ] Use inputs from #21, #23, #26, and #25; if an input is not complete, write a tracked assumption and return once the dependency lands.
- [ ] Define a reference architecture with these modules: agent orchestrator, model gateway, context registry, mode router, skill registry, tool gateway, permission proxy, approval engine, branch workspace, validation runner, audit ledger, evals/observability.
- [ ] Define a 90-day PoC route: P0 read-only exploration, P1 branch-local code changes, P2 preview/CI validation, P3 ontology/function/tool expansion, P4 evals and operationalization.
- [ ] State which capabilities must be platform-native and which can be implemented by an external agent framework.
- [ ] Comment on #24 with the PoC route and document path.

### Wave 3: Synthesis And Review

**Issue:** [#27](https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/issues/27)

- [ ] Create `docs/synthesis/palantir-ai-fde-research.md`.
- [ ] Integrate all raw documents into one decision-ready synthesis.
- [ ] Answer the three primary questions: AI FDE's functional positioning, AI FDE's likely architecture design, and a self-build implementation plan.
- [ ] Include source index, issue index, evidence gaps, unresolved contradictions, and follow-up validation plan.
- [ ] Comment on #27 and #20 with the final synthesis path and top-level conclusion.

## Agent Prompt Template

Each Agent should start with this prompt shape, replacing the issue-specific fields:

```markdown
You are working on Palantir AI FDE research for issue #[issue-number].

Read:
- docs/superpowers/plans/2026-05-30-palantir-ai-fde-research-plan.md
- The GitLab issue body for #[issue-number]
- Any completed raw docs listed as dependencies

Rules:
- Use official Palantir sources first.
- Mark every key conclusion with 【事实】, 【推断】, or 【猜测】.
- Do not overclaim internal Palantir mechanisms that public docs do not expose.
- Write only your assigned raw document unless your issue explicitly depends on synthesis.
- At the end, comment on your GitLab issue with the document path, top findings, and evidence gaps.
```

## Review Checklist

- [ ] Every raw document has source URLs and collection date.
- [ ] Every important claim has a confidence label.
- [ ] No raw document silently depends on a private Palantir implementation detail.
- [ ] Functional positioning, interaction model, governance, architecture, and implementation plan are covered by separate files.
- [ ] The synthesis links back to #20 through #27.
- [ ] The final implementation blueprint distinguishes platform-native capabilities from agent-framework capabilities.
- [ ] Public documentation volatility is noted, because AI FDE feature availability may vary by customer and change over time.

## Completion Criteria

The research is complete when #21 through #27 are closed, #20 contains the final synthesis link, and `docs/synthesis/palantir-ai-fde-research.md` can stand alone as the answer to:

1. What is Palantir AI FDE's product function and boundary?
2. How is AI FDE likely architected across AIP, Foundry, Ontology, tools, permissions, branching, validation, and audit?
3. What should be built first if we want to reproduce the useful parts in our own platform?
