-- ============================================================
-- ContractorModBridge.lua
-- Shows FS25_ContractorMod workers in the NPCFavor roster as
-- display-only worker presences (RSF-F357 section 6).
--
-- A HELPER slot or a displayed name is not a stable worker
-- identity, so a presence carries NO personal state: no trust
-- value (not a fake zero), no favour, gift, tie, history or
-- recovery, and it is never saved. It shows the observed name,
-- location and vehicle under a transient allocator-issued number
-- and an explicit presence kind. Reusing a slot updates the same
-- presence only because it carries nothing personal. The workers'
-- actual employment and bodies remain ContractorMod's.
--
-- Detection:  ContractorMod.workers (class-level static table)
--             FS25 mods are sandboxed so g_contractormod (set via
--             getfenv(0) in ContractorMod's env) is not visible here.
--             ContractorMod.workers is on the Class() registered table
--             and accessible from the shared game environment.
-- Polling:    every 5 s, no event hooks exist in ContractorMod.
--             A readable empty list removes presences; an
--             unreadable list marks last-observed positions
--             unavailable and disables interactions; neither
--             removes any retained historic person record.
-- 3D visuals: ContractorMod already renders workers; no entity
--             spawn, no second body, no AI actor.
-- ============================================================

ContractorModBridge = ContractorModBridge or {}
ContractorModBridge.__index = ContractorModBridge

local LOG_PREFIX = "[NPC Favor][ContractorBridge]"
local SYNC_INTERVAL = 5.0  -- seconds between worker list polls

ContractorModBridge.STATUS_READABLE   = "readable"
ContractorModBridge.STATUS_UNREADABLE = "unreadable"

function ContractorModBridge.new(npcSystem)
    local self = setmetatable({}, ContractorModBridge)
    self.npcSystem  = npcSystem
    self.isActive   = false
    self.syncTimer  = 0
    self.lastStatus = nil
    return self
end

-- Returns (workers, status). "readable" with a list (possibly empty) when the
-- worker source can be read; nil, "unreadable" when it cannot. The two differ
-- on purpose: empty removes presences, unreadable only marks them unavailable.
--
-- Both g_contractormod (instance) and ContractorMod (class) are set inside
-- ContractorMod's sandboxed mod environment and are NOT visible here.
-- For now we build the list from g_npcManager.nameToNPC: ContractorMod
-- registers "HELPER1" to "HELPER8" there (shared game object). Names are
-- "Worker N" until ContractorMod exposes the display names. When
-- g_currentMission.contractorWorkers is available (future), we use that.
function ContractorModBridge:getWorkers()
    -- Future: official bridge via g_currentMission (requested in issue)
    if g_currentMission ~= nil and type(g_currentMission.contractorWorkers) == "table" then
        return g_currentMission.contractorWorkers, ContractorModBridge.STATUS_READABLE
    end
    -- Try direct class access (works if ContractorMod ever shares its env)
    if ContractorMod ~= nil and type(ContractorMod.workers) == "table" then
        return ContractorMod.workers, ContractorModBridge.STATUS_READABLE
    end
    if g_contractormod ~= nil and type(g_contractormod.workers) == "table" then
        return g_contractormod.workers, ContractorModBridge.STATUS_READABLE
    end
    -- Fallback: enumerate g_npcManager HELPER* entries (always shared)
    if g_npcManager == nil or type(g_npcManager.nameToNPC) ~= "table" then
        return nil, ContractorModBridge.STATUS_UNREADABLE
    end
    local workers = {}
    for i = 1, 8 do
        local helperName = "HELPER" .. i
        local npc = g_npcManager.nameToNPC[helperName]
        if npc ~= nil then
            table.insert(workers, {
                name   = "Worker " .. i,
                index  = i,      -- the actual HELPER slot, not a compacted position
                id     = i,
                active = true,
                npc    = npc,    -- g_npcManager NPC object (has position via rootNode)
            })
        end
    end
    return workers, ContractorModBridge.STATUS_READABLE
end

-- Called once the host's people are READY (never before: a presence draws
-- its transient number from the same allocator and the roster must own it).
function ContractorModBridge:initialize()
    -- Check via modManager first (reliable: does not depend on env scoping)
    local modLoaded = g_modManager ~= nil and g_modManager:getModByName("FS25_ContractorMod") ~= nil
    if not modLoaded then return end
    if self.npcSystem == nil or not self.npcSystem.isServer then return end

    self.isActive = true
    print(LOG_PREFIX .. " ContractorMod detected; workers appear as display-only presences")
    self:syncWorkers()
end

-- The actual slot key of a worker entry: its HELPER index, never the position
-- in the enumerated list.
local function slotKeyOf(idx, worker)
    local slot = worker.index or worker.id or idx
    return "HELPER" .. tostring(slot)
end

-- Poll the worker list: upsert presences for the slots seen, remove the ones
-- gone, or mark every presence unavailable when the list cannot be read.
function ContractorModBridge:syncWorkers()
    local people = self.npcSystem and self.npcSystem.people
    if people == nil then return end

    local workers, status = self:getWorkers()
    if status == ContractorModBridge.STATUS_UNREADABLE or workers == nil then
        if self.lastStatus ~= ContractorModBridge.STATUS_UNREADABLE then
            print(LOG_PREFIX .. " worker list unreadable; last observed positions marked unavailable")
        end
        self.lastStatus = ContractorModBridge.STATUS_UNREADABLE
        people:setPresencesUnavailable(true)
        return
    end
    self.lastStatus = ContractorModBridge.STATUS_READABLE
    people:setPresencesUnavailable(false)

    local seen = {}
    for idx, worker in pairs(workers) do
        if type(worker) == "table" and worker.active ~= false and worker.name and worker.name ~= "" then
            local key = slotKeyOf(idx, worker)
            seen[key] = true
            local observed = { name = worker.name, currentVehicle = worker.currentVehicle }
            if worker.x ~= nil then
                observed.x, observed.y, observed.z = worker.x, worker.y, worker.z
            elseif worker.npc ~= nil and worker.npc.rootNode ~= nil then
                local ok, wx, wy, wz = pcall(getWorldTranslation, worker.npc.rootNode)
                if ok and wx then observed.x, observed.y, observed.z = wx, wy, wz end
            end
            local presence = people:upsertPresence(key, observed)
            if presence ~= nil and presence.firstSeenLogged ~= true then
                presence.firstSeenLogged = true
                print(string.format("%s Worker '%s' shown as presence #%d", LOG_PREFIX, worker.name, presence.id))
            end
        end
    end

    -- Presences whose slots are no longer in a readable list are removed.
    local gone = {}
    for _, key in ipairs(people.presenceOrder) do
        if not seen[key] then gone[#gone + 1] = key end
    end
    for _, key in ipairs(gone) do
        people:removePresence(key)
        print(string.format("%s Worker presence removed (%s)", LOG_PREFIX, key))
    end
    if #gone > 0 or next(seen) ~= nil then
        self.npcSystem.syncDirty = true
    end
end

-- Called every frame from NPCSystem:update() (server only, dt in seconds)
function ContractorModBridge:update(dt)
    if not self.isActive then return end

    self.syncTimer = self.syncTimer + dt
    if self.syncTimer >= SYNC_INTERVAL then
        self.syncTimer = 0
        self:syncWorkers()
    end
end

function ContractorModBridge:delete()
    self.isActive   = false
    self.syncTimer  = 0
    self.lastStatus = nil
    if self.npcSystem and self.npcSystem.people and self.npcSystem.people.clearPresences then
        self.npcSystem.people:clearPresences()
    end
end
