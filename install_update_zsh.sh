#!/usr/bin/env bash
# Modular Zsh + terminal bootstrap (macOS / Linux). Compatible with bash 3.2.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_TYPE="$(uname)"
INSTALL_MODE="${INSTALL_MODE:-}"
DRY_RUN="${DRY_RUN:-0}"
ZSHRC_ONLY=0
UPDATE=0
PLAIN="${PLAIN:-0}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh-setup"
SELECTION_FILE="$CONFIG_DIR/selection.env"
GLOSSARY_DEST="$CONFIG_DIR/glossary.tsv"
ARGS=("$@")
OMP_THEME_URL="${OMP_THEME_URL:-https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/kushal.omp.json}"
OMP_THEME_NAME="$(basename "$OMP_THEME_URL")"
ITERM_JSON="$REPO_DIR/terminal_config/Custom.json"
TERMINAL_FILE="$REPO_DIR/terminal_config/Custom.terminal"

usage() {
  cat <<'EOF'
Usage: ./install_update_zsh.sh [--full | --custom] [--update] [--zshrc-only] [--dry-run] [--plain]
  --full         accept the default answer to every question
  --custom       ask about every module
  --update       machine already set up: git pull this repo, reuse the modules saved on
                 this machine, only ask about new ones, then re-apply everything
  --zshrc-only   only regenerate ~/.zshrc (no install, no terminal setup)
  --dry-run      change nothing: print actions and the diff of the generated ~/.zshrc
  --plain        no live display, one line per action
EOF
}

for arg in "$@"; do
  case "$arg" in
    --full) INSTALL_MODE="FULL" ;;
    --custom) INSTALL_MODE="CUSTOM" ;;
    --zshrc-only) INSTALL_MODE="FULL"; ZSHRC_ONLY=1 ;;
    --update) UPDATE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --plain) PLAIN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

# ------------------------------ Update: pull, then re-run the fresh script ------
if [[ "$UPDATE" == "1" && "${UPDATE_PULLED:-0}" != "1" ]]; then
  echo "Updating repo $REPO_DIR ..."
  if [[ "$DRY_RUN" == "1" ]]; then echo "  [dry-run] git pull --ff-only"; git -C "$REPO_DIR" fetch -q origin || true
  elif git -C "$REPO_DIR" pull --ff-only; then :; else echo "  ! pull failed (local changes or diverged history); continuing with the local copy" >&2; fi
  UPDATE_PULLED=1 exec bash "$REPO_DIR/$(basename "${BASH_SOURCE[0]}")" "${ARGS[@]}"
fi

# ------------------------------ Helpers ----------------------------------------
dry() { [[ "$DRY_RUN" == "1" ]]; }
timestamp() { date +"%Y%m%d-%H%M%S"; }

# Step state of the action being run (read by run_queue): done | have | skip | fail
STEP_STATE=done; STEP_NOTE=""
UI_ON=0; UI_USED=0; UI_PID=""; UI_LOG=""
NEXT_STEPS=""; RECAP=""; BREW_MISSING=0

last_log_line() { if [[ -n "$UI_LOG" && -f "$UI_LOG" ]]; then tail -n 1 "$UI_LOG" | cut -c1-140; fi; }
mark_done() { if [[ "$STEP_STATE" == "done" ]]; then STEP_NOTE="${1:-}"; fi; }
have_step() { if [[ "$STEP_STATE" == "done" ]]; then STEP_STATE=have; STEP_NOTE="${1:-}"; fi; }
skip_step() { if [[ "$STEP_STATE" == "done" ]]; then STEP_STATE=skip; STEP_NOTE="${1:-}"; fi; }
next_step() { NEXT_STEPS="${NEXT_STEPS}${1}"$'\n'; }

run() {
  if dry; then echo "  [dry-run] $*"; return 0; fi
  if "$@"; then return 0; fi
  STEP_STATE=fail; STEP_NOTE="$(last_log_line)"; [[ -n "$STEP_NOTE" ]] || STEP_NOTE="$* failed"
  echo "  ! failed: $*" >&2
  return 0
}

ask() {
  local prompt default reply
  prompt="$1"; default="${2:-Y}"
  if [[ "$default" =~ ^[Yy]$ ]]; then prompt="$prompt [Y/n] "; else prompt="$prompt [y/N] "; fi
  if [[ "$INSTALL_MODE" == "FULL" ]]; then
    reply="$default"
  else
    read -r -p "$prompt" reply || true
  fi
  reply="${reply:-$default}"
  case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# pick <id> <label> <Y|N>: records the answer in SEL_<id>
pick() {
  local cur="SEL_$1"
  if [[ "$UPDATE" == "1" && -n "${!cur:-}" ]]; then return 0; fi
  if ask "$2" "$3"; then eval "SEL_$1=1"; else eval "SEL_$1=0"; fi
}
sel() { local v="SEL_$1"; [[ "${!v:-0}" == "1" ]]; }
skip() { eval "SEL_$1=0"; }

# need <module> <dependency>: turns the dependency on when the module is selected
need() {
  if sel "$1" && ! sel "$2"; then
    eval "SEL_$2=1"
    echo "  -> '$2' enabled (required by '$1')"
  fi
}

brew_ok() { command -v brew >/dev/null 2>&1; }

find_brew() {
  local b
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$b" ]]; then eval "$("$b" shellenv)"; return 0; fi
  done
  return 1
}

# Runs before the live display: the Homebrew installer needs the terminal (sudo password, Enter)
BREW_JUST_INSTALLED=0
preflight_brew() {
  [[ "$OS_TYPE" == "Darwin" ]] || return 0
  if ! brew_ok && find_brew; then echo "Homebrew found at $(command -v brew) (was not on PATH)."; fi
  if ! brew_ok && sel homebrew; then
    echo "Installing Homebrew (may ask for your password)..."
    run bash -c '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    if ! dry; then
      find_brew || true
      if brew_ok; then BREW_JUST_INSTALLED=1; fi
    fi
  fi
  if brew_ok && ! dry && ! grep -qs 'brew shellenv' "$HOME/.zprofile" 2>/dev/null; then
    echo "eval \"\$($(command -v brew) shellenv)\"" >> "$HOME/.zprofile"
  fi
  if ! brew_ok; then
    BREW_MISSING=1
    next_step "Homebrew is missing: rerun $REPO_DIR/$(basename "${BASH_SOURCE[0]}") --update --full (the Homebrew module installs it)"
  fi
  return 0
}

step_homebrew() {
  if ! brew_ok; then skip_step "not installed (Homebrew module off or install failed)"; return 0; fi
  if [[ "$BREW_JUST_INSTALLED" == "1" ]]; then mark_done "installed"; return 0; fi
  run brew update --quiet; mark_done "updated"
}

pkg() { # pkg <brew-name> [apt-name]
  local brew_name="$1" apt_name="${2:-$1}"
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    if ! brew_ok; then skip_step "needs Homebrew"; return 0; fi
    if brew list --formula "$brew_name" >/dev/null 2>&1; then echo "  ok: $brew_name"; have_step "already installed"; else run brew install "$brew_name"; mark_done "installed"; fi
  else
    if dpkg -s "$apt_name" >/dev/null 2>&1; then echo "  ok: $apt_name"; have_step "already installed"; else run sudo apt install -y "$apt_name"; mark_done "installed"; fi
  fi
}

cask() { # cask <name> [app-path ...]
  local name="$1" app found=0; shift
  for app in "$@"; do [[ -d "$app" ]] && found=1; done
  if ! brew_ok; then skip_step "needs Homebrew"; return 0; fi
  if [[ "$found" == "1" ]] || brew list --cask "$name" >/dev/null 2>&1; then
    echo "  ok: $name"; have_step "already installed"
  else
    run brew install --cask "$name"; mark_done "installed"
  fi
}

# ------------------------------ Live display ------------------------------------
# share/ui.py (rich) draws the progress from events written to fd 3; everything else goes to the log file while it runs.
ui_python() {
  local py="$CONFIG_DIR/venv/bin/python"
  xcode-select -p >/dev/null 2>&1 || return 1
  mkdir -p "$CONFIG_DIR"
  if [[ ! -x "$py" ]]; then python3 -m venv "$CONFIG_DIR/venv" >/dev/null 2>&1 || return 1; fi
  if ! "$py" -c "import rich" >/dev/null 2>&1; then
    echo "Installing the display library (rich, first run only)..." >&2
    "$py" -m pip install --quiet rich >/dev/null 2>&1 || return 1
  fi
  echo "$py"
}

ui() { # ui <kind> <field>...: no-op without the live display
  [[ "$UI_ON" == "1" ]] || return 0
  local IFS=$'\t'
  printf '%s\n' "$*" >&3 2>/dev/null || true
}

ui_start() {
  dry && return 0
  [[ "$PLAIN" != "1" && -t 1 && "$OS_TYPE" == "Darwin" ]] || return 0
  local py fifo
  py="$(ui_python)" || { echo "Live display unavailable (python3 + rich needed); using plain output."; return 0; }
  fifo="$(mktemp -u "${TMPDIR:-/tmp}/zshsetup-ui.XXXXXX")"
  mkfifo "$fifo" || return 0
  UI_LOG="$CONFIG_DIR/install.log"; : > "$UI_LOG"
  "$py" "$REPO_DIR/share/ui.py" < "$fifo" &
  UI_PID=$!
  exec 3> "$fifo"
  rm -f "$fifo"
  trap '' PIPE
  exec 4>&1 5>&2
  exec >> "$UI_LOG" 2>&1
  UI_ON=1; UI_USED=1
}

ui_stop() {
  [[ "$UI_ON" == "1" ]] || return 0
  UI_ON=0
  exec 1>&4 2>&5 3>&- 4>&- 5>&-
  wait "$UI_PID" 2>/dev/null || true
}
trap ui_stop EXIT

# ------------------------------ Step queue --------------------------------------
Q_PHASE=(); Q_KEY=(); Q_LABEL=(); Q_CMD=()
queue() { # queue <phase> <key> <label> <command...>
  Q_PHASE+=("$1"); Q_KEY+=("$2"); Q_LABEL+=("$3"); shift 3
  Q_CMD+=("$(printf '%q ' "$@")")
}

run_queue() {
  local n=${#Q_PHASE[@]} i ph tot last="" t0 note failed=0
  if [[ "$UI_ON" == "1" ]]; then
    ui H "Terminal setup" "$REPO_DIR" "mode $INSTALL_MODE$([[ "$UPDATE" == "1" ]] && echo ' + update')"
    for ph in "Tools" "Shell config" "Terminal apps"; do
      tot=0
      for ((i=0; i<n; i++)); do if [[ "${Q_PHASE[$i]}" == "$ph" ]]; then tot=$((tot+1)); fi; done
      if [[ "$tot" -gt 0 ]]; then ui P "$ph" "$tot"; fi
    done
  fi
  for ((i=0; i<n; i++)); do
    ph="${Q_PHASE[$i]}"
    if [[ "$UI_ON" != "1" && "$ph" != "$last" ]]; then echo; echo "== $ph =="; last="$ph"; fi
    STEP_STATE=done; STEP_NOTE=""
    ui B "$ph" "${Q_KEY[$i]}" "${Q_LABEL[$i]}"
    t0=$SECONDS
    eval "${Q_CMD[$i]}"
    note="${STEP_NOTE//$'\t'/ }"; note="${note//$'\n'/ }"
    ui E "$ph" "${Q_KEY[$i]}" "$STEP_STATE" "$((SECONDS - t0))" "$note"
    case "$STEP_STATE" in
      skip|fail) RECAP="${RECAP}  [${STEP_STATE}] ${Q_KEY[$i]}: ${note}"$'\n' ;;
    esac
    if [[ "$STEP_STATE" == "fail" ]]; then failed=1; fi
  done
  return "$failed"
}

# ------------------------------ Module selection -------------------------------
echo "Setting up Zsh environment... (repo: $REPO_DIR)"
if [[ "$UPDATE" == "1" && -f "$SELECTION_FILE" ]]; then
  eval "$(grep -E '^SEL_[a-z0-9_]+=[01]$' "$SELECTION_FILE" || true)"
  echo "Reusing saved modules from $SELECTION_FILE"
  INSTALL_MODE="${INSTALL_MODE:-CUSTOM}"
fi
if [[ -z "$INSTALL_MODE" ]]; then
  if ask "Use FULL install mode (auto-accept defaults)?" "Y"; then INSTALL_MODE="FULL"; else INSTALL_MODE="CUSTOM"; fi
fi
echo "Mode: $INSTALL_MODE$([[ "$UPDATE" == "1" ]] && echo ' + update')$(dry && echo ' (dry-run)')"

echo; echo "== Tools =="
pick base    "Base dependencies (zsh git curl)?" "Y"
if [[ "$OS_TYPE" == "Darwin" ]]; then pick homebrew "Homebrew (installed if missing, updated otherwise; most tools below need it)?" "Y"; else skip homebrew; fi
pick fzf     "fzf (fuzzy finder, Ctrl-R, key-bindings)?" "Y"
pick zoxide  "zoxide (smarter cd: z / zi)?" "Y"
pick eza     "eza (fzf-tab directory preview)?" "Y"
pick omp     "oh-my-posh prompt (theme: $OMP_THEME_NAME)?" "Y"
pick font    "Meslo Nerd Font (glyphs for the prompt)?" "Y"
pick bat     "bat (cat with syntax highlighting, fzf preview)?" "Y"
pick fd      "fd (fast find, feeds fzf)?" "Y"
pick atuin   "atuin (searchable shell history, owns Ctrl-R)?" "Y"
pick delta   "git-delta (readable git diffs, via a git include file)?" "Y"
pick lazygit "lazygit (git terminal UI, alias lg)?" "Y"
pick mise    "mise (per-project tool versions: Java, Terraform, ...)?" "Y"
pick direnv  "direnv (per-directory env vars via .envrc)?" "Y"

if [[ "${SEL_antigen:-0}" == "1" && -z "${SEL_antidote:-}" ]]; then
  echo; echo "Migration: Antigen is replaced by antidote (plugins load statically, autosuggestions and highlighting are deferred)."
  echo "  ~/.antigen and ~/.antigen.zsh are left on disk; the new ~/.zshrc no longer loads them."
fi

echo; echo "== Plugin manager =="
pick antidote "antidote plugin manager + zsh-defer (required for the plugins below)?" "Y"

if sel antidote; then
  echo; echo "== Plugins =="
  pick p_git      "git (aliases/completions)?" "Y"
  pick p_autosug  "zsh-autosuggestions (ghost text, deferred)?" "Y"
  pick p_histsub  "zsh-history-substring-search (up/down)?" "Y"
  pick p_aliastip "alias-tips (shows the alias you could have used)?" "Y"
  pick p_ssh      "ssh-agent (loads id_ed25519)?" "Y"
  pick p_fzftab   "fzf-tab (fzf-powered TAB completion)?" "Y"
  pick p_fsh      "fast-syntax-highlighting (deferred)?" "Y"
else
  for m in p_git p_autosug p_histsub p_aliastip p_ssh p_fzftab p_fsh; do skip "$m"; done
fi

echo; echo "== Shell options =="
conda_default="N"; [[ -d "$HOME/anaconda3" ]] && conda_default="Y"
pick conda   "Conda init block (\$HOME/anaconda3)?" "$conda_default"
pick vscode  "VS Code guard (skip prompt/plugins while VS Code resolves its env)?" "Y"
pick usercfg "Personal aliases, history timestamps, key bindings?" "Y"
pick zhelp   "zhelp command (glossary of aliases, keys and tools)?" "Y"

if [[ "$OS_TYPE" == "Darwin" && "$ZSHRC_ONLY" == "0" ]]; then
  echo; echo "== Terminal apps =="
  pick iterm2      "Install iTerm2 and set up the Custom profile?" "Y"
  pick terminalapp "Import the Terminal.app Custom profile?" "Y"
else
  skip iterm2; skip terminalapp
fi

# Dependencies
need p_fzftab fzf
need iterm2 font
need terminalapp font
if [[ "$ZSHRC_ONLY" == "0" ]]; then preflight_brew; fi

# ------------------------------ zshrc generation -------------------------------
emit_zshrc() {
  cat <<'EOF'
# If come from bash might have to change $PATH
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# user-local binaries (claude, pipx, ...) and opencode
export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/.opencode/bin" ]] && export PATH="$HOME/.opencode/bin:$PATH"
EOF

  if sel conda; then cat <<'EOF'


# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$("$HOME/anaconda3/bin/conda" 'shell.zsh' 'hook' 2> /dev/null)"
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
  fi

  if sel mise; then cat <<'EOF'


#### mise ####
command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"
EOF
  fi

  if sel vscode; then cat <<'EOF'


#### VS Code ####
# VS Code resolves its env with a tty-less login shell: stop here, nothing below sets env
[[ -n "${VSCODE_RESOLVING_ENVIRONMENT:-}" ]] && return
EOF
  fi

  if sel p_ssh; then cat <<'EOF'


#### SSH Agent ####
zstyle ':omz:plugins:ssh-agent' identities id_ed25519
EOF
  fi

  if sel antidote; then cat <<'EOF'


#### antidote (plugins listed in ~/.zsh_plugins.txt) ####
for __antidote in "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/antidote/share/antidote/antidote.zsh" "$HOME/.antidote/antidote.zsh"; do
  [[ -r "$__antidote" ]] && { source "$__antidote"; break; }
done
unset __antidote
(( $+functions[antidote] )) && antidote load
EOF
  fi

  printf '\n\n#### User configuration ####\n'
  if [[ "$OS_TYPE" == "Linux" ]]; then
    if sel bat; then echo 'command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1 && alias bat=batcat'; fi
    if sel fd;  then echo 'command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1 && alias fd=fdfind'; fi
  fi
  if sel fzf && sel fd; then cat <<'EOF'
# fzf x fd: list files/dirs with fd (hidden files included, .git excluded)
if command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
fi
EOF
  fi
  if sel fzf && sel bat; then cat <<'EOF'
command -v bat >/dev/null 2>&1 && export FZF_CTRL_T_OPTS="--preview 'bat -n --color=always --line-range :200 {}'"
EOF
  fi
  if sel fzf; then cat <<'EOF'
# fzf setup
[ -f $HOME/.fzf.zsh ] && source $HOME/.fzf.zsh
EOF
  fi
  if sel zoxide; then cat <<'EOF'

# zoxide (z / zi)
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
EOF
  fi
  if sel atuin; then cat <<'EOF'

# atuin owns Ctrl-R (after fzf); Up/Down stay with history-substring-search
command -v atuin >/dev/null 2>&1 && eval "$(atuin init zsh --disable-up-arrow)"
EOF
  fi
  if sel direnv; then cat <<'EOF'

# direnv (.envrc per directory)
command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"
EOF
  fi
  if sel lazygit; then cat <<'EOF'

alias lg=lazygit
EOF
  fi
  if sel usercfg; then cat <<'EOF'

# Set personal aliases
alias zshconfig="nano ~/.zshrc"

# Enable history timestamps
HIST_STAMPS="yyyy-mm-dd"
EOF
    if sel p_histsub; then cat <<'EOF'

# History substring search bindings (↑/↓)
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
EOF
    fi
  fi

  if sel p_fzftab; then
    cat <<'EOF'


#### fzf-tab UI settings ####
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' menu no
EOF
    if sel eza; then echo "zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always \$realpath'"; fi
    cat <<'EOF'
zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' switch-group '<' '>'
EOF
  fi

  if sel zhelp; then cat <<'EOF'


#### zhelp ####
zhelp() {
  local g="$HOME/.config/zsh-setup/glossary.tsv" fmt='{printf "%-6s %-26s %s\n", $2, $3, $4}'
  [[ -f "$g" ]] || { echo "zhelp: $g missing (run install_update_zsh.sh --update)"; return 1; }
  if [[ -n "$1" ]]; then
    echo "-- glossary --"; grep -i -- "$*" "$g" | awk -F'\t' "$fmt"
    echo "-- aliases --"; alias | grep -i -- "$*"
    echo "-- functions --"; print -l ${(k)functions} | grep -v '^_' | grep -i -- "$*" | head -20
  elif command -v fzf >/dev/null 2>&1; then
    awk -F'\t' "$fmt" "$g" | fzf --prompt='zhelp> ' --no-sort
  else
    awk -F'\t' "$fmt" "$g" | ${PAGER:-less}
  fi
}
EOF
  fi

  # Oh My Posh must stay last
  if sel omp; then
    printf '\n\n#### Oh My Posh theme ####\n'
    printf 'if [[ $- == *i* ]]; then\n'
    printf '  if command -v oh-my-posh >/dev/null 2>&1; then\n'
    printf '    __omp_cfg="$HOME/.config/oh-my-posh/%s"\n' "$OMP_THEME_NAME"
    printf '    [[ -f "$__omp_cfg" ]] || __omp_cfg="%s"\n' "$OMP_THEME_URL"
    printf '    eval "$(oh-my-posh init zsh --config "$__omp_cfg")" || \\\n'
    printf "      PROMPT='%%F{cyan}%%n@%%m%%f:%%F{yellow}%%~%%f %%# '\n"
    printf '    unset __omp_cfg\n'
    printf '  else\n'
    printf "    PROMPT='%%F{cyan}%%n@%%m%%f:%%F{yellow}%%~%%f %%# '\n"
    printf '  fi\n'
    printf 'fi\n'
  fi
}

emit_plugins() {
  echo "# Generated by install_update_zsh.sh from the selected modules; edit the selection, not this file"
  if sel p_git || sel p_ssh; then
    echo "getantidote/use-omz"
    echo "ohmyzsh/ohmyzsh path:lib"
  fi
  if sel p_git;      then echo "ohmyzsh/ohmyzsh path:plugins/git"; fi
  if sel p_ssh;      then echo "ohmyzsh/ohmyzsh path:plugins/ssh-agent"; fi
  if sel p_aliastip; then echo "djui/alias-tips"; fi
  echo "mattmc3/ez-compinit"
  if sel p_fzftab;   then echo "Aloxaf/fzf-tab"; fi
  if sel p_histsub;  then echo "zsh-users/zsh-history-substring-search"; fi
  if sel p_autosug || sel p_fsh; then echo "romkatv/zsh-defer"; fi
  if sel p_autosug;  then echo "zsh-users/zsh-autosuggestions kind:defer"; fi
  if sel p_fsh;      then echo "zdharma-continuum/fast-syntax-highlighting kind:defer"; fi
}

write_plugins() {
  local tmp
  tmp="$(mktemp)"
  emit_plugins > "$tmp"
  sync_file "$tmp" "$HOME/.zsh_plugins.txt" "plugin list"
  rm -f "$tmp"
}

antidote_src() {
  local f
  for f in "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/antidote/share/antidote/antidote.zsh" "$HOME/.antidote/antidote.zsh"; do
    if [[ -r "$f" ]]; then echo "$f"; return 0; fi
  done
  return 1
}

write_zshrc() {
  local target="$HOME/.zshrc" tmp
  tmp="$(mktemp)"
  emit_zshrc > "$tmp"
  if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
    echo "~/.zshrc already up to date."; have_step "already up to date"
  elif dry; then
    echo "[dry-run] ~/.zshrc would change:"
    diff -u "$target" "$tmp" || true
  else
    if [[ "$UPDATE" == "1" && -f "$target" ]]; then diff -u "$target" "$tmp" || true; fi
    if [[ -f "$target" ]]; then
      cp -p "$target" "$target.bak.$(timestamp)"
      echo "Backed up ~/.zshrc -> ~/.zshrc.bak.*"
    fi
    cp "$tmp" "$target"
    echo "Wrote ~/.zshrc"; mark_done "written, previous one backed up"
  fi
  rm -f "$tmp"
}

# ------------------------------ Steps ------------------------------------------
sync_file() { # sync_file <src> <dest> <label>
  if [[ -f "$2" ]] && cmp -s "$1" "$2"; then
    echo "$3 already up to date."; have_step "already up to date"
  elif dry; then
    echo "[dry-run] $3 would be written to $2"
  else
    mkdir -p "$(dirname "$2")"; cp "$1" "$2"; echo "Wrote $3 ($2)"; mark_done "written"
  fi
}

write_glossary() {
  local tmp mod kind name desc
  tmp="$(mktemp)"
  while IFS=$'\t' read -r mod kind name desc; do
    if [[ -z "$mod" || "$mod" == \#* ]]; then continue; fi
    if [[ "$mod" == "core" ]] || sel "$mod"; then printf '%s\t%s\t%s\t%s\n' "$mod" "$kind" "$name" "$desc" >> "$tmp"; fi
  done < "$REPO_DIR/share/glossary.tsv"
  sync_file "$tmp" "$GLOSSARY_DEST" "zhelp glossary"
  rm -f "$tmp"
}

setup_delta() {
  local dest="$CONFIG_DIR/delta.gitconfig"
  sync_file "$REPO_DIR/share/delta.gitconfig" "$dest" "delta git config"
  if git config --global --get-all include.path 2>/dev/null | grep -qxF "$dest"; then
    echo "  git include.path already set."
  else
    run git config --global --add include.path "$dest"; mark_done "git include added"
  fi
}

import_atuin_history() {
  if ! command -v atuin >/dev/null 2>&1; then skip_step "atuin not installed"; return 0; fi
  if [[ -f "$HOME/.zsh_history" && ! -f "$CONFIG_DIR/atuin-imported" ]]; then
    run atuin import zsh
    if ! dry; then mkdir -p "$CONFIG_DIR"; touch "$CONFIG_DIR/atuin-imported"; fi
    mark_done "history imported"
  else
    have_step "nothing to import"
  fi
}

build_plugins() {
  local src
  if src="$(antidote_src)"; then
    run zsh -c "source '$src'; antidote bundle < \"\$HOME/.zsh_plugins.txt\" > \"\$HOME/.zsh_plugins.zsh\""
    mark_done "bundle generated"
  else
    echo "  antidote not found; plugins will be cloned on the next shell start once it is installed."
    skip_step "antidote not installed"
  fi
}

step_base() {
  local t any=0
  if [[ "$OS_TYPE" == "Linux" ]]; then run sudo apt update; fi
  for t in zsh git curl; do
    if command -v "$t" >/dev/null 2>&1; then echo "  ok: $t"; else any=1; pkg "$t"; fi
  done
  if [[ "$any" == "0" ]]; then have_step "already installed"; fi
}

step_antidote() {
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    pkg antidote
  elif [[ -d "$HOME/.antidote" ]]; then
    run git -C "$HOME/.antidote" pull --ff-only; mark_done "updated"
  else
    run git clone --depth 1 https://github.com/mattmc3/antidote.git "$HOME/.antidote"; mark_done "cloned"
  fi
}

step_fzf() {
  if [[ -d "$HOME/.fzf" ]]; then
    run git -C "$HOME/.fzf" pull --ff-only; mark_done "updated"
  else
    run git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"; mark_done "cloned"
  fi
  run "$HOME/.fzf/install" --key-bindings --completion --no-update-rc
}

step_zoxide() {
  pkg zoxide
  if command -v zoxide >/dev/null 2>&1 && [[ -f "$HOME/.z" && ! -f "$HOME/Library/Application Support/zoxide/db.zo" && ! -f "$HOME/.local/share/zoxide/db.zo" ]]; then
    run zoxide import z
  fi
}

step_omp() {
  if [[ "$OS_TYPE" == "Darwin" ]]; then
    pkg oh-my-posh
  elif ! command -v oh-my-posh >/dev/null 2>&1; then
    run bash -c 'curl -s https://ohmyposh.dev/install.sh | bash -s'; mark_done "installed"
  else
    have_step "already installed"
  fi
  run mkdir -p "$HOME/.config/oh-my-posh"
  run curl -fsSL "$OMP_THEME_URL" -o "$HOME/.config/oh-my-posh/$OMP_THEME_NAME"
}

step_font() {
  if [[ "$OS_TYPE" == "Darwin" ]]; then cask font-meslo-lg-nerd-font; else have_step "macOS only"; fi
}

font_status() { # font_status <iterm|vscode>: applies the font through share/apply_font.py
  local out rc=0
  if dry; then echo "  [dry-run] apply_font.py $1"; return 0; fi
  out="$(python3 "$REPO_DIR/share/apply_font.py" "$1" 2>&1)" || rc=$?
  echo "  font $1: $out"
  case "$rc" in
    0) mark_done "$out" ;;
    3) have_step "$out" ;;
    2) skip_step "$out" ;;
    *) STEP_STATE=fail; STEP_NOTE="$out" ;;
  esac
}

step_font_iterm() { font_status iterm; }
step_font_terminal() { font_status terminal; }
step_font_vscode() { font_status vscode; }

step_iterm2() {
  local dest_dir guid home_escaped
  cask iterm2 /Applications/iTerm.app "$HOME/Applications/iTerm.app"
  if [[ ! -f "$ITERM_JSON" ]]; then echo "  Skipped: $ITERM_JSON not found."; skip_step "profile file not found"; return 0; fi
  dest_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  guid="$(plutil -extract Guid raw -o - "$ITERM_JSON")"
  home_escaped="${HOME//\//\\/}"
  if defaults read com.googlecode.iterm2 "New Bookmarks" 2>/dev/null | grep -q "Guid = \"$guid\""; then
    echo "  Profile $guid already in iTerm2 preferences; Dynamic Profile skipped."
    dry || defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$guid"
  elif dry; then
    echo "  [dry-run] wrap $ITERM_JSON as a Dynamic Profile -> $dest_dir/Custom.json (Guid=$guid)"
    echo "  [dry-run] defaults write com.googlecode.iterm2 \"Default Bookmark Guid\" -string $guid"
  else
    mkdir -p "$dest_dir"
    { printf '{"Profiles":['; sed "s#\"Working Directory\" : \"[^\"]*\"#\"Working Directory\" : \"$home_escaped\"#" "$ITERM_JSON"; printf ']}\n'; } > "$dest_dir/Custom.json"
    defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$guid"
    echo "  Dynamic profile installed and set as default (Guid=$guid). Restart iTerm2."
  fi
}

step_terminalapp() {
  local profile_name
  if [[ ! -f "$TERMINAL_FILE" ]]; then echo "  Skipped: $TERMINAL_FILE not found."; skip_step "profile file not found"; return 0; fi
  profile_name="$(plutil -extract name raw -o - "$TERMINAL_FILE" 2>/dev/null || true)"
  run /usr/bin/open -g "$TERMINAL_FILE"
  if [[ -n "$profile_name" ]]; then
    run defaults write com.apple.Terminal "Default Window Settings" -string "$profile_name"
    run defaults write com.apple.Terminal "Startup Window Settings" -string "$profile_name"
    echo "  Profile '$profile_name' imported and set as default. Reopen Terminal.app."
    mark_done "profile '$profile_name' imported"
  else
    echo "  Profile opened/imported; name not detected."
  fi
}

# ------------------------------ Plan -------------------------------------------
if [[ "$ZSHRC_ONLY" == "0" ]]; then
  if sel homebrew; then queue Tools homebrew  "install / update"        step_homebrew; fi
  if sel base;    then queue Tools base       "zsh git curl"            step_base; fi
  if sel antidote; then queue Tools antidote  "plugin manager"          step_antidote; fi
  if sel fzf;     then queue Tools fzf        "fuzzy finder"            step_fzf; fi
  if sel zoxide;  then queue Tools zoxide     "smarter cd"              step_zoxide; fi
  if sel eza;     then queue Tools eza        "ls replacement"          pkg eza; fi
  if sel bat;     then queue Tools bat        "cat with highlighting"   pkg bat; fi
  if sel fd;      then queue Tools fd         "fast find"               pkg fd fd-find; fi
  if sel atuin;   then queue Tools atuin      "shell history"           pkg atuin; fi
  if sel delta;   then queue Tools git-delta  "readable diffs"          pkg git-delta; fi
  if sel lazygit; then queue Tools lazygit    "git terminal UI"         pkg lazygit; fi
  if sel mise;    then queue Tools mise       "tool versions"           pkg mise; fi
  if sel direnv;  then queue Tools direnv     "per-directory env"       pkg direnv; fi
  if sel omp;     then queue Tools oh-my-posh "prompt + theme"          step_omp; fi
  if sel font;    then queue Tools meslo-font "Nerd Font"               step_font; fi
fi

queue "Shell config" zshrc "~/.zshrc" write_zshrc
if sel antidote; then queue "Shell config" plugin-list "~/.zsh_plugins.txt" write_plugins; fi
if sel zhelp;    then queue "Shell config" glossary "zhelp glossary" write_glossary; fi
if [[ "$ZSHRC_ONLY" == "0" ]]; then
  if sel antidote && [[ "$DRY_RUN" != "1" ]]; then queue "Shell config" plugin-bundle "antidote bundle" build_plugins; fi
  if sel delta; then queue "Shell config" git-delta "git include file" setup_delta; fi
  if sel atuin; then queue "Shell config" atuin-import "zsh history" import_atuin_history; fi
fi

if sel iterm2;      then queue "Terminal apps" iterm2 "app + Custom profile" step_iterm2; fi
if sel terminalapp; then queue "Terminal apps" terminal.app "Custom profile" step_terminalapp; fi
if sel font && [[ "$OS_TYPE" == "Darwin" ]]; then
  if sel iterm2; then queue "Terminal apps" iterm-font "MesloLGS NF Mono 13 in all profiles" step_font_iterm; fi
  if sel terminalapp; then queue "Terminal apps" terminal-font "MesloLGS NF Mono 13 in all profiles" step_font_terminal; fi
  queue "Terminal apps" vscode-font "integrated terminal font" step_font_vscode
fi

# ------------------------------ Run --------------------------------------------
if [[ "$ZSHRC_ONLY" == "0" ]] && ! dry; then
  mkdir -p "$(dirname "$SELECTION_FILE")"
  (set | grep -E '^SEL_[a-z0-9_]+=[01]$' || true) > "$SELECTION_FILE"
fi

ui_start
queue_rc=0
run_queue || queue_rc=$?

if [[ "$ZSHRC_ONLY" == "0" ]] && sel omp && command -v oh-my-posh >/dev/null 2>&1; then
  run oh-my-posh enable reload
fi
next_step "exec zsh"

if [[ "$UI_ON" == "1" ]]; then
  while IFS= read -r line; do if [[ -n "$line" ]]; then ui N "$line"; fi; done <<< "$NEXT_STEPS"
  ui L "$UI_LOG"
fi
ui_stop

if [[ "$UI_USED" == "0" ]]; then
  if [[ -n "$RECAP" ]]; then echo; echo "Skipped / failed:"; printf '%s' "$RECAP"; fi
  if [[ "$ZSHRC_ONLY" == "0" ]] && ! dry; then echo; echo "Saved module selection -> $SELECTION_FILE"; fi
  echo; printf '%s' "$NEXT_STEPS" | sed 's/^/Next: /'
else
  echo "Done."
fi
exit "$queue_rc"
