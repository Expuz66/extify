import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:finamp/services/update_installer.dart';
import 'package:finamp/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A release payload shaped like the real GitHub API response for
/// Expuz66/extify (drafts/prereleases excluded by /releases/latest).
Map<String, dynamic> releaseJson({
  String tag = '1.0.2',
  String name = 'Extify 1.0.2',
  String body = 'Fixes and polish.',
  bool draft = false,
  bool prerelease = false,
  String publishedAt = '2026-10-17T07:22:57Z',
  List<Map<String, dynamic>>? assets,
}) => {
  'tag_name': tag,
  'name': name,
  'body': body,
  'html_url': 'https://github.com/Expuz66/extify/releases/tag/$tag',
  'published_at': publishedAt,
  'draft': draft,
  'prerelease': prerelease,
  'assets':
      assets ??
      [
        {
          'name': 'app-arm64-v8a-release.apk',
          'size': 50470632,
          'browser_download_url': 'https://github.com/Expuz66/extify/releases/download/$tag/app-arm64-v8a-release.apk',
          'content_type': 'application/vnd.android.package-archive',
          'digest': 'sha256:${'a' * 64}',
        },
        {
          'name': 'app-arm64-v8a-release.apk.sha1',
          'size': 40,
          'browser_download_url':
              'https://github.com/Expuz66/extify/releases/download/$tag/app-arm64-v8a-release.apk.sha1',
          'digest': 'sha256:${'b' * 64}',
        },
        {
          'name': 'app-armeabi-v7a-release.apk',
          'size': 50906642,
          'browser_download_url':
              'https://github.com/Expuz66/extify/releases/download/$tag/app-armeabi-v7a-release.apk',
          'digest': 'sha256:${'c' * 64}',
        },
        {
          'name': 'app-release-universal.apk',
          'size': 122086965,
          'browser_download_url': 'https://github.com/Expuz66/extify/releases/download/$tag/app-release-universal.apk',
          'digest': 'sha256:${'d' * 64}',
        },
      ],
};

UpdateService serviceWith(
  http.Client client, {
  String installedVersion = '1.0.1+201',
  List<String> abis = const ['arm64-v8a', 'armeabi-v7a'],
}) => UpdateService(
  owner: UpdateService.defaultOwner,
  repository: UpdateService.defaultRepository,
  installedVersion: installedVersion,
  installedPackageName: 'com.expuz.extify',
  supportedAbis: abis,
  client: client,
);

void main() {
  group('Extify updater configuration invariants', () {
    test('the update source is the real public repository', () {
      expect(UpdateService.defaultOwner, 'Expuz66');
      expect(UpdateService.defaultRepository, 'extify');
      expect(
        UpdateService.releasesLatestUri(UpdateService.defaultOwner, UpdateService.defaultRepository).toString(),
        'https://api.github.com/repos/Expuz66/extify/releases/latest',
      );
    });

    test('the application ID the updater validates against is unchanged', () {
      expect(UpdateService.canonicalApplicationId, 'com.expuz.extify');
    });
  });

  group('AppVersion parsing and comparison', () {
    test('parses plain and prefixed release tags', () {
      expect(AppVersion.tryParse('1.0.1'), const AppVersion(1, 0, 1));
      expect(AppVersion.tryParse('v1.2.3'), const AppVersion(1, 2, 3));
      // A stray dot (a real tag in this repository is "v.1.0.1") still parses.
      expect(AppVersion.tryParse('v.1.0.1'), const AppVersion(1, 0, 1));
      expect(AppVersion.tryParse('release-2.0'), const AppVersion(2, 0, 0));
      expect(AppVersion.tryParse('1.2.3+45'), const AppVersion(1, 2, 3, 45));
      expect(AppVersion.tryParse(''), isNull);
      expect(AppVersion.tryParse(null), isNull);
    });

    test('compares by name first, then build number', () {
      expect(const AppVersion(1, 0, 2) > const AppVersion(1, 0, 1), isTrue);
      expect(const AppVersion(1, 1, 0) > const AppVersion(1, 0, 9), isTrue);
      expect(const AppVersion(2, 0, 0) > const AppVersion(1, 9, 9), isTrue);
      expect(const AppVersion(1, 0, 1, 201) > const AppVersion(1, 0, 1), isTrue);
      expect(const AppVersion(1, 0, 1) > const AppVersion(1, 0, 1, 201), isFalse);
      expect(const AppVersion(1, 0, 1, 5) > const AppVersion(1, 0, 1, 5), isFalse);
    });
  });

  group('APK asset selection', () {
    test('prefers the most preferred supported ABI', () {
      final service = serviceWith(MockClient((_) async => http.Response('', 200)), abis: ['arm64-v8a', 'armeabi-v7a']);
      final assets = [
        ReleaseAsset.fromJson({
          'name': 'app-armeabi-v7a-release.apk',
          'size': 1,
          'browser_download_url': 'https://x/1',
        }),
        ReleaseAsset.fromJson({'name': 'app-arm64-v8a-release.apk', 'size': 1, 'browser_download_url': 'https://x/2'}),
        ReleaseAsset.fromJson({'name': 'app-release-universal.apk', 'size': 1, 'browser_download_url': 'https://x/3'}),
      ].whereType<ReleaseAsset>().toList();

      expect(service.selectApkAsset(assets)!.name, 'app-arm64-v8a-release.apk');
    });

    test('follows the device ABI order', () {
      final service = serviceWith(MockClient((_) async => http.Response('', 200)), abis: ['x86_64']);
      final assets = [
        ReleaseAsset.fromJson({'name': 'app-arm64-v8a-release.apk', 'size': 1, 'browser_download_url': 'https://x/1'}),
        ReleaseAsset.fromJson({'name': 'app-x86_64-release.apk', 'size': 1, 'browser_download_url': 'https://x/2'}),
        ReleaseAsset.fromJson({'name': 'app-release-universal.apk', 'size': 1, 'browser_download_url': 'https://x/3'}),
      ].whereType<ReleaseAsset>().toList();

      expect(service.selectApkAsset(assets)!.name, 'app-x86_64-release.apk');
    });

    test('falls back to a universal APK', () {
      final service = serviceWith(MockClient((_) async => http.Response('', 200)), abis: ['riscv64']);
      final assets = [
        ReleaseAsset.fromJson({'name': 'app-arm64-v8a-release.apk', 'size': 1, 'browser_download_url': 'https://x/1'}),
        ReleaseAsset.fromJson({'name': 'app-release-universal.apk', 'size': 1, 'browser_download_url': 'https://x/2'}),
      ].whereType<ReleaseAsset>().toList();

      expect(service.selectApkAsset(assets)!.name, 'app-release-universal.apk');
    });

    test('accepts a single ABI-less APK', () {
      final service = serviceWith(MockClient((_) async => http.Response('', 200)), abis: ['arm64-v8a']);
      final assets = [
        ReleaseAsset.fromJson({'name': 'app-release.apk', 'size': 1, 'browser_download_url': 'https://x/1'}),
      ].whereType<ReleaseAsset>().toList();

      expect(service.selectApkAsset(assets)!.name, 'app-release.apk');
    });

    test('rejects ABI-specific APKs and checksum sidecars when nothing matches', () {
      final service = serviceWith(MockClient((_) async => http.Response('', 200)), abis: ['riscv64']);
      final assets = [
        ReleaseAsset.fromJson({'name': 'app-arm64-v8a-release.apk', 'size': 1, 'browser_download_url': 'https://x/1'}),
        ReleaseAsset.fromJson({
          'name': 'app-arm64-v8a-release.apk.sha1',
          'size': 40,
          'browser_download_url': 'https://x/2',
        }),
      ].whereType<ReleaseAsset>().toList();

      expect(service.selectApkAsset(assets), isNull);
    });
  });

  group('Release asset JSON parsing', () {
    test('extracts the published GitHub sha256 digest', () {
      final asset = ReleaseAsset.fromJson({
        'name': 'app-arm64-v8a-release.apk',
        'size': 50470632,
        'browser_download_url': 'https://github.com/Expuz66/extify/releases/download/1.0.1/app-arm64-v8a-release.apk',
        'digest': 'sha256:4de03d11fc9b413458ab726c9db2eb3cf0163a09f903d51dbf78a6049d9202c2',
      })!;

      expect(asset.sha256, '4de03d11fc9b413458ab726c9db2eb3cf0163a09f903d51dbf78a6049d9202c2');
      expect(asset.size, 50470632);
    });

    test('reports no checksum when GitHub omits the digest', () {
      final asset = ReleaseAsset.fromJson({
        'name': 'app-release.apk',
        'size': 1,
        'browser_download_url': 'https://x/1',
      })!;

      expect(asset.sha256, isNull);
    });

    test('ignores non-sha256 and malformed entries', () {
      expect(
        ReleaseAsset.fromJson({
          'name': 'a.apk',
          'size': 1,
          'browser_download_url': 'https://x/1',
          'digest': 'sha1:abc',
        })!.sha256,
        isNull,
      );
      expect(ReleaseAsset.fromJson({'name': 'a.apk'}), isNull);
    });
  });

  group('checkForUpdates', () {
    test('reports an available update with the right asset', () async {
      final service = serviceWith(
        MockClient((request) async {
          expect(request.url.path, '/repos/Expuz66/extify/releases/latest');
          return http.Response(jsonEncode(releaseJson()), 200);
        }),
      );

      final result = await service.checkForUpdates();

      expect(result, isA<UpdateAvailable>());
      final release = (result as UpdateAvailable).release;
      expect(release.version, const AppVersion(1, 0, 2));
      expect(release.asset.name, 'app-arm64-v8a-release.apk');
      expect(release.asset.sha256, 'a' * 64);
      expect(release.releaseNotes, 'Fixes and polish.');
    });

    test('reports up to date when the installed version is the published one', () async {
      final service = serviceWith(
        MockClient((_) async => http.Response(jsonEncode(releaseJson(tag: '1.0.1')), 200)),
        installedVersion: '1.0.1+201',
      );

      final result = await service.checkForUpdates();

      expect(result, isA<UpdateUpToDate>());
      expect((result as UpdateUpToDate).latest, '1.0.1');
    });

    test('never offers a downgrade', () async {
      final service = serviceWith(
        MockClient((_) async => http.Response(jsonEncode(releaseJson(tag: '0.9.0')), 200)),
        installedVersion: '1.0.1+201',
      );

      expect(await service.checkForUpdates(), isA<UpdateUpToDate>());
    });

    test('reports a rate limit instead of an empty success', () async {
      final service = serviceWith(
        MockClient(
          (_) async =>
              http.Response('{"message":"API rate limit exceeded"}', 403, headers: {'x-ratelimit-remaining': '0'}),
        ),
      );

      final result = await service.checkForUpdates();

      expect(result, isA<UpdateCheckFailed>());
      expect((result as UpdateCheckFailed).error.kind, UpdateErrorKind.rateLimit);
    });

    test('maps transport failures to a network error', () async {
      final service = serviceWith(MockClient((_) async => throw const SocketException('no route to host')));

      final result = await service.checkForUpdates();

      expect((result as UpdateCheckFailed).error.kind, UpdateErrorKind.network);
    });

    test('reports no releases when a repository only has prereleases', () async {
      final service = serviceWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/releases/latest')) return http.Response('{"message":"Not Found"}', 404);
          return http.Response(
            jsonEncode([releaseJson(tag: '2.0.0', prerelease: true), releaseJson(tag: '1.5.0', draft: true)]),
            200,
          );
        }),
      );

      final result = await service.checkForUpdates();

      expect((result as UpdateCheckFailed).error.kind, UpdateErrorKind.noReleases);
    });

    test('falls back to the release list when /latest 404s', () async {
      final service = serviceWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/releases/latest')) return http.Response('{"message":"Not Found"}', 404);
          return http.Response(
            jsonEncode([
              releaseJson(tag: '1.0.1', publishedAt: '2026-10-01T00:00:00Z'),
              releaseJson(tag: '1.0.2', publishedAt: '2026-10-17T00:00:00Z'),
            ]),
            200,
          );
        }),
      );

      final result = await service.checkForUpdates();

      expect(result, isA<UpdateAvailable>());
      expect((result as UpdateAvailable).release.version, const AppVersion(1, 0, 2));
    });

    test('reports a release without a usable APK', () async {
      final service = serviceWith(
        MockClient(
          (_) async => http.Response(
            jsonEncode(
              releaseJson(
                assets: [
                  {'name': 'Extify-1.0.2-linux.tar.gz', 'size': 10, 'browser_download_url': 'https://x/linux'},
                ],
              ),
            ),
            200,
          ),
        ),
      );

      final result = await service.checkForUpdates();

      expect((result as UpdateCheckFailed).error.kind, UpdateErrorKind.noCompatibleApk);
    });

    test('reports a malformed payload instead of throwing', () async {
      final service = serviceWith(MockClient((_) async => http.Response('not json', 200)));

      final result = await service.checkForUpdates();

      expect((result as UpdateCheckFailed).error.kind, UpdateErrorKind.malformedResponse);
    });
  });

  group('downloadAsset', () {
    test('streams to disk and reports progress', () async {
      final bytes = Uint8List.fromList(List<int>.generate(1024, (index) => index % 251));
      final directory = await Directory.systemTemp.createTemp('extify-update-test');
      addTearDown(() => directory.delete(recursive: true));

      final service = serviceWith(
        MockClient((request) async {
          expect(request.url.toString(), 'https://example.test/app-release.apk');
          return http.Response.bytes(bytes, 200, headers: {'content-length': bytes.length.toString()});
        }),
      );

      final asset = ReleaseAsset(
        name: 'app-release.apk',
        size: bytes.length,
        downloadUrl: Uri.parse('https://example.test/app-release.apk'),
        sha256: null,
      );

      final progress = <int>[];
      final file = await service.downloadAsset(
        asset: asset,
        directory: directory,
        onProgress: (received, total) => progress.add(received),
      );

      expect(await file.readAsBytes(), bytes);
      expect(file.path, endsWith('app-release.apk'));
      expect(progress.isNotEmpty, isTrue);
      expect(progress.last, bytes.length);
      // No partial file is left behind on success.
      expect(File('${file.path}.part').existsSync(), isFalse);
    });

    test('deletes the partial file and reports a download error', () async {
      final directory = await Directory.systemTemp.createTemp('extify-update-test-fail');
      addTearDown(() => directory.delete(recursive: true));

      final service = serviceWith(MockClient((_) async => http.Response('nope', 500)));
      final asset = ReleaseAsset(
        name: 'app-release.apk',
        size: 10,
        downloadUrl: Uri.parse('https://example.test/a.apk'),
      );

      await expectLater(
        service.downloadAsset(asset: asset, directory: directory),
        throwsA(isA<UpdateException>().having((e) => e.kind, 'kind', UpdateErrorKind.download)),
      );
      expect(File('${directory.path}${Platform.pathSeparator}app-release.apk.part').existsSync(), isFalse);
    });
  });

  group('startup check throttle', () {
    test('round-trips the last check timestamp', () async {
      final directory = await Directory.systemTemp.createTemp('extify-throttle-test');
      addTearDown(() => directory.delete(recursive: true));
      final marker = File('${directory.path}${Platform.pathSeparator}update_check.json');

      expect(await UpdateService.readLastCheck(marker), isNull);

      final when = DateTime.fromMillisecondsSinceEpoch(1750000000000);
      await UpdateService.writeLastCheck(marker, when);

      expect(await UpdateService.readLastCheck(marker), when);
    });

    test('treats a corrupt marker as no previous check', () async {
      final directory = await Directory.systemTemp.createTemp('extify-throttle-corrupt');
      addTearDown(() => directory.delete(recursive: true));
      final marker = File('${directory.path}${Platform.pathSeparator}update_check.json');
      await marker.writeAsString('{ not json');

      expect(await UpdateService.readLastCheck(marker), isNull);
    });
  });

  group('dismissed release memory', () {
    test('round-trips the dismissed release version', () async {
      final directory = await Directory.systemTemp.createTemp('extify-dismiss-test');
      addTearDown(() => directory.delete(recursive: true));
      final marker = File('${directory.path}${Platform.pathSeparator}update_check.json');

      expect(await UpdateService.readDismissedVersion(marker), isNull);

      await UpdateService.writeDismissedVersion(marker, '1.0.3');

      expect(await UpdateService.readDismissedVersion(marker), const AppVersion(1, 0, 3));
    });

    test('ignores a dismissed version that cannot be parsed', () async {
      final directory = await Directory.systemTemp.createTemp('extify-dismiss-garbage');
      addTearDown(() => directory.delete(recursive: true));
      final marker = File('${directory.path}${Platform.pathSeparator}update_check.json');
      await marker.writeAsString(jsonEncode({'dismissedVersion': 'next tuesday'}));

      expect(await UpdateService.readDismissedVersion(marker), isNull);
    });

    test('the cooldown and the dismissed version do not overwrite each other', () async {
      final directory = await Directory.systemTemp.createTemp('extify-marker-merge');
      addTearDown(() => directory.delete(recursive: true));
      final marker = File('${directory.path}${Platform.pathSeparator}update_check.json');
      final when = DateTime.fromMillisecondsSinceEpoch(1750000000000);

      await UpdateService.writeDismissedVersion(marker, '1.0.3');
      await UpdateService.writeLastCheck(marker, when);
      expect(await UpdateService.readDismissedVersion(marker), const AppVersion(1, 0, 3));

      await UpdateService.writeDismissedVersion(marker, '1.0.4');
      expect(await UpdateService.readLastCheck(marker), when);
      expect(await UpdateService.readDismissedVersion(marker), const AppVersion(1, 0, 4));
    });

    test('prompts for anything until a release is dismissed, then only for newer ones', () {
      expect(UpdateService.shouldPromptFor(const AppVersion(1, 0, 3), null), isTrue);
      expect(UpdateService.shouldPromptFor(const AppVersion(1, 0, 3), const AppVersion(1, 0, 2)), isTrue);
      expect(UpdateService.shouldPromptFor(const AppVersion(1, 0, 3), const AppVersion(1, 0, 3)), isFalse);
      expect(UpdateService.shouldPromptFor(const AppVersion(1, 0, 3), const AppVersion(1, 0, 4)), isFalse);
    });
  });

  group('downloaded APK validation', () {
    InstalledAppInfo installed({List<String>? digests}) => InstalledAppInfo(
      packageName: 'com.expuz.extify',
      versionName: '1.0.1',
      versionCode: 201,
      signingSha256: 'debugcert',
      signingSha256All: digests ?? const ['debugcert'],
    );

    ApkInfo apk({
      String packageName = 'com.expuz.extify',
      String versionName = '1.0.2',
      int versionCode = 202,
      String fileSha256 = 'good',
      List<String>? signing,
    }) => ApkInfo(
      packageName: packageName,
      versionName: versionName,
      versionCode: versionCode,
      signingSha256: (signing ?? const ['debugcert']).first,
      signingSha256All: signing ?? const ['debugcert'],
      fileSha256: fileSha256,
      bytes: 100,
    );

    final asset = ReleaseAsset(
      name: 'app.apk',
      size: 100,
      downloadUrl: Uri.parse('https://example.test/app.apk'),
      sha256: 'good',
    );

    test('accepts a matching APK', () {
      final validation = UpdateInstaller.validate(apk: apk(), installed: installed(), asset: asset);
      expect(validation.isValid, isTrue, reason: validation.problems.toString());
    });

    test('accepts a match through a rotated signing history', () {
      final validation = UpdateInstaller.validate(
        apk: apk(signing: ['newcert']),
        installed: installed(digests: ['newcert', 'oldcert']),
        asset: asset,
      );
      expect(validation.isValid, isTrue);
    });

    test('rejects a checksum mismatch', () {
      final validation = UpdateInstaller.validate(
        apk: apk(fileSha256: 'tampered'),
        installed: installed(),
        asset: asset,
      );
      expect(validation.problems, contains(ApkValidationProblem.checksumMismatch));
    });

    test('rejects a size mismatch', () {
      final big = ApkInfo(
        packageName: 'com.expuz.extify',
        versionName: '1.0.2',
        versionCode: 202,
        signingSha256: 'debugcert',
        signingSha256All: const ['debugcert'],
        fileSha256: 'good',
        bytes: 999,
      );
      final validation = UpdateInstaller.validate(apk: big, installed: installed(), asset: asset);
      expect(validation.problems, contains(ApkValidationProblem.sizeMismatch));
    });

    test('rejects a different application ID', () {
      final validation = UpdateInstaller.validate(
        apk: apk(packageName: 'com.evil.clone'),
        installed: installed(),
        asset: asset,
      );
      expect(validation.problems, contains(ApkValidationProblem.packageMismatch));
    });

    test('rejects a different signing certificate', () {
      final validation = UpdateInstaller.validate(
        apk: apk(signing: ['attacker']),
        installed: installed(),
        asset: asset,
      );
      expect(validation.problems, contains(ApkValidationProblem.signatureMismatch));
    });

    test('rejects an older build', () {
      final validation = UpdateInstaller.validate(
        apk: apk(versionName: '1.0.0', versionCode: 150),
        installed: installed(),
        asset: asset,
      );
      expect(validation.problems, contains(ApkValidationProblem.versionOlderThanInstalled));
    });

    test('skips checksum verification when GitHub publishes no digest', () {
      final noDigest = ReleaseAsset(name: 'app.apk', size: 100, downloadUrl: Uri.parse('https://example.test/app.apk'));
      expect(
        UpdateInstaller.validate(
          apk: apk(fileSha256: 'anything'),
          installed: installed(),
          asset: noDigest,
        ).isValid,
        isTrue,
      );
    });
  });
}
