#!/usr/bin/env bash
#
# initRepot — initialise le repo git local + crée le repo GitHub privé + push
# =============================================================================
# Déposé à la racine d'un projet par `initProject`. Lancé depuis ce dossier,
# il prend en charge la création du repo GitHub et le premier push.
#
# Comportement :
#   - confirme le profil gh actif (option de basculer via login web)
#   - nom du repo GitHub = nom du dossier courant
#   - owner = compte gh actuellement authentifié (après confirmation)
#   - git init -b main si le dossier n'est pas encore un repo git
#   - git add -A  (exclut ce script du commit initial via `git rm --cached`)
#   - git commit -m "init"  (skip s'il n'y a rien à committer)
#   - gh repo create OWNER/NAME --private --source=. --remote=origin --push
#   - si tout s'est bien passé : suppression de ce script (mission accomplie)
#
# Usage : ./initRepot.sh         (depuis la racine du projet)
# Dépendances : git, gh
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

step() { printf "\n${BOLD}${GREEN}==> %s${NC}\n" "$*"; }
info() { printf "${BLUE}%s${NC}\n" "$*"; }
warn() { printf "${YELLOW}%s${NC}\n" "$*"; }
err()  { printf "${RED}%s${NC}\n" "$*" >&2; }

# Prompt oui/non avec valeur par défaut (mêmes conventions que initProject).
confirm() {
  local question="$1" default="${2:-n}" hint answer
  if [ "$default" = "y" ] || [ "$default" = "o" ]; then
    hint="[O/n]"
  else
    hint="[o/N]"
  fi
  while true; do
    read -r -p "$(printf "${BLUE}%s${NC} %s " "$question" "$hint")" answer
    answer="${answer:-$default}"
    case "$answer" in
      y|Y|yes|YES|o|O|oui|OUI) return 0 ;;
      n|N|no|NO|non|NON)       return 1 ;;
      *) warn "Réponds par o/n." ;;
    esac
  done
}

# Chemin de CE script (pour l'exclure du commit + l'autodétruire à la fin).
SELF_PATH="${BASH_SOURCE[0]}"
SELF_NAME="$(basename "$SELF_PATH")"

# -----------------------------------------------------------------------------
# 1. Vérification des dépendances
# -----------------------------------------------------------------------------
command -v git >/dev/null 2>&1 || { err "git introuvable."; exit 1; }
command -v gh  >/dev/null 2>&1 || { err "gh (GitHub CLI) introuvable."; exit 1; }

# -----------------------------------------------------------------------------
# 2. Profil GitHub : vérifie l'auth, propose de conserver ou de basculer
# -----------------------------------------------------------------------------
step "Profil GitHub"

# Cas 1 : pas du tout authentifié → propose le login web
if ! gh auth status >/dev/null 2>&1; then
  warn "Pas connecté à GitHub CLI."
  if confirm "Lancer 'gh auth login --web' maintenant ?" y; then
    gh auth login --web
  else
    err "Abandon."
    exit 1
  fi
fi

# Cas 2 : un compte est actif → affiche-le, propose de basculer
GH_USER=$(gh api user --jq .login)
info "Profil actif : $GH_USER"

if ! confirm "Conserver ce profil ?" y; then
  info "Connexion via navigateur..."
  gh auth login --web
  GH_USER=$(gh api user --jq .login)
  info "Nouveau profil actif : $GH_USER"
fi

# -----------------------------------------------------------------------------
# 3. Contexte : nom du dossier + repo cible
# -----------------------------------------------------------------------------
FOLDER_NAME="$(basename "$PWD")"
FULL_REPO="${GH_USER}/${FOLDER_NAME}"

step "Initialisation du repo ${FULL_REPO}"

# Abort si le repo GitHub existe déjà — on ne veut pas écraser un repo existant
# ni pousser dessus par accident.
if gh repo view "$FULL_REPO" >/dev/null 2>&1; then
  err "Le repo ${FULL_REPO} existe déjà sur GitHub. Abort."
  exit 1
fi

# -----------------------------------------------------------------------------
# 4. git init si nécessaire
# -----------------------------------------------------------------------------
if [ ! -d .git ]; then
  info "git init -b main"
  git init -q -b main
else
  info "Repo git déjà initialisé."
fi

# -----------------------------------------------------------------------------
# 5. Garantit user.name / user.email (sinon git commit explose)
# -----------------------------------------------------------------------------
if ! git config user.name >/dev/null 2>&1; then
  n=$(git config --global user.name 2>/dev/null || echo "$GH_USER")
  git config user.name "$n"
fi
if ! git config user.email >/dev/null 2>&1; then
  e=$(git config --global user.email 2>/dev/null || echo "${GH_USER}@users.noreply.github.com")
  git config user.email "$e"
fi

# -----------------------------------------------------------------------------
# 6. add + commit "init" — on EXCLUT ce script du commit initial.
#    `git rm --cached` retire le fichier de l'index (sans toucher au disque) ;
#    le `|| true` couvre le cas où le fichier n'a pas été staged (rare, mais
#    set -e nous mordrait).
# -----------------------------------------------------------------------------
git add -A
git rm --cached --quiet -- "$SELF_NAME" 2>/dev/null || true

if git diff --cached --quiet; then
  warn "Rien à committer (ou déjà committé)."
else
  git commit -q -m "init"
  info "Commit 'init' créé."
fi

# -----------------------------------------------------------------------------
# 7. Création du repo privé + remote + push (en une commande)
# -----------------------------------------------------------------------------
info "Création du repo privé ${FULL_REPO} + ajout du remote 'origin' + push"
gh repo create "$FULL_REPO" --private --source=. --remote=origin --push

# -----------------------------------------------------------------------------
# 8. Succès → autodestruction du script (mission accomplie).
#    À ce point, `set -e` garantit qu'on n'est ici que si tout ce qui précède
#    a réussi. Le script n'est pas dans l'index (cf. étape 6), il n'y a donc
#    rien à `git rm` — un simple `rm` suffit.
# -----------------------------------------------------------------------------
rm -- "$SELF_PATH"
info "Script ${SELF_NAME} supprimé (mission accomplie)."

step "✓ Repo ${FULL_REPO} créé et code poussé sur GitHub."
info "URL : https://github.com/${FULL_REPO}"
