import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/typography.dart';
import '../../core/util/html_util.dart';
import '../../l10n/strings.dart';
import '../widgets/common.dart';

/// Largest page rendered; more is cut so a huge response cannot freeze the UI.
const int kMaxHtmlPreviewChars = 500000;

/// Renders a page without letting it touch the app:
/// * no JavaScript, iframes, video or plugins (the renderer ignores them),
/// * images from the network are blocked until the user allows them,
/// * `file:` and `asset:` images are never loaded,
/// * links are opened in the system browser only after a confirmation.
class _SafeFactory extends WidgetFactory {
  _SafeFactory({required this.allowNetworkImages});

  final bool allowNetworkImages;

  @override
  ImageProvider? imageProviderFromNetwork(String url) {
    if (!allowNetworkImages) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return NetworkImage(url);
  }

  @override
  ImageProvider? imageProviderFromAsset(String url) => null;

  @override
  ImageProvider? imageProviderFromFileUri(String url) => null;
}

/// A browser-like view of an HTML response: an address bar with the page
/// title, URL and a lock icon, and the rendered page below. It is a static
/// renderer, not a browser engine: scripts do not run and CSS support is
/// partial, so complex sites can look different.
class HtmlBrowserView extends StatefulWidget {
  const HtmlBrowserView({super.key, required this.html, required this.url});

  final String html;
  final Uri url;

  @override
  State<HtmlBrowserView> createState() => _HtmlBrowserViewState();
}

class _HtmlBrowserViewState extends State<HtmlBrowserView> {
  bool _images = false;

  Future<bool> _onTapUrl(String raw) async {
    final uri = widget.url.resolve(raw);
    if (!isOpenableLink(uri)) {
      if (mounted) await showToast(context, context.t('html.linkBlocked'));
      return true;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t('html.openLinkTitle')),
        content: SelectableText(uri.toString(), style: ctx.mono),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.t('common.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.t('html.openLink')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final truncated = widget.html.length > kMaxHtmlPreviewChars;
    final source = truncated
        ? widget.html.substring(0, kMaxHtmlPreviewChars)
        : widget.html;
    final title = htmlTitleOf(widget.html);
    final secure = widget.url.scheme == 'https';
    final hasImages = htmlHasImages(source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Address bar.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            border: Border.all(color: c.border),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.public, size: 14, color: c.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.secondary.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: c.surfaceBase,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            secure ? Icons.lock_outline : Icons.lock_open,
                            size: 15,
                            color: secure ? c.success : c.warning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.url.toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.ltr,
                              style: context.mono.copyWith(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.t('html.openInBrowser'),
                    icon: Icon(
                      Icons.open_in_new,
                      size: 18,
                      color: c.textSecondary,
                    ),
                    onPressed: () => _onTapUrl(widget.url.toString()),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (hasImages && !_images)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            color: c.warning.withAlpha(26),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.image_not_supported_outlined,
                  size: 16,
                  color: c.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.t('html.imagesBlocked'),
                    style: context.secondary,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _images = true),
                  child: Text(context.t('html.loadImages')),
                ),
              ],
            ),
          ),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                left: BorderSide(color: c.border),
                right: BorderSide(color: c.border),
                bottom: BorderSide(color: c.border),
              ),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Theme(
              // Pages are drawn on white like a browser, whatever the app theme.
              data: ThemeData.light(),
              child: SelectionArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: HtmlWidget(
                    source,
                    baseUrl: widget.url,
                    factoryBuilder: () =>
                        _SafeFactory(allowNetworkImages: _images),
                    onTapUrl: _onTapUrl,
                    textStyle: const TextStyle(
                      color: Color(0xFF1B1B1B),
                      fontSize: 15,
                      height: 1.45,
                      fontFamily: kUiFont,
                      fontFamilyFallback: <String>[kPersianFont],
                    ),
                    rebuildTriggers: <Object>[_images],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            truncated
                ? context.t('html.truncated', <String>[
                    '${kMaxHtmlPreviewChars ~/ 1000}',
                  ])
                : context.t('html.staticNote'),
            style: context.secondary,
          ),
        ),
      ],
    );
  }
}
