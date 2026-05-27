#!/usr/bin/env bash
#
# startWork — démarre une session de travail multi-repos
# =============================================================================
# Scanne le dossier courant à la recherche de sous-projets, ouvre une window
# Cursor par sous-projet détecté, puis lance Claude Code à l'endroit courant.
#
# Pensé pour le workflow `-initProject` : après avoir initialisé plusieurs
# sous-repos dans un dossier parent, `-startWork` ouvre toute la stack en un
# coup et te dépose dans une session Claude prête à dispatcher.
#
# Comportement :
#   1. localise un binaire Cursor utilisable (PATH ou /Applications)
#   2. liste les sous-dossiers à profondeur 1 (en excluant le bruit usuel :
#      .git, .claude, node_modules, dist, build)
#   3. demande confirmation avant d'ouvrir N windows
#   4. ouvre une window Cursor par sous-projet (--new-window)
#   5. exec claude à l'endroit courant
#
# Usage : -startWork                 (depuis le dossier parent à scanner)
# Dépendances : cursor (CLI ou /Applications/Cursor.app), claude
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

# -----------------------------------------------------------------------------
# 1. Localise un binaire Cursor utilisable
# -----------------------------------------------------------------------------
# Préférence : CLI 'cursor' dans le PATH (installé via "Shell Command: Install
# 'cursor' command" depuis Cursor). Fallback : binaire embarqué dans
# Cursor.app sur macOS.
CURSOR_BIN=""
if command -v cursor >/dev/null 2>&1; then
  CURSOR_BIN="cursor"
elif [ -x "/Applications/Cursor.app/Contents/Resources/app/bin/cursor" ]; then
  CURSOR_BIN="/Applications/Cursor.app/Contents/Resources/app/bin/cursor"
else
  err "CLI 'cursor' introuvable (ni dans PATH, ni dans /Applications/Cursor.app)."
  err "Installe-le depuis Cursor : Cmd+Shift+P → \"Shell Command: Install 'cursor' command\"."
  exit 1
fi

command -v claude >/dev/null 2>&1 || {
  err "CLI 'claude' introuvable dans le PATH."
  exit 1
}

# -----------------------------------------------------------------------------
# 2. Scan du dossier courant — sous-dossiers à profondeur 1, hors bruit usuel.
#    Le glob `*/` ignore déjà les dossiers cachés (`.git`, `.claude`, etc.) ;
#    le case ci-dessous attrape les noms non cachés à exclure.
# -----------------------------------------------------------------------------
step "Scan de $(pwd)"

PROJECTS=()
for d in */; do
  [ -d "$d" ] || continue
  name="${d%/}"
  case "$name" in
    node_modules|dist|build|out|target|vendor) continue ;;
  esac
  PROJECTS+=("$name")
done

if [ "${#PROJECTS[@]}" -eq 0 ]; then
  warn "Aucun sous-projet détecté à $(pwd)."
else
  info "Sous-projets détectés (${#PROJECTS[@]}) :"
  for p in "${PROJECTS[@]}"; do
    echo "  - $p"
  done
fi

# -----------------------------------------------------------------------------
# 3. Confirmation — évite d'ouvrir 50 windows par accident si on lance la
#    commande dans un dossier trop large.
# -----------------------------------------------------------------------------
if [ "${#PROJECTS[@]}" -gt 0 ]; then
  echo
  if ! confirm "Ouvrir ${#PROJECTS[@]} window(s) Cursor + Claude Code ici ?" y; then
    err "Abandon."
    exit 1
  fi
fi

# -----------------------------------------------------------------------------
# 4. Une window Cursor par sous-projet
# -----------------------------------------------------------------------------
# `--new-window` force une window dédiée par appel (sinon Cursor réutilise
# la dernière active et on perd la séparation visuelle).
# -----------------------------------------------------------------------------
if [ "${#PROJECTS[@]}" -gt 0 ]; then
  step "Ouverture des windows Cursor"
  for p in "${PROJECTS[@]}"; do
    printf "  %s ... " "$p"
    "$CURSOR_BIN" --new-window "$PWD/$p" >/dev/null 2>&1
    printf "${GREEN}OK${NC}\n"
  done
fi

# -----------------------------------------------------------------------------
# 5. Claude Code à l'endroit courant
# -----------------------------------------------------------------------------
# `exec` remplace ce bash par claude → pas de processus parent inutile, et la
# session interactive prend la main proprement sur le TTY courant.
# -----------------------------------------------------------------------------
step "Lancement de Claude Code dans $(pwd)"
exec claude
