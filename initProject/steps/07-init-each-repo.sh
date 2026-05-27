#!/usr/bin/env bash
#
# steps/07-init-each-repo.sh
# =============================================================================
# Étape 7 — Cœur du workflow : pour chaque template sélectionné, copier son
# contenu localement et déposer un script `initRepot.sh` à la racine du
# dossier projet. Configure aussi un dossier `.claude/` à la racine du
# dossier parent pour aiguiller Claude vers les `.claude/` de chaque
# sous-projet quand on descend dans l'un d'eux.
#
# Pour chaque template :
#   1. Clone le template via gh (juste pour récupérer le contenu)
#   2. Strip son historique git (`rm -rf .git`)
#   3. Ajoute '.env*' au .gitignore (avant tout futur `git add`)
#   4. Dépose `initRepot.sh` à la racine + chmod +x
#
# Plus de `git init` / `git commit` / `git remote add` côté initProject :
# l'utilisateur lance `./initRepot.sh` quand il est prêt à publier — ce script
# fait git init + add + commit + gh repo create + push en une fois.
#
# Après la boucle :
#   - crée `$PARENT_DIR/.claude/rules/00-subprojects.md` avec les consignes
#     de dispatch (chargé mécaniquement par Claude quand on descend dans
#     un sous-projet, puisque le harness charge les `.claude/` parents).
#
# Consomme : SELECTED[], NEW_NAMES[], CURRENT_USER, PARENT_DIR, SUFFIX,
#            SCRIPT_DIR (pour localiser le template initRepot.sh)
# Produit  : INITIALIZED[] (succès), SKIPPED[] (dossier déjà présent),
#            FAILED[] (échec de clone)
# =============================================================================

init_each_repo() {
  step "Copie locale + dépose de initRepot.sh"

  INITIALIZED=()
  SKIPPED=()
  FAILED=()

  # ----- Vérifie que le template initRepot.sh est bien présent -----
  local initrepot_source="${SCRIPT_DIR}/templates/initRepot.sh"
  if [ ! -f "$initrepot_source" ]; then
    err "Template initRepot introuvable : $initrepot_source"
    exit 1
  fi

  # ----- Boucle principale -----
  local i template new_name target_dir
  for i in "${!SELECTED[@]}"; do
    template="${SELECTED[$i]}"
    new_name="${NEW_NAMES[$i]}"
    target_dir="${PARENT_DIR}/${new_name}"

    printf "  %s ... " "$new_name"

    # Cas 0 : le dossier existe déjà → on n'écrase rien, on skip
    if [ -e "$target_dir" ]; then
      printf "${YELLOW}existe déjà, skip${NC}\n"
      SKIPPED+=("$new_name")
      continue
    fi

    # 1. Clone du template (gh gère l'auth pour les templates privés)
    if ! gh repo clone "${CURRENT_USER}/${template}" "$target_dir" >/dev/null 2>&1; then
      printf "${RED}échec du clone${NC}\n"
      FAILED+=("$new_name")
      continue
    fi

    # 2. Strip de l'historique git du template
    rm -rf "${target_dir}/.git"

    # 3. Ajoute '.env*' au .gitignore (idempotent)
    _add_env_to_gitignore "${target_dir}/.gitignore"

    # 4. Dépose initRepot.sh à la racine
    _install_initrepot_script "$initrepot_source" "$target_dir"

    printf "${GREEN}OK${NC}\n"
    INITIALIZED+=("$new_name")
  done

  # ----- Après la boucle : .claude/ au niveau parent -----
  # Crée `$PARENT_DIR/.claude/rules/00-subprojects.md` pour indiquer à Claude
  # (mécaniquement chargé quand on descend dans un sous-projet) d'aller
  # chercher les configs `.claude/` de chacun des sous-projets initialisés.
  if [ "${#INITIALIZED[@]}" -gt 0 ]; then
    _write_parent_claude_dir
  fi
}

# -----------------------------------------------------------------------------
# Helpers internes (préfixe `_` pour signaler qu'ils ne sont pas appelés
# depuis l'extérieur de cette étape).
# -----------------------------------------------------------------------------

# Ajoute la ligne `.env*` à un .gitignore donné si elle n'y est pas déjà.
# Le fichier est créé s'il n'existe pas.
_add_env_to_gitignore() {
  local gitignore_file="$1"
  [ -f "$gitignore_file" ] || touch "$gitignore_file"
  if ! grep -qxF '.env*' "$gitignore_file"; then
    {
      printf '\n# Ignore all files starting with .env at any depth\n'
      printf '.env*\n'
    } >> "$gitignore_file"
  fi
}

# Copie initRepot.sh à la racine du dossier projet + chmod +x.
_install_initrepot_script() {
  local source="$1"
  local target_dir="$2"
  cp "$source" "${target_dir}/initRepot.sh"
  chmod +x "${target_dir}/initRepot.sh"
}

# Crée $PARENT_DIR/.claude/rules/00-subprojects.md.
#
# Pourquoi ce fichier :
#   $PARENT_DIR/.claude/ est mécaniquement chargé par le harness Claude Code
#   quand on descend dans n'importe quel sous-dossier — donc settings.json,
#   agents/, commands/ partagés seront disponibles dans tous les sous-projets.
#   Le fichier `rules/00-subprojects.md` sert de point d'ancrage et de doc :
#   il indique à Claude comment dispatcher vers les `.claude/` des sous-projets,
#   et les futures règles partagées iront dans le même dossier.
_write_parent_claude_dir() {
  local claude_dir="${PARENT_DIR}/.claude"
  local rules_dir="${claude_dir}/rules"
  local rules_file="${rules_dir}/00-subprojects.md"

  mkdir -p "$rules_dir"

  {
    printf '# Sous-projets\n\n'
    printf 'Ce dossier parent regroupe plusieurs sous-projets, chacun avec son propre\n'
    printf '`.claude/` (settings, agents, commandes, mémoires) et éventuellement son\n'
    printf '`CLAUDE.md`. Les sous-projets initialisés ici :\n\n'
    local n
    for n in "${INITIALIZED[@]}"; do
      printf -- '- `./%s/.claude/` (et `./%s/CLAUDE.md` si présent)\n' "$n" "$n"
    done
    printf '\n## Comportement attendu\n\n'
    printf 'Quand tu travailles depuis ce dossier parent, charge et applique en priorité\n'
    printf 'les configurations `.claude/` (et `CLAUDE.md` s'\''il existe) du sous-projet\n'
    printf 'concerné par la tâche.\n\n'
    printf '## Comment choisir le sous-projet\n\n'
    printf '1. Si la tâche cible un fichier précis, applique les règles du sous-projet\n'
    printf '   contenant ce fichier.\n'
    printf '2. Si la tâche est transverse (touche plusieurs sous-projets), applique\n'
    printf '   l'\''union des règles de chacun.\n'
    printf '3. En cas de conflit entre règles, mentionne-le et demande l'\''arbitrage.\n\n'
    printf '## Conseil\n\n'
    printf 'Pour bosser focus sur un seul sous-projet, ouvre Claude directement depuis\n'
    printf 'son dossier — son `.claude/` et son `CLAUDE.md` seront chargés nativement,\n'
    printf 'sans passer par cette indirection.\n'
  } > "$rules_file"

  info ".claude/ créé    : $claude_dir"
}
