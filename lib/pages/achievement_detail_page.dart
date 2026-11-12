import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';
import '../services/achievement_profiles.dart';
import '../services/field_achievements.dart';
import '../theme/app_theme.dart';

class AchievementDetailPage extends StatefulWidget {
  const AchievementDetailPage({
    super.key,
    required this.achievements,
    this.celebration = false,
    this.unlocked = true,
  });
  final List<FieldAchievement> achievements;
  final bool celebration, unlocked;
  @override
  State<AchievementDetailPage> createState() => _AchievementDetailPageState();
}

class _AchievementDetailPageState extends State<AchievementDetailPage> {
  int position = 0;
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final achievement = widget.achievements[position];
    final profile = achievementProfiles[achievement.target]!;
    return Scaffold(
      key: const ValueKey('achievement-detail-page'),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          widget.celebration ? 'Un nuovo traguardo' : achievement.title,
        ),
        actions: [
          IconButton(
            key: const ValueKey('close-achievement'),
            tooltip: 'Chiudi',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              children: [
                if (widget.achievements.length > 1)
                  Text(
                    'Medaglia ${position + 1} di ${widget.achievements.length}',
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 10),
                Center(
                  child: Chip(
                    avatar: Icon(
                      widget.unlocked ? Icons.auto_awesome : Icons.lock_outline,
                      size: 18,
                    ),
                    label: Text(
                      widget.unlocked
                          ? 'Medaglia sbloccata'
                          : 'Una storia da scoprire',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SpinningMedal(
                  key: ValueKey('spinning-medal-${achievement.target}'),
                  achievement: achievement,
                  unlocked: widget.unlocked,
                ),
                const SizedBox(height: 14),
                Text(
                  achievement.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.forest,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${profile.material} · ${achievement.target} ${achievement.target == 1 ? 'specie diversa' : 'specie diverse'}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          key: const ValueKey('achievement-person'),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          profile.dates,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          profile.biography,
                          style: const TextStyle(height: 1.6, fontSize: 16),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Fonti e letture',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        for (final source in profile.sources)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(source.title),
                                Link(
                                  uri: Uri.parse(source.url),
                                  target: LinkTarget.blank,
                                  builder: (_, follow) => TextButton.icon(
                                    onPressed: follow,
                                    icon: const Icon(
                                      Icons.open_in_new,
                                      size: 16,
                                    ),
                                    label: const Text('Apri fonte online'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Text(
                          'Il profilo è disponibile offline; le fonti si aprono con internet.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Un traguardo personale di Italic Go, dedicato a chi ha contribuito alla conoscenza dei licheni.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('continue-achievement'),
                  onPressed: () {
                    if (position + 1 == widget.achievements.length) {
                      Navigator.pop(context);
                    } else {
                      setState(() => position++);
                      scroll.jumpTo(0);
                    }
                  },
                  icon: Icon(
                    position + 1 == widget.achievements.length
                        ? Icons.check
                        : Icons.arrow_forward,
                  ),
                  label: Text(
                    position + 1 == widget.achievements.length
                        ? 'Continua'
                        : 'Prossima medaglia',
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

/// One finite turn, rather than a perpetual animation. The PNGs supplied for the
/// medals are reused at every platform's native resolution.
class SpinningMedal extends StatefulWidget {
  const SpinningMedal({
    super.key,
    required this.achievement,
    required this.unlocked,
  });
  final FieldAchievement achievement;
  final bool unlocked;
  @override
  State<SpinningMedal> createState() => _SpinningMedalState();
}

class _SpinningMedalState extends State<SpinningMedal>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  bool started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) || !widget.unlocked) {
      controller.value = 1;
    } else if (!started) {
      controller.forward();
    }
    started = true;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final medal =
        achievementMedals[fieldAchievements.indexOf(widget.achievement)];
    final profile = achievementProfiles[widget.achievement.target]!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '${widget.achievement.title}, ${profile.material}',
          image: true,
          child: ExcludeSemantics(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final diameter = math.min(230.0, constraints.maxWidth);
                return SizedBox.square(
                  dimension: diameter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFE5D8AF).withValues(alpha: .6),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: AnimatedBuilder(
                      animation: controller,
                      child: Opacity(
                        opacity: widget.unlocked ? 1 : .4,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Image.asset(
                            'assets/medals/$medal.png',
                            cacheWidth: 660,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      builder: (_, child) {
                        final t = Curves.easeOutCubic.transform(
                          controller.value,
                        );
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, .0015)
                            ..rotateY(2 * math.pi * t)
                            ..scaleByDouble(.88 + .12 * t, .88 + .12 * t, 1, 1),
                          child: child,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.unlocked && !MediaQuery.disableAnimationsOf(context))
          TextButton.icon(
            key: const ValueKey('replay-medal'),
            onPressed: () => controller.forward(from: 0),
            icon: const Icon(Icons.rotate_right, size: 18),
            label: const Text('Fai girare la medaglia'),
          ),
      ],
    );
  }
}
