# ماتریس قابلیت‌ها در برابر فهرست کارهای اصلی

فهرست کارهایی که فرستادید (فازهای ۰ تا ۸؛ متن چسبانده‌شده وسط فاز ۸ قطع شده بود) با آنچه در مخزن نوشته شده مقایسه شده است. وضعیت‌ها: **انجام‌شده** = پیاده‌سازی شده و با تست‌های اجراشده پوشش داده شده (برای رفتارهای فقط-UI: بررسی نوع در برابر Flutter 3.35.7 اما اجرا نشده)؛ **ناقص** = با محدودیت مستند کار می‌کند؛ **ردشده** = عمداً ساخته نشده، دلیل ذکر شده. آنچه اجرا شد و نشد در `PROJECT_STATUS.md` است.

خلاصه: ۳۰ انجام‌شده، ۱۴ ناقص، ۲ ردشده (با دلیل)، ۰ انجام‌نشده از ۴۶ مورد دسته‌بندی‌شده.

| فاز | مورد | وضعیت | توضیح |
|---|---|---|---|
| P0 | Competitor research, feature matrix, complaint database | ناقص | پژوهش با منبع و تاریخ در `docs/COMPETITOR_RESEARCH.md` انجام شد (Postman، Insomnia، Bruno، Hoppscotch). پایگاه شکایت‌ها هنوز نیست؛ به بررسی منظم و بزرگ‌تر ردیاب‌های issue نیاز دارد. |
| P0 | PRD, MVP, acceptance criteria, benchmarks | ناقص | مشخصات محصول و الزامات امنیتی هست؛ بنچمارک اندازه‌گیری‌شده و PRD رسمی نیست. |
| P1 | Android, Windows, Linux | انجام‌شده | برای هر سه نوشته شده؛ هیچ‌کدام هنوز ساخته یا آزموده نشده. |
| P1 | iOS/macOS-ready architecture | ناقص | کد خاص پلتفرم جز dart:io، حافظه امن و app links نیست؛ بررسی نشده. |
| P1 | Clean architecture, DI, Bloc/Cubit, repository interfaces | ناقص | پوشه‌های قابلیت، تزریق سازنده و رابط repository هست؛ جداسازی domain/data همه‌جا دقیق نیست. |
| P1 | FFI / native engine | ردشده | استفاده نشده. `dart:io` نیازهای فعلی را برآورده می‌کند و هیچ اندازه‌گیری سودی نشان نداده؛ موتور FFI ساخت بومی جداگانه برای هر پلتفرم می‌خواهد. فقط با بنچمارک بازنگری شود. |
| P2 | Design system, themes, accent, density, persisted | انجام‌شده | شش تم، رنگ دلخواه، تراکم، مقیاس متن، کاهش حرکت. |
| P2 | Premium look (soft cards, floating nav, onboarding) | انجام‌شده | در نسخه ۰٫۳٫۰ اضافه شد. جلای بصری هنوز نیاز به بررسی شما روی دستگاه دارد. |
| P2 | Resizable panels, multiple tabs, command palette, context menus | انجام‌شده | نوار کناری و تقسیم قابل تغییر، زبانه‌ها، Ctrl+K، منوها. |
| P2 | Draggable/reorderable tabs | انجام‌شده | نوار تب دسکتاپ با `ReorderableListView`؛ منطق ترتیب با تست پوشش داده شده. خود حرکت کشیدن بررسی نوع شده اما روی دستگاه اجرا نشده. |
| P2 | Configurable keyboard shortcuts | انجام‌شده | هفت عمل در تنظیمات > صفحه‌کلید قابل تغییر است، با تشخیص تداخل، اعتبارسنجی و بازنشانی. میان‌برهای ویرایشگر ثابت می‌مانند. تست شده. |
| P2 | Restore workspace after restart (tabs, panel sizes) | انجام‌شده | تب‌ها (پیش‌نویس بدون رمز)، تب فعال، عرض نوار کناری و چیدمان تقسیم برای هر فضای کاری بازیابی می‌شوند. رمزهای واردشده در تب‌های ذخیره‌نشده نگه‌داری نمی‌شوند. تست شده. |
| P2 | Drag-and-drop import, native file dialogs | انجام‌شده | `file_picker` برای پنجره‌های باز/ذخیره پشت رابط `FileService` و `desktop_drop` برای رها کردن فایل روی پنجره و دیدن پیش‌نمایش درون‌ریزی. افزونه‌ها هنوز روی دستگاه اجرا نشده‌اند. |
| P2 | Android share/open-with for cURL and collections | ناقص | پل Kotlin، فیلترهای manifest و سرویس Dart نوشته شده‌اند؛ متن یا JSON اشتراک‌گذاشته‌شده پیش‌نمایش درون‌ریزی را باز می‌کند. هرگز روی Android ساخته یا اجرا نشده. |
| P2 | Accessibility (labels, focus, scaling) | ناقص | برچسب‌ها، مقیاس متن و تم کنتراست بالا هست؛ بازبینی screen reader انجام نشده. |
| P3 | All methods incl. custom, params, headers, enable/disable | انجام‌شده | ردیف‌های کلید/مقدار با فعال/غیرفعال؛ کلیدهای تکراری مجاز. |
| P3 | Body types: JSON, text, form, multipart, files, GraphQL | انجام‌شده | فایل چندبخشی با مسیر. XML با نوع خام و Content-Type. |
| P3 | Binary body from file, load/save body to file | انجام‌شده | نوع بدنه باینری (مسیر فایل، بررسی اندازه با سقف درخواست)، بارگذاری/ذخیره بدنه متنی از/در فایل، و خروجی cURL و Postman. با سرور محلی تست شده. |
| P3 | Timeout, cancel, redirects (policy, limit, chain shown) | ناقص | فقط یک زمان‌انتظار کلی؛ تعداد تغییر مسیر نمایش داده می‌شود نه کل زنجیره. |
| P3 | HTTP/2, HTTP/3 | ناقص | HTTP/2 از طریق ALPN با بسته `http2` (اختیاری در تنظیمات، فقط https بدون پراکسی، یک اتصال برای هر درخواست، بدون push). با سرور HTTP/2 محلی پشت پایان‌دهنده TLS آزموده شده. HTTP/3 پشتیبانی نمی‌شود: `dart:io` از QUIC پشتیبانی ندارد. |
| P3 | Cookie jar and persistence | انجام‌شده | ظرف کوکی مطابق RFC 6265 در پایگاه داده فضای کاری، برای هر گام تغییر مسیر، با صفحه مدیریت و کلید خاموش‌کردن. محدودیت: فهرست public-suffix ندارد. تست شده. |
| P3 | Distinct DNS / TLS / timeout / cancel errors | ناقص | تایم‌اوت، لغو، TLS، اتصال، پروتکل و تغییر مسیر جدا هستند؛ DNS داخل «اتصال» است. |
| P3 | No duplicate sends, concurrent requests across tabs | انجام‌شده | یک زبانه همزمان دو بار ارسال نمی‌کند؛ زبانه‌ها مستقل‌اند. |
| P4 | Status, time, size, headers, cookies, body, copy, save | انجام‌شده | به‌علاوه هشدار بریده‌شدن و تعداد تغییر مسیر. |
| P4 | Timestamps and timing breakdown (DNS/connect/TLS) | ناقص | زبانه زمان‌بندی: اتصال (DNS و TCP و TLS با هم)، انتظار (ارسال + اولین بایت)، دریافت، تغییر مسیرها و مجموع. `dart:io` این‌ها را جدا گزارش نمی‌کند. |
| P4 | JSON tree, expand/collapse, copy JSON path | انجام‌شده | حالت درخت در نمای بدنه: باز شدن تنبل، صفحه‌بندی فهرست‌های بلند، کپی مقدار و کپی مسیر JSONPath. سازنده مسیر تست شده. |
| P4 | XML/HTML/text/image/binary, large responses | انجام‌شده | HTML فقط به‌صورت متن. بدنه‌های بزرگ با نمای خطی مجازی. |
| P4 | Audio/video previews | ردشده | ساخته نشد: پخش مطمئن روی Windows، Linux و Android به پشته رسانه بومی (مثلاً `media_kit`) با فایل‌های حجیم نیاز دارد. بازرس پیام روشن و دکمه ذخیره نشان می‌دهد. |
| P4 | Request inspector (masked, what was sent) | ناقص | متد، نشانی، سربرگ (پوشانده)، پیش‌نمایش بدنه و هشدارها؛ بازرس منشأ متغیر نیست. |
| P5 | None, Basic, Bearer, API key | انجام‌شده | رمزها در حافظه امن. |
| P5 | OAuth 2.0 | ناقص | فقط Authorization Code با PKCE و تازه‌سازی. |
| P5 | Inherited auth (collection/folder) | انجام‌شده | درخواست‌ها می‌توانند احراز هویت (و هدرها) را از نزدیک‌ترین پوشه یا مجموعه ارث ببرند. زبانه Auth منبع را نشان می‌دهد. رمزها در ذخیره‌سازی امن می‌مانند. تست شده. |
| P5 | mTLS, custom CA, certificate inspection | انجام‌شده | زنجیره گواهی و کلید مشتری (PEM، گذرواژه در ذخیره‌سازی امن)، CA اضافه، و نمای گواهی سرور در زبانه زمان‌بندی. با سرور mTLS محلی تست شده. |
| P5 | Secure storage, redaction, safe export | انجام‌شده | حافظه امن با جایگزین حافظه‌ای و هشدار. |
| P6 | Collections, folders, move, reorder, duplicate, favorites, search | انجام‌شده | جابه‌جایی با بالا/پایین، نه کشیدن. |
| P6 | Folder-level settings/variables/auth, collection auth | انجام‌شده | مجموعه‌ها و پوشه‌ها احراز هویت، هدر و اسکریپت دارند؛ پوشه‌ها متغیر هم دارند. رمزها در گاوصندوق، نه در پایگاه داده یا خروجی پیش‌فرض. |
| P6 | Bulk edit/delete/export, request templates | انجام‌شده | حالت انتخاب در کتابخانه (حذف، انتقال، خروجی گروهی)، ویرایش گروهی هدر/پارامتر/متغیر، و الگوهای درخواست داخلی و کاربر. تست شده. |
| P6 | Multiple workspaces | انجام‌شده | هر فضای کاری یک فایل پایگاه داده جدا است (مجموعه‌ها، محیط‌ها، تاریخچه، کوکی‌ها، الگوها، نشست). تنظیمات و رمزها مشترک‌اند. |
| P6 | History: search, replay, retention, redaction | انجام‌شده | فیلتر با متد/نشانی؛ فیلتر وضعیت/زمان ندارد. |
| P7 | Global, collection, environment variables with precedence | انجام‌شده | به‌علاوه مقادیر زمان اجرا از زنجیره‌سازی. |
| P7 | Folder/request-level variables, resolution inspector | انجام‌شده | اولویت: سراسری < مجموعه < پوشه < درخواست < محیط < زمان اجرا. زبانه متغیرها هر `{{name}}` را با مقدار (رمزها پنهان) و لایه منبع نشان می‌دهد. تست شده. |
| P7 | Import/export environments | ناقص | محیط‌ها داخل خروجی PostBox می‌روند؛ فایل جداگانه نیست. |
| P8 | Pre/post-request scripts and sandbox | انجام‌شده | PostBox Script: مفسر کوچکی که برای همین برنامه نوشته شده (بدون موتور JavaScript)، با محدودیت گام، زمان و اندازه، بدون دسترسی به فایل/شبکه/رمزها. اسکریپت مجموعه، پوشه و درخواست. اسکریپت‌ها هرگز درون‌ریزی نمی‌شوند. `docs/fa/SCRIPTING.md`. تست شده. |
| P8 | Assertions (status, header, body, JSONPath, duration) | انجام‌شده | اعتبارسنجی JSON schema ندارد. |
| P8 | Collection runner, sequential, reports | انجام‌شده | گزارش Markdown/JSON. |
| P8 | Parallel runs, data-driven runs, fixtures | ناقص | اجراکننده تکرار، تا ۸ تکرار موازی و فایل داده CSV/JSON را پشتیبانی می‌کند (ستون‌ها متغیر می‌شوند). سرور mock یا مدیریت fixture ندارد. |

فازهای ۹ به بعد در متن چسبانده‌شده نبودند. بقیه فهرست را بفرستید تا جدول کامل شود.
