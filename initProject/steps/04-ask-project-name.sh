#!/usr/bin/env bash
#
# steps/04-ask-project-name.sh
# =============================================================================
# Étape 4 — Nom du projet
#
# But : demander le nom du projet à l'utilisateur. Ce nom servira à :
#         1. préfixer les nouveaux repos (ex. 'door' → 'door_node_express')
#         2. nommer le dossier parent qui contiendra tous les clones locaux
#
# Le nom est nettoyé (sanitize_name) pour être valide en repo/dossier :
# minuscules, alphanumérique + underscore uniquement.
#
# Consomme : (rien)
# Produit  : SUFFIX  (nom nettoyé)
# =============================================================================

ask_project_name() {
  step "Nom du projet"

  SUFFIX=""
  while [ -z "$SUFFIX" ]; do
    read -r -p "$(printf "${BLUE}Nom du projet (préfixe des repos + dossier parent, ex: door) : ${NC}")" raw
    SUFFIX=$(sanitize_name "$raw")
    [ -z "$SUFFIX" ] && warn "Nom invalide. Recommence."
  done

  info "Nom : $SUFFIX"
}
