import 'package:flutter/material.dart';
import '../models/observation.dart';
import '../data/italic_reference_repository.dart';

enum FindingColorMode { identification, growth, substrate }

extension FindingColorLabel on FindingColorMode {
  String get label => switch (this) {
    FindingColorMode.identification => 'Identificazione',
    FindingColorMode.growth => 'Forma di crescita',
    FindingColorMode.substrate => 'Substrato',
  };
}

class FindingCategory {
  const FindingCategory(this.label, this.color);
  final String label;
  final Color color;
}

class MapCategories {
  MapCategories(Iterable<ItalicTaxon> taxa) {
    for (final taxon in taxa) {
      if (taxon.italicId != null) {
        byId[taxon.italicId] = taxon;
      }
      for (final name in [taxon.scientificName, ...taxon.synonyms]) {
        final key = name.trim().toLowerCase();
        byName.putIfAbsent(key, () => []).add(taxon);
      }
    }
  }
  final byId = <int?, ItalicTaxon>{};
  final byName = <String, List<ItalicTaxon>>{};
  static const unknown = FindingCategory('Non specificato', Color(0xFF68747D));
  FindingCategory category(
    Observation o,
    FindingColorMode mode, {
    String? plotSubstrate,
  }) {
    if (mode == FindingColorMode.identification) {
      return o.rank == IdentificationRank.species &&
              o.taxonName?.trim().isNotEmpty == true
          ? const FindingCategory('Identificata', Color(0xFF24833D))
          : const FindingCategory('Non identificata', Color(0xFFD32F2F));
    }
    if (mode == FindingColorMode.substrate) {
      final text = (o.substrate ?? plotSubstrate ?? '').toLowerCase();
      if (text.contains('silice')) {
        return const FindingCategory('Roccia silicea', Color(0xFF5B5AC7));
      }
      if (text.contains('calcar')) {
        return const FindingCategory('Roccia calcarea', Color(0xFFAA7024));
      }
      if (text.contains('cortecc')) {
        return const FindingCategory('Corteccia', Color(0xFF8D4D30));
      }
      if (text.contains('legno')) {
        return const FindingCategory('Legno', Color(0xFFB45504));
      }
      if (text.contains('suolo')) {
        return const FindingCategory('Suolo', Color(0xFF706321));
      }
      if (text.contains('muschi')) {
        return const FindingCategory('Muschio', Color(0xFF278650));
      }
      return text.isEmpty
          ? unknown
          : const FindingCategory('Altro substrato', Color(0xFFAB3686));
    }
    if (o.rank != IdentificationRank.species) return unknown;
    final matches = byName[o.taxonName?.trim().toLowerCase()];
    final taxon =
        byId[o.taxonItalicId] ??
        (matches?.length == 1 ? matches!.single : null);
    final growth = (taxon?.growthForm ?? '').toLowerCase();
    if (growth.startsWith('foliose')) {
      return const FindingCategory('Foglioso', Color(0xFF278650));
    }
    if (growth.startsWith('crustose')) {
      return const FindingCategory('Crostoso', Color(0xFFD0770A));
    }
    if (growth.startsWith('fruticose')) {
      return const FindingCategory('Fruticoso', Color(0xFF326FC4));
    }
    if (growth.startsWith('squamulose')) {
      return const FindingCategory('Squamuloso', Color(0xFF9854BD));
    }
    if (growth.startsWith('leprose')) {
      return const FindingCategory('Leproso', Color(0xFFC84575));
    }
    if (growth.startsWith('lichenicolous')) {
      return const FindingCategory('Lichenicolo', Color(0xFF835232));
    }
    if (growth.startsWith('non-lichenised')) {
      return const FindingCategory('Non lichenizzato', Color(0xFF28898C));
    }
    return unknown;
  }
}
