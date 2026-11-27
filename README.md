# mac-setup

Sets up a Mac for work or home: Homebrew packages, shell aliases, and git identities that sign commits with SSH keys stored in 1Password. Everything runs through `make`, and `make help` lists the targets.

## Quick start

```sh
make work      # or: make home. Installs Homebrew and that Brewfile
make aliases   # loads zsh/aliases.zsh from ~/.zshrc
make git-work  # or: make git-home. Sets up git identities (1Password SSH keys, gh logins)
make acli      # logs acli in to an identity's Atlassian account with an API token; rerun for each
```

Each identity has its own folder, `~/Documents/git/<identity>/`. Inside it, git, `gh` and `acli` use that identity's accounts. Everywhere else they use personal's.

After installing or removing apps, run `make dump-work` (or `make dump-home`) to update that Brewfile, then review the change with `git diff`.

## Layout

| Folder | Contents |
|---|---|
| `acli/` | `login.sh`, which logs acli in to an identity's Atlassian account |
| `brew/` | `Brewfile.work`, `Brewfile.home`, and `dump.py`, which updates a Brewfile from what's installed |
| `git/` | `gitconfig`, and `identity.sh`, which onboards each git identity |
| `ssh/` | `config`, which points SSH at the 1Password agent |
| `zsh/` | `aliases.zsh`, loaded from `~/.zshrc`, with the `gh` and `acli` wrappers that pick the folder's account |

To add a tool, give it its own folder for its config and any script that manages it, and add a target to the `Makefile`.
