#!/usr/bin/env bash
#
# lib/colors.sh — codes couleur ANSI + helpers d'affichage
# =============================================================================
# Ce fichier centralise tous les écrits à l'écran pour le workflow.
# Utiliser ces helpers permet d'avoir un rendu cohérent et de modifier la
# présentation à un seul endroit.
#
# step "..."  → titre vert gras, marque une nouvelle phase du workflow
# info "..."  → ligne bleue, info neutre
# warn "..."  → ligne jaune, avertissement
# err  "..."  → ligne rouge sur stderr, erreur
# =============================================================================

# Codes ANSI (lus tels quels par printf — les `\033` restent littéraux car
# entourés de single-quotes).
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'      # No Color (reset)

# Titre d'étape — saut de ligne avant pour séparer visuellement.
step() { printf "\n${BOLD}${GREEN}==> %s${NC}\n" "$*"; }

# Info neutre.
info() { printf "${BLUE}%s${NC}\n" "$*"; }

# Avertissement (jaune, sur stdout — l'utilisateur le lit, le script continue).
warn() { printf "${YELLOW}%s${NC}\n" "$*"; }

# Erreur (rouge, sur stderr — pour être facile à isoler en cas de pipe/log).
err()  { printf "${RED}%s${NC}\n" "$*" >&2; }
