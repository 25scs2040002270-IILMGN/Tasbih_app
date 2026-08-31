import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import '../models/dhikr.dart';
import '../models/session.dart';
import '../utils/constants.dart';

/// Current backup schema version.
const int kBackupSchemaVersion = 1;

/// Result of a backup export operation.
class BackupExportResult {
  const BackupExportResult({required this.success, this.filePath, this.error});
  final bool success;
  final String? filePath;
  final String? error;
}

/// Result of a backup import operation.
class BackupImportResult {
  const BackupImportResult({
    required this.success,
    this.dhikrImported = 0,
    this.sessionsImported = 0,
    this.error,
  });
  final bool success;
  final int dhikrImported;
  final int sessionsImported;
  final String? error;
}

/// Parsed and validated backup data ready for import.
class BackupData {
  const BackupData({
    required this.exportedAt,
    required this.settings,
    required this.customDhikr,
    required this.sessions,
  });
  final String exportedAt;
  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> customDhikr;
  final List<Map<String, dynamic>> sessions;
}

/// Handles export and import of local JSON backup files.
///
/// Data stays 100% on the device — no network calls, no cloud.
class BackupService {
  BackupService({required DatabaseHelper dbHelper}) : _db = dbHelper;

  final DatabaseHelper _db;

  // ─── Export ───────────────────────────────────────────────────────────────

  /// Exports all user data to a JSON file in the app's documents directory.
  /// Returns the path to the created file, or an error message.
  Future<BackupExportResult> exportBackup() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Read custom Dhikr
      final allDhikr = await _db.getAllDhikr();
      final customDhikr = allDhikr.where((d) => d.isCustom).toList();

      // 2. Read all sessions
      final sessions = await _db.getAllSessions();

      // 3. Build settings map
      final settingsMap = {
        'default_target': prefs.getInt(kPrefDefaultTarget) ?? kDefaultTarget,
        'vibration': prefs.getBool(kPrefVibration) ?? true,
        'sound': prefs.getBool(kPrefSound) ?? false,
        'theme_mode': prefs.getInt(kPrefTheme) ?? 0,
      };

      // 4. Build backup JSON
      final backup = {
        'schema_version': kBackupSchemaVersion,
        'app': 'tasbih',
        'exported_at': DateTime.now().toIso8601String(),
        'settings': settingsMap,
        'custom_dhikr': customDhikr
            .map((d) => {
                  'name': d.name,
                  'arabic': d.arabic,
                  'created_at': d.createdAt,
                })
            .toList(),
        'sessions': sessions
            .map((s) => {
                  'dhikr_id': s.dhikrId,
                  'dhikr_name': s.dhikrName,
                  'count': s.count,
                  'target': s.target,
                  'date': s.date,
                  'created_at': s.createdAt,
                  'updated_at': s.updatedAt,
                })
            .toList(),
      };

      // 5. Write file
      final jsonString = const JsonEncoder.withIndent('  ').convert(backup);
      final filePath = await _resolveExportPath();
      final file = File(filePath);
      await file.writeAsString(jsonString, flush: true);

      return BackupExportResult(success: true, filePath: filePath);
    } catch (e) {
      return BackupExportResult(
        success: false,
        error: 'Export failed: ${e.toString()}',
      );
    }
  }

  Future<String> _resolveExportPath() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final fileName = 'tasbih_backup_$dateStr.json';

    try {
      // Prefer external storage (Downloads-accessible) on Android
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        return '${extDir.path}/$fileName';
      }
    } catch (_) {}

    // Fallback to app documents directory
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$fileName';
  }

  // ─── Import ───────────────────────────────────────────────────────────────

  /// Opens the file picker and returns parsed backup data if valid, or null
  /// if the user cancelled or the file is invalid.
  ///
  /// Throws [BackupValidationException] with a human-readable message if
  /// the file is malformed or incompatible.
  Future<BackupData?> pickAndValidateBackup() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
        allowMultiple: false,
      );
    } catch (e) {
      throw BackupValidationException('Could not open file picker: $e');
    }

    if (result == null || result.files.isEmpty) return null; // user cancelled

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw BackupValidationException('Selected file is empty or unreadable.');
    }

    final jsonString = utf8.decode(bytes);
    return _validateJson(jsonString);
  }

  /// Exposed for unit testing only — parses and validates a raw JSON string.
  /// Throws [BackupValidationException] for invalid input.
  BackupData? parseJsonForTest(String jsonString) => _validateJson(jsonString);

  BackupData _validateJson(String jsonString) {
    dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } catch (_) {
      throw BackupValidationException(
        'Invalid file: not valid JSON. Please select a Tasbih backup file.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw BackupValidationException(
        'Invalid backup format. Please select a Tasbih backup file.',
      );
    }

    final map = decoded;

    // Schema version check
    final schemaVersion = map['schema_version'];
    if (schemaVersion == null) {
      throw BackupValidationException(
        'This file is not a Tasbih backup (missing schema version).',
      );
    }
    if (schemaVersion is! int || schemaVersion > kBackupSchemaVersion) {
      throw BackupValidationException(
        'This backup was created by a newer version of Tasbih (schema v$schemaVersion). '
        'Please update the app.',
      );
    }

    final appField = map['app'];
    if (appField != 'tasbih') {
      throw BackupValidationException(
        'This file was not created by Tasbih. Please select a valid Tasbih backup.',
      );
    }

    // Parse custom_dhikr
    final rawDhikr = map['custom_dhikr'];
    final customDhikr = <Map<String, dynamic>>[];
    if (rawDhikr is List) {
      for (final item in rawDhikr) {
        if (item is Map<String, dynamic> &&
            item['name'] is String &&
            (item['name'] as String).isNotEmpty) {
          customDhikr.add(item);
        }
      }
    }

    // Parse sessions
    final rawSessions = map['sessions'];
    final sessions = <Map<String, dynamic>>[];
    if (rawSessions is List) {
      for (final item in rawSessions) {
        if (item is Map<String, dynamic> &&
            item['dhikr_name'] is String &&
            item['date'] is String) {
          sessions.add(item);
        }
      }
    }

    return BackupData(
      exportedAt: map['exported_at'] as String? ?? '',
      settings: map['settings'] as Map<String, dynamic>? ?? {},
      customDhikr: customDhikr,
      sessions: sessions,
    );
  }

  /// Imports a validated [BackupData] into the database.
  /// Custom Dhikrs are matched by name to avoid duplicates.
  /// Sessions are inserted by date+dhikr_name; existing ones are kept.
  Future<BackupImportResult> importBackup(BackupData data) async {
    try {
      int dhikrCount = 0;
      int sessionCount = 0;
      final now = DateTime.now().toIso8601String();

      // 1. Import settings
      if (data.settings.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final defaultTarget = data.settings['default_target'];
        if (defaultTarget is int && defaultTarget > 0) {
          await prefs.setInt(kPrefDefaultTarget, defaultTarget);
        }
        final vibration = data.settings['vibration'];
        if (vibration is bool) {
          await prefs.setBool(kPrefVibration, vibration);
        }
        final sound = data.settings['sound'];
        if (sound is bool) {
          await prefs.setBool(kPrefSound, sound);
        }
        final themeMode = data.settings['theme_mode'];
        if (themeMode is int) {
          await prefs.setInt(kPrefTheme, themeMode);
        }
      }

      // 2. Import custom Dhikr (skip if name already exists)
      final existingDhikr = await _db.getAllDhikr();
      final existingNames = existingDhikr.map((d) => d.name.toLowerCase()).toSet();

      for (final d in data.customDhikr) {
        final name = d['name'] as String;
        if (existingNames.contains(name.toLowerCase())) continue;

        await _db.insertDhikr(Dhikr(
          name: name,
          arabic: d['arabic'] as String? ?? '',
          isCustom: true,
          createdAt: d['created_at'] as String? ?? now,
        ));
        existingNames.add(name.toLowerCase());
        dhikrCount++;
      }

      // 3. Import sessions (skip duplicates by date + dhikr_name)
      final allExistingDhikr = await _db.getAllDhikr();
      final dhikrByName = {
        for (final d in allExistingDhikr) d.name.toLowerCase(): d,
      };

      for (final s in data.sessions) {
        final dhikrName = s['dhikr_name'] as String? ?? '';
        final date = s['date'] as String? ?? '';
        if (dhikrName.isEmpty || date.isEmpty) continue;

        // Try to find the matching Dhikr in our DB by name
        final dhikr = dhikrByName[dhikrName.toLowerCase()];
        if (dhikr == null || dhikr.id == null) continue;

        // Check if a session already exists for this dhikr+date
        final existing = await _db.getSessionForDate(dhikr.id!, date);
        if (existing != null) continue; // don't overwrite existing sessions

        final count = s['count'];
        final target = s['target'];

        await _db.upsertSession(Session(
          dhikrId: dhikr.id!,
          dhikrName: dhikr.name,
          count: count is int ? count : 0,
          target: target is int ? target : kDefaultTarget,
          date: date,
          createdAt: s['created_at'] as String? ?? now,
          updatedAt: s['updated_at'] as String? ?? now,
        ));
        sessionCount++;
      }

      return BackupImportResult(
        success: true,
        dhikrImported: dhikrCount,
        sessionsImported: sessionCount,
      );
    } catch (e) {
      return BackupImportResult(
        success: false,
        error: 'Restore failed: ${e.toString()}',
      );
    }
  }
}

/// Thrown when a backup file fails validation.
class BackupValidationException implements Exception {
  const BackupValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}
