-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- NETWORK SYNC:
-- [x] Server-to-client bulk sync of NPC positions and states
-- [x] Periodic broadcast every 5 seconds from server update loop
-- [x] On-join sync to newly connected players via sendToConnection
-- [ ] Delta compression - only send NPCs whose state changed since last sync
-- [ ] Adaptive sync frequency based on player proximity to NPCs
-- [ ] Level-of-detail sync (full data for nearby, minimal for distant)
--
-- BANDWIDTH & PERFORMANCE:
-- [x] DoS prevention with MAX_NPC_COUNT cap (50 NPCs per packet)
-- [x] Stream drain for oversized packets to prevent desync
-- [x] String truncation on all read/write operations
-- [ ] Binary packing for position data (quantized int16 instead of float32)
-- [ ] Batch coalescing - merge rapid state changes into single packet
-- [ ] Bandwidth monitoring with automatic throttle under high load
--
-- SECURITY:
-- [x] Client-only execution gate (server ignores incoming state events)
-- [ ] Packet sequence numbering to detect replay attacks
-- [ ] Checksum validation on received NPC data arrays
-- =========================================================

--[[
    FS25_NPCFavor - NPC State Sync Event

    Server-to-client bulk sync of all NPC positions, states, and data.
    Sent periodically (every 5 seconds) and on state changes.

    Pattern from: UsedPlusSettingsEvent TYPE_BULK
    OWASP: DoS cap on NPC count, stream drain for oversized packets,
           client-only execution gate, string truncation.
]]

NPCStateSyncEvent = NPCStateSyncEvent or {}
local NPCStateSyncEvent_mt = Class(NPCStateSyncEvent, Event)

InitEventClass(NPCStateSyncEvent, "NPCStateSyncEvent")

-- Maximum NPCs to sync in a single packet (DoS prevention)
NPCStateSyncEvent.MAX_NPC_COUNT = 50

function NPCStateSyncEvent.emptyNew()
    local self = Event.new(NPCStateSyncEvent_mt)
    self.npcData = {}
    return self
end

function NPCStateSyncEvent.new(npcDataArray)
    local self = NPCStateSyncEvent.emptyNew()
    self.npcData = npcDataArray or {}
    return self
end

function NPCStateSyncEvent:writeStream(streamId, connection)
    local count = math.min(#self.npcData, NPCStateSyncEvent.MAX_NPC_COUNT)
    streamWriteUInt8(streamId, count)

    for i = 1, count do
        local npc = self.npcData[i]
        streamWriteInt32(streamId, npc.id or 0)
        streamWriteString(streamId, (npc.name or ""):sub(1, 64))
        streamWriteString(streamId, (npc.personality or ""):sub(1, 32))
        streamWriteFloat32(streamId, npc.x or 0)
        streamWriteFloat32(streamId, npc.y or 0)
        streamWriteFloat32(streamId, npc.z or 0)
        streamWriteString(streamId, (npc.aiState or "idle"):sub(1, 32))
        streamWriteFloat32(streamId, npc.relationship or 50)
        streamWriteBool(streamId, npc.isActive or false)
        streamWriteString(streamId, (npc.currentAction or "idle"):sub(1, 32))
    end
end

function NPCStateSyncEvent:readStream(streamId, connection)
    local rawCount = streamReadUInt8(streamId)

    -- OWASP DoS: Cap NPC count
    local safeCount = math.min(rawCount, NPCStateSyncEvent.MAX_NPC_COUNT)

    self.npcData = {}
    for i = 1, safeCount do
        local entry = {}
        entry.id = streamReadInt32(streamId)
        entry.name = streamReadString(streamId):sub(1, 64)
        entry.personality = streamReadString(streamId):sub(1, 32)
        entry.x = streamReadFloat32(streamId)
        entry.y = streamReadFloat32(streamId)
        entry.z = streamReadFloat32(streamId)
        entry.aiState = streamReadString(streamId):sub(1, 32)
        entry.relationship = streamReadFloat32(streamId)
        entry.isActive = streamReadBool(streamId)
        entry.currentAction = streamReadString(streamId):sub(1, 32)
        table.insert(self.npcData, entry)
    end

    -- OWASP DoS: Drain remaining entries if rawCount exceeded cap
    for i = safeCount + 1, rawCount do
        streamReadInt32(streamId)    -- id
        streamReadString(streamId)   -- name
        streamReadString(streamId)   -- personality
        streamReadFloat32(streamId)  -- x
        streamReadFloat32(streamId)  -- y
        streamReadFloat32(streamId)  -- z
        streamReadString(streamId)   -- aiState
        streamReadFloat32(streamId)  -- relationship
        streamReadBool(streamId)     -- isActive
        streamReadString(streamId)   -- currentAction
    end

    self:run(connection)
end

function NPCStateSyncEvent:run(connection)
    -- OWASP Access Control: Only process on clients
    if g_server ~= nil then
        return
    end

    -- Apply synced state
    if g_NPCSystem and g_NPCSystem.applyNetworkState then
        g_NPCSystem:applyNetworkState(self.npcData)
    end
end

--[[
    Broadcast current NPC state from server to all clients.
    Called periodically from NPCSystem:update() on the server.
]]
function NPCStateSyncEvent.broadcastState()
    if g_server == nil or g_NPCSystem == nil then
        return
    end

    local data = g_NPCSystem:collectSyncData()
    if data and #data > 0 then
        g_server:broadcastEvent(NPCStateSyncEvent.new(data), false)
    end
end

--[[
    Send current NPC state to a specific connection (on player join).
    @param connection - Target client connection
]]
function NPCStateSyncEvent.sendToConnection(connection)
    if g_server == nil or g_NPCSystem == nil then
        return
    end

    local data = g_NPCSystem:collectSyncData()
    if data and #data > 0 then
        connection:sendEvent(NPCStateSyncEvent.new(data))
    end
end

print("[NPC Favor] NPCStateSyncEvent loaded")
