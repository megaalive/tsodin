# Audit R2 — stage-dump UTF-16 mapping probe

Source reference baseline: `7b82fdf7b0703f809e7d5c9093c3c9e6addc4b5c`,
pinned Odin `dev-2026-10` with `-o:speed`.
Baseline dedicated Actions run: `37953755131` on candidate `b141806`.
Nine raw samples per one-line source, after two warmups:
128 declarations: 5.97 ms; 256: 13.30 ms; 512: 39.28 ms; 1024:
135.88 ms (all full CLI dump subprocess medians).
The 512 -> 1024 ratio is ~3.46x. This is scoped evidence for an
unfavorable full-dump scaling shape, NOT isolated UTF-16 CPU cycles.

This patch adds dump-only scalar-boundary-aligned UTF-16 checkpoints about
every 256 bytes. Queries binary-search a checkpoint then invoke the original
UTF-8-to-UTF-16 reference decoder on at most about 256 bytes. Out-of-range
and continuation-byte offsets remain invalid. The source snapshot, generic
`source_position`, dump/3 output structure, and public `tsodin check`
behavior remain unchanged.

The dedicated workflow builds the frozen baseline and candidate at the same
pinned Odin revision on the same runner. AB/BA samples are interleaved, the
full serialized output must have byte-identical SHA256 within and across both
binaries, and independent strict TextDecoder validates all token/node UTF-16
spans. Exact source reference unit tests exercise all offsets around a scalar
crossing a 256-byte boundary and Unicode line separators.

## Same-runner result — 9 October 2026

GitHub Actions: [37954527513](https://github.com/megaalive/tsodin/actions/runs/37954527513)
on feature revision `f93f64d`. Baseline is pinned at `7b82fdf`.
Each lane uses the same Ubuntu 24.04 runner and Odin `-o:speed` toolchain,
with two warmups and nine rotated/reversed full-process samples per size.
Median wall-time is inclusive of startup, parsing, checking and JSON output.

| One-line declarations | Base ms | Indexed ms | Indexed/base |
|---:|---:|---:|---:|
| 128 | 6.5606 | 4.9171 | 0.7495 |
| 256 | 15.0385 | 7.6647 | 0.5097 |
| 512 | 43.4505 | 13.1807 | 0.3033 |
| 1024 | 146.5186 | 24.1927 | 0.1651 |

All output byte checksums match baseline exactly for each input; every
scanner/AST token position independently matches strict JavaScript TextDecoder,
and native tests compare every possible byte offset across a multibyte
scalar straddling a checkpoint to the original `source_position` function.
Full raw samples and checksums are preserved in the `dump-span-probe`
workflow artifact (retention 21 days). No measurements were discarded.

**Decision:** retain the dump-only index: roughly 83.5% lower full-process
wall-time at 1024 declarations, about 6.06x higher observed throughput on
this limited workload. This is NOT an end-to-end TypeScript benchmark, a
published language ranking, a claim about a general source-position path,
or a promise of identical ratios on a different machine.
