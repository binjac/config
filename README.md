## Terminal Setup

Modular Zsh + iTerm2 / Terminal.app bootstrap for macOS and Linux. You pick the modules; the same script installs them and generates `~/.zshrc`, so every machine ends up identical.

## First install

```sh
git clone git@github.com:binjac/config.git ~/config
cd ~/config
./install_update_zsh.sh          # asks FULL (defaults) or CUSTOM (pick each module)
exec zsh
```

Keep the clone: it is what `--update` pulls from.

## Update a machine that already has the config

```sh
cd ~/config
./install_update_zsh.sh --update
exec zsh
```

`--update` runs `git pull --ff-only`, re-runs the fresh script, reuses the modules chosen on this machine (saved in `~/.config/zsh-setup/selection.env`), asks only about modules added since, installs what is missing, then regenerates `~/.zshrc` (old one backed up as `~/.zshrc.bak.<timestamp>`, diff printed). Add `--full` to accept defaults for new modules without prompts.

On a machine configured before the selection file existed, the first `--update` asks the usual FULL/CUSTOM question, then remembers the answers.

## Options

| Flag | Effect |
| --- | --- |
| `--full` | accept the default answer to every question |
| `--custom` | ask about every module |
| `--update` | pull the repo, reuse saved modules, ask only about new ones |
| `--zshrc-only` | only regenerate `~/.zshrc` (no install, no terminal setup, nothing saved) |
| `--dry-run` | change nothing; print the actions and the diff of the generated `~/.zshrc` |
| `--plain` | no live display, one line per action |

In a terminal on macOS the run shows a live display (`share/ui.py`, rich, installed in `~/.config/zsh-setup/venv` on first run): one progress bar per phase (Tools, Shell config, Terminal apps), the steps in flight, then a results panel listing what was skipped or failed and what to do next. Command output goes to `~/.config/zsh-setup/install.log`. Without a terminal, with `--dry-run` or `--plain`, it prints one line per action.

`OMP_THEME_URL` picks the oh-my-posh theme (default `kushal`); the theme is downloaded once to `~/.config/oh-my-posh/` so the prompt does not depend on the network.

If Homebrew is missing and its module is off, the tools that need it are reported as skipped; enable the module (or install Homebrew) and rerun `./install_update_zsh.sh --update --full`. Before applying the font, `share/apply_font.py` checks that macOS resolves `MesloLGSNFM-Regular`; if not (files quarantined or unregistered, apps then fall back to Menlo) it strips the quarantine flag, resets the user font cache and restarts `fontd`, and the step fails if the font is still not found. iTerm2 fonts are only applied while iTerm2 is closed (it would overwrite them); Terminal.app is updated live.

## Modules

| Group | Modules |
| --- | --- |
| Tools | Homebrew (installed if missing, updated otherwise), base (zsh git curl), fzf, zoxide, eza, oh-my-posh, Meslo Nerd Font, bat, fd, atuin, git-delta, lazygit, mise, direnv |
| Plugin manager | antidote (+ zsh-defer) |
| Plugins | git, zsh-autosuggestions, zsh-history-substring-search, alias-tips, ssh-agent, fzf-tab, fast-syntax-highlighting |
| Shell config | conda init, VS Code guard, aliases / history timestamps / key bindings, `zhelp` |
| Terminal apps (macOS) | iTerm2 (cask + Dynamic Profile from `terminal_config/Custom.json`), Terminal.app profile (`terminal_config/Custom.terminal`), then MesloLGS Nerd Font Mono Regular 13 set in every iTerm2 and Terminal.app profile and in the VS Code integrated terminal (`share/apply_font.py`) |

Dependencies are enabled automatically (fzf-tab needs fzf, the terminal profiles need the Nerd Font). Only the macOS path has been tested; on Linux most of the newer tools are not in `apt` and are skipped with a message (the `.zshrc` guards every init with `command -v`).

- **zhelp** prints a glossary of the aliases, keys and tools of the modules installed on this machine (`share/glossary.tsv`, filtered at install time into `~/.config/zsh-setup/glossary.tsv`). `zhelp` opens an fzf list; `zhelp <term>` also greps the live aliases and functions (`zhelp git` lists the ~200 git aliases).
- **antidote** replaces Antigen. Plugins come from `~/.zsh_plugins.txt`, generated from the selected modules, and load from a static file; autosuggestions and syntax highlighting are deferred with zsh-defer. On `--update`, a machine that used Antigen is migrated (`~/.antigen*` is left on disk, no longer loaded).
- **atuin** owns Ctrl-R (Up/Down stay with history-substring-search); your zsh history is imported once. No account or sync is set up.
- **git-delta** is enabled through a git include file (`~/.config/zsh-setup/delta.gitconfig` added to `include.path`), your own git config is not rewritten.
- **fd / bat** feed fzf: Ctrl-T lists files with fd and previews them with bat.
- **mise / direnv** manage per-project tool versions / environment variables (`.mise.toml`, `.envrc`).
- **zoxide** replaces `z` / autojump: same `z` command, plus `zi` for interactive selection. Existing `~/.z` history is imported on first install.
- **VS Code guard**: VS Code resolves its environment with a tty-less login shell. The generated `.zshrc` returns early in that case (`VSCODE_RESOLVING_ENVIRONMENT`), which avoids the "unable to resolve shell environment" timeouts.
- **Terminal profiles**: `Custom.json` is the iTerm2 profile export; the installer wraps it as a Dynamic Profile and sets it as default. `Custom.terminal` is the Terminal.app profile.

## Secrets

Never put tokens in this repo or in `~/.zshrc`. Copy `.zprofile.example` to `~/.zprofile` (or a `600` file it sources), fill in the values and `chmod 600` it.

## Agent setup

Claude Code and OpenCode share one agnostic home (`~/.agents`) with thin per-tool bridges. Layout and rebuild steps for a new machine: [docs/agents-setup.md](docs/agents-setup.md).
