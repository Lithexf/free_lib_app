import 'package:flutter/material.dart';
import '../ui/theme/app_colors.dart';

/// All possible reading statuses a book can have in the user's library.
enum ReadingStatus {
  planToRead('Plan to Read', Icons.bookmark_outline, AppColors.statusPlanToRead),
  reading('Reading', Icons.auto_stories, AppColors.statusReading),
  completed('Completed', Icons.check_circle_outline, AppColors.statusCompleted),
  onHold('On Hold', Icons.pause_circle_outline, AppColors.statusOnHold),
  dropped('Dropped', Icons.cancel_outlined, AppColors.statusDropped),
  rereading('Re-reading', Icons.replay, AppColors.statusRereading);

  const ReadingStatus(this.label, this.icon, this.color);

  /// Human-readable label for display
  final String label;

  /// Icon associated with this status
  final IconData icon;

  /// Color associated with this status
  final Color color;

  /// Convert from database string to enum
  static ReadingStatus fromString(String value) {
    return ReadingStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ReadingStatus.planToRead,
    );
  }
}
