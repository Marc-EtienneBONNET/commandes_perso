#!/usr/bin/env bash
#
# steps/03-select-templates.sh
# =============================================================================
# Étape 3 — Sélection des templates à dupliquer
#
# But : pour chaque template trouvé à l'étape 2, demander oui/non.
#       Si aucun n'est retenu, on arrête le script (rien à faire).
#
# Consomme : TEMPLATES[]
# Produit  : SELECTED[]  (sous-ensemble retenu)
# =============================================================================

select_templates() {
  step "Sélection des templates"

  SELECTED=()
  local t
  for t in "${TEMPLATES[@]}"; do
    if confirm "Inclure '$t' ?" n; then
      SELECTED+=("$t")
    fi
  done

  if [ "${#SELECTED[@]}" -eq 0 ]; then
    warn "Aucun template sélectionné. Abandon."
    exit 0
  fi

  info "Sélection (${#SELECTED[@]}) : ${SELECTED[*]}"
}
