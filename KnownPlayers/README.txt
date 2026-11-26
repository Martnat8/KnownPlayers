KnownPlayers 0.5.3b4 (WoW Forever, Interface 16001)

INSTALL
Extract the KnownPlayers folder into World of Warcraft/Interface/AddOns.
Restart WoW or run /reload. Type /kp options to open settings.
Keep a backup of your SavedVariables before installing a new development build.

SETTINGS
- KnownPlayers: enable player and NPC nameplate filtering separately, control the
  minimap button, and reset preferences without deleting stored characters.
  The Nameplate setup panel lists WoW settings that are off, including
  friendly player and NPC nameplates and Always Show Nameplates for
  visibility outside combat. Enable nameplate settings turns on the listed
  options together. WoW's Enemy Nameplates option controls hostile units
  separately.
- Player Nameplates: choose what to track, how long to remember each reason, and
  which reason takes priority. Use Manage beside a category to open its list, then click
  History on a player row. In Known Battle.net Alts, Linked History opens the
  history of the saved character shown under Recognized through.
  Add players manually through the portrait right-click menu or /kp remember
  while targeting another player. Same-realm space/hyphen duplicates are merged on load
  when GUIDs do not conflict; category histories and timestamps are retained.
  Use /kp players to search All Players by name, realm, reason, personal
  note, or tag. A player matches when they have any selected reason.
  Click the star in a list or in Player History to keep a player through
  inactivity. Click it again to let inactivity limits apply.
  The trash can removes the selected reason in a category list or forgets
  the entire character in All Players. Click History or choose View Player
  History in the portrait menu to see the last activity for each saved
  reason. Edit the personal note and comma-separated tags there, then
  click Save. Most recent first sorts by the latest recorded activity.
- NPC Nameplates: check the QuestieDB connection, choose service categories and
  their priority, and manage remembered NPCs and their retention. NPCs are remembered using the portrait's
  right-click menu or /kp npctoggle while targeting a creature. Pin an NPC in
  the manager or portrait menu to keep it from expiring.
- Appearance: choose player and NPC names and health bars, friendly minion
  visibility, category colors, nameplate distances, and minimum opacity.

Use Undo in the lists or /kp undo within 30 seconds of the last individual
removal. Use Backup & Restore on the KnownPlayers tab for bulk clears.

BACKUP & RESTORE
Create a dated manual restore point or use the latest automatic point saved
before a reset, bulk clear, import or restore. Select settings, player history,
or saved NPCs independently when restoring.
Export selects settings, player history, and saved NPCs by default. Uncheck
any section you want to leave out, click Prepare to Copy, then press Ctrl+C
and save the text outside WoW. Keep exports with private player history to
yourself. Battle.net links stay in local restore points. Blizzard's
client-wide settings stay in WoW.
Under Import, click Paste Backup and press Ctrl+V to see the preview. Merge
adds missing player and NPC records and keeps existing personal notes. Replace
prompts before overwriting the selected sections. Use Show Backup Text on
either tab if you need to see the full text.

RETENTION
On a fresh install or Reset Settings, Avoid, Manually Added, Raid, Party, Trade,
and Whisper are set to Forever. Inspect defaults to 30 days and Target to
six hours. Guild membership and linked alts follow their underlying guild
or Battle.net relationship. Avoid starts at the top of the player color priority.
Each character sees their current guild's roster. Switching characters preserves
the other guilds' saved records. A guild departure preserves personal notes and
tags for the next time you recognize that player through another interaction.
Manually remembered NPCs separately default to 30-day expiration enabled.
Existing saved retention settings are preserved when upgrading. Expiration
checks run on load and every five seconds. A player reason expires based on
its last interaction. Known for goes back to its first recorded interaction.

PLAYER DATA
One player record can contain multiple reasons: Trade, Party, Raid, Guild,
Whisper, Target, Inspect, Manually Added, and Avoid. Removing a reason
preserves the remaining reasons. NPC records are kept separately by creature
ID. Battle.net associations are based on friends' observed characters and
require a directly known character with a reason other than Avoid to anchor
recognition. Toggle Avoid with the skull button next to Favorite or use
Add to Avoid on a player portrait. Open the Avoid list from Player Nameplates.

NPC CATEGORIES & COLORS
Automatic NPC service recognition uses the separately installed QuestieDB
addon (API contract 4). KnownPlayers contains no built-in NPC identity or
classification database. Manually remembered NPCs remain available without
QuestieDB, since they are user-saved records rather than a bundled fallback.
Enable NPC nameplate filtering and the desired service categories, then use
Appearance to choose their name colors. NPCs with multiple enabled roles use your saved priority order: the
highest enabled category wins. The default order is Manually Added,
Flight Masters, Trainers, Bankers, Vendors, Repair NPCs, Innkeepers,
Auctioneers, and Quest NPCs.
Use the up/down buttons in NPC Nameplates to change the order.
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
overhead-name CVars and restores the previous values when disabled. Automatic
NPC role filtering requires QuestieDB and enabled categories. Remembered NPCs
and overrides can use the nameplates WoW supplies without QuestieDB.
Distance and opacity can affect which nameplates are visible. In combat
refers to your own combat. Health bars fade as you leave combat where the
addon can update the nameplate. WoW may limit changes to protected frames.
With Known Only enabled, a player's pets, guardians, and totems follow that
player's visibility when WoW supplies the owner's identity and a nameplate.
Show friendly player minions under Character name controls whether friendly
minions are shown at all. Their nameplates follow the player health-bar
setting when enabled.

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
