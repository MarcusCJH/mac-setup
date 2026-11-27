#!/bin/bash
# Onboard one git identity; rerun it to change one, e.g. after a job change.
#   make git-home  ->  git/identity.sh personal
#   make git-work  ->  git/identity.sh, which asks for the work identity's name
# Each identity has its own name, email, 1Password SSH key and repo folder
# ~/Documents/git/<identity>/; personal is used everywhere else. Creates the
# key if needed, walks you through adding it to GitHub, logs the GitHub CLI in
# as that account (if gh is installed), and writes
# ~/.gitconfig-<identity> and ~/.ssh/github-<identity>.pub (the public key it
# points at). No keys live in this repo. To drop an identity, delete those two
# files and rerun.
set -euo pipefail

repos=$HOME/Documents/git
# The 1Password agent socket, as set in ~/.ssh/config
agent=$(ssh -G github.com 2>/dev/null | sed -n 's/^identityagent //p')

if [ ! -S "$agent" ]; then
	echo "Can't reach the 1Password SSH agent. Turn on 1Password > Settings > Developer > 'Use the SSH agent', then rerun." >&2
	exit 1
fi

# ask <question> <default>: print the answer, or the default when left blank
ask() {
	local answer=
	read -rp "$1${2:+ [$2]}: " answer || true
	echo "${answer:-$2}"
}

# Keys the 1Password agent offers, one "type base64 title" line each
agent_keys() { SSH_AUTH_SOCK=$agent ssh-add -L 2>/dev/null | grep '^ssh-' || true; }

# Identities on this Mac, one per public key file
identities() {
	for p in "$HOME"/.ssh/github-*.pub; do
		[ -e "$p" ] || continue
		p=${p##*/github-}
		echo "${p%.pub}"
	done
}

# The GitHub account this identity's key logs in as, if any. ssh -T always
# exits 1 on GitHub, so read the greeting; -n keeps ssh off the prompts' stdin.
github_login() {
	ssh -nT -o StrictHostKeyChecking=accept-new -i "$pubfile" -o IdentitiesOnly=yes git@github.com 2>&1 |
		sed -n 's/^Hi \([^!]*\)!.*/\1/p' || true
}

identity=${1:-}
if [ -z "$identity" ]; then
	echo "Identities on this Mac: $(identities | xargs)"
	identity=$(ask "Work identity to add or change; also its folder ~/Documents/git/<name>/ (e.g. acme)" "")
fi
case $identity in
	"" | *[!A-Za-z0-9._-]*) echo "Use letters, digits, '.', '_' or '-' for the identity" >&2; exit 1 ;;
esac
config=$HOME/.gitconfig-$identity
pubfile=$HOME/.ssh/github-$identity.pub
folder=$repos/$identity

echo
echo "== $identity identity"
# Defaults are this Mac's previous answers, or the name another identity uses
name=$(ask "Name" "$(git config -f "$config" user.name 2>/dev/null || git config --global --includes user.name 2>/dev/null || true)")
email=$(ask "Email" "$(git config -f "$config" user.email 2>/dev/null || true)")
[ -n "$name" ] && [ -n "$email" ] || { echo "Name and email are required" >&2; exit 1; }

echo "SSH keys in 1Password:"
agent_keys | cut -d' ' -f3- | sed 's/^/  /'
key=$(ask "Key for your $identity GitHub account (a new name creates one)" "$(cut -d' ' -f3- "$pubfile" 2>/dev/null || echo "GitHub-$identity")")

pub=$(agent_keys | awk -v t="$key" 'substr($0, length($1) + length($2) + 3) == t { print $1, $2; exit }')
if [ -z "$pub" ]; then
	case $(ask "No 1Password SSH key called '$key'. Create it? [y/N]" "") in
		[yY]*) ;;
		*) echo "Nothing changed" >&2; exit 1 ;;
	esac
	command -v op >/dev/null || { echo "Needs the 1Password CLI (in the Brewfiles), or create the key in the 1Password app and rerun" >&2; exit 1; }
	# The Personal vault is the one 1Password's SSH agent serves by default.
	# </dev/null: op reads a piped stdin as its input and refuses.
	op item create --category "SSH Key" --title "$key" --vault Personal --ssh-generate-key ed25519 </dev/null >/dev/null
	pub=$(op item get "$key" --vault Personal --fields label="public key" </dev/null | cut -d' ' -f1,2)
fi

# One key per account: GitHub logs in as whichever account owns the key
other=$(grep -lF "$pub" "$HOME"/.ssh/github-*.pub 2>/dev/null | grep -vxF "$pubfile" || true)
[ -z "$other" ] || { echo "'$key' is already used by $other; pick another key" >&2; exit 1; }

mkdir -p "$folder"
echo "$pub $key" > "$pubfile"
cat > "$config" <<EOF
# $identity identity, written by git/identity.sh; rerun it to change
[user]
	name = $name
	email = $email
	signingkey = ~/.ssh/github-$identity.pub
[core]
	sshCommand = ssh -i ~/.ssh/github-$identity.pub -o IdentitiesOnly=yes
EOF

# Rebuild from all identities: the rules ~/.gitconfig includes (personal
# everywhere, each identity inside its folder; this also applies to clones),
# and allowed_signers (on fd 3) so `git log --show-signature` can verify them
{
	echo "# Written by git/identity.sh from the identities on this Mac"
	printf '[include]\n\tpath = ~/.gitconfig-personal\n'
	for i in $(identities); do
		printf '[includeIf "gitdir:%s/"]\n\tpath = ~/.gitconfig-%s\n' "$repos/$i" "$i"
		echo "$(git config -f "$HOME/.gitconfig-$i" user.email) namespaces=\"git\" $(cut -d' ' -f1,2 "$HOME/.ssh/github-$i.pub")" >&3
	done
} > "$HOME/.gitconfig-identities" 3> "$HOME/.ssh/allowed_signers"

login=$(github_login)
if [ -z "$login" ]; then
	pbcopy < "$pubfile"
	echo
	echo "Add the key to your $identity GitHub account. It's on your clipboard, and"
	echo "GitHub's new SSH key page is opening:"
	echo "  1. Check you're signed in to GitHub as your $identity account"
	echo "  2. Paste it with Key type 'Authentication Key' and save"
	echo "  3. Open the page again, paste it with Key type 'Signing Key' and save"
	[ "$identity" = personal ] || echo "  4. If the organization uses SSO, click 'Configure SSO' next to the key and authorize it"
	open https://github.com/settings/ssh/new
	while [ -z "$login" ] && read -rp "Press Enter once added (s to skip): " answer && [ "$answer" != s ]; do
		login=$(github_login)
		[ -n "$login" ] || echo "GitHub doesn't accept the key yet"
	done
fi

# gh keeps one login per GitHub account; the gh function in zsh/aliases.zsh
# reads github.user to pick the one for the folder you're in
if [ -n "$login" ]; then
	git config -f "$config" github.user "$login"
	if command -v gh >/dev/null && ! gh auth token --user "$login" >/dev/null 2>&1; then
		echo
		echo "Log the GitHub CLI in as $login. Its code goes on your clipboard; in the"
		echo "browser, switch to your $login account before you enter it."
		gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key --web --clipboard || true
		gh auth token --user "$login" >/dev/null 2>&1 || echo "gh isn't logged in as $login; rerun this setup to retry" >&2
	fi
fi

echo
echo "$identity: $name <$email>"
echo "  GitHub: ${login:-not connected yet, rerun this setup once the key is added}"
echo "  Repos:  clone into ${folder/#$HOME/~}/"
