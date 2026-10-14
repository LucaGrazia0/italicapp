import 'package:flutter/material.dart';
import 'app_store.dart';
import 'data/observation_repository.dart';
import 'pages/capture_page.dart';
import 'pages/diary_page.dart';
import 'pages/italic_page.dart';
import 'pages/settings_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore(ObservationRepository());
  await store.init();
  runApp(ItalicApp(store: store));
}

class ItalicApp extends StatelessWidget {
  const ItalicApp({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'italicapp',
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
  @override
  Widget build(BuildContext context) {
    final pages = [
      DiaryPage(store: widget.store),
      CapturePage(
        store: widget.store,
        onSaved: () => setState(() => index = 0),
      ),
      const ItalicPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: IndexedStack(index: index, children: pages),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        height: 76,
        elevation: 0,
        backgroundColor: const Color(0xFFF5F2E9),
        indicatorColor: const Color(0xFF88A68B),
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Diario',
          ),
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: 'Fotocamera',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'ITALIC',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Impostazioni',
          ),
        ],
      ),
    );
  }
}
