import 'package:flutter/material.dart';
import '../models/ecological_scale.dart';
import '../services/ecological_compatibility_engine.dart';

class EcologicalFilters extends StatelessWidget {
  const EcologicalFilters({
    super.key,
    required this.scales,
    required this.photobiont,
    required this.reproduction,
    required this.onScaleChanged,
    required this.onPhotobiontChanged,
    required this.onReproductionChanged,
  });

  final Map<String, int> scales;
  final String photobiont, reproduction;
  final void Function(String, int?) onScaleChanged;
  final ValueChanged<String> onPhotobiontChanged, onReproductionChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 16),
      _category(
        'Fotobionte',
        photobiont,
        EcologicalCompatibilityEngine.photobiontOptions,
        onPhotobiontChanged,
      ),
      const SizedBox(height: 16),
      _category(
        'Strategia riproduttiva',
        reproduction,
        EcologicalCompatibilityEngine.reproductionOptions,
        onReproductionChanged,
      ),
      const Divider(height: 32),
      Text(
        'Scale ecologiche ITALIC',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 6),
      const Text(
        'Seleziona le classi che conosci. Sono indici ecologici: '
        'il pH non è una misura di laboratorio e la classe altitudinale non è una quota in metri. '
        'Lascia “Qualsiasi” per i criteri non osservati.',
      ),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 620
              ? (constraints.maxWidth - 16) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final definition in EcologicalScaleDefinition.all)
                SizedBox(
                  width: width,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(
                      'scale-${definition.key}-${scales[definition.key] ?? "all"}',
                    ),
                    initialValue: scales[definition.key],
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText:
                          '${definition.label} (${definition.min}–${definition.max})',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<int>(
                        value: null,
                        child: Text('Qualsiasi'),
                      ),
                      for (
                        var value = definition.min;
                        value <= definition.max;
                        value++
                      )
                        DropdownMenuItem(
                          value: value,
                          child: Text('Classe $value'),
                        ),
                    ],
                    onChanged: (value) => onScaleChanged(definition.key, value),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 8),
    ],
  );

  Widget _category(
    String label,
    String selected,
    Map<String, String> options,
    ValueChanged<String> changed,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label-$selected'),
    initialValue: selected,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final option in options.entries)
        DropdownMenuItem(value: option.key, child: Text(option.value)),
    ],
    onChanged: (value) {
      if (value != null) changed(value);
    },
  );
}
