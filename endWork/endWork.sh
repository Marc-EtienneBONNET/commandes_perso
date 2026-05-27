#!/usr/bin/env bash
#
# endWork — termine une session de travail multi-repos
# =============================================================================
# Pendant de `-startWork` : scanne le dossier courant à la recherche des
# sous-projets ouverts dans Cursor, et ferme leurs windows une par une.
#
# Pensé pour clore proprement une session : si `-startWork` a ouvert N windows
# Cursor (une par sous-projet, chacune sur son propre Space en fullscreen),
# `-endWork` les referme toutes en un coup quand le travail est terminé.
#
# Comportement :
#   1. liste les sous-dossiers à profondeur 1 (mêmes exclusions que startWork :
#      node_modules, dist, build, out, target, vendor)
#   2. lit le state global de Cursor (storage.json) pour savoir quels folders
#      sont actuellement ouverts dans des windows
#   3. intersection des deux → liste finale des windows à fermer
#   4. affiche le récap et demande confirmation
#   5. ferme chaque window via AppleScript + Cmd+W : Cursor déclenche son
#      propre dialogue de sauvegarde s'il y a des modifications non
#      sauvegardées (c'est volontaire, on ne force pas la fermeture)
#
# Permissions requises (one-shot, demandé au 1er run) :
#   - macOS Accessibility pour le terminal d'où -endWork est lancé.
#     System Settings → Privacy → Accessibility → coche Terminal/iTerm.
#     Idem que -startWork, donc déjà accordé si tu utilises -startWork.
#
# Usage : -endWork                   (depuis le dossier parent à scanner)
# Dépendances : python3 (présent par défaut sur macOS), Cursor.app
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

# Prompt oui/non avec valeur par défaut (mêmes conventions que startWork).
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
# 0. Préchecks — storage Cursor + python3 (pour parser le JSON).
# -----------------------------------------------------------------------------
CURSOR_STORAGE="$HOME/Library/Application Support/Cursor/User/globalStorage/storage.json"
if [ ! -f "$CURSOR_STORAGE" ]; then
  err "storage.json introuvable : $CURSOR_STORAGE"
  err "Cursor n'a peut-être jamais été lancé sur ce Mac."
  exit 1
fi

command -v python3 >/dev/null 2>&1 || {
  err "python3 introuvable — requis pour parser storage.json."
  exit 1
}

# -----------------------------------------------------------------------------
# 1. Scan du dossier courant — mêmes règles que startWork.
#    Le glob `*/` ignore déjà les dossiers cachés ; le case ci-dessous
#    attrape les noms non cachés à exclure.
# -----------------------------------------------------------------------------
step "Scan de $(pwd)"

CANDIDATES=()
for d in */; do
  [ -d "$d" ] || continue
  name="${d%/}"
  case "$name" in
    node_modules|dist|build|out|target|vendor) continue ;;
  esac
  CANDIDATES+=("$(pwd)/$name")
done

# Cas spécial : si le cwd est lui-même un repo (présence d'un marker usuel),
# l'inclure dans les candidats — utile quand on lance -endWork DANS un
# sous-projet pour fermer juste cette window-là.
if [ -e ".git" ] || [ -e "package.json" ] || [ -e "docker-compose.yml" ]; then
  CANDIDATES+=("$(pwd)")
fi

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  warn "Aucun sous-projet détecté à $(pwd)."
  exit 0
fi

info "Sous-projets candidats (${#CANDIDATES[@]}) :"
for c in "${CANDIDATES[@]}"; do
  echo "  - ${c##*/}"
done

# -----------------------------------------------------------------------------
# 2. Lecture du state Cursor — backupWorkspaces.folders[].folderUri liste
#    les folders actuellement ouverts dans des windows (file:// URI
#    percent-encodée, on décode pour comparer à des chemins POSIX bruts).
# -----------------------------------------------------------------------------
step "Windows Cursor ouvertes"

OPEN_FOLDERS=$(python3 - "$CURSOR_STORAGE" <<'PY'
import json, sys, urllib.parse
with open(sys.argv[1]) as f:
    data = json.load(f)
for folder in data.get("backupWorkspaces", {}).get("folders", []):
    uri = folder.get("folderUri", "")
    if uri.startswith("file://"):
        print(urllib.parse.unquote(uri[len("file://"):]))
PY
)

if [ -z "$OPEN_FOLDERS" ]; then
  warn "Aucune window Cursor ouverte d'après storage.json."
  exit 0
fi

info "Folders actuellement ouverts dans Cursor :"
while IFS= read -r f; do
  echo "  - $f"
done <<< "$OPEN_FOLDERS"

# -----------------------------------------------------------------------------
# 3. Intersection — quels candidats sont actuellement ouverts dans Cursor ?
#    Match exact sur le chemin absolu (avec trailing slash normalisé).
# -----------------------------------------------------------------------------
TO_CLOSE=()
for cand in "${CANDIDATES[@]}"; do
  cand_norm="${cand%/}"
  if grep -Fxq "$cand_norm" <<< "$OPEN_FOLDERS"; then
    TO_CLOSE+=("$cand_norm")
  fi
done

if [ "${#TO_CLOSE[@]}" -eq 0 ]; then
  warn "Aucune window Cursor ouverte ne correspond aux sous-repos du dossier courant."
  exit 0
fi

step "Windows à fermer (${#TO_CLOSE[@]})"
for w in "${TO_CLOSE[@]}"; do
  echo "  - ${w##*/}"
done

echo
if ! confirm "Fermer ces ${#TO_CLOSE[@]} window(s) Cursor ?" y; then
  err "Abandon."
  exit 1
fi

# -----------------------------------------------------------------------------
# 4. Fermeture via AppleScript / System Events.
#    Stratégie : pour chaque window ciblée, on filtre les windows Cursor par
#    `name contains "<basename>"`, on ramène chaque match au premier plan
#    (AXRaise), puis Cmd+W. Cursor gère lui-même le dialogue « voulez-vous
#    sauvegarder ? » s'il y a des modifications non sauvegardées — c'est
#    volontaire, on ne contourne pas.
#
# Caveats :
#   - si deux repos ouverts ont le même basename (improbable mais possible),
#     les deux windows seront fermées. C'est le seul cas où la stratégie
#     basename peut être trop large.
#   - le titre d'une window Cursor inclut généralement le basename de son
#     workspace (avec ou sans fichier ouvert devant). Pas de garantie
#     contractuelle de Cursor là-dessus — si Cursor changeait son format de
#     titre, ce match casserait.
# -----------------------------------------------------------------------------
close_window_for() {
  local repo_path="$1"
  local repo_name="${repo_path##*/}"
  osascript <<APPLESCRIPT 2>/dev/null
tell application "Cursor" to activate
delay 0.2
tell application "System Events"
  tell process "Cursor"
    set targetWindows to (every window whose name contains "$repo_name")
    repeat with w in targetWindows
      perform action "AXRaise" of w
      delay 0.15
      keystroke "w" using {command down}
      delay 0.3
    end repeat
  end tell
end tell
APPLESCRIPT
}

step "Fermeture des windows"
for w in "${TO_CLOSE[@]}"; do
  printf "  %s ... " "${w##*/}"
  if close_window_for "$w"; then
    printf "${GREEN}OK${NC}\n"
  else
    printf "${YELLOW}KO (Accessibility manquante ?)${NC}\n"
  fi
done

# -----------------------------------------------------------------------------
# 5. Vérification — relit storage.json après une courte pause pour signaler
#    les windows qui n'auraient pas été fermées (dialogue de sauvegarde en
#    attente, par ex.).
#
# Note : storage.json est mis à jour par Cursor à intervalles / sur certains
# events ; il peut être légèrement en retard. Un warning ici n'est donc pas
# nécessairement un échec — c'est juste un signal qu'il faut vérifier.
# -----------------------------------------------------------------------------
sleep 1

step "Vérification"
REMAINING=$(python3 - "$CURSOR_STORAGE" <<'PY'
import json, sys, urllib.parse
with open(sys.argv[1]) as f:
    data = json.load(f)
for folder in data.get("backupWorkspaces", {}).get("folders", []):
    uri = folder.get("folderUri", "")
    if uri.startswith("file://"):
        print(urllib.parse.unquote(uri[len("file://"):]))
PY
)

STILL_OPEN=()
for w in "${TO_CLOSE[@]}"; do
  if grep -Fxq "$w" <<< "$REMAINING"; then
    STILL_OPEN+=("${w##*/}")
  fi
done

if [ "${#STILL_OPEN[@]}" -eq 0 ]; then
  info "Toutes les windows ciblées ont été fermées."
else
  warn "Encore listées comme ouvertes : ${STILL_OPEN[*]}"
  warn "(probablement un dialogue de sauvegarde en attente, ou state Cursor pas encore flush)"
fi
