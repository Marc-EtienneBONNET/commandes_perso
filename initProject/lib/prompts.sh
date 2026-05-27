#!/usr/bin/env bash
#
# lib/prompts.sh — prompts utilisateur réutilisables
# =============================================================================
# confirm "question" [y|n]
#   Pose une question oui/non. Renvoie 0 (oui) ou 1 (non).
#   Accepte les variantes FR (o/oui/non) et EN (y/n/yes/no).
#   Le second argument indique la valeur par défaut (touche Entrée).
#
# sanitize_name "valeur brute"
#   Nettoie un nom pour qu'il soit valide comme nom de repo ou de dossier :
#     - lowercase
#     - tout caractère hors [a-z0-9_] devient `_`
#     - trim les `_` en début et fin
#   Stdout : le nom nettoyé.
# =============================================================================

confirm() {
  local question="$1" default="${2:-n}" hint answer

  # Hint affiché à côté de la question, met en évidence la valeur par défaut
  if [ "$default" = "y" ] || [ "$default" = "o" ]; then
    hint="[O/n]"
  else
    hint="[o/N]"
  fi

  while true; do
    read -r -p "$(printf "${BLUE}%s${NC} %s " "$question" "$hint")" answer
    # Entrée vide → on prend le défaut
    answer="${answer:-$default}"
    case "$answer" in
      y|Y|yes|YES|o|O|oui|OUI) return 0 ;;
      n|N|no|NO|non|NON)       return 1 ;;
      *) warn "Réponds par o/n." ;;
    esac
  done
}

sanitize_name() {
  printf "%s" "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9_]+/_/g; s/^_+//; s/_+$//'
}
