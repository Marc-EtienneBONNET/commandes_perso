# commandes_perso

Mes commandes shell personnelles. Une commande = un sous-dossier avec un point d'entrée `.sh`. L'installeur `init.sh` les copie dans `~/.commandes_perso/`, crée des symlinks dans `~/.local/bin/` (préfixés `-` pour les distinguer des commandes natives), et ajoute `~/.local/bin` au `PATH` via `~/.zshrc`.

---

## Sommaire

1. [Installation](#installation)
2. [Utilisation](#utilisation)
3. [Structure du repo](#structure-du-repo)
4. [Commandes disponibles](#commandes-disponibles)
5. [Ajouter une nouvelle commande](#ajouter-une-nouvelle-commande)
6. [Mise à jour](#mise-à-jour)
7. [Désinstallation](#désinstallation)
8. [Comment ça marche en interne](#comment-ça-marche-en-interne)

---

## Installation

```bash
# 1. Clone le repo (n'importe où — il sert juste à porter le code)
git clone git@github.com:Marc-EtienneBONNET/commandes_perso.git
cd commandes_perso

# 2. Lance l'installeur
./init.sh
```

L'installeur :
- détecte chaque commande définie comme sous-dossier `<nom>/<nom>.sh` ;
- copie son code dans `~/.commandes_perso/<nom>/` ;
- crée un symlink `~/.local/bin/-<nom>` → entry point ;
- ajoute (idempotent) `export PATH="$HOME/.local/bin:$PATH"` à `~/.zshrc` ;
- te propose en fin de course de **supprimer le repo local** (le repo GitHub n'est jamais touché).

Pour activer dans la session courante :

```bash
source ~/.zshrc
```

Ou ouvre simplement un nouveau terminal.

---

## Utilisation

Toutes les commandes sont préfixées par `-` pour les distinguer immédiatement des commandes natives (`ls`, `cd`, etc.) et des binaires installés par d'autres outils.

```bash
-initProject
-<autre-commande>
```

Le préfixe `-` est cohérent avec la convention utilisée pour les slash-commands Claude Code (`~/.claude/commands/-xxx.md`).

---

## Structure du repo

```
commandes_perso/
├── README.md                       ← ce fichier
├── init.sh                         ← installeur (à lancer après clone)
└── <nom>/                          ← une commande = un dossier
    ├── <nom>.sh                    ← entry point (OBLIGATOIRE)
    ├── lib/                        ← (optionnel) utilitaires sourcés
    │   └── *.sh
    ├── steps/                      ← (optionnel) étapes métier
    │   └── *.sh
    └── hooks/                      ← (optionnel) hooks à copier ailleurs
        └── *
```

**Règle stricte** : pour qu'une commande soit détectée par `init.sh`, le sous-dossier `<nom>/` doit contenir un fichier `<nom>.sh` (même nom, suffixe `.sh`). Sinon le dossier est ignoré.

---

## Commandes disponibles

### `-initProject`

Workflow d'initialisation d'un nouveau projet à partir de templates GitHub.

**Flux** :
1. Demande sur quel compte gh tu es connecté, propose de le conserver ou de basculer via login web.
2. Liste les repos marqués `isTemplate=true` sur ton profil.
3. Demande, pour chacun, si tu veux l'inclure.
4. Demande le nom du projet (`<suffixe>`), utilisé en préfixe des nouveaux repos et nom du dossier parent.
5. Calcule les nouveaux noms : strip `model[_-]?` du template puis préfixe `<suffixe>_`.
   Exemple : `model_node_express` + suffixe `door` → `door_node_express`.
6. Ouvre le Finder pour choisir où poser le projet, crée un dossier `<suffixe>/` à cet endroit.
7. Pour chaque template choisi : clone son contenu en local, strip `.git`, ajoute `.env*` au `.gitignore`, `git init -b main` + commit initial, pré-configure `origin` vers `USER/<nouveau_nom>` (le repo n'existe pas encore sur GitHub), installe un hook `pre-push`.
8. **Aucun repo n'est créé sur GitHub à ce stade**. Le hook `pre-push` se charge de créer le repo GitHub privé au moment du premier `git push`, avec le nom dérivé de l'URL d'origin.

Le code de cette commande est dans `initProject/` et est découpé en :
- `initProject.sh` — orchestrateur
- `lib/colors.sh` `lib/prompts.sh` `lib/checks.sh` — utilitaires
- `steps/01-...` à `steps/08-...` — une étape métier par fichier
- `hooks/pre-push` — hook copié dans chaque repo cloné

Voir les en-têtes des fichiers pour le détail (chaque step documente ce qu'il **consomme** et ce qu'il **produit**).

### `-endWork`

Pendant de `-startWork` : ferme les windows Cursor liées aux sous-repos du dossier courant.

**Flux** :
1. Scanne le dossier courant pour lister les sous-projets (mêmes exclusions que `-startWork` : `node_modules`, `dist`, `build`, `out`, `target`, `vendor`). Inclut aussi le cwd lui-même s'il porte un marker (`.git`, `package.json`, `docker-compose.yml`).
2. Lit `~/Library/Application Support/Cursor/User/globalStorage/storage.json` (champ `backupWorkspaces.folders`) pour connaître les folders actuellement ouverts dans Cursor.
3. Intersecte les deux listes → windows à fermer.
4. Affiche le récap et demande confirmation.
5. Pour chaque match, AppleScript via System Events : `AXRaise` la window dont le titre contient le basename du repo, puis envoie `Cmd+W`. Cursor garde la main sur le dialogue de sauvegarde des modifications non sauvegardées.
6. Relit `storage.json` pour signaler les windows qui n'auraient pas été fermées (dialogue en attente, ou state Cursor pas encore flush).

**Permissions requises** : macOS Accessibility pour le terminal hôte. Identique à `-startWork` — déjà accordé si tu utilises `-startWork`.

Le code est dans `endWork/endWork.sh` (script monolithique, ~200 lignes, pas de découpage en `lib/` / `steps/` nécessaire).

---

## Ajouter une nouvelle commande

1. Crée un sous-dossier `<nom>/` à la racine du repo.
2. Crée le fichier `<nom>/<nom>.sh` (entry point) avec un shebang `#!/usr/bin/env bash` et `chmod +x`.
3. Pour les commandes complexes, suis le pattern d'`initProject/` (`lib/`, `steps/`, etc.).
4. Relance `./init.sh` à la racine. La nouvelle commande sera détectée, installée, et accessible via `-<nom>`.

**Conventions** :
- Le `name` du dossier doit matcher exactement le `name` du `.sh` à l'intérieur.
- Préférer le découpage en `lib/` + `steps/` dès que l'entry point dépasse ~100 lignes (cf. `initProject/` comme référence).
- Documenter en en-tête de chaque `.sh` ce qu'il fait, consomme et produit (variables globales partagées entre étapes sourcées).

---

## Mise à jour

```bash
cd commandes_perso
git pull
./init.sh
```

`init.sh` est idempotent : il **remplace** les installs existantes (suppression puis recopie). Aucun risque de fichier résiduel d'une ancienne version d'une commande **donnée**.

> **Limite connue** : `init.sh` ne supprime PAS les commandes installées qui n'existent plus dans le repo source. Si tu retires un dossier `<nom>/` du repo et que tu fais `./init.sh`, l'install `~/.commandes_perso/<nom>` et le symlink `~/.local/bin/-<nom>` survivront. Supprime-les manuellement :
> ```bash
> rm -rf ~/.commandes_perso/<nom>
> rm -f ~/.local/bin/-<nom>
> ```

---

## Désinstallation

Pour tout retirer :

```bash
# 1. Supprime les installs et symlinks
rm -rf ~/.commandes_perso
rm -f ~/.local/bin/-*

# 2. Retire le bloc PATH ajouté à ~/.zshrc
# Cherche les marqueurs '# >>> commandes_perso (init.sh) >>>' et
# '# <<< commandes_perso (init.sh) <<<' et supprime tout entre les deux.
```

(Avec `sed` :)
```bash
sed -i.bak '/# >>> commandes_perso (init\.sh) >>>/,/# <<< commandes_perso (init\.sh) <<</d' ~/.zshrc
```

---

## Comment ça marche en interne

### Pourquoi un dossier d'install séparé du repo ?

`~/.commandes_perso/` héberge le code **exécuté** par les symlinks. Le repo source n'a pas besoin de rester sur la machine après install : l'installeur propose même de le supprimer en fin de course. Du coup :

- Le code des commandes vit dans `~/.commandes_perso/` (stable, à jour).
- Le repo source ne sert qu'à porter les sources pour `init.sh`. On le re-clone si besoin de mettre à jour.

### Pourquoi un symlink dans `~/.local/bin/` plutôt qu'ajouter `~/.commandes_perso/` au PATH ?

Mettre `~/.commandes_perso/` au PATH ne suffirait pas : on aurait à invoquer `<nom>/<nom>.sh` (chemin imbriqué). Le symlink `~/.local/bin/-<nom>` pointe directement sur l'entry point et offre un nom court (`-<nom>`).

`~/.local/bin/` est un choix XDG-friendly, souvent déjà dans le PATH des distros modernes. `init.sh` l'ajoute via `~/.zshrc` au cas où.

### Pourquoi le préfixe `-` ?

- **Distinction visuelle** : impossible de confondre `-initProject` avec une commande native (`ls`, `git`, `gh`, etc.).
- **Cohérence avec Claude Code** : les slash-commands perso utilisent déjà ce préfixe (`~/.claude/commands/-xxx.md`).
- **Aucun risque de collision** : ~aucune commande native ne commence par `-`.

### Pourquoi un bloc avec marqueurs dans `~/.zshrc` ?

Les marqueurs `# >>> commandes_perso (init.sh) >>>` / `# <<< commandes_perso (init.sh) <<<` permettent :
- de détecter si le bloc est déjà présent → idempotence du script ;
- de retirer proprement la modif lors d'une désinstallation (un seul `sed` cible le bloc complet).
