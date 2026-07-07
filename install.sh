#!/usr/bin/env bash
#
# almnd installer. Sets up access to the private @pdmandl/almnd package on
# GitHub Packages and installs it globally. If you don't have access yet, it
# helps you request it — you shouldn't need to do anything else by hand.
#
#   curl -fsSL <this-url>/install.sh | bash
#   # or: bash install.sh
#
set -euo pipefail

SCOPE="@pdmandl"
PACKAGE="@pdmandl/almnd"
REGISTRY="npm.pkg.github.com"
REPO="pdmandl/almnd-wrapper"
OWNER_EMAIL="paul.mandl@findustrial.io"
NPMRC="$HOME/.npmrc"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[33m!\033[0m %s\n' "$1"; }
die()  { printf '\033[31m✖ %s\033[0m\n' "$1" >&2; exit 1; }

# --- prerequisites ---------------------------------------------------------
command -v node >/dev/null 2>&1 || die "Node.js 18+ is required — https://nodejs.org"
command -v npm  >/dev/null 2>&1 || die "npm is required (ships with Node.js)"
command -v gh   >/dev/null 2>&1 || die "GitHub CLI (gh) is required — https://cli.github.com"

# --- authenticate with GitHub ---------------------------------------------
if ! gh auth status >/dev/null 2>&1; then
  bold "Signing in to GitHub…"
  gh auth login
fi
USERNAME="$(gh api user --jq .login 2>/dev/null || echo "unknown")"
ok "Authenticated as $USERNAME"

# --- write the npm config for the @pdmandl scope --------------------------
# Reads the token from gh so no PAT has to be created by hand. Idempotent:
# strip any prior entries for this scope/registry before re-adding them.
write_npmrc() {
  local token="$1"
  touch "$NPMRC"
  grep -v -e "^${SCOPE}:registry=" -e "//${REGISTRY}/:_authToken=" "$NPMRC" > "$NPMRC.tmp" 2>/dev/null || true
  mv "$NPMRC.tmp" "$NPMRC"
  {
    echo "${SCOPE}:registry=https://${REGISTRY}"
    echo "//${REGISTRY}/:_authToken=${token}"
  } >> "$NPMRC"
}

write_npmrc "$(gh auth token)"
ok "Configured $NPMRC for $SCOPE"

# --- try to install --------------------------------------------------------
attempt_install() { npm install -g "$PACKAGE" >/tmp/almnd-install.log 2>&1; }

bold "Installing ${PACKAGE}..."
if attempt_install; then
  ok "Installed. Try: almnd --version"
  exit 0
fi

# First failure is often a missing read:packages scope on the gh token — add it and retry once.
warn "Install failed — refreshing GitHub permissions and retrying…"
gh auth refresh -h github.com -s read:packages >/dev/null 2>&1 || true
write_npmrc "$(gh auth token)"
if attempt_install; then
  ok "Installed. Try: almnd --version"
  exit 0
fi

# --- still failing: you probably don't have access to the package ---------
warn "Couldn't install $PACKAGE. You most likely don't have access yet."
echo
printf '%s' "Request access now (opens/prepares an email to the maintainer)? [Y/n] "
read -r ans </dev/tty || ans="y"
case "${ans:-y}" in
  n|N) ;;
  *)
    subject="almnd: access request for ${PACKAGE}"
    body="Hi,%0A%0APlease grant my GitHub account read access to the ${PACKAGE} package.%0A%0AGitHub username: ${USERNAME}%0A%0AThanks!"
    url="mailto:${OWNER_EMAIL}?subject=$(printf '%s' "$subject" | sed 's/ /%20/g')&body=${body}"
    if command -v open >/dev/null 2>&1; then open "$url" >/dev/null 2>&1 || true       # macOS
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 || true  # Linux
    fi
    echo
    bold "Send this to $OWNER_EMAIL if the email didn't open:"
    echo "  Please grant GitHub user '$USERNAME' read access to $PACKAGE."
    ;;
esac
echo
echo "Once you've been granted access, re-run this installer and you're done."
echo "(Install log: /tmp/almnd-install.log)"
exit 1
