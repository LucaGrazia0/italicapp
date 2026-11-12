import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:italicapp/widgets/key_step_transition.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets(
      'A step changes immediately, briefly blocks duplicate taps and respects reduced motion: $reduced',
      (tester) async {
        var step = 1;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return MediaQuery(
                  data: MediaQueryData(disableAnimations: reduced),
                  child: Scaffold(
                    body: KeyStepTransition(
                      step: step,
                      child: TextButton(
                        onPressed: () => update(() => step++),
                        child: Text('Bivio $step'),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('Bivio 1'));
        await tester.pump();
        expect(find.text('Bivio 2'), findsOneWidget);
        expect(find.text('Bivio 1'), findsNothing);
        final pointer = find
            .descendant(
              of: find.byType(KeyStepTransition),
              matching: find.byType(IgnorePointer),
            )
            .first;
        expect(tester.widget<IgnorePointer>(pointer).ignoring, !reduced);
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.widget<IgnorePointer>(pointer).ignoring, false);
        await tester.tap(find.text('Bivio 2'));
        await tester.pumpAndSettle();
        expect(find.text('Bivio 3'), findsOneWidget);
        update(() => step--);
        await tester.pumpAndSettle();
        expect(find.text('Bivio 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
