#!/usr/bin/env bash
#
# initRepot — initialise le repo git local + crée le repo GitHub privé + push
# =============================================================================
# Déposé à la racine d'un projet par `initProject`. Lancé depuis ce dossier,
# il prend en charge la création du repo GitHub et le premier push.
#
# Comportement :
#   - nom du repo GitHub = nom du dossier courant
#   - owner = compte gh actuellement authentifié
#   - git init -b main si le dossier n'est pas encore un repo git
#   - git add -A
#   - git commit -m "init"  (skip s'il n'y a rien à committer)
#   - gh repo create OWNER/NAME --private --source=. --remote=origin --push
#
# Usage : ./initRepot.sh         (depuis la racine du projet)
# Dépendances : git, gh (authentifié)
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

# -----------------------------------------------------------------------------
# 1. Vérification des dépendances
# -----------------------------------------------------------------------------
command -v git >/dev/null 2>&1 || { err "git introuvable."; exit 1; }
command -v gh  >/dev/null 2>&1 || { err "gh (GitHub CLI) introuvable."; exit 1; }
gh auth status >/dev/null 2>&1 || {
  err "gh non authentifié — lance 'gh auth login' d'abord."
  exit 1
}

# -----------------------------------------------------------------------------
# 2. Contexte : nom du dossier + owner
# -----------------------------------------------------------------------------
FOLDER_NAME="$(basename "$PWD")"
GH_USER="$(gh api user --jq .login)"
FULL_REPO="${GH_USER}/${FOLDER_NAME}"

step "Initialisation du repo ${FULL_REPO}"

# Abort si le repo GitHub existe déjà — on ne veut pas écraser un repo existant
# ni pousser dessus par accident.
if gh repo view "$FULL_REPO" >/dev/null 2>&1; then
  err "Le repo ${FULL_REPO} existe déjà sur GitHub. Abort."
  exit 1
fi

# -----------------------------------------------------------------------------
# 3. git init si nécessaire
# -----------------------------------------------------------------------------
if [ ! -d .git ]; then
  info "git init -b main"
  git init -q -b main
else
  info "Repo git déjà initialisé."
fi

# -----------------------------------------------------------------------------
# 4. Garantit user.name / user.email (sinon git commit explose)
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
# 5. add + commit "init"
# -----------------------------------------------------------------------------
git add -A
if git diff --cached --quiet; then
  warn "Rien à committer (ou déjà committé)."
else
  git commit -q -m "init"
  info "Commit 'init' créé."
fi

# -----------------------------------------------------------------------------
# 6. Création du repo privé + remote + push (en une commande)
# -----------------------------------------------------------------------------
info "Création du repo privé ${FULL_REPO} + ajout du remote 'origin' + push"
gh repo create "$FULL_REPO" --private --source=. --remote=origin --push

step "✓ Repo ${FULL_REPO} créé et code poussé sur GitHub."
info "URL : https://github.com/${FULL_REPO}"
