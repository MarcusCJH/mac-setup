# A fresh Homebrew install is not on PATH until a new shell starts
export PATH := /opt/homebrew/bin:/usr/local/bin:$(PATH)

.PHONY: help brew work home

help:
	@echo "make work | make home                   install Homebrew and that Brewfile"
	@echo "make check-work | make check-home       list Brewfile entries not installed"
	@echo "make cleanup-work | make cleanup-home   list installed packages not in the Brewfile"

brew:
	@command -v brew >/dev/null || /bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

work home: brew
	brew bundle --file=Brewfile.$@

check-%:
	brew bundle check --verbose --file=Brewfile.$*

cleanup-%:
	brew bundle cleanup --file=Brewfile.$*
