import 'dart:async';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:finamp/l10n/app_localizations_en.dart';
import 'package:finamp/l10n/app_localizations_id.dart';
import 'package:finamp/services/app_error_classifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// The exception chopper's generated services throw for an unsuccessful
/// response (`Response.bodyOrThrow` -> `ChopperHttpException`).
Object httpFailure(int statusCode) => ChopperHttpException(Response(http.Response('', statusCode), null));

void main() {
  final en = AppLocalizationsEn();
  final id = AppLocalizationsId();

  group('httpStatusCodeOf', () {
    test('reads the status from the exception chopper throws', () {
      expect(httpStatusCodeOf(httpFailure(401)), 401);
      expect(httpStatusCodeOf(httpFailure(503)), 503);
    });

    test('reads the status from a raw chopper response', () {
      expect(httpStatusCodeOf(Response(http.Response('', 500), null)), 500);
    });

    test('returns null for errors that are not HTTP responses', () {
      expect(httpStatusCodeOf(SocketException('nope')), isNull);
      expect(httpStatusCodeOf(TimeoutException('slow')), isNull);
      expect(httpStatusCodeOf(Exception('boom')), isNull);
    });
  });

  group('classifyApiError', () {
    test('401 on the authentication request is a credential failure', () {
      expect(classifyApiError(httpFailure(401), isAuthenticationRequest: true), AppErrorKind.invalidCredentials);
    });

    test('401 from an unrelated endpoint is not a credential failure', () {
      expect(classifyApiError(httpFailure(401), isAuthenticationRequest: false), AppErrorKind.unknown);
    });

    test('5xx is reported as temporarily unavailable', () {
      for (final status in [500, 502, 503, 504]) {
        expect(
          classifyApiError(httpFailure(status), isAuthenticationRequest: true),
          AppErrorKind.serverTemporarilyUnavailable,
          reason: 'HTTP $status',
        );
      }
    });

    test('other HTTP statuses are unknown', () {
      for (final status in [400, 403, 404, 418, 429]) {
        expect(classifyApiError(httpFailure(status), isAuthenticationRequest: true), AppErrorKind.unknown);
      }
    });

    test('transport failures are unreachable-server failures', () {
      final transportErrors = <Object>[
        SocketException('Connection refused'),
        TimeoutException('timed out'),
        HandshakeException('bad certificate'),
        HttpException('bad response'),
        http.ClientException('failed'),
      ];
      for (final error in transportErrors) {
        expect(
          classifyApiError(error, isAuthenticationRequest: true),
          AppErrorKind.serverUnreachable,
          reason: '${error.runtimeType} should be a transport failure',
        );
      }
    });

    test('a timeout is never reported as wrong credentials', () {
      expect(
        classifyApiError(TimeoutException('slow'), isAuthenticationRequest: true),
        isNot(AppErrorKind.invalidCredentials),
      );
      expect(classifyApiError(httpFailure(503), isAuthenticationRequest: true), isNot(AppErrorKind.invalidCredentials));
    });

    test('a failed file write is not treated as a connectivity problem', () {
      expect(
        classifyApiError(const FileSystemException('disk full'), isAuthenticationRequest: true),
        AppErrorKind.unknown,
      );
    });

    test('unexpected errors are unknown', () {
      expect(classifyApiError(StateError('boom'), isAuthenticationRequest: true), AppErrorKind.unknown);
      expect(classifyApiError('boom', isAuthenticationRequest: true), AppErrorKind.unknown);
    });
  });

  group('classifyApiErrorWithConnectivity', () {
    Future<AppErrorKind> classify(Object error, {required bool online, bool isAuthenticationRequest = true}) =>
        classifyApiErrorWithConnectivity(
          error,
          isAuthenticationRequest: isAuthenticationRequest,
          hasNetwork: () async => online,
        );

    test('a transport failure with no network interface is "no internet"', () async {
      expect(await classify(SocketException('Failed host lookup'), online: false), AppErrorKind.noNetwork);
      expect(await classify(http.ClientException('failed'), online: false), AppErrorKind.noNetwork);
      expect(await classify(TimeoutException('slow'), online: false), AppErrorKind.noNetwork);
    });

    test('a transport failure with a network interface is an unreachable server', () async {
      expect(await classify(SocketException('Failed host lookup'), online: true), AppErrorKind.serverUnreachable);
    });

    test('connectivity is not consulted when the server answered', () async {
      // "online: false" would flip these to noNetwork if the probe were used.
      expect(await classify(httpFailure(401), online: false), AppErrorKind.invalidCredentials);
      expect(await classify(httpFailure(500), online: false), AppErrorKind.serverTemporarilyUnavailable);
    });
  });

  group('localized messages', () {
    test('English copy', () {
      expect(appErrorTitle(en, AppErrorKind.noNetwork), 'No internet connection');
      expect(appErrorBody(en, AppErrorKind.noNetwork), 'Check your internet connection and try again.');
      expect(appErrorTitle(en, AppErrorKind.invalidCredentials), 'Incorrect username or password');
      expect(appErrorBody(en, AppErrorKind.invalidCredentials), 'Please check your login details and try again.');
      expect(appErrorTitle(en, AppErrorKind.serverUnreachable), 'Unable to connect to server');
      expect(appErrorTitle(en, AppErrorKind.serverTemporarilyUnavailable), 'Server temporarily unavailable');
      expect(appErrorTitle(en, AppErrorKind.unknown), 'Something went wrong. Please try again.');
    });

    test('Indonesian copy', () {
      expect(appErrorTitle(id, AppErrorKind.noNetwork), 'Tidak ada koneksi internet');
      expect(appErrorBody(id, AppErrorKind.noNetwork), 'Periksa koneksi internet kamu, lalu coba lagi.');
      expect(appErrorTitle(id, AppErrorKind.invalidCredentials), 'Username atau password salah');
      expect(appErrorBody(id, AppErrorKind.invalidCredentials), 'Periksa kembali detail login kamu, lalu coba lagi.');
      expect(appErrorTitle(id, AppErrorKind.serverUnreachable), 'Tidak dapat terhubung ke server');
      expect(appErrorTitle(id, AppErrorKind.serverTemporarilyUnavailable), 'Server sementara tidak tersedia');
      expect(appErrorTitle(id, AppErrorKind.unknown), 'Terjadi kesalahan. Silakan coba lagi.');
    });

    test('messages never contain raw backend details', () {
      for (final localizations in [en, id]) {
        for (final kind in AppErrorKind.values) {
          final text = appErrorDisplayText(localizations, kind);
          expect(text, isNot(contains('http')));
          expect(text, isNot(contains('Status code')));
          expect(text, isNot(contains('Exception')));
          expect(text, isNot(contains('Kode status')));
        }
      }
    });

    test('display text combines title and supporting text', () {
      expect(
        appErrorDisplayText(en, AppErrorKind.noNetwork),
        'No internet connection\nCheck your internet connection and try again.',
      );
      expect(appErrorDisplayText(en, AppErrorKind.serverUnreachable), 'Unable to connect to server');
    });

    test('only wrong credentials are not retryable', () {
      expect(appErrorIsRetryable(AppErrorKind.invalidCredentials), isFalse);
      for (final kind in AppErrorKind.values.where((kind) => kind != AppErrorKind.invalidCredentials)) {
        expect(appErrorIsRetryable(kind), isTrue, reason: kind.name);
      }
    });
  });

  group('describeErrorForLog', () {
    test('reports only the status code for HTTP failures', () {
      final description = describeErrorForLog(httpFailure(401));
      expect(description, contains('401'));
      expect(description, isNot(contains('Username')));
      expect(description, isNot(contains('AuthenticationByName')));
    });

    test('does not leak an unexpected exception message', () {
      expect(describeErrorForLog(Exception('super-secret-password')), isNot(contains('super-secret-password')));
    });
  });
}
