import 'package:flutter/material.dart';
import '../brand.dart';

/// Paints the opening artwork before loading the diary. The home subtree is
/// mounted only after initialization, including its achievement baseline.
class AppStartup extends StatefulWidget {
  const AppStartup({super.key, this.initialize, required this.child});
  final Future<void> Function()? initialize;
  final Widget child;
  static const artwork = 'assets/branding/lichen-intro-v2.webp';
  static const motionDuration = Duration(milliseconds: 2400);
  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup>
    with SingleTickerProviderStateMixin {
  late final motion =
      AnimationController(vsync: this, duration: AppStartup.motionDuration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _maybeEnter();
        });
  bool ready = false,
      failed = false,
      entered = false,
      started = false,
      entryQueued = false;

  @override
  void initState() {
    super.initState();
    ready = widget.initialize == null;
    if (!ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _prepare();
      });
    }
  }

  Future<void> _prepare() async {
    setState(() {
      failed = false;
      ready = false;
    });
    try {
      await widget.initialize!();
      if (!mounted) return;
      setState(() => ready = true);
      _maybeEnter();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      motion.value = 1;
    } else if (!started) {
      motion.forward();
    }
    started = true;
  }

  void _maybeEnter() {
    if (!mounted || entered || entryQueued || !ready || !motion.isCompleted) {
      return;
    }
    entryQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      entryQueued = false;
      _enter();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _enter() {
    if (!mounted || entered || !ready) return;
    motion.stop();
    setState(() => entered = true);
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220),
    child: entered
        ? KeyedSubtree(key: const ValueKey('startup-home'), child: widget.child)
        : LichenOpening(
            key: const ValueKey('lichen-opening'),
            motion: motion,
            ready: ready,
            failed: failed,
            onRetry: _prepare,
          ),
  );
}

/// Generated decorative collage, deliberately separate from scientific photos.
class LichenOpening extends StatelessWidget {
  const LichenOpening({
    super.key,
    required this.motion,
    required this.ready,
    required this.failed,
    required this.onRetry,
  });
  final Animation<double> motion;
  final bool ready, failed;
  final VoidCallback onRetry;

  Widget _action(BuildContext context) {
    if (failed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Avvio non riuscito. Riprova.',
            key: ValueKey('startup-error'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            key: const ValueKey('retry-startup'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Riprova'),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (MediaQuery.disableAnimationsOf(context))
          const Icon(Icons.hourglass_empty, color: Colors.white, size: 18)
        else
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        const SizedBox(width: 12),
        const Flexible(
          child: Text(
            'Sto aprendo il diario…',
            key: ValueKey('startup-loading'),
            style: TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF182E20),
    body: Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          child: AnimatedBuilder(
            animation: motion,
            child: Opacity(
              opacity: .82,
              child: Image.asset(
                AppStartup.artwork,
                fit: BoxFit.cover,
                cacheWidth: 1000,
                errorBuilder: (_, _, _) => const SizedBox.expand(),
              ),
            ),
            builder: (_, child) {
              final t = Curves.easeInOutCubic.transform(motion.value);
              return Transform.translate(
                offset: Offset(2.5 * t, -4 * t),
                child: Transform.scale(scale: 1 + .045 * t, child: child),
              );
            },
          ),
        ),
        // Contrast only near the footer; the centre stays photographic throughout.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.transparent,
                Color(0xE609140E),
              ],
              stops: [0, .62, 1],
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: AnimatedBuilder(
              animation: motion,
              child: Semantics(
                header: true,
                child: Text(
                  AppBrand.name.toUpperCase(),
                  key: const ValueKey('opening-title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 46,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    shadows: [Shadow(color: Color(0xCC000000), blurRadius: 20)],
                  ),
                ),
              ),
              builder: (_, child) {
                final t = Curves.easeOut.transform(
                  (motion.value / .6).clamp(0.0, 1.0),
                );
                return Opacity(
                  opacity: .55 + .45 * t,
                  child: Transform.translate(
                    offset: Offset(0, 6 * (1 - t)),
                    child: child,
                  ),
                );
              },
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AnimatedBuilder(
                animation: motion,
                builder: (_, _) => !ready && (failed || motion.value == 1)
                    ? _action(context)
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
