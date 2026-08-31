import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:tasbih/database/database_helper.dart';
import 'package:tasbih/models/dhikr.dart';
import 'package:tasbih/models/session.dart';
import 'package:tasbih/services/backup_service.dart';
import 'package:tasbih/services/counter_service.dart';
import 'package:tasbih/services/settings_service.dart';
import 'package:tasbih/utils/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // ─── DatabaseHelper CRUD & Statistics Tests ──────────────────────────────

  group('DatabaseHelper CRUD & Statistics Tests', () {
    late DatabaseHelper dbHelper;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dbHelper = DatabaseHelper();
      // Clean sessions before each test for isolation
      final db = await dbHelper.database;
      await db.delete(DatabaseHelper.tableSession);
    });

    test('Default Dhikrs are present and accessible', () async {
      final list = await dbHelper.getAllDhikr();
      expect(list.isNotEmpty, isTrue);
      expect(list.any((d) => d.name == 'SubhanAllah'), isTrue);
      expect(list.any((d) => d.name == 'Alhamdulillah'), isTrue);
      expect(list.any((d) => d.name == 'Allahu Akbar'), isTrue);
      expect(list.any((d) => d.name == 'Astaghfirullah'), isTrue);
    });

    test('Custom Dhikr can be added, updated, and deleted', () async {
      final now = DateTime.now().toIso8601String();
      final customDhikr = Dhikr(
        name: 'Ayat al-Kursi',
        arabic: 'اللَّهُ لَا إِلَهَ إِلَّا هُوَ',
        isCustom: true,
        createdAt: now,
      );

      // Create
      final id = await dbHelper.insertDhikr(customDhikr);
      expect(id, isNotNull);

      // Read
      final fetched = await dbHelper.getDhikrById(id);
      expect(fetched, isNotNull);
      expect(fetched!.name, equals('Ayat al-Kursi'));
      expect(fetched.isCustom, isTrue);

      // Update
      final updated = fetched.copyWith(name: 'Ayatul Kursi');
      await dbHelper.updateDhikr(updated);
      final fetchedUpdated = await dbHelper.getDhikrById(id);
      expect(fetchedUpdated!.name, equals('Ayatul Kursi'));

      // Delete
      await dbHelper.deleteDhikr(id);
      final fetchedDeleted = await dbHelper.getDhikrById(id);
      expect(fetchedDeleted, isNull);
    });

    test('Session upsert and date range totals compute accurately', () async {
      final now = DateTime.now().toIso8601String();
      const testDate = '2026-08-28';

      final session1 = Session(
        dhikrId: 1,
        dhikrName: 'SubhanAllah',
        count: 33,
        target: 33,
        date: testDate,
        createdAt: now,
        updatedAt: now,
      );
      await dbHelper.upsertSession(session1);

      final session2 = Session(
        dhikrId: 2,
        dhikrName: 'Alhamdulillah',
        count: 67,
        target: 100,
        date: testDate,
        createdAt: now,
        updatedAt: now,
      );
      await dbHelper.upsertSession(session2);

      final total = await dbHelper.getTotalForDate(testDate);
      expect(total, equals(100));

      final breakdown = await dbHelper.getDhikrBreakdownForDate(testDate);
      expect(breakdown.length, equals(2));
      expect(
        breakdown.firstWhere((b) => b['dhikr_name'] == 'Alhamdulillah')['count'],
        equals(67),
      );
    });

    test('Session created_at is preserved on update', () async {
      final originalCreatedAt = '2026-01-01T10:00:00.000';
      const testDate = '2026-08-28';

      final original = Session(
        dhikrId: 1,
        dhikrName: 'SubhanAllah',
        count: 10,
        target: 33,
        date: testDate,
        createdAt: originalCreatedAt,
        updatedAt: originalCreatedAt,
      );
      final id = await dbHelper.upsertSession(original);

      // Update with a later updatedAt but the same session ID
      final updatedAt = DateTime.now().toIso8601String();
      final updated = Session(
        id: id,
        dhikrId: 1,
        dhikrName: 'SubhanAllah',
        count: 25,
        target: 33,
        date: testDate,
        createdAt: 'this-should-be-ignored',
        updatedAt: updatedAt,
      );
      await dbHelper.upsertSession(updated);

      // Re-fetch and check that created_at was not overwritten
      final fetched = await dbHelper.getSessionForDate(1, testDate);
      expect(fetched, isNotNull);
      expect(fetched!.count, equals(25));
      expect(fetched.createdAt, equals(originalCreatedAt),
          reason: 'created_at must be preserved on update');
    });

    test('getCustomDhikr returns only custom entries', () async {
      final now = DateTime.now().toIso8601String();
      await dbHelper.insertDhikr(Dhikr(
        name: 'TestCustom',
        arabic: '',
        isCustom: true,
        createdAt: now,
      ));

      final custom = await dbHelper.getCustomDhikr();
      expect(custom.every((d) => d.isCustom), isTrue);
      expect(custom.any((d) => d.name == 'TestCustom'), isTrue);
      // Default Dhikrs must not appear in custom list
      expect(custom.any((d) => d.name == 'SubhanAllah'), isFalse);
    });
  });

  // ─── CounterService Stateful & UX Tests ──────────────────────────────────

  group('CounterService Stateful & UX Tests', () {
    late DatabaseHelper dbHelper;
    late SettingsService settings;
    late CounterService counter;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'vibration': false,
        'sound': false,
        'default_target': 33,
      });

      dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      await db.delete(DatabaseHelper.tableSession);

      settings = await SettingsService.create();
      counter = CounterService(dbHelper: dbHelper, settingsService: settings);

      final testDhikr = Dhikr(
        id: 1,
        name: 'SubhanAllah',
        arabic: 'سُبْحَانَ اللَّهِ',
        createdAt: DateTime.now().toIso8601String(),
      );
      await counter.init(testDhikr);
    });

    test('Increment updates count and todayTotal', () {
      expect(counter.count, equals(0));
      expect(counter.todayTotal, equals(0));

      counter.increment();
      expect(counter.count, equals(1));
      expect(counter.todayTotal, equals(1));
      expect(counter.canUndo, isTrue);
    });

    test('Rapid tapping (100 taps) increments count to 100', () {
      for (int i = 0; i < 100; i++) {
        counter.increment();
      }
      expect(counter.count, equals(100));
      expect(counter.todayTotal, equals(100));
    });

    test('Undo removes last increment', () async {
      counter.increment(); // 1
      counter.increment(); // 2
      counter.increment(); // 3
      expect(counter.count, equals(3));

      await counter.undo();
      expect(counter.count, equals(2));
      expect(counter.todayTotal, equals(2));
    });

    test('Reset zeros count and adjusts todayTotal', () async {
      counter.increment();
      counter.increment();
      counter.increment();
      expect(counter.count, equals(3));

      await counter.reset();
      expect(counter.count, equals(0));
      expect(counter.todayTotal, equals(0));
      expect(counter.canUndo, isFalse);
    });

    test('Target reached activates celebration state', () async {
      await counter.setTarget(3);
      expect(counter.target, equals(3));

      counter.increment(); // 1
      expect(counter.isTargetReached, isFalse);

      counter.increment(); // 2
      expect(counter.isTargetReached, isFalse);

      counter.increment(); // 3 (hit target)
      expect(counter.isTargetReached, isTrue);
      expect(counter.targetReachedFlag, isTrue);

      counter.increment(); // 4 (exceeded target — should still work)
      expect(counter.isTargetReached, isTrue);
      expect(counter.count, equals(4));
    });
  });

  // ─── BackupService Round-Trip Tests ──────────────────────────────────────

  group('BackupService Validation Tests', () {
    late DatabaseHelper dbHelper;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        kPrefDefaultTarget: 33,
        kPrefVibration: true,
        kPrefSound: false,
        kPrefTheme: 0,
      });
      dbHelper = DatabaseHelper();
      final db = await dbHelper.database;
      await db.delete(DatabaseHelper.tableSession);
    });

    test('Valid backup JSON is parsed correctly', () {
      final svc = BackupService(dbHelper: dbHelper);
      const json = '''
{
  "schema_version": 1,
  "app": "tasbih",
  "exported_at": "2026-08-29T10:00:00.000",
  "settings": { "default_target": 99, "vibration": true, "sound": false, "theme_mode": 0 },
  "custom_dhikr": [
    { "name": "Test Dhikr", "arabic": "", "created_at": "2026-08-29T10:00:00.000" }
  ],
  "sessions": [
    {
      "dhikr_id": 1, "dhikr_name": "SubhanAllah", "count": 33, "target": 33,
      "date": "2026-08-28", "created_at": "2026-08-28T10:00:00.000",
      "updated_at": "2026-08-28T10:05:00.000"
    }
  ]
}
''';
      // Access via public validation method (reflection of internal method)
      final result = svc.parseJsonForTest(json);
      expect(result, isNotNull);
      expect(result!.customDhikr.length, equals(1));
      expect(result.sessions.length, equals(1));
      expect(result.settings['default_target'], equals(99));
    });

    test('Invalid JSON is rejected gracefully', () {
      final svc = BackupService(dbHelper: dbHelper);
      expect(
        () => svc.parseJsonForTest('this is not json {{{'),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('Wrong app field is rejected', () {
      final svc = BackupService(dbHelper: dbHelper);
      const json = '{"schema_version": 1, "app": "other_app", "custom_dhikr": [], "sessions": []}';
      expect(
        () => svc.parseJsonForTest(json),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('Missing schema_version is rejected', () {
      final svc = BackupService(dbHelper: dbHelper);
      const json = '{"app": "tasbih", "custom_dhikr": [], "sessions": []}';
      expect(
        () => svc.parseJsonForTest(json),
        throwsA(isA<BackupValidationException>()),
      );
    });

    test('Backup import: sessions are imported without duplicating', () async {
      final svc = BackupService(dbHelper: dbHelper);
      const json = '''
{
  "schema_version": 1,
  "app": "tasbih",
  "exported_at": "2026-08-29T10:00:00.000",
  "settings": { "default_target": 33, "vibration": true, "sound": false, "theme_mode": 0 },
  "custom_dhikr": [],
  "sessions": [
    {
      "dhikr_id": 1, "dhikr_name": "SubhanAllah", "count": 50, "target": 33,
      "date": "2026-07-01", "created_at": "2026-07-01T10:00:00.000",
      "updated_at": "2026-07-01T10:05:00.000"
    }
  ]
}
''';
      final data = svc.parseJsonForTest(json)!;

      // First import — should succeed
      final result1 = await svc.importBackup(data);
      expect(result1.success, isTrue);
      expect(result1.sessionsImported, equals(1));

      // Second import of same data — should skip duplicates
      final result2 = await svc.importBackup(data);
      expect(result2.success, isTrue);
      expect(result2.sessionsImported, equals(0),
          reason: 'Duplicate session on same date+dhikr must not be imported again');

      // Verify count is still 50 (not 100 from a hypothetical double import)
      final total = await dbHelper.getTotalForDate('2026-07-01');
      expect(total, equals(50));
    });
  });
}
