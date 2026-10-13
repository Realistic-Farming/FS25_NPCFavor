-- NPC-204 views and text: the work page, the dialog, the Recovery rows and door, provider text, reconciliation.
--!load: src/utils/NPCFarmIdentity.lua, src/utils/NPCReleaseGate.lua, src/settings/NPCSettings.lua, src/scripts/NPCPersonRoster.lua, src/scripts/NPCRelationshipManager.lua, src/scripts/NPCFavorSystem.lua, src/scripts/NPCFavorRecovery.lua, src/scripts/NPCCompanionContribution.lua, src/scripts/NPCFieldWork.lua, src/scripts/NPCAI.lua, src/scripts/ContractorModBridge.lua, src/scripts/NPCInteractionUI.lua, src/events/NPCStateSyncEvent.lua, src/events/NPCInteractionEvent.lua, src/events/NPCFavorRecoveryEvents.lua, src/events/NPCPersonDialogEvents.lua, src/integrations/NPCStateLedgerBridge.lua, src/integrations/NPCNetworkSyncBridge.lua, src/NPCSystem.lua, src/scripts/NPCPersonDialog.lua, src/gui/NPCDialog.lua, src/gui/NPCListDialog.lua, src/gui/NPCAdminEditDialog.lua, src/gui/NPCFavorManagementDialog.lua, src/scripts/NPCFavorHUD.lua, src/settings/NPCFavorGUI.lua
--!text: translations/lang_br.xml, translations/lang_ct.xml, translations/lang_cz.xml, translations/lang_da.xml, translations/lang_de.xml, translations/lang_ea.xml, translations/lang_en.xml, translations/lang_es.xml, translations/lang_fc.xml, translations/lang_fi.xml, translations/lang_fr.xml, translations/lang_hu.xml, translations/lang_id.xml, translations/lang_it.xml, translations/lang_jp.xml, translations/lang_kr.xml, translations/lang_nl.xml, translations/lang_no.xml, translations/lang_pl.xml, translations/lang_pt.xml, translations/lang_ro.xml, translations/lang_ru.xml, translations/lang_sv.xml, translations/lang_tr.xml, translations/lang_uk.xml, translations/lang_vi.xml
--
-- THE ENTRY-POINT BAR for slice 4 (Implementation v1.1 sections 3.11 and 3.12).
-- A test caller binds only through the published mission handle and drives the
-- real verbs. Every farmer view enters where production enters it: the person
-- dialog request event (the work page, the neighbour view, Offer help) and
-- NPCInteractionEvent for accept, both decoded from their reply events on the
-- typed stream, so the receiving side's text resolution runs; the Recovery
-- page and commands through the Recovery door's own events; and the standalone
-- management door on the client (NPCFavorManagementDialog: its own view
-- request, row painter, click handler and confirmation, then the command it
-- sends). Text is read through a reduced native I18N (I18N.lua:150-194: a mod
-- table inheriting the base game's through __index, getText's lookup order and
-- its Missing answer), with NPCFavor's own table taken from the shipped
-- translations/lang_de.xml, and every one of the 26 shipped locale files is
-- read for the eight keys. Nothing hand-fills a favour, a row, a token or a
-- revision.
--
-- What this proves: the views and text contract, offline. What it does not:
-- GUI layout and rendering (Wizard's pass owns the final door), real fonts for
-- every script, native transport.

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


;(function()   -- a scope of its own: the fixture already holds most of main's 200 locals
-- =========================================================
-- The native I18N, reduced to what the text proof reads (I18N.lua:150-194)
-- =========================================================
-- A mod's text table inherits the base game's through __index; getText reads
-- the named mod environment first, then the caller's own table, and answers
-- "Missing ..." for an unknown key.
local BASE_TEXTS = { base_only_line = "A base-game line" }
local I18N_ROOT = { texts = BASE_TEXTS, modEnvironments = {} }
function I18N_ROOT:getText(name, customEnv)
    local ret = nil
    if customEnv ~= nil then
        local modEnv = self.modEnvironments[customEnv]
        if modEnv ~= nil then ret = modEnv.texts[name] end
    end
    if ret == nil then
        ret = self.texts[name]
        if ret == nil then ret = string.format("Missing '%s' in l10n%s.xml", name, "_en") end
    end
    return ret
end
function I18N_ROOT:hasText(name) return name ~= nil and self.texts[name] ~= nil end
local function addModI18N(modName, own)
    local env = setmetatable({ texts = setmetatable(own or {}, { __index = BASE_TEXTS }) }, { __index = I18N_ROOT })
    I18N_ROOT.modEnvironments[modName] = env
    return env
end
local function localeTexts(path)
    local out = {}
    for name, text in (SOURCE_TEXT[path] or ""):gmatch('<text name="([^"]+)" text="([^"]*)"') do out[name] = text end
    return out
end
-- NPCFavor's own table is a shipped locale file (German, so its copy can never be
-- mistaken for the English fallbacks in the code); the companion's is its own.
local NPC_TEXT = localeTexts("translations/lang_de.xml")
g_i18n = addModI18N("FS25_NPCFavor", NPC_TEXT)
local COMPANION_TEXTS = {}
addModI18N(MOD, COMPANION_TEXTS)

local function nowReq() return nextReq() end
local function rowWith(reply, id)
    for _, row in ipairs(reply and reply.rows or {}) do
        if row.token ~= nil and g_NPCSystem ~= nil then
            local rec = g_NPCSystem.favorSystem:getRecoveryRecordByToken(tonumber(row.token))
            if rec ~= nil and rec.id == id then return row end
        end
    end
    return nil
end

-- =========================================================
-- K: the eight host keys ship with real text in all 26 locale files
-- =========================================================
local KEYS = { "npc_contrib_generic_title", "npc_contrib_generic_desc", "npc_contrib_step_report", "npc_contrib_step_talk",
    "npc_contrib_hold_work_off", "npc_contrib_hold_companion_missing", "npc_contrib_hold_companion_incompatible", "npc_contrib_let_go" }
for _, lang in ipairs({ "br", "ct", "cz", "da", "de", "ea", "en", "es", "fc", "fi", "fr", "hu", "id", "it", "jp", "kr",
                        "nl", "no", "pl", "pt", "ro", "ru", "sv", "tr", "uk", "vi" }) do
    local texts = localeTexts("translations/lang_" .. lang .. ".xml")
    local bad = {}
    for _, k in ipairs(KEYS) do
        local v = texts[k]
        if type(v) ~= "string" or v == "" or v:find("^%[EN%]") or v:find("\226\128\148", 1, true) then bad[#bad + 1] = k end
    end
    T.eq("K." .. lang .. " the eight keys ship with real text", table.concat(bad, ","), "")
end

-- =========================================================
-- V: the work page and the dialog view (3.11)
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("vv")
    local fav = server.favorSystem
    local M = newConnection("M", 14, 2)
    USERS[M].getIsMasterUser = function() return true end
    standAt(M, person.position.x, person.position.z)
    local id = offer("alex", 1).favorId
    local rec = recordOf(server, id)
    local pageA = request(A, R.OP_VIEW_WORK, 0, nowReq())
    local rowA = rowWith(pageA, id)
    T.ok("V1 the addressed farm's work page lists the companion offer", rowA ~= nil)
    T.eq("V2 with Accept lit for that farm", rowA and rowA.canAccept, true)
    T.eq("V3 its text is resolved, never the kind id", rowA and rowA.description, NPC_TEXT.npc_contrib_generic_desc)
    T.eq("V4 another farm's work page does not list it", tostring(rowWith(request(C, R.OP_VIEW_WORK, 0, nowReq()), id)), "nil")
    T.eq("V5 nor does a master's of another farm", tostring(rowWith(request(M, R.OP_VIEW_WORK, 0, nowReq()), id)), "nil")
    local viewA = request(A, R.OP_VIEW, person.id, nowReq())
    T.eq("V6 at the neighbour, the addressed farm is offered it", viewA.result .. "/" .. #viewA.rows, R.RESULT_OFFER .. "/1")
    local viewC = request(C, R.OP_VIEW, person.id, nowReq())
    T.eq("V7 every other farm reads BUSY with no row", viewC.result .. "/" .. #viewC.rows, R.RESULT_BUSY .. "/0")
    local viewM = request(M, R.OP_VIEW, person.id, nowReq())
    T.eq("V8 a master of another farm reads BUSY too", viewM.result .. "/" .. #viewM.rows, R.RESULT_BUSY .. "/0")
    local before = #fav.activeFavors
    request(C, R.OP_OFFER_HELP, person.id, nowReq())
    T.eq("V9 Offer help on the occupied neighbour creates nothing", #fav.activeFavors, before)
    local acc = workAction(A, IE.ACTION_FAVOR_ACCEPT, person.id, 1, sel(nowReq(), viewA.rows[1]))
    T.eq("V10 the farmer accepts from the row the dialog showed", acc.result .. "/" .. rec.status, R.RESULT_ACCEPTED .. "/active")
    local mine = request(A, R.OP_VIEW, person.id, nowReq())
    T.eq("V11 the owner then reads its accepted work", mine.result .. "/" .. tostring(mine.rows[1] and mine.rows[1].canComplete), R.RESULT_ACCEPTED .. "/false")
    T.eq("V12 other farms still read BUSY", request(C, R.OP_VIEW, person.id, nowReq()).result, R.RESULT_BUSY)
    handle():reportFavorStep(NS, { favorId = id, outcome = "irrigation_done", farmId = 1 })
    local after = request(A, R.OP_VIEW, person.id, nowReq())
    T.eq("V13 after the report the owner's row lights Complete and names the TALK step",
        tostring(after.rows[1] and after.rows[1].canComplete) .. "/" .. tostring(after.rows[1] and after.rows[1].nextStepText), "true/" .. NPC_TEXT.npc_contrib_step_talk)
    lock(server)
    tickFavours(server)
    T.eq("V14 held work is absent from the active readers", tostring(server:hasActiveFavorOfType(NS .. ":emergency_water")) .. "/" .. tostring(rowWith(request(A, R.OP_VIEW_WORK, 0, nowReq()), id)), "false/nil")
end)()

-- =========================================================
-- T: provider text, proved to be the provider's own (3.11)
-- =========================================================
;(function()
    COMPANION_TEXTS.tc_water_desc = "Haul water to the dry field"
    COMPANION_TEXTS.tc_water_report = "Water hauled"
    COMPANION_TEXTS.tc_water_talk = "Tell Alex it is done"
    local server, client, A, B, C, person = companionWorld("vt")
    local fav = server.favorSystem
    local function kind(key, desc, report, talk)
        local r = handle():registerFavorType(NS, water({ kindKey = key, descriptionKey = desc,
            steps = { { kind = "REPORT", outcome = "irrigation_done", textKey = report }, { kind = "TALK", textKey = talk } } }))
        return r.result
    end
    T.eq("T0 the keyed kinds are declared", kind("keyed", "tc_water_desc", "tc_water_report", "tc_water_talk") .. kind("inherited", "base_only_line") .. kind("missing", "tc_no_such_key"), "READYREADYREADY")
    local function offerKind(key)
        local r = handle():requestFavorOffer(NS, key, { personKey = "alex", addressedFarmId = 1, targetKey = "40" })
        return recordOf(server, r.favorId)
    end
    local keyed = offerKind("keyed")
    T.eq("T1 a proved provider key sets the description", keyed.description, "Haul water to the dry field")
    T.eq("T2 and the step texts", keyed.steps[1].description .. "/" .. keyed.steps[2].description, "Water hauled/Tell Alex it is done")
    T.eq("T3 the name is NPCFavor's own title key, never the kind id", keyed.name, "npc_contrib_generic_title")
    -- The receiving machine speaks another language: its copy resolves there.
    COMPANION_TEXTS.tc_water_desc = "Wasser zum trockenen Feld fahren"
    COMPANION_TEXTS.tc_water_report = "Wasser gefahren"
    local page = request(A, R.OP_VIEW_WORK, 0, nowReq())
    local row = rowWith(page, keyed.id)
    T.eq("T4 the receiver resolves the row's text in its own language from the keys it carries",
        tostring(row and row.description) .. "/" .. tostring(row and row.nextStepText), "Wasser zum trockenen Feld fahren/Wasser gefahren")
    T.eq("T5 the server's own record keeps the text it resolved", keyed.description, "Haul water to the dry field")
    handle():reportFavorStep(NS, { favorId = keyed.id, outcome = "target_gone", farmId = 1 })
    local inherited = offerKind("inherited")
    T.eq("T6 a key the provider only inherits from the base game is not its own: host copy", inherited.description, NPC_TEXT.npc_contrib_generic_desc)
    handle():reportFavorStep(NS, { favorId = inherited.id, outcome = "target_gone", farmId = 1 })
    local missing = offerKind("missing")
    T.eq("T7 a missing key never shows a Missing banner: host copy", missing.description, NPC_TEXT.npc_contrib_generic_desc)
    T.eq("T8 with the host step copy", missing.steps[1].description .. "/" .. missing.steps[2].description, NPC_TEXT.npc_contrib_step_report .. "/" .. NPC_TEXT.npc_contrib_step_talk)
    COMPANION_TEXTS.tc_water_desc, COMPANION_TEXTS.tc_water_report, COMPANION_TEXTS.tc_water_talk = nil, nil, nil
end)()

-- =========================================================
-- R: the Recovery view's companion rows (3.11)
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("vr")
    local fav = server.favorSystem
    local M = newConnection("M", 14, 2)
    USERS[M].getIsMasterUser = function() return true end
    local rec = recordOf(server, offer("alex", 1).favorId)
    accept(server, A, person, rec, nowReq())
    lock(server)
    tickFavours(server)
    local row = rowOf(viewAs(A), rec)
    T.ok("R1 the owning farm's Recovery page lists its held companion job", row ~= nil)
    T.eq("R2 held WORK_OFF with LET_GO lit", row and (tostring(row.contributionHeld) .. "/" .. row.contributionHoldReason .. "/" .. tostring(row.canLetGo)), "true/WORK_OFF/true")
    T.eq("R3 no Resume, Assign, Done or Cancel for it",
        row and (tostring(row.knownOwnerResumable) .. tostring(row.assignable) .. tostring(row.canComplete) .. tostring(row.canAbandon)), "falsefalsefalsefalse")
    T.eq("R4 not inspect-only while LET_GO is available", row and row.inspectOnly, false)
    T.eq("R5 its reason key is the hold's, never the unknown-type key", row and row.unavailableKey, "npc_contrib_hold_work_off")
    T.ok("R6 its remaining time is known", row ~= nil and row.timeKnown == true and row.timeRemaining > 0)
    T.eq("R7 a master of another farm sees no companion row", tostring(rowOf(viewAs(M), rec)), "nil")
    -- A built-in paused row stays the administrator's to see.
    local bea = claimed(server, "bea", 600, 600)
    standAt(A, bea.position.x, bea.position.z)
    dice({ 0.99, rollFor(fav, bea, "watch_property", 1) })
    local offerReply = request(A, R.OP_OFFER_HELP, bea.id, nowReq())
    realDice()
    local builtIn = nil
    for _, f in ipairs(fav.activeFavors) do if f.npcId == bea.id and not NPCCompanion.isContributed(f) then builtIn = f end end
    workAction(A, IE.ACTION_FAVOR_ACCEPT, bea.id, 1, sel(nowReq(), offerReply.rows[1]))
    server:setPersonLive(bea, false, NPCPersonRoster.REASON_WAITING_COUNT)
    local builtRow = rowOf(viewAs(M), builtIn)
    T.ok("R8 masters still see built-in recovery rows", builtRow ~= nil)
    T.eq("R9 which carry no LET_GO and no hold", builtRow and (tostring(builtRow.canLetGo) .. "/" .. tostring(builtRow.contributionHeld)), "false/false")
    -- The unlock with the companion job's neighbour away: paused, not held.
    server:setPersonLive(person, false, NPCPersonRoster.REASON_WAITING_COUNT)
    open(server)
    tickFavours(server)
    local away = rowOf(viewAs(A), rec)
    T.eq("R10 an away neighbour's job reads paused, no LET_GO, waiting",
        away and (away.pauseReason .. "/" .. tostring(away.canLetGo) .. "/" .. tostring(away.knownOwnerResumable) .. "/" .. away.unavailableKey),
        RV.REASON_NEIGHBOUR_UNAVAILABLE .. "/false/false/npc_recovery_unavail_waiting")
    server:setPersonLive(person, true)
    local back = rowOf(viewAs(A), rec)
    T.eq("R11 once she is back Resume lights from the contributed predicate",
        back and (tostring(back.knownOwnerResumable) .. "/" .. tostring(back.inspectOnly) .. "/" .. back.unavailableKey), "true/false/")
end)()

-- =========================================================
-- D: the standalone Recovery door (3.11 floor), on the client
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("vd")
    local rec = recordOf(server, offer("alex", 1).favorId)
    accept(server, A, person, rec, nowReq())
    lock(server)
    tickFavours(server)
    MONEY = {}
    useClient()
    local mdlg = setmetatable({ mode = "recovery", npcSystem = client, page = 1, updates = 0 }, { __index = NPCFavorManagementDialog })
    mdlg.updateDisplay = function(self) self.updates = self.updates + 1 end
    NPCFavorManagementDialog.INSTANCE = mdlg
    mdlg:requestRecoveryView("")
    exchange(A)
    local row = mdlg.recoveryView and mdlg.recoveryView.rows[1]
    T.ok("D1 the door's own view request brought back the held job", row ~= nil and row.canLetGo == true)
    mdlg.favorIndices = {}
    for _, n in ipairs({ "cancel", "complete", "canceltxt", "completetxt", "cancelbg", "completebg", "view", "goto", "viewtxt", "gototxt",
                         "viewbg", "gotobg", "desc", "npc", "time", "reward", "border", "bg" }) do
        mdlg["favor1" .. n] = el()
    end
    mdlg:fillRecoveryRow(1, row, client)
    T.eq("D2 the row shows LET_GO in its own control, labelled from the shipped key",
        tostring(mdlg.favor1cancel.visible) .. "/" .. tostring(mdlg.favor1canceltxt.text), "true/" .. NPC_TEXT.npc_contrib_let_go)
    T.eq("D3 and no Resume, Assign or Done", tostring(mdlg.favor1complete.visible), "false")
    T.ok("D4 the hold reason is shown on the row", tostring(mdlg.favor1desc.text):find(NPC_TEXT.npc_contrib_hold_work_off:sub(1, 20), 1, true) ~= nil)
    local shown = nil
    local savedYesNo = YesNoDialog
    YesNoDialog = { show = function(cb, target, text, title, a, b, c, d, e, ctx) shown = { cb = cb, target = target, text = text, ctx = ctx } return true end }
    NPCFavorManagementDialog.onClickFavor1Cancel(mdlg)
    T.eq("D5 the click asks for confirmation of op 5, never ABANDON", shown and shown.ctx and shown.ctx.op, NPCFavorRecovery.OP_LET_GO)
    T.ok("D6 the confirmation names LET_GO and the hold", shown ~= nil and shown.text:find(NPC_TEXT.npc_contrib_let_go, 1, true) ~= nil
        and shown.text:find(NPC_TEXT.npc_contrib_hold_work_off:sub(1, 20), 1, true) ~= nil)
    if shown ~= nil then shown.cb(shown.target, true, shown.ctx) end
    exchange(A)
    useServer()
    T.eq("D7 the server let the job go, without fault", rec.status .. "/" .. moneyTotal(1), "closed/0")
    useClient()
    exchange(A)
    T.eq("D8 the door shows the result and asks for a fresh page", tostring(mdlg.footerMessage), NPC_TEXT.npc_contrib_let_go)
    YesNoDialog = savedYesNo
    NPCFavorManagementDialog.INSTANCE = nil
    useServer()
    T.eq("D9 no stream fault", FAULTS, 0)
end)()

-- =========================================================
-- W: provider reconciliation (3.12)
-- =========================================================
;(function()
    local server, client, A, B, C, person = companionWorld("vw")
    local bea = claimed(server, "bea", 600, 600)
    local pending = recordOf(server, offer("bea", 2).favorId)
    local rec = recordOf(server, offer("alex", 1).favorId)
    accept(server, A, person, rec, nowReq())
    local w = handle():getProviderWork(NS)
    local byId = {}
    for _, r in ipairs(w.rows or {}) do byId[r.favorId] = r end
    T.eq("W1 the provider reads its own open offer and job", w.result .. "/" .. #w.rows, "READY/2")
    local o, j = byId[pending.id] or {}, byId[rec.id] or {}
    T.eq("W2 the offer row: state, addressed farm, kind, outcome", tostring(o.state) .. "/" .. tostring(o.farmId) .. "/" .. tostring(o.kindKey) .. "/" .. tostring(o.expectedOutcome), "OFFERED/2/emergency_water/irrigation_done")
    T.eq("W3 the job row: state, owning farm, person, revision", tostring(j.state) .. "/" .. tostring(j.farmId) .. "/" .. tostring(j.personId == person.id) .. "/" .. tostring(j.recordRevision == rec.recordRevision), "ACCEPTED/1/true/true")
    lock(server)
    tickFavours(server)
    local w2 = handle():getProviderWork(NS)
    T.eq("W4 after the lock: the withdrawn offer is gone and the job reads HELD", #w2.rows .. "/" .. tostring(w2.rows[1] and w2.rows[1].state) .. "/" .. tostring(w2.rows[1] and w2.rows[1].holdReason), "1/HELD/WORK_OFF")
    T.eq("W5 rows are copies (no authority over the host record)", (function() w2.rows[1].state = "X" return rec.status end)(), "paused_recovery")
    T.eq("W6 another provider reads none of it", #(handle():getProviderWork("other_companion").rows or {}), 0)
    local late = newLedger(nil, true)
    local re = boot({ placeables = town(4), maxNPCs = 3, dir = "vw_late", ledger = late })
    SIDE.server = { sys = re, mission = g_currentMission, g_server = g_server, localPlayer = nil }
    publish(re)
    local early = handle():getProviderWork(NS)
    T.eq("W7 before the favour load is ready it answers UNAVAILABLE, not an empty list", early.result .. "/" .. tostring(early.rows), "UNAVAILABLE/nil")
end)()

end)()

T.summary()
