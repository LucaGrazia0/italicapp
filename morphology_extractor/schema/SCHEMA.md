# Schema dei caratteri

Ogni file rappresenta un taxon e conserva identità, metodo di estrazione, modello realmente usato e stato della revisione. `characters` contiene osservazioni atomiche: una proprietà per record, associata a una struttura e sostenuta da una citazione letterale.

`structure` usa un vocabolario controllato. `part` consente una specificazione più fine senza mescolare la proprietà. `character` è un vocabolario estensibile; valori consigliati sono `presence`, `growth_form`, `color`, `shape`, `size`, `position`, `surface`, `consistency`, `anatomy`, `chemical_reaction`, `secondary_metabolite` e `diagnostic_feature`.

`status` distingue `present`, `absent`, `variable`, `ambiguous` e `reported`. La mancanza di un record significa soltanto “non riportato”: non equivale mai ad assenza.

`normalized_values` è una lista per preservare alternative. Ogni valore mantiene obbligatoriamente `raw`, cioè la grafia originale, e può aggiungere campi normalizzati. Gli intervalli conservano estremi e unità; le reazioni usano `reaction`, `value` e, se presente, `color`.

`qualifiers` conserva avverbi e condizioni. `certainty` descrive la chiarezza del testo. `review_required` segnala variabilità, ambiguità o interpretazioni che richiedono controllo umano.

`warnings` raccoglie problemi trasversali, come una struttura che potrebbe appartenere al lichene ospite. `review_status` è separato dalla validazione automatica: un JSON formalmente valido non è scientificamente approvato.
