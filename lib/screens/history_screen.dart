import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../database/database_helper.dart';
import '../models/session.dart';

/// Fully functional History Screen backed by local SQLite queries.
///
/// Displays:
/// - Summary cards: Today, This Week, This Month, Lifetime Total
/// - Today's Dhikr-wise Breakdown
/// - Weekly Aggregates
/// - Monthly Aggregates
/// - Daily Logs (expandable by date with session details)
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _loading = true;

  int _todayTotal = 0;
  int _weekTotal = 0;
  int _monthTotal = 0;
  int _lifetimeTotal = 0;

  List<Map<String, dynamic>> _todayBreakdown = [];
  List<Map<String, dynamic>> _monthlyTotals = [];
  List<Session> _allSessions = [];
  Map<String, List<Session>> _groupedSessions = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = context.read<DatabaseHelper>();
    final now = DateTime.now();
    final todayStr = _dateStr(now);

    final todayTotal = await db.getTotalForDate(todayStr);

    // Current week calculation (Monday to Sunday)
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekTotal = await db.getTotalForDateRange(_dateStr(weekStart), todayStr);

    // Current month calculation
    final monthStart = DateTime(now.year, now.month, 1);
    final monthTotal = await db.getTotalForDateRange(_dateStr(monthStart), todayStr);

    final lifetimeTotal = await db.getLifetimeTotal();

    final todayBreakdown = await db.getDhikrBreakdownForDate(todayStr);
    final monthlyTotals = await db.getMonthlyTotals(limit: 6);
    final allSessions = await db.getAllSessions();

    final grouped = <String, List<Session>>{};
    for (final s in allSessions) {
      grouped.putIfAbsent(s.date, () => []).add(s);
    }

    if (mounted) {
      setState(() {
        _todayTotal = todayTotal;
        _weekTotal = weekTotal;
        _monthTotal = monthTotal;
        _lifetimeTotal = lifetimeTotal;
        _todayBreakdown = todayBreakdown;
        _monthlyTotals = monthlyTotals;
        _allSessions = allSessions;
        _groupedSessions = grouped;
        _loading = false;
      });
    }
  }

  String _dateStr(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  String _friendlyDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final d = DateTime(dt.year, dt.month, dt.day);
      final diff = today.difference(d).inDays;
      if (diff == 0) return 'Today';
      if (diff == 1) return 'Yesterday';
      return DateFormat('EEEE, d MMM y').format(dt);
    } catch (_) {
      return isoDate;
    }
  }

  String _formatMonth(String yyyyMm) {
    try {
      final parts = yyyyMm.split('-');
      if (parts.length >= 2) {
        final year = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final dt = DateTime(year, month);
        return DateFormat('MMMM yyyy').format(dt);
      }
      return yyyyMm;
    } catch (_) {
      return yyyyMm;
    }
  }

  int _dailyTotal(List<Session> sessions) =>
      sessions.fold(0, (sum, s) => sum + s.count);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History & Statistics'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _allSessions.isEmpty
              ? _EmptyState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    children: [
                      // ── Summary Cards ────────────────────────────────────
                      _SummaryGrid(
                        todayTotal: _todayTotal,
                        weekTotal: _weekTotal,
                        monthTotal: _monthTotal,
                        lifetimeTotal: _lifetimeTotal,
                      ),

                      const SizedBox(height: 20),

                      // ── Today's Breakdown ────────────────────────────────
                      if (_todayBreakdown.isNotEmpty) ...[
                        _SectionHeader(
                          title: "Today's Dhikr Breakdown",
                          icon: Icons.pie_chart_outline_rounded,
                        ),
                        const SizedBox(height: 8),
                        _TodayBreakdownCard(breakdown: _todayBreakdown),
                        const SizedBox(height: 20),
                      ],

                      // ── Monthly Summary ──────────────────────────────────
                      if (_monthlyTotals.isNotEmpty) ...[
                        _SectionHeader(
                          title: 'Monthly Summary',
                          icon: Icons.calendar_month_rounded,
                        ),
                        const SizedBox(height: 8),
                        _MonthlySummaryCard(
                          monthlyTotals: _monthlyTotals,
                          formatMonth: _formatMonth,
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ── Daily Log ────────────────────────────────────────
                      _SectionHeader(
                        title: 'Daily History Log',
                        icon: Icons.history_rounded,
                      ),
                      const SizedBox(height: 8),
                      ..._groupedSessions.entries.map((entry) {
                        final date = entry.key;
                        final sessions = entry.value;
                        final total = _dailyTotal(sessions);
                        return _DayCard(
                          dateTitle: _friendlyDate(date),
                          rawDate: date,
                          total: total,
                          sessions: sessions,
                        );
                      }),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colorScheme.primary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

// ─── Summary Grid ─────────────────────────────────────────────────────────────

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.todayTotal,
    required this.weekTotal,
    required this.monthTotal,
    required this.lifetimeTotal,
  });

  final int todayTotal;
  final int weekTotal;
  final int monthTotal;
  final int lifetimeTotal;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Today',
                value: todayTotal,
                icon: Icons.today_rounded,
                isHighlight: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'This Week',
                value: weekTotal,
                icon: Icons.date_range_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'This Month',
                value: monthTotal,
                icon: Icons.calendar_month_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'Lifetime',
                value: lifetimeTotal,
                icon: Icons.all_inclusive_rounded,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.isHighlight = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: isHighlight
          ? colorScheme.primaryContainer.withAlpha(90)
          : colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isHighlight
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  icon,
                  size: 18,
                  color: isHighlight ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _formatNumber(value),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: isHighlight
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ─── Today Breakdown Card ─────────────────────────────────────────────────────

class _TodayBreakdownCard extends StatelessWidget {
  const _TodayBreakdownCard({required this.breakdown});
  final List<Map<String, dynamic>> breakdown;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxCount = breakdown.fold<int>(
      1,
      (max, item) => (item['count'] as int? ?? 0) > max ? (item['count'] as int? ?? 0) : max,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: breakdown.map((item) {
            final name = item['dhikr_name'] as String? ?? '';
            final count = item['count'] as int? ?? 0;
            final fraction = (count / maxCount).clamp(0.0, 1.0);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.primary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─── Monthly Summary Card ─────────────────────────────────────────────────────

class _MonthlySummaryCard extends StatelessWidget {
  const _MonthlySummaryCard({
    required this.monthlyTotals,
    required this.formatMonth,
  });

  final List<Map<String, dynamic>> monthlyTotals;
  final String Function(String) formatMonth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: monthlyTotals.map((m) {
            final monthStr = m['month'] as String? ?? '';
            final total = m['total'] as int? ?? 0;

            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withAlpha(90),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.calendar_month_rounded, size: 16, color: colorScheme.primary),
              ),
              title: Text(
                formatMonth(monthStr),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              trailing: Text(
                '$total counts',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                  fontSize: 14,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─── Day Card ─────────────────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.dateTitle,
    required this.rawDate,
    required this.total,
    required this.sessions,
  });

  final String dateTitle;
  final String rawDate;
  final int total;
  final List<Session> sessions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateTitle,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    if (dateTitle != rawDate)
                      Text(
                        rawDate,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$total',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          children: sessions.map((s) {
            return ListTile(
              dense: true,
              leading: Icon(
                Icons.circle,
                size: 8,
                color: colorScheme.primary,
              ),
              title: Text(
                s.dhikrName,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                'Target: ${s.target}',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              trailing: Text(
                '${s.count}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: colorScheme.primary,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_toggle_off_rounded,
              size: 80,
              color: colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No History Yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start counting your Dhikr from the home screen to build your daily history and statistics.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
