# AGENT.md — WildGrove Standing Agent Instructions

This file is the baseline for **any** agent (Claude or otherwise) working in this repo,
regardless of which task you've been asked to do. It doesn't describe a specific task —
for that, see "Active task playbooks" below. Read this file first, every time.

---

## Trust the code, not the docs

This codebase has a demonstrated, repeated pattern of documentation drifting from code in
both directions — things marked fixed that are broken, and things marked as open debt that
are already fixed. Every claim you make in your own output must be backed by a direct read
of the `.gd`/`.tres`/`.tscn` file in question, not by quoting what another doc says about it.
If you can't verify something in the time available, say so explicitly and mark it as
unverified — do not round up to a claim of correctness.

---

## Use the service graph — don't hand-grep the DI wiring

`scripts/agent/service_graph.py` exists so you don't have to reconstruct service wiring,
event flow, or interface conformance by grepping `config/BootstrapConfig.tres`,
`scripts/platform/ServiceKeys.gd`, `scripts/platform/BootPipeline.gd`, every `*Events.gd`,
and `scripts/platform/interfaces/*.gd` by hand. It's read-only, needs no Godot, and is safe to
run at any time. Default output is JSON (that's the point — it's for you, not for a human
reading a terminal), and the default run already includes services + events + interfaces in
one call — you should not need more than one invocation to get the full picture.

**Before touching a service** — adding one, changing its deps, debugging a "why is this
`null`" bug, checking what else might break — run one of:

```bash
python3 scripts/agent/service_graph.py --service <name>   # deps, dependents (blast radius),
                                                             # siblings, cross-scope bridge status
python3 scripts/agent/service_graph.py                     # full graph + events + interfaces + findings
python3 scripts/agent/service_graph.py --events             # only the event graph (namespaces, signals,
                                                             # direct EventBus.* vs. IEventBus-indirection
                                                             # access, dead/unconsumed signals)
python3 scripts/agent/service_graph.py --interfaces          # only interface conformance (real `extends I*`
                                                             # vs. comment-only `## implements I*` claims,
                                                             # stub vs. non-trivial method bodies)
python3 scripts/agent/service_graph.py --pretty             # any of the above, human-readable (for people, not you)
```

`findings` (or exit code 1 on the full-graph run) surfaces structural problems automatically:
broken dep references, dependency cycles, a global service depending on a session service, a
session service depending on a global service whose key isn't in the `BootPipeline.gd`
cross-scope bridge list (the exact class of bug that made `PvPService.permission_service`
silently `null` at runtime until it was fixed — see `git log` / commit history for that fix),
missing `ServiceKeys` constants, services with no discoverable unit test, signals that are
declared but never emitted or never connected, UI code still using the direct `EventBus.*`
autoload instead of the `IEventBus` indirection (ADR-012), `emit_<wrapper>()` functions whose
name doesn't match the signal they actually emit (resolved correctly either way — this is a
readability warning, not a bug), `emit_<wrapper>()` functions whose target signal *can't* be
verified from the body at all (this one fails loud — it used to silently guess by name equality,
which was itself the kind of workaround this tool exists to catch, and got removed), a
measurement audit of native `signal` declarations that share a name with an EventBus signal
(currently: `inventory_changed`, symptom of two parallel channels for one fact, see TODO point
7), `get_service()`/`require()`/`get_optional()` calls using a raw string literal where a
matching `ServiceKeys` constant already exists (production code only, see TODO point 8), and —
treated as an ERROR-class finding, not a style nit — any `## implements I*`/`## Implementiert
I*` comment that isn't backed by a real `extends I*`. A comment is not a contract; the compiler
checks nothing there.
See `TODO-offene-probleme.md` → "Zwei parallele Pfade für dieselbe Sache" for the fuller
writeup and the decision log behind each finding kind.

**If the script's output doesn't answer what you need, and you find yourself falling back to
grep anyway** — that's not a neutral fallback, it's a gap in the tool. Get your answer
however you need to for the task at hand, but say so explicitly in your response: name what
information was missing and propose the specific extension to `service_graph.py` that would
have made grep unnecessary. Don't silently normalize working around the tool. The tool is
only worth maintaining if gaps get reported and closed instead of quietly re-discovered every
session.

---

## Active task playbooks

This repo currently has two task-specific playbooks. Neither is "the" task by default — you
should be told (or infer from context) which one applies:

- **`ReviewAgent.md`** — audit / architecture meta-analysis. Read, verify, write findings —
  no implementation.
- **`ImplementAgent.md`** — bug-fix execution log for the Prio-3 fix pass. Bug-by-bug,
  tests + docs updated atomically, ZIP output after each logical group.

If you're not sure which applies, ask rather than guessing — the two have very different
"don't do X" rules (e.g. ReviewAgent.md explicitly forbids silently fixing things while
auditing).

---

## A few standing rules that apply everywhere

- **No franchise names** — concepts only, in code, comments, docs, and your own output.
- **CI pipeline** (`docs/ci-pipeline.md`) is an owner-provided, frozen reference. Don't change
  its behavior, thresholds, or gating logic without discussing it with the project owner
  first, even if a change looks obviously correct.
