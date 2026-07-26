# NPC Favor Roadmap

**Current version:** 1.2.7.1
**Last updated:** 2026-07-25

> *"These NPCs notice me. They remember what I do. I'm part of this world, not just passing through it."*

---

## What works today

Confirmed working as of v1.2.7.0 (verified against the source checklists):

**Core lifecycle and AI**
- NPC spawn, update, save/load, delete; persistence across sessions via uniqueId/name matching
- 8-state AI with a needs system (energy, social, hunger, workSatisfaction)
- 5 personality types plus a "loner" variant driving behavior and schedules
- Road spline pathfinding with an LRU path cache
- Weather-aware scheduling with a schedule-aware commute speed boost
- Building-based spawning and role assignment (farmer, shopkeeper, worker) at shops, garages, and farms
- NPC farm ownership: farmland assignment, farm naming, field assignment

**Relationships**
- 7-tier system (Hostile to Best Friend), color coded, with an NPC-to-NPC social graph
- Grudge mechanic (memory of past slights), temporary moods with expiry, passive decay for inactive NPCs
- Per-tier benefits are defined and displayed (discounts, equipment borrowing, gifts) but see Known Issues for enforcement
- NPC-initiated gift giving at the best-friend tier
- Relationship change floating text ("+5 with John")

**Favors**
- 10 favor types with time limits, progress tracking, difficulty-scaled rewards and penalties
- Multi-step progression with location checkpoints; all stuck-favor conditions resolved
- Step-completion crash fixed in v1.2.7.0 (issue #62)
- Player-offered favors ("Offer help") with personality-aware decline and a 15% reward bonus
- Personality- and role-weighted generation
- Weather-emergency contextual favors (farmers first, one per in-game day)
- Seasonal favors (snow clearing in winter, irrigation in summer)
- NPC encounter memory feeding generation weights, NPC selection, and dialog tone

**Field work (v1.2.7.0)**
- Farmer NPCs spawn their own equipment on demand at the field edge and run a genuine base-game AIJobFieldWork: till, sow, or harvest, matched to the field's current state
- Crop safety (never plow or cut a standing crop), with GoTo pathfinding and kinematic visual fallbacks
- FieldSentry integration masks NPC favor fields from the soil sim (issue #56)

**UI and dialog**
- E-key interaction dialog, F6 Favor Management, F7 NPC List (paginated), F5 custom settings panel (3 categories)
- Dialog shows relationship level and benefits, favor progress, backstory/bio, mood face (happy/neutral/angry), decay warnings, and a schedule board ("Ask about work" shows the current activity plus the next slots)
- Gift selection UI: 3-tier panel ($200 / $500 / $1,000) with correct money deduction
- Admin GUI: NPCAdminListDialog and NPCAdminEditDialog for host management
- HUD: resizable favor overlay, compass direction arrows, flash notifications, right-click edit mode
- Map hotspots via the PlaceableHotspot API; markers can be toggled with showMapMarkers
- NPC name tags and relationship level projected above heads
- 1-on-1 socializing and group gatherings both produce staggered speech bubbles

**Multiplayer (implemented in code, not yet live-tested)**
- State sync (collectSyncData / applyNetworkState) broadcast every 5 seconds and on join
- Interaction routing with distance and ownership checks
- Settings sync through a master-rights-gated event pipeline

**Persistence and settings**
- 42 settings persisted per savegame; separate settings XML
- Auto-save NPC data every 5 real minutes on the server
- Save schema versioning with a migrate function and legacy detection

**Localization**
- 10 languages for all core UI, settings, relationship labels, HUD notifications, and personality backstories

**Integration**
- ContractorModBridge Phases 1 to 3 (worker detection, relationship layer, job-complete triggers)
- Companion-mod detection adds context-aware conversation topics
- Ecosystem bedrock migration BUILT (2026-07-11, folded into v1.2.7.1): all four core-API bridges delegate-when-present (StateLedger `NPCFavor_State`, NetworkSync `NPCFavor_Sync`, MasterHUD `NPCFavor_HUD`, SettingsHub `FS25_NPCFavor` selfPersisted). Each no-ops when its core API is absent.
- Farm-attributed money authority BUILT: favor money is server-authoritative through the mod's own NPCInteractionEvent, stamped with `favor.ownerFarmId` at accept, with idempotency flags on reward/repayment/loan. Correct on host/SP; the double-pay exploit is closed. See TODO.md for the test-owed items.
- Companion read API BUILT (9bdfdde): a relationship + favor read surface for DairyCore / ProStaff consumers.

---

## Known issues (partially working)

### Ambient vehicles
Farmer NPCs now drive real spawned equipment for field work. What remains missing is *ambient* travel: NPCs still commute on foot between home, town, and social events, and do not drive cars or tractors around the map for non-work movement. The `driving` AI state and the hybrid/realistic/visual vehicle-mode setting have no effect on commuting. The tractor/commute visual props are still blocked because i3d models will not load from game pak archives at runtime.

### Reputation benefits are shown but not enforced
Per-tier discounts, equipment borrowing, and shared resources are defined in NPCRelationshipManager and displayed in the dialog, but there is no hook into actual shop or buy prices. High relationship shows a "20% discount" label that does not yet change what the player pays.

### Group and emergent social content
Speech bubbles now fire for pairs and gatherings, but the emergent events (Friday party, harvest gathering, morning market, Sunday rest) exist in NPCScheduler and position NPCs without much unique content, and are largely untested in a full playthrough.

### Borrow tractor favor
The step-completion crash is fixed (v1.2.7.0), so the favor now progresses and completes. Steps 1 to 3 are still proximity-to-farm rather than a true hand-over-the-keys vehicle interaction, so it works but feels thin.

### Multiplayer never live-tested
The sync infrastructure is complete and wired, but has not been exercised in a real two-player session. There are no per-player interaction cooldowns and no conflict resolution when two players interact with the same NPC at once.

### Flavor text localization
Personality backstories and farm/age snippets are translated across all 10 languages. Mood prefixes, some personality-flavored dialog, and birthday messages remain English-only.

---

## Short-term

*Things that can ship in the next patch or two.*

**Multiplayer 2-player live test.** The single highest-value item. Infrastructure and wiring are done; it needs a real session with sync logging to shake out edge cases.

**Custom map hotspot icon.** icon.dds still fails to load from the ZIP at runtime. The fix is to preload the texture during loadMission00Finished while the ZIP context is active. Marker show/hide already works.

**TV / 4K settings-panel readability.** A player reported the F5 panel text is tiny and low-contrast at distance. favorHudScale sizes the HUD but not the panel. Add a `favorPanelScale` setting (independent of HUD scale, range 0.8-2.0) and a high-contrast toggle for the panel. Both persist through SettingsHub and ship in 26 languages. See ecosystem ledger 2026-07-26. Wizard ready to build once Arissani approves (toggle vs fixed default contrast).

**Reputation discount enforcement.** The tier benefits are already computed and displayed. Hook the discount into shop or buy prices so the number actually means something.

---

## Medium-term

*Deeper features that close the gap between what exists in code and what the vision describes.*

**Ambient vehicles.** Field-work equipment spawning works. The remaining gap is travel: NPCs driving to town, home, and events instead of walking. The vision endorses the "illusion of travel" so off-screen teleport and despawn are acceptable; perfect driving AI is not required.

**Richer group conversation content.** Deepen speech-bubble topics for pairs and gatherings, and validate the emergent events. Positioning and staggered bubbles already work; only richer content is missing.

**Contextual favor triggers (remaining legs).** Weather emergencies are wired. triggerContextualFavor also supports missed_delivery and equipment_failure and just needs world-state callbacks to fire them.

**NPCs refusing help.** The grudge mechanic exists but does not yet gate favor offers. An NPC with a grudge or a pattern of ignored favors should decline or offer worse rewards.

**Location-based schedule enforcement.** Roles drive schedule templates and favor weights already. Still missing: a shopkeeper physically staying near their building, and an NPC not "working" unless near a field.

**Dynamic schedule adjustments.** Field harvested triggers a switch to a maintenance activity. Not started.

**Dialog improvements.** Favor acceptance/rejection when multiple favors are offered; context-aware buttons such as "Return equipment"; an NPC portrait in the conversation dialog (map detail card already has partial portrait support via getPortraitImagePath).

**Flavor text localization (remaining).** Cover the remaining mood dialog and personality responses in all 10 languages. Backstories are done.

---

## Long-term

*Aspirational items from the vision document and source TODOs. Sequencing depends on what the engine allows.*

**NPCs approaching the player proactively.** Best-friend NPCs already initiate gifts. Extend this so high-relationship NPCs walk toward the player to start a request, a thank-you, or a greeting rather than always waiting for E.

**Word of mouth.** When two NPCs socialize they occasionally exchange opinions about the player, nudging the listener's relationship value.

**Home interactions.** Visiting an NPC at home: knock, wait, NPC answers if home and awake. isAtHome exists; the interaction does not.

**Global town reputation.** A town-wide opinion that affects all NPCs, layered on top of the per-NPC values.

**Dynamic population and lifecycle.** New NPCs arrive over time, existing ones age and eventually leave. Population density per area.

**Economy tie-ins.** NPC farm output nudges local market prices; NPC-owned fields compete with the player. NPC field work now produces real crop-state changes, which makes this more reachable.

**Hiring NPCs as farmhands.** Permanent workers with wages, skill progression, task assignment, and the ability to quit if mistreated.

**Mod API hooks.** A public g_NPCFavorAPI with registerNPCType and registerFavorType so other mods can extend the system without patching source.

**Southern hemisphere season support.** A single boolean in NPCSettings to invert the calendar. TimeHelper.getSeason is the only place that changes.

**Relative time formatting.** "2 hours ago", "yesterday" in favor timers and timestamps. TimeHelper has a TODO stub for this.

---

## Out of scope

These will not be built:

- Full life simulation (eating, sleeping animations)
- Enterable NPC homes with interiors
- Branching dialogue trees or heavy narrative scripting
- Romance or dating mechanics

---

## Guiding principle

Every item here should make NPCs feel **noticed**, **persistent**, and **socially meaningful**, without overwhelming the farming experience.
