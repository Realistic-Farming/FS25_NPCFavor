# NPC Favor -- Changelog

All notable changes to the FS25_NPCFavor mod are documented below, organized by version. This changelog is derived from the actual git history and issue tracker.

---

## Unreleased

### Added
- **Control Center actions** (suite Control Center, requires SettingsHub): `FAVOR_MENU`, `NPC_LIST`, `NPC_SETTINGS`.
- **Playtest fixes:** NpcRfPdaGuest (Esc neighbor-table pager), NPCFavorHUD, NPC_HUD_EDIT (RShift+Z), translation sync.

---

## v1.2.7.1 -- Favor completion fix, money authority, core-service bridges, and a companion read API

### Favors
- Fixed favors never progressing (#62): every favor step within 30m of its target called a non-existent `queueNotification` method, so each proximity check threw a Lua error and no favor could progress or finish (the borrow-tractor favor would hand over the keys, then do nothing at the field marker). Step completion now flashes on the favor HUD like every other notification.

### Money handling (server-authoritative)
- Favors now pay the farm that accepted them. The owning farm is stamped when the favor is accepted and used at every money site, so the correct farm is paid even on a dedicated server, and clients never apply money locally.
- Favor completion, loan repayment, and gifts all route through the mod's own server-authoritative event, with a single completion path.
- Added idempotency flags (reward paid, repayment collected, loan deducted), persisted across save and reload, so a reload can no longer double-pay a favor.
- Fixed a live double-payout in the favor management dialog.
- Legacy in-flight favors from older saves are migrated to a default farm so they still pay out.

### Core-service bridges (Realistic-Farming ecosystem)
- NPCFavor now bridges onto the four core services when they are installed, and keeps its own paths as the standalone fallback: StateLedger (state save and restore, with npc_favor.xml kept as a safety copy), NetworkSync (NPC state batched through the shared sync), MasterHUD (the favor draw loop), and SettingsHub (settings mirror). Each one no-ops when its service is not present, so the mod runs exactly as before on its own.

### Companion read API
- Added a read-only API other mods can use to read relationship and favor state (relationship value, a threshold check, and whether a farm has an active favor of a given type). Read-only and server-authoritative, added for Dairy Core and Pro Staff.

---

## v1.2.7.0 -- Real base-game AI field work (till / sow / harvest)

Farmer NPCs now do real, game-AI-driven field work with their own equipment, matched to what each field actually needs.

### NPC field work (NEW)
- **Real base-game AI tillage**: an NPC's tractor + implement runs a genuine AIJobFieldWork and tills the ground. Because the AI helper needs the job's farm to own the field (and NPC farms do not own land), the field's farmland is temporarily borrowed by the local player's farm for the duration of the job, then restored. A save-hook safeguard restores every borrow before any save, so a temporary ownership can never persist.
- **Full job-to-field matching**: each farmer NPC gets a job role and the matching equipment: till (tractor + plow/cultivator), sow (tractor + seeder, seeded), or harvest (self-propelled combine + header). An NPC only runs the AI job when the field's current state matches its role.
- **Crop safety**: NPCs read the field's real crop and growth state and never plow or cut a growing crop. A harvester is only assigned to a field that is actually ripe.
- **Fallbacks**: when the game AI cannot run (no implement, hire limit reached), the NPC drives its combo with base-game GoTo pathfinding, or a kinematic visual pass, so it always looks busy without errors.

### On-demand equipment (architecture)
- Equipment is now spawned **on demand**: an NPC's tractor/combine + implement is created at the field edge the moment they start working, matched to the field's **current** need, and despawned again when they stop. Previously equipment was decided once at spawn from a snapshot of the field, so it could go stale (a plow left on a field that had since grown a crop). Deciding at work time removes that mismatch entirely; a growing field simply gets no equipment and the NPC visits on foot.
- If an NPC leaves work while their vehicle is still loading, the load is cancelled before the implement is spawned, so no equipment is created just to be deleted.

### Fixes
- Fixed favors never completing (#62): every favor step within 30m of its target called a non-existent `queueNotification` method, so each proximity check threw a Lua error and no favor could progress or finish ("not a single favor has worked"). Step completion now flashes on the favor HUD like every other notification, with a new localized `npc_hud_step_done` string across all 10 languages.
- Fixed a VehicleCharacter crash from a wrong loadCharacter argument order (was calling a table), and 5 no-op vehicle deletions (g_currentMission:removeVehicle does not exist; use Vehicle:delete).
- Eliminated a map-marker overlay render flood ("Unknown entity id ...") by sharing one never-freed overlay across all NPC markers.
- Fixed harvester headers never attaching: the New Holland combo pointed at a header file as its "combine", so two headers were being paired. It now uses the real combine (chSeries), and the header attaches and harvests.
- Silenced the "Can't change money of spectator farm" log spam from every angle: NPC AI job cost is zeroed, NPC vehicles keep their fuel topped so the base game never auto-bills the spectator farm for a refuel, and (when installed) Worker Costs also drops any charge aimed at the spectator farm.

### AI behaviour, multiplayer, and edge cases
- Added the "loner" personality to the daily schedule so those NPCs keep to their own routine.
- Schedule-aware commute speed boost (previously only in the evening), so NPCs running late move quicker at any time of day.
- Group gatherings now show a speech bubble even when no direct social partner is found nearby.
- Reduced NPC-to-NPC social pairing distance to 50m so neighbours pair up more naturally.
- Split the movement-speed bookkeeping so an NPC's mood-based speed is preserved correctly across walk and run modes.
- Clear stale gathering data when an NPC goes to sleep, and delegate scheduled-activity lookups to a single source (removes a duplicate code path).
- Client-side orphan-vehicle detection in multiplayer, so a stranded NPC vehicle is cleaned up on clients too.

### New console command
- **npcDeleteVehicle [radius]** -- delete the nearest vehicle/implement to you (cleanup for stranded units); never deletes the vehicle you are in.

---

## v1.2.2.6 -- Favor HUD Rework & Compass Navigation

**Branch:** `feature/favor-ui-improvements` (PR #30)
**Authors:** XelaNull

### HUD Edit Mode & Resize System (NEW)
- **Right-click toggle** replaces F8 keybind for entering HUD edit mode
- **Corner resize handles**: Drag any corner to uniformly scale the HUD (0.5xâ€“2.0x)
- **Edge resize handles**: Drag left/right edges to adjust width independently (0.5xâ€“2.0x width multiplier)
- **Camera lock**: Camera rotation freezes during edit mode to prevent accidental camera spin while dragging
- **Smart guards**: Edit mode blocked when player is in a vehicle, GUI/dialog is open, or HUD is locked in settings
- **Auto-exit**: Exiting to vehicle or opening a dialog automatically closes edit mode
- **HUD shortcut buttons**: List, Favors, and Admin dialog quick-access buttons at bottom of HUD box
- All resize/position/width settings persisted via NPCSettings (XML save/load)

### Compass Direction Arrows (NEW)
- **Pixel-art compass needle** on each favor row points toward the target NPC relative to camera facing
- Arrow rotates smoothly via 2D rotation matrix on per-frame grid dots
- Uses `localDirectionToWorld` camera forward vector for reliable camera-relative angles (avoids `getRotation` sign convention issues)
- **Distance + cardinal direction text** (e.g., "NE 250m") with color coding: green (<100m), yellow (100â€“500m), gray (>500m)
- **Proximity dot**: When within 3m of NPC, arrow replaced with centered dot to avoid erratic `atan2` behavior at near-zero distance
- 8-direction compass labels (N, NE, E, SE, S, SW, W, NW) localized in all 10 languages

### Flash Notification System (NEW)
- **HUD-resident notifications** replace game's messageCenter popups for favor events
- Color-coded by event type: orange (new favor), cyan (progress), green (complete), red (failed), yellow (perfect bonus)
- Multi-line support with fade-in/pulse/fade-out animation (4s duration)
- Notification queue ensures messages display sequentially without overlap

### Favor Timer Accuracy Fix
- Favor expiration timers now use in-game time (`TimeHelper.getGameTimeMs()`) instead of real wall-clock time
- Timers now correctly scale with game speed (1x, 5x, 120x)
- New `TimeHelper.getGameTimeMs()` function: returns `currentDay * 86,400,000 + dayTime`

### HUD Visual Polish
- Drop shadow on HUD background for depth
- Permanent subtle border (always visible, not just in edit mode)
- Pulsing blue border during edit mode, green during active resize/drag
- Version watermark in bottom-right corner
- Progress bars on favor rows when progress > 0%

### Translations
- 13 new i18n keys across all 10 language files (compass directions, flash notification templates)
- Updated edit mode hint text to reference resize capability

### Minor Fixes
- Favor Management Dialog: border element visibility now toggles with row content
- NPCSystem boot notification displays mod version number
- Expanded input event debug logging for troubleshooting keybind issues

---

## v1.2.2.5 -- Translation Rework & Codebase Restore

**Commits:** `869a478` through `b74eab3` (2026-02-10 to 2026-02-12)
**Authors:** Dueesberch (Christian), TisonK, XelaNull
**Issues Fixed:** #20 (Merge conflicted files committed)
**PRs Merged:** #23, #24, #28, #29

### Translation System Rework (PR #28 by Dueesberch)
- **Extracted translations from modDesc.xml**: Moved ~1,700 lines of inline `<l10n>` translations to 10 separate `translations/lang_*.xml` files (one per language: en, de, fr, pl, es, it, cz, br, uk, ru)
- Changed `modDesc.xml` from inline `<l10n>` block to `<l10n filenamePrefix="translations/lang" defaultLanguage="en" />` for external loading
- Added additional translations from past PRs that were missing
- Removed duplicated translation lines
- Cleaned up temp working files

### Codebase Restoration (PR #24 by XelaNull)
- **Reverted whitespace-only reformatting**: TisonK's PR #23 merge introduced massive whitespace changes across 16 files with zero functional code changes. Restored the working v1.2.2.4 codebase with version bump.
- **Merge conflict cleanup** (fixes #20): TisonK's merge accidentally committed files with `<<<<<<< HEAD` conflict markers. Fixed by removing the conflicted files and restoring from v1.2.2.4.

### Map Hotspot Nil-Guard (TisonK, `869a478`)
- **Temp fix for PlaceableHotspot crash** (mitigates #18, #26): Added nil-checks for `hotspot.overlay` before proceeding with hotspot creation. The `PlaceableHotspot.lua:213: attempt to index nil with 'width'` error caused map freeze when opening the PDA.
- Added `setPlaceableType()` method detection with fallback to direct property assignment
- Abort hotspot creation gracefully if overlay fails to initialize

### Housekeeping
- Updated CLAUDE.md with developer workspace paths and mod directory listing
- Added no-branding rule to CLAUDE.md

---

## v1.2.2.4 -- Settings Persistence & ESC Menu Expansion

**Commit:** `3e8691e` (2026-02-09)
**Authors:** XelaNull, Claude & Samantha (Claude Code)
**Issues Fixed:** #15 (Settings reset when exiting savegame)

### Settings Persistence (fixes #15)
- **Save path fix**: `NPCSettings:saveToXMLFile(missionInfo)` now writes to `missionInfo.savegameDirectory` (tempsavegame during save), matching the UsedPlus pattern. Previously wrote directly to `savegame5/` which got overwritten when the game swapped tempsavegame â†’ savegame5.
- **Load fix**: Replaced unreliable `g_fileIO:fileExists()` with `XMLFile.loadIfExists` (proven FS25 API). Previously silently fell back to defaults every load.
- **No orphan writes**: ESC menu, console commands, and sync events now update settings in-memory only. Disk persistence happens exclusively via the `FSCareerMissionInfo.saveToXMLFile` hook (UsedPlus pattern).
- **Diagnostic logging**: Settings load/save now prints messages to game log to help debug persistence issues.

### Expanded ESC Menu Settings (6 â†’ 13 controls)
- 7 new controls: Show Favor List, Show Relationship Bars, Show Map Markers, Enable Gifts, Allow Multiple Favors, Max Active Favors (dropdown: 1/2/3/5/8/10), Relationship Decay
- All 13 controls grouped under single "NPC Favor System" section header for easy identification in multi-mod setups
- New `showMapMarkers` setting with instant toggle via `NPCEntity:toggleAllMapHotspots()`
- 170 new i18n strings (17 entries Ã— 10 languages)

### Dialog & Icon ZIP Fixes
- Eagerly load all 3 dialogs (NPCDialog, NPCListDialog, NPCFavorManagementDialog) during `loadMission00Finished` while the mod's ZIP filesystem context is active. Previously lazy loading failed on second session with "Failed to open xml file".
- Removed custom icon.dds overlay from map hotspots (DirectStorage can't resolve ZIP paths outside mission-load context); uses reliable built-in `PlaceableHotspot.TYPE.EXCLAMATION_MARK` icon instead.
- Removed duplicate l10n entries (`button_cancel`, `button_refresh`, `button_close`) that shadowed base game definitions and spammed warnings on every load.

---

## v1.2.2.3 -- HUD Polish & Female NPC Clothing Fix

**Commit:** `d545e17` (2026-02-09)
**Authors:** XelaNull, Claude (Claude Code)

### HUD Overlay & Name Tags
- Suppress NPC HUD rendering during pause, full-screen map, ESC menu, and dialogs
- Dynamic name tag Y scaling based on distance (1.8m close â†’ 2.6m at 15m)
- Lower speech bubble Y offset (2.8 â†’ 2.3) and interaction hint (2.5 â†’ 2.0)

### Female NPC Clothing & Camera Fix
- Fix female NPCs getting male clothing by force-loading `playerF` XML config
- Replace simple headgear offset with recursive node search for hat (-0.044m) and glasses (+0.012m) adjustments
- Fix behind-camera projection in `projectWorldToScreen` with dot-product check
- Clean up dialog boilerplate in NPCFavorManagementDialog, NPCListDialog, NPCFavorGUI
- Add NPCTeleport module source loading

---

## v1.2.2.2 -- Map Hotspots, Field Work, NPC Clothing & Build System

**Commits:** `44c1a7e` through `aee4b17` (2026-02-09)
**Authors:** XelaNull, Claude (Claude Code)
**Issues Fixed:** #12 (Map hotspot visibility)

### Map Hotspots & NPC Name Labels (fixes #12)
- Convert map hotspots from abstract `MapHotspot` (invisible) to `PlaceableHotspot` with icon overlay and fallback icon type
- Remove hotspot when NPC sleeps, recreate on wakeup â€” fixes icons persisting at night
- Add `drawMapLabels()` method rendering NPC names above map icons via `IngameMap.drawFields` hook

### NPCFieldWork Module (new)
- Realistic boustrophedon (serpentine) row traversal replacing simplistic rectangular patterns
- Multi-worker coordination (max 2 per field with size-based caps)
- Smooth Bezier headland turns
- Personality-driven pattern selection (grumpy â†’ perimeter, lazy â†’ spot check)
- Legacy `initFieldWork` preserved as fallback

### NPC Clothing Overhaul
- Curate PRESET_POOL: remove beekeeper, horsebackRider, longHaulTrucker, wetwork
- Use clone-and-modify pattern for male presets (game's `applyCustomWorkStyle` approach)
- Post-apply headgear sanitization (removes helmets, veils, motorcycle gear)
- Fix property names: `selectedIndex` â†’ `selectedItemIndex`, `selectedColor` â†’ `selectedColorIndex`
- Use `getItemNameIndex()` API for proper item lookup
- Expand outfit tables: 7 â†’ 12 male, 6 â†’ 12 female (all farm-appropriate)
- Add "working" to `isWalking` check to fix animation sliding during field work

### Favor Management Dialog
- Move `NPCFavorManagementDialog.lua` from `gui/` to `src/gui/` (consistent with other dialog files)
- Rework dialog layout and button handling

### Build System (new)
- Cross-platform build script (`build.sh`) for Git Bash on Windows, native on macOS/Linux
- Uses .NET `ZipFile` API on Windows to preserve directory structure
- `--deploy` flag copies to FS25 mods folder with auto-detection
- Excludes dev files (.git, .claude, CLAUDE.md, build.sh) from zip

---

## v1.2.2.1 -- Favor Dialog Fixes & Refactor

**Commits:** `9e56d76` through `c4e293d` (2026-02-09)
**Author:** TisonK
**Fixes:** Critical load failure from v1.2.2.0

### Favor Management Dialog Fixes
- **Critical fix**: Added missing `source()` call in `main.lua` for `NPCFavorManagementDialog.lua` -- the v1.2.2.0 dialog could not actually open because its Lua code was never loaded
- Relocated `NPCFavorManagementDialog.lua` from `gui/` to `src/gui/` (consistent with other dialog files)
- Rewrote dialog XML from custom `npc*` profiles to proper FS25 dialog patterns (`fs25_dialogBg`, `fs25_dialogContentContainer`, `buttonOK`, etc.)
- Added defensive nil-checks on all GUI element access (`if elem and elem.setText then`)
- Fixed relationship method name (`modifyRelationship` â†’ `updateRelationship`)
- Added support for both scalar (`favor.reward = 500`) and table (`favor.reward = {amount=500}`) reward formats
- Reduced max visible favors from 10 to 5 (matching the 5-row dialog layout)

---

## v1.2.2.0 -- Favor Management Dialog & Keybinds

**Commits:** `3e80c56` through `22fd032` (2026-02-09)
**Author:** TisonK
**Issues Fixed:** #5 (NPC behind player after teleport), #6 (floating text after teleport), #9 (favor management UI), #10 (NPC list keybind)

### Favor Management Dialog (new -- fixes #9)
- New `NPCFavorManagementDialog` (XML + Lua) showing active favors with NPC name, description, time remaining, and reward
- 4 action buttons per favor: View details, Cancel (with -10 relationship penalty), Go To (teleport), Complete (with money reward)
- Relationship-colored NPC names and time urgency coloring
- Accessible via F6 key or `npcFavors` console command

### Keyboard Shortcuts (fixes #10)
- **F6** (`FAVOR_MENU`) -- Opens Favor Management dialog
- **F7** (`NPC_LIST`) -- Opens NPC roster dialog (previously console-only via `npcList`)
- Both keybinds registered with full RVB pattern, localized in all 10 languages

### Teleport Improvements
- **Face-NPC rotation** (fixes #5): After all teleports (npcGoto, NPC List, Favor dialog), player now rotates 180Â° to face the NPC instead of having NPC behind them
- **UI stabilization** (fixes #6): Added `lastTeleportTime` tracking with 0.5 game-minute cooldown to prevent HUD text jank after teleporting

### Documentation
- Added `VISION.md` -- 211-line design pillars document with 4-phase roadmap
- Added `TODO.md` -- 130-line development roadmap organized by priority tier
- Updated `README.md` to clarify multiplayer is untested

---

## v1.2.0.0 -- NPC AI Overhaul

**Branch:** `feature/living-neighborhood-system` (PR #3, merged `bd99ca3`)
**Authors:** UsedPlus Team (XelaNull + Claude AI)
**Scope:** 38 files changed, ~17,400 lines added

A comprehensive AI overhaul transforming mechanical schedule-following NPCs into personality-driven characters with internal motivations, social dynamics, weather awareness, and visual feedback systems.

### Relationship System Overhaul
- 7-tier relationship system: Hostile (0-9), Unfriendly (10-24), Neutral (25-39), Acquaintance (40-59), Friend (60-74), Close Friend (75-89), Best Friend (90-100)
- NPCs start with randomized relationship (5-35) -- a natural mix of strangers and vaguely familiar neighbors
- Tier names now consistent across all UI surfaces (overhead display, dialog, NPC list)
- Favor requests gated behind Neutral (25+), gift giving behind Neutral (30+) -- no bribing strangers
- Passive relationship decay (-0.5/day after 2 days without interaction, floors at 25)
- Grudge system: persistent negative feelings from bad interactions, reduces positive gains
- NPC-initiated gifts: best friends (75+) have small daily chance to surprise the player

### Needs and Mood System
- 4-need system (energy, social, hunger, workSatisfaction) on 0-100 scale
- Personality-specific need rates (hardworking gets guilty when idle, social gets lonely faster)
- Mood derived from needs: happy/neutral/stressed/tired
- Mood affects walk speed (+/-20%), greeting tone, social willingness
- Mood indicator in dialog: `[+]` happy, `[!]` stressed, `[~]` tired

### NPC-NPC Social System
- NPC-NPC relationship graph with personality compatibility matrix
- Compatible pairs (hardworking+generous, social+social) drift toward friendship
- Incompatible pairs (social+grumpy, hardworking+lazy) drift toward rivalry
- Social partner selection prioritizes NPCs with higher relationship values
- Conversation topic generation based on time, weather, personality, and relationship

### Weather and Season Awareness
- Rain/storm interrupts field work (50% chance to go home in rain, always in storms)
- Seasonal schedule shifts (winter: +1hr wake, shorter work day; summer: opposite)
- Weather-aware conversation topics ("Terrible weather today...")
- Uses existing `getWeatherFactor()` API (no new dependencies)

### Daily Schedule Improvements
- Personality-specific wake/work/sleep times (hardworking wakes at 5:00, lazy at 7:00)
- Weekend variation: Sunday = no work, extended social; Saturday = half-day
- Farmers wake before sunrise for realistic agricultural schedules

### AI Behavior
- Markov chain transition probabilities integrated into fallback decision weighting (12 state-to-state entries)
- 4 field work patterns: row traversal, spiral inward, perimeter walk, spot check
- Observable personality differentiation: wider speed ranges, idle micro-behaviors
- Bezier curves for smooth path corners
- Memory system (10 records per NPC with sentiment tracking, stored but not yet driving behavior)

### Visual Feedback
- Floating relationship change text (+1, -2 popups above NPCs)
- Speech bubbles during NPC-NPC socializing
- Name tags and relationship tier above NPC heads
- Height variation per NPC (0.95-1.05 Y scale)
- Animated character models (male + female via FS25 HumanGraphicsComponent) -- walk/idle animations work in most cases; some NPCs slide without animating (known issue, root cause not yet identified)

### Dialog Improvements
- NPC backstory/bio section (visible at relationship 40+)
- "Ask about plans" button shows NPC's next 3 scheduled activities
- Relationship decay warning when NPC hasn't been talked to recently
- Personality-flavored gift thank-you messages
- Context-aware greetings that scale from hostile ("Do I know you?") to warm ("Great to see you!")

### Bug Fixes
- **Talk button spam exploit** -- case mismatch (`"DAILY_INTERACTION"` vs `"daily_interaction"`) let players gain infinite relationship points. Fixed + added "already chatted today" feedback.
- **Floating NPCs** -- tractor/vehicle props set Y offset for cab seating, but models never loaded (invisible placeholders). Removed all Y offset assignments.
- **NPCs waking too late** -- most personalities had wake=6 or later. Adjusted to 5:00-7:00 range.
- **Gift button cycling** -- multi-tier gift UI code existed but `self["btnGiftText"]` doesn't resolve in FS25's GUI system. Reverted to working simple $500 gift.

### Infrastructure
- Building classification system (residential, commercial, industrial, agricultural, services)
- Farm ownership assignment from farmlandId on placeables
- Gender system with male/female name pools
- NPCListDialog showing farm name + field count per NPC
- Version single source of truth (`g_NPCFavorMod.version` in main.lua)
- Comprehensive `docs/` folder with architecture, AI, relationship, and settings documentation
- 25 TODO items marked as completed across 10 file headers

### Known Limitations
- **NPC animation sliding** -- Some NPCs slide along the ground without their walk animation playing; root cause not yet identified *(fixed in v1.2.2.2)*
- **Silent groups and walking pairs** -- Group gatherings and walking pairs position NPCs correctly but generate no conversation content; only 1-on-1 socializing produces speech bubbles
- **Map hotspots** -- MapHotspot creation code exists but markers do not appear on the in-game map *(fixed in v1.2.2.2)*
- **NPC vehicles/tractors** -- Code exists but i3d models cannot be loaded from game pak archives at runtime; NPCs walk everywhere
- **Flavor text localization** -- Mood prefixes, backstories, birthday messages, and personality dialog added in v1.2.0 are English-only (core UI is fully localized)

---

## v1.1.0.0 -- i18n, Code Stewardship, and Documentation

**Commit:** `fcafd9f` (2026-02-08)
**Authors:** UsedPlus Team (XelaNull + Claude AI)

### Internationalization
- 77 new translation keys added to `modDesc.xml` in 10 languages (English, German, French, Polish, Spanish, Italian, Czech, Brazilian Portuguese, Ukrainian, Russian)
- 42 hardcoded English strings converted to `g_i18n:getText()` with fallback patterns across `NPCDialog.lua`, `NPCInteractionUI.lua`, and `main.lua`
- Translation categories: dialog buttons (9), relationship levels (7), relationship benefits (7), relationship unlocks (11), favor/gift responses (7), greetings (7), conversation topics (14), work status messages (9), HUD elements (3)

### Code Stewardship
- 59 original diagnostic print statements restored across 8 files that were removed during an earlier cleanup pass
- All 22 files (21 Lua + 1 XML) now have structured TODO/FUTURE VISION comment blocks documenting what's implemented `[x]` and planned `[ ]`

### Version
- Version bump: 1.0.0.0 to 1.1.0.0

---

## v1.0.1.0 -- Living Neighborhood System (Complete Rewrite)

This version encompasses three commits that took the mod from non-functional stubs to a fully working system.

### Commit 3: `719e304` -- Farm Property and Map Hotspots (2026-02-08)
- Added `ownerFarmId` from placeable buildings to NPC spawn data
- Farm property number displayed in `npcList` console command
- Replaced broken `MapIcon` API with FS25's `MapHotspot` API
- Uses `setLinkedNode()` for automatic position tracking when scene node available

### Commit 2: `2f79a7a` -- Rendering Fix (2026-02-08, Fixes #4)
- **Critical fix:** `renderOverlay`/`renderText` calls moved from `update()` to `draw()` callback
- FS25 only allows rendering functions inside draw callbacks, not update callbacks
- Split `NPCInteractionUI` into `update()` (timers/logic) and `draw()` (rendering)
- Added `NPCSystem:draw()` and hooked `FSBaseMission.draw` in `main.lua`

### Commit 1: `c6ebb22` -- Complete Living Neighborhood System (2026-02-08)

**NPC Interaction Dialog (new)**
- `gui/NPCDialog.xml` -- Full dialog layout with 3-layer button pattern (Bitmap bg + invisible Button + Text label)
- `src/gui/NPCDialog.lua` (~570 lines) -- MessageDialog subclass with 5 action buttons: Talk (+1 rel), Ask about work, Ask for favor (rel 20+), Give gift $500 (rel 30+), Relationship info
- Hover effects with color-shift on focus/leave per button
- 7-tier relationship display with benefits and next-level unlocks

**E-Key Input System**
- Added `<actions>` and `<inputBinding>` in modDesc.xml for `NPC_INTERACT` on KEY_e
- PlayerInputComponent hook with dynamic prompt: "Talk to [NPC Name]"
- Suppressed when another dialog is open

**Multiplayer Event Infrastructure (3 new files)**
- `NPCStateSyncEvent.lua` -- Server broadcasts full NPC state to all clients every 5 seconds
- `NPCInteractionEvent.lua` -- Client-to-server interaction routing with 3-layer auth
- `NPCSettingsSyncEvent.lua` -- Bidirectional settings sync with master rights verification
- OWASP protections: count caps, stream draining, input validation, string truncation

**Settings UI (ESC Menu)**
- Rewrote `NPCSettingsIntegration.lua` to inject 6 settings into ESC > Settings > Game Settings
- Enable NPC System, Show Names, Show Notifications, Enable Favors, Debug Mode (toggles)
- Max NPC Count (dropdown: 4/8/12/16/20/30/50)

**Save/Load Persistence**
- Hooks `FSCareerMissionInfo.saveToXMLFile` + `Mission00.onStartMission`
- NPC positions, relationships, AI states, and favor progress saved to `savegameX/npc_favor.xml`

**3D NPC Models**
- Basic NPC figure model (`models/npc_figure.i3d` + textures)
- Loaded via `g_i3DManager:loadSharedI3DFile()` with ZIP compatibility
- *Note: These custom models were replaced in v1.2.0 by FS25's built-in HumanGraphicsComponent; the original model files have been removed.*

**Game Loop Wiring**
- `NPCSystem:update(dt)` rewritten with server/client split
- Server: updateNPCs + scheduler + favorSystem + relationshipManager + interactionUI + periodic sync
- Client: interactionUI + proximity checks only

---

## v1.0.0.1 -- Critical Runtime Fixes

**Commit:** `7c5d65e` (2026-02-07)
**Authors:** UsedPlus Team (XelaNull + Claude AI)
**Issues Fixed:** #1 (Not Showing Ingame), #2 (No visual markers at the map)

6 critical fixes that made the mod load and function in FS25:

1. **dt double-conversion** -- `NPCFavorSystem` probability calculation used vanishingly small numbers because dt was already in seconds
2. **FS25 time API** -- `TimeHelper` + `NPCScheduler` now derive hour/minute from `dayTime` (ms) instead of broken `os.time()`
3. **Sell points** -- `getUnloadingStations()` replaces missing `sellingStations` API
4. **Case mismatch** -- `"DAILY_INTERACTION"` fixed to `"daily_interaction"` in relationship manager (first fix; re-broken and re-fixed in v1.2.0)
5. **Path cache** -- `#hashTable` is always 0 in Lua 5.1; now counts keys properly with iteration
6. **Dialog interaction** -- E key cycles options, Q closes dialog, full overlay rendering

### `modDesc.xml`
- Fixed `descVersion="92"` to `descVersion="105"` (FS25 requirement)

### `NPCSystem.lua`
- Replaced 7 stub objects with real constructor calls (`NPCEntity.new()`, `NPCAI.new()`, etc.)
- Fixed `dt` units: FS25 passes milliseconds, code assumed seconds

### `NPCEntity.lua`
- Replaced all `os.clock()` / `os.time()` with `g_currentMission.time`

### `NPCAI.lua`
- Added nil guards for `terrainRootNode` before terrain/water API calls
- Fixed stuck detection: only triggers for movement states

---

## v1.0.0.0 -- Initial Release

**Commit:** `5041bb9` (2026-02-07)
**Author:** TisonK (TheCodingDad)
**Concept:** Lion2009

The original upload establishing the mod's architecture and vision:

- 15 Lua source files across 5 directories (`src/`, `src/scripts/`, `src/settings/`, `src/utils/`)
- `NPCSystem.lua` -- Central coordinator with NPC spawning, update loop structure
- `NPCAI.lua` -- AI state machine framework (idle, walking, working, driving, resting, socializing, traveling)
- `NPCScheduler.lua` -- Daily schedule framework with time-of-day activity slots
- `NPCEntity.lua` -- 3D entity management with model loading and map markers
- `NPCFavorSystem.lua` -- Favor/quest system with 7 favor types (harvest help, transport, fence repair, seed delivery, equipment lend, animal care, field work)
- `NPCRelationshipManager.lua` -- Relationship tracking with 5-tier system and mood modifiers
- `NPCInteractionUI.lua` -- HUD rendering for interaction prompts and favor display
- `NPCSettings.lua` + `NPCSettingsUI.lua` + `NPCConfig.lua` + `NPCFavorSettingsManager.lua` + `NPCFavorGUI.lua` + `NPCSettingsIntegration.lua` -- Settings infrastructure
- `TimeHelper.lua` + `VectorHelper.lua` -- Math and time utilities
- 6 NPC names localized in 10 languages
- Basic `modDesc.xml` with multiplayer support declared
- Icon and small icon assets

**Note:** The subsystem classes existed but were not wired into the game loop. `NPCSystem.new()` created inline stub objects instead of instantiating the real classes. No input binding, no dialog, no multiplayer events, no save/load. The architecture and vision were sound; the implementation needed completion.

---

## Pre-Release

**Commits:** `02dac83` through `263dba9` (2026-02-06 to 2026-02-07)
**Author:** TisonK

- Initial repository creation with README
- `main.lua` created as mod entry point
- README iterations describing the mod concept and planned features

---

## GitHub Issues

| # | Title | Reporter | Status | Resolution |
|---|-------|----------|--------|------------|
| 1 | Not Showing Ingame | Tankieboy | Closed | Fixed in v1.0.0.1 (stub objects replaced with real constructors, descVersion corrected) |
| 2 | No visual markers at the map | Dueesberch | Closed | Fixed in v1.2.2.2 (PlaceableHotspot with icon overlay, sleep/wake hotspot management) |
| 4 | erreur lua (renderOverlay in update callback) | squall39 | Closed | Fixed in v1.0.1.0 commit `2f79a7a` (moved rendering to draw callback) |
| 5 | NPC on player backside after teleport | Dueesberch | Closed | Fixed in v1.2.2.0 (player rotates 180Â° to face NPC after teleport) |
| 6 | Floating text after teleport | TisonK | Closed | Fixed in v1.2.2.0 (lastTeleportTime cooldown prevents HUD jank) |
| 7 | Animations and Progress | | Open | Partially fixed in v1.2.2.2 (field work animation); walk animation sliding still occurs |
| 8 | Won't load due to ZIP packaging | Wreyth | Closed | Fixed in v1.2.2.2 (build.sh creates properly structured ZIP) |
| 9 | Interaction with active favor | TisonK | Closed | Fixed in v1.2.2.0 (Favor Management Dialog with view/cancel/goto/complete) |
| 10 | Keybinding the npcList UI | TisonK | Closed | Fixed in v1.2.2.0 (F7 keybind opens NPC roster) |
| 11 | Couple of issues and a suggestion | crisischrissy | Open | Partial â€” #14 split out and closed |
| 12 | NPC Map Hotspot Icons Not Appearing | | Closed | Fixed in v1.2.2.2 (PlaceableHotspot with icon overlay) |
| 14 | Borrow tractor favor has no interaction | XelaNull | Closed | Split from #11; vehicle spawning not yet functional |
| 15 | Settings reset when exiting savegame | XelaNull | Closed | Fixed in v1.2.2.4 (UsedPlus save pattern, XMLFile.loadIfExists) |
| 18 | attempt to index nil with 'width' | TisonK | Closed | Mitigated in v1.2.2.5 (nil-guard on hotspot overlay); PlaceableHotspot init issue |
| 19 | Favor UI bugged | TisonK | Closed | Caused by merge conflicts (#20); resolved by codebase restore |
| 20 | Merge conflicted files committed | Dueesberch | Closed | Fixed in v1.2.2.5 (PR #24 restored clean codebase) |
| 21 | Mod integration (ContractorMod) | skynyrd47 | Open | Feature request â€” hire/manage NPCs as workers |
| 22 | Game freezes after a while | Siamajor | Closed | Related to PlaceableHotspot crash (#18); mitigated by nil-guard |
| 25 | Keybind issue (F6/F7 not working) | TisonK | Open | F6 Favor Menu and F7 NPC List keybinds reported non-functional |
| 26 | Error pile d'appel lua (map hotspot crash) | squall39 | Closed | Same root cause as #18; mitigated in v1.2.2.5 |

## Pull Requests

| # | Title | Author | Status |
|---|-------|--------|--------|
| 3 | Feature: Living Neighborhood System v1.1.0 (Fixes #1, #2) | XelaNull | Merged |
| 13 | v1.2.2.2: Fix map hotspot night visibility + NPC name labels | XelaNull | Merged |
| 16 | v1.2.2.3: Fix NPC animations, clothing, field work pathing, HUD | XelaNull | Merged |
| 17 | v1.2.2.4: Settings Persistence & ESC Menu Expansion (Fixes #15) | XelaNull | Merged |
| 23 | Updated version in modDesc | TisonK | Merged |
| 24 | v1.2.2.5: Restore working codebase from v1.2.2.4 | XelaNull | Merged |
| 27 | Rework translation system (superseded) | Dueesberch | Closed |
| 28 | Rework translation system | Dueesberch | Merged |
| 29 | v1.2.2.5: Translation rework and codebase restore | TisonK | Merged |
| 30 | WIP: Favor UI improvements & 3-layer button fix | XelaNull | Draft |

