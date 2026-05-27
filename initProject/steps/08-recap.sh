#!/usr/bin/env bash
#
# steps/08-recap.sh
# =============================================================================
# Étape 8 — Récap final
#
# Affiche :
#   - le dossier parent local créé
#   - les sous-projets copiés (chacun avec un initRepot.sh prêt à l'emploi)
#   - les sous-projets skippés (dossier déjà existant)
#   - les sous-projets en échec (clone raté)
#   - le mode d'emploi pour publier sur GitHub (./initRepot.sh)
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
    echo "Dossiers prêts (${#INITIALIZED[@]}) — pas encore sur GitHub :"
    local n
    for n in "${INITIALIZED[@]}"; do
      echo "  - $PARENT_DIR/$n  (futur repo → ${CURRENT_USER}/$n)"
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

  # ----- Mode d'emploi pour publier -----
  echo
  info "Pour publier un sous-projet sur GitHub, va dedans et lance :"
  echo "  cd <dossier>"
  echo "  ./initRepot.sh"
  info "→ git init + commit 'init' + création du repo privé + push."
  echo
  info "Un CLAUDE.md a aussi été déposé à la racine du dossier parent :"
  info "il indique à Claude (ouvert depuis $PARENT_DIR) d'utiliser les"
  info "\`.claude/\` de chaque sous-projet."
  echo
  info "Bon dev !"
}
