# Architecture

## Goal

tsodin is a TypeScript checker/compiler designed for correctness, maintainability, and unusually high performance.

The architecture should exploit Odin's control over representation, allocation, and code shape without turning the repository into opaque benchmark code.

Guiding rule:

> **Make semantics obvious. Make data compact. Make hot paths ruthless.**

## Initial pipeline

    Source Text
       |
    Scanner / Tokenizer
       |
    Parser
       |
    Syntax representation
       |
    Binder / Symbols
       |
    Module graph + resolution
       |
    Checker
       |
    Type relation / generic instantiation / caches
       |
    Diagnostics
       |
    Optional emit

The exact boundaries are not frozen. They must evolve from correctness, profiling, and TypeScript semantics rather than framework habits.

## Odin-native design

tsodin is not a transliteration of tsgo, ts-rs, the TypeScript compiler, or any other implementation.

Other compilers are useful as semantic references, compatibility oracles, benchmark competitors, and sources of test cases. Their internal object models, ownership patterns, control flow, and language-specific workarounds are not architectural templates.

When an existing implementation is written around Go, Rust, C++, or JavaScript constraints, redesign the problem for Odin instead of reproducing those constraints.

Prefer Odin-native choices when they improve the design, including:

- explicit allocators and lifetime-scoped arenas;
- `context.allocator` and `context.temp_allocator` where ownership remains clear;
- compact distinct integer IDs;
- dense arrays and data-oriented layouts;
- slices for ordinary checked access and multi-pointers for justified hot paths;
- explicit procedure specialization when genericity hides cost;
- Odin's native concurrency, SIMD, and platform facilities when measured and appropriate.

Semantic compatibility may be ported. Implementation accidents should not be.

## Design biases

### Stable IDs over pointer graphs

Prefer explicit handles where they improve locality and lifetime control.

    Node_Id   :: distinct u32
    Symbol_Id :: distinct u32
    Type_Id   :: distinct u32
    Module_Id :: distinct u32

The exact widths are not promises. Widths must be justified by reachable cardinality, failure behavior, and measurement.

### Data before instructions

Optimization order should normally be:

    algorithm
      -> data representation
      -> lifetime / allocation
      -> locality
      -> control flow
      -> generated machine code
      -> SIMD / architecture-specific work
      -> handwritten assembly only when still justified

Assembly is a last tool, not the project's personality.

### Explicit cost

Prefer designs where allocation, copying, interning, cache lookup, and expensive semantic work are visible.

Avoid abstractions that make a hot operation look cheap when it is not.

### Semantic units, not enterprise layers

Functions and files should follow meaningful compiler operations such as:

    scan_token
    parse_expression
    bind_declaration
    resolve_symbol
    resolve_module
    check_call
    instantiate_signature
    relate_types
    is_assignable

Do not introduce generic provider/factory/manager layers without a demonstrated need.

A hot function may remain relatively large when splitting it would make control flow, invariants, or generated code worse.

## Reference and optimized implementations

For semantics that become difficult to inspect after optimization, keep a simple oracle when practical.

Good candidates include type relations, substitution/instantiation, hash-table behavior, incremental invalidation, and scanner classification.

The optimized path must be testable against the oracle with differential or property-based tests.

## Incremental architecture

Incrementality should be designed early rather than retrofitted after a monolithic checker exists.

Expected first-class concepts include:

- stable module/file identity;
- dependency and invalidation graph;
- per-file/source-version lifetime;
- reusable canonical type/symbol state where valid;
- explicit cache ownership and invalidation;
- deterministic rebuild behavior.

## Compatibility

TypeScript compatibility is not a performance knob.

If tsodin intentionally matches a surprising TypeScript behavior, mark the reason with COMPAT and point to a conformance test or documented behavior.

Never simplify strange compatibility behavior without proving that the semantic contract remains correct.

## Non-goals

- architecture astronautics;
- framework-shaped compiler design;
- hiding expensive work behind generic APIs;
- maximizing generated line count;
- treating benchmark tricks as product architecture;
- claiming compatibility or speed that has not been reproduced.

## Change rule

A major architecture change should be explainable in terms of at least one of:

- clearer semantics;
- stronger correctness;
- better lifetime model;
- smaller data;
- better locality;
- lower measured cost;
- simpler contributor mental model.

If none applies, the change probably does not belong.
