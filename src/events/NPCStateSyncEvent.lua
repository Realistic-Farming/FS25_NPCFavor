-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- NETWORK SYNC:
-- [x] Server-to-client bulk sync of NPC positions and states
-- [x] Periodic broadcast every 5 seconds from server update loop
-- [x] On-join sync to newly connected players via sendToConnection
-- [x] RSF-F357: paged complete snapshots with a sequence number; the client
--     publishes only when every page has arrived and agrees
-- [ ] Delta compression - only send NPCs whose state changed since last sync
-- [ ] Adaptive sync frequency based on player proximity to NPCs
-- [ ] Level-of-detail sync (full data for nearby, minimal for distant)
--
-- BANDWIDTH & PERFORMANCE:
-- [x] DoS prevention with MAX_NPC_COUNT cap (50 records per packet)
-- [x] Stream drain for oversized packets to prevent desync
-- [x] String truncation on all read/write operations
-- [ ] Binary packing for position data (quantized int16 instead of float32)
-- [ ] Batch coalescing - merge rapid state changes into single packet
-- [ ] Bandwidth monitoring with automatic throttle under high load
--
-- SECURITY:
-- [x] Client-only execution gate (server ignores incoming state events)
-- [x] Packet sequence numbering (RSF-F357: an older snapshot never replaces a newer one)
-- [ ] Checksum validation on received NPC data arrays
-- =========================================================

--[[
    FS25_NPCFavor - NPC State Sync Event

    Server-to-client publication of the complete public roster as one stamped
    snapshot in pages of at most 50 records (RSF-F357 section 8). Sent
    periodically (every 5 seconds), on state changes, and on join.

    A page carries the snapshot header (schema, server person load state,
    sequence, total record count, page index and count, the unavailable flag
    and a reason key) followed by its records: every retained person, live or
    waiting, every worker presence and every opaque row. Personal trust and a
    position travel only for a live person; a presence carries no trust value,
    not a fake zero. No favour, owner, payment or recovery detail.

    Pattern from: UsedPlusSettingsEvent TYPE_BULK
    OWASP: DoS cap on record count, stream drain for oversized packets,
           client-only execution gate, string truncation.
]]

NPCStateSyncEvent = NPCStateSyncEvent or {}
local NPCStateSyncEvent_mt = Class(NPCStateSyncEvent, Event)

InitEventClass(NPCStateSyncEvent, "NPCStateSyncEvent")

-- Maximum records in a single packet (DoS prevention); equals the roster's page bound.
NPCStateSyncEvent.MAX_NPC_COUNT = 50

local NAME_LIMIT, SHORT_LIMIT, LABEL_LIMIT = 64, 32, 128

function NPCStateSyncEvent.emptyNew()
    local self = Event.new(NPCStateSyncEvent_mt)
    self.page = nil
    return self
end

--- @param page  one page of a snapshot (NPCPersonRoster.pageOf)
function NPCStateSyncEvent.new(page)
    local self = NPCStateSyncEvent.emptyNew()
    self.page = page
    return self
end

local function bound(s, limit)
    s = tostring(s or "")
    if #s > limit then return s:sub(1, limit) end
    return s
end

local function writeRecord(streamId, rec)
    streamWriteUInt8(streamId, NPCPersonRoster.KIND_CODE[rec.kind] or 4)
    streamWriteBool(streamId, rec.personIdPresent == true)
    streamWriteInt32(streamId, rec.personIdPresent and rec.personId or 0)
    streamWriteInt32(streamId, rec.ordinal or 0)
    streamWriteString(streamId, bound(rec.name, NAME_LIMIT))
    streamWriteString(streamId, bound(rec.personality, SHORT_LIMIT))
    streamWriteString(streamId, bound(rec.aiState, SHORT_LIMIT))
    streamWriteString(streamId, bound(rec.currentAction, SHORT_LIMIT))
    streamWriteBool(streamId, rec.isFemale == true)
    streamWriteInt32(streamId, rec.appearanceSeed or 1)
    streamWriteString(streamId, bound(rec.roleLabel, LABEL_LIMIT))
    streamWriteString(streamId, bound(rec.houseLabel, LABEL_LIMIT))
    streamWriteString(streamId, bound(rec.reasonKey, LABEL_LIMIT))
    streamWriteBool(streamId, rec.trustPresent == true)
    streamWriteFloat32(streamId, rec.trustPresent and rec.trust or 0)
    streamWriteBool(streamId, rec.positionPresent == true)
    streamWriteFloat32(streamId, rec.positionPresent and rec.x or 0)
    streamWriteFloat32(streamId, rec.positionPresent and rec.y or 0)
    streamWriteFloat32(streamId, rec.positionPresent and rec.z or 0)
    streamWriteBool(streamId, rec.providerPresent == true)
    streamWriteBool(streamId, rec.actionable == true)
end

local function readRecord(streamId)
    local rec = {}
    rec.kind = NPCPersonRoster.KIND_NAME[streamReadUInt8(streamId)] or "OPAQUE"
    rec.personIdPresent = streamReadBool(streamId)
    rec.personId = streamReadInt32(streamId)
    rec.ordinal = streamReadInt32(streamId)
    rec.name = bound(streamReadString(streamId), NAME_LIMIT)
    rec.personality = bound(streamReadString(streamId), SHORT_LIMIT)
    rec.aiState = bound(streamReadString(streamId), SHORT_LIMIT)
    rec.currentAction = bound(streamReadString(streamId), SHORT_LIMIT)
    rec.isFemale = streamReadBool(streamId)
    rec.appearanceSeed = streamReadInt32(streamId)
    rec.roleLabel = bound(streamReadString(streamId), LABEL_LIMIT)
    rec.houseLabel = bound(streamReadString(streamId), LABEL_LIMIT)
    rec.reasonKey = bound(streamReadString(streamId), LABEL_LIMIT)
    rec.trustPresent = streamReadBool(streamId)
    rec.trust = streamReadFloat32(streamId)
    rec.positionPresent = streamReadBool(streamId)
    rec.x = streamReadFloat32(streamId)
    rec.y = streamReadFloat32(streamId)
    rec.z = streamReadFloat32(streamId)
    rec.providerPresent = streamReadBool(streamId)
    rec.actionable = streamReadBool(streamId)
    if not rec.personIdPresent then rec.personId = 0 end
    if not rec.trustPresent then rec.trust = 0 end
    if not rec.positionPresent then rec.x, rec.y, rec.z = 0, 0, 0 end
    return rec
end

function NPCStateSyncEvent:writeStream(streamId, connection)
    local page = self.page or {}
    streamWriteUInt8(streamId, page.schema or NPCPersonRoster.SCHEMA)
    streamWriteUInt8(streamId, NPCPersonRoster.LOAD_STATE_CODE[page.loadState] or 1)
    streamWriteInt32(streamId, page.sequence or 0)
    streamWriteInt32(streamId, page.total or 0)
    streamWriteUInt8(streamId, page.pageIndex or 1)
    streamWriteUInt8(streamId, page.pageCount or 1)
    streamWriteBool(streamId, page.unavailable == true)
    streamWriteString(streamId, bound(page.reasonKey, LABEL_LIMIT))

    local records = page.records or {}
    local count = math.min(#records, NPCStateSyncEvent.MAX_NPC_COUNT)
    streamWriteUInt8(streamId, count)
    for i = 1, count do
        writeRecord(streamId, records[i])
    end
end

function NPCStateSyncEvent:readStream(streamId, connection)
    local page = {}
    page.schema = streamReadUInt8(streamId)
    page.loadState = NPCPersonRoster.LOAD_STATE_NAME[streamReadUInt8(streamId)] or "WAITING"
    page.sequence = streamReadInt32(streamId)
    page.total = streamReadInt32(streamId)
    page.pageIndex = streamReadUInt8(streamId)
    page.pageCount = streamReadUInt8(streamId)
    page.unavailable = streamReadBool(streamId)
    page.reasonKey = bound(streamReadString(streamId), LABEL_LIMIT)

    local rawCount = streamReadUInt8(streamId)

    -- OWASP DoS: Cap record count
    local safeCount = math.min(rawCount, NPCStateSyncEvent.MAX_NPC_COUNT)

    page.records = {}
    for _ = 1, safeCount do
        table.insert(page.records, readRecord(streamId))
    end

    -- OWASP DoS: Drain remaining entries if rawCount exceeded cap
    for _ = safeCount + 1, rawCount do
        readRecord(streamId)
    end

    self.page = page
    self:run(connection)
end

function NPCStateSyncEvent:run(connection)
    -- OWASP Access Control: Only process on clients
    if g_server ~= nil then
        return
    end

    -- Stage the page; the roster publishes only a complete, agreeing snapshot.
    if g_NPCSystem and g_NPCSystem.people and g_NPCSystem.people.receivePage then
        g_NPCSystem.people:receivePage(self.page)
    end
end

--- Send every page of one snapshot through `send(event)`. An initialized empty
--- roster is one complete zero-row snapshot; an unavailable snapshot is one
--- page that says so.
local function sendSnapshot(snapshot, send)
    if snapshot == nil then return end
    for pageIndex = 1, snapshot.pageCount do
        send(NPCStateSyncEvent.new(NPCPersonRoster.pageOf(snapshot, pageIndex)))
    end
end

--[[
    Broadcast the current snapshot from server to all clients.
    Called periodically from NPCSystem:update() on the server.
]]
function NPCStateSyncEvent.broadcastState()
    if g_server == nil or g_NPCSystem == nil or g_NPCSystem.publishSnapshot == nil then
        return
    end
    sendSnapshot(g_NPCSystem:publishSnapshot(), function(event)
        g_server:broadcastEvent(event, false)
    end)
end

--[[
    Send the current snapshot to a specific connection (on player join).
    @param connection - Target client connection
]]
function NPCStateSyncEvent.sendToConnection(connection)
    if g_server == nil or g_NPCSystem == nil or g_NPCSystem.publishSnapshot == nil then
        return
    end
    sendSnapshot(g_NPCSystem:publishSnapshot(), function(event)
        connection:sendEvent(event)
    end)
end

print("[NPC Favor] NPCStateSyncEvent loaded")
