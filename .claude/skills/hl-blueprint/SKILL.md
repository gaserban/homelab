---
name: hl-blueprint
description: Grow a skill from a node graph drawn in the Skill Blueprint editor. Usage: /hl-blueprint <skill> sync <json> | expand <node> | compile | publish
disable-model-invocation: true
argument-hint: "<skill> sync <json> | expand <node> | compile | publish"
---

The operator draws a skill as a **blueprint**: nodes with a title and one line of intent, wired
together, in the Skill Blueprint editor (an artifact). You grow each node into the text it expands
to, one node per run, and keep the graph and the editor in step with the repo.

`$ARGUMENTS` is `<skill> <verb> [...]`. The blueprint is `docs/agents/blueprints/<skill>.json`;
the editor page is `docs/agents/blueprints/editor.html`, published at the graph's `artifact` URL.
Work on the refactor's own branch.

## The graph

Each node carries `id`, `title`, `kind`, `gate` (`""`, `checkpoint`, `gate`), `status`, `x`, `y`,
`intent`, `target`, `decisions`, `research`. Each wire carries `from`, `to`, `kind` and `label`.
`flow` hands over the file or fact named in `label`, `loop` sends work back, and `uses` calls the
target and comes back.

**The operator owns** layout, `title`, `intent`, `kind`, `gate`, the node set and the wires.
**You own** `status`, `decisions`, `research` and `target`. Write the graph with `jq` and keep
its formatting as `jq .` prints it.

| kind | `target` when empty | written with |
| --- | --- | --- |
| stage, procedure | `.claude/skills/<skill>/references/<id>.md` | skill-creator |
| subskill | `.claude/skills/hl-<id>/SKILL.md` | skill-creator |
| subagent | `.claude/agents/<id>.md` | agent-development |
| hook | `.claude/hooks/<id>.sh`, plus its settings entry | hook-development |
| operator | none: the conductor names the command to type | — |

`status` moves `idea` → `grilled` → `drafted` → `done`. A node is `inline` while its prose still
sits inside the parent SKILL.md. A node becomes `done` only when the operator says a real run used
its file.

## sync

The operator pasted the editor's JSON after the verb. Validate it with `jq`. Merge it into the
blueprint: take the operator's fields from the paste, and keep your own fields from the repo file
for every node id present in both. Report the change as a list of nodes and wires added, removed
and renamed, plus edits to title, intent, kind or gate. When a removed node has a written target
file, name the file and ask whether to delete it. Done when the file passes `jq` and every
difference is in your report.

## expand <node>

1. **Gather.** Read the node and its neighbourhood: what each incoming wire hands it, what it
   hands on, what it uses, the files of those neighbours, and its current text (its target, or
   its section of the parent SKILL.md when it is `inline`). Read `docs/adr/README.md` and the
   ADRs the node touches.
2. **Grill.** Invoke `grilling` with this node as the root of the design tree. The tree is
   complete when it settles the node's input (what it refuses to start without), its steps, its
   **completion criterion**, its handover, the model it runs on, how it fails, and its gate summary
   when it ends on one. A question about a neighbour becomes an open item on that neighbour's
   `decisions`, prefixed `open:`. Write each settled decision as one line in `decisions` and set
   `status` to `grilled`.
3. **Research.** Each question grilling handed to sources rather than the operator goes to the
   `research` skill on Sonnet (`model: sonnet`), all in one message. A question only a run can
   answer is settled by a short experiment under `$TMPDIR/hl-proto/<skill>-<id>/`, removed
   afterwards. Add each note's path to `research`. Done when every handed-off question is sourced,
   measured, or marked unanswered in `decisions`.
4. **Write.** Invoke the skill from the kind table on the node's `target`, given the decisions
   and the research. Apply `writing-for-agents`. The file opens with what the node receives and
   closes on its completion criterion and handover. For a reference file, use only skill-creator's
   drafting step; the eval loop runs on the whole skill after `compile`. Fill `target`, set
   `status` to `drafted`.
5. Run **publish**.

## compile

Rewrite the parent skill's stage list from the blueprint. Walk the `flow` wires from the node
with no incoming flow, and give each stage an entry. The entry holds the title, the intent, a link
to its reference file, its gate or checkpoint, and the label of its outgoing flow. A `loop` becomes
one sentence on the stage it leaves, and a `uses` becomes a link. An `inline` node keeps its prose
where it is. Leave every section that no node owns as it is. Before renaming a stage, grep
`.claude/hooks/` and the state-file schema for the old name and update every reader. Then offer
the operator skill-creator's eval loop over the skill's `evals/`. Done when every non-operator
node is reachable from the parent SKILL.md.

## publish

Republish the editor at the graph's `artifact` URL. Read it first if this conversation has not.
Publish `editor.html` as the page, with `files` mapping `graph.json` to the blueprint and
`nodes/<id>.md` to each node's written target. Wrap a hook in a fenced block in a scratch copy.
Map a removed node's `nodes/<id>.md` to `null`. Give the operator the link.
