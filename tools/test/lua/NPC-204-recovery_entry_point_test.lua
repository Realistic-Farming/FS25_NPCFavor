-- NPC-204 Recovery: held companion work, LET_GO, Resume, the waiting person and the farm lifecycle.
--!load: src/utils/NPCFarmIdentity.lua, src/utils/NPCReleaseGate.lua, src/settings/NPCSettings.lua, src/scripts/NPCPersonRoster.lua, src/scripts/NPCRelationshipManager.lua, src/scripts/NPCFavorSystem.lua, src/scripts/NPCFavorRecovery.lua, src/scripts/NPCCompanionContribution.lua, src/scripts/NPCFieldWork.lua, src/scripts/NPCAI.lua, src/scripts/ContractorModBridge.lua, src/scripts/NPCInteractionUI.lua, src/events/NPCStateSyncEvent.lua, src/events/NPCInteractionEvent.lua, src/events/NPCFavorRecoveryEvents.lua, src/events/NPCPersonDialogEvents.lua, src/integrations/NPCStateLedgerBridge.lua, src/integrations/NPCNetworkSyncBridge.lua, src/NPCSystem.lua, src/scripts/NPCPersonDialog.lua, src/gui/NPCDialog.lua, src/gui/NPCListDialog.lua, src/gui/NPCAdminEditDialog.lua, src/gui/NPCFavorManagementDialog.lua, src/scripts/NPCFavorHUD.lua, src/settings/NPCFavorGUI.lua
--
-- THE ENTRY-POINT BAR for slice 2 (Implementation v1.1 sections 3.8 and 3.9).
-- A test caller binds only through the published mission handle,
-- g_currentMission.npcFavorSystem (main.lua:227, :275), and registers, claims,
-- declares, offers and reports through the real verbs. The farmer enters where
-- production enters: NPCInteractionEvent for accept and complete, and the
-- Recovery door's own events for everything else: NPCFavorRecoveryViewRequestEvent
-- for the page (its reply decoded from NPCFavorRecoveryViewReplyEvent) and
-- NPCFavorRecoveryCommandEvent for Resume, LET_GO and the refused operations, each
-- built from the token and revisions the farmer's page carried, on a typed mock
-- stream from a remote connection (readStream with its operation whitelist, run,
-- the actor resolved from the connection). The lock is the player's persisted
-- setting read by the real predicate on the favour system's tick; a person goes
-- waiting through NPCSystem:setPersonLive; farms come and go through the
-- production FARM_DELETED and FARM_CREATED subscribers. Nothing hand-fills a
-- favour, a hold, a pause, a token or a revision.
--
-- What this proves: the Recovery half of the host contract, offline. What it does
-- not: saving held work (the persistence slice), the Recovery view's new row
-- fields, masters' visibility and the management door's LET_GO control (the views
-- slice), GUI rendering, native transport.

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
-- H: held work and LET_GO (3.8)
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("rh")
    local fav = server.favorSystem
    local M = newConnection("M", 14, 2)
    USERS[M].getIsMasterUser = function() return true end
    local rec = recordOf(server, offer("alex", 1).favorId)
    accept(server, A, person, rec, "1")
    MONEY = {}
    local trust0, failed0, done0, hist0 = person.relationship, person.totalFavorsFailed or 0, person.totalFavorsCompleted or 0, history(fav)
    lock(server)
    tickFavours(server)
    T.eq("H1 the lock holds the accepted job WORK_OFF in Recovery", tostring(rec.contributionHoldReason) .. "/" .. tostring(inList(fav.recoveryFavors, rec)), "WORK_OFF/true")
    T.ok("H2 the owning farm's Recovery page lists it with a token", rowOf(viewAs(A), rec) ~= nil)
    local res = command(A, RV.OP_RESUME, rec)
    T.eq("H3 a held job cannot be resumed", res.result .. "/" .. res.messageKey, RV.RESULT_REFUSED .. "/npc_recovery_refused_not_resumable")
    local assign = command(M, RV.OP_ASSIGN_AND_RESUME, rec, A)
    local complete = command(A, RV.OP_COMPLETE, rec)
    local abandon = command(A, RV.OP_ABANDON, rec)
    T.eq("H4 assign, complete and abandon never act on companion work",
        assign.messageKey .. "/" .. complete.messageKey .. "/" .. abandon.messageKey .. "/" .. rec.status,
        "npc_recovery_refused_operation/npc_recovery_refused_operation/npc_recovery_refused_operation/paused_recovery")
    local other = command(C, RV.OP_LET_GO, rec, A)
    T.eq("H5 another farm cannot let it go, even with the owner's selection", other.result .. "/" .. other.messageKey, RV.RESULT_REFUSED .. "/npc_recovery_refused_not_owner")
    local master = command(M, RV.OP_LET_GO, rec, A)
    T.eq("H6 a master of another farm gets no exception", master.result .. "/" .. master.messageKey, RV.RESULT_REFUSED .. "/npc_recovery_refused_not_owner")
    local stale = command(A, RV.OP_LET_GO, rec, nil, "999")
    T.eq("H7 a stale revision is refused", stale.messageKey .. "/" .. rec.status, "npc_recovery_refused_stale/paused_recovery")
    local tok = rec.recoveryToken
    local go = command(A, RV.OP_LET_GO, rec)
    T.eq("H8 the owning farm lets the held job go while the surface is LOCKED", go.result .. "/" .. go.messageKey, RV.RESULT_OK .. "/npc_contrib_let_go")
    T.ok("H9 it left every collection and its token is retired",
        rec.status == "closed" and not inList(fav.recoveryFavors, rec) and not inList(fav.activeFavors, rec) and fav:getRecoveryRecordByToken(tok) == nil)
    T.eq("H10 no money, trust, failure count, completion or history",
        moneyTotal(1) .. "/" .. (person.relationship - trust0) .. "/" .. ((person.totalFavorsFailed or 0) - failed0) .. "/" .. ((person.totalFavorsCompleted or 0) - done0) .. "/" .. (history(fav) - hist0),
        "0/0/0/0/0")
    T.eq("H11 the neighbour is free of the obligation", fav:isPersonHeldByContribution(person.id), false)
    local again = command(A, RV.OP_LET_GO, rec)
    T.ok("H12 a second LET_GO finds nothing to close", again.result ~= RV.RESULT_OK)
end)()

-- =========================================================
-- M: the companion goes away; LET_GO is the farmer's exit
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("rm")
    local fav = server.favorSystem
    local rec = recordOf(server, offer("alex", 1).favorId)
    accept(server, A, person, rec, "1")
    MONEY = {}
    local trust0 = person.relationship
    handle():unregisterCompanionProvider(NS)
    T.eq("M1 an absent companion holds the job COMPANION_MISSING", rec.contributionHoldReason, "COMPANION_MISSING")
    local res = command(A, RV.OP_RESUME, rec)
    T.eq("M2 it cannot be resumed while the companion is missing", res.messageKey, "npc_recovery_refused_not_resumable")
    local go = command(A, RV.OP_LET_GO, rec)
    T.eq("M3 the farmer lets it go without fault", go.result .. "/" .. rec.status .. "/" .. (person.relationship - trust0) .. "/" .. moneyTotal(1), RV.RESULT_OK .. "/closed/0/0")
end)()

-- =========================================================
-- U: the unlock with an away neighbour, then Resume (3.8, v1.1)
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("ru")
    local fav = server.favorSystem
    local bea = claimed(server, "bea", 600, 600)
    standAt(B, bea.position.x, bea.position.z)
    local away = recordOf(server, offer("bea", 1).favorId)
    accept(server, B, bea, away, "1")
    advance(HOUR)
    lock(server)
    tickFavours(server)
    local frozen = away.timeRemaining
    server:setPersonLive(bea, false, NPCPersonRoster.REASON_WAITING_COUNT)
    open(server)
    tickFavours(server)
    T.eq("U1 unlock keeps an away neighbour's job in Recovery under the neighbour pause",
        tostring(inList(fav.recoveryFavors, away)) .. "/" .. tostring(away.recoveryReason) .. "/" .. tostring(away.contributionHeld), "true/" .. RV.REASON_NEIGHBOUR_UNAVAILABLE .. "/false")
    local letgo = command(A, RV.OP_LET_GO, away)
    T.eq("U2 a cleared lock hold offers no LET_GO", letgo.result .. "/" .. letgo.messageKey .. "/" .. away.status, RV.RESULT_REFUSED .. "/npc_recovery_refused_operation/paused_recovery")
    local early = command(A, RV.OP_RESUME, away)
    T.eq("U3 resume waits for the neighbour", early.result .. "/" .. early.messageKey, RV.RESULT_REFUSED .. "/npc_recovery_unavail_waiting")
    local stranger = command(C, RV.OP_RESUME, away, A)
    T.eq("U4 another farm cannot resume it", stranger.messageKey, "npc_recovery_refused_not_owner")
    server:setPersonLive(bea, true)
    advance(2 * HOUR)
    local res = command(A, RV.OP_RESUME, away)
    T.eq("U5 resume works once the neighbour is back", res.result .. "/" .. res.messageKey, RV.RESULT_OK .. "/npc_recovery_ok_resumed")
    T.eq("U6 the resumed job is active work", tostring(inList(fav.activeFavors, away)) .. "/" .. away.status .. "/" .. tostring(away.recoveryReason), "true/active/nil")
    T.eq("U7 its frozen remaining time is re-based", away.expirationGameTime, g_currentMission.time + frozen)
    T.ok("U8 it keeps its contribution and is never marked recovered from legacy", NPCCompanion.isContributed(away) and away.recoveredFromLegacy ~= true)
    MONEY = {}
    handle():reportFavorStep(NS, { favorId = away.id, outcome = "irrigation_done", farmId = 1 })
    local done = workAction(B, IE.ACTION_FAVOR_COMPLETE, bea.id, 1, sel("2", rowFor(server, away, B)))
    T.eq("U9 a resumed job still finishes at the neighbour and pays once", done.messageKey .. "/" .. moneyTotal(1), "npc_dialog_completed/400")
end)()

-- =========================================================
-- W: the person goes waiting (3.8)
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("rw")
    local fav = server.favorSystem
    local bea = claimed(server, "bea", 600, 600)
    local pending = recordOf(server, offer("bea", 1).favorId)
    local tok, rev = pending.recoveryToken, pending.recordRevision
    local trust0, failed0 = bea.relationship, bea.totalFavorsFailed or 0
    server:setPersonLive(bea, false, NPCPersonRoster.REASON_WAITING_COUNT)
    T.eq("W1 a waiting person's pending companion offer closes", pending.status .. "/" .. tostring(inList(fav.activeFavors, pending)), "closed/false")
    T.ok("W2 its token is retired and its revision bumped, so the provider sees it closed", fav:getRecoveryRecordByToken(tok) == nil and pending.recordRevision == rev + 1)
    T.eq("W3 without fault", (bea.relationship - trust0) .. "/" .. ((bea.totalFavorsFailed or 0) - failed0), "0/0")
    local rec = recordOf(server, offer("alex", 1).favorId)
    accept(server, A, person, rec, "1")
    server:setPersonLive(person, false, NPCPersonRoster.REASON_WAITING_COUNT)
    T.eq("W4 accepted companion work pauses as neighbour_unavailable, keeping its block",
        rec.status .. "/" .. tostring(rec.recoveryReason) .. "/" .. tostring(NPCCompanion.isContributed(rec)), "paused_recovery/" .. RV.REASON_NEIGHBOUR_UNAVAILABLE .. "/true")
    T.eq("W5 and keeps its neighbour occupied", fav:isPersonHeldByContribution(person.id), true)
    local go = command(A, RV.OP_LET_GO, rec)
    T.eq("W6 a merely paused job is resumed, not let go", go.messageKey .. "/" .. rec.status, "npc_recovery_refused_operation/paused_recovery")
    server:setPersonLive(person, true)
    local res = command(A, RV.OP_RESUME, rec)
    T.eq("W7 it resumes through the contributed branch once she is back", res.messageKey .. "/" .. rec.status, "npc_recovery_ok_resumed/active")
end)()

-- =========================================================
-- B: built-in recovery keeps its behaviour; LET_GO is companion-only
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("rb")
    local fav = server.favorSystem
    local bea = claimed(server, "bea", 600, 600)
    standAt(A, bea.position.x, bea.position.z)
    dice({ 0.99, rollFor(fav, bea, "watch_property", 1) })
    local offerReply = request(A, R.OP_OFFER_HELP, bea.id, "1")
    realDice()
    local builtIn = nil
    for _, f in ipairs(fav.activeFavors) do if f.npcId == bea.id and not NPCCompanion.isContributed(f) then builtIn = f end end
    T.ok("B1 a built-in favour was offered through OFFER_HELP", offerReply ~= nil and builtIn ~= nil)
    workAction(A, IE.ACTION_FAVOR_ACCEPT, bea.id, 1, sel("2", offerReply.rows[1]))
    server:setPersonLive(bea, false, NPCPersonRoster.REASON_WAITING_COUNT)
    T.eq("B2 the built-in job pauses as before", builtIn.status .. "/" .. tostring(builtIn.recoveryReason), "paused_recovery/" .. RV.REASON_NEIGHBOUR_UNAVAILABLE)
    local go = command(A, RV.OP_LET_GO, builtIn)
    T.eq("B3 LET_GO refuses built-in work", go.result .. "/" .. go.messageKey .. "/" .. builtIn.status, RV.RESULT_REFUSED .. "/npc_recovery_refused_operation/paused_recovery")
    server:setPersonLive(bea, true)
    local res = command(A, RV.OP_RESUME, builtIn)
    T.eq("B4 built-in Resume still goes through F148 (recovered from legacy)", res.messageKey .. "/" .. tostring(builtIn.recoveredFromLegacy), "npc_recovery_ok_resumed/true")
end)()

-- =========================================================
-- F: the farm lifecycle (3.9)
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("rf")
    local fav = server.favorSystem
    local bea = claimed(server, "bea", 600, 600)
    local pending = recordOf(server, offer("bea", 2).favorId)
    local job = recordOf(server, offer("alex", 2).favorId)
    accept(server, C, person, job, "1")
    MONEY = {}
    local trust0, failed0, hist0 = person.relationship, person.totalFavorsFailed or 0, history(fav)
    server:onFarmDeletedMessage(2)
    T.eq("F1 a FARM_DELETED while the farm is live changes nothing", pending.status .. "/" .. job.status, "pending/active")
    local farm2 = LIVE_FARMS[2]
    LIVE_FARMS[2] = nil
    server:onFarmDeletedMessage(2)
    T.eq("F2 deleting the farm closes its companion offer and job", pending.status .. "/" .. job.status, "closed/closed")
    T.ok("F3 never orphaned into Recovery as owner_farm_deleted", not inList(fav.recoveryFavors, job) and job.recoveryReason == nil)
    T.eq("F4 without fault", moneyTotal(2) .. "/" .. (person.relationship - trust0) .. "/" .. ((person.totalFavorsFailed or 0) - failed0) .. "/" .. (history(fav) - hist0), "0/0/0/0")
    -- a missed notice: the number is reused before FARM_DELETED arrives
    LIVE_FARMS[2] = farm2
    local late = recordOf(server, offer("alex", 2).favorId)
    accept(server, C, person, late, "2")
    LIVE_FARMS[2] = nil
    LIVE_FARMS[2] = { farmId = 2, name = "New Farm 2", money = 0 }
    server:onFarmCreatedMessage(2)
    T.eq("F5 a new farm reusing the number never inherits the old farm's job", late.status .. "/" .. tostring(inList(fav.activeFavors, late)), "closed/false")
    local fresh = recordOf(server, offer("alex", 2).favorId)
    server:onFarmDeletedMessage(2)
    T.eq("F6 the old farm's delayed FARM_DELETED leaves the new farm's work alone", fresh.status, "pending")
    LIVE_FARMS[2] = farm2
end)()

T.summary()
