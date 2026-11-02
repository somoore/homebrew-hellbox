# homebrew-hellbox — security findings (adjudicated)

**Scanned:** `somoore/homebrew-hellbox` at commit `2441cb4` ("chore: add Apache-2.0 LICENSE"),
2026-11-02. All 4 tracked files: `.github/workflows/update-formula.yml`, `Formula/hellbox.rb`,
`README.md`, `LICENSE`. No vendored code, generated dirs, or build output.

**Tools:** semgrep 1.183.0 (0 results), trivy 0.76.1 repo + config (0 results), gitleaks 8.30.1
(worktree: no leaks; history: `[]`), actionlint 1.7.12, shellcheck 0.11.0, `ruby -c`,
plus a manual behavioural replay of the workflow steps (stubbed `gh`/`curl`/`sha256sum`).

**Team roles:** PM (scope/priorities), AppSec (breadth), pentest (reachability), devil's advocate
(verdicts), QA (verification plan). The review is consolidated in
`/Users/scottmoore/github/.security-scan/homebrew-hellbox/TEAM.md`; per-role files were not present,
so `TEAM.md` plus the scanner JSON was the adjudication input. Scanner output contained nothing the
team missed.

**Baseline:** no test suite, no CI on PRs, `ruby -c Formula/hellbox.rb` → `Syntax OK`.

## Findings

| ID | Severity | Status | Location | Issue | Fix | Verification |
|----|----------|--------|----------|-------|-----|--------------|
| SEC-01 | MEDIUM | **FIXED** | `.github/workflows/update-formula.yml:67-73` (gate set), `:83`, `:157` | The "assets still publishing" path was `exit 0`, so the download step *succeeded* after `changed=true` was already emitted. The regenerate and PR steps ran with empty (or 1-of-4) `SHA_*` values, producing a PR whose formula contained `sha256 ""`. An empty/crashed `gh release view` tag gave `version ""` the same way. | On fetch failure write `skip=true` to `$GITHUB_OUTPUT` before `exit 0`; both later steps are now gated on `steps.rel.outputs.changed == 'true' && steps.sums.outputs.skip != 'true'` (`!= 'true'` so a skipped/empty step still behaves correctly). Regenerate additionally asserts `TAG`/`VERSION` are set, re-validates the tag, and requires all four hashes to match `^[0-9a-f]{64}$` before the heredoc, so a partial sum set can never be written. The resolve step now runs `set -euo pipefail`, so a failed/empty `gh release view` fails loudly instead of emitting `version ""`. | `script/test-guards.sh` → all pass (empty, truncated and uppercase hashes rejected). Behavioural replay with a stubbed `curl` that 404s the 4th asset: download step exits 0 with `skip=true`; `:83`/`:157` both require `skip != 'true'`. Replay with one empty hash: regenerate exits 1 and `Formula/hellbox.rb` is byte-identical (unchanged). Valid replay regenerates a file byte-identical to the committed formula. |
| SEC-02 | LOW | **FIXED** | `.github/workflows/update-formula.yml:32-37`, `:98-100`; new `script/check-release-inputs.sh` | `TAG`/`VERSION` came straight from the hellbox release tag and were interpolated into the generated Ruby inside double-quoted literals. Git refs may legally contain `#`, `{`, `}`, `` ` ``, `"`, `;`, `$`, `(`, `)`, so a tag like ``v1.0.0#{`id`}`` broke out of the string and ran at formula-load time (`brew info`/`brew install`). Attestation verification bounds who can mint such a tag, hence LOW, but it widened "trusted binary" to "trusted code in the tap". | New `script/check-release-inputs.sh tag <TAG>` accepts only `^v?[0-9]+\.[0-9]+\.[0-9]+([-+.][0-9A-Za-z.]+)?$` and derives `VERSION` from it with the same character allowlist. Called in the resolve step (fails before any output is written) and again in regenerate (before the heredoc). `sha256` subcommand validates hash shape. The heredoc stays unquoted but can now only receive `[0-9A-Za-z.+-]` from tag/version and 64-hex hashes. | `script/test-guards.sh`: `v1.0.0#{`id`}`, `v1.0.0";system("id")`, `v1.0.0/a`, `""`, `v1.0` all rejected (exit 1); `v1.0.27` and `v1.0.0-rc.1` accepted. Replay of the resolve step with a hostile tag prints `unexpected release tag` and exits 1 with no outputs; regenerate with hostile `TAG`/`VERSION` exits 1 and leaves the formula unchanged. Validator also rejects an artifact containing `version "1.0.27#{`id`}"`. |
| SEC-03 | LOW | **FIXED** | new `.github/workflows/validate.yml`; new `script/validate-formula.sh`; new `script/test-guards.sh` | Nothing parsed or linted the machine-written formula before it reached a merge candidate; the only gate was a human reading a diff labelled "attestation-verified". This is what let SEC-01 become a merge candidate. | Added `validate.yml` on `pull_request` and `push` to `main` (`permissions: contents: read`, `actions/checkout` SHA-pinned, concurrency-cancelled). It runs the guard regression tests, then `script/validate-formula.sh`: `ruby -c`; exactly 4 `sha256 "<64 lowercase hex>"` pins and no `:no_check`; exactly one `version`; every `url` points at `…/releases/download/v<version>/`. Independent of `brew`, so the gate cannot be flaky. | `script/test-guards.sh` → 19/19 pass, including committed formula passes and 6 mutated formulas fail. `script/validate-formula.sh Formula/hellbox.rb` → `formula OK: valid Ruby, 4 sha256 pins, version 1.0.27 matches every url`. `actionlint` → exit 0 on both workflows. |
| SEC-04 | INFO | ACCEPTED RISK | `.github/workflows/update-formula.yml:12-14`, `:24`, `:170` | Workflow-wide `contents: write` + `pull-requests: write` are inherited by the download/hash step; checkout persists the token; the job force-pushes. | Not fixed (devil's advocate verdict, and it is the minimum scope needed to create a branch and PR). Nothing downloaded is executed, and the force-push ref is a bot-owned `tap-bump-<version>`. | Reviewed control flow; no privilege escalation path found. Residual noted below. |
| SEC-05 | INFO | ACCEPTED RISK | `.github/workflows/update-formula.yml:22`, `:58-62`, `:76` | `ubuntu-latest` and the runner-provided `gh`/`curl`/`sha256sum` that perform the integrity decision are mutable inputs. | Not fixed. The new `validate.yml` pins `ubuntu-24.04`; pinning `gh` or rebuilding it would be disproportionate for a tap. | Reviewed; `actions/checkout` remains SHA-pinned in both workflows. |
| SEC-06 | INFO | ACCEPTED RISK | `.github/workflows/update-formula.yml:76-78` | `gh attestation verify` binds artifact → workflow + tag but not the builder (self-hosted runner or any file revision at that tag is accepted). | Not fixed: inherent transitive trust. Documented here instead of widening scope. | Reviewed attestation arguments: repo, signer workflow and source-ref are all specified. |
| SEC-07 | INFO | ACCEPTED RISK | `Formula/hellbox.rb:43`, `README.md:15-16` | Caveats tell users to clone the default branch and run `./deploy.sh` with their AWS credentials — unpinned code execution. | Not fixed: it is the product's documented install flow and the fix is a product decision. Changing it would break documented behaviour. | Reviewed rendered caveats/README; no change made. |
| FP-01 | — | FALSE POSITIVE | `.github/workflows/update-formula.yml` `run:` blocks | "Shell/command injection via `TAG`/`VERSION`." | Not fixed. | Every expansion was quoted and there is no `eval`/`sh -c`; expanding a variable never re-parses backticks or `$(…)`. The real sink was Ruby (SEC-02). |
| FP-02 | — | FALSE POSITIVE | `:34-35`, `:71` | "`GITHUB_OUTPUT` injection / multiline output forging." | Not fixed. | Git forbids control characters in ref names, so no newline can reach `$GITHUB_OUTPUT`; `gh attestation verify` must also pass first. |
| FP-03 | — | FALSE POSITIVE | `:60-61` | "SSRF / open redirect via the asset URL." | Not fixed. | Scheme and host are hardcoded to `github.com`; ref charset forbids `..` and `?`; `curl` sends no credentials. |
| FP-04 | — | FALSE POSITIVE | `Formula/hellbox.rb:36` | "Formula installs arbitrary files via `Dir["hellbox-*"].first`." | Not fixed. | Asset names are literals in the workflow and Homebrew stages exactly one file per platform. (Cosmetic only: `.first` on an empty glob raises.) |
| FP-05 | — | FALSE POSITIVE | `Formula/hellbox.rb:48-50` | "`brew test` executes an unverified download." | Not fixed. | `install` only copies; the `--version` run happens in `brew test`, after Homebrew's pinned-SHA256 check. |
| FP-06 | — | FALSE POSITIVE | `:29`, `:46`, `:159` | "Hardcoded secret in the workflow." | Not fixed. | `GH_TOKEN: ${{ github.token }}` is the ephemeral job token passed to the two steps that call `gh`; no PAT, no long-lived secret, none in history (`gitleaks` history: `[]`). |
| FP-07 | — | FALSE POSITIVE | `Formula/hellbox.rb:16,20,27,31` | "Weak/truncated checksums." | Not fixed. | Four distinct 64-hex SHA-256 values, consistent across the per-version history. |
| FP-08 | — | FALSE POSITIVE | `.github/workflows/*` | "Pwn-request via `pull_request_target`." | Not fixed. | No such trigger exists. The new `validate.yml` uses `pull_request` only and checks out no PR code beyond the repo itself. |

## Residual risk

- **SEC-03 is only effective if branch protection requires the new check.** `main` protection and
  `CODEOWNERS` are repository settings, not files in this tree, and this task forbids commits/pushes.
  The owner must add "validate / formula" as a required status check on `main` (and, ideally,
  `CODEOWNERS` for `Formula/`). Until then the workflow runs and reports, but does not block a merge.
- **SEC-01 defence in depth relies on two layers.** The primary fix is the `skip` output/gate; the
  second is the hash assertion inside the regenerate step. A future edit that inserts a new step
  between download and regenerate must also gate on `skip != 'true'`. The hash assertion still
  prevents the empty-hash artifact itself from being written.
- **SEC-02 uses an allowlist of tag shapes.** If hellbox changes its tag scheme (e.g.
  `release-2026.1`), the updater fails loudly and opens no PR — safe, but it will need a one-line
  regex update in `script/check-release-inputs.sh`.
- **`brew audit --strict` is not in CI.** It needs a real tap install (`brew tap somoore/hellbox
  "$GITHUB_WORKSPACE"`) and, as noted in `TEAM.md`, it can re-resolve Homebrew's own bundle, which
  makes it a flaky gate. The added validator covers syntax, pin count, hash shape, `:no_check` and
  version/URL consistency without `brew`. `actionlint` is not run in CI either, to avoid adding a
  third-party action that cannot be archived-verified offline; it passes locally (exit 0).
- **SEC-04/SEC-05/SEC-06/SEC-07 remain accepted risks** as adjudicated: workflow-wide write
  permission inherited by the download step, mutable `ubuntu-latest` + runner-provided `gh`, the
  unbounded attestation builder identity, and the documented unpinned `deploy.sh` install flow.
- **No owner-rotation actions are required:** no secret was found in the working tree or history, so
  nothing needs rotating.
- `Formula/hellbox.rb` was **not** edited by hand; it was regenerated by the fixed template during
  verification and came out byte-identical. `LICENSE` untouched.

## Verification commands (all run in the repo, 2026-11-02)

```
ruby -c Formula/hellbox.rb                              # Syntax OK
./script/test-guards.sh                                 # 19/19 ok, exit 0
./script/validate-formula.sh Formula/hellbox.rb         # formula OK: valid Ruby, 4 sha256 pins, version 1.0.27 matches every url
actionlint                                              # exit 0 (both workflows)
shellcheck script/*.sh                                  # exit 0
gitleaks detect --no-git --redact                        # no leaks found
```

Behavioural replay (stubbed `gh`/`curl`/`sleep`/`sha256sum`, ad-hoc, not committed): hostile tag →
resolve exits 1, no outputs; empty tag → resolve exits 1, no outputs; 4th asset 404 → download exits
0 with `skip=true`; one empty hash → regenerate exits 1 with the formula unchanged; valid inputs →
regenerated formula byte-identical to the committed one; gate conditions at `:83` and `:157` both
include `steps.sums.outputs.skip != 'true'`.
