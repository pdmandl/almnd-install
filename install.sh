#!/usr/bin/env bash
#
# almnd installer. Sets up access to the private @pdmandl/almnd package on
# GitHub Packages and installs it globally. Paste a GitHub token when prompted,
# or (if the GitHub CLI is installed) press Enter to let it fetch one for you.
# If you don't have access to the package yet, it helps you request it.
#
#   curl -fsSL <this-url>/install.sh | bash
#   # or: bash install.sh
#
set -euo pipefail

SCOPE="@pdmandl"
PACKAGE="@pdmandl/almnd"
REGISTRY="npm.pkg.github.com"
REPO="pdmandl/almnd-wrapper"
OWNER_EMAIL="p.d.mandl@gmail.com"
NPMRC="$HOME/.npmrc"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[33m!\033[0m %s\n' "$1"; }
die()  { printf '\033[31m✖ %s\033[0m\n' "$1" >&2; exit 1; }

# --- prerequisites ---------------------------------------------------------
command -v node >/dev/null 2>&1 || die "Node.js 18+ is required — https://nodejs.org"
command -v npm  >/dev/null 2>&1 || die "npm is required (ships with Node.js)"
command -v curl >/dev/null 2>&1 || die "curl is required"

# --- obtain a GitHub token (read:packages) --------------------------------
# Priority: GITHUB_TOKEN env var → token pasted at the prompt → GitHub CLI.
# TOKEN_SRC records where it came from so the retry logic below knows whether
# a gh scope refresh could help.
TOKEN="${GITHUB_TOKEN:-}"
TOKEN_SRC="env"
if [ -z "$TOKEN" ]; then
  bold "A GitHub token with the 'read:packages' scope is needed to install ${PACKAGE}."
  echo  "Create one at: https://github.com/settings/tokens/new?scopes=read:packages&description=almnd"
  if command -v gh >/dev/null 2>&1; then
    printf 'Paste a token (input hidden), or press Enter to use the GitHub CLI: '
  else
    printf 'Paste your token (input hidden): '
  fi
  read -rs TOKEN </dev/tty || TOKEN=""
  echo
  TOKEN_SRC="input"
  if [ -z "$TOKEN" ]; then
    command -v gh >/dev/null 2>&1 || die "No token entered."
    gh auth status >/dev/null 2>&1 || gh auth login
    gh auth refresh -h github.com -s read:packages >/dev/null 2>&1 || true
    TOKEN="$(gh auth token)"
    TOKEN_SRC="gh"
  fi
fi
[ -n "$TOKEN" ] || die "No token available."

# --- identify the account (best-effort, for access requests) --------------
USERNAME="$(curl -fsSL -H "Authorization: Bearer $TOKEN" https://api.github.com/user 2>/dev/null \
  | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(String(JSON.parse(s).login||""))}catch{}})' || true)"
if [ -n "$USERNAME" ]; then ok "Authenticated as $USERNAME"; else USERNAME="unknown"; warn "Token accepted (couldn't read your username)"; fi

# --- write the npm config for the @pdmandl scope --------------------------
# Idempotent: strip any prior entries for this scope/registry before re-adding.
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

write_npmrc "$TOKEN"
ok "Configured $NPMRC for $SCOPE"

# --- try to install --------------------------------------------------------
attempt_install() { npm install -g "$PACKAGE" >/tmp/almnd-install.log 2>&1; }

bold "Installing ${PACKAGE}..."
if attempt_install; then
  ok "Installed. Try: almnd --version"
  exit 0
fi

# If the token came from gh, a missing read:packages scope is a likely cause —
# add it and retry once. (A pasted/env token can't be refreshed this way.)
if [ "$TOKEN_SRC" = "gh" ]; then
  warn "Install failed — adding the read:packages scope and retrying…"
  gh auth refresh -h github.com -s read:packages >/dev/null 2>&1 || true
  write_npmrc "$(gh auth token)"
  if attempt_install; then
    ok "Installed. Try: almnd --version"
    exit 0
  fi
fi

# --- still failing: bad token or no access to the package -----------------
warn "Couldn't install $PACKAGE. Your token may lack the 'read:packages' scope, or you don't have access to the package yet."
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
