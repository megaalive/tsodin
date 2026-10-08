# AGENTS.md

This is the fast onboarding map for human contributors and coding agents.

## Project intent

tsodin is a performance-first TypeScript checker/compiler in Odin.

Core rule:

> **Readable invariants, aggressive implementation.**

Do not "clean up" unusual code merely because it differs from ordinary application code. Smart or hacky code is welcome when it is correct, measurable, and explainable.

## Read first

1. README.md
2. docs/ARCHITECTURE.md
3. docs/MEMORY.md
4. docs/PERFORMANCE.md
5. docs/BENCHMARKING.md
6. docs/HACKS.md

A contributor should be able to understand the repository shape, critical invariants, memory lifetimes, and benchmark rules in roughly fifteen minutes.

## Expected pipeline

    source
      -> scanner
      -> parser
      -> binder / symbol tables
      -> module graph / resolution
      -> checker / type relations
      -> diagnostics
      -> optional emit

This map may evolve, but changes must be documented.

## Contributor rules

- Correctness is a gate, not a benchmark variable.
- Do not remove work, weaken semantics, alter inputs, or change expected outputs to win a benchmark.
- Prefer explicit cost over hidden cost.
- Prefer compact data and stable integer IDs over pointer-rich object graphs when measured or structurally justified.
- Hot paths may use raw pointers, custom layouts, arenas, branchless code, SIMD, or other unusual techniques.
- Every non-obvious optimization must document why it exists, its invariant, its evidence, and its failure mode.
- Preserve a simple/reference implementation or oracle when optimized semantics are difficult to inspect.
- Do not create giant generated functions merely because an agent can.
- Do not create ceremonial abstractions, factories, interface layers, or generic wrappers without a concrete need.
- Split code by semantic responsibility and hot-path boundaries, not arbitrary line-count rules.
- Keep comments useful. Do not write comments that only restate the next line.
- Use natural English commit messages.
- Update relevant documentation when introducing or removing a documented hack.

## Comment tags

Use these tags when they add real value:

    // PERF:      why a non-obvious performance choice exists
    // INVARIANT: condition that must remain true
    // SAFETY:    why unchecked/raw memory access is valid
    // COMPAT:    intentional behavior required for TypeScript compatibility
    // HACK Hxxx: pointer into docs/HACKS.md

Example:

    // PERF H002: multi-pointer access avoids a bounds-check edge in this probe.
    // INVARIANT: capacity is a power of two and mask == capacity-1.
    // SAFETY: index is always masked before this load.
    // See docs/HACKS.md before replacing this with slice indexing.
    key := keys_ptr[index]

Do not write comments like "Get key" immediately above a line that obviously gets a key.

## Optimized code

When an implementation is intentionally clever, prefer this shape:

    simple semantic/reference implementation
                     |
           differential/property tests
                     |
          optimized production path

The reference path may live only in tests. Its purpose is to make correctness independently understandable.

## Debug versus release

Debug builds should aggressively check invariants where practical. Release hot paths may remove repeated checks after those invariants are proven and tested.

Do not treat debug assertions as an excuse for undocumented unsafe code.

## Performance changes

Before changing code marked PERF or HACK:

1. understand the documented invariant;
2. inspect the associated evidence;
3. preserve exact semantics and checksums/tests;
4. benchmark the replacement under the documented protocol;
5. update or retire the hack record based on evidence.

A simpler implementation is welcome if it preserves correctness and wins or matches the relevant measurement.

## Agent rule

AI can implement, review, benchmark, and document work. AI-generated reasoning that exists only in a chat is not sufficient project documentation.

If the current model disappears tomorrow, the repository must still explain why its non-obvious code exists.
