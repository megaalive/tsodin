# Research transfer: ts-fp to tsodin

This is a decision record, not a new benchmark classification.

## Separate historical evidence from the later optimization lab

1. The original ts-fp Free Pascal experiment was closed without a successful product-level TypeScript checker. Historical benchmark decisions remain unchanged.
2. The repository's final-exploration-decision.md selected Odin as the **next language for research** despite a prospective `PRAGMATIC_UNSTABLE` global classification. It did not say Odin was universally faster.
3. After that closure, ts-fp hosted a bounded Odin hotpath optimization lab P1–P6. The final P6 result was `HOTPATH_P6_STRONG`, with the runner's literal `projectAction: STOP_P1_AND_REVIEW`. That lab is complete; no P7.

P6 source: megaalive/ts-fp at 8e374b388e57fca8b61c359ec4a6dbb792f5c6fe. Final documentation: tools/benchmark/odin-hotpath-p6.md on ts-fp main 6306143660eac352fdbfe37be60f41f5b9e6b740.

| Checksum-equivalent synthetic kernel | Median Odin/Rust wall |
|---|---:|
| K1 classification | 0.633695809x |
| K2 flat hash | 0.944804817x |
| K3 relation cache | 0.926505222x |
| Geometric mean | 0.821656449x |

All three passed the lab's 5% relative MAD, split-half drift, and order-bias gates. The P6 host was Xeon W-1350P Ubuntu 24.04 on WSL2, with CPU 0 pinned. Stable paired wall time is primary; virtualized PMU counters are secondary. Do **not** retroactively relabel the earlier unstable run, or describe P6 as whole-compiler performance.

Valid conclusion: on these pinned checksum-equivalent kernels, the optimized Odin candidate was stably faster than the Rust reference in wall time. That evidence justifies proceeding with the Odin compiler project.

Invalid conclusions: Odin beats Rust generally, is already faster than tsgo, or will definitely meet the real-project G2 target.

## Transferable investigation leads, not automatic implementations

- Branch-light classification can reduce expensive mispredictions even when instruction count increases.
- Compact u32 hash values may improve locality when cardinality permits.
- Compact packing is not automatically fast: the 2-bit relation state lost to a u8 representation.
- Raw views can remove checked-access overhead but demand explicit indexing invariants.
- Specialization can avoid extra widening/control work.
- Eliminating zero-fill can help a proven write-before-read backing array.

The new project must remeasure each optimization against real TypeScript inputs. More synthetic P7 tuning is out of scope.

## Sources

- https://github.com/megaalive/ts-fp/blob/main/ts-fp-plan-v3.md
- https://github.com/megaalive/ts-fp/blob/main/tools/benchmark/final-exploration-decision.md
- https://github.com/megaalive/ts-fp/blob/main/tools/benchmark/odin-hotpath-p6.md
- https://github.com/megaalive/ts-fp/commit/6306143660eac352fdbfe37be60f41f5b9e6b740
