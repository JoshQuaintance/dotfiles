# Interactive shell functions loader
# Loads modular function suites from ~/.dotfiles/zsh/functions/*.zsh

ZSH_FUNCTIONS_DIR="${0:A:h}/functions"

if [ -d "$ZSH_FUNCTIONS_DIR" ]; then
  for _func_file in "$ZSH_FUNCTIONS_DIR"/*.zsh(N); do
    source "$_func_file"
  done
  unset _func_file
fi
