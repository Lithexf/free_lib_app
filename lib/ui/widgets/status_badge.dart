import 'package:flutter/material.dart';
import '../../data/models/reading_status.dart';

/// Color-coded reading status badge chip.
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: selected
              ? status.color.withValues(alpha: 0.2)
              : status.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? status.color.withValues(alpha: 0.6)
                : status.color.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              status.icon,
              size: compact ? 12 : 14,
              color: status.color,
            ),
            const SizedBox(width: 4),
            Text(
              status.label,
              style: TextStyle(
                color: status.color,
                fontSize: compact ? 10 : 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
