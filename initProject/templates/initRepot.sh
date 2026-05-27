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
#   - résout l'alias SSH (~/.ssh/config) correspondant au profil gh actif —
#     indispensable pour les setups multi-comptes (clé pro vs clé perso) où
#     `gh repo create` ajoute toujours un remote `git@github.com:…` qui pointe
#     vers la clé par défaut, donc échoue à pusher sur un compte secondaire
#   - git init -b main si le dossier n'est pas encore un repo git
#   - git add -A  (exclut ce script du commit initial via `git rm --cached`)
#   - git commit -m "init"  (skip s'il n'y a rien à committer)
#   - gh repo create OWNER/NAME --private (sans push)
#   - git remote add origin git@<alias_ssh>:OWNER/NAME.git
#   - git push -u origin main, avec retry exponentiel pour absorber le délai
#     de propagation côté GitHub (l'API renvoie 200 avant que le serveur git
#     n'expose le nouveau repo, d'où des "Repository not found" transitoires)
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
# 3. Résolution du host SSH correspondant au profil gh actif
#
#    Setup typique : plusieurs comptes GitHub avec des clés SSH distinctes
#    déclarés via des alias dans ~/.ssh/config :
#      Host github.com         → compte par défaut (clé X)
#      Host github.com-perso   → compte perso (clé Y)
#
#    Par défaut `gh repo create … --push` ajoute `git@github.com:OWNER/NAME`
#    sans tenir compte de quelle clé peut accéder à OWNER. Si OWNER n'est PAS
#    le compte associé à la clé par défaut, le push échoue avec
#    « Repository not found ».
#
#    On résout en interrogeant chaque Host github.com* du ssh config via
#    `ssh -T` : GitHub répond « Hi USERNAME! » et on garde l'alias dont le
#    USERNAME matche le profil gh actif. Fallback : `github.com` brut.
# -----------------------------------------------------------------------------
resolve_ssh_host() {
  local target_user="$1"
  local ssh_config="$HOME/.ssh/config"

  if [ ! -f "$ssh_config" ]; then
    printf 'github.com'
    return
  fi

  # Tous les Host candidats : `github.com` et alias `github.com-*`.
  local hosts
  hosts=$(awk '/^[[:space:]]*Host[[:space:]]+/ {
    for (i=2; i<=NF; i++) if ($i ~ /^github\.com(-|$)/) print $i
  }' "$ssh_config" | awk '!seen[$0]++')

  local host out user
  while IFS= read -r host; do
    [ -z "$host" ] && continue
    # `-n` ferme stdin de ssh — sans ça, il consomme le heredoc `<<<` qui
    # alimente le `while read` et la boucle s'arrête après le 1er host.
    out=$(ssh -n -T -o BatchMode=yes -o ConnectTimeout=5 \
              -o StrictHostKeyChecking=accept-new \
              "git@${host}" 2>&1 || true)
    user=$(printf '%s' "$out" | sed -n 's/^Hi \([^!]*\)!.*/\1/p')
    if [ "$user" = "$target_user" ]; then
      printf '%s' "$host"
      return
    fi
  done <<< "$hosts"

  printf 'github.com'
}

info "Résolution de l'alias SSH pour ${GH_USER}..."
SSH_HOST=$(resolve_ssh_host "$GH_USER")
info "Alias SSH retenu : ${SSH_HOST}"

# -----------------------------------------------------------------------------
# 4. Contexte : nom du dossier + repo cible
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
# 5. git init si nécessaire
# -----------------------------------------------------------------------------
if [ ! -d .git ]; then
  info "git init -b main"
  git init -q -b main
else
  info "Repo git déjà initialisé."
fi

# -----------------------------------------------------------------------------
# 6. Identité git LOCALE alignée sur le profil gh choisi.
#
#    Sans ça, `git commit` retomberait sur la config globale (souvent celle
#    du compte par défaut / pro), et un repo perso finirait par contenir des
#    commits signés à la mauvaise identité.
#
#    `gh api user` donne `.name`, `.email` (peut être null si privé), `.id`.
#    Si l'email est privé → on retombe sur l'adresse noreply officielle :
#    `<id>+<login>@users.noreply.github.com`.
# -----------------------------------------------------------------------------
GH_NAME=$(gh api user --jq '.name // .login')
GH_EMAIL=$(gh api user --jq '.email')
if [ -z "$GH_EMAIL" ] || [ "$GH_EMAIL" = "null" ]; then
  GH_ID=$(gh api user --jq '.id')
  GH_EMAIL="${GH_ID}+${GH_USER}@users.noreply.github.com"
fi
git config user.name  "$GH_NAME"
git config user.email "$GH_EMAIL"
info "Identité git locale : ${GH_NAME} <${GH_EMAIL}>"

# -----------------------------------------------------------------------------
# 7. add + commit "init" — on EXCLUT ce script du commit initial.
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
# 8. Création du repo privé, puis remote SSH avec l'alias résolu, puis push.
#    On évite `gh repo create --source --remote --push` parce qu'il forcerait
#    `git@github.com:…` (alias par défaut), incompatible avec un compte
#    secondaire dont la clé SSH se trouve derrière un autre Host.
# -----------------------------------------------------------------------------
info "Création du repo privé ${FULL_REPO}"
gh repo create "$FULL_REPO" --private

REMOTE_URL="git@${SSH_HOST}:${FULL_REPO}.git"
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE_URL"
else
  git remote add origin "$REMOTE_URL"
fi
info "Remote 'origin' → ${REMOTE_URL}"

# -----------------------------------------------------------------------------
# 9. Push initial avec retry — GitHub a souvent un délai entre la réponse 200
#    de l'API `gh repo create` et la disponibilité du repo côté serveur git.
#    Pendant cette fenêtre (1–10 s en général), le push échoue avec
#    « Repository not found ». On retry avec un backoff doux plutôt que de
#    laisser tomber sur la première tentative.
# -----------------------------------------------------------------------------
push_with_retry() {
  local delays=(2 3 5 8 12)
  local out

  # Première tentative immédiate (souvent ça passe).
  if out=$(git push -u origin main 2>&1); then
    printf '%s\n' "$out"
    return 0
  fi

  warn "Push refusé au premier essai (propagation GitHub en cours ?)."
  local delay
  for delay in "${delays[@]}"; do
    info "Retry dans ${delay}s..."
    sleep "$delay"
    if out=$(git push -u origin main 2>&1); then
      printf '%s\n' "$out"
      return 0
    fi
  done

  err "Push toujours refusé après plusieurs tentatives :"
  printf '%s\n' "$out" >&2
  return 1
}

info "Push initial sur main"
push_with_retry

# -----------------------------------------------------------------------------
# 10. Succès → autodestruction du script (mission accomplie).
#     À ce point, `set -e` garantit qu'on n'est ici que si tout ce qui précède
#     a réussi. Le script n'est pas dans l'index (cf. étape 7), il n'y a donc
#     rien à `git rm` — un simple `rm` suffit.
# -----------------------------------------------------------------------------
rm -- "$SELF_PATH"
info "Script ${SELF_NAME} supprimé (mission accomplie)."

step "✓ Repo ${FULL_REPO} créé et code poussé sur GitHub."
info "URL : https://github.com/${FULL_REPO}"
