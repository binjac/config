#!/bin/bash
set -euo pipefail

echo "Setting up Zsh environment safely..."

# Detect OS
OS_TYPE=$(uname)

# Install system dependencies
if [[ "$OS_TYPE" == "Linux" ]]; then
    echo "Updating system packages..."
    sudo apt update && sudo apt install -y zsh git curl autojump fzf
elif [[ "$OS_TYPE" == "Darwin" ]]; then
    echo "Updating Homebrew packages..."
    brew update && brew install zsh git autojump fzf
fi

# Backup existing .zshrc
if [ -f "$HOME/.zshrc" ]; then
    echo "Backing up existing .zshrc to .zshrc.backup..."
    cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
fi

#### Install Oh My Zsh if not installed ####
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended
else
    echo "Oh My Zsh already installed."
fi

#### Install Antigen ####
echo "Installing/Updating Antigen..."
curl -fsSL https://git.io/antigen > "$HOME/.antigen.zsh"

#### Install or update fzf ####
if [ ! -d "$HOME/.fzf" ]; then
    echo "Installing fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    "$HOME/.fzf/install" --all
else
    echo "Updating fzf..."
    (cd "$HOME/.fzf" && git pull && ./install --all)
fi

#### Install Oh My Posh ####
if [[ "$OS_TYPE" == "Darwin" ]]; then
  # Install oh-my-posh + Nerd Font (for icons)
  brew list --formula oh-my-posh >/dev/null 2>&1 || brew install oh-my-posh
  brew tap homebrew/cask-fonts >/dev/null 2>&1 || true
  brew list --cask font-meslo-lg-nerd-font >/dev/null 2>&1 || brew install --cask font-meslo-lg-nerd-font
elif [[ "$OS_TYPE" == "Linux" ]]; then
  if ! command -v oh-my-posh >/dev/null 2>&1; then
    curl -s https://ohmyposh.dev/install.sh | bash -s
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

echo "Creating new .zshrc with your configuration..."

cat > ~/.zshrc << 'EOF'
# If come from bash might have to change $PATH
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

#### Oh My Zsh ####
# Path to Oh My Zsh installation
export ZSH="$HOME/.oh-my-zsh"
# Disable OMZ prompt; oh-my-posh will render it
ZSH_THEME=""

#### Antigen ####
# Load Antigen
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

# Load Oh My Zsh
source "$ZSH/oh-my-zsh.sh"

# Oh My Posh theme (Kushal; use stable main raw URL)
eval "$(oh-my-posh init zsh --config https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/kushal.omp.json)"

#### SSH Agent ####
export SSH_AUTO_SPAWN="yes"
export SSH_USE_STRICT_MODE="no"
export SSH_ADD_KEYS="$HOME/.ssh/id_rsa $HOME/.ssh/id_ed25519"

if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" > /dev/null
  ssh-add "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519" 2>/dev/null
fi

#### User configuration ####
# Autojump (Linux path)
if [ -f /usr/share/autojump/autojump.zsh ]; then
    source /usr/share/autojump/autojump.zsh
fi

# fzf setup (only if installed)
[ -f "$HOME/.fzf.zsh" ] && source "$HOME/.fzf.zsh"

# Set personal aliases
alias zshconfig="nano ~/.zshrc"
alias ohmyzsh="nano ~/.oh-my-zsh"

# Enable history timestamps
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
# !! Contents within this block are managed by 'conda init' !!
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

# Install eza if not installed (for fzf-tab preview)
if [[ "$OS_TYPE" == "Linux" ]]; then
    if ! command -v eza &> /dev/null; then
        echo "Installing eza for directory previews..."
        sudo apt install -y eza || echo "eza not available in repositories. You may need to install it manually."
    fi
elif [[ "$OS_TYPE" == "Darwin" ]]; then
    if ! command -v eza &> /dev/null; then
        echo "Installing eza for directory previews..."
        brew install eza
    fi
fi

# Enable live reload if OMP present
if command -v oh-my-posh >/dev/null 2>&1; then
  oh-my-posh enable reload >/dev/null 2>&1 || true
fi

echo "Reloading Zsh configuration..."
# shellcheck disable=SC1090
source ~/.zshrc || echo "Configuration will be applied when you restart your terminal."

echo "✅ Zsh setup complete! Your configuration has been deployed."
echo "Restart your terminal or run 'exec zsh' to apply all changes."
