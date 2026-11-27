# Shell aliases and functions, sourced from ~/.zshrc (run `make aliases` to hook
# this up). Edits here take effect in new shells, or after `source ~/.zshrc`.

alias python=python3
alias pip=pip3

# _identity_get <file> <key>: a setting from ~/<file>-<identity> for the
# identity folder you're in, ~/Documents/git/<identity>/, else personal's
_identity_get() {
	local id=${${PWD#$HOME/Documents/git/}%%/*}
	[[ -f ~/.gitconfig-$id ]] || id=personal
	git config -f ~/$1-$id "$2" 2>/dev/null
}

# gh acts as the GitHub account of the identity folder you're in (logins set up
# by git/identity.sh)
gh() {
	local user token
	user=$(_identity_get .gitconfig github.user)
	# gh auth manages the stored logins itself, and an explicit GH_TOKEN wins
	[[ $1 == auth || -n $GH_TOKEN || -z $user ]] || token=$(command gh auth token --user "$user" 2>/dev/null)
	if [[ -n $token ]]; then GH_TOKEN=$token command gh "$@"; else command gh "$@"; fi
}

# acli jira/confluence acts as the Atlassian account of the identity folder
# you're in (logins set up by acli/login.sh). Switching is a ~1s network call and
# sticks for other shells too, so it only runs when another account is active.
acli() {
	local profile
	[[ $1 == (jira|confluence) && $2 != auth ]] && profile=$(_identity_get .acli atlassian.$1)
	if [[ -n $profile ]] && ! grep -qxF "current_profile: $profile" ~/.config/acli/${1}_config.yaml 2>/dev/null; then
		command acli $1 auth switch --site "$(_identity_get .acli atlassian.site)" --email "$(_identity_get .acli atlassian.email)" >/dev/null ||
			{ echo "acli: can't switch $1 to this folder's account; rerun make acli" >&2; return 1; }
	fi
	command acli "$@"
}
