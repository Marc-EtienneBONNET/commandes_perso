#!/usr/bin/env bash
#
# steps/07-init-each-repo.sh
# =============================================================================
# Étape 7 — Cœur du workflow : pour chaque template sélectionné, copier son
# contenu localement et préparer un repo prêt à pousser.
#
# Pour chaque template :
#   1. Clone le template via gh (juste pour récupérer le contenu)
#   2. Strip son historique git (`rm -rf .git`)
#   3. Ajoute '.env*' au .gitignore AVANT le premier `git add` → le `.env`
#      éventuel du template n'est PAS tracké dans le nouveau repo
#   4. `git init -b main` + commit initial
#   5. Configure `origin` vers ${CURRENT_USER}/<new_name>
#      (le repo n'existe pas encore — le hook pre-push s'en occupera)
#   6. Installe le hook pre-push (depuis hooks/pre-push) dans .git/hooks/
#
# Consomme : SELECTED[], NEW_NAMES[], CURRENT_USER, PARENT_DIR, GH_PROTO,
#            SCRIPT_DIR (pour localiser le fichier hook source)
# Produit  : INITIALIZED[] (succès), SKIPPED[] (dossier déjà présent),
#            FAILED[] (échec de clone)
# =============================================================================

init_each_repo() {
  step "Copie locale + git init + hook pre-push"

  INITIALIZED=()
  SKIPPED=()
  FAILED=()

  # ----- Vérifie que le hook source est bien présent (sinon abort) -----
  local hook_source="${SCRIPT_DIR}/hooks/pre-push"
  if [ ! -f "$hook_source" ]; then
    err "Hook source introuvable : $hook_source"
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

    # 4-6. Tout le reste se fait dans le repo cloné, dans un sous-shell pour
    # ne pas avoir à `cd ..` après.
    (
      cd "$target_dir"
      _ensure_git_identity
      _do_initial_commit "$template"
      _configure_origin "$new_name"
      _install_pre_push_hook "$hook_source"
    )

    printf "${GREEN}OK${NC}\n"
    INITIALIZED+=("$new_name")
  done
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

# Garantit qu'un user.name / user.email est défini pour CE repo (local).
# Évite le crash de `git commit` si le global est vide ou inexistant.
# Stratégie :
#   1. Si local déjà défini → on touche pas
#   2. Sinon : on hérite du global s'il existe
#   3. Sinon : fallback sur le login gh + email no-reply GitHub
_ensure_git_identity() {
  if ! git config user.name >/dev/null 2>&1; then
    local n
    n=$(git config --global user.name 2>/dev/null || echo "$CURRENT_USER")
    git config user.name "$n"
  fi
  if ! git config user.email >/dev/null 2>&1; then
    local e
    e=$(git config --global user.email 2>/dev/null || echo "${CURRENT_USER}@users.noreply.github.com")
    git config user.email "$e"
  fi
}

# `git init -b main` + premier commit (tout sauf gitignored).
_do_initial_commit() {
  local template="$1"
  git init -q -b main
  git add -A
  git commit -q -m "Initial commit from ${template}"
}

# Configure le remote `origin` vers l'URL FUTURE du repo GitHub.
# Le repo n'existe pas encore — le hook pre-push le créera au premier push.
_configure_origin() {
  local new_name="$1"
  local origin_url
  if [ "$GH_PROTO" = "ssh" ]; then
    origin_url="git@github.com:${CURRENT_USER}/${new_name}.git"
  else
    origin_url="https://github.com/${CURRENT_USER}/${new_name}.git"
  fi
  git remote add origin "$origin_url"
}

# Copie le hook pre-push (depuis hooks/pre-push) dans .git/hooks/ + chmod +x.
_install_pre_push_hook() {
  local hook_source="$1"
  local hook_dest=".git/hooks/pre-push"
  cp "$hook_source" "$hook_dest"
  chmod +x "$hook_dest"
}
