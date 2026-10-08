# Compiler Observatory — public static site

Site path: `/` on the `main` branch for https://megaalive.github.io/tsodin/ (when GitHub Pages uses `main / (root)`).

## Purpose

The website is a public-facing **engineering instrument**, not a marketing performance scoreboard:

- Benchmark Arena: P1–P6 archived synthetic kernel ratios against one Rust reference.
- Research Log: why each experiment was retained, rejected or withheld from global classification.
- Source X-Ray: independent browser-side Unicode visualization demonstrating UTF-8 byte vs UTF-16 unit positions.
- Engineering Progress: explicitly dated status snapshot; no false live metrics or checker compatibility claims.

It is deliberately built with static HTML, CSS, vanilla browser JavaScript and one local JSON data file. No package install, bundled framework, external script, web service, analytics, tracking or live API is needed.

## Evidence and provenance

`data/observatory.json` is an explicit, reviewable snapshot derived from the closed `megaalive/ts-fp` hotpath laboratory:

- historical early selection: `tools/benchmark/final-exploration-decision.md` (separate research decision);
- post-closure P1–P6 source records: `tools/benchmark/odin-hotpath-pN.md`;
- P6 winner: `HOTPATH_P6_STRONG`, with literal `projectAction: STOP_P1_AND_REVIEW`;
- authoritative P6 candidate `8e374b388e57fca8b61c359ec4a6dbb792f5c6fe`;
- archive final `6306143660eac352fdbfe37be60f41f5b9e6b740`;
- checksum parity, paired wall observations and stability limits per the pinned protocol.

These are **synthetic** results. The website must never rephrase P6 as an end-to-end TypeScript checker win. P3 has a failed global stability gate, so even its calculated display geomean is non-qualifying. The source of truth remains the archived repository and raw evidence, not a manually edited chart.

The project-progress section is a static snapshot dated **8 October 2026**. Updating it requires reviewing actual `tsodin` main/CI state. Status labels are categorical; M1 has no invented numeric completion percentage.

## Interactive Source X-Ray contract

The browser visualization is derived independently from Unicode rules using `TextEncoder` and JavaScript code-point iteration. It is **not the Odin implementation**. It shows byte-prefix boundaries and UTF-16 offsets, including intentionally invalid offsets inside multibyte scalars, and explicitly warns when a lone surrogate is normalized by the browser encoder.

The actual Odin reference code lives in `src/source/utf16.odin`. No browser-executed scanner, AST viewer, or type checker should appear until a real comparable implementation exists.

## Maintenance / publishing

- Edit `index.html`, `styles.css`, `app.js`, `lib/observatory-core.mjs` and `data/observatory.json`.
- Run: `node tools/observatory/check.mjs`
- Syntax-check: `node --check app.js` and `node --check lib/observatory-core.mjs`.
- GitHub Actions `Observatory smoke` checks this on relevant PRs/main pushes.
- Publish via GitHub Pages `main / (root)`; no deploy workflow needed for that Pages mode.
- Preserve mobile reading at 390px and 430px; ensure long input/labels do not cause document overflow.
- Respect reduced-motion and keyboard access.
- Keep accurate dated evidence, working source links and no auto-generated benchmark numbers from shared CI runners.

## Next increments

1. Add actual frozen TypeScript 7 diagnostic goldens (not just captured CI artifacts).
2. When M1 scanner exists, expose a deterministic exported scan-trace fixture with exact source SHA and revision.
3. Once the first real checker vertical slice exists, add its own build-generated evidence and comparison lanes, distinctly separated from P6 synthetic history.

Do not fake incomplete compiler pipeline stages to make the visual more impressive.
