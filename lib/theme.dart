import 'package:flutter/material.dart';

/// Design tokens. Resolve with [Pal.of] so widgets follow light/dark mode.
class Pal {
  const Pal._({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.outline,
    required this.text,
    required this.muted,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color outline;
  final Color text;
  final Color muted;

  bool get isDark => brightness == Brightness.dark;

  static const accent = Color(0xFFFF7A1A);
  static const red = Color(0xFFFF4D5E);
  static const amber = Color(0xFFFFB020);
  static const green = Color(0xFF22C58B);
  static const blue = Color(0xFF4C9AFF);
  static const violet = Color(0xFF8B7CFF);
  static const teal = Color(0xFF19C3D6);

  static const brand = LinearGradient(
    colors: [Color(0xFFFFA23D), Color(0xFFF0501E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Colours used to tint dashboard icons.
  static const series = [accent, blue, violet, teal, green, amber];

  static const dark = Pal._(
    brightness: Brightness.dark,
    bg: Color(0xFF0B0E14),
    surface: Color(0xFF131822),
    surface2: Color(0xFF1B2230),
    outline: Color(0xFF263045),
    text: Color(0xFFE8ECF4),
    muted: Color(0xFF8A95A9),
  );

  static const light = Pal._(
    brightness: Brightness.light,
    bg: Color(0xFFF3F5F9),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEDF0F6),
    outline: Color(0xFFE0E5EE),
    text: Color(0xFF111827),
    muted: Color(0xFF667085),
  );

  static Pal of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

OutlineInputBorder _border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c, width: 1.5),
    );

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Pal.dark : Pal.light;
  final scheme = ColorScheme.fromSeed(seedColor: Pal.accent, brightness: b)
      .copyWith(
    primary: Pal.accent,
    onPrimary: Colors.white,
    surface: p.surface,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    outline: p.outline,
    error: Pal.red,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: p.text),
      titleTextStyle: TextStyle(
        color: p.text,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Pal.accent.withOpacity(0.16),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? Pal.accent : p.muted,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 26,
            color: s.contains(WidgetState.selected) ? Pal.accent : p.muted,
          )),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: _border(Colors.transparent),
      enabledBorder: _border(Colors.transparent),
      focusedBorder: _border(Pal.accent),
      errorBorder: _border(Pal.red),
      focusedErrorBorder: _border(Pal.red),
      labelStyle: TextStyle(color: p.muted),
      hintStyle: TextStyle(color: p.muted),
      prefixIconColor: p.muted,
      suffixIconColor: p.muted,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Pal.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.surface2,
      contentTextStyle: TextStyle(color: p.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(color: p.outline, space: 1, thickness: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? Pal.accent : p.outline),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.outline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Pal.accent,
      linearTrackColor: Colors.transparent,
    ),
  );
}
