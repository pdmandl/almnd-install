# almnd installer

Public installer for the private [`@pdmandl/almnd`](https://github.com/pdmandl/almnd-wrapper) package.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/pdmandl/almnd-install/main/install.sh)
```

Requires [Node 18+](https://nodejs.org) and the [GitHub CLI](https://cli.github.com).
The script signs you in via `gh`, configures npm for GitHub Packages, and installs
`almnd` globally. If you don't have access to the package yet, it helps you request it.

This repo holds only the installer — it contains no secrets. The tool's source is private.
