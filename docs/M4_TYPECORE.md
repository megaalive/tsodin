# M4-G5F8V — canonical primitive TypeId kernel

At M4-G5F8V, the native checker carried a compact primitive domain and
source-backed literal/flow facts but did not yet integrate the canonical pool.
This slice introduced the separate, tested `src/typecore` foundation.
M4-G5F8W1 and W2 subsequently connected primitive union annotations and
bounded `typeof` branch narrowing. General unions, structural assignability,
module resolution and full TypeScript compatibility remain unsupported.

## Upstream contracts and boundaries

- Source/harness inventory: Microsoft TypeScript Go snapshot
  [`6ad8c56`](https://github.com/microsoft/TypeScript/tree/6ad8c56f9b5a9bb910046c56059296311adc24ba).
- Pinned semantic authority: TypeScript **7.0.2** at
  [`1e4744d`](https://github.com/microsoft/TypeScript/tree/1e4744d68260a7cb91b62b12edc3f6a2187faaf1).
- Official `types/union/unionTypeReduction.ts` at the TS7 pin uses
  structural interface/call-signature reduction, which is **not implemented**
  here and must not be counted as conformance.
- Official `expressions/typeGuards/typeGuardOfFormTypeOfNumber.ts`
  exercises true/false branch narrowing of primitive unions, alongside
  objects/classes outside our supported type domain.

This kernel implements only the familiar primitive contracts for
`never`, `any`, `unknown`, broad `number`/`string`/`boolean`,
Boolean literals, and their normalized unions. An exact pinned TS7 oracle-only witness captures desired source constructs;
the narrower supported production path now has independent end-to-end
fixtures under `checker-union-annotations-*` and `checker-typeof-flow-*`.
The original union reduction test is not an official Tsodin conformance pass.

## Representation

- `Type_Id` is `distinct u32` and **pool-local** (except fixed built-ins).
  ID 0 is invalid; IDs 1–8 are never/any/unknown/number/string/boolean/true/false.
- A `Pool` owns one dense array of `Node` and a contiguous array of
  canonical sorted union constituents. No pointer-based type graph.
- `intern_union` flattens nested unions, removes `never` and duplicates,
  reduces `true | false` to `boolean`, applies the any/unknown absorption
  rules, and reuses a canonical union ID for any member order.
- Invalid references and unsupported narrowing fail closed without modifying
  the interned type store. `union_members` returns a borrowed view invalidated
  by future successful insertions.
- Normalization currently uses a temporary buffer and a linear scan of the
  type pool. This is a correctness/reference kernel, **not a claimed hot-path
  performance optimization**. Profile and add indexing only when real usage
  and memory-lifetime requirements justify it.

## Restricted relations and flow partition

`assignable` and `overlap` deliberately cover the primitive domain,
unions, the Boolean literal relation, and special any/unknown/never cases.
They are **not** full TypeScript structural assignability or the result of
a runtime equality expression.

`split_typeof` computes both partitions of the exact primitive domain:
e.g. `number | string | boolean` split on `typeof === "number"`
becomes `number` and `string | boolean`. Unknown/any inputs remain
unsupported rather than getting a fabricated complement. W2 consumes this
operation with explicit branch snapshots, assignment invalidation and joins
within its proven primitive-only subset.

## Evidence and next step

- `odin test src/typecore` covers canonical identity, nesting, Boolean
  reduction, special types, invalid input, assignability, overlap, and both
  `typeof` arms.
- Independent TypeScript 7.0.2 CLI projects
  `tests/oracle/typecore-union-contract-{valid,errors}` capture source
  acceptance/error behavior **as oracle-only fixtures**. They do not
  establish Odinian diagnostic parity or official conformance.
- W1 implemented primitive union annotations; W2 implements bounded
  `typeof` narrowing, assignment invalidation and union joins.
  See [W1](M4_UNION_ANNOTATIONS.md) and [W2](M4_TYPEOF_FLOW.md).
  The production checker still uses primitive fast-path arrays; canonical
  handles are opt-in only for files with union annotations.
- Public `tsodin check` and Pages performance claims remain disabled.
