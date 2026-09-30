#!/usr/bin/env bash
# Modular Zsh + terminal bootstrap (macOS / Linux). Compatible with bash 3.2.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_TYPE="$(uname)"
INSTALL_MODE="${INSTALL_MODE:-}"
DRY_RUN="${DRY_RUN:-0}"
ZSHRC_ONLY=0
UPDATE=0
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-setup"
SELECTION_FILE="$CONFIG_DIR/selection.env"
GLOSSARY_DEST="$CONFIG_DIR/glossary.tsv"
ARGS=("$@")
OMP_THEME_URL="${OMP_THEME_URL:-https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/kushal.omp.json}"
OMP_THEME_NAME="$(basename "$OMP_THEME_URL")"
ITERM_JSON="$REPO_DIR/terminal_config/Custom.json"
TERMINAL_FILE="$REPO_DIR/terminal_config/Custom.terminal"

usage() {
  cat <<'EOF'
Usage: ./install_update_zsh.sh [--full | --custom] [--update] [--zshrc-only] [--dry-run]
  --full         accept the default answer to every question
  --custom       ask about every module
  --update       machine already set up: git pull this repo, reuse the modules saved on
                 this machine, only ask about new ones, then re-apply everything
  --zshrc-only   only regenerate ~/.zshrc (no install, no terminal setup)
  --dry-run      change nothing: print actions and the diff of the generated ~/.zshrc
EOF
}

for arg in "$@"; do
  case "$arg" in
    --full) INSTALL_MODE="FULL" ;;
    --custom) INSTALL_MODE="CUSTOM" ;;
    --zshrc-only) INSTALL_MODE="FULL"; ZSHRC_ONLY=1 ;;
    --update) UPDATE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

# ------------------------------ Update: pull, then re-run the fresh script ------
if [[ "$UPDATE" == "1" && "${UPDATE_PULLED:-0}" != "1" ]]; then
  echo "Updating repo $REPO_DIR ..."
  if [[ "$DRY_RUN" == "1" ]]; then echo "  [dry-run] git pull --ff-only"; git -C "$REPO_DIR" fetch -q origin || true
  elif git -C "$REPO_DIR" pull --ff-only; then :; else echo "  ! pull failed (local changes or diverged history); continuing with the local copy" >&2; fi
  UPDATE_PULLED=1 exec bash "$REPO_DIR/$(basename "${BASH_SOURCE[0]}")" "${ARGS[@]}"
fi

# ------------------------------ Helpers ----------------------------------------
dry() { [[ "$DRY_RUN" == "1" ]]; }
timestamp() { date +"%Y%m%d-%H%M%S"; }

run() {
  if dry; then echo "  [dry-run] $*"; return 0; fi
  "$@" || { echo "  ! failed: $*" >&2; return 0; }
}

ask() {
  local prompt default reply
  prompt="$1"; default="${2:-Y}"
  if [[ "$default" =~ ^[Yy]$ ]]; then prompt="$prompt [Y/n] "; else prompt="$prompt [y/N] "; fi
  if [[ "$INSTALL_MODE" == "FULL" ]]; then
    reply="$default"
  else
    read -r -p "$prompt" reply || true
  fi
  reply="${reply:-$default}"
  case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# pick <id> <label> <Y|N>: records the answer in SEL_<id>
pick() {
  local cur="SEL_$1"
  if [[ "$UPDATE" == "1" && -n "${!cur:-}" ]]; then return 0; fi
  if ask "$2" "$3"; then eval "SEL_$1=1"; else eval "SEL_$1=0"; fi
}
sel() { local v="SEL_$1"; [[ "${!v:-0}" == "1" ]]; }
skip() { eval "SEL_$1=0"; }

# need <module> <dependency>: turns the dependency on when the module is selected
need() {
  if sel "$1" && ! sel "$2"; then
    eval "SEL_$2=1"
    echo "  -> '$2' enabled (required by '$1')"
  fi
}

ensure_brew() {
  command -v brew >/dev/null 2>&1 && return 0
  if ask "Homebrew not found. Install it now?" "N"; then
    run bash -c '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    if ! dry && [[ -x /opt/homebrew/bin/brew ]]; then
      grep -qs 'brew shellenv' "$HOME/.zprofile" || echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
  else
    echo "  Homebrew not installed; Homebrew-dependent steps are skipped."
  fi
  command -v brew >/dev/null 2>&1
}

pkg() { # pkg <brew-name> [apt-name]
  local brew_name="$1" apt_name="${2:-$1}"
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    if ensure_brew; then
      if brew list --formula "$brew_name" >/dev/null 2>&1; then echo "  ok: $brew_name"; else run brew install "$brew_name"; fi
    fi
  else
    if dpkg -s "$apt_name" >/dev/null 2>&1; then echo "  ok: $apt_name"; else run sudo apt install -y "$apt_name"; fi
  fi
}

cask() { # cask <name> [app-path ...]
  local name="$1" app found=0; shift
  for app in "$@"; do [[ -d "$app" ]] && found=1; done
  if ensure_brew; then
    if [[ "$found" == "1" ]] || brew list --cask "$name" >/dev/null 2>&1; then
      echo "  ok: $name"
    else
      run brew install --cask "$name"
    fi
  fi
}

# ------------------------------ Module selection -------------------------------
echo "Setting up Zsh environment... (repo: $REPO_DIR)"
if [[ "$UPDATE" == "1" && -f "$SELECTION_FILE" ]]; then
  eval "$(grep -E '^SEL_[a-z0-9_]+=[01]$' "$SELECTION_FILE" || true)"
  echo "Reusing saved modules from $SELECTION_FILE"
  INSTALL_MODE="${INSTALL_MODE:-CUSTOM}"
fi
if [[ -z "$INSTALL_MODE" ]]; then
  if ask "Use FULL install mode (auto-accept defaults)?" "Y"; then INSTALL_MODE="FULL"; else INSTALL_MODE="CUSTOM"; fi
fi
echo "Mode: $INSTALL_MODE$([[ "$UPDATE" == "1" ]] && echo ' + update')$(dry && echo ' (dry-run)')"

echo; echo "== Tools =="
pick base    "Base dependencies (zsh git curl)?" "Y"
pick fzf     "fzf (fuzzy finder, Ctrl-R, key-bindings)?" "Y"
pick zoxide  "zoxide (smarter cd: z / zi)?" "Y"
pick eza     "eza (fzf-tab directory preview)?" "Y"
pick omp     "oh-my-posh prompt (theme: $OMP_THEME_NAME)?" "Y"
pick font    "Meslo Nerd Font (glyphs for the prompt)?" "Y"
pick bat     "bat (cat with syntax highlighting, fzf preview)?" "Y"
pick fd      "fd (fast find, feeds fzf)?" "Y"
pick atuin   "atuin (searchable shell history, owns Ctrl-R)?" "Y"
pick delta   "git-delta (readable git diffs, via a git include file)?" "Y"
pick lazygit "lazygit (git terminal UI, alias lg)?" "Y"
pick mise    "mise (per-project tool versions: Java, Terraform, ...)?" "Y"
pick direnv  "direnv (per-directory env vars via .envrc)?" "Y"

echo; echo "== Zsh framework =="
pick omz     "Oh My Zsh?" "Y"
pick antigen "Antigen plugin manager (required for the plugins below)?" "Y"

if sel antigen; then
  echo; echo "== Plugins =="
  pick p_git      "git (aliases/completions)?" "Y"
  pick p_autosug  "zsh-autosuggestions (ghost text)?" "Y"
  pick p_histsub  "zsh-history-substring-search (up/down)?" "Y"
  pick p_aliastip "alias-tips (shows the alias you could have used)?" "Y"
  pick p_fzf      "junegunn/fzf plugin?" "Y"
  pick p_ssh      "ssh-agent (loads id_ed25519)?" "Y"
  pick p_fzftab   "fzf-tab (fzf-powered TAB completion)?" "Y"
  pick p_synhl    "zsh-syntax-highlighting?" "Y"
else
  for m in p_git p_autosug p_histsub p_aliastip p_fzf p_ssh p_fzftab p_synhl; do skip "$m"; done
fi

echo; echo "== Shell config =="
conda_default="N"; [[ -d "$HOME/anaconda3" ]] && conda_default="Y"
pick conda   "Conda init block (\$HOME/anaconda3)?" "$conda_default"
pick vscode  "VS Code guard (skip prompt/plugins while VS Code resolves its env)?" "Y"
pick usercfg "Personal aliases, history timestamps, key bindings?" "Y"
pick zhelp   "zhelp command (glossary of aliases, keys and tools)?" "Y"

if [[ "$OS_TYPE" == "Darwin" && "$ZSHRC_ONLY" == "0" ]]; then
  echo; echo "== Terminal apps =="
  pick iterm2      "Install iTerm2 and set up the Custom profile?" "Y"
  pick terminalapp "Import the Terminal.app Custom profile?" "Y"
else
  skip iterm2; skip terminalapp
fi

# Dependencies
need p_fzf fzf
need p_fzftab fzf
need iterm2 font
need terminalapp font

# ------------------------------ zshrc generation -------------------------------
emit_zshrc() {
  cat <<'EOF'
# If come from bash might have to change $PATH
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH
EOF

  if sel conda; then cat <<'EOF'


# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$("$HOME/anaconda3/bin/conda" 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="$HOME/anaconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<
EOF
  fi

  if sel mise; then cat <<'EOF'


#### mise ####
command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"
EOF
  fi

  if sel vscode; then cat <<'EOF'


#### VS Code ####
# VS Code resolves its env with a tty-less login shell: stop here, nothing below sets env
[[ -n "${VSCODE_RESOLVING_ENVIRONMENT:-}" ]] && return
EOF
  fi

  if sel omz; then cat <<'EOF'


#### Oh My Zsh ####
# Path to Oh My Zsh installation
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
EOF
  fi

  if sel p_ssh; then cat <<'EOF'


#### SSH Agent ####
zstyle ':omz:plugins:ssh-agent' identities id_ed25519
zstyle ':omz:plugins:ssh-agent' quiet yes
EOF
  fi

  if sel antigen; then
    cat <<'EOF'


#### Antigen ####
# Load Antigen
if [ -f "$HOME/.antigen.zsh" ]; then
  source "$HOME/.antigen.zsh"

  # Use Oh My Zsh plugins
  antigen use oh-my-zsh

  # Load plugins (fzf-tab after fzf, syntax-highlighting last)
EOF
    if sel p_git;      then echo "  antigen bundle git"; fi
    if sel p_autosug;  then echo "  antigen bundle zsh-users/zsh-autosuggestions"; fi
    if sel p_histsub;  then echo "  antigen bundle zsh-users/zsh-history-substring-search"; fi
    if sel p_aliastip; then echo "  antigen bundle djui/alias-tips"; fi
    if sel p_fzf;      then echo "  antigen bundle junegunn/fzf"; fi
    if sel p_ssh;      then echo "  antigen bundle ssh-agent"; fi
    if sel p_fzftab;   then echo "  antigen bundle Aloxaf/fzf-tab"; fi
    if sel p_synhl;    then echo "  antigen bundle zsh-users/zsh-syntax-highlighting"; fi
    cat <<'EOF'

  # Apply Antigen settings
  antigen apply
fi
EOF
  fi

  printf '\n\n#### User configuration ####\n'
  if [[ "$OS_TYPE" == "Linux" ]]; then
    if sel bat; then echo 'command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1 && alias bat=batcat'; fi
    if sel fd;  then echo 'command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1 && alias fd=fdfind'; fi
  fi
  if sel fzf && sel fd; then cat <<'EOF'
# fzf x fd: list files/dirs with fd (hidden files included, .git excluded)
if command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
fi
EOF
  fi
  if sel fzf && sel bat; then cat <<'EOF'
command -v bat >/dev/null 2>&1 && export FZF_CTRL_T_OPTS="--preview 'bat -n --color=always --line-range :200 {}'"
EOF
  fi
  if sel fzf; then cat <<'EOF'
# fzf setup
[ -f $HOME/.fzf.zsh ] && source $HOME/.fzf.zsh
EOF
  fi
  if sel zoxide; then cat <<'EOF'

# zoxide (z / zi)
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
EOF
  fi
  if sel atuin; then cat <<'EOF'

# atuin owns Ctrl-R (after fzf); Up/Down stay with history-substring-search
command -v atuin >/dev/null 2>&1 && eval "$(atuin init zsh --disable-up-arrow)"
EOF
  fi
  if sel direnv; then cat <<'EOF'

# direnv (.envrc per directory)
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"
EOF
  fi
  if sel lazygit; then cat <<'EOF'

alias lg=lazygit
EOF
  fi
  if sel usercfg; then cat <<'EOF'

# Set personal aliases
alias zshconfig="nano ~/.zshrc"
alias ohmyzsh="nano ~/.oh-my-zsh"

# Enable history timestamps
HIST_STAMPS="yyyy-mm-dd"
EOF
    if sel p_histsub; then cat <<'EOF'

# History substring search bindings (↑/↓)
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
EOF
    fi
  fi

  if sel p_fzftab; then
    cat <<'EOF'


#### fzf-tab UI settings ####
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' menu no
EOF
    if sel eza; then echo "zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always \$realpath'"; fi
    cat <<'EOF'
zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' switch-group '<' '>'
EOF
  fi

  if sel zhelp; then cat <<'EOF'


#### zhelp ####
zhelp() {
  local g="$HOME/.config/zsh-setup/glossary.tsv" fmt='{printf "%-6s %-26s %s\n", $2, $3, $4}'
  [[ -f "$g" ]] || { echo "zhelp: $g missing (run install_update_zsh.sh --update)"; return 1; }
  if [[ -n "$1" ]]; then
    echo "-- glossary --"; grep -i -- "$*" "$g" | awk -F'\t' "$fmt"
    echo "-- aliases --"; alias | grep -i -- "$*"
    echo "-- functions --"; print -l ${(k)functions} | grep -v '^_' | grep -i -- "$*" | head -20
  elif command -v fzf >/dev/null 2>&1; then
    awk -F'\t' "$fmt" "$g" | fzf --prompt='zhelp> ' --no-sort
  else
    awk -F'\t' "$fmt" "$g" | ${PAGER:-less}
  fi
}
EOF
  fi

  # Oh My Posh must stay last
  if sel omp; then
    printf '\n\n#### Oh My Posh theme ####\n'
    printf 'if [[ $- == *i* ]]; then\n'
    printf '  if command -v oh-my-posh >/dev/null 2>&1; then\n'
    printf '    __omp_cfg="$HOME/.config/oh-my-posh/%s"\n' "$OMP_THEME_NAME"
    printf '    [[ -f "$__omp_cfg" ]] || __omp_cfg="%s"\n' "$OMP_THEME_URL"
    printf '    eval "$(oh-my-posh init zsh --config "$__omp_cfg")" || \\\n'
    printf "      PROMPT='%%F{cyan}%%n@%%m%%f:%%F{yellow}%%~%%f %%# '\n"
    printf '    unset __omp_cfg\n'
    printf '  else\n'
    printf "    PROMPT='%%F{cyan}%%n@%%m%%f:%%F{yellow}%%~%%f %%# '\n"
    printf '  fi\n'
    printf 'fi\n'
  fi
}

write_zshrc() {
  local target="$HOME/.zshrc" tmp
  tmp="$(mktemp)"
  emit_zshrc > "$tmp"
  if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
    echo "~/.zshrc already up to date."
  elif dry; then
    echo "[dry-run] ~/.zshrc would change:"
    diff -u "$target" "$tmp" || true
  else
    if [[ "$UPDATE" == "1" && -f "$target" ]]; then diff -u "$target" "$tmp" || true; fi
    if [[ -f "$target" ]]; then
      cp -p "$target" "$target.bak.$(timestamp)"
      echo "Backed up ~/.zshrc -> ~/.zshrc.bak.*"
    fi
    cp "$tmp" "$target"
    echo "Wrote ~/.zshrc"
  fi
  rm -f "$tmp"
}

# ------------------------------ Installs ---------------------------------------
if [[ "$ZSHRC_ONLY" == "0" ]]; then
  echo; echo "== Installing =="

  if sel base; then
    if [[ "$OS_TYPE" == "Linux" ]]; then run sudo apt update; fi
    for t in zsh git curl; do
      if command -v "$t" >/dev/null 2>&1; then echo "  ok: $t"; else pkg "$t"; fi
    done
  fi

  if sel omz; then
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
      echo "  ok: Oh My Zsh"
    else
      run bash -c 'curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | sh -s -- --unattended'
    fi
  fi

  if sel antigen; then
    if dry; then echo "  [dry-run] curl -fsSL https://git.io/antigen > ~/.antigen.zsh"; else curl -fsSL https://git.io/antigen > "$HOME/.antigen.zsh"; fi
  fi

  if sel fzf; then
    if [[ -d "$HOME/.fzf" ]]; then
      run git -C "$HOME/.fzf" pull --ff-only
    else
      run git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    fi
    run "$HOME/.fzf/install" --key-bindings --completion --no-update-rc
  fi

  if sel zoxide; then
    pkg zoxide
    if command -v zoxide >/dev/null 2>&1 && [[ -f "$HOME/.z" && ! -f "$HOME/Library/Application Support/zoxide/db.zo" && ! -f "$HOME/.local/share/zoxide/db.zo" ]]; then
      run zoxide import z
    fi
  fi

  if sel eza; then pkg eza; fi
  if sel bat; then pkg bat; fi
  if sel fd; then pkg fd fd-find; fi
  if sel atuin; then pkg atuin; fi
  if sel delta; then pkg git-delta; fi
  if sel lazygit; then pkg lazygit; fi
  if sel mise; then pkg mise; fi
  if sel direnv; then pkg direnv; fi

  if sel omp; then
    if [[ "$OS_TYPE" == "Darwin" ]]; then
      pkg oh-my-posh
    elif ! command -v oh-my-posh >/dev/null 2>&1; then
      run bash -c 'curl -s https://ohmyposh.dev/install.sh | bash -s'
    fi
    run mkdir -p "$HOME/.config/oh-my-posh"
    run curl -fsSL "$OMP_THEME_URL" -o "$HOME/.config/oh-my-posh/$OMP_THEME_NAME"
  fi

  if sel font && [[ "$OS_TYPE" == "Darwin" ]]; then cask font-meslo-lg-nerd-font; fi
fi

sync_file() { # sync_file <src> <dest> <label>
  if [[ -f "$2" ]] && cmp -s "$1" "$2"; then
    echo "$3 already up to date."
  elif dry; then
    echo "[dry-run] $3 would be written to $2"
  else
    mkdir -p "$(dirname "$2")"; cp "$1" "$2"; echo "Wrote $3 ($2)"
  fi
}

write_glossary() {
  local tmp mod kind name desc
  tmp="$(mktemp)"
  while IFS=$'\t' read -r mod kind name desc; do
    if [[ -z "$mod" || "$mod" == \#* ]]; then continue; fi
    if [[ "$mod" == "core" ]] || sel "$mod"; then printf '%s\t%s\t%s\t%s\n' "$mod" "$kind" "$name" "$desc" >> "$tmp"; fi
  done < "$REPO_DIR/share/glossary.tsv"
  sync_file "$tmp" "$GLOSSARY_DEST" "zhelp glossary"
  rm -f "$tmp"
}

setup_delta() {
  local dest="$CONFIG_DIR/delta.gitconfig"
  sync_file "$REPO_DIR/share/delta.gitconfig" "$dest" "delta git config"
  if git config --global --get-all include.path 2>/dev/null | grep -qxF "$dest"; then
    echo "  git include.path already set."
  else
    run git config --global --add include.path "$dest"
  fi
}

import_atuin_history() {
  if command -v atuin >/dev/null 2>&1 && [[ -f "$HOME/.zsh_history" && ! -f "$CONFIG_DIR/atuin-imported" ]]; then
    run atuin import zsh
    if ! dry; then mkdir -p "$CONFIG_DIR"; touch "$CONFIG_DIR/atuin-imported"; fi
  fi
}

echo; echo "== Zsh config =="
write_zshrc
if sel zhelp; then write_glossary; fi
if [[ "$ZSHRC_ONLY" == "0" ]]; then
  if sel delta; then setup_delta; fi
  if sel atuin; then import_atuin_history; fi
fi

# ------------------------------ Terminal apps ----------------------------------
if sel iterm2; then
  echo; echo "== iTerm2 =="
  cask iterm2 /Applications/iTerm.app "$HOME/Applications/iTerm.app"
  if [[ -f "$ITERM_JSON" ]]; then
    dest_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
    guid="$(plutil -extract Guid raw -o - "$ITERM_JSON")"
    home_escaped="${HOME//\//\\/}"
    if defaults read com.googlecode.iterm2 "New Bookmarks" 2>/dev/null | grep -q "Guid = \"$guid\""; then
      echo "  Profile $guid already in iTerm2 preferences; Dynamic Profile skipped."
      dry || defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$guid"
    elif dry; then
      echo "  [dry-run] wrap $ITERM_JSON as a Dynamic Profile -> $dest_dir/Custom.json (Guid=$guid)"
      echo "  [dry-run] defaults write com.googlecode.iterm2 \"Default Bookmark Guid\" -string $guid"
    else
      mkdir -p "$dest_dir"
      { printf '{"Profiles":['; sed "s#\"Working Directory\" : \"[^\"]*\"#\"Working Directory\" : \"$home_escaped\"#" "$ITERM_JSON"; printf ']}\n'; } > "$dest_dir/Custom.json"
      defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$guid"
      echo "  Dynamic profile installed and set as default (Guid=$guid). Restart iTerm2."
    fi
  else
    echo "  Skipped: $ITERM_JSON not found."
  fi
fi

if sel terminalapp; then
  echo; echo "== Terminal.app =="
  if [[ -f "$TERMINAL_FILE" ]]; then
    profile_name="$(plutil -extract name raw -o - "$TERMINAL_FILE" 2>/dev/null || true)"
    run /usr/bin/open -g "$TERMINAL_FILE"
    if [[ -n "$profile_name" ]]; then
      run defaults write com.apple.Terminal "Default Window Settings" -string "$profile_name"
      run defaults write com.apple.Terminal "Startup Window Settings" -string "$profile_name"
      echo "  Profile '$profile_name' imported and set as default. Reopen Terminal.app."
    else
      echo "  Profile opened/imported; name not detected."
    fi
  else
    echo "  Skipped: $TERMINAL_FILE not found."
  fi
fi

# ------------------------------ Save selection ---------------------------------
if [[ "$ZSHRC_ONLY" == "0" ]] && ! dry; then
  mkdir -p "$(dirname "$SELECTION_FILE")"
  (set | grep -E '^SEL_[a-z0-9_]+=[01]$' || true) > "$SELECTION_FILE"
  echo "Saved module selection -> $SELECTION_FILE"
fi

# ------------------------------ Done -------------------------------------------
if [[ "$ZSHRC_ONLY" == "0" ]] && sel omp && command -v oh-my-posh >/dev/null 2>&1; then
  run oh-my-posh enable reload
fi
echo; echo "Done. Restart your terminal or run 'exec zsh' to apply."
