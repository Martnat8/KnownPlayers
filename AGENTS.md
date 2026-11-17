# Agent instructions

## Project and development environment

- KnownPlayers is a WoW Forever addon targeting interface `16001` and Lua 5.1. The game provides its runtime APIs; local Lua checks cannot replace in-game testing.
- Use `nix develop` for Node.js 22, Lua 5.1 (`lua`/`luac`), Git, Bash, ZIP, Actionlint, and ShellCheck. No npm or external Lua packages are needed.
- `flake.nix` uses Determinate's weekly nixpkgs distribution on FlakeHub; preserve this source and the reproducible `flake.lock`. Supported systems are x86-64/ARM64 Linux and Apple Silicon macOS, not Intel macOS with the current snapshot.
- `.envrc` supports optional direnv + nix-direnv (`direnv allow`). `.direnv/` and Nix `result` links are ignored. Do not install hooks or change local configuration without permission.
- Entering the shell does not install hooks. When authorized, enable the committed `.githooks/pre-commit` with `git config --local core.hooksPath .githooks`; it calls the shared `scripts/check-changelog.sh`.
- For intentional dependency updates, run `nix flake update`, validate the shell, and include the lock-file change and a changelog entry. Git-backed flakes ignore untracked files; stage new flake files when authorized, or use `nix develop path:.` while checking untracked changes.

## Validation and change safety

- Inspect the working tree before editing; keep changes focused and preserve unrelated user work. Do not commit, tag, push, or publish without the user's authorization.
- Run relevant checks inside the development shell; these are the repository's validation commands:
  - Release tooling: `node --test scripts/*.test.mjs`.
  - Version/changelog consistency: `node scripts/check-version.mjs` (set `TAG=vVERSION` to validate a release tag).
  - Lua syntax: `find KnownPlayers -type f -name '*.lua' -exec luac -p {} +`.
  - Workflow lint: `actionlint .github/workflows/release.yml`.
  - Shell lint: `shellcheck scripts/check-changelog.sh .githooks/pre-commit`.
  - Nix changes: `nix flake check --all-systems --no-build`, then exercise affected commands with `nix develop -c ...`.
- Fix relevant failures before declaring completion; distinguish syntax/tooling checks from actual in-game testing. Never execute a release helper merely to test it against the real repository; regression tests use temporary Git repositories.
- Never publish SavedVariables, character names, BattleTags, credentials, or other private data in code, changelogs, logs, screenshots, or issue reports.

## Changelog and commits

- **Every commit must update `CHANGELOG.md` before committing**, including documentation, tests, tooling, and release commits.
- Add a concise, descriptive bullet under `## [Unreleased]` and stage the changelog with the corresponding changes. Preserve existing release sections and published history; do not log private player data.
- The shared pre-commit hook checks the staged changelog, not unstaged edits. CI checks every commit in a PR/push, not only the combined diff; do not bypass these safeguards.
- Keep `VERSION` and all version-bearing metadata unchanged in pull requests. The `pr-version` job rejects version changes; only the project owner creates releases after contributions are merged.

## Versioning and release helper

- `VERSION` is the source of truth. Follow SemVer's `MAJOR.MINOR.PATCH` rules: patch for fixes, minor for backward-compatible features, major for breaking changes; reset lower components when bumping.
- Pre-releases use the project's compact `bN` suffix, not standard SemVer's hyphenated spelling: e.g. `0.1.14b3`. Start at `b0` for each new target production version and increase `N` monotonically.
- Production versions, release tags, and published assets are immutable. Never move, delete, reuse, or overwrite a published release; fix mistakes with a new version.
- Use `node scripts/release.mjs <prod|dev> [patch|minor|major]`; the release type is required, the bump type defaults to `patch`, and a supplied bump type must be valid even when ignored.
  - From production: bump the selected component; `prod` stays unsuffixed, while `dev` appends `b0`.
  - From a pre-release: ignore the bump type; `dev` increments only `N`, and `prod` removes the suffix without another numeric bump.
- The helper synchronizes `VERSION`, `KnownPlayers/KnownPlayers.toc`, `KnownPlayers/Core.lua`, and the version headers in `README.md` and `KnownPlayers/README.txt`; historical version mentions remain unchanged.
- It moves `[Unreleased]` notes into a dated version section, leaves a fresh `[Unreleased]` section, creates commit `[release] VERSION`, and creates annotated tag `vVERSION`. It requires release-note bullets, consistent metadata, a clean `main` worktree/index (including no untracked files), and reachable `origin`; it refuses conflicting local/remote tags and never pushes.
- If Git fails after staging or committing, inspect `git status`, `git log`, and tags before retrying. Do not discard work or reset history automatically.

## Project owner and release consent

- The project owner's GitHub username is **`Martnat8`**. A fork's namespace is not proof of project ownership.
- Inspect authenticated account metadata when deciding whether owner-only instructions apply: if GitHub CLI is available, use `gh api user --jq .login` for the current GitHub host/account. Compare logins case-insensitively. Do not infer identity from the OS username, Git author name/email, or remote URL; never dump environment variables or tokens to identify an account.
- If authentication is unavailable or inconclusive, ask the user to confirm their GitHub username before treating them as the owner. Do not install/authenticate GitHub CLI or change accounts without permission.
- **When the user is identified as `Martnat8`, after completing requested contribution work, ask: "Would you like to create a new release? If so, should it be a pre-release or a production release?"** Wait for an explicit answer; do not assume a release is wanted.
- If the user is not `Martnat8`, follow the contributor/PR workflow; do not offer or perform an owner-only release on their behalf.
- If the owner requests a release, map pre-release to `dev` and production to `prod`. When the current version is production, confirm the appropriate patch/minor/major bump (default patch); when already a pre-release, explain that the helper ignores that argument. Show the proposed version before running the helper.
- Before releasing, ensure approved changes and their changelog notes are committed, `main` is synchronized with the intended remote, and checks pass. Confirm the target repository: the publishing workflow additionally requires the tagging actor to equal `github.repository_owner`; do not relax authorization guards or publish to a fork accidentally.
- After creating the approved local release commit/tag, ask separately before pushing. Use an atomic push such as `git push --atomic origin main vVERSION`, never force-push a release tag.
- Owner-pushed tags trigger validation and packaging; GitHub release descriptions use the full `CHANGELOG.md`, and `bN` tags are marked as pre-releases. Publishing is tag-triggered, not triggered by ordinary PR merges.
- Repository settings must require `pr-version`, `changelog`, and validation on `main`, restrict `v*` tag creation to the owner, block tag updates/deletions, and enable immutable GitHub releases where available. Workflow checks cannot prevent administrators from manually editing releases; do not claim otherwise.
