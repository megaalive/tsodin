# Odin blue-glass visual previews

These two preview pages exist **only on the `preview/odin-blue-glass-variants` branch** until the user chooses a direction. The GitHub Pages site on `main` is unchanged.

- `preview/soft/index.html`: Blue Glassy Soft — brighter Odin-inspired blue, comfortable contrast, restrained soft glow and translucent glass.
- `preview/neon/index.html`: Blue Neon Odin — saturated electric blues, stronger edge lighting, glow and glass.

Both pages use the existing root `styles.css`, `app.js` and `lib/observatory-core.mjs`. They load the same frozen archive data (a copy is placed below each preview for unchanged relative asset resolution). The only differences are supplemental theme CSS and a preview-only theme switcher.

**Publishing note:** GitHub Pages is currently configured on `main`. Do not merge this preview PR without the user's visual approval. No benchmark or scientific claims have been changed.

A public preview CDN may show these branch files via:

- `https://raw.githack.com/megaalive/tsodin/preview/odin-blue-glass-variants/preview/soft/index.html`
- `https://raw.githack.com/megaalive/tsodin/preview/odin-blue-glass-variants/preview/neon/index.html`

GitHub Pages does not provide separate branch previews automatically; raw.githack.com is an external read-only renderer for the public branch, *not* an official tsodin deployment. If it fails, use the files attached to the preview CI workflow.
