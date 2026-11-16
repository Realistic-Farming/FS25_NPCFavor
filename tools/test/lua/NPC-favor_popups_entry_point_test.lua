-- NPC favor step progress on a dedicated server: a joined player's walking completes the steps.
--!load: src/utils/NPCFarmIdentity.lua, src/settings/NPCSettings.lua, src/scripts/NPCPersonRoster.lua, src/scripts/NPCRelationshipManager.lua, src/scripts/NPCFavorSystem.lua, src/scripts/NPCFavorRecovery.lua, src/events/NPCFavorFlashEvent.lua, src/scripts/NPCFavorFlash.lua, src/scripts/NPCFieldWork.lua, src/scripts/NPCAI.lua, src/scripts/ContractorModBridge.lua, src/scripts/NPCInteractionUI.lua, src/events/NPCStateSyncEvent.lua, src/events/NPCInteractionEvent.lua, src/events/NPCPersonDialogEvents.lua, src/integrations/NPCStateLedgerBridge.lua, src/integrations/NPCNetworkSyncBridge.lua, src/NPCSystem.lua, src/scripts/NPCPersonDialog.lua, src/gui/NPCDialog.lua, src/gui/NPCListDialog.lua, src/gui/NPCAdminEditDialog.lua, src/gui/NPCFavorManagementDialog.lua, src/scripts/NPCFavorHUD.lua, src/settings/NPCFavorGUI.lua
--
--!text: translations/lang_en.xml, src/gui/NPCFavorManagementDialog.lua
-- Favour pop-ups reach the players they belong to, not only the host's own screen.
-- THE ENTRY-POINT BAR. A favour is offered through the client's OFFER_HELP and accepted through the
-- client's accept event, both arriving on a real connection (writeStream, readStream and run with the
-- connection). Its pop-ups are then raised only by the host's own sim: NPCSystem:update, the call
-- production makes each frame, for steps, completion and expiry, and the random generator for a public
-- offer. The server is a dedicated one (g_server set, no local player) unless a row sets up a listen
-- host. Each connected player is a Player object in the engine's player list with a farm and a
-- connection, so what a player is sent is read off its connection; a pure client receives an event
-- through its own readStream and run, and its screen is a recording HUD. Nothing hand-calls a pop-up,
-- a send or a screen.
--
-- What this proves: who is sent which pop-up, in what words and colour a receiving screen shows it, that
-- a host's own screen follows the same audience, and the wire. What it does not: the real HUD drawing,
-- the engine's own connection and event dispatch, or a game with real players (the TESTING.md row).

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
local HUD_TEXT = { npc_hud_new_favor = "New: %s needs help!", npc_hud_completed = "Done: %s", npc_hud_step_done = "Step %d done: %s",
    npc_hud_failed = "Failed: %s", npc_hud_cancelled = "Cancelled: %s", npc_hud_perfect = "Perfect! %s bonus!" }
g_i18n = { getText = function(_, key) return HUD_TEXT[key] or key end, hasText = function(_, key) return HUD_TEXT[key] ~= nil end }
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
FLASH = {}
NPCFavorHUD.new = function(sys) return { npcSystem = sys, loadFromSettings = function() end,
    flashFavor = function(self, msg, color) FLASH[#FLASH + 1] = { side = self.npcSystem.isServer and "server" or "client", msg = msg, color = color } end,
    update = function() end, delete = function() end } end
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
    local c = { name = name, sent = {}, flashes = {} }
    -- Pop-up events are kept apart from replies, so a request still counts exactly its own answer.
    c.sendEvent = function(self, ev)
        if ev.className == "NPCFavorFlashEvent" then self.flashes[#self.flashes + 1] = ev else self.sent[#self.sent + 1] = ev end
    end
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
        if conn == nil then
            -- A server without a local player has no farm of its own (FSBaseMission.lua:1067-1085).
            if g_server ~= nil and g_localPlayer == nil then return nil end
            return self.localFarmId
        end
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
local KIND = NPCFavorFlashEvent.KIND
local function rowOf(favor) return { token = tostring(favor.recoveryToken), recordRevision = favor.recordRevision or 0 } end
local function near(loc, dx, dz) return loc.x + (dx or 0), loc.z + (dz or 0) end
local function tick(server) useServer() server:update(16) end

-- What a connection was sent, one entry per pop-up: kind:step:text.
local function got(conn)
    local t = {}
    for i, ev in ipairs(conn.flashes) do t[i] = ev.kind .. ":" .. ev.n .. ":" .. ev.text end
    return table.concat(t, "|")
end
local function count(conn, kind)
    local n = 0
    for _, ev in ipairs(conn.flashes) do if ev.kind == kind then n = n + 1 end end
    return n
end
-- The pop-ups a side's own screen showed, in order.
local function lastOf(conn, kind)
    for i = #conn.flashes, 1, -1 do if conn.flashes[i].kind == kind then return conn.flashes[i] end end
end
-- The pop-ups a side's own screen showed, in order.
local function screen(side)
    local t = {}
    for _, f in ipairs(FLASH) do if f.side == side then t[#t + 1] = f.msg end end
    return table.concat(t, "|")
end

-- One favour for a person, offered and accepted by a connection through the client's own events.
local function acceptFor(conn, personId, farmId)
    useServer()
    local server = SIDE.server.sys
    local npc = server:getNPCById(personId)
    local fs = server.favorSystem
    standAt(conn, npc.position.x, npc.position.z)
    npc.relationship = 45
    local before = #fs.activeFavors
    dice({ 0.99, rollFor(fs, npc, "help_harvest", farmId) })
    request(conn, R.OP_OFFER_HELP, personId, "1")
    realDice()
    local favor = fs.activeFavors[before + 1]
    local accepted = workAction(conn, IE.ACTION_FAVOR_ACCEPT, personId, farmId, sel("2", rowOf(favor)))
    return favor, accepted
end

-- A server (dedicated unless a listen host is set up), a pure client that receives what
-- is sent, and three connected players: A and B on farm 1, C on farm 2, all standing far
-- from every person until a row moves them.
local function popupWorld(dir)
    clearPlayers()
    FLASH = {}
    local placeables = town(4)
    local server, sm = boot({ placeables = placeables, maxNPCs = 3, dir = dir })
    SIDE.server = { sys = server, mission = sm, g_server = g_server, localPlayer = nil }
    local client, cm = boot({ placeables = placeables, maxNPCs = 3, dir = dir, server = false, localFarmId = 1 })
    SIDE.client = { sys = client, mission = cm }
    useServer()
    for _, npc in ipairs(server.activeNPCs) do npc.personality = "friendly" npc.relationship = 30 end
    local A = newConnection("A", 11, 1)
    local B = newConnection("B", 12, 1)
    local C = newConnection("C", 13, 2)
    standAt(A, 5000, 5000)
    standAt(B, 5000, 5000)
    standAt(C, 5000, 5000)
    return server, sm, A, B, C
end

-- =========================================================
-- Q: a favour's pop-ups reach the players it belongs to, on a dedicated server
-- =========================================================
do
    local server, sm, A, B, C = popupWorld("q1")
    local favor, accepted = acceptFor(A, 1, 1)
    T.eq("Q0 [reached] a dedicated server holds an accepted favour of farm 1, with a field step and a home step",
        tostring(accepted and accepted.result) .. "/" .. favor.status .. "/" .. tostring(favor.ownerFarmId) .. "/" .. #favor.steps,
        R.RESULT_ACCEPTED .. "/active/1/2")
    T.eq("Q1 NAMED [entry point]: accepting raised 'Favor accepted' for both players of farm 1 and for nobody else",
        got(A) .. "/" .. got(B) .. "/" .. #C.flashes,
        KIND.ACCEPTED .. ":0:" .. favor.description .. "/" .. KIND.ACCEPTED .. ":0:" .. favor.description .. "/0")
    T.eq("Q2 the dedicated server's own screen showed nothing (it has no farm and no player)", screen("server"), "")

    local s1, s2 = favor.steps[1].location, favor.steps[2].location
    standAt(A, near(s1, 20, 0))
    tick(server)
    T.eq("Q3 NAMED: a step walked on a dedicated server raised 'Step 1 done' for both players of farm 1, not for farm 2",
        count(A, KIND.STEP_DONE) .. "/" .. count(B, KIND.STEP_DONE) .. "/" .. count(C, KIND.STEP_DONE),
        "1/1/0")
    local ev = A.flashes[#A.flashes]
    T.eq("Q4 the event carries the kind, the step id and the step's own words",
        ev.kind .. ":" .. ev.n .. ":" .. ev.text, KIND.STEP_DONE .. ":1:" .. favor.steps[1].description)

    -- The event travels the wire into a pure client, which shows it in its own words.
    useClient()
    roundTrip(ev, nil)
    T.eq("Q5 the joined player's own screen shows 'Step 1 done' with the step's words, in green",
        screen("client"), "Step 1 done: " .. favor.steps[1].description)
    T.eq("Q6 and its colour is the green step pop-up", table.concat(FLASH[#FLASH].color, ","), "0.3,1,0.3,1")

    standAt(A, near(s2, 0, 25))
    tick(server)
    T.eq("Q7 finishing the favour raised 'Done' for farm 1's players and nobody else",
        count(A, KIND.COMPLETED) .. "/" .. count(B, KIND.COMPLETED) .. "/" .. count(C, KIND.COMPLETED), "1/1/0")
    T.eq("Q8 and its text is the favour's own description", lastOf(A, KIND.COMPLETED).text, favor.description)
    T.eq("Q9 no stream fault so far", FAULTS, 0)
end

do
    -- A favour that runs out of time: 'Failed' goes to its farm only.
    local server, sm, A, B, C = popupWorld("q2")
    local favor = acceptFor(A, 1, 1)
    advance(100 * 3600 * 1000)
    tick(server)
    T.eq("Q10 an expired favour raised 'Failed' for farm 1's players, and nobody else",
        favor.status .. "/" .. count(A, KIND.FAILED) .. "/" .. count(B, KIND.FAILED) .. "/" .. count(C, KIND.FAILED), "failed/1/1/0")
    useClient()
    roundTrip(A.flashes[#A.flashes], nil)
    T.eq("Q11 and the joined player's screen reads 'Failed:' in red", screen("client") .. "/" .. table.concat(FLASH[#FLASH].color, ","),
        "Failed: " .. favor.description .. "/1,0.3,0.3,1")
end

do
    -- An offer nobody owns yet belongs to everyone who has a farm.
    local server, sm, A, B, C = popupWorld("q3")
    local S = newConnection("S", 14, 0)
    standAt(S, 5000, 5000)
    server.settings.enableFavors = true
    useServer()
    advance(20000)
    dice({ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 })
    tick(server)
    realDice()
    T.eq("Q12 the random generator made an offer nobody owns", #server.favorSystem.activeFavors .. "/" .. tostring(server.favorSystem.activeFavors[1] and server.favorSystem.activeFavors[1].ownerFarmId), "1/nil")
    T.eq("Q13 NAMED: a public offer's 'New: ... needs help!' reached every player with a farm, and not the one without",
        count(A, KIND.NEW_FAVOR) .. "/" .. count(B, KIND.NEW_FAVOR) .. "/" .. count(C, KIND.NEW_FAVOR) .. "/" .. #S.flashes, "1/1/1/0")
    local offer = server.favorSystem.activeFavors[1]
    T.eq("Q14 and it names the person who asks", lastOf(A, KIND.NEW_FAVOR).text .. "/" .. lastOf(C, KIND.NEW_FAVOR).n, tostring(offer.npcName) .. "/0")
end

-- =========================================================
-- H: a listen host's own screen follows the same audience
-- =========================================================
do
    local server, sm, A, B, C = popupWorld("h1")
    local hostConn = newConnection("H", 99, 1)
    local host = standAt(hostConn, 5000, 5000)
    SIDE.server.localPlayer = host
    useServer()
    local favor1 = acceptFor(A, 1, 1)
    T.eq("H1 a listen host of farm 1 saw 'Favor accepted' for farm 1's favour on its own screen",
        screen("server"), "Favor accepted: " .. favor1.description)
    T.eq("H2 the host's own player is not sent the event (its screen shows it directly)", #hostConn.flashes, 0)
    T.eq("H3 farm 1's joined player was sent it", count(A, KIND.ACCEPTED), 1)
    local before = #FLASH
    local favor2 = acceptFor(C, 2, 2)
    T.eq("H4 farm 2's favour accepted by a farm 2 player", tostring(favor2.ownerFarmId), "2")
    T.eq("H5 NAMED: the host of farm 1 saw nothing of farm 2's favour on its own screen", #FLASH - before, 0)
    T.eq("H6 farm 2's player was sent it, farm 1's players were not sent it", count(C, KIND.ACCEPTED) .. "/" .. count(A, KIND.ACCEPTED) .. "/" .. count(B, KIND.ACCEPTED), "1/1/1")
end

-- =========================================================
-- W: the wire and the receiving side
-- =========================================================
do
    local server, sm, A, B, C = popupWorld("w1")
    local long = string.rep("a", 199) .. "\195\169" .. "tail"
    local ev = NPCFavorFlashEvent.new(KIND.COMPLETED, 7, long)
    local s = _sfMockStream()
    ev:writeStream(s, nil)
    useClient()
    local rx = NPCFavorFlashEvent.emptyNew()
    local before = #FLASH
    rx:readStream(s, nil)
    T.eq("W1 the stream drained exactly, no type errors", (s.r - 1) .. "/" .. s.typeErrors .. "/" .. s.underflows, #s.q .. "/0/0")
    T.eq("W2 text is cut at 200 bytes on a character boundary (the 2-byte character is dropped whole)",
        #rx.text .. "/" .. tostring(rx.text:sub(-1) == "a"), "199/true")
    T.eq("W3 a received pop-up shows once on the receiving screen", #FLASH - before, 1)
    local bad = NPCFavorFlashEvent.new(9, 1, "x")
    local sb = _sfMockStream()
    bad:writeStream(sb, nil)
    local rb = NPCFavorFlashEvent.emptyNew()
    local before2 = #FLASH
    local realPrint, logged = print, {}
    print = function(...) logged[#logged + 1] = table.concat({ ... }, " ") end
    rb:readStream(sb, nil)
    print = realPrint
    T.eq("W4 a kind outside the range is dropped at readStream, shows nothing and is logged once",
        (#FLASH - before2) .. "/" .. #logged .. "/" .. tostring((logged[1] or ""):find("Invalid favour pop-up kind", 1, true) ~= nil), "0/1/true")
    -- A pop-up arriving at the server is ignored: only a client shows it.
    useServer()
    local before3 = #FLASH
    local srx = NPCFavorFlashEvent.emptyNew()
    local ss = _sfMockStream()
    NPCFavorFlashEvent.new(KIND.COMPLETED, 0, "x"):writeStream(ss, nil)
    srx:readStream(ss, A)
    T.eq("W5 an event arriving at the server from a connection shows nothing there", #FLASH - before3, 0)
    local realText = HUD_TEXT.npc_hud_step_done
    HUD_TEXT.npc_hud_step_done = "Schritt %s fertig"
    local okMsg, msg = pcall(NPCFavorFlashEvent.compose, KIND.STEP_DONE, 3, "Hof")
    HUD_TEXT.npc_hud_step_done = "Schritt fertig %d %d %d"
    local okMsg2, msg2 = pcall(NPCFavorFlashEvent.compose, KIND.STEP_DONE, 3, "Hof")
    HUD_TEXT.npc_hud_step_done = realText
    T.eq("W6 a translation with the wrong placeholders still gives a sentence, in the English fallback for a step pop-up",
        tostring(okMsg) .. "/" .. tostring(msg) .. "/" .. tostring(okMsg2) .. "/" .. tostring(msg2),
        "true/Schritt 3 fertig/true/Step 3 done: Hof")
    T.eq("W7 no stream fault anywhere in the file", FAULTS, 0)
end
