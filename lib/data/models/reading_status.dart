import 'package:flutter/material.dart';

/// All possible reading statuses a book can have in the user's library.
enum ReadingStatus {
  planToRead('Plan to Read', Icons.bookmark_outline, Color(0xFF5B8DEF)),
  reading('Reading', Icons.auto_stories, Color(0xFF00D9A6)),
  completed('Completed', Icons.check_circle_outline, Color(0xFFE8A838)),
  onHold('On Hold', Icons.pause_circle_outline, Color(0xFFFF9F43)),
  dropped('Dropped', Icons.cancel_outlined, Color(0xFFFF6B6B)),
  rereading('Re-reading', Icons.replay, Color(0xFFAB7AFF));

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
