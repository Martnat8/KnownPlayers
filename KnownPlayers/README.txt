KnownPlayers 0.5.0b5 (WoW Forever, Interface 16001)

INSTALL
Extract the KnownPlayers folder into World of Warcraft/Interface/AddOns.
Restart WoW or run /reload. Type /kp options to open settings.
Keep a backup of your SavedVariables before installing a new development build.

SETTINGS
- KnownPlayers: enable player and NPC nameplate filtering separately, adjust
  nameplate distance and opacity, and reset preferences without deleting
  stored characters.
- Player Nameplates & Lists: player name/guild/health-bar settings, tracking
  toggles alongside category colors and priority, and per-reason player
  expiration. Use List beside a tracking category to open its list, then click
  History on a player row. In Known Battle.net Alts, Linked History opens the
  history of the saved character shown under Recognized through.
  Add players manually through the portrait right-click menu or /kp remember
  while targeting another player. Same-realm space/hyphen duplicates are merged on load
  when GUIDs do not conflict; category histories and timestamps are retained.
  Use /kp players to open All Players. It has reason filters, All/None, and an
  immediate Remove button that forgets the entire character record. Use History
  or the portrait menu to see the last interaction for each reason and edit
  personal notes and comma-separated tags. Search matches notes and tags, and Most recent
  first sorts by the latest tracked interaction. Favorites are pinned in the
  player list and are exempt from inactivity expiration.
- NPC Nameplates & Lists: NPC name/title/health-bar settings, remembered NPC
  list, and manual NPC retention. NPCs are remembered using the portrait's
  right-click menu or /kp npctoggle while targeting a creature. Pin an NPC in
  the manager or portrait menu to keep it from expiring.

Use Undo in the lists or /kp undo within 30 seconds of the last individual
removal. Bulk clears require confirmation and cannot be undone.

RETENTION
On a fresh install or Reset Settings, forgetting is enabled with 30 days for
all applicable player reasons. Guild membership does not expire based on time.
Manually remembered NPCs separately default to 30-day expiration enabled.
Existing saved retention settings are preserved when upgrading. Expiration
runs on load and periodically, not precisely at the minute of expiration.

PLAYER DATA
One player record can contain multiple reasons: Trade, Party, Raid, Guild,
Whisper, Target, Inspect and Manually Added. Removing a reason
preserves the remaining reasons. NPC records are kept separately by creature
ID. Battle.net associations are based on friends' observed characters and
require a directly known character to anchor recognition.

NPC CATEGORIES & COLORS
Automatic NPC service recognition uses the separately installed QuestieDB
addon (API contract 4). KnownPlayers contains no built-in NPC identity or
classification database. Manually remembered NPCs remain available without
QuestieDB, since they are user-saved records rather than a bundled fallback.
Enable NPC nameplate filtering and the desired service categories, then use
NPC Nameplates & Lists to choose their name colors. NPCs with multiple enabled roles use your saved priority order: the
highest enabled category wins. The defaults match version 0.4.2 (manual,
flight, banker, auctioneer, repair, trainer, innkeeper, vendor, quest).
Use the up/down buttons in NPC Nameplates & Lists to change the order.
Use /kp npcsource to view the live connection status. If QuestieDB is missing
or incompatible, automatic service classifications will not be available.
The addon does not copy QuestieDB data into SavedVariables. The settings
page displays green for a connected QuestieDB bridge and red otherwise.

NPC MANAGEMENT & OVERRIDES
Right-click an NPC target to choose Always Show, Always Hide, or Automatic.
Overrides take precedence over category settings for NPCs that have a
nameplate. The NPC Manager shows only manually remembered NPCs and explicit
visibility overrides; it does not track every NPC encountered. Search the
saved list, filter by service category, and cycle override modes there.
Blizzard still determines which NPCs have nameplates in range; Always Show
cannot generate a nameplate for a unit Blizzard has not provided.

NAMEPLATE APPEARANCE
KnownPlayers does not set Blizzard's nameplate width, height or global scale.
Normal full-name displays use Blizzard's own name font; custom first-name,
guild/title, and names-only labels mirror the live native font and frame scale.
To filter names individually, active filtering temporarily manages the native
overhead-name CVars (and friendly NPC nameplate availability), restoring the
previous values when disabled. Other game nameplate sizing options are left
alone. Combat-only health bars remain experimental on protected frames.

PRIVACY
Saved character data and linked BattleTags remain local in WoW SavedVariables.
Do not commit or publish your personal SavedVariables files.

KNOWN LIMITATIONS
Native overhead names are game-engine labels: individual names outside
nameplate range cannot be selectively modified. NPC GUIDs may be restricted
in dungeons; unidentifiable units are left alone rather than causing errors.

COMMANDS
/kp options; /kp status; /kp list; /kp players; /kp scan; /kp guildscan;
/kp remember; /kp npctoggle; /kp undo; /kp dbtest; /kp help

0.3.3: Reset Settings to Defaults refreshes controls without /reload.
0.3.4: Removed unreliable Add Player text field. Use right-click Remember Player
or /kp remember while targeting a player. No other behavior changed.

0.3.6: Player Health Bar modes: Always, In Combat (your character's combat),
and Never. Previous Show Health Bar preference is preserved on upgrade.
Only players are affected; NPC display settings remain independent.
The combat-only mode is experimental. WoW Forever may block updates to
protected nameplates during combat; those frames are left unchanged until
combat ends rather than triggering an unsafe protected-frame operation.

0.4.0: Initial limited Classic service NPC list and category toggles.
0.4.1: Optional QuestieDB API integration with a local fallback.
0.4.2: Removed the 83-NPC local database and its documentation. QuestieDB is
now the only source of automatic NPC classifications. The NPC settings page
shows bridge status and explains the dependency. Each service category and
manually remembered NPCs have independently customizable nameplate colors.
Color choices persist across reloads. Existing manual NPC records are kept.

0.4.3: Added editable NPC category priority, matching the player Color / up /
down row layout, while retaining NPC enable checkboxes. The top enabled
category determines color for multi-role NPCs. Priority survives reloads and
reset-to-defaults restores the pre-0.4.3 order. The QuestieDB bridge and
saved/manual NPCs are unchanged.

0.4.4: Added saved-NPC visibility overrides and a searchable management list,
color-coded QuestieDB bridge status, and nameplate font/scale reconciliation.
Normal names remain Blizzard-rendered unless custom text is specifically
required by a KnownPlayers appearance option.
