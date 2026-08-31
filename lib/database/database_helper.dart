import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/dhikr.dart';
import '../models/session.dart';
import '../utils/constants.dart';

/// Manages database operations for the Tasbih application.
///
/// On Native Android / Desktop: Uses SQLite (`sqflite` / `sqflite_common_ffi`) with indexing.
/// On Web: Uses SharedPreferences structured JSON persistence so data survives page refresh/restarts.
class DatabaseHelper {
  static const String _dbName = 'tasbih.db';
  static const int _dbVersion = 2;

  // Table names
  static const String tableDhikr = 'dhikr';
  static const String tableSession = 'sessions';

  // Web SharedPreferences storage keys
  static const String _spKeyWebDhikr = 'tasbih_offline_dhikr_data';
  static const String _spKeyWebSessions = 'tasbih_offline_sessions_data';

  Database? _database;

  // In-memory fallback state for Web
  final List<Dhikr> _webDhikrs = [];
  final List<Session> _webSessions = [];
  int _nextDhikrId = 1;
  int _nextSessionId = 1;
  bool _webInitialized = false;

  /// Returns the singleton [Database] instance on native platforms.
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    try {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.linux ||
              defaultTargetPlatform == TargetPlatform.macOS)) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      final dbPath = await getDatabasesPath();
      final path = join(dbPath, _dbName);

      return await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      debugPrint('Database initialization error: $e. Falling back to in-memory factory.');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Create Dhikr table
    await db.execute('''
      CREATE TABLE $tableDhikr (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        arabic TEXT NOT NULL DEFAULT '',
        is_custom INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // 2. Create Sessions table
    await db.execute('''
      CREATE TABLE $tableSession (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dhikr_id INTEGER NOT NULL,
        dhikr_name TEXT NOT NULL DEFAULT '',
        count INTEGER NOT NULL DEFAULT 0,
        target INTEGER NOT NULL DEFAULT 33,
        date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (dhikr_id) REFERENCES $tableDhikr (id) ON DELETE CASCADE
      )
    ''');

    // 3. Create Performance Indexes for scalable long-term queries
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_date ON $tableSession(date);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_dhikr_date ON $tableSession(dhikr_id, date);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_created_at ON $tableSession(created_at);');

    // 4. Seed default Dhikr entries
    final now = DateTime.now().toIso8601String();
    for (final entry in kDefaultDhikr) {
      await db.insert(tableDhikr, {
        'name': entry['name']!,
        'arabic': entry['arabic']!,
        'is_custom': 0,
        'created_at': now,
      });
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2: no structural changes; version bump reserves space for future migrations.
    // Add future ALTER TABLE statements here as additional versions are released.
    // Example for v3: if (oldVersion < 3) { await db.execute('ALTER TABLE ...'); }
  }

  // ─── Web Local Persistence ──────────────────────────────────────────────────

  Future<void> _initWebIfNeeded() async {
    if (_webInitialized) return;
    _webInitialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final dhikrJson = prefs.getString(_spKeyWebDhikr);
      final sessionsJson = prefs.getString(_spKeyWebSessions);

      if (dhikrJson != null && dhikrJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(dhikrJson);
        _webDhikrs.clear();
        for (final item in decoded) {
          _webDhikrs.add(Dhikr.fromMap(Map<String, dynamic>.from(item)));
        }
        if (_webDhikrs.isNotEmpty) {
          _nextDhikrId = _webDhikrs.map((d) => d.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
        }
      } else {
        // Seed defaults
        final now = DateTime.now().toIso8601String();
        for (final entry in kDefaultDhikr) {
          _webDhikrs.add(Dhikr(
            id: _nextDhikrId++,
            name: entry['name']!,
            arabic: entry['arabic']!,
            isCustom: false,
            createdAt: now,
          ));
        }
        await _saveWebDhikrs();
      }

      if (sessionsJson != null && sessionsJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(sessionsJson);
        _webSessions.clear();
        for (final item in decoded) {
          _webSessions.add(Session.fromMap(Map<String, dynamic>.from(item)));
        }
        if (_webSessions.isNotEmpty) {
          _nextSessionId = _webSessions.map((s) => s.id ?? 0).reduce((a, b) => a > b ? a : b) + 1;
        }
      }
    } catch (e) {
      debugPrint('Error initializing web storage: $e');
    }
  }

  Future<void> _saveWebDhikrs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_webDhikrs.map((d) => d.toMap()).toList());
      await prefs.setString(_spKeyWebDhikr, jsonStr);
    } catch (e) {
      debugPrint('Error saving web dhikrs: $e');
    }
  }

  Future<void> _saveWebSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_webSessions.map((s) => s.toMap()).toList());
      await prefs.setString(_spKeyWebSessions, jsonStr);
    } catch (e) {
      debugPrint('Error saving web sessions: $e');
    }
  }

  // ─── Dhikr CRUD ──────────────────────────────────────────────────────────────

  Future<List<Dhikr>> getAllDhikr() async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      return List<Dhikr>.from(_webDhikrs);
    }
    final db = await database;
    final maps = await db.query(tableDhikr, orderBy: 'is_custom ASC, id ASC');
    return maps.map(Dhikr.fromMap).toList();
  }

  /// Returns only user-created custom Dhikr entries.
  Future<List<Dhikr>> getCustomDhikr() async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      return _webDhikrs.where((d) => d.isCustom).toList();
    }
    final db = await database;
    final maps = await db.query(
      tableDhikr,
      where: 'is_custom = 1',
      orderBy: 'id ASC',
    );
    return maps.map(Dhikr.fromMap).toList();
  }

  Future<Dhikr?> getDhikrById(int id) async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      try {
        return _webDhikrs.firstWhere((d) => d.id == id);
      } catch (_) {
        return null;
      }
    }
    final db = await database;
    final maps = await db.query(
      tableDhikr,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Dhikr.fromMap(maps.first);
  }

  Future<int> insertDhikr(Dhikr dhikr) async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      final id = _nextDhikrId++;
      final newDhikr = dhikr.copyWith(id: id);
      _webDhikrs.add(newDhikr);
      await _saveWebDhikrs();
      return id;
    }
    final db = await database;
    return db.insert(tableDhikr, dhikr.toMap());
  }

  Future<int> updateDhikr(Dhikr dhikr) async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      final idx = _webDhikrs.indexWhere((d) => d.id == dhikr.id);
      if (idx != -1) {
        _webDhikrs[idx] = dhikr;
        await _saveWebDhikrs();
        return 1;
      }
      return 0;
    }
    final db = await database;
    return db.update(
      tableDhikr,
      dhikr.toMap(),
      where: 'id = ?',
      whereArgs: [dhikr.id],
    );
  }

  Future<int> deleteDhikr(int id) async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      _webDhikrs.removeWhere((d) => d.id == id);
      await _saveWebDhikrs();
      return 1;
    }
    final db = await database;
    return db.delete(tableDhikr, where: 'id = ?', whereArgs: [id]);
  }

  // ─── Session CRUD ─────────────────────────────────────────────────────────────

  /// Insert or update a session for the given dhikr.
  ///
  /// When updating an existing session (session.id != null), the original
  /// [Session.createdAt] timestamp is preserved — only [Session.updatedAt]
  /// and the mutable fields (count, target) are written.
  Future<int> upsertSession(Session session) async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      if (session.id != null) {
        final idx = _webSessions.indexWhere((s) => s.id == session.id);
        if (idx != -1) {
          // Preserve original createdAt on update
          final preserved = session.copyWith(
            createdAt: _webSessions[idx].createdAt,
          );
          _webSessions[idx] = preserved;
          await _saveWebSessions();
          return session.id!;
        }
      }
      final id = _nextSessionId++;
      final newSession = session.copyWith(id: id);
      _webSessions.add(newSession);
      await _saveWebSessions();
      return id;
    }

    final db = await database;
    if (session.id != null) {
      // Only update mutable fields; preserve created_at from original row.
      await db.update(
        tableSession,
        {
          'dhikr_name': session.dhikrName,
          'count': session.count,
          'target': session.target,
          'updated_at': session.updatedAt,
        },
        where: 'id = ?',
        whereArgs: [session.id],
      );
      return session.id!;
    } else {
      return db.insert(tableSession, session.toMap());
    }
  }

  /// Returns the session for the given dhikr on the given date, or null.
  Future<Session?> getSessionForDate(int dhikrId, String date) async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      try {
        return _webSessions.firstWhere(
          (s) => s.dhikrId == dhikrId && s.date == date,
        );
      } catch (_) {
        return null;
      }
    }

    final db = await database;
    final maps = await db.query(
      tableSession,
      where: 'dhikr_id = ? AND date = ?',
      whereArgs: [dhikrId, date],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Session.fromMap(maps.first);
  }

  /// Returns all sessions for a given date, ordered by updated_at DESC.
  Future<List<Session>> getSessionsForDate(String date) async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      final list = _webSessions.where((s) => s.date == date).toList();
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    }

    final db = await database;
    final maps = await db.query(
      tableSession,
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'updated_at DESC, created_at DESC',
    );
    return maps.map(Session.fromMap).toList();
  }

  /// Returns all sessions grouped by date, ordered by date DESC.
  Future<List<Session>> getAllSessions() async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      final list = List<Session>.from(_webSessions);
      list.sort((a, b) {
        final dateComp = b.date.compareTo(a.date);
        if (dateComp != 0) return dateComp;
        return b.updatedAt.compareTo(a.updatedAt);
      });
      return list;
    }

    final db = await database;
    final maps = await db.query(
      tableSession,
      orderBy: 'date DESC, updated_at DESC',
    );
    return maps.map(Session.fromMap).toList();
  }

  // ─── Statistics & Aggregations ───────────────────────────────────────────────

  /// Returns total count for a specific date (e.g. today).
  Future<int> getTotalForDate(String date) async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      return _webSessions
          .where((s) => s.date == date)
          .fold<int>(0, (sum, s) => sum + s.count);
    }

    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(count), 0) as total FROM $tableSession WHERE date = ?',
      [date],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  /// Returns total count for a date range (inclusive).
  Future<int> getTotalForDateRange(String startDate, String endDate) async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      return _webSessions
          .where((s) => s.date.compareTo(startDate) >= 0 && s.date.compareTo(endDate) <= 0)
          .fold<int>(0, (sum, s) => sum + s.count);
    }

    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(count), 0) as total FROM $tableSession WHERE date >= ? AND date <= ?',
      [startDate, endDate],
    );
    return (result.first['total'] as int?) ?? 0;
  }

  /// Returns lifetime total count across all recorded sessions.
  Future<int> getLifetimeTotal() async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      return _webSessions.fold<int>(0, (sum, s) => sum + s.count);
    }

    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(count), 0) as total FROM $tableSession',
    );
    return (result.first['total'] as int?) ?? 0;
  }

  /// Returns Dhikr-wise totals for a specific date.
  Future<List<Map<String, dynamic>>> getDhikrBreakdownForDate(String date) async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      final daySessions = _webSessions.where((s) => s.date == date).toList();
      return daySessions
          .map((s) => {
                'dhikr_name': s.dhikrName,
                'count': s.count,
                'target': s.target,
              })
          .toList();
    }

    final db = await database;
    return db.rawQuery(
      '''SELECT dhikr_name, SUM(count) as count, target 
         FROM $tableSession 
         WHERE date = ? 
         GROUP BY dhikr_id 
         ORDER BY count DESC''',
      [date],
    );
  }

  /// Returns daily totals for recent days.
  Future<List<Map<String, dynamic>>> getDailyTotals({int limit = 30}) async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      final map = <String, int>{};
      for (final s in _webSessions) {
        map[s.date] = (map[s.date] ?? 0) + s.count;
      }
      final sortedKeys = map.keys.toList()..sort((a, b) => b.compareTo(a));
      return sortedKeys
          .take(limit)
          .map((d) => {'date': d, 'total': map[d]})
          .toList();
    }

    final db = await database;
    return db.rawQuery(
      '''SELECT date, SUM(count) as total 
         FROM $tableSession 
         GROUP BY date 
         ORDER BY date DESC 
         LIMIT ?''',
      [limit],
    );
  }

  /// Returns monthly totals grouped by 'YYYY-MM'.
  Future<List<Map<String, dynamic>>> getMonthlyTotals({int limit = 12}) async {
    if (kIsWeb) {
      await _initWebIfNeeded();
      final map = <String, int>{};
      for (final s in _webSessions) {
        final monthKey = s.date.length >= 7 ? s.date.substring(0, 7) : s.date;
        map[monthKey] = (map[monthKey] ?? 0) + s.count;
      }
      final sortedKeys = map.keys.toList()..sort((a, b) => b.compareTo(a));
      return sortedKeys
          .take(limit)
          .map((m) => {'month': m, 'total': map[m]})
          .toList();
    }

    final db = await database;
    return db.rawQuery(
      '''SELECT SUBSTR(date, 1, 7) as month, SUM(count) as total 
         FROM $tableSession 
         GROUP BY month 
         ORDER BY month DESC 
         LIMIT ?''',
      [limit],
    );
  }
}
