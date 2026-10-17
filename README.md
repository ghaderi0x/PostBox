# PostBox

Open-source, local-first HTTP API client by Uniqueone. Android, Windows, Linux. MIT.

**Status: early scaffold (v0.1.0).** Only the design tokens and the core HTTP engine exist, and they have not yet been run through `flutter analyze`/`flutter test`. See `docs/PROJECT_STATUS.md`.

## Get started
```
flutter create --org com.uniqueone --project-name postbox --platforms android,windows,linux .
flutter pub get
flutter test
flutter run
```
Linux builds need `libsecret-1-dev` (used for secret storage).

Docs: `docs/` (English), `docs/fa/` (فارسی).

---

# پست‌باکس

کلاینت متن‌باز و محلی‌محور HTTP از Uniqueone برای اندروید، ویندوز و لینوکس. مجوز MIT.

**وضعیت: اسکلت اولیه (۰٫۱٫۰).** فقط توکن‌های طراحی و هسته موتور HTTP وجود دارد و هنوز با `flutter analyze` و `flutter test` اجرا نشده است. جزئیات در `docs/fa/PROJECT_STATUS.md`.
