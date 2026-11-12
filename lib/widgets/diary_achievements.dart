import 'package:flutter/material.dart';
import '../app_store.dart';
import '../pages/achievement_detail_page.dart';
import '../data/scientific_data.dart';
import '../services/field_achievements.dart';
import '../theme/app_theme.dart';

class DiaryAchievements extends StatefulWidget {
  const DiaryAchievements({super.key, required this.store, this.loadIndex});
  final AppStore store;
  final Future<FieldAchievementIndex> Function()? loadIndex;
  @override
  State<DiaryAchievements> createState() => _DiaryAchievementsState();
}

class _DiaryAchievementsState extends State<DiaryAchievements> {
  late Future<FieldAchievementIndex> loading;

  void reload() => setState(() {
    loading = (widget.loadIndex ?? FieldAchievementIndex.load)();
  });
  @override
  void initState() {
    super.initState();
    loading = (widget.loadIndex ?? FieldAchievementIndex.load)();
    ScientificData.changes.addListener(reload);
  }

  @override
  void dispose() {
    ScientificData.changes.removeListener(reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FieldAchievementIndex>(
    future: loading,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return OutlinedButton.icon(
          onPressed: reload,
          icon: const Icon(Icons.emoji_events_outlined, size: 18),
          label: const Text('Traguardi · Riprova'),
        );
      }
      if (!snapshot.hasData) {
        return const OutlinedButton(
          key: ValueKey('open-achievements'),
          onPressed: null,
          child: Text('Traguardi'),
        );
      }
      return ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) {
          final progress = snapshot.data!.progress(
            widget.store.observations,
            additionalSpecies: widget.store.plots.expand(
              (p) => p.species.map((s) => s.name),
            ),
          );
          return OutlinedButton.icon(
            key: const ValueKey('open-achievements'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FieldAchievementsPage(
                  store: widget.store,
                  index: snapshot.data!,
                ),
              ),
            ),
            icon: const Icon(Icons.emoji_events_outlined, size: 18),
            label: Text(
              'Traguardi · ${progress.unlockedCount}/${fieldAchievements.length}',
              key: const ValueKey('achievement-unlocked-count'),
            ),
          );
        },
      );
    },
  );
}

class FieldAchievementsPage extends StatelessWidget {
  const FieldAchievementsPage({
    super.key,
    required this.store,
    required this.index,
  });
  final AppStore store;
  final FieldAchievementIndex index;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('I tuoi traguardi')),
    body: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final progress = index.progress(
          store.observations,
          additionalSpecies: store.plots.expand(
            (p) => p.species.map((s) => s.name),
          ),
        );
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${progress.speciesCount} ${progress.speciesCount == 1 ? 'specie diversa' : 'specie diverse'}',
              key: const ValueKey('achievement-page-count'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppTheme.forest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${progress.unlockedCount} di ${fieldAchievements.length} traguardi sbloccati',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Ogni specie conta una volta: più foto, sinonimi, sottospecie e varietà della stessa specie non aumentano il conteggio. Contano le determinazioni a livello di specie riconosciute nella checklist locale.',
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < fieldAchievements.length; i++)
              _AchievementBadge(
                achievement: fieldAchievements[i],
                progress: progress,
                medal: achievementMedals[i],
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'I traguardi funzionano offline e si aggiornano con le specie presenti nel diario, anche dopo correzioni o eliminazioni. Nessuna foto o posizione viene inviata per il conteggio.',
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({
    required this.achievement,
    required this.progress,
    required this.medal,
  });
  final FieldAchievement achievement;
  final FieldAchievementProgress progress;
  final String medal;
  @override
  Widget build(BuildContext context) {
    final unlocked = progress.unlocked(achievement);
    final color = unlocked ? AppTheme.forest : const Color(0xFF626D65);
    return Semantics(
      container: true,
      child: Card(
        key: ValueKey('achievement-${achievement.target}'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: unlocked ? AppTheme.sage : const Color(0xFFE1E6DE),
            width: unlocked ? 1.5 : 1,
          ),
        ),
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AchievementDetailPage(
                achievements: [achievement],
                unlocked: unlocked,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Opacity(
                  opacity: unlocked ? 1 : .35,
                  child: Image.asset(
                    'assets/medals/$medal.png',
                    width: 76,
                    height: 76,
                    cacheWidth: 240,
                    semanticLabel: achievement.description,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        achievement.title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                      ),
                      Text(
                        '${achievement.target} ${achievement.target == 1 ? 'specie diversa' : 'specie diverse'}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 5),
                      Text(achievement.description),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            unlocked ? Icons.check_circle : Icons.lock_outline,
                            size: 17,
                            color: color,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              unlocked
                                  ? 'Sbloccato'
                                  : '${progress.remaining(achievement) == 1 ? 'Manca' : 'Mancano'} ${progress.remaining(achievement)} specie',
                              key: ValueKey(
                                'achievement-state-${achievement.target}',
                              ),
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              unlocked
                                  ? 'Rivedi la medaglia e la storia'
                                  : 'Scopri il lichenologo',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right, color: color),
                        ],
                      ),
                      if (!unlocked) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: progress.fraction(achievement),
                          minHeight: 5,
                          borderRadius: BorderRadius.circular(6),
                          semanticsLabel: achievement.title,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
