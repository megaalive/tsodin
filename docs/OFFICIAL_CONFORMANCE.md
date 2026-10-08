# Official TypeScript tests: adoption policy

The official native Go compiler and test harness now live in
microsoft/TypeScript. microsoft/typescript-go was staging and is archived.

TypeScript compiler and conformance tests exercise diagnostics,
options and emit baselines; the language-service Fourslash suite is
a later milestone. The official workflows use npx hereby test and
npx hereby validate, but running those only checks upstream, not tsodin.

C0: Compare syntax diagnostics and positions for a pinned subset.
C1: Compare end-to-end source-to-diagnostics on projects that tsodin
actually supports. C2: Expand to the full applicable compiler and
conformance corpus, maintaining version-scoped evidence.

Every report must distinguish passed, failed, unsupported,
out-of-scope and not-run cases. Never count skipped cases as passes.

Pin the exact official upstream revision and preserve its test harness
directives. Do not copy the whole corpus or silently relax baselines.
Upstream cases may expand into multiple files and compiler options.

Until the binder/checker are operational, TypeScript CLI acceptance
is independent reference evidence, not diagnostic parity. Emit-only
tests and Fourslash are excluded from early checker gates.

When TypeScript 8 appears, add its separate profile and fixture gates.
Keep TS7 evidence intact rather than replacing it.
