#!/bin/bash

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

# Install Oh My Zsh if not installed
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended
else
    echo "Oh My Zsh already installed."
fi

# Install Antigen
echo "Installing/Updating Antigen..."
curl -L git.io/antigen > ~/.antigen.zsh

# Install or update fzf
if [ ! -d "$HOME/.fzf" ]; then
    echo "Installing fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all
else
    echo "Updating fzf..."
    cd ~/.fzf && git pull && ./install --all
fi

# Use $HOME/config not $HOME/install
DOTFILES="$HOME/config"

echo "Appending Zsh configuration to .zshrc..."

cat << 'EOF' >> ~/.zshrc

#### --- Custom Zsh Setup from binjac/config --- ####

# Path to Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="eastwood"

# Load Antigen
source ~/.antigen.zsh

antigen use oh-my-zsh

# Load plugins
antigen bundle git
antigen bundle zsh-users/zsh-autosuggestions
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle djui/alias-tips
antigen bundle rupa/z
antigen bundle junegunn/fzf
antigen bundle ssh-agent
antigen bundle zsh-users/zsh-history-substring-search

antigen apply

# Load Oh My Zsh
source $ZSH/oh-my-zsh.sh

#### SSH Agent ####

export SSH_AUTO_SPAWN="yes"
export SSH_USE_STRICT_MODE="no"
export SSH_ADD_KEYS="~/.ssh/id_rsa ~/.ssh/id_ed25519"

if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" > /dev/null
  ssh-add ~/.ssh/id_rsa ~/.ssh/id_ed25519 2>/dev/null
fi

#### User configuration ####

# Autojump
[ -f /usr/share/autojump/autojump.zsh ] && source /usr/share/autojump/autojump.zsh

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Personal Aliases
alias zshconfig="nano ~/.zshrc"
alias ohmyzsh="nano ~/.oh-my-zsh"

# Enable history timestamps
HIST_STAMPS="yyyy-mm-dd"

EOF

echo "Reloading Zsh configuration..."
source ~/.zshrc

echo "✅ Zsh setup complete! Restart your terminal or run 'exec zsh' to apply changes."
