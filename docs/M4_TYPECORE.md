# M4-G5F8V — canonical primitive TypeId kernel

The native checker currently carries a compact primitive domain and source-backed
literal/flow facts. It has **not** gained general unions, type annotations,
structural assignability, `typeof` parsing, module resolution, or full TypeScript
compatibility. This slice introduces the separate, tested `src/typecore`
representation on which those capabilities can be implemented.

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
Boolean literals, and their normalized unions. An exact pinned TS7 witness
demonstrates the desired accepted and rejected source constructs. Tsodin
cannot yet run that witness through its own parser/checker.

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
unsupported rather than getting a fabricated complement; joins/assignments
must later use the checker flow model and real source locations.

## Evidence and next step

- `odin test src/typecore` covers canonical identity, nesting, Boolean
  reduction, special types, invalid input, assignability, overlap, and both
  `typeof` arms.
- Independent TypeScript 7.0.2 CLI projects
  `tests/oracle/typecore-union-contract-{valid,errors}` capture source
  acceptance/error behavior **as oracle-only fixtures**. They do not
  establish Odinian diagnostic parity or official conformance.
- Next vertical slice: parser/binder support for `typeof` and primitive
  union annotations, followed by narrowed assignments and joins under
  pinned differential assertions. Only then consider replacing the
  production checker's existing primitive arrays with canonical handles.
- Public `tsodin check` and Pages performance claims remain disabled.
