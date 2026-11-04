import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/reading_status.dart';
import '../../providers/book_providers.dart';
import '../../ui/theme/app_colors.dart';

/// Statistics dashboard showing reading insights, annual reading goal,
/// page count totals, and interactive charts.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(bookStatsProvider);

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: CustomScrollView(
            slivers: [
              // Header
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Statisztika',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Az olvasási utazásod és éves célod egy pillantásra',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Stats content
              SliverToBoxAdapter(
                child: statsAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(60),
                    child: Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    ),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.error,
                            size: 42,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Hiba a statisztika betöltésekor:\n$error',
                            style:
                                const TextStyle(color: AppColors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => ref.invalidate(bookStatsProvider),
                            child: const Text('Újratöltés'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  data: (stats) => _buildStats(context, ref, stats),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStats(BuildContext context, WidgetRef ref, BookStats stats) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Interactive Yearly Reading Goal card (always accessible!)
          _buildYearlyGoalCard(context, ref, stats),
          const SizedBox(height: 20),

          if (stats.totalCount == 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              child: Column(
                children: [
                  Icon(
                    Icons.bar_chart_rounded,
                    size: 60,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Még nincsenek részletes grafikonok',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Adj hozzá könyveket vonalkód-szkenneléssel vagy kereséssel, hogy megjelenjenek a részletes eloszlások!',
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else ...[
            // Responsive quick stats grid
            _buildQuickStats(stats),
            const SizedBox(height: 20),

            // Responsive Charts (2 columns on wide tablets/landscape, stacked on phones)
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 680 &&
                    stats.booksAddedPerMonth.isNotEmpty;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildStatusChart(stats)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTimelineChart(stats)),
                    ],
                  );
                }

                return Column(
                  children: [
                    _buildStatusChart(stats),
                    if (stats.booksAddedPerMonth.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _buildTimelineChart(stats),
                    ],
                  ],
                );
              },
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildYearlyGoalCard(
    BuildContext context,
    WidgetRef ref,
    BookStats stats,
  ) {
    final year = DateTime.now().year;
    final completed = stats.completedThisYear;
    final goal = stats.yearlyGoal > 0 ? stats.yearlyGoal : 12;
    final progress = (completed / goal).clamp(0.0, 1.0);
    final pct = (progress * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.secondary.withValues(alpha: 0.16),
            AppColors.primary.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.secondary.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$year-as olvasási kihívás',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      completed >= goal
                          ? 'Gratulálunk! Teljesítetted az idei célodat!'
                          : '$completed / $goal könyv elolvasva idén ($pct%)',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _showEditGoalDialog(context, ref, goal),
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Cél'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: AppColors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(
                completed >= goal ? AppColors.accent : AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditGoalDialog(
    BuildContext context,
    WidgetRef ref,
    int currentGoal,
  ) {
    final controller = TextEditingController(text: '$currentGoal');
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text(
            'Éves olvasási cél beállítása',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hány könyvet szeretnél elolvasni ebben az évben?',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'pl. 12',
                  suffixText: 'könyv',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Mégse'),
            ),
            ElevatedButton(
              onPressed: () async {
                final val = int.tryParse(controller.text.trim());
                if (val != null && val > 0) {
                  await ref.read(yearlyGoalProvider.notifier).updateGoal(val);
                }
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Mentés'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickStats(BookStats stats) {
    final items = <_StatItem>[
      _StatItem(
        icon: Icons.library_books_rounded,
        color: AppColors.secondary,
        label: 'Összes könyv',
        value: '${stats.totalCount}',
      ),
      _StatItem(
        icon: Icons.menu_book_rounded,
        color: AppColors.accent,
        label: 'Olvasott oldal',
        value: _formatCompactNumber(stats.totalPagesRead),
      ),
      _StatItem(
        icon: Icons.star_rounded,
        color: AppColors.primary,
        label: 'Átlag értékelés',
        value: stats.averageRating > 0
            ? stats.averageRating.toStringAsFixed(1)
            : '—',
      ),
      _StatItem(
        icon: ReadingStatus.completed.icon,
        color: ReadingStatus.completed.color,
        label: ReadingStatus.completed.label,
        value: '${stats.countByStatus['completed'] ?? 0}',
      ),
      _StatItem(
        icon: ReadingStatus.reading.icon,
        color: ReadingStatus.reading.color,
        label: ReadingStatus.reading.label,
        value: '${stats.countByStatus['reading'] ?? 0}',
      ),
      _StatItem(
        icon: ReadingStatus.planToRead.icon,
        color: ReadingStatus.planToRead.color,
        label: ReadingStatus.planToRead.label,
        value: '${stats.countByStatus['planToRead'] ?? 0}',
      ),
      _StatItem(
        icon: ReadingStatus.onHold.icon,
        color: ReadingStatus.onHold.color,
        label: ReadingStatus.onHold.label,
        value: '${stats.countByStatus['onHold'] ?? 0}',
      ),
      _StatItem(
        icon: ReadingStatus.dropped.icon,
        color: ReadingStatus.dropped.color,
        label: ReadingStatus.dropped.label,
        value: '${stats.countByStatus['dropped'] ?? 0}',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 380
            ? 2
            : constraints.maxWidth < 680
                ? 2
                : 4;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 108,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return _buildStatCard(
              icon: item.icon,
              iconColor: item.color,
              label: item.label,
              value: item.value,
            );
          },
        );
      },
    );
  }

  String _formatCompactNumber(int n) {
    if (n >= 10000) {
      return '${(n / 1000).toStringAsFixed(1)}k';
    }
    return '$n';
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChart(BookStats stats) {
    final statusEntries = ReadingStatus.values
        .where((s) => (stats.countByStatus[s.name] ?? 0) > 0)
        .toList();

    if (statusEntries.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Eloszlás állapot szerint',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),

          // Pie chart
          SizedBox(
            height: 180,
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 40,
                sections: statusEntries.map((status) {
                  final count = stats.countByStatus[status.name] ?? 0;
                  final percentage = (count / stats.totalCount * 100);
                  return PieChartSectionData(
                    value: count.toDouble(),
                    color: status.color,
                    radius: 45,
                    title: '${percentage.round()}%',
                    titleStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Legend
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: statusEntries.map((status) {
              final count = stats.countByStatus[status.name] ?? 0;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: status.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${status.label} ($count)',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineChart(BookStats stats) {
    final data = stats.booksAddedPerMonth;
    if (data.isEmpty) return const SizedBox.shrink();

    final maxCount = data.fold<int>(
      0,
      (max, entry) =>
          (entry['count'] as int) > max ? (entry['count'] as int) : max,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Havi gyarapodás (utolsó 12 hónap)',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxCount + 1).toDouble(),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppColors.surfaceLight,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${rod.toY.toInt()} könyv',
                        const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= data.length) {
                          return const SizedBox.shrink();
                        }
                        final monthStr = data[index]['month'] as String;
                        final month = monthStr.length >= 7
                            ? monthStr.substring(5)
                            : monthStr;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            month,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(data.length, (index) {
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: (data[index]['count'] as int).toDouble(),
                        gradient: const LinearGradient(
                          colors: [AppColors.secondary, AppColors.accent],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        width: 16,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
}
