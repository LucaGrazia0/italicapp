import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class FieldNavigation extends StatelessWidget {
  const FieldNavigation({
    super.key,
    required this.index,
    required this.onSelected,
  });
  final int index;
  final ValueChanged<int> onSelected;
  static const labels = [
    'Diario',
    'Fotocamera',
    'ITALIC',
    'Mappa',
    'Impostazioni',
  ];
  static const icons = [
    Icons.calendar_month_outlined,
    Icons.camera_alt_outlined,
    Icons.menu_book_rounded,
    Icons.map_outlined,
    Icons.settings_outlined,
  ];

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: AppTheme.ivory,
      border: Border(top: BorderSide(color: Color(0xFFDBE4DA))),
      boxShadow: [
        BoxShadow(
          color: Color(0x14234C3A),
          blurRadius: 18,
          offset: Offset(0, -4),
        ),
      ],
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Semantics(
                    button: true,
                    selected: index == i,
                    label: labels[i],
                    child: Material(
                      color: i == 2
                          ? AppTheme.forest
                          : index == i
                          ? const Color(0xFFE7EFE3)
                          : Colors.white,
                      elevation: i == 2 ? 3 : 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: i == 2
                              ? AppTheme.forest
                              : index == i
                              ? AppTheme.sage
                              : const Color(0xFFD6E1D2),
                          width: index == i ? 1.8 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey('nav-$i'),
                        onTap: () => onSelected(i),
                        child: SizedBox(
                          height: i == 2 ? 74 : 64,
                          child: ExcludeSemantics(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  icons[i],
                                  size: i == 2 ? 30 : 28,
                                  color: i == 2
                                      ? Colors.white
                                      : AppTheme.forest,
                                ),
                                if (i == 2) ...[
                                  const SizedBox(height: 5),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    child: Text(
                                      labels[i],
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: i == 2 ? 12 : 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: i == 2
                                            ? Colors.white
                                            : AppTheme.charcoal,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
