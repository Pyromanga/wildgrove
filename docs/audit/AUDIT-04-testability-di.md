# AUDIT-04 — Dependency Injection & Testability Review (Section H)

**Scope:** External testability/DI review, cross-verified against actual code during implementation.
**Method:** Code first. Every finding cites file + line. Continues AUDIT-03's lettered
convention (A–G already used) — this review's findings are Section H.
**Trust:** `*.gd` / `*.tres` = truth. The review itself = hypothesis until verified.
**Date:** 2026-06
**Source:** External review, pasted in full by the project owner. See `ImplementAgent.md`
for the execution plan and round-by-round status.

> **Implementation status** is tracked here, same as AUDIT-03. Completed items marked ✅.

---

## Legend

| Symbol | Meaning |
|--------|---------|
| 🔴 P0 | Class/method completely untestable without disk/SceneTree |
| 🟠 P1 | Silent failure or locator-access that breaks test isolation |
| 🟡 P2 | Long-term/architectural — accepted debt, not fixed this round |
| 🔵 P3 | Consistency / duplication |
| ✅ | Fixed in this implementation round |

---

## AUDIT H — Dependency Injection & Testability

### H-01 🔴 P0 ✅ — ServiceValidator: hardcoded disk load

**Verified.** `ServiceValidator._load_config()` called `ResourceLoader.exists()` / `load()`
on a hardcoded `res://config/BootstrapConfig.tres` path on every `validate()` /
`validate_session()` call — no way to inject a fake config.

**Fixed.** `config: BootstrapConfig` is now an injectable property (analogous to
`ServiceFactory.mounter`). `_load_config()` returns the injected `config` if set; otherwise
falls back to the new `BootstrapConfig.load_default()` static method and caches the result.
The disk-path constant moved to `BootstrapConfig.gd` (`DEFAULT_PATH`) — single source of
truth for "where does the config live on disk", and the only place that still touches
`res://`.

Deviation from the review's literal suggestion ("`_load_config()` wird zur statischen
Utility-Methode, die nur in ServiceOrchestrator aufgerufen wird"): in this codebase the
testable orchestration layer is `BootPipeline` (`RefCounted`, already has injectable
helpers for validator/resolver/factory/initializer/installer/teardown), not
`ServiceOrchestrator` (the thin `Node` shell). Property injection on `ServiceValidator`
itself keeps the fix consistent with that existing pattern instead of introducing a new one.

Test: `tests/unit/test_service_validator.gd` (new) — injected fake config (no disk access),
structural validation still works (null entry, missing path, self-dependency, cross-registry
external names), and a fallback test confirming production behavior (real `.tres` load) is
unchanged when nothing is injected.

---

### H-02 🔴 P0 ✅ — GameManager: hardcoded `load()` inside `configure()`

*(status updated after implementation — see below)*

---

### H-03 🟠 P1 ✅ — `Services.ticker.register_service(self)` in `on_ready()` (3×)

*(status updated after implementation — see below)*

---

### H-04 🟠 P1 ✅ — `CombatSystem` — `Services.equipment` locator inside calculation methods

Cross-references **D-01** (AUDIT-03, still open there as "→ BUG-14 Round 2/3"). This fix
closes D-01 as well — see cross-reference note in that section once both docs are updated.

*(status updated after implementation — see below)*

---

### H-05 🟠 P1 — Untyped `deps: Dictionary` with silent null-cast

*(status updated after implementation — see below)*

---

### H-06 🟠 P1 — Duck-typing instead of a shared interface in ServiceInitializer/TeardownManager

*(status updated after implementation — see below)*

---

### H-07 🟡 P2 — `EventBus` global, no injection point

**Verified, not fixed this round.** 209 non-comment usages across 48 files. The review
itself flags this as intentionally global infrastructure (ADR-002) and the suggested fix as
long-term. Fully injecting EventBus would mean threading it through every `Service`/
`ServiceNode` that connects a signal in `on_ready()` — touching close to 50 files for a
change with no immediate bug behind it. Per `ReviewAgent.md`'s own standard ("don't flag
complexity as a problem on its own — flag it only when it doesn't trace back to a real,
statable problem"), this is logged as accepted, deliberate debt rather than implemented
unilaterally. Raised here so it isn't lost, not actioned without a separate go-ahead.

---

### H-08 🟡 P2 — `Logger` AutoLoad implicit dependency in all core classes

**Verified, not fixed this round.** 144 call sites across `scripts/core/*.gd`. Same
reasoning as H-07: real fix (an injectable null-logger) is mechanically simple in isolation
but touches every core class's call sites to thread it through, for a problem that in
practice GUT already works around (GUT loads AutoLoads). Logged as accepted debt, not
silently implemented as a wide mechanical edit.

---

### H-09 🔵 P3 — `ServiceInstaller` magic strings duplicate `ServiceKeys`

*(status updated after implementation — see below)*

---

## Not Verified / Out of Scope (explicit)

- `WorldService.on_ready()` also reads `Services.respawn` via locator, and `on_tick()` reads
  `Services.game_manager` — same pattern as H-03/H-04 but **not named in the review**, and
  left untouched this round to avoid silently expanding scope beyond what was asked.
- `EntityContext.gd` / `UIContext.gd` read `Services.equipment` directly — same family of
  issue as H-04 but in a different layer (context objects, not a Service's own calculation
  method). Not touched this round.
