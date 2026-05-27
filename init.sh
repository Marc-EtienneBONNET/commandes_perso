#!/usr/bin/env bash
#
# init.sh — installer pour mes commandes perso
# =============================================================================
# Installe chaque commande définie comme sous-dossier de ce repo dans
# ~/.commandes_perso, et crée un symlink dans ~/.local/bin (ajouté au PATH
# via ~/.zshrc) pour que les commandes soient invocables de n'importe où.
#
# Pattern attendu pour qu'un sous-dossier soit reconnu comme une commande :
#   <nom>/<nom>.sh    (entry point)
#
# Les symlinks créés dans ~/.local/bin sont TOUJOURS préfixés par `-` pour
# distinguer visuellement les commandes perso des commandes natives.
#
# Exemple : initProject/initProject.sh → invocable via `-initProject`
#
# Si une commande déjà installée porte le même nom, elle est remplacée
# (le script est idempotent).
#
# En fin de course, propose de supprimer le repo source local (le repo GitHub
# n'est jamais touché).
#
# Usage : ./init.sh    (depuis la racine de commandes_perso)
# Dépendances : bash 3.2+, zsh comme shell utilisateur
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Couleurs et helpers d'affichage
# -----------------------------------------------------------------------------
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
# Constantes : chemins source et destination
# -----------------------------------------------------------------------------
# Dossier dans lequel vit ce script (= racine de commandes_perso)
SOURCE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Où va vivre le code des commandes installées (XDG-friendly, dans le home)
INSTALL_DIR="$HOME/.commandes_perso"

# Où on pose les symlinks invocables (~/.local/bin est souvent déjà dans PATH ;
# si non, on l'y ajoute via ~/.zshrc à l'étape 4)
BIN_DIR="$HOME/.local/bin"

# Fichier zsh à modifier
ZSHRC="$HOME/.zshrc"

# Marqueurs pour pouvoir détecter et idempotemment réinjecter notre bloc
PATH_MARKER_START="# >>> commandes_perso (init.sh) >>>"
PATH_MARKER_END="# <<< commandes_perso (init.sh) <<<"

# -----------------------------------------------------------------------------
# 1. Détection des commandes
# -----------------------------------------------------------------------------
# Une "commande" est définie par convention comme un sous-dossier dont le nom
# matche un .sh à l'intérieur. Ex : initProject/initProject.sh
# -----------------------------------------------------------------------------
step "Détection des commandes dans $SOURCE_DIR"

COMMANDS=()
for d in "$SOURCE_DIR"/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  entry="${d%/}/${name}.sh"
  if [ -f "$entry" ]; then
    COMMANDS+=("$name")
    echo "  - $name  (entry : $entry)"
  fi
done

if [ "${#COMMANDS[@]}" -eq 0 ]; then
  err "Aucune commande détectée. Pattern attendu : <dossier>/<dossier>.sh"
  exit 1
fi

# -----------------------------------------------------------------------------
# 2. Création des dossiers cibles
# -----------------------------------------------------------------------------
step "Préparation des dossiers d'installation"
mkdir -p "$INSTALL_DIR" "$BIN_DIR"
info "Code des commandes : $INSTALL_DIR"
info "Symlinks (PATH)    : $BIN_DIR"

# -----------------------------------------------------------------------------
# 3. Installation de chaque commande
# -----------------------------------------------------------------------------
# Pour chaque commande détectée :
#   a. supprime l'ancienne install (dossier + symlink) si présente
#   b. copie le dossier source vers $INSTALL_DIR/<name>
#   c. chmod +x sur tous les .sh + sur d'éventuels hooks (extensionless)
#   d. crée le symlink $BIN_DIR/<name> → entry point
# -----------------------------------------------------------------------------
step "Installation"

for name in "${COMMANDS[@]}"; do
  src="$SOURCE_DIR/$name"
  dst="$INSTALL_DIR/$name"
  # Préfixe `-` systématique sur l'exe (convention command-naming.md).
  # Si le nom commence déjà par `-`, on ne double pas.
  case "$name" in
    -*) bin_name="$name" ;;
    *)  bin_name="-$name" ;;
  esac
  bin_link="$BIN_DIR/$bin_name"
  entry_in_dst="$dst/$name.sh"

  printf "  %s -> %s ... " "$name" "$bin_name"

  # a. Remplacement propre : supprime l'existant
  rm -rf "$dst"
  rm -f  "$bin_link"

  # b. Copie complète du dossier source
  cp -R "$src" "$dst"

  # c. Rendre exécutables les .sh + les fichiers dans hooks/ (sans extension)
  find "$dst" -type f -name "*.sh" -exec chmod +x {} \;
  if [ -d "$dst/hooks" ]; then
    find "$dst/hooks" -type f -exec chmod +x {} \;
  fi

  # d. Symlink dans PATH (nom de l'exe = <name>, sans .sh)
  ln -s "$entry_in_dst" "$bin_link"

  printf "${GREEN}OK${NC}\n"
done

# -----------------------------------------------------------------------------
# 4. Ajout de ~/.local/bin au PATH via ~/.zshrc
# -----------------------------------------------------------------------------
# On encadre l'ajout par des marqueurs : si le bloc existe déjà, on ne touche
# pas. Sinon, on l'ajoute en fin de fichier.
# -----------------------------------------------------------------------------
step "Configuration de ~/.zshrc"

[ -f "$ZSHRC" ] || touch "$ZSHRC"

if grep -qF "$PATH_MARKER_START" "$ZSHRC"; then
  info "Bloc déjà présent dans $ZSHRC — rien à ajouter."
else
  {
    printf '\n%s\n' "$PATH_MARKER_START"
    printf 'export PATH="%s:$PATH"\n' "$BIN_DIR"
    printf '%s\n' "$PATH_MARKER_END"
  } >> "$ZSHRC"
  info "Bloc ajouté à $ZSHRC :"
  info "  export PATH=\"$BIN_DIR:\$PATH\""
fi

# -----------------------------------------------------------------------------
# 5. Récap
# -----------------------------------------------------------------------------
step "Commandes installées"
for name in "${COMMANDS[@]}"; do
  case "$name" in
    -*) bin_name="$name" ;;
    *)  bin_name="-$name" ;;
  esac
  echo "  $bin_name  →  $INSTALL_DIR/$name/${name}.sh"
done
echo
info "Pour utiliser dans la session actuelle :"
echo "  source ~/.zshrc"
echo
info "Ou ouvre simplement un nouveau terminal. Tu pourras ensuite taper :"
for name in "${COMMANDS[@]}"; do
  case "$name" in
    -*) bin_name="$name" ;;
    *)  bin_name="-$name" ;;
  esac
  echo "  $bin_name"
done

# -----------------------------------------------------------------------------
# 6. Suppression optionnelle du repo source local
# -----------------------------------------------------------------------------
# À ce stade, tout le code des commandes a été COPIÉ dans $INSTALL_DIR.
# Le repo source devient inutile sur la machine (à part pour les mises à jour
# futures via git pull + re-run de init.sh). L'utilisateur peut donc le
# supprimer en local sans perdre les commandes installées.
# Le repo GitHub n'est JAMAIS touché par cette opération.
# -----------------------------------------------------------------------------
step "Nettoyage du repo source local"

info "Repo source : $SOURCE_DIR"
info "Install     : $INSTALL_DIR (indépendant du repo source)"
echo
if confirm "Supprimer le repo local $SOURCE_DIR ? (le repo GitHub reste intact)" n; then
  # cd hors du repo avant de le supprimer — le script lui-même tourne depuis
  # ce repo, bash a déjà chargé le script en mémoire donc la suppression du
  # fichier source est sans danger pour la suite de l'exécution.
  cd "$HOME"
  rm -rf "$SOURCE_DIR"
  info "Repo local supprimé."
  warn "Pour mettre à jour les commandes plus tard : re-clone le repo GitHub"
  warn "puis relance ./init.sh depuis la racine."
else
  info "Repo source conservé."
fi
