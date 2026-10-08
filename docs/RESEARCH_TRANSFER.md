# Architectural decision: build tsodin in Odin

The earlier language-selection experiments were exploration in a **different repository with a different objective**. They are not measurements of tsodin and do not provide a compiler performance baseline.

The present project starts from a clean Odin-native architecture:
- correctness and pinned TypeScript 7 diagnostic oracle before speed claims;
- UTF-8 internal source, TypeScript-compatible UTF-16 diagnostic positions;
- explicit lifetime and identity boundaries;
- a narrow real-project source-to-diagnostics vertical slice before expanding conformance;
- end-to-end performance comparisons only after the relevant checker work is actually implemented with comparable semantics.

This document intentionally does **not** republish the historical experiment's benchmark tables, code, links or methodology. Those records remain in their original repository. The observable evidence for tsodin itself begins with its public commits, source tree, CI and future real-project checker tests.

See [Execution](EXECUTION.md), [Oracle contract](ORACLE.md), and [Benchmarking doctrine](BENCHMARKING.md).
