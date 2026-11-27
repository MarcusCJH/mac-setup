# A fresh Homebrew install is not on PATH until a new shell starts
export PATH := /opt/homebrew/bin:/usr/local/bin:$(PATH)

ZSHRC := $(HOME)/.zshrc
ALIASES_LINE := source "$(CURDIR)/zsh/aliases.zsh"

.PHONY: help brew work home aliases git-config git-home git-work acli

help:
	@echo "make work | make home                   install Homebrew and that Brewfile"
	@echo "make check-work | make check-home       list Brewfile entries not installed"
	@echo "make cleanup-work | make cleanup-home   list installed packages not in the Brewfile"
	@echo "make dump-work | make dump-home         update that Brewfile to match what's installed"
	@echo "make aliases                            source zsh/aliases.zsh from ~/.zshrc"
	@echo "make git-home                           onboard the personal git identity"
	@echo "make git-work                           onboard a work git identity (own folder); rerun for each"
	@echo "make acli                               log acli in to an identity's Atlassian account; rerun for each"

# install_file,<repo file>,<destination>,<mode>: copy into place, moving aside
# an existing file that differs so nothing is silently lost
define install_file
	@if cmp -s $(1) $(2); then echo "unchanged  $(2)"; else \
		if [ -e $(2) ]; then mv $(2) $(2).bak-$$(date +%Y%m%d%H%M%S) && echo "backed up  $(2)"; fi; \
		install -m $(3) $(1) $(2) && echo "installed  $(2)"; fi
endef

git-config:
	@install -d -m 700 $(HOME)/.ssh
	$(call install_file,git/gitconfig,$(HOME)/.gitconfig,644)
	$(call install_file,ssh/config,$(HOME)/.ssh/config,600)

# Personal identity: name, email and 1Password key; rerun to change it
git-home: git-config
	@git/identity.sh personal

# One work identity with its own folder; rerun to add another or change one
git-work: git-config
	@[ -f $(HOME)/.gitconfig-personal ] || git/identity.sh personal
	@git/identity.sh

# One identity's Atlassian account, by API token; rerun to add another or change one
acli:
	@acli/login.sh

# Also replaces a line pointing at where aliases.zsh used to be in this repo
aliases:
	@touch $(ZSHRC)
	@grep -qxF '$(ALIASES_LINE)' $(ZSHRC) || { \
		sed -i '' '\|^source "$(CURDIR)/.*aliases\.zsh"$$|d' $(ZSHRC); \
		echo '$(ALIASES_LINE)' >> $(ZSHRC); }
	@echo "~/.zshrc sources zsh/aliases.zsh; open a new terminal or run: source ~/.zshrc"

brew:
	@command -v brew >/dev/null || /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

work home: brew
	brew bundle --file=brew/Brewfile.$@

check-%:
	brew bundle check --verbose --file=brew/Brewfile.$*

cleanup-%:
	brew bundle cleanup --file=brew/Brewfile.$*

# Keeps the Brewfile's sections and comments; see brew/dump.py
dump-%:
	@brew/dump.py brew/Brewfile.$*
