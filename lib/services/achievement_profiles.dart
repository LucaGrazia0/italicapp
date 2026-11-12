class AchievementSource {
  const AchievementSource(this.title, this.url);
  final String title, url;
}

class AchievementProfile {
  const AchievementProfile({
    required this.name,
    required this.dates,
    required this.material,
    required this.biography,
    required this.sources,
  });
  final String name, dates, material, biography;
  final List<AchievementSource> sources;
}

const _history = AchievementSource(
  'ITALIC · Breve storia della lichenologia in Italia',
  'https://italic.units.it/?procedure=base&t=140&c=141',
);

/// Short original summaries, checked against the linked sources on 2026-11-12.
/// Kept in the app so the profiles remain readable without a connection.
const achievementProfiles = <int, AchievementProfile>{
  1: AchievementProfile(
    name: 'Federico Cesi',
    dates: '1585–1630',
    material: 'Legno',
    biography:
        'Tra i pionieri dell’osservazione dei licheni, utilizzò il microscopio di Galileo. ITALIC gli attribuisce la prima chiara illustrazione dei soredi: uno sguardo nuovo su strutture piccolissime.',
    sources: [_history],
  ),
  10: AchievementProfile(
    name: 'Martino Anzi',
    dates: '1812–1881',
    material: 'Bronzo',
    biography:
        'Protagonista della lichenologia italiana dell’Ottocento, contribuì alla conoscenza floristica del territorio. La diffusione di campioni essiccati favorì lo studio e il confronto delle specie descritte.',
    sources: [_history],
  ),
  50: AchievementProfile(
    name: 'Abramo Bartolomeo Massalongo',
    dates: '1824–1860',
    material: 'Argento',
    biography:
        'Rinnovò la classificazione dei licheni valorizzando i caratteri microscopici, soprattutto quelli delle spore. I suoi studi contribuirono a riconoscere affinità nascoste dietro forme di crescita molto diverse.',
    sources: [_history],
  ),
  100: AchievementProfile(
    name: 'Maria Cengia Sambo',
    dates: '1888–1939',
    material: 'Oro',
    biography:
        'Insegnante e studiosa dei licheni, raccolse ampiamente nelle Alpi italiane. Nei suoi lavori trovano spazio osservazioni ecologiche, maturate anche fuori dai percorsi accademici dell’epoca.',
    sources: [_history],
  ),
  500: AchievementProfile(
    name: 'Erik Acharius',
    dates: '1757–1819',
    material: 'Platino',
    biography:
        'Lichenologo svedese, elaborò uno dei primi sistemi di classificazione dei licheni. Le sue opere, fondate principalmente sui caratteri macroscopici, segnarono una tappa fondamentale nello sviluppo della disciplina.',
    sources: [_history],
  ),
  1000: AchievementProfile(
    name: 'Pier Luigi Nimis',
    dates: 'Nato nel 1953',
    material: 'Diamante',
    biography:
        'Botanico dell’Università di Trieste, unisce lo studio dei licheni alla bioindicazione e all’informatica della biodiversità. La sua attività comprende strumenti digitali per identificare gli organismi e il sistema informativo ITALIC.',
    sources: [
      AchievementSource(
        'Università di Trieste · Profilo e attività scientifica',
        'https://dsv.units.it/it/ricerca/ambiti/gruppi/19610',
      ),
      AchievementSource(
        'Nimis e collaboratori · ITALIC 8.0, dati e riferimenti',
        'https://italic.units.it/index.php/?procedure=base&t=61&c=62',
      ),
    ],
  ),
};
