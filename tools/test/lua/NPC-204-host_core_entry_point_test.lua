-- NPC-204 host core: companion neighbours and one simple contributed job.
--!load: src/utils/NPCFarmIdentity.lua, src/utils/NPCReleaseGate.lua, src/settings/NPCSettings.lua, src/scripts/NPCPersonRoster.lua, src/scripts/NPCRelationshipManager.lua, src/scripts/NPCFavorSystem.lua, src/scripts/NPCFavorRecovery.lua, src/scripts/NPCCompanionContribution.lua, src/scripts/NPCFieldWork.lua, src/scripts/NPCAI.lua, src/scripts/ContractorModBridge.lua, src/scripts/NPCInteractionUI.lua, src/events/NPCStateSyncEvent.lua, src/events/NPCInteractionEvent.lua, src/events/NPCPersonDialogEvents.lua, src/integrations/NPCStateLedgerBridge.lua, src/integrations/NPCNetworkSyncBridge.lua, src/NPCSystem.lua, src/scripts/NPCPersonDialog.lua, src/gui/NPCDialog.lua, src/gui/NPCListDialog.lua, src/gui/NPCAdminEditDialog.lua, src/gui/NPCFavorManagementDialog.lua, src/scripts/NPCFavorHUD.lua, src/settings/NPCFavorGUI.lua
--
-- THE ENTRY-POINT BAR. A test caller binds to NPCFavor only through the
-- published mission handle, g_currentMission.npcFavorSystem (main.lua:227,
-- :275), exactly as a companion mod would, and registers, claims, declares,
-- offers and reports through the real verbs on the real NPCSystem. The farmer
-- side enters where production enters it: NPCInteractionEvent on a typed mock
-- stream from a remote connection (readStream, run, the actor resolved from
-- the connection, the request gate, the face-to-face distance), and the
-- person dialog request events. The work surface is opened and locked by the
-- player's own persisted setting, settings.experimentalSystems, read through
-- the real NPCReleaseGate predicate on the favour system's own tick. Both
-- systems boot through NPCSystem.new, onMissionLoaded and the first-frame
-- init updater (the town comes from the fixture's houses). Nothing hand-fills
-- a provider, a person, a kind, a favour, a token or a revision: the code
-- under test obtains them all. The world supplies only what a player or the
-- engine supplies: a loaded-mod table, positions, trust and a cooldown value.
--
-- What this proves: the host core contract, offline. What it does not: native
-- transport, the Recovery door and LET_GO (the Recovery slice), save and load
-- of companion work (the persistence slice), the work page and dialog views
-- and locale text (the views slice), GUI rendering, frame cost.

-- =========================================================
-- World
-- =========================================================
TimeHelper = { getGameTimeMs = function() return (g_currentMission and g_currentMission.time) or 0 end }
VectorHelper = VectorHelper or { distance2D = function(x1, z1, x2, z2) local dx, dz = x1 - x2, z1 - z2 return math.sqrt(dx * dx + dz * dz) end }
FarmManager = { SPECTATOR_FARM_ID = 0, SINGLEPLAYER_FARM_ID = 1, MAX_FARM_ID = 8, GUIDED_TOUR_FARM_ID = 14, INVALID_FARM_ID = 15 }
local LIVE_FARMS = {
    [1] = { farmId = 1, name = "Farm 1", money = 100000 },
    [2] = { farmId = 2, name = "Farm 2", money = 100000 },
    [3] = { farmId = 3, name = "Farm 3", money = 0 },
}
g_farmManager = {
    getFarmById = function(_, id) return LIVE_FARMS[id] end,
    getFarms = function(_) local l = {} for _, f in pairs(LIVE_FARMS) do l[#l + 1] = f end table.sort(l, function(a, b) return a.farmId < b.farmId end) return l end,
}
g_modManager = { getModByName = function() return nil end }
addConsoleCommand = function() end
g_i18n = { getText = function(_, key) return key end, hasText = function() return false end }
NPCTeleport = { teleportToNPC = function(_, npc) NPCTeleport.last = npc.id return true, "teleported to " .. npc.id end }

-- Nodes: world positions by node id.
local NODES = {}
function getWorldTranslation(node)
    local p = NODES[node]
    if p == nil then return 0, 0, 0 end
    return p.x, p.y, p.z
end
function getTerrainHeightAtWorldPos(_, x, _y, z) return 5 end

-- Subsystems NPCSystem.new instantiates that are not under test here. The
-- HUD class stays real (its work-page reader is under test); only the
-- constructor the boot calls is replaced.
NPCEntity = { new = function(sys)
    return {
        npcSystem = sys, npcEntities = {}, created = {}, removed = {},
        initialize = function() end,
        createNPCEntity = function(self, npc) self.npcEntities[npc.id] = { npcId = npc.id } self.created[#self.created + 1] = npc.id return true end,
        removeNPCEntity = function(self, npc) if self.npcEntities[npc.id] then self.npcEntities[npc.id] = nil self.removed[#self.removed + 1] = npc.id end end,
        updateNPCEntity = function() end,
        drawMapLabels = function() end,
    }
end }
NPCScheduler = { new = function()
    return { getCurrentHour = function() return 12 end, getCurrentMinute = function() return 0 end,
        getCurrentDay = function() return 1 end, getWeatherFactor = function() return 1 end,
        update = function() end, scheduledNPCInteractions = {} }
end }
-- The interaction UI's topic chooser is the real one (the module is loaded); only the
-- constructor the boot calls is replaced, and it hands the real chooser to the object.
local realTopicKey, realTopic = NPCInteractionUI.getRandomConversationTopicKey, NPCInteractionUI.getRandomConversationTopic
NPCInteractionUI.new = function(sys) return { npcSystem = sys, update = function() end, delete = function() end, updateFavorList = function() end,
    getRandomConversationTopicKey = realTopicKey, getRandomConversationTopic = realTopic } end
NPCFavorHUD.new = function(sys) return { npcSystem = sys, loadFromSettings = function() end, flashFavor = function() end, update = function() end, delete = function() end } end
NPCSettingsIntegration = { new = function() return { initialize = function() end } end }
NPCSettingsPanel = { new = function() return { initialize = function() end, update = function() end, delete = function() end } end }

-- In-memory XML file store.
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
XMLFile = {
    create = function(_, path, _root) local m = xmlMock({}) m.path = path return m end,
    loadIfExists = function(_, path, _root)
        local store = DISK[path]
        if store == nil then return nil end
        local copy = {}
        for k, v in pairs(store) do copy[k] = v end
        local m = xmlMock(copy) m.path = path
        return m
    end,
}

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

-- Connections, users, players and farms of the remote world.
local USERS, CONN_FARM, PLAYERS = {}, {}, {}
local MONEY = {}          -- addMoney ledger by farm
local BROADCASTS = 0
local function newConnection(name, userId, farmId)
    local c = { name = name, sent = {} }
    c.sendEvent = function(self, ev) self.sent[#self.sent + 1] = ev end
    USERS[c] = { getId = function() return userId end, getIsMasterUser = function() return false end }
    CONN_FARM[c] = farmId
    return c
end
local function standAt(conn, x, z)
    PLAYERS[conn] = { getPosition = function() return x, 5, z end }
end
local HOST = { x = 0, z = 0 }
local function hostAt(x, z) HOST.x, HOST.z = x, z end
local function localPlayer() return { getPosition = function() return HOST.x, 5, HOST.z end } end

local function newMission(opts)
    local m = {
        time = 1000, environment = { currentDay = 1, daysPerPeriod = 1 },
        missionInfo = { savegameDirectory = opts.dir or "sg" },
        isMissionStarted = true, terrainRootNode = 1, terrainSize = 2048,
        placeableSystem = { placeables = opts.placeables or {} },
        updateables = {},
        addUpdateable = function(self, u) self.updateables[#self.updateables + 1] = u end,
        addIngameNotification = function() end,
        getIsServer = function() return g_server ~= nil end,
        userManager = { getUserByConnection = function(_, conn) return USERS[conn] end },
        playerSystem = { players = PLAYERS, getPlayerByConnection = function(_, conn) return PLAYERS[conn] end },
        addMoney = function(_, amount, farmId) MONEY[farmId] = (MONEY[farmId] or 0) + amount if LIVE_FARMS[farmId] then LIVE_FARMS[farmId].money = LIVE_FARMS[farmId].money + amount end end,
    }
    m.localFarmId = opts.localFarmId or 1
    m.getFarmId = function(self, conn)
        if conn == nil then return self.localFarmId end
        return CONN_FARM[conn]
    end
    return m
end
local function serverObject() return { broadcastEvent = function() BROADCASTS = BROADCASTS + 1 end } end

-- Boot through production's own entry point (NPCSystem.new, onMissionLoaded,
-- the captured first-frame updater). Returns the system and its mission.
local function boot(opts)
    opts = opts or {}
    g_server = (opts.server ~= false) and serverObject() or nil
    g_client = nil
    g_localPlayer = nil
    g_currentMission = newMission(opts)
    NPCStateLedgerBridge.active, NPCStateLedgerBridge.delivered, NPCStateLedgerBridge.pendingState = false, false, nil
    local sys = NPCSystem.new(g_currentMission, "mod/", "FS25_NPCFavor")
    g_NPCSystem = sys
    if opts.ledger then
        g_currentMission.stateLedger = opts.ledger
        NPCStateLedgerBridge.register()
    end
    sys:onMissionLoaded()
    sys.settings.maxNPCs = opts.maxNPCs or 3
    sys.settings.npcDriveVehicles = false
    sys.settings.enableFavors = false
    sys.settings.showNotifications = false
    sys.settings.debugMode = false
    sys._initResult = g_currentMission.updateables[1]:update(16)
    return sys, g_currentMission
end

-- Stub ledger: stores hooks, delivers its block on parse (or when told to).
local function newLedger(block, hold)
    local L = { modules = {}, block = block, hasParsed = false, hold = hold == true }
    function L:registerModule(name, hooks) self.modules[name] = hooks if self.hasParsed then hooks.deserialize(self.block) end return true end
    function L:parseFile() if self.hasParsed or self.hold then return end self:deliver() end
    function L:deliver() self.hasParsed = true for _, h in pairs(self.modules) do h.deserialize(self.block) end end
    return L
end

-- Two processes: the globals of one side at a time.
local SIDE = {}
local function useServer()
    g_server, g_client = SIDE.server.g_server, nil
    g_NPCSystem, g_currentMission = SIDE.server.sys, SIDE.server.mission
    g_localPlayer = SIDE.server.localPlayer
end
local OUTBOX = {}
local function useClient()
    g_server = nil
    g_client = { getServerConnection = function() return { sendEvent = function(_, ev) OUTBOX[#OUTBOX + 1] = ev end } end }
    g_NPCSystem, g_currentMission = SIDE.client.sys, SIDE.client.mission
    g_localPlayer = nil
end
local function advance(ms)
    if SIDE.server then SIDE.server.mission.time = SIDE.server.mission.time + ms end
    if SIDE.client then SIDE.client.mission.time = SIDE.client.mission.time + ms end
end

-- The typed stream: a received event is what readStream makes of it.
local FAULTS = 0
local function roundTrip(ev, connection)
    local s = _sfMockStream()
    ev:writeStream(s, nil)
    local rx = _G[ev.className].emptyNew()
    rx:readStream(s, connection)
    if s.typeErrors ~= 0 or s.underflows ~= 0 or (s.r - 1) ~= #s.q then FAULTS = FAULTS + 1 end
    return rx
end
-- The wire view of a reply without dispatching it anywhere.
local function decode(ev)
    local ss, sn, sc = g_server, g_NPCSystem, g_client
    g_server, g_NPCSystem, g_client = nil, nil, nil
    local rx = roundTrip(ev, nil)
    g_server, g_NPCSystem, g_client = ss, sn, sc
    return rx.reply
end
-- A remote request arriving at the server on `conn`: the decoded reply (or nil) and how many events went back.
local function request(conn, op, personId, requestId, cursor)
    useServer()
    local before = #conn.sent
    roundTrip(NPCPersonDialogRequestEvent.new({ requestId = requestId, op = op, personId = personId, cursor = cursor or "" }), conn)
    local n = #conn.sent - before
    return n == 1 and decode(conn.sent[#conn.sent]) or nil, n
end
local function workAction(conn, actionType, npcId, farmId, data, value)
    useServer()
    local before = #conn.sent
    roundTrip(NPCInteractionEvent.new(actionType, npcId, farmId, value or 0, data), conn)
    local n = #conn.sent - before
    return n == 1 and decode(conn.sent[#conn.sent]) or nil, n
end
local function sel(requestId, row) return requestId .. "|" .. row.token .. "|" .. row.recordRevision end
-- The client's queued requests reach the server on `conn`; its replies come back.
local function exchange(conn)
    local requests = OUTBOX
    OUTBOX = {}
    local replies = {}
    useServer()
    for _, ev in ipairs(requests) do
        local before = #conn.sent
        roundTrip(ev, conn)
        for i = before + 1, #conn.sent do replies[#replies + 1] = conn.sent[i] end
    end
    useClient()
    for _, ev in ipairs(replies) do roundTrip(ev, nil) end
    return #requests, #replies
end

-- Deterministic dice: no-argument rolls pop from the queue (then 0); ranged rolls return their floor.
local origRandom = math.random
local function dice(values)
    local i = 0
    math.random = function(a, b)
        if a == nil then i = i + 1 return values[i] or 0 end
        if b == nil then return 1 end
        return a
    end
end
local function realDice() math.random = origRandom end
-- The selection roll that lands on one favour type for this person and acting farm.
local function rollFor(fav, npc, typeId, farmId)
    local total, before, width = 0, nil, nil
    local cb = NPCFavorSystem.PERSONALITY_CATEGORY_WEIGHTS[npc.personality] or {}
    local rb = NPCFavorSystem.ROLE_CATEGORY_WEIGHTS[npc.role] or {}
    for _, ft in ipairs(fav.favorTypes) do
        if fav:checkFavorRequirements(npc, ft, farmId) then
            local w = 10 - ft.difficulty
            if cb[ft.category] then w = w * cb[ft.category] end
            if rb[ft.category] then w = w * rb[ft.category] end
            w = math.max(0.1, w)
            if ft.id == typeId then before, width = total, w end
            total = total + w
        end
    end
    if before == nil then return nil end
    return (before + width * 0.5) / total
end

local R = NPCPersonDialog
local IE = NPCInteractionEvent
local function el() local e = {} e.setText = function(self, t) self.text = t end e.setVisible = function(self, v) self.visible = v end e.setTextColor = function() end e.setImageColor = function() end return e end

-- A host with three people, one pure client READY from the host's snapshot,
-- two remote connections on farm 1 and one on farm 2.
local function world(opts)
    opts = opts or {}
    local placeables = town(opts.houses or 4)
    local server, sm = boot({ placeables = placeables, maxNPCs = opts.maxNPCs or 3, dir = opts.dir or "w" })
    SIDE.server = { sys = server, mission = sm, g_server = g_server, localPlayer = nil }
    for _, npc in ipairs(server.activeNPCs) do npc.personality = "friendly" npc.relationship = 30 end
    local client, cm = boot({ placeables = placeables, maxNPCs = opts.maxNPCs or 3, dir = opts.dir or "w", server = false, localFarmId = 1 })
    SIDE.client = { sys = client, mission = cm }
    useServer()
    local snapshot = server:publishSnapshot()
    local ev = NPCStateSyncEvent.new(NPCPersonRoster.pageOf(snapshot, 1))
    local s = _sfMockStream()
    ev:writeStream(s, nil)
    useClient()
    NPCStateSyncEvent.emptyNew():readStream(s, nil)
    local A = newConnection("A", 11, 1)
    local B = newConnection("B", 12, 1)
    local C = newConnection("C", 13, 2)
    useServer()
    return server, client, A, B, C
end

-- =========================================================
-- The companion: a test caller that binds only through the published handle
-- =========================================================
-- main.lua publishes the system as g_currentMission.npcFavorSystem (main.lua:227,
-- :275); the bench's boot does not run main.lua, so the one publishing line is
-- repeated here. Everything after it is what a companion mod would call.
g_modIsLoaded = { FS25_TestCompanion = true, FS25_OtherCompanion = true }
local NS, MOD = "test_companion", "FS25_TestCompanion"
local HOUR = 3600000
local function handle() return g_currentMission.npcFavorSystem end
local function publish(server) SIDE.server.mission.npcFavorSystem = server end
local function spec() return { namespace = NS, modName = MOD, apiVersion = 1 } end
local function water(over)
    local d = {
        kindKey = "emergency_water", version = 1, category = "fieldwork", difficulty = 1,
        offerHours = 12, workHours = 24, minTrust = 10,
        reward = { relationship = 6, money = 400 }, penalty = { relationship = -8 },
        addressing = "ADDRESSED", offeredPerson = "OWN_PERSON", targetKind = "FIELD",
        steps = { { kind = "REPORT", outcome = "irrigation_done" }, { kind = "TALK" } },
    }
    for k, v in pairs(over or {}) do d[k] = v end
    return d
end
local function claim(key, x, z) return handle():claimProviderPerson(NS, key, { displayName = "Alex " .. key, home = { x = x or 500, z = z or 500 } }) end
local function open(server) server.settings.experimentalSystems = true end
local function lock(server) server.settings.experimentalSystems = false end
local function tickFavours(server) useServer() server.favorSystem:update(16) end
local function offer(key, farmId, target)
    return handle():requestFavorOffer(NS, "emergency_water", { personKey = key, addressedFarmId = farmId, targetKey = target or "40" })
end
local function recordOf(server, id)
    local f = server.favorSystem:findContributedFavor(id)
    if f ~= nil then return f end
    for _, list in ipairs({ server.favorSystem.completedFavors, server.favorSystem.failedFavors, server.favorSystem.abandonedFavors }) do
        for _, g in ipairs(list) do if g.id == id then return g end end
    end
    return nil
end
local function inList(list, rec) for _, r in ipairs(list or {}) do if r == rec then return true end end return false end
local function rowFor(server, rec, conn)
    useServer()
    return server:describeWorkRow(rec, NPCFarmIdentity.resolveActor(conn))
end
local function moneyTotal(farmId) return MONEY[farmId] or 0 end
-- A prepared world: the companion registered, one kind declared, the surface
-- opened by the player's own setting, and one provider person claimed.
local function companionWorld(dir)
    local server, client, A, B, C = world({ dir = dir })
    publish(server)
    useServer()
    handle():registerCompanionProvider(spec())
    handle():registerFavorType(NS, water())
    local r = claim("alex")
    local person = server:getNPCById(r.personId)
    person.relationship = 30
    person.personality = "friendly"
    standAt(A, person.position.x, person.position.z)
    standAt(B, person.position.x, person.position.z)
    standAt(C, person.position.x, person.position.z)
    open(server)
    return server, client, A, B, C, person
end

-- =========================================================
-- P: provider registration (3.1)
-- =========================================================
;(function()
    local server, client, A = world({ dir = "np" })
    publish(server)
    useClient()
    local onClient = client:registerCompanionProvider(spec())
    T.eq("P1 on a client every verb answers REFUSED not_server", onClient.result .. "/" .. onClient.reason, "REFUSED/not_server")
    useServer()
    T.eq("P2 a namespace outside the grammar is refused", handle():registerCompanionProvider({ namespace = "AB", modName = MOD, apiVersion = 1 }).reason, "bad_namespace")
    T.eq("P3 an undeclared key is refused", handle():registerCompanionProvider({ namespace = NS, modName = MOD, apiVersion = 1, extra = 1 }).reason, "bad_spec")
    T.eq("P4 a mod not loaded this session is refused", handle():registerCompanionProvider({ namespace = NS, modName = "FS25_Absent", apiVersion = 1 }).reason, "mod_not_loaded")
    T.eq("P5 an API version other than 1 is refused", handle():registerCompanionProvider({ namespace = NS, modName = MOD, apiVersion = 2 }).reason, "api_version")
    local r = handle():registerCompanionProvider(spec())
    T.eq("P6 registration is READY with API version 1 and the surface LOCKED by default", r.result .. "/" .. r.reason .. "/" .. r.apiVersion .. "/" .. r.surface, "READY/registered/1/LOCKED")
    local again = handle():registerCompanionProvider(spec())
    T.eq("P7 an identical re-registration is idempotent", again.result .. "/" .. again.reason, "READY/already_registered")
    local taken = handle():registerCompanionProvider({ namespace = NS, modName = "FS25_OtherCompanion", apiVersion = 1 })
    T.eq("P8 another mod cannot take a namespace the first loaded mod owns", taken.result .. "/" .. taken.reason, "REFUSED/namespace_taken")
    T.eq("P9 unregistering an unknown provider answers NO_MATCH", handle():unregisterCompanionProvider("nobody_here").result, "NO_MATCH")
    T.ok("P10 no answer is ever a silent nil (a malformed call still answers)", type(handle():registerCompanionProvider(nil)) == "table")
end)()

-- =========================================================
-- Q: provider person (3.2)
-- =========================================================
;(function()
    local server = world({ dir = "nq" })
    publish(server)
    useServer()
    handle():registerCompanionProvider(spec())
    local before = server.people:count()
    local r = claim("alex")
    local person = server:getNPCById(r.personId)
    T.eq("Q1 a new provider person is created READY with a durable number", r.result .. "/" .. r.reason, "READY/created")
    T.ok("Q2 she is a live durable neighbour of this provider", person ~= nil and person.live == true and person.personKind == "durable"
        and person.origin == "provider" and person.providerToken == NS .. "/alex")
    T.eq("Q3 the roster grew by one", server.people:count(), before + 1)
    local again = claim("alex", 900, 900)
    T.eq("Q4 the same key claims the same person (position never identifies her)", again.result .. "/" .. again.reason .. "/" .. tostring(again.personId == r.personId), "READY/claimed/true")
    T.eq("Q5 and creates nobody", server.people:count(), before + 1)
    T.eq("Q6 claims stay available while the work surface is LOCKED", server.favorSystem:readCompanionSurface() .. "/" .. claim("alex").result, "LOCKED/READY")
    claim("bea") claim("cal") claim("dee")
    local fifth = claim("eve")
    T.eq("Q7 a fifth person for one provider is refused", fifth.result .. "/" .. fifth.reason, "REFUSED/person_limit")
    T.eq("Q8 a name over 64 bytes is refused", handle():claimProviderPerson(NS, "zed", { displayName = string.rep("n", 65), home = { x = 1, z = 1 } }).reason, "bad_name")
    T.eq("Q9 a non-finite home is refused", handle():claimProviderPerson(NS, "zed", { displayName = "Zed", home = { x = 0 / 0, z = 1 } }).reason, "bad_home")
    T.eq("Q10 and nothing was created by the refusals", server.people:count(), before + 4)
    local unknown = handle():claimProviderPerson("not_registered", "alex", { displayName = "X", home = { x = 1, z = 1 } })
    T.eq("Q11 an unregistered provider claims nobody", unknown.reason, "provider_unknown")

    -- Save, reload: the same number waits for her companion, and the claim wakes her.
    server:saveToXMLFile(g_currentMission.missionInfo)
    local re = boot({ placeables = town(4), maxNPCs = 3, dir = "nq" })
    local back = re.people:getPerson(r.personId)
    T.ok("Q12 after reload the provider person keeps her number, origin and token", back ~= nil and back.origin == "provider" and back.providerToken == NS .. "/alex")
    T.eq("Q13 and waits for her companion", tostring(back and back.live) .. "/" .. tostring(back and back.waitingReason), "false/" .. NPCPersonRoster.REASON_WAITING_COMPANION)
    re.mission = g_currentMission
    g_currentMission.npcFavorSystem = re
    re:registerCompanionProvider(spec())
    local woke = re:claimProviderPerson(NS, "alex", { displayName = "Someone Else", home = { x = 7, z = 7 } })
    T.eq("Q14 the claim after reload wakes the same number", woke.result .. "/" .. woke.reason .. "/" .. tostring(woke.personId == r.personId), "READY/claimed/true")
    T.ok("Q15 she is live again", back.live == true)
end)()

-- =========================================================
-- D: work declaration (3.3)
-- =========================================================
;(function()
    local server = world({ dir = "nd" })
    publish(server)
    useServer()
    T.eq("D1 an unregistered provider declares nothing", handle():registerFavorType(NS, water()).reason, "provider_unknown")
    handle():registerCompanionProvider(spec())
    local builtIn = #server.favorSystem.favorTypes
    local r = handle():registerFavorType(NS, water())
    T.eq("D2 a valid declaration is READY with the kind id", r.result .. "/" .. r.reason .. "/" .. r.kindId, "READY/declared/" .. NS .. ":emergency_water")
    T.eq("D3 an identical redeclaration is idempotent", handle():registerFavorType(NS, water()).reason, "already_declared")
    T.eq("D4 a changed redeclaration in the same mission is refused", handle():registerFavorType(NS, water({ reward = { relationship = 6, money = 401 } })).reason, "redeclared_changed")
    T.eq("D5 a reserved outcome cannot be declared", handle():registerFavorType(NS, water({ kindKey = "k2", steps = { { kind = "REPORT", outcome = "target_gone" }, { kind = "TALK" } } })).reason, "reserved_outcome")
    T.eq("D6 work time over 72 hours is refused", handle():registerFavorType(NS, water({ kindKey = "k3", workHours = 73 })).reason, "bad_work_time")
    T.eq("D7 money over 1000 is refused", handle():registerFavorType(NS, water({ kindKey = "k4", reward = { relationship = 1, money = 1001 } })).reason, "bad_reward")
    T.eq("D8 a positive penalty is refused", handle():registerFavorType(NS, water({ kindKey = "k5", penalty = { relationship = 1 } })).reason, "bad_penalty")
    T.eq("D9 three steps are refused", handle():registerFavorType(NS, water({ kindKey = "k6", steps = { { kind = "REPORT", outcome = "a" }, { kind = "TALK" }, { kind = "TALK" } } })).reason, "bad_steps")
    T.eq("D10 an undeclared key is refused", handle():registerFavorType(NS, water({ kindKey = "k7", callback = function() end })).reason, "bad_declaration")
    T.eq("D11 a non-integer number is refused", handle():registerFavorType(NS, water({ kindKey = "k8", difficulty = 1.5 })).reason, "bad_difficulty")
    local hits = 0
    for _, ft in ipairs(server.favorSystem.favorTypes) do if tostring(ft.id):find(":", 1, true) then hits = hits + 1 end end
    T.eq("D12 a contributed kind never enters favorTypes", #server.favorSystem.favorTypes .. "/" .. hits, builtIn .. "/0")
    for i = 2, 16 do handle():registerFavorType(NS, water({ kindKey = "kind_" .. i })) end
    T.eq("D13 a seventeenth kind for one provider is refused", handle():registerFavorType(NS, water({ kindKey = "kind_17" })).reason, "kind_limit")
end)()

-- =========================================================
-- O: offer (3.4) and G: built-in generation closed on an occupied person
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("no")
    local fav = server.favorSystem
    lock(server)
    local locked = offer("alex", 1)
    T.eq("O1 while LOCKED an offer refuses surface_locked and creates nothing", locked.result .. "/" .. locked.reason .. "/" .. #fav.activeFavors, "REFUSED/surface_locked/0")
    server.settings.experimentalSystems = nil
    T.eq("O2 an unreadable opt-in is LOCKED (fail-closed)", offer("alex", 1).reason, "surface_locked")
    open(server)
    T.eq("O3 an undeclared kind is refused", handle():requestFavorOffer(NS, "not_declared", { personKey = "alex", addressedFarmId = 1 }).reason, "kind_undeclared")
    T.eq("O4 the spectator farm is not an addressed farm", offer("alex", 0).reason, "bad_farm")
    T.eq("O5 a person this provider never claimed is refused", offer("stranger", 1).reason, "person_unknown")
    T.eq("O6 a FIELD kind needs a well-formed target", handle():requestFavorOffer(NS, "emergency_water", { personKey = "alex", addressedFarmId = 1 }).reason, "bad_target")
    person.relationship = 5
    T.eq("O7 trust under the host's ask floor waits", offer("alex", 1).result .. "/" .. offer("alex", 1).reason, "WAIT/trust_low")
    person.relationship = 30
    person.favorCooldown = 10
    T.eq("O8 a running cooldown waits", offer("alex", 1).reason, "cooldown")
    person.favorCooldown = 0
    local nextId = fav._nextFavorId
    local now = g_currentMission.time
    local r = offer("alex", 1)
    T.eq("O9 the offer is OFFERED with a number from the private allocator", r.result .. "/" .. r.reason .. "/" .. tostring(r.favorId == nextId), "OFFERED/offered/true")
    local rec = recordOf(server, r.favorId)
    local c = rec.contribution
    T.eq("O10 a pending, unowned record of the kind id", rec.status .. "/" .. tostring(rec.ownerFarmId) .. "/" .. tostring(rec.ownerFarmIdPresent) .. "/" .. rec.type,
        "pending/nil/false/" .. NS .. ":emergency_water")
    T.eq("O11 the contribution block", c.schema .. "/" .. c.namespace .. "/" .. c.kindKey .. "/" .. c.kindVersion .. "/" .. c.targetKind .. "/" .. c.targetKey .. "/" .. c.addressedFarmId .. "/" .. c.reportOutcome .. "/" .. tostring(c.reportDone),
        "1/" .. NS .. "/emergency_water/1/FIELD/40/1/irrigation_done/false")
    T.eq("O12 steps from the declaration: REPORT (not dialog, no location) then TALK (dialog)",
        #rec.steps .. "/" .. rec.steps[1].id .. tostring(rec.steps[1].isDialogStep) .. tostring(rec.steps[1].location) .. "/" .. rec.steps[2].id .. tostring(rec.steps[2].isDialogStep),
        "2/1falsenil/2true")
    T.eq("O13 the farmer's target is never written into taskData.fieldId", tostring(rec.taskData.fieldId), "nil")
    T.ok("O14 payment facts are known: rewardPaid false and present", rec.rewardPaid == false and rec.rewardPaidPresent == true)
    T.eq("O15 the offer expires after the declared offer time", rec.expirationGameTime, now + 12 * HOUR)
    T.ok("O16 the record carries a selection token", fav:getRecoveryRecordByToken(rec.recoveryToken) == rec)
    T.eq("O17 the offer set no cooldown on the person", person.favorCooldown, 0)
    local same = offer("alex", 1)
    T.eq("O18 an identical request answers the same favour", same.result .. "/" .. same.reason .. "/" .. tostring(same.favorId == r.favorId) .. "/" .. #fav.activeFavors, "OFFERED/already_offered/true/1")
    local other = offer("alex", 1, "41")
    T.eq("O19 any other request on an occupied person waits", other.result .. "/" .. other.reason, "WAIT/person_busy")
    local early = handle():reportFavorStep(NS, { favorId = r.favorId, outcome = "irrigation_done", farmId = 1 })
    T.eq("O20 a report before acceptance does not advance", early.result .. "/" .. early.reason, "NO_MATCH/not_accepted")

    -- G: every built-in door is closed on the occupied person.
    T.eq("G1 the random roll's gate refuses the occupied person", fav:canNPCRequestFavor(person), false)
    local help = request(C, R.OP_OFFER_HELP, person.id, "1")
    T.eq("G2 OFFER_HELP creates nothing for an occupied person", #fav.activeFavors, 1)
    T.eq("G3 the contextual trigger creates nothing", tostring(fav:triggerContextualFavor(person, "harvest")), "nil")
    T.ok("G4 the reply to another farm carries no row of the companion job", help == nil or #(help.rows or {}) == 0)

    -- A: acceptance (3.5)
    T.eq("A1 an addressed offer is never public", NPCPersonDialog.isPublicOffer(rec, g_currentMission.time), false)
    T.eq("A2 the person-first accept skips contributed rows", tostring(fav:acceptFavorForNPC(person.id, 1)) .. "/" .. rec.status, "nil/pending")
    local row = rowFor(server, rec, A)
    local direct = { server:serverAcceptFavor(person, 1, { token = rec.recoveryToken, recordRevision = rec.recordRevision }) }
    T.eq("A3 the built-in accept refuses a contribution record", tostring(direct[1]) .. "/" .. rec.status, "false/pending")
    local wrongFarm = workAction(C, IE.ACTION_FAVOR_ACCEPT, person.id, 2, sel("9", row))
    T.eq("A4 another farm cannot accept an addressed offer", wrongFarm.result .. "/" .. wrongFarm.messageKey .. "/" .. rec.status, R.RESULT_REFUSED .. "/npc_dialog_refused_farm/pending")
    local rev0 = rec.recordRevision
    local accepted = workAction(A, IE.ACTION_FAVOR_ACCEPT, person.id, 1, sel("5", row))
    T.eq("A5 the addressed farm accepts at the neighbour", accepted.result .. "/" .. accepted.messageKey .. "/" .. rec.status .. "/" .. tostring(rec.ownerFarmId), R.RESULT_ACCEPTED .. "/npc_dialog_accepted/active/1")
    T.eq("A6 the expiry is re-based to acceptance plus the work time", rec.expirationGameTime, g_currentMission.time + 24 * HOUR)
    T.eq("A7 the revision was bumped", rec.recordRevision, rev0 + 1)
    local replay = workAction(A, IE.ACTION_FAVOR_ACCEPT, person.id, 1, sel("5", row))
    T.eq("A8 the same accept replays its result without a second accept", replay.result .. "/" .. rec.recordRevision, R.RESULT_ACCEPTED .. "/" .. (rev0 + 1))
    T.eq("A9 an accepted companion job is ordinary active presence of its kind id", server:hasActiveFavorOfType(NS .. ":emergency_water"), true)

    -- R: report (3.6)
    local current = rowFor(server, rec, A)
    local tooEarly = workAction(A, IE.ACTION_FAVOR_COMPLETE, person.id, 1, sel("6", current))
    T.eq("R1 the farmer cannot finish before the companion reports", tooEarly.result .. "/" .. tooEarly.messageKey .. "/" .. rec.status, R.RESULT_REFUSED .. "/npc_dialog_refused_not_ready/active")
    T.eq("R2 a report for another farm is NO_MATCH", handle():reportFavorStep(NS, { favorId = rec.id, outcome = "irrigation_done", farmId = 2 }).result, "NO_MATCH")
    T.eq("R3 a report of an undeclared outcome is refused", handle():reportFavorStep(NS, { favorId = rec.id, outcome = "rain_fell", farmId = 1 }).reason, "wrong_outcome")
    T.eq("R4 a report on a number nobody holds is NO_MATCH", handle():reportFavorStep(NS, { favorId = 9999, outcome = "irrigation_done", farmId = 1 }).result, "NO_MATCH")
    local rev1 = rec.recordRevision
    local done = handle():reportFavorStep(NS, { favorId = rec.id, outcome = "irrigation_done", farmId = 1 })
    T.eq("R5 the declared report completes REPORT once", done.result .. "/" .. tostring(rec.steps[1].completed) .. "/" .. tostring(c.reportDone) .. "/" .. rec.recordRevision, "DONE/true/true/" .. (rev1 + 1))
    T.eq("R6 a replayed report answers ALREADY_DONE", handle():reportFavorStep(NS, { favorId = rec.id, outcome = "irrigation_done", farmId = 1 }).result, "ALREADY_DONE")

    -- C: completion and the money gate (section 5, invariant 1)
    MONEY = {}
    local trust0, done0 = person.relationship, person.totalFavorsCompleted or 0
    T.eq("C1 completeFavor refuses companion work (no other caller can finish it)", fav:completeFavor(rec.id), false)
    local actorA = NPCFarmIdentity.resolveActor(A)
    local rc = fav:serverRecoveryCommand(actorA, { requestId = "77", collectionRevision = tostring(fav._recoveryCollectionRevision), recordRevision = tostring(rec.recordRevision), token = tostring(rec.recoveryToken), op = NPCFavorRecovery.OP_COMPLETE })
    T.eq("C2 the recovery COMPLETE command refuses it", rc.result, NPCFavorRecovery.RESULT_REFUSED)
    T.eq("C3 and neither moved money or trust", moneyTotal(1) .. "/" .. person.relationship .. "/" .. rec.status, "0/" .. trust0 .. "/active")
    current = rowFor(server, rec, A)
    local stranger = workAction(C, IE.ACTION_FAVOR_COMPLETE, person.id, 2, sel("10", current))
    T.eq("C4 another farm cannot finish it", stranger.messageKey .. "/" .. rec.status, "npc_recovery_refused_not_owner/active")
    local finished = workAction(A, IE.ACTION_FAVOR_COMPLETE, person.id, 1, sel("7", current))
    T.eq("C5 after the report the farmer finishes at the neighbour", finished.result .. "/" .. finished.messageKey .. "/" .. rec.status, R.RESULT_OK .. "/npc_dialog_completed/completed")
    T.eq("C6 the declared money is paid once to the owning farm, nothing else", moneyTotal(1) .. "/" .. moneyTotal(2), "400/0")
    T.eq("C7 the declared relationship reward is paid once", person.relationship - trust0, 6)
    T.ok("C8 the record moved to completed once, its token retired, rewardPaid set",
        inList(fav.completedFavors, rec) and not inList(fav.activeFavors, rec) and fav:getRecoveryRecordByToken(rec.recoveryToken) == nil and rec.rewardPaid == true)
    T.eq("C9 the neighbour's completed count moved once", (person.totalFavorsCompleted or 0) - done0, 1)
    local again = workAction(A, IE.ACTION_FAVOR_COMPLETE, person.id, 1, sel("8", current))
    T.ok("C10 a second COMPLETE changes nothing", again ~= nil and again.result ~= R.RESULT_OK and moneyTotal(1) == 400)
    fav:applyFavorRewards(rec)
    T.eq("C11 a replayed reward writes no second money and no second trust", moneyTotal(1) .. "/" .. (person.relationship - trust0), "400/6")
    T.eq("C12 a completed job frees the neighbour for built-in work again", fav:canNPCRequestFavor(person), true)
end)()

-- =========================================================
-- F: abandon, expiry and lapse (3.6, 3.7): relationship-only, never money
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("nf")
    local fav = server.favorSystem
    MONEY = {}
    -- abandon: half the copied penalty and the ordinary failure count
    local r = offer("alex", 1)
    local rec = recordOf(server, r.favorId)
    workAction(A, IE.ACTION_FAVOR_ACCEPT, person.id, 1, sel("1", rowFor(server, rec, A)))
    local trust0, failed0 = person.relationship, person.totalFavorsFailed or 0
    local gone = workAction(A, IE.ACTION_FAVOR_ABANDON, person.id, 1, sel("2", rowFor(server, rec, A)))
    T.eq("F1 walking away abandons the job", gone.messageKey .. "/" .. rec.status, "npc_dialog_abandoned/abandoned")
    T.eq("F2 half the trust penalty and one failure count", (person.relationship - trust0) .. "/" .. ((person.totalFavorsFailed or 0) - failed0), math.floor(-8 * 0.5) .. "/1")
    -- expiry of accepted work: the full copied penalty through failFavor
    local r2 = offer("alex", 1)
    local rec2 = recordOf(server, r2.favorId)
    workAction(A, IE.ACTION_FAVOR_ACCEPT, person.id, 1, sel("3", rowFor(server, rec2, A)))
    trust0, failed0 = person.relationship, person.totalFavorsFailed or 0
    advance(25 * HOUR)
    tickFavours(server)
    T.eq("F3 accepted work that runs out fails", rec2.status .. "/" .. tostring(inList(fav.failedFavors, rec2)), "failed/true")
    T.eq("F4 with the full trust penalty and one failure count", (person.relationship - trust0) .. "/" .. ((person.totalFavorsFailed or 0) - failed0), "-8/1")
    -- an offer that lapses: nothing at all
    local r3 = offer("alex", 1)
    local rec3 = recordOf(server, r3.favorId)
    trust0, failed0 = person.relationship, person.totalFavorsFailed or 0
    local histories = #fav.failedFavors + #fav.completedFavors + #fav.abandonedFavors
    advance(13 * HOUR)
    tickFavours(server)
    T.eq("F5 an unanswered offer lapses and leaves every collection", rec3.status .. "/" .. tostring(inList(fav.activeFavors, rec3)), "closed/false")
    T.eq("F6 a lapse writes no trust, no failure count and no history", (person.relationship - trust0) .. "/" .. ((person.totalFavorsFailed or 0) - failed0) .. "/" .. (#fav.failedFavors + #fav.completedFavors + #fav.abandonedFavors - histories), "0/0/0")
    T.ok("F7 the lapsed offer's token is retired", fav:getRecoveryRecordByToken(rec3.recoveryToken) == nil)
    T.eq("F8 no path above moved money", moneyTotal(1) + moneyTotal(2), 0)
end)()

-- =========================================================
-- L: the lock and the unlock, driven from the real predicate (3.7, v1.1)
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("nl")
    local fav = server.favorSystem
    local bea = server:getNPCById(claim("bea", 600, 600).personId)
    bea.relationship, bea.personality = 30, "friendly"
    standAt(B, bea.position.x, bea.position.z)
    local pendingId = offer("bea", 1).favorId
    local pending = recordOf(server, pendingId)
    local id = offer("alex", 1).favorId
    local rec = recordOf(server, id)
    workAction(A, IE.ACTION_FAVOR_ACCEPT, person.id, 1, sel("1", rowFor(server, rec, A)))
    MONEY = {}
    local trust0 = person.relationship
    advance(HOUR)
    lock(server)
    tickFavours(server)
    T.ok("L1 the lock withdraws a pending offer without fault", pending.status == "closed" and not inList(fav.activeFavors, pending) and bea.relationship == 30)
    T.eq("L2 the lock holds accepted work WORK_OFF", tostring(rec.contributionHeld) .. "/" .. tostring(rec.contributionHoldReason), "true/WORK_OFF")
    T.eq("L3 held work is in Recovery, paused, its expiry cleared", tostring(inList(fav.recoveryFavors, rec)) .. "/" .. tostring(inList(fav.activeFavors, rec)) .. "/" .. rec.status .. "/" .. tostring(rec.expirationGameTime), "true/false/paused_recovery/nil")
    local frozen = rec.timeRemaining
    T.eq("L4 its remaining time is frozen", frozen, 23 * HOUR)
    T.eq("L5 an advancing report refuses while LOCKED", handle():reportFavorStep(NS, { favorId = id, outcome = "irrigation_done", farmId = 1 }).reason, "surface_locked")
    T.eq("L6 a person claim is READY while LOCKED", claim("alex").result, "READY")
    local held = workAction(A, IE.ACTION_FAVOR_ABANDON, person.id, 1, sel("2", rowFor(server, rec, A)))
    T.ok("L7 held work cannot be abandoned", held ~= nil and held.result ~= R.RESULT_OK and rec.status == "paused_recovery")
    T.eq("L8 a held job still occupies its neighbour against built-in work", tostring(fav:canNPCRequestFavor(person)) .. "/" .. tostring(fav:generateFavorForNPC(person, false, 1)), "false/nil")
    advance(30 * HOUR)
    tickFavours(server)
    T.ok("L9 held work never runs out, fails or pays", rec.status == "paused_recovery" and rec.timeRemaining == frozen and person.relationship == trust0 and moneyTotal(1) == 0)
    -- a second job whose neighbour goes away while it is held
    open(server)
    tickFavours(server)
    T.eq("L10 unlock returns lock-held work to active by itself", tostring(inList(fav.activeFavors, rec)) .. "/" .. rec.status, "true/active")
    T.ok("L11 unlock clears the lock hold", rec.contributionHeld == false and rec.contributionHoldReason == nil)
    T.eq("L12 unlock re-bases the frozen remaining time", rec.expirationGameTime, g_currentMission.time + frozen)
    local awayId = offer("bea", 1).favorId
    local away = recordOf(server, awayId)
    workAction(B, IE.ACTION_FAVOR_ACCEPT, bea.id, 1, sel("3", rowFor(server, away, B)))
    lock(server)
    tickFavours(server)
    server:setPersonLive(bea, false, NPCPersonRoster.REASON_WAITING_COUNT)
    T.eq("L13 a waiting person does not touch a lock-held row", tostring(away.contributionHoldReason) .. "/" .. tostring(away.recoveryReason), "WORK_OFF/nil")
    open(server)
    tickFavours(server)
    T.eq("L14 unlock keeps an away neighbour's job in Recovery", tostring(inList(fav.recoveryFavors, away)) .. "/" .. away.status, "true/paused_recovery")
    T.eq("L15 that job takes the neighbour pause", away.recoveryReason, NPCFavorRecovery.REASON_NEIGHBOUR_UNAVAILABLE)
    T.ok("L16 that job is no longer held", away.contributionHeld == false)
    lock(server)
    tickFavours(server)
    local closed = handle():reportFavorStep(NS, { favorId = id, outcome = "target_gone", farmId = 1 })
    T.eq("L17 the provider may close locked work without fault", closed.result .. "/" .. rec.status .. "/" .. (person.relationship - trust0), "CLOSED/closed/0")
    T.eq("L18 nothing on the lock path moved money", moneyTotal(1), 0)
end)()

-- =========================================================
-- U: the provider goes and comes back (3.1, 3.3)
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("nu")
    local fav = server.favorSystem
    local bea = server:getNPCById(claim("bea", 600, 600).personId)
    bea.relationship, bea.personality = 30, "friendly"
    local pending = recordOf(server, offer("bea", 1).favorId)
    local rec = recordOf(server, offer("alex", 1).favorId)
    workAction(A, IE.ACTION_FAVOR_ACCEPT, person.id, 1, sel("1", rowFor(server, rec, A)))
    local u = handle():unregisterCompanionProvider(NS)
    T.eq("U1 unregistering answers DONE", u.result, "DONE")
    T.eq("U2 its pending offers close without fault", pending.status, "closed")
    T.eq("U3 its accepted job holds COMPANION_MISSING", tostring(rec.contributionHoldReason) .. "/" .. tostring(inList(fav.recoveryFavors, rec)), "COMPANION_MISSING/true")
    T.eq("U4 an absent provider reports nothing", handle():reportFavorStep(NS, { favorId = rec.id, outcome = "irrigation_done", farmId = 1 }).reason, "provider_unknown")
    T.ok("U5 its people remain neighbours", server:getNPCById(person.id) == person and person.live == true)
    handle():registerCompanionProvider(spec())
    T.eq("U6 re-registration alone does not bind the job", rec.contributionHoldReason, "COMPANION_MISSING")
    T.eq("U7 an advancing report waits for the kind", handle():reportFavorStep(NS, { favorId = rec.id, outcome = "irrigation_done", farmId = 1 }).reason, "kind_undeclared")
    handle():registerFavorType(NS, water({ steps = { { kind = "REPORT", outcome = "water_hauled" }, { kind = "TALK" } } }))
    T.eq("U8 an incompatible declaration holds it COMPANION_INCOMPATIBLE", rec.contributionHoldReason, "COMPANION_INCOMPATIBLE")
    handle():unregisterCompanionProvider(NS)
    handle():registerCompanionProvider(spec())
    handle():registerFavorType(NS, water({ version = 2, acceptsVersions = { 1 } }))
    T.eq("U9 a compatible declaration binds it back to active work", tostring(inList(fav.activeFavors, rec)) .. "/" .. rec.status .. "/" .. tostring(rec.contributionHeld), "true/active/false")
    T.ok("U10 resuming never marks it recovered from legacy", rec.recoveredFromLegacy ~= true)
end)()

-- =========================================================
-- S: the opt-in is persisted with the save
-- =========================================================
;(function()
    local server = world({ dir = "ns" })
    useServer()
    T.eq("S1 a new save starts with the surface locked", tostring(server.settings.experimentalSystems), "false")
    server.settings.experimentalSystems = true
    server:saveToXMLFile(g_currentMission.missionInfo)
    local re = boot({ placeables = town(4), maxNPCs = 3, dir = "ns" })
    T.eq("S2 the player's opt-in survives a reload", tostring(re.settings.experimentalSystems), "true")
    T.eq("S3 and the predicate reads it as OPEN", re.favorSystem:readCompanionSurface(), "OPEN")
end)()

T.summary()
