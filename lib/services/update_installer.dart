import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'update_service.dart';

/// Identity and integrity data for an APK file, read by the Android platform.
class ApkInfo {
  const ApkInfo({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.signingSha256,
    required this.signingSha256All,
    required this.fileSha256,
    required this.bytes,
  });

  final String packageName;
  final String versionName;
  final int versionCode;

  /// SHA-256 of the APK's primary signing certificate.
  final String signingSha256;

  /// Every signing certificate digest Android reported for the APK, so a key
  /// rotation history still matches.
  final List<String> signingSha256All;

  /// SHA-256 of the file itself.
  final String fileSha256;

  final int bytes;

  /// `versionName+versionCode`, so it can be compared with [AppVersion].
  AppVersion get version => AppVersion.tryParse('$versionName+$versionCode') ?? const AppVersion(0, 0, 0);

  factory ApkInfo.fromMap(Map<Object?, Object?> map) => ApkInfo(
    packageName: map['packageName'] as String? ?? '',
    versionName: map['versionName'] as String? ?? '',
    versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
    signingSha256: (map['signingSha256'] as String? ?? '').toLowerCase(),
    signingSha256All: _digestList(map['signingSha256All']),
    fileSha256: (map['fileSha256'] as String? ?? '').toLowerCase(),
    bytes: (map['bytes'] as num?)?.toInt() ?? 0,
  );
}

/// Identity of the currently installed app, from the platform package manager.
class InstalledAppInfo {
  const InstalledAppInfo({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.signingSha256,
    required this.signingSha256All,
  });

  final String packageName;
  final String versionName;
  final int versionCode;
  final String signingSha256;
  final List<String> signingSha256All;

  AppVersion get version => AppVersion.tryParse('$versionName+$versionCode') ?? const AppVersion(0, 0, 0);

  factory InstalledAppInfo.fromMap(Map<Object?, Object?> map) => InstalledAppInfo(
    packageName: map['packageName'] as String? ?? '',
    versionName: map['versionName'] as String? ?? '',
    versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
    signingSha256: (map['signingSha256'] as String? ?? '').toLowerCase(),
    signingSha256All: _digestList(map['signingSha256All']),
  );
}

/// Reads a platform-provided list of hex digests defensively.
List<String> _digestList(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<String>().map((digest) => digest.toLowerCase()).where((digest) => digest.isNotEmpty).toList();
}

/// A reason a downloaded APK must not be installed.
enum ApkValidationProblem {
  /// The file size does not match the size GitHub reports for the asset.
  sizeMismatch,

  /// The file's SHA-256 does not match the checksum published by GitHub.
  checksumMismatch,

  /// The APK targets a different application ID than the installed app.
  packageMismatch,

  /// The APK is older than the installed build, so Android would reject it.
  versionOlderThanInstalled,

  /// The APK is signed with a different certificate than the installed app,
  /// so Android would refuse the update.
  signatureMismatch,
}

class ApkValidation {
  const ApkValidation({required this.problems});

  /// Empty when the APK is safe to hand to the package installer.
  final List<ApkValidationProblem> problems;

  bool get isValid => problems.isEmpty;
}

/// Platform bridge for installing an update on Android.
///
/// All APK inspection happens in the Android package manager rather than by
/// parsing the APK in Dart, so the application ID and signing certificate are
/// read exactly the way Android itself reads them.
class UpdateInstaller {
  static const MethodChannel _channel = MethodChannel('com.unicornsonlsd.finamp/update_installer');

  /// In-app updating only makes sense where Android packages can be installed.
  static bool get isSupported => Platform.isAndroid;

  static Future<List<String>> supportedAbis() async {
    final abis = await _channel.invokeListMethod<String>('getSupportedAbis');
    return abis ?? const [];
  }

  static Future<InstalledAppInfo> installedApp() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('getInstalledAppInfo');
    if (map == null) {
      throw StateError('The platform returned no installed app information.');
    }
    return InstalledAppInfo.fromMap(map);
  }

  /// Directory the platform has whitelisted for the file provider, so the
  /// installer can read the APK from it.
  static Future<Directory> updateDirectory() async {
    final path = await _channel.invokeMethod<String>('getUpdateDir');
    if (path == null || path.isEmpty) {
      throw StateError('The platform returned no update directory.');
    }
    return Directory(path);
  }

  static Future<ApkInfo> inspectApk(File file) async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('inspectApk', {'path': file.path});
    if (map == null) {
      throw StateError('The platform could not read the downloaded file.');
    }
    return ApkInfo.fromMap(map);
  }

  /// Opens Android's package installer for [file].
  ///
  /// This is the supported install path: the OS shows its own confirmation UI
  /// and the user decides. Nothing is installed silently.
  static Future<void> installApk(File file) => _channel.invokeMethod<void>('installApk', {'path': file.path});

  /// Whether this app is currently allowed to request package installs.
  static Future<bool> canRequestPackageInstalls() async {
    try {
      return await Permission.requestInstallPackages.isGranted;
    } catch (_) {
      // permission_handler is unavailable: fall back to letting the system
      // installer ask the user itself.
      return false;
    }
  }

  /// Opens the "install unknown apps" screen when Android requires it.
  static Future<bool> requestPackageInstallPermission() async {
    try {
      final status = await Permission.requestInstallPackages.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Compares a downloaded APK against both the published release metadata and
  /// the installed app.
  static ApkValidation validate({
    required ApkInfo apk,
    required InstalledAppInfo installed,
    required ReleaseAsset asset,
  }) {
    final problems = <ApkValidationProblem>[];

    if (asset.size > 0 && apk.bytes != asset.size) {
      problems.add(ApkValidationProblem.sizeMismatch);
    }

    final expectedSha = asset.sha256?.toLowerCase();
    if (expectedSha != null && expectedSha.isNotEmpty && apk.fileSha256 != expectedSha) {
      problems.add(ApkValidationProblem.checksumMismatch);
    }

    if (apk.packageName != installed.packageName) {
      problems.add(ApkValidationProblem.packageMismatch);
    }

    if (apk.version.compareTo(installed.version) < 0) {
      problems.add(ApkValidationProblem.versionOlderThanInstalled);
    }

    if (!_signingCertificatesMatch(apk, installed)) {
      problems.add(ApkValidationProblem.signatureMismatch);
    }

    return ApkValidation(problems: problems);
  }

  /// True when Android would accept the APK as an update: some certificate the
  /// installed app was signed with also signed the APK. A key-rotation history
  /// on either side still matches.
  static bool _signingCertificatesMatch(ApkInfo apk, InstalledAppInfo installed) {
    final installedDigests = installed.signingSha256All.isNotEmpty
        ? installed.signingSha256All
        : [if (installed.signingSha256.isNotEmpty) installed.signingSha256];
    final apkDigests = apk.signingSha256All.isNotEmpty
        ? apk.signingSha256All
        : [if (apk.signingSha256.isNotEmpty) apk.signingSha256];

    // If Android reported nothing for one side we cannot judge; let the
    // installer decide rather than blocking a legitimate update.
    if (installedDigests.isEmpty || apkDigests.isEmpty) return true;

    return apkDigests.any(installedDigests.contains);
  }
}
