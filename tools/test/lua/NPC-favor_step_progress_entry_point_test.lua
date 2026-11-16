-- NPC favor step progress on a dedicated server: a joined player's walking completes the steps.
--!load: src/utils/NPCFarmIdentity.lua, src/settings/NPCSettings.lua, src/scripts/NPCPersonRoster.lua, src/scripts/NPCRelationshipManager.lua, src/scripts/NPCFavorSystem.lua, src/scripts/NPCFavorRecovery.lua, src/scripts/NPCFieldWork.lua, src/scripts/NPCAI.lua, src/scripts/ContractorModBridge.lua, src/scripts/NPCInteractionUI.lua, src/events/NPCStateSyncEvent.lua, src/events/NPCInteractionEvent.lua, src/events/NPCPersonDialogEvents.lua, src/integrations/NPCStateLedgerBridge.lua, src/integrations/NPCNetworkSyncBridge.lua, src/NPCSystem.lua, src/scripts/NPCPersonDialog.lua, src/gui/NPCDialog.lua, src/gui/NPCListDialog.lua, src/gui/NPCAdminEditDialog.lua, src/gui/NPCFavorManagementDialog.lua, src/scripts/NPCFavorHUD.lua, src/settings/NPCFavorGUI.lua
--
--!text: translations/lang_en.xml, src/gui/NPCFavorManagementDialog.lua
-- THE ENTRY-POINT BAR. A favour is offered through the client's OFFER_HELP and accepted through
-- the client's accept event, both arriving on a real connection (writeStream, readStream and
-- run with the connection), so the record, its owner farm and its step locations are what the
-- host built. Its steps then progress only through NPCSystem:update, the host's own per-frame
-- tick, which is the call production makes: updatePlayerPosition, then favorSystem:update, then
-- checkFavorProgress. A dedicated server has no local player (g_server set, g_localPlayer nil),
-- so its own position reads as invalid and the old step check, which read only that, never saw a
-- joined player walk up to a step. Nothing here hand-completes a step, hand-sets a progress or
-- feeds the check a position: the players stand where the engine's player list says they stand.
--
-- What this proves: which players the server counts for a step, and that the player's own work
-- page then names the next step. What it does not: the real Player position getters on a
-- remote player in the engine (the same getter the talk distance check already relies on), the
-- HUD arrow's drawing, or the "Step done" flash, which the server raises on its own HUD only.

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
local USERS, CONN_FARM, PLAYERS, PLAYER_OF = {}, {}, {}, {}
local MONEY = {}          -- addMoney ledger by farm
local BROADCASTS = 0
local function newConnection(name, userId, farmId)
    local c = { name = name, sent = {} }
    c.sendEvent = function(self, ev) self.sent[#self.sent + 1] = ev end
    USERS[c] = { getId = function() return userId end, getIsMasterUser = function() return false end }
    CONN_FARM[c] = farmId
    return c
end
-- The engine's own list (PlayerSystem.players is an array) of Player objects: each
-- answers getFarmId and getPosition, the two reads the server's step check makes.
local function standAt(conn, x, z)
    local p = PLAYER_OF[conn]
    if p == nil then
        p = { connection = conn, farm = CONN_FARM[conn] }
        p.getFarmId = function(self) return self.farm end
        p.getPosition = function(self) return self.x, 5, self.z end
        PLAYER_OF[conn] = p
        PLAYERS[#PLAYERS + 1] = p
    end
    p.x, p.z = x, z
    return p
end
local function clearPlayers()
    for i = #PLAYERS, 1, -1 do PLAYERS[i] = nil end
    PLAYER_OF = {}
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
        playerSystem = { players = PLAYERS, getPlayerByConnection = function(_, conn) return PLAYER_OF[conn] end },
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

-- =========================================================
-- Rows
-- =========================================================
local function rowOf(favor) return { token = tostring(favor.recoveryToken), recordRevision = favor.recordRevision or 0 } end
local function near(loc, dx, dz) return loc.x + (dx or 0), loc.z + (dz or 0) end
local function done(favor)
    local s = {}
    for i, step in ipairs(favor.steps) do s[i] = step.completed and "1" or "0" end
    return table.concat(s)
end

-- A dedicated server: g_server and no local player. One favour is offered and then
-- accepted by connection A (farm 1) through the client's own events, so the record,
-- its owner farm and its step locations are exactly what the host built. Returns the
-- host, its mission, connections A and C (farm 2), the person, the favour system and
-- the accepted favour.
local function dedicated(dir)
    clearPlayers()
    local server, sm = boot({ placeables = town(4), maxNPCs = 3, dir = dir })
    SIDE.server = { sys = server, mission = sm, g_server = g_server, localPlayer = nil }
    for _, npc in ipairs(server.activeNPCs) do npc.personality = "friendly" npc.relationship = 30 end
    useServer()
    local A = newConnection("A", 11, 1)
    local C = newConnection("C", 13, 2)
    local p1 = server:getNPCById(1)
    standAt(A, p1.position.x, p1.position.z)
    p1.relationship = 45
    local fs = server.favorSystem
    dice({ 0.99, rollFor(fs, p1, "help_harvest", 1) })
    request(A, R.OP_OFFER_HELP, 1, "1")
    realDice()
    local favor = fs.activeFavors[1]
    local accepted = workAction(A, IE.ACTION_FAVOR_ACCEPT, 1, 1, sel("2", rowOf(favor)))
    return server, sm, A, C, p1, fs, favor, accepted
end
local function tick(server) useServer() server:update(16) end

-- =========================================================
-- P: a joined player's walking completes the favour's steps on a dedicated server
-- =========================================================
do
    local server, sm, A, C, p1, fs, favor, accepted = dedicated("p1")
    local s1, s2 = favor.steps[1].location, favor.steps[2].location
    T.eq("P0 [reached] a help_harvest favour is accepted by farm 1, with a field step and a home step more than 30 m apart",
        tostring(accepted and accepted.result) .. "/" .. favor.status .. "/" .. tostring(favor.ownerFarmId) .. "/" .. #favor.steps
            .. "/" .. tostring(VectorHelper.distance2D(s1.x, s1.z, s2.x, s2.z) > 30),
        R.RESULT_ACCEPTED .. "/active/1/2/true")

    standAt(A, near(s1, 45, 0))
    tick(server)
    T.eq("P1 a dedicated server has no local player and reads no position of its own (the case the old step check could not see past)",
        tostring(g_localPlayer) .. "/" .. tostring(server.playerPositionValid), "nil/false")
    T.eq("P2 the owning farm's player 45 m from the field step completes nothing", done(favor) .. "/" .. tostring(favor.progress == 0), "00/true")

    standAt(C, near(s1))
    tick(server)
    T.eq("P3 a player of another farm standing exactly on the field step completes nothing", done(favor) .. "/" .. tostring(favor.progress == 0), "00/true")

    standAt(A, near(s1, 20, 0))
    tick(server)
    T.eq("P4 NAMED [entry point]: the owning farm's player 20 m from the field step completes it, and only it",
        done(favor) .. "/" .. tostring(favor.progress == 50), "10/true")

    local reply = request(A, R.OP_VIEW_WORK, 0, "5")
    local row = reply and reply.rows and reply.rows[1]
    T.eq("P5 the player's own work page now names step 2 as the next step, so the arrow jumps on",
        tostring(row and row.nextStepId) .. "/" .. tostring(row and row.nextStepLocationPresent), "2/true")
    T.near("P6 and its location is the home point, in x", row and row.nextStepX or -1, s2.x, 0.01)
    T.near("P7 and in z", row and row.nextStepZ or -1, s2.z, 0.01)

    standAt(A, near(s2, 0, 25))
    tick(server)
    T.eq("P8 walking on to the home step completes the favour", favor.status .. "/" .. tostring(favor.progress == 100), "completed/true")
    T.eq("P9 no stream fault", FAULTS, 0)
end

do
    -- Two players of the owning farm: the far one is listed first, the near one second.
    local server, sm, A, C, p1, fs, favor = dedicated("p2")
    local B = newConnection("B", 12, 1)
    local s1 = favor.steps[1].location
    standAt(A, near(s1, 200, 0))
    standAt(B, near(s1, 0, 10))
    -- Two entries the engine would never list, in front of the real players: one with no
    -- getFarmId and one whose getFarmId raises. Neither may stop the check.
    table.insert(PLAYERS, 1, { getPosition = function() return s1.x, 5, s1.z end })
    table.insert(PLAYERS, 1, { getFarmId = function() error("no farm") end, getPosition = function() return s1.x, 5, s1.z end })
    tick(server)
    T.eq("P10 any player of the owning farm counts: one far and listed first, one near, completes the step, with two broken list entries skipped",
        done(favor) .. "/" .. tostring(favor.progress == 50), "10/true")
end

do
    -- A listen host: the local player is in the engine's list like any other, and
    -- g_localPlayer is the same object. The host's own farm decides whether its walking counts.
    local server, sm, A, C, p1, fs, favor = dedicated("p3")
    local s1 = favor.steps[1].location
    local hostConn = newConnection("H", 99, 1)
    local host = standAt(hostConn, near(s1, 0, 5))
    standAt(A, near(s1, 300, 0))
    SIDE.server.localPlayer = host
    useServer()
    tick(server)
    T.eq("P11 a listen host of the owning farm standing 5 m from the step completes it, and reads its own position",
        done(favor) .. "/" .. tostring(server.playerPositionValid), "10/true")

    local server2, sm2, A2, C2, p12, fs2, favor2 = dedicated("p4")
    local t1 = favor2.steps[1].location
    local hostConn2 = newConnection("H", 99, 2)
    local host2 = standAt(hostConn2, near(t1, 0, 5))
    standAt(A2, near(t1, 300, 0))
    SIDE.server.localPlayer = host2
    useServer()
    tick(server2)
    T.eq("P12 a listen host that belongs to another farm standing on the step completes nothing for this farm's favour",
        done(favor2), "00")
end

do
    -- The favour's own owner is not an ordinary farm: no one matches, whoever stands there.
    local server, sm, A, C, p1, fs, favor = dedicated("p5")
    local s1 = favor.steps[1].location
    favor.ownerFarmId = 0
    local S = newConnection("S", 14, 0)
    standAt(S, near(s1))
    standAt(A, near(s1))
    tick(server)
    T.eq("P13 a favour with no ordinary owner farm completes nothing, even with a spectator and a farm player on its step", done(favor), "00")
end

do
    -- No player system to ask (an offline bench): the machine's own position is used, as it always was.
    local server, sm, A, C, p1, fs, favor = dedicated("p6")
    local s1 = favor.steps[1].location
    local me = { getPosition = function() return s1.x + 4, 5, s1.z end }
    g_localPlayer = me
    SIDE.server.localPlayer = me
    sm.playerSystem = nil
    tick(server)
    T.eq("P14 with no player system the local position still completes the step, as before", done(favor), "10")
end

T.eq("P15 no stream fault anywhere in the file", FAULTS, 0)
