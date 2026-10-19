import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Why an update operation failed. Kept separate from the message so the UI can
/// pick a localized string instead of showing raw exception text.
enum UpdateErrorKind {
  /// GitHub could not be reached (no connection, DNS, TLS, timeout, ...).
  network,

  /// GitHub returned a rate limit response (HTTP 403/429).
  rateLimit,

  /// The repository exists but has no published, stable (non-draft,
  /// non-prerelease) release.
  noReleases,

  /// A release was found, but it has no APK usable on this device.
  noCompatibleApk,

  /// GitHub answered with something that could not be understood.
  malformedResponse,

  /// The download itself failed.
  download,
}

/// An expected, user-presentable update failure.
class UpdateException implements Exception {
  const UpdateException(this.kind, {this.detail});

  final UpdateErrorKind kind;
  final String? detail;

  @override
  String toString() => 'UpdateException(${kind.name}${detail == null ? '' : ': $detail'})';
}

/// A version number parsed out of a release tag or the installed package info.
///
/// Downloads are compared by version *name* first and build number second, so an
/// installed `1.0.1+201` is correctly treated as up to date against a published
/// `1.0.1` tag rather than as an update.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, [this.build = 0]);

  final int major;
  final int minor;
  final int patch;
  final int build;

  /// Tolerant of real-world tags: `1.0.1`, `v1.0.1`, `v.1.0.1`, `1.2.3+45`,
  /// `release-2.0`. Anything with at least one number parses.
  static final RegExp _pattern = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:\+(\d+))?');

  static AppVersion? tryParse(String? input) {
    if (input == null) return null;
    final match = _pattern.firstMatch(input.trim());
    if (match == null) return null;
    return AppVersion(
      int.parse(match.group(1)!),
      int.tryParse(match.group(2) ?? '') ?? 0,
      int.tryParse(match.group(3) ?? '') ?? 0,
      int.tryParse(match.group(4) ?? '') ?? 0,
    );
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  String toString() => build > 0 ? '$major.$minor.$patch+$build' : '$major.$minor.$patch';

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch &&
      other.build == build;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);
}

/// A downloadable file attached to a GitHub release.
class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.size, required this.downloadUrl, this.sha256});

  final String name;
  final int size;
  final Uri downloadUrl;

  /// SHA-256 published by GitHub for this asset (the API `digest` field), if
  /// present. Used to verify the download; `null` means no trusted checksum is
  /// available and verification is skipped.
  final String? sha256;

  static ReleaseAsset? fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String?;
    final url = json['browser_download_url'] as String?;
    if (name == null || url == null) return null;

    String? sha256;
    final digest = json['digest'];
    if (digest is String && digest.startsWith('sha256:')) {
      sha256 = digest.substring('sha256:'.length).toLowerCase();
    }

    return ReleaseAsset(
      name: name,
      size: (json['size'] as num?)?.toInt() ?? 0,
      downloadUrl: Uri.parse(url),
      sha256: sha256,
    );
  }
}

/// A published, stable release plus the APK asset chosen for this device.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.name,
    required this.releaseNotes,
    required this.htmlUrl,
    required this.publishedAt,
    required this.asset,
  });

  final String tagName;
  final AppVersion version;
  final String? name;
  final String releaseNotes;
  final Uri htmlUrl;
  final DateTime? publishedAt;
  final ReleaseAsset asset;
}

sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

/// A newer stable release with a device-compatible APK is available.
class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable(this.release);

  final ReleaseInfo release;
}

/// The installed build is the newest published stable release.
class UpdateUpToDate extends UpdateCheckResult {
  const UpdateUpToDate({required this.installed, required this.latest});

  final String installed;
  final String latest;
}

/// The check could not complete.
class UpdateCheckFailed extends UpdateCheckResult {
  const UpdateCheckFailed(this.error);

  final UpdateException error;
}

/// Talks to the GitHub Releases API for a single repository.
///
/// Deliberately constructed with plain values instead of reading platform APIs
/// itself, so the version/asset logic is unit-testable without any platform
/// channel; [UpdateInstaller] supplies the installed package name and the
/// device's ABIs on Android.
///
/// ## Release asset naming convention
///
/// Only published, stable releases are considered, and the APK is always taken
/// from the `browser_download_url` the API returns - no download URL is ever
/// built here. Assets are matched by name, in this order:
///
/// 1. `app-<abi>-release.apk` for one of [knownAbis] (`arm64-v8a`,
///    `armeabi-v7a`, `x86_64`, `x86`) - Flutter's `--split-per-abi` names.
///    Preferred, because they are roughly 40 % smaller than the universal
///    build.
/// 2. a single asset whose name contains `universal`, e.g.
///    `app-release-universal.apk`.
/// 3. a single asset whose name contains no ABI at all, e.g.
///    `extify-android.apk`.
///
/// `.sha1` / `.sha256` sidecars are ignored because they are not APKs. Keep at
/// most one asset per name, and keep the ABI-less fallback unique, so the
/// choice stays deterministic.
class UpdateService {
  UpdateService({
    required this.owner,
    required this.repository,
    required this.installedVersion,
    required this.installedPackageName,
    required this.supportedAbis,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const String defaultOwner = 'Expuz66';
  static const String defaultRepository = 'extify';

  /// The application ID every Extify build uses.
  static const String canonicalApplicationId = 'com.expuz.extify';

  /// ABI substrings we understand, longest first so `arm64-v8a` is tested
  /// before the shorter `arm64` style names.
  static const List<String> knownAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'x86'];

  /// Minimum gap between automatic startup checks, so relaunching the app a few
  /// times in a row does not turn into a burst of API calls. Kept short so a
  /// release published after the last check is still offered the same day; the
  /// manual check in Settings is never throttled.
  static const Duration startupCheckCooldown = Duration(hours: 1);

  final String owner;
  final String repository;
  final String installedVersion;
  final String installedPackageName;
  final List<String> supportedAbis;

  final http.Client _client;

  static Uri releasesLatestUri(String owner, String repository) =>
      Uri.https('api.github.com', '/repos/$owner/$repository/releases/latest');

  static Uri releasesUri(String owner, String repository) =>
      Uri.https('api.github.com', '/repos/$owner/$repository/releases');

  static const Map<String, String> _headers = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  static const Duration _timeout = Duration(seconds: 20);

  /// Looks up the newest stable release and decides whether it is an update.
  Future<UpdateCheckResult> checkForUpdates() async {
    try {
      final release = await _fetchLatestStableRelease();
      if (release == null) {
        return const UpdateCheckFailed(UpdateException(UpdateErrorKind.noReleases));
      }

      final asset = selectApkAsset(release.assets);
      if (asset == null) {
        return const UpdateCheckFailed(UpdateException(UpdateErrorKind.noCompatibleApk));
      }

      final installed = AppVersion.tryParse(installedVersion);
      final available = AppVersion.tryParse(release.tagName) ?? release.version;

      final info = ReleaseInfo(
        tagName: release.tagName,
        version: available,
        name: release.name,
        releaseNotes: release.body,
        htmlUrl: release.htmlUrl,
        publishedAt: release.publishedAt,
        asset: asset,
      );

      if (installed != null && !(available > installed)) {
        return UpdateUpToDate(installed: installed.toString(), latest: available.toString());
      }

      return UpdateAvailable(info);
    } on UpdateException catch (e) {
      return UpdateCheckFailed(e);
    } on TimeoutException {
      return const UpdateCheckFailed(UpdateException(UpdateErrorKind.network, detail: 'request timed out'));
    } on SocketException catch (e) {
      return UpdateCheckFailed(UpdateException(UpdateErrorKind.network, detail: e.message));
    } on http.ClientException catch (e) {
      return UpdateCheckFailed(UpdateException(UpdateErrorKind.network, detail: e.message));
    } on FormatException catch (e) {
      return UpdateCheckFailed(UpdateException(UpdateErrorKind.malformedResponse, detail: e.message));
    }
  }

  /// `/releases/latest` already excludes drafts and prereleases. If it 404s we
  /// fall back to listing releases and picking the newest stable one, so a
  /// repository with only prereleases reports "no releases" rather than a
  /// misleading network error.
  Future<_RawRelease?> _fetchLatestStableRelease() async {
    final latest = await _client.get(releasesLatestUri(owner, repository), headers: _headers).timeout(_timeout);
    if (latest.statusCode == 200) {
      return _RawRelease.fromJson(jsonDecode(latest.body) as Map<String, dynamic>);
    }
    if (latest.statusCode != 404) {
      _throwForStatus(latest);
    }

    // `/releases/latest` answers 404 both when no *stable* release exists and
    // when the repository is not publicly readable. The full list tells the two
    // apart: only the first is a normal "nothing published yet".
    final list = await _client.get(releasesUri(owner, repository), headers: _headers).timeout(_timeout);
    if (list.statusCode != 200) _throwForStatus(list);

    final decoded = jsonDecode(list.body);
    if (decoded is! List) {
      throw const UpdateException(UpdateErrorKind.malformedResponse, detail: 'expected a list of releases');
    }

    final stable = decoded
        .whereType<Map<String, dynamic>>()
        .map(_RawRelease.fromJson)
        .where((release) => release.isStable)
        .toList();
    if (stable.isEmpty) return null;

    stable.sort(
      (a, b) => (b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
    return stable.first;
  }

  Never _throwForStatus(http.Response response) {
    if (response.statusCode == 403 || response.statusCode == 429) {
      final remaining = response.headers['x-ratelimit-remaining'];
      if (response.statusCode == 429 || remaining == '0') {
        throw const UpdateException(UpdateErrorKind.rateLimit);
      }
    }
    if (response.statusCode == 404) {
      // For the release list a 404 means the repository itself is not public.
      throw const UpdateException(UpdateErrorKind.noReleases);
    }
    throw UpdateException(UpdateErrorKind.malformedResponse, detail: 'HTTP ${response.statusCode}');
  }

  /// Picks the best APK for this device, preferring the most preferred
  /// supported ABI, then a universal build, then a single ABI-less APK.
  ReleaseAsset? selectApkAsset(List<ReleaseAsset> assets) {
    final apks = assets.where((asset) => asset.name.toLowerCase().endsWith('.apk')).toList();
    if (apks.isEmpty) return null;

    for (final abi in supportedAbis) {
      final wanted = abi.toLowerCase();
      for (final apk in apks) {
        if (apk.name.toLowerCase().contains(wanted)) return apk;
      }
    }

    for (final apk in apks) {
      if (apk.name.toLowerCase().contains('universal')) return apk;
    }

    final abiLess = apks.where((apk) {
      final name = apk.name.toLowerCase();
      return !knownAbis.any(name.contains);
    }).toList();
    if (abiLess.length == 1) return abiLess.first;

    return null;
  }

  /// Streams [asset] into [directory], reporting progress, and returns the file.
  ///
  /// [shouldCancel] is polled between chunks so the UI can abort a download.
  /// A partial file is deleted before returning/throwing.
  Future<File> downloadAsset({
    required ReleaseAsset asset,
    required Directory directory,
    void Function(int received, int? total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final target = File('${directory.path}${Platform.pathSeparator}${asset.name}');
    final partial = File('${target.path}.part');

    if (await partial.exists()) await partial.delete();

    try {
      final request = http.Request('GET', asset.downloadUrl)..headers.addAll(_headers);
      final response = await _client.send(request).timeout(_timeout);

      if (response.statusCode != 200) {
        throw UpdateException(
          response.statusCode == 403 || response.statusCode == 429
              ? UpdateErrorKind.rateLimit
              : UpdateErrorKind.download,
          detail: 'HTTP ${response.statusCode}',
        );
      }

      final total = response.contentLength ?? (asset.size > 0 ? asset.size : null);
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          if (shouldCancel?.call() ?? false) {
            throw const UpdateException(UpdateErrorKind.download, detail: 'cancelled');
          }
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(received, total);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (await target.exists()) await target.delete();
      return await partial.rename(target.path);
    } on UpdateException {
      if (await partial.exists()) await partial.delete();
      rethrow;
    } on TimeoutException {
      if (await partial.exists()) await partial.delete();
      throw const UpdateException(UpdateErrorKind.network, detail: 'download timed out');
    } on SocketException catch (e) {
      if (await partial.exists()) await partial.delete();
      throw UpdateException(UpdateErrorKind.network, detail: e.message);
    } on http.ClientException catch (e) {
      if (await partial.exists()) await partial.delete();
      throw UpdateException(UpdateErrorKind.network, detail: e.message);
    } on FileSystemException catch (e) {
      if (await partial.exists()) await partial.delete();
      throw UpdateException(UpdateErrorKind.download, detail: e.message);
    }
  }

  /// Timestamp of the last automatic check inside the marker file.
  static const String _lastCheckKey = 'lastCheckEpochMs';

  /// Version the user dismissed inside the marker file.
  static const String _dismissedVersionKey = 'dismissedVersion';

  /// Reads the updater's marker file. A missing, unreadable or corrupt file is
  /// reported as "nothing remembered" rather than as an error.
  static Future<Map<String, dynamic>> _readMarker(File file) async {
    try {
      if (!await file.exists()) return <String, dynamic>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return <String, dynamic>{};
      return decoded;
    } catch (_) {
      // A corrupt or unreadable marker just means "nothing remembered".
      return <String, dynamic>{};
    }
  }

  /// Merges [patch] into the marker file so the two kinds of memory stored in
  /// it (cooldown timestamp, dismissed version) cannot overwrite each other.
  static Future<void> _patchMarker(File file, Map<String, dynamic> patch) async {
    try {
      final marker = await _readMarker(file);
      marker.addAll(patch);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(marker));
    } catch (_) {
      // Best effort only; failing to record updater memory must never break the
      // app.
    }
  }

  /// Remembers when the last automatic check happened, so the startup check can
  /// respect a cooldown without touching the settings database.
  static Future<DateTime?> readLastCheck(File file) async {
    final millis = (await _readMarker(file))[_lastCheckKey];
    if (millis is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis.toInt());
  }

  static Future<void> writeLastCheck(File file, DateTime when) =>
      _patchMarker(file, {_lastCheckKey: when.millisecondsSinceEpoch});

  /// The release the user last sent away with "Later" (or by dismissing the
  /// dialog), so the same release is not offered on every launch.
  static Future<AppVersion?> readDismissedVersion(File file) async {
    final raw = (await _readMarker(file))[_dismissedVersionKey];
    if (raw is! String) return null;
    return AppVersion.tryParse(raw);
  }

  /// Stores [version] as dismissed. A newer release clears the effect by itself
  /// because [shouldPromptFor] compares versions instead of strings.
  static Future<void> writeDismissedVersion(File file, String version) =>
      _patchMarker(file, {_dismissedVersionKey: version});

  /// Whether a release is worth interrupting the user for: nothing was
  /// dismissed yet, or [available] is newer than what was dismissed.
  static bool shouldPromptFor(AppVersion available, AppVersion? dismissed) =>
      dismissed == null || available > dismissed;

  void close() => _client.close();
}

/// Intermediate representation of a GitHub release payload.
class _RawRelease {
  _RawRelease({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    required this.htmlUrl,
    required this.publishedAt,
    required this.isStable,
    required this.assets,
  });

  final String tagName;
  final AppVersion version;
  final String? name;
  final String body;
  final Uri htmlUrl;
  final DateTime? publishedAt;
  final bool isStable;
  final List<ReleaseAsset> assets;

  factory _RawRelease.fromJson(Map<String, dynamic> json) {
    final tag = json['tag_name'] as String? ?? '';
    final assets = (json['assets'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ReleaseAsset.fromJson)
        .whereType<ReleaseAsset>()
        .toList();

    return _RawRelease(
      tagName: tag,
      version: AppVersion.tryParse(tag) ?? const AppVersion(0, 0, 0),
      name: json['name'] as String?,
      body: (json['body'] as String? ?? '').trim(),
      htmlUrl: Uri.tryParse(json['html_url'] as String? ?? '') ?? Uri.parse('https://github.com'),
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      isStable: json['draft'] != true && json['prerelease'] != true,
      assets: assets,
    );
  }
}
