# Compiler Observatory — live public project status

Site: https://megaalive.github.io/tsodin/

The Observatory is a minimal, static HTML/CSS/vanilla JavaScript website using the approved Odin Blue Glassy Soft theme.

## Current data, not old experiments

The homepage now visualizes **only current tsodin data** from GitHub's unauthenticated public REST API on page load and when the visitor presses **Refresh data**:

| Panel | Public endpoint | Interpretation |
| --- | --- | --- |
| Latest main commit and recent history | `/repos/megaalive/tsodin/commits?sha=main&per_page=5` | Most recent GitHub response; not a long-lived cached fixture |
| Workflow runs / pinned Odin CI | `/repos/megaalive/tsodin/actions/runs?branch=main&per_page=30` | Exact run state and SHA. Only the run whose `head_sha` matches the fetched main SHA can represent CI for that HEAD |
| Source file inventory / oracle fixture counts | `/repos/megaalive/tsodin/git/trees/main?recursive=1` | File existence only; neither implementation completeness nor parity is inferred |

No backend, npm install, authentication credential, tracking script, local persistent cache or benchmark-data archive is used. The API is subject to availability, CORS and unauthenticated GitHub rate limits; when unavailable the page displays **UNAVAILABLE/PARTIAL**, and the affected panel shows no invented result. Refresh is manual; no background polling. Timestamps explicitly indicate the last completed fetch, not a continuous live stream.

The source map uses conservatively named conventional directories for scanner/parser/binder/checker detection. No matching directory means `NOT DETECTED`, not that no implementation exists anywhere. The CLI and UTF-16 mapper are separate source-presence checks.

### Evidence boundary

- The repository is currently a bootstrap/early development project; CLI type checking is not implemented.
- Oracle project directories do not prove diagnostic parity, and successful build/tests do not prove checker functionality.
- Real TypeScript project performance stays `Not measured` until equivalent implementation, corpus and compatibility gates exist.
- Shared GitHub runners are not a suitable source of authoritative speed comparisons.
- The historical language-selection exploration remains in its separate private source repository; no P1–P6 figures, cloned samples or links are included in this public website or its data.

### Source X-Ray

This is an independent JavaScript UTF-8 byte vs UTF-16 code-unit position reference, not Odin scanner or checker execution. The source reference lives in `src/source/utf16.odin`. Intra-code-point byte offsets are rejected. Lone surrogate input is normalized by the browser encoder and labeled accordingly.

## Maintenance

- Homepage: `index.html`, `styles.css`, `soft-glass.css`, `live.css`, `app.js`.
- Pure helpers: `lib/observatory-core.mjs`.
- Run offline smoke: `node tools/observatory/check.mjs`; validate syntax with `node --check app.js`.
- CI: `.github/workflows/observatory.yml`, plus existing pinned Odin CI.
- Published via GitHub Pages `main / (root)`; no separate backend or deployment framework.
- Mobile minimum targets 390px and 430px with no document overflow; honor reduced-motion preferences.
- Historical `/preview/` pages redirect to the canonical Observatory after the Soft Glassy selection.

## Future

When the actual scanner and parser/checker are implemented, the public site may show their verified source traces, real oracle parity and separately measured end-to-end workload results; the current Observatory must not display these as done before such evidence exists.
