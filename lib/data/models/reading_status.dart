import 'package:flutter/material.dart';

/// A felhasználó könyvtárában szereplő könyvek lehetséges olvasási állapotai.
enum ReadingStatus {
  planToRead('Tervben van', Icons.bookmark_outline, Color(0xFF5B8DEF)),
  reading('Olvasom', Icons.auto_stories, Color(0xFF00D9A6)),
  completed('Befejezve', Icons.check_circle_outline, Color(0xFFE8A838)),
  onHold('Szüneteltetve', Icons.pause_circle_outline, Color(0xFFFF9F43)),
  dropped('Abbahagyott', Icons.cancel_outlined, Color(0xFFFF6B6B)),
  rereading('Újraolvasom', Icons.replay, Color(0xFFAB7AFF));

  const ReadingStatus(this.label, this.icon, this.color);

  /// Megjelenítendő magyar megnevezés
  final String label;

  /// Az állapothoz tartozó ikon
  final IconData icon;

  /// Az állapothoz tartozó szín
  final Color color;

  /// Adatbázisbeli szöveges értékből felsorolási típusra alakítás
  static ReadingStatus fromString(String value) {
    return ReadingStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ReadingStatus.planToRead,
    );
  }
}
