import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/settings_service.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';

/// Root widget of the Tasbih application.
///
/// Reads the theme from [SettingsService] and renders the [HomeScreen].
class TasbihApp extends StatelessWidget {
  const TasbihApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    final themeMode = switch (settings.themeMode) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.system => ThemeMode.system,
    };

    return MaterialApp(
      title: 'Tasbih',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const HomeScreen(),
    );
  }
}
