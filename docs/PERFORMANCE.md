# Performance Doctrine

## Position

tsodin is intentionally performance-first, but benchmark numbers are not permission to make the code unknowable.

The project favors disciplined hackery:

> **Non-obvious code is allowed. Unexplained code is not.**

"Best practice" for ordinary applications is not automatically best practice for a compiler hot path.

## What is allowed

When correct and justified, tsodin may use:

- raw and multi-pointers;
- custom allocators and arenas;
- compact integer handles;
- structure-of-arrays layouts;
- hand-built hash tables and caches;
- branch-light or branchless transformations;
- unchecked access behind explicit invariants;
- prefetching;
- SIMD;
- architecture-specific paths;
- unusual bit manipulation;
- specialization instead of generic abstraction.

These are tools, not goals.

## Measured cleverness

Clever code must earn its complexity.

A performance idea should normally move through:

    hypothesis
      -> isolated change
      -> correctness gate
      -> stable measurement
      -> machine-code/counter inspection when useful
      -> keep or reject

A clever-looking optimization that does not improve the target should be removed.

## Four-part rule

Every retained non-obvious optimization must make these discoverable:

1. WHY — what cost or code shape it addresses;
2. INVARIANT — what must remain true;
3. EVIDENCE — benchmark, profile, disassembly, or structural reason;
4. FAILURE MODE — what breaks if the assumption changes.

Use short source comments plus a longer hack/performance record when needed.

## Comment quality

Useful:

    // PERF: use a multi-pointer because this indexed probe retains a bounds edge
    // with a slice on the pinned Odin compiler.
    // INVARIANT: index is masked by capacity-1 before every access.
    key := keys_ptr[index]

Useless:

    // Read the key.
    key := keys_ptr[index]

Do not comment obvious syntax. Explain surprising reasons.

## No unexplained magic numbers

Performance constants must have a name or a nearby explanation.

If a constant was selected experimentally, link it to the relevant hack or benchmark record.

## Performance archaeology

A future contributor should be able to reconstruct why a strange optimization exists.

Important decisions should preserve:

- before/after revisions;
- toolchain identity;
- workload identity;
- correctness checksum/conformance state;
- stable wall measurements;
- useful counters;
- machine-code findings when relevant;
- final keep/reject decision.

Future Odin releases may optimize code differently. A hack justified today may become unnecessary later.

## Replaceable hacks

No hack is sacred.

A contributor is encouraged to remove a workaround when a simpler implementation preserves exact semantics, passes conformance/differential tests, and matches or improves the relevant stable benchmark.

The answer to "why is this weird?" should be documentation and reproducible evidence, not folklore.

## Representation before instruction tricks

Prefer gains from data width, dense IDs, arenas, interning, and locality before resorting to exotic instruction tricks.

However, do not assume smaller is faster. Measure the real workload.

## Hot path review

For an identified hot path, inspect algorithmic complexity, allocations, data width, working set, cache locality, dependent loads, branch count/predictability, bounds overhead, inlining, and generated assembly when necessary.

Optimization should target an observed cost, not aesthetic preference.

## AI-generated optimization

An agent may propose aggressive code, but a retained optimization must become repository knowledge.

A chat transcript is not evidence storage.

If an agent cannot explain the invariant and failure mode of a change, that change is not ready to merge.
