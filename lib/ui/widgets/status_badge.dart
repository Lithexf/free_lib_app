import 'package:flutter/material.dart';
import '../../data/models/reading_status.dart';
import '../theme/app_colors.dart';

/// Egyszerű szöveges állapotcímke.
class StatusBadge extends StatelessWidget {
  final ReadingStatus status;
  final bool selected;
  final VoidCallback? onTap;
  final bool compact;

  const StatusBadge({
    super.key,
    required this.status,
    this.selected = false,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? status.color : AppColors.surfaceBorder,
          ),
        ),
        child: Text(
          status.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: status.color,
            fontSize: compact ? 10 : 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
