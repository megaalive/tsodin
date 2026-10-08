# Hack Registry

This file indexes intentional non-obvious implementation choices.

A "hack" here is not sloppy code. It is a technique that would be easy for a future contributor or agent to simplify incorrectly.

## Rule

Every registered hack should answer:

- Why does it exist?
- What invariant makes it valid?
- What evidence justified it?
- What happens if the assumption changes?
- How can it be retired?

Use identifiers such as H001, H002, and so on.

Source code may point here with:

    // HACK H002 — see docs/HACKS.md

## Template

### Hxxx — Short title

**Location:** path/to/file.odin

**Why:**  
What cost, compiler behavior, compatibility edge, or representation problem does this address?

**Invariant:**  
What must remain true for the implementation to be correct?

**Evidence:**  
Benchmark/profile/disassembly/conformance evidence and relevant revision.

**Failure mode:**  
What goes wrong when the invariant no longer holds?

**Retirement test:**  
How can a contributor prove the hack is no longer needed?

---

## Seed lessons from the ts-fp Odin exploration

These are not automatically tsodin implementation decisions. They are lessons to carry into future experiments.

### L001 — Branch-light classification can dominate instruction-count intuition

A scanner-like classification kernel became dramatically faster after changing code shape to reduce branches, despite retiring more instructions.

**Lesson:** inspect cycles, branches, generated code, and stable wall time rather than optimizing instruction count in isolation.

### L002 — Compact values can improve table behavior

A hash-table kernel improved after logical values were stored as u32 instead of u64.

**Lesson:** choose representation width from real cardinality and measure the resulting working set.

### L003 — Smaller representation can still lose

Packing a four-state relation value into two bits reduced memory footprint and cache misses but increased manipulation cost enough to regress stable wall time.

**Lesson:** "smaller" is a hypothesis, not a result.

### L004 — Raw hot-path views can remove avoidable checks

Multi-pointer table access helped remove bounds/control overhead in synthetic hot paths.

**Lesson:** raw access is allowed when an invariant makes it safe and evidence shows the checked representation is costly.

### L005 — Specialization can beat generic internal width

Carrying a compact value type end-to-end through a hot table path reduced machine work compared with widening internally for convenience.

**Lesson:** do not pay abstraction/conversion cost in a measured hot path merely to make internal APIs generic.

## No permanent folklore

When tsodin gains real Hxxx entries, each must point to code and evidence.

Lessons Lxxx are historical guidance only. They must not be cited as proof that the same optimization will help a real TypeScript workload.
