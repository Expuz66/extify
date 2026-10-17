import 'dart:async';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:finamp/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;

/// Extify: classifies failures from Jellyfin/HTTP calls into a small set of
/// cases that each have a friendly, localized message.
///
/// The point is to stop showing raw backend errors (URLs, status lines,
/// exception strings) to the user while still keeping the classification
/// testable and reusable across the login screen and the global error snackbar.
enum AppErrorKind {
  /// The device has no usable network connection at all.
  noNetwork,

  /// The server explicitly rejected the submitted login credentials
  /// (HTTP 401 on the authentication request itself).
  invalidCredentials,

  /// The server could not be reached: connection refused, DNS failure,
  /// timeout, TLS failure, ...
  serverUnreachable,

  /// The server answered, but with a server-side error (HTTP 5xx).
  serverTemporarilyUnavailable,

  /// Anything we cannot classify more precisely.
  unknown,
}

/// Returns the HTTP status code carried by [error], or `null` if [error] is not
/// an HTTP response failure.
///
/// Chopper's generated services call `Response.bodyOrThrow`, which throws a
/// [ChopperHttpException] carrying the [Response] for unsuccessful requests.
/// Raw [Response]s and other [ChopperException]s are handled too so callers do
/// not need to know which of them they received.
int? httpStatusCodeOf(Object? error) {
  if (error is Response) return error.statusCode;
  if (error is ChopperHttpException) return error.response.statusCode;
  if (error is ChopperException) return error.response?.statusCode;
  return null;
}

/// Whether [error] is a transport-level failure, i.e. no HTTP response was
/// received at all.
///
/// Deliberately limited to network/dart:io transport types: a
/// [FileSystemException] (for example from a failed download write) must not be
/// reported as a connectivity problem.
bool isTransportError(Object? error) {
  return error is SocketException ||
      error is TimeoutException ||
      error is HandshakeException ||
      error is CertificateException ||
      error is HttpException ||
      error is http.ClientException;
}

/// Classifies [error] without performing any I/O.
///
/// [isAuthenticationRequest] must be `true` only for the login/authentication
/// request. A 401 from any other endpoint is *not* a credential failure, so it
/// is reported as [AppErrorKind.unknown] instead of
/// [AppErrorKind.invalidCredentials].
AppErrorKind classifyApiError(Object? error, {required bool isAuthenticationRequest}) {
  final statusCode = httpStatusCodeOf(error);

  if (statusCode != null) {
    if (statusCode == 401 && isAuthenticationRequest) {
      return AppErrorKind.invalidCredentials;
    }
    if (statusCode >= 500) {
      return AppErrorKind.serverTemporarilyUnavailable;
    }
    return AppErrorKind.unknown;
  }

  if (isTransportError(error)) {
    return AppErrorKind.serverUnreachable;
  }

  return AppErrorKind.unknown;
}

/// Reports whether the device currently has a usable network interface.
typedef NetworkAvailabilityProbe = Future<bool> Function();

/// Extify: probes the device's network interfaces.
///
/// Note that connectivity plugins only prove the *absence* of a connection
/// reliably. A reported Wi-Fi/mobile interface does not prove the internet (or
/// the Jellyfin server) is actually reachable, so this is only used to upgrade a
/// transport failure to [AppErrorKind.noNetwork] when there is no interface at
/// all. Actual reachability is always decided by the real request failing.
Future<bool> deviceHasNetworkInterface() async {
  try {
    final connections = await Connectivity().checkConnectivity();
    return !connections.contains(ConnectivityResult.none);
  } catch (_) {
    // If the platform cannot answer, assume a connection exists so a
    // server-side problem is not misreported as a missing internet connection.
    return true;
  }
}

/// Like [classifyApiError], but refines an unreachable server into
/// [AppErrorKind.noNetwork] when the device has no network interface.
///
/// [hasNetwork] is injectable so the classification can be unit tested without
/// platform channels.
Future<AppErrorKind> classifyApiErrorWithConnectivity(
  Object? error, {
  required bool isAuthenticationRequest,
  NetworkAvailabilityProbe? hasNetwork,
}) async {
  final kind = classifyApiError(error, isAuthenticationRequest: isAuthenticationRequest);

  if (kind != AppErrorKind.serverUnreachable) return kind;

  final probe = hasNetwork ?? deviceHasNetworkInterface;
  return await probe() ? AppErrorKind.serverUnreachable : AppErrorKind.noNetwork;
}

/// The short title shown for [kind].
String appErrorTitle(AppLocalizations l10n, AppErrorKind kind) => switch (kind) {
  AppErrorKind.noNetwork => l10n.errorNoInternetConnection,
  AppErrorKind.invalidCredentials => l10n.errorIncorrectCredentials,
  AppErrorKind.serverUnreachable => l10n.errorUnableToConnectToServer,
  AppErrorKind.serverTemporarilyUnavailable => l10n.errorServerTemporarilyUnavailable,
  AppErrorKind.unknown => l10n.errorSomethingWentWrong,
};

/// The optional supporting sentence shown underneath the title for [kind].
String? appErrorBody(AppLocalizations l10n, AppErrorKind kind) => switch (kind) {
  AppErrorKind.noNetwork => l10n.errorNoInternetConnectionBody,
  AppErrorKind.invalidCredentials => l10n.errorIncorrectCredentialsBody,
  _ => null,
};

/// Whether retrying the failed operation can reasonably succeed without the user
/// changing any input first. Wrong credentials are not retryable: the user has
/// to edit the username or password.
bool appErrorIsRetryable(AppErrorKind kind) => kind != AppErrorKind.invalidCredentials;

/// The full localized message for [kind], with the supporting sentence on a
/// second line when the kind has one.
String appErrorDisplayText(AppLocalizations l10n, AppErrorKind kind) {
  final title = appErrorTitle(l10n, kind);
  final body = appErrorBody(l10n, kind);
  return body == null ? title : "$title\n$body";
}

/// A short, credential-free description of [error] for diagnostic logs.
///
/// Never includes the request body, headers or exception messages that could
/// contain credentials. Login request bodies are additionally censored by
/// `censored_log.dart` before being stored or exported.
String describeErrorForLog(Object? error) {
  final statusCode = httpStatusCodeOf(error);
  if (statusCode != null) {
    return "HTTP $statusCode (${error.runtimeType})";
  }
  if (isTransportError(error)) {
    // Transport exception messages describe the socket/DNS failure only and
    // never contain the request body.
    return "${error.runtimeType}: $error";
  }
  return error.runtimeType.toString();
}
