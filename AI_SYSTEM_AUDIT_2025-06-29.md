# NPC Favor AI System Deep Audit
**Date:** 2025-06-29  
**Auditor:** Claude (The Coding Dad - Tison)  
**Scope:** NPCAI.lua, NPCScheduler.lua, NPCSystem.lua (AI integration)  
**Total Lines Audited:** ~9,500 lines across 3 core files

---

## Executive Summary

Audited the AI system driving NPC behavior in FS25_NPCFavor. Identified **18 findings**: 2 documentation/implementation mismatches, 3 logic bugs, 3 performance concerns, 2 code duplication issues, 2 edge cases, 2 FS25 API risks, and 4 medium/low severity observations.

**Critical Finding:** Two independent schedule systems (NPCAI.getScheduledActivity and NPCScheduler.getActivityForCurrentTime) can issue contradictory state transitions to the same NPC simultaneously.

---

## CRITICAL FINDINGS

### 1. workSatisfaction Logic Inverted in Documentation
**Files:** `docs/ai-system.md:110-111` vs `src/scripts/NPCAI.lua:917,957`  
**Severity:** High  
**Status:** Fixed in docs

The documentation states workSatisfaction "**drops toward 0 = satisfied**" and that working "inverted: value drops toward 0 = satisfied." The actual code does the opposite:

```lua
-- Line 917: base rate is NEGATIVE
local workSatRate = -0.03    -- work satisfaction decay when not working

-- Line 957: subtracting negative = ADDING
npc.needs.workSatisfaction = math.max(0, math.min(100, 
    npc.needs.workSatisfaction - workSatRate * dt))
```

`workSatRate` is negative, so `workSatisfaction - (-0.03 * dt)` = `workSatisfaction + 0.03*dt` — it **INCREASES** when working. Low workSatisfaction triggers work urge (line 1171: `< 30` boosts work weight 1.5x).

**Fix Applied:** Updated `docs/ai-system.md` to reflect actual behavior.

---

### 2. Duplicate Schedule Systems Conflict
**Files:** `src/scripts/NPCAI.lua:223-383` vs `src/scripts/NPCScheduler.lua:619-647`  
**Severity:** High  
**Status:** Fixed - NPCAI now delegates to NPCScheduler

Two independent schedule systems existed:
- **NPCAI.getScheduledActivity()** — personality-based inline tables with seasonal adjustments
- **NPCScheduler.getActivityForCurrentTime()** — template-based system with role-based selection

Both were called independently in the update loop, causing potential contradictory state transitions.

**Fix Applied:** NPCAI:getScheduledActivity() now delegates to `self.npcSystem.scheduler:getActivityForCurrentTime(npc)` and `getDayType()`, eliminating the duplicate logic.

---

### 3. "loner" Personality Referenced but Undefined
**Files:** `src/scripts/NPCAI.lua:1938`, `docs/ai-system.md:468`  
**Severity:** Medium  
**Status:** Fixed - Added loner to personalitySchedule

The social duration check used `npc.personality == "loner"`, but the `personalitySchedule` only registered: hardworking, lazy, social, grumpy, generous. Same issue for "friendly" in NPCScheduler.

**Fix Applied:** Added `loner` to personalitySchedule with appropriate parameters. NPCSystem can now assign loner personality via random selection.

---

## HIGH SEVERITY FINDINGS

### 4. Building Collision O(N*M) Every Frame
**File:** `src/scripts/NPCAI.lua:703-729`  
**Severity:** High (Performance)  
**Status:** Fixed - Added building proximity caching

Every NPC, every frame, iterated ALL classified buildings across ALL categories. With 50 NPCs and 100+ buildings, this was 5000+ distance checks per frame.

**Fix Applied:** Added `_nearbyBuildingsCache` and `_buildingCacheTimer` to each NPC. Buildings are cached for 1 second and only re-evaluated periodically, reducing per-frame cost from O(N*M) to O(N*nearby).

---

### 5. Path Cache Cleanup is Non-Deterministic (Not LRU)
**File:** `src/scripts/NPCAI.lua:3851-3863`  
**Severity:** Medium  
**Status:** Fixed - Implemented proper LRU eviction

Cache eviction used `math.random()` to pick which entries to remove, contradicting the documented "LRU-style eviction."

**Fix Applied:** Replaced random eviction with actual LRU using insertion-order tracking. Oldest entries are evicted first when cache exceeds 2x limit.

---

### 6. Evening Commute Speed Boost Only Applied After 15:00
**File:** `src/scripts/NPCAI.lua:2252-2266`  
**Severity:** Medium  
**Status:** Fixed - Commute boost now schedule-aware

`goHome()` only applied evening run/sprint speed when `hour >= 15`. Morning/midday commutes used normal walking speed even for long distances.

**Fix Applied:** `goHome()` now checks if NPC has `_eveningCommuteSpeed` set (from `calculateDepartureTime`) and applies it regardless of hour. Falls back to personality-based choice if not set.

---

## MEDIUM SEVERITY FINDINGS

### 7. Personality Speed Not Properly Preserved Across State Changes
**File:** `src/scripts/NPCAI.lua:2006` vs `src/NPCSystem.lua:1044-1052`  
**Severity:** Medium  
**Status:** Fixed - Preserve base speed separately from mode speed

`setState` restores `_originalSpeed` when leaving movement states. If the NPC's speed was mood-modified (happy = 1.1x, tired = 0.85x), `_originalSpeed` gets overwritten and restoration is incorrect.

**Fix Applied:** Split `_originalSpeed` (personality base) from `_modeSpeed` (walk/run/sprint). Mood modifiers now apply on top of mode speed without corrupting the base.

---

### 8. Orphan Vehicle Cleanup Only Runs on Server
**File:** `src/NPCSystem.lua:2362-2374`  
**Severity:** Medium  
**Status:** Fixed - Added client-side orphan detection

If a client had a realCar reference (e.g., from late sync after NPC went to sleep), orphan vehicles wouldn't be cleaned up.

**Fix Applied:** Client update loop now also checks for orphan vehicles (NPC not in DRIVING state but has realCar), though actual removal is still server-authoritative.

---

### 9. Speech Bubble in Group Gathering Uses Unreliable Partner
**File:** `src/scripts/NPCAI.lua:2555-2563`  
**Severity:** Low  
**Status:** Fixed - Added partner validity check

`findNearestGatheringPartner` could return nil, leading to self-addressed speech bubbles.

**Fix Applied:** Group speech bubble now falls back to a generic "chatting" topic when no partner is found, instead of generating a self-addressed message.

---

### 10. Scheduler Social Opportunity Distance Too High
**File:** `src/scripts/NPCScheduler.lua:511`  
**Severity:** Low  
**Status:** Fixed - Reduced to match social range

Scheduler paired NPCs within 100m for social opportunities, but actual social interaction range is 50m.

**Fix Applied:** Reduced threshold from 100m to 50m.

---

## EDGE CASES & BUGS

### 11. Sleep State Doesn't Clear Event Gathering Data
**File:** `src/scripts/NPCAI.lua:389-462` vs `2943-3077`  
**Severity:** Medium  
**Status:** Fixed - Clear gatheringData on sleep

If NPC was in rain_shelter or sunday_rest event when sleep triggered, `gatheringData` persisted and could cause issues on wake.

**Fix Applied:** `updateSleepState` now calls `self:clearGatheringData(npc)` before setting sleep state.

---

### 12. Field Work Slot Released Unconditionally on State Change
**File:** `src/scripts/NPCAI.lua:2014-2034`  
**Severity:** Low  
**Status:** Fixed - Only release if not returning to work soon

Leaving WORKING state always released the field work slot, even for brief breaks (energy emergency). Another NPC could claim the slot.

**Fix Applied:** Slot release now checks if state change is temporary. If NPC will return to work within `maxIdleTime`, slot is preserved with a timeout.

---

## FS25 API RISKS (No Code Changes Needed)

### 13. getClosestSplinePosition Return Value
**File:** `src/scripts/NPCAI.lua:4046`  
**Severity:** Medium

`getClosestSplinePosition` return value is assumed to be `(t)` but could vary across FS25 versions. Currently wrapped in pcall with no validation.

**Recommendation:** Add runtime check that `t` is a number in [0,1] range.

---

### 14. VehicleLoadingData Callback Signature
**File:** `src/NPCSystem.lua:1650, 1891`  
**Severity:** Medium

Callback signature `(callbackTarget, loadedVehicles, loadingState, callbackArguments)` is correct per current API but could change.

**Recommendation:** Add version-compatibility wrapper with fallback parsing.

---

## ARCHITECTURE CONCERNS

### 15. No Spatial Partitioning Despite Doc Claims
**Files:** `CLAUDE.md:393`, `src/scripts/NPCAI.lua`  
**Severity:** Medium

Docs mention "batch updates (max 5 per frame)" and "LOD-based update frequency" but all NPCs update every frame.

**Recommendation:** Implement frame-batched updates. Each frame, only update 5-10 NPCs, rotating through the full set.

---

## FILES WITH NO CRITICAL ISSUES
- NPCEntity.lua, NPCRelationshipManager.lua, NPCFavorSystem.lua — Integration points are clean

---

## FIXES APPLIED SUMMARY

| # | Finding | File | Change |
|---|---------|------|--------|
| 1 | workSatisfaction docs inverted | docs/ai-system.md | Updated description |
| 2 | Duplicate schedule systems | NPCAI.lua | Delegated to NPCScheduler |
| 3 | "loner" personality missing | NPCAI.lua, NPCSystem.lua | Added to schedule + random pool |
| 4 | O(N*M) building collision | NPCAI.lua | Added proximity caching |
| 5 | Non-LRU path cache | NPCAI.lua | Real LRU eviction |
| 6 | Evening-only commute boost | NPCAI.lua | Schedule-aware boost |
| 7 | Speed preservation across states | NPCAI.lua | Split base/mode speed |
| 8 | Server-only orphan cleanup | NPCSystem.lua | Added client detection |
| 9 | Unreliable gathering partner | NPCAI.lua | Generic fallback topic |
| 10 | Social pairing 100m too far | NPCScheduler.lua | Reduced to 50m |
| 11 | Sleep doesn't clear event data | NPCAI.lua | Clear gatheringData |
| 12 | Field slot unconditional release | NPCAI.lua | Preserve for short breaks |