# Visual editors for agent workflows and skills

Checked 2026-10-26. Method: web searches for dedicated tools, then primary sources for each
candidate: the repo's README and LICENSE, sample flow files and source read through `gh api`, plus
`pushed_at`, `archived`, license, latest release, last default-branch commit and the contributors
endpoint. Dates below are the last default-branch commit unless marked "release". Advisories were
not checked for most rows (the API refused the Dependabot endpoint; cc-wf-studio's published
advisories list was empty), so no row is marked advisory-clean. "Inference" is mine, not a source's.

Question, from the operator: "Search online for tools like this that could help us in visually
scripting agent workflows/scripts. Consider TypeScript/JS/Go/Rust/C++ solutions or other languages
if they fit our needs. Ideally search if there are dedicated tools online for this."

Context: our Skill Blueprint is a hand-written single-page editor over `hl-engineer.json` (nodes with
`kind`, `gate`, prose fields; wires `flow`/`loop`/`uses` carrying a handover label), expanded into
SKILL.md reference files by `hl-blueprint`. Orchestration stays in Claude Code
([harness.md](../agents/harness.md), "Flow model").

## Short answer

- **Dedicated tools exist, and they are young.** Three community tools author Claude Code
  skills/agents on a canvas: `cc-wf-studio` (VS Code, 5.4k stars), `claude-workflow-composer` (local
  browser app, 37 stars) and `claude-studio` (unverified, repo gone). Nothing from Anthropic turned up,
  and no tool turned up that maps a graph onto a skill's reference-file tree.
- **cc-wf-studio: borrow ideas, do not adopt.** The editor is AGPL-3.0 (we reject that for Flyde
  too), one human wrote nearly all of it, and it exports one orchestrator SKILL.md plus inline agents.
  Its `core`, `cli` and `mcp` packages are MIT.
- **claude-workflow-composer (CWC): borrow ideas; closest data model to ours.** MIT, React Flow
  canvas, edges that carry a prose trigger and handover artifacts, loop-back edges. Single maintainer,
  no GitHub release, and its test-run harness launches Claude with `--permission-mode
  bypassPermissions`. Not a fit as our front-end.
- **Keep our editor.** If it outgrows hand-written HTML, build on **React Flow / xyflow** (MIT,
  release 2026-09-24, several maintainers): sub-flows, handle ids, connection validation. **JSON
  Canvas** (MIT) is a possible interchange so Obsidian can open the graph, but it has no port or
  wire-kind concept.
- **Reject the LLM runtimes** (Rivet, Langflow, Dify, n8n, Flowise, AutoGen Studio, Prompt flow,
  LangGraph Studio, Griptape Nodes, ComfyUI). They own execution, which ADR 0014/0016 and the Flow
  model rule out. Several also fail the checklist outright (below).

## Comparison

"Prose" = can a node carry free-form Markdown or text.

| Tool | Lang | Kind | File format, prose? | Editor | Licence | Last commit / release | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [cc-wf-studio](https://github.com/breaking-brake/cc-wf-studio) | TS | dedicated | JSON, `.vscode/workflows/*.json`; `prompt` textareas on prompt/subAgent nodes | VS Code; `ccwf canvas` browser (experimental) | AGPL-3.0 ext; MIT core/cli/mcp | 2026-08-02; release 3.36.0 2026-07-11 | borrow ideas |
| [claude-workflow-composer](https://github.com/fayzan123/claude-workflow-composer) | TS | dedicated | JSON `.cwc`; edge `trigger` prose, node `systemPrompt` | local web (React Flow) | MIT | 2026-07-25; no release | borrow ideas |
| claude-studio (androidZzT) | TS | dedicated | YAML in `.claude/workflows/` per [post](https://dev.to/zagentz/claude-studio-a-visual-orchestration-platform-for-claude-code-multi-agent-workflows-5g0p) | local web | MIT per post | repo returns 404 | unverified |
| [Flyde](https://github.com/flydelabs/flyde) | TS | LLM runtime | `.flyde` YAML | VS Code | custom (operator: AGPLv3 editor) | 2025-07-27 | rejected earlier |
| [Rivet](https://github.com/Ironclad/rivet) | TS | LLM runtime | YAML `.rivet-project`; text nodes | desktop | MIT | 2026-08-26 (bot-heavy); release 2025-08-08 | reject |
| [Langflow](https://github.com/langflow-ai/langflow) | Py | LLM runtime | JSON starter flows | web | MIT | 2026-10-26; v1.13.0 2026-10-22 | reject |
| [Dify](https://github.com/langgenius/dify) | Py/TS | LLM runtime | YAML DSL (not read) | web | modified Apache (multi-tenant and logo limits) | 2026-10-26 | reject |
| [n8n](https://github.com/n8n-io/n8n) | TS | automation runtime | JSON | web | Sustainable Use (not OSI) | 2026-10-26 | reject |
| [Flowise](https://github.com/FlowiseAI/Flowise) | TS | LLM runtime | JSON | web | Apache-style plus commercial `enterprise/` | **archived**; 2026-08-13 | reject |
| [AutoGen Studio](https://microsoft.github.io/autogen/stable/user-guide/autogenstudio-user-guide/index.html) | Py | LLM runtime | JSON team spec | web | CC-BY-4.0 / MIT | repo README: archived | reject |
| [Prompt flow](https://github.com/microsoft/promptflow) | Py | LLM runtime | `flow.dag.yaml` | VS Code | MIT | README: retires 2027-04-20; release 2025-01-09 | reject |
| [LangGraph Studio](https://docs.langchain.com/langsmith/studio) | Py | debugger | needs a LangGraph server | desktop/web | n/a | n/a | reject |
| [Griptape Nodes](https://github.com/griptape-ai/griptape-nodes-engine) | Py | LLM runtime | saved as Python | cloud IDE | Apache-2.0 engine | 2026-10-26 | reject (SaaS editor) |
| [ComfyUI](https://github.com/comfyanonymous/ComfyUI) | Py | runtime | JSON | web | GPL-3.0 | 2026-10-26 | reject |
| [Node-RED](https://github.com/node-red/node-red) | JS | runtime | JSON; Markdown description per node | web | Apache-2.0 | 2026-10-26; 5.0.9 2026-10-21 | borrow ideas |
| [Open Agent Spec](https://github.com/oracle/agent-spec) | Py/TS | spec | JSON/YAML via SDKs | none found | Apache-2.0 or UPL | 2026-10-26; release 2026-09-11 | borrow ideas |
| [Inkeep Visual Builder](https://github.com/inkeep/agents) | TS | LLM runtime | code-synced; SKILL.md entry | web | Elastic 2.0 + terms | 2026-10-26 | reject |
| [React Flow / xyflow](https://github.com/xyflow/xyflow) | TS | library | JSON of your design | you build | MIT | 2026-10-26; 2026-09-24 | library under our editor |
| [Rete.js](https://github.com/retejs/rete) | TS | library | n/a | you build | MIT | 2025-06-30 | stale |
| litegraph.js ([orig](https://github.com/jagenjo/litegraph.js), [Comfy fork](https://github.com/Comfy-Org/litegraph.js)) | TS | library | JSON | you build | MIT | 2024-01-08; 2025-08-06 | stale |
| [Drawflow](https://github.com/jerosoler/Drawflow) | JS | library | JSON | you build | MIT | 2024-10-19 | stale |
| [JointJS](https://github.com/clientIO/joint) | TS | library | JSON | you build | MPL-2.0 | 2026-10-26 | possible, heavier |
| [maxGraph](https://github.com/maxGraph/maxGraph) | TS | library | XML/JSON | you build | Apache-2.0 | 2026-10-26 | possible, heavier |
| [egui-snarl](https://github.com/zakarumych/egui-snarl) | Rust | library | serde | desktop | MIT or Apache-2.0 | 2026-08-26 | reject (not a page) |
| [imgui-node-editor](https://github.com/thedmd/imgui-node-editor) | C++ | library | none | desktop | MIT | 2026-10-14 | reject |
| [imnodes](https://github.com/Nelarius/imnodes) | C++ | library | none | desktop | MIT | 2026-10-17; release 2022 | reject |
| [cimgui-go](https://github.com/AllenDang/cimgui-go) | Go | bindings | none | desktop | MIT | 2026-10-15 | reject |
| [JSON Canvas](https://github.com/obsidianmd/jsoncanvas) | n/a | format | JSON; text nodes are Markdown | Obsidian | MIT | 2026-07-24 | interchange option |
| Mermaid / D2 / bpmn-js / tldraw / Excalidraw | various | diagram | text or JSON, labels only | various | MIT / MPL-2.0 / watermark / restricted / MIT | all 2026 | reject as editor |

Notes on the table. The Go row is the only Go option found: no dedicated Go node editor surfaced
([search result](https://github.com/fyne-io/fyne/wiki/Proposal:-Data-Visualization) calls Fyne's a
proposal). bpmn-js's [licence](https://github.com/bpmn-io/bpmn-js/blob/develop/LICENSE) forbids
removing its watermark. tldraw's [licence](https://github.com/tldraw/tldraw/blob/main/LICENSE.md)
restricts production use. Mermaid and D2 render text to pictures; neither has an editor that writes
the text back. Rete.js, litegraph.js and Drawflow fail the 12-month rule on last commit.

## cc-wf-studio (dedicated, closest in spirit)

- **What it is.** "Design workflows on a canvas. Export as Markdown your AI agent already
  understands" ([README](https://github.com/breaking-brake/cc-wf-studio#readme)). A React Flow canvas
  in a VS Code extension, plus a CLI (`ccwf render | validate | export | run | preview | canvas | mcp`)
  and an MCP server so Claude Code can read and edit the same file.
- **File.** [`sample-workflow.json`](https://github.com/breaking-brake/cc-wf-studio/blob/main/packages/cli/fixtures/sample-workflow.json):
  `nodes[{id,type,name,position,data}]`, `connections[{id,from,to,fromPort,toPort}]`. Node types in
  [`core/src/schema/nodes`](https://github.com/breaking-brake/cc-wf-studio/tree/main/packages/core/src/schema/nodes):
  prompt, subAgent, skill, mcp, ifElse, switch, askUserQuestion, group, subAgentFlow (a sub-graph
  reference), branch. Prose lives in schema-declared fields (`prompt`, `agentDefinition`,
  `description` textareas, some "edit in editor"). Whether unknown `data` keys survive is **unverified**;
  the property panel is generated from a zod schema, which suggests a closed set.
- **Export.** `ccwf export` writes `.claude/skills/<workflow>/SKILL.md` plus
  `.claude/agents/<sub-agent>.md`; its own README admits the SKILL.md body still comes from the
  "legacy SlashCommand generator" with frontmatter the skill spec does not recognise.
- **Checklist.** Release 3.36.0 on 2026-07-11, last commit 2026-08-02: maintained. Licence: the VS Code
  extension is AGPL-3.0, the `core`, `cli`, `mcp` packages are MIT (README, package LICENSE files).
  The MIT CLI's build script copies the extension's webview bundle into `dist/webview`
  ([package.json](https://github.com/breaking-brake/cc-wf-studio/blob/main/packages/cli/package.json)),
  so the licence of the `ccwf canvas` editor is **unclear**. Maintainers: 6 contributors, but in the
  last 100 commits 95 are by two accounts that look like one person (`breaking-brake`,
  `breaking-breake`; same-person is inference) and 5 by a bot: fails "more than one maintainer".
- **Fit.** Authoring and Markdown export fit. It fails ours on structure: it assumes one orchestrator
  SKILL.md and inline agents, with no per-stage reference files, no wire kinds (`flow`/`loop`/`uses`),
  no named handover. Its `run` can spawn Claude Code, which is acceptable because Claude Code stays
  the runtime.

## claude-workflow-composer (dedicated, closest data model)

- **What it is.** A local server (`npx claude-cwc`, loopback, per-run token) that scans Claude Code
  history for repeated work, recommends a rule, skill, loop or multi-agent workflow, and edits
  workflows on a canvas ([README](https://github.com/fayzan123/claude-workflow-composer#readme)).
  `package.json` depends on `@xyflow/react`.
- **File.** [`gate-loop.cwc`](https://github.com/fayzan123/claude-workflow-composer/blob/main/tests/fixtures/gate-loop.cwc)
  is JSON: `meta`, `nodes[{id,position,agent{name,description,completionCriteria,systemPrompt,...}}]`,
  `edges[{from,to,label,trigger,context[{name,type,path}],terminalType}]`. The edge `trigger` is a
  prose sentence and `context` is a typed handover (`file`, `text`, `json`), so a loop-back with
  feedback is an ordinary edge. [`src/schema.ts`](https://github.com/fayzan123/claude-workflow-composer/blob/main/src/schema.ts)
  defines it. Real-time validation flags disconnected nodes and missing completion criteria.
- **Export.** Workflow: `.claude/skills/cwc-<slug>/SKILL.md` orchestrator (hidden via
  `disable-model-invocation: true` by default) plus `.claude/agents/*.md`; a preview of every file
  before writing; ownership comments so it never overwrites hand-written files.
- **Checklist.** MIT, last commit 2026-07-25; no GitHub release (npm version 0.12.2 in `package.json`;
  registry not reachable here, so published releases are **unverified**); all 100 recent commits are by
  one author: fails "more than one maintainer". Its Test run spawns Claude headlessly with
  `--permission-mode bypassPermissions` (README), which our hooks and sandbox rules would not
  accept unattended.
- **Fit.** Best match to "edges carry a handover". Not adoptable as our front-end: orchestrator prose
  is generated, node kinds are agents only (no hooks, no operator steps, no stage/procedure split).

## claude-studio (unverified)

A dev.to post describes a Next.js and React Flow editor over `~/.claude/` with four edge types
(dispatch, report, sync, roundtrip) and YAML workflows in `.claude/workflows/`. The repo it names,
`androidZzT/claude-studio`, returned 404 on 2026-10-26, so licence, maintenance and format are
unverified.

## React Flow as the library under our editor

MIT, maintained by a small team (top contributors 3,970 and 760 commits), latest `@xyflow/react`
12.12.0 on 2026-09-24. Documented: multiple handles per node need a unique `id`
([handles](https://reactflow.dev/learn/customization/handles)); sub-flows via `parentId` and
`extent: 'parent'`, parents listed before children ([sub flows](https://reactflow.dev/learn/layouting/sub-flows)).
It needs a React build step, which our single-HTML editor lacks today (inference). cc-wf-studio and
CWC both chose it, which is the best evidence of fit. Only worth the switch if we want sub-graphs or
port validation.

## Ideas worth borrowing

- **A handover that is data, not a label.** CWC edges carry `context[{name,type,path}]` and a prose
  `trigger` ([schema.ts](https://github.com/fayzan123/claude-workflow-composer/blob/main/src/schema.ts)).
  Our `label` could become `{trigger, handover: {name, kind: file|text|json, path}}`.
- **Separate control wires from data wires, with named ports.** Open Agent Spec has `ControlFlowEdge`
  (with `from_branch`, a branch name offered by the source node) and `DataFlowEdge` (named
  `source_output` to `destination_input`, type-checked in a validator)
  ([controlflowedge.py](https://github.com/oracle/agent-spec/blob/main/pyagentspec/src/pyagentspec/flows/edges/controlflowedge.py),
  [dataflowedge.py](https://github.com/oracle/agent-spec/blob/main/pyagentspec/src/pyagentspec/flows/edges/dataflowedge.py)).
  Our gates could expose named branches (pass, fail, escalate) instead of free `loop` wires.
- **Validation before export.** CWC flags duplicate slugs, disconnected nodes and missing completion
  criteria; cc-wf-studio ships `ccwf validate` with exit 0/1 and `--json`
  ([cli README](https://github.com/breaking-brake/cc-wf-studio/blob/main/packages/cli/README.md)).
  Our `jq` check on `sync` could become a rule list in the editor.
- **Terminal outcomes.** CWC `terminalType`: complete, escalated, aborted.
- **Reference nodes.** CWC drags an existing `.claude/agents/*.md` onto the canvas as a pointer, not a
  copy ("reference node"); matches our `target`.
- **Machine-edit path.** cc-wf-studio exposes the graph through an MCP server (`get_workflow`,
  `apply_workflow`) so Claude edits the canvas live
  ([README](https://github.com/breaking-brake/cc-wf-studio#readme)). Our `sync` is a paste; a local
  file watcher is the cheaper equivalent.
- **Per-node Markdown description and sub-flows.** Node-RED: "Every node, group and tab can have
  longer-form documentation ... formatted using Markdown", plus subflows and Comment nodes
  ([docs](https://nodered.org/docs/developing-flows/documenting-flows)).
- **Graphs as functions with their own tests.** Rivet calls graphs from graphs and tests them with
  validator graphs ([trivet](https://rivet.ironcladapp.com/docs/user-guide/trivet-validation-graphs)).
  Maps to `evals/` per sub-skill.
- **Generate the property panel from one schema.** cc-wf-studio derives its panel and its "ignored by
  target X" warnings from a zod schema ([sub-agent-schema.ts](https://github.com/breaking-brake/cc-wf-studio/blob/main/packages/core/src/schema/nodes/sub-agent-schema.ts)).
- **A second front-end for free.** JSON Canvas text nodes hold Markdown, file nodes point at a path,
  edges carry a `label` ([spec](https://github.com/obsidianmd/jsoncanvas/blob/main/spec/1.0.md)). A
  one-way exporter would let Obsidian show the graph with node prose and links to the reference
  files; round-tripping `kind` and `gate` has no home in the spec (inference).

## Unanswered

- Whether cc-wf-studio's `data` objects keep unknown keys, and the licence of its `ccwf canvas` webview.
- Whether `claude-studio` ever existed publicly as named; its repo is 404.
- npm release history for `claude-cwc`; the registry was not reachable from the sandbox.
- Open advisories for any candidate except cc-wf-studio's empty published list; treat all as unverified.
- Dify's YAML DSL, Langflow's schema, JointJS and maxGraph feature limits behind commercial tiers:
  not read, since runtimes are rejected on architecture and the libraries are only relevant if we leave
  React Flow.
- Obsidian's own licence and whether Canvas can run headless in WSL2: not assessed.
- Anthropic-made tooling: none found in searches; absence is not proof.
