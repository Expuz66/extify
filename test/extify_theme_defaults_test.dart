import 'package:finamp/models/finamp_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the Extify theme defaults a fresh install receives.
///
/// `main.dart` writes `FinampSettings.create()` (which uses the [FinampSettings]
/// constructor) only when the settings box is empty, so these values decide what
/// brand-new users see. Existing users keep whatever is already saved in Hive,
/// because the generated adapter always writes and reads every field.
void main() {
  group('Extify default theme preferences', () {
    test('AMOLED theme is enabled by default', () {
      expect(DefaultSettings.amoledTheme, isTrue);
    });

    test('the monochrome in-app logo is enabled by default', () {
      // This only affects the icon inside the app; the launcher icon is
      // generated separately and must not be touched by this default.
      expect(DefaultSettings.useMonochromeIcon, isTrue);
    });

    test('a freshly created settings object picks both defaults up', () {
      final settings = FinampSettings(
        downloadLocations: [],
        downloadLocationsMap: {},
        tabSortBy: {},
        tabSortOrder: {},
        homeScreenConfiguration: DefaultSettings.homeScreenConfiguration,
        gridImageSize: DefaultSettings.gridImageSize,
        homeScreenImageSize: DefaultSettings.homeScreenImageSize,
        deviceId: 'test-device',
      );

      expect(settings.amoledTheme, isTrue);
      expect(settings.useMonochromeIcon, isTrue);
    });
  });
}
