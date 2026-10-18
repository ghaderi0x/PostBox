# انتشار

**هیچ‌کدام از این مراحل اجرا نشده است.** روی دستگاه واقعی اجرا و نتیجه را در `PROJECT_STATUS.md` ثبت کنید.

## تنظیم نخست

```
./tool/setup_platforms.sh
flutter pub get
dart format . && flutter analyze && flutter test
```

## اندروید

شناسه برنامه `com.uniqueone.postbox`. گوگل پلی از ۲۰۲۶-۰۸-۳۱ برای برنامه‌ها و به‌روزرسانی‌های جدید هدف API 36 را می‌خواهد (در ۲۰۲۶-۱۰-۱۸ بررسی شد؛ پیش از انتشار در Play Console دوباره بررسی کنید). در `android/app/build.gradle.kts` مقدارهای `minSdk = 24` و `targetSdk = 36`، تنظیم امضا از `key.properties` و فعال‌سازی R8 (`isMinifyEnabled = true`، `isShrinkResources = true`) را بگذارید؛ قطعه کد کامل در نسخه انگلیسی `docs/RELEASE.md` است.

کلید بارگذاری: `keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`. فایل `key.properties` و keystore را **هرگز commit نکنید** (در `.gitignore` هستند). ساخت: `flutter build appbundle --release`. نسخه release را روی دستگاه یا شبیه‌ساز واقعی آزمایش کنید (حافظه امن، بازگشت OAuth، فارسی، کد کوچک‌شده با R8).

متن فروشگاه و خلاصه ایمنی داده در `docs/fa/PLAY_STORE.md`؛ سیاست حریم خصوصی در `docs/fa/PRIVACY_POLICY.md` (باید روی نشانی عمومی منتشر شود).

## ویندوز (فقط روی ویندوز)

`flutter build windows --release` و سپس کامپایل `packaging/postbox.iss` با Inno Setup 6. روی ماشین تمیز آزمایش کنید.

## لینوکس (فقط روی لینوکس)

`flutter build linux --release`، سپس `./packaging/build_deb.sh` و `./packaging/build_appimage.sh`. اجرا نیاز به `libsecret-1-0` و یک سرویس keyring دارد.

## CI

`.github/workflows/ci.yml` برای هر push فرمت، تحلیل و آزمون را اجرا و هر پلتفرم را روی runner خودش می‌سازد.

## تعریف «آماده انتشار»

همه فایل‌های بالا ساخته **و** روی پلتفرم خود آزموده شده باشند و نتیجه هر پلتفرم ثبت شده باشد.
