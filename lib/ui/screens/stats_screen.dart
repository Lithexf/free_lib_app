import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/reading_status.dart';
import '../../providers/book_providers.dart';
import '../theme/app_colors.dart';

/// Egyszerű statisztikai képernyő alap számadatokkal, éves céllal és diagramokkal.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(bookStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Statisztika')),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Hiba a statisztika betöltésekor: $error'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => ref.invalidate(bookStatsProvider),
                  child: const Text('Újratöltés'),
                ),
              ],
            ),
          ),
        ),
        data: (stats) => _buildContent(context, ref, stats),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, BookStats stats) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildYearlyGoalCard(context, ref, stats),
              const SizedBox(height: 14),
              if (stats.totalCount == 0)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Még nincsenek könyvek a könyvtáradban.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else ...[
                _buildSummaryGrid(stats),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 680 &&
                        stats.booksAddedPerMonth.isNotEmpty;
                    if (isWide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildStatusChart(stats)),
                          const SizedBox(width: 14),
                          Expanded(child: _buildTimelineChart(stats)),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        _buildStatusChart(stats),
                        if (stats.booksAddedPerMonth.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _buildTimelineChart(stats),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        ),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '$year-as olvasási kihívás: $completed / $goal könyv',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _showEditGoalDialog(context, ref, goal),
                  child: const Text('Módosítás'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.surfaceLight,
              color: AppColors.primary,
            ),
          ],
        ),
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('Éves olvasási cél'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Könyvek száma'),
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
      ),
    );
  }

  Widget _buildSummaryGrid(BookStats stats) {
    final items = <(String, String)>[
      ('Összes könyv', '${stats.totalCount}'),
      ('Olvasott oldal', '${stats.totalPagesRead}'),
      (
        'Átlag értékelés',
        stats.averageRating > 0 ? stats.averageRating.toStringAsFixed(1) : '—'
      ),
      ('Befejezve', '${stats.countByStatus['completed'] ?? 0}'),
      ('Olvasom', '${stats.countByStatus['reading'] ?? 0}'),
      ('Tervben van', '${stats.countByStatus['planToRead'] ?? 0}'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 600 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 78,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.$2,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusChart(BookStats stats) {
    final statusEntries = ReadingStatus.values
        .where((s) => (stats.countByStatus[s.name] ?? 0) > 0)
        .toList();

    if (statusEntries.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Állapot szerinti megoszlás',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 170,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 32,
                  sections: statusEntries.map((status) {
                    final count = stats.countByStatus[status.name] ?? 0;
                    return PieChartSectionData(
                      value: count.toDouble(),
                      color: status.color,
                      radius: 44,
                      title: '$count',
                      titleStyle: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: statusEntries.map((status) {
                final count = stats.countByStatus[status.name] ?? 0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, color: status.color),
                    const SizedBox(width: 6),
                    Text(
                      '${status.label}: $count',
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
      ),
    );
  }

  Widget _buildTimelineChart(BookStats stats) {
    final data = stats.booksAddedPerMonth;
    if (data.isEmpty) return const SizedBox.shrink();

    final maxCount = data.fold<int>(
      0,
      (max, entry) {
        final c = (entry['count'] as num?)?.toInt() ?? 0;
        return c > max ? c : max;
      },
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Havi gyarapodás',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 170,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: (maxCount + 1).toDouble(),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
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
                          final m = (data[index]['month'] as String?) ?? '';
                          final label = m.length >= 7 ? m.substring(5) : m;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(data.length, (index) {
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: ((data[index]['count'] as num?)?.toInt() ?? 0)
                              .toDouble(),
                          color: AppColors.primary,
                          width: 14,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
