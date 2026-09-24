-- RSF-F221: a saved favour's remaining travel target must not move on reload.
--!load: src/utils/NPCFarmIdentity.lua, src/scripts/NPCPersonRoster.lua, src/scripts/NPCFavorSystem.lua, src/scripts/NPCFavorRecovery.lua, src/NPCSystem.lua
-- Ported from the certified design bar (Office Tyson/mods/FS25_NPCFavor/
-- RSF-F221-travel_target_persistence_spec_test.lua). The witness blocks and the
-- reference contract are kept as delivered: the step builder itself is
-- unchanged by this repair (a nil home still yields one step; the placeholder
-- lives in the restore assembly, not the builder). A real-source section at
-- the end drives the built exportFavorRecord, the XML writer and reader, the
-- restore assembly and the StateLedger path. Nothing here proves native UI,
-- disk, network, multiplayer or gameplay.

TimeHelper = {getGameTimeMs = function() return 1000 end}
g_currentMission = {time = 1000, player = {farmId = 1}}
FarmManager = FarmManager or {SPECTATOR_FARM_ID = 0, SINGLEPLAYER_FARM_ID = 1, MAX_FARM_ID = 8,
    GUIDED_TOUR_FARM_ID = 14, INVALID_FARM_ID = 15}
local LIVE_FARMS = {}
g_farmManager = {
    getFarmById = function(_, id) return LIVE_FARMS[id] end,
    getFarms = function(_)
        local list = {}
        for _, farm in pairs(LIVE_FARMS) do list[#list + 1] = farm end
        table.sort(list, function(a, b) return a.farmId < b.farmId end)
        return list
    end,
}
local function setLiveFarms(ids)
    for k in pairs(LIVE_FARMS) do LIVE_FARMS[k] = nil end
    for _, id in ipairs(ids) do LIVE_FARMS[id] = {farmId = id, name = "Farm " .. id, showInFarmScreen = true, isSpectator = false} end
end
setLiveFarms({1, 3})

VectorHelper = VectorHelper or {}
VectorHelper.distance2D = function(x1, z1, x2, z2)
    local dx, dz = x2 - x1, z2 - z1
    return math.sqrt(dx * dx + dz * dz)
end

local function builderSelf()
    return setmetatable({
        findNearestSellPoint = function(_self, x, z)
            return {x = x + 100, y = 0, z = z + 100, name = "Co-op"}
        end
    }, {__index = NPCFavorSystem})
end

-- ---------------------------------------------------------------------------
-- WITNESS 1. A nil home does not degrade the rebuild, it collapses it to one
-- step. This is the trap that would silently discard every saved destination
-- in the missing-neighbour case, which is the case the repair exists for.
-- ---------------------------------------------------------------------------
do
    local sys = builderSelf()
    local absent = {id = 7, name = "Gone", homePosition = nil, assignedField = nil}
    local steps = NPCFavorSystem.generateFavorSteps(sys, {id = "fix_fence"}, absent)
    T.eq("F221 witness: a nil home yields exactly one step, not a degraded three", #steps, 1)
    T.eq("F221 witness: that one step carries no location at all", steps[1].location, nil)
    T.eq("F221 witness: the early return ignores the favour type entirely", steps[1].description, "Complete the task")

    local present = {id = 7, name = "Here", homePosition = {x = 10, y = 2, z = 20}, assignedField = nil}
    local full = NPCFavorSystem.generateFavorSteps(sys, {id = "fix_fence"}, present)
    T.eq("F221 witness: the same favour type with a real home yields three steps", #full, 3)
    T.ok("F221 witness: so a saved three-step set cannot match a nil-home rebuild", #full ~= #steps)
end

-- ---------------------------------------------------------------------------
-- WITNESS 2. One table object sits at more than one step index, so an in-place
-- write to a step location rewrites a sibling step in the same list.
-- ---------------------------------------------------------------------------
do
    local sys = builderSelf()
    local npc = {id = 3, name = "Mara", homePosition = {x = 5, y = 1, z = 6}, assignedField = nil}

    local tractor = NPCFavorSystem.generateFavorSteps(sys, {id = "borrow_tractor"}, npc)
    T.eq("F221 witness: borrow_tractor builds three steps", #tractor, 3)
    T.ok("F221 witness: tractor steps 1 and 3 are the SAME table object", rawequal(tractor[1].location, tractor[3].location))
    T.ok("F221 witness: and that object is the neighbour's own home record", rawequal(tractor[1].location, npc.homePosition))

    local watch = NPCFavorSystem.generateFavorSteps(sys, {id = "watch_property"}, npc)
    T.ok("F221 witness: watch_property shares one object across both steps", rawequal(watch[1].location, watch[2].location))

    local loan = NPCFavorSystem.generateFavorSteps(sys, {id = "loan_money"}, npc)
    T.ok("F221 witness: loan_money shares one object across both steps", rawequal(loan[1].location, loan[2].location))

    -- The consequence, demonstrated rather than asserted in prose.
    tractor[1].location.x = 999
    T.eq("F221 witness: writing step 1 in place moves step 3 as well", tractor[3].location.x, 999)
    T.eq("F221 witness: and it moves the neighbour's home record too", npc.homePosition.x, 999)
end

-- ---------------------------------------------------------------------------
-- WITNESS 3. An assigned field's centre is aliased by reference, and a helper
-- return is not. These are the alias sources the never-write-in-place rule
-- classifies.
-- ---------------------------------------------------------------------------
do
    local sys = builderSelf()
    local field = {id = 1, center = {x = 80, y = 0, z = 90}, size = 1}
    local npc = {id = 4, name = "Ines", homePosition = {x = 0, y = 0, z = 0}, assignedField = field}

    local harvest = NPCFavorSystem.generateFavorSteps(sys, {id = "help_harvest"}, npc)
    T.ok("F221 witness: a field step aliases the neighbour's field centre", rawequal(harvest[1].location, field.center))

    local equip = NPCFavorSystem.generateFavorSteps(sys, {id = "retrieve_equipment"}, npc)
    T.ok("F221 witness: the equipment step is the third alias source", rawequal(equip[1].location, field.center))

    local sell = NPCFavorSystem.generateFavorSteps(sys, {id = "transport_goods"}, npc)
    T.ok("F221 witness: a sell-point step is a private table, not an alias", not rawequal(sell[2].location, field.center))
    T.ok("F221 witness: and not the home record either", not rawequal(sell[2].location, npc.homePosition))

    local water = NPCFavorSystem.generateFavorSteps(sys, {id = "water_animals"}, npc)
    T.ok("F221 witness: a computed offset step is private", not rawequal(water[2].location, npc.homePosition))
end

-- ---------------------------------------------------------------------------
-- WITNESS 4. The destinations move between sessions. Two calls with the same
-- neighbour and a re-picked field produce different points, which is the
-- farmer-visible defect stated as a fact rather than as a claim.
-- ---------------------------------------------------------------------------
do
    local sys = builderSelf()
    local npc = {id = 5, name = "Ove", homePosition = {x = 0, y = 0, z = 0}, assignedField = nil}
    local first = NPCFavorSystem.generateFavorSteps(sys, {id = "fix_fence"}, npc)
    local firstX, firstZ = first[2].location.x, first[2].location.z

    local moved = false
    for _ = 1, 40 do
        local again = NPCFavorSystem.generateFavorSteps(sys, {id = "fix_fence"}, npc)
        if again[2].location.x ~= firstX or again[2].location.z ~= firstZ then moved = true; break end
    end
    T.ok("F221 witness: the materials pile re-rolls on a fresh build", moved)

    npc.assignedField = {id = 2, center = {x = 300, y = 0, z = 300}, size = 1}
    local withField = NPCFavorSystem.generateFavorSteps(sys, {id = "help_harvest"}, npc)
    T.eq("F221 witness: a field step follows whatever field the neighbour holds now", withField[1].location.x, 300)
    npc.assignedField = {id = 3, center = {x = -400, y = 0, z = 55}, size = 1}
    local afterRepick = NPCFavorSystem.generateFavorSteps(sys, {id = "help_harvest"}, npc)
    T.eq("F221 witness: and moves when the neighbour's field is re-picked", afterRepick[1].location.x, -400)
end

-- ---------------------------------------------------------------------------
-- REFERENCE CONTRACT for the unbuilt repair. Small explicit helpers so the
-- later production implementation can replace each one at its seam.
-- ---------------------------------------------------------------------------

-- A step row as both writers must carry it: named keys, never array slots.
local function stepRow(step)
    local has = step.location ~= nil
    return {
        completed = step.completed == true,
        locPresent = has,
        x = has and step.location.x or nil,
        y = has and step.location.y or nil,
        z = has and step.location.z or nil,
    }
end

local function saveSteps(steps)
    local rows = {}
    for i = 1, #steps do rows[i] = stepRow(steps[i]) end
    return {stepCount = #steps, steps = rows}
end

-- XML row keys are zero-based, matching the mod's own favour rows.
local function writeStepsXML(handle, prefix, saved)
    handle[prefix .. "#stepCount"] = saved.stepCount
    for i = 1, saved.stepCount do
        local key = string.format("%s.step(%d)", prefix, i - 1)
        local r = saved.steps[i]
        handle[key .. "#completed"] = r.completed
        handle[key .. "#locPresent"] = r.locPresent
        if r.locPresent then
            handle[key .. "#x"] = r.x
            handle[key .. "#y"] = r.y
            handle[key .. "#z"] = r.z
        end
    end
end

local function readStepsXML(handle, prefix)
    local n = handle[prefix .. "#stepCount"]
    if n == nil then return nil end
    local rows = {}
    for i = 1, n do
        local key = string.format("%s.step(%d)", prefix, i - 1)
        if handle[key .. "#completed"] == nil and handle[key .. "#locPresent"] == nil then
            return nil -- a declared count with a missing child is a broken set
        end
        local present = handle[key .. "#locPresent"] == true
        local x, y, z = handle[key .. "#x"], handle[key .. "#y"], handle[key .. "#z"]
        if present and (x == nil or y == nil or z == nil) then
            present = false -- a half-written coordinate is absent, never zero
            x, y, z = nil, nil, nil
        end
        rows[i] = {completed = handle[key .. "#completed"] == true,
                   locPresent = present, x = x, y = y, z = z}
    end
    return {stepCount = n, steps = rows}
end

-- The restore overlay. Replacement only: every location it sets is a new table.
local function overlay(steps, saved)
    if saved == nil or saved.stepCount ~= #steps then return false end
    for i = 1, #steps do
        local r = saved.steps[i]
        if r.locPresent then
            steps[i].location = {x = r.x, y = r.y, z = r.z}
        else
            steps[i].location = nil
        end
        steps[i].completed = r.completed
    end
    return true
end

local function percentFromFlags(steps)
    local done = 0
    for i = 1, #steps do if steps[i].completed then done = done + 1 end end
    if #steps == 0 then return 0 end
    return (done / #steps) * 100
end

-- ---------------------------------------------------------------------------
-- CONTRACT 1. Round trip: the destinations a farmer was promised come back.
-- ---------------------------------------------------------------------------
do
    local sys = builderSelf()
    local npc = {id = 9, name = "Sanna", homePosition = {x = 40, y = 3, z = 60},
                 assignedField = {id = 5, center = {x = 500, y = 0, z = 510}, size = 1}}
    local accepted = NPCFavorSystem.generateFavorSteps(sys, {id = "fix_fence"}, npc)
    accepted[1].completed = true
    local pileX, pileZ = accepted[2].location.x, accepted[2].location.z

    local handle = {}
    writeStepsXML(handle, "npcFavor.favors.favor(0)", saveSteps(accepted))
    T.eq("F221 contract: the first step row is written at index zero", handle["npcFavor.favors.favor(0).step(0)#locPresent"], true)
    T.eq("F221 contract: a three-step set ends at index two", handle["npcFavor.favors.favor(0).step(2)#locPresent"], true)
    T.eq("F221 contract: nothing is written at index three", handle["npcFavor.favors.favor(0).step(3)#locPresent"], nil)

    npc.assignedField = {id = 6, center = {x = -900, y = 0, z = 12}, size = 1}
    local rebuilt = NPCFavorSystem.generateFavorSteps(sys, {id = "fix_fence"}, npc)
    local saved = readStepsXML(handle, "npcFavor.favors.favor(0)")
    T.ok("F221 contract: the saved set is readable back", overlay(rebuilt, saved))
    T.near("F221 contract: the materials pile is where he left it, x", rebuilt[2].location.x, pileX, 0.0001)
    T.near("F221 contract: the materials pile is where he left it, z", rebuilt[2].location.z, pileZ, 0.0001)
    T.eq("F221 contract: his finished step is still finished", rebuilt[1].completed, true)
    T.near("F221 contract: percent is derived from the flags", percentFromFlags(rebuilt), 100 / 3, 0.0001)
end

-- ---------------------------------------------------------------------------
-- CONTRACT 2. Replacement, not mutation. The neighbour's own records survive,
-- and no two steps come back sharing one table.
-- ---------------------------------------------------------------------------
do
    local sys = builderSelf()
    local field = {id = 8, center = {x = 120, y = 0, z = 130}, size = 1}
    local npc = {id = 12, name = "Rolf", homePosition = {x = 7, y = 1, z = 8}, assignedField = field}
    local accepted = NPCFavorSystem.generateFavorSteps(sys, {id = "borrow_tractor"}, npc)
    local handle = {}
    writeStepsXML(handle, "row", saveSteps(accepted))

    local homeBefore = {x = npc.homePosition.x, y = npc.homePosition.y, z = npc.homePosition.z}
    local centerBefore = {x = field.center.x, y = field.center.y, z = field.center.z}
    local rebuilt = NPCFavorSystem.generateFavorSteps(sys, {id = "borrow_tractor"}, npc)
    T.ok("F221 contract: the rebuild still shares one object before the overlay", rawequal(rebuilt[1].location, rebuilt[3].location))
    overlay(rebuilt, readStepsXML(handle, "row"))

    T.ok("F221 contract: after the overlay steps 1 and 3 are independent tables", not rawequal(rebuilt[1].location, rebuilt[3].location))
    T.ok("F221 contract: no restored location is the neighbour's home record", not rawequal(rebuilt[1].location, npc.homePosition))
    T.ok("F221 contract: no restored location is the field centre record", not rawequal(rebuilt[2].location, field.center))
    T.eq("F221 contract: the neighbour's home is unmoved, x", npc.homePosition.x, homeBefore.x)
    T.eq("F221 contract: the neighbour's home is unmoved, z", npc.homePosition.z, homeBefore.z)
    T.eq("F221 contract: the field centre is unmoved, x", field.center.x, centerBefore.x)
    T.eq("F221 contract: the field centre is unmoved, z", field.center.z, centerBefore.z)

    rebuilt[1].location.x = -1
    T.ok("F221 contract: and writing one restored step no longer moves its twin", rebuilt[3].location.x ~= -1)
end

-- ---------------------------------------------------------------------------
-- CONTRACT 3. The missing neighbour, which is the case the placeholder rule
-- exists for. A non-nil placeholder keeps the saved set; a nil one loses it.
-- ---------------------------------------------------------------------------
do
    local sys = builderSelf()
    local npc = {id = 21, name = "Vera", homePosition = {x = 60, y = 2, z = 70}, assignedField = nil}
    local accepted = NPCFavorSystem.generateFavorSteps(sys, {id = "fix_fence"}, npc)
    local savedX = accepted[3].location.x
    local handle = {}
    writeStepsXML(handle, "row", saveSteps(accepted))
    local saved = readStepsXML(handle, "row")

    local goodStub = {id = 21, name = "Vera", homePosition = {x = 0, y = 0, z = 0}, assignedField = nil}
    local goodRebuild = NPCFavorSystem.generateFavorSteps(sys, {id = "fix_fence"}, goodStub)
    T.eq("F221 contract: a non-nil placeholder rebuilds the right number of steps", #goodRebuild, saved.stepCount)
    T.ok("F221 contract: so the saved set applies", overlay(goodRebuild, saved))
    T.near("F221 contract: and the fence point survives the neighbour's absence", goodRebuild[3].location.x, savedX, 0.0001)
    T.ok("F221 contract: the placeholder table is not written onto anything live", goodStub.homePosition.x == 0)

    local nilStub = {id = 21, name = "Vera", homePosition = nil, assignedField = nil}
    local badRebuild = NPCFavorSystem.generateFavorSteps(sys, {id = "fix_fence"}, nilStub)
    T.eq("F221 contract: a nil placeholder rebuilds one step", #badRebuild, 1)
    T.ok("F221 contract: so the saved set cannot apply and the destinations are lost", not overlay(badRebuild, saved))
end

-- ---------------------------------------------------------------------------
-- CONTRACT 4. Partial and absent rows each take the stated answer.
-- ---------------------------------------------------------------------------
do
    local sys = builderSelf()
    local npc = {id = 30, name = "Ida", homePosition = {x = 1, y = 0, z = 2}, assignedField = nil}
    local accepted = NPCFavorSystem.generateFavorSteps(sys, {id = "fix_fence"}, npc)

    T.eq("F221 contract: a save with no step block reads as absent", readStepsXML({}, "row"), nil)

    local torn = {}
    writeStepsXML(torn, "row", saveSteps(accepted))
    torn["row.step(1)#completed"] = nil
    torn["row.step(1)#locPresent"] = nil
    T.eq("F221 contract: a declared count with a missing child reads as absent", readStepsXML(torn, "row"), nil)

    local half = {}
    writeStepsXML(half, "row", saveSteps(accepted))
    half["row.step(1)#z"] = nil
    local halfRead = readStepsXML(half, "row")
    T.eq("F221 contract: a half-written coordinate is absent", halfRead.steps[2].locPresent, false)
    local rebuilt = NPCFavorSystem.generateFavorSteps(sys, {id = "fix_fence"}, npc)
    overlay(rebuilt, halfRead)
    T.eq("F221 contract: and restores as nil, never as the origin of the map", rebuilt[2].location, nil)

    local short = {}
    writeStepsXML(short, "row", saveSteps(accepted))
    short["row#stepCount"] = 2
    local mismatch = NPCFavorSystem.generateFavorSteps(sys, {id = "fix_fence"}, npc)
    T.ok("F221 contract: a count mismatch falls through to today's rebuild", not overlay(mismatch, readStepsXML(short, "row")))

    local dialogStep = {{id = 1, description = "Talk", completed = false, location = nil}}
    local dh = {}
    writeStepsXML(dh, "row", saveSteps(dialogStep))
    T.eq("F221 contract: a step that never had a location saves as absent", dh["row.step(0)#locPresent"], false)
    local dr = readStepsXML(dh, "row")
    local dialogRebuild = {{id = 1, description = "Talk", completed = false, location = {x = 9, y = 9, z = 9}}}
    overlay(dialogRebuild, dr)
    T.eq("F221 contract: and restores as absent rather than inventing a point", dialogRebuild[1].location, nil)
end

-- ---------------------------------------------------------------------------
-- CONTRACT 5. A saved y is carried verbatim, including zero, and completion is
-- compared in XZ only. This is why nothing on the restore path re-samples y.
-- ---------------------------------------------------------------------------
do
    local sys = builderSelf()
    local npc = {id = 40, name = "Tor", homePosition = {x = 10, y = 4, z = 10},
                 assignedField = {id = 9, center = {x = 200, y = 0, z = 220}, size = 1}}
    local accepted = NPCFavorSystem.generateFavorSteps(sys, {id = "help_harvest"}, npc)
    T.eq("F221 contract: a field centre legitimately carries y zero", accepted[1].location.y, 0)

    local handle = {}
    writeStepsXML(handle, "row", saveSteps(accepted))
    T.eq("F221 contract: y zero is written, not dropped as falsy", handle["row.step(0)#y"], 0)
    local rebuilt = NPCFavorSystem.generateFavorSteps(sys, {id = "help_harvest"}, npc)
    overlay(rebuilt, readStepsXML(handle, "row"))
    T.eq("F221 contract: and comes back as zero rather than re-sampled", rebuilt[1].location.y, 0)

    local player = {x = 200, z = 220}
    local flat = VectorHelper.distance2D(player.x, player.z, rebuilt[1].location.x, rebuilt[1].location.z)
    T.near("F221 contract: standing on the point is zero metres in XZ", flat, 0, 0.0001)
    T.ok("F221 contract: which is why a wrong y can never hold the step open", flat < 30)
end

-- ---------------------------------------------------------------------------
-- CONTRACT 6. A legacy save behaves exactly as it does today, and the schema
-- round-trips a second time without drift.
-- ---------------------------------------------------------------------------
do
    local sys = builderSelf()
    local npc = {id = 50, name = "Elin", homePosition = {x = 3, y = 0, z = 4}, assignedField = nil}
    local legacy = NPCFavorSystem.generateFavorSteps(sys, {id = "water_animals"}, npc)
    T.ok("F221 contract: a legacy row has no step block to read", readStepsXML({}, "legacyRow") == nil)
    T.ok("F221 contract: so it takes today's rebuild untouched", not overlay(legacy, readStepsXML({}, "legacyRow")))
    T.eq("F221 contract: with today's step count", #legacy, 2)

    local first = {}
    writeStepsXML(first, "row", saveSteps(legacy))
    local readBack = readStepsXML(first, "row")
    local again = NPCFavorSystem.generateFavorSteps(sys, {id = "water_animals"}, npc)
    overlay(again, readBack)
    local second = {}
    writeStepsXML(second, "row", saveSteps(again))
    T.eq("F221 contract: a second save writes the same x", second["row.step(1)#x"], first["row.step(1)#x"])
    T.eq("F221 contract: the same z", second["row.step(1)#z"], first["row.step(1)#z"])
    T.eq("F221 contract: and the same count", second["row#stepCount"], first["row#stepCount"])
end

-- =====================================================================
-- REAL-SOURCE SECTION (Fred, 2026-09-15): the built repair through the
-- production seams. exportFavorRecord, NPCSystem.writeFavorRecordXML and
-- readFavorRecordXML, NPCFavorRecovery.decodeSavedSteps, the restore
-- assembly in buildRestoredRecord (via restoreFavor, direct path), and the
-- StateLedger serializeState / deserializeState round trip.
-- =====================================================================

local FAVOR_TYPES = {
    {id = "fix_fence", name = "Fix fence", description = "Fence", difficulty = 1, category = "repair",
        requirements = {}, reward = {relationship = 5, money = 100, xp = 0}, penalty = {relationship = -3}},
    {id = "borrow_tractor", name = "Borrow tractor", description = "Tractor", difficulty = 1, category = "equipment",
        requirements = {}, reward = {relationship = 5, money = 100, xp = 0}, penalty = {relationship = -3}},
    {id = "help_harvest", name = "Help harvest", description = "Harvest", difficulty = 1, category = "fieldwork",
        requirements = {}, reward = {relationship = 5, money = 100, xp = 0}, penalty = {relationship = -3}},
    {id = "watch_property", name = "Watch property", description = "Watch", difficulty = 1, category = "misc",
        requirements = {}, reward = {relationship = 5, money = 100, xp = 0}, penalty = {relationship = -3}},
}

-- A real favor system with the REAL step builder (not stubbed).
local function realSystem(npcs)
    local sys = NPCFavorSystem.new({activeNPCs = npcs, settings = {enableFavors = false, debugMode = false},
        relationshipManager = {updateRelationship = function() end},
        playerPosition = {x = 0, y = 0, z = 0}, playerPositionValid = true})
    sys.favorTypes = FAVOR_TYPES
    sys.findNearestSellPoint = function(_, x, z) return {x = x + 100, y = 0, z = z + 100, name = "Co-op"} end
    sys:installEmptyFavorSnapshot()
    return sys
end

local function neighbour(home, field)
    return {id = 11, name = "NPC11", homePosition = home, assignedField = field, isActive = true,
        favorCooldown = 0, relationship = 60, personality = "friendly", position = {x = 0, y = 0, z = 0}, rotation = {y = 0}}
end

-- An accepted live row built with the real builder against this system's NPC.
local function acceptedRow(sys, typeId, ownerFarmId)
    local npc = sys.npcSystem.activeNPCs[1]
    local favorType = sys:getFavorTypeById(typeId)
    local row = {id = sys:allocateFavorId(), npcId = npc.id, npcName = npc.name, type = typeId, personRefKind = "durable",
        description = favorType.description, status = "active", progress = 0, timeRemaining = 60000,
        expirationGameTime = 61000, ownerFarmId = ownerFarmId, ownerFarmIdPresent = ownerFarmId ~= nil,
        rewardPaid = false, rewardPaidPresent = true, repaymentCollected = false, repaymentCollectedPresent = true,
        reward = favorType.reward, penalty = favorType.penalty, taskData = {},
        steps = sys:generateFavorSteps(favorType, npc), recordRevision = 0}
    row.totalSteps = #row.steps
    row.currentStep = 1
    table.insert(sys.activeFavors, row)
    return row
end

local function newXmlMock()
    local store = {}
    local m = {store = store}
    m.setInt = function(_, k, v) store[k] = v end
    m.setFloat = function(_, k, v) store[k] = v end
    m.setString = function(_, k, v) store[k] = v end
    m.setBool = function(_, k, v) store[k] = v end
    local function get(_, k, default) if store[k] ~= nil then return store[k] end return default end
    m.getInt, m.getFloat, m.getString, m.getBool = get, get, get, get
    m.hasProperty = function(_, k) return store[k] ~= nil end
    return m
end

-- (R1) Export carries a named-key step row per step, by value, and the XML
-- writer puts the first child at .step(0). y zero is written, not dropped.
do
    setLiveFarms({1, 3})
    local sys = realSystem({neighbour({x = 40, y = 3, z = 60}, {id = 5, center = {x = 500, y = 0, z = 510}, size = 1})})
    local row = acceptedRow(sys, "help_harvest", 1)
    row.steps[1].completed = true
    local flat = sys:exportFavorRecord(row)
    T.eq("R1 export: stepCount equals the live list", flat.stepCount, 2)
    T.eq("R1 export: field step x copied", flat.steps[1].x, 500)
    T.eq("R1 export: field step y zero copied verbatim", flat.steps[1].y, 0)
    T.eq("R1 export: completed flag copied", flat.steps[1].completed, true)
    T.eq("R1 export: home step locPresent", flat.steps[2].locPresent, true)
    T.ok("R1 export: the exported row is not the live location table", not rawequal(flat.steps[1], row.steps[1].location))
    flat.steps[1].x = -1
    T.eq("R1 export: mutating the export leaves the live field centre alone", row.steps[1].location.x, 500)

    local xml = newXmlMock()
    NPCSystem.writeFavorRecordXML(xml, "npcFavor.favors.favor(0)", flat)
    T.eq("R1 xml: stepCount attribute", xml.store["npcFavor.favors.favor(0)#stepCount"], 2)
    T.eq("R1 xml: first child at index zero", xml.store["npcFavor.favors.favor(0).step(0)#locPresent"], true)
    T.eq("R1 xml: y zero written", xml.store["npcFavor.favors.favor(0).step(0)#y"], 0)
    T.eq("R1 xml: last child at index one", xml.store["npcFavor.favors.favor(0).step(1)#completed"], false)
    T.eq("R1 xml: nothing at index two", xml.store["npcFavor.favors.favor(0).step(2)#locPresent"], nil)
    T.eq("R1 xml: schema marker stays 1", xml.store["npcFavor.favors.favor(0)#f148Schema"], 1)

    local back = NPCSystem.readFavorRecordXML(xml, "npcFavor.favors.favor(0)")
    T.eq("R1 read: count round-trips", back.stepCount, 2)
    T.eq("R1 read: x round-trips", back.steps[1].x, -1)
    T.eq("R1 read: y zero round-trips", back.steps[1].y, 0)
    T.eq("R1 read: completed round-trips", back.steps[1].completed, true)
    local decoded = NPCFavorRecovery.decodeSavedSteps(back)
    T.ok("R1 decode: the set is usable", decoded ~= nil and decoded.stepCount == 2)
end

-- (R2) Round trip through restore: the destinations come back where they
-- were, by replacement, with the neighbour's records untouched and no two
-- steps sharing one table. Percent is derived from the saved flags.
do
    setLiveFarms({1, 3})
    local field = {id = 5, center = {x = 500, y = 0, z = 510}, size = 1}
    local npc = neighbour({x = 40, y = 3, z = 60}, field)
    local sys = realSystem({npc})
    local row = acceptedRow(sys, "borrow_tractor", 1)
    row.steps[1].completed = true
    T.ok("R2 setup: the live tractor list aliases home at 1 and 3", rawequal(row.steps[1].location, row.steps[3].location))
    local savedFieldX = row.steps[2].location.x
    local flat = sys:exportFavorRecord(row)
    flat.progress = 0   -- a stale saved percent must lose to the flags

    -- Between sessions the neighbour's field is re-picked and the home moves.
    field.center.x = -900
    npc.homePosition.x = 41
    local sys2 = realSystem({npc})
    local restored, where = sys2:restoreFavor(flat)
    T.eq("R2 restore: enters the active collection", where, "active")
    T.eq("R2 restore: three steps", #restored.steps, 3)
    T.eq("R2 restore: field step is where it was saved", restored.steps[2].location.x, savedFieldX)
    T.eq("R2 restore: home step is the accept-time home, not today's", restored.steps[1].location.x, 40)
    T.eq("R2 restore: finished step still finished", restored.steps[1].completed, true)
    T.eq("R2 restore: unfinished step still open", restored.steps[2].completed, false)
    T.near("R2 restore: percent from flags, not the stale saved percent", restored.progress, 100 / 3, 0.0001)
    T.eq("R2 restore: currentStep is the first open step", restored.currentStep, 2)
    T.ok("R2 restore: steps 1 and 3 are independent tables", not rawequal(restored.steps[1].location, restored.steps[3].location))
    T.ok("R2 restore: no restored location is the neighbour's home record", not rawequal(restored.steps[1].location, npc.homePosition))
    T.ok("R2 restore: no restored location is the field centre record", not rawequal(restored.steps[2].location, field.center))
    T.eq("R2 restore: the neighbour's home is unmoved by the restore", npc.homePosition.x, 41)
    T.eq("R2 restore: the field centre is unmoved by the restore", field.center.x, -900)
    restored.steps[1].location.x = -1
    T.ok("R2 restore: writing one restored step does not move its twin", restored.steps[3].location.x ~= -1)

    -- A second save writes the same destinations: no drift.
    local again = sys2:exportFavorRecord(restored)
    T.eq("R2 second save: same field x", again.steps[2].x, flat.steps[2].x)
    T.eq("R2 second save: same field z", again.steps[2].z, flat.steps[2].z)
    T.eq("R2 second save: same count", again.stepCount, flat.stepCount)
    T.eq("R2 second save: flag survives", again.steps[1].completed, true)
end

-- (R3) The missing neighbour keeps every saved destination (call-local
-- placeholder home), and a legacy row with a missing neighbour is exactly
-- today's one-step fallback.
do
    setLiveFarms({1, 3})
    local npc = neighbour({x = 60, y = 2, z = 70}, nil)
    local sys = realSystem({npc})
    local row = acceptedRow(sys, "fix_fence", 1)
    local fenceX, fenceZ = row.steps[3].location.x, row.steps[3].location.z
    local flat = sys:exportFavorRecord(row)

    local gone = realSystem({})
    local restored, where = gone:restoreFavor(flat)
    -- RSF-F357: work whose durable person is absent pauses as neighbour_unavailable; its destinations are kept.
    T.eq("R3 missing NPC: pauses as neighbour_unavailable (RSF-F357), owner is a live farm", where, "recovery")
    T.eq("R3 missing NPC: the reason is neighbour_unavailable", restored.recoveryReason, NPCFavorRecovery.REASON_NEIGHBOUR_UNAVAILABLE)
T.eq("R3 missing NPC: neighbour reported unresolved", restored.npcResolved, false)
    T.eq("R3 missing NPC: full three-step list, not the one-step collapse", #restored.steps, 3)
    T.near("R3 missing NPC: fence point survives, x", restored.steps[3].location.x, fenceX, 0.0001)
    T.near("R3 missing NPC: fence point survives, z", restored.steps[3].location.z, fenceZ, 0.0001)
    T.eq("R3 missing NPC: home step is the saved home, not the placeholder", restored.steps[1].location.x, 60)

    -- A present neighbour with no home: the placeholder is never written onto it.
    local homeless = neighbour(nil, nil)
    local sys3 = realSystem({homeless})
    local r3 = sys3:restoreFavor(flat)
    T.eq("R3 homeless NPC: saved set applies", #r3.steps, 3)
    T.eq("R3 homeless NPC: placeholder not written onto the live neighbour", homeless.homePosition, nil)

    -- Legacy shape: no step set at all, neighbour gone. Today's behaviour.
    local legacy = sys:exportFavorRecord(row)
    legacy.stepCount, legacy.steps = nil, nil
    local gone2 = realSystem({})
    local r2 = gone2:restoreFavor(legacy)
    T.eq("R3 legacy + missing NPC: today's one-step fallback", #r2.steps, 1)
    T.eq("R3 legacy + missing NPC: with no location", r2.steps[1].location, nil)
end

-- (R4) Count mismatch and legacy rows fall through to today's regenerate and
-- positional percent mapping, aliasing and all.
do
    setLiveFarms({1, 3})
    local npc = neighbour({x = 1, y = 0, z = 2}, nil)
    local sys = realSystem({npc})
    local row = acceptedRow(sys, "fix_fence", 1)
    local flat = sys:exportFavorRecord(row)
    flat.stepCount = 2   -- a type-definition change between versions
    flat.progress = 67
    local r = sys:restoreFavor(flat)
    T.eq("R4 mismatch: regenerated three steps", #r.steps, 3)
    T.eq("R4 mismatch: percent mapping marks two done", r.steps[2].completed, true)
    T.eq("R4 mismatch: and leaves the third open", r.steps[3].completed, false)
    T.eq("R4 mismatch: saved percent kept", r.progress, 67)
    T.ok("R4 mismatch: today's aliasing untouched (home step is the home record)", rawequal(r.steps[1].location, npc.homePosition))

    local legacy = sys:exportFavorRecord(row)
    legacy.stepCount, legacy.steps = nil, nil
    legacy.progress = 100
    local l = sys:restoreFavor(legacy)
    T.eq("R4 legacy: percent mapping completes all three", l.steps[3].completed, true)
    T.eq("R4 legacy: saved percent kept", l.progress, 100)
    T.ok("R4 legacy: today's aliasing untouched", rawequal(l.steps[1].location, npc.homePosition))
end

-- (R5) Partial rows through the real XML reader take the stated answers.
do
    setLiveFarms({1, 3})
    local npc = neighbour({x = 1, y = 0, z = 2}, nil)
    local sys = realSystem({npc})
    local row = acceptedRow(sys, "fix_fence", 1)
    local flat = sys:exportFavorRecord(row)

    local torn = newXmlMock()
    NPCSystem.writeFavorRecordXML(torn, "row", flat)
    torn.store["row.step(1)#completed"] = nil
    torn.store["row.step(1)#locPresent"] = nil
    torn.store["row.step(1)#x"] = nil
    torn.store["row.step(1)#y"] = nil
    torn.store["row.step(1)#z"] = nil
    local tornFlat = NPCSystem.readFavorRecordXML(torn, "row")
    T.eq("R5 torn: declared count with a missing child decodes as absent", NPCFavorRecovery.decodeSavedSteps(tornFlat), nil)
    local tr = sys:restoreFavor(tornFlat)
    T.ok("R5 torn: so the row regenerates", rawequal(tr.steps[1].location, npc.homePosition))

    local half = newXmlMock()
    NPCSystem.writeFavorRecordXML(half, "row", flat)
    half.store["row.step(1)#z"] = nil
    local halfFlat = NPCSystem.readFavorRecordXML(half, "row")
    local halfDecoded = NPCFavorRecovery.decodeSavedSteps(halfFlat)
    T.eq("R5 half: the set is still usable", halfDecoded.stepCount, 3)
    T.eq("R5 half: the half-written step is absent", halfDecoded.steps[2].locPresent, false)
    local hr = sys:restoreFavor(halfFlat)
    T.eq("R5 half: restores as nil, never the map origin", hr.steps[2].location, nil)
    T.eq("R5 half: the other steps keep their destinations", hr.steps[3].location.x, flat.steps[3].x)

    local dialog = newXmlMock()
    local wrow = acceptedRow(sys, "watch_property", 1)
    wrow.steps[2].location = nil   -- a step that genuinely had no location
    NPCSystem.writeFavorRecordXML(dialog, "row", sys:exportFavorRecord(wrow))
    T.eq("R5 absent: saved as locPresent false", dialog.store["row.step(1)#locPresent"], false)
    T.eq("R5 absent: no coordinate written", dialog.store["row.step(1)#x"], nil)
    local dr = sys:restoreFavor(NPCSystem.readFavorRecordXML(dialog, "row"))
    T.eq("R5 absent: restores as nil rather than inventing a point", dr.steps[2].location, nil)
    T.eq("R5 absent: the dialog flag still comes from the builder", dr.steps[2].isDialogStep, true)
end

-- (R6) A paused recovery row carries its destinations through the recovery
-- collection too.
do
    setLiveFarms({1, 2, 3})
    local npc = neighbour({x = 9, y = 1, z = 8}, nil)
    local sys = realSystem({npc})
    local row = acceptedRow(sys, "fix_fence", 2)
    local pileX = row.steps[2].location.x
    setLiveFarms({1, 3})
    sys:onFarmDeleted(2)
    T.eq("R6 setup: the row is orphaned", row.status, NPCFavorRecovery.STATUS_PAUSED)
    local flat = sys:exportFavorRecord(row)
    T.eq("R6 export: a recovery row exports its steps", flat.stepCount, 3)

    local sys2 = realSystem({npc})
    local r, where = sys2:restoreFavor(flat)
    T.eq("R6 restore: lands in recovery", where, "recovery")
    T.eq("R6 restore: keeps its reason", r.recoveryReason, NPCFavorRecovery.REASON_OWNER_FARM_DELETED)
    T.near("R6 restore: keeps the pile where it was", r.steps[2].location.x, pileX, 0.0001)
    T.ok("R6 restore: no alias to the neighbour's home", not rawequal(r.steps[1].location, npc.homePosition))
end

-- (R7) The StateLedger path: serializeState carries the rows and a fresh
-- host restores the same destinations through deserializeState.
do
    setLiveFarms({1, 3})
    local function bareHost(npc, ready)
        local fav = realSystem({npc})
        fav._favorLoadState = NPCFavorRecovery.LOAD_WAITING
        fav._favorLoadFailOrigin = nil
        fav.activeFavors, fav.recoveryFavors = {}, {}
        npc.uniqueId = "npc-" .. npc.id
        local host = setmetatable({
            activeNPCs = {npc}, settings = {debugMode = false, maxNPCs = 1}, favorSystem = fav,
            relationshipManager = {npcRelationships = {}}, isInitialized = true, isServer = true, npcCount = 1, syncDirty = false,
        }, {__index = NPCSystem})
        -- RSF-F357: the host owns its people. The saving host holds the
        -- neighbour as a live durable person; the loading host starts WAITING.
        host.people = NPCPersonRoster.new(host)
        if ready then
            npc.personKind, npc.origin, npc.townCandidate, npc.live = "durable", "town", true, true
            host.people:reserveId(npc.id)
            host.people:addPerson(npc)
            host.people:markReady()
        end
        fav.npcSystem = host
        return host, fav
    end
    local npcA = neighbour({x = 12, y = 0, z = 13}, nil)
    local hostA, favA = bareHost(npcA, true)
    favA:installEmptyFavorSnapshot()
    local row = acceptedRow(favA, "fix_fence", 1)
    row.steps[1].completed = true
    local pileX, pileZ = row.steps[2].location.x, row.steps[2].location.z
    local block = hostA:serializeState()
    T.eq("R7 ledger: one favor row serialized", #block.favors, 1)
    T.eq("R7 ledger: the row carries its step count", block.favors[1].stepCount, 3)
    T.eq("R7 ledger: named keys, not slots", block.favors[1].steps[2].x, pileX)
    T.eq("R7 ledger: recoveryFavors block present and empty", #block.recoveryFavors, 0)

    local npcB = neighbour({x = 99, y = 0, z = 99}, nil)   -- the neighbour moved house
    local hostB, favB = bareHost(npcB)
    hostB:deserializeState(block)
    T.eq("R7 ledger: load is READY", favB:getFavorLoadState(), NPCFavorRecovery.LOAD_READY)
    T.eq("R7 ledger: one active favor", #favB.activeFavors, 1)
    local got = favB.activeFavors[1]
    T.near("R7 ledger: pile x survives", got.steps[2].location.x, pileX, 0.0001)
    T.near("R7 ledger: pile z survives", got.steps[2].location.z, pileZ, 0.0001)
    T.eq("R7 ledger: home step is the accept-time home", got.steps[1].location.x, 12)
    T.eq("R7 ledger: flag survives", got.steps[1].completed, true)
    -- The NPC block restores the neighbour's saved home as it always has; that
    -- is today's NPC persistence, not this repair. What F221 owns: the step
    -- location is its own table, not the neighbour's restored home record.
    -- RSF-F357: the saved person is restored by durable number into the
    -- roster before any town exists; the hand-made npcB is never touched.
    local restoredPerson = hostB.people:getPerson(npcA.id)
    T.eq("R7 ledger: the NPC block restores the saved home as before", restoredPerson.homePosition.x, 12)
    T.ok("R7 ledger: the home step is not the neighbour's home record", not rawequal(got.steps[1].location, restoredPerson.homePosition))
T.eq("R7 ledger: delivered block not mutated by restore", block.favors[1].steps[2].x, pileX)
end

-- =====================================================================
-- REVIEW FIXES (Bob, 2026-09-15, cold review of #109): the placeholder home
-- only counts when the saved set can apply, and the XML reader is bounded
-- by the children that exist, not by the declared count.
-- =====================================================================

-- (R8) BLOCKER case: a row saved from the one-step nil-home shape, neighbour
-- still missing on reload. The placeholder must not turn the map origin into
-- durable destinations; the row rebuilds as today's one-step nil list and
-- re-exports as locPresent false.
do
    setLiveFarms({1, 3})
    local gone = realSystem({})
    local oneStep = {
        f148Schema = 1, favorId = 77, npcId = 11, npcName = "NPC11", type = "fix_fence", description = "Fence",
        status = "active", progress = 0, timeRemainingPresent = true, timeRemaining = 60000,
        ownerFarmIdPresent = true, ownerFarmId = 1, rewardPaidPresent = true, rewardPaid = false,
        stepCount = 1, steps = {{completed = false, locPresent = false}},
    }
    local r = gone:restoreFavor(oneStep)
    T.eq("R8 mismatch + missing NPC: today's one-step list, not the placeholder's three", #r.steps, 1)
    T.eq("R8 mismatch + missing NPC: that step has no location", r.steps[1].location, nil)
    local again = gone:exportFavorRecord(r)
    T.eq("R8 mismatch + missing NPC: re-export count is one", again.stepCount, 1)
    T.eq("R8 mismatch + missing NPC: re-export carries no invented coordinate", again.steps[1].locPresent, false)
    T.eq("R8 mismatch + missing NPC: no x written", again.steps[1].x, nil)

    -- Same with a present but homeless neighbour and a changed-definition count.
    local homeless = neighbour(nil, nil)
    local sys2 = realSystem({homeless})
    local twoStep = {}
    for k, v in pairs(oneStep) do twoStep[k] = v end
    twoStep.stepCount = 2
    twoStep.steps = {{completed = true, locPresent = true, x = 5, y = 0, z = 5}, {completed = false, locPresent = false}}
    local r2 = sys2:restoreFavor(twoStep)
    T.eq("R8 homeless + count mismatch: one-step fallback", #r2.steps, 1)
    T.eq("R8 homeless + count mismatch: nil location", r2.steps[1].location, nil)
    T.eq("R8 homeless + count mismatch: placeholder never written onto the neighbour", homeless.homePosition, nil)

    -- The matching case still works after the fix.
    local npc = neighbour({x = 60, y = 2, z = 70}, nil)
    local sys = realSystem({npc})
    local row = acceptedRow(sys, "fix_fence", 1)
    local fenceX = row.steps[3].location.x
    local flat = sys:exportFavorRecord(row)
    local r3 = realSystem({}):restoreFavor(flat)
    T.eq("R8 matching set + missing NPC: still three steps", #r3.steps, 3)
    T.near("R8 matching set + missing NPC: fence point still survives", r3.steps[3].location.x, fenceX, 0.0001)
end

-- (R9) MAJOR case: a corrupt or edited #stepCount must not spin the reader.
do
    local xml = newXmlMock()
    local probes = 0
    local baseHas = xml.hasProperty
    xml.hasProperty = function(self, k) probes = probes + 1 return baseHas(self, k) end
    xml.store["row#f148Schema"] = 1
    xml.store["row#npcId"] = 11
    xml.store["row#type"] = "fix_fence"
    xml.store["row#stepCount"] = 2000000000
    xml.store["row.step(0)#completed"] = false
    xml.store["row.step(0)#locPresent"] = false
    local flat = NPCSystem.readFavorRecordXML(xml, "row")
    T.eq("R9 huge count: the declared count is read", flat.stepCount, 2000000000)
    T.eq("R9 huge count: one child read", flat.steps[1] ~= nil, true)
    T.eq("R9 huge count: reading stopped at the first missing child", flat.steps[2], nil)
    T.ok("R9 huge count: the reader did not walk the declared count", probes < 100)
    T.eq("R9 huge count: decode treats the set as absent", NPCFavorRecovery.decodeSavedSteps(flat), nil)
end
