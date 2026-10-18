# PostBox

Open-source, local-first HTTP API client by **Uniqueone**. Android, Windows, Linux. MIT licence. English and Persian (full RTL).

> **Status: complete first draft, not yet compiled.** All planned phases are written, but the code has never been built or run (no Flutter SDK was available when it was written). Read `docs/PROJECT_STATUS.md` before relying on anything.

## Features

Requests with all methods, JSON/form/multipart/raw/GraphQL bodies, SSE and WebSocket; response inspector with pretty/raw/diff views; custom code editor; collections, favorites, history; environments and secret variables; Basic, Bearer, API key and OAuth 2.0 (PKCE); import cURL/Postman/PostBox/OpenAPI-JSON and export cURL/Postman/PostBox; assertions, chaining and a collection runner; six themes; command palette (Ctrl+K). No account, no telemetry, no sync.

## Get started

```
./tool/setup_platforms.sh     # generates android/windows/linux, patches the Android manifest
flutter pub get
dart format . && flutter analyze && flutter test
flutter run -d linux          # or windows / an Android device
```

Linux needs `libsecret-1-dev` to build and a keyring service at runtime. Fonts and icons are not bundled yet (`assets/fonts/README.md`).

## Documentation

`docs/` (English) and `docs/fa/` (فارسی): product spec, architecture, design system, security, testing, roadmap, status, editor, import/export, release, privacy policy, Play listing.

## Licence

MIT, see `LICENSE`. Third-party notices: `docs/THIRD_PARTY_NOTICES.md`.

---

# پست‌باکس (PostBox)

کلاینت متن‌باز و محلی‌محور HTTP از **Uniqueone** برای اندروید، ویندوز و لینوکس. مجوز MIT. فارسی (راست‌به‌چپ کامل) و انگلیسی.

> **وضعیت: پیش‌نویس کامل، هنوز کامپایل نشده.** همه فازها نوشته شده‌اند اما کد هرگز ساخته یا اجرا نشده است (هنگام نوشتن، Flutter SDK در دسترس نبود). پیش از هر اتکایی `docs/fa/PROJECT_STATUS.md` را بخوانید.

## قابلیت‌ها

درخواست با همه متدها، بدنه JSON/فرم/چندبخشی/خام/GraphQL، SSE و وب‌سوکت؛ بازرس پاسخ با نمای مرتب/خام/تفاوت؛ ویرایشگر کد سفارشی؛ مجموعه‌ها، علاقه‌مندی‌ها و تاریخچه؛ محیط‌ها و متغیرهای رمز؛ Basic، Bearer، کلید API و OAuth 2.0 (PKCE)؛ درون‌ریزی cURL/Postman/PostBox/OpenAPI-JSON و برون‌بری cURL/Postman/PostBox؛ ادعاها، زنجیره‌سازی و اجراگر مجموعه؛ شش تم؛ پالت فرمان (Ctrl+K). بدون حساب کاربری، تله‌متری و همگام‌سازی.

## شروع

```
./tool/setup_platforms.sh
flutter pub get
dart format . && flutter analyze && flutter test
flutter run -d linux
```

برای ساخت در لینوکس به `libsecret-1-dev` و هنگام اجرا به یک سرویس keyring نیاز است. فونت‌ها و آیکون‌ها هنوز بسته‌بندی نشده‌اند.

## مستندات

پوشه `docs/` (انگلیسی) و `docs/fa/` (فارسی).
