#!/usr/bin/env bash
#
# steps/06-pick-destination.sh
# =============================================================================
# Étape 6 — Choix du dossier de destination
#
# But : créer un sous-dossier nommé <SUFFIX> dans le dossier courant
#       (là où la commande a été lancée). Ce sous-dossier contiendra
#       les clones locaux.
#
# Consomme : SUFFIX
# Produit  : PARENT_DIR  (chemin absolu du sous-dossier qui contiendra les clones)
# =============================================================================

pick_destination() {
  step "Dossier de destination"

  local dest_path
  dest_path="${PWD%/}"

  PARENT_DIR="${dest_path}/${SUFFIX}"

  if [ -d "$PARENT_DIR" ]; then
    warn "$PARENT_DIR existe déjà."
    if ! confirm "Continuer (les clones iront dedans) ?" n; then
      exit 0
    fi
  else
    mkdir -p "$PARENT_DIR"
  fi

  info "Dossier parent : $PARENT_DIR"
}
