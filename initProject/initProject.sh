#!/usr/bin/env bash
#
# initProject.sh — point d'entrée
# =============================================================================
# Workflow d'initialisation d'un nouveau projet à partir de tes templates GitHub.
#
# Approche : copie locale d'abord, création GitHub différée.
#   - le script ne crée AUCUN repo sur GitHub.
#   - chaque dossier local obtient un git init propre + un hook pre-push.
#   - au premier `git push`, le hook crée le repo GitHub privé à la volée
#     (avec le nom du dossier).
#
# Organisation :
#   initProject.sh          → ce fichier (orchestrateur)
#   lib/colors.sh           → couleurs + helpers d'affichage (step/info/...)
#   lib/prompts.sh          → confirm() + sanitize_name()
#   lib/checks.sh           → vérification des dépendances (git, gh, osascript)
#   steps/01..08-*.sh       → une étape métier par fichier
#   hooks/pre-push          → hook copié dans chaque repo cloné
#
# Usage : ./initProject.sh
# Dépendances : git, gh (GitHub CLI), osascript (macOS), bash 3.2+
# =============================================================================

set -euo pipefail

# Localise le dossier dans lequel vit ce script (résout les symlinks).
# Permet d'invoquer initProject.sh depuis n'importe où sans casser les `source`.
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
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
pick_destination       # → PARENT_DIR, GH_PROTO
init_each_repo         # → INITIALIZED[], SKIPPED[], FAILED[]
print_recap
