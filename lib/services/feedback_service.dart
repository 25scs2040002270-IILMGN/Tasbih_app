import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Centralized service for audio and haptic feedback across the application.
class FeedbackService {
  FeedbackService() {
    _initAudio();
  }

  // Audio players for sound effects with fast recycling for rapid tapping
  final List<AudioPlayer> _clickPlayers = [];
  int _currentClickIndex = 0;
  static const int _poolSize = 3;

  AudioPlayer? _milestonePlayer;
  bool _audioInitialized = false;
  bool _hasVibrator = true;

  Future<void> _initAudio() async {
    try {
      for (int i = 0; i < _poolSize; i++) {
        final player = AudioPlayer();
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setReleaseMode(ReleaseMode.stop);
        _clickPlayers.add(player);
      }

      _milestonePlayer = AudioPlayer();
      await _milestonePlayer?.setPlayerMode(PlayerMode.lowLatency);
      await _milestonePlayer?.setReleaseMode(ReleaseMode.stop);

      _audioInitialized = true;
    } catch (e) {
      debugPrint('Error initializing audio players: $e');
    }

    try {
      final hasVib = await Vibration.hasVibrator();
      _hasVibrator = hasVib;
    } catch (e) {
      debugPrint('Error checking vibrator availability: $e');
    }
  }

  /// Trigger haptic feedback for a standard count increment.
  Future<void> triggerCountVibration() async {
    try {
      if (_hasVibrator) {
        final hasCustomSupport = await Vibration.hasCustomVibrationsSupport();
        if (hasCustomSupport == true) {
          await Vibration.vibrate(duration: 35, amplitude: 128);
          return;
        } else {
          await Vibration.vibrate(duration: 35);
          return;
        }
      }
    } catch (_) {}

    // Fallback to system haptics
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {
      try {
        await HapticFeedback.vibrate();
      } catch (_) {}
    }
  }

  /// Trigger haptic feedback when reaching a milestone / target count.
  Future<void> triggerMilestoneVibration() async {
    try {
      if (_hasVibrator) {
        final hasCustomSupport = await Vibration.hasCustomVibrationsSupport();
        if (hasCustomSupport == true) {
          // Double pulse: 0ms wait, 80ms pulse, 70ms pause, 140ms pulse
          await Vibration.vibrate(
            pattern: [0, 80, 70, 140],
            intensities: [0, 180, 0, 255],
          );
          return;
        } else {
          await Vibration.vibrate(pattern: [0, 80, 70, 140]);
          return;
        }
      }
    } catch (_) {}

    // Fallback to system haptics
    try {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.heavyImpact();
    } catch (_) {
      try {
        await HapticFeedback.vibrate();
      } catch (_) {}
    }
  }

  /// Play audio sound for a standard count increment.
  Future<void> playCountSound() async {
    if (_audioInitialized && _clickPlayers.isNotEmpty) {
      try {
        final player = _clickPlayers[_currentClickIndex];
        _currentClickIndex = (_currentClickIndex + 1) % _clickPlayers.length;
        await player.stop();
        await player.play(AssetSource('sounds/click.wav'), volume: 1.0);
        return;
      } catch (e) {
        debugPrint('Error playing click audio asset: $e');
      }
    }

    // Fallback to system click sound
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
  }

  /// Play audio sound for reaching a target / milestone.
  Future<void> playMilestoneSound() async {
    if (_audioInitialized && _milestonePlayer != null) {
      try {
        await _milestonePlayer?.stop();
        await _milestonePlayer?.play(AssetSource('sounds/milestone.wav'), volume: 1.0);
        return;
      } catch (e) {
        debugPrint('Error playing milestone audio asset: $e');
      }
    }

    // Fallback to system alert sound
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }

  /// Dispose audio players when application terminates.
  void dispose() {
    for (final player in _clickPlayers) {
      player.dispose();
    }
    _clickPlayers.clear();
    _milestonePlayer?.dispose();
  }
}
