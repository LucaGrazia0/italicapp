import 'package:flutter/material.dart';
import 'app_store.dart';
import 'data/observation_repository.dart';
import 'pages/capture_page.dart';
import 'pages/diary_page.dart';
import 'pages/italic_page.dart';
import 'pages/settings_page.dart';
import 'theme/app_theme.dart';
import 'data/scientific_data.dart';
import 'brand.dart';
import 'widgets/field_navigation.dart';
import 'pages/findings_map_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore(ObservationRepository());
  await Future.wait([store.init(), ScientificData.initialize()]);
  runApp(ItalicApp(store: store));
}

class ItalicApp extends StatelessWidget {
  const ItalicApp({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppBrand.name,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: Shell(store: store),
  );
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.store});
  final AppStore store;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;
  final visited = <int>{0};

  void select(int value) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      index = value;
      visited.add(value);
    });
  }

  @override
  void initState() {
    super.initState();
    ScientificData.changes.addListener(_dataChanged);
  }

  void _dataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ScientificData.changes.removeListener(_dataChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DiaryPage(store: widget.store),
      CapturePage(store: widget.store, onSaved: () => select(0)),
      ItalicPage(key: ValueKey(ScientificData.currentRevision)),
      FindingsMapPage(store: widget.store),
      SettingsPage(
        store: widget.store,
        onOpenDiary: () => select(0),
        onOpenItalic: () => select(2),
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: IndexedStack(
              index: index,
              children: [
                for (var i = 0; i < pages.length; i++)
                  TickerMode(
                    enabled: index == i,
                    child: visited.contains(i)
                        ? pages[i]
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: FieldNavigation(index: index, onSelected: select),
    );
  }
}
