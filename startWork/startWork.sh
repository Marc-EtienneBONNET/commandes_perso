#!/usr/bin/env bash
#
# startWork — démarre une session de travail multi-repos
# =============================================================================
# Scanne le dossier courant à la recherche de sous-projets, ouvre une window
# Cursor par sous-projet détecté + une window Terminal `claude agents`, et
# bascule chaque window en fullscreen — ce qui sur macOS la place dans son
# propre Space (bureau dédié).
#
# Pensé pour le workflow `-initProject` : après avoir initialisé plusieurs
# sous-repos dans un dossier parent, `-startWork` ouvre toute la stack en un
# coup, chaque app sur son propre bureau, prête à dispatcher.
#
# Comportement :
#   1. localise un binaire Cursor utilisable (PATH ou /Applications)
#   2. liste les sous-dossiers à profondeur 1 (en excluant le bruit usuel :
#      node_modules, dist, build, out, target, vendor)
#   3. demande confirmation avant d'ouvrir N windows
#   4. ouvre une window Cursor par sous-projet + fullscreen (→ nouveau Space)
#   5. ouvre une window terminal (iTerm si détecté, sinon Terminal) avec
#      `cd $PWD && claude agents` + fullscreen (→ nouveau Space)
#
# Permissions requises (one-shot, demandé au 1er run) :
#   - macOS Accessibility pour le terminal d'où -startWork est lancé.
#     System Settings → Privacy → Accessibility → coche Terminal/iTerm.
#     Sans ça, les windows s'ouvrent mais ne passent pas en fullscreen.
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
# 4. Une window Cursor par sous-projet + passage en fullscreen
# -----------------------------------------------------------------------------
# `--new-window` force une window dédiée par appel (sinon Cursor réutilise
# la dernière active).
#
# Fullscreen via AXFullScreen sur la window frontmost : macOS bascule alors
# cette window dans son propre Space. La séquence est :
#   - cursor --new-window  (ouvre la window, la rend frontmost)
#   - sleep                 (laisser le temps à la window d'apparaître)
#   - System Events → set AXFullScreen true sur window 1 du process Cursor
#
# Si l'Accessibility n'est pas accordée, l'AppleScript échoue : on continue
# avec un warn, la window reste juste en taille normale.
# -----------------------------------------------------------------------------
fullscreen_front_window() {
  # $1 = nom du process tel que vu par System Events (ex. "Cursor", "Terminal")
  local app="$1"
  osascript <<APPLESCRIPT 2>/dev/null || return 1
tell application "System Events"
  tell process "$app"
    set frontmost to true
    delay 0.2
    tell window 1
      set value of attribute "AXFullScreen" to true
    end tell
  end tell
end tell
APPLESCRIPT
}

if [ "${#PROJECTS[@]}" -gt 0 ]; then
  step "Ouverture des windows Cursor (fullscreen → nouveau Space chacune)"
  for p in "${PROJECTS[@]}"; do
    printf "  %s ... " "$p"
    "$CURSOR_BIN" --new-window "$PWD/$p" >/dev/null 2>&1
    sleep 1.5
    if fullscreen_front_window "Cursor"; then
      printf "${GREEN}OK${NC}\n"
    else
      printf "${YELLOW}OK (fullscreen KO — Accessibility ?)${NC}\n"
    fi
  done
fi

# -----------------------------------------------------------------------------
# 5. `claude agents` dans un terminal séparé + fullscreen (→ nouveau Space)
# -----------------------------------------------------------------------------
# Ouvre une NOUVELLE window terminal positionnée sur $PWD, y lance
# `claude agents`, puis bascule cette window en fullscreen (Space dédié).
#
# Détection : si on tourne dans iTerm (TERM_PROGRAM=iTerm.app), on cible iTerm
# (process "iTerm2" pour System Events) ; sinon fallback sur Terminal.app.
#
# Échappement : $PWD est entouré de guillemets dans le `cd` final → supporte
# les espaces. Caveat : un `"` littéral dans $PWD casserait l'AppleScript
# (improbable mais à connaître).
# -----------------------------------------------------------------------------
step "Ouverture de 'claude agents' dans un terminal séparé ($(pwd))"

term_proc=""
case "${TERM_PROGRAM:-}" in
  iTerm.app)
    osascript <<APPLESCRIPT
tell application "iTerm"
  activate
  create window with default profile
  tell current session of current window
    write text "cd \"$PWD\" && claude agents"
  end tell
end tell
APPLESCRIPT
    term_proc="iTerm2"
    ;;
  *)
    osascript <<APPLESCRIPT
tell application "Terminal"
  activate
  do script "cd \"$PWD\" && claude agents"
end tell
APPLESCRIPT
    term_proc="Terminal"
    ;;
esac

sleep 0.8
if fullscreen_front_window "$term_proc"; then
  info "Terminal séparé ouvert (fullscreen, nouveau Space)."
else
  warn "Terminal ouvert mais fullscreen KO (Accessibility manquante ?)."
fi
