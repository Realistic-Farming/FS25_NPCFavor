-- NPC-204 save and load: companion work through both save paths and the favour-number high-water.
--!load: src/utils/NPCFarmIdentity.lua, src/utils/NPCReleaseGate.lua, src/settings/NPCSettings.lua, src/scripts/NPCPersonRoster.lua, src/scripts/NPCRelationshipManager.lua, src/scripts/NPCFavorSystem.lua, src/scripts/NPCFavorRecovery.lua, src/scripts/NPCCompanionContribution.lua, src/scripts/NPCFieldWork.lua, src/scripts/NPCAI.lua, src/scripts/ContractorModBridge.lua, src/scripts/NPCInteractionUI.lua, src/events/NPCStateSyncEvent.lua, src/events/NPCInteractionEvent.lua, src/events/NPCFavorRecoveryEvents.lua, src/events/NPCPersonDialogEvents.lua, src/integrations/NPCStateLedgerBridge.lua, src/integrations/NPCNetworkSyncBridge.lua, src/NPCSystem.lua, src/scripts/NPCPersonDialog.lua, src/gui/NPCDialog.lua, src/gui/NPCListDialog.lua, src/gui/NPCAdminEditDialog.lua, src/gui/NPCFavorManagementDialog.lua, src/scripts/NPCFavorHUD.lua, src/settings/NPCFavorGUI.lua
--
-- THE ENTRY-POINT BAR for slice 3 (Implementation v1.1 section 3.10). Every
-- save goes through production's writers (NPCSystem:saveToXMLFile, and
-- NPCSystem:serializeState, the StateLedger module's own serialize hook) and
-- every reload through a fresh boot of the server from that XML or from the
-- delivered ledger block (NPCSystem.new, onMissionLoaded, the first-frame
-- updater, the bridge's deserialize). The companion comes back the way a
-- companion loads, through the published mission handle: register, claim,
-- declare. The farmer acts through NPCInteractionEvent and the Recovery door's
-- own events. Nothing hand-fills a favour, a hold, a token or a revision. Two
-- saves are edited on purpose, as evidence a foreign or hand-edited save could
-- carry: a row without its durable person mark, and a contribution block of a
-- later schema.
--
-- What this proves: the persistence contract, offline. What it does not: real
-- disk, the real StateLedger file, the Recovery view's new fields (the views
-- slice), GUI rendering.

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
-- The farmer's Recovery door: the view and the command, on the wire
-- =========================================================
local RV = NPCFavorRecovery
local REQ = 100
local function nextReq() REQ = REQ + 1 return tostring(REQ) end
-- The owning farm's Recovery page, requested on `conn` through the real view
-- request event and decoded from the real reply event.
local function viewAs(conn)
    useServer()
    local before = #conn.sent
    roundTrip(NPCFavorRecoveryViewRequestEvent.new(nextReq(), ""), conn)
    if #conn.sent - before ~= 1 then return nil end
    return decode(conn.sent[#conn.sent])
end
local function rowOf(view, rec)
    for _, row in ipairs(view and view.rows or {}) do
        if tonumber(row.token) == rec.recoveryToken then return row end
    end
    return nil
end
-- One command on `conn`, built from the page `viewConn` (default `conn`) just
-- received: the token, record revision and collection revision the farmer saw.
-- Always answers a table; no reply at all reads as result -1.
local function command(conn, op, rec, viewConn, revisionOverride)
    local view = viewAs(viewConn or conn)
    local row = rowOf(view, rec)
    local cmd = { requestId = nextReq(), collectionRevision = view and view.collectionRevision or "0",
        recordRevision = revisionOverride or (row and row.recordRevision) or "0",
        token = row and row.token or "0", op = op }
    useServer()
    local before = #conn.sent
    roundTrip(NPCFavorRecoveryCommandEvent.new(cmd), conn)
    if #conn.sent - before ~= 1 then return { result = -1, messageKey = "no_reply" } end
    return decode(conn.sent[#conn.sent]) or { result = -1, messageKey = "no_reply" }
end
local function history(fav) return #fav.failedFavors + #fav.completedFavors + #fav.abandonedFavors end
local function accept(server, conn, person, rec, id)
    workAction(conn, IE.ACTION_FAVOR_ACCEPT, person.id, rec.contribution.addressedFarmId, sel(id, rowFor(server, rec, conn)))
end
local function claimed(server, key, x, z)
    local p = server:getNPCById(claim(key, x, z).personId)
    p.relationship, p.personality = 30, "friendly"
    return p
end


-- =========================================================
-- Save and reload through production's own paths
-- =========================================================
local ROOT_KEY = "npcFavor"
local function savedFile(dir) return DISK[dir .. "/npc_favor.xml"] end
-- A new process: the server boots from the save at `dir` (or from a delivered
-- ledger block) through NPCSystem.new, onMissionLoaded and the first-frame
-- updater, and main.lua's one publishing line runs again.
local function reboot(dir, block)
    local re = boot({ placeables = town(4), maxNPCs = 3, dir = dir, ledger = block and newLedger(block) or nil })
    SIDE.server = { sys = re, mission = g_currentMission, g_server = g_server, localPlayer = nil }
    publish(re)
    return re
end
-- The companion comes back the way a companion loads: register, claim, declare.
local function companionReturns(sys, decl)
    useServer()
    handle():registerCompanionProvider(spec())
    local alex = sys:getNPCById(claim("alex").personId)
    handle():registerFavorType(NS, decl or water())
    return alex
end
local function favorKeyOf(file, id)
    for _, list in ipairs({ ".favors.favor", ".recoveryFavors.favor" }) do
        for i = 0, 20 do
            local k = ROOT_KEY .. list .. "(" .. i .. ")"
            if file[k .. "#favorId"] == id then return k end
        end
    end
    return nil
end
local function find(fav, id)
    for _, list in ipairs({ fav.activeFavors, fav.recoveryFavors }) do
        for _, f in ipairs(list) do if f.id == id then return f end end
    end
    return nil
end
-- One accepted, reported job on farm 1, plus an unsaved pending offer and a
-- completed job, so the high-water has numbers to protect.
local function preparedJob(dir)
    local server, client, A, B, C, person = companionWorld(dir)
    local fav = server.favorSystem
    local bea = claimed(server, "bea", 600, 600)
    standAt(B, bea.position.x, bea.position.z)
    local done = recordOf(server, offer("bea", 1).favorId)
    accept(server, B, bea, done, "1")
    handle():reportFavorStep(NS, { favorId = done.id, outcome = "irrigation_done", farmId = 1 })
    workAction(B, IE.ACTION_FAVOR_COMPLETE, bea.id, 1, sel("2", rowFor(server, done, B)))
    local rec = recordOf(server, offer("alex", 1).favorId)
    accept(server, A, person, rec, "3")
    handle():reportFavorStep(NS, { favorId = rec.id, outcome = "irrigation_done", farmId = 1 })
    local pending = recordOf(server, offer("bea", 1).favorId)
    advance(2 * HOUR)
    tickFavours(server)
    return server, A, B, C, person, rec, pending, done
end

-- =========================================================
-- X: the XML path, reload without and then with the companion
-- =========================================================
;(function()
    local server, A, B, C, person, rec, pending, done = preparedJob("sx")
    local fav = server.favorSystem
    local id, remaining, nextId = rec.id, rec.expirationGameTime - g_currentMission.time, fav._nextFavorId
    server:saveToXMLFile(g_currentMission.missionInfo)
    local f = savedFile("sx")
    local key = favorKeyOf(f, id)
    T.ok("X1 the accepted job is saved", key ~= nil)
    T.ok("X2 with its contribution block beside the F148 row", key ~= nil and f[key .. ".contribution#fields"] ~= nil)
    T.eq("X3 the F148 schema stays 1; the contribution schema is its own field", key and f[key .. "#f148Schema"], 1)
    T.eq("X4 the companion's pending offer is not saved", tostring(favorKeyOf(f, pending.id)), "nil")
    T.eq("X5 the favour-number high-water is saved", f[ROOT_KEY .. "#nextFavorId"], nextId)
    T.ok("X6 the completed job's number is below it", done.id < nextId and pending.id < nextId)

    local re = reboot("sx")
    local fav2 = re.favorSystem
    T.eq("X7 the reload is READY", fav2:getFavorLoadState(), "READY")
    local back = find(fav2, id)
    T.ok("X8 without the companion the job is in Recovery, held", back ~= nil and inList(fav2.recoveryFavors, back) and back.contributionHeld == true)
    T.eq("X9 its hold is COMPANION_MISSING (the surface is open)", back and back.contributionHoldReason, "COMPANION_MISSING")
    T.ok("X10 its clock is stopped: no expiry, the remaining time kept", back ~= nil and back.expirationGameTime == nil and math.abs(back.timeRemaining - remaining) < 1)
    local c = back and back.contribution or {}
    T.eq("X11 its contribution came back from the block",
        tostring(c.namespace) .. "/" .. tostring(c.kindKey) .. "/" .. tostring(c.kindVersion) .. "/" .. tostring(c.targetKind) .. "/" .. tostring(c.targetKey) .. "/" .. tostring(c.addressedFarmId) .. "/" .. tostring(c.reportOutcome) .. "/" .. tostring(c.reportDone),
        NS .. "/emergency_water/1/FIELD/40/1/irrigation_done/true")
    T.eq("X12 the two fixed steps are rebuilt: REPORT done (not dialog), TALK open (dialog)",
        back and (tostring(back.steps[1].completed) .. tostring(back.steps[1].isDialogStep) .. "/" .. tostring(back.steps[2].completed) .. tostring(back.steps[2].isDialogStep)),
        "truefalse/falsetrue")
    T.eq("X13 its copied reward and penalty came back", back and (back.reward.money .. "/" .. back.reward.relationship .. "/" .. back.penalty.relationship), "400/6/-8")
    T.eq("X14 the type is the kind id, never an invalid record", back and (back.type .. "/" .. tostring(back.recoveryReason)), NS .. ":emergency_water/nil")
    T.eq("X15 the high-water is installed", fav2._nextFavorId, nextId)
    advance(30 * HOUR)
    tickFavours(re)
    T.ok("X16 held work never runs out, fails or pays", back ~= nil and back.status == "paused_recovery" and math.abs(back.timeRemaining - remaining) < 1)

    MONEY = {}
    local alex = companionReturns(re)
    T.eq("X17 the companion's register, claim and declare return the job to active work",
        tostring(inList(fav2.activeFavors, back)) .. "/" .. back.status .. "/" .. tostring(back.contributionHeld), "true/active/false")
    T.ok("X18 with its remaining time re-based", math.abs(back.expirationGameTime - (g_currentMission.time + remaining)) < 1)
    T.ok("X19 never marked recovered from legacy", back.recoveredFromLegacy ~= true)
    claim("bea", 600, 600)
    local r2 = offer("bea", 1)
    T.eq("X20 a new offer takes the saved high-water: no number from before the save is issued again",
        r2.result .. "/" .. tostring(r2.favorId == nextId) .. "/" .. tostring(r2.favorId ~= pending.id and r2.favorId ~= done.id), "OFFERED/true/true")
    standAt(A, alex.position.x, alex.position.z)
    local finished = workAction(A, IE.ACTION_FAVOR_COMPLETE, alex.id, 1, sel("4", rowFor(re, back, A)))
    T.eq("X21 the reloaded job finishes at the neighbour (its REPORT kept) and pays once", finished.messageKey .. "/" .. moneyTotal(1), "npc_dialog_completed/400")
end)()

-- =========================================================
-- L: the ledger path, locked at load, then unlocked
-- =========================================================
;(function()
    local server, A, B, C, person, rec, pending = preparedJob("sl")
    local fav = server.favorSystem
    local id, remaining, nextId = rec.id, rec.expirationGameTime - g_currentMission.time, fav._nextFavorId
    lock(server)
    tickFavours(server)
    local block = NPCCompanion.copyRow(server:serializeState())
    local saved = nil
    for _, row in ipairs(block.recoveryFavors or {}) do if row.favorId == id then saved = row end end
    T.ok("L1 the ledger state carries the held job with its block", saved ~= nil and type(saved.contribution) == "table" and saved.contribution.schema == 1)
    T.eq("L2 the block names its hold", saved and (tostring(saved.contribution.held) .. "/" .. tostring(saved.contribution.holdReason)), "true/WORK_OFF")
    T.eq("L3 the ledger state carries the high-water", block.nextFavorId, nextId)
    local anyPending = false
    for _, row in ipairs(block.favors or {}) do if row.favorId == pending.id then anyPending = true end end
    T.eq("L4 the companion's pending offer is not in the ledger state", anyPending, false)

    local re = reboot("sl_ledger", block)
    local fav2 = re.favorSystem
    re.settings.experimentalSystems = false
    local back = find(fav2, id)
    T.eq("L5 the ledger reload holds it WORK_OFF while the surface is LOCKED", back and back.contributionHoldReason, "WORK_OFF")
    T.eq("L6 and installs the high-water", fav2._nextFavorId, nextId)
    companionReturns(re)
    tickFavours(re)
    T.eq("L7 a returning companion does not lift the lock hold", back.contributionHoldReason, "WORK_OFF")
    open(re)
    tickFavours(re)
    T.eq("L8 the unlock returns it to active work", tostring(inList(fav2.activeFavors, back)) .. "/" .. back.status, "true/active")
    T.ok("L9 with its remaining time", math.abs(back.expirationGameTime - (g_currentMission.time + remaining)) < 1)
end)()

-- =========================================================
-- E: a companion that registers before the favour load finishes
-- =========================================================
;(function()
    local server, A, B, C, person, rec = preparedJob("se")
    local id, remaining = rec.id, rec.expirationGameTime - g_currentMission.time
    local block = NPCCompanion.copyRow(server:serializeState())
    -- The ledger has not delivered yet: people and favours wait. The companion
    -- loads first, registering and declaring through the handle.
    local late = newLedger(block, true)
    local re = boot({ placeables = town(4), maxNPCs = 3, dir = "se_ledger", ledger = late })
    SIDE.server = { sys = re, mission = g_currentMission, g_server = g_server, localPlayer = nil }
    publish(re)
    T.eq("E1 the favours are still waiting for the ledger", re.favorSystem:getFavorLoadState(), "WAITING")
    open(re)   -- this ledger-only boot has no settings file of its own; the player opts in
    handle():registerCompanionProvider(spec())
    handle():registerFavorType(NS, water())
    late:deliver()
    local fav2 = re.favorSystem
    local back = find(fav2, id)
    T.eq("E2 the restore binds the job to the already declared kind: no hold", back and tostring(back.contributionHeld), "false")
    T.eq("E3 its person still waits for her claim, so it takes F357's neighbour pause", back and tostring(back.recoveryReason), RV.REASON_NEIGHBOUR_UNAVAILABLE)
    local alex = re:getNPCById(claim("alex").personId)
    local res = command(A, RV.OP_RESUME, back)
    T.eq("E4 once she is claimed the farmer resumes it", res.messageKey .. "/" .. back.status, "npc_recovery_ok_resumed/active")
    T.ok("E5 with its remaining time", math.abs(back.expirationGameTime - (g_currentMission.time + remaining)) < 1)
end)()

-- =========================================================
-- P: a reloaded job whose person cannot be proved; LET_GO is its exit
-- =========================================================
;(function()
    local server, A, B, C, person, rec = preparedJob("sp")
    local id = rec.id
    server:saveToXMLFile(g_currentMission.missionInfo)
    -- The saved row lost its durable person mark (a hand-edited or foreign
    -- save): F357 cannot prove the person from it.
    local f = savedFile("sp")
    local key = favorKeyOf(f, id)
    f[key .. "#personRefKind"] = nil
    local re = reboot("sp")
    local fav2 = re.favorSystem
    local back = find(fav2, id)
    T.eq("P1 the unproven job reloads in Recovery with the person_unproven reason", back and (tostring(back.personUnproven) .. "/" .. tostring(back.recoveryReason)), "true/" .. RV.REASON_PERSON_UNPROVEN)
    MONEY = {}
    local alex = companionReturns(re)
    T.ok("P2 the companion's return clears the hold but the job stays paused", back.contributionHeld == false and inList(fav2.recoveryFavors, back))
    local res = command(A, RV.OP_RESUME, back)
    T.eq("P3 an unproven job cannot be resumed", res.result .. "/" .. res.messageKey, RV.RESULT_REFUSED .. "/npc_recovery_unavail_person")
    local stranger = command(C, RV.OP_LET_GO, back, A)
    T.eq("P4 another farm cannot let it go", stranger.messageKey, "npc_recovery_refused_not_owner")
    local trust0 = alex.relationship
    local go = command(A, RV.OP_LET_GO, back)
    T.eq("P5 the owning farm lets the unproven job go", go.result .. "/" .. go.messageKey .. "/" .. back.status, RV.RESULT_OK .. "/npc_contrib_let_go/closed")
    T.eq("P6 without fault", moneyTotal(1) .. "/" .. (alex.relationship - trust0), "0/0")
end)()

-- =========================================================
-- F: an unsupported contribution schema stays inert and round-trips
-- =========================================================
;(function()
    local server, A, B, C, person, rec = preparedJob("sf")
    local id = rec.id
    server:saveToXMLFile(g_currentMission.missionInfo)
    local f = savedFile("sf")
    local key = favorKeyOf(f, id)
    -- A later NPCFavor wrote contribution schema 2, with a field this one does not know.
    f[key .. ".contribution#fields"] = f[key .. ".contribution#fields"]:gsub("schema=number:1", "schema=number:2")
        :gsub("(addressedFarmId=number:%d+)", "%1;futureField=string:kept as is")
    local packed = f[key .. ".contribution#fields"]
    local re = reboot("sf")
    local fav2 = re.favorSystem
    T.eq("F1 the load is not failed by it", fav2:getFavorLoadState(), "READY")
    local back = find(fav2, id)
    T.ok("F2 the row is kept in Recovery, inert, never decoded", back ~= nil and inList(fav2.recoveryFavors, back) and back.contributionInert == true and back.contribution == nil)
    MONEY = {}
    companionReturns(re)
    local res = command(A, RV.OP_RESUME, back)
    local go = command(A, RV.OP_LET_GO, back)
    T.ok("F3 it is inspect-only: neither resumed nor let go", res.result ~= RV.RESULT_OK and go.result ~= RV.RESULT_OK and back.status == "paused_recovery")
    T.eq("F4 nothing was paid", moneyTotal(1), 0)
    re:saveToXMLFile(g_currentMission.missionInfo)
    local f2 = savedFile("sf")
    local key2 = favorKeyOf(f2, id)
    T.eq("F5 the next save writes its contribution block back unchanged", key2 and f2[key2 .. ".contribution#fields"], packed)
    T.eq("F6 and its saved status unchanged", key2 and f2[key2 .. "#status"], f[key .. "#status"])
end)()

-- =========================================================
-- G: a saved job whose farm is gone at load closes without fault
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("sg")
    local rec = recordOf(server, offer("alex", 2).favorId)
    accept(server, C, person, rec, "1")
    local id = rec.id
    server:saveToXMLFile(g_currentMission.missionInfo)
    local farm2 = LIVE_FARMS[2]
    LIVE_FARMS[2] = nil
    local re = reboot("sg")
    T.eq("G1 the load is READY", re.favorSystem:getFavorLoadState(), "READY")
    T.eq("G2 the deleted farm's job is not restored (never orphaned to another farm)", tostring(find(re.favorSystem, id)), "nil")
    LIVE_FARMS[2] = farm2
end)()

T.summary()
