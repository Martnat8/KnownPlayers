KnownPlayers 0.1.7 (WoW Forever, Interface 16001)

Install: Extract KnownPlayers into Interface/AddOns, replacing prior files; /reload.
Options: /kp options, then KnownPlayers in the AddOns settings menu.

Seven direct-interaction lists have independent retention settings, searching,
and manual removal. Category expiration uses each category's last encounter
and is checked at startup and every 10 minutes during play.

Battle.net associations (new in 1.2.0):
- The "Automatically recognize Battle.net friends' alts" setting is on by default.
- The addon observes currently exposed WoW character name/realm/GUID for
  Battle.net friends, and remembers those observations by BattleTag.
- When any observed character matches a directly known record by exact
  Name-Realm or GUID, other observed characters on that BattleTag appear in
  the "Associated" pop-out list on the main settings page.
- Alts do not inherit a Trade/Party/etc. interaction they never performed.
  Direct interaction player counts are unchanged.
- Only observed characters can be discovered. The friend's full alt roster
  is not available; the original known character must be observed at least
  once as a Battle.net friend for automatic linking to activate.
- A BattleTag is stored in SavedVariables as an internal account-level link;
  temporary Battle.net numeric IDs are not stored. No BattleTags are shown
  in the list window.
- Associated entries are derived from observed identities and live direct
  records, so associations cease being active if their last directly known
  character expires or is removed. Observations remain cached until cleared
  manually from the SavedVariables file (future UI management possible).
- If BattleTags are unavailable or privacy-masked, associations will not be
  created rather than using potentially incorrect account IDs.

Commands: /kp status, /kp list, /kp dbtest, /kp options, /kp scan, /kp guildscan

The feature has not been tested in the user's WoW Forever build yet.

1.2.1 settings layout:
- All tracking and category-specific retention options live on the scrollable main settings page.
- Open List launches search, remove, and clear controls only.
- Associated list is labeled Known Battle.net Alts.

1.3.1: Settings reorganized into Player Tracking (expandable), Nameplate Appearance (placeholder), and Player Lists.

1.3.1: Main KnownPlayers page now shows grouped tracking toggles and per-category retention controls. Nameplate Appearance and Player Lists remain subpages.

1.3.2 nameplate experiment: Use the Nameplate Appearance page to temporarily
hide/restore your currently targeted player's visible nameplate. No automated
nameplate changes. Also accessible via /kp platehide and /kp plateshow.

For new installations, automatic forgetting is OFF and each list's initial
retention duration is 30 days; existing saved preferences are preserved.

1.3.7: Adds optional guild-name second line to Names Only nameplates.

1.3.8: Category nameplate colors and priority controls, opacity fix for guild text,
retention presets (1 min / 5 min / etc.), Guild retention removed. Existing retention settings preserved.

1.3.14: Reapply category name colors to native nameplates after Blizzard name updates and hover; preserve original vertex colors when restoring.

1.3.15: PvP Attackers category (opt-in, red/highest priority).
Records direct player attacks against your character from combat-log damage and missed attacks.
Does not identify pet owners or capture combat events outside logging range.

1.3.18: Move nameplate filtering toggle to top of main settings and remove subtitle.

0.1.1 Privacy and performance:
- Battle.net character observations are retained in SavedVariables only after
  at least one character in that friend group is directly known. Unlinked
  observations are temporary in-memory data and are lost at logout/reload.
- Existing unlinked observations are removed from persistent storage at startup,
  but can still be linked during the same session. Linked groups are preserved.
- BattleTags remain stored locally for linked Battle.net friends; no addon data
  is transmitted by KnownPlayers. Do not share your SavedVariables publicly.
- Indexed lookups reduce repeated GUID and Battle.net group scans during
  nameplate updates. Nameplate rendering cadence remains unchanged.

Native overhead-name setting management (0.1.7):
- When "Enable KnownPlayers nameplate filtering" is turned on, KnownPlayers
  temporarily sets UnitNameFriendlyPlayerName and UnitNameEnemyPlayerName to 0.
  This prevents distant 3D overhead names from bypassing nameplate filtering.
- The previous CVar values are restored when filtering is disabled, when
  settings are reset, or when the game logs out/reloads normally.
- NPC, minion, own-name, and actual nameplate settings are not changed.
- Beyond Blizzard's nameplate range, even recognized players have no native
  overhead names; selective distance-based names remain unavailable.
- If the game crashes or the addon is removed while filtering is active,
  manually restore friendly/enemy overhead names in WoW's Names settings.

NPC list and right-click menu (0.1.7)
------------------------------------
Right-click a targeted creature NPC's unit frame to choose "Remember NPC" or
"Remove NPC from KnownPlayers". You can also use /kp npctoggle while targeting
a creature NPC. Browse, search, remove, or clear entries from Settings >
Player & NPC Lists > NPCs. The records are saved separately from players.

NPC entries are keyed by the stable creature template ID, not the temporary
individual spawn GUID: different spawns of the same NPC type share recognition.
NPCs are never auto-added simply by targeting them, and do not expire.

Optional "Filter NPC nameplates" is off by default. With both it and the main
known-player nameplate filter enabled, creature NPCs on this list retain their
nameplates and other creature NPC nameplates become transparent. Quest/NPC
nameplates may be hidden: disable NPC filtering if desired. Pets, other
units, and the base game's native NPC overhead names are not changed.

The target right-click integration uses Blizzard's Menu.ModifyMenu API, when
available; /kp npctoggle is a fallback for unsupported menu variants.

0.1.7: Independent NPC filtering, managed NPC visibility CVars, optional NPC inactivity retention.

0.1.7: Independent NPC nameplate options (full/first name, optional NPC title,
and show health bar). These apply to remembered NPCs. NPC titles are read
from tooltip data when available; they are not player guild names.
