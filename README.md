# KnownPlayers

A World of Warcraft **Forever** addon that remembers characters you encounter and customizes their nameplates based on how you know them.

**Version:** 0.4.5b1

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

Bug fixes, features, and documentation improvements are welcome. Make focused changes and open a pull request describing what changed and how you tested it.

Run `nix develop` to get Node.js 22, Lua 5.1, and the other development tools, or install them yourself. After cloning, enable the shared commit hook:

```sh
git config --local core.hooksPath .githooks
```

**Update `CHANGELOG.md` before every commit.** Add a short bullet under `[Unreleased]` explaining your change, and stage it with your other files. Leave published release notes unchanged.

Before opening a pull request, run these checks from the development shell:

```sh
node --test scripts/*.test.mjs
node scripts/check-version.mjs
find KnownPlayers -type f -name '*.lua' -exec luac -p {} +
```

We use `MAJOR.MINOR.PATCH` versioning: fixes bump patch, backward-compatible features bump minor, and breaking changes bump major. Pre-releases append `b0`, `b1`, and so on (for example, `0.1.14b3`), starting at zero for each target version. Production releases are immutable. Keep version numbers unchanged in pull requests; [Martnat8](https://github.com/Martnat8) handles releases.

Detailed guidance for coding assistants is in [AGENTS.md](AGENTS.md).
