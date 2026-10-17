import 'package:finamp/components/LoginScreen/login_flow.dart';
import 'package:finamp/utils/supported_locales.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the Extify configuration that must not drift: the fixed Jellyfin
/// server the onboarding flow authenticates against, and the two offered
/// languages. These are cheap assertions on top-level constants, so they run
/// without any platform channel.
void main() {
  group('Extify configuration invariants', () {
    test('the fixed Jellyfin server URL is the expected https address', () {
      expect(extifyDefaultServerUrl, 'https://stream.expuz-server.my.id');

      final uri = Uri.parse(extifyDefaultServerUrl);
      expect(uri.scheme, 'https');
      expect(uri.host, 'stream.expuz-server.my.id');
    });

    test('the fixed server URL has no trailing slash or path suffix', () {
      // The Jellyfin API client appends its own path segments.
      expect(extifyDefaultServerUrl.endsWith('/'), isFalse);
      expect(Uri.parse(extifyDefaultServerUrl).path, isEmpty);
    });

    test('only English and Indonesian are offered', () {
      expect(extifySupportedLocales, equals(const <Locale>[Locale('en'), Locale('id')]));
    });

    test('English is first so it is the fallback locale', () {
      expect(extifySupportedLocales.first, const Locale('en'));
    });
  });
}
