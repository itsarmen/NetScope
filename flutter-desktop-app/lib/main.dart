/*
 * Project : NetScope
 * Author  : AMiran Kimadze (itsarmen)
 * GitHub  : https://github.com/itsarmen
 * Email   : amoswaper@gmail.com
 * Web     : https://xrow.asia
 */

import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

import 'app_state.dart';
import 'log_database.dart';
import 'settings.dart';
import 'ui/app_theme.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await YaruWindowTitleBar.ensureInitialized();

  final db = NetworkDatabase(NetworkDatabase.defaultPath())..open();
  final settingsStore = SettingsStore(SettingsStore.defaultPath());
  final state = AppState(db, settingsStore);

  runApp(NetScopeApp(state: state));
}

class NetScopeApp extends StatefulWidget {
  const NetScopeApp({super.key, required this.state});

  final AppState state;

  @override
  State<NetScopeApp> createState() => _NetScopeAppState();
}

class _NetScopeAppState extends State<NetScopeApp> {
  @override
  void initState() {
    super.initState();
    widget.state.init();
  }

  @override
  void dispose() {
    widget.state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YaruTheme(
      data: const YaruThemeData(variant: YaruVariant.orange),
      builder: (context, yaru, child) => MaterialApp(
        title: 'NetScope',
        debugShowCheckedModeBanner: false,
        theme: _cleanTheme(yaru.theme),
        themeMode: ThemeMode.light,
        home: HomePage(state: widget.state),
      ),
    );
  }

  /// White-outlined, soft-bordered, compact light style.
  ThemeData _cleanTheme(ThemeData base) {
    const white = Color(0xFFFFFFFF);
    final scheme = base.colorScheme.copyWith(
      primary: AppColors.accent,
      onPrimary: Colors.white,
      error: AppColors.error,
      surface: white,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.secondary,
      outline: AppColors.border,
      outlineVariant: AppColors.borderField,
    );

    final softOutline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radius),
      borderSide: const BorderSide(color: AppColors.borderField),
    );
    final focusOutline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radius),
      borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: white,
      cardColor: white,
      canvasColor: white,
      splashFactory: NoSplash.splashFactory,
      textSelectionTheme: const TextSelectionThemeData(
        selectionColor: AppColors.selection,
        cursorColor: AppColors.accent,
        selectionHandleColor: AppColors.accent,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.tooltipBg,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        waitDuration: const Duration(milliseconds: 400),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        space: 1,
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusPopup),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          backgroundColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          foregroundColor: AppColors.secondary,
          fixedSize: const Size.square(AppSizes.iconButton),
          padding: EdgeInsets.zero,
          iconSize: AppSizes.iconButtonIcon,
          minimumSize: const Size.square(AppSizes.iconButton),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.borderField),
          minimumSize: const Size(0, AppSizes.button),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: AppSizes.fontBody),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          minimumSize: const Size(0, AppSizes.button),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: AppSizes.fontBody),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: white,
          foregroundColor: AppColors.accent,
          side: const BorderSide(color: AppColors.accent, width: 1.5),
          minimumSize: const Size(0, AppSizes.button),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          textStyle: const TextStyle(fontSize: AppSizes.fontBody),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radius),
          ),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: AppColors.checkboxBorder),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.text
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll<Color>(Colors.white),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll<double>(8),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? AppColors.scrollbarHover
              : AppColors.scrollbar,
        ),
        trackColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        trackVisibility: const WidgetStatePropertyAll<bool>(false),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radius),
          side: const BorderSide(color: AppColors.border),
        ),
        textStyle: const TextStyle(
          fontSize: AppSizes.fontBody,
          color: AppColors.text,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll<Color>(white),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(
            Colors.transparent,
          ),
          side: const WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: AppColors.border),
          ),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radius),
            ),
          ),
        ),
      ),
      menuButtonTheme: MenuButtonThemeData(
        style: MenuItemButton.styleFrom(foregroundColor: AppColors.text),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll<Color>(white),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(
            Colors.transparent,
          ),
          side: const WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: AppColors.border),
          ),
        ),
        textStyle: const TextStyle(
          fontSize: AppSizes.fontBody,
          color: AppColors.text,
        ),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        filled: false,
        fillColor: Colors.transparent,
        prefixIconColor: AppColors.secondary,
        suffixIconColor: AppColors.secondary,
        enabledBorder: softOutline,
        focusedBorder: focusOutline,
      ),
    );
  }
}
