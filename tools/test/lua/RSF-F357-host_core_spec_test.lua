-- RSF-F357 host core: saved neighbours and their accepted work keep the same person.
--!load: src/utils/NPCFarmIdentity.lua, src/settings/NPCSettings.lua, src/scripts/NPCPersonRoster.lua, src/scripts/NPCRelationshipManager.lua, src/scripts/NPCFavorSystem.lua, src/scripts/NPCFavorRecovery.lua, src/scripts/NPCFieldWork.lua, src/scripts/NPCAI.lua, src/scripts/ContractorModBridge.lua, src/events/NPCStateSyncEvent.lua, src/integrations/NPCStateLedgerBridge.lua, src/integrations/NPCNetworkSyncBridge.lua, src/NPCSystem.lua
--
-- THE ENTRY-POINT BAR. Every group starts from production's own entry point:
-- NPCSystem.new, then onMissionLoaded, then the first-frame init updater the
-- mission mock captured (NPCSystem.lua's initUpdater), so initializeNPCs,
-- createNPCAtLocation and the allocator populate the town from the fixture's
-- placeables. Saves go through saveToXMLFile and reload through
-- loadFromXMLFile (the same XML the production writer wrote, in an in-memory
-- file store); the ledger route goes through NPCStateLedgerBridge.register
-- with a stub ledger that only stores and returns blocks; the second startup
-- path goes through onStartMissionLoad (main.lua's append is a one-line call
-- to it); pages travel through NPCStateSyncEvent's writeStream/readStream on a
-- typed mock stream; the NetworkSync array through the bridge's own
-- serialize/deserialize. Nothing hand-fills activeNPCs, a favour list, an id
-- or the high-water mark: the code under test obtains them all.
--
-- What this proves: the host core's contract, offline. What it does not:
-- native bodies, real disk, real transport, GUI, frame cost (A1 to A8 are
-- native observations owed at release).

-- =========================================================
-- World
-- =========================================================
TimeHelper = { getGameTimeMs = function() return (g_currentMission and g_currentMission.time) or 0 end }
VectorHelper = VectorHelper or { distance2D = function(x1, z1, x2, z2) local dx, dz = x1 - x2, z1 - z2 return math.sqrt(dx * dx + dz * dz) end }
FarmManager = { SPECTATOR_FARM_ID = 0, SINGLEPLAYER_FARM_ID = 1, MAX_FARM_ID = 8, GUIDED_TOUR_FARM_ID = 14, INVALID_FARM_ID = 15 }
local LIVE_FARMS = { [1] = { farmId = 1, name = "Farm 1", money = 100000 }, [2] = { farmId = 2, name = "Farm 2", money = 100000 } }
g_farmManager = {
    getFarmById = function(_, id) return LIVE_FARMS[id] end,
    getFarms = function(_) local l = {} for _, f in pairs(LIVE_FARMS) do l[#l + 1] = f end table.sort(l, function(a, b) return a.farmId < b.farmId end) return l end,
}
local MODS = {}
g_modManager = { getModByName = function(_, name) return MODS[name] end }
addConsoleCommand = function() end
g_i18n = { getText = function(_, key) return key end, hasText = function() return false end }

-- Nodes: world positions by node id.
local NODES = {}
function getWorldTranslation(node)
    local p = NODES[node]
    if p == nil then return 0, 0, 0 end
    return p.x, p.y, p.z
end
function getTerrainHeightAtWorldPos(_, x, _y, z) return 5 end

-- Subsystems NPCSystem.new instantiates that are not under test here.
NPCEntity = { new = function(sys)
    return {
        npcSystem = sys, npcEntities = {}, created = {}, removed = {},
        initialize = function() end,
        createNPCEntity = function(self, npc)
            self.npcEntities[npc.id] = { npcId = npc.id }
            self.created[#self.created + 1] = npc.id
            return true
        end,
        removeNPCEntity = function(self, npc)
            if self.npcEntities[npc.id] then
                self.npcEntities[npc.id] = nil
                self.removed[#self.removed + 1] = npc.id
            end
        end,
        updateNPCEntity = function() end,
        drawMapLabels = function() end,
    }
end }
NPCScheduler = { new = function()
    return { getCurrentHour = function() return 12 end, getCurrentMinute = function() return 0 end,
        getCurrentDay = function() return 1 end, getWeatherFactor = function() return 1 end,
        update = function() end, scheduledNPCInteractions = {} }
end }
NPCInteractionUI = { new = function() return { update = function() end, delete = function() end } end }
NPCFavorHUD = { new = function() return { loadFromSettings = function() end, flashFavor = function() end, update = function() end, delete = function() end } end }
NPCSettingsIntegration = { new = function() return { initialize = function() end } end }
NPCSettingsPanel = { new = function() return { initialize = function() end, update = function() end, delete = function() end } end }
NPCFavorGUI = { new = function() return { registerConsoleCommands = function() end } end }

-- In-memory XML file store: the production writer and reader meet here.
local DISK = {}
local function xmlMock(store)
    local m = { store = store }
    m.setInt = function(_, k, v) store[k] = v end
    m.setFloat = function(_, k, v) store[k] = v end
    m.setString = function(_, k, v) store[k] = v end
    m.setBool = function(_, k, v) store[k] = v end
    local function get(_, k, default) if store[k] ~= nil then return store[k] end return default end
    m.getInt, m.getFloat, m.getString, m.getBool = get, get, get, get
    m.hasProperty = function(_, k) return store[k] ~= nil end
    m.iterate = function(_, prefix, fn)
        local i = 0
        while true do
            local key = prefix .. "(" .. i .. ")"
            local found = false
            for k in pairs(store) do
                if k:sub(1, #key + 1) == key .. "#" or k:sub(1, #key + 1) == key .. "." then found = true break end
            end
            if not found then return end
            fn(i, key)
            i = i + 1
        end
    end
    m.delete = function() end
    m.save = function(self) DISK[self.path] = self.store end
    return m
end
local XML_READS = 0
XMLFile = {
    create = function(_, path, _root) local m = xmlMock({}) m.path = path return m end,
    loadIfExists = function(_, path, _root)
        if path:match("npc_favor%.xml$") then XML_READS = XML_READS + 1 end
        local store = DISK[path]
        if store == nil then return nil end
        local copy = {}
        for k, v in pairs(store) do copy[k] = v end
        local m = xmlMock(copy) m.path = path
        return m
    end,
}
local function fileAt(dir) return DISK[dir .. "/npc_favor.xml"] end

-- Placeables: a house is a table with a root node, a unique id and an owner.
local NODE_SEQ = 100
local function house(uid, x, z, ownerFarmId)
    NODE_SEQ = NODE_SEQ + 1
    NODES[NODE_SEQ] = { x = x, y = 5, z = z }
    return { rootNode = NODE_SEQ, typeName = "farmhouse", spec_farmhouse = {}, ownerFarmId = ownerFarmId or 0,
        getName = function() return "House " .. uid end, getUniqueId = function() return uid end }
end
local function town(n)
    local list = {}
    for i = 1, n do list[i] = house("house_" .. i, i * 100, i * 100, 0) end
    return list
end

local function newMission(opts)
    return {
        time = 1000, environment = { currentDay = 1, daysPerPeriod = 1 },
        missionInfo = { savegameDirectory = opts.dir or "sg" },
        isMissionStarted = true, terrainRootNode = 1, terrainSize = 2048,
        placeableSystem = { placeables = opts.placeables or {} },
        updateables = {},
        addUpdateable = function(self, u) self.updateables[#self.updateables + 1] = u end,
        getFarmId = function() return 1 end,
        addIngameNotification = function() end,
        getIsServer = function() return g_server ~= nil end,
    }
end

-- Boot through production's own entry point. Returns the system; the init
-- updater is ticked once (it returns true when it removed itself).
local function boot(opts)
    opts = opts or {}
    g_server = (opts.server ~= false) and {} or nil
    g_client = nil
    g_currentMission = newMission(opts)
    NPCStateLedgerBridge.active, NPCStateLedgerBridge.delivered, NPCStateLedgerBridge.pendingState = false, false, nil
    local sys = NPCSystem.new(g_currentMission, "mod/", "FS25_NPCFavor")
    g_NPCSystem = sys
    if opts.ledger then
        g_currentMission.stateLedger = opts.ledger
        NPCStateLedgerBridge.register()
    end
    sys:onMissionLoaded()
    -- onMissionLoaded restored the saved settings of this slot (production);
    -- the fixture's count is the player's current choice, applied after that.
    sys.settings.maxNPCs = opts.maxNPCs or 3
    sys.settings.npcDriveVehicles = false
    sys.settings.enableFavors = false
    sys.settings.showNotifications = false
    sys.settings.debugMode = false
    if not opts.noTick then
        sys._initResult = g_currentMission.updateables[1]:update(16)
    end
    return sys
end
local function tick(sys) return g_currentMission.updateables[1]:update(16) end

-- Stub ledger: stores hooks, delivers its block on parse (or when told to).
local function newLedger(block, hold)
    local L = { modules = {}, block = block, hasParsed = false, hold = hold == true }
    function L:registerModule(name, hooks) self.modules[name] = hooks if self.hasParsed then hooks.deserialize(self.block) end return true end
    function L:parseFile() if self.hasParsed or self.hold then return end self:deliver() end
    function L:deliver() self.hasParsed = true for _, h in pairs(self.modules) do h.deserialize(self.block) end end
    function L:serialize(name) return self.modules[name].serialize() end
    return L
end

local function ids(list) local out = {} for i, npc in ipairs(list) do out[i] = npc.id end table.sort(out) return out end
local function join(list) local s = {} for i, v in ipairs(list) do s[i] = tostring(v) end return table.concat(s, ",") end
local function names(list) local out = {} for _, npc in ipairs(list) do out[npc.name] = true end return out end
local function personById(sys, id) return sys.people:getPerson(id) end

-- =========================================================
-- S: first-frame init on a new career (server)
-- =========================================================
do
    local sys = boot({ placeables = town(4), maxNPCs = 3, dir = "s1" })
    T.eq("S1 the init updater ran once and removed itself", sys._initResult, true)
    T.eq("S2 people are READY after the first frame", sys.people:getLoadState(), "READY")
    T.eq("S3 favours are READY (a new career is a valid empty snapshot)", sys.favorSystem:getFavorLoadState(), "READY")
    T.eq("S4 three newcomers fill the count", #sys.activeNPCs, 3)
    T.eq("S5 the roster holds exactly the live newcomers", sys.people:count(), 3)
    T.eq("S6 numbers come from the allocator, in order", join(ids(sys.activeNPCs)), "1,2,3")
    T.eq("S7 the high-water mark is the last number issued", sys.people:getHighWater(), 3)
    T.eq("S8 every live person has a body", #sys.entityManager.created, 3)
    T.ok("S9 the home's native unique id is kept as an attribute", sys.activeNPCs[1].homeUniqueId ~= nil and sys.activeNPCs[1].homeUniqueId:match("^house_") ~= nil)
    T.eq("S10 no uniqueId text key is minted any more", sys.activeNPCs[1].uniqueId, nil)
    T.eq("S11 a newcomer is a durable town person", sys.activeNPCs[2].personKind .. "/" .. sys.activeNPCs[2].origin, "durable/town")
    T.ok("S12 the newcomer is actionable", sys:isPersonActionable(sys.activeNPCs[1]))
    T.eq("S13 getNPCById returns the unique live person", sys:getNPCById(2), sys.activeNPCs[2])
    T.eq("S14 getNPCById refuses a number nobody has", sys:getNPCById(99), nil)
    local view = sys:getNeighbourRosterView()
    T.eq("S15 roster view: READY and CURRENT", view.personLoadState .. "/" .. view.snapshotState, "READY/CURRENT")
    T.eq("S16 roster view: three LIVE rows with trust and position", #view.rows, 3)
    T.ok("S17 a live row carries its trust and a position", view.rows[1].kind == "LIVE" and view.rows[1].trust ~= nil and view.rows[1].position ~= nil)
    T.ok("S18 a live row's action flags are on", view.rows[1].canTalk and view.rows[1].canGoTo)
    -- The second startup path is a no-op after the first selection.
    local before = sys.people.revision
    sys:onStartMissionLoad(g_currentMission.missionInfo)
    T.eq("S19 onStartMission after READY selects nothing again", sys.people:count() .. "/" .. tostring(sys.people.revision == before), "3/true")
    T.eq("S20 a repeated loadFromXMLFile after READY is a no-op", (sys:loadFromXMLFile(g_currentMission.missionInfo)), nil)
    T.eq("S21 the roster is unchanged by it", #sys.activeNPCs, 3)
end

-- =========================================================
-- X: XML round trip, count, homes, continuity
-- =========================================================
do
    local placeables = town(4)
    local sys = boot({ placeables = placeables, maxNPCs = 3, dir = "x1" })
    local p2 = sys.activeNPCs[2]
    p2.relationship = 77
    p2.name = "Greta Hoffmann"
    -- Accepted work for person 2 through the real favour creator.
    local favor = sys.favorSystem:createFavor(p2, "fix_fence")
    T.eq("X0 a new favour is marked durable", favor.personRefKind, "durable")
    table.insert(sys.favorSystem.activeFavors, favor)
    local accepted = sys.favorSystem:acceptFavorForNPC(p2.id, 1)
    T.ok("X0b the offer was accepted by farm 1", accepted ~= nil and accepted.ownerFarmId == 1)
    -- A tie between 1 and 2 through the real pair graph.
    sys.relationshipManager:updateNPCNPCRelationship(sys.activeNPCs[1], p2, "socialize")

    sys:saveToXMLFile(g_currentMission.missionInfo)
    local f = fileAt("x1")
    T.ok("X1 the save wrote a file", f ~= nil)
    T.eq("X2 the file carries the person schema", f["npcFavor#personSchema"], 1)
    T.eq("X3 and the high-water mark", f["npcFavor#personIdHighWater"], 3)
    T.eq("X4 a person row carries her durable number", f["npcFavor.npcs.npc(1)#id"], 2)
    T.eq("X5 and her house's unique id", f["npcFavor.npcs.npc(1).home#uniqueId"], p2.homeUniqueId)
    T.eq("X6 the favour row carries the durable mark", f["npcFavor.favors.favor(0)#personRefKind"], "durable")
    T.eq("X7 the tie carries the durable endpoint mark", f["npcFavor.npcRelationships.rel(0)#endpointKind"], "durable")

    -- Reload into a fresh system: same people, same numbers, same trust.
    local re = boot({ placeables = placeables, maxNPCs = 3, dir = "x1" })
    T.eq("X8 reload: READY", re.people:getLoadState(), "READY")
    T.eq("X9 reload: the same three numbers, no newcomer", join(ids(re.activeNPCs)), "1,2,3")
    local q2 = re:getNPCById(2)
    T.eq("X10 reload: person 2 keeps her trust", q2.relationship, 77)
    T.eq("X11 reload: and her name", q2.name, "Greta Hoffmann")
    T.eq("X12 reload: and her house", q2.homeUniqueId, p2.homeUniqueId)
    T.eq("X13 reload: her home spot is the saved one", q2.homePosition.x, p2.homePosition.x)
    T.eq("X14 reload: the high-water mark is restored", re.people:getHighWater(), 3)
    T.eq("X15 reload: the accepted work is active with the same person", #re.favorSystem.activeFavors, 1)
    T.eq("X16 reload: it names person 2 by number", re.favorSystem.activeFavors[1].npcId, 2)
    T.eq("X17 reload: the tie reconnected into the pair graph", re.relationshipManager:getNPCNPCValue(1, 2) ~= 50, true)

    -- Count reduced: the third person waits (ascending-number order), keeps her data, has no body.
    local fewer = boot({ placeables = placeables, maxNPCs = 2, dir = "x1" })
    T.eq("X18 count 2: two live", #fewer.activeNPCs, 2)
    T.eq("X19 count 2: the roster still holds three", fewer.people:count(), 3)
    local w3 = personById(fewer, 3)
    T.eq("X20 count 2: person 3 waits for the count", w3.waitingReason, "npc_person_waiting_count")
    T.eq("X21 count 2: she has no body", fewer.entityManager.npcEntities[3], nil)
    T.eq("X22 count 2: getNPCById does not return a waiting person", fewer:getNPCById(3), nil)
    T.eq("X23 count 2: but the retained lookup does", fewer:resolveRetainedPerson(3), w3)
    T.ok("X24 count 2: a waiting person is not actionable", not fewer:isPersonActionable(w3))
    local view = fewer:getNeighbourRosterView()
    local waitingRow = nil
    for _, row in ipairs(view.rows) do if row.personId == 3 then waitingRow = row end end
    T.eq("X25 count 2: the roster view shows her WAITING with her reason", waitingRow.kind .. "/" .. waitingRow.reasonKey, "WAITING/npc_person_waiting_count")
    T.eq("X26 count 2: a waiting row has no trust, not a zero", waitingRow.trust, nil)
    T.eq("X27 count 2: and no position", waitingRow.position, nil)
    fewer:saveToXMLFile(g_currentMission.missionInfo)
    T.eq("X28 count 2: the waiting person is saved", fileAt("x1")["npcFavor.npcs.npc(2)#id"], 3)

    -- Count raised: she returns before any newcomer.
    local more = boot({ placeables = placeables, maxNPCs = 4, dir = "x1" })
    T.eq("X29 count 4: the retained three return first", join(ids(more.activeNPCs)), "1,2,3,4")
    T.eq("X30 count 4: person 3 is live again", personById(more, 3).live, true)
    T.eq("X31 count 4: one newcomer got the next number, never a reused one", more.people:getHighWater(), 4)

    -- A house removed: the person keeps her identity and moves, nobody is exchanged.
    local rebuilt = { placeables[1], placeables[3], placeables[4], house("house_9", 900, 900, 0) }
    local moved = boot({ placeables = rebuilt, maxNPCs = 3, dir = "x1" })
    local m2 = moved:getNPCById(2)
    T.ok("X32 house removed: person 2 is still person 2", m2 ~= nil and m2.name == "Greta Hoffmann" and m2.relationship == 77)
    T.ok("X33 house removed: she has a different house now", m2.homeUniqueId ~= p2.homeUniqueId)
    T.eq("X34 house removed: nobody was created or exchanged", join(ids(moved.activeNPCs)), "1,2,3")
end

-- =========================================================
-- L: legacy work is held (a pre-F357 save)
-- =========================================================
do
    -- A save written before this repair: person rows with uniqueId only, favours
    -- without the durable mark, one paused row with its own reason.
    local dir = "l1"
    local sys0 = boot({ placeables = town(3), maxNPCs = 2, dir = dir })
    sys0:saveToXMLFile(g_currentMission.missionInfo)
    local f = fileAt(dir)
    -- Rewrite it into the legacy shape.
    f["npcFavor#personSchema"], f["npcFavor#personIdHighWater"] = nil, nil
    f["npcFavor.npcs.npc(0)#id"], f["npcFavor.npcs.npc(1)#id"] = nil, nil
    f["npcFavor.npcs.npc(0)#uniqueId"] = "npc_1_old_1111"
    f["npcFavor.npcs.npc(1)#uniqueId"] = "npc_2_old_2222"
    f["npcFavor.npcs.npc(0).home#uniqueId"], f["npcFavor.npcs.npc(1).home#uniqueId"] = nil, nil
    f["npcFavor.npcs.npc(0).stats#relationship"] = 61
    local function legacyFavor(i, status, npcId, owner)
        local k = "npcFavor.favors.favor(" .. i .. ")"
        f[k .. "#f148Schema"] = 1
        f[k .. "#favorId"] = 10 + i
        f[k .. "#npcId"] = npcId
        f[k .. "#npcName"] = "Old Name"
        f[k .. "#type"] = "fix_fence"
        f[k .. "#description"] = "Fix"
        f[k .. "#status"] = status
        f[k .. "#timeRemainingPresent"] = true
        f[k .. "#timeRemaining"] = 4242
        f[k .. "#progress"] = (status == "pending") and 0 or 40
        f[k .. "#ownerFarmIdPresent"] = owner ~= nil
        if owner ~= nil then f[k .. "#ownerFarmId"] = owner end
        f[k .. "#rewardPaidPresent"] = true
        f[k .. "#rewardPaid"] = false
        f[k .. "#repaymentCollectedPresent"] = true
        f[k .. "#repaymentCollected"] = false
        f[k .. "#awaitingConfirmation"] = false
    end
    legacyFavor(0, "active", 1, 1)
    legacyFavor(1, "in_progress", 2, 1)
    legacyFavor(2, "pending", 1, nil)
    f["npcFavor.recoveryFavors.favor(0)#f148Schema"] = 1
    f["npcFavor.recoveryFavors.favor(0)#favorId"] = 20
    f["npcFavor.recoveryFavors.favor(0)#npcId"] = 2
    f["npcFavor.recoveryFavors.favor(0)#npcName"] = "Old Name"
    f["npcFavor.recoveryFavors.favor(0)#type"] = "fix_fence"
    f["npcFavor.recoveryFavors.favor(0)#status"] = "paused_recovery"
    f["npcFavor.recoveryFavors.favor(0)#recoveryReason"] = "owner_farm_deleted"
    f["npcFavor.recoveryFavors.favor(0)#timeRemainingPresent"] = true
    f["npcFavor.recoveryFavors.favor(0)#timeRemaining"] = 999
    f["npcFavor.recoveryFavors.favor(0)#ownerFarmIdPresent"] = true
    f["npcFavor.recoveryFavors.favor(0)#ownerFarmId"] = 15
    f["npcFavor.recoveryFavors.favor(0)#rewardPaidPresent"] = true
    f["npcFavor.recoveryFavors.favor(0)#rewardPaid"] = false

    local sys = boot({ placeables = town(3), maxNPCs = 2, dir = dir })
    T.eq("L1 a legacy save loads READY", sys.people:getLoadState(), "READY")
    T.eq("L2 legacy people are restored as durable people with new numbers, favour references reserved first", join(ids(sys.activeNPCs)), "3,4")
    T.eq("L3 the high-water mark sits above every reserved reference", sys.people:getHighWater(), 4)
    T.eq("L4 a legacy person keeps her saved trust", sys.activeNPCs[1].relationship, 61)
    T.eq("L5 her old text key is evidence only", sys.activeNPCs[1].legacyUniqueId, "npc_1_old_1111")
    T.eq("L6 the legacy town grammar sized her as a town candidate", sys.activeNPCs[1].townCandidate, true)
    T.eq("L7 no legacy favour is live", #sys.favorSystem.activeFavors, 0)
    local rec = sys.favorSystem.recoveryFavors
    T.eq("L8 the accepted, the in-progress and the paused rows are held; the clean offer is withdrawn", #rec, 3)
    local byId = {}
    for _, r in ipairs(rec) do byId[r.id] = r end
    local active, inProgress, paused = byId[10], byId[11], byId[20]
    T.eq("L9 held active row: paused, unproven", active.status .. "/" .. active.recoveryReason, "paused_recovery/person_unproven")
    T.eq("L10 held active row: original status kept", active.originalStatus, "active")
    T.eq("L11 held active row: remaining time frozen", active.timeRemaining .. "/" .. tostring(active.expirationGameTime), "4242/nil")
    T.eq("L12 held active row: owner and payment facts kept", tostring(active.ownerFarmId) .. "/" .. tostring(active.rewardPaid), "1/false")
    T.eq("L13 held active row: the saved name is kept as text", active.npcName, "Old Name")
    -- A namesake is never a witness: a row naming a live person by NAME with a number nobody has.
    local namesake = sys.favorSystem:restoreFavor({ f148Schema = 1, favorId = 77, npcId = 99, npcName = sys.activeNPCs[1].name,
        type = "fix_fence", status = "active", timeRemainingPresent = true, timeRemaining = 10, progress = 0,
        ownerFarmIdPresent = true, ownerFarmId = 1, rewardPaidPresent = true, rewardPaid = false,
        repaymentCollectedPresent = true, repaymentCollected = false })
    T.eq("L13b a namesake row is not resolved to the live person of that name", tostring(namesake.npcResolved) .. "/" .. namesake.status, "false/paused_recovery")
    T.eq("L14 held active row: not resumable", active.resumable, false)
    T.eq("L15 held active row: inspect-only", sys.favorSystem:isRecoveryRecordInspectOnly(active), true)
    T.eq("L16 held active row: the unavailable key names the person", sys.favorSystem:getRecoveryUnavailableKey(active), "npc_recovery_unavail_person")
    T.eq("L17 held in-progress row: original status kept", inProgress.originalStatus .. "/" .. inProgress.recoveryReason, "in_progress/person_unproven")
    T.eq("L18 held paused row keeps its own reason", paused.recoveryReason, "owner_farm_deleted")
    T.eq("L19 held paused row: unproven, so no assignment either", sys.favorSystem:isRecoveryRecordActionable(paused), false)
    -- No pay, no penalty, no resume.
    local relCalls = 0
    local rm = sys.relationshipManager
    local origUpdate = rm.updateRelationship
    rm.updateRelationship = function(self, ...) relCalls = relCalls + 1 return origUpdate(self, ...) end
    T.eq("L20 a held row cannot complete", sys.favorSystem:completeFavor(active.id), false)
    T.eq("L21 a held row cannot fail", sys.favorSystem:failFavor(active.id, "time_expired"), false)
    T.eq("L22 a held row cannot be abandoned", sys.favorSystem:abandonFavor(active.id), false)
    sys.favorSystem:applyFavorRewards(active)
    sys.favorSystem:applyFavorPenalties(active)
    T.eq("L23 nothing was paid or penalised", relCalls, 0)
    T.eq("L24 a held row cannot resume", sys.favorSystem:resumeRecoveryRecord(active, 1) and "resumed" or "refused", "refused")
    T.eq("L25 the held row is still held after the refusals", active.status, "paused_recovery")
    -- It round-trips as held.
    sys:saveToXMLFile(g_currentMission.missionInfo)
    local again = boot({ placeables = town(3), maxNPCs = 2, dir = dir })
    T.eq("L26 after another reload it is still held, same reason", again.favorSystem.recoveryFavors[1].recoveryReason, "person_unproven")
    T.eq("L27 and the people keep their new numbers", join(ids(again.activeNPCs)), "3,4")
    -- An unmarked row whose number a LIVE person holds (a hand-edited or half-migrated
    -- save): the mark alone decides, and the resume door stays shut even though she is here.
    local g = fileAt(dir)
    local n = 0
    while g["npcFavor.favors.favor(" .. n .. ")#favorId"] ~= nil do n = n + 1 end
    local k = "npcFavor.favors.favor(" .. n .. ")"
    g[k .. "#f148Schema"], g[k .. "#favorId"], g[k .. "#npcId"], g[k .. "#npcName"] = 1, 55, 3, "Whoever"
    g[k .. "#type"], g[k .. "#status"], g[k .. "#timeRemainingPresent"], g[k .. "#timeRemaining"] = "fix_fence", "active", true, 777
    g[k .. "#progress"], g[k .. "#ownerFarmIdPresent"], g[k .. "#ownerFarmId"] = 0, true, 1
    g[k .. "#rewardPaidPresent"], g[k .. "#rewardPaid"] = true, false
    g[k .. "#repaymentCollectedPresent"], g[k .. "#repaymentCollected"] = true, false
    local third = boot({ placeables = town(3), maxNPCs = 2, dir = dir })
    local held = nil
    for _, r in ipairs(third.favorSystem.recoveryFavors) do if r.id == 55 then held = r end end
    T.ok("L28 an unmarked row naming a live person's number is held all the same", held ~= nil and held.recoveryReason == "person_unproven")
    T.eq("L29 the person it names is live", third:getNPCById(3) ~= nil, true)
    T.eq("L30 and still it cannot resume", third.favorSystem:resumeRecoveryRecord(held, 1), false)
    T.eq("L31 nor is it actionable", third.favorSystem:isRecoveryRecordActionable(held), false)
end

-- =========================================================
-- Q: duplicated numbers, unknown schema, opaque rows, the throw path
-- =========================================================
do
    local dir = "q1"
    local sys0 = boot({ placeables = town(3), maxNPCs = 3, dir = dir })
    local fav = sys0.favorSystem:createFavor(sys0.activeNPCs[2], "fix_fence")
    table.insert(sys0.favorSystem.activeFavors, fav)
    sys0.favorSystem:acceptFavorForNPC(2, 1)
    sys0:saveToXMLFile(g_currentMission.missionInfo)
    local f = fileAt(dir)
    -- Two saved rows with one number: person 3's row is renumbered onto 2.
    f["npcFavor.npcs.npc(2)#id"] = 2
    local sys = boot({ placeables = town(3), maxNPCs = 3, dir = dir })
    T.eq("Q1 both rows are retained under distinct numbers", sys.people:count(), 3)
    T.eq("Q2 no row keeps the duplicated number; new numbers are minted above the mark", join(ids(sys.activeNPCs)), "1,4,5")
    T.eq("Q3 the duplicated number is unproven", select(2, sys:resolveRetainedPerson(2)), "unproven")
    T.eq("Q4 the favour that named it is held, not attached to either", #sys.favorSystem.activeFavors .. "/" .. #sys.favorSystem.recoveryFavors, "0/1")
    T.eq("Q5 as person_unproven", sys.favorSystem.recoveryFavors[1].recoveryReason, "person_unproven")
    sys:saveToXMLFile(g_currentMission.missionInfo)
    local again = boot({ placeables = town(3), maxNPCs = 3, dir = dir })
    T.eq("Q6 the old number is never reused later", join(ids(again.activeNPCs)), "1,4,5")
    T.eq("Q7 the reference stays unproven on every later reload", again.favorSystem.recoveryFavors[1].recoveryReason, "person_unproven")

    -- Unknown future person schema: FAILED, file untouched, nothing created.
    local dir2 = "q2"
    local s2 = boot({ placeables = town(3), maxNPCs = 3, dir = dir2 })
    s2:saveToXMLFile(g_currentMission.missionInfo)
    fileAt(dir2)["npcFavor#personSchema"] = 2
    local before = fileAt(dir2)
    local okBoot, failed = pcall(boot, { placeables = town(3), maxNPCs = 3, dir = dir2 })
    T.eq("Q7b unknown person schema: refused inside the load, no throw out of the init pass", okBoot, true)
    if not okBoot then failed = { people = NPCPersonRoster.new(nil), favorSystem = NPCFavorSystem.new({ activeNPCs = {} }), activeNPCs = {}, saveToXMLFile = function() end, serializeState = function() end, isPersonActionable = function() return true end, consoleCommandSpawn = function() return "" end } end
    T.eq("Q8 unknown person schema: FAILED", failed.people:getLoadState(), "FAILED")
    T.eq("Q9 unknown schema: no town, no newcomer", #failed.activeNPCs .. "/" .. failed.people:count(), "0/0")
    T.eq("Q10 unknown schema: the favour load is FAILED with origin abort", failed.favorSystem:getFavorLoadFailOrigin(), "abort")
    T.eq("Q11 unknown schema: the player was told", failed._personLoadFailedNotified, true)
    failed:saveToXMLFile(g_currentMission.missionInfo)
    T.eq("Q12 unknown schema: the save left the file exactly as it was", fileAt(dir2), before)
    T.eq("Q13 unknown schema: no ledger block, serializeState omits the module", failed:serializeState(), nil)
    T.ok("Q14 unknown schema: nothing is actionable", not failed:isPersonActionable({ id = 1, personKind = "durable", live = true, isActive = true }))
    T.eq("Q15 unknown schema: the console creator refuses", failed:consoleCommandSpawn("X"):match("not ready") ~= nil, true)

    -- Opaque rows: a primitive under the people block round-trips as evidence.
    local dir3 = "q3"
    local s3 = boot({ placeables = town(2), maxNPCs = 2, dir = dir3 })
    s3:saveToXMLFile(g_currentMission.missionInfo)
    fileAt(dir3)["npcFavor.opaquePeople.row(0)#value"] = "42"
    fileAt(dir3)["npcFavor.opaquePeople.row(0)#valueType"] = "number"
    local o = boot({ placeables = town(2), maxNPCs = 2, dir = dir3 })
    T.eq("Q16 an opaque row is retained", #o.people.opaque, 1)
    T.eq("Q17 it names no person", o.people:count(), 2)
    local ov = o:getNeighbourRosterView()
    T.eq("Q18 the roster view lists it as OPAQUE with no person id", ov.rows[3].kind .. "/" .. tostring(ov.rows[3].personId), "OPAQUE/nil")
    o:saveToXMLFile(g_currentMission.missionInfo)
    T.eq("Q19 it is written back at the next save", fileAt(dir3)["npcFavor.opaquePeople.row(0)#value"], "42")
end

-- =========================================================
-- G: the ledger route
-- =========================================================
do
    -- A ledger that has registered but not delivered keeps the people WAITING:
    -- no town, no bodies, no allocation; XML is never chosen for a late provider.
    local placeables = town(3)
    DISK["g1/npc_favor.xml"] = nil
    local late = newLedger(nil, true)
    XML_READS = 0
    local sys = boot({ placeables = placeables, maxNPCs = 3, dir = "g1", ledger = late })
    T.eq("G1 late ledger: the init pass completed", sys._initResult, true)
    T.eq("G2 late ledger: people WAITING", sys.people:getLoadState(), "WAITING")
    T.eq("G3 late ledger: no town, no allocation", #sys.activeNPCs .. "/" .. sys.people:getHighWater(), "0/0")
    T.eq("G4 late ledger: XML was not read", XML_READS, 0)
    T.eq("G5 late ledger: favours WAITING too", sys.favorSystem:getFavorLoadState(), "WAITING")
    sys:onStartMissionLoad(g_currentMission.missionInfo)
    T.eq("G6 late ledger: the second startup path does not choose XML either", XML_READS .. "/" .. sys.people:getLoadState(), "0/WAITING")
    sys:update(16)
    T.eq("G7 late ledger: nothing simulates while WAITING", sys.updateCounter, 1)
    sys:saveToXMLFile(g_currentMission.missionInfo)
    T.eq("G8 late ledger: nothing is saved while WAITING", fileAt("g1"), nil)
    T.eq("G9 late ledger: serializeState hands back nothing (no block)", sys:serializeState(), nil)
    -- The late delivery of a nil block permits XML (none exists: a new career).
    late:deliver()
    T.eq("G10 late nil delivery: the same selected load ran and the people are READY", sys.people:getLoadState(), "READY")
    T.eq("G11 late nil delivery: the town was filled once", join(ids(sys.activeNPCs)), "1,2,3")
    late:deliver()
    T.eq("G12 a repeated delivery is a no-op", join(ids(sys.activeNPCs)) .. "/" .. sys.people:getHighWater(), "1,2,3/3")
    T.eq("G12b the people stay READY through it", sys.people:getLoadState() .. "/" .. sys.people:count(), "READY/3")

    -- A delivered block owns the load: XML is not read, the same people return.
    local block = late:serialize("NPCFavor_State")
    T.eq("G13 the ledger block carries the person schema and mark", block.personSchema .. "/" .. block.personIdHighWater, "1/3")
    T.eq("G14 the ledger block carries every retained person by number", #block.npcs, 3)
    XML_READS = 0
    local owned = newLedger(block, false)
    local re = boot({ placeables = placeables, maxNPCs = 3, dir = "g1", ledger = owned })
    T.eq("G15 delivered block: READY from the ledger", re.people:getLoadState(), "READY")
    T.eq("G16 delivered block: XML was not read", XML_READS, 0)
    T.eq("G17 delivered block: the same numbers", join(ids(re.activeNPCs)), "1,2,3")
    T.ok("G18 delivered block: the original delivered table is kept by identity", re._ledgerOriginalState == block)

    -- A block the real importer refuses (encounters not a table) throws inside
    -- the protected apply: FAILED with origin abort, the original handed back.
    local bad = { schemaVersion = "1.2.4", personSchema = 1, personIdHighWater = 3,
        npcs = { { id = 1, name = "Broken", encounters = 5 } }, favors = {}, recoveryFavors = {}, relationships = {} }
    local badLedger = newLedger(bad, false)
    local okBoot, fb = pcall(boot, { placeables = placeables, maxNPCs = 3, dir = "g1", ledger = badLedger })
    T.eq("G18b unsafe row: the throw is caught inside the load (the init pass survives)", okBoot, true)
    if not okBoot then fb = { people = NPCPersonRoster.new(nil), favorSystem = NPCFavorSystem.new({ activeNPCs = {} }), activeNPCs = {}, serializeState = function() end } end
    T.eq("G19 unsafe row: people FAILED", fb.people:getLoadState(), "FAILED")
    T.eq("G20 unsafe row: favour load FAILED, origin abort", fb.favorSystem:getFavorLoadFailOrigin(), "abort")
    T.ok("G21 unsafe row: serializeState returns the delivered block itself", fb:serializeState() == bad)
    T.eq("G22 unsafe row: no newcomer was created", #fb.activeNPCs .. "/" .. fb.people:count(), "0/0")
    T.eq("G23 unsafe row: the delivered row is untouched", bad.npcs[1].encounters, 5)
    T.eq("G24 unsafe row: a repeated delivery does not revive the load", (badLedger:deliver() or fb.people:getLoadState()), "FAILED")
end

-- =========================================================
-- C: the pure client and the paged own event
-- =========================================================
do
    local placeables = town(4)
    local server = boot({ placeables = placeables, maxNPCs = 3, dir = "c1" })
    server.activeNPCs[1].relationship = 33
    local snapshot = server:publishSnapshot()
    T.eq("C1 the server's snapshot carries every record once", snapshot.total .. "/" .. snapshot.pageCount, "3/1")
    T.eq("C2 the sequence is positive and increases", snapshot.sequence, 1)

    -- The pure client boots WAITING: no roster, no allocator, no town.
    local client = boot({ placeables = placeables, maxNPCs = 3, dir = "c1", server = false })
    T.eq("C3 client: the init pass completed", client._initResult, true)
    T.eq("C4 client: WAITING with no people", client.people:getLoadState() .. "/" .. #client.activeNPCs .. "/" .. client.people:getHighWater(), "WAITING/0/0")
    T.eq("C5 client: no local XML was chosen (file exists on disk: the server wrote nothing yet, but the client never asked)", client.people.selectedSource, nil)
    local cv = client:getNeighbourRosterView()
    T.eq("C6 client: the view says WAITING and UNAVAILABLE", cv.personLoadState .. "/" .. cv.snapshotState, "WAITING/UNAVAILABLE")

    -- One page through the real stream round trip publishes the snapshot.
    local function deliver(page)
        local ev = NPCStateSyncEvent.new(page)
        local s = _sfMockStream()
        ev:writeStream(s, nil)
        local rx = NPCStateSyncEvent.emptyNew()
        g_server, g_NPCSystem = nil, client
        rx:readStream(s, nil)
        return s
    end
    local s = deliver(NPCPersonRoster.pageOf(snapshot, 1))
    T.eq("C7 the stream drained exactly, no type errors", s.r - 1 .. "/" .. s.typeErrors .. "/" .. s.underflows, #s.q .. "/0/0")
    T.eq("C8 client: READY from the complete snapshot", client.people:getLoadState(), "READY")
    T.eq("C9 client: the three live people have bodies, by the server's numbers", join(ids(client.activeNPCs)) .. "/" .. #client.entityManager.created, "1,2,3/3")
    T.eq("C10 client: trust travelled", client:getNPCById(1).relationship, 33)
    T.eq("C11 client: still no allocation on the client", client.people:getHighWater(), 0)
    cv = client:getNeighbourRosterView()
    T.eq("C12 client: the view is READY and CURRENT at the server's sequence", cv.personLoadState .. "/" .. cv.snapshotState .. "/" .. cv.revision, "READY/CURRENT/1")
    T.ok("C13 client: a live row is actionable in the view", cv.rows[1].canTalk)
    T.ok("C14 client: isPersonActionable agrees for a live synced person", client:isPersonActionable(client.activeNPCs[1]))

    -- 51 people: two pages; the 51st reaches the client only when both agree.
    g_server, g_NPCSystem = {}, server
    for i = 4, 51 do
        local npc = server:createNPCAtLocation({ x = i, y = 0, z = i })
        npc.name = "P" .. i
        server:initializeNPCData(npc, { x = i, y = 0, z = i }, npc.id)
        server.people:addPerson(npc)
        server:setPersonLive(npc, true)
    end
    local big = server:publishSnapshot()
    T.eq("C15 51 people need two pages", big.total .. "/" .. big.pageCount, "51/2")
    T.eq("C16 the first page keeps the 50-record bound", #NPCPersonRoster.pageOf(big, 1).records, 50)
    deliver(NPCPersonRoster.pageOf(big, 2))
    T.eq("C17 the out-of-order last page stages without publishing", client.people.publishedSequence, 1)
    T.eq("C18 while a newer snapshot is incomplete the view is PENDING", client:getNeighbourRosterView().snapshotState, "PENDING")
    T.eq("C19 the displayed people are last-confirmed, not the partial town", #client.activeNPCs, 3)
    deliver(NPCPersonRoster.pageOf(big, 1))
    T.eq("C20 the first page completes it", client.people.publishedSequence, 2)
    T.eq("C21 the 51st person reached the client", client:getNPCById(51) ~= nil and #client.activeNPCs == 51, true)
    deliver(NPCPersonRoster.pageOf(big, 1))
    T.eq("C22 an identical duplicate page is harmless", client.people.publishedSequence .. "/" .. #client.activeNPCs, "2/51")

    -- A conflicting duplicate page at the same sequence is refused.
    g_server, g_NPCSystem = {}, server
    server.activeNPCs[1].relationship = 90
    local next1 = server:publishSnapshot()
    local page1 = NPCPersonRoster.pageOf(next1, 1)
    local page1b = NPCPersonRoster.pageOf(next1, 1)
    page1b.records = {}
    for i, rec in ipairs(page1.records) do local c = {} for k, v in pairs(rec) do c[k] = v end page1b.records[i] = c end
    page1b.records[1].name = "changed same-ID payload"
    deliver(page1)
    deliver(page1b)
    T.eq("C23 a conflicting duplicate page cannot publish", client.people.publishedSequence, 2)
    deliver(NPCPersonRoster.pageOf(next1, 2))
    T.eq("C24 the invalidated snapshot stays unpublished even when its pages are all there", client.people.publishedSequence, 2)
    T.eq("C25 the last-confirmed trust is kept (not the conflicting page's)", client:getNPCById(1).relationship, 33)

    -- A newer complete snapshot (48 people now waiting: still records, no bodies)
    -- replaces everything; an older one cannot undo it.
    g_server, g_NPCSystem = {}, server
    for i = 4, 51 do server:setPersonLive(server.people:getPerson(i), false, "npc_person_waiting_count") end
    local smaller = server:publishSnapshot()
    T.eq("C25b waiting people stay in the snapshot", smaller.total .. "/" .. smaller.pageCount, "51/2")
    deliver(NPCPersonRoster.pageOf(smaller, 1))
    T.eq("C25c half of it published nothing", client.people.publishedSequence, 2)
    deliver(NPCPersonRoster.pageOf(smaller, 2))
    T.eq("C26 the newer complete snapshot publishes", client.people.publishedSequence, smaller.sequence)
    T.eq("C27 people the snapshot no longer carries live lose their bodies", #client.activeNPCs .. "/" .. #client.entityManager.removed, "3/48")
    T.eq("C28 waiting people are display rows, not bodies", #client:getNeighbourRosterView().rows, 51)
    deliver(NPCPersonRoster.pageOf(big, 1))
    deliver(NPCPersonRoster.pageOf(big, 2))
    T.eq("C29 an older snapshot cannot replace the newer one", client.people.publishedSequence .. "/" .. #client.activeNPCs, smaller.sequence .. "/3")

    -- A complete snapshot with no live person removes every body; the people are still listed.
    g_server, g_NPCSystem = {}, server
    for i = 1, 3 do server:setPersonLive(server.people:getPerson(i), false, "npc_person_waiting_count") end
    local empty = server:publishSnapshot()
    deliver(NPCPersonRoster.pageOf(empty, 1))
    deliver(NPCPersonRoster.pageOf(empty, 2))
    T.eq("C30 a complete zero-body snapshot is authoritative", client.people.publishedSequence .. "/" .. #client.activeNPCs, empty.sequence .. "/0")

    -- The server refuses to publish more than 4096 records; nothing saved is dropped.
    g_server, g_NPCSystem = {}, server
    for i = 52, 4098 do server.people:addPerson({ id = i, personKind = "durable", name = "R" .. i, live = false, position = { x = 0, y = 0, z = 0 } }) end
    local tooBig = server:publishSnapshot()
    T.eq("C31 over 4096 records: the snapshot is unavailable, with a reason", tostring(tooBig.unavailable) .. "/" .. tooBig.reasonKey, "true/npc_person_snapshot_too_large")
    T.eq("C32 over 4096 records: no saved record was dropped", server.people:count(), 4098)
    deliver(NPCPersonRoster.pageOf(tooBig, 1))
    T.eq("C33 the client keeps its last-confirmed roster and reports UNAVAILABLE", client.people.publishedSequence .. "/" .. client:getNeighbourRosterView().snapshotState, empty.sequence .. "/UNAVAILABLE")
    T.eq("C34 the page count bound is 82 for 4096", NPCPersonRoster.pageCountFor(4096), 82)
    local claim = NPCPersonRoster.pageOf(big, 1)
    claim.sequence, claim.total, claim.pageCount = 99, 4097, 82
    T.eq("C35 a page claiming more than 4096 records is rejected", client.people:receivePage(claim), "rejected")
    g_server, g_NPCSystem = {}, server
end

-- =========================================================
-- B: the server sends every page, an empty roster included
-- =========================================================
do
    local sent = {}
    local sys = boot({ placeables = {}, maxNPCs = 0, dir = "b1" })
    g_server = { broadcastEvent = function(_, ev) sent[#sent + 1] = ev end }
    NPCStateSyncEvent.broadcastState()
    T.eq("B1 an initialized empty roster is one complete zero-row snapshot, sent", #sent .. "/" .. sent[1].page.total .. "/" .. sent[1].page.pageCount, "1/0/1")
    sys.settings.maxNPCs = 16
    for i = 1, 51 do
        local npc = sys:createNPCAtLocation({ x = i, y = 0, z = i })
        npc.name = "B" .. i
        sys:initializeNPCData(npc, { x = i, y = 0, z = i }, npc.id)
        sys.people:addPerson(npc)
        sys:setPersonLive(npc, true)
    end
    sent = {}
    NPCStateSyncEvent.broadcastState()
    T.eq("B2 51 people go out as two pages of one sequence", #sent .. "/" .. sent[1].page.sequence .. "/" .. sent[2].page.sequence .. "/" .. #sent[2].page.records, "2/2/2/1")
    local pushed = {}
    NPCStateSyncEvent.sendToConnection({ sendEvent = function(_, ev) pushed[#pushed + 1] = ev end })
    T.eq("B3 the join push sends every page too, with the next sequence", #pushed .. "/" .. pushed[1].page.sequence, "2/3")
    g_server = {}
end

-- =========================================================
-- N: the NetworkSync FULL array
-- =========================================================
do
    local placeables = town(3)
    local server = boot({ placeables = placeables, maxNPCs = 2, dir = "n1" })
    local snapshot = server:publishSnapshot()
    local arr = NPCNetworkSyncBridge.serialize(snapshot)
    T.eq("N1 the array is header + 21 per record + trailer", #arr, 6 + 2 * 21 + 2)
    local back, why = NPCNetworkSyncBridge.deserialize(arr)
    T.ok("N2 a complete valid array deserializes", back ~= nil, why)
    T.eq("N3 with the same sequence and records", back.sequence .. "/" .. #back.records, snapshot.sequence .. "/2")
    local stale = {} for i, v in ipairs(arr) do stale[i] = v end
    stale[6 + 21 + 1] = snapshot.sequence - 1
    T.eq("N4 a stale per-record stamp is refused", select(2, NPCNetworkSyncBridge.deserialize(stale)), "stale_stamp")
    local trailer = {} for i, v in ipairs(arr) do trailer[i] = v end
    trailer[#trailer] = 1
    T.eq("N5 a mismatched trailer is refused", select(2, NPCNetworkSyncBridge.deserialize(trailer)), "bad_trailer")
    local short = {} for i = 1, #arr - 21 do short[i] = arr[i] end
    short[4] = 2
    T.eq("N6 a missing record is refused", select(2, NPCNetworkSyncBridge.deserialize(short)), "length_mismatch")
    local dup = {} for i, v in ipairs(arr) do dup[i] = v end
    dup[6 + 21 + 4] = dup[6 + 4]
    T.eq("N7 a duplicate id is refused", select(2, NPCNetworkSyncBridge.deserialize(dup)), "bad_id")

    -- The client applies a valid array through the same atomic apply, and the
    -- own-event page of the same sequence is then an idempotent duplicate.
    local client = boot({ placeables = placeables, maxNPCs = 2, dir = "n1", server = false })
    g_server, g_NPCSystem = nil, client
    NPCNetworkSyncBridge._onReadState(arr)
    T.eq("N8 the client published the array", client.people.publishedSequence .. "/" .. #client.activeNPCs, snapshot.sequence .. "/2")
    local ev = NPCStateSyncEvent.new(NPCPersonRoster.pageOf(snapshot, 1))
    local s = _sfMockStream()
    ev:writeStream(s, nil)
    NPCStateSyncEvent.emptyNew():readStream(s, nil)
    T.eq("N9 the same sequence through the own event is a duplicate, not a second town", client.people.publishedSequence .. "/" .. #client.activeNPCs, snapshot.sequence .. "/2")
    NPCNetworkSyncBridge._onReadState(stale)
    T.eq("N10 a refused array marks the client unavailable and keeps the roster", client:getNeighbourRosterView().snapshotState .. "/" .. #client.activeNPCs, "UNAVAILABLE/2")
    g_server, g_NPCSystem = {}, server
end

-- =========================================================
-- F: field work keys by durable number; the AI gate
-- =========================================================
do
    local sys = boot({ placeables = town(3), maxNPCs = 2, dir = "f1" })
    local a, b = sys.activeNPCs[1], sys.activeNPCs[2]
    a.legacyUniqueId, b.legacyUniqueId = "same_legacy_text", "same_legacy_text"
    a.uniqueId, b.uniqueId = "same_legacy_text", "same_legacy_text"
    local field = { id = 7, center = { x = 100, z = 100 }, size = 20000 }   -- large: two workers admitted
    math.randomseed(1)
    local origRandom = math.random
    local function fixedRoll(n, m)
        if n == 100 and m == nil then return 50 end
        if n == nil then return origRandom() end
        if m == nil then return origRandom(n) end
        return origRandom(n, m)
    end
    math.random = fixedRoll
    local _, slotA = sys.fieldWork:getWorkPattern(a, field)
    local _, slotB = sys.fieldWork:getWorkPattern(b, field)
    math.random = origRandom
    T.eq("F1 two people with one legacy text key reserve separately", tostring(slotA) .. "/" .. tostring(slotB), "1/2")
    T.eq("F2 the registry holds their numbers, not the text", join(sys.fieldWork.activeWorkers["7"]), "1,2")
    -- Release through the AI's own release path: A's release keeps B's slot.
    sys.aiSystem:_releaseFieldWorkSlot(a)
    T.eq("F3 releasing A keeps B's reservation", join(sys.fieldWork.activeWorkers["7"]), "2")
    -- The work-timer break releases by number too.
    b.aiState, b.workTimer, b.personality = "working", 10000, "lazy"
    math.random = function() return 0.1 end
    sys.aiSystem:updateWorkingState(b, 1)
    math.random = origRandom
    T.eq("F4 the work-timer break released B's own slot", sys.fieldWork.activeWorkers["7"], nil)
    -- A presence and an unnumbered row get no slot; the AI gate refuses them.
    T.eq("F5 a row without a durable number gets no slot", (sys.fieldWork:getWorkPattern({ name = "ghost", personality = "hardworking" }, field)), nil)
    local presence = sys.people:upsertPresence("HELPER1", { name = "Worker 1", x = 1, y = 0, z = 1 })
    presence.assignedField = field
    sys.aiSystem:initFieldWork(presence)
    T.eq("F6 a presence does no field work (no slot, no path)", tostring(presence.fieldWorkPath) .. "/" .. tostring(sys.fieldWork.activeWorkers["7"]), "nil/nil")
    sys:setPersonLive(a, false, "npc_person_waiting_count")
    a.assignedField = field
    sys.aiSystem:initFieldWork(a)
    T.eq("F7 a waiting person does no field work either, and no legacy fallback runs", tostring(a.fieldWorkPath), "nil")
    -- The waiting transition released her own slot and nothing else.
    sys:setPersonLive(b, true)
    math.random = fixedRoll
    sys.fieldWork:getWorkPattern(b, field)
    math.random = origRandom
    sys:setPersonLive(b, false, "npc_person_waiting_count")
    T.eq("F8 the waiting transition releases her own reservation", sys.fieldWork.activeWorkers["7"], nil)
    T.eq("F9 and her body is gone while she stays in the roster", tostring(sys.entityManager.npcEntities[b.id]) .. "/" .. sys.people:count(), "nil/2")
    T.eq("F9b she left the live view", #sys.activeNPCs, 0)
    -- Accepted work of a person going waiting pauses; it resumes only to her, once live.
    sys:setPersonLive(b, true)
    local fav = sys.favorSystem:createFavor(b, "fix_fence")
    table.insert(sys.favorSystem.activeFavors, fav)
    sys.favorSystem:acceptFavorForNPC(b.id, 1)
    sys:setPersonLive(b, false, "npc_person_waiting_count")
    T.eq("F10 her accepted work paused as neighbour_unavailable", #sys.favorSystem.activeFavors .. "/" .. fav.recoveryReason, "0/neighbour_unavailable")
    T.eq("F11 with its status and time preserved", fav.originalStatus .. "/" .. tostring(fav.timeRemaining > 0), "active/true")
    T.eq("F12 it is not actionable while she waits", sys.favorSystem:isRecoveryRecordActionable(fav), false)
    T.eq("F13 the unavailable key says she waits", sys.favorSystem:getRecoveryUnavailableKey(fav), "npc_recovery_unavail_waiting")
    sys:setPersonLive(b, true)
    T.eq("F14 once she is live the owning farm's resume route is open", sys.favorSystem:isRecoveryRecordActionable(fav) and fav.resumable, true)
    T.eq("F15 resume brings the same job back to the same person", sys.favorSystem:resumeRecoveryRecord(fav, 1) and sys.favorSystem.activeFavors[1] == fav, true)
end

-- =========================================================
-- P: worker presences
-- =========================================================
do
    MODS["FS25_ContractorMod"] = { name = "FS25_ContractorMod" }
    NODES[501] = { x = 10, y = 0, z = 20 }
    g_npcManager = { nameToNPC = { HELPER1 = { rootNode = 501 } } }
    local sys = boot({ placeables = town(3), maxNPCs = 2, dir = "p1" })
    T.eq("P1 a worker slot is a presence with an allocator number, after the people are READY", sys.people:count() .. "/" .. #sys.people.presenceOrder .. "/" .. sys.people.presences["HELPER1"].id, "2/1/3")
    T.eq("P2 a presence never enters activeNPCs", #sys.activeNPCs, 2)
    local presence = sys.people.presences["HELPER1"]
    T.eq("P3 a presence has no trust value", presence.relationship, nil)
    T.ok("P4 a presence is not actionable", not sys:isPersonActionable(presence))
    T.eq("P5 trust cannot be written to a presence", sys.relationshipManager:updateRelationship(presence.id, 5, "contractor_greeting"), false)
    T.eq("P6 a gift to a presence is refused and costs nothing", sys:serverGiveGift(presence, 1, 100, "money"), false)
    T.eq("P7 a favour for a presence is refused", sys.favorSystem:generateFavorForNPC(presence, true), nil)
    local view = sys:getNeighbourRosterView()
    T.eq("P8 the roster view shows it as PRESENCE with its position and no trust", view.rows[3].kind .. "/" .. tostring(view.rows[3].trust) .. "/" .. tostring(view.rows[3].position ~= nil), "PRESENCE/nil/true")
    sys:saveToXMLFile(g_currentMission.missionInfo)
    T.eq("P9 a presence is never saved; the high-water mark it drew is", fileAt("p1")["npcFavor.npcs.npc(2)#id"] == nil and fileAt("p1")["npcFavor#personIdHighWater"] == 3, true)
    -- Unreadable list: last-observed positions unavailable, nothing removed.
    g_npcManager.nameToNPC = nil
    sys.contractorBridge:syncWorkers()
    T.eq("P10 an unreadable list marks the presence unavailable and keeps it", tostring(presence.unavailable) .. "/" .. #sys.people.presenceOrder, "true/1")
    T.eq("P11 an unavailable presence shows no position", sys:getNeighbourRosterView().rows[3].position, nil)
    -- Readable again, slot reused: the same presence, the same number.
    g_npcManager.nameToNPC = { HELPER1 = { rootNode = 501 } }
    sys.contractorBridge:syncWorkers()
    T.eq("P12 a reused slot updates the same presence", sys.people.presences["HELPER1"].id .. "/" .. tostring(sys.people.presences["HELPER1"].unavailable), "3/false")
    -- Readable and empty: the presence is removed; retained people are untouched.
    g_npcManager.nameToNPC = {}
    sys.contractorBridge:syncWorkers()
    T.eq("P13 a readable empty list removes the presence", #sys.people.presenceOrder, 0)
    T.eq("P14 and touches no retained person", sys.people:count() .. "/" .. #sys.activeNPCs, "2/2")
    MODS["FS25_ContractorMod"] = nil
    g_npcManager = nil
end

-- =========================================================
-- K: the consultant claim (host half of section 7)
-- =========================================================
do
    local placeables = town(3)
    local sys = boot({ placeables = placeables, maxNPCs = 2, dir = "k1" })
    T.eq("K1 the capability version is published", NPCSystem.savedNeighbourIdentityVersion, 1)
    T.eq("K2 no consultant yet: the getter is nil with a reason", select(2, sys:getCropStressConsultantId()), "npc_person_consultant_absent")
    local id = sys:claimCropStressConsultant("Alex Chen", { x = 5, y = 0, z = 5 })
    T.eq("K3 the claim creates one consultant through the normal path, numbered by the allocator", id, 3)
    local alex = sys:getNPCById(3)
    T.eq("K4 origin consultant, the fixed token, live, actionable", alex.origin .. "/" .. alex.providerToken .. "/" .. tostring(sys:isPersonActionable(alex)), "consultant/cs_alex_chen/true")
    T.ok("K5 normal starting trust, not a caller value", alex.relationship >= 5 and alex.relationship <= 35)
    T.eq("K6 the getter returns her number", sys:getCropStressConsultantId(), 3)
    T.eq("K7 a second claim returns the same person", sys:claimCropStressConsultant("Alex Chen", { x = 9, y = 0, z = 9 }), 3)
    T.eq("K8 the consultant does not count against the town", #sys.activeNPCs, 3)
    T.eq("K9 a bad position is refused", (sys:claimCropStressConsultant("Alex Chen", { x = 0 / 0, z = 1 })), nil)
    alex.relationship = 42
    sys:saveToXMLFile(g_currentMission.missionInfo)
    T.eq("K10 the provider token is saved on her row", fileAt("k1")["npcFavor.npcs.npc(2)#providerToken"], "cs_alex_chen")
    -- Reload: she waits for the companion claim, keeps her trust, and wakes as the same person.
    local re = boot({ placeables = placeables, maxNPCs = 2, dir = "k1" })
    local waiting = re:resolveRetainedPerson(3)
    T.eq("K11 reload: the saved consultant waits for her companion", waiting.live == false and waiting.waitingReason or "live", "npc_person_waiting_companion")
    T.eq("K12 reload: the getter is nil while she waits", select(2, re:getCropStressConsultantId()), "npc_person_waiting_companion")
    T.eq("K13 reload: the town did not wait for her", #re.activeNPCs, 2)
    T.eq("K14 reload: the claim wakes the same person", re:claimCropStressConsultant("Alex Chen", { x = 1, y = 0, z = 1 }), 3)
    T.eq("K15 reload: with her saved trust, no caller floor", re:getNPCById(3).relationship, 42)
    -- Two saved rows with the token: conflict, no lower-id winner, both kept.
    local f = fileAt("k1")
    f["npcFavor.npcs.npc(1)#providerToken"] = "cs_alex_chen"
    local dup = boot({ placeables = placeables, maxNPCs = 2, dir = "k1" })
    local got, why = dup:claimCropStressConsultant("Alex Chen", { x = 1, y = 0, z = 1 })
    T.eq("K16 a duplicate provider claim returns nil with the conflict reason", tostring(got) .. "/" .. why, "nil/npc_person_identity_conflict")
    T.eq("K17 both rows are kept", dup.people:count(), 3)
    T.eq("K18 the getter reports the conflict", select(2, dup:getCropStressConsultantId()), "npc_person_identity_conflict")
    -- A pure client reads the getter only from a complete roster.
    local client = boot({ placeables = placeables, maxNPCs = 2, dir = "k1", server = false })
    T.eq("K19 client: nil before a complete roster", select(2, client:getCropStressConsultantId()), "npc_person_loading")
    g_server, g_NPCSystem = {}, re
    local snapshot = re:publishSnapshot()
    g_server, g_NPCSystem = nil, client
    client.people:receivePage(NPCPersonRoster.pageOf(snapshot, 1))
    T.eq("K20 client: the unique live consultant's number from the published roster", client:getCropStressConsultantId(), 3)
    g_server, g_NPCSystem = {}, re
end

-- =========================================================
-- M: the name pool skips retained names
-- =========================================================
do
    local placeables = town(3)
    local sys = boot({ placeables = placeables, maxNPCs = 2, dir = "m1" })
    local n1, n2 = sys.activeNPCs[1].name, sys.activeNPCs[2].name
    sys:saveToXMLFile(g_currentMission.missionInfo)
    -- Reload with the count raised by one and the first two waiting is not possible
    -- (they return first), so retain them as non-town rows instead: origin outside
    -- without the town grammar keeps them waiting, and the two newcomers must not
    -- take their names.
    local f = fileAt("m1")
    f["npcFavor.npcs.npc(0)#origin"], f["npcFavor.npcs.npc(1)#origin"] = "outside", "outside"
    local re = boot({ placeables = placeables, maxNPCs = 2, dir = "m1" })
    T.eq("M1 the retained rows wait (kept from before)", personById(re, 1).waitingReason .. "/" .. personById(re, 2).waitingReason, "npc_person_kept_legacy/npc_person_kept_legacy")
    local got = names(re.activeNPCs)
    T.eq("M2 two newcomers filled the count", #re.activeNPCs, 2)
    T.eq("M2b their numbers came from the allocator, above the retained ones, never from the array length", join(ids(re.activeNPCs)), "3,4")
    T.ok("M3 neither newcomer took a retained name", not got[n1] and not got[n2])
    -- Both pools retained: places stay empty with one reason, no namesake.
    local dir = "m2"
    local s2 = boot({ placeables = placeables, maxNPCs = 2, dir = dir })
    s2:saveToXMLFile(g_currentMission.missionInfo)
    local ff = fileAt(dir)
    local i = 0
    for _, name in ipairs(s2.maleNames) do
        ff["npcFavor.npcs.npc(" .. i .. ")#id"] = 100 + i
        ff["npcFavor.npcs.npc(" .. i .. ")#name"] = name
        ff["npcFavor.npcs.npc(" .. i .. ")#origin"] = "outside"
        i = i + 1
    end
    for _, name in ipairs(s2.femaleNames) do
        ff["npcFavor.npcs.npc(" .. i .. ")#id"] = 100 + i
        ff["npcFavor.npcs.npc(" .. i .. ")#name"] = name
        ff["npcFavor.npcs.npc(" .. i .. ")#origin"] = "outside"
        i = i + 1
    end
    ff["npcFavor#personIdHighWater"] = 200
    local ex = boot({ placeables = placeables, maxNPCs = 2, dir = dir })
    T.eq("M4 every name retained: the places stay empty", #ex.activeNPCs, 0)
    T.eq("M5 the retained rows are all there", ex.people:count(), 24)
    T.eq("M6 the exhaustion was logged once", ex.people.namesExhaustedLogged, true)
    T.eq("M7 the mark was not moved by the refusals", ex.people:getHighWater(), 200)
end

-- =========================================================
-- T: ties and serializer gates
-- =========================================================
do
    local placeables = town(3)
    local sys = boot({ placeables = placeables, maxNPCs = 3, dir = "t1" })
    sys.relationshipManager:updateNPCNPCRelationship(sys.activeNPCs[1], sys.activeNPCs[2], "work")
    sys:saveToXMLFile(g_currentMission.missionInfo)
    local f = fileAt("t1")
    -- A legacy tie (no mark) beside it.
    f["npcFavor.npcRelationships.rel(1)#key"] = "2:3"
    f["npcFavor.npcRelationships.rel(1)#value"] = 88
    f["npcFavor.npcRelationships.rel(1)#lastInteraction"] = 0
    f["npcFavor.npcRelationships.rel(1)#interactionCount"] = 4
    local re = boot({ placeables = placeables, maxNPCs = 3, dir = "t1" })
    T.eq("T1 the marked tie reconnects", re.relationshipManager.npcRelationships["1:2"] ~= nil, true)
    T.eq("T2 the legacy tie does not enter the pair graph", re.relationshipManager.npcRelationships["2:3"], nil)
    T.eq("T3 it is retained as evidence", #re.people.legacyTies, 1)
    re:saveToXMLFile(g_currentMission.missionInfo)
    local g = fileAt("t1")
    T.eq("T4 the legacy tie is re-emitted without the mark", g["npcFavor.npcRelationships.rel(1)#key"] .. "/" .. tostring(g["npcFavor.npcRelationships.rel(1)#endpointKind"]), "2:3/nil")
    T.eq("T5 the reconnected tie is re-emitted with it", g["npcFavor.npcRelationships.rel(0)#endpointKind"], "durable")

    -- Serializer gates: an empty roster with an allocated mark persists; so does a
    -- waiting-only roster; FAILED writes nothing.
    local dir = "t2"
    local e = boot({ placeables = {}, maxNPCs = 0, dir = dir })
    T.eq("T6 count 0: nobody is live", #e.activeNPCs, 0)
    e.people:allocateId()
    e:saveToXMLFile(g_currentMission.missionInfo)
    T.eq("T7 an empty roster with an allocated mark is saved (npcCount 0 is not a gate)", fileAt(dir)["npcFavor#personIdHighWater"], 1)
    local w = boot({ placeables = town(2), maxNPCs = 2, dir = "t3" })
    w:saveToXMLFile(g_currentMission.missionInfo)
    local w0 = boot({ placeables = town(2), maxNPCs = 0, dir = "t3" })
    T.eq("T8 count 0 on reload: everybody waits", w0.people:count() .. "/" .. #w0.activeNPCs, "2/0")
    w0:saveToXMLFile(g_currentMission.missionInfo)
    T.eq("T9 a waiting-only roster persists", fileAt("t3")["npcFavor.npcs.npc(1)#id"], 2)
    local state = w0:serializeState()
    T.eq("T10 the ledger table carries both waiting people and the mark", #state.npcs .. "/" .. state.personIdHighWater, "2/2")
end

-- =========================================================
-- D: reset, exhaustion, teardown
-- =========================================================
do
    local placeables = town(3)
    local sys = boot({ placeables = placeables, maxNPCs = 2, dir = "d1" })
    sys:saveToXMLFile(g_currentMission.missionInfo)
    sys.people:allocateId()   -- a number issued after the save (a presence, say)
    sys:consoleCommandReset()
    tick(sys)
    T.eq("D1 the developer reset ends the old town and starts one controlled load", sys.people:getLoadState() .. "/" .. #sys.activeNPCs, "READY/2")
    T.eq("D2 the mark was never lowered, not even to the saved one", sys.people:getHighWater(), 3)
    T.eq("D3 the same numbers came back", join(ids(sys.activeNPCs)), "1,2")
    local seqBefore = sys.people.snapshotSequence
    sys:publishSnapshot()
    T.ok("D4 the snapshot sequence keeps increasing across the reset", sys.people.snapshotSequence > seqBefore)
    -- Exhaustion refuses creation, never wraps, existing people stay usable.
    sys.people.highWater = NPCPersonRoster.MAX_ID
    local id, why = sys.people:allocateId()
    T.eq("D5 exhaustion refuses before incrementing", tostring(id) .. "/" .. why .. "/" .. sys.people:getHighWater(), "nil/npc_person_exhausted/" .. NPCPersonRoster.MAX_ID)
    sys.settings.maxNPCs = 5   -- room under the count, so the allocator is what refuses
    T.eq("D6 the console creator refuses with the reason", sys:consoleCommandSpawn("Late"):match("exhausted") ~= nil, true)
    T.eq("D6b the refusal created nobody", #sys.activeNPCs .. "/" .. sys.people:count(), "2/2")
    T.ok("D7 existing people remain usable", sys:isPersonActionable(sys.activeNPCs[1]))
    T.ok("D8 the ceiling is a valid number and the next is not", NPCPersonRoster.validId(NPCPersonRoster.MAX_ID) and not NPCPersonRoster.validId(NPCPersonRoster.MAX_ID + 1))
    -- Mission teardown clears the population, the reservations and the receive state.
    sys.fieldWork.activeWorkers["9"] = { 1 }
    sys:delete()
    T.eq("D9 delete clears the roster, the reservations and the mark", sys.people:count() .. "/" .. tostring(next(sys.fieldWork.activeWorkers)) .. "/" .. sys.people:getHighWater(), "0/nil/0")
    T.eq("D10 delete clears the live view", #sys.activeNPCs, 0)
end
