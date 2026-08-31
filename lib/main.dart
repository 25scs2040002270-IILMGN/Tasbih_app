import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'database/database_helper.dart';
import 'models/dhikr.dart';
import 'services/counter_service.dart';
import 'services/feedback_service.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise services
  final dbHelper = DatabaseHelper();
  final settings = await SettingsService.create();
  final feedback = FeedbackService();

  // Load default Dhikr for the initial counter session
  final dhikrList = await dbHelper.getAllDhikr();
  final initialDhikr = dhikrList.isNotEmpty
      ? dhikrList.first
      : Dhikr(
          id: 1,
          name: 'SubhanAllah',
          arabic: 'سُبْحَانَ اللَّهِ',
          createdAt: DateTime.now().toIso8601String(),
        );

  final counterService = CounterService(
    dbHelper: dbHelper,
    settingsService: settings,
    feedbackService: feedback,
  );
  await counterService.init(initialDhikr);

  runApp(
    MultiProvider(
      providers: [
        Provider<DatabaseHelper>.value(value: dbHelper),
        Provider<FeedbackService>.value(value: feedback),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<CounterService>.value(value: counterService),
      ],
      child: const TasbihApp(),
    ),
  );
}
