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

Record the final measured ratios only after the workflow succeeds. This
is diagnostic stage-dump measurement, NOT an end-to-end TypeScript benchmark
or a public language performance comparison.
