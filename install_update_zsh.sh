#!/usr/bin/env bash
set -euo pipefail

echo "Setting up Zsh environment..."

OS_TYPE="$(uname)"

# ------------------------------ Base deps --------------------------------------
if [[ "$OS_TYPE" == "Linux" ]]; then
  echo "Updating system packages..."
  sudo apt update
  sudo apt install -y zsh git curl autojump fzf || true
elif [[ "$OS_TYPE" == "Darwin" ]]; then
  echo "Updating Homebrew packages..."
  brew update
  brew install zsh git autojump fzf
fi

# ------------------------------ Backup zshrc -----------------------------------
if [[ -f "$HOME/.zshrc" ]]; then
  echo "Backing up existing .zshrc -> ~/.zshrc.backup"
  cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
fi

# ------------------------------ Oh My Zsh --------------------------------------
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  echo "Installing Oh My Zsh (unattended)..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended
else
  echo "Oh My Zsh already installed."
fi

# ------------------------------ Antigen ----------------------------------------
echo "Installing/Updating Antigen..."
curl -fsSL https://git.io/antigen > "$HOME/.antigen.zsh"

# ------------------------------ fzf --------------------------------------------
if [[ ! -d "$HOME/.fzf" ]]; then
  echo "Installing fzf..."
  git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
  "$HOME/.fzf/install" --all
else
  echo "Updating fzf..."
  (cd "$HOME/.fzf" && git pull && ./install --all)
fi

# ------------------------------ Oh My Posh -------------------------------------
if [[ "$OS_TYPE" == "Darwin" ]]; then
  brew list --formula oh-my-posh >/dev/null 2>&1 || brew install oh-my-posh
  brew list --cask font-meslo-lg-nerd-font >/dev/null 2>&1 || brew install --cask font-meslo-lg-nerd-font
elif [[ "$OS_TYPE" == "Linux" ]]; then
  if ! command -v oh-my-posh >/dev/null 2>&1; then
    curl -s https://ohmyposh.dev/install.sh | bash -s
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

# ------------------------------ Write .zshrc -----------------------------------
echo "Creating new .zshrc with your configuration..."

cat > ~/.zshrc << 'EOF'
# If come from bash might have to change $PATH
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

#### Oh My Zsh ####
export ZSH="$HOME/.oh-my-zsh"
# Disable OMZ prompt; oh-my-posh will render it
ZSH_THEME=""

#### Antigen ####
source "$HOME/.antigen.zsh"

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

# Load Oh My Zsh
source "$ZSH/oh-my-zsh.sh"

# Oh My Posh theme (Kushal)
eval "$(oh-my-posh init zsh --config https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/kushal.omp.json)"

#### SSH Agent ####
export SSH_AUTO_SPAWN="yes"
export SSH_USE_STRICT_MODE="no"
export SSH_ADD_KEYS="$HOME/.ssh/id_rsa $HOME/.ssh/id_ed25519"

if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" > /dev/null
  ssh-add "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519" 2>/dev/null || true
fi

#### User configuration ####
# Autojump (Linux path)
if [ -f /usr/share/autojump/autojump.zsh ]; then
    source /usr/share/autojump/autojump.zsh
fi

# fzf setup (only if installed)
[ -f "$HOME/.fzf.zsh" ] && source "$HOME/.fzf.zsh"

# Aliases
alias zshconfig="nano ~/.zshrc"
alias ohmyzsh="nano ~/.oh-my-zsh"

# History timestamps
HIST_STAMPS="yyyy-mm-dd"

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
if [[ -f "$HOME/anaconda3/bin/conda" ]]; then
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
fi
# <<< conda initialize <<<
EOF

# ------------------------------ Extras -----------------------------------------
# eza for previews
if [[ "$OS_TYPE" == "Linux" ]]; then
  command -v eza >/dev/null 2>&1 || sudo apt install -y eza || true
elif [[ "$OS_TYPE" == "Darwin" ]]; then
  command -v eza >/dev/null 2>&1 || brew install eza
fi

# Enable live reload if OMP present
if command -v oh-my-posh >/dev/null 2>&1; then
  oh-my-posh enable reload >/dev/null 2>&1 || true
fi

# ------------------------------ macOS profiles ---------------------------------
if [[ "$OS_TYPE" == "Darwin" ]]; then
  echo "Configuring terminal profiles (iTerm2 & Terminal.app)..."

  # iTerm2 Dynamic Profile
  ITERM_SRC_JSON="${PWD}/terminal_config/Custom.json"
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
    if [[ -n "$ITERM_GUID" ]]; then
      defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$ITERM_GUID"
      echo "iTerm2: Dynamic profile installed and set default (Guid=$ITERM_GUID)."
    else
      echo "iTerm2: Warning - no Guid found in Custom.json; profile copied but not set default."
    fi
  else
    echo "iTerm2: Skipped (terminal_config/Custom.json not found)."
  fi

  # Apple Terminal profile (.terminal)
  TERM_SRC_FILE="${PWD}/terminal_config/Custom.terminal"
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
      echo "Terminal.app: Warning - could not detect profile name in Custom.terminal."
    fi
  else
    echo "Terminal.app: Skipped (terminal_config/Custom.terminal not found)."
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

echo "✅ Zsh setup complete! Your configuration has been deployed."
echo "Restart your terminal or run 'exec zsh' to apply all changes."
