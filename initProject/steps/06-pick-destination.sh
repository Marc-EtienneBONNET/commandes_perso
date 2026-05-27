#!/usr/bin/env bash
#
# steps/06-pick-destination.sh
# =============================================================================
# Étape 6 — Choix du dossier de destination
#
# But : ouvrir le sélecteur de dossier Finder (via osascript). À l'intérieur
#       du dossier choisi, on crée un sous-dossier nommé <SUFFIX> qui
#       contiendra les clones locaux.
#
# On profite aussi de cette étape pour récupérer le protocole git (ssh ou
# https) configuré dans gh — c'est utilisé dans l'étape 7 pour construire
# l'URL d'origin de chaque repo cloné.
#
# Consomme : SUFFIX
# Produit  : PARENT_DIR  (chemin absolu du sous-dossier qui contiendra les clones)
#            GH_PROTO    ("ssh" ou "https")
# =============================================================================

pick_destination() {
  step "Dossier de destination"

  info "Le Finder va s'ouvrir."
  local dest_path
  dest_path=$(
    osascript -e 'POSIX path of (choose folder with prompt "Où veux-tu mettre le nouveau projet ?")' 2>/dev/null \
      || true
  )
  dest_path="${dest_path%/}"   # retire un éventuel slash final

  if [ -z "$dest_path" ]; then
    warn "Aucun dossier choisi. Abandon."
    exit 0
  fi

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

  # Récupère le protocole git de gh : ssh ou https. Sert à fabriquer l'URL
  # d'origin (qu'on configurera dans chaque repo) à l'étape suivante.
  GH_PROTO=$(gh config get git_protocol 2>/dev/null || echo https)
}
