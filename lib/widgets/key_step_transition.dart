import 'package:flutter/material.dart';

/// A short visual beat without async delays, loading screens or duplicated
/// outgoing buttons. Only the incoming step owns interactive controls.
class KeyStepTransition extends StatefulWidget {
  const KeyStepTransition({super.key, required this.step, required this.child});
  final Object step;
  final Widget child;
  static const duration = Duration(milliseconds: 200);
  @override
  State<KeyStepTransition> createState() => _KeyStepTransitionState();
}

class _KeyStepTransitionState extends State<KeyStepTransition>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: KeyStepTransition.duration,
    value: 1,
  );
  @override
  void didUpdateWidget(KeyStepTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step != widget.step) {
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.value = 1;
      } else {
        controller.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) controller.value = 1;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    child: widget.child,
    builder: (_, child) {
      final t = Curves.easeOutCubic.transform(controller.value);
      return ExcludeFocus(
        excluding: controller.isAnimating,
        child: IgnorePointer(
          ignoring: controller.isAnimating,
          child: Opacity(
            opacity: .2 + .8 * t,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - t)),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}
