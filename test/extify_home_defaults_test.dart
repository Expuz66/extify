import 'package:finamp/models/finamp_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the Extify default home layout that a fresh install receives.
///
/// These defaults only seed a brand-new settings box (see `setupHive` in
/// `main.dart`, which writes `FinampSettings.create()` when the box is empty),
/// so they must stay exactly as designed: changing them changes what new users
/// see, while existing users keep their saved configuration.
void main() {
  group('Extify default home layout', () {
    test('only Home, Albums, Playlists and Tracks tabs are enabled', () {
      expect(DefaultSettings.showTabs[ContentType.home], isTrue);
      expect(DefaultSettings.showTabs[ContentType.albums], isTrue);
      expect(DefaultSettings.showTabs[ContentType.playlists], isTrue);
      expect(DefaultSettings.showTabs[ContentType.tracks], isTrue);

      expect(DefaultSettings.showTabs[ContentType.genericArtists], isFalse);
      expect(DefaultSettings.showTabs[ContentType.albumArtists], isFalse);
      expect(DefaultSettings.showTabs[ContentType.performingArtists], isFalse);
      expect(DefaultSettings.showTabs[ContentType.genres], isFalse);
    });

    test('the visible tab bar is ordered Home, Albums, Playlists, Tracks', () {
      // The music screen renders `tabOrder` filtered by `showTabs`.
      final visible = DefaultSettings.tabOrder
          .where((type) => type.isTab && (DefaultSettings.showTabs[type] ?? false))
          .toList();

      expect(visible, [ContentType.home, ContentType.albums, ContentType.playlists, ContentType.tracks]);
    });

    test('the four quick actions are enabled in the expected order', () {
      final actions = DefaultSettings.homeScreenConfiguration.actions.map((config) => config.action).toList();

      expect(actions, [
        FinampQuickActions.shuffleTracks,
        FinampQuickActions.playRandomFavoriteItem,
        FinampQuickActions.playPreviousQueue,
        FinampQuickActions.surpriseMe,
      ]);
    });

    test('the three home sections are configured in the expected order', () {
      final presets = DefaultSettings.homeScreenConfiguration.sections.map((section) => section.presetType).toList();

      expect(presets, [
        HomeScreenSectionPresetType.recentlyAddedAlbums,
        HomeScreenSectionPresetType.favoriteTracks,
        HomeScreenSectionPresetType.recentlyAddedPlaylists,
      ]);
    });

    test('the default home sections are all renderable presets', () {
      for (final section in DefaultSettings.homeScreenConfiguration.sections) {
        expect(section.presetType, isNotNull);
        expect(section.presetType!.isEnabled, isTrue);
      }
    });
  });
}
