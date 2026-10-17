import 'dart:ui';

extension BlankString on String {
  bool get isBlank => trim().isEmpty;

  bool get isNotBlank => !isBlank;
}

extension NullableEmptyString on String? {
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}

extension NullableBlankString on String? {
  bool get isNullOrBlank => this == null || this!.isBlank;
}

extension NullableJoin on Iterable<String?> {
  /// Joins all non-null elements as String.  If none exist, returns null.
  String? joinNonNull([String separator = ""]) => nonNulls.isEmpty ? null : nonNulls.join(separator);
}

extension StringToColor on String {
  /// Converts a hex color string to a [Color] object.
  ///
  /// Accepts strings in the format:
  /// - "#RRGGBB" (without alpha channel; assumes full opacity)
  /// - "#AARRGGBB"
  ///
  /// Returns:
  /// - A [Color] if the string is valid.
  /// - `null` if the string does not match the expected length.
  ///
  /// Examples:
  /// ```
  /// "#FF5733".toColorOrNull();   // Color(0xFFFF5733)
  /// "#80FF5733".toColorOrNull(); // Color(0x80FF5733)
  /// "#XYZ".toColorOrNull();      // null
  /// ```
  Color? toColorOrNull() {
    final hex = replaceFirst('#', '');
    if (hex.length == 6) {
      return _parseColor('FF$hex');
    } else if (hex.length == 8) {
      return _parseColor(hex);
    }
    return null;
  }

  Color? _parseColor(String hex) {
    try {
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return null;
    }
  }
}
