import 'package:flutter/material.dart';
import '../data/italic_reference_repository.dart';

class ItalicTaxonPage extends StatelessWidget {
  const ItalicTaxonPage({super.key,required this.taxon});
  final ItalicTaxon taxon;

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Scheda ITALIC')),
    body:Align(alignment:Alignment.topCenter,child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:800),
      child:ListView(padding:const EdgeInsets.all(20),children:[
        Text(taxon.scientificName,style:Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontStyle:FontStyle.italic,fontWeight:FontWeight.w800)),
        if(taxon.italicId!=null) Text('ITALIC ID ${taxon.italicId}'),
        const Divider(height:32),
        if(taxon.description?.trim().isNotEmpty==true) block(context,'Descrizione',taxon.description!),
        if(taxon.synonyms.isNotEmpty) block(context,'Sinonimi',taxon.synonyms.join('\n')),
        blockMaybe(context,'Distribuzione italiana',taxon.distribution),
        blockMaybe(context,'Nota ecologica',taxon.note),
        const SizedBox(height:10),
        heading(context,'Caratteri ed ecologia'),
        blockMaybe(context,'Forma di crescita',taxon.growthForm),
        blockMaybe(context,'Substrato',taxon.substrata),
        blockMaybe(context,'Fotobionte',taxon.photobiont),
        blockMaybe(context,'Strategia riproduttiva',taxon.reproductiveStrategy),
        blockMaybe(context,'Affinità climatica',taxon.climaticAffinity),
        if(taxon.belts.isNotEmpty)...[
          heading(context,'Fasce / ecoregioni'),
          for(final e in taxon.belts.entries) row(e.key,e.value.toString()),
        ],
        if(taxon.ecologicalScales.isNotEmpty)...[
          heading(context,'Scale ecologiche ITALIC'),
          for(final e in taxon.ecologicalScales.entries) row(e.key,_scaleValue(e.value)),
        ],
        const SizedBox(height:18),
        const Text('I dati assenti in ITALIC restano vuoti: italicapp non li stima.'),
      ]),
    )),
  );

  String _scaleValue(dynamic v) {
    if(v is Map) {
      final min=v['min'], max=v['max'];
      if(min!=null && max!=null) return min==max?'$min':'$min–$max';
    }
    return v.toString();
  }

  Widget heading(BuildContext c,String t)=>Padding(
    padding:const EdgeInsets.only(top:14,bottom:8),
    child:Text(t,style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w800)));
  Widget block(BuildContext c,String t,String v)=>Card(child:Padding(
    padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(t,style:Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w700)),
      const SizedBox(height:8),SelectableText(v),
    ])));
  Widget blockMaybe(BuildContext c,String t,String? v)=>
    v==null||v.trim().isEmpty?const SizedBox.shrink():block(c,t,v);
  Widget row(String k, String v) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          SelectableText(v),
        ],
      ),
    ),
  );
}
