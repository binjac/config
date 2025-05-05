#!/bin/bash

set -e

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

# Install or update Antigen
echo "Installing/Updating Antigen..."
curl -L git.io/antigen > "$HOME/.antigen.zsh"

# Install or update fzf
if [ ! -d "$HOME/.fzf" ]; then
    echo "Installing fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    "$HOME/.fzf/install" --all
else
    echo "Updating fzf..."
    cd "$HOME/.fzf" && git pull && ./install --all
fi

# Set Zsh as default shell if not already
if [ "$SHELL" != "$(which zsh)" ]; then
    chsh -s "$(which zsh)"
    echo "Default shell changed to zsh. Log out and log in again for changes to take effect."
fi

# Block to append to .zshrc
ZSHRC_BLOCK_START="#### --- Custom Zsh Setup from binjac/config --- ####"
ZSHRC_BLOCK_END="#### --- End Custom Zsh Setup --- ####"

# Remove previous block if present
sed -i.bak "/$ZSHRC_BLOCK_START/,/$ZSHRC_BLOCK_END/d" "$HOME/.zshrc"

cat << 'EOF' >> "$HOME/.zshrc"
#### --- Custom Zsh Setup from binjac/config --- ####

# Path to Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="eastwood"

# Load Antigen
source "$HOME/.antigen.zsh"
antigen use oh-my-zsh

# Load plugins (load fzf before fzf-tab, syntax-highlighting last)
antigen bundle git
antigen bundle zsh-users/zsh-autosuggestions
antigen bundle zsh-users/zsh-history-substring-search
antigen bundle djui/alias-tips
antigen bundle rupa/z
antigen bundle junegunn/fzf
antigen bundle ssh-agent
antigen bundle Aloxaf/fzf-tab
antigen bundle zsh-users/zsh-syntax-highlighting

antigen apply

# Load Oh My Zsh
source "$ZSH/oh-my-zsh.sh"

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
[ -f /usr/share/autojump/autojump.zsh ] && source /usr/share/autojump/autojump.zsh

# fzf
[ -f "$HOME/.fzf.zsh" ] && source "$HOME/.fzf.zsh"

# Personal Aliases
alias zshconfig="nano ~/.zshrc"
alias ohmyzsh="nano ~/.oh-my-zsh"

# Enable history timestamps
HIST_STAMPS="yyyy-mm-dd"

# fzf-tab UI settings
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*:messages' format '%d'
zstyle ':completion:*:warnings' format 'No matches for: %d'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':fzf-tab:complete:_zlua:*' query-string input
zstyle ':fzf-tab:*' fzf-preview 'head -200 {}'

EOF

echo "Reloading Zsh configuration..."
source "$HOME/.zshrc" || true

echo "✅ Zsh setup complete! Restart your terminal or run 'exec zsh' to apply changes."
