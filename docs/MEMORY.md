# Memory Model

## Purpose

Memory layout and lifetime are architectural concerns in tsodin, not an afterthought.

Odin provides explicit allocators plus implicit context.allocator and context.temp_allocator. tsodin should use that control deliberately, while avoiding allocator cleverness where allocation is not actually a bottleneck.

## Lifetime-first design

Prefer allocating by lifetime rather than freeing individual compiler objects one by one.

Initial lifetime classes to evaluate:

    project / session
      - interned strings
      - stable module identity
      - canonical symbols/types that truly survive file versions
      - long-lived caches

    file / source version
      - tokens
      - syntax nodes
      - binder state
      - file-local indexes

    check / query
      - temporary substitutions
      - relation worklists
      - transient inference state

    worker scratch
      - temporary buffers
      - diagnostics construction
      - traversal stacks
      - short-lived sorting / lookup work

These are design hypotheses until real workloads validate them.

## Arena bias

Arenas are preferred where many objects share a lifetime.

Expected benefits:

- cheap bump allocation;
- bulk reset/destroy;
- low per-object metadata;
- predictable ownership;
- good spatial locality;
- fewer allocator calls.

Do not use an arena merely because Odin makes it convenient. A retained arena must have a clear lifetime boundary and measured or structural benefit.

## Context allocator policy

Subsystems may override context.allocator or context.temp_allocator for a bounded scope when that makes ownership simpler.

Do not rely on implicit context in a way that obscures lifetime.

A contributor should be able to answer:

- which allocator owns this value?
- how long is it valid?
- what invalidates it?
- can it escape this scope?
- when is the memory reset or destroyed?

## IDs versus pointers

Stable integer IDs are preferred for dense compiler stores when they improve compactness, serialization, invalidation, or cache behavior.

Pointers remain appropriate for tightly scoped arena-local traversal, proven hot paths, and APIs where pointer identity is part of the representation.

Do not convert everything to IDs or everything to pointers as ideology.

## Strings

String interning is expected to matter for identifiers, property names, module paths, and canonical textual keys.

The interner should eventually define lifetime, ID width, hashing, deduplication guarantees, worker model, invalidation policy, and memory accounting.

Avoid hidden string copies in hot semantic paths.

## Worker-local scratch

Parallel checking should prefer worker-local scratch/state where practical to reduce synchronization and ownership ambiguity.

No shared mutable allocator should be introduced casually into a hot path.

## Hot-loop rule

Some checker loops should be treated with a realtime-like mindset:

- no surprise allocation;
- no hidden resize;
- no accidental string construction;
- no unpredictable cleanup;
- reuse scratch buffers when useful.

This is not a blanket ban on allocation. It is a rule for code identified as hot.

## Debug invariants

Debug builds should check lifetime and representation assumptions aggressively where practical.

    when ODIN_DEBUG {
        assert(index <= table.mask)
        assert(is_power_of_two(capacity))
        assert(type_id != INVALID_TYPE_ID)
    }

Release code may rely on established invariants in hot paths.

## Measurement rule

Allocator changes must be evaluated with appropriate metrics, such as allocation count, allocated bytes, peak RSS, working set/cache behavior, wall time, retained memory after incremental rebuild, and reset/destroy cost.

A smaller allocation count is not automatically faster, and a smaller representation is not automatically faster.

The ts-fp packed-state experiment is a warning: reduced footprint can lose when decoding/manipulation cost dominates.

## Lifetime table

Once implementation begins, each major arena should be represented in a short table kept synchronized with code.

| Region | Owner | Contents | Reset boundary | May escape? |
|---|---|---|---|---|
| project | project | TBD | project close | within project |
| file | source version | TBD | file replacement | no |
| worker scratch | worker | TBD | query/batch | no |
