#!/usr/bin/env bash
#
# steps/05-compute-new-names.sh
# =============================================================================
# Étape 5 — Calcul des noms des nouveaux repos
#
# Règle : <SUFFIX>_<nom du template sans préfixe `model`>
#   - 'model_node_express'      → 'node_express'      → 'door_node_express'
#   - 'model-react-native-expo' → 'react-native-expo' → 'door_react_native_expo'
#   - 'foo' (sans préfixe)      → 'foo'               → 'door_foo'
#
# NEW_NAMES[i] correspond toujours à SELECTED[i] (indices alignés).
#
# Affiche le mapping puis demande confirmation avant de continuer.
#
# Consomme : SELECTED[], SUFFIX
# Produit  : NEW_NAMES[]
# =============================================================================

compute_new_names() {
  step "Nouveaux noms"

  NEW_NAMES=()
  local t base new_name
  for t in "${SELECTED[@]}"; do
    # Strip un éventuel préfixe `model_`, `model-` ou simplement `model` initial
    base=$(printf "%s" "$t" | sed -E 's/^model[_-]?//')
    new_name="${SUFFIX}_${base}"
    NEW_NAMES+=("$new_name")
    printf "  %-40s -> ${GREEN}%s${NC}\n" "$t" "$new_name"
  done

  if ! confirm "Confirmer la copie locale (sans création GitHub) ?" y; then
    warn "Abandon."
    exit 0
  fi
}
