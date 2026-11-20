import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/core/util/html_util.dart';

void main() {
  test('finds the page title and collapses whitespace', () {
    expect(
      htmlTitleOf('<html><head><title>  My\n  page </title></head>'),
      'My page',
    );
    expect(htmlTitleOf('<TITLE lang="fa">سلام</TITLE>'), 'سلام');
    expect(htmlTitleOf('<p>no title</p>'), isNull);
    expect(htmlTitleOf('<title>   </title>'), isNull);
  });

  test('detects images', () {
    expect(htmlHasImages('<p>x</p><IMG src="a.png">'), isTrue);
    expect(htmlHasImages('<p>image</p>'), isFalse);
    expect(htmlHasImages('<imgx>'), isFalse);
  });

  test('only web and mail links may be opened', () {
    expect(isOpenableLink(Uri.parse('https://a.test')), isTrue);
    expect(isOpenableLink(Uri.parse('http://a.test')), isTrue);
    expect(isOpenableLink(Uri.parse('mailto:a@b.test')), isTrue);
    expect(isOpenableLink(Uri.parse('file:///etc/passwd')), isFalse);
    expect(isOpenableLink(Uri.parse('javascript:alert(1)')), isFalse);
    expect(isOpenableLink(Uri.parse('intent://x')), isFalse);
  });
}
