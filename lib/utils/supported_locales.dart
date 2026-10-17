import 'package:flutter/widgets.dart';

/// The only locales Extify offers in the language selector.
///
/// The full set of translations generated from `lib/l10n/*.arb` is still
/// present on disk, but only these two are exposed to the user. Device
/// languages outside this list fall back to English, since English is the
/// first entry of `MaterialApp.supportedLocales`.
const List<Locale> extifySupportedLocales = <Locale>[Locale("en"), Locale("id")];
