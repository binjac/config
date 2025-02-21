#!/bin/bash

echo "Setting up Zsh environment..."

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

# Install Oh My Zsh if not installed
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended
fi

# Install Antigen
echo "Installing/Updating Antigen..."
curl -L git.io/antigen > ~/.antigen.zsh

# Install fzf if not installed
if [ ! -d "$HOME/.fzf" ]; then
    echo "Installing fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all
else
    echo "Updating fzf..."
    cd ~/.fzf && git pull && ./install --all
fi

# Write Zsh configuration
echo "Configuring Zsh with Antigen..."
cat << EOF > ~/.zshrc
# Path to Oh My Zsh
export ZSH="\$HOME/.oh-my-zsh"

# Set the theme
ZSH_THEME="eastwood"

# Load Antigen
source ~/.antigen.zsh

# Use Oh My Zsh plugins
antigen use oh-my-zsh

# Load plugins
antigen bundle git
antigen bundle zsh-users/zsh-autosuggestions
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle djui/alias-tips
antigen bundle rupa/z
antigen bundle junegunn/fzf

# Apply Antigen settings
antigen apply

# Load Oh My Zsh (already included with Antigen, but keep it if needed)
source \$ZSH/oh-my-zsh.sh

# Autojump
if [ -f /usr/share/autojump/autojump.zsh ]; then
    source /usr/share/autojump/autojump.zsh
fi

# fzf setup (only if installed)
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Set personal aliases
alias zshconfig="nano ~/.zshrc"
alias ohmyzsh="nano ~/.oh-my-zsh"

# Enable history timestamps
HIST_STAMPS="yyyy-mm-dd"
EOF

# Reload Zsh
echo "Reloading Zsh configuration..."
source ~/.zshrc

echo "Zsh setup complete! Restart your terminal or run 'exec zsh' to apply changes."

