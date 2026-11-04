import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Egyszerű üres-állapot kijelző, ha nincs könyv vagy találat.
class EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final IconData? secondaryActionIcon;
  final VoidCallback? onSecondaryAction;

  const EmptyState({
    super.key,
    this.title = 'A könyvtárad üres',
    this.subtitle = 'Adj hozzá könyvet vonalkóddal vagy kereséssel.',
    this.icon = Icons.menu_book_outlined,
    this.actionLabel,
    this.actionIcon = Icons.qr_code_scanner,
    this.onAction,
    this.secondaryActionLabel,
    this.secondaryActionIcon,
    this.onSecondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: onAction,
                    icon: Icon(actionIcon, size: 18),
                    label: Text(actionLabel!),
                  ),
                  if (secondaryActionLabel != null &&
                      onSecondaryAction != null)
                    OutlinedButton.icon(
                      onPressed: onSecondaryAction,
                      icon: Icon(secondaryActionIcon ?? Icons.add, size: 18),
                      label: Text(secondaryActionLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
