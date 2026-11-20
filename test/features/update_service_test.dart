import 'package:flutter_test/flutter_test.dart';
import 'package:postbox/features/settings/domain/app_settings.dart';
import 'package:postbox/features/update/update_service.dart';

const String _sum =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> _release({String tag = 'v1.2.0'}) => <String, dynamic>{
  'tag_name': tag,
  'draft': false,
  'body': '## New\n- thing',
  'html_url': 'https://github.com/ghaderi0x/PostBox/releases/tag/$tag',
  'published_at': '2026-11-01T10:00:00Z',
  'assets': <Map<String, dynamic>>[
    <String, dynamic>{
      'name': 'PostBox-1.2.0-windows-setup.exe',
      'browser_download_url':
          'https://github.com/ghaderi0x/PostBox/releases/download/$tag/PostBox-1.2.0-windows-setup.exe',
      'size': 1234,
    },
    <String, dynamic>{
      'name': 'PostBox-1.2.0-macos.dmg',
      'browser_download_url':
          'https://github.com/ghaderi0x/PostBox/releases/download/$tag/PostBox-1.2.0-macos.dmg',
    },
    <String, dynamic>{
      'name': 'postbox_1.2.0_amd64.deb',
      'browser_download_url':
          'https://github.com/ghaderi0x/PostBox/releases/download/$tag/postbox_1.2.0_amd64.deb',
    },
    <String, dynamic>{
      'name': 'PostBox-1.2.0-x86_64.AppImage',
      'browser_download_url':
          'https://github.com/ghaderi0x/PostBox/releases/download/$tag/PostBox-1.2.0-x86_64.AppImage',
    },
    <String, dynamic>{
      'name': 'evil.exe',
      'browser_download_url': 'https://evil.example/evil.exe',
    },
  ],
};

void main() {
  group('versions', () {
    test('parse', () {
      expect(UpdateService.parseVersion('v1.2.3'), <int>[1, 2, 3]);
      expect(UpdateService.parseVersion('1.2'), <int>[1, 2, 0]);
      expect(UpdateService.parseVersion('1.2.3+5'), <int>[1, 2, 3]);
      expect(UpdateService.parseVersion('2.0.0-beta.1'), <int>[2, 0, 0]);
      expect(UpdateService.parseVersion('nightly'), isNull);
      expect(UpdateService.parseVersion(''), isNull);
    });

    test('isNewer compares numerically, not as text', () {
      expect(UpdateService.isNewer('1.10.0', '1.9.0'), isTrue);
      expect(UpdateService.isNewer('v1.1.0', '1.0.9'), isTrue);
      expect(UpdateService.isNewer('2.0.0', '1.99.99'), isTrue);
      expect(UpdateService.isNewer('1.1.0', '1.1.0'), isFalse);
      expect(UpdateService.isNewer('1.0.9', '1.1.0'), isFalse);
      expect(UpdateService.isNewer('garbage', '1.0.0'), isFalse);
      expect(UpdateService.isNewer('1.2.0', 'garbage'), isFalse);
    });
  });

  group('release parsing', () {
    test('reads a release and drops untrusted download links', () {
      final r = ReleaseInfo.fromJson(_release())!;
      expect(r.version, '1.2.0');
      expect(r.tag, 'v1.2.0');
      expect(r.assets.map((a) => a.name), isNot(contains('evil.exe')));
      expect(r.assets, hasLength(4));
      expect(r.publishedAt, isNotNull);
    });

    test('rejects drafts, bad tags and non-objects', () {
      expect(ReleaseInfo.fromJson(null), isNull);
      expect(ReleaseInfo.fromJson('x'), isNull);
      expect(ReleaseInfo.fromJson(_release(tag: 'latest')), isNull);
      final draft = _release()..['draft'] = true;
      expect(ReleaseInfo.fromJson(draft), isNull);
    });

    test('page link must be on github.com', () {
      final j = _release()..['html_url'] = 'https://evil.example/x';
      expect(
        ReleaseInfo.fromJson(j)!.pageUrl,
        startsWith('https://github.com/ghaderi0x/PostBox'),
      );
    });
  });

  group('installer choice', () {
    final r = ReleaseInfo.fromJson(_release())!;

    test('per platform', () {
      expect(
        UpdateService.pickInstaller(r, UpdatePlatform.windows)!.name,
        'PostBox-1.2.0-windows-setup.exe',
      );
      expect(
        UpdateService.pickInstaller(r, UpdatePlatform.macos)!.name,
        'PostBox-1.2.0-macos.dmg',
      );
      expect(
        UpdateService.pickInstaller(r, UpdatePlatform.linuxDeb)!.name,
        'postbox_1.2.0_amd64.deb',
      );
      expect(
        UpdateService.pickInstaller(r, UpdatePlatform.linuxAppImage)!.name,
        'PostBox-1.2.0-x86_64.AppImage',
      );
      expect(UpdateService.pickInstaller(r, UpdatePlatform.other), isNull);
    });

    test('nothing when the release has no matching file', () {
      const empty = ReleaseInfo(
        version: '1.2.0',
        tag: 'v1.2.0',
        notes: '',
        pageUrl: 'https://github.com/ghaderi0x/PostBox',
        assets: <ReleaseAsset>[],
      );
      expect(
        UpdateService.pickInstaller(empty, UpdatePlatform.windows),
        isNull,
      );
    });
  });

  group('download safety', () {
    test('only https on GitHub hosts', () {
      expect(
        UpdateService.isTrustedDownloadUrl('https://github.com/a/b/c.exe'),
        isTrue,
      );
      expect(
        UpdateService.isTrustedDownloadUrl(
          'https://objects.githubusercontent.com/x',
        ),
        isTrue,
      );
      expect(
        UpdateService.isTrustedDownloadUrl('http://github.com/x'),
        isFalse,
      );
      expect(
        UpdateService.isTrustedDownloadUrl('https://github.com.evil.io/x'),
        isFalse,
      );
      expect(UpdateService.isTrustedDownloadUrl('file:///etc/passwd'), isFalse);
    });

    test('checksum lookup', () {
      final sums =
          '$_sum  postbox_1.2.0_amd64.deb\n'
          '${'b' * 64} *PostBox-1.2.0-windows-setup.exe\n';
      expect(UpdateService.checksumFor(sums, 'postbox_1.2.0_amd64.deb'), _sum);
      expect(
        UpdateService.checksumFor(sums, 'PostBox-1.2.0-windows-setup.exe'),
        'b' * 64,
      );
      expect(UpdateService.checksumFor(sums, 'other.bin'), isNull);
      expect(UpdateService.checksumFor('garbage', 'x'), isNull);
    });
  });

  test('update settings survive a JSON round trip', () {
    const s = AppSettings(checkUpdates: false, skippedVersion: '1.2.0');
    final back = AppSettings.fromJson(s.toJson());
    expect(back.checkUpdates, isFalse);
    expect(back.skippedVersion, '1.2.0');
    expect(const AppSettings().checkUpdates, isTrue);
  });
}
