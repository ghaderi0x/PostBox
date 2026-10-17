# Design System

- **Tokens:** semantic only (`surfaceBase`, `textPrimary`, `accent`, `danger`, method colors). Widgets use `context.colors`.
- **Themes (target):** PostBox Orange (default), Midnight, Arctic, Emerald, Violet, High Contrast. Implemented: Orange light and dark.
- **Fonts:** Vazirmatn (Persian), Inter (UI), JetBrains Mono (code). Not yet bundled; add files under `assets/fonts/` with their OFL licences, then declare in `pubspec.yaml`.
- **Icons:** one library only; no Unicode symbols as icons.
- **Layout:** desktop sidebar + workspace + inspector; Android compact navigation and bottom sheets.
- **Quality gate per screen:** narrow/wide, light/dark, EN/FA, overflow, text scale, keyboard, all states.
- **Logo:** `assets/branding/logo.svg`, an original simple mark, intentionally easy to replace.
