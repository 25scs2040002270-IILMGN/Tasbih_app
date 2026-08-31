import 'dart:async';
import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import '../models/dhikr.dart';
import '../models/session.dart';
import '../utils/constants.dart';
import 'feedback_service.dart';
import 'settings_service.dart';

/// Manages the active counting session with instant UI response,
/// robust undo history, offline SQLite persistence, and haptic/audio feedback.
class CounterService extends ChangeNotifier {
  CounterService({
    required DatabaseHelper dbHelper,
    required SettingsService settingsService,
    FeedbackService? feedbackService,
  })  : _db = dbHelper,
        _settings = settingsService,
        _feedback = feedbackService ?? FeedbackService();

  final DatabaseHelper _db;
  final SettingsService _settings;
  final FeedbackService _feedback;

  Dhikr? _selectedDhikr;
  int _count = 0;
  int _target = kDefaultTarget;
  int? _sessionId;
  String? _sessionCreatedAt; // preserved from DB; never overwritten on update
  int _todayTotal = 0;
  bool _targetReachedFlag = false;

  /// Stack of counts before each increment (for undo).
  final List<int> _undoStack = [];

  /// Timer for debouncing database writes during rapid tapping.
  Timer? _persistDebounceTimer;

  Dhikr? get selectedDhikr => _selectedDhikr;
  int get count => _count;
  int get target => _target;
  int get todayTotal => _todayTotal;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get hasSession => _selectedDhikr != null;
  bool get targetReachedFlag => _targetReachedFlag;

  /// Progress as a value between 0.0 and 1.0 (or greater if exceeded).
  double get progress =>
      _target > 0 ? (_count / _target).clamp(0.0, 1.0) : 0.0;

  bool get isTargetReached => _target > 0 && _count >= _target;

  // ─── Initialisation ───────────────────────────────────────────────────────

  /// Initialize or restore today's session for the given [dhikr].
  Future<void> init(Dhikr dhikr) async {
    _flushPendingPersist();
    _selectedDhikr = dhikr;
    _target = _settings.defaultTarget;
    final today = _todayString();

    try {
      final existing = await _db.getSessionForDate(dhikr.id!, today);
      if (existing != null) {
        _sessionId = existing.id;
        _count = existing.count;
        _target = existing.target;
        _sessionCreatedAt = existing.createdAt; // preserve original timestamp
      } else {
        _count = 0;
        _sessionId = null;
        _sessionCreatedAt = null;
      }

      _todayTotal = await _db.getTotalForDate(today);
    } catch (e) {
      debugPrint('Error loading session: $e');
      _count = 0;
    }

    _undoStack.clear();
    _targetReachedFlag = false;
    notifyListeners();
  }

  /// Switch to a different Dhikr.
  Future<void> selectDhikr(Dhikr dhikr) => init(dhikr);

  // ─── Counter Operations ───────────────────────────────────────────────────

  /// Increment the counter by 1.
  /// Immediate UI update + async feedback & scheduled persistence.
  void increment() {
    if (_selectedDhikr == null) return;

    _undoStack.add(_count);
    if (_undoStack.length > 100) _undoStack.removeAt(0);

    _count++;
    _todayTotal++;

    // Check if target was reached with this tap
    if (_target > 0 && _count == _target) {
      _targetReachedFlag = true;
      _triggerMilestoneFeedback();
    } else {
      _targetReachedFlag = false;
      _triggerStandardFeedback();
    }

    notifyListeners();
    _schedulePersist();
  }

  /// Undo the last increment.
  Future<void> undo() async {
    if (_undoStack.isEmpty) return;

    final previous = _undoStack.removeLast();
    final diff = _count - previous;
    _count = previous;
    _todayTotal = (_todayTotal - diff).clamp(0, _todayTotal);
    _targetReachedFlag = false;
    notifyListeners();

    await _persistNow();
  }

  /// Reset the current session count to 0.
  Future<void> reset() async {
    _undoStack.clear();
    _todayTotal = (_todayTotal - _count).clamp(0, _todayTotal);
    _count = 0;
    _targetReachedFlag = false;
    notifyListeners();

    await _persistNow();
  }

  // ─── Target Management ────────────────────────────────────────────────────

  Future<void> setTarget(int newTarget) async {
    if (newTarget < 1) return;
    _target = newTarget;
    notifyListeners();
    await _persistNow();
  }

  // ─── Persistence ──────────────────────────────────────────────────────────

  void _schedulePersist() {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _persistNow();
    });
  }

  void _flushPendingPersist() {
    if (_persistDebounceTimer?.isActive ?? false) {
      _persistDebounceTimer?.cancel();
      _persistNow();
    }
  }

  Future<void> _persistNow() async {
    if (_selectedDhikr?.id == null) return;

    final today = _todayString();
    final now = DateTime.now().toIso8601String();
    // Use preserved createdAt if this session already exists, else use now.
    final createdAt = _sessionCreatedAt ?? now;

    final session = Session(
      id: _sessionId,
      dhikrId: _selectedDhikr!.id!,
      dhikrName: _selectedDhikr!.name,
      count: _count,
      target: _target,
      date: today,
      createdAt: createdAt,
      updatedAt: now,
    );

    try {
      final savedId = await _db.upsertSession(session);
      if (_sessionId == null) {
        // First time we save this session — store both ID and created timestamp.
        _sessionId = savedId;
        _sessionCreatedAt = createdAt;
      }
      _todayTotal = await _db.getTotalForDate(today);
      notifyListeners();
    } catch (e) {
      debugPrint('Error persisting session: $e');
    }
  }

  // ─── Feedback (Haptics & Audio) ───────────────────────────────────────────

  void _triggerStandardFeedback() {
    // 1. Vibration
    if (_settings.vibration) {
      _feedback.triggerCountVibration();
    }

    // 2. Click Sound
    if (_settings.sound) {
      _feedback.playCountSound();
    }
  }

  void _triggerMilestoneFeedback() {
    // Distinct double pulse on milestone target reach
    if (_settings.vibration) {
      _feedback.triggerMilestoneVibration();
    }

    if (_settings.sound) {
      _feedback.playMilestoneSound();
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _todayString() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _flushPendingPersist();
    super.dispose();
  }
}
