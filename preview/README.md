# Odin blue-glass theme previews

The two candidate designs are published on **GitHub Pages under /preview/** so the main Observatory homepage remains unchanged until visual approval.

- Comparison landing page: https://megaalive.github.io/tsodin/preview/
- Blue Glassy Soft: https://megaalive.github.io/tsodin/preview/soft/
- Blue Neon Odin: https://megaalive.github.io/tsodin/preview/neon/

These preview pages are static, share the existing root `styles.css`, `app.js` and Odin benchmark archive, and add only supplemental theme styles. Benchmark values and checker implementation are unchanged.

Both previews contain a bottom theme switcher. Preview pages remain separated from the homepage; a selected design should eventually be applied to root styling in a **separate change**, not by silently replacing the homepage.

**Deployment requirement:** GitHub Pages configured to use `main / (root)`. The PR must pass preview integrity and Odin CI before merging. A published preview needs its files in `main` because Pages is not serving this branch automatically.

No external raw.githack renderer is required.
