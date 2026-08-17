# NPC Favor -- TODO / Roadmap

**Current version:** 1.2.7.66
**Last updated:** 2026-08-15

This TODO reflects the **honest current state** of the mod. The "Done" block below is the original v1.2.2.4 baseline and still holds; the fuller current-state picture (field work, player-offered favors, the bedrock migration) lives in ROADMAP.md and the section below. Items are grouped by status: what works, what's partially working, what's broken, and what's planned.

---

## Recently merged

- **2026-08-15** Esc framework table freeze (NPC Favor guest, #87): shared grid restated per show; 1.2.7.66. In-game owed: the table keeps its columns after visiting another Esc guest in the same session.

---

## Done (Working in v1.2.2.4)

### Core Systems
- [x] NPC system initialization and lifecycle (spawn, update, save, load, delete)
- [x] Needs-based AI with 4 internal needs (energy, social, hunger, workSatisfaction)
- [x] 8-state AI state machine (idle, walking, working, driving, resting, socializing, traveling, gathering)
- [x] 5 personality types (hardworking, lazy, social, grumpy, generous) affecting behavior
- [x] Road spline pathfinding with cached paths (NPCPathfinder)
- [x] NPCFieldWork module with boustrophedon row traversal
- [x] Personality-specific daily schedules with weekend variation and seasonal adjustment
- [x] Weather awareness (rain/storm interrupts field work, weather-aware dialog)

### Relationships
- [x] 7-tier player-NPC relationship system (Hostile through Best Friend, 0-100 scale)
- [x] NPC-NPC social graph with personality compatibility matrix
- [x] Relationship decay for inactive relationships (configurable)
- [x] Grudge system for persistent negative feelings
- [x] NPC-initiated gifts at high relationship levels

### Favors
- [x] 7 favor types with time limits, progress tracking, and rewards
- [x] Favor Management Dialog (F6) with view, cancel, goto, complete actions
- [x] Favor frequency and difficulty settings
- [x] Configurable max active favors and multiple favor toggle

### Dialog & UI
- [x] E-key interaction dialog with 5 action buttons (Talk, Work, Favor, Gift, Relationship Info)
- [x] NPC List dialog (F7) with roster table and teleport-to-NPC buttons
- [x] World-space speech bubbles for NPC-NPC socializing
- [x] Floating name tags with dynamic Y-scaling by distance
- [x] Floating relationship change text (+1, -2 popups)
- [x] Active favor list HUD overlay
- [x] Map hotspots using PlaceableHotspot (built-in exclamation mark icon)
- [x] HUD suppression during pause, map, ESC menu, and dialogs

### Settings & Persistence
- [x] 42 settings persisted to XML per-savegame
- [x] 13 settings exposed in ESC menu under "NPC Favor System" header
- [x] Settings save via FSCareerMissionInfo.saveToXMLFile hook (UsedPlus pattern)
- [x] Settings load via XMLFile.loadIfExists
- [x] Multiplayer settings sync (NPCSettingsSyncEvent)
- [x] NPC data save/load (positions, relationships, AI state, needs, favors)

### Infrastructure
- [x] 10-language localization (1,500+ i18n strings inline in modDesc.xml)
- [x] Multiplayer event system (state sync, interaction routing, settings sync)
- [x] Eager dialog loading from ZIP (works reliably from mod archives)
- [x] Cross-platform build script with --deploy flag
- [x] Console commands (npcHelp, npcStatus, npcList, npcGoto, npcDebug, npcFavors, npcProbe)
- [x] Gender system with male/female name pools and clothing
- [x] Animated character models via FS25 HumanGraphicsComponent

---

## Partially Working / Known Issues

### NPC Vehicles
- [ ] Vehicle prop code exists but no vehicles spawn or render
- [ ] `spawnNPCTractor`, `seatNPCInVehicle`, `unseatNPCFromVehicle` are implemented but i3d models can't be loaded from game pak archives at runtime
- [ ] NPCs walk everywhere; driving state exists but is non-functional
- [ ] Vehicle mode setting exists (hybrid/realistic/visual) but has no visible effect

### Social Behaviors
- [ ] Group gatherings position NPCs correctly but generate no conversation content
- [ ] Walking pairs form but produce no speech bubbles (only 1-on-1 socializing works)
- [ ] Friday party, harvest gathering, morning market, Sunday rest events exist in code but are untested

### Localization
- [ ] Mood prefixes, backstories, and personality-flavored dialog are English-only
- [ ] Core UI, settings, and relationship labels are fully localized in all 10 languages

### Favors
- [ ] "Borrow tractor" favor has no interaction menu option (issue #14)
- [ ] Favor progress tracking is implemented but some favor types lack completion detection

### Multiplayer
- [ ] Multiplayer sync infrastructure is complete but multiplayer is untested
- [ ] State sync, interaction routing, and settings sync events all implemented

### TV / 4K readability (issue #63 sub-issue #2)
- [ ] F5 settings panel has no independent scale and uses light-gray-on-white text, unreadable on TV at distance. Design: add `favorPanelScale` (independent of HUD scale, range 0.8-2.0) + high-contrast toggle. See ecosystem ledger 2026-07-26. Wizard ready to build once Arissani approves (toggle vs fixed default contrast).

### Ecosystem bedrock migration + money authority (BUILT 2026-07-11, pending in-game + two-machine MP test)
Built as one coherent pass per the farm-attribution cert (NPCFAVOR-FARM-ATTRIBUTION-CERT.md) + the bedrock playbook. All four bridges are delegate-when-present (no bedrock dependency; each no-ops when its core API is absent). Money is server-authoritative through the mod's OWN NPCInteractionEvent, so money correctness does not depend on bedrock being installed.
- [x] Bedrock migration built: StateLedger (`NPCFavor_State`, serializeState/deserializeState, npc_favor.xml kept as safety copy), NetworkSync (`NPCFavor_Sync`, full-snapshot state sync via collectSyncData/applyNetworkState, own NPCStateSyncEvent kept as fallback), MasterHUD (`NPCFavor_HUD` subscribe of NPCSystem:draw, own draw hook stands down when active), SettingsHub (`FS25_NPCFavor`, selfPersisted mirror of the panel's settings + admin/player split). Bridge files in src/integrations/, registered at loadMission00Finished.
- [x] Money authority: all six sites now pay `favor.ownerFarmId` server-side (NPCFavorSystem 883 loan disburse, 1112 loan repayment, 1119 reward, 1154 bonus; NPCDialog gift deduct via serverGiveGift; loan-repay dialog paths now send intent). Client dialogs send intent through NPCInteractionEvent; no client-side addMoney remains.
- [x] Farm attribution: `favor.ownerFarmId` stamped at accept (acceptFavorForNPC(npcId, farmId), validated by NPCInteractionEvent:run), persisted, with a host-farm migration default (resolveOwnerFarmId, logged) for legacy in-flight favors.
- [x] Idempotency: `rewardPaid` (reward + perfect bonus) and `repaymentCollected` (loan principal) added alongside the existing `loanAmountDeducted`, all persisted in both the XML and StateLedger round-trips.
- [x] Dead dispatch rewired: serverAcceptFavor -> acceptFavorForNPC(npc.id, farmId); serverCompleteFavor / serverAbandonFavor resolve the favor by npc then call the real favorId signatures. completeFavor is now server-gated (`g_server == nil` early return) so it is the single authoritative completion path.
- [x] BUG fixed: NPCFavorManagementDialog:376 inline addMoney double-pay removed (completeFavor is the single pay path); that button now sends a server-authoritative completion intent.
- [x] Companion read API (9bdfdde): a relationship + favor read surface for companions (the DairyCore / ProStaff ask), so consumers read the relationship state without touching internals.
- [x] Save hardening (#63, 1db1a8b): XML strings escaped on save and the load path hardened against corruption.
- [x] Released folded into v1.2.7.1 (money authority + core-service bridges + companion read API rolled into the hotfix line rather than a separate 1.2.8.0).
- [ ] TEST OWED: in-game host/SP smoke test (accept, complete, loan lifecycle, gift, perfect bonus, reload). The live two-machine MP test is hardware-blocked (ledger reframe 2026-07-15); the operative gate for the wave is the network self-test harness + a single-host smoke. Money is server-authoritative and correct on host/SP regardless. Verify a client's favor money lands on the correct farm.
- [ ] ARCHITECTURE NOTE (flagged, not changed): favor GENERATION + state are effectively per-client in the current MP design (favor sim runs server-only, but dialogs create/manage favors on whichever machine opens them; collectSyncData carries NPC state, not favors). The money fix closes the client-authoritative-money exploit and is fully correct on host/SP. A full server-authoritative favor lifecycle (server owns generation + favor-state sync to clients) is a larger follow-up in K's deep-audit territory, not part of this money pass.

---

## Planned / Not Started

### Short-Term
- [ ] Custom map hotspot icon (current: built-in exclamation mark; custom icon.dds fails from ZIP)
- [ ] Close GitHub issues that are fixed (#2, #12 fixed but still Open on GitHub)
- [ ] Test multiplayer functionality end-to-end

### Medium-Term
- [ ] Make NPC vehicles functional (major engine limitation to solve)
- [ ] Vehicle parking logic near destinations (VISION: vehicles park at work/shop/home)
- [ ] Group conversation content for gatherings and walking pairs
- [ ] Localize flavor text (backstories, mood dialog, personality responses) in all 10 languages
- [ ] Favor completion detection for all 7 favor types
- [ ] NPC memory system driving behavior (10 records per NPC exist but don't influence decisions yet)
- [ ] Contextual favor triggers (NPC vehicle breaks down, missed delivery, weather emergency)
- [ ] Player-offered favors (currently only NPCs can request; VISION: player can offer help too)
- [ ] NPC role differentiation (farmer, shop owner, contractor, resident affect schedules and favor types)
- [ ] Personality-preferred favor types (generous NPCs ask different favors than grumpy ones)

### Long-Term / Aspirational
- [ ] NPCs requesting favors proactively (approaching the player)
- [ ] NPCs refusing help based on past behavior patterns
- [ ] Reputation-based unlocks (discounts at shops, access to special tasks)
- [ ] Visiting NPCs at home (knock on door, home-based interactions)
- [ ] Home-based mood modifiers (distance from home, home condition affecting NPC mood)
- [ ] Word of mouth (NPCs share opinions about the player with each other, indirect consequences)
- [ ] Economy tie-ins (NPC farm output affects local market prices)
- [ ] Hooks for other mods to register custom NPCs or favor types
- [ ] Southern hemisphere season support
- [ ] Relative time formatting in UI ("2 hours ago", "yesterday")

---

## Explicitly Out of Scope

- Full NPC life simulation (eating, sleeping animations, interior homes)
- Interior NPC homes (homes are logical anchors, not enterable buildings)
- Heavy dialogue trees or branching narratives
- Romance / dating mechanics

---

## Guiding Principle

> Every item on this list should support the core goal: making NPCs feel *noticed*, *persistent*, and *socially meaningful* without overwhelming the farming experience.

This list is expected to evolve as FS25 modding constraints and design ideas change.
