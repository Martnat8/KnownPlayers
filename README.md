# KnownPlayers

A World of Warcraft **Forever** addon that remembers characters you encounter and customizes their nameplates based on how you know them.

**Version:** 0.1.7

**Tested target:** WoW Forever, interface `16001` (client-specific; standard retail compatibility is not established).

## Features

- Recognize players through trade, party, raid, guild, whispers, targeting, inspecting, and PvP attacks.
- Keep independently searchable player lists with individual removal and clear-list controls.
- Set optional, category-specific inactivity expiration (guild membership is exempt).
- Hide unknown player nameplates; choose health bars, name format, and guild name display.
- Customize category name colors and priority.
- Discover associated characters for Battle.net friends when the client exposes their active characters and a known character can be matched.

## Install

1. Download the release ZIP from the **Releases** page (once published).
2. Place the `KnownPlayers` folder into your WoW Forever `Interface/AddOns/` directory.
3. Enable the addon and use `/reload` if the game is running.
4. Open **Options → AddOns → KnownPlayers** to configure tracking, nameplates, and player lists.

The GitHub source archive contains repository files as well as the addon folder; install **only** the `KnownPlayers` folder.

## Commands

- `/kp options` — open settings
- `/kp status` — show version and stored record counts
- `/kp list` — display up to 10 saved records
- `/kp scan` — scan current party/raid
- `/kp guildscan` — request a guild roster scan
- `/kp help` — show all commands

## Privacy and saved data

The addon stores character names, realms, identifiers, interaction categories and timestamps in WoW **SavedVariables** on your computer. For linked Battle.net friends, it also stores BattleTags and observed character associations locally to support alt recognition across sessions. Unlinked friend observations are session-only. The addon does **not** upload this information.

**Do not publish or attach your personal SavedVariables files to bug reports.** To back up your lists, copy your SavedVariables before upgrading or using Clear All Lists.

## Limitations

- Battle.net alt recognition only works for available friend information; it cannot reveal every character on an account or discover strangers' alts.
- Nameplate compatibility with other UI addons and behavior during combat have not been comprehensively tested.
- Clearing lists is destructive; automatic tracking may subsequently add players again.

## Reporting issues

Open a GitHub Issue with the addon version, client build, reproducible steps, and the error text. Remove character names, BattleTags, and other personal information from logs or screenshots before sharing.

## Contributing

### Before every commit

**Every commit must update `CHANGELOG.md`**, including documentation, tests, and tooling changes. Add a concise, user-facing bullet to the `## [Unreleased]` section explaining what changed, then stage it with your other changes. Keep existing release sections intact; do not rewrite published history or put private player data in the changelog. CI checks every commit in a pull request, not just the combined diff. If several commits need correcting, amend/rebase them before requesting review.

Enable the shared, committed Git hook after cloning (Git does not install hooks automatically):

```sh
git config --local core.hooksPath .githooks
```

The hook at `.githooks/pre-commit` uses the committed `scripts/check-changelog.sh` to check the **staged** changelog. This setup is opt-in and local to each clone, so contributors and the repository owner can use the same hook. CI also catches commits made without the hook. Run the dependency-free tooling tests with Node.js 22 or newer:

```sh
node --test scripts/*.test.mjs
node scripts/check-version.mjs
```

### Versioning

`VERSION` is the source of truth. We follow SemVer's `MAJOR.MINOR.PATCH` rules: patch for fixes, minor for backward-compatible features, and major for breaking changes. Pre-releases use the project's compact `bN` suffix (for example, `0.1.14b3`), rather than SemVer's standard hyphenated spelling. `N` starts at `0` for each new target production version and increases monotonically. Production versions, tags, and published release contents are immutable: fix mistakes in a new version; never move/delete/reuse a release tag or replace its assets.

Do not bump versions or create release tags in a pull request. The PR guard requires the version to remain equal to the base branch's version. This initial tooling setup adds `VERSION` at the existing addon version, not a new release. Only the repository owner creates and publishes releases, directly on `main`, after merging contributions.

### Creating a release (repository owner only)

1. Enable the hook above. Commit all changes, including descriptive notes under `[Unreleased]`, and start with a clean `main` checkout synchronized with `origin/main` (including no untracked files).
2. With Git and Node.js 22+ installed and `origin` reachable, run:

   ```sh
   node scripts/release.mjs dev minor  # e.g. 0.1.7 -> 0.2.0b0
   # OR:
   node scripts/release.mjs prod       # e.g. 0.1.7 -> 0.1.8
   ```

   The required first argument is `prod` or `dev`. The optional second argument is `patch` (default), `minor`, or `major`. From a production version, either release type bumps that component and resets lower components; `dev` also appends `b0`. From a pre-release, the second argument is ignored: `dev` increments only `N` (e.g. `0.2.0b0 -> 0.2.0b1`), while `prod` removes the suffix without another bump (`0.2.0b1 -> 0.2.0`).

3. The helper updates `VERSION`, the TOC, the Lua runtime version, and both README version headers. It moves the `[Unreleased]` notes into a dated version section, leaves a fresh `[Unreleased]` section, commits as `[release] VERSION`, and creates an annotated `vVERSION` tag. Historical version mentions remain unchanged. It refuses inconsistent metadata, empty release notes, dirty worktrees, and conflicting local/remote tags. It never pushes or overwrites a release.
4. Review the commit and tag, then push them together using the command printed by the helper, for example:

   ```sh
   git push --atomic origin main v0.2.0b0
   ```

   The owner's tag push runs validation and publishes the installable ZIP with the **full `CHANGELOG.md` contents** as the release description. Tags with a `bN` suffix are marked as GitHub pre-releases. Other actors cannot publish through this workflow.

Repository-owner setup on GitHub: require the `pr-version` and `changelog` checks (and validation) in the `main` branch ruleset. Add a tag ruleset for `v*` restricting creation to the owner and blocking updates/deletions, and enable immutable GitHub releases where available. Workflow conditions alone cannot prevent someone with repository administration/release permissions from manually editing releases or tags. Local hooks also cannot authenticate GitHub account ownership; publishing authorization is enforced by the workflow and repository rules.
