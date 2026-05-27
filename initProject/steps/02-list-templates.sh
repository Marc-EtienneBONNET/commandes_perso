#!/usr/bin/env bash
#
# steps/02-list-templates.sh
# =============================================================================
# Étape 2 — Liste des templates disponibles
#
# But : lister tous les repos du compte actif marqués `isTemplate=true` sur
#       GitHub. Si aucun template, on arrête le script (rien à dupliquer).
#
# Consomme : CURRENT_USER
# Produit  : TEMPLATES[]  (tableau des noms de templates, triés)
# =============================================================================

list_templates() {
  step "Templates disponibles sur $CURRENT_USER"

  TEMPLATES=()

  # `gh repo list` + filtre jq sur `isTemplate==true`. On lit le résultat
  # ligne par ligne pour rester compatible bash 3.2 (macOS) : pas de mapfile.
  while IFS= read -r line; do
    [ -n "$line" ] && TEMPLATES+=("$line")
  done < <(
    gh repo list "$CURRENT_USER" \
      --limit 500 \
      --json name,isTemplate \
      --jq '.[] | select(.isTemplate==true) | .name' \
      | sort
  )

  if [ "${#TEMPLATES[@]}" -eq 0 ]; then
    err "Aucun repo marqué template trouvé sur $CURRENT_USER."
    warn "Marque tes modèles avec : gh repo edit OWNER/REPO --template"
    exit 1
  fi

  info "${#TEMPLATES[@]} template(s) détecté(s) :"
  local t
  for t in "${TEMPLATES[@]}"; do
    echo "  - $t"
  done
}
