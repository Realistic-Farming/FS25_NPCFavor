-- RSF-F357 actions and private views: remote dialogs carry intent, host state alone mutates.
--!load: src/utils/NPCFarmIdentity.lua, src/settings/NPCSettings.lua, src/scripts/NPCPersonRoster.lua, src/scripts/NPCRelationshipManager.lua, src/scripts/NPCFavorSystem.lua, src/scripts/NPCFavorRecovery.lua, src/scripts/NPCFieldWork.lua, src/scripts/NPCAI.lua, src/scripts/ContractorModBridge.lua, src/scripts/NPCInteractionUI.lua, src/events/NPCStateSyncEvent.lua, src/events/NPCInteractionEvent.lua, src/events/NPCPersonDialogEvents.lua, src/integrations/NPCStateLedgerBridge.lua, src/integrations/NPCNetworkSyncBridge.lua, src/NPCSystem.lua, src/scripts/NPCPersonDialog.lua, src/gui/NPCDialog.lua, src/gui/NPCListDialog.lua, src/gui/NPCAdminEditDialog.lua, src/gui/NPCFavorManagementDialog.lua, src/scripts/NPCFavorHUD.lua, src/settings/NPCFavorGUI.lua
--
-- THE ENTRY-POINT BAR. Every request enters where production enters it: a
-- client's NPCPersonDialogRequestEvent or NPCInteractionEvent goes through
-- writeStream on a typed mock stream and readStream on the server side with
-- the requesting connection, which is what the engine does with a received
-- event; readStream calls run, run resolves the actor from the connection
-- through the mission's userManager and farm lookup, and the dispatcher
-- answers through that connection's sendEvent. The reply event then travels
-- the same stream back and lands through its own readStream, run and
-- dispatch on the client's adapter. The listen host / single player path
-- enters through NPCPersonDialogRequestEvent.sendRequest and
-- NPCInteractionEvent.sendToServer with g_server and g_localPlayer present,
-- exactly as the dialog's button handlers call them. Both systems boot
-- through NPCSystem.new, onMissionLoaded and the first-frame init updater
-- (the host fills its town from the fixture's houses; the pure client
-- becomes READY from one snapshot page through NPCStateSyncEvent). Nothing
-- hand-fills a favour list, a token, a session, a request id or a view: the
-- offers come from OFFER_HELP through the dispatcher, the tokens from the
-- favour system's own allocator, the views from the replies.
--
-- What this proves: the actions and private views contract, offline. What it
-- does not: native transport, the real Player position getters, GUI element
-- rendering, the RF PDA host (A3, A5, A7 are native observations owed at
-- release).

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
-- W: the wire
-- =========================================================
do
    local req = NPCPersonDialogRequestEvent.new({ requestId = "7", op = R.OP_TALK, personId = 2, cursor = "" })
    local s = _sfMockStream()
    req:writeStream(s, nil)
    local rx = NPCPersonDialogRequestEvent.emptyNew()
    g_server, g_NPCSystem = nil, nil
    rx:readStream(s, nil)
    T.eq("W1 request round trip: id, op, person, cursor", rx.request.requestId .. "/" .. rx.request.op .. "/" .. rx.request.personId .. "/" .. rx.request.cursor, "7/1/2/")
    T.eq("W2 the request stream drained exactly, no type errors", (s.r - 1) .. "/" .. s.typeErrors .. "/" .. s.underflows, #s.q .. "/0/0")
    local bad = NPCPersonDialogRequestEvent.new({ requestId = "8", op = 9, personId = 2, cursor = "" })
    local ran = false
    local s2 = _sfMockStream()
    bad:writeStream(s2, nil)
    local rx2 = NPCPersonDialogRequestEvent.emptyNew()
    rx2.run = function() ran = true end
    rx2:readStream(s2, nil)
    T.eq("W3 an operation outside the range is dropped at readStream, run never called", ran, false)

    local long = string.rep("a", 255) .. "\195\169" .. "tail"
    local row = { token = "12345678901234", recordRevision = "3", personIdPresent = true, personId = 2, npcName = "Greta", status = "pending",
        type = "fix_fence", description = long, progress = 12.5, timeKnown = true, timeRemainingMs = 4200, rewardMoney = 1500,
        nextStepText = "Meet at the farm", nextStepId = 1, nextStepLocationPresent = true, nextStepX = 10.5, nextStepZ = -3,
        isDialogStep = false, isLoanRepayStep = true, awaitingConfirmation = false, loanAmountPresent = true, loanAmount = 5000,
        recoveredFromLegacy = false, canAccept = true, canComplete = false, canAbandon = true, completed = false }
    local rows = {}
    for i = 1, 25 do rows[i] = row end
    local reply = { requestId = "7", kind = R.KIND_WORK_PAGE, op = R.OP_VIEW_WORK, personId = 0, farmId = 1, result = R.RESULT_OK,
        messageKey = "npc_dialog_ok", text = long, toneKey = "npc_dialog_tone_warm", topicKey = "npc_topic_weather", trustPresent = true, trust = 31.5, cursor = "", nextCursor = "20",
        total = 25, totalKnown = true, sampledTime = 1000, completedCount = 4, completedKnown = true, rows = rows }
    local s3 = _sfMockStream()
    NPCPersonDialogReplyEvent.new(reply):writeStream(s3, nil)
    local rx3 = NPCPersonDialogReplyEvent.emptyNew()
    rx3:readStream(s3, nil)
    local got = rx3.reply
    T.eq("W4 the reply stream drained exactly, no type errors", (s3.r - 1) .. "/" .. s3.typeErrors .. "/" .. s3.underflows, #s3.q .. "/0/0")
    T.eq("W5 header fields travel", got.requestId .. "/" .. got.kind .. "/" .. got.op .. "/" .. got.farmId .. "/" .. got.result .. "/" .. got.messageKey, "7/2/4/1/1/npc_dialog_ok")
    T.eq("W6 trust, tone and the topic key travel", tostring(got.trust) .. "/" .. tostring(got.toneKey) .. "/" .. tostring(got.topicKey), "31.5/npc_dialog_tone_warm/npc_topic_weather")
    T.eq("W7 the page fields travel", got.nextCursor .. "/" .. got.total .. "/" .. tostring(got.totalKnown) .. "/" .. got.completedCount .. "/" .. tostring(got.completedKnown), "20/25/true/4/true")
    T.eq("W8 a page never carries more than 20 rows on the wire", #got.rows, 20)
    T.eq("W9 text is cut at 256 bytes on a character boundary (the 2-byte character is dropped whole)", #got.text .. "/" .. tostring(got.text:sub(-1) == "a"), "255/true")
    local r1 = got.rows[1]
    T.eq("W10 a row's token is cut to the 10-character wire number", r1.token, "1234567890")
    T.eq("W11 a row's facts travel", r1.personId .. "/" .. r1.npcName .. "/" .. r1.status .. "/" .. r1.progress .. "/" .. r1.timeRemainingMs .. "/" .. r1.rewardMoney .. "/" .. r1.nextStepX .. "/" .. r1.loanAmount, "2/Greta/pending/12.5/4200/1500/10.5/5000")
    T.eq("W12 a row's flags travel", tostring(r1.isLoanRepayStep) .. tostring(r1.canAccept) .. tostring(r1.canComplete) .. tostring(r1.canAbandon) .. tostring(r1.loanAmountPresent), "truetruefalsetruetrue")
    local absent = { token = "5", recordRevision = "0", personIdPresent = false, personId = 77, nextStepLocationPresent = false, nextStepX = 9, loanAmountPresent = false, loanAmount = 9 }
    local s4 = _sfMockStream()
    NPCPersonDialogReplyEvent.new({ requestId = "1", kind = 2, op = 4, farmId = 1, result = 1, rows = { absent }, trustPresent = false, trust = 5 }):writeStream(s4, nil)
    local rx4 = NPCPersonDialogReplyEvent.emptyNew()
    rx4:readStream(s4, nil)
    local a = rx4.reply.rows[1]
    T.eq("W13 an absent person, location or loan reads as absent, never as its placeholder", a.personId .. "/" .. a.nextStepX .. "/" .. a.loanAmount .. "/" .. tostring(rx4.reply.trust), "0/0/0/nil")
end

-- =========================================================
-- A: the actor and the entry
-- =========================================================
do
    local server, client, A, B, C = world({ dir = "a" })
    local p1 = server:getNPCById(1)
    standAt(A, p1.position.x + 3, p1.position.z)
    local reply, n = request(A, R.OP_VIEW, 1, "1")
    T.eq("A1 a remote request from a known connection is answered on that connection", n .. "/" .. tostring(reply and reply.result), "1/" .. R.RESULT_NO_WORK)
    T.eq("A2 the answer names the actor's farm and the person", reply.farmId .. "/" .. reply.personId, "1/1")
    T.eq("A3 nobody else received it and nothing was broadcast", #B.sent .. "/" .. #C.sent .. "/" .. BROADCASTS, "0/0/0")
    local ghost = { sent = {}, sendEvent = function(self, ev) self.got = (self.got or 0) + 1 end }
    local _, n2 = request(ghost, R.OP_VIEW, 1, "1")
    T.eq("A4 a connection without a user is refused silently", n2 .. "/" .. tostring(ghost.got), "0/nil")
    local S = newConnection("S", 14, 0)
    standAt(S, p1.position.x, p1.position.z)
    local r3 = request(S, R.OP_VIEW, 1, "1")
    T.eq("A5 a spectator's dialog request is refused as no farm", r3.result .. "/" .. r3.messageKey, R.RESULT_REFUSED .. "/npc_dialog_refused_farm")
    local _, n4 = workAction(S, IE.ACTION_FAVOR_ACCEPT, 1, 0, "1|1|0")
    T.eq("A6 a spectator's work action gets no reply at all", n4, 0)
    local _, n5 = workAction(A, IE.ACTION_FAVOR_ACCEPT, 1, 2, "1|1|0")
    T.eq("A7 a claim for a farm that is not the actor's is dropped", n5, 0)
    -- The dedicated server has no local actor: the local entry refuses.
    useServer()
    g_localPlayer = nil
    T.eq("A8 dedicated server: the local dialog entry refuses without a local player, even for the proximity-free page", NPCPersonDialogRequestEvent.sendRequest({ requestId = "1", op = R.OP_VIEW_WORK, personId = 0, cursor = "" }), false)
    T.eq("A9 dedicated server: the local work entry refuses too", NPCInteractionEvent.sendToServer(IE.ACTION_FAVOR_ACCEPT, 1, 1, 0, "1|1|0"), false)
    -- The listen host acts through the same dispatcher as a remote actor.
    SIDE.server.localPlayer = localPlayer()
    useServer()
    hostAt(p1.position.x, p1.position.z + 4)
    server:beginPersonDialog(1)
    local sent = server:requestPersonDialogAction("VIEW", 1, nil)
    local view = server:getPersonDialogView(1)
    T.eq("A10 listen host: the local entry executes and the reply lands on the local adapter", tostring(sent) .. "/" .. tostring(view.available) .. "/" .. tostring(view.result), "true/true/" .. R.RESULT_NO_WORK)
    T.eq("A11 the host's own request id allocator started at 1", view.lastRequestId, "1")
    server:endPersonDialog()
    T.eq("A12 no stream fault so far", FAULTS, 0)
end

-- =========================================================
-- G: the per-connection request gate
-- =========================================================
do
    local server, client, A, B, C = world({ dir = "g" })
    local p1 = server:getNPCById(1)
    standAt(A, p1.position.x, p1.position.z)
    standAt(B, p1.position.x, p1.position.z)
    local first = request(A, R.OP_TALK, 1, "5")
    T.eq("G1 a fresh id executes: Talk credited", first.result .. "/" .. first.messageKey .. "/" .. tostring(first.trust), R.RESULT_OK .. "/npc_dialog_talk_ok/31")
    local again = request(A, R.OP_TALK, 1, "5")
    T.eq("G2 the same id with the same request replays the retained result (not re-executed: a rerun would read LIMIT)", again.result .. "/" .. tostring(again.trust), R.RESULT_OK .. "/31")
    T.eq("G3 the replay credited nothing", p1.relationship, 31)
    local changed = request(A, R.OP_VIEW, 1, "5")
    T.eq("G4 the same id with a different request is refused as reuse", changed.result .. "/" .. changed.messageKey, R.RESULT_REFUSED .. "/npc_dialog_refused_request_reuse")
    local _, n = request(A, R.OP_VIEW, 1, "4")
    T.eq("G5 an older id is stale: nothing is sent back", n, 0)
    local _, n2 = request(A, R.OP_VIEW, 1, "x5")
    T.eq("G6 a malformed id is dropped", n2, 0)
    local ex = request(A, R.OP_VIEW, 1, tostring(NPCFarmIdentity.WIRE_MAX))
    T.eq("G7 the last wire number is exhaustion, not a request", ex.result .. "/" .. ex.messageKey, R.RESULT_UNAVAILABLE .. "/npc_dialog_unavailable")
    local other = request(B, R.OP_VIEW, 1, "5")
    T.eq("G8 another connection's id 5 is fresh (per-connection gate)", other.result, R.RESULT_NO_WORK)
    local next1 = request(A, R.OP_VIEW, 1, "6")
    T.eq("G9 a larger id is fresh again", next1.result, R.RESULT_NO_WORK)
    -- A farm change under the same id is not a replay.
    CONN_FARM[A] = 2
    local moved = request(A, R.OP_VIEW, 1, "6")
    T.eq("G10 the same id after a farm change is refused as changed", moved.result .. "/" .. moved.messageKey, R.RESULT_REFUSED .. "/npc_dialog_refused_request_reuse")
    CONN_FARM[A] = 1
    -- The work-action gate is the same gate: a work action id below the dialog high-water is stale.
    local _, n3 = workAction(A, IE.ACTION_FAVOR_ACCEPT, 1, 1, "3|1|0")
    T.eq("G11 a work action with an older id is stale: nothing is sent", n3, 0)
    -- A disconnect clears the session: id 1 is fresh once the user is removed.
    useServer()
    server:onUserRemovedMessage(USERS[A])
    local fresh = request(A, R.OP_VIEW, 1, "1")
    T.eq("G12 after the user left, the connection's ids start over", fresh.result, R.RESULT_NO_WORK)
    T.eq("G13 no stream fault", FAULTS, 0)
end

-- =========================================================
-- D: the exact acting player's distance
-- =========================================================
do
    local server, client, A, B, C = world({ dir = "d" })
    local p1 = server:getNPCById(1)
    standAt(A, p1.position.x + 50, p1.position.z)       -- the actor, far
    standAt(B, p1.position.x + 2, p1.position.z)        -- a farm-mate, next to her
    local far = request(A, R.OP_TALK, 1, "1")
    T.eq("D1 a farm-mate standing next to the person does not bring the actor near", far.result .. "/" .. far.messageKey, R.RESULT_REFUSED .. "/npc_dialog_refused_far")
    T.eq("D2 nothing was credited", p1.relationship, 30)
    PLAYERS[A] = nil
    local unknown = request(A, R.OP_TALK, 1, "2")
    T.eq("D3 an actor whose position cannot be established is refused, never treated as near", unknown.result .. "/" .. unknown.messageKey, R.RESULT_REFUSED .. "/npc_dialog_refused_far")
    PLAYERS[A] = { getPosition = function() return 0 / 0, 5, p1.position.z end }
    local nan = request(A, R.OP_TALK, 1, "3")
    T.eq("D4 a non-finite position is unknown", nan.result, R.RESULT_REFUSED)
    standAt(A, p1.position.x + 14.9, p1.position.z)
    local near = request(A, R.OP_TALK, 1, "4")
    T.eq("D5 the actor at 14.9 m is near", near.result, R.RESULT_OK)
    standAt(A, p1.position.x + 15.1, p1.position.z)
    local edge = request(A, R.OP_VIEW, 1, "5")
    T.eq("D6 the actor at 15.1 m is far", edge.messageKey, "npc_dialog_refused_far")
    -- A player in a vehicle: the getter is the state machine's own, the root node only a fallback.
    PLAYERS[A] = { rootNode = 0, getPosition = function() return p1.position.x, 5, p1.position.z end }
    T.eq("D7 the position getter wins over the root node", (request(A, R.OP_VIEW, 1, "6")).result, R.RESULT_NO_WORK)
    NODES[999] = { x = p1.position.x, y = 5, z = p1.position.z }
    PLAYERS[A] = { rootNode = 999 }
    T.eq("D8 without a getter the root node's translation is used", (request(A, R.OP_VIEW, 1, "7")).result, R.RESULT_NO_WORK)
    local _, n = workAction(A, IE.ACTION_FAVOR_ACCEPT, 1, 1, "8|1|0")
    standAt(A, p1.position.x + 40, p1.position.z)
    local wfar = workAction(A, IE.ACTION_FAVOR_ACCEPT, 1, 1, "9|1|0")
    T.eq("D9 a work action from too far is refused with a reply", wfar.result .. "/" .. wfar.messageKey, R.RESULT_REFUSED .. "/npc_dialog_refused_far")
    PLAYERS[A] = nil
    local wunk = workAction(A, IE.ACTION_FAVOR_ACCEPT, 1, 1, "10|1|0")
    T.eq("D10 a work action from an unknown position is refused, never let through", wunk.result .. "/" .. wunk.messageKey, R.RESULT_REFUSED .. "/npc_dialog_refused_far")
end

-- =========================================================
-- T: Talk
-- =========================================================
do
    local server, client, A, B, C = world({ dir = "t" })
    local p2 = server:getNPCById(2)
    standAt(A, p2.position.x, p2.position.z + 5)
    standAt(C, p2.position.x, p2.position.z - 5)
    p2.encounters = { { type = "gift_given", sentiment = "positive", time = 1000 } }
    local talk = request(A, R.OP_TALK, 2, "1")
    T.eq("T1 Talk applies the +1 daily input and reports the trust", talk.result .. "/" .. tostring(talk.trust) .. "/" .. p2.relationship, R.RESULT_OK .. "/31/31")
    T.eq("T2 the reply carries the topic as a key with its English fallback; the host resolved nothing", tostring(talk.topicKey):match("^npc_topic_") ~= nil and talk.text ~= "" and talk.text:find("^npc_topic_") == nil, true)
    T.eq("T3 the tone key travels from the encounter memory", talk.toneKey, "npc_dialog_tone_warm")
    local limit = request(A, R.OP_TALK, 2, "2")
    T.eq("T4 a second Talk the same day is the day's limit, trust unchanged", limit.result .. "/" .. limit.messageKey .. "/" .. p2.relationship, R.RESULT_LIMIT .. "/npc_dialog_talk_limit/31")
    local other = request(C, R.OP_TALK, 2, "1")
    T.eq("T5 the daily limit is the person's, not the farm's", other.result .. "/" .. p2.relationship, R.RESULT_LIMIT .. "/31")
    T.eq("T6 the host marks its sync dirty after a credit", server.syncDirty, true)
    p2.live = false
    local gone = request(A, R.OP_TALK, 2, "3")
    T.eq("T7 a person who is not live is refused as a person", gone.messageKey, "npc_dialog_refused_person")
    p2.live = true
    local none = request(A, R.OP_TALK, 42, "4")
    T.eq("T8 a number nobody has is refused as a person", none.messageKey, "npc_dialog_refused_person")
end

-- =========================================================
-- O: Offer help
-- =========================================================
do
    local server, client, A, B, C = world({ dir = "o" })
    local p1, p2, p3 = server:getNPCById(1), server:getNPCById(2), server:getNPCById(3)
    standAt(A, p1.position.x, p1.position.z)
    p1.relationship = 24
    local low = request(A, R.OP_OFFER_HELP, 1, "1")
    T.eq("O1 below the threshold the offer is refused, nothing created", low.messageKey .. "/" .. #server.favorSystem.activeFavors, "npc_dialog_refused_relationship/0")
    p1.relationship = 30
    p1.personality = "grumpy"
    dice({ 0.1 })
    local declined = request(A, R.OP_OFFER_HELP, 1, "2")
    realDice()
    T.eq("O2 the personality decline roll runs on the server", declined.result .. "/" .. declined.messageKey .. "/" .. declined.text, R.RESULT_DECLINED .. "/npc_dialog_declined/grumpy")
    T.eq("O3 a decline creates nothing and starts no cooldown", #server.favorSystem.activeFavors .. "/" .. tostring(p1.favorCooldown or 0), "0/0")
    p1.personality, p1.relationship = "friendly", 45
    dice({ 0.99, rollFor(server.favorSystem, p1, "watch_property", 1) })
    local offer = request(A, R.OP_OFFER_HELP, 1, "3")
    realDice()
    local row = offer.rows[1]
    T.eq("O4 an offer is created on the host and attached as one row", offer.result .. "/" .. offer.messageKey .. "/" .. #offer.rows, R.RESULT_OFFER .. "/npc_dialog_offer/1")
    T.eq("O5 the row names the person, the type and the first step", row.personId .. "/" .. row.type .. "/" .. row.nextStepText, "1/watch_property/Go to NPC's property")
    T.eq("O6 the row carries the host token and revision 0, and only Accept is on", row.token .. "/" .. row.recordRevision .. "/" .. tostring(row.canAccept) .. tostring(row.canComplete) .. tostring(row.canAbandon), server.favorSystem.activeFavors[1].recoveryToken .. "/0/truefalsefalse")
    T.ok("O7 the token is the favour system's own", tonumber(row.token) > 0 and server.favorSystem:getRecoveryRecordByToken(tonumber(row.token)) == server.favorSystem.activeFavors[1])
    T.eq("O8 the offer is a public one: unowned, unpaid, unprogressed", tostring(server.favorSystem.activeFavors[1].ownerFarmId) .. "/" .. tostring(server.favorSystem.activeFavors[1].rewardPaid), "nil/false")
    T.eq("O9 the generation cooldown started", p1.favorCooldown > 0, true)
    local again = request(A, R.OP_OFFER_HELP, 1, "4")
    T.eq("O10 a second Offer help returns the same offer, never a duplicate", again.result .. "/" .. again.rows[1].token .. "/" .. #server.favorSystem.activeFavors, R.RESULT_OFFER .. "/" .. row.token .. "/1")
    local seen = request(C, R.OP_OFFER_HELP, 1, "1")
    standAt(C, p1.position.x, p1.position.z)
    seen = request(C, R.OP_OFFER_HELP, 1, "2")
    T.eq("O11 another farm sees the same public offer", seen.result .. "/" .. seen.rows[1].token, R.RESULT_OFFER .. "/" .. row.token)
    -- The acting farm's balance is what a money requirement reads (loan_money needs 5000).
    p3.relationship = 60
    local loanType
    for _, ft in ipairs(server.favorSystem.favorTypes) do if ft.id == "loan_money" then loanType = ft end end
    T.eq("O12 a money requirement reads the acting farm's balance, not the host player's", tostring(server.favorSystem:checkFavorRequirements(p3, loanType, 3)) .. "/" .. tostring(server.favorSystem:checkFavorRequirements(p3, loanType, 2)), "false/true")
    T.eq("O13 with no acting farm and no host player the requirement is unmet", server.favorSystem:checkFavorRequirements(p3, loanType, nil), false)
    T.eq("O14 no stream fault", FAULTS, 0)
end

-- =========================================================
-- K: work actions bound to the work shown
-- =========================================================
do
    local server, client, A, B, C = world({ dir = "k" })
    local p1, p2 = server:getNPCById(1), server:getNPCById(2)
    standAt(A, p1.position.x, p1.position.z)
    standAt(B, p1.position.x, p1.position.z)
    standAt(C, p1.position.x, p1.position.z)
    p1.relationship = 45
    dice({ 0.99, rollFor(server.favorSystem, p1, "watch_property", 1) })
    local offer = request(A, R.OP_OFFER_HELP, 1, "1")
    realDice()
    local row = offer.rows[1]
    local favor = server.favorSystem.activeFavors[1]
    MONEY = {}
    -- Accept: the cooldown from the generation is no barrier.
    T.ok("K0 the generation cooldown is running", p1.favorCooldown > 0)
    local stale = workAction(A, IE.ACTION_FAVOR_ACCEPT, 1, 1, "2|" .. row.token .. "|5")
    T.eq("K1 a revision that is not the one shown is stale", stale.result .. "/" .. stale.messageKey .. "/" .. favor.status, R.RESULT_STALE .. "/npc_dialog_refused_stale/pending")
    local _, n = workAction(A, IE.ACTION_FAVOR_ACCEPT, 1, 1, "3|x|0")
    T.eq("K2 a malformed selection is dropped without a reply", n .. "/" .. favor.status, "0/pending")
    standAt(B, p2.position.x, p2.position.z)
    local wrong = workAction(B, IE.ACTION_FAVOR_ACCEPT, 2, 1, sel("1", row))
    T.eq("K3 a token of another person's work is stale for this person", wrong.result .. "/" .. wrong.messageKey .. "/" .. favor.status, R.RESULT_STALE .. "/npc_dialog_refused_stale/pending")
    local accepted = workAction(A, IE.ACTION_FAVOR_ACCEPT, 1, 1, sel("5", row))
    T.eq("K4 the offer shown is accepted for the actor's farm", accepted.result .. "/" .. accepted.messageKey .. "/" .. favor.status .. "/" .. tostring(favor.ownerFarmId), R.RESULT_ACCEPTED .. "/npc_dialog_accepted/active/1")
    T.eq("K5 the accept bumped the revision and kept the token", favor.recordRevision .. "/" .. tostring(favor.recoveryToken == tonumber(row.token)), "1/true")
    T.eq("K6 the reply names the request it answers", accepted.requestId .. "/" .. accepted.kind, "5/" .. R.KIND_ACTION)
    local replay = workAction(A, IE.ACTION_FAVOR_ACCEPT, 1, 1, sel("5", row))
    T.eq("K7 the same accept replays its result without a second accept", replay.result .. "/" .. favor.recordRevision, R.RESULT_ACCEPTED .. "/1")
    do
        local actorA = NPCFarmIdentity.resolveActor(A)
        local okR, cachedR = NPCInteractionEvent.execute(IE.ACTION_FAVOR_ACCEPT, 1, 1, 0, sel("5", row), actorA)
        T.eq("K7b the replayed accept reports success to a host caller (ACCEPTED is a success)", tostring(okR) .. "/" .. tostring(cachedR and cachedR.result), "true/" .. R.RESULT_ACCEPTED)
    end
    local twice = workAction(A, IE.ACTION_FAVOR_ACCEPT, 1, 1, sel("6", row))
    T.eq("K8 accepting again with the old revision is stale", twice.result .. "/" .. favor.status, R.RESULT_STALE .. "/active")
    T.eq("K9 only the requester got the replies", #A.sent .. "/" .. #B.sent .. "/" .. BROADCASTS, "5/1/0")
    -- View: the owner sees the work, another farm reads busy without details.
    local mine = request(A, R.OP_VIEW, 1, "7")
    T.eq("K10 the owner's view is the accepted work", mine.result .. "/" .. mine.rows[1].status .. "/" .. tostring(mine.rows[1].canAbandon), R.RESULT_ACCEPTED .. "/active/true")
    local theirs = request(C, R.OP_VIEW, 1, "1")
    T.eq("K11 another farm reads busy with no row", theirs.result .. "/" .. theirs.messageKey .. "/" .. #theirs.rows, R.RESULT_BUSY .. "/npc_dialog_busy/0")
    local offerBusy = request(C, R.OP_OFFER_HELP, 1, "2")
    T.eq("K12 and cannot get a second offer from a busy person", offerBusy.result .. "/" .. #server.favorSystem.activeFavors, R.RESULT_BUSY .. "/1")
    -- Complete: the server re-derives the step condition; client flags mean nothing.
    local current = mine.rows[1]
    local early = workAction(A, IE.ACTION_FAVOR_COMPLETE, 1, 1, sel("8", current))
    T.eq("K13 completion before the travel step is done is refused as not ready (not stale: the selection still matches)", early.result .. "/" .. early.messageKey .. "/" .. favor.status, R.RESULT_REFUSED .. "/npc_dialog_refused_not_ready/active")
    local notOwner = workAction(C, IE.ACTION_FAVOR_COMPLETE, 1, 2, sel("3", current))
    T.eq("K14 another farm cannot complete it", notOwner.result .. "/" .. notOwner.messageKey .. "/" .. favor.status, R.RESULT_REFUSED .. "/npc_recovery_refused_not_owner/active")
    local notOwnerAbandon = workAction(C, IE.ACTION_FAVOR_ABANDON, 1, 2, sel("4", current))
    T.eq("K15 nor abandon it", notOwnerAbandon.messageKey .. "/" .. favor.status, "npc_recovery_refused_not_owner/active")
    standAt(B, p2.position.x, p2.position.z)
    local crossAbandon = workAction(B, IE.ACTION_FAVOR_ABANDON, 2, 1, sel("2", current))
    T.eq("K15b person 1's token through person 2's abandon is stale, the work untouched", crossAbandon.result .. "/" .. crossAbandon.messageKey .. "/" .. favor.status, R.RESULT_STALE .. "/npc_dialog_refused_stale/active")
    favor.steps[1].completed = true   -- the player arrived (the progress tracker's own fact)
    local view2 = request(A, R.OP_VIEW, 1, "9")
    T.eq("K16 with the travel step done the dialog step is next and Complete is on", view2.rows[1].nextStepText .. "/" .. tostring(view2.rows[1].isDialogStep) .. "/" .. tostring(view2.rows[1].canComplete), "Talk to NPC to complete the watch/true/true")
    -- The owner refuses after the dialog condition passed (here: no server): the step it marked is unmarked again.
    do
        local savedServer = g_server
        g_server = nil
        local okC, whyC = server:serverCompleteFavor(p1, 1, { token = tonumber(row.token), recordRevision = favor.recordRevision })
        g_server = savedServer
        T.eq("K16b when the owner refuses the completion the record keeps the facts it had", tostring(okC) .. "/" .. whyC .. "/" .. tostring(favor.steps[2].completed) .. "/" .. favor.status, "false/npc_dialog_refused_stale/false/active")
    end
    local reward = favor.reward.money or 0
    local rel = p1.relationship
    local done = workAction(A, IE.ACTION_FAVOR_COMPLETE, 1, 1, sel("10", view2.rows[1]))
    T.eq("K17 completion through the dialog step pays the owner farm once", done.result .. "/" .. done.messageKey .. "/" .. favor.status .. "/" .. tostring(MONEY[1]), R.RESULT_OK .. "/npc_dialog_completed/completed/" .. reward)
    T.eq("K18 the token is retired and the revision moved", tostring(server.favorSystem:getRecoveryRecordByToken(tonumber(row.token))) .. "/" .. tostring(favor.recordRevision > 1), "nil/true")
    T.eq("K19 trust moved by the reward", p1.relationship > rel, true)
    local afterDone = workAction(A, IE.ACTION_FAVOR_COMPLETE, 1, 1, sel("11", view2.rows[1]))
    T.eq("K20 completing again is stale: the money is paid once", afterDone.result .. "/" .. MONEY[1], R.RESULT_STALE .. "/" .. reward)
    -- Abandon: bound the same way.
    standAt(A, p2.position.x, p2.position.z)
    dice({ 0.99 })
    local offer2 = request(A, R.OP_OFFER_HELP, 2, "12")
    realDice()
    local row2 = offer2.rows[1]
    local favor2 = server.favorSystem:getRecoveryRecordByToken(tonumber(row2.token))
    workAction(A, IE.ACTION_FAVOR_ACCEPT, 2, 1, sel("13", row2))
    local shown = request(A, R.OP_VIEW, 2, "14").rows[1]
    local ab = workAction(A, IE.ACTION_FAVOR_ABANDON, 2, 1, sel("15", shown))
    T.eq("K21 abandon of the work shown", ab.result .. "/" .. ab.messageKey .. "/" .. favor2.status, R.RESULT_OK .. "/npc_dialog_abandoned/abandoned")
    T.eq("K22 its token is retired", server.favorSystem:getRecoveryRecordByToken(tonumber(row2.token)), nil)
    -- The remote relationship action is not a trust writer.
    local before = p2.relationship
    local _, nr = workAction(A, IE.ACTION_RELATIONSHIP, 2, 1, "", 50)
    T.eq("K23 a client-supplied relationship change is refused silently", nr .. "/" .. p2.relationship, "0/" .. before)
    -- A gift: server balance, server deduction, trust in the reply.
    local money = LIVE_FARMS[1].money
    local gift = workAction(A, IE.ACTION_GIFT, 2, 1, "money", 500)
    T.eq("K24 a gift moves money on the server and reports the trust", gift.result .. "/" .. gift.messageKey .. "/" .. tostring(gift.trust) .. "/" .. (money - LIVE_FARMS[1].money), R.RESULT_OK .. "/npc_dialog_gift_ok/" .. p2.relationship .. "/500")
    LIVE_FARMS[3].money = 0
    standAt(C, p2.position.x, p2.position.z)
    CONN_FARM[C] = 3
    local poor = workAction(C, IE.ACTION_GIFT, 2, 3, "money", 500)
    T.eq("K25 an unaffordable gift is refused before any deduction", poor.result .. "/" .. LIVE_FARMS[3].money, R.RESULT_REFUSED .. "/0")
    CONN_FARM[C] = 2
    T.eq("K26 no stream fault", FAULTS, 0)
end

-- =========================================================
-- P: the farm-private work page
-- =========================================================
do
    local server, client, A, B, C = world({ dir = "p" })
    local p1, p2 = server:getNPCById(1), server:getNPCById(2)
    standAt(A, p1.position.x, p1.position.z)
    standAt(C, p2.position.x, p2.position.z)
    p1.relationship = 45
    dice({ 0.99, rollFor(server.favorSystem, p1, "watch_property", 1) })
    local o1 = request(A, R.OP_OFFER_HELP, 1, "1").rows[1]
    realDice()
    workAction(A, IE.ACTION_FAVOR_ACCEPT, 1, 1, sel("2", o1))
    dice({ 0.99 })
    local o2 = request(C, R.OP_OFFER_HELP, 2, "1").rows[1]
    realDice()
    local mine = request(A, R.OP_VIEW_WORK, 0, "3")
    T.eq("P1 farm 1's page: its accepted work and the public offer", mine.result .. "/" .. mine.kind .. "/" .. #mine.rows .. "/" .. mine.total .. "/" .. tostring(mine.totalKnown), R.RESULT_OK .. "/" .. R.KIND_WORK_PAGE .. "/2/2/true")
    local theirs = request(C, R.OP_VIEW_WORK, 0, "2")
    T.eq("P2 farm 2's page: only the public offer, never farm 1's work", #theirs.rows .. "/" .. theirs.rows[1].status .. "/" .. theirs.rows[1].personId, "1/pending/2")
    T.eq("P3 the page needs no proximity", (function() standAt(C, 9999, 9999) return request(C, R.OP_VIEW_WORK, 0, "3").result end)(), R.RESULT_OK)
    T.eq("P4 the completed count is known and zero, not absent", tostring(mine.completedKnown) .. "/" .. mine.completedCount, "true/0")
    local legacy = server.favorSystem:getRecoveryRecordByToken(tonumber(o2.token))
    legacy.recoveredFromLegacy = true   -- a resumed legacy row is never a public offer
    local held = request(C, R.OP_VIEW_WORK, 0, "4")
    standAt(C, p2.position.x, p2.position.z)
    local heldView = request(C, R.OP_VIEW, 2, "5")
    T.eq("P4b a pending row with the legacy mark is off the page and not an offer in the dialog", #held.rows .. "/" .. heldView.result, "0/" .. R.RESULT_NO_WORK)
    legacy.recoveredFromLegacy = false
    local S = newConnection("S", 15, 0)
    local spec = request(S, R.OP_VIEW_WORK, 0, "1")
    T.eq("P5 a spectator has no page", spec.result .. "/" .. spec.messageKey, R.RESULT_REFUSED .. "/npc_dialog_refused_farm")
    -- Readiness: a host still WAITING on its ledger answers UNAVAILABLE, never a claimed zero.
    local held = boot({ placeables = town(3), maxNPCs = 2, dir = "p-held", ledger = newLedger(nil, true) })
    SIDE.server = { sys = held, mission = g_currentMission, g_server = g_server, localPlayer = nil }
    local H = newConnection("H", 16, 1)
    standAt(H, 0, 0)
    local un = request(H, R.OP_VIEW_WORK, 0, "1")
    T.eq("P6 a WAITING host's page is unavailable with no total", un.result .. "/" .. un.messageKey .. "/" .. tostring(un.totalKnown), R.RESULT_UNAVAILABLE .. "/npc_work_view_unavailable/false")
    local unTalk = request(H, R.OP_TALK, 1, "2")
    T.eq("P7 and a person request says the people are loading", unTalk.result .. "/" .. unTalk.messageKey, R.RESULT_UNAVAILABLE .. "/npc_person_loading")
    T.eq("P8 no stream fault", FAULTS, 0)
end

-- Paging: 21 offers through the host's own dialog entry, 20 rows a page.
do
    local placeables = town(22)
    local server, sm = boot({ placeables = placeables, maxNPCs = 21, dir = "pg" })
    SIDE.server = { sys = server, mission = sm, g_server = g_server, localPlayer = localPlayer() }
    useServer()
    T.eq("P9 twenty-one people", #server.activeNPCs, 21)
    dice({})
    for _, npc in ipairs(server.activeNPCs) do
        npc.personality, npc.relationship = "friendly", 30
        hostAt(npc.position.x, npc.position.z)
        server:beginPersonDialog(npc.id)
        server:requestPersonDialogAction("OFFER_HELP", npc.id, nil)
        server:endPersonDialog()
    end
    realDice()
    T.eq("P10 twenty-one offers exist on the host", #server.favorSystem.activeFavors, 21)
    server:requestPersonalWorkView("")
    local page1 = server:getPersonalWorkView()
    T.eq("P11 the first page holds 20 rows, the total is 21, a cursor follows", page1.state .. "/" .. #page1.rows .. "/" .. page1.total .. "/" .. page1.nextCursor, "CURRENT/20/21/" .. page1.rows[20].token)
    server:requestPersonalWorkView(page1.nextCursor)
    local page2 = server:getPersonalWorkView()
    T.eq("P12 the second page holds the last row", #page2.rows .. "/" .. page2.rows[1].token, "1/" .. server.favorSystem.activeFavors[21].recoveryToken)
    T.ok("P13 rows are ordered by token", tonumber(page1.rows[1].token) < tonumber(page1.rows[20].token) and tonumber(page1.rows[20].token) < tonumber(page2.rows[1].token))
end

-- =========================================================
-- C: the pure client's adapters
-- =========================================================
do
    local server, client, A, B, C = world({ dir = "c" })
    local p1, p2 = server:getNPCById(1), server:getNPCById(2)
    standAt(A, p1.position.x, p1.position.z)
    useClient()
    T.eq("C1 client: READY from the snapshot, no allocation", client.people:getLoadState() .. "/" .. client.people:getHighWater(), "READY/0")
    local sent, why = client:requestPersonDialogAction("VIEW", 1, nil)
    T.eq("C2 no dialog context, no request", tostring(sent) .. "/" .. why, "false/npc_dialog_unavailable")
    client:beginPersonDialog(1)
    local v0 = client:getPersonDialogView(1)
    T.eq("C3 a fresh context is unavailable and not pending", tostring(v0.available) .. "/" .. tostring(v0.pending), "false/false")
    sent = client:requestPersonDialogAction("VIEW", 1, nil)
    local v1 = client:getPersonDialogView(1)
    T.eq("C4 VIEW is sent and pending", tostring(sent) .. "/" .. tostring(v1.pending) .. "/" .. #OUTBOX, "true/true/1")
    local nreq, nrep = exchange(A)
    local v2 = client:getPersonDialogView(1)
    T.eq("C5 the reply landed through the stream on the adapter", nreq .. "/" .. nrep .. "/" .. tostring(v2.available) .. "/" .. tostring(v2.pending) .. "/" .. tostring(v2.result), "1/1/true/false/" .. R.RESULT_NO_WORK)
    T.eq("C6 the first client request id is 1", v2.lastRequestId, "1")
    -- Talk in the client's own language: the host sends the key, this reader resolves it.
    local dlgC = setmetatable({ npc = client:getNPCById(1), npcSystem = client, buttonEnabled = {}, responseText = el(), responseBg = el() }, { __index = NPCDialog })
    NPCDialog.INSTANCE = dlgC
    local origGetText = g_i18n.getText
    g_i18n.getText = function(_, key) if tostring(key):find("^npc_topic_") then return "FR:" .. key end return key end
    client:requestPersonDialogAction("TALK", 1, nil)
    exchange(A)
    local vt = client:getPersonDialogView(1)
    T.eq("C6b Talk: the host sent the topic key, the client painted it in its own language, never the host's text",
        tostring(vt.topicKey):match("^npc_topic_") ~= nil and dlgC.responseText.text:find("FR:npc_topic_", 1, true) ~= nil and dlgC.responseText.text:find(vt.text, 1, true) == nil, true)
    g_i18n.getText = origGetText
    NPCDialog.INSTANCE = nil
    client:requestPersonDialogAction("OFFER_HELP", 1, nil)
    useServer()
    p1.relationship = 45
    dice({ 0.99, rollFor(server.favorSystem, p1, "watch_property", 1) })
    exchange(A)
    realDice()
    local v3 = client:getPersonDialogView(1)
    T.eq("C7 the offer view: a pending row with Accept", tostring(v3.result) .. "/" .. tostring(v3.offer ~= nil) .. "/" .. tostring(v3.offer and v3.offer.canAccept) .. "/" .. tostring(v3.work), R.RESULT_OFFER .. "/true/true/nil")
    v3.offer.token = "9"
    T.eq("C8 the view is a copy: editing it does not touch the adapter's cache", client:getPersonDialogView(1).offer.token ~= "9", true)
    local offer = client:getPersonDialogView(1).offer
    -- A late reply for an older id, or another person, is dropped.
    client:requestPersonDialogAction("VIEW", 1, nil)
    local pendingId = client.dialogClient.pending.requestId
    client:onPersonDialogReply({ requestId = "1", kind = R.KIND_DIALOG, op = R.OP_VIEW, personId = 1, farmId = 1, result = R.RESULT_BUSY, rows = {} })
    T.eq("C9 a reply for an older request id is dropped", tostring(client:getPersonDialogView(1).pending) .. "/" .. tostring(client:getPersonDialogView(1).result), "true/" .. R.RESULT_OFFER)
    client:onPersonDialogReply({ requestId = pendingId, kind = R.KIND_DIALOG, op = R.OP_VIEW, personId = 2, farmId = 1, result = R.RESULT_BUSY, rows = {} })
    T.eq("C10 a reply about another person is dropped", tostring(client:getPersonDialogView(1).pending), "true")
    client:onPersonDialogReply({ requestId = pendingId, kind = R.KIND_DIALOG, op = R.OP_VIEW, personId = 1, farmId = 2, result = R.RESULT_BUSY, rows = {} })
    T.eq("C11 a reply for another farm is dropped", tostring(client:getPersonDialogView(1).pending), "true")
    exchange(A)
    T.eq("C12 the real reply clears the pending", tostring(client:getPersonDialogView(1).pending), "false")
    -- Accept through the adapter: the selection travels as requestId|token|revision.
    sent = client:requestPersonDialogAction("ACCEPT_OFFER", 1, { token = offer.token, recordRevision = offer.recordRevision })
    local ev = OUTBOX[1]
    T.eq("C13 the accept carries the binding", tostring(sent) .. "/" .. ev.className .. "/" .. ev.actionType .. "/" .. ev.data, "true/NPCInteractionEvent/" .. IE.ACTION_FAVOR_ACCEPT .. "/" .. client.dialogClient.pending.requestId .. "|" .. offer.token .. "|" .. offer.recordRevision)
    exchange(A)
    local v4 = client:getPersonDialogView(1)
    T.eq("C14 the accepted result landed on the dialog view", tostring(v4.result) .. "/" .. tostring(v4.kind), R.RESULT_ACCEPTED .. "/" .. R.KIND_ACTION)
    T.eq("C15 the host's record is active for farm 1", server.favorSystem.activeFavors[1].status .. "/" .. tostring(server.favorSystem.activeFavors[1].ownerFarmId), "active/1")
    sent, why = client:requestPersonDialogAction("ACCEPT_OFFER", 1, { token = "abc", recordRevision = "0" })
    T.eq("C16 a selection that is not a wire number is refused locally", tostring(sent) .. "/" .. why, "false/npc_dialog_refused_stale")
    sent, why = client:requestPersonDialogAction("VIEW_WORK", 1, nil)
    T.eq("C17 VIEW_WORK is not a person operation", tostring(sent) .. "/" .. why, "false/npc_dialog_refused_operation")
    -- Ending the dialog clears the view; a late reply cannot reopen it.
    client:requestPersonDialogAction("VIEW", 1, nil)
    client:endPersonDialog()
    exchange(A)
    T.eq("C18 after the dialog closed the view is unavailable and the late reply dropped", tostring(client:getPersonDialogView(1).available) .. "/" .. client:getPersonDialogView(1).reasonKey, "false/npc_dialog_unavailable")
    -- The id allocator never resets on a new dialog.
    client:beginPersonDialog(2)
    client:requestPersonDialogAction("VIEW", 2, nil)
    T.ok("C19 request ids keep climbing across dialogs", tonumber(client.dialogClient.pending.requestId) >= 6)
    OUTBOX = {}
    client:endPersonDialog()
    -- Exhaustion refuses before sending and stays refused.
    local savedNext = client.dialogClient.nextRequestId
    client.dialogClient.nextRequestId = NPCFarmIdentity.WIRE_MAX
    client:beginPersonDialog(2)
    sent, why = client:requestPersonDialogAction("VIEW", 2, nil)
    client.dialogClient.nextRequestId = 1
    local sent2 = client:requestPersonDialogAction("VIEW", 2, nil)
    T.eq("C20 an exhausted allocator refuses and stays exhausted", tostring(sent) .. "/" .. why .. "/" .. tostring(sent2), "false/npc_dialog_unavailable/false")
    client.dialogClient.exhausted, client.dialogClient.nextRequestId = false, savedNext   -- a reconnect (fresh mission) is the only reset
    client:endPersonDialog()
    -- The work page: UNAVAILABLE, PENDING, CURRENT, LAST_CONFIRMED, then released.
    local w0 = client:getPersonalWorkView()
    T.eq("C21 no page yet: UNAVAILABLE with a reason, no total", w0.state .. "/" .. w0.reasonKey .. "/" .. tostring(w0.total), "UNAVAILABLE/npc_work_view_unavailable/nil")
    T.eq("C22 one request goes out and a second waits", tostring(client:requestPersonalWorkView("")) .. "/" .. tostring(client:requestPersonalWorkView("")), "true/false")
    T.eq("C23 while it is out the page is PENDING", client:getPersonalWorkView().state, "PENDING")
    exchange(A)
    local w1 = client:getPersonalWorkView()
    T.eq("C24 the page is CURRENT with farm 1's work", w1.state .. "/" .. #w1.rows .. "/" .. w1.total .. "/" .. w1.rows[1].status .. "/" .. tostring(w1.ageMs), "CURRENT/1/1/active/0")
    advance(4001)
    T.eq("C24b older than two intervals with NO request out it is LAST_CONFIRMED all the same (the age rules, not the pending state)", client:getPersonalWorkView().state .. "/" .. #client:getPersonalWorkView().rows, "LAST_CONFIRMED/1")
    local rowC = client:getPersonalWorkView().rows[1]
    local sentC, whyC = client:requestWorkAction("ABANDON_WORK", 1, { token = rowC.token, recordRevision = rowC.recordRevision })
    T.eq("C24c a reader acting from a last-confirmed page is refused; the page is for looking at", tostring(sentC) .. "/" .. whyC .. "/" .. #OUTBOX, "false/npc_work_view_last_confirmed/0")
    client:requestPersonalWorkView("")
    exchange(A)
    T.eq("C24d a fresh page is CURRENT again", client:getPersonalWorkView().state, "CURRENT")
    client:requestPersonalWorkView("")
    advance(4001)
    T.eq("C25 a page older than two intervals with a request out is LAST_CONFIRMED, rows kept", client:getPersonalWorkView().state .. "/" .. #client:getPersonalWorkView().rows, "LAST_CONFIRMED/1")
    OUTBOX = {}
    advance(4001)
    client:tickPersonalWork(2000)
    T.eq("C26 a request that never came back is released after the grace, watcher or not", tostring(client.dialogClient.work.pendingRequestId), "nil")
    T.eq("C26b the release does not make the old page current: it stays last-confirmed until a reply lands", client:getPersonalWorkView().state, "LAST_CONFIRMED")
    -- Watchers drive the refresh through the system's own update.
    client:watchPersonalWork(true)
    local ok, err = pcall(function() client:update(2000) end)
    T.eq("C27 the update tick issued the refresh for the watcher", tostring(ok) .. "/" .. tostring(client.dialogClient.work.pendingRequestId ~= nil) .. "/" .. #OUTBOX, "true/true/1")
    exchange(A)
    client:watchPersonalWork(false)
    OUTBOX = {}
    client:update(2000)
    T.eq("C28 without a watcher no refresh goes out", #OUTBOX, 0)
    -- A farm change clears every private view.
    client:beginPersonDialog(1)
    SIDE.client.mission.localFarmId = 2
    T.eq("C29 after a farm change the dialog view and the page are refused", client:getPersonDialogView(1).reasonKey .. "/" .. client:getPersonalWorkView().reasonKey, "npc_dialog_refused_farm/npc_dialog_refused_farm")
    client:update(16)
    T.eq("C30 the tick cleared them", tostring(client.dialogClient.context) .. "/" .. #client.dialogClient.work.rows, "nil/0")
    SIDE.client.mission.localFarmId = 1
    T.eq("C31 no stream fault", FAULTS, 0)
end

-- =========================================================
-- H, M: the HUD and the management dialog read the page
-- =========================================================
do
    local server, client, A, B, C = world({ dir = "h" })
    local p1 = server:getNPCById(1)
    standAt(B, p1.position.x, p1.position.z)   -- a farm-mate makes the offer; the client acts over A
    standAt(A, p1.position.x + 3, p1.position.z)
    p1.relationship = 45
    dice({ 0.99, rollFor(server.favorSystem, p1, "watch_property", 1) })
    local o1 = request(B, R.OP_OFFER_HELP, 1, "1").rows[1]
    realDice()
    useClient()
    local hud = setmetatable({ npcSystem = client, animTimer = 0, flashQueue = {} }, NPCFavorHUD_mt)
    T.eq("H1 the HUD shows nothing before a page", #hud:visibleWork(), 0)
    client.settings.showFavorList = true
    hud:update(16)
    T.eq("H2 the HUD registered as a watcher through its own update", client.dialogClient.watchers, 1)
    client:update(2000)
    exchange(A)
    T.eq("H3 the HUD draws the page's open rows", #hud:visibleWork() .. "/" .. hud:visibleWork()[1].status, "1/pending")
    client.settings.showFavorList = false
    hud:update(16)
    T.eq("H4 hiding the list releases the watcher", client.dialogClient.watchers, 0)
    -- The management dialog: rows from the page, a context-free abandon bound to the row.
    local mdlg = setmetatable({ mode = "active", npcSystem = client, page = 1, updates = 0 }, { __index = NPCFavorManagementDialog })
    mdlg.updateDisplay = function(self) self.updates = self.updates + 1 end
    NPCFavorManagementDialog.INSTANCE = mdlg
    local items = mdlg:getPageItems()
    T.eq("M1 the page items are the view's rows with the legacy fields mapped", #items .. "/" .. tostring(items[1].npcId) .. "/" .. tostring(items[1].reward ~= nil), "1/1/true")
    client:requestWorkAction("ACCEPT_OFFER", 1, { token = items[1].token, recordRevision = items[1].recordRevision })
    exchange(A)
    T.eq("M2 the context-free result reached the dialog and asked for a fresh page", tostring(mdlg.footerMessage) .. "/" .. tostring(client.dialogClient.pending) .. "/" .. tostring(client.dialogClient.work.pendingRequestId ~= nil), "npc_dialog_accepted/nil/true")
    exchange(A)
    local row = mdlg:getPageItems()[1]
    T.eq("M3 the refreshed row is the accepted work with Cancel on", row.status .. "/" .. tostring(row.canAbandon) .. "/" .. tostring(row.canComplete), "active/true/false")
    mdlg.favorIndices = {}
    mdlg.favor1cancel, mdlg.favor1complete = el(), el()
    mdlg:fillFavorRow(1, row, client)
    T.eq("M3b on a CURRENT page the row's Cancel is shown", tostring(mdlg.favor1cancel.visible) .. "/" .. tostring(mdlg.favor1complete.visible), "true/false")
    advance(4001)
    local stale = mdlg:getPageItems()[1]
    mdlg:fillFavorRow(1, stale, client)
    T.eq("M3c on a LAST_CONFIRMED page the same row shows no Cancel or Done", mdlg.workView.state .. "/" .. tostring(mdlg.favor1cancel.visible) .. "/" .. tostring(mdlg.favor1complete.visible), "LAST_CONFIRMED/false/false")
    client:requestPersonalWorkView("")
    exchange(A)
    row = mdlg:getPageItems()[1]
    client:requestWorkAction("ABANDON_WORK", row.npcId, { token = row.token, recordRevision = row.recordRevision })
    exchange(A)
    exchange(A)
    T.eq("M4 abandon through the dialog's route", tostring(mdlg.footerMessage) .. "/" .. #server.favorSystem.activeFavors, "npc_dialog_abandoned/0")
    T.eq("M5 the page is empty and known", #mdlg:getPageItems() .. "/" .. tostring(client:getPersonalWorkView().totalKnown), "0/true")
    NPCFavorManagementDialog.INSTANCE = nil
    T.eq("M6 no stream fault", FAULTS, 0)
end

-- =========================================================
-- U: the face-to-face dialog on a listen host (the button handlers)
-- =========================================================
do
    local server, sm = boot({ placeables = town(4), maxNPCs = 3, dir = "u" })
    SIDE.server = { sys = server, mission = sm, g_server = g_server, localPlayer = localPlayer() }
    SIDE.client = nil
    useServer()
    local p1 = server:getNPCById(1)
    p1.personality, p1.relationship = "friendly", 45
    hostAt(p1.position.x + 2, p1.position.z)
    -- The MessageDialog base is not on the bench; its open and close are no-ops here.
    NPCDialog.superClass = function() return { onOpen = function() end, onClose = function() end } end
    local dlg = setmetatable({ npc = p1, npcSystem = server, buttonEnabled = {}, responseText = el(), responseBg = el(), btnFavorText = el(), btnFavorBg = el(), giftPanelVisible = false }, { __index = NPCDialog })
    dlg:onOpen()
    local v = server:getPersonDialogView(p1.id)
    T.eq("U1 opening the dialog begins the context and asks for the view", tostring(NPCDialog.INSTANCE == dlg) .. "/" .. tostring(v.available) .. "/" .. tostring(v.result), "true/true/" .. R.RESULT_NO_WORK)
    T.eq("U2 with nothing to show the Favor button offers help at 45 trust", tostring(dlg.buttonEnabled.Favor) .. "/" .. dlg.btnFavorText.text, "true/Offer help")
    T.eq("U3 nothing is painted for a silent view reply", tostring(dlg.responseText.text), "nil")
    dlg:onClickTalk()
    local vTalk = server:getPersonDialogView(p1.id)
    T.ok("U4 Talk paints the neighbour's line, the topic resolved by this reader from its key", tostring(vTalk.topicKey):match("^npc_topic_") ~= nil and dlg.responseText.text:find(vTalk.text, 1, true) ~= nil)
    T.eq("U5 and the trust moved", p1.relationship, 46)
    dlg:onClickTalk()
    T.ok("U6 the second Talk paints the day's limit", dlg.responseText.text:find("Already chatted") ~= nil)
    T.ok("U7 the pending line is not left painted after a synchronous reply", dlg.responseText.text:find("Asking") == nil)
    dice({ 0.99, rollFor(server.favorSystem, p1, "watch_property", 1) })
    dlg:onClickFavor()
    realDice()
    T.ok("U8 Offer help paints the acceptance line with the first step", dlg.responseText.text:find("Really%? That's amazing") ~= nil and dlg.responseText.text:find("Go to NPC's property") ~= nil)
    T.eq("U9 the button becomes Accept Favor", dlg.btnFavorText.text, "Accept Favor")
    dlg:onClickFavor()
    local favor = server.favorSystem.activeFavors[1]
    T.eq("U10 Accept binds to the offer shown and the host accepted it", favor.status .. "/" .. tostring(favor.ownerFarmId), "active/1")
    T.ok("U11 the acceptance line is painted", dlg.responseText.text:find("Thank you! I really need your help") ~= nil)
    T.eq("U12 the button reads progress while the travel step is open", dlg.btnFavorText.text, "Check favor progress")
    dlg:onClickFavor()
    T.ok("U13 the progress click paints the next step", dlg.responseText.text:find("Next: Go to NPC's property") ~= nil)
    -- The player walked there (the tracker's own fact) and comes back to talk: reopen refreshes the view.
    favor.steps[1].completed = true
    dlg:onClose()
    T.eq("U14 closing the dialog ends the context", tostring(server.dialogClient.context) .. "/" .. tostring(NPCDialog.INSTANCE), "nil/nil")
    dlg.npc = p1
    dlg:onOpen()
    T.eq("U15 reopened, the button reads Complete favor", dlg.btnFavorText.text, "Complete favor")
    -- A refused Complete on the host: the reply's own line stays, nothing paints over it.
    local origGetText = g_i18n.getText
    g_i18n.getText = function(_, key) return "T:" .. tostring(key) end
    favor.steps[1].completed = false   -- the tracker's fact moved under the open dialog
    dlg:onClickFavor()
    T.eq("U15b the host's refusal line is what the player reads, not the pending or the unavailable line", tostring(dlg.responseText.text) .. "/" .. favor.status, "T:npc_dialog_refused_not_ready/active")
    g_i18n.getText = origGetText
    favor.steps[1].completed = true
    dlg:onOpen()
    MONEY = {}
    dlg:onClickFavor()
    T.eq("U16 Complete pays once and paints the reward line", favor.status .. "/" .. tostring(MONEY[1]) .. "/" .. tostring(dlg.responseText.text:find("Here's your reward") ~= nil), "completed/" .. (favor.reward.money or 0) .. "/true")
    T.eq("U17 every local request went through the dispatcher's gate", server.dialogSessions["local"].highWater, 9)
    -- A gift on the host: the thanks line, and the money moved once.
    g_i18n.getText = function(_, key) return "T:" .. tostring(key) end
    local moneyBefore = LIVE_FARMS[1].money
    dlg:executeGift(200)
    T.eq("U16b a gift on the host ends on the thanks line with the money moved once", tostring(dlg.responseText.text):find("T:npc_dialog_gift_thanks", 1, true) ~= nil and (moneyBefore - LIVE_FARMS[1].money) == 200, true)
    g_i18n.getText = origGetText
    T.eq("U18 the legacy completion path is closed for ordinary work", dlg:sendCompletion({ recoveredFromLegacy = false }, nil, false), "unavailable")
    dlg:onClose()
    NPCDialog.superClass = nil
end

-- =========================================================
-- E, N: the admin gate, the console command, the list
-- =========================================================
do
    local server, sm = boot({ placeables = town(4), maxNPCs = 3, dir = "e" })
    SIDE.server = { sys = server, mission = sm, g_server = g_server, localPlayer = localPlayer() }
    useServer()
    local p2 = server:getNPCById(2)
    p2.relationship = 40
    local adm = setmetatable({ npc = p2, npcSystem = server, statusText = el() }, { __index = NPCAdminEditDialog })
    adm.updateDisplay = function() end
    g_server = nil
    adm:adjustRelationship(5)
    T.eq("E1 a remote client cannot adjust: unavailable, trust unchanged", tostring(adm.statusText.text):sub(1, 16) .. "/" .. p2.relationship, "Unavailable here/40")
    g_server = SIDE.server.g_server
    g_localPlayer = nil
    adm:adjustRelationship(5)
    T.eq("E2 a dedicated server with no local player cannot either", p2.relationship, 40)
    g_localPlayer = SIDE.server.localPlayer
    adm:adjustRelationship(5)
    T.eq("E3 the host adjusts directly and reports it", p2.relationship .. "/" .. tostring(adm.statusText.text ~= nil), "45/true")
    -- npcGoto resolves the durable number, never a row position.
    server:setPersonLive(server:getNPCById(1), false, "npc_person_waiting_count")
    T.eq("N1 person 1 is waiting, rows are 2 and 3", #server.activeNPCs .. "/" .. server.activeNPCs[1].id .. "/" .. server.activeNPCs[2].id, "2/2/3")
    T.eq("N2 npcGoto 3 goes to person 3 (row 2)", server.gui:npcGoto("3") .. "/" .. NPCTeleport.last, "teleported to 3/3")
    T.ok("N3 npcGoto 1 refuses a waiting person", server.gui:npcGoto("1"):find("not found") ~= nil)
    T.ok("N4 the list numbers people by durable number", server.gui:npcGoto():find("  3%. ") ~= nil and server.gui:npcGoto():find("  1%. ") == nil)
    -- The neighbour list dialog keys rows by durable number.
    local list = setmetatable({ npcSystem = server, currentPage = 1, closed = 0 }, { __index = NPCListDialog })
    list.close = function(self) self.closed = self.closed + 1 end
    list:updateDisplay()
    T.eq("N5 rows describe the roster view: the waiting person has no Go", tostring(list.rowDescriptor[1].personId) .. "/" .. tostring(list.rowDescriptor[1].canGoTo) .. "/" .. tostring(list.rowDescriptor[3].personId) .. "/" .. tostring(list.rowDescriptor[3].canGoTo), "1/false/3/true")
    NPCTeleport.last = nil
    list:teleportToRow(1)
    T.eq("N6 Go on the waiting row does nothing", tostring(NPCTeleport.last) .. "/" .. list.closed, "nil/0")
    list:teleportToRow(3)
    T.eq("N7 Go on row 3 reaches person 3 by number", tostring(NPCTeleport.last) .. "/" .. list.closed, "3/1")
    -- Teardown clears the dispatcher's sessions and the client's views.
    server:beginPersonDialog(2)
    server:requestPersonDialogAction("VIEW", 2, nil)
    server:delete()
    T.eq("N8 delete clears sessions and views", tostring(next(server.dialogSessions or {})) .. "/" .. tostring(server.dialogClient.context), "nil/nil")
    T.eq("N9 no stream fault in the whole run", FAULTS, 0)
end
