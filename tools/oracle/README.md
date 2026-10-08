# Versioned TypeScript CLI oracle captures

This tool observes a pinned public TypeScript CLI, not the tsodin scanner or
an alternative JS compiler API. It makes **no** product compatibility or
performance claim.

- Profile registry: `tests/oracle/profiles.json`.
- Default registered profile: `ts7`, TypeScript `7.0.2`, exact npm package,
  CLI executable, upstream revision, and invocation arguments.
- Fixture manifest: `tests/oracle/manifest.json` (still pinned to TS7).
- CLI invocation: `node tools/oracle/profile.mjs npmSpec ts7`.
- Registry smoke: `node tools/oracle/profile.test.mjs`.
- Capture: `TSODIN_ORACLE_PROFILE=ts7 TSODIN_TSC=/path/to/tsc node tools/oracle/capture.mjs`.
- CI uploads `oracle-ts7-raw` for review (14 days); these captures are
  transient, not committed goldens.

`scanner-ascii` is a CLI **acceptance** fixture for the supported basic lexical
shape. Odin scanner unit tests cover the corresponding subset. The CLI does
not expose scanner token streams, so CLI acceptance cannot be mislabelled
token parity; unknown token forms remain explicit unsupported errors.

When TS8 becomes real, add a separately pinned profile and compatible corpus.
Keep the TS7 baseline and its gates. Update the matrix only after the new
profile's exact executable and CLI flags are independently verified.
Do not dynamically install `latest`; failures and incompatible options are
separate observable regressions, not a reason to silently downgrade.

## Supplemental lexical witness

`src/scantrace` emits Odin token ordinals + UTF-16 spans for real fixture
files. `tools/oracle/compare-scanner.mjs` compares these with a pinned
`@typescript/typescript6@6.0.2` API scanner on two accepted sources,
including CRLF and a supplementary Unicode character inside trivia.
The TypeScript 7 CLI's project-level acceptance is a separate CI gate.
Neither comparison is token parity with the TypeScript 7 native compiler.
The auxiliary tool is invoked only in the oracle workflow and adds no
runtime dependency to tsodin itself.
