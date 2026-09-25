# Interactive shell functions loader
# Loads modular function suites from ~/.dotfiles/zsh/functions/*.zsh

ZSH_FUNCTIONS_DIR="${0:A:h}/functions"

if [ -d "$ZSH_FUNCTIONS_DIR" ]; then
  # Temporarily disable alias expansion while loading function definitions
  # so active aliases never corrupt function declarations on reload/re-source
  local _aliases_were_active=false
  [[ -o aliases ]] && _aliases_were_active=true
  setopt NO_ALIASES

  for _func_file in "$ZSH_FUNCTIONS_DIR"/*.zsh(N); do
    source "$_func_file"
  done
  unset _func_file

  [ "$_aliases_were_active" = true ] && setopt ALIASES
  unset _aliases_were_active
fi
