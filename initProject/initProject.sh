#!/usr/bin/env bash
#
# initProject.sh — point d'entrée
# =============================================================================
# Workflow d'initialisation d'un nouveau projet à partir de tes templates GitHub.
#
# Approche : copie locale d'abord, création GitHub différée.
#   - le script ne crée AUCUN repo sur GitHub.
#   - chaque dossier local reçoit son contenu de template + un script
#     `initRepot.sh` à la racine.
#   - quand l'utilisateur est prêt, il lance `./initRepot.sh` depuis le
#     dossier : git init + add + commit "init" + gh repo create (privé) + push.
#   - un dossier `.claude/rules/` est aussi déposé à la racine du dossier
#     parent pour aiguiller Claude vers les `.claude/` de chaque sous-projet.
#
# Organisation :
#   initProject.sh          → ce fichier (orchestrateur)
#   lib/colors.sh           → couleurs + helpers d'affichage (step/info/...)
#   lib/prompts.sh          → confirm() + sanitize_name()
#   lib/checks.sh           → vérification des dépendances (git, gh, osascript)
#   steps/01..08-*.sh       → une étape métier par fichier
#   templates/initRepot.sh  → script copié à la racine de chaque dossier projet
#
# Usage : ./initProject.sh
# Dépendances : git, gh (GitHub CLI), osascript (macOS), bash 3.2+
# =============================================================================

set -euo pipefail

# Localise le dossier dans lequel vit ce script (résout les symlinks).
# Permet d'invoquer initProject.sh depuis n'importe où sans casser les `source`,
# y compris via un symlink (ex. ~/.local/bin/-initProject → ~/.commandes_perso/...).
# macOS n'a pas `readlink -f`, donc on déroule la chaîne de symlinks à la main.
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
export SCRIPT_DIR

# -----------------------------------------------------------------------------
# Chargement des utilitaires (lib/)
# -----------------------------------------------------------------------------
. "$SCRIPT_DIR/lib/colors.sh"
. "$SCRIPT_DIR/lib/prompts.sh"
. "$SCRIPT_DIR/lib/checks.sh"

# -----------------------------------------------------------------------------
# Chargement des étapes (steps/) — chaque fichier définit une fonction
# -----------------------------------------------------------------------------
. "$SCRIPT_DIR/steps/01-check-profile.sh"
. "$SCRIPT_DIR/steps/02-list-templates.sh"
. "$SCRIPT_DIR/steps/03-select-templates.sh"
. "$SCRIPT_DIR/steps/04-ask-project-name.sh"
. "$SCRIPT_DIR/steps/05-compute-new-names.sh"
. "$SCRIPT_DIR/steps/06-pick-destination.sh"
. "$SCRIPT_DIR/steps/07-init-each-repo.sh"
. "$SCRIPT_DIR/steps/08-recap.sh"

# -----------------------------------------------------------------------------
# Pré-flight : git / gh / osascript présents ?
# -----------------------------------------------------------------------------
check_dependencies

# -----------------------------------------------------------------------------
# Workflow — chaque fonction est dans son propre fichier (steps/).
# Le commentaire à droite indique ce que chaque étape PRODUIT
# (variables globales lues par les étapes suivantes).
# -----------------------------------------------------------------------------
check_profile          # → CURRENT_USER
list_templates         # → TEMPLATES[]
select_templates       # → SELECTED[]
ask_project_name       # → SUFFIX
compute_new_names      # → NEW_NAMES[]
pick_destination       # → PARENT_DIR
init_each_repo         # → INITIALIZED[], SKIPPED[], FAILED[]
print_recap
