# ماتریس قابلیت‌ها در برابر فهرست کارهای اصلی

فهرست کارهایی که فرستادید (فازهای ۰ تا ۸؛ متن چسبانده‌شده وسط فاز ۸ قطع شده بود) با آنچه در مخزن نوشته شده مقایسه شده است. «انجام‌شده» یعنی نوشته شده، نه راستی‌آزمایی با اجرا (به `PROJECT_STATUS.md` نگاه کنید).

خلاصه: 16 انجام‌شده، 9 ناقص، 21 انجام‌نشده از 46 مورد دسته‌بندی‌شده.

| فاز | مورد | وضعیت | توضیح |
|---|---|---|---|
| P0 | Competitor research, feature matrix, complaint database | انجام‌نشده | انجام نشده. نیاز به یک دور پژوهش مستقل با منبع و تاریخ دارد. |
| P0 | PRD, MVP, acceptance criteria, benchmarks | ناقص | مشخصات محصول و الزامات امنیتی هست؛ بنچمارک اندازه‌گیری‌شده و PRD رسمی نیست. |
| P1 | Android, Windows, Linux | انجام‌شده | برای هر سه نوشته شده؛ هیچ‌کدام هنوز ساخته یا آزموده نشده. |
| P1 | iOS/macOS-ready architecture | ناقص | کد خاص پلتفرم جز dart:io، حافظه امن و app links نیست؛ بررسی نشده. |
| P1 | Clean architecture, DI, Bloc/Cubit, repository interfaces | ناقص | پوشه‌های قابلیت، تزریق سازنده و رابط repository هست؛ جداسازی domain/data همه‌جا دقیق نیست. |
| P1 | FFI / native engine | انجام‌نشده | استفاده نشده. سودی اندازه‌گیری نشده و dart:io نیاز فعلی را برآورده می‌کند. |
| P2 | Design system, themes, accent, density, persisted | انجام‌شده | شش تم، رنگ دلخواه، تراکم، مقیاس متن، کاهش حرکت. |
| P2 | Premium look (soft cards, floating nav, onboarding) | انجام‌شده | در نسخه ۰٫۳٫۰ اضافه شد. جلای بصری هنوز نیاز به بررسی شما روی دستگاه دارد. |
| P2 | Resizable panels, multiple tabs, command palette, context menus | انجام‌شده | نوار کناری و تقسیم قابل تغییر، زبانه‌ها، Ctrl+K، منوها. |
| P2 | Draggable/reorderable tabs | انجام‌نشده | زبانه‌ها قابل کشیدن یا جابه‌جایی نیستند. |
| P2 | Configurable keyboard shortcuts | انجام‌نشده | میان‌برها ثابت‌اند. |
| P2 | Restore workspace after restart (tabs, panel sizes) | انجام‌نشده | زبانه‌های باز و اندازه پنل‌ها ذخیره نمی‌شوند؛ درخواست‌های ذخیره‌شده می‌مانند. |
| P2 | Drag-and-drop import, native file dialogs | انجام‌نشده | وابستگی انتخاب فایل نیست. درون‌ریزی با مسیر تایپ‌شده یا متن چسبانده‌شده است. |
| P2 | Android share/open-with for cURL and collections | انجام‌نشده | پیاده‌سازی نشده. |
| P2 | Accessibility (labels, focus, scaling) | ناقص | برچسب‌ها، مقیاس متن و تم کنتراست بالا هست؛ بازبینی screen reader انجام نشده. |
| P3 | All methods incl. custom, params, headers, enable/disable | انجام‌شده | ردیف‌های کلید/مقدار با فعال/غیرفعال؛ کلیدهای تکراری مجاز. |
| P3 | Body types: JSON, text, form, multipart, files, GraphQL | انجام‌شده | فایل چندبخشی با مسیر. XML با نوع خام و Content-Type. |
| P3 | Binary body from file, load/save body to file | انجام‌نشده | پیاده‌سازی نشده. |
| P3 | Timeout, cancel, redirects (policy, limit, chain shown) | ناقص | فقط یک زمان‌انتظار کلی؛ تعداد تغییر مسیر نمایش داده می‌شود نه کل زنجیره. |
| P3 | HTTP/2, HTTP/3 | انجام‌نشده | HttpClient در dart:io فقط HTTP/1.1 دارد. |
| P3 | Cookie jar and persistence | انجام‌نشده | کوکی‌ها نمایش داده می‌شوند اما ذخیره یا دوباره ارسال نمی‌شوند. |
| P3 | Distinct DNS / TLS / timeout / cancel errors | ناقص | تایم‌اوت، لغو، TLS، اتصال، پروتکل و تغییر مسیر جدا هستند؛ DNS داخل «اتصال» است. |
| P3 | No duplicate sends, concurrent requests across tabs | انجام‌شده | یک زبانه همزمان دو بار ارسال نمی‌کند؛ زبانه‌ها مستقل‌اند. |
| P4 | Status, time, size, headers, cookies, body, copy, save | انجام‌شده | به‌علاوه هشدار بریده‌شدن و تعداد تغییر مسیر. |
| P4 | Timestamps and timing breakdown (DNS/connect/TLS) | انجام‌نشده | فقط مدت کل. |
| P4 | JSON tree, expand/collapse, copy JSON path | انجام‌نشده | نمای مرتب/خام با جستجو؛ درخت ندارد. |
| P4 | XML/HTML/text/image/binary, large responses | انجام‌شده | HTML فقط به‌صورت متن. بدنه‌های بزرگ با نمای خطی مجازی. |
| P4 | Audio/video previews | انجام‌نشده | پیاده‌سازی نشده. |
| P4 | Request inspector (masked, what was sent) | ناقص | متد، نشانی، سربرگ (پوشانده)، پیش‌نمایش بدنه و هشدارها؛ بازرس منشأ متغیر نیست. |
| P5 | None, Basic, Bearer, API key | انجام‌شده | رمزها در حافظه امن. |
| P5 | OAuth 2.0 | ناقص | فقط Authorization Code با PKCE و تازه‌سازی. |
| P5 | Inherited auth (collection/folder) | انجام‌نشده | احراز هویت برای هر درخواست جدا است. |
| P5 | mTLS, custom CA, certificate inspection | انجام‌نشده | پیاده‌سازی نشده. |
| P5 | Secure storage, redaction, safe export | انجام‌شده | حافظه امن با جایگزین حافظه‌ای و هشدار. |
| P6 | Collections, folders, move, reorder, duplicate, favorites, search | انجام‌شده | جابه‌جایی با بالا/پایین، نه کشیدن. |
| P6 | Folder-level settings/variables/auth, collection auth | انجام‌نشده | مجموعه‌ها فقط متغیر دارند. |
| P6 | Bulk edit/delete/export, request templates | انجام‌نشده | پیاده‌سازی نشده. |
| P6 | Multiple workspaces | انجام‌نشده | یک فضای کاری محلی. |
| P6 | History: search, replay, retention, redaction | انجام‌شده | فیلتر با متد/نشانی؛ فیلتر وضعیت/زمان ندارد. |
| P7 | Global, collection, environment variables with precedence | انجام‌شده | به‌علاوه مقادیر زمان اجرا از زنجیره‌سازی. |
| P7 | Folder/request-level variables, resolution inspector | انجام‌نشده | هشدار متغیر حل‌نشده هست؛ منشأ نمایش داده نمی‌شود. |
| P7 | Import/export environments | ناقص | محیط‌ها داخل خروجی PostBox می‌روند؛ فایل جداگانه نیست. |
| P8 | Pre/post-request scripts and sandbox | انجام‌نشده | عمداً ساخته نشده تا sandbox انتخاب شود. |
| P8 | Assertions (status, header, body, JSONPath, duration) | انجام‌شده | اعتبارسنجی JSON schema ندارد. |
| P8 | Collection runner, sequential, reports | انجام‌شده | گزارش Markdown/JSON. |
| P8 | Parallel runs, data-driven runs, fixtures | انجام‌نشده | پیاده‌سازی نشده. |

فازهای ۹ به بعد در متن چسبانده‌شده نبودند. بقیه فهرست را بفرستید تا جدول کامل شود.
