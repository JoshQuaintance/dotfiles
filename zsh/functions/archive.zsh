# ==============================================================================
# Universal Archive Extraction & Packing (`zsh/functions/archive.zsh`)
# ==============================================================================
# Format-inferred archive decompression (`extract` / `x`) and creation (`pack`),
# accelerating with `ouch` when installed and falling back to tar/zip/7z/zstd.

# Universal Archive Extractor (extract / x)
# Uses Rust-based `ouch` when available, with portable fallback to tar/unzip/7z/zstd.
extract() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;203;166;247mextract\033[0m (alias: \033[1mx\033[0m) — Universal archive extractor\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  extract <archive...>   Extract one or more archives\n"
    printf "  extract                Interactively pick archive(s) in FZF\n"
    return 0
  fi

  if [ $# -eq 0 ] && [ -t 0 ] && [ -t 1 ] && command -v fzf &>/dev/null; then
    local -a fzf_mode_flags
    _fzf_vim_mode "📦 Extract Archive > " "  j/k: move │ space: select │ /: search │ enter: extract │ q: quit" "extract" "space" "" "space:toggle+down"
    local picked
    picked=$(find . -maxdepth 3 -type f \( -iname "*.tar.gz" -o -iname "*.tgz" -o -iname "*.tar.bz2" -o -iname "*.tbz2" -o -iname "*.tar.xz" -o -iname "*.txz" -o -iname "*.tar.zst" -o -iname "*.tar" -o -iname "*.zip" -o -iname "*.7z" -o -iname "*.rar" -o -iname "*.gz" -o -iname "*.bz2" -o -iname "*.zst" \) 2>/dev/null | sed 's|^\./||' | sort | fzf --multi --height=~50% --marker="✓ " "${fzf_mode_flags[@]}")
    [ -z "$picked" ] && return 0
    local f
    for f in "${(@f)picked}"; do
      extract "$f" || return $?
    done
    return 0
  fi

  if [ -z "$1" ]; then
    printf "\033[33mUsage: extract <archive_file>\033[0m\n" >&2
    printf "Supports: .tar.gz, .tgz, .tar.bz2, .tbz2, .tar.xz, .txz, .zip, .rar, .7z, .tar.zst, .zst, .gz, .bz2\n" >&2
    return 1
  fi

  if [ ! -f "$1" ]; then
    printf "\033[31m✖ File not found: %s\033[0m\n" "$1" >&2
    return 1
  fi

  local file="$1"
  # :l = lowercase parameter expansion in Zsh
  case "${file:l}" in
    *.tar.bz2|*.tbz2|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.zst|*.tar|*.bz2|*.rar|*.gz|*.zip|*.z|*.7z|*.zst)
      # Fast path: use `ouch decompress --here` when installed, falling back on error
      if command -v ouch &>/dev/null && ouch decompress --here -y "$file" 2>/dev/null; then
        return 0
      fi
      ;;
  esac

  case "${file:l}" in
    *.tar.bz2|*.tbz2)   tar xvjf "$file" ;;
    *.tar.gz|*.tgz)     tar xvzf "$file" ;;
    *.tar.xz|*.txz)     tar xvJf "$file" ;;
    *.tar.zst)          tar --zstd -xvf "$file" 2>/dev/null || zstd -d -c "$file" | tar xvf - ;;
    *.tar)              tar xvf "$file" ;;
    *.bz2)              bunzip2 "$file" ;;
    *.rar)              unrar x "$file" ;;
    *.gz)               gunzip "$file" ;;
    *.zip)              unzip "$file" ;;
    *.z)                uncompress "$file" ;;
    *.7z)               if command -v 7zz &>/dev/null; then 7zz x "$file"; else 7z x "$file"; fi ;;
    *.zst)              zstd -d "$file" ;;
    *)
      printf "\033[31m✖ Cannot extract '%s' — unsupported extension.\033[0m\n" "$file" >&2
      return 1
      ;;
  esac
}

# Tab completion for extract / x: complete supported archive files
_extract() {
  _files -g '*.(tar.bz2|tbz2|tar.gz|tgz|tar.xz|txz|tar.zst|tar|bz2|rar|gz|zip|Z|z|7z|zst)(-.)'
}
(( $+functions[compdef] )) && compdef _extract extract x || true

# Universal Archive Creator (pack)
# Companion to extract: creates archives from files/directories based on output extension.
# Uses Rust-based `ouch` when available, with portable fallback to tar/zip/7z/zstd.
# Usage:
#   pack <archive_name> <files/dirs...>   -> Create archive in specified format (.tar.gz, .zip, .tar.zst, .7z, etc.)
#   pack <directory>                      -> Defaults to <directory>.tar.gz
pack() {
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    printf "\033[1;38;2;203;166;247mpack\033[0m — Universal archive creator (companion to \033[1mextract\033[0m / \033[1mx\033[0m)\n\n"
    printf "\033[1mUsage:\033[0m\n"
    printf "  pack <archive.ext> <files/dirs...>   Create archive inferred from extension\n"
    printf "  pack <folder>                        Create <folder>.tar.gz from <folder>\n\n"
    printf "\033[1mSupported formats:\033[0m\n"
    printf "  .tar.gz, .tgz, .tar.bz2, .tbz2, .tar.xz, .txz, .tar.zst, .tar, .zip, .7z, .gz, .bz2, .zst\n"
    return 0
  fi

  if [ $# -eq 0 ] && [ -t 0 ] && [ -t 1 ] && command -v fzf &>/dev/null; then
    local -a fzf_mode_flags
    _fzf_vim_mode "🗜  Pack Files/Folders > " "  j/k: move │ space: select │ /: search │ enter: pack │ q: quit" "pack" "space" "" "space:toggle+down"
    local picked
    picked=$(find . -maxdepth 2 -not -path '*/.git*' -not -path '.' 2>/dev/null | sed 's|^\./||' | sort | fzf --multi --height=~50% --marker="✓ " "${fzf_mode_flags[@]}")
    [ -z "$picked" ] && return 0
    local -a sel_items=("${(@f)picked}")
    local def_name="${sel_items[1]%/}.tar.gz"
    printf "\033[1;36m?\033[0m Archive name [\033[1;33m%s\033[0m]: " "$def_name"
    local out_name=""
    IFS= read -r out_name
    set -- "${out_name:-$def_name}" "${sel_items[@]}"
  elif [ $# -eq 0 ]; then
    printf "\033[33mUsage: pack <archive_file> <files_or_dirs...>\033[0m\n" >&2
    return 1
  fi

  local archive="$1"
  shift

  # Shorthand: 'pack <dir>' with 1 arg and no archive extension creates '<dir>.tar.gz'
  if [ $# -eq 0 ]; then
    local clean_target="${archive%/}"
    if [ -e "$clean_target" ]; then
      set -- "$clean_target"
      archive="${clean_target}.tar.gz"
    else
      printf "\033[33mUsage: pack <archive_file> <files_or_dirs...>\033[0m\n" >&2
      return 1
    fi
  fi

  local item
  for item in "$@"; do
    if [ ! -e "$item" ]; then
      printf "\033[31m✖ Target not found: %s\033[0m\n" "$item" >&2
      return 1
    fi
  done

  local rc=1
  # :l = lowercase parameter expansion in Zsh
  case "${archive:l}" in
    *.tar.bz2|*.tbz2|*.tar.gz|*.tgz|*.tar.xz|*.txz|*.tar.zst|*.tar|*.zip|*.7z|*.gz|*.bz2|*.zst)
      if command -v ouch &>/dev/null && ouch compress -y "$@" "$archive" 2>/dev/null; then
        rc=0
      fi
      ;;
  esac

  if [ $rc -ne 0 ]; then
    case "${archive:l}" in
      *.tar.bz2|*.tbz2)   tar cjvf "$archive" "$@" ;;
      *.tar.gz|*.tgz)     tar czvf "$archive" "$@" ;;
      *.tar.xz|*.txz)     tar cJvf "$archive" "$@" ;;
      *.tar.zst)          tar --zstd -cvf "$archive" "$@" 2>/dev/null || { tar cvf - "$@" | zstd -o "$archive"; } ;;
      *.tar)              tar cvf "$archive" "$@" ;;
      *.zip)              zip -r "$archive" "$@" ;;
      *.7z)               if command -v 7zz &>/dev/null; then 7zz a "$archive" "$@"; else 7z a "$archive" "$@"; fi ;;
      *.gz)               gzip -k -c "$1" > "$archive" ;;
      *.bz2)              bzip2 -k -c "$1" > "$archive" ;;
      *.zst)              zstd -k "$1" -o "$archive" ;;
      *)
        printf "\033[31m✖ Cannot pack '%s' — unsupported archive extension.\033[0m\n" "$archive" >&2
        printf "Supported: .tar.gz, .tgz, .tar.bz2, .tbz2, .tar.xz, .txz, .tar.zst, .tar, .zip, .7z, .gz, .bz2, .zst\n" >&2
        return 1
        ;;
    esac
    rc=$?
  fi

  if [ $rc -eq 0 ] && [ -f "$archive" ]; then
    local sz
    sz=$(du -h "$archive" 2>/dev/null | awk '{print $1}')
    printf "\033[32m✔ Created archive:\033[0m \033[1m%s\033[0m (%s)\n" "$archive" "${sz:-done}"
  fi
  return $rc
}
