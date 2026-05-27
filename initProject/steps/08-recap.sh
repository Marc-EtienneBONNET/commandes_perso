#!/usr/bin/env bash
#
# steps/08-recap.sh
# =============================================================================
# Étape 8 — Récap final
#
# Affiche :
#   - le dossier parent local créé
#   - les repos initialisés (avec l'URL origin pré-configurée)
#   - les repos skippés (dossier déjà existant)
#   - les repos en échec (clone raté)
#   - un rappel du comportement du hook pre-push
#
# Consomme : PARENT_DIR, CURRENT_USER, INITIALIZED[], SKIPPED[], FAILED[]
# Produit  : (rien — affichage uniquement)
# =============================================================================

print_recap() {
  step "Projet initialisé localement"

  echo "Dossier parent : $PARENT_DIR"
  echo

  # ----- Succès -----
  if [ "${#INITIALIZED[@]}" -gt 0 ]; then
    echo "Repos initialisés (${#INITIALIZED[@]}) — pas encore sur GitHub :"
    local n
    for n in "${INITIALIZED[@]}"; do
      echo "  - $PARENT_DIR/$n  (origin → ${CURRENT_USER}/$n)"
    done
  fi

  # ----- Skippés (dossier déjà existant) -----
  if [ "${#SKIPPED[@]}" -gt 0 ]; then
    echo
    warn "Dossiers déjà existants, skippés (${#SKIPPED[@]}) :"
    local n
    for n in "${SKIPPED[@]}"; do
      echo "  - $n"
    done
  fi

  # ----- Échecs -----
  if [ "${#FAILED[@]}" -gt 0 ]; then
    echo
    err "Échecs (${#FAILED[@]}) :"
    local n
    for n in "${FAILED[@]}"; do
      echo "  - $n"
    done
  fi

  # ----- Rappel du hook pre-push -----
  echo
  info "Au premier 'git push -u origin main' depuis l'un de ces dossiers, le"
  info "hook pre-push créera automatiquement le repo GitHub privé"
  info "'${CURRENT_USER}/<nom_du_dossier>' (basé sur l'URL d'origin)."
  echo
  info "Bon dev !"
}
