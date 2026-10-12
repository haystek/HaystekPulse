import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Haystek Pulse colours: Haystek blue on a cool light ground, with a
/// near-black ink for text and the strongest surfaces.
class AppColors {
  static const Color blue = Color(0xFF1B4FD8);
  static const Color blueDeep = Color(0xFF123A9E);
  static const Color blueTint = Color(0xFFE4ECFF);
  static const Color blueSoft = Color(0xFFDCE6FF);
  static const Color replyTint = Color(0xFFEEF3FF);
  static const Color ink = Color(0xFF0E1A3A);
  static const Color muted = Color(0xFF55607A);
  static const Color background = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE3E8F2);
  static const Color inputBorder = Color(0xFFC9CFD9);
  static const Color alert = Color(0xFFE0562F);

  // Older names still used by a few screens.
  static const Color navy = blueDeep;
  static const Color text = ink;
  static const Color green = ink;
  static const Color success = blue;
}

/// Bricolage Grotesque for headings and numbers. Body text is Figtree
/// (set in the theme below).
TextStyle heading(
    double size, {
      Color color = AppColors.ink,
      FontWeight weight = FontWeight.w600,
      double height = 1.15,
    }) {
  return GoogleFonts.bricolageGrotesque(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: size >= 24 ? -0.6 : -0.2,
  );
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.blue,
    primary: AppColors.blue,
    surface: Colors.white,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    outlineVariant: AppColors.border,
    error: const Color(0xFFC0341D),
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final textTheme = GoogleFonts.figtreeTextTheme(base.textTheme).apply(
    bodyColor: AppColors.ink,
    displayColor: AppColors.ink,
  );

  OutlineInputBorder inputBorder(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  final buttonText = GoogleFonts.figtree(
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  return base.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.figtree(
        color: AppColors.ink,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 52),
        shape: const StadiumBorder(),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(64, 46),
        side: const BorderSide(color: AppColors.ink, width: 1.5),
        shape: const StadiumBorder(),
        textStyle: buttonText.copyWith(fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.blue,
        textStyle: buttonText.copyWith(fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: inputBorder(AppColors.inputBorder, 1.5),
      enabledBorder: inputBorder(AppColors.inputBorder, 1.5),
      focusedBorder: inputBorder(AppColors.ink, 1.5),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      actionTextColor: AppColors.blueSoft,
      contentTextStyle: GoogleFonts.figtree(color: Colors.white, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
  );
}