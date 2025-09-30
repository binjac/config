#!/usr/bin/env bash
set -euo pipefail

echo "Setting up Zsh environment..."
OS_TYPE="$(uname)"

# ------------------------------ Backup zshrc -----------------------------------
if [[ -f "$HOME/.zshrc" ]]; then
  echo "Backing up existing .zshrc -> ~/.zshrc.backup"
  cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
fi
timestamp() { date +"%Y%m%d-%H%M%S"; }
backup_file() { [[ -f "$1" ]] && cp -p "$1" "$1.bak.$(timestamp)" && echo "Backed up $1 -> $1.bak.$(timestamp)"; }
write_file() { backup_file "$1"; printf "%s\n" "$2" > "$1"; echo "Wrote $1"; }

# ------------------------------ Helpers ----------------------------------------
ask() {
  local prompt default reply
  prompt="$1"; default="${2:-Y}"
  [[ "$default" =~ ^[Yy]$ ]] && prompt="$prompt [Y/n] " || prompt="$prompt [y/N] "
  if [[ "${INSTALL_MODE:-}" == "FULL" ]]; then
    reply="$default"
  else
    read -r -p "$prompt" reply || true
  fi
  reply="${reply:-$default}"
  case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

ensure_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    if ask "Homebrew not found. Install it now?" "N"; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
      eval "$(/opt/homebrew/bin/brew shellenv)"
    else
      echo "Homebrew not installed; skipping Homebrew-dependent steps."
    fi
  fi
}
install_pkg_brew() {
  ensure_brew
  if command -v brew >/dev/null 2>&1; then
    brew list --formula "$1" >/dev/null 2>&1 || brew install "$1"
  else
    echo "brew not found; skipping formula '$1'"
  fi
}
install_cask_brew() {
  ensure_brew
  if command -v brew >/dev/null 2>&1; then
    brew list --cask "$1" >/dev/null 2>&1 || brew install --cask "$1"
  else
    echo "brew not found; skipping cask '$1'"
  fi
}

# ------------------------------ Install mode -------------------------------------
if ask "Use FULL install mode (auto-accept defaults)?" "Y"; then
  INSTALL_MODE="FULL"
  echo "Mode: FULL (auto-accepting defaults)"
else
  INSTALL_MODE="CUSTOM"
  echo "Mode: CUSTOM (interactive prompts)"
fi

# ------------------------------ Base deps (optional) ---------------------------
if ask "Install/Update base dependencies (zsh git curl autojump fzf)?" "Y"; then
  if [[ "$OS_TYPE" == "Linux" ]]; then
    sudo apt update || true
    sudo apt install -y zsh git curl autojump fzf || true
  elif [[ "$OS_TYPE" == "Darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
      brew update || true
      install_pkg_brew zsh || true
      install_pkg_brew git || true
      install_pkg_brew autojump || true
      install_pkg_brew fzf || true
    else
      echo "Skipping base deps on macOS; Homebrew is not installed."
    fi
  fi
fi

# ------------------------------ Oh My Zsh (optional) ---------------------------
if ask "Install/Update Oh My Zsh?" "Y"; then
  if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    echo "Installing Oh My Zsh (unattended)..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended
  else
    echo "Oh My Zsh already installed."
  fi
fi

# ------------------------------ Antigen (optional) -----------------------------
if ask "Install/Update Antigen to ~/.antigen.zsh ?" "Y"; then
  curl -fsSL https://git.io/antigen > "$HOME/.antigen.zsh"
  echo "Antigen installed/updated."
fi

# ------------------------------ fzf (optional) ---------------------------------
if ask "Install/Update fzf and key-bindings?" "Y"; then
  if [[ ! -d "$HOME/.fzf" ]]; then
    git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    "$HOME/.fzf/install" --all
  else
    (cd "$HOME/.fzf" && git pull && ./install --all)
  fi
fi

# ------------------------------ Oh My Posh (optional) --------------------------
if ask "Install/Update oh-my-posh and Meslo Nerd Font?" "Y"; then
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    install_pkg_brew oh-my-posh
    install_cask_brew font-meslo-lg-nerd-font || true
  else
    if ! command -v oh-my-posh >/dev/null 2>&1; then
      curl -s https://ohmyposh.dev/install.sh | bash -s
      export PATH="$HOME/.local/bin:$PATH"
    fi
  fi
fi

# ------------------------------ FULL .zshrc (verbatim w/ $HOME) ----------------
# EXACT order, OMP at the very end, Conda paths generic with $HOME.
read -r -d '' FULL_ZSHRC <<'EOF'
# If come from bash might have to change $PATH
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH


#### Oh My Zsh ####
# Path to Oh My Zsh installation
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""


#### Antigen ####
# Load Antigen
if [ -f "$HOME/.antigen.zsh" ]; then
  source "$HOME/.antigen.zsh"

  # Use Oh My Zsh plugins
  antigen use oh-my-zsh

  # Load plugins (fzf-tab after fzf, syntax-highlighting last)
  antigen bundle git
  antigen bundle zsh-users/zsh-autosuggestions
  antigen bundle zsh-users/zsh-history-substring-search
  antigen bundle djui/alias-tips
  antigen bundle rupa/z
  antigen bundle junegunn/fzf
  antigen bundle ssh-agent
  antigen bundle Aloxaf/fzf-tab
  antigen bundle zsh-users/zsh-syntax-highlighting

  # Apply Antigen settings
  antigen apply
fi


#### SSH Agent ####
export SSH_AUTO_SPAWN="yes"
export SSH_USE_STRICT_MODE="no"
export SSH_ADD_KEYS="$HOME/.ssh/id_rsa $HOME/.ssh/id_ed25519"

if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" > /dev/null
  ssh-add "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519" 2>/dev/null
fi


#### User configuration ####
# Autojump
if [ -f /usr/share/autojump/autojump.zsh ]; then
  source /usr/share/autojump/autojump.zsh
fi

# fzf setup
[ -f $HOME/.fzf.zsh ] && source $HOME/.fzf.zsh

# Set personal aliases
alias zshconfig="nano ~/.zshrc"
alias ohmyzsh="nano ~/.oh-my-zsh"

# Enable history timestamps
HIST_STAMPS="yyyy-mm-dd"

# History substring search bindings (↑/↓)
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down


#### fzf-tab UI settings ####
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' switch-group '<' '>'


# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('$HOME/anaconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
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


#### Oh My Posh theme ####
if [[ $- == *i* ]]; then
  if command -v oh-my-posh >/dev/null 2>&1; then
    eval "$(oh-my-posh init zsh --config https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/kushal.omp.json)" || \
      PROMPT='%F{cyan}%n@%m%f:%F{yellow}%~%f %# '
  else
    PROMPT='%F{cyan}%n@%m%f:%F{yellow}%~%f %# '
  fi
fi
EOF

# ------------------------------ Modular blocks ---------------------------------
BLOCK_PATH=$'# If come from bash might have to change $PATH\n# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH\n'
BLOCK_OMZ=$'#### Oh My Zsh ####\n# Path to Oh My Zsh installation\nexport ZSH="$HOME/.oh-my-zsh"\nZSH_THEME=""\n'
BLOCK_ANTIGEN_HEADER=$'#### Antigen ####\n# Load Antigen\nif [ -f "$HOME/.antigen.zsh" ]; then\n  source "$HOME/.antigen.zsh"\n\n  # Use Oh My Zsh plugins\n  antigen use oh-my-zsh\n\n  # Load plugins (fzf-tab after fzf, syntax-highlighting last)\n'
PLUG_git=$'  antigen bundle git\n'
PLUG_autosugg=$'  antigen bundle zsh-users/zsh-autosuggestions\n'
PLUG_hist_sub=$'  antigen bundle zsh-users/zsh-history-substring-search\n'
PLUG_alias_tips=$'  antigen bundle djui/alias-tips\n'
PLUG_rupa_z=$'  antigen bundle rupa/z\n'
PLUG_fzf=$'  antigen bundle junegunn/fzf\n'
PLUG_ssh=$'  antigen bundle ssh-agent\n'
PLUG_fzf_tab=$'  antigen bundle Aloxaf/fzf-tab\n'
PLUG_syntax=$'  antigen bundle zsh-users/zsh-syntax-highlighting\n'
BLOCK_ANTIGEN_FOOTER=$'\n  # Apply Antigen settings\n  antigen apply\nfi\n'

read -r -d '' BLOCK_SSH_AGENT <<'EOF'

#### SSH Agent ####
export SSH_AUTO_SPAWN="yes"
export SSH_USE_STRICT_MODE="no"
export SSH_ADD_KEYS="$HOME/.ssh/id_rsa $HOME/.ssh/id_ed25519"

if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" > /dev/null
  ssh-add "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519" 2>/dev/null
fi
EOF

read -r -d '' BLOCK_USER_CFG <<'EOF'

#### User configuration ####
# Autojump
if [ -f /usr/share/autojump/autojump.zsh ]; then
  source /usr/share/autojump/autojump.zsh
fi

# fzf setup
[ -f $HOME/.fzf.zsh ] && source $HOME/.fzf.zsh

# Set personal aliases
alias zshconfig="nano ~/.zshrc"
alias ohmyzsh="nano ~/.oh-my-zsh"

# Enable history timestamps
HIST_STAMPS="yyyy-mm-dd"

# History substring search bindings (↑/↓)
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
EOF

read -r -d '' BLOCK_FZFTAB_UI <<'EOF'

#### fzf-tab UI settings ####
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' switch-group '<' '>'
EOF

read -r -d '' BLOCK_CONDA <<'EOF'

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('$HOME/anaconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
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

read -r -d '' BLOCK_OMP_DEFAULT <<'EOF'

#### Oh My Posh theme ####
if [[ $- == *i* ]]; then
  if command -v oh-my-posh >/dev/null 2>&1; then
    eval "$(oh-my-posh init zsh --config __OMP_URL__)" || \
      PROMPT='%F{cyan}%n@%m%f:%F{yellow}%~%f %# '
  else
    PROMPT='%F{cyan}%n@%m%f:%F{yellow}%~%f %# '
  fi
fi
EOF

# ------------------------------ Mode selection ---------------------------------
if ask "Write FULL .zshrc (verbatim with \$HOME paths)?" "Y"; then
  write_file "$HOME/.zshrc" "$FULL_ZSHRC"
else
  echo "Personalized mode — choose each section/plugin."
  out=""
  enable_hist_sub=0
  enable_fzf_tab=0

  ask "Include PATH comment block?" "Y" && out+="$BLOCK_PATH"$'\n'
  ask "Include Oh My Zsh block (ZSH path + empty theme)?" "Y" && out+="$BLOCK_OMZ"$'\n'

  if ask "Include Antigen block (plugin manager)?" "Y"; then
    out+="$BLOCK_ANTIGEN_HEADER"
    ask "Plugin: git (git aliases/completions)?" "Y" && out+="$PLUG_git"
    ask "Plugin: zsh-autosuggestions (ghost text suggestions)?" "Y" && out+="$PLUG_autosugg"
    if ask "Plugin: zsh-history-substring-search (↑/↓ search)?" "Y"; then
      out+="$PLUG_hist_sub"; enable_hist_sub=1
    fi
    ask "Plugin: djui/alias-tips (show expanded alias)?" "Y" && out+="$PLUG_alias_tips"
    ask "Plugin: rupa/z (legacy dir-jump; optional if using autojump)?" "N" && out+="$PLUG_rupa_z"
    if ask "Plugin: fzf (fuzzy finder integration)?" "Y"; then
      out+="$PLUG_fzf"
    fi
    ask "Plugin: ssh-agent (auto-load keys)?" "Y" && out+="$PLUG_ssh"
    if ask "Plugin: fzf-tab (TAB completion via fzf)?" "Y"; then
      out+="$PLUG_fzf_tab"; enable_fzf_tab=1
    fi
    ask "Plugin: zsh-syntax-highlighting (colorize CLI)?" "Y" && out+="$PLUG_syntax"
    out+="$BLOCK_ANTIGEN_FOOTER"
  fi

  ask "Include SSH Agent block?" "Y" && out+="$BLOCK_SSH_AGENT"
  ask "Include User configuration block (autojump, fzf, aliases, timestamps, bindkeys)?" "Y" && out+="$BLOCK_USER_CFG"
  (( enable_fzf_tab )) && ask "Include fzf-tab UI settings?" "Y" && out+="$BLOCK_FZFTAB_UI"
  ask "Include Conda initialize block (from \$HOME/anaconda3)?" "Y" && out+="$BLOCK_CONDA"

  # Oh My Posh MUST be last
  if ask "Include Oh My Posh theme block (init last)?" "Y"; then
    default_url="https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/kushal.omp.json"
    read -r -p "Enter oh-my-posh theme URL (blank=default): " omp_url
    omp_url="${omp_url:-$default_url}"
    omp_block="${BLOCK_OMP_DEFAULT//__OMP_URL__/$omp_url}"
    out+="$omp_block"
  fi

  write_file "$HOME/.zshrc" "$out"
fi

# ------------------------------ Extras -----------------------------------------
if ask "Install eza for fzf-tab preview (optional)?" "N"; then
  if [[ "$OS_TYPE" == "Linux" ]]; then
    sudo apt install -y eza || true
  elif [[ "$OS_TYPE" == "Darwin" ]]; then
    install_pkg_brew eza || true
  fi
fi

if command -v oh-my-posh >/dev/null 2>&1; then
  oh-my-posh enable reload >/dev/null 2>&1 || true
fi

# ------------------------------ Terminal/iTerm2 setup --------------------------
iterm_prompt_default="Y"
[[ "${INSTALL_MODE:-}" == "FULL" ]] && iterm_prompt_default="N"
if [[ "$OS_TYPE" == "Darwin" ]] && ask "Configure iTerm2 & Terminal.app profiles now?" "$iterm_prompt_default"; then
  echo "Configuring terminal profiles..."

  # iTerm2 Dynamic Profile
  read -r -p "Path to iTerm2 Dynamic Profile JSON (e.g. terminal_config/Custom.json): " ITERM_SRC_JSON
  ITERM_SRC_JSON="${ITERM_SRC_JSON:-terminal_config/Custom.json}"
  ITERM_DEST_DIR="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  if [[ -f "$ITERM_SRC_JSON" ]]; then
    mkdir -p "$ITERM_DEST_DIR"
    cp -f "$ITERM_SRC_JSON" "$ITERM_DEST_DIR/Custom.json"
    ITERM_GUID="$('/usr/bin/python3' - <<'PY'
import json,sys
p=json.load(open(sys.argv[1]))
print(p.get("Guid",""))
PY
"$ITERM_SRC_JSON")"
    if [[ -n "${ITERM_GUID}" ]]; then
      defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$ITERM_GUID"
      echo "iTerm2: Dynamic profile installed and set default (Guid=$ITERM_GUID)."
    else
      echo "iTerm2: Profile copied; no Guid found to set default."
    fi
  else
    echo "iTerm2: Skipped (file not found: $ITERM_SRC_JSON)."
  fi

  # Apple Terminal profile
  read -r -p "Path to Terminal.app profile (.terminal) (e.g. terminal_config/Custom.terminal): " TERM_SRC_FILE
  TERM_SRC_FILE="${TERM_SRC_FILE:-terminal_config/Custom.terminal}"
  if [[ -f "$TERM_SRC_FILE" ]]; then
    /usr/bin/open -g "$TERM_SRC_FILE" || true
    TERM_PROFILE_NAME="$('/usr/bin/plutil' -convert json -o - "$TERM_SRC_FILE" 2>/dev/null | /usr/bin/python3 - <<'PY'
import json,sys
data=json.load(sys.stdin)
ws=data.get("Window Settings",{})
print(next(iter(ws.keys()),""))
PY
)"
    if [[ -n "$TERM_PROFILE_NAME" ]]; then
      defaults write com.apple.Terminal "Default Window Settings" -string "$TERM_PROFILE_NAME"
      defaults write com.apple.Terminal "Startup Window Settings" -string "$TERM_PROFILE_NAME"
      echo "Terminal.app: Profile '$TERM_PROFILE_NAME' imported and set as default."
    else
      echo "Terminal.app: Could not detect profile name; profile opened/imported."
    fi
  else
    echo "Terminal.app: Skipped (file not found: $TERM_SRC_FILE)."
  fi

  # Nudge apps to reload next launch (safe if not running)
  killall iTerm2  >/dev/null 2>&1 || true
  killall Terminal >/dev/null 2>&1 || true
  echo "Profiles configured. Reopen iTerm2/Terminal to apply."
fi

# ------------------------------ Done -------------------------------------------
echo "Reloading Zsh configuration..."
# shellcheck disable=SC1090
source "$HOME/.zshrc" || echo "Configuration will be applied when you restart your terminal."
echo "✅ Zsh setup complete! Restart your terminal or run 'exec zsh' to apply."
