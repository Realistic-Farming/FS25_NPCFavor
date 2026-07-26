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
--   * NetworkSync installed -> the periodic NPC state broadcast (relationship, position,
--     aiState per NPC) folds into NetworkSync's single 1Hz batch instead of the mod's own
--     5-second NPCStateSyncEvent.
--   * NetworkSync absent     -> nothing changes; NPCStateSyncEvent carries the state
--     exactly as before.
--
-- WHAT THIS BRIDGE DOES AND DOES NOT CARRY:
--   * Carries: the same per-NPC state array the mod already computes (collectSyncData) and
--     applies (applyNetworkState). No new payload is invented; the wire is a flat encoding
--     of that array so the two paths stay identical.
--   * Does NOT carry money. Favor money and completion are server-authoritative through the
--     mod's OWN hardened NPCInteractionEvent (validated client-to-server), which works with
--     or without bedrock. Money correctness never depends on NetworkSync being installed, so
--     the action channel is deliberately not used here.
--   * Settings are SettingsHub's domain (NPCSettingsHubBridge), not carried here.
--   * The mod's own join push (NPCStateSyncEvent.sendToConnection) stays live as the
--     standalone join guarantee; NetworkSync's own join snapshot also fires when present.
--     applyNetworkState is idempotent, so a client receiving both is harmless.
--
-- The cross-mod handle is g_currentMission.networkSync. Registration is order independent.
-- =========================================================

NPCNetworkSyncBridge = {}

-- Locked network channel / module id. Never renamed (a later rename desyncs a mixed lobby).
NPCNetworkSyncBridge.MODULE_ID = "NPCFavor_Sync"
NPCNetworkSyncBridge.CHANNEL   = "NPCFavor_Sync"

NPCNetworkSyncBridge.active = false   -- NetworkSync present and we registered

local function b2i(v) return v and 1 or 0 end
local function i2b(v) return (tonumber(v) or 0) ~= 0 end

-- =========================================================
-- Pure serialize / deserialize of collectSyncData()'s array
-- =========================================================
-- Flat array: arr[1] = count, then per NPC 10 values matching collectSyncData exactly:
--   id, name, personality, x, y, z, aiState, relationship, isActive(0/1), currentAction
function NPCNetworkSyncBridge.serialize(data)
    local arr = { 0 }
    local n = 0
    for _, npc in ipairs(data or {}) do
        n = n + 1
        arr[#arr + 1] = npc.id or 0
        arr[#arr + 1] = npc.name or ""
        arr[#arr + 1] = npc.personality or ""
        arr[#arr + 1] = npc.x or 0
        arr[#arr + 1] = npc.y or 0
        arr[#arr + 1] = npc.z or 0
        arr[#arr + 1] = npc.aiState or "idle"
        arr[#arr + 1] = npc.relationship or 50
        arr[#arr + 1] = b2i(npc.isActive == true)
        arr[#arr + 1] = npc.currentAction or "idle"
    end
    arr[1] = n
    return arr
end

-- Rebuild the { ... } record array applyNetworkState expects. Never crashes on a short
-- or malformed array.
function NPCNetworkSyncBridge.deserialize(arr)
    local out = {}
    if type(arr) ~= "table" then return out end
    local i = 1
    local count = tonumber(arr[i]) or 0; i = i + 1
    for _ = 1, count do
        local entry = {}
        entry.id            = tonumber(arr[i]) or 0; i = i + 1
        entry.name          = arr[i] or "";          i = i + 1
        entry.personality   = arr[i] or "";          i = i + 1
        entry.x             = tonumber(arr[i]) or 0; i = i + 1
        entry.y             = tonumber(arr[i]) or 0; i = i + 1
        entry.z             = tonumber(arr[i]) or 0; i = i + 1
        entry.aiState       = arr[i] or "idle";      i = i + 1
        entry.relationship  = tonumber(arr[i]) or 50; i = i + 1
        entry.isActive      = i2b(arr[i]);           i = i + 1
        entry.currentAction = arr[i] or "idle";      i = i + 1
        out[#out + 1] = entry
    end
    return out
end

-- =========================================================
-- NetworkSync callbacks (plain functions - called with no self)
-- =========================================================

-- Server: hand NetworkSync the whole NPC state array for the next batch.
function NPCNetworkSyncBridge._onWriteState()
    if g_NPCSystem == nil or g_NPCSystem.collectSyncData == nil then return { 0 } end
    return NPCNetworkSyncBridge.serialize(g_NPCSystem:collectSyncData())
end

-- Client: apply a received NPC state array through the mod's own apply path.
function NPCNetworkSyncBridge._onReadState(arr)
    if g_NPCSystem == nil or g_NPCSystem.applyNetworkState == nil then return end
    g_NPCSystem:applyNetworkState(NPCNetworkSyncBridge.deserialize(arr))
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
