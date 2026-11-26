import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The text determines the height. No inherited button sizing or line limits.
class KeyChoiceCard extends StatelessWidget {
  const KeyChoiceCard({
    super.key,
    required this.letter,
    required this.label,
    required this.onPressed,
  });
  final String letter, label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onPressed != null,
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0xFFD4E0D4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.forest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      letter,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Alternativa $letter',
                      style: const TextStyle(
                        color: AppTheme.forest,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 22,
                    color: AppTheme.forest,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DefaultTextStyle(
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 18,
                  height: 1.5,
                  color: AppTheme.charcoal,
                ),
                child: Text(
                  label,
                  softWrap: true,
                  textWidthBasis: TextWidthBasis.parent,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Full-width actions with an explicitly bounded, wrapping text column.
class KeyActionButton extends StatelessWidget {
  const KeyActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.subtitle,
    this.trailing = false,
  });
  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary, trailing;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? Colors.white : AppTheme.forest;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Material(
        color: primary ? AppTheme.forest : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: primary ? AppTheme.forest : const Color(0xFFD4E0D4),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                Icon(icon, size: 23, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        softWrap: true,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 16,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          softWrap: true,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: foreground, size: 22),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class KeySheetHeader extends StatelessWidget {
  const KeySheetHeader({super.key, required this.title, required this.onClose});
  final String title;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 8, 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppTheme.forest,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Chiudi',
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

class KeyNotice extends StatelessWidget {
  const KeyNotice({
    super.key,
    required this.title,
    required this.message,
    this.action,
  });
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFBF1E1),
      border: Border.all(color: const Color(0xFFE8D9BD)),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
        ),
        const SizedBox(height: 6),
        Text(message, style: const TextStyle(height: 1.5)),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    ),
  );
}
