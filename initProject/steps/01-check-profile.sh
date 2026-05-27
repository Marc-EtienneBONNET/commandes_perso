#!/usr/bin/env bash
#
# steps/01-check-profile.sh
# =============================================================================
# Étape 1 — Profil GitHub
#
# But : afficher le compte gh actuellement actif, proposer de le conserver ou
#       de basculer (login web). Si pas du tout authentifié, proposer login.
#
# Consomme : (rien)
# Produit  : CURRENT_USER  (login GitHub de l'utilisateur actif)
# =============================================================================

check_profile() {
  step "Profil GitHub"

  # ----- Cas 1 : aucun compte authentifié -----
  if ! gh auth status >/dev/null 2>&1; then
    warn "Pas connecté à GitHub CLI."
    if confirm "Lancer 'gh auth login --web' maintenant ?" y; then
      gh auth login --web
    else
      err "Abandon."
      exit 1
    fi
  fi

  # ----- Cas 2 : un compte est actif, on récupère son login -----
  CURRENT_USER=$(gh api user --jq .login)
  info "Profil actif : $CURRENT_USER"

  # ----- L'utilisateur peut vouloir basculer sur un autre compte -----
  if ! confirm "Conserver ce profil ?" y; then
    info "Connexion via navigateur..."
    gh auth login --web
    CURRENT_USER=$(gh api user --jq .login)
    info "Nouveau profil actif : $CURRENT_USER"
  fi
}
