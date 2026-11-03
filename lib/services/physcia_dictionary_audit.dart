import '../data/character_matrix_repository.dart';
import '../models/character_review.dart';
import 'character_dictionary.dart';
import 'physcia_review_engine.dart';

enum PhysciaAuditStatus {
  available('Proposte disponibili'),
  compare('Da confrontare'),
  uncertain('Testi da chiarire'),
  missing('Non documentato'),
  manual('Valutazioni manuali'),
  consistent('Valori concordanti'),
  notApplicable('Non applicabile'),
  stale('Fonte da aggiornare');

  const PhysciaAuditStatus(this.label);
  final String label;
}

class PhysciaAuditCell {
  const PhysciaAuditCell({
    required this.row,
    required this.character,
    required this.proposal,
    required this.record,
    required this.status,
    required this.message,
    this.relatedCharacter,
  });
  final MatrixTaxon row;
  final PilotCharacter character;
  final ReviewProposal proposal;
  final CharacterReview? record;
  final PhysciaAuditStatus status;
  final String message;
  final PilotCharacter? relatedCharacter;
}

/// Read-only comparison. A dictionary disagreement never changes the registry
/// or invalidates an author's judgement by itself.
class PhysciaDictionaryAudit {
  List<PhysciaAuditCell> analyze(
    CharacterMatrix matrix,
    CharacterDictionary dictionary,
    ReviewRegistry registry,
  ) {
    final result = <PhysciaAuditCell>[];
    for (final row in matrix.taxa.where((r) => PhysciaPilot.inScope(r.taxon))) {
      final proposals = {
        for (final c in PhysciaPilot.characters)
          c.id: PhysciaPilot.proposal(row, c, dictionary: dictionary),
      };
      for (final c in PhysciaPilot.characters) {
        final proposal = proposals[c.id]!;
        final record = registry.latest(row.taxon.italicId!, c.id);
        PhysciaAuditCell cell(
          PhysciaAuditStatus status,
          String message, [
          PilotCharacter? related,
        ]) => PhysciaAuditCell(
          row: row,
          character: c,
          proposal: proposal,
          record: record,
          status: status,
          message: message,
          relatedCharacter: related,
        );
        final absence = PhysciaPilot.absenceFor(registry, row.taxon, c.id);
        if (absence != null) {
          result.add(
            cell(
              PhysciaAuditStatus.notApplicable,
              'Dipende da ${PhysciaPilot.absenceLabel(absence)} · ${absence.statusLabel}. La cronologia è conservata.',
            ),
          );
          continue;
        }
        if (record != null &&
            (!record.matches(row.taxon) || !c.validValue(record.value))) {
          result.add(
            cell(
              PhysciaAuditStatus.stale,
              'La fonte o la codifica è cambiata: riapri la cella prima di usarla.',
            ),
          );
          continue;
        }
        if (record != null && record.quote.trim().isNotEmpty) {
          // These pairs address actual organ/attribute mixups. Presence in a
          // different field is a suggestion to inspect, never an automatic edit.
          final relatedId = const {
            'upper_surface_pruina': 'apothecia_disc_pruina',
            'apothecia_shape': 'apothecia_insertion',
          }[c.id];
          if (relatedId != null) {
            bool supports(ReviewProposal p) => p.hits.any(
              (h) =>
                  h.quote.contains(record.quote) &&
                  record.quote.contains(h.term),
            );
            if (!supports(proposal) && supports(proposals[relatedId]!)) {
              final related = PhysciaPilot.character(relatedId)!;
              result.add(
                cell(
                  PhysciaAuditStatus.compare,
                  'La citazione salvata sembra riferirsi a «${related.label}», anziché a «${c.label}». Controlla il contesto: nessun valore è stato spostato.',
                  related,
                ),
              );
              continue;
            }
          }
        }
        if (proposal.isCandidate) {
          if (record == null || record.value == 'unknown') {
            result.add(
              cell(
                PhysciaAuditStatus.available,
                record == null
                    ? 'Il dizionario propone un valore con citazione. Apri la cella per verificarlo e salvarlo.'
                    : 'Il valore incerto già salvato ha precedenza. Puoi riprendere esplicitamente la proposta come nuova bozza.',
              ),
            );
          } else if (c.stable(record.value) &&
              c.encode(c.selected(record.value)) ==
                  c.encode(c.selected(proposal.value))) {
            result.add(
              cell(
                PhysciaAuditStatus.consistent,
                'Il valore salvato concorda con la proposta del dizionario. Stato della cella: ${record.statusLabel}.',
              ),
            );
          } else if (c.stable(record.value)) {
            result.add(
              cell(
                PhysciaAuditStatus.compare,
                'Valore salvato e proposta del dizionario differiscono. Verifica la citazione e le condizioni: la tua revisione resta conservata.',
              ),
            );
          } else {
            result.add(
              cell(
                PhysciaAuditStatus.manual,
                'È presente una codifica manuale non stabile (${record.statusLabel}). La proposta è disponibile per il confronto.',
              ),
            );
          }
        } else if (record != null) {
          result.add(
            cell(
              PhysciaAuditStatus.manual,
              'Valore inserito manualmente. Il dizionario non produce una proposta univoca equivalente; questo non dimostra che la valutazione sia errata.',
            ),
          );
        } else if (proposal.status == 'needs_review') {
          result.add(
            cell(
              PhysciaAuditStatus.uncertain,
              'Menzioni, condizioni o più stati richiedono lettura del testo. Nessuna assenza dedotta.',
            ),
          );
        } else {
          result.add(
            cell(
              PhysciaAuditStatus.missing,
              'Nessuna evidenza riconosciuta nel contesto richiesto. Non documentato non significa assente.',
            ),
          );
        }
      }
    }
    return result;
  }
}
