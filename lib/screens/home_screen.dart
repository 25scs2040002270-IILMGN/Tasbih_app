import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../services/counter_service.dart';
import '../widgets/counter_button.dart';
import '../widgets/dhikr_selector_sheet.dart';
import '../widgets/progress_ring.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

/// Primary home screen containing the Tasbih counter.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasbih'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'History',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: const SafeArea(child: _HomeBody()),
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody();

  @override
  Widget build(BuildContext context) {
    final counter = context.watch<CounterService>();

    if (!counter.hasSession) {
      return _EmptyState(onSelectDhikr: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const DhikrSelectorSheet(),
        );
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive button size
        final buttonDiameter =
            (constraints.maxWidth * 0.52).clamp(160.0, 240.0);

        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(height: 8),

                // ── Dhikr Selector Chip ────────────────────────────────────────────
                _DhikrChip(),

                const SizedBox(height: 20),

                // ── Counter + Progress Ring ────────────────────────────────────
                _CounterArea(buttonDiameter: buttonDiameter),

                const SizedBox(height: 24),

                // ── Count Display & Milestone ──────────────────────────────
                _CountDisplay(),

                const SizedBox(height: 12),

                // ── Target & Progress Indicator ────────────────────────────
                _ProgressAndTargetPill(),

                const SizedBox(height: 20),

                // ── Action Buttons (Undo & Reset) ─────────────────────────
                _ActionButtons(),

                const SizedBox(height: 12),

                // ── Today Total Footer ─────────────────────────────────────
                _TodayFooter(),

                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Empty State (no Dhikr selected) ─────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSelectDhikr});
  final VoidCallback onSelectDhikr;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 44,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Welcome to Tasbih',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Select a Dhikr to begin counting.\nYour progress is saved automatically.',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text('Choose Dhikr'),
              onPressed: onSelectDhikr,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Dhikr Chip ───────────────────────────────────────────────────────────────

class _DhikrChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final counter = context.watch<CounterService>();
    final colorScheme = Theme.of(context).colorScheme;
    final dhikrName = counter.selectedDhikr?.name ?? 'Select Dhikr';
    final arabicText = counter.selectedDhikr?.arabic ?? '';

    return GestureDetector(
      onTap: () => _openSelector(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withAlpha(20),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  dhikrName,
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (arabicText.isNotEmpty)
                  Text(
                    arabicText,
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer.withAlpha(200),
                      fontSize: 14,
                      fontFamily: 'serif',
                    ),
                    textDirection: TextDirection.rtl,
                  ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.expand_more_rounded,
              color: colorScheme.onPrimaryContainer,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _openSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DhikrSelectorSheet(),
    );
  }
}

// ─── Counter Area ─────────────────────────────────────────────────────────────

class _CounterArea extends StatelessWidget {
  const _CounterArea({required this.buttonDiameter});
  final double buttonDiameter;

  @override
  Widget build(BuildContext context) {
    final counter = context.watch<CounterService>();
    final ringSize = buttonDiameter + 24;

    return SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Progress ring with celebration glow if target reached
          AnimatedProgressRing(
            progress: counter.progress,
            size: ringSize,
            isTargetReached: counter.isTargetReached,
          ),
          // Large touch-target counter button
          CounterButton(
            onTap: counter.hasSession ? counter.increment : () {},
            label: counter.hasSession ? 'TAP' : 'Select\nDhikr',
          ),
        ],
      ),
    );
  }
}

/// Animated wrapper around [ProgressRing].
class AnimatedProgressRing extends StatelessWidget {
  const AnimatedProgressRing({
    super.key,
    required this.progress,
    required this.size,
    this.isTargetReached = false,
  });

  final double progress;
  final double size;
  final bool isTargetReached;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (_, value, child) => ProgressRing(
        progress: value,
        size: size,
        strokeWidth: 10,
      ),
    );
  }
}

// ─── Count Display ────────────────────────────────────────────────────────────

class _CountDisplay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final counter = context.watch<CounterService>();
    final colorScheme = Theme.of(context).colorScheme;
    final fmt = NumberFormat.decimalPattern();
    final countStr = counter.count >= 10000
        ? fmt.format(counter.count)
        : '${counter.count}';

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: animation,
            child: child,
          ),
          child: Text(
            countStr,
            key: ValueKey(counter.count),
            style: TextStyle(
              fontSize: counter.count >= 10000 ? 60 : 76,
              fontWeight: FontWeight.w800,
              color: counter.isTargetReached
                  ? colorScheme.primary
                  : colorScheme.onSurface,
              height: 1,
            ),
          ),
        ),
        if (counter.isTargetReached) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, size: 14, color: colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  'Target Reached',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Progress & Target Pill ───────────────────────────────────────────────────

class _ProgressAndTargetPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final counter = context.watch<CounterService>();
    final colorScheme = Theme.of(context).colorScheme;

    if (!counter.hasSession) return const SizedBox.shrink();

    final pct = (counter.progress * 100).round();

    return GestureDetector(
      onTap: () => _showTargetDialog(context, counter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withAlpha(120),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Target: ${counter.target}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
            Text(
              '  •  $pct%',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.edit_outlined,
              size: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTargetDialog(BuildContext context, CounterService counter) async {
    final targets = [33, 99, 100, 500, 1000];
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Change Target'),
        children: [
          ...targets.map(
            (t) => ListTile(
              leading: Icon(
                counter.target == t
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: Theme.of(ctx).colorScheme.primary,
              ),
              title: Text('$t counts'),
              onTap: () => Navigator.pop(ctx, t),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: const Text('Custom Target…'),
            onTap: () async {
              Navigator.pop(ctx);
              await _showCustomTargetInput(context, counter);
            },
          ),
        ],
      ),
    );

    if (selected != null) {
      await counter.setTarget(selected);
    }
  }

  Future<void> _showCustomTargetInput(BuildContext context, CounterService counter) async {
    final controller = TextEditingController(text: '${counter.target}');
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Custom Target'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Target count',
              hintText: 'e.g. 50',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              if (n == null || n < 1) return 'Enter a number greater than 0';
              return null;
            },
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
        await counter.setTarget(n);
      }
    }
  }
}

// ─── Action Buttons ───────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final counter = context.watch<CounterService>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Undo
          _ActionButton(
            icon: Icons.undo_rounded,
            label: 'Undo',
            enabled: counter.canUndo,
            onTap: counter.canUndo ? counter.undo : null,
          ),
          const SizedBox(width: 16),
          // Reset
          _ActionButton(
            icon: Icons.refresh_rounded,
            label: 'Reset',
            enabled: counter.count > 0,
            onTap: counter.count > 0
                ? () => _confirmReset(context, counter)
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(
    BuildContext context,
    CounterService counter,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Count'),
        content: Text(
          'Reset count for "${counter.selectedDhikr?.name}" to zero?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await counter.reset();
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: enabled
            ? colorScheme.primary
            : colorScheme.onSurface.withAlpha(60),
        side: BorderSide(
          color: enabled
              ? colorScheme.outline
              : colorScheme.outlineVariant.withAlpha(60),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    );
  }
}

// ─── Today Total Footer ───────────────────────────────────────────────────────

class _TodayFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final counter = context.watch<CounterService>();
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withAlpha(60),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.today_rounded,
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Text(
            "Today's Total",
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            '${counter.todayTotal}',
            style: TextStyle(
              color: colorScheme.primary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
