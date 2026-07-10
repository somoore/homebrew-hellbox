# homebrew-hellbox

Homebrew tap for [Hellbox](https://github.com/somoore/hellbox) — DOOM inside an
AWS Lambda MicroVM.

```bash
brew install somoore/hellbox/hellbox   # install
brew upgrade hellbox                   # update
brew uninstall hellbox                 # remove
```

Then clone the repo and play:

```bash
git clone https://github.com/somoore/hellbox
cd hellbox && ./deploy.sh   # picks up the brew-installed binary
```

## How this tap stays fresh and trustworthy

`.github/workflows/update-formula.yml` polls the hellbox releases every six
hours. Before pinning new SHA256s into the formula it verifies each binary's
GitHub build-provenance attestation against the hellbox release workflow and
the release tag — a tampered asset fails verification and never reaches the
formula. Homebrew then enforces those SHA256s on every install.
