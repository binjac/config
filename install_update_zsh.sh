#!/bin/bash

set -e

echo "🔧 Setting up Zsh environment..."

# Detect OS type
OS_TYPE=$(uname)

# Install dependencies
if [[ "$OS_TYPE" == "Linux" ]]; then
    echo "Updating system packages..."
    sudo apt update
    sudo apt install -y zsh git curl autojump fzf eza
elif [[ "$OS_TYPE" == "Darwin" ]]; then
    echo "Updating Homebrew packages..."
    brew update
    brew install zsh git autojump fzf eza
fi

# Backup existing .zshrc if present
if [ -f "$HOME/.zshrc" ]; then
    echo "Backing up existing .zshrc to .zshrc.backup..."
    cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
fi

# Install Oh My Zsh if not present
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

# Remove any previous custom block in .zshrc
ZSHRC_BLOCK_START="#### --- Managed by binjac/config install_update_zsh.sh --- ####"
ZSHRC_BLOCK_END="#### --- End managed block --- ####"
sed -i.bak "/$ZSHRC_BLOCK_START/,/$ZSHRC_BLOCK_END/d" "$HOME/.zshrc" || true

# Append new config block
cat << 'EOF' >> "$HOME/.zshrc"
#### --- Managed by binjac/config install_update_zsh.sh --- ####

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="eastwood"

# Antigen
source $HOME/.antigen.zsh
antigen use oh-my-zsh

# Plugins
antigen bundle git
antigen bundle zsh-users/zsh-autosuggestions
antigen bundle zsh-users/zsh-history-substring-search
antigen bundle djui/alias-tips
antigen bundle rupa/z
antigen bundle junegunn/fzf
antigen bundle ssh-agent
antigen bundle Aloxaf/fzf-tab
antigen bundle zsh-users/zsh-syntax-highlighting

# Apply Antigen
antigen apply

# Oh My Zsh core
source $ZSH/oh-my-zsh.sh

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

# fzf setup (only if installed)
[ -f $HOME/.fzf.zsh ] && source $HOME/.fzf.zsh

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

#### --- End managed block --- ####
EOF

echo "Reloading Zsh configuration..."
source "$HOME/.zshrc" || true

echo "✅ Zsh setup complete! Restart your terminal or run 'exec zsh' to apply changes."
