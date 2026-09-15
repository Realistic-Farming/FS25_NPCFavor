-- =========================================================
-- FS25 NPC Favor Mod - Favor recovery (RSF-F148)
-- =========================================================
-- Extends NPCFavorSystem with the second lifecycle collection
-- (recoveryFavors), the one-status record contract, the load-once seam,
-- the farm-identity orphaning transition, session selection tokens and the
-- server-validated recovery view and command.
--
-- A favour belongs to the farm that accepted it, and only to that farm.
-- An unanswered request stays unanswered across a reload. A record whose
-- meaning an old save cannot establish is paused, kept, and shown; it is
-- never quietly attached to a farm, and no money moves until a person
-- explicitly resumes it.
--
-- Loaded directly after NPCFavorSystem.lua; every function here is a method
-- on NPCFavorSystem or a helper in the NPCFavorRecovery namespace.
-- =========================================================

NPCFavorRecovery = NPCFavorRecovery or {}

NPCFavorRecovery.SCHEMA = 1
NPCFavorRecovery.STATUS_PAUSED = "paused_recovery"
NPCFavorRecovery.PAGE_SIZE = 20

-- The four persisted recovery reason tokens. Saved ASCII, never UI copy.
NPCFavorRecovery.REASON_LEGACY_ACCEPTANCE_UNKNOWN = "legacy_acceptance_unknown"
NPCFavorRecovery.REASON_OWNER_UNRESOLVED          = "owner_unresolved"
NPCFavorRecovery.REASON_INVALID_RECORD            = "invalid_record"
NPCFavorRecovery.REASON_OWNER_FARM_DELETED        = "owner_farm_deleted"

NPCFavorRecovery.KNOWN_REASONS = {
    legacy_acceptance_unknown = true,
    owner_unresolved = true,
    invalid_record = true,
    owner_farm_deleted = true,
}

-- Only an orphaned row may be assigned to a new farm by a verified host or
-- administrator. Every other reason, and every unknown token, is inspect-only.
NPCFavorRecovery.ASSIGNABLE_REASONS = {
    owner_farm_deleted = true,
}

NPCFavorRecovery.OP_RESUME            = 1
NPCFavorRecovery.OP_ASSIGN_AND_RESUME = 2
NPCFavorRecovery.OP_COMPLETE          = 3
NPCFavorRecovery.OP_ABANDON           = 4
NPCFavorRecovery.OP_MIN = 1
NPCFavorRecovery.OP_MAX = 4

NPCFavorRecovery.RESULT_OK               = 1
NPCFavorRecovery.RESULT_REFUSED          = 2
NPCFavorRecovery.RESULT_NO_LONGER_PAUSED = 3
NPCFavorRecovery.RESULT_UNAVAILABLE      = 4

NPCFavorRecovery.LOAD_WAITING  = "WAITING"
NPCFavorRecovery.LOAD_APPLYING = "APPLYING"
NPCFavorRecovery.LOAD_READY    = "READY"
NPCFavorRecovery.LOAD_FAILED   = "FAILED"

-- Why a load is FAILED. A refused record (unsupported schema) means the
-- delivered table was read in full and only the favor blocks are untrusted;
-- an abort (a throw while loading or applying) means the apply stopped at an
-- unknown point, so nothing reconstructed from the delivery is trusted.
NPCFavorRecovery.FAIL_ORIGIN_RECORD = "record"
NPCFavorRecovery.FAIL_ORIGIN_ABORT  = "abort"

local ACTIVE_STATUS = { active = true, in_progress = true }
local TERMINAL_STATUS = { completed = true, failed = true, abandoned = true }

local function isFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function knownBool(value, present)
    return present == true and type(value) == "boolean"
end

local function removeIdentity(list, record)
    for i, candidate in ipairs(list) do
        if candidate == record then
            table.remove(list, i)
            return true
        end
    end
    return false
end

local function nowMs()
    if TimeHelper ~= nil and TimeHelper.getGameTimeMs ~= nil then
        return TimeHelper.getGameTimeMs()
    end
    return (g_currentMission and g_currentMission.time) or 0
end

-- =========================================================
-- State owned by the favor system
-- =========================================================

function NPCFavorSystem:initRecoveryState()
    self.recoveryFavors = {}
    self._favorLoadState = NPCFavorRecovery.LOAD_WAITING
    self._favorLoadFailOrigin = nil
    self._loadStaging = nil
    self._ledgerOriginalState = nil
    self._nextFavorId = 1
    self._recoveryTokens = { byToken = {}, next = 1 }
    self._recoveryCollectionRevision = 0
    self._recoveryRequests = {}
    self._recoveryRequestOrder = {}
    self._recoveryRequestSeq = 0
    self._recoveryViews = {}
    self._recoveryCounterExhausted = false
end

--- Private monotonic favor id allocator. Initialised above the largest saved
--- id at the selected initial load; never reset by a repeated startup call.
function NPCFavorSystem:allocateFavorId()
    local id = self._nextFavorId or 1
    self._nextFavorId = id + 1
    return id
end

function NPCFavorSystem:noteAssignedFavorId(id)
    if NPCFarmIdentity.isInteger(id) and id >= (self._nextFavorId or 1) then
        self._nextFavorId = id + 1
    end
end

function NPCFavorSystem:getFavorTypeById(typeId)
    if typeId == nil then return nil end
    for _, ft in ipairs(self.favorTypes or {}) do
        if ft.id == typeId then return ft end
    end
    return nil
end

function NPCFavorSystem:getRecoveryFavors()
    return self.recoveryFavors or {}
end

-- =========================================================
-- Record facts
-- =========================================================

--- Type-sensitive required payment facts. A loan needs a known finite
--- positive amount and known booleans for the debit and the repayment; every
--- row needs a known rewardPaid boolean. Presence and value must agree.
function NPCFavorRecovery.paymentFactsKnown(favor)
    if type(favor) ~= "table" then return false end
    if not knownBool(favor.rewardPaid, favor.rewardPaidPresent) then return false end
    if favor.type == "loan_money" then
        if not knownBool(favor.repaymentCollected, favor.repaymentCollectedPresent) then return false end
        local td = favor.taskData or {}
        local amount = td.loanAmount
        if favor.loanAmountPresent ~= true or not isFiniteNumber(amount) or amount <= 0 then
            return false
        end
        if not knownBool(td.loanAmountDeducted, favor.loanAmountDeductedPresent) then return false end
    end
    return true
end

function NPCFavorRecovery.isPaused(favor)
    return type(favor) == "table" and favor.status == NPCFavorRecovery.STATUS_PAUSED
end

--- True when the record's neighbour resolves in the live NPC set (by id, then name).
function NPCFavorSystem:favorNPCExists(favor)
    if type(favor) ~= "table" then return false end
    return self:resolveRestoredNPC({ npcId = favor.npcId, npcName = favor.npcName }) ~= nil
end

--- True when a paused row is structurally actionable: its neighbour and type
--- resolve, its time is known, its required payment facts are complete, and
--- it has a route back (known-owner resume or administrative assignment). The
--- reservation test uses this and never the resumable flag alone.
function NPCFavorSystem:isRecoveryRecordActionable(favor)
    if not NPCFavorRecovery.isPaused(favor) then return false end
    if self:getFavorTypeById(favor.type) == nil then return false end
    if favor.timeRemainingRaw ~= nil or not isFiniteNumber(favor.timeRemaining) then return false end
    if not self:favorNPCExists(favor) then return false end
    if not NPCFavorRecovery.paymentFactsKnown(favor) then return false end
    if NPCFavorRecovery.ASSIGNABLE_REASONS[favor.recoveryReason] == true then
        -- Assignment is only a route back while no valid owner exists.
        return not NPCFarmIdentity.isOrdinaryFarmId(favor.ownerFarmId)
    end
    if favor.resumable == true and NPCFavorRecovery.KNOWN_REASONS[favor.recoveryReason] == true
        and favor.recoveryReason ~= NPCFavorRecovery.REASON_INVALID_RECORD
        and favor.recoveryReason ~= NPCFavorRecovery.REASON_OWNER_UNRESOLVED then
        return true
    end
    return false
end

function NPCFavorSystem:isRecoveryRecordInspectOnly(favor)
    return NPCFavorRecovery.isPaused(favor) and not self:isRecoveryRecordActionable(favor)
end

--- Reason a paused row cannot be acted on, as a localisation key, or nil.
function NPCFavorSystem:getRecoveryUnavailableKey(favor)
    if not NPCFavorRecovery.isPaused(favor) then return nil end
    if self:getFavorTypeById(favor.type) == nil then return "npc_recovery_unavail_type" end
    if favor.timeRemainingRaw ~= nil or not isFiniteNumber(favor.timeRemaining) then return "npc_recovery_unavail_time" end
    if not self:favorNPCExists(favor) then return "npc_recovery_unavail_npc" end
    if not NPCFavorRecovery.paymentFactsKnown(favor) then return "npc_recovery_unavail_facts" end
    if NPCFavorRecovery.KNOWN_REASONS[favor.recoveryReason] ~= true then return "npc_recovery_unavail_reason" end
    if favor.recoveryReason == NPCFavorRecovery.REASON_INVALID_RECORD then return "npc_recovery_unavail_reason" end
    if favor.recoveryReason == NPCFavorRecovery.REASON_OWNER_UNRESOLVED then return "npc_recovery_unavail_owner" end
    if favor.recoveryReason == NPCFavorRecovery.REASON_OWNER_FARM_DELETED then return nil end
    if favor.resumable ~= true then return "npc_recovery_unavail_owner" end
    return nil
end

--- A structurally actionable recovery row reserves its neighbour against all
--- new ordinary generation until it is explicitly resolved.
function NPCFavorSystem:isNPCReservedByRecovery(npcId)
    if npcId == nil then return false end
    for _, favor in ipairs(self.recoveryFavors or {}) do
        if favor.npcId == npcId and self:isRecoveryRecordActionable(favor) then
            return true
        end
    end
    return false
end

--- Rows in recoveryFavors or at paused status are never progressed,
--- completed, failed, abandoned, penalised or paid, regardless of caller.
function NPCFavorSystem:isFavorInRecovery(favor)
    if type(favor) ~= "table" then return false end
    if favor.status == NPCFavorRecovery.STATUS_PAUSED then return true end
    for _, candidate in ipairs(self.recoveryFavors or {}) do
        if candidate == favor then return true end
    end
    return false
end

-- =========================================================
-- Load-once seam
-- =========================================================

function NPCFavorSystem:getFavorLoadState()
    return self._favorLoadState or NPCFavorRecovery.LOAD_WAITING
end

--- FAIL_ORIGIN_RECORD or FAIL_ORIGIN_ABORT while FAILED, nil otherwise.
function NPCFavorSystem:getFavorLoadFailOrigin()
    if self._favorLoadState ~= NPCFavorRecovery.LOAD_FAILED then return nil end
    return self._favorLoadFailOrigin or NPCFavorRecovery.FAIL_ORIGIN_RECORD
end

function NPCFavorSystem:isFavorLoadReady()
    return self._favorLoadState == NPCFavorRecovery.LOAD_READY
end

--- Begin the one initial application. Returns a staging table to restore
--- into, or nil when the selected snapshot is already installed or the
--- load has FAILED: both are terminal for the session, so a second load
--- call (init and onStartMission both reach loadFromXMLFile) can never
--- install a fresh or empty snapshot over an untouched save. Only
--- resetFavorLoadState (a new mission) starts over.
function NPCFavorSystem:beginFavorLoad()
    if self._favorLoadState == NPCFavorRecovery.LOAD_READY
        or self._favorLoadState == NPCFavorRecovery.LOAD_FAILED then
        return nil
    end
    self._favorLoadState = NPCFavorRecovery.LOAD_APPLYING
    self._loadStaging = { active = {}, recovery = {}, maxId = 0, unnumbered = {}, failed = false }
    return self._loadStaging
end

--- Unreadable or unsupported saved data: keep the bytes, install nothing.
--- @param origin  FAIL_ORIGIN_RECORD (default) or FAIL_ORIGIN_ABORT
function NPCFavorSystem:failFavorLoad(reason, origin)
    if origin ~= NPCFavorRecovery.FAIL_ORIGIN_ABORT then
        origin = NPCFavorRecovery.FAIL_ORIGIN_RECORD
    end
    print(string.format("[NPC Favor] Favor load FAILED (%s, %s); saved favors left untouched and not rewritten",
        tostring(reason), origin))
    self._loadStaging = nil
    self._favorLoadState = NPCFavorRecovery.LOAD_FAILED
    self._favorLoadFailOrigin = origin
end

--- Swap the staged collections in once and mark READY.
function NPCFavorSystem:installFavorSnapshot(staging)
    if staging == nil or staging ~= self._loadStaging
        or self._favorLoadState ~= NPCFavorRecovery.LOAD_APPLYING then
        return false
    end
    if staging.failed then
        self:failFavorLoad(staging.failReason or "unsupported record", staging.failOrigin)
        return false
    end

    local nextId = math.max(self._nextFavorId or 1, (staging.maxId or 0) + 1)
    for _, record in ipairs(staging.unnumbered) do
        record.id = nextId
        nextId = nextId + 1
    end
    self._nextFavorId = nextId

    self.activeFavors = staging.active
    self.recoveryFavors = staging.recovery
    self._loadStaging = nil
    self._favorLoadState = NPCFavorRecovery.LOAD_READY
    self:rebuildRecoveryTokens()
    return true
end

--- A new mission with no saved favor data is a valid empty snapshot.
function NPCFavorSystem:installEmptyFavorSnapshot()
    local staging = self:beginFavorLoad()
    if staging ~= nil then
        self:installFavorSnapshot(staging)
    end
end

function NPCFavorSystem:resetFavorLoadState()
    self:initRecoveryState()
end

-- =========================================================
-- Persistence contract: one flat record shape for both writers
-- =========================================================

--- Export a favor as a flat table of primitives. Both the XML writer and the
--- StateLedger writer serialize exactly this table.
function NPCFavorSystem:exportFavorRecord(favor)
    local td = favor.taskData or {}
    local reward = favor.reward
    local flat = {
        f148Schema = NPCFavorRecovery.SCHEMA,
        favorId = favor.id,
        npcId = favor.npcId or 0,
        npcName = favor.npcName or "",
        type = favor.type or "",
        description = favor.description or "",
        status = favor.status or "pending",
        -- An unknown time is written as absent, never as a made-up 0.
        timeRemainingPresent = favor.timeRemainingRaw == nil and isFiniteNumber(favor.timeRemaining),
        timeRemaining = (favor.timeRemainingRaw == nil and isFiniteNumber(favor.timeRemaining)) and favor.timeRemaining or nil,
        progress = favor.progress or 0,
        awaitingConfirmation = favor.awaitingConfirmation == true,

        ownerFarmIdPresent = favor.ownerFarmId ~= nil,
        ownerFarmId = favor.ownerFarmId,
        rewardPaidPresent = type(favor.rewardPaid) == "boolean",
        rewardPaid = favor.rewardPaid,
        repaymentCollectedPresent = type(favor.repaymentCollected) == "boolean",
        repaymentCollected = favor.repaymentCollected,
        loanAmountDeductedPresent = type(td.loanAmountDeducted) == "boolean",
        loanAmountDeducted = td.loanAmountDeducted,
        loanAmountPresent = isFiniteNumber(td.loanAmount),
        loanAmount = td.loanAmount,
        taskFieldIdPresent = td.fieldId ~= nil,
        taskFieldId = td.fieldId,

        rewardRelationship = (type(reward) == "table" and (reward.relationship or 0)) or 0,
        rewardMoney = (type(reward) == "table" and (reward.money or 0)) or (tonumber(reward) or 0),
        rewardXp = (type(reward) == "table" and (reward.xp or 0)) or 0,

        recoveredFromLegacy = favor.recoveredFromLegacy == true,
        recoveryReason = favor.recoveryReason,
        resumable = favor.resumable,
        originalStatus = favor.originalStatus,
        originalOwnerFarmIdPresent = favor.originalOwnerFarmId ~= nil,
        originalOwnerFarmId = favor.originalOwnerFarmId,
    }
    -- Keep raw inspect-only values a legacy row carried but could not use.
    if favor.taskFieldIdRaw ~= nil and td.fieldId == nil then
        flat.taskFieldIdPresent = true
        flat.taskFieldId = favor.taskFieldIdRaw
    end
    return flat
end

--- Usable field id: finite positive integer. Anything else stays unavailable.
function NPCFavorRecovery.decodeFieldId(present, raw)
    if present ~= true then return nil end
    if not NPCFarmIdentity.isInteger(raw) or raw <= 0 then return nil end
    return raw
end

--- Resolve the neighbour for a saved row: by id first, then by name.
function NPCFavorSystem:resolveRestoredNPC(saved)
    local npcs = self.npcSystem and self.npcSystem.activeNPCs
    if not npcs then return nil end
    if saved.npcId ~= nil then
        for _, candidate in ipairs(npcs) do
            if candidate.id == saved.npcId then return candidate end
        end
    end
    if saved.npcName and saved.npcName ~= "" then
        for _, candidate in ipairs(npcs) do
            if candidate.name == saved.npcName then return candidate end
        end
    end
    return nil
end

--- Build the in-memory record from a flat saved row. Presence and value are
--- preserved separately; nothing here decides which collection it enters.
function NPCFavorSystem:buildRestoredRecord(saved, schema)
    local favorType = self:getFavorTypeById(saved.type)
    local npc = self:resolveRestoredNPC(saved)
    local npcResolved = (npc ~= nil)

    -- Regenerate steps once (the save does not persist the step list).
    local steps
    if favorType then
        if not npc then
            print(string.format(
                "[NPC Favor] restoreFavor: NPC id=%s name=%s missing; regenerating steps with fallback",
                tostring(saved.npcId), tostring(saved.npcName)))
            npc = { id = saved.npcId or 0, name = saved.npcName or "", homePosition = nil, assignedField = nil }
        end
        steps = self:generateFavorSteps(favorType, npc)
    else
        print(string.format("[NPC Favor] restoreFavor: unknown favor type '%s'; record kept for inspection",
            tostring(saved.type)))
        steps = {{id = 1, description = "Complete the task", completed = false, location = nil}}
    end

    local n = #steps
    local savedProgress = tonumber(saved.progress) or 0
    if n > 0 then
        local done = math.floor((savedProgress / 100) * n + 0.5)
        if done < 0 then done = 0 elseif done > n then done = n end
        for i = 1, done do steps[i].completed = true end
    end
    local currentStep = 1
    if n > 0 then
        currentStep = steps[n].id or n
        for i, step in ipairs(steps) do
            if not step.completed then
                currentStep = step.id or i
                break
            end
        end
    end

    local legacy = (schema == nil)
    local function presentFlag(flagName, valueName)
        if legacy then
            return saved[flagName] == true or (saved[flagName] == nil and saved[valueName] ~= nil)
        end
        return saved[flagName] == true
    end

    local ownerPresent = presentFlag("ownerFarmIdPresent", "ownerFarmId")
    local rewardPaidPresent = presentFlag("rewardPaidPresent", "rewardPaid")
    local repaymentPresent = presentFlag("repaymentCollectedPresent", "repaymentCollected")
    local deductedPresent = presentFlag("loanAmountDeductedPresent", "loanAmountDeducted")
    local loanAmountPresent = presentFlag("loanAmountPresent", "loanAmount")
    local fieldPresent = presentFlag("taskFieldIdPresent", "taskFieldId")

    local timePresent = presentFlag("timeRemainingPresent", "timeRemaining")
    local timeRemaining = timePresent and saved.timeRemaining or nil
    local fieldId = NPCFavorRecovery.decodeFieldId(fieldPresent, saved.taskFieldId)

    -- Known booleans are copied with explicit ifs: the `cond and value or nil`
    -- idiom turns a known false into nil, which is exactly the false/unknown
    -- confusion this record contract exists to prevent.
    local function knownBoolValue(present, value)
        if present and type(value) == "boolean" then
            return value, true
        end
        return nil, false
    end
    local rewardPaidValue, rewardPaidKnown = knownBoolValue(rewardPaidPresent, saved.rewardPaid)
    local repaymentValue, repaymentKnown = knownBoolValue(repaymentPresent, saved.repaymentCollected)
    local deductedValue, deductedKnown = knownBoolValue(deductedPresent, saved.loanAmountDeducted)
    local loanAmountValue = nil
    if loanAmountPresent and isFiniteNumber(saved.loanAmount) then
        loanAmountValue = saved.loanAmount
    end

    local reward
    if favorType then
        reward = favorType.reward
    elseif type(saved.reward) == "table" then
        reward = saved.reward
    else
        reward = {
            relationship = tonumber(saved.rewardRelationship) or 0,
            money = tonumber(saved.rewardMoney) or tonumber(saved.reward) or 0,
            xp = tonumber(saved.rewardXp) or 0,
        }
    end

    local record = {
        id = nil,
        npcId = saved.npcId or 0,
        npcName = saved.npcName or "",
        type = saved.type,
        name = favorType and favorType.name or saved.type,
        description = saved.description or (favorType and favorType.description or ""),
        difficulty = favorType and favorType.difficulty or 1,
        category = favorType and favorType.category or "misc",

        status = "pending",
        progress = savedProgress,
        progressDetails = {},

        createdTime = nowMs(),
        expirationGameTime = nil,
        timeRemaining = isFiniteNumber(timeRemaining) and timeRemaining or 0,
        timeRemainingRaw = (not isFiniteNumber(timeRemaining)) and tostring(saved.timeRemaining) or nil,
        npcResolved = npcResolved,
        estimatedCompletionTime = nil,

        requirements = favorType and favorType.requirements or {},
        reward = reward,
        penalty = favorType and favorType.penalty or { relationship = -5, reputation = -10 },

        location = nil,
        taskData = {
            loanAmount = loanAmountValue,
            loanAmountDeducted = deductedValue,
            fieldId = fieldId,
        },
        taskFieldIdRaw = (fieldPresent and fieldId == nil) and saved.taskFieldId or nil,

        ownerFarmId = ownerPresent and saved.ownerFarmId or nil,
        ownerFarmIdPresent = ownerPresent and saved.ownerFarmId ~= nil,
        rewardPaid = rewardPaidValue,
        rewardPaidPresent = rewardPaidKnown,
        repaymentCollected = repaymentValue,
        repaymentCollectedPresent = repaymentKnown,
        loanAmountDeductedPresent = deductedKnown,
        loanAmountPresent = loanAmountValue ~= nil,
        awaitingConfirmation = saved.awaitingConfirmation == true,

        recoveredFromLegacy = saved.recoveredFromLegacy == true,
        recoveryReason = nil,
        resumable = nil,
        originalStatus = nil,
        originalOwnerFarmId = nil,
        recordRevision = 0,

        startTime = nil,
        completionTime = nil,
        completionDuration = nil,
        playerNotes = "",
        priority = 1,
        currentStep = currentStep,
        totalSteps = n > 0 and n or 1,
        steps = steps,
        f148Schema = NPCFavorRecovery.SCHEMA,
    }
    return record
end

--- Decide the collection for a restored record. Returns "active" or "recovery".
function NPCFavorSystem:classifyRestoredRecord(record, saved, schema)
    local typeKnown = self:getFavorTypeById(record.type) ~= nil
    local timeOk = record.timeRemainingRaw == nil
    local ownerOrdinary = record.ownerFarmIdPresent and NPCFarmIdentity.isOrdinaryFarmId(record.ownerFarmId)

    local function pause(reason, resumable)
        record.status = NPCFavorRecovery.STATUS_PAUSED
        record.recoveryReason = reason
        record.resumable = (resumable == true)
        record.expirationGameTime = nil
        return "recovery"
    end

    -- A saved paused row keeps its saved reason and original fields exactly.
    -- Type, time or neighbour trouble only makes it inspect-only at read time
    -- (isRecoveryRecordActionable); nothing is normalized on load.
    if schema ~= nil and saved.status == NPCFavorRecovery.STATUS_PAUSED then
        local reason = saved.recoveryReason
        if type(reason) ~= "string" or reason == "" then
            reason = NPCFavorRecovery.REASON_INVALID_RECORD
        end
        record.status = NPCFavorRecovery.STATUS_PAUSED
        record.recoveryReason = reason   -- unknown tokens round-trip unchanged
        record.resumable = (saved.resumable == true)
        if saved.originalStatus == "active" or saved.originalStatus == "in_progress" then
            record.originalStatus = saved.originalStatus
        end
        if saved.originalOwnerFarmIdPresent == true then
            record.originalOwnerFarmId = saved.originalOwnerFarmId
        end
        record.expirationGameTime = nil
        if reason ~= NPCFavorRecovery.REASON_LEGACY_ACCEPTANCE_UNKNOWN or not ownerOrdinary then
            -- resumable is the known-owner gate and nothing else.
            record.resumable = false
        end
        return "recovery"
    end

    if not typeKnown or not timeOk then
        return pause(NPCFavorRecovery.REASON_INVALID_RECORD, false)
    end

    if schema == nil then
        -- Legacy row: status was never saved, so acceptance cannot be proven.
        -- A present ordinary owner may resume explicitly; anything else waits
        -- for inspection. Owner presence alone never proves acceptance.
        if ownerOrdinary then
            return pause(NPCFavorRecovery.REASON_LEGACY_ACCEPTANCE_UNKNOWN, true)
        end
        return pause(NPCFavorRecovery.REASON_OWNER_UNRESOLVED, false)
    end

    local st = saved.status
    if st == "pending" then
        local td = record.taskData or {}
        if record.ownerFarmIdPresent or saved.ownerFarmIdPresent == true
            or record.rewardPaid == true or record.repaymentCollected == true
            or td.loanAmountDeducted == true or (record.progress or 0) > 0 or record.awaitingConfirmation then
            return pause(NPCFavorRecovery.REASON_INVALID_RECORD, false)
        end
        record.status = "pending"
        record.ownerFarmId = nil
        record.expirationGameTime = record.createdTime + record.timeRemaining
        return "active"
    end

    if ACTIVE_STATUS[st] then
        if not ownerOrdinary then
            record.originalStatus = st
            record.originalOwnerFarmId = record.ownerFarmId
            return pause(NPCFavorRecovery.REASON_OWNER_UNRESOLVED, false)
        end
        record.status = st
        record.startTime = record.createdTime
        record.expirationGameTime = record.createdTime + record.timeRemaining
        return "active"
    end

    -- Terminal or unknown status in a saved row: inspect-only, never promoted.
    return pause(NPCFavorRecovery.REASON_INVALID_RECORD, false)
end

--- Restore one saved favor row. With a staging table (the initial load) the
--- record is placed in staging; without one it enters the live collections
--- directly. Returns the record and its collection name, or nil plus a reason.
function NPCFavorSystem:restoreFavor(saved, staging)
    if type(saved) ~= "table" then
        return nil, "empty"
    end
    -- A row with no usable type is still evidence: it is kept as an
    -- invalid_record rather than dropped and lost at the next save. The
    -- delivered row is never mutated (the ledger copies it back on a FAILED
    -- load), so the repair goes on a shallow copy.
    if type(saved.type) ~= "string" then
        local copy = {}
        for k, v in pairs(saved) do copy[k] = v end
        copy.type = ""
        saved = copy
    end

    local schema = saved.f148Schema
    if schema ~= nil and (not NPCFarmIdentity.isInteger(schema) or schema ~= NPCFavorRecovery.SCHEMA) then
        if staging ~= nil then
            staging.failed = true
            staging.failReason = "unsupported favor schema " .. tostring(schema)
        end
        print(string.format("[NPC Favor] restoreFavor: unsupported favor schema %s; refusing load", tostring(schema)))
        return nil, "unsupported_schema"
    end

    local record = self:buildRestoredRecord(saved, schema)
    local collection = self:classifyRestoredRecord(record, saved, schema)

    local savedId = saved.favorId
    if NPCFarmIdentity.isInteger(savedId) and savedId > 0 then
        record.id = savedId
    end

    if staging ~= nil then
        staging.seenIds = staging.seenIds or {}
        if record.id ~= nil and staging.seenIds[record.id] then
            -- Duplicate saved id: the second row gets a fresh id at install.
            record.id = nil
        end
        if record.id ~= nil then
            staging.seenIds[record.id] = true
            if record.id > (staging.maxId or 0) then staging.maxId = record.id end
        else
            staging.unnumbered[#staging.unnumbered + 1] = record
        end
        table.insert(staging[collection], record)
    else
        -- Direct (non-staged) restore, used by the offline bench. It honours the
        -- same classification; schema failure returned above.
        if record.id ~= nil then
            self:noteAssignedFavorId(record.id)
        else
            record.id = self:allocateFavorId()
        end
        if collection == "active" then
            table.insert(self.activeFavors, record)
        else
            table.insert(self.recoveryFavors, record)
            self:assignRecoveryToken(record)
        end
        if record.recoveredFromLegacy and collection == "active" then
            self:assignRecoveryToken(record)
        end
    end
    return record, collection
end

-- =========================================================
-- Farm identity: orphaning on the engine's farm lifecycle messages
-- =========================================================

--- The orphaning transition. One state change: sentinel owner, paused status,
--- owner_farm_deleted reason, not resumable by the known-owner route, moved out
--- of the live list. Money and clock paths key on those facts.
function NPCFavorSystem:orphanFavorRecord(favor)
    local wasActive = removeIdentity(self.activeFavors, favor)
    local wasLive = wasActive or ACTIVE_STATUS[favor.status] == true
    if wasLive then
        favor.originalStatus = ACTIVE_STATUS[favor.status] and favor.status or favor.originalStatus
        if favor.expirationGameTime ~= nil then
            favor.timeRemaining = favor.expirationGameTime - nowMs()
        end
    end
    -- The first orphaning records the owner; a later notice for a row that
    -- already remembers one keeps the earlier fact.
    if favor.originalOwnerFarmId == nil then
        favor.originalOwnerFarmId = favor.ownerFarmId
    end
    favor.ownerFarmId = NPCFarmIdentity.invalidFarmId()
    favor.ownerFarmIdPresent = true
    favor.status = NPCFavorRecovery.STATUS_PAUSED
    -- The owner_farm_deleted reason (and with it assignability) applies only
    -- to a job that was live or whose only doubt was legacy acceptance. Every
    -- other paused row keeps its own reason, including an unknown token, so
    -- deleting a farm never promotes an inspect-only record.
    if wasLive or favor.recoveryReason == NPCFavorRecovery.REASON_LEGACY_ACCEPTANCE_UNKNOWN then
        favor.recoveryReason = NPCFavorRecovery.REASON_OWNER_FARM_DELETED
    end
    favor.resumable = false
    favor.expirationGameTime = nil
    favor.recoveredFromLegacy = false
    self:bumpRecordRevision(favor)
    local inRecovery = false
    for _, candidate in ipairs(self.recoveryFavors) do
        if candidate == favor then inRecovery = true break end
    end
    if not inRecovery then
        table.insert(self.recoveryFavors, favor)
    end
    self:assignRecoveryToken(favor)
    if self.npcSystem then self.npcSystem.syncDirty = true end
end

local function orphanRowsOwnedBy(self, farmId)
    local touched = 0
    local lists = { self.activeFavors, self.recoveryFavors }
    for _, list in ipairs(lists) do
        for i = #list, 1, -1 do
            local favor = list[i]
            if favor.ownerFarmId == farmId then
                self:orphanFavorRecord(favor)
                touched = touched + 1
            end
        end
    end
    if touched > 0 then
        print(string.format("[NPC Favor] Farm %d lifecycle: %d accepted favor(s) moved to recovery (owner_farm_deleted)",
            farmId, touched))
    end
    return touched
end

--- FARM_DELETED. If a live farm still holds the number the notice is stale
--- and nothing happens; that is what protects a new farm's new job from an
--- old notification. Idempotent by construction.
function NPCFavorSystem:onFarmDeleted(farmId)
    if not NPCFarmIdentity.isOrdinaryFarmIdShape(farmId) then return 0 end
    if NPCFarmIdentity.getLiveFarm(farmId) ~= nil then return 0 end
    return orphanRowsOwnedBy(self, farmId)
end

--- FARM_CREATED (server only, gated by the caller). No staleness check: any
--- accepted job already carrying this number predates the farm, because the
--- farm did not exist to accept anything.
function NPCFavorSystem:onFarmCreated(farmId)
    if not NPCFarmIdentity.isOrdinaryFarmIdShape(farmId) then return 0 end
    return orphanRowsOwnedBy(self, farmId)
end

--- USER_REMOVED: drop the retained requests and view of the departed actor.
function NPCFavorSystem:onActorDisconnected(connectionId)
    if connectionId == nil then return end
    self._recoveryViews[connectionId] = nil
    local prefix = connectionId .. ":"
    for key in pairs(self._recoveryRequests) do
        if key:sub(1, #prefix) == prefix then
            self._recoveryRequests[key] = nil
        end
    end
end

-- =========================================================
-- Session selection tokens
-- =========================================================

function NPCFavorSystem:bumpRecordRevision(favor)
    favor.recordRevision = (favor.recordRevision or 0) + 1
end

function NPCFavorSystem:assignRecoveryToken(favor)
    local tokens = self._recoveryTokens
    if favor.recoveryToken ~= nil and tokens.byToken[favor.recoveryToken] == favor then
        return favor.recoveryToken
    end
    local t = tokens.next
    if t >= NPCFarmIdentity.WIRE_MAX then
        self._recoveryCounterExhausted = true
        return nil
    end
    tokens.next = t + 1
    tokens.byToken[t] = favor
    favor.recoveryToken = t
    return t
end

function NPCFavorSystem:retireRecoveryToken(favor)
    if favor.recoveryToken ~= nil and self._recoveryTokens.byToken[favor.recoveryToken] == favor then
        self._recoveryTokens.byToken[favor.recoveryToken] = nil
    end
end

--- Rebuild after the authoritative collection is loaded or replaced. The
--- ordinal keeps climbing so a retired token is never reused in a session.
function NPCFavorSystem:rebuildRecoveryTokens()
    local nextOrdinal = (self._recoveryTokens and self._recoveryTokens.next) or 1
    self._recoveryTokens = { byToken = {}, next = nextOrdinal }
    for _, favor in ipairs(self.recoveryFavors or {}) do
        favor.recoveryToken = nil
        self:assignRecoveryToken(favor)
    end
    for _, favor in ipairs(self.activeFavors or {}) do
        if favor.recoveredFromLegacy then
            favor.recoveryToken = nil
            self:assignRecoveryToken(favor)
        end
    end
    self._recoveryCollectionRevision = (self._recoveryCollectionRevision or 0) + 1
    self._recoveryRequests = {}
    self._recoveryRequestOrder = {}
    self._recoveryViews = {}
end

function NPCFavorSystem:getRecoveryRecordByToken(tokenNumber)
    if tokenNumber == nil then return nil end
    return self._recoveryTokens.byToken[tokenNumber]
end

-- =========================================================
-- Resume
-- =========================================================

--- Move a paused record back to the live list once. No money moves here.
function NPCFavorSystem:resumeRecoveryRecord(favor, targetFarmId)
    if not removeIdentity(self.recoveryFavors, favor) then
        return false
    end
    local now = nowMs()
    favor.status = (favor.originalStatus == "in_progress") and "in_progress" or "active"
    favor.ownerFarmId = targetFarmId
    favor.ownerFarmIdPresent = true
    favor.recoveredFromLegacy = true
    favor.recoveryReason = nil
    favor.resumable = nil
    favor.originalStatus = nil
    favor.originalOwnerFarmId = nil
    favor.startTime = now
    favor.createdTime = favor.createdTime or now
    favor.expirationGameTime = now + (isFiniteNumber(favor.timeRemaining) and favor.timeRemaining or 0)
    self:bumpRecordRevision(favor)
    table.insert(self.activeFavors, favor)
    self:assignRecoveryToken(favor)
    return true
end

-- =========================================================
-- Eligible farms for administrative assignment
-- =========================================================

function NPCFavorSystem:getEligibleFarms()
    local list, byId = {}, {}
    if g_farmManager ~= nil and type(g_farmManager.getFarms) == "function" then
        for _, farm in ipairs(g_farmManager:getFarms() or {}) do
            local id = farm.farmId
            if type(farm.getId) == "function" then
                id = farm:getId()
            end
            if NPCFarmIdentity.isOrdinaryFarmId(id)
                and g_farmManager:getFarmById(id) == farm
                and farm.isSpectator ~= true
                and farm.showInFarmScreen ~= false then
                list[#list + 1] = { farmId = id, name = tostring(farm.name or "") }
                byId[id] = farm
            end
        end
    end
    table.sort(list, function(a, b) return a.farmId < b.farmId end)
    return list, byId
end

-- =========================================================
-- Server-validated recovery view
-- =========================================================

local function rowVisibleTo(favor, actor)
    if actor.isMaster then return true end
    if actor.farmId == nil then return false end
    return favor.ownerFarmId == actor.farmId and NPCFarmIdentity.isOrdinaryFarmId(favor.ownerFarmId)
end

function NPCFavorSystem:collectRecoveryRows(actor)
    local rows = {}
    for _, favor in ipairs(self.recoveryFavors or {}) do
        if favor.recoveryToken ~= nil and rowVisibleTo(favor, actor) then
            rows[#rows + 1] = favor
        end
    end
    for _, favor in ipairs(self.activeFavors or {}) do
        if favor.recoveredFromLegacy and favor.recoveryToken ~= nil and rowVisibleTo(favor, actor) then
            rows[#rows + 1] = favor
        end
    end
    table.sort(rows, function(a, b) return a.recoveryToken < b.recoveryToken end)
    return rows
end

local function triBool(value, present)
    if present ~= true or type(value) ~= "boolean" then return 2 end
    return value and 1 or 0
end

--- Authoritative description of one row for the private view.
function NPCFavorSystem:describeRecoveryRow(favor)
    local td = favor.taskData or {}
    local paused = NPCFavorRecovery.isPaused(favor)
    local ownerOrdinary = NPCFarmIdentity.isOrdinaryFarmId(favor.ownerFarmId)
    local actionable = self:isRecoveryRecordActionable(favor)
    local liveRecovered = favor.recoveredFromLegacy == true and ACTIVE_STATUS[favor.status] == true
    return {
        token = NPCFarmIdentity.encodeWireNumber(favor.recoveryToken) or "",
        recordRevision = NPCFarmIdentity.encodeWireNumber(favor.recordRevision or 0) or "0",
        npcId = favor.npcId or 0,
        npcName = favor.npcName or "",
        type = favor.type or "",
        description = favor.description or "",
        status = favor.status or "",
        progress = favor.progress or 0,
        timeRemaining = isFiniteNumber(favor.timeRemaining) and favor.timeRemaining or 0,
        timeKnown = favor.timeRemainingRaw == nil,
        ownerFarmId = favor.ownerFarmId or -1,
        ownerKnown = ownerOrdinary,
        recoveryReason = favor.recoveryReason or "",
        resumable = favor.resumable == true,
        knownOwnerResumable = paused and actionable and favor.resumable == true and ownerOrdinary,
        assignable = paused and actionable and NPCFavorRecovery.ASSIGNABLE_REASONS[favor.recoveryReason] == true
            and not ownerOrdinary,
        inspectOnly = paused and not actionable,
        unavailableKey = self:getRecoveryUnavailableKey(favor) or "",
        loanAmount = (favor.loanAmountPresent and isFiniteNumber(td.loanAmount)) and td.loanAmount or -1,
        loanAmountDeducted = triBool(td.loanAmountDeducted, favor.loanAmountDeductedPresent),
        rewardPaid = triBool(favor.rewardPaid, favor.rewardPaidPresent),
        repaymentCollected = triBool(favor.repaymentCollected, favor.repaymentCollectedPresent),
        fieldKnown = td.fieldId ~= nil,
        recoveredFromLegacy = favor.recoveredFromLegacy == true,
        canComplete = liveRecovered,
        canAbandon = liveRecovered,
    }
end

--- Build the page reply for a verified actor. Never broadcast.
--- @return table|nil reply
function NPCFavorSystem:serverRecoveryView(actor, requestId, cursor)
    if actor == nil or not NPCFarmIdentity.validWireNumber(requestId) then
        return nil
    end
    cursor = cursor or ""
    if cursor ~= "" and not NPCFarmIdentity.validToken(cursor) then
        return nil
    end
    local reply = {
        requestId = requestId,
        collectionRevision = NPCFarmIdentity.encodeWireNumber(self._recoveryCollectionRevision or 0) or "0",
        nextCursor = "",
        unavailable = false,
        rows = {},
        eligibleFarms = {},
        totalRows = 0,
    }
    if not self:isFavorLoadReady() or self._recoveryCounterExhausted then
        reply.unavailable = true
        return reply
    end

    local after = (cursor ~= "") and tonumber(cursor) or 0
    local rows = self:collectRecoveryRows(actor)
    reply.totalRows = #rows
    local count = 0
    for _, favor in ipairs(rows) do
        if favor.recoveryToken > after then
            if count >= NPCFavorRecovery.PAGE_SIZE then
                reply.nextCursor = reply.rows[#reply.rows].token
                break
            end
            reply.rows[#reply.rows + 1] = self:describeRecoveryRow(favor)
            count = count + 1
        end
    end

    local viewFarms = {}
    if actor.isMaster then
        local list, byId = self:getEligibleFarms()
        reply.eligibleFarms = list
        viewFarms = byId
    end
    self._recoveryViews[actor.connectionId] = {
        requestId = requestId,
        eligibleFarms = viewFarms,
        isMaster = actor.isMaster,
    }
    return reply
end

-- =========================================================
-- Server-validated recovery command
-- =========================================================

local function hasLiveJobForNPC(self, npcId)
    for _, live in ipairs(self.activeFavors or {}) do
        if live.npcId == npcId then return true end
    end
    return false
end

--- Apply one confirmed command for a verified actor.
--- cmd = { requestId, collectionRevision, recordRevision, token, op,
---         targetFarmId (number or nil), originatingViewRequestId }
--- @return table|nil reply { requestId, op, result, messageKey }
function NPCFavorSystem:serverRecoveryCommand(actor, cmd)
    if actor == nil or type(cmd) ~= "table" then return nil end
    local op = cmd.op
    local function reply(result, key)
        return { requestId = cmd.requestId, op = op or 0, result = result, messageKey = key or "" }
    end
    if not NPCFarmIdentity.validWireNumber(cmd.requestId) then return nil end
    if not NPCFarmIdentity.isInteger(op) or op < NPCFavorRecovery.OP_MIN or op > NPCFavorRecovery.OP_MAX then
        return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_operation")
    end
    if not self:isFavorLoadReady() or self._recoveryCounterExhausted then
        return reply(NPCFavorRecovery.RESULT_UNAVAILABLE, "npc_recovery_unavailable")
    end
    if not NPCFarmIdentity.validWireNumber(cmd.collectionRevision)
        or not NPCFarmIdentity.validWireNumber(cmd.recordRevision)
        or not NPCFarmIdentity.validToken(cmd.token) then
        return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_stale")
    end
    local targetFarmId = cmd.targetFarmId
    if targetFarmId ~= nil and not NPCFarmIdentity.isOrdinaryFarmId(targetFarmId) then
        return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_target")
    end

    -- Retained result: same connection, same request id and identical payload
    -- returns the retained result, but only after the actor's current rights
    -- are re-resolved and still match the rights the result was earned with;
    -- changed rights fall through to a fresh validation. A different payload
    -- under the same id is refused.
    local requestKey = actor.connectionId .. ":" .. cmd.requestId
    local fingerprint = table.concat({
        cmd.token, cmd.collectionRevision, cmd.recordRevision, tostring(op),
        tostring(targetFarmId or ""), tostring(cmd.originatingViewRequestId or ""),
    }, "|")
    local rights = tostring(actor.farmId or "nil") .. "|" .. (actor.isMaster and "ADMIN" or "MEMBER")
    local prior = self._recoveryRequests[requestKey]
    if prior ~= nil then
        if prior.fingerprint ~= fingerprint then
            return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_request_reuse")
        end
        if prior.rights == rights then
            return { requestId = cmd.requestId, op = op, result = prior.result, messageKey = prior.messageKey or "" }
        end
        self._recoveryRequests[requestKey] = nil
    end

    if tonumber(cmd.collectionRevision) ~= (self._recoveryCollectionRevision or 0) then
        return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_stale")
    end
    local record = self:getRecoveryRecordByToken(tonumber(cmd.token))
    if record == nil then
        return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_stale")
    end
    if tonumber(cmd.recordRevision) ~= (record.recordRevision or 0) then
        return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_stale")
    end

    local result, key

    if op == NPCFavorRecovery.OP_RESUME or op == NPCFavorRecovery.OP_ASSIGN_AND_RESUME then
        local inRecovery = false
        for _, candidate in ipairs(self.recoveryFavors) do
            if candidate == record then inRecovery = true break end
        end
        if not inRecovery or not NPCFavorRecovery.isPaused(record) then
            return reply(NPCFavorRecovery.RESULT_NO_LONGER_PAUSED, "npc_recovery_no_longer_paused")
        end
        if self:getFavorTypeById(record.type) == nil then
            return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_unavail_type")
        end
        if record.timeRemainingRaw ~= nil or not isFiniteNumber(record.timeRemaining) then
            return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_unavail_time")
        end
        if not self:favorNPCExists(record) then
            return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_unavail_npc")
        end
        if not NPCFavorRecovery.paymentFactsKnown(record) then
            return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_unavail_facts")
        end

        local target
        if op == NPCFavorRecovery.OP_RESUME then
            -- Known-owner route: the one thing resumable gates.
            if record.resumable ~= true then
                return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_not_resumable")
            end
            if not NPCFarmIdentity.isOrdinaryFarmId(record.ownerFarmId) then
                return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_unavail_owner")
            end
            if actor.farmId == nil or actor.farmId ~= record.ownerFarmId then
                return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_not_owner")
            end
            target = record.ownerFarmId
        else
            -- Administrative assignment never reads resumable. It needs a
            -- verified host/admin, the owner_farm_deleted reason, no valid
            -- existing owner, and an explicit revalidated target from the
            -- originating view.
            if not actor.isMaster then
                return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_not_admin")
            end
            if NPCFavorRecovery.ASSIGNABLE_REASONS[record.recoveryReason] ~= true then
                return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_not_assignable")
            end
            if NPCFarmIdentity.isOrdinaryFarmId(record.ownerFarmId) then
                return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_owner_valid")
            end
            if targetFarmId == nil then
                return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_target")
            end
            local view = self._recoveryViews[actor.connectionId]
            if view == nil or view.requestId ~= cmd.originatingViewRequestId or not view.isMaster then
                return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_view")
            end
            local listed = view.eligibleFarms[targetFarmId]
            if listed == nil or NPCFarmIdentity.getLiveFarm(targetFarmId) ~= listed then
                return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_target")
            end
            target = targetFarmId
        end

        if hasLiveJobForNPC(self, record.npcId) then
            return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_live_job")
        end
        if not self:resumeRecoveryRecord(record, target) then
            return reply(NPCFavorRecovery.RESULT_NO_LONGER_PAUSED, "npc_recovery_no_longer_paused")
        end
        result, key = NPCFavorRecovery.RESULT_OK, "npc_recovery_ok_resumed"
        if self.npcSystem then self.npcSystem.syncDirty = true end

    else
        -- COMPLETE / ABANDON on a live recoveredFromLegacy row, exact owner.
        local inActive = false
        for _, candidate in ipairs(self.activeFavors) do
            if candidate == record then inActive = true break end
        end
        if not inActive or record.recoveredFromLegacy ~= true or not ACTIVE_STATUS[record.status] then
            return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_not_live")
        end
        if not NPCFarmIdentity.isOrdinaryFarmId(record.ownerFarmId)
            or actor.farmId == nil or actor.farmId ~= record.ownerFarmId then
            return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_not_owner")
        end
        local ok
        if op == NPCFavorRecovery.OP_COMPLETE then
            ok = self:completeFavor(record.id)
            key = "npc_recovery_ok_completed"
        else
            ok = self:abandonFavor(record.id)
            key = "npc_recovery_ok_abandoned"
        end
        if not ok then
            return reply(NPCFavorRecovery.RESULT_REFUSED, "npc_recovery_refused_not_live")
        end
        self:bumpRecordRevision(record)
        self:retireRecoveryToken(record)
        result = NPCFavorRecovery.RESULT_OK
        if self.npcSystem then self.npcSystem.syncDirty = true end
    end

    self:retainRecoveryRequest(requestKey, { fingerprint = fingerprint, rights = rights, result = result, messageKey = key })
    return reply(result, key)
end

--- Retain a successful command result, capped so the table cannot grow
--- without bound in a long session (oldest entries are evicted first).
NPCFavorRecovery.MAX_RETAINED_REQUESTS = 256
function NPCFavorSystem:retainRecoveryRequest(requestKey, entry)
    self._recoveryRequestOrder = self._recoveryRequestOrder or {}
    local order = self._recoveryRequestOrder
    entry.seq = (self._recoveryRequestSeq or 0) + 1
    self._recoveryRequestSeq = entry.seq
    -- Re-retaining a key (a fresh validation under the same request id)
    -- moves it to the newest position instead of leaving a stale duplicate
    -- whose eviction would drop the live entry early.
    if self._recoveryRequests[requestKey] ~= nil then
        for i = #order, 1, -1 do
            if order[i] == requestKey then table.remove(order, i) end
        end
    end
    self._recoveryRequests[requestKey] = entry
    order[#order + 1] = requestKey
    while #order > NPCFavorRecovery.MAX_RETAINED_REQUESTS do
        local oldest = table.remove(order, 1)
        if self._recoveryRequests[oldest] ~= nil then
            self._recoveryRequests[oldest] = nil
        end
    end
end

print("[NPC Favor] NPCFavorRecovery loaded")
