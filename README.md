# MacThermalWatch

Prototype CLI local pour comprendre **quand** un Mac chauffe, **si macOS limite le
CPU**, et **quel processus** reste anormalement gourmand.

Développé par **Richard BATHIEBO**.

L'outil ne tente pas de désactiver le bridage thermique : ce bridage protège le
processeur, la batterie et la carte mère. Il observe, alerte et conserve les
incidents utiles au diagnostic.

## Ce que le prototype mesure

- l'état thermique officiel de macOS : `nominal`, `fair`, `serious`, `critical` ;
- sur les Mac Intel compatibles, `CPU_Speed_Limit`, `CPU_Scheduler_Limit` et le
  nombre de CPU disponibles via `pmset` ;
- les processus qui consomment le plus de CPU et de mémoire ;
- la charge système sur 1, 5 et 15 minutes ;
- un processus qui dépasse le seuil CPU pendant plusieurs mesures consécutives.

Les incidents sont écrits localement, par défaut dans :

```text
~/Library/Logs/MacThermalWatch/events.jsonl
```

Aucune donnée n'est envoyée sur Internet et aucune application n'est fermée.

## Application graphique — recommandé

L'interface native présente l'état de la machine en langage simple, l'évolution
de la vitesse CPU, les applications les plus actives, les incidents récents et
une recommandation adaptée à la situation.

Après avoir cloné le dépôt, construire l'application cliquable :

```bash
cd mac-thermal-watch
./scripts/build-app.sh
open dist/MacThermalWatch.app
```

La compilation se fait directement sur le Mac : le bon binaire est donc produit
automatiquement, que la machine utilise un processeur Intel ou Apple Silicon.
Une fois construite, `MacThermalWatch.app` peut être déplacée dans le dossier
`Applications` et ouverte sans repasser par le Terminal.

L'application :

- démarre automatiquement la surveillance à son ouverture ;
- affiche un statut global **normal**, **attention** ou **danger** ;
- explique les mesures sans demander de connaissances techniques ;
- montre la vitesse CPU, le planificateur, la charge et les processus actifs ;
- permet de quitter proprement une application utilisateur trop lourde après
  confirmation, avec une fermeture forcée séparée et explicitement signalée ;
- propose un assistant « Réduire la charge » qui suit la récupération du CPU ;
- protège les processus système, qui ne peuvent jamais être fermés depuis l'app ;
- conserve les incidents dans le même journal JSONL que la CLI ;
- ne désactive aucune protection et ne ferme aucun programme automatiquement.

## Utiliser la version en ligne de commande

Il faut macOS 12 ou plus récent et les outils de ligne de commande Apple. Après
avoir cloné le dépôt :

```bash
cd mac-thermal-watch
swift run -c release macthermalwatch --once
```

Pour surveiller en continu avec une notification lors d'un incident :

```bash
swift run -c release macthermalwatch --notify --interval 5
```

Arrêter avec `Control-C`.

Si `swift` n'est pas installé :

```bash
xcode-select --install
```

Le premier lancement compile le programme. Les suivants peuvent utiliser le
binaire directement :

```bash
.build/release/macthermalwatch --notify
```

## Lire le résultat

Exemple :

```text
Thermique: SERIOUS | vitesse CPU: 58% | ordonnanceur: 72% | CPU disponibles: 6/8
⚠️ Vitesse CPU limitée à 58% — Une limitation thermique ou énergétique est active.
⚠️ Processus durablement gourmand — ExampleApp (PID 123) utilise 97.5% CPU depuis 3 mesures.
```

Un processus peut dépasser 100 % sur une machine multicœur. Le seuil par défaut
de 80 % est donc volontairement sensible ; pour une application de rendu vidéo,
on peut utiliser par exemple `--cpu-threshold 150`.

## Protocole de test conseillé

1. Lancer l'outil pendant cinq minutes sans application lourde.
2. Reproduire le ralentissement habituel pendant dix à quinze minutes.
3. Noter l'heure exacte où le Mac devient lent ou le ventilateur très audible.
4. Copier la sortie du terminal et le fichier `events.jsonl`.
5. Comparer le processus en tête avec l'état thermique et les limites CPU.

Pour un test court sans créer de journal :

```bash
swift run macthermalwatch --once --no-log
```

Pour une sortie exploitable par un autre programme :

```bash
swift run macthermalwatch --json --no-log
```

## Vérifier le projet

```bash
swift test
swift build -c release
```

## Limites actuelles et suite logique

- `pmset -g therm` fournit surtout les indicateurs recherchés sur les Mac Intel ;
  sur certaines machines, ces champs peuvent être indisponibles.
- Un processus très gourmand n'est pas automatiquement un bug : un export vidéo
  ou une compilation peuvent légitimement saturer plusieurs cœurs.
- Les températures et vitesses de ventilateurs précises demandent des mécanismes
  privilégiés et moins stables. Une phase suivante pourra proposer un mode
  optionnel basé sur `powermetrics`, sans le rendre obligatoire.
- Après validation sur le MacBook 2019, le cœur Swift pourra être réutilisé dans
  une application de barre des menus avec historique, graphiques et boutons
  « Ouvrir Moniteur d'activité » / « Quitter l'application » confirmés par
  l'utilisateur.
