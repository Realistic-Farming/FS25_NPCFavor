-- NPC Favor #137: a multiplayer client builds its list of neighbours in
-- talking range.
--
-- Entry point under test: the REAL production method NPCSystem:update(dt),
-- called with self.isServer = false (a multiplayer client / dedicated-server
-- player). The object under test is NOT built through NPCSystem.new() (that
-- constructor instantiates ~15 other real classes, e.g. NPCEntity, NPCAI,
-- NPCScheduler, which this defect does not touch); instead a bare table is
-- given the real NPCSystem_mt metatable, so every method call below (update,
-- checkPlayerProximity, updateNPCs) runs production's own code, not a copy of
-- it. Only entityManager / interactionUI / favorHUD / aiSystem / scheduler /
-- favorSystem / relationshipManager / contractorBridge are stubs (none of
-- NPCSystem's own logic lives in them for this defect); checkPlayerProximity
-- and the update's client/server branching are the real src/NPCSystem.lua
-- code, unmodified.
--
-- main.lua was probed and CANNOT be loaded in this harness: loading it dies
-- immediately on `local modItem = g_modManager:getModByName(modName)` (line
-- 68, before the function under test is even reached) because prelude.lua
-- does not stub g_modManager, and main.lua's own `source(...)` boot (loading
-- ~30 further files) is not modelled either. The existing NPC-204 tests note
-- the same thing ("the bench's boot does not run main.lua"); this is not a
-- gap introduced here. Per the brief's fallback, T7 therefore asserts
-- directly on npcSystem.nearbyNPCs -- the one field both main.lua's per-frame
-- action-active check (main.lua:700-715) and its NPC_INTERACT callback
-- (main.lua:410-434) read -- rather than driving main.lua.
--
-- Modelled (no production equivalent available in this harness):
--   * entityManager, interactionUI, favorHUD, aiSystem, scheduler,
--     favorSystem, relationshipManager, contractorBridge: no-op stubs that
--     record nothing except entityManager's call list (used to confirm the
--     fix's loop still calls updateNPCEntity once per npc in activeNPCs).
--   * g_localPlayer:getPosition() -- the first of updatePlayerPosition's four
--     real fallback methods; a stub player standing in for a real g_player.
--
-- dt is passed in milliseconds, matching what FS25 passes to :update (the
-- real method divides by 1000 internally); the value chosen (100) is far
-- below every server-only timer threshold so none of those fire.
--!load: src/NPCSystem.lua

local function setPlayerPos(x, y, z)
    g_localPlayer = { getPosition = function() return x, y, z end }
    g_currentMission.player = nil
    g_currentMission.controlledVehicle = nil
end

local function clearPlayerPos()
    g_localPlayer = nil
    g_currentMission.player = nil
    g_currentMission.controlledVehicle = nil
end

local function makeEntityManager()
    local calls = {}
    return {
        calls = calls,
        updateNPCEntity = function(_self, npc, _dt)
            calls[#calls + 1] = npc
        end,
    }
end

local function makeInteractionUI()
    return {
        update = function(_self, _dt) end,
        showInteractionHint = function(_self, _npc, _dist) end,
        hideInteractionHint = function(_self) end,
        interactionHintNPC = nil,
    }
end

local function makeFavorHUD()
    return { update = function(_self, _dt) end }
end

local function makeNPC(id, x, z, isSleeping)
    return {
        id = id,
        name = "NPC" .. tostring(id),
        isActive = true,
        isSleeping = isSleeping or false,
        position = { x = x, y = 0, z = z },
        canInteract = false,
        interactionDistance = nil,
        favorCooldown = 0,
    }
end

-- Builds a client-side NPCSystem through the REAL metatable (NPCSystem_mt),
-- not NPCSystem.new(). Only the fields NPCSystem:update's client branch and
-- checkPlayerProximity read are set.
local function makeClientSys(activeNPCs)
    local sys = setmetatable({}, NPCSystem_mt)
    sys.settings = { enabled = true, debugMode = false, maxNPCs = 10 }
    sys.isInitialized = true
    sys.isServer = false
    sys.updateCounter = 0
    sys.people = nil
    sys.activeNPCs = activeNPCs
    sys.entityManager = makeEntityManager()
    sys.interactionUI = makeInteractionUI()
    sys.favorHUD = makeFavorHUD()
    sys.playerPosition = { x = 0, y = 0, z = 0 }
    sys.playerPositionValid = false
    sys.nearbyNPCs = {} -- mirrors NPCSystem.new's own default (line ~276)
    sys.settingsPanel = nil
    sys.tickPersonalWork = nil
    return sys
end

-- Builds a server-side NPCSystem the same way, with the extra fields
-- NPCSystem:update's server branch touches unconditionally (contractorBridge,
-- scheduler, favorSystem, relationshipManager) or that must not trip a timer
-- during a single update (relocateTimer/SYNC_INTERVAL/etc, all far above
-- threshold or left at their natural nil-defaults).
local function makeServerSys(activeNPCs)
    local sys = setmetatable({}, NPCSystem_mt)
    sys.settings = { enabled = true, debugMode = false, maxNPCs = 10 }
    sys.isInitialized = true
    sys.isServer = true
    sys.updateCounter = 0
    sys.people = nil
    sys.activeNPCs = activeNPCs
    sys.npcCount = #activeNPCs
    sys.entityManager = makeEntityManager()
    sys.interactionUI = makeInteractionUI()
    sys.favorHUD = makeFavorHUD()
    sys.aiSystem = { updateNPCState = function(_self, _npc, _dt) end }
    sys.scheduler = {
        update = function(_self, _dt) end,
        getCurrentHour = function(_self) return 0 end,
    }
    sys.favorSystem = { update = function(_self, _dt) end }
    sys.relationshipManager = { update = function(_self, _dt) end }
    sys.contractorBridge = { update = function(_self, _dt) end }
    sys.eventScheduler = nil
    sys.relocateTimer = 0
    sys.RELOCATE_INTERVAL = 1e9
    sys.syncTimer = 0
    sys.SYNC_INTERVAL = 1e9
    sys.syncDirty = false
    sys.playerPosition = { x = 0, y = 0, z = 0 }
    sys.playerPositionValid = false
    sys.nearbyNPCs = {}
    sys.settingsPanel = nil
    sys.tickPersonalWork = nil
    return sys
end

local function containsById(list, id)
    for _, npc in ipairs(list) do
        if npc.id == id then return true end
    end
    return false
end

local function sortedIds(list)
    local ids = {}
    for _, npc in ipairs(list) do ids[#ids + 1] = npc.id end
    table.sort(ids)
    return table.concat(ids, ",")
end

-- ===== T1: client, one neighbour within 5 m =====
do
    local npc1 = makeNPC("A", 3, 0)
    local sys = makeClientSys({ npc1 })
    setPlayerPos(0, 0, 0)
    sys:update(100)

    T.eq("T1_nearbyNPCs_count", #sys.nearbyNPCs, 1)
    T.ok("T1_nearbyNPCs_holds_the_neighbour", sys.nearbyNPCs[1] == npc1)
    T.ok("T1_canInteract_true", npc1.canInteract == true)
    T.eq("T1_updateNPCEntity_called_once", #sys.entityManager.calls, 1)
end

-- ===== T2: client, neighbour walks out to 6 m: no stale entry =====
do
    local npc1 = makeNPC("A", 3, 0)
    local sys = makeClientSys({ npc1 })
    setPlayerPos(0, 0, 0)
    sys:update(100) -- neighbour in range; not asserted here (that is T1's job)

    npc1.position.x = 6 -- player stands still, neighbour walks out to 6 m
    sys:update(100)

    T.eq("T2_nearbyNPCs_empty_after_leaving_range", #sys.nearbyNPCs, 0)
    T.ok("T2_canInteract_false_after_leaving_range", npc1.canInteract == false)
end

-- ===== T3: client, a sleeping neighbour within 5 m =====
do
    local npc1 = makeNPC("A", 3, 0, true) -- isSleeping = true
    local sys = makeClientSys({ npc1 })
    setPlayerPos(0, 0, 0)
    sys:update(100)

    T.eq("T3_sleeping_neighbour_not_in_nearbyNPCs", #sys.nearbyNPCs, 0)
    T.ok("T3_sleeping_neighbour_canInteract_false", npc1.canInteract == false)
end

-- ===== T4: client, two neighbours in range: both listed =====
do
    local npcA = makeNPC("A", 2, 0) -- 2 m
    local npcB = makeNPC("B", 4, 0) -- 4 m
    local sys = makeClientSys({ npcA, npcB })
    setPlayerPos(0, 0, 0)
    sys:update(100)

    T.eq("T4_nearbyNPCs_count", #sys.nearbyNPCs, 2)
    T.ok("T4_nearbyNPCs_holds_A", containsById(sys.nearbyNPCs, "A"))
    T.ok("T4_nearbyNPCs_holds_B", containsById(sys.nearbyNPCs, "B"))
    T.eq("T4_updateNPCEntity_called_once_per_npc", #sys.entityManager.calls, 2)
end

-- ===== T5: client, no valid player position =====
do
    local npc1 = makeNPC("A", 3, 0)
    local sys = makeClientSys({ npc1 })
    clearPlayerPos()
    sys:update(100)

    T.ok("T5_playerPositionValid_false", sys.playerPositionValid == false)
    T.eq("T5_nearbyNPCs_empty_without_player_position", #sys.nearbyNPCs, 0)
end

-- ===== T6: server (isServer = true): unchanged; same contents as before =====
do
    -- Three npcs: A in range, B out of range, C in range but asleep. Built
    -- twice (independent tables) so the server run and the client run never
    -- mutate each other's fixture.
    local serverNPCs = { makeNPC("A", 3, 0), makeNPC("B", 6, 0), makeNPC("C", 3, 0, true) }
    local clientNPCs = { makeNPC("A", 3, 0), makeNPC("B", 6, 0), makeNPC("C", 3, 0, true) }

    local serverSys = makeServerSys(serverNPCs)
    setPlayerPos(0, 0, 0)
    serverSys:update(100)

    local clientSys = makeClientSys(clientNPCs)
    setPlayerPos(0, 0, 0)
    clientSys:update(100)

    T.eq("T6_server_nearbyNPCs_is_A_only", sortedIds(serverSys.nearbyNPCs), "A")
    T.eq("T6_server_and_client_nearbyNPCs_match",
        sortedIds(serverSys.nearbyNPCs), sortedIds(clientSys.nearbyNPCs))
end

-- ===== T7: nearbyNPCs is the one input both main.lua reads (main.lua itself
-- cannot be driven in this harness; see file header) =====
do
    -- 7a: a neighbour in range makes the action-active check's own list
    -- non-empty (main.lua:700 `if not isDialogOpen and npcSystem.nearbyNPCs`
    -- then iterates it; an empty list leaves shouldShow false).
    local npc1 = makeNPC("A", 3, 0)
    local sysWith = makeClientSys({ npc1 })
    setPlayerPos(0, 0, 0)
    sysWith:update(100)
    T.ok("T7a_nearbyNPCs_nonempty_with_neighbour_in_range", #sysWith.nearbyNPCs > 0)

    -- 7b: no neighbour in range leaves the same list empty (shouldShow stays
    -- false / the callback's `nearest` stays nil).
    local npc2 = makeNPC("A", 6, 0)
    local sysWithout = makeClientSys({ npc2 })
    setPlayerPos(0, 0, 0)
    sysWithout:update(100)
    T.eq("T7b_nearbyNPCs_empty_with_no_neighbour_in_range", #sysWithout.nearbyNPCs, 0)

    -- 7c: with two neighbours in range, the one with the smaller
    -- interactionDistance (the callback's selection key, main.lua:429-433) is
    -- the actual nearer npc.
    local npcA = makeNPC("A", 2, 0)
    local npcB = makeNPC("B", 4, 0)
    local sysTwo = makeClientSys({ npcA, npcB })
    setPlayerPos(0, 0, 0)
    sysTwo:update(100)

    local nearest, nearestDist = nil, 999
    for _, npc in ipairs(sysTwo.nearbyNPCs) do
        if npc.canInteract and npc.interactionDistance < nearestDist then
            nearest = npc
            nearestDist = npc.interactionDistance
        end
    end
    T.ok("T7c_callback_would_pick_the_nearer_neighbour", nearest == npcA)
end
