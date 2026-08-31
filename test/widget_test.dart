import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tasbih/app.dart';
import 'package:tasbih/database/database_helper.dart';
import 'package:tasbih/services/counter_service.dart';
import 'package:tasbih/services/feedback_service.dart';
import 'package:tasbih/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('App smoke test: renders MaterialApp', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'vibration': false,
      'sound': false,
      'default_target': 33,
    });

    final dbHelper = DatabaseHelper();
    final settings = await SettingsService.create();
    final feedback = FeedbackService();
    final counterService = CounterService(
      dbHelper: dbHelper,
      settingsService: settings,
      feedbackService: feedback,
    );

    // Do NOT call counterService.init() — this avoids a real DB lookup that
    // times out in pure widget test mode on CI. The home screen shows the
    // empty-state ("Choose Dhikr") when hasSession is false.
    await tester.pumpWidget(
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

    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    // App bar title
    expect(find.text('Tasbih'), findsOneWidget);
  });
}
