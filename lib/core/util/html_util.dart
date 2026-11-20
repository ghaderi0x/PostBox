/// Small helpers for the HTML preview. Pure Dart so they can be tested.
library;

/// Pulls the `<title>` out of an HTML document, or null.
String? htmlTitleOf(String html) {
  final m = RegExp(
    r'<title[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(html);
  final t = m?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// True when the page refers to remote images (`<img>` tags).
bool htmlHasImages(String html) =>
    RegExp(r'<img\b', caseSensitive: false).hasMatch(html);

/// Only http and https links may be opened from a page.
bool isOpenableLink(Uri uri) =>
    uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'mailto';
