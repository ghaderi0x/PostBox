# Design System

## Tokens

Widgets use semantic tokens through `context.colors` (`PostBoxColors`): surfaces, border, text roles, accent and its foreground, success/warning/danger, method colors, and syntax colors. No raw hex values appear in widgets.

## Themes

Six presets, each with light and dark variants: **PostBox Orange** (default), **Midnight**, **Arctic**, **Emerald**, **Violet**, **High Contrast**. Customization: light/dark/system, preset accent or a custom accent colour, surface style (raised with borders, or flat), density, text scaling (80% to 160%), reduced motion, editor appearance. All persist.

**Contrast:** the palettes were chosen with WCAG ratios computed in a script (text and secondary text at least 4.5:1 on both surfaces, High Contrast 7:1, accent foreground at least 4.5:1, semantic and syntax colours at least 4.5:1). `test/ui/design_contrast_test.dart` re-checks all of this in Dart. A custom accent colour can reduce contrast; the foreground colour on it is chosen automatically for readability.

## Typography roles

Page title, section heading, body, secondary label, form label, method badge, URL, code (size from Settings), error, status code, timing. They are defined once in `core/design/typography.dart`.

Fonts: Inter (UI), Vazirmatn (Persian), JetBrains Mono (code). **Not bundled yet**; see `assets/fonts/README.md`. The theme already names them with fallbacks so declaring the files is enough.

## Icons

One library only: Material Icons. No Unicode symbols are used as icons. The editor's `.*` and `Aa` toggles are text labels, as in most editors.

## Layouts

- **Desktop (>= 900 px):** top bar with environment selector, command palette, import/export and settings; resizable sidebar (collections and history); tab strip; resizable request/response split that can be stacked or side by side.
- **Phone (< 900 px):** bottom navigation Library / Request / Response, tab switcher in a bottom sheet, wrapped URL bar, send moves to the response page. Dialogs and sheets avoid the keyboard through the default scaffold behaviour.

## Quality gate

Required before a screen is called done: narrow and wide, light and dark, English and Persian, overflow, text scaling, keyboard navigation, all states (loading, empty, error, success, disabled), every control works.

**What was actually checked for this version:** contrast ratios (computed), and widget tests that pump the desktop layout, the phone layout and Persian/RTL with a 1.4 text scale and assert that no layout exception is thrown (written, **not yet run**). **Not checked:** screenshots, visual polish, real-device keyboard behaviour, golden images. Expect to adjust spacing after the first look.

## Logo and icon

The logo is `assets/branding/logo.png` (1024 px, transparent corners). In the app it is always drawn by `BrandLogo` (`lib/ui/widgets/brand.dart`): splash screen, header, menu, About and onboarding. Derived files in `assets/branding`: `logo_256.png` (in-app), `logo_512.png` (Linux icon, native splash), `app_icon.ico` (Windows installer), `logo_foreground.png` and `logo_background.png` (Android adaptive icon). Launcher icons are generated with `dart run flutter_launcher_icons` and the Android native splash with `dart run flutter_native_splash:create` (both configured in `pubspec.yaml`).

**Digits:** Persian digits are on by default in every language. They are drawn by `PostBoxDigits`, a 10-glyph font derived from Vazirmatn that is placed first in the font list, so every number in normal UI text shows Persian shapes while code, URLs and JSON keep Latin digits. Turn it off in Settings > Language and accessibility.

**Header:** desktop header = logo and name, workspace chip, command-palette search field with its shortcut, environment picker, then import/export, theme toggle and settings buttons. Phones use a compact app bar with the logo, the request name and method, the environment chip and search.

**Settings** are split into eight groups (Appearance, Language and accessibility, Requests, Editor, Data and privacy, Keyboard, Developer, About): a two-pane layout on wide windows, one page per group on phones.
