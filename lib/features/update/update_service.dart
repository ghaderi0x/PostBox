import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/app_info.dart';

/// One downloadable file of a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, this.size = 0});

  final String name;
  final String url;
  final int size;
}

/// The newest published release of the project.
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tag,
    required this.notes,
    required this.pageUrl,
    required this.assets,
    this.publishedAt,
  });

  /// Plain version such as `1.2.0` (no leading "v").
  final String version;
  final String tag;
  final String notes;
  final String pageUrl;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;

  /// Lenient parser for the GitHub "latest release" response.
  static ReleaseInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final tag = '${json['tag_name'] ?? ''}'.trim();
    if (tag.isEmpty || UpdateService.parseVersion(tag) == null) return null;
    if (json['draft'] == true) return null;
    final assets = <ReleaseAsset>[];
    final raw = json['assets'];
    if (raw is List) {
      for (final a in raw) {
        if (a is! Map) continue;
        final name = '${a['name'] ?? ''}';
        final url = '${a['browser_download_url'] ?? ''}';
        if (name.isEmpty || !UpdateService.isTrustedDownloadUrl(url)) continue;
        assets.add(
          ReleaseAsset(
            name: name,
            url: url,
            size: a['size'] is int ? a['size'] as int : 0,
          ),
        );
      }
    }
    final page = '${json['html_url'] ?? ''}';
    return ReleaseInfo(
      version: tag.replaceFirst(RegExp(r'^[vV]'), ''),
      tag: tag,
      notes: '${json['body'] ?? ''}'.trim(),
      pageUrl: page.startsWith('https://github.com/')
          ? page
          : '$repositoryUrl/releases/latest',
      publishedAt: DateTime.tryParse('${json['published_at'] ?? ''}'),
      assets: assets,
    );
  }
}

enum UpdatePlatform { windows, macos, linuxDeb, linuxAppImage, other }

/// Looks up new versions on GitHub and downloads their installers.
///
/// Network use is limited to one small request to the GitHub API per app
/// start (and only when the user left the check on in Settings), plus the
/// installer download when the user asks for it.
class UpdateService {
  UpdateService({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;

  static final Uri latestReleaseApi = Uri.parse(
    'https://api.github.com/repos/$repositoryOwner/$repositoryName/releases/latest',
  );

  /// `1.2.3`, `v1.2.3`, `1.2.3+5`, `1.2.3-beta.1` -> [1, 2, 3]; else null.
  static List<int>? parseVersion(String v) {
    final m = RegExp(
      r'^[vV]?(\d+)\.(\d+)(?:\.(\d+))?(?:[-+].*)?$',
    ).firstMatch(v.trim());
    if (m == null) return null;
    return <int>[
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3) ?? '0'),
    ];
  }

  /// True when [remote] is a higher version than [local].
  static bool isNewer(String remote, String local) {
    final r = parseVersion(remote);
    final l = parseVersion(local);
    if (r == null || l == null) return false;
    for (var i = 0; i < 3; i++) {
      if (r[i] != l[i]) return r[i] > l[i];
    }
    return false;
  }

  /// Only https links on GitHub's own hosts may be downloaded.
  static bool isTrustedDownloadUrl(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https') return false;
    final h = u.host.toLowerCase();
    return h == 'github.com' ||
        h == 'api.github.com' ||
        h.endsWith('.githubusercontent.com');
  }

  /// Newest release, or null when offline, rate limited or malformed. Never
  /// throws: a failed check must not disturb the app.
  Future<ReleaseInfo?> fetchLatest({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = _clientFactory()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(latestReleaseApi).timeout(timeout);
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'PostBox/$appVersion');
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final body = await res.transform(utf8.decoder).join().timeout(timeout);
      return ReleaseInfo.fromJson(jsonDecode(body));
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Which installer family fits this machine.
  static UpdatePlatform detectPlatform() {
    if (Platform.isWindows) return UpdatePlatform.windows;
    if (Platform.isMacOS) return UpdatePlatform.macos;
    if (Platform.isLinux) {
      if (Platform.environment.containsKey('APPIMAGE')) {
        return UpdatePlatform.linuxAppImage;
      }
      if (File('/usr/bin/dpkg').existsSync()) return UpdatePlatform.linuxDeb;
      return UpdatePlatform.linuxAppImage;
    }
    return UpdatePlatform.other;
  }

  /// The release file to offer for [platform], or null if none matches.
  static ReleaseAsset? pickInstaller(
    ReleaseInfo release,
    UpdatePlatform platform,
  ) {
    bool match(bool Function(String n) test) =>
        release.assets.any((a) => test(a.name.toLowerCase()));
    ReleaseAsset? find(bool Function(String n) test) {
      for (final a in release.assets) {
        if (test(a.name.toLowerCase())) return a;
      }
      return null;
    }

    switch (platform) {
      case UpdatePlatform.windows:
        return find((n) => n.endsWith('.exe') && n.contains('setup')) ??
            (match((n) => n.endsWith('.exe'))
                ? find((n) => n.endsWith('.exe'))
                : null);
      case UpdatePlatform.macos:
        return find((n) => n.endsWith('.dmg'));
      case UpdatePlatform.linuxDeb:
        return find((n) => n.endsWith('.deb'));
      case UpdatePlatform.linuxAppImage:
        return find((n) => n.endsWith('.appimage'));
      case UpdatePlatform.other:
        return null;
    }
  }

  /// Finds the SHA-256 of [fileName] inside a `SHA256SUMS.txt` body.
  static String? checksumFor(String sums, String fileName) {
    for (final line in const LineSplitter().convert(sums)) {
      final m = RegExp(
        r'^([0-9a-fA-F]{64})\s+\*?(.+)$',
      ).firstMatch(line.trim());
      if (m != null && m.group(2)!.trim() == fileName) {
        return m.group(1)!.toLowerCase();
      }
    }
    return null;
  }

  Future<String?> _fetchSums(ReleaseInfo release) async {
    ReleaseAsset? sums;
    for (final a in release.assets) {
      if (a.name.toLowerCase() == 'sha256sums.txt') sums = a;
    }
    if (sums == null) return null;
    final client = _clientFactory();
    try {
      final req = await client.getUrl(Uri.parse(sums.url));
      req.headers.set(HttpHeaders.userAgentHeader, 'PostBox/$appVersion');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      return await res.transform(utf8.decoder).join();
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads [asset] into a temp folder, reporting 0..1 progress, and
  /// checks it against the release checksum file when one is published.
  /// Throws [UpdateException] on any problem.
  Future<File> download(
    ReleaseInfo release,
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!isTrustedDownloadUrl(asset.url)) {
      throw const UpdateException('untrusted');
    }
    final dir = await getTemporaryDirectory();
    final folder = Directory(p.join(dir.path, 'postbox-update'));
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    await folder.create(recursive: true);
    final file = File(p.join(folder.path, p.basename(asset.name)));

    final client = _clientFactory()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(asset.url));
      req.headers.set(HttpHeaders.userAgentHeader, 'PostBox/$appVersion');
      final res = await req.close();
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw UpdateException('http ${res.statusCode}');
      }
      final total = res.contentLength > 0 ? res.contentLength : asset.size;
      final sink = file.openWrite();
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;
      try {
        await for (final chunk in res) {
          if (isCancelled?.call() ?? false)
            throw const UpdateException('cancelled');
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      } finally {
        await sink.close();
        hasher.close();
      }
      final expected = checksumFor(await _fetchSums(release) ?? '', asset.name);
      if (expected != null && '${digestSink.value}' != expected) {
        await file.delete();
        throw const UpdateException('checksum');
      }
      onProgress?.call(1);
      return file;
    } on UpdateException {
      rethrow;
    } on Object catch (e) {
      throw UpdateException('$e');
    } finally {
      client.close(force: true);
    }
  }

  /// Starts the installer. The caller should close the app afterwards on
  /// Windows so the installer can replace its files.
  Future<void> launchInstaller(File file, UpdatePlatform platform) async {
    switch (platform) {
      case UpdatePlatform.windows:
        await Process.start(
          file.path,
          const <String>[],
          mode: ProcessStartMode.detached,
        );
      case UpdatePlatform.macos:
        // Mounts the disk image; the user drags PostBox to Applications.
        await Process.start('open', <String>[
          file.path,
        ], mode: ProcessStartMode.detached);
      case UpdatePlatform.linuxDeb:
        await Process.start('xdg-open', <String>[
          file.path,
        ], mode: ProcessStartMode.detached);
      case UpdatePlatform.linuxAppImage:
        await Process.run('chmod', <String>['+x', file.path]);
        await Process.start(
          file.path,
          const <String>[],
          mode: ProcessStartMode.detached,
        );
      case UpdatePlatform.other:
        throw const UpdateException('unsupported');
    }
  }
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;

  @override
  String toString() => 'UpdateException($message)';
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
