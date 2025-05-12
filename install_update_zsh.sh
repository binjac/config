#!/bin/bash
set -e

echo "🔧 Setting up Zsh environment..."

# Detect OS type
OS_TYPE=$(uname)

# Install dependencies
if [[ "$OS_TYPE" == "Linux" ]]; then
  sudo apt update
  sudo apt install -y zsh git curl autojump fzf eza
elif [[ "$OS_TYPE" == "Darwin" ]]; then
  brew update
  brew install zsh git autojump fzf eza
fi

# Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "Installing Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" --unattended
fi

# Antigen
echo "Installing/Updating Antigen..."
curl -L git.io/antigen > "$HOME/.antigen.zsh"

# fzf
if [ ! -d "$HOME/.fzf" ]; then
  git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
  "$HOME/.fzf/install" --all
else
  cd "$HOME/.fzf" && git pull && ./install --all
fi

# Set Zsh as default shell if not already
if [ "$SHELL" != "$(which zsh)" ]; then
  chsh -s "$(which zsh)"
  echo "Default shell changed to zsh. Log out and in again for changes to take effect."
fi

# Backup .zshrc if present
if [ -f "$HOME/.zshrc" ]; then
  cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
fi

# Write new .zshrc
cat > "$HOME/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="eastwood"

source $HOME/.antigen.zsh
antigen use oh-my-zsh

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

source $ZSH/oh-my-zsh.sh

export SSH_AUTO_SPAWN="yes"
export SSH_USE_STRICT_MODE="no"
export SSH_ADD_KEYS="$HOME/.ssh/id_rsa $HOME/.ssh/id_ed25519"
if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" > /dev/null
  ssh-add "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ed25519" 2>/dev/null
fi

if [ -f /usr/share/autojump/autojump.zsh ]; then
  source /usr/share/autojump/autojump.zsh
fi

[ -f $HOME/.fzf.zsh ] && source $HOME/.fzf.zsh

alias zshconfig="nano ~/.zshrc"
alias ohmyzsh="nano ~/.oh-my-zsh"

HIST_STAMPS="yyyy-mm-dd"

zstyle ':completion:*:git-checkout:*' sort false
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' switch-group '<' '>'
EOF

# Reset and update Antigen plugins (guarantee latest + fix cache issues)
zsh -ic "antigen reset; antigen update"

echo "✅ Zsh setup complete! Restart your terminal or run 'exec zsh' to apply changes."
