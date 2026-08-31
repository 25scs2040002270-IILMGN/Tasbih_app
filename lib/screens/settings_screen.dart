import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/database_helper.dart';
import '../services/backup_service.dart';
import '../services/feedback_service.dart';
import '../services/settings_service.dart';

/// Application settings screen.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const SafeArea(child: _SettingsBody()),
    );
  }
}

class _SettingsBody extends StatefulWidget {
  const _SettingsBody();

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  bool _backupLoading = false;
  bool _restoreLoading = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colorScheme = Theme.of(context).colorScheme;
    final db = context.read<DatabaseHelper>();

    final feedback = context.read<FeedbackService>();

    return ListView(
      children: [
        // ── Feedback ──────────────────────────────────────────────────────
        _SectionHeader('Feedback'),
        SwitchListTile(
          secondary: const Icon(Icons.vibration_rounded),
          title: const Text('Vibration'),
          subtitle: const Text('Vibrate on each count'),
          value: settings.vibration,
          onChanged: (val) {
            settings.setVibration(val);
            if (val) {
              feedback.triggerCountVibration();
            }
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.volume_up_rounded),
          title: const Text('Sound'),
          subtitle: const Text('Click sound on each count'),
          value: settings.sound,
          onChanged: (val) {
            settings.setSound(val);
            if (val) {
              feedback.playCountSound();
            }
          },
        ),

        const Divider(),

        // ── Appearance ────────────────────────────────────────────────────
        _SectionHeader('Appearance'),
        ListTile(
          leading: const Icon(Icons.palette_rounded),
          title: const Text('Theme'),
          subtitle: Text(_themeName(settings.themeMode)),
          onTap: () => _showThemePicker(context, settings),
        ),

        const Divider(),

        // ── Counter ───────────────────────────────────────────────────────
        _SectionHeader('Counter'),
        ListTile(
          leading: const Icon(Icons.flag_rounded),
          title: const Text('Default Target'),
          subtitle: Text('${settings.defaultTarget} counts per session'),
          onTap: () => _showTargetPicker(context, settings),
        ),

        const Divider(),

        // ── Data ──────────────────────────────────────────────────────────
        _SectionHeader('Data'),
        ListTile(
          leading: _backupLoading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              : Icon(Icons.backup_rounded, color: colorScheme.primary),
          title: const Text('Backup Data'),
          subtitle: const Text('Export a local backup file'),
          enabled: !_backupLoading && !_restoreLoading,
          onTap: () => _doBackup(db, settings),
        ),
        ListTile(
          leading: _restoreLoading
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              : Icon(Icons.restore_rounded, color: colorScheme.primary),
          title: const Text('Restore Data'),
          subtitle: const Text('Import from a backup file'),
          enabled: !_backupLoading && !_restoreLoading,
          onTap: () => _doRestore(db, settings),
        ),

        const Divider(),

        // ── About ─────────────────────────────────────────────────────────
        _SectionHeader('About'),
        ListTile(
          leading: const Icon(Icons.info_outline_rounded),
          title: const Text('Tasbih'),
          subtitle: const Text('Version 1.0.0 • Personal offline Dhikr counter'),
          onTap: () => _showAbout(context),
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  // ─── Backup ───────────────────────────────────────────────────────────────

  Future<void> _doBackup(
    DatabaseHelper db,
    SettingsService settings,
  ) async {
    if (_backupLoading) return;
    setState(() => _backupLoading = true);

    final svc = BackupService(dbHelper: db);
    final result = await svc.exportBackup();

    if (!mounted) return;
    setState(() => _backupLoading = false);

    if (result.success) {
      final path = result.filePath ?? '';
      _showSnackBar(
        '✓ Backup saved to:\n$path',
        isError: false,
      );
    } else {
      _showSnackBar(result.error ?? 'Backup failed.', isError: true);
    }
  }

  // ─── Restore ──────────────────────────────────────────────────────────────

  Future<void> _doRestore(
    DatabaseHelper db,
    SettingsService settings,
  ) async {
    if (_restoreLoading) return;

    // 1. Pick + validate file (shows file picker)
    final svc = BackupService(dbHelper: db);
    BackupData? data;
    try {
      data = await svc.pickAndValidateBackup();
    } on BackupValidationException catch (e) {
      if (!mounted) return;
      _showSnackBar(e.message, isError: true);
      return;
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Could not read file: $e', isError: true);
      return;
    }

    if (data == null || !mounted) return; // user cancelled

    // 2. Show confirmation dialog
    final confirmed = await _showRestoreConfirmation(data);
    if (!mounted || confirmed != true) return;

    setState(() => _restoreLoading = true);
    final result = await svc.importBackup(data);

    // 3. Reload settings from prefs after restore
    await settings.reload();

    if (!mounted) return;
    setState(() => _restoreLoading = false);

    if (result.success) {
      _showSnackBar(
        '✓ Restored ${result.sessionsImported} sessions'
        '${result.dhikrImported > 0 ? " and ${result.dhikrImported} custom Dhikr" : ""}.',
        isError: false,
      );
    } else {
      _showSnackBar(result.error ?? 'Restore failed.', isError: true);
    }
  }

  Future<bool?> _showRestoreConfirmation(
    BackupData data,
  ) {
    final dateStr = data.exportedAt.length >= 10
        ? data.exportedAt.substring(0, 10)
        : data.exportedAt;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.restore_rounded,
          color: Theme.of(ctx).colorScheme.primary,
          size: 32,
        ),
        title: const Text('Restore Backup?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This backup contains:',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.event_note_rounded,
              label: '${data.sessions.length} session records',
            ),
            _InfoRow(
              icon: Icons.auto_awesome_rounded,
              label: '${data.customDhikr.length} custom Dhikr',
            ),
            if (dateStr.isNotEmpty)
              _InfoRow(
                icon: Icons.calendar_today_rounded,
                label: 'Exported on $dateStr',
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.errorContainer.withAlpha(80),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Theme.of(ctx).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Existing sessions on the same date will not be overwritten. '
                      'New data will be added alongside your current records.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onErrorContainer,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.restore_rounded, size: 16),
            label: const Text('Restore'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
  }

  // ─── Theme ────────────────────────────────────────────────────────────────

  String _themeName(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.system:
        return 'System default';
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
    }
  }

  void _showThemePicker(BuildContext context, SettingsService settings) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Choose Theme',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                for (final mode in AppThemeMode.values)
                  ListTile(
                    leading: Icon(
                      settings.themeMode == mode
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: Theme.of(ctx).colorScheme.primary,
                    ),
                    title: Text(_themeName(mode)),
                    onTap: () {
                      settings.setThemeMode(mode);
                      Navigator.pop(ctx);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Target ───────────────────────────────────────────────────────────────

  Future<void> _showTargetPicker(
    BuildContext context,
    SettingsService settings,
  ) async {
    final options = [11, 33, 99, 100, 1000];
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Default Target'),
        children: [
          ...options.map(
            (v) => ListTile(
              leading: Icon(
                settings.defaultTarget == v
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: Theme.of(ctx).colorScheme.primary,
              ),
              title: Text('$v'),
              onTap: () => Navigator.pop(ctx, v),
            ),
          ),
          ListTile(
            title: const Text('Custom…'),
            leading: const Icon(Icons.edit),
            onTap: () async {
              Navigator.pop(ctx);
              await _showCustomTargetDialog(context, settings);
            },
          ),
        ],
      ),
    );

    if (selected != null) {
      await settings.setDefaultTarget(selected);
    }
  }

  Future<void> _showCustomTargetDialog(
    BuildContext context,
    SettingsService settings,
  ) async {
    final controller = TextEditingController(
      text: '${settings.defaultTarget}',
    );
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom Target'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Target count',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n < 1) return 'Enter a positive number';
              return null;
            },
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final n = int.tryParse(controller.text);
      if (n != null && n > 0) {
        await settings.setDefaultTarget(n);
      }
    }
  }

  // ─── About ────────────────────────────────────────────────────────────────

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'Tasbih',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2025 Personal Use',
      children: const [
        SizedBox(height: 16),
        Text(
          'A simple, beautiful offline Tasbih (Dhikr) counter.\n\n'
          'No account. No internet. No tracking. Just counting.',
        ),
      ],
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 5 : 4),
      ),
    );
  }
}

// ─── Info Row Helper ──────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
