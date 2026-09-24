-- =========================================================
-- FS25 NPC Favor - NetworkSync bridge
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
-- Optional bridge to FS25_NetworkSync. NPCFavor ships standalone, so this is strictly
-- delegate-when-present:
--   * NetworkSync installed -> the periodic public roster snapshot folds into
--     NetworkSync's single 1Hz batch instead of the mod's own 5-second NPCStateSyncEvent.
--   * NetworkSync absent     -> nothing changes; NPCStateSyncEvent carries the state
--     exactly as before.
--
-- WHAT THIS BRIDGE DOES AND DOES NOT CARRY:
--   * Carries: the same stamped snapshot the own event pages (RSF-F357 section 8), as
--     one flat FULL array: the snapshot header, every record with its own sequence
--     stamp, and a final sequence/count trailer. The host adapter validates every
--     stamp and count and feeds the SAME atomic roster apply only after a complete
--     valid array; a mixed or short array is unavailable, never partial current state.
--     NetworkSync's own framing chunks the array under its event budget and
--     reassembles it before onReadState; no second service is invented.
--   * Does NOT carry money. Favor money and completion are server-authoritative through the
--     mod's OWN hardened NPCInteractionEvent (validated client-to-server), which works with
--     or without bedrock. Money correctness never depends on NetworkSync being installed, so
--     the action channel is deliberately not used here.
--   * Settings are SettingsHub's domain (NPCSettingsHubBridge), not carried here.
--   * The mod's own join push (NPCStateSyncEvent.sendToConnection) stays live as the
--     standalone join guarantee; NetworkSync's own join snapshot also fires when present.
--     Both routes carry the same server sequence number, so a duplicate delivery is
--     idempotent on the client.
--
-- The cross-mod handle is g_currentMission.networkSync. Registration is order independent.
-- =========================================================

NPCNetworkSyncBridge = NPCNetworkSyncBridge or {}

-- Locked network channel / module id. Never renamed (a later rename desyncs a mixed lobby).
NPCNetworkSyncBridge.MODULE_ID = "NPCFavor_Sync"
NPCNetworkSyncBridge.CHANNEL   = "NPCFavor_Sync"

NPCNetworkSyncBridge.active = false   -- NetworkSync present and we registered

-- Header: 6 values. Record: 21 values. Trailer: 2 values.
NPCNetworkSyncBridge.HEADER_LEN  = 6
NPCNetworkSyncBridge.RECORD_LEN  = 21
NPCNetworkSyncBridge.TRAILER_LEN = 2

local function b2i(v) return v and 1 or 0 end
local function i2b(v) return (tonumber(v) or 0) ~= 0 end

-- =========================================================
-- Pure serialize / deserialize of a snapshot (NPCPersonRoster.publishSnapshot)
-- =========================================================
-- Flat array:
--   header  : schema, loadStateCode, sequence, total, unavailable(0/1), reasonKey
--   record x total: sequenceStamp, kindCode, personIdPresent(0/1), personId, ordinal,
--                   name, personality, aiState, currentAction, isFemale(0/1), appearanceSeed,
--                   roleLabel, houseLabel, reasonKey, trustPresent(0/1), trust,
--                   positionPresent(0/1), x, y, z, providerPresent(0/1) .. actionable is
--                   folded into the last slot as providerPresent*2 + actionable
--   trailer : sequence, total
function NPCNetworkSyncBridge.serialize(snapshot)
    local arr = {}
    if type(snapshot) ~= "table" then return arr end
    local records = snapshot.records or {}
    local total = snapshot.unavailable and 0 or #records
    arr[#arr + 1] = snapshot.schema or NPCPersonRoster.SCHEMA
    arr[#arr + 1] = NPCPersonRoster.LOAD_STATE_CODE[snapshot.loadState] or 1
    arr[#arr + 1] = snapshot.sequence or 0
    arr[#arr + 1] = total
    arr[#arr + 1] = b2i(snapshot.unavailable == true)
    arr[#arr + 1] = tostring(snapshot.reasonKey or "")
    for i = 1, total do
        local rec = records[i]
        arr[#arr + 1] = snapshot.sequence or 0
        arr[#arr + 1] = NPCPersonRoster.KIND_CODE[rec.kind] or 4
        arr[#arr + 1] = b2i(rec.personIdPresent == true)
        arr[#arr + 1] = rec.personIdPresent and rec.personId or 0
        arr[#arr + 1] = rec.ordinal or 0
        arr[#arr + 1] = tostring(rec.name or "")
        arr[#arr + 1] = tostring(rec.personality or "")
        arr[#arr + 1] = tostring(rec.aiState or "")
        arr[#arr + 1] = tostring(rec.currentAction or "")
        arr[#arr + 1] = b2i(rec.isFemale == true)
        arr[#arr + 1] = rec.appearanceSeed or 1
        arr[#arr + 1] = tostring(rec.roleLabel or "")
        arr[#arr + 1] = tostring(rec.houseLabel or "")
        arr[#arr + 1] = tostring(rec.reasonKey or "")
        arr[#arr + 1] = b2i(rec.trustPresent == true)
        arr[#arr + 1] = rec.trustPresent and rec.trust or 0
        arr[#arr + 1] = b2i(rec.positionPresent == true)
        arr[#arr + 1] = rec.positionPresent and rec.x or 0
        arr[#arr + 1] = rec.positionPresent and rec.y or 0
        arr[#arr + 1] = rec.positionPresent and rec.z or 0
        arr[#arr + 1] = b2i(rec.providerPresent == true) * 2 + b2i(rec.actionable == true)
    end
    arr[#arr + 1] = snapshot.sequence or 0
    arr[#arr + 1] = total
    return arr
end

--- Rebuild and VALIDATE the snapshot. Returns nil plus a reason on any short,
--- mixed or stale array: a header/total mismatch, a record whose stamp is not
--- the header sequence, a trailer that disagrees, a duplicate or invalid id.
--- Never crashes on a malformed array.
function NPCNetworkSyncBridge.deserialize(arr)
    if type(arr) ~= "table" then return nil, "not_a_table" end
    local H, R, T = NPCNetworkSyncBridge.HEADER_LEN, NPCNetworkSyncBridge.RECORD_LEN, NPCNetworkSyncBridge.TRAILER_LEN
    if #arr < H + T then return nil, "short" end
    local snapshot = {}
    snapshot.schema = tonumber(arr[1])
    snapshot.loadState = NPCPersonRoster.LOAD_STATE_NAME[tonumber(arr[2]) or 0]
    snapshot.sequence = tonumber(arr[3])
    local total = tonumber(arr[4])
    snapshot.unavailable = i2b(arr[5])
    snapshot.reasonKey = tostring(arr[6] or "")
    if snapshot.schema ~= NPCPersonRoster.SCHEMA or snapshot.loadState == nil then return nil, "bad_header" end
    if not NPCPersonRoster.validId(snapshot.sequence) then return nil, "bad_sequence" end
    if total == nil or total < 0 or total > NPCPersonRoster.MAX_RECORDS or total ~= math.floor(total) then
        return nil, "bad_total"
    end
    if #arr ~= H + total * R + T then return nil, "length_mismatch" end
    local trailerSeq, trailerTotal = tonumber(arr[#arr - 1]), tonumber(arr[#arr])
    if trailerSeq ~= snapshot.sequence or trailerTotal ~= total then return nil, "bad_trailer" end

    snapshot.records = {}
    local seen = {}
    local i = H + 1
    for _ = 1, total do
        local rec = {}
        local stamp = tonumber(arr[i]); i = i + 1
        if stamp ~= snapshot.sequence then return nil, "stale_stamp" end
        rec.kind = NPCPersonRoster.KIND_NAME[tonumber(arr[i]) or 0] or "OPAQUE"; i = i + 1
        rec.personIdPresent = i2b(arr[i]); i = i + 1
        rec.personId = tonumber(arr[i]) or 0; i = i + 1
        rec.ordinal = tonumber(arr[i]) or 0; i = i + 1
        rec.name = tostring(arr[i] or ""); i = i + 1
        rec.personality = tostring(arr[i] or ""); i = i + 1
        rec.aiState = tostring(arr[i] or ""); i = i + 1
        rec.currentAction = tostring(arr[i] or ""); i = i + 1
        rec.isFemale = i2b(arr[i]); i = i + 1
        rec.appearanceSeed = tonumber(arr[i]) or 1; i = i + 1
        rec.roleLabel = tostring(arr[i] or ""); i = i + 1
        rec.houseLabel = tostring(arr[i] or ""); i = i + 1
        rec.reasonKey = tostring(arr[i] or ""); i = i + 1
        rec.trustPresent = i2b(arr[i]); i = i + 1
        rec.trust = tonumber(arr[i]) or 0; i = i + 1
        rec.positionPresent = i2b(arr[i]); i = i + 1
        rec.x = tonumber(arr[i]) or 0; i = i + 1
        rec.y = tonumber(arr[i]) or 0; i = i + 1
        rec.z = tonumber(arr[i]) or 0; i = i + 1
        local flags = tonumber(arr[i]) or 0; i = i + 1
        rec.providerPresent = flags >= 2
        rec.actionable = (flags % 2) == 1
        if not rec.personIdPresent then rec.personId = 0 end
        if rec.personIdPresent then
            if not NPCPersonRoster.validId(rec.personId) or seen[rec.personId] then return nil, "bad_id" end
            seen[rec.personId] = true
        end
        snapshot.records[#snapshot.records + 1] = rec
    end
    snapshot.total = total
    snapshot.pageCount = NPCPersonRoster.pageCountFor(total)
    return snapshot
end

-- =========================================================
-- NetworkSync callbacks (plain functions - called with no self)
-- =========================================================

-- Server: hand NetworkSync the whole stamped snapshot for the next batch.
function NPCNetworkSyncBridge._onWriteState()
    if g_NPCSystem == nil or g_NPCSystem.publishSnapshot == nil then return { } end
    local snapshot = g_NPCSystem:publishSnapshot()
    if snapshot == nil then return { } end
    return NPCNetworkSyncBridge.serialize(snapshot)
end

-- Client: validate the complete array, then the same atomic roster apply.
function NPCNetworkSyncBridge._onReadState(arr)
    if g_NPCSystem == nil or g_NPCSystem.people == nil or g_NPCSystem.people.receiveWhole == nil then return end
    local snapshot, why = NPCNetworkSyncBridge.deserialize(arr)
    if snapshot == nil then
        print(string.format("[NPC Favor] NetworkSync roster array refused (%s); keeping the last confirmed roster", tostring(why)))
        g_NPCSystem.people.clientUnavailable = true
        g_NPCSystem.people.clientReason = NPCPersonRoster.REASON_SNAPSHOT_PARTIAL
        return
    end
    g_NPCSystem.people:receiveWhole(snapshot)
end

-- =========================================================
-- Public: flag the module dirty for the next 1Hz batch.
-- =========================================================
-- Called from the NPC state broadcast choke point. Returns true when handled (so the own
-- NPCStateSyncEvent stands down), false when NetworkSync is absent so the caller fires its
-- own event.
function NPCNetworkSyncBridge.markDirty()
    if not NPCNetworkSyncBridge.active then return false end
    local ns = (g_currentMission and g_currentMission.networkSync) or g_networkSync
    if ns == nil then return false end
    ns:markDirty(NPCNetworkSyncBridge.MODULE_ID)
    return true
end

-- =========================================================
-- Registration (loadMission00Finished)
-- =========================================================
function NPCNetworkSyncBridge.register()
    NPCNetworkSyncBridge.active = false

    local ns = (g_currentMission and g_currentMission.networkSync) or g_networkSync
    if ns == nil then
        print("[NPC Favor] NetworkSync not detected; NPC MP sync uses its own event classes")
        return
    end

    local ok, err = pcall(function()
        ns:registerModule(NPCNetworkSyncBridge.MODULE_ID, {
            channel      = NPCNetworkSyncBridge.CHANNEL,
            onWriteState = NPCNetworkSyncBridge._onWriteState,
            onReadState  = NPCNetworkSyncBridge._onReadState,
        })
    end)

    if ok then
        NPCNetworkSyncBridge.active = true
        print(string.format("[NPC Favor] Registered with NetworkSync as '%s' (NPC state batches through NetworkSync)",
            NPCNetworkSyncBridge.MODULE_ID))
    else
        NPCNetworkSyncBridge.active = false
        print(string.format("[NPC Favor] NetworkSync registration failed: %s (falling back to NPC event classes)", tostring(err)))
    end
end
