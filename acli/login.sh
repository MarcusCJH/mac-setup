#!/bin/bash
# Log acli (Jira and Confluence) in to one git identity's Atlassian account with
# an API token; rerun it to change that account or replace an expired token.
#   make acli  ->  acli/login.sh, which asks for the identity
# acli stores the token itself (in the login Keychain), and nothing else does.
# The site, email and acli's profile ids go in ~/.acli-<identity>, where the acli
# function in zsh/aliases.zsh reads them to switch to that account inside
# ~/Documents/git/<identity>/ (personal's is used everywhere else).
set -euo pipefail

command -v acli >/dev/null || { echo "Needs acli, from the work Brewfile: make work" >&2; exit 1; }

# ask <question> <default>: print the answer, or the default when left blank
ask() {
	local answer=
	read -rp "$1${2:+ [$2]}: " answer || true
	echo "${answer:-$2}"
}

identity=${1:-}
if [ -z "$identity" ]; then
	echo "Identities on this Mac: $(ls "$HOME"/.ssh/github-*.pub 2>/dev/null | sed 's|.*/github-||; s|\.pub$||' | xargs)"
	identity=$(ask "Identity whose Atlassian account this is" "")
fi
config=$HOME/.acli-$identity
[ -n "$identity" ] && [ -f "$HOME/.ssh/github-$identity.pub" ] || { echo "No '$identity' identity; set it up first with make git-work" >&2; exit 1; }

echo
echo "== $identity Atlassian account"
site=$(ask "Site, e.g. acme.atlassian.net" "$(git config -f "$config" atlassian.site 2>/dev/null || true)")
# Accept a pasted URL, or just the name before .atlassian.net
site=${site#*://}
site=${site%%/*}
case $site in
	"") echo "The site is required" >&2; exit 1 ;;
	*.*) ;;
	*) site=$site.atlassian.net ;;
esac
email=$(ask "Email" "$(git config -f "$config" atlassian.email 2>/dev/null || git config -f "$HOME/.gitconfig-$identity" user.email 2>/dev/null || true)")
[ -n "$email" ] || { echo "The email is required" >&2; exit 1; }

echo
echo "Create an API token. Atlassian's API tokens page is opening:"
echo "  1. Check you're signed in to Atlassian as $email"
echo "  2. Click 'Create API token' (not the one with scopes), name it e.g. acli-$identity, and copy it"
open https://id.atlassian.com/manage-profile/security/api-tokens
read -rsp "Paste the token (hidden): " token || true
echo
[ -n "$token" ] || { echo "No token, nothing changed" >&2; exit 1; }

cat > "$config" <<EOF
# $identity's Atlassian account for acli, written by acli/login.sh; rerun it to change
[atlassian]
	site = $site
	email = $email
EOF
# atlassian.<product> holds acli's current_profile for the account, so the acli
# function can skip switching (a network call) when it's already active; an
# unreadable one is saved as "unknown", which makes it switch every time
products=
for product in jira confluence; do
	if printf '%s' "$token" | acli "$product" auth login --site "$site" --email "$email" --token &&
		acli "$product" auth switch --site "$site" --email "$email" >/dev/null; then
		profile=$(sed -n 's/^current_profile: //p' "$HOME/.config/acli/${product}_config.yaml" 2>/dev/null || true)
		git config -f "$config" "atlassian.$product" "${profile:-unknown}"
		products="$products $product"
	else
		echo "No $product login; that's fine if $site doesn't use it" >&2
	fi
done
[ -n "$products" ] || { echo "acli couldn't log in; check the site, email and token, then rerun" >&2; exit 1; }

echo
echo "$identity: $email on $site"
echo "  acli:$products"
