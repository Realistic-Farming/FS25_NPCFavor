-- =========================================================
-- FS25 NPC Favor - Person roster (RSF-F357)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
-- The host-owned population: who the saved neighbours are, which durable number
-- names each of them, which of them are live in the town right now and which are
-- waiting, and the one allocator every creator draws from.
--
-- A house, a displayed name, an array position or a hired-worker slot never
-- chooses the person who owns trust or work. The durable number does. The number
-- comes from personIdHighWater, which only ever rises, is persisted even when no
-- person is live, and is checked for exhaustion BEFORE it is incremented.
--
-- Load order (server only): the saved people are restored BEFORE a town is
-- created. The selected snapshot is reserved (every valid person number, every
-- favour and tie endpoint, the saved high-water mark), staged, and committed
-- once; only then are town places filled with retained people first and
-- newcomers after. A pure client never runs any of that: it starts WAITING and
-- becomes READY only from a complete, validated server snapshot.
--
-- What lives here: the roster and its lookups, the allocator, the staged apply,
-- the person row import/export shared by the XML and StateLedger writers, the
-- transient worker presences, the public snapshot assembly (pages of at most 50
-- records, at most 4096 records) and the client-side staging that publishes a
-- snapshot only when every page has arrived and agrees.
--
-- What does not: bodies, AI, favours and money stay with their existing owners
-- in NPCSystem, NPCEntity, NPCAI and NPCFavorSystem.
-- =========================================================

NPCPersonRoster = NPCPersonRoster or {}
local NPCPersonRoster_mt = Class(NPCPersonRoster)

-- The person schema is versioned apart from npc_favor.xml's SAVE_SCHEMA_VERSION.
NPCPersonRoster.SCHEMA = 1
NPCPersonRoster.MAX_ID = 2147483647

NPCPersonRoster.LOAD_WAITING = "WAITING"
NPCPersonRoster.LOAD_READY   = "READY"
NPCPersonRoster.LOAD_FAILED  = "FAILED"

NPCPersonRoster.SNAPSHOT_CURRENT     = "CURRENT"
NPCPersonRoster.SNAPSHOT_PENDING     = "PENDING"
NPCPersonRoster.SNAPSHOT_UNAVAILABLE = "UNAVAILABLE"

NPCPersonRoster.KIND_LIVE     = "LIVE"
NPCPersonRoster.KIND_WAITING  = "WAITING"
NPCPersonRoster.KIND_PRESENCE = "PRESENCE"
NPCPersonRoster.KIND_OPAQUE   = "OPAQUE"

NPCPersonRoster.PERSON_DURABLE  = "durable"
NPCPersonRoster.PERSON_PRESENCE = "presence"
NPCPersonRoster.REF_DURABLE     = "durable"

NPCPersonRoster.ORIGIN_TOWN       = "town"
NPCPersonRoster.ORIGIN_CONSULTANT = "consultant"
NPCPersonRoster.ORIGIN_OUTSIDE    = "outside"

-- The one supported provider token. Callers cannot supply another.
NPCPersonRoster.CONSULTANT_TOKEN = "cs_alex_chen"

NPCPersonRoster.PAGE_RECORDS = 50
NPCPersonRoster.MAX_RECORDS  = 4096
NPCPersonRoster.MAX_PAGES    = 82
NPCPersonRoster.NAME_LIMIT   = 64
NPCPersonRoster.SHORT_LIMIT  = 32
NPCPersonRoster.LABEL_LIMIT  = 128

-- Reason keys (localisation keys, never farmer-facing identifiers).
NPCPersonRoster.REASON_LOADING              = "npc_person_loading"
NPCPersonRoster.REASON_FAILED               = "npc_person_failed"
NPCPersonRoster.REASON_WAITING_COUNT        = "npc_person_waiting_count"
NPCPersonRoster.REASON_WAITING_HOME         = "npc_person_waiting_home"
NPCPersonRoster.REASON_WAITING_COMPANION    = "npc_person_waiting_companion"
NPCPersonRoster.REASON_KEPT_LEGACY          = "npc_person_kept_legacy"
NPCPersonRoster.REASON_IDENTITY_CONFLICT    = "npc_person_identity_conflict"
NPCPersonRoster.REASON_PRESENCE             = "npc_person_presence"
NPCPersonRoster.REASON_PRESENCE_UNAVAILABLE = "npc_person_presence_unavailable"
NPCPersonRoster.REASON_OPAQUE               = "npc_person_opaque"
NPCPersonRoster.REASON_EXHAUSTED            = "npc_person_exhausted"
NPCPersonRoster.REASON_SNAPSHOT_TOO_LARGE   = "npc_person_snapshot_too_large"
NPCPersonRoster.REASON_SNAPSHOT_PARTIAL     = "npc_person_snapshot_partial"
NPCPersonRoster.REASON_NAMES_EXHAUSTED      = "npc_person_names_exhausted"

local LOAD_STATE_CODE = { WAITING = 1, READY = 2, FAILED = 3 }
local LOAD_STATE_NAME = { "WAITING", "READY", "FAILED" }
local KIND_CODE = { LIVE = 1, WAITING = 2, PRESENCE = 3, OPAQUE = 4 }
local KIND_NAME = { "LIVE", "WAITING", "PRESENCE", "OPAQUE" }
NPCPersonRoster.LOAD_STATE_CODE = LOAD_STATE_CODE
NPCPersonRoster.LOAD_STATE_NAME = LOAD_STATE_NAME
NPCPersonRoster.KIND_CODE = KIND_CODE
NPCPersonRoster.KIND_NAME = KIND_NAME

-- =========================================================
-- Pure helpers
-- =========================================================

function NPCPersonRoster.isFiniteNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

--- A durable number: a finite integral number in 1..2147483647 (the signed Int32
--- event field). Anything else is unproven evidence, never coerced to a live id.
function NPCPersonRoster.validId(id)
    return NPCPersonRoster.isFiniteNumber(id) and id >= 1 and id <= NPCPersonRoster.MAX_ID
        and id == math.floor(id)
end

function NPCPersonRoster.boundLabel(s, limit)
    s = tostring(s or "")
    if #s > limit then return s:sub(1, limit) end
    return s
end

--- The legacy town uniqueId grammar ("npc_<index>_<name>_<rand>"). A legacy row in
--- this shape may be SIZED as a town candidate for the count; that is a placement
--- rule, never proof of identity for a favour, tie or provider claim.
function NPCPersonRoster.isTownCandidateGrammar(uniqueId)
    return type(uniqueId) == "string" and uniqueId:match("^npc_%d+_") ~= nil
end

function NPCPersonRoster.pageCountFor(total)
    return math.max(1, math.ceil(total / NPCPersonRoster.PAGE_RECORDS))
end

-- =========================================================
-- Construction and teardown
-- =========================================================

function NPCPersonRoster.new(npcSystem)
    local self = setmetatable({}, NPCPersonRoster_mt)
    self.npcSystem = npcSystem
    self.highWater = 0
    self.snapshotSequence = 0
    self.revision = 0
    self:reset(false)
    self:_clearReceiveState()
    return self
end

--- Controlled teardown of the population (a new controlled load follows). The
--- high-water mark is kept unless a brand-new mission starts: the same saved
--- population never gets its numbers reused. The mission's snapshot sequence
--- keeps increasing across a developer town reset.
function NPCPersonRoster:reset(keepHighWater)
    if not keepHighWater then self.highWater = 0 end
    self.loadState = NPCPersonRoster.LOAD_WAITING
    self.loadReason = NPCPersonRoster.REASON_LOADING
    self.loadDetail = nil
    self.selectedSource = nil
    self.original = nil
    self.roster = {}
    self.byId = {}
    self.opaque = {}
    self.unprovenIds = {}
    self.legacyTies = {}
    self.presences = {}
    self.presenceOrder = {}
    self.presencesUnavailable = false
    self.exhausted = false
    self.namesExhaustedLogged = false
    self.revision = (self.revision or 0) + 1
end

--- Mission teardown clears everything, receive state and sequences included.
function NPCPersonRoster:teardownMission()
    self:reset(false)
    self.snapshotSequence = 0
    self:_clearReceiveState()
end

function NPCPersonRoster:_clearReceiveState()
    self.pending = nil
    self.publishedSequence = 0
    self.clientRows = nil
    self.clientById = {}
    self.clientLoadState = NPCPersonRoster.LOAD_WAITING
    self.clientReason = NPCPersonRoster.REASON_LOADING
    self.clientUnavailable = true
end

-- =========================================================
-- Load state
-- =========================================================

function NPCPersonRoster:getLoadState() return self.loadState end
function NPCPersonRoster:isReady() return self.loadState == NPCPersonRoster.LOAD_READY end
function NPCPersonRoster:isWaiting() return self.loadState == NPCPersonRoster.LOAD_WAITING end
function NPCPersonRoster:isFailed() return self.loadState == NPCPersonRoster.LOAD_FAILED end

--- Record which source owns this load and keep its delivered table by identity,
--- so a FAILED load can hand the exact original back.
function NPCPersonRoster:selectSource(source, original)
    self.selectedSource = source
    self.original = original
end

function NPCPersonRoster:noteWaitingOnLedger()
    self.loadReason = NPCPersonRoster.REASON_LOADING
end

--- FAILED is terminal for the session: no live person mutation, no newcomer
--- creation, the original selected data preserved. Retry is a later corrected
--- load or a new mission, never in-session reconstruction.
function NPCPersonRoster:fail(reasonKey, detail)
    self.loadState = NPCPersonRoster.LOAD_FAILED
    self.loadReason = reasonKey or NPCPersonRoster.REASON_FAILED
    self.loadDetail = detail
    self.roster = {}
    self.byId = {}
    self.opaque = {}
    self.legacyTies = {}
    self.revision = self.revision + 1
    print(string.format("[NPC Favor] Person load FAILED (%s): %s; saved neighbours left untouched and not rewritten",
        tostring(self.loadReason), tostring(detail)))
end

function NPCPersonRoster:markReady()
    if self.loadState ~= NPCPersonRoster.LOAD_WAITING then return false end
    self.loadState = NPCPersonRoster.LOAD_READY
    self.loadReason = nil
    self.revision = self.revision + 1
    return true
end

-- =========================================================
-- The allocator
-- =========================================================

--- Issue the next durable number. Exhaustion is checked BEFORE the increment
--- and refuses; it never wraps and never renumbers valid people.
function NPCPersonRoster:allocateId()
    if self.highWater >= NPCPersonRoster.MAX_ID then
        if not self.exhausted then
            self.exhausted = true
            print("[NPC Favor] Person identity numbers are exhausted; no new neighbour can be created")
        end
        return nil, NPCPersonRoster.REASON_EXHAUSTED
    end
    self.highWater = self.highWater + 1
    return self.highWater
end

--- Reserve a number seen in the selected snapshot. The mark only rises.
function NPCPersonRoster:reserveId(id)
    if NPCPersonRoster.validId(id) and id > self.highWater then
        self.highWater = id
    end
end

function NPCPersonRoster:getHighWater() return self.highWater end

-- =========================================================
-- Person rows: the one flat shape both writers persist
-- =========================================================

local function copyEncounters(list)
    local out = {}
    if list == nil then return out end
    if type(list) ~= "table" then
        error("person row: encounters is not a table")
    end
    for i, e in ipairs(list) do
        if i > 10 then break end
        if type(e) ~= "table" then
            error("person row: encounter " .. tostring(i) .. " is not a table")
        end
        local enc = {
            type = e.type or "", time = e.time or 0, details = e.details or "",
            partner = e.partner or "", sentiment = e.sentiment or "neutral",
        }
        if enc.partner == "" then enc.partner = nil end
        out[#out + 1] = enc
    end
    return out
end

local function num(v, default)
    if NPCPersonRoster.isFiniteNumber(v) then return v end
    return default
end

--- Build the runtime person table from a saved row. Pure: the row is never
--- mutated (the ledger hands the delivered table back on a FAILED load). The
--- durable number is assigned by the caller after the reservation pass.
--- Raises on a structurally unsafe nested shape; the apply's protected call
--- turns that into FAILED with the original preserved.
function NPCPersonRoster.importPersonRow(row)
    if type(row) ~= "table" then
        error("person row is not a table")
    end
    local px, py, pz = num(row.px, 0), num(row.py, 0), num(row.pz, 0)
    local hasHome = row.hasHome == true or NPCPersonRoster.isFiniteNumber(row.hx)
    local home = nil
    if hasHome then
        home = { x = num(row.hx, 0), y = num(row.hy, 0), z = num(row.hz, 0) }
    end
    local legacyUid = row.legacyUniqueId or row.uniqueId
    if legacyUid ~= nil and type(legacyUid) ~= "string" then legacyUid = tostring(legacyUid) end
    local person = {
        id = nil,
        personKind = NPCPersonRoster.PERSON_DURABLE,
        name = tostring(row.name or ""),
        isFemale = row.isFemale == true,
        age = num(row.age, 30),
        personality = tostring(row.personality or "hardworking"),
        position = { x = px, y = py, z = pz },
        rotation = { x = 0, y = num(row.ry, 0), z = 0 },
        isActive = true,
        currentAction = tostring(row.currentAction or "idle"),
        currentTask = nil,
        currentVehicle = nil,
        targetPosition = nil,
        canInteract = false,
        interactionDistance = 999,
        homePosition = home,
        homeBuilding = nil,
        homeBuildingName = tostring(row.homeBuildingName or ""),
        homeUniqueId = (type(row.homeUniqueId) == "string" and row.homeUniqueId ~= "") and row.homeUniqueId or nil,
        assignedField = nil,
        assignedVehicles = {},
        relationship = num(row.relationship, 50),
        favorCooldown = num(row.favorCooldown, 0),
        lastInteractionTime = 0,
        totalFavorsCompleted = num(row.favorsCompleted, 0),
        totalFavorsFailed = num(row.favorsFailed, 0),
        model = "farmer",
        clothing = { "farmer" },
        appearanceSeed = num(row.appearanceSeed, 1),
        heightScale = num(row.heightScale, 1.0),
        aiState = tostring(row.aiState or "idle"),
        path = nil,
        movementSpeed = num(row.movementSpeed, 1.0),
        aiPersonalityModifiers = {
            workEthic = num(row.workEthic, 1.0),
            sociability = num(row.sociability, 1.0),
            generosity = num(row.generosity, 1.0),
            punctuality = num(row.punctuality, 1.0),
        },
        _workEthicOffset = num(row.workEthicOffset, 0),
        lastUpdateTime = 0,
        updatePriority = 1,
        encounters = copyEncounters(row.encounters),
        lastGreetingTime = 0,
        greetingText = nil,
        greetingTimer = 0,
        dodgeTimer = 0,
        needs = {
            energy = num(row.energy, 20),
            social = num(row.social, 30),
            hunger = num(row.hunger, 10),
            workSatisfaction = num(row.workSatisfaction, 50),
        },
        mood = tostring(row.mood or "neutral"),
        birthdayMonth = math.random(1, 12),
        birthdayDay = math.random(1, 28),
        role = (type(row.role) == "string" and row.role ~= "") and row.role or nil,
        workplaceBuilding = nil,
        uniqueId = nil,
        legacyUniqueId = legacyUid,
        saveData = {},
        entityId = nil,
        -- RSF-F357 identity facts
        origin = NPCPersonRoster.ORIGIN_OUTSIDE,
        providerToken = nil,
        live = false,
        waitingReason = nil,
        legacy = not NPCPersonRoster.validId(row.id),
        townCandidate = false,
    }
    if row.origin == NPCPersonRoster.ORIGIN_TOWN or row.origin == NPCPersonRoster.ORIGIN_CONSULTANT then
        person.origin = row.origin
    end
    if row.providerToken == NPCPersonRoster.CONSULTANT_TOKEN then
        person.providerToken = NPCPersonRoster.CONSULTANT_TOKEN
    end
    if person.origin == NPCPersonRoster.ORIGIN_TOWN then
        person.townCandidate = true
    elseif person.legacy and NPCPersonRoster.isTownCandidateGrammar(legacyUid) then
        person.townCandidate = true
    end
    return person
end

--- The flat row for both writers. Positions and homes are copied by value.
function NPCPersonRoster.exportPersonRow(npc)
    local pm = npc.aiPersonalityModifiers or {}
    local nd = npc.needs or {}
    local pos = npc.position or {}
    local rot = npc.rotation or {}
    local d = {
        id = npc.id,
        origin = npc.origin or NPCPersonRoster.ORIGIN_TOWN,
        providerToken = npc.providerToken,
        homeUniqueId = npc.homeUniqueId,
        legacyUniqueId = npc.legacyUniqueId,
        role = npc.role,
        name = npc.name or "",
        personality = npc.personality or "",
        age = npc.age or 30,
        px = pos.x or 0, py = pos.y or 0, pz = pos.z or 0,
        ry = rot.y or 0,
        relationship = npc.relationship or 50,
        favorsCompleted = npc.totalFavorsCompleted or 0,
        favorsFailed = npc.totalFavorsFailed or 0,
        favorCooldown = npc.favorCooldown or 0,
        aiState = npc.aiState or "idle",
        currentAction = npc.currentAction or "idle",
        workEthic = pm.workEthic or 1.0, sociability = pm.sociability or 1.0,
        generosity = pm.generosity or 1.0, punctuality = pm.punctuality or 1.0,
        workEthicOffset = npc._workEthicOffset or 0,
        appearanceSeed = npc.appearanceSeed or 1,
        isFemale = npc.isFemale or false,
        movementSpeed = npc.movementSpeed or 1.0,
        heightScale = npc.heightScale or 1.0,
        energy = nd.energy or 20, social = nd.social or 30,
        hunger = nd.hunger or 10, workSatisfaction = nd.workSatisfaction or 50,
        mood = npc.mood or "neutral",
        homeBuildingName = npc.homeBuildingName or "",
        encounters = {},
    }
    if npc.homePosition then
        d.hasHome = true
        d.hx = npc.homePosition.x or 0
        d.hy = npc.homePosition.y or 0
        d.hz = npc.homePosition.z or 0
    end
    if npc.encounters then
        for ei, e in ipairs(npc.encounters) do
            if ei > 10 then break end
            d.encounters[#d.encounters + 1] = {
                type = e.type or "", time = e.time or 0, details = e.details or "",
                partner = e.partner or "", sentiment = e.sentiment or "neutral",
            }
        end
    end
    return d
end

-- =========================================================
-- The staged apply (server)
-- =========================================================

--- Reserve every valid number the snapshot mentions: person numbers (counting
--- duplicates), favour references, tie endpoints and the saved high-water mark.
--- References do not make duplicate people; only two person rows with one
--- number do.
function NPCPersonRoster.reserve(selected)
    local used, personCount, duplicate, high = {}, {}, {}, 0
    local function add(id)
        if NPCPersonRoster.validId(id) then
            used[id] = true
            if id > high then high = id end
        end
    end
    for _, row in ipairs(selected.rows or {}) do
        if type(row) == "table" and NPCPersonRoster.validId(row.id) then
            personCount[row.id] = (personCount[row.id] or 0) + 1
            if personCount[row.id] > 1 then duplicate[row.id] = true end
            add(row.id)
        end
    end
    for _, id in ipairs(selected.favourRefIds or {}) do add(id) end
    for _, tie in ipairs(selected.tieRows or {}) do
        add(tie.a); add(tie.b)
    end
    add(selected.highWater)
    return { used = used, duplicate = duplicate, personCount = personCount, high = high }
end

--- Apply the selected snapshot once. `selected` is the normalised table both
--- sources produce: { personSchema, highWater, rows, opaqueRows, favourRefIds,
--- tieRows }. Returns true when the roster is committed (not yet READY: the
--- town fill follows), or false plus a reason when the load was refused, in
--- which case the state is FAILED and the original is preserved. Structurally
--- unsafe rows raise; the caller's protected call turns that into FAILED too.
function NPCPersonRoster:applySelected(selected)
    if self.loadState ~= NPCPersonRoster.LOAD_WAITING then
        return false, "not_waiting"
    end
    selected = selected or {}
    local schema = selected.personSchema
    if schema ~= nil and schema ~= NPCPersonRoster.SCHEMA then
        -- An unknown future schema refuses application and preserves the
        -- original; it never treats a future row as a fresh legacy row.
        self:fail(NPCPersonRoster.REASON_FAILED, "unsupported person schema " .. tostring(schema))
        return false, "unsupported_schema"
    end

    -- 1. Reservation pass, before any number is issued.
    local reservation = NPCPersonRoster.reserve(selected)
    if reservation.high > self.highWater then self.highWater = reservation.high end
    for id in pairs(reservation.duplicate) do self.unprovenIds[id] = true end

    -- 2. Stage every row: keep a unique valid number, mint for a duplicate or
    --    missing number, keep anything else as opaque evidence.
    local staged = {}
    local opaque = {}
    for _, raw in ipairs(selected.opaqueRows or {}) do
        opaque[#opaque + 1] = raw
    end
    for _, row in ipairs(selected.rows or {}) do
        if type(row) ~= "table" then
            opaque[#opaque + 1] = row
        else
            local person = NPCPersonRoster.importPersonRow(row)
            local id = row.id
            if NPCPersonRoster.validId(id) and not reservation.duplicate[id] then
                person.id = id
            else
                local minted = self:allocateId()
                if minted == nil then
                    -- No safe allocation: the row stays a waiting record outside
                    -- the actionable person map, and round-trips as evidence.
                    opaque[#opaque + 1] = row
                    person = nil
                else
                    person.id = minted
                end
            end
            if person ~= nil then
                staged[#staged + 1] = person
            end
        end
    end
    table.sort(staged, function(a, b) return a.id < b.id end)

    -- 3. Ties: a marked tie between two uniquely validated retained people
    --    reconnects; everything else is inactive historical evidence.
    local byId = {}
    for _, person in ipairs(staged) do byId[person.id] = person end
    local reconnect, legacyTies = {}, {}
    for _, tie in ipairs(selected.tieRows or {}) do
        if type(tie) == "table" and tie.endpointKind == NPCPersonRoster.REF_DURABLE
            and NPCPersonRoster.validId(tie.a) and NPCPersonRoster.validId(tie.b)
            and byId[tie.a] ~= nil and byId[tie.b] ~= nil and tie.a ~= tie.b then
            reconnect[#reconnect + 1] = tie
        else
            legacyTies[#legacyTies + 1] = tie
        end
    end

    -- 4. Commit once.
    self.roster = staged
    self.byId = byId
    self.opaque = opaque
    self.legacyTies = legacyTies
    self.reconnectTies = reconnect
    self.revision = self.revision + 1
    return true
end

-- =========================================================
-- Roster lookups
-- =========================================================

--- The unique validated retained person for a durable number, live or waiting.
--- Returns nil plus "unproven" for a number the snapshot could not prove
--- (two rows carried it) and nil plus "absent" otherwise.
function NPCPersonRoster:getPerson(id)
    if not NPCPersonRoster.validId(id) then return nil, "unproven" end
    if self.unprovenIds[id] then return nil, "unproven" end
    local person = self.byId[id]
    if person == nil then return nil, "absent" end
    return person
end

function NPCPersonRoster:getLivePerson(id)
    local person = self:getPerson(id)
    if person ~= nil and person.live then return person end
    return nil
end

function NPCPersonRoster:isNameRetained(name)
    if type(name) ~= "string" or name == "" then return false end
    for _, person in ipairs(self.roster) do
        if person.name == name then return true end
    end
    return false
end

--- A newcomer created by a host path with a number already allocated.
function NPCPersonRoster:addPerson(person)
    if type(person) ~= "table" or not NPCPersonRoster.validId(person.id) then return false end
    if self.byId[person.id] ~= nil then return false end
    person.personKind = NPCPersonRoster.PERSON_DURABLE
    person.live = person.live == true
    self.roster[#self.roster + 1] = person
    self.byId[person.id] = person
    self.revision = self.revision + 1
    return true
end

function NPCPersonRoster:count()
    return #self.roster
end

function NPCPersonRoster:peopleWithToken(token)
    local out = {}
    for _, person in ipairs(self.roster) do
        if person.providerToken == token then out[#out + 1] = person end
    end
    return out
end

function NPCPersonRoster:touch()
    self.revision = self.revision + 1
end

-- =========================================================
-- Transient worker presences (never saved, never in activeNPCs)
-- =========================================================

--- Show an observed worker slot as a display presence. The first sight of a
--- slot draws a number from the allocator (so the mark persists); a reused slot
--- updates the same presence only because it carries no personal state.
function NPCPersonRoster:upsertPresence(slotKey, observed)
    if slotKey == nil or type(observed) ~= "table" then return nil end
    local presence = self.presences[slotKey]
    if presence == nil then
        local id = self:allocateId()
        if id == nil then return nil end
        presence = {
            id = id,
            personKind = NPCPersonRoster.PERSON_PRESENCE,
            slot = slotKey,
            position = { x = 0, y = 0, z = 0 },
            rotation = { x = 0, y = 0, z = 0 },
            isActive = true,
            live = false,
            relationship = nil,
        }
        self.presences[slotKey] = presence
        self.presenceOrder[#self.presenceOrder + 1] = slotKey
    end
    presence.name = NPCPersonRoster.boundLabel(observed.name or "", NPCPersonRoster.NAME_LIMIT)
    if NPCPersonRoster.isFiniteNumber(observed.x) and NPCPersonRoster.isFiniteNumber(observed.z) then
        presence.position.x = observed.x
        presence.position.y = num(observed.y, presence.position.y)
        presence.position.z = observed.z
        presence.positionKnown = true
    end
    presence.currentVehicle = observed.currentVehicle
    presence.currentAction = observed.currentVehicle ~= nil and "working" or "idle"
    presence.unavailable = false
    self.revision = self.revision + 1
    return presence
end

function NPCPersonRoster:removePresence(slotKey)
    if self.presences[slotKey] == nil then return end
    self.presences[slotKey] = nil
    for i, key in ipairs(self.presenceOrder) do
        if key == slotKey then table.remove(self.presenceOrder, i) break end
    end
    self.revision = self.revision + 1
end

--- An unreadable worker list marks last-observed positions unavailable and
--- disables their interactions; it removes nothing.
function NPCPersonRoster:setPresencesUnavailable(flag)
    flag = flag == true
    if self.presencesUnavailable == flag then return end
    self.presencesUnavailable = flag
    for _, key in ipairs(self.presenceOrder) do
        self.presences[key].unavailable = flag
    end
    self.revision = self.revision + 1
end

function NPCPersonRoster:clearPresences()
    self.presences = {}
    self.presenceOrder = {}
    self.presencesUnavailable = false
    self.revision = self.revision + 1
end

function NPCPersonRoster:getPresence(id)
    for _, key in ipairs(self.presenceOrder) do
        local p = self.presences[key]
        if p.id == id then return p end
    end
    return nil
end

-- =========================================================
-- Public snapshot (server)
-- =========================================================

local function personRecord(person, actionable)
    local live = person.live == true
    local rec = {
        kind = live and NPCPersonRoster.KIND_LIVE or NPCPersonRoster.KIND_WAITING,
        personIdPresent = true,
        personId = person.id,
        ordinal = 0,
        name = NPCPersonRoster.boundLabel(person.name, NPCPersonRoster.NAME_LIMIT),
        personality = NPCPersonRoster.boundLabel(person.personality, NPCPersonRoster.SHORT_LIMIT),
        aiState = NPCPersonRoster.boundLabel(live and person.aiState or "idle", NPCPersonRoster.SHORT_LIMIT),
        currentAction = NPCPersonRoster.boundLabel(live and person.currentAction or "idle", NPCPersonRoster.SHORT_LIMIT),
        isFemale = person.isFemale == true,
        appearanceSeed = num(person.appearanceSeed, 1),
        roleLabel = NPCPersonRoster.boundLabel(person.role or "", NPCPersonRoster.LABEL_LIMIT),
        houseLabel = NPCPersonRoster.boundLabel(person.homeBuildingName or "", NPCPersonRoster.LABEL_LIMIT),
        reasonKey = NPCPersonRoster.boundLabel(live and "" or (person.waitingReason or ""), NPCPersonRoster.LABEL_LIMIT),
        trustPresent = false, trust = 0,
        positionPresent = false, x = 0, y = 0, z = 0,
        providerPresent = person.providerToken == NPCPersonRoster.CONSULTANT_TOKEN,
        actionable = actionable == true,
    }
    -- Trust and position are facts of a live person only. A waiting person keeps
    -- her saved name and reason; she gets no fabricated live trust or arrow.
    if live and NPCPersonRoster.isFiniteNumber(person.relationship) then
        rec.trustPresent = true
        rec.trust = math.max(0, math.min(100, person.relationship))
    end
    if live and person.position and NPCPersonRoster.isFiniteNumber(person.position.x)
        and NPCPersonRoster.isFiniteNumber(person.position.z) then
        rec.positionPresent = true
        rec.x, rec.y, rec.z = person.position.x, num(person.position.y, 0), person.position.z
    end
    return rec
end

local function presenceRecord(presence)
    local rec = {
        kind = NPCPersonRoster.KIND_PRESENCE,
        personIdPresent = true,
        personId = presence.id,
        ordinal = 0,
        name = NPCPersonRoster.boundLabel(presence.name, NPCPersonRoster.NAME_LIMIT),
        personality = "",
        aiState = NPCPersonRoster.boundLabel(presence.currentAction or "idle", NPCPersonRoster.SHORT_LIMIT),
        currentAction = NPCPersonRoster.boundLabel(presence.currentAction or "idle", NPCPersonRoster.SHORT_LIMIT),
        isFemale = false,
        appearanceSeed = 1,
        roleLabel = "",
        houseLabel = "",
        reasonKey = presence.unavailable and NPCPersonRoster.REASON_PRESENCE_UNAVAILABLE or NPCPersonRoster.REASON_PRESENCE,
        trustPresent = false, trust = 0,      -- a presence carries no trust value, not a fake zero
        positionPresent = false, x = 0, y = 0, z = 0,
        providerPresent = false,
        actionable = false,
    }
    if presence.positionKnown and not presence.unavailable then
        rec.positionPresent = true
        rec.x, rec.y, rec.z = presence.position.x, presence.position.y, presence.position.z
    end
    return rec
end

local function opaqueRecord(raw, ordinal)
    local label = ""
    if type(raw) == "table" and type(raw.name) == "string" then label = raw.name end
    return {
        kind = NPCPersonRoster.KIND_OPAQUE,
        personIdPresent = false,
        personId = 0,
        ordinal = ordinal,
        name = NPCPersonRoster.boundLabel(label, NPCPersonRoster.NAME_LIMIT),
        personality = "", aiState = "", currentAction = "",
        isFemale = false, appearanceSeed = 1,
        roleLabel = "", houseLabel = "",
        reasonKey = NPCPersonRoster.REASON_OPAQUE,
        trustPresent = false, trust = 0,
        positionPresent = false, x = 0, y = 0, z = 0,
        providerPresent = false,
        actionable = false,
    }
end

--- Every record of the current population, in a stable order: durable people
--- by number, then presences, then opaque rows by ordinal. Returns nil plus a
--- reason when the count exceeds the supported client snapshot; no saved host
--- record is dropped to make it fit.
function NPCPersonRoster:buildRecords()
    local sys = self.npcSystem
    local records = {}
    for _, person in ipairs(self.roster) do
        local actionable = false
        if sys ~= nil and sys.isPersonActionable ~= nil then
            actionable = sys:isPersonActionable(person)
        end
        records[#records + 1] = personRecord(person, actionable)
    end
    for _, key in ipairs(self.presenceOrder) do
        records[#records + 1] = presenceRecord(self.presences[key])
    end
    for i, raw in ipairs(self.opaque) do
        records[#records + 1] = opaqueRecord(raw, i)
    end
    if #records > NPCPersonRoster.MAX_RECORDS then
        return nil, NPCPersonRoster.REASON_SNAPSHOT_TOO_LARGE
    end
    return records
end

--- Stamp a new snapshot with the next sequence number. A snapshot that cannot
--- be assembled publishes unavailable status with zero records; the client keeps
--- its last-confirmed roster and refuses a partial-current claim.
function NPCPersonRoster:publishSnapshot()
    if self.snapshotSequence >= NPCPersonRoster.MAX_ID then
        return { schema = NPCPersonRoster.SCHEMA, loadState = self.loadState, sequence = NPCPersonRoster.MAX_ID,
            unavailable = true, reasonKey = NPCPersonRoster.REASON_EXHAUSTED, records = {}, total = 0, pageCount = 1 }
    end
    self.snapshotSequence = self.snapshotSequence + 1
    local snapshot = {
        schema = NPCPersonRoster.SCHEMA,
        loadState = self.loadState,
        sequence = self.snapshotSequence,
        unavailable = false,
        reasonKey = "",
        records = {},
        total = 0,
        pageCount = 1,
    }
    if self.loadState == NPCPersonRoster.LOAD_READY then
        local records, why = self:buildRecords()
        if records == nil then
            snapshot.unavailable = true
            snapshot.reasonKey = why
        else
            snapshot.records = records
            snapshot.total = #records
            snapshot.pageCount = NPCPersonRoster.pageCountFor(#records)
        end
    else
        snapshot.reasonKey = self.loadReason or ""
    end
    return snapshot
end

--- One page of a snapshot (1-based), with the header repeated.
function NPCPersonRoster.pageOf(snapshot, pageIndex)
    local page = {
        schema = snapshot.schema, loadState = snapshot.loadState, sequence = snapshot.sequence,
        total = snapshot.total, pageIndex = pageIndex, pageCount = snapshot.pageCount,
        unavailable = snapshot.unavailable, reasonKey = snapshot.reasonKey, records = {},
    }
    local first = (pageIndex - 1) * NPCPersonRoster.PAGE_RECORDS + 1
    local last = math.min(pageIndex * NPCPersonRoster.PAGE_RECORDS, snapshot.total)
    for i = first, last do
        page.records[#page.records + 1] = snapshot.records[i]
    end
    return page
end

-- =========================================================
-- Client staging: publish only a complete, agreeing snapshot
-- =========================================================

local function validRecord(rec, seen)
    if type(rec) ~= "table" then return false end
    local kind = rec.kind
    if kind == NPCPersonRoster.KIND_OPAQUE then
        return rec.personIdPresent ~= true
    end
    if kind ~= NPCPersonRoster.KIND_LIVE and kind ~= NPCPersonRoster.KIND_WAITING
        and kind ~= NPCPersonRoster.KIND_PRESENCE then
        return false
    end
    if rec.personIdPresent ~= true or not NPCPersonRoster.validId(rec.personId) then return false end
    if seen[rec.personId] then return false end
    seen[rec.personId] = true
    return true
end

local function sameRecords(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        local x, y = a[i], b[i]
        for k, v in pairs(x) do if y[k] ~= v then return false end end
        for k in pairs(y) do if x[k] == nil then return false end end
    end
    return true
end

--- Receive one page of a snapshot. Identical duplicate pages are harmless; a
--- conflicting duplicate, a bad count, a bad id or a bad schema invalidates the
--- pending snapshot; an older sequence never replaces newer pending or
--- published data. Publication happens only when all pages agree and the full
--- set validates. Returns one of "complete", "staged", "duplicate", "rejected",
--- "unavailable".
function NPCPersonRoster:receivePage(page)
    if type(page) ~= "table" or page.schema ~= NPCPersonRoster.SCHEMA then return "rejected" end
    local sequence, total = page.sequence, page.total
    if not NPCPersonRoster.validId(sequence) then return "rejected" end
    if sequence < self.publishedSequence then return "rejected" end
    if sequence == self.publishedSequence and self.publishedSequence > 0 then return "duplicate" end

    if page.unavailable == true then
        -- The server could not assemble a current snapshot. Nothing partial is
        -- published; what is displayed stays last-confirmed and unavailable for
        -- interactions.
        self.clientUnavailable = true
        self.clientReason = page.reasonKey or NPCPersonRoster.REASON_SNAPSHOT_TOO_LARGE
        if self.pending ~= nil and self.pending.sequence < sequence then self.pending = nil end
        return "unavailable"
    end

    if not NPCPersonRoster.isFiniteNumber(total) or total < 0 or total > NPCPersonRoster.MAX_RECORDS
        or total ~= math.floor(total) then return "rejected" end
    local pageCount, pageIndex = page.pageCount, page.pageIndex
    if pageCount ~= NPCPersonRoster.pageCountFor(total) or pageCount > NPCPersonRoster.MAX_PAGES then return "rejected" end
    if not NPCPersonRoster.isFiniteNumber(pageIndex) or pageIndex < 1 or pageIndex > pageCount
        or pageIndex ~= math.floor(pageIndex) then return "rejected" end
    local expected = math.min(NPCPersonRoster.PAGE_RECORDS, math.max(0, total - (pageIndex - 1) * NPCPersonRoster.PAGE_RECORDS))
    if type(page.records) ~= "table" or #page.records ~= expected then return "rejected" end

    local pending = self.pending
    if pending == nil or sequence > pending.sequence then
        -- A newer snapshot replaces the pending one; only one bounded assembly.
        -- What is displayed meanwhile is last-confirmed (the view says PENDING).
        pending = { sequence = sequence, total = total, pageCount = pageCount, pages = {}, received = 0,
            invalid = false, loadState = page.loadState, reasonKey = page.reasonKey }
        self.pending = pending
    elseif sequence < pending.sequence then
return "rejected"
    end
    if pending.total ~= total or pending.pageCount ~= pageCount or pending.loadState ~= page.loadState then
        pending.invalid = true
        return "rejected"
    end
    local held = pending.pages[pageIndex]
    if held ~= nil then
        if not sameRecords(held, page.records) then
            pending.invalid = true
            return "rejected"
        end
        return "duplicate"
    end
    pending.pages[pageIndex] = page.records
    pending.received = pending.received + 1
    if pending.received < pending.pageCount then return "staged" end
    if pending.invalid then return "rejected" end

    local seen, rows = {}, {}
    for i = 1, pending.pageCount do
        for _, rec in ipairs(pending.pages[i]) do
            if not validRecord(rec, seen) then
                pending.invalid = true
                return "rejected"
            end
            rows[#rows + 1] = rec
        end
    end
    if #rows ~= total then
        pending.invalid = true
        return "rejected"
    end
    self.pending = nil
    self:_publishClient(sequence, pending.loadState, rows, pending.reasonKey)
    return "complete"
end

--- The NetworkSync route: one complete validated array becomes the same atomic
--- apply. The caller validated stamps, counts and the trailer already; this
--- re-checks the record set and the sequence rule.
function NPCPersonRoster:receiveWhole(snapshot)
    if type(snapshot) ~= "table" or snapshot.schema ~= NPCPersonRoster.SCHEMA then return "rejected" end
    if not NPCPersonRoster.validId(snapshot.sequence) then return "rejected" end
    if snapshot.sequence < self.publishedSequence then return "rejected" end
    if snapshot.sequence == self.publishedSequence and self.publishedSequence > 0 then return "duplicate" end
    if snapshot.unavailable == true then
        self.clientUnavailable = true
        self.clientReason = snapshot.reasonKey or NPCPersonRoster.REASON_SNAPSHOT_TOO_LARGE
        return "unavailable"
    end
    local records = snapshot.records
    if type(records) ~= "table" or #records > NPCPersonRoster.MAX_RECORDS then return "rejected" end
    local seen = {}
    for _, rec in ipairs(records) do
        if not validRecord(rec, seen) then return "rejected" end
    end
    if self.pending ~= nil and self.pending.sequence <= snapshot.sequence then self.pending = nil end
    self:_publishClient(snapshot.sequence, snapshot.loadState, records, snapshot.reasonKey)
    return "complete"
end

function NPCPersonRoster:_publishClient(sequence, loadState, rows, reasonKey)
    self.publishedSequence = sequence
    self.clientRows = rows
    self.clientById = {}
    for _, rec in ipairs(rows) do
        if rec.personIdPresent then self.clientById[rec.personId] = rec end
    end
    self.clientLoadState = loadState or NPCPersonRoster.LOAD_READY
    self.clientReason = reasonKey or ""
    self.clientUnavailable = false
    if self.clientLoadState == NPCPersonRoster.LOAD_READY then
        self.loadState = NPCPersonRoster.LOAD_READY
        self.loadReason = nil
    else
        -- A server that is WAITING or FAILED is an explicit state on the client
        -- too, never a fake empty town.
        self.loadState = self.clientLoadState
        self.loadReason = (reasonKey ~= "" and reasonKey) or NPCPersonRoster.REASON_LOADING
    end
    self.revision = sequence
    local sys = self.npcSystem
    if sys ~= nil and sys.installClientSnapshot ~= nil then
        sys:installClientSnapshot(self.clientLoadState, rows, sequence)
    end
end

--- CURRENT: a complete snapshot is published and nothing newer is pending.
--- PENDING: a newer snapshot is incomplete, so what is displayed is
--- last-confirmed and unavailable for interactions. UNAVAILABLE: nothing
--- published yet, or the server could not assemble a current snapshot.
function NPCPersonRoster:getClientSnapshotState()
    if self.clientRows == nil then return NPCPersonRoster.SNAPSHOT_UNAVAILABLE end
    if self.pending ~= nil and self.pending.sequence > self.publishedSequence and not self.pending.invalid then
        return NPCPersonRoster.SNAPSHOT_PENDING
    end
    if self.clientUnavailable then return NPCPersonRoster.SNAPSHOT_UNAVAILABLE end
    return NPCPersonRoster.SNAPSHOT_CURRENT
end

-- =========================================================
-- The copied roster view (section 9a)
-- =========================================================

local function viewRow(rec, index)
    local row = {
        displayKey = index,
        kind = rec.kind,
        personId = rec.personIdPresent and rec.personId or nil,
        name = rec.name, roleLabel = rec.roleLabel, houseLabel = rec.houseLabel,
        reasonKey = rec.reasonKey,
        trust = rec.trustPresent and rec.trust or nil,
        position = rec.positionPresent and { x = rec.x, y = rec.y, z = rec.z } or nil,
        providerPresent = rec.providerPresent == true,
        isFemale = rec.isFemale == true,
        appearanceSeed = rec.appearanceSeed,
        canTalk = rec.actionable == true,
        canGift = rec.actionable == true,
        canWork = rec.actionable == true,
        canGoTo = rec.actionable == true and rec.positionPresent == true,
    }
    return row
end

--- Schema 1: personLoadState, snapshotState, revision, a reason key and copied
--- rows. No favour, payment, owner farm or private recovery record appears.
--- Missing trust is unavailable, never zero.
function NPCPersonRoster:getRosterView(isServer)
    local view = { schema = 1, rows = {} }
    if isServer then
        view.personLoadState = self.loadState
        view.revision = self.revision
        view.reasonKey = self.loadReason or ""
        if self.loadState == NPCPersonRoster.LOAD_READY then
            local records, why = self:buildRecords()
            if records == nil then
                view.snapshotState = NPCPersonRoster.SNAPSHOT_UNAVAILABLE
                view.reasonKey = why
            else
                view.snapshotState = NPCPersonRoster.SNAPSHOT_CURRENT
                for i, rec in ipairs(records) do view.rows[i] = viewRow(rec, i) end
            end
        else
            view.snapshotState = NPCPersonRoster.SNAPSHOT_UNAVAILABLE
        end
        return view
    end
    view.personLoadState = self.clientRows ~= nil and self.clientLoadState or NPCPersonRoster.LOAD_WAITING
    view.revision = self.publishedSequence
    view.snapshotState = self:getClientSnapshotState()
    view.reasonKey = self.clientReason or ""
    if self.clientRows ~= nil then
        for i, rec in ipairs(self.clientRows) do view.rows[i] = viewRow(rec, i) end
    end
    return view
end

print("[NPC Favor] NPCPersonRoster loaded")
