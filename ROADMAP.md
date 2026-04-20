# NPC Favor — Roadmap

**Current version:** 1.2.3.0  
**Last updated:** April 2026

> *"These NPCs notice me. They remember what I do. I'm part of this world, not just passing through it."*

---

## What works today

Everything below is confirmed working as of v1.2.3.0, accounting for all changes through the v1.2.2.6 HUD rework:

- NPC lifecycle: spawn, update, save/load, delete
- 8-state AI with needs system (energy, social, hunger, workSatisfaction)
- 5 personality types influencing behavior and schedules
- Road spline pathfinding with LRU path cache
- Boustrophedon field work with personality-driven row patterns
- Weather-aware scheduling
- 7-tier relationship system (Hostile → Best Friend), NPC-NPC social graph, grudge system
- 7 favor types with time limits, progress tracking, and rewards
- Favor Management Dialog (F6), NPC List dialog (F7), E-key interaction dialog
- HUD: resizable favor overlay, compass direction arrows, flash notifications, edit mode (right-click)
- Favor timers running on in-game time (corrected in v1.2.2.6)
- 42 settings persisted to XML per savegame, 13 exposed in ESC menu
- Multiplayer event infrastructure: state sync, interaction routing, settings sync
- 10-language localization for all core UI, settings, and relationship labels
- ContractorModBridge: worker detection and relationship layer (Phase 1–2 complete)

---

## Known issues (partially working)

### NPC vehicles
Vehicle prop code exists — `spawnNPCTractor`, `seatNPCInVehicle`, `unseatNPCFromVehicle` are all implemented — but i3d models cannot be loaded from game pak archives at runtime. NPCs walk everywhere. The `driving` AI state and the vehicle mode setting (hybrid/realistic/visual) exist but have no effect.

### Group social content
Group gatherings position NPCs correctly but generate no conversation content. Walking pairs form but produce no speech bubbles. Only 1-on-1 NPC socializing produces speech bubbles today. The Friday party, harvest gathering, morning market, and Sunday rest events exist in `NPCScheduler` but are untested.

### Borrow tractor favor
The favor type exists and can be assigned to an NPC, but there is no interaction menu option to fulfil it. Blocked by vehicles not being functional.

### Favor completion detection
Progress tracking works for all 7 favor types, but completion detection is missing or incomplete for some types — favors can get stuck in progress without resolving.

### Multiplayer
The sync infrastructure is complete but has never been tested in a real two-player session. No per-player interaction cooldowns exist and there is no conflict resolution when two players interact with the same NPC simultaneously.

### Flavor text localization
Mood prefixes, NPC backstories, personality-flavored dialog, and birthday messages are English-only. All structural UI, settings labels, and relationship tier names are fully localized across all 10 languages.

---

## Short-term

*Things that can ship in the next patch or two.*

**Custom map hotspot icon**  
`icon.dds` currently fails to load from the ZIP at runtime because DirectStorage can't resolve mod ZIP paths outside the mission-load window. The fix is to preload the texture during `loadMission00Finished` while the ZIP context is still active — the same window used for eager dialog loading.

**Favor completion detection**  
Audit all 7 favor types and wire up missing completion callbacks. This is the most impactful user-facing fix that doesn't depend on any engine limitation.

**Multiplayer end-to-end test**  
Run a real two-player session with sync logging enabled. The infrastructure is there — it just needs to be exercised and the inevitable edge cases fixed.

**ContractorModBridge — Phase 3 triggers**  
Co-work proximity gains, greeting radius, job-complete rewards, and crash penalties are defined in `ContractorModBridge.lua` but not yet connected. Completing this closes issue #21 without requiring ContractorMod to expose a public API.

**Save file migration system**  
The XML loader reads a version tag but performs no migration. Adding a migration path now is cheap — waiting until the save format diverges makes it expensive and breaks player saves.

**Auto-save NPC data**  
Currently NPC state only saves on manual save. Adding a periodic auto-save guard would prevent data loss on crash.

---

## Medium-term

*Deeper features that close the gap between what exists in code and what the vision describes.*

**NPC vehicles**  
The biggest open gap. Options to investigate: loading vehicle models from the mod's own ZIP rather than the game pak, or building a visual-only prop vehicle using a simpler mesh that doesn't require pak access. The vision document explicitly endorses "illusion of travel" — off-screen teleporting and despawning outside the player's view are acceptable. Perfect driving AI is not required.

**Group conversation content**  
Generate speech bubble content for walking pairs and group gatherings. The positioning logic already works; only the content generation is missing. The untested emergent events (Friday party, harvest gathering, morning market, Sunday rest) should be validated at the same time.

**Player-offered favors**  
Currently only NPCs can request favors. Adding an "Offer help" option to the dialog lets the player initiate the social contract, which is explicitly called out in the vision document.

**NPC memory influencing behavior**  
Each NPC already stores up to 10 encounter records in the save file but these records don't influence any decisions. Connect them to dialog tone and favor generation: an NPC who has been ignored repeatedly should be less forthcoming; one who receives regular gifts should generate favors more readily.

**Contextual favor triggers**  
React to world state: NPC vehicle breaks down, a delivery is missed, a weather emergency interrupts work. `NPCScheduler` already has weather and event callbacks — they need to feed into `NPCFavorSystem` to produce reactive favor requests.

**NPC role differentiation**  
Roles (farmer, shop owner, contractor, resident) are assigned at spawn but barely affect behavior. A shop owner should skew their schedule toward their building; a contractor should generate transport and equipment favors. Implement role-based schedule overrides in `NPCScheduler` and role-filtered favor weights in `NPCFavorSystem`.

**Personality-preferred favor types**  
Generous NPCs should ask for different things than grumpy ones. Add a personality-weighting layer to the favor generation logic in `NPCFavorSystem`.

**Flavor text localization**  
Coordinate with community translators to cover backstories, mood dialog, and personality responses in all 10 languages. The infrastructure is already in place.

**Schedule improvements**  
- Custom per-NPC schedules instead of only personality templates  
- Location-based enforcement (NPC won't "work" if not physically near a field)  
- Dynamic adjustments (field harvested → switch to maintenance activity)  
- Player-visible schedule board showing when and where NPCs will be  

**Dialog improvements**  
- Gift selection UI (choose from money, crops, or equipment rather than a hardcoded $500)  
- Favor acceptance/rejection dialog when multiple favors are on offer  
- Context-aware buttons (e.g. "Return equipment" when the player holds a borrowed item)  
- NPC portrait/avatar image in the conversation dialog  

---

## Long-term

*Aspirational items from the vision document and source-file TODOs. Sequencing depends on what the FS25 engine allows and how earlier phases land.*

**Reputation-based unlocks**  
High-relationship NPCs offer shop discounts, equipment loans, and shared resources. The relationship tier benefits are already defined in `NPCRelationshipManager` — they need to be enforced at interaction time rather than just displayed.

**NPCs refusing help**  
An NPC with a grudge or a pattern of ignored favors should decline new requests or offer worse rewards.

**NPCs approaching the player proactively**  
High-relationship NPCs walk toward the player to initiate a request, a thank-you, or a greeting, rather than always waiting for E to be pressed.

**Word of mouth**  
When two NPCs socialize they occasionally exchange opinions about the player, nudging the listener's relationship value. This creates indirect consequences without any direct player action.

**Home interactions**  
Visiting an NPC at their home: knock, wait, NPC answers if home and awake. Home-proximity mood modifiers (distance traveled from home, time spent away) connect naturally here.

**NPC lifecycle**  
New NPCs arrive over time, existing ones age and eventually retire or leave. Dynamic population density per area.

**Economy tie-ins**  
NPC farm output nudges local market prices. NPC-owned fields compete with the player for harvest and sales.

**Hiring NPCs as farmhands**  
Permanent workers with wages, skill progression, task assignment, and the ability to quit if mistreated or underpaid.

**Mod API hooks**  
A public `g_NPCFavorAPI` table with `registerNPCType()` and `registerFavorType()` so other mods can extend the system without patching NPC Favor's source directly.

**Southern hemisphere season support**  
A single boolean setting in `NPCSettings` to invert the season calendar. `TimeHelper.getSeason()` is the only place that needs to change.

**Relative time formatting**  
"2 hours ago", "yesterday" in favor timers and interaction timestamps. `TimeHelper` already has a `TODO` stub for `formatRelativeTime(ms)`.

---

## Out of scope

These will not be built:

- Full life simulation (eating animations, sleeping animations)
- Enterable NPC homes with interiors
- Branching dialogue trees or heavy narrative scripting
- Romance or dating mechanics

---

## Guiding principle

Every item on this list should make NPCs feel **noticed**, **persistent**, and **socially meaningful** — without overwhelming the farming experience.
