-- =========================================================
-- FS25 NPC Favor - StateLedger bridge
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
-- Optional bridge to FS25_StateLedger. NPCFavor ships standalone, so this is strictly
-- delegate-when-present:
--   * StateLedger installed -> the ecosystem master save file is the LOAD source of
--     truth (npc_favor.xml is still written every save as a safety copy, so removing the
--     ledger later never loses data).
--   * StateLedger absent     -> nothing changes; npc_favor.xml is primary as always.
--
-- On the first load after installing the ledger onto an existing save, the ledger has no
-- NPC block yet (deserialize delivers nil), so NPCSystem's load falls back to importing
-- the existing npc_favor.xml. From then on the ledger carries the state.
--
-- The cross-mod handle is g_currentMission.stateLedger (the bare g_stateLedger global is
-- only visible inside StateLedger's own mod environment). Registration is order
-- independent: StateLedger delivers our deserialize exactly once, whether we register
-- before or after it parses the master file. We force the idempotent parseFile right
-- after registering so deserialize is delivered BEFORE NPCFavor's own load runs (which
-- happens later, in the first-frame init), rather than letting hook order decide.
-- =========================================================

NPCStateLedgerBridge = NPCStateLedgerBridge or {}

-- Locked persistence key inside the master file. Never renamed after first persist (a
-- later rename orphans saved NPC state). Matches StateLedger's <Mod>_<Thing> convention.
NPCStateLedgerBridge.MODULE_ID = "NPCFavor_State"

NPCStateLedgerBridge.active       = false   -- ledger present and we registered
NPCStateLedgerBridge.delivered    = false   -- deserialize has fired (once)
NPCStateLedgerBridge.pendingState = nil     -- cached table from deserialize (nil = new/no block)

-- True when the ledger is the load source of truth for this load (present, registered,
-- and it delivered an actual block). When present but empty, NPCFavor imports npc_favor.xml.
function NPCStateLedgerBridge.hasLedgerState()
    return NPCStateLedgerBridge.active
        and NPCStateLedgerBridge.delivered
        and NPCStateLedgerBridge.pendingState ~= nil
end

-- Apply the cached ledger state into the live system. Returns true when a real block was
-- applied. Called from NPCSystem's load flow instead of loadFromXMLFile when present.
function NPCStateLedgerBridge.applyState()
    local sys = g_NPCSystem
    if sys == nil or sys.deserializeState == nil or not NPCStateLedgerBridge.hasLedgerState() then
        return false
    end
    sys:deserializeState(NPCStateLedgerBridge.pendingState)
    return true
end

-- Register with StateLedger if present. Called at loadMission00Finished, after the ledger
-- has published its g_currentMission handle in Mission00.load.
function NPCStateLedgerBridge.register()
    NPCStateLedgerBridge.active       = false
    NPCStateLedgerBridge.delivered    = false
    NPCStateLedgerBridge.pendingState = nil

    local ledger = (g_currentMission ~= nil and g_currentMission.stateLedger) or g_stateLedger
    if ledger == nil then
        print("[NPC Favor] StateLedger not detected; NPC data uses its own npc_favor.xml")
        return
    end
    local sys = g_NPCSystem
    if sys == nil then return end

    local ok, err = pcall(function()
        ledger:registerModule(NPCStateLedgerBridge.MODULE_ID, {
            serialize = function()
                return sys:serializeState()
            end,
            deserialize = function(data)
                NPCStateLedgerBridge.delivered    = true
                NPCStateLedgerBridge.pendingState = data   -- nil on a brand-new save
            end,
        })
        -- Force the idempotent parse so deserialize lands before the mod's first-frame
        -- load; otherwise hook order (loadMission00Finished vs StateLedger's own parse)
        -- would decide whether pendingState is ready in time.
        if ledger.parseFile ~= nil then
            ledger:parseFile()
        end
    end)

    if ok then
        NPCStateLedgerBridge.active = true
        print(string.format("[NPC Favor] Registered with StateLedger as '%s' (npc_favor.xml kept as safety copy)",
            NPCStateLedgerBridge.MODULE_ID))
    else
        print(string.format("[NPC Favor] StateLedger registration failed: %s (falling back to npc_favor.xml)", tostring(err)))
    end
end
