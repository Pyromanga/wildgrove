# ReviewAgent.md — WildGrove Architecture Meta-Analysis

> Renamed from `AGENT.md`. `AGENT.md` is now the standing, repo-wide baseline that applies to
> any agent regardless of task; this file is the task-specific playbook for the audit/
> meta-analysis round. Read `AGENT.md` first, then this file if you've been pointed at it.

This file defines the active task for any agent (Claude or otherwise) working on a
**meta-analysis of the WildGrove codebase** — not feature work, not implementation. If you've
been pointed at this file, your job is auditing, verifying, and planning, in that order. Do
not start writing gameplay code from this brief alone; produce or extend an implementation
plan first, get it reviewed by the human, then implement.

## The one rule that overrides all others here

**Trust the code. Do not trust the comments, the ADR status fields, or `docs/review.md`'s
checkmarks without verifying them against the file they describe.** This codebase has a
demonstrated, repeated pattern of documentation drifting from code in both directions —
things marked fixed that are broken, and things marked as open debt that are already fixed.
See `docs/audit/AUDIT-01-pain-points-and-review-verification.md`, Findings 1 and 4, for two
concrete, file-and-line-cited examples of exactly this. Every claim you make in your own
output must be backed by a direct read of the `.gd`/`.tres`/`.tscn` file in question, not by
quoting what another doc says about it. If you can't verify something in the time available,
say so explicitly and mark it as unverified — do not round up to a claim of correctness.

## Project context, briefly

WildGrove is a solo-developer, mobile-first 3D RPG (Godot 4.6.3 / GDScript) combining open-world
exploration, a numeric skill-progression system, seasonal farming, and a village/wildlife
layer — see `README.md` for the concept summary. **Do not reference real game franchises by
name anywhere in code, comments, docs, or your own output.** Concepts only (e.g. "numeric
skill progression," not the name of the game that popularized it). A few stragglers still
exist in the codebase from before this rule — see "Tracked but not yet done" below.

The codebase is intentionally over-engineered relative to its current size: the explicit goal,
stated by the project owner, is a foundation suitable for 20+ years of growth on an
enterprise-grade architecture, built by a single developer who is aware of the tradeoff and
wants it anyway. **Do not flag complexity as a problem on its own.** Flag it only when it
doesn't trace back to a real, statable problem (see `AUDIT-02-adr-meta-analysis.md` for the
standard being applied — it's the right bar to keep using).

## What's already done (round 1)

- `docs/audit/AUDIT-01-pain-points-and-review-verification.md` — verified discrepancies
  between `docs/review.md`/ADRs and actual code, CI pipeline critique, prioritized pain
  points, and an explicit "Not Yet Audited" scope list.
- `docs/audit/AUDIT-02-adr-meta-analysis.md` — per-ADR judgment: sound reasoning vs.
  cargo-cult, where debt was accepted that shouldn't have been (atomic save writes flagged as
  the clearest case), and one cross-cutting structural recommendation.
- `README.md` rewritten to concept-only language, structure matches what's actually on disk.
- `docs/ci-pipeline.md` — authoritative, frozen reference for the existing CI workflow
  (provided by the owner, not in the original zip). **Changes to this pipeline require a
  conversation with the human first — do not edit `.github/workflows/build-apk.yml`'s
  behavior unilaterally even if a fix seems obviously correct.**

## What's explicitly NOT done yet (pick up here)

From `AUDIT-01`'s "Not Yet Audited" section — treat all of this as unverified, not clean:

- `scripts/ui/components/`, `scripts/ui/visuals/` (~25 files, unread)
- `scripts/world/` entity layer beyond the files spot-checked in round 1 (~25 files, unread)
- `docs/principles.md`, `docs/services.md`, `docs/history.md`, `CONTRIBUTING.md`,
  `docs/MIGRATION.md`, `docs/MIGRATION-010.md` — referenced but not read in full
- All `.tscn` scene files — editor-level signal wiring was not inspected at all. Given the
  bugs already found in script-level wiring (the `SkillSystem` rename bug), scene-level wiring
  is at least as plausible a place for the same class of drift, and it's invisible to a
  text-only `.gd` read — you need to actually open or parse the `.tscn` files.
- `tests/IntegrationTest.gd` and the 7 existing unit test files — existence confirmed, content
  not reviewed for correctness or for whether they actually exercise the failure modes they
  claim to guard against.
- A systematic project-wide sweep for the `SkillSystem`-style bug pattern (a field renamed in
  its declaration but not in every call site within the same file). Round 1 found one instance
  because it happened to be the one thing `docs/review.md` specifically claimed was fixed —
  that's a good prior, not a complete search.
- Nothing has been executed. No Godot binary was available in the round-1 sandbox (no network
  access). If you have Godot available, **actually run the project and the test suite** — this
  upgrades several "static evidence, high confidence" findings to "confirmed," and may surface
  runtime-only issues (signal connection order, scene-tree timing, race conditions) that static
  reading cannot.

## Tracked but not yet done — real-IP cleanup

Round 1 found franchise-name references outside the README in: `project.godot` (line 2),
`scripts/resources/PlayerStats.gd` (line 31, comment), `docs/adr/010-multiplayer-authority-tiers.md`
(line 40, prose argument that also names a franchise's actual server architecture as
precedent — rewriting this one needs care, since the *argument* should survive even though
the *name* shouldn't). These were deliberately left untouched in round 1 (analysis-first, per
the owner's instruction) — do this as one atomic, checklist-driven pass, not piecemeal, and
re-grep afterward (`grep -rliE "runescape|zelda|stardew|animal crossing|nintendo" .`) to
confirm zero remaining hits before considering it done.

## Working method for this task

1. **Pace it.** Don't try to produce a complete, final audit in one pass. The owner has
   explicitly asked for incremental delivery — more total feedback over multiple rounds, not
   one maximal dump. Pick a bounded slice (a layer, a subsystem, a doc), audit it
   thoroughly, write it up, stop.
2. **Number your audit docs** (`AUDIT-03-...md`, `AUDIT-04-...md`, ...) and put them in
   `docs/audit/`, following the format of `AUDIT-01`/`AUDIT-02`: a methodology/scope
   statement at the top, evidence-cited findings (file + line), an explicit "what I did and
   didn't check" close. The point of this format is that a *different* agent or the human can
   cross-check your claims without re-deriving them — don't lose that property for the sake
   of brevity.
3. **Distinguish verified from inferred.** If you can't execute something, say "verified by
   static reading" vs. "inferred, needs execution to confirm" — round 1 did this consistently
   for the CI pipeline's `results.xml` question and you should hold the same bar.
4. **Don't silently fix things while auditing.** This task is analysis and planning. If you
   find something exactly as clear-cut as the `SkillSystem._ensure_player()` bug (an
   unambiguous, isolated, one-line fix with no design judgment involved), you may propose the
   fix inline in your write-up, but don't commit it as part of an audit pass without it being
   asked for — keep analysis and implementation as separate, reviewable steps, the same way
   round 1 kept the audit separate from actually rewriting `project.godot`.
5. **When you have enough rounds of audit to cover the "Not Yet Audited" list above**,
   synthesize an implementation plan: a prioritized, sequenced list of fixes and process
   changes (test-gating CI, atomic saves, the IP cleanup pass, a `test_skill_system.gd`, etc.)
   that a human or a future implementation-focused agent session can execute against. That
   plan is the actual deliverable this whole meta-analysis exists to produce — the audits are
   the evidence base for it, not the end goal themselves.

## What "done" looks like for this task

Not "every file read" — that's not a useful target on its own. Done looks like: every claim
of correctness anywhere in `docs/` (ADRs, `review.md`, `architecture.md`, etc.) has either
been re-verified against current code or explicitly flagged as unverified, and there's a
single prioritized implementation plan a developer could pick up and execute top-to-bottom
without having to re-derive priority or re-check whether a "fixed" claim is real.
