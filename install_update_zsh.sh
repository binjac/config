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
echo "Configuring Zsh with Antigen and SSH Agent..."
cat << EOF > ~/.zshrc
#### Oh My Zsh ####
# Path to Oh My Zsh installation
export ZSH="\$HOME/.oh-my-zsh"

# Set name of the theme to load
ZSH_THEME="eastwood"


#### Antigen ####
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
antigen bundle ssh-agent

# Apply Antigen settings
antigen apply

# Load Oh My Zsh
source \$ZSH/oh-my-zsh.sh


#### SSH Agent ####
# SSH Agent Setup
export SSH_AUTO_SPAWN="yes"
export SSH_USE_STRICT_MODE="no"
export SSH_ADD_KEYS="~/.ssh/id_rsa ~/.ssh/id_ed25519"

if [ -z "\$SSH_AUTH_SOCK" ]; then
  eval "\$(ssh-agent -s)" > /dev/null
  ssh-add ~/.ssh/id_rsa ~/.ssh/id_ed25519 2>/dev/null
fi


#### User configuration ####
# Autojump
if [ -f /usr/share/autojump/autojump.zsh ]; then
    source /usr/share/autojump/autojump.zsh
fi

# fzf setup (only if installed)
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Set personal aliases (Optional, modify as needed)
alias zshconfig="nano ~/.zshrc"
alias ohmyzsh="nano ~/.oh-my-zsh"

# Enable history timestamps
HIST_STAMPS="yyyy-mm-dd"

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="\$(/Users/valentin.binjacar/anaconda3/bin/conda 'shell.zsh' 'hook' 2> /dev/null)"
if [ \$? -eq 0 ]; then
    eval "\$__conda_setup"
else
    if [ -f "/Users/valentin.binjacar/anaconda3/etc/profile.d/conda.sh" ]; then
        . "/Users/valentin.binjacar/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="/Users/valentin.binjacar/anaconda3/bin:\$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<
EOF

# Reload Zsh
echo "Reloading Zsh configuration..."
source ~/.zshrc

echo "Zsh setup complete! Restart your terminal or run 'exec zsh' to apply changes."
