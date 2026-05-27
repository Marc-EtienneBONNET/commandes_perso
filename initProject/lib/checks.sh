#!/usr/bin/env bash
#
# lib/checks.sh — vérifications de dépendances
# =============================================================================
# check_dependencies
#   Vérifie que les binaires requis par le workflow sont installés.
#   Quitte le script avec un message d'erreur clair si l'un manque.
#
# Binaires requis :
#   - git       : version control (utilisé pour init + commit)
#   - gh        : GitHub CLI (auth, listing templates, création de repo)
#   - osascript : macOS uniquement, pour le sélecteur de dossier Finder
# =============================================================================

check_dependencies() {
  command -v git >/dev/null 2>&1 || {
    err "git introuvable. Installe-le via 'brew install git' ou Xcode CLT."
    exit 1
  }

  command -v gh >/dev/null 2>&1 || {
    err "gh (GitHub CLI) introuvable. https://cli.github.com/"
    exit 1
  }

  command -v osascript >/dev/null 2>&1 || {
    err "osascript introuvable (script prévu pour macOS)."
    exit 1
  }
}
