## Terminal Setup

This repo bootstraps a consistent Zsh+iTerm2 environment on macOS or Linux.

## Installation
```sh
git clone https://github.com/binjac/config.git ~/config
cd ~/config
chmod +x install_update_zsh.sh
./install_update_zsh.sh
cd ~
rm -rf ~/config
exec zsh
```

### Prompt: Oh My Posh

- **Engine:** [oh-my-posh](https://ohmyposh.dev/)
- **Theme (default):** `easy-term` (set via `OMP_THEME_URL`, defaults to the raw URL from OMP’s repo)
- **Why OMP?** Fast, portable, themeable JSON config, great glyph support with Nerd Fonts.

**Switch theme:**  
Change the env var when running the installer, e.g.:
```bash
OMP_THEME_URL="https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/kushal.omp.json" ./install_update_zsh.sh
```

### Zsh Plugins (via Antigen)

- **git** — Git aliases and completions  
- **zsh-users/zsh-autosuggestions** — Inline history-based suggestions as you type  
- **zsh-users/zsh-history-substring-search** — Use ↑/↓ to search history by substring  
- **djui/alias-tips** — Shows the alias you could’ve used after typing a long command  
- **rupa/z** — Quickly jump to frequently used directories by substring  
- **junegunn/fzf** — Fuzzy finder, Ctrl-R history search, file search, etc.  
- **ssh-agent** — Auto-starts and loads your SSH keys  
- **Aloxaf/fzf-tab** — FZF-powered tab completion UI  
- **zsh-users/zsh-syntax-highlighting** — Highlights valid commands, flags, and errors  
