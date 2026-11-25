# Changelog

## [Unreleased]

## [0.5.2b4] - 2026-11-25

- Discard pending Battle.net observations when tracking is disabled and block their promotion after opt-out.
- Preserve omitted tracking choices in settings imports and show explicit tracking changes in the backup preview.
- Let players delete either local restore point and explain that restore points can retain forgotten history.
- Report a completed restore or import even when a follow-up refresh fails.

## [0.5.2b3] - 2026-11-25

- Preserve disputed GUID-less history when tracking or importing a player with a confirmed GUID.

## [0.5.2b2] - 2026-11-24

- Check both player aliases for competing GUIDs before moving history at startup or during backup import.
- Preserve the remote realm when an exact whisper sender key is shared by a different GUID.
- Include player history in automatic checkpoints before settings changes that schedule roster scans.

## [0.5.2b1] - 2026-11-24

- Preserve GUID-less history during startup when multiple players claim the same name and realm.
- Skip ambiguous GUID-less backup rows after checking both saved and incoming identities.
- Keep long notes and extensive history in local backups and checkpoint only the sections changed by each bulk action.
- Resolve already-qualified whisper senders against saved identities before appending a local realm.
- Decline ambiguous Battle.net alt matches when looking up a name without a GUID.
- Retry only unresolved nameplate CVar restores so newer settings stay intact.

## [0.5.2b0] - 2026-11-24

- Check the addon manifest and smoke-test startup in load order in CI.
- Reject backup merges that exceed history limits and keep local restore points and settings resets available for existing oversized histories.
- Scan group, guild, and Battle.net rosters when restoring or resetting settings enables tracking.
- Keep whispers from hyphenated character names in the correct history and skip self-whispers.
- Match imported players against staged history without modifying live data or invalidating its caches during planning.
- Restore a released nameplate's opacity during combat when the game permits it, so the next unit can use the frame.
- Refresh player lists once per opening, share name searches across lists, and centralize window navigation and Escape handling.
- Separate nameplate CVar ownership from rendering and reuse the player category color when drawing custom labels.
- Remove unused legacy player and NPC helpers while preserving older health-bar preferences and saved priorities on upgrade.

## [0.5.1] - 2026-11-23

- Add Backup & Restore with dated restore points, automatic backups before bulk changes, settings-only exports by default, and a preview before merging or replacing imported data.
- Show the QuestieDB connection status beside the NPC database heading and fit the category list and NPC Manager controls in the default settings window.
- Expand the minimap settings window to fit the Appearance tab within the screen and restore its previous height when switching tabs.
- Give distance and opacity labels enough space beside their sliders and shorten the NPC distance label.

## [0.5.1b4] - 2026-11-23

- Isolate the database self-test from saved history and prevent player menu actions from falling back to an unrelated target.
- Scope guild records to their guild, preserve personal details, and reconcile later roster changes during the same session.
- Remove stale Battle.net links after a complete friend-list scan, reject ambiguous name-only matches, and update the identity index incrementally.
- Skip restricted unit comparisons safely and retry restoring WoW name settings after a reset.
- Centralize player category definitions, run Lua behavior tests in CI, and enforce LF for release metadata and scripts.

## [0.5.1b3] - 2026-11-22

- Keep custom nameplate text attached to the active unit when WoW recycles a frame, hide it behind the camera, and match the live nameplate scale and fade.

## [0.5.1b2] - 2026-11-22

- Moved the NPC priority explanation above QuestieDB status while preserving the category table's position.
- Grouped player and NPC appearance controls in matching side-by-side panels and aligned the distance, opacity, and default controls.

## [0.5.1b1] - 2026-11-22

- Added one Nameplate setup panel that explains missing WoW settings and enables friendly player, friendly NPC, and out-of-combat nameplates together. Separate checks cover tracking categories, QuestieDB, and native names outside the filter.

## [0.5.1b0] - 2026-11-22

- Made pets, guardians, and totems follow their owner's nameplate visibility when Known Only is on, and added a friendly minion visibility toggle under Character name.
- Enabled the minimap button by default for new settings.
- Added padding around the color swatches and replaced the priority button text with arrow icons for players and NPCs.
- Reorganized settings into four tabs, combined player tracking and retention in one table, and moved colors, names, health bars, distance, and opacity to Appearance.
- Added a Forever retention option, category-specific defaults for new settings, and a combat-only NPC health bar option.
- Placed player and NPC colors in bordered side-by-side tables, updated default priorities and durations, and closed lists when leaving the settings tab that opened them.

## [0.5.0] - 2026-11-21

- Redesigned Settings around three tabs and added an optional minimap button that opens the same layout in a vertically resizable window. The button works with MinimapButtonButton.
- Added draggable Player History from player portraits and lists. See why and when you met each player, their race and class when available, and edit searchable notes and tags. Escape closes windows in reverse opening order.
- Added shortcuts to each player category list and `/kp players` for All Players. Player lists show class and race icons and can filter by class. The Battle.net Alts list links to the saved player's history.
- Added Name and Known for sorting to the player lists, Battle.net Alts, and NPC Manager. All Players can also sort by most recent interaction.
- Added stars and trash cans beside player names. Stars save immediately and keep favorites from expiring, including after a reload. NPCs can also be favorited. Undo an individual removal within 30 seconds from the lists or with `/kp undo`.
- Check for inactivity expiration every five seconds and update open lists and nameplates when entries expire.
- Show the installed version in About, explain how interactions reveal nameplates in the README, and fold earlier changelog entries into an expandable history.

## Release history

<details>

<summary>Show previous releases and prereleases</summary>

## [0.5.0b8] - 2026-11-21

- Made Player History draggable from the portrait menu and player lists.
- Check inactivity every five seconds and refresh open lists and nameplates when saved entries expire.
- Added star and trash-can controls beside player names in category lists and All Players, and a star toggle in Player History.
- Save Player History favorites immediately so they survive reloads and inactivity expiration.

## [0.5.0b7] - 2026-11-21

- Fit the settings window to the player tracking controls and centered the tabs above an inset border shared by both settings views.

## [0.5.0b6] - 2026-11-21

- Added a Class / Race icon column and a class filter to player category lists, All Players, and Known Battle.net Alts.
- Centered class and race icons under the Class dropdown and added them beside their labels in Player History.
- Added an optional minimap button that opens a height-resizable KnownPlayers window with three settings tabs, with support for MinimapButtonButton collection.
- Made KnownPlayers dialogs replace the minimap settings window until they close, and moved the player appearance controls below the forgetting settings.
- Replaced AddOns settings subcategories with the same three tabs as the minimap window, and moved remembered NPC retention above NPC management.

## [0.5.0b5] - 2026-11-21

- Made Escape close Player History and list windows in reverse opening order, and clarified the Favorite label in Player History.
- Added descriptions and aligned the spacing for Character name and Health bar settings, and clarified the remembered NPC retention label.

## [0.5.0b4] - 2026-11-21

- Added clickable Name and Known for sorting to the player category lists, All Players, Battle.net Alts, and NPC Manager.

## [0.5.0b3] - 2026-11-21

- Expanded the README to explain how everyday interactions make familiar players' nameplates visible.
- Moved notes and tags above the interaction reasons in Player History, placed Favorite next to the character name, and added race and class when available.

## [0.5.0b2] - 2026-11-21

- Added History to player category lists and Linked History to Known Battle.net Alts.
- Removed the four Player Lists shortcuts from settings and added `/kp players` to open All Players.

## [0.5.0b1] - 2026-11-21

- Added a List button to each player tracking row to open that category’s saved entries.
- Fixed Player History layering so list controls do not draw over the editor.

## [0.5.0b0] - 2026-11-21

- Added player history on portraits and in Player Lists, with per-reason interaction dates, searchable notes and tags, and recent sorting.
- Added pinned player and NPC favorites that are exempt from inactivity expiration.
- Added a 30-second undo for the most recent individual removal, available in lists and through `/kp undo`.
- Displayed the installed KnownPlayers version in the About window.
- Moved player tracking toggles into the player color and priority rows, matching the NPC settings layout.

## [0.4.5] - 2026-11-21

- Promoted the 0.4.5 pre-release series with the About window, nameplate controls, QuestieDB fallback, and player and guild tracking fixes.

## [0.4.5b6] - 2026-11-21

- Added an About button on the main settings page with help for tracking, NPC overrides, nameplates, and saved lists.

## [0.4.5b5] - 2026-11-21

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

</details>
