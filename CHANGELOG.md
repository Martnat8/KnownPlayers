# Changelog

## [Unreleased]

- Clarified the NPC Management description to say “Search manually saved NPCs.”
- Kept attackable NPC nameplates visible by default when automatic NPC filtering is enabled and restored the game's hostile NPC name setting on upgrade.

## [0.4.5b4] - 2026-11-21

- Fixed a startup error after PvP removal by sizing the player nameplate color-priority list to the available categories.

## [0.4.5b3] - 2026-11-21

- Removed PvP attacker tracking, its controls, and its player-list category. TODO: Revisit PvP tracking when it can be tested in WoW Forever.
- Made `/kp remember` use the same identity checks as the portrait menu and explain when the targeted player cannot be identified.
- Cleared old Guild reasons on confirmed guild departures and switches while preserving other encounter reasons.

## [0.4.5b2] - 2026-11-21

- Paused automatic NPC filtering when QuestieDB is unavailable and kept unclassified NPCs visible while honoring manual overrides.

## [0.4.5b1] - 2026-11-21

- Added player and NPC nameplate distance and minimum opacity sliders to the main settings page.

## [0.4.5b0] - 2026-11-21
- Restored the packaged README header format expected by release validation.
- Synchronized all version metadata to 0.4.4.

## 0.4.4
- Added NPC visibility overrides: **Always Show**, **Always Hide**, and **Automatic**, accessible from NPC portrait right-click menus.
- Added a searchable NPC Manager for manually remembered NPCs and NPCs with visibility overrides, including category filters and management actions.
- Colored the QuestieDB connection status green when connected and red when unavailable or incompatible.
- Preserved Blizzard's native nameplate font and layout for standard full-name displays; custom name, guild, and NPC-title labels now track the native font size and effective scale.
- Kept NPC override records separate from QuestieDB classifications; automatic NPC encounter history is not stored.

## 0.4.3
- Added customizable NPC category color priority, organized like the player category priority list.
- Added numbered rows with category enable checkboxes, color previews, and up/down priority buttons.
- Made the highest-priority enabled role determine the color of NPCs with multiple services.
- Preserved existing NPC colors and category preferences, with the previous fixed priority order used as the default.

## 0.4.2
- Removed the bundled 83-NPC reference database and fallback classification logic.
- Made QuestieDB the exclusive source of automatic NPC service classifications; manually remembered NPCs remain available without it.
- Added a QuestieDB bridge/dependency notice and connection status to the NPC settings page.
- Added persistent, customizable NPC nameplate colors for service categories and Manually Added NPCs.

## 0.4.1
- Integrated QuestieDB as an optional external source of NPC classifications using its public API.
- Added on-demand recognition of NPC service roles and quest-related NPCs, with cached lookups.
- Retained the built-in NPC subset as a fallback when QuestieDB was unavailable or lacked an entry.
- Added `/kp npcsource` to report the NPC data-source connection status.

## 0.4.0
- Introduced an initial, limited built-in database of 83 Classic NPC IDs and service classifications.
- Added NPC category toggles for vendors, trainers, bankers, auctioneers, flight masters, innkeepers, repair NPCs, quest NPCs, and manually remembered NPCs.
- Supported NPCs belonging to multiple service categories without duplicating saved records.
- Kept automatic service classifications separate from manually remembered NPC records.

## 0.3.6
- Reorganized the Player Nameplates & Lists appearance controls into aligned **Character Name** and **Health Bar** sections.
- Improved spacing and visual dividers without changing nameplate behavior.

## 0.3.5
- Replaced the player Show Health Bar checkbox with **Always**, **In Combat**, and **Never** modes.
- Preserved existing health-bar preferences when upgrading.
- Added combat-state refresh handling, with protected-frame restrictions noted for the experimental In Combat mode.

## 0.3.4
- Removed the unreliable manual Add Player text input and button.
- Moved Player Lists upward to remove unused space.
- Retained portrait right-click **Remember Player** and `/kp remember` as the supported manual-add methods.

## 0.3.3
- Attempted to improve manual text-entry recognition by resolving nearby players against their observed names, realms, and GUIDs.
- Changed Reset Settings to Defaults to refresh controls and nameplates without reloading the UI.
- Preserved player and NPC records when resetting preferences.

## 0.3.2
- Normalized same-realm player-name variants using spaces or hyphens, reducing duplicate player records.
- Added migration to merge compatible duplicate histories while preserving interaction reasons and timestamps; conflicting GUIDs remain separate.
- Replaced the player-list **Reasons** button with an immediate **Remove** action for the whole player record.
- Improved matching and searching for names containing spaces or hyphens.

## 0.3.1
- Moved player forgetting toggles and durations from the main settings page to Player Nameplates & Lists, below category colors and priority.
- Tightened retention-row spacing to match the priority controls.
- Added a manual player-name entry field and **Add Player** button (removed in 0.3.4).

## 0.3.0
- Reorganized settings into **KnownPlayers**, **Player Nameplates & Lists**, and **NPC Nameplates & Lists** pages.
- Moved player appearance, category colors and priority, and searchable player lists to the player page.
- Moved NPC appearance, remembered NPC lists, and NPC inactivity controls to the NPC page.
- Set new-install inactivity-forgetting defaults to enabled at 30 days for applicable player interactions and manually remembered NPCs; preserved existing saved preferences.
- Kept guild membership roster-based rather than subject to inactivity expiration.
- Added category filters to the unified player-list window.

## 0.2.1
- Consolidated player interaction histories into one character-keyed table with multiple recognition reasons.
- Added a distinct **Manually Added** player reason and player-portrait right-click actions.
- Added a unified All Players list and controls to inspect or remove recognition reasons.
- Added guild-roster reconciliation when opening the Guild list: remove stale Guild reasons without deleting other interaction history.
- Preserved records when a refreshed guild roster was empty or incomplete.

## 0.1.7
- Added independent NPC recognition, nameplate filtering, searchable saved-NPC lists, and portrait right-click Remember/Forget actions.
- Stored manually remembered NPCs by creature template ID rather than individual spawn GUID.
- Added NPC appearance options for full/first name, optional title, and health-bar display.
- Added optional NPC inactivity retention.
- Added management of native overhead-name CVars to prevent unfiltered names bypassing active nameplate filtering, with restoration when filtering is disabled.

## 0.1.3
- Repositioned guild-name text above the health bar when both are displayed.

## 0.1.2
- Adjusted guild-name placement with health bars enabled.

## 0.1.1
- Reduced persistent storage of unlinked Battle.net friend observations.
- Added cached character identity and association lookups.

## 0.1.0
- Initial public-release baseline with interaction tracking, configurable retention, searchable lists, Battle.net alt recognition, and nameplate display and color options.
