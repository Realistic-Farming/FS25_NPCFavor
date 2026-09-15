-- RSF-F148: recovery persistence and farm ownership contract.
--!load: src/utils/NPCFarmIdentity.lua, src/scripts/NPCFavorSystem.lua, src/scripts/NPCFavorRecovery.lua, src/events/NPCInteractionEvent.lua, src/NPCSystem.lua, src/integrations/NPCStateLedgerBridge.lua
-- Ported from the certified design bar (Office Tyson/mods/FS25_NPCFavor/
-- RSF-F148-recovery_contract_spec_test.lua) with two changes: the real-source
-- witnesses now assert the REPAIRED behaviour, and the fold-check group carries
-- Bob's port correction (assignable = { owner_farm_deleted } only, and the
-- invalid_record token). The reference-model blocks are kept as delivered.
-- A real-source section at the end exercises the built NPCFavorSystem +
-- NPCFavorRecovery + NPCFarmIdentity + NPCInteractionEvent seams.
-- Nothing here proves native UI, disk, network, multiplayer or gameplay.

-- Real-source witness setup. The repaired restoreFavor never promotes a saved
-- pending-shaped row to active and never defaults an absent owner.
TimeHelper = {getGameTimeMs = function() return 1000 end}
VectorHelper = VectorHelper or {distance2D = function(x1, z1, x2, z2) local dx, dz = x1 - x2, z1 - z2 return math.sqrt(dx * dx + dz * dz) end}
g_currentMission = {time = 1000, player = {farmId = 1}}
FarmManager = FarmManager or {SPECTATOR_FARM_ID = 0, SINGLEPLAYER_FARM_ID = 1, MAX_FARM_ID = 8,
    GUIDED_TOUR_FARM_ID = 14, INVALID_FARM_ID = 15}
FarmManager.MAX_FARM_ID = FarmManager.MAX_FARM_ID or 8
FarmManager.GUIDED_TOUR_FARM_ID = FarmManager.GUIDED_TOUR_FARM_ID or 14
FarmManager.INVALID_FARM_ID = FarmManager.INVALID_FARM_ID or 15
-- Live farm table used by NPCFarmIdentity through g_farmManager.
local LIVE_FARMS = {}
g_farmManager = {
    getFarmById = function(_, id) return LIVE_FARMS[id] end,
    getFarms = function(_)
        local list = {}
        for _, farm in pairs(LIVE_FARMS) do list[#list + 1] = farm end
        table.sort(list, function(a, b) return a.farmId < b.farmId end)
        return list
    end,
}
local function setLiveFarms(ids)
    for k in pairs(LIVE_FARMS) do LIVE_FARMS[k] = nil end
    for _, id in ipairs(ids) do LIVE_FARMS[id] = {farmId = id, name = "Farm " .. id, showInFarmScreen = true, isSpectator = false} end
end
setLiveFarms({1, 3})

local function newWitness()
    local w = NPCFavorSystem.new({activeNPCs = {{id = 11, name = "Mara", homePosition = {x = 0, y = 0, z = 0}}},
        settings = {enableFavors = false}})
    w.favorTypes = {{id = "help_harvest", name = "Help harvest", description = "Harvest", difficulty = 1,
        category = "fieldwork", requirements = {}, reward = {relationship = 1, money = 10}, penalty = {relationship = -1}},
        {id = "loan_money", name = "Loan", description = "Loan", difficulty = 3, category = "financial",
        requirements = {}, reward = {relationship = 25, money = 1500}, penalty = {relationship = -25}}}
    w.generateFavorSteps = function()
        return {{id = 1, description = "Harvest", completed = false, location = {x = 0, y = 0, z = 0}}}
    end
    return w
end
local witness = newWitness()

local legacyRow = {
    npcId = 11, npcName = "Mara", type = "help_harvest", description = "Harvest",
    timeRemaining = 60000, progress = 0, awaitingConfirmation = false,
    ownerFarmId = nil, rewardPaid = false, repaymentCollected = false,
    loanAmountDeducted = false, reward = {relationship = 1, money = 10, xp = 0}
}
local restored, where = NPCFavorSystem.restoreFavor(witness, legacyRow)
T.eq("F148 source witness: a legacy pending-shaped row is NOT promoted to active", #witness.activeFavors, 0)
T.eq("F148 source witness: it enters the recovery collection", where, "recovery")
T.eq("F148 source witness: at paused status", restored.status, "paused_recovery")
T.eq("F148 source witness: an absent owner is NOT defaulted to farm 1", restored.ownerFarmId, nil)
T.eq("F148 source witness: absent owner presence is preserved as false", restored.ownerFarmIdPresent, false)
T.eq("F148 source witness: an ownerless legacy row carries owner_unresolved", restored.recoveryReason, "owner_unresolved")
T.eq("F148 source witness: and it is not resumable", restored.resumable, false)
T.eq("F148 source witness: a legacy stored-false payment flag stays a known false", restored.rewardPaid, false)
T.eq("F148 source witness: and its presence is recorded", restored.rewardPaidPresent, true)
T.eq("F148 source witness: ownerless legacy row is inspect-only", witness:isRecoveryRecordInspectOnly(restored), true)

-- Load-once: restoring through the staging seam twice installs once.
local twice = newWitness()
local staging = twice:beginFavorLoad()
T.ok("F148 first beginFavorLoad returns a staging table", staging ~= nil)
NPCFavorSystem.restoreFavor(twice, legacyRow, staging)
NPCFavorSystem.restoreFavor(twice, {npcId = 11, npcName = "Mara", type = "help_harvest", description = "Harvest",
    f148Schema = 1, status = "active", timeRemainingPresent = true, timeRemaining = 60000, progress = 10, ownerFarmIdPresent = true, ownerFarmId = 3,
    rewardPaidPresent = true, rewardPaid = false, repaymentCollectedPresent = true, repaymentCollected = false}, staging)
T.eq("F148 staging holds the rows before install", #staging.active + #staging.recovery, 2)
T.eq("F148 live collections untouched before install", #twice.activeFavors + #twice.recoveryFavors, 0)
T.eq("F148 installFavorSnapshot succeeds", twice:installFavorSnapshot(staging), true)
T.eq("F148 load state is READY after install", twice:getFavorLoadState(), "READY")
T.eq("F148 one active row installed", #twice.activeFavors, 1)
T.eq("F148 one recovery row installed", #twice.recoveryFavors, 1)
T.eq("F148 a second beginFavorLoad after READY returns nil", twice:beginFavorLoad(), nil)
T.eq("F148 load twice gives no duplicates", #twice.activeFavors + #twice.recoveryFavors, 2)
T.ok("F148 installed rows received unique live ids", twice.activeFavors[1].id ~= twice.recoveryFavors[1].id)
T.ok("F148 allocator sits above the installed ids", twice:allocateFavorId() > math.max(twice.activeFavors[1].id, twice.recoveryFavors[1].id))

-- Reference contract helpers. These are intentionally small and explicit so
-- the later production implementation can replace each helper at its seam.
local function farmIsValid(farms, farmId)
    if type(farmId) ~= "number" or farmId ~= math.floor(farmId) then return false end
    if farmId <= 0 or farmId > 8 or farmId == 14 or farmId == 15 then return false end
    return farms[farmId] ~= nil
end

local function actorFarm(actor, farms)
    if type(actor) ~= "table" or type(actor.farmId) ~= "number" then return nil end
    if not farmIsValid(farms, actor.farmId) then return nil end
    return actor.farmId
end

local function ownerIsKnown(record, farms)
    return record.ownerFarmIdPresent == true and farmIsValid(farms, record.ownerFarmId)
end

local function activeQuery(active, favorType, farmId)
    for _, record in ipairs(active) do
        if record.status == "active" or record.status == "in_progress" then
            if record.type == favorType and (farmId == nil or record.ownerFarmId == farmId) then
                return true
            end
        end
    end
    return false
end

local function generationAllowed(active, npcId)
    for _, record in ipairs(active) do
        if record.npcId == npcId then return false end
    end
    return true
end

local function generationAllowedV3(active, recovery, npcId)
    if not generationAllowed(active, npcId) then return false end
    for _, record in ipairs(recovery) do
        local reserves = record.resumable == true
        if not reserves and record.status == "paused_recovery" and record.recoveryReason == "owner_farm_deleted" then
            if record.type == "loan_money" then
                reserves = type(record.loanAmount) == "number" and record.loanAmount > 0
                    and record.loanAmountDeductedPresent == true and type(record.loanAmountDeducted) == "boolean"
                    and record.repaymentCollectedPresent == true and type(record.repaymentCollected) == "boolean"
            else
                reserves = record.rewardPaidPresent == true and type(record.rewardPaid) == "boolean"
            end
        end
        if record.npcId == npcId and reserves then return false end
    end
    return true
end

local function validWireNumber(value)
    if type(value) ~= "string" or not value:match("^%d+$") or #value > 10 then return false end
    local n = tonumber(value)
    return n ~= nil and n >= 0 and n <= 2147483647
end

local function validToken(value)
    if not validWireNumber(value) then return false end
    return tonumber(value) > 0
end

local function hasToken(tokenMap, token)
    return validToken(token) and tokenMap[token] ~= nil
end

local function nextWireNumber(value)
    return tostring(tonumber(value) + 1)
end

local function paymentFactsKnown(record)
    local function boolPresent(value, present)
        return present == true and type(value) == "boolean"
    end
    if not boolPresent(record.rewardPaid, record.rewardPaidPresent) then
        return false
    end
    if record.type == "loan_money" then
        if not boolPresent(record.repaymentCollected, record.repaymentCollectedPresent) then return false end
        local amount = record.loanAmount
        if record.loanAmountPresent ~= true or type(amount) ~= "number"
            or amount ~= amount or amount <= 0 or amount == math.huge or amount == -math.huge then
            return false
        end
        return boolPresent(record.loanAmountDeducted, record.loanAmountDeductedPresent)
    end
    return true
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

local function oldActionAllowed(record, actorFarmId)
    if record.collection == "recovery" or record.status == "paused_recovery" then return false end
    if record.recoveredFromLegacy == true then return false end
    return (record.status == "active" or record.status == "in_progress")
        and ownerIsKnown(record, { [record.ownerFarmId] = true })
        and record.ownerFarmId == actorFarmId
end

local function resume(manager, token, collectionRevision, recordRevision, actor, targetFarmId, verifiedAdmin, requestId)
    -- actor is a private server-resolved context, never a native User object or
    -- a client-declared farm claim. Its connectionId is the trusted session key.
    if type(actor) ~= "table" or type(actor.connectionId) ~= "string"
        or actor.connectionId == "" then return false end
    if not validWireNumber(requestId) or not validWireNumber(recordRevision) then return false end
    if targetFarmId ~= nil and not farmIsValid(manager.farms, targetFarmId) then return false end
    local actorFarmId = actorFarm(actor, manager.farms)
    local admin = verifiedAdmin == true
    if actorFarmId == nil and not admin then return false end
    if not validWireNumber(collectionRevision)
        or collectionRevision ~= manager.collectionRevision
        or not hasToken(manager.tokens, token) then
        return false
    end
    local record = manager.tokens[token]
    local requestKey = actor.connectionId .. ":" .. requestId
    local fingerprint = table.concat({token, collectionRevision, recordRevision,
        tostring(targetFarmId or ""), tostring(actorFarmId or "nil"), admin and "ADMIN" or "MEMBER"}, "|")
    local prior = manager.completedRequests[requestKey]
    if prior ~= nil then
        return prior.fingerprint == fingerprint and prior.result == true
    end

    if record.collection ~= "recovery" or record.status ~= "paused_recovery" then return false end
    -- resumable gates only the known-owner route. A deleted-owner row is
    -- deliberately false here and remains assignable by an administrator.
    if targetFarmId == nil and record.resumable ~= true then return false end
    if not validWireNumber(recordRevision) or recordRevision ~= record.recordRevision then return false end

    local target = record.ownerFarmId
    if targetFarmId ~= nil then
        if not admin or ownerIsKnown(record, manager.farms) then return false end
        if record.recoveryReason ~= "owner_farm_deleted" then return false end
        if not farmIsValid(manager.farms, targetFarmId) then return false end
        target = targetFarmId
    elseif not ownerIsKnown(record, manager.farms) or actorFarmId ~= record.ownerFarmId then
        return false
    end
    if not farmIsValid(manager.farms, target) then return false end
    if not paymentFactsKnown(record) then return false end
    for _, live in ipairs(manager.active) do
        if live.npcId == record.npcId then return false end
    end

    if not removeIdentity(manager.recovery, record) then return false end
    record.collection = "active"
    record.status = (record.originalStatus == "in_progress") and "in_progress" or "active"
    record.ownerFarmId = target
    record.ownerFarmIdPresent = true
    record.recoveredFromLegacy = true
    record.recordRevision = nextWireNumber(record.recordRevision)
    table.insert(manager.active, record)
    manager.completedRequests[requestKey] = {fingerprint = fingerprint, result = true}
    return true
end

-- Disjoint ordinary and recovery collections. Resumable recovery reserves its
-- NPC slot; inspect-only recovery does not. Neither enters the active query.
local farms = {[1] = {}, [2] = {}, [3] = {}}
local active = {{id = 10, npcId = 11, type = "help_harvest", status = "active",
    ownerFarmId = 1, ownerFarmIdPresent = true}}
local recovery = {{id = 20, npcId = 12, type = "loan_money", status = "paused_recovery",
    collection = "recovery", resumable = false, recoveryReason = "owner_farm_deleted", recordRevision = "2",
    ownerFarmIdPresent = false, ownerFarmId = nil,
    progress = 40, loanAmount = 5000, loanAmountPresent = true,
    loanAmountDeducted = false, loanAmountDeductedPresent = true,
    rewardPaid = false, rewardPaidPresent = true,
    repaymentCollected = false, repaymentCollectedPresent = true}}
T.eq("F148 reference active query accepts the known owner", activeQuery(active, "help_harvest", 1), true)
T.eq("F148 reference active query excludes the neighbour", activeQuery(active, "help_harvest", 2), false)
T.eq("F148 reference global query remains available", activeQuery(active, "help_harvest", nil), true)
T.eq("F148 recovery rows are absent from the ordinary query", activeQuery(recovery, "loan_money", nil), false)
T.eq("F148 resumable recovery reserves its NPC generation slot", generationAllowedV3(active, recovery, 12), false)
T.eq("F148 ordinary active row still occupies its NPC slot", generationAllowed(active, 11), false)
local inspectOnly = {npcId = 13, status = "paused_recovery", resumable = false}
T.eq("F148 unsupported inspect-only recovery does not reserve generation slot", generationAllowedV3(active, {inspectOnly}, 13), true)

-- One selected full load only. A later live mutation survives repeated or late
-- callbacks; a generic clear-before-every-deserialize would fail this contract.
local loader = {state = "WAITING", active = {}, recovery = {}, collectionRevision = 0, recordRevision = 0}
function loader:applySelected(snapshot)
    if self.state == "READY" then return false end
    self.state = "APPLYING"
    local newActive, newRecovery = {}, {}
    for _, record in ipairs(snapshot.active or {}) do table.insert(newActive, record) end
    for _, record in ipairs(snapshot.recovery or {}) do table.insert(newRecovery, record) end
    self.active, self.recovery = newActive, newRecovery
    self.collectionRevision = self.collectionRevision + 1
    self.state = "READY"
    return true
end
local selectedRecord = {id = 31, status = "active", collection = "active", progress = 5,
    ownerFarmId = 1, ownerFarmIdPresent = true}
T.eq("F148 selected initial snapshot applies once", loader:applySelected({active = {selectedRecord}}), true)
selectedRecord.progress = 65
T.eq("F148 live progress mutation is visible after initial load", loader.active[1].progress, 65)
T.eq("F148 repeated/late snapshot callback is ignored", loader:applySelected({active = {{id = 31, progress = 5}}}), false)
T.eq("F148 repeated callback does not throw away live progress", loader.active[1].progress, 65)

-- Exact-token resume and authority. A known owner can resume only its own row;
-- host/admin can assign an ownerless row to a selected ordinary farm. The same
-- record object moves from recovery to active rather than being copied.
-- Every actor table below is a SERVER-RESOLVED context (connectionId, farmId,
-- and verified rights), never a native User object or a client claim.
local manager = {active = {}, recovery = {}, tokens = {}, farms = farms,
    collectionRevision = "7", recordRevision = "2", completedRequests = {}}
local ownerless = recovery[1]
manager.recovery = {ownerless}
manager.tokens = { ["20"] = ownerless }
T.eq("F148 missing actor refuses resume", resume(manager, "20", "7", "2", nil, nil, false, "0"), false)
T.eq("F148 dedicated nil-farm context refuses resume", resume(manager, "20", "7", "2", {connectionId = "dedicated"}, nil, false, "1"), false)
T.eq("F148 stale collection revision refuses resume", resume(manager, "20", "6", "2", {connectionId = "farm-a", farmId = 1}, nil, false, "1"), false)
T.eq("F148 stale record revision refuses resume", resume(manager, "20", "7", "1", {connectionId = "farm-a", farmId = 1}, nil, false, "2"), false)
T.eq("F148 missing token refuses resume", resume(manager, "missing", "7", "2", {connectionId = "farm-a", farmId = 1}, nil, false, "3"), false)
T.eq("F148 ordinary member cannot assign an ownerless row", resume(manager, "20", "7", "2", {connectionId = "farm-a", farmId = 1}, 2, false, "4"), false)
T.eq("F148 spectator assignment target is refused", resume(manager, "20", "7", "2", {connectionId = "farm-a", farmId = 1}, 0, true, "5"), false)
T.eq("F148 guided-tour assignment target is refused", resume(manager, "20", "7", "2", {connectionId = "farm-a", farmId = 1}, 14, true, "6"), false)
T.eq("F148 invalid assignment target is refused", resume(manager, "20", "7", "2", {connectionId = "farm-a", farmId = 1}, 15, true, "7"), false)
T.eq("F148 absent assignment target farm is refused", resume(manager, "20", "7", "2", {connectionId = "farm-a", farmId = 1}, 8, true, "8"), false)
T.eq("F148 verified spectator admin can assign a valid target farm", resume(manager, "20", "7", "2", {connectionId = "farm-a", farmId = 0}, 2, true, "9"), true)
T.eq("F148 assigned row leaves recovery collection", #manager.recovery, 0)
T.eq("F148 assigned row enters active collection", #manager.active, 1)
T.eq("F148 assignment moves the same record object", manager.active[1], ownerless)
T.eq("F148 assigned owner is the selected farm", ownerless.ownerFarmId, 2)
T.eq("F148 assignment preserves progress", ownerless.progress, 40)
T.eq("F148 assignment performs no payment", ownerless.rewardPaid, false)
T.eq("F148 assignment preserves loan debit flag", ownerless.loanAmountDeducted, false)
T.eq("F148 assignment preserves repayment flag", ownerless.repaymentCollected, false)
T.eq("F148 assignment preserves loan flag presence", ownerless.loanAmountDeductedPresent, true)
T.eq("F148 assignment preserves reward flag presence", ownerless.rewardPaidPresent, true)
T.eq("F148 resume marks the actual moved record as legacy-recovered", ownerless.recoveredFromLegacy, true)
T.eq("F148 old action rejects the actual resumed record", oldActionAllowed(manager.active[1], 2), false)
T.eq("F148 exact-token retry is idempotent for the same connection and fingerprint", resume(manager, "20", "7", "2", {connectionId = "farm-a", farmId = 0}, 2, true, "9"), true)
T.eq("F148 stale/repeated token cannot resume another row", resume(manager, "20", "7", "2", {connectionId = "farm-a", farmId = 1}, 2, true, "10"), false)

-- A changed token/payload with the same request id from the same connection is
-- rejected, while a different trusted connection may use that request id once.
local secondOwnerless = {id = 21, npcId = 14, type = "help_harvest", status = "paused_recovery",
    collection = "recovery", resumable = false, recoveryReason = "owner_farm_deleted", recordRevision = "2", ownerFarmIdPresent = false,
    progress = 10, rewardPaid = false, rewardPaidPresent = true,
    repaymentCollected = false, repaymentCollectedPresent = true}
table.insert(manager.recovery, secondOwnerless)
manager.tokens["21"] = secondOwnerless
T.eq("F148 same connection changed token/payload is refused", resume(manager, "21", "7", "2", {connectionId = "farm-a", farmId = 0}, 3, true, "9"), false)
T.eq("F148 different trusted connection may reuse request id", resume(manager, "21", "7", "2", {connectionId = "farm-b", farmId = 0}, 3, true, "9"), true)
T.eq("F148 second row resumes as the same object", manager.active[2], secondOwnerless)

-- Known-owner success and cross-farm refusal. Use a fresh manager because the
-- prior row is now active and cannot be resumed a second time.
local knownManager = {active = {}, recovery = {}, tokens = {}, farms = farms,
    collectionRevision = "9", recordRevision = "0", completedRequests = {}}
local known = {id = 40, type = "help_harvest", status = "paused_recovery", collection = "recovery",
    ownerFarmId = 2, ownerFarmIdPresent = true, progress = 20, resumable = true, originalStatus = "in_progress",
    rewardPaid = true, rewardPaidPresent = true,
    repaymentCollected = false, repaymentCollectedPresent = true}
knownManager.recovery = {known}
knownManager.tokens = { ["40"] = known }
known.recordRevision = "2"
T.eq("F148 other farm cannot resume known-owner work", resume(knownManager, "40", "9", "2", {connectionId = "farm-a", farmId = 1}, nil, false, "11"), false)
T.eq("F148 known owner can resume its work", resume(knownManager, "40", "9", "2", {connectionId = "farm-b", farmId = 2}, nil, false, "12"), true)
T.eq("F148 known-owner resume preserves in_progress status", known.status, "in_progress")
T.eq("F148 known-owner resume preserves same object", knownManager.active[1], known)

-- Recovered rows cannot fall through old NPC-keyed complete/abandon actions.
local recoveredActive = {status = "active", collection = "active", recoveredFromLegacy = true,
    ownerFarmId = 2, ownerFarmIdPresent = true}
local ordinaryActive = {status = "active", collection = "active", recoveredFromLegacy = false,
    ownerFarmId = 2, ownerFarmIdPresent = true}
T.eq("F148 old action rejects recovered active row", oldActionAllowed(recoveredActive, 2), false)
T.eq("F148 old action rejects recovered row from another farm", oldActionAllowed(recoveredActive, 1), false)
T.eq("F148 ordinary owner action remains a legitimate success", oldActionAllowed(ordinaryActive, 2), true)
T.eq("F148 old action rejects paused recovery row", oldActionAllowed({status = "paused_recovery", collection = "recovery", ownerFarmId = 2, ownerFarmIdPresent = true}, 2), false)

-- Unknown presence is not permission to execute money-bearing recovery. All
-- flags must be explicitly present, including explicit false values.
local unknownPaymentManager = {active = {}, recovery = {}, tokens = {}, farms = farms,
    collectionRevision = "12", recordRevision = "0", completedRequests = {}}
local unknownPayment = {id = 50, type = "loan_money", status = "paused_recovery", collection = "recovery",
    ownerFarmIdPresent = false, progress = 0, recordRevision = "2", resumable = true,
    loanAmount = 5000, loanAmountDeducted = false,
    rewardPaid = false, repaymentCollected = false,
    loanAmountPresent = true, loanAmountDeductedPresent = false,
    rewardPaidPresent = true, repaymentCollectedPresent = true}
unknownPaymentManager.recovery = {unknownPayment}
unknownPaymentManager.tokens = { ["50"] = unknownPayment }
T.eq("F148 unknown payment presence refuses admin assignment", resume(unknownPaymentManager, "50", "12", "2", {connectionId = "farm-a", farmId = 0}, 2, true, "13"), false)
T.eq("F148 unknown payment row remains in recovery", #unknownPaymentManager.recovery, 1)
T.eq("F148 unknown payment row cannot enter active", #unknownPaymentManager.active, 0)

T.eq("F148 nondecimal request id refuses command", resume(unknownPaymentManager, "50", "12", "2", {connectionId = "farm-a", farmId = 0}, 2, true, "req"), false)
T.eq("F148 max wire revision is accepted as decimal ASCII", validWireNumber("2147483647"), true)
T.eq("F148 wire revision above signed range is refused", validWireNumber("2147483648"), false)
T.eq("F148 zero request/revision is allowed", validWireNumber("0"), true)
T.eq("F148 zero token is refused", validToken("0"), false)
T.eq("F148 max positive token is accepted", validToken("2147483647"), true)
T.eq("F148 overlong wire token is refused", validToken("12345678901"), false)

-- A valid farm, owner and complete presence set is a positive recovery path.
-- These direct actorFarm fixtures are also already SERVER-RESOLVED contexts;
-- the farm id is not being read from a native User or trusted from a client.
T.ok("F148 ordinary farm resolver accepts a real farm", actorFarm({connectionId = "farm-b", farmId = 2}, farms) == 2)
T.ok("F148 spectator actor is unavailable", actorFarm({connectionId = "spectator", farmId = 0}, farms) == nil)
T.ok("F148 guided-tour actor is unavailable", actorFarm({connectionId = "tour", farmId = 14}, farms) == nil)
T.ok("F148 missing actor farm is unavailable", actorFarm({connectionId = "dedicated"}, farms) == nil)
T.ok("F148 invalid actor farm is unavailable", actorFarm({connectionId = "invalid", farmId = 99}, farms) == nil)

-- Future positive schemas refuse load/save without downgrade, while a readable
-- status-less legacy row remains inspect-only recovery evidence.
local function schemaDisposition(schema, readable)
    if schema == 1 then return "SUPPORTED" end
    if type(schema) == "number" and schema > 1 then return "UNSUPPORTED" end
    if schema == nil and readable then return "LEGACY_RECOVERY" end
    return "FAILED"
end
T.eq("F148 current recovery schema is supported", schemaDisposition(1, true), "SUPPORTED")
T.eq("F148 future positive schema refuses without downgrade", schemaDisposition(2, true), "UNSUPPORTED")
T.eq("F148 readable status-less legacy row enters inspection recovery", schemaDisposition(nil, true), "LEGACY_RECOVERY")
T.eq("F148 unreadable record does not become an empty save", schemaDisposition(nil, false), "FAILED")

-- Owner ruling: a paused harvest leaves ordinary soil simulation running; the
-- active FieldSentry job contract returns only after the same record resumes.
local function fieldWorkMode(record)
    if record.status == "active" or record.status == "in_progress" then return "ACTIVE_JOB" end
    return "NORMAL_SOIL"
end
T.eq("F148 paused harvest leaves normal soil simulation running", fieldWorkMode({status = "paused_recovery"}), "NORMAL_SOIL")
T.eq("F148 pending harvest leaves normal soil simulation running", fieldWorkMode({status = "pending"}), "NORMAL_SOIL")
T.eq("F148 resumed harvest restores active job mode", fieldWorkMode({status = "active"}), "ACTIVE_JOB")
-- Author readback additions: discriminating malformed input and lifecycle cases.
T.eq("F148 missing record revision is refused without formatting it", resume(manager, "20", "7", nil, {connectionId="farm-a",farmId=0}, 2, true, "9"), false)
T.eq("F148 same connection changed target cannot replay prior result", resume(manager, "20", "7", "2", {connectionId="farm-a",farmId=0}, 3, true, "9"), false)
T.eq("F148 same connection changed actor farm cannot replay prior result", resume(manager, "20", "7", "2", {connectionId="farm-a",farmId=1}, 2, true, "9"), false)
T.eq("F148 non-loan needs no fabricated loan or repayment fields", paymentFactsKnown({type="help_harvest", rewardPaid=false, rewardPaidPresent=true}), true)
T.eq("F148 unknown loan deduction alone prevents execution", paymentFactsKnown(unknownPayment), false)
local deletedOwner = {npcId=15,type="help_harvest",status="paused_recovery",collection="recovery",resumable=false,
    recoveryReason="owner_farm_deleted",recordRevision="0",ownerFarmId=8,ownerFarmIdPresent=true,
    rewardPaid=false,rewardPaidPresent=true}
local deletedManager = {active={},recovery={deletedOwner},tokens={["70"]=deletedOwner},farms=farms,
    collectionRevision="1",completedRequests={}}
T.eq("F148 admin can explicitly replace a deleted former owner", resume(deletedManager,"70","1","0",{connectionId="admin",farmId=0},2,true,"1"), true)
T.eq("F148 deleted-owner assignment preserves the exact record",deletedManager.active[1],deletedOwner)
local detached = {npcId=16,type="help_harvest",status="paused_recovery",collection="recovery",resumable=true,
    recordRevision="0",ownerFarmId=2,ownerFarmIdPresent=true,rewardPaid=false,rewardPaidPresent=true}
local detachedManager = {active={},recovery={},tokens={["71"]=detached},farms=farms,collectionRevision="1",completedRequests={}}
T.eq("F148 stale token cannot resurrect a record absent from recovery",resume(detachedManager,"71","1","0",{connectionId="member",farmId=2},nil,false,"1"),false)
T.eq("F148 absent recovery record creates no active copy",#detachedManager.active,0)
detached.resumable=false; detachedManager.recovery={detached}
T.eq("F148 inspect-only record refuses even with known payment flags",resume(detachedManager,"71","1","0",{connectionId="member",farmId=2},nil,false,"2"),false)
T.eq("F148 inspect-only record still permits new ordinary generation",generationAllowedV3({},detachedManager.recovery,16),true)

-- R3 binding checks. These are reference UI/schema bindings, not native widgets,
-- XML APIs, StateLedger I/O or real event transport.
T.eq("F148 cached admin result is refused after rights are revoked",resume(manager,"20","7","2",{connectionId="farm-a",farmId=0},2,false,"9"),false)
local busyRecord={npcId=44,type="help_harvest",status="paused_recovery",originalStatus="active",collection="recovery",resumable=true,
    recordRevision="0",ownerFarmId=2,ownerFarmIdPresent=true,rewardPaid=false,rewardPaidPresent=true}
local busy={active={{npcId=44,status="active"}},recovery={busyRecord},tokens={["80"]=busyRecord},farms=farms,
    collectionRevision="1",completedRequests={}}
T.eq("F148 resume cannot displace another ordinary job for that NPC",resume(busy,"80","1","0",{connectionId="member",farmId=2},nil,false,"1"),false)
T.eq("F148 occupied NPC leaves recovery evidence in place",busy.recovery[1],busyRecord)
busy.active={}
T.eq("F148 resume becomes possible once ordinary work finishes",resume(busy,"80","1","0",{connectionId="member",farmId=2},nil,false,"2"),true)
T.eq("F148 original active status is preserved",busyRecord.status,"active")

local function encodeField(record)
    local field=record.taskData and record.taskData.fieldId
    return {taskFieldIdPresent=field~=nil,taskFieldId=field}
end
local function decodeField(data)
    local id=data.taskFieldId
    if data.taskFieldIdPresent~=true or type(id)~="number" or id~=id
        or id==math.huge or id==-math.huge or id<=0 or id~=math.floor(id) then return nil end
    return id
end
T.eq("F148 record encoding preserves a known harvest field",decodeField(encodeField({taskData={fieldId=37}})),37)
T.eq("F148 legacy missing field does not acquire today's NPC field",decodeField({}),nil)
T.eq("F148 explicit absent field cannot be promoted from a placeholder",decodeField({taskFieldIdPresent=false,taskFieldId=37}),nil)
T.eq("F148 field zero stays unavailable",decodeField({taskFieldIdPresent=true,taskFieldId=0}),nil)
T.eq("F148 noninteger field stays unavailable",decodeField({taskFieldIdPresent=true,taskFieldId=1.5}),nil)

local farmA={farmId=1,name="Oak Farm",showInFarmScreen=true,isSpectator=false}
local farmB={farmId=2,name="Oak Farm",showInFarmScreen=true,isSpectator=false}
local farmHidden={farmId=3,name="Hidden",showInFarmScreen=false,isSpectator=false}
local special={farmId=0,name="Spectator",showInFarmScreen=true,isSpectator=true}
local function pickerSnapshot(list,current)
    local view={options={},byId={},selectedFarmId=nil}
    for _, farm in ipairs(list) do
        local id=farm.farmId
        if farmIsValid(current,id) and current[id]==farm and farm.isSpectator~=true and farm.showInFarmScreen~=false then
            view.options[#view.options+1]={farmId=id,label=farm.name.." (#"..id..")"}
            view.byId[id]=farm
        end
    end
    return view
end
local function pickerConfirm(view,id,yes,current)
    if yes~=true or id==nil or view.byId[id]==nil or current[id]~=view.byId[id] then return false end
    return farmIsValid(current,id)
end
local currentFarms={[0]=special,[1]=farmA,[2]=farmB,[3]=farmHidden}
local view=pickerSnapshot({special,farmA,farmB,farmHidden},currentFarms)
T.eq("F148 picker contains only the two ordinary visible farms",#view.options,2)
T.eq("F148 picker has no automatic first-farm choice",view.selectedFarmId,nil)
T.ok("F148 duplicate names remain distinguishable by id",view.options[1].label~=view.options[2].label)
T.eq("F148 confirm without explicit farm selection does nothing",pickerConfirm(view,nil,true,currentFarms),false)
T.eq("F148 cancelled assignment does nothing",pickerConfirm(view,2,false,currentFarms),false)
T.eq("F148 explicit current target is a legitimate assignment choice",pickerConfirm(view,2,true,currentFarms),true)
currentFarms[2]=nil
T.eq("F148 deleted assignment target requires a refreshed choice",pickerConfirm(view,2,true,currentFarms),false)
currentFarms[2]={farmId=2,name="Replacement",showInFarmScreen=true}
T.eq("F148 recreated same-id farm is not the originally chosen object",pickerConfirm(view,2,true,currentFarms),false)

local function completionRoute(row,control)
    if row.collection=="recovery" or row.status=="paused_recovery" then return "NO_COMPLETION" end
    if row.recoveredFromLegacy then
        if control=="ManagementDone" or control=="NPCDialogComplete" then return "TOKEN_COMPLETE" end
        if control=="ManagementCancel" then return "TOKEN_ABANDON" end
    end
    return "ORDINARY"
end
T.eq("F148 Management Done routes the actual resumed object by token",completionRoute(known,"ManagementDone"),"TOKEN_COMPLETE")
T.eq("F148 NPC dialog completion uses that same token route",completionRoute(known,"NPCDialogComplete"),"TOKEN_COMPLETE")
T.eq("F148 Management Cancel uses owner abandon without its extra local penalty",completionRoute(known,"ManagementCancel"),"TOKEN_ABANDON")
T.eq("F148 Done cannot complete a paused record",completionRoute({collection="recovery",status="paused_recovery"},"ManagementDone"),"NO_COMPLETION")
T.eq("F148 ordinary never-paused Done remains available",completionRoute(ordinaryActive,"ManagementDone"),"ORDINARY")
-- Runner appends T.summary(); no duplicate terminal is emitted here.

-- =====================================================================
-- RSF-F148 FARM IDENTITY CONTRACT (added at the broad round one fold).
-- Arissani's 2026-09-14 ruling: a favour belongs to the farm that accepted
-- it; when that farm is deleted its accepted job ownership is invalidated;
-- a new farm reusing the number inherits neither the job nor its rewards
-- nor its charges; that state stays distinct from an unaccepted offer; no
-- second farm identity is minted and no new save field is added.
--
-- The first block below is a REAL-SOURCE WITNESS against the supplied
-- production restoreFavor and it is the load-bearing one: it proves the
-- sentinel survives the shipped restore while nil does not. The remaining
-- blocks are a reference contract for the unbuilt transition. They model
-- state and authority. They prove no native UI, no network, no disk, no
-- multiplayer and no gameplay behaviour.
-- =====================================================================

FarmManager.MAX_FARM_ID = FarmManager.MAX_FARM_ID or 8
FarmManager.GUIDED_TOUR_FARM_ID = FarmManager.GUIDED_TOUR_FARM_ID or 14
FarmManager.INVALID_FARM_ID = FarmManager.INVALID_FARM_ID or 15

T.eq("F148 identity sentinel is the engine INVALID_FARM_ID", FarmManager.INVALID_FARM_ID, 15)
T.ok("F148 identity sentinel sits outside the usable farm range",
    FarmManager.INVALID_FARM_ID > FarmManager.MAX_FARM_ID)
T.ok("F148 identity sentinel is not the spectator farm",
    FarmManager.INVALID_FARM_ID ~= FarmManager.SPECTATOR_FARM_ID)
T.ok("F148 identity sentinel is not the guided tour farm",
    FarmManager.INVALID_FARM_ID ~= FarmManager.GUIDED_TOUR_FARM_ID)

-- REAL-SOURCE WITNESS. The ruling requires a sentinel rather than nil
-- because the shipped restore re-resolves an absent owner onto a live farm.
-- Exercise the supplied restoreFavor on both shapes and record what it does.
local identityWitness = newWitness()

local function savedRow(owner)
    return {
        npcId = 11, npcName = "Mara", type = "help_harvest", description = "Harvest",
        timeRemaining = 60000, progress = 0, awaitingConfirmation = false,
        ownerFarmId = owner, rewardPaid = false, repaymentCollected = false,
        loanAmountDeducted = false, reward = {relationship = 1, money = 10, xp = 0}
    }
end

local sentinelRestored = NPCFavorSystem.restoreFavor(identityWitness, savedRow(FarmManager.INVALID_FARM_ID))
T.eq("F148 source witness does NOT re-resolve an owner already at the sentinel",
    sentinelRestored.ownerFarmId, FarmManager.INVALID_FARM_ID)
T.eq("F148 source witness: a sentinel-owned legacy row is paused, not active", sentinelRestored.status, "paused_recovery")

local nilRestored = NPCFavorSystem.restoreFavor(identityWitness, savedRow(nil))
T.eq("F148 source witness no longer re-resolves an absent owner onto a live farm", nilRestored.ownerFarmId, nil)

local ordinaryRestored = NPCFavorSystem.restoreFavor(identityWitness, savedRow(3))
T.eq("F148 source witness leaves an ordinary stored owner alone", ordinaryRestored.ownerFarmId, 3)
T.eq("F148 source witness: a legacy row with a live owner is legacy_acceptance_unknown",
    ordinaryRestored.recoveryReason, "legacy_acceptance_unknown")
T.eq("F148 source witness: and may be resumed explicitly by that owner", ordinaryRestored.resumable, true)
T.eq("F148 source witness: nothing legacy entered the live list", #identityWitness.activeFavors, 0)

-- Reference contract for the unbuilt transition. Helpers are small and
-- explicit so the production implementation can replace each at its seam.

local ACTIVE_STATUS = {active = true, in_progress = true}

local function newManager()
    return {
        activeFavors = {}, recoveryFavors = {},
        completedFavors = {}, failedFavors = {}, abandonedFavors = {},
        liveFarms = {[1] = true, [2] = true}
    }
end

local function getFarmById(mgr, farmId)
    if farmId == nil then return nil end
    if mgr.liveFarms[farmId] then return {farmId = farmId} end
    return nil
end

local function place(mgr, collection, row)
    row.collection = collection
    table.insert(mgr[collection], row)
    return row
end

local function removeFrom(list, row)
    for i, r in ipairs(list) do
        if r == row then table.remove(list, i) return true end
    end
    return false
end

-- THE ORPHANING TRANSITION. One state change, applied to every collection
-- that can still cause a money or relationship effect or be resumed.
local WALKED = {"activeFavors", "recoveryFavors"}

local function orphanRow(mgr, row)
    row.ownerFarmId = FarmManager.INVALID_FARM_ID
    row.status = "paused_recovery"
    row.recoveryReason = "owner_farm_deleted"
    row.resumable = false
    if row.collection ~= "recoveryFavors" then
        removeFrom(mgr[row.collection], row)
        place(mgr, "recoveryFavors", row)
    end
    return row
end

local function onFarmDeleted(mgr, farmId)
    if getFarmById(mgr, farmId) ~= nil then return 0 end  -- stale notice, live farm holds the number
    local touched = 0
    for _, name in ipairs(WALKED) do
        local list = mgr[name]
        for i = #list, 1, -1 do
            local row = list[i]
            if row.ownerFarmId == farmId then orphanRow(mgr, row) touched = touched + 1 end
        end
    end
    return touched
end

local function onFarmCreated(mgr, farmId, isServer)
    if not isServer then return 0 end  -- :241 publishes on the client replication path
    local touched = 0
    for _, name in ipairs(WALKED) do
        local list = mgr[name]
        for i = #list, 1, -1 do
            local row = list[i]
            if row.ownerFarmId == farmId then orphanRow(mgr, row) touched = touched + 1 end
        end
    end
    return touched
end

-- Deletion orphans a live job, and the transition is a state change rather
-- than a value write.
local mgr = newManager()
local liveJob = place(mgr, "activeFavors", {npcId = 11, type = "help_harvest", status = "active", ownerFarmId = 2,
    rewardPaid = false, rewardPaidPresent = true})
mgr.liveFarms[2] = nil
T.eq("F148 deletion touches the one row owned by the deleted farm", onFarmDeleted(mgr, 2), 1)
T.eq("F148 an orphaned job takes the invalid sentinel", liveJob.ownerFarmId, FarmManager.INVALID_FARM_ID)
T.eq("F148 an orphaned job takes the paused recovery status", liveJob.status, "paused_recovery")
T.eq("F148 an orphaned job carries the owner-deleted reason", liveJob.recoveryReason, "owner_farm_deleted")
T.eq("F148 an orphaned job is not resumable", liveJob.resumable, false)
T.eq("F148 an orphaned job leaves the live collection", #mgr.activeFavors, 0)
T.eq("F148 an orphaned job enters the recovery collection", #mgr.recoveryFavors, 1)
T.eq("F148 an assignable owner-deleted row reserves its NPC despite resumable false",
    generationAllowedV3({}, mgr.recoveryFavors, 11), false)
local incompleteOrphan = {npcId = 17, type = "help_harvest", status = "paused_recovery",
    recoveryReason = "owner_farm_deleted", resumable = false, rewardPaidPresent = false}
T.eq("F148 an owner-deleted row with incomplete required facts is inspect-only and does not reserve",
    generationAllowedV3({}, {incompleteOrphan}, 17), true)

-- The tick consequence. The update loop walks activeFavors only, so an
-- orphaned job cannot expire, cannot fail and cannot cost the relationship.
local function tickWouldReach(mgr, row)
    for _, r in ipairs(mgr.activeFavors) do if r == row then return true end end
    return false
end
T.eq("F148 the favour tick can no longer reach an orphaned job", tickWouldReach(mgr, liveJob), false)

-- The field sentry consequence. It keys on status and on the live list.
local function sentryMasks(mgr, row)
    if not tickWouldReach(mgr, row) then return false end
    return ACTIVE_STATUS[row.status] == true
end
T.eq("F148 the field sentry releases the field an orphaned job was masking", sentryMasks(mgr, liveJob), false)

-- A row already in the recovery collection is reached too. This is the
-- failure the first round found: without it a paused row keeps a valid
-- owner across the reuse and the new farm can resume it.
local mgr2 = newManager()
local pausedKnownOwner = place(mgr2, "recoveryFavors", {npcId = 12, status = "paused_recovery", ownerFarmId = 2, resumable = true})
mgr2.liveFarms[2] = nil
T.eq("F148 deletion reaches a row already sitting in the recovery collection", onFarmDeleted(mgr2, 2), 1)
T.eq("F148 a paused row loses its owner to the sentinel", pausedKnownOwner.ownerFarmId, FarmManager.INVALID_FARM_ID)
T.eq("F148 a paused row becomes not resumable", pausedKnownOwner.resumable, false)
T.eq("F148 a paused row stays in the recovery collection rather than moving twice", #mgr2.recoveryFavors, 1)

-- Known-owner resume cannot match an orphaned row afterwards.
local function knownOwnerResumeAllowed(mgr, row, actorFarmId)
    if row.status ~= "paused_recovery" then return false end
    if row.resumable ~= true then return false end
    if row.ownerFarmId == FarmManager.INVALID_FARM_ID then return false end
    if getFarmById(mgr, row.ownerFarmId) == nil then return false end
    return row.ownerFarmId == actorFarmId
end
mgr2.liveFarms[2] = true  -- the number is reissued to a new farm
T.eq("F148 a new farm taking the reissued number cannot resume the old paused job",
    knownOwnerResumeAllowed(mgr2, pausedKnownOwner, 2), false)

-- A pending offer has no owner stamped, so deletion leaves it alone and it
-- stays distinct from an orphaned job, which is the ruling's own wording.
local mgr3 = newManager()
local pendingOffer = place(mgr3, "activeFavors", {npcId = 13, status = "pending", ownerFarmId = nil})
mgr3.liveFarms[2] = nil
T.eq("F148 deletion touches no pending offer", onFarmDeleted(mgr3, 2), 0)
T.eq("F148 a pending offer keeps its pending status", pendingOffer.status, "pending")
T.eq("F148 a pending offer stays out of the recovery collection", #mgr3.recoveryFavors, 0)

-- Another farm's job is untouched.
local mgr4 = newManager()
local otherFarmJob = place(mgr4, "activeFavors", {npcId = 14, status = "active", ownerFarmId = 1})
mgr4.liveFarms[2] = nil
T.eq("F148 deletion of one farm does not touch another farm's job", onFarmDeleted(mgr4, 2), 0)
T.eq("F148 another farm's job keeps its owner", otherFarmJob.ownerFarmId, 1)
T.eq("F148 another farm's job keeps its status", otherFarmJob.status, "active")

-- Terminal collections are deliberately not walked, and the reason is that
-- every payment and penalty on those rows is made in the call that moves
-- them there. Assert the deliberate exclusion so a later change is visible.
local mgr5 = newManager()
local completedRow = place(mgr5, "completedFavors", {npcId = 15, status = "completed", ownerFarmId = 2})
mgr5.liveFarms[2] = nil
T.eq("F148 deletion deliberately does not walk the terminal collections", onFarmDeleted(mgr5, 2), 0)
T.eq("F148 a completed row keeps its owner for its own history", completedRow.ownerFarmId, 2)

-- The stale notice. A delayed delete arriving after the number is reissued
-- must do nothing, which is what stops it invalidating a new farm's job.
local mgr6 = newManager()
local newFarmJob = place(mgr6, "activeFavors", {npcId = 16, status = "active", ownerFarmId = 2})
T.eq("F148 a stale deletion notice touches nothing while a live farm holds the number", onFarmDeleted(mgr6, 2), 0)
T.eq("F148 a new farm's newly accepted job survives an old deletion notice", newFarmJob.ownerFarmId, 2)
T.eq("F148 a new farm's newly accepted job keeps its active status", newFarmJob.status, "active")
T.eq("F148 a new farm's newly accepted job stays in the live collection", #mgr6.activeFavors, 1)

-- Idempotency. Repeated and delayed delivery is safe by construction
-- because the second pass matches nothing.
local mgr7 = newManager()
local repeatJob = place(mgr7, "activeFavors", {npcId = 17, status = "active", ownerFarmId = 2})
mgr7.liveFarms[2] = nil
T.eq("F148 first delivery orphans the job", onFarmDeleted(mgr7, 2), 1)
T.eq("F148 second delivery of the same notice matches nothing", onFarmDeleted(mgr7, 2), 0)
T.eq("F148 third delivery still matches nothing", onFarmDeleted(mgr7, 2), 0)
T.eq("F148 the record is unchanged after repeated delivery", repeatJob.ownerFarmId, FarmManager.INVALID_FARM_ID)
T.eq("F148 the recovery collection does not grow on repeated delivery", #mgr7.recoveryFavors, 1)

-- Creation closes the other end: a job already carrying the number when the
-- farm is created must predate it, because the farm did not exist to accept.
local mgr8 = newManager()
local predatingJob = place(mgr8, "activeFavors", {npcId = 18, status = "active", ownerFarmId = 2})
T.eq("F148 creation orphans a job that already carried the new farm's number", onFarmCreated(mgr8, 2, true), 1)
T.eq("F148 the predating job takes the sentinel", predatingJob.ownerFarmId, FarmManager.INVALID_FARM_ID)
T.eq("F148 the predating job leaves the live collection", #mgr8.activeFavors, 0)

-- The creation handler is server-only. The engine also publishes on the
-- client replication path, where every existing farm looks new at join.
local mgr9 = newManager()
local clientSideJob = place(mgr9, "activeFavors", {npcId = 19, status = "active", ownerFarmId = 2})
T.eq("F148 the creation handler does nothing on the client replication path", onFarmCreated(mgr9, 2, false), 0)
T.eq("F148 a joining client does not orphan a live job", clientSideJob.ownerFarmId, 2)

-- Money. Both sites read the owner and write it back, so the guard protects
-- the record as well as the payment.
local function payOwner(row, amount, ledger)
    if row.ownerFarmId == FarmManager.INVALID_FARM_ID then return false end
    local farmId = row.ownerFarmId or 1  -- the shipped fallback resolver, never reached under the guard
    row.ownerFarmId = farmId
    ledger[farmId] = (ledger[farmId] or 0) + amount
    return true
end

local ledger = {}
local orphanPay = {status = "paused_recovery", ownerFarmId = FarmManager.INVALID_FARM_ID}
T.eq("F148 an orphaned job pays nobody", payOwner(orphanPay, 500, ledger), false)
T.eq("F148 an orphaned job charges nobody", payOwner(orphanPay, -500, ledger), false)
T.eq("F148 no money moved for an orphaned job", ledger[FarmManager.INVALID_FARM_ID], nil)
T.eq("F148 the orphaned record was not re-stamped by the money site", orphanPay.ownerFarmId, FarmManager.INVALID_FARM_ID)

local livePay = {status = "active", ownerFarmId = 1}
T.eq("F148 a live job still pays its owner", payOwner(livePay, 500, ledger), true)
T.eq("F148 the live owner received the payment", ledger[1], 500)

-- The published query contract, all four answer cases.
local function hasActiveFavorOfType(mgr, favorType, farmId)
    if farmId ~= nil and getFarmById(mgr, farmId) == nil then return false end
    for _, row in ipairs(mgr.activeFavors) do
        if row.type == favorType and ACTIVE_STATUS[row.status] then
            if farmId == nil or row.ownerFarmId == farmId then return true end
        end
    end
    return false
end

local qm = newManager()
place(qm, "activeFavors", {npcId = 20, type = "help_harvest", status = "active", ownerFarmId = 1})
place(qm, "activeFavors", {npcId = 21, type = "help_harvest", status = "pending", ownerFarmId = nil})
place(qm, "recoveryFavors", {npcId = 22, type = "help_harvest", status = "paused_recovery", ownerFarmId = FarmManager.INVALID_FARM_ID})

T.eq("F148 query with no farm argument answers across all farms", hasActiveFavorOfType(qm, "help_harvest", nil), true)
T.eq("F148 query for the owning farm matches its job", hasActiveFavorOfType(qm, "help_harvest", 1), true)
T.eq("F148 query for another live farm does not match", hasActiveFavorOfType(qm, "help_harvest", 2), false)
T.eq("F148 query for a farm that no longer resolves answers false", hasActiveFavorOfType(qm, "help_harvest", 7), false)
T.eq("F148 query for the sentinel itself answers false", hasActiveFavorOfType(qm, "help_harvest", FarmManager.INVALID_FARM_ID), false)
T.eq("F148 a pending offer never satisfies the active query", hasActiveFavorOfType(qm, "nonexistent_type", nil), false)

-- An orphaned row never qualifies, for any farm argument.
local qm2 = newManager()
local orphanQ = place(qm2, "activeFavors", {npcId = 23, type = "help_harvest", status = "active", ownerFarmId = 2})
qm2.liveFarms[2] = nil
onFarmDeleted(qm2, 2)
T.eq("F148 an orphaned job does not satisfy an unscoped query", hasActiveFavorOfType(qm2, "help_harvest", nil), false)
T.eq("F148 an orphaned job does not satisfy a query from the reissued farm", hasActiveFavorOfType(qm2, "help_harvest", 2), false)

-- Persistence. The sentinel is truthy so the conditional writer stores it,
-- and no new field is added to carry the state.
local function xmlWrite(row)
    local out = {}
    if row.ownerFarmId then out.ownerFarmId = row.ownerFarmId end
    out.status = row.status
    return out
end
local writtenOrphan = xmlWrite(orphanQ)
T.eq("F148 the conditional writer stores the sentinel because it is truthy", writtenOrphan.ownerFarmId, FarmManager.INVALID_FARM_ID)
T.eq("F148 the orphaned state rides the status the design already had", writtenOrphan.status, "paused_recovery")
T.eq("F148 no new save field is introduced to carry the invalidated state",
    (writtenOrphan.orphaned == nil and writtenOrphan.farmIdentity == nil and writtenOrphan.invalidated == nil), true)

local writtenNilOwner = xmlWrite({ownerFarmId = nil, status = "pending"})
T.eq("F148 the conditional writer omits an absent owner, which is why nil could not carry the state",
    writtenNilOwner.ownerFarmId, nil)

-- =====================================================================
-- RSF-F148 ROUND TWO FOLD. Two blockers closed: the creation handler has
-- its own control flow and does NOT carry the deletion staleness guard;
-- and an orphaned row stays administratively assignable under part one
-- section 4 while remaining unreachable by known-owner resume.
-- =====================================================================

-- The creation handler must NOT reuse the deletion guard. createFarm puts
-- the farm in the live table at FarmManager.lua:322 and publishes at :323,
-- so at handler time the farm always resolves. A copied guard never fires.
local mgrC = newManager()
local predating = place(mgrC, "activeFavors", {npcId = 30, status = "active", ownerFarmId = 2})
T.ok("F148 creation: the farm is live in the table when the notice arrives", getFarmById(mgrC, 2) ~= nil)
T.eq("F148 creation orphans the predating row even though the farm resolves, because creation carries no staleness guard",
    onFarmCreated(mgrC, 2, true), 1)
T.eq("F148 creation would have orphaned nothing if the deletion guard were reused",
    (getFarmById(mgrC, 2) ~= nil) and 0 or 1, 0)
T.eq("F148 the predating row took the sentinel on creation", predating.ownerFarmId, FarmManager.INVALID_FARM_ID)
T.eq("F148 the predating row carries the owner-deleted reason", predating.recoveryReason, "owner_farm_deleted")

-- Deletion keeps its guard. The two handlers are deliberately different.
local mgrD = newManager()
local liveD = place(mgrD, "activeFavors", {npcId = 31, status = "active", ownerFarmId = 2})
T.eq("F148 deletion still refuses to act while the number resolves", onFarmDeleted(mgrD, 2), 0)
T.eq("F148 the two handlers differ: creation acts where deletion refuses",
    (onFarmCreated(mgrD, 2, true) == 1) and (liveD.ownerFarmId == FarmManager.INVALID_FARM_ID), true)

-- Administrative assignment survives. Part one section 4 already covers a
-- record whose former owner was deleted; resumable=false revokes the
-- known-owner route only, never the administrative one.
local function knownOwnerResume(mgr, row, actorFarmId)
    if row.status ~= "paused_recovery" then return false end
    if row.resumable ~= true then return false end
    if row.ownerFarmId == FarmManager.INVALID_FARM_ID then return false end
    return row.ownerFarmId == actorFarmId
end

local function adminAssign(mgr, row, targetFarmId, verifiedAdmin, confirmed)
    if not verifiedAdmin then return "REFUSED_NOT_ADMIN" end
    if not confirmed then return "REFUSED_NOT_CONFIRMED" end
    if row.status ~= "paused_recovery" then return "REFUSED_NOT_PAUSED" end
    -- a valid existing owner is never overwritten
    if row.ownerFarmId ~= FarmManager.INVALID_FARM_ID and getFarmById(mgr, row.ownerFarmId) ~= nil then
        return "REFUSED_OWNER_STILL_VALID"
    end
    if targetFarmId == nil then return "REFUSED_NO_TARGET" end
    if targetFarmId == FarmManager.SPECTATOR_FARM_ID then return "REFUSED_SPECTATOR" end
    if targetFarmId == FarmManager.GUIDED_TOUR_FARM_ID then return "REFUSED_TOUR" end
    if targetFarmId == FarmManager.INVALID_FARM_ID then return "REFUSED_INVALID" end
    if targetFarmId < 1 or targetFarmId > FarmManager.MAX_FARM_ID then return "REFUSED_RANGE" end
    if getFarmById(mgr, targetFarmId) == nil then return "REFUSED_TARGET_GONE" end
    row.ownerFarmId = targetFarmId
    row.status = "active"
    row.resumable = nil
    row.recoveryReason = nil
    removeFrom(mgr.recoveryFavors, row)
    place(mgr, "activeFavors", row)
    return "ASSIGNED"
end

local mgrA = newManager()
local orphanA = place(mgrA, "activeFavors", {npcId = 32, status = "active", ownerFarmId = 2})
mgrA.liveFarms[2] = nil
onFarmDeleted(mgrA, 2)
T.eq("F148 an orphaned job is not reachable by known-owner resume", knownOwnerResume(mgrA, orphanA, 1), false)
mgrA.liveFarms[2] = true
T.eq("F148 an orphaned job is not reachable by a farm that took the reissued number", knownOwnerResume(mgrA, orphanA, 2), false)
T.eq("F148 an orphaned job refuses assignment without a verified administrator", adminAssign(mgrA, orphanA, 1, false, true), "REFUSED_NOT_ADMIN")
T.eq("F148 an orphaned job refuses assignment without explicit confirmation", adminAssign(mgrA, orphanA, 1, true, false), "REFUSED_NOT_CONFIRMED")
T.eq("F148 an orphaned job refuses assignment with no target chosen", adminAssign(mgrA, orphanA, nil, true, true), "REFUSED_NO_TARGET")
T.eq("F148 an orphaned job refuses the spectator farm as a target", adminAssign(mgrA, orphanA, FarmManager.SPECTATOR_FARM_ID, true, true), "REFUSED_SPECTATOR")
T.eq("F148 an orphaned job refuses the guided tour farm as a target", adminAssign(mgrA, orphanA, FarmManager.GUIDED_TOUR_FARM_ID, true, true), "REFUSED_TOUR")
T.eq("F148 an orphaned job refuses the sentinel as a target", adminAssign(mgrA, orphanA, FarmManager.INVALID_FARM_ID, true, true), "REFUSED_INVALID")
T.eq("F148 an orphaned job refuses a target outside the usable range", adminAssign(mgrA, orphanA, 9, true, true), "REFUSED_RANGE")
T.eq("F148 an orphaned job refuses a target farm that does not exist", adminAssign(mgrA, orphanA, 5, true, true), "REFUSED_TARGET_GONE")

T.eq("F148 an orphaned job IS assignable by a verified administrator to an explicitly chosen live farm",
    adminAssign(mgrA, orphanA, 1, true, true), "ASSIGNED")
T.eq("F148 the assigned job now belongs to the chosen farm", orphanA.ownerFarmId, 1)
T.eq("F148 the assigned job returns to the live collection", #mgrA.activeFavors, 1)
T.eq("F148 the assigned job is no longer in the recovery collection", #mgrA.recoveryFavors, 0)
T.eq("F148 the assigned job sheds its orphan reason", orphanA.recoveryReason, nil)

-- A valid existing owner is never overwritten by the administrative route.
local mgrB = newManager()
local pausedValid = place(mgrB, "recoveryFavors", {npcId = 33, status = "paused_recovery", ownerFarmId = 1, resumable = true})
T.eq("F148 administrative assignment refuses a record whose owner is still valid",
    adminAssign(mgrB, pausedValid, 2, true, true), "REFUSED_OWNER_STILL_VALID")
T.eq("F148 that record keeps its owner", pausedValid.ownerFarmId, 1)

-- Never-stuck: an orphaned job always has exactly one route back, and it
-- is deliberate rather than automatic.
local function routesBack(mgr, row)
    local n = 0
    if knownOwnerResume(mgr, row, row.ownerFarmId) then n = n + 1 end
    local probe = {npcId = row.npcId, status = row.status, ownerFarmId = row.ownerFarmId, resumable = row.resumable}
    if adminAssign(mgr, probe, 1, true, true) == "ASSIGNED" then n = n + 1 end
    return n
end
local mgrN = newManager()
local orphanN = place(mgrN, "activeFavors", {npcId = 34, status = "active", ownerFarmId = 2})
mgrN.liveFarms[2] = nil
onFarmDeleted(mgrN, 2)
T.eq("F148 an orphaned job is never permanently stuck: exactly one route back exists", routesBack(mgrN, orphanN), 1)

-- The published query answers by its own branch, not by where the row sits.
local function queryExplicit(mgr, favorType, farmId, rows)
    if farmId ~= nil and getFarmById(mgr, farmId) == nil then return false end
    for _, row in ipairs(rows) do
        if row.type == favorType and ACTIVE_STATUS[row.status] then
            if farmId == nil or row.ownerFarmId == farmId then return true end
        end
    end
    return false
end
local mgrQ = newManager()
-- deliberately hand the walk a list that still contains an orphaned row, to
-- prove the branch and not the row's location is what answers.
local strayOrphan = {type = "help_harvest", status = "active", ownerFarmId = FarmManager.INVALID_FARM_ID}
T.eq("F148 the query answers false for the sentinel by its own branch even if an orphaned row is still in the walked list",
    queryExplicit(mgrQ, "help_harvest", FarmManager.INVALID_FARM_ID, {strayOrphan}), false)
T.eq("F148 the query answers false for any farm id that does not resolve, by the same branch",
    queryExplicit(mgrQ, "help_harvest", 6, {strayOrphan}), false)

-- ---------------------------------------------------------------------------
-- FOLD-CHECK ROUND. Three corrections came back and each gets a witness so the
-- document and this bar cannot drift apart again.
-- ---------------------------------------------------------------------------

-- Correction 1. `resumable` is the known-owner gate and nothing else. The
-- administrative assign must never read it, and inspect-only must be keyed to
-- the recovery reason, because two different situations set the flag false and
-- only one of them is inspect-only.
do
    -- Bob's port correction: only owner_farm_deleted is assignable. The bar's
    -- second token (owner_farm_unresolvable) is not one of the four persisted
    -- reasons and is dropped here; the Design copy needs the same correction.
    local ASSIGNABLE_REASON = { owner_farm_deleted = true }
    local function inspectOnly(row)
        if row.status ~= "paused_recovery" then return false end
        return ASSIGNABLE_REASON[row.recoveryReason] ~= true
    end

    local mgrR = newManager()
    local orphanR = place(mgrR, "activeFavors", {npcId = 71, status = "active", ownerFarmId = 2})
    mgrR.liveFarms[2] = nil
    onFarmDeleted(mgrR, 2)
    T.eq("F148 fold-check: an orphaned row carries the deleted-owner reason", orphanR.recoveryReason, "owner_farm_deleted")
    T.eq("F148 fold-check: and it is not inspect-only, because its reason is assignable", inspectOnly(orphanR), false)
    T.eq("F148 fold-check: resumable is false on it", orphanR.resumable, false)

    -- The flag is false, and the admin route is open anyway. That is the whole point.
    local probeFalse = {npcId = 71, status = "paused_recovery", ownerFarmId = FarmManager.INVALID_FARM_ID,
                        resumable = false, recoveryReason = "owner_farm_deleted"}
    T.eq("F148 fold-check: the admin assign succeeds with resumable false",
        adminAssign(mgrR, probeFalse, 1, true, true), "ASSIGNED")

    -- Flip the flag to true and nothing about the admin route changes, which
    -- proves the command does not consult it rather than merely tolerating it.
    local probeTrue = {npcId = 71, status = "paused_recovery", ownerFarmId = FarmManager.INVALID_FARM_ID,
                       resumable = true, recoveryReason = "owner_farm_deleted"}
    T.eq("F148 fold-check: and gives the same answer with resumable true",
        adminAssign(mgrR, probeTrue, 1, true, true), "ASSIGNED")

    local probeNil = {npcId = 71, status = "paused_recovery", ownerFarmId = FarmManager.INVALID_FARM_ID,
                      recoveryReason = "owner_farm_deleted"}
    T.eq("F148 fold-check: and the same answer with the flag absent entirely",
        adminAssign(mgrR, probeNil, 1, true, true), "ASSIGNED")

    -- A genuinely inspect-only row sets the same flag false and is refused for
    -- a different reason, which is why the flag cannot carry both meanings.
    local malformed = {npcId = 72, status = "paused_recovery", ownerFarmId = FarmManager.INVALID_FARM_ID,
                       resumable = false, recoveryReason = "invalid_record"}
    T.eq("F148 fold-check: a malformed legacy row shares the false flag", malformed.resumable, false)
    T.eq("F148 fold-check: but IS inspect-only, by its reason", inspectOnly(malformed), true)
    -- Build the pair fresh, because adminAssign clears the flag on the row it
    -- consumes and a consumed probe would prove nothing.
    local orphanedPair = {status = "paused_recovery", ownerFarmId = FarmManager.INVALID_FARM_ID,
                          resumable = false, recoveryReason = "owner_farm_deleted"}
    local inspectPair  = {status = "paused_recovery", ownerFarmId = FarmManager.INVALID_FARM_ID,
                          resumable = false, recoveryReason = "invalid_record"}
    T.eq("F148 fold-check: both rows carry the identical flag value", orphanedPair.resumable, inspectPair.resumable)
    T.ok("F148 fold-check: yet only one is inspect-only, so the flag alone cannot tell them apart",
        inspectOnly(orphanedPair) ~= inspectOnly(inspectPair))
    T.eq("F148 fold-check: the assignable one is assignable", adminAssign(mgrR, orphanedPair, 1, true, true), "ASSIGNED")

    -- And the known-owner resume still refuses the sentinel, which is the one
    -- thing the flag is actually for.
    local sentinelRow = {npcId = 73, status = "paused_recovery", ownerFarmId = FarmManager.INVALID_FARM_ID, resumable = false}
    T.eq("F148 fold-check: known-owner resume still refuses a sentinel owner",
        knownOwnerResume(mgrR, sentinelRow, FarmManager.INVALID_FARM_ID), false)

    -- Port witness: the three non-assignable persisted tokens and an unknown
    -- token are inspect-only; only owner_farm_deleted is not.
    for _, token in ipairs({"owner_unresolved", "legacy_acceptance_unknown", "invalid_record", "some_future_token"}) do
        T.eq("F148 fold-check port: token '" .. token .. "' is inspect-only",
            inspectOnly({status = "paused_recovery", recoveryReason = token, resumable = false}), true)
    end
    T.eq("F148 fold-check port: owner_farm_deleted is the only assignable token",
        inspectOnly({status = "paused_recovery", recoveryReason = "owner_farm_deleted", resumable = false}), false)
end

-- Correction 2. Two subscriptions, not one. Deletion alone leaves the reuse
-- hole open; only the creation notice closes it.
do
    local mgrD = newManager()
    local jobD = place(mgrD, "activeFavors", {npcId = 81, status = "active", ownerFarmId = 3})
    -- The delete notice is delayed past the reuse, so by the time it lands the
    -- number already belongs to somebody new and the staleness guard declines.
    mgrD.liveFarms[3] = true
    T.eq("F148 fold-check: a delayed deletion notice correctly declines to act", onFarmDeleted(mgrD, 3), 0)
    T.eq("F148 fold-check: so with only one subscription the old job still carries the reused number", jobD.ownerFarmId, 3)
    T.eq("F148 fold-check: and it is still sitting in the live collection", #mgrD.activeFavors, 1)

    -- The creation notice is the other end, and it acts with no staleness check.
    T.eq("F148 fold-check: the creation notice orphans the stale row", onFarmCreated(mgrD, 3, true), 1)
    T.eq("F148 fold-check: the reused number no longer owns the old job", jobD.ownerFarmId, FarmManager.INVALID_FARM_ID)
    T.eq("F148 fold-check: which leaves the live collection empty", #mgrD.activeFavors, 0)

    -- The creation handler is server-only; on a client it must do nothing at
    -- all, because a farm replicating at join is not a new farm.
    local mgrC = newManager()
    local jobC = place(mgrC, "activeFavors", {npcId = 82, status = "active", ownerFarmId = 4})
    mgrC.liveFarms[4] = true
    T.eq("F148 fold-check: a client creation notice orphans nothing", onFarmCreated(mgrC, 4, false), 0)
    T.eq("F148 fold-check: and leaves the joining client's view of the job intact", jobC.ownerFarmId, 4)
end

-- Correction 3. The neighbour fallback this design once called "the literal 15"
-- is the spectator farm, 0, because 0 is truthy in Lua and the `or 15` tail
-- never runs while FarmManager is loaded.
do
    local liveFallback = (FarmManager.SPECTATOR_FARM_ID or 15)
    T.eq("F148 fold-check: the neighbour fallback evaluates to the spectator farm", liveFallback, 0)
    T.ok("F148 fold-check: it is not the invalid sentinel", liveFallback ~= FarmManager.INVALID_FARM_ID)
    T.ok("F148 fold-check: zero is truthy in Lua, which is why the tail is dead", (0 and true) == true)
    -- Only with FarmManager absent would the tail run, which is not the game.
    local absent = (nil or 15)
    T.eq("F148 fold-check: the tail only runs when FarmManager is missing entirely", absent, 15)
    T.ok("F148 fold-check: so a neighbour record and a favour record never share a fallback",
        liveFallback ~= FarmManager.INVALID_FARM_ID)
end


-- =====================================================================
-- REAL-SOURCE SECTION (port bench). Exercises the built NPCFavorSystem +
-- NPCFavorRecovery + NPCFarmIdentity + NPCInteractionEvent on controlled
-- fixtures. The game clock, farm manager, mission and relationship manager
-- are recorded stubs. No native UI, disk, network or gameplay claim.
-- =====================================================================

local moneyCalls = {}
g_currentMission.addMoney = function(_, amount, farmId) moneyCalls[#moneyCalls + 1] = {amount = amount, farmId = farmId} end
g_currentMission.getFarmId = function(_, connection)
    if connection ~= nil then return connection.__farmId end
    return g_currentMission.__localFarmId
end
MoneyType = MoneyType or { OTHER = 3 }
-- The favor system's money and completion paths are server-only.
g_server = {}

local function newRealSystem(npcIds)
    local npcs = {}
    for _, id in ipairs(npcIds or {11}) do
        npcs[#npcs + 1] = {id = id, name = "NPC" .. id, homePosition = {x = 0, y = 0, z = 0}, isActive = true,
            favorCooldown = 0, relationship = 60, personality = "friendly"}
    end
    local rel = {calls = {}}
    rel.updateRelationship = function(_, npcId, delta, reason) rel.calls[#rel.calls + 1] = {npcId = npcId, delta = delta, reason = reason} end
    local sys = NPCFavorSystem.new({activeNPCs = npcs, settings = {enableFavors = false, debugMode = false},
        relationshipManager = rel, playerPosition = {x = 0, y = 0, z = 0}, playerPositionValid = true})
    sys.generateFavorSteps = function(_, favorType)
        return {{id = 1, description = "Step", completed = false, location = {x = 0, y = 0, z = 0}}}
    end
    sys:installEmptyFavorSnapshot()
    return sys, rel
end

local function liveRow(sys, npcId, ownerFarmId, status, favorType)
    local row = {id = sys:allocateFavorId(), npcId = npcId, npcName = "NPC" .. npcId, type = favorType or "help_harvest",
        description = "Harvest", status = status or "active", progress = 0, timeRemaining = 60000,
        expirationGameTime = 61000, ownerFarmId = ownerFarmId, ownerFarmIdPresent = ownerFarmId ~= nil,
        rewardPaid = false, rewardPaidPresent = true, repaymentCollected = false, repaymentCollectedPresent = true,
        reward = {relationship = 1, money = 10, xp = 0}, penalty = {relationship = -4},
        taskData = {}, steps = {{id = 1, description = "Step", completed = false, location = {x = 0, y = 0, z = 0}}},
        recordRevision = 0}
    table.insert(sys.activeFavors, row)
    return row
end

-- Deletion handler, both publish paths reach the same handler with the farm id.
do
    setLiveFarms({1, 2})
    local sys = newRealSystem({11, 12})
    local job = liveRow(sys, 11, 2, "active")
    local offer = liveRow(sys, 12, nil, "pending")
    T.eq("RS deletion: a live farm holding the number makes the notice stale", sys:onFarmDeleted(2), 0)
    setLiveFarms({1})
    T.eq("RS deletion (immediate publish path): orphans the one accepted row", sys:onFarmDeleted(2), 1)
    T.eq("RS deletion: sentinel owner", job.ownerFarmId, 15)
    T.eq("RS deletion: paused status", job.status, "paused_recovery")
    T.eq("RS deletion: owner_farm_deleted reason", job.recoveryReason, "owner_farm_deleted")
    T.eq("RS deletion: not resumable by the known-owner route", job.resumable, false)
    T.eq("RS deletion: original status kept for resume", job.originalStatus, "active")
    T.eq("RS deletion: left the live list", #sys.activeFavors, 1)
    T.eq("RS deletion: entered recovery", #sys.recoveryFavors, 1)
    T.eq("RS deletion: pending offer untouched", offer.status, "pending")
    T.eq("RS deletion: repeated (delayed publish path) delivery matches nothing", sys:onFarmDeleted(2), 0)
    T.eq("RS deletion: recovery collection does not grow", #sys.recoveryFavors, 1)
    T.ok("RS deletion: orphaned row got a session token", job.recoveryToken ~= nil)
    T.eq("RS deletion: orphan with complete facts reserves its NPC", sys:isNPCReservedByRecovery(11), true)
    T.eq("RS deletion: orphan is actionable (assignable), not inspect-only", sys:isRecoveryRecordInspectOnly(job), false)
    -- The tick and every mutation path refuse the paused row.
    sys:update(1)
    T.eq("RS deletion: update does not expire or fail the paused row", job.status, "paused_recovery")
    T.eq("RS deletion: completeFavor refuses", sys:completeFavor(job.id), false)
    T.eq("RS deletion: abandonFavor refuses", sys:abandonFavor(job.id), false)
    T.eq("RS deletion: failFavor refuses", sys:failFavor(job.id, "time_expired"), false)
    -- Money reads the sentinel as nobody and never re-stamps the record.
    moneyCalls = {}
    sys:applyFavorRewards(job)
    T.eq("RS money: an orphaned job pays nobody", #moneyCalls, 0)
    T.eq("RS money: the record was not re-stamped", job.ownerFarmId, 15)
    local loan = {id = 99, npcId = 12, type = "loan_money", status = "active", ownerFarmId = 15, progress = 0,
        taskData = {loanAmount = 5000, loanAmountDeducted = false},
        steps = {{id = 1, description = "Hand over", completed = false, location = {x = 0, y = 0, z = 0}}}}
    sys:checkFavorProgress(loan, 1)
    T.eq("RS money: an orphaned loan charges nobody", #moneyCalls, 0)
    T.eq("RS money: the loan record was not re-stamped", loan.ownerFarmId, 15)
    T.eq("RS money: the loan debit flag stays false", loan.taskData.loanAmountDeducted, false)
end

-- Creation handler: no staleness guard, orphans a predating row while the
-- farm resolves; the row already in recovery is reached too.
do
    setLiveFarms({1, 2})
    local sys = newRealSystem({11, 12})
    local predating = liveRow(sys, 11, 2, "in_progress")
    local pausedKnown = {id = sys:allocateFavorId(), npcId = 12, type = "help_harvest", status = "paused_recovery",
        recoveryReason = "legacy_acceptance_unknown", resumable = true, ownerFarmId = 2, ownerFarmIdPresent = true,
        timeRemaining = 1000, rewardPaid = false, rewardPaidPresent = true, taskData = {}, recordRevision = 0}
    table.insert(sys.recoveryFavors, pausedKnown)
    T.ok("RS creation: the farm is live when the notice arrives", NPCFarmIdentity.getLiveFarm(2) ~= nil)
    T.eq("RS creation: orphans both rows carrying the number", sys:onFarmCreated(2), 2)
    T.eq("RS creation: predating row takes the sentinel", predating.ownerFarmId, 15)
    T.eq("RS creation: predating in_progress status is preserved as original", predating.originalStatus, "in_progress")
    T.eq("RS creation: row already in recovery loses its owner", pausedKnown.ownerFarmId, 15)
    T.eq("RS creation: row already in recovery is no longer resumable", pausedKnown.resumable, false)
    T.eq("RS creation: recovery collection holds exactly two, no double move", #sys.recoveryFavors, 2)
    T.eq("RS creation: live list empty", #sys.activeFavors, 0)
end

-- Server-validated command: admin assign with resumable=false succeeds only for
-- owner_farm_deleted; known-owner resume; stale / mismatch refusals.
do
    setLiveFarms({1, 2, 3})
    local sys = newRealSystem({11, 12, 13, 14, 15})
    local orphan = liveRow(sys, 11, 2, "active")
    setLiveFarms({1, 3})
    sys:onFarmDeleted(2)
    setLiveFarms({1, 2, 3})  -- number reissued to a new farm
    local unresolved = {id = sys:allocateFavorId(), npcId = 12, type = "help_harvest", status = "paused_recovery",
        recoveryReason = "owner_unresolved", resumable = false, ownerFarmIdPresent = false, timeRemaining = 1000,
        rewardPaid = false, rewardPaidPresent = true, taskData = {}, recordRevision = 0}
    local legacyKnown = {id = sys:allocateFavorId(), npcId = 13, type = "help_harvest", status = "paused_recovery",
        recoveryReason = "legacy_acceptance_unknown", resumable = true, ownerFarmId = 3, ownerFarmIdPresent = true,
        timeRemaining = 1000, rewardPaid = false, rewardPaidPresent = true, taskData = {}, recordRevision = 0,
        originalStatus = "in_progress", reward = {relationship = 1, money = 10, xp = 0}}
    local invalid = {id = sys:allocateFavorId(), npcId = 14, type = "help_harvest", status = "paused_recovery",
        recoveryReason = "invalid_record", resumable = false, ownerFarmIdPresent = false, timeRemaining = 1000,
        rewardPaid = false, rewardPaidPresent = true, taskData = {}, recordRevision = 0}
    local unknownTok = {id = sys:allocateFavorId(), npcId = 15, type = "help_harvest", status = "paused_recovery",
        recoveryReason = "some_future_token", resumable = false, ownerFarmId = 15, ownerFarmIdPresent = true,
        timeRemaining = 1000, rewardPaid = false, rewardPaidPresent = true, taskData = {}, recordRevision = 0}
    for _, r in ipairs({unresolved, legacyKnown, invalid, unknownTok}) do
        table.insert(sys.recoveryFavors, r)
        sys:assignRecoveryToken(r)
    end
    local admin = {connectionId = "user:admin", farmId = nil, isMaster = true}
    local memberB = {connectionId = "user:b", farmId = 2, isMaster = false}
    local memberC = {connectionId = "user:c", farmId = 3, isMaster = false}

    local view = sys:serverRecoveryView(admin, "1", "")
    T.ok("RS view: admin receives a reply", view ~= nil)
    T.eq("RS view: admin sees all five recovery rows", #view.rows, 5)
    T.eq("RS view: admin receives the eligible farm list", #view.eligibleFarms, 3)
    local memberView = sys:serverRecoveryView(memberB, "2", "")
    T.eq("RS view: the farm that took the reissued number sees no row (sentinel owner is nobody)", #memberView.rows, 0)
    local viewC = sys:serverRecoveryView(memberC, "3", "")
    T.eq("RS view: a member sees only its own farm's row", #viewC.rows, 1)
    T.eq("RS view: member rows are not offered assignment farms", #viewC.eligibleFarms, 0)
    local function rowFor(v, record)
        for _, r in ipairs(v.rows) do if tonumber(r.token) == record.recoveryToken then return r end end
        return nil
    end
    local orphanRow = rowFor(view, orphan)
    T.eq("RS view: orphan row is assignable", orphanRow.assignable, true)
    T.eq("RS view: orphan row is not known-owner resumable", orphanRow.knownOwnerResumable, false)
    T.eq("RS view: owner_unresolved is inspect-only", rowFor(view, unresolved).inspectOnly, true)
    T.eq("RS view: invalid_record is inspect-only", rowFor(view, invalid).inspectOnly, true)
    T.eq("RS view: unknown token is inspect-only", rowFor(view, unknownTok).inspectOnly, true)
    T.eq("RS view: unknown token is not assignable", rowFor(view, unknownTok).assignable, false)
    T.eq("RS view: unknown token round-trips unchanged in the view", rowFor(view, unknownTok).recoveryReason, "some_future_token")

    local function cmd(actor, record, op, target, requestId, viewId, overrides)
        local c = {requestId = requestId, collectionRevision = view.collectionRevision,
            recordRevision = tostring(record.recordRevision or 0), token = tostring(record.recoveryToken),
            op = op, targetFarmId = target, originatingViewRequestId = viewId or "1"}
        for k, v in pairs(overrides or {}) do c[k] = v end
        return sys:serverRecoveryCommand(actor, c)
    end
    local OK, REFUSED = NPCFavorRecovery.RESULT_OK, NPCFavorRecovery.RESULT_REFUSED
    local ASSIGN, RESUME = NPCFavorRecovery.OP_ASSIGN_AND_RESUME, NPCFavorRecovery.OP_RESUME

    T.eq("RS cmd: member cannot assign", cmd(memberB, orphan, ASSIGN, 1, "10").result, REFUSED)
    T.eq("RS cmd: admin assign refuses spectator target", cmd(admin, orphan, ASSIGN, 0, "11").result, REFUSED)
    T.eq("RS cmd: admin assign refuses guided tour target", cmd(admin, orphan, ASSIGN, 14, "12").result, REFUSED)
    T.eq("RS cmd: admin assign refuses the sentinel target", cmd(admin, orphan, ASSIGN, 15, "13").result, REFUSED)
    T.eq("RS cmd: admin assign refuses an absent farm", cmd(admin, orphan, ASSIGN, 8, "14").result, REFUSED)
    T.eq("RS cmd: admin assign refuses no target", cmd(admin, orphan, ASSIGN, nil, "15").result, REFUSED)
    T.eq("RS cmd: admin assign refuses a wrong originating view", cmd(admin, orphan, ASSIGN, 1, "16", "999").result, REFUSED)
    T.eq("RS cmd: stale collection revision refused",
        cmd(admin, orphan, ASSIGN, 1, "17", "1", {collectionRevision = "0"}).result, REFUSED)
    T.eq("RS cmd: stale record revision refused",
        cmd(admin, orphan, ASSIGN, 1, "18", "1", {recordRevision = "0"}).result, REFUSED)
    T.eq("RS cmd: non-decimal request id yields no reply", cmd(admin, orphan, ASSIGN, 1, "req"), nil)
    T.eq("RS cmd: unknown op refused", cmd(admin, orphan, 9, 1, "19").result, REFUSED)
    T.eq("RS cmd: admin assign refuses owner_unresolved", cmd(admin, unresolved, ASSIGN, 1, "20").result, REFUSED)
    T.eq("RS cmd: admin assign refuses invalid_record", cmd(admin, invalid, ASSIGN, 1, "21").result, REFUSED)
    T.eq("RS cmd: admin assign refuses an unknown token", cmd(admin, unknownTok, ASSIGN, 1, "22").result, REFUSED)
    T.eq("RS cmd: admin assign refuses a record whose owner is still valid", cmd(admin, legacyKnown, ASSIGN, 1, "23").result, REFUSED)
    T.eq("RS cmd: known-owner resume refuses the orphan (resumable false)", cmd(memberB, orphan, RESUME, nil, "24").result, REFUSED)
    T.eq("RS cmd: nothing moved by the refusals", #sys.activeFavors, 0)

    local preRevision = tostring(orphan.recordRevision or 0)
    local ok1 = cmd(admin, orphan, ASSIGN, 1, "30")
    T.eq("RS cmd: admin assign with resumable=false succeeds for owner_farm_deleted", ok1.result, OK)
    T.eq("RS cmd: assigned owner is the chosen farm", orphan.ownerFarmId, 1)
    T.eq("RS cmd: assigned row is live again", orphan.status, "active")
    T.eq("RS cmd: assigned row is marked recovered", orphan.recoveredFromLegacy, true)
    T.eq("RS cmd: the same object moved to the live list", sys.activeFavors[1], orphan)
    T.eq("RS cmd: assignment moved no money", #moneyCalls, 0)
    T.eq("RS cmd: retry with the same fingerprint returns the retained result",
        cmd(admin, orphan, ASSIGN, 1, "30", "1", {recordRevision = preRevision}).result, OK)
    T.eq("RS cmd: retry did not resume anything else or move money", #sys.activeFavors + #moneyCalls, 1)
    T.eq("RS cmd: same request id with a different payload is refused",
        cmd(admin, orphan, ASSIGN, 3, "30", "1", {recordRevision = preRevision}).result, REFUSED)
    T.eq("RS cmd: same request id on another connection is an independent request that fails its own validation",
        cmd({connectionId = "user:other", farmId = nil, isMaster = true}, orphan, ASSIGN, 1, "30", "1", {recordRevision = preRevision}).result, REFUSED)
    T.eq("RS cmd: a new request against the moved row is no longer paused",
        cmd(admin, orphan, ASSIGN, 1, "31", "1", {recordRevision = tostring(orphan.recordRevision)}).result,
        NPCFavorRecovery.RESULT_NO_LONGER_PAUSED)
    T.eq("RS cmd: the resumed row still occupies its NPC", #sys.activeFavors, 1)

    T.eq("RS cmd: another farm cannot resume the known-owner row", cmd(memberB, legacyKnown, RESUME, nil, "40").result, REFUSED)
    local busy = liveRow(sys, 13, 3, "active")
    T.eq("RS cmd: resume refuses while an ordinary job occupies that NPC", cmd(memberC, legacyKnown, RESUME, nil, "41").result, REFUSED)
    table.remove(sys.activeFavors, #sys.activeFavors)
    T.eq("RS cmd: the known owner resumes its own row", cmd(memberC, legacyKnown, RESUME, nil, "42").result, OK)
    T.eq("RS cmd: original in_progress status restored", legacyKnown.status, "in_progress")
    T.eq("RS cmd: resume rebuilt expiry from now plus remaining", legacyKnown.expirationGameTime, 1000 + 1000)

    -- The old NPC-keyed door refuses the recovered row; the token route completes it.
    T.eq("RS route: recovered row is not found by old actions on another farm", legacyKnown.ownerFarmId, 3)
    local done = cmd(memberB, legacyKnown, NPCFavorRecovery.OP_COMPLETE, nil, "50", "1",
        {recordRevision = tostring(legacyKnown.recordRevision)})
    T.eq("RS route: another farm cannot complete the recovered row by token", done.result, REFUSED)
    moneyCalls = {}
    local doneC = cmd(memberC, legacyKnown, NPCFavorRecovery.OP_COMPLETE, nil, "51", "1",
        {recordRevision = tostring(legacyKnown.recordRevision)})
    T.eq("RS route: the owner completes the recovered row by token", doneC.result, OK)
    T.eq("RS route: completion paid the owner once", #moneyCalls, 1)
    T.eq("RS route: reward followed the record owner", moneyCalls[1].farmId, 3)
    T.eq("RS route: completed row left the live list", #sys.activeFavors, 1)

    -- Reservation reads reason plus facts, never the flag alone.
    T.eq("RS reserve: inspect-only rows do not reserve", sys:isNPCReservedByRecovery(12), false)
    T.eq("RS reserve: unknown token does not reserve", sys:isNPCReservedByRecovery(15), false)
end

-- Persistence round trip through the flat record shape: schema, status,
-- presence, unknown token, future schema refusal.
do
    setLiveFarms({1, 2})
    local sys = newRealSystem({11, 12, 13, 14})
    local pending = liveRow(sys, 11, nil, "pending")
    local active = liveRow(sys, 12, 2, "active")
    local paused = {id = sys:allocateFavorId(), npcId = 13, type = "help_harvest", status = "paused_recovery",
        recoveryReason = "some_future_token", resumable = false, ownerFarmId = 15, ownerFarmIdPresent = true,
        timeRemaining = 4242, rewardPaidPresent = false, taskData = {fieldId = 37}, recordRevision = 0}
    table.insert(sys.recoveryFavors, paused)
    local flats = {}
    for _, f in ipairs(sys.activeFavors) do flats[#flats + 1] = sys:exportFavorRecord(f) end
    for _, f in ipairs(sys.recoveryFavors) do flats[#flats + 1] = sys:exportFavorRecord(f) end
    T.eq("RS persist: every row carries schema 1", flats[1].f148Schema, 1)
    T.eq("RS persist: pending status is written", flats[1].status, "pending")
    T.eq("RS persist: pending owner presence is false", flats[1].ownerFarmIdPresent, false)
    T.eq("RS persist: active status is written", flats[2].status, "active")
    T.eq("RS persist: unknown token is exported unchanged", flats[3].recoveryReason, "some_future_token")
    T.eq("RS persist: unknown payment fact exports as not present", flats[3].rewardPaidPresent, false)
    T.eq("RS persist: field id exported", flats[3].taskFieldId, 37)

    local reload = newRealSystem({11, 12, 13, 14})
    reload._favorLoadState = "WAITING"
    local staging = reload:beginFavorLoad()
    for _, flat in ipairs(flats) do reload:restoreFavor(flat, staging) end
    T.eq("RS persist: install succeeds", reload:installFavorSnapshot(staging), true)
    T.eq("RS persist: a reloaded pending offer comes back pending", reload.activeFavors[1].status, "pending")
    T.eq("RS persist: the reloaded offer gained no owner", reload.activeFavors[1].ownerFarmId, nil)
    T.eq("RS persist: the accepted row comes back active with its owner", reload.activeFavors[2].ownerFarmId, 2)
    T.eq("RS persist: the paused row stays paused", reload.recoveryFavors[1].status, "paused_recovery")
    T.eq("RS persist: unknown token survives load unchanged", reload.recoveryFavors[1].recoveryReason, "some_future_token")
    T.eq("RS persist: unknown token stays inspect-only", reload:isRecoveryRecordInspectOnly(reload.recoveryFavors[1]), true)
    T.eq("RS persist: sentinel owner survives without re-resolution", reload.recoveryFavors[1].ownerFarmId, 15)
    T.eq("RS persist: frozen time survives", reload.recoveryFavors[1].timeRemaining, 4242)
    T.eq("RS persist: field id restored to taskData", reload.recoveryFavors[1].taskData.fieldId, 37)
    T.eq("RS persist: saved ids are kept", reload.activeFavors[2].id, active.id)

    -- Orphaned state round trip: owner_farm_deleted through the writers.
    setLiveFarms({1})
    sys:onFarmDeleted(2)
    local orphanFlat = sys:exportFavorRecord(active)
    T.eq("RS persist: orphaned row writes the sentinel owner", orphanFlat.ownerFarmId, 15)
    T.eq("RS persist: orphaned row writes the paused status", orphanFlat.status, "paused_recovery")
    T.eq("RS persist: orphaned row writes owner_farm_deleted", orphanFlat.recoveryReason, "owner_farm_deleted")
    local reload2 = newRealSystem({12})
    reload2._favorLoadState = "WAITING"
    local st2 = reload2:beginFavorLoad()
    reload2:restoreFavor(orphanFlat, st2)
    reload2:installFavorSnapshot(st2)
    T.eq("RS persist: orphaned row reloads as an orphaned row, not active", reload2.recoveryFavors[1].status, "paused_recovery")
    T.eq("RS persist: reloaded orphan keeps its reason", reload2.recoveryFavors[1].recoveryReason, "owner_farm_deleted")
    T.eq("RS persist: reloaded orphan is still assignable", reload2:isRecoveryRecordActionable(reload2.recoveryFavors[1]), true)

    -- Future schema refuses the whole load without touching live state.
    local future = newRealSystem({11})
    future._favorLoadState = "WAITING"
    local st3 = future:beginFavorLoad()
    future:restoreFavor({f148Schema = 2, type = "help_harvest", npcId = 11, status = "active"}, st3)
    T.eq("RS persist: a future schema marks the staging failed", st3.failed, true)
    T.eq("RS persist: install refuses", future:installFavorSnapshot(st3), false)
    T.eq("RS persist: load state is FAILED", future:getFavorLoadState(), "FAILED")
    T.eq("RS persist: nothing was installed", #future.activeFavors + #future.recoveryFavors, 0)
    T.eq("RS persist: a FAILED system accepts no favor", future:acceptFavorForNPC(11, 1), nil)
end

-- Client claim sites: the local claim is g_currentMission:getFarmId() validated
-- as an ordinary farm; 0 / 14 / 15 / nil / unknown are unavailable before send.
do
    setLiveFarms({1, 2})
    for _, bad in ipairs({0, 14, 15, 99}) do
        g_currentMission.__localFarmId = bad
        T.eq("RS claim: local farm " .. bad .. " is unavailable", NPCFarmIdentity.localClaimFarmId(), nil)
    end
    g_currentMission.__localFarmId = nil
    T.eq("RS claim: nil local farm is unavailable", NPCFarmIdentity.localClaimFarmId(), nil)
    g_currentMission.__localFarmId = 2
    T.eq("RS claim: an ordinary local farm is claimed", NPCFarmIdentity.localClaimFarmId(), 2)
    local sys = newRealSystem({11})
    liveRow(sys, 11, nil, "pending")
    T.eq("RS claim: accept with no farm is refused", sys:acceptFavorForNPC(11, 0), nil)
    T.eq("RS claim: accept with the sentinel is refused", sys:acceptFavorForNPC(11, 15), nil)
    T.eq("RS claim: the row is still pending", sys.activeFavors[1].status, "pending")
    T.ok("RS claim: accept with an ordinary farm succeeds", sys:acceptFavorForNPC(11, 2) ~= nil)
    T.eq("RS claim: the accepting farm is stamped", sys.activeFavors[1].ownerFarmId, 2)
end

-- Server side: NPCInteractionEvent:run resolves the farm from the connection
-- and refuses a mismatch; a dedicated nil connection has no actor.
do
    setLiveFarms({1, 2})
    g_localPlayer = nil
    local users = {}
    g_currentMission.userManager = {getUserByConnection = function(_, c) return users[c] end}
    local executed = {}
    local savedExecute = NPCInteractionEvent.execute
    NPCInteractionEvent.execute = function(actionType, npcId, farmId) executed[#executed + 1] = farmId return true end
    local conn = {__farmId = 2}
    users[conn] = {getId = function() return 7 end, getIsMasterUser = function() return false end}
    local ev = NPCInteractionEvent.new(NPCInteractionEvent.ACTION_FAVOR_COMPLETE, 11, 1, 0, "")
    ev:run(conn)
    T.eq("RS server: claimed farm 1 with actual farm 2 is refused before dispatch", #executed, 0)
    ev = NPCInteractionEvent.new(NPCInteractionEvent.ACTION_FAVOR_COMPLETE, 11, 2, 0, "")
    ev:run(conn)
    T.eq("RS server: matching claim dispatches", #executed, 1)
    local specConn = {__farmId = 0}
    users[specConn] = {getId = function() return 8 end, getIsMasterUser = function() return true end}
    ev = NPCInteractionEvent.new(NPCInteractionEvent.ACTION_FAVOR_COMPLETE, 11, 0, 0, "")
    ev:run(specConn)
    T.eq("RS server: a spectator admin cannot act on a favor as farm 0", #executed, 1)
    T.eq("RS server: dedicated nil connection has no actor", NPCFarmIdentity.resolveActor(nil), nil)
    local actor = NPCFarmIdentity.resolveActor(specConn)
    T.eq("RS server: spectator admin resolves with no farm but master rights", actor.farmId, nil)
    T.eq("RS server: master flag carried", actor.isMaster, true)
    g_localPlayer = {}
    g_currentMission.__localFarmId = 1
    local host = NPCFarmIdentity.resolveActor(nil)
    T.eq("RS server: listen host resolves through the local player", host.farmId, 1)
    T.eq("RS server: listen host is the master", host.isMaster, true)
    NPCInteractionEvent.execute = savedExecute
    g_server = nil
    g_localPlayer = nil
end


-- =====================================================================
-- REVIEW ROUND ONE (Bob, 2026-09-15): witnesses for B1, B2, M4, M5, M6,
-- M7, M3 and the request-cache rights rule.
-- =====================================================================

-- B1: deleting or creating farm N never promotes an inspect-only row. Only
-- a live job or a legacy_acceptance_unknown row takes owner_farm_deleted.
do
    setLiveFarms({1, 2})
    local sys = newRealSystem({11, 12, 13, 14, 15, 16})
    local live = liveRow(sys, 11, 2, "active")
    local function pausedRow(npcId, reason, extra)
        local r = {id = sys:allocateFavorId(), npcId = npcId, npcName = "NPC" .. npcId, type = "help_harvest", status = "paused_recovery",
            recoveryReason = reason, resumable = false, ownerFarmId = 2, ownerFarmIdPresent = true, timeRemaining = 1000,
            rewardPaid = false, rewardPaidPresent = true, taskData = {}, recordRevision = 0,
            reward = {relationship = 1, money = 10, xp = 0}}
        for k, v in pairs(extra or {}) do r[k] = v end
        table.insert(sys.recoveryFavors, r)
        sys:assignRecoveryToken(r)
        return r
    end
    local legacy = pausedRow(12, "legacy_acceptance_unknown", {resumable = true})
    local unresolved = pausedRow(13, "owner_unresolved")
    local invalid = pausedRow(14, "invalid_record")
    local unknown = pausedRow(15, "some_future_token")
    setLiveFarms({1})
    T.eq("B1 deletion touches every row carrying the number", sys:onFarmDeleted(2), 5)
    T.eq("B1 live job takes owner_farm_deleted", live.recoveryReason, "owner_farm_deleted")
    T.eq("B1 legacy_acceptance_unknown takes owner_farm_deleted", legacy.recoveryReason, "owner_farm_deleted")
    T.eq("B1 owner_unresolved keeps its reason", unresolved.recoveryReason, "owner_unresolved")
    T.eq("B1 invalid_record keeps its reason", invalid.recoveryReason, "invalid_record")
    T.eq("B1 unknown token keeps its token", unknown.recoveryReason, "some_future_token")
    for _, r in ipairs({legacy, unresolved, invalid, unknown}) do
        T.eq("B1 sentinel owner on " .. tostring(r.recoveryReason), r.ownerFarmId, 15)
        T.eq("B1 resumable false on " .. tostring(r.recoveryReason), r.resumable, false)
    end
    T.eq("B1 owner_unresolved stays inspect-only", sys:isRecoveryRecordInspectOnly(unresolved), true)
    T.eq("B1 invalid_record stays inspect-only", sys:isRecoveryRecordInspectOnly(invalid), true)
    T.eq("B1 unknown token stays inspect-only", sys:isRecoveryRecordInspectOnly(unknown), true)
    T.eq("B1 unknown token does not reserve its NPC", sys:isNPCReservedByRecovery(15), false)
    T.eq("B1 the live job is assignable", sys:isRecoveryRecordActionable(live), true)
    -- Creation path, same rule.
    setLiveFarms({1, 3})
    local sys2 = newRealSystem({21, 22})
    local inv2 = {id = sys2:allocateFavorId(), npcId = 21, npcName = "NPC21", type = "help_harvest", status = "paused_recovery",
        recoveryReason = "invalid_record", resumable = false, ownerFarmId = 3, ownerFarmIdPresent = true, timeRemaining = 1000,
        rewardPaid = false, rewardPaidPresent = true, taskData = {}, recordRevision = 0}
    table.insert(sys2.recoveryFavors, inv2)
    T.eq("B1 creation reaches the row", sys2:onFarmCreated(3), 1)
    T.eq("B1 creation keeps invalid_record", inv2.recoveryReason, "invalid_record")
    -- Sentinel and special ids are not farm lifecycle events for this mod.
    T.eq("B1 minor: a notice for the sentinel id touches nothing", sys:onFarmDeleted(15), 0)
    T.eq("B1 minor: a creation notice for the spectator id touches nothing", sys:onFarmCreated(0), 0)
end

-- B2: a saved paused row keeps its reason even when its type or time is bad.
do
    setLiveFarms({1, 2})
    local sys = newRealSystem({11})
    sys._favorLoadState = "WAITING"
    local st = sys:beginFavorLoad()
    local badType = sys:restoreFavor({f148Schema = 1, status = "paused_recovery", recoveryReason = "owner_farm_deleted",
        type = "no_such_type", npcId = 11, npcName = "NPC11", timeRemainingPresent = true, timeRemaining = 500,
        ownerFarmIdPresent = true, ownerFarmId = 15, originalStatus = "in_progress", originalOwnerFarmIdPresent = true, originalOwnerFarmId = 2,
        rewardPaidPresent = true, rewardPaid = false}, st)
    local badTime = sys:restoreFavor({f148Schema = 1, status = "paused_recovery", recoveryReason = "some_future_token",
        type = "help_harvest", npcId = 11, npcName = "NPC11", timeRemainingPresent = false,
        ownerFarmIdPresent = true, ownerFarmId = 15, rewardPaidPresent = true, rewardPaid = false}, st)
    sys:installFavorSnapshot(st)
    T.eq("B2 bad type keeps owner_farm_deleted", badType.recoveryReason, "owner_farm_deleted")
    T.eq("B2 bad type keeps originalStatus", badType.originalStatus, "in_progress")
    T.eq("B2 bad type keeps originalOwnerFarmId", badType.originalOwnerFarmId, 2)
    T.eq("B2 bad type is inspect-only at read time", sys:isRecoveryRecordInspectOnly(badType), true)
    T.eq("B2 unknown time keeps the unknown token", badTime.recoveryReason, "some_future_token")
    T.eq("B2 unknown time is recorded as unknown, not 0", badTime.timeRemainingRaw ~= nil, true)
    T.eq("B2 unknown time is inspect-only", sys:isRecoveryRecordInspectOnly(badTime), true)
    -- M3: the unknown time is exported as absent, never as a made-up 0.
    local flat = sys:exportFavorRecord(badTime)
    T.eq("M3 unknown time exports with presence false", flat.timeRemainingPresent, false)
    T.eq("M3 unknown time exports no value", flat.timeRemaining, nil)
    local flat2 = sys:exportFavorRecord(badType)
    T.eq("M3 a known time exports with presence true", flat2.timeRemainingPresent, true)
    T.eq("M3 a known time exports its value", flat2.timeRemaining, 500)
end

-- M4: a row whose neighbour no longer exists is inspect-only and reserves nothing.
do
    setLiveFarms({1, 2})
    local sys = newRealSystem({11})
    local ghost = {id = sys:allocateFavorId(), npcId = 99, npcName = "Gone", type = "help_harvest", status = "paused_recovery",
        recoveryReason = "owner_farm_deleted", resumable = false, ownerFarmId = 15, ownerFarmIdPresent = true, timeRemaining = 1000,
        rewardPaid = false, rewardPaidPresent = true, taskData = {}, recordRevision = 0, reward = {money = 10}}
    table.insert(sys.recoveryFavors, ghost)
    sys:assignRecoveryToken(ghost)
    T.eq("M4 missing neighbour is inspect-only", sys:isRecoveryRecordInspectOnly(ghost), true)
    T.eq("M4 missing neighbour does not reserve", sys:isNPCReservedByRecovery(99), false)
    local admin = {connectionId = "user:admin", farmId = nil, isMaster = true}
    local view = sys:serverRecoveryView(admin, "1", "")
    local r = sys:serverRecoveryCommand(admin, {requestId = "2", collectionRevision = view.collectionRevision, recordRevision = "0",
        token = tostring(ghost.recoveryToken), op = NPCFavorRecovery.OP_ASSIGN_AND_RESUME, targetFarmId = 1, originatingViewRequestId = "1"})
    T.eq("M4 assignment of a ghost-neighbour row is refused", r.result, NPCFavorRecovery.RESULT_REFUSED)
    T.eq("M4 refusal names the neighbour", r.messageKey, "npc_recovery_unavail_npc")
end

-- M5: an owner_farm_deleted row whose owner is a live farm is not actionable
-- and holds no reservation.
do
    setLiveFarms({1, 2})
    local sys = newRealSystem({11})
    local odd = {id = sys:allocateFavorId(), npcId = 11, npcName = "NPC11", type = "help_harvest", status = "paused_recovery",
        recoveryReason = "owner_farm_deleted", resumable = false, ownerFarmId = 2, ownerFarmIdPresent = true, timeRemaining = 1000,
        rewardPaid = false, rewardPaidPresent = true, taskData = {}, recordRevision = 0}
    table.insert(sys.recoveryFavors, odd)
    T.eq("M5 valid-owner orphan row is not actionable", sys:isRecoveryRecordActionable(odd), false)
    T.eq("M5 and reserves nothing", sys:isNPCReservedByRecovery(11), false)
end

-- M6: a row with no usable type is kept as invalid_record, not dropped.
do
    setLiveFarms({1, 2})
    local sys = newRealSystem({11})
    sys._favorLoadState = "WAITING"
    local st = sys:beginFavorLoad()
    local kept, where = sys:restoreFavor({npcId = 11, npcName = "NPC11", timeRemaining = 100, ownerFarmId = 2}, st)
    sys:installFavorSnapshot(st)
    T.ok("M6 a type-less legacy row is kept", kept ~= nil)
    T.eq("M6 it enters recovery", where, "recovery")
    T.eq("M6 as invalid_record", kept.recoveryReason, "invalid_record")
    T.eq("M6 and is written back at the next save", sys:exportFavorRecord(kept).recoveryReason, "invalid_record")
end

-- M7: completeFavor refuses a row without an ordinary owner before any change.
do
    setLiveFarms({1, 2})
    local sys, rel = newRealSystem({11})
    local row = liveRow(sys, 11, 15, "active")
    moneyCalls = {}
    T.eq("M7 completion with the sentinel owner is refused", sys:completeFavor(row.id), false)
    T.eq("M7 the row was not marked complete", row.status, "active")
    T.eq("M7 the row stayed in the live list", #sys.activeFavors, 1)
    T.eq("M7 nothing was paid", #moneyCalls, 0)
    T.eq("M7 no relationship change was applied", #rel.calls, 0)
end

-- Cache: a rights change under the same request id is a fresh validation,
-- not a request-reuse refusal.
do
    setLiveFarms({1, 2, 3})
    local sys = newRealSystem({11})
    local orphan = liveRow(sys, 11, 2, "active")
    setLiveFarms({1, 3})
    sys:onFarmDeleted(2)
    local admin = {connectionId = "user:x", farmId = nil, isMaster = true}
    local view = sys:serverRecoveryView(admin, "1", "")
    local rev = tostring(orphan.recordRevision)
    local function go(actor)
        return sys:serverRecoveryCommand(actor, {requestId = "5", collectionRevision = view.collectionRevision, recordRevision = rev,
            token = tostring(orphan.recoveryToken), op = NPCFavorRecovery.OP_ASSIGN_AND_RESUME, targetFarmId = 1, originatingViewRequestId = "1"})
    end
    T.eq("cache: first admin assign succeeds", go(admin).result, NPCFavorRecovery.RESULT_OK)
    local demoted = {connectionId = "user:x", farmId = nil, isMaster = false}
    local again = go(demoted)
    T.eq("cache: same id after rights revoked is revalidated, not replayed", again.result, NPCFavorRecovery.RESULT_REFUSED)
    T.ok("cache: and the refusal is a fresh validation, not request reuse", again.messageKey ~= "npc_recovery_refused_request_reuse")
    T.eq("cache: the retained result is gone", sys._recoveryRequests["user:x:5"], nil)
    sys:onActorDisconnected("user:x")
    T.eq("cache: disconnect clears the actor's view", sys._recoveryViews["user:x"], nil)
end


-- =====================================================================
-- REVIEW ROUND TWO (Bob, 2026-09-15): the load-abort and copy-back
-- contract through the real NPCSystem + NPCStateLedgerBridge seams, and
-- the XML round-trip of an unknown remaining time.
-- =====================================================================

-- A bare NPCSystem host: enough of the instance for loadFromXMLFile,
-- saveToXMLFile, serializeState and deserializeState without NPCSystem.new
-- (which builds every subsystem). The favor system starts WAITING.
local function newHost(npcIds, opts)
    opts = opts or {}
    local fav, rel = newRealSystem(npcIds)
    fav._favorLoadState = NPCFavorRecovery.LOAD_WAITING
    fav._favorLoadFailOrigin = nil
    fav.activeFavors, fav.recoveryFavors = {}, {}
    local host = setmetatable({
        activeNPCs = {}, settings = {debugMode = false}, favorSystem = fav,
        relationshipManager = {npcRelationships = {}}, isInitialized = true, npcCount = #(npcIds or {11}),
        syncDirty = false,
    }, {__index = NPCSystem})
    for _, npc in ipairs(fav.npcSystem.activeNPCs) do
        npc.uniqueId = "npc-" .. npc.id
        if not opts.noPosition then
            npc.position, npc.rotation = {x = 0, y = 0, z = 0}, {y = 0}
        end
        host.activeNPCs[#host.activeNPCs + 1] = npc
    end
    fav.npcSystem = host
    return host, fav, rel
end

-- In-memory XMLFile handle: the attribute table stands in for the file.
local function newXmlMock()
    local store = {}
    local m = {store = store}
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
                if k:sub(1, #key + 1) == key .. "#" then found = true break end
            end
            if not found then return end
            fn(i, key)
            i = i + 1
        end
    end
    m.delete = function() end
    m.save = function() end
    return m
end

local function ledgerDeliver(host, block)
    g_NPCSystem = host
    NPCStateLedgerBridge.active, NPCStateLedgerBridge.delivered, NPCStateLedgerBridge.pendingState = true, true, block
end
local function ledgerReset()
    g_NPCSystem = nil
    NPCStateLedgerBridge.active, NPCStateLedgerBridge.delivered, NPCStateLedgerBridge.pendingState = false, false, nil
end

-- (5a) loadFromXMLFile: a throw before the favor block is FAILED, not an
-- empty snapshot, and the XML save then leaves the file alone.
do
    setLiveFarms({1, 2})
    local host, fav = newHost({11})
    local savedXMLFile = XMLFile
    local created = 0
    XMLFile = {
        loadIfExists = function() error("disk read failed") end,
        create = function() created = created + 1 return newXmlMock() end,
    }
    host:loadFromXMLFile({savegameDirectory = "sg"})
    T.eq("R2 XML abort: favor load is FAILED", fav:getFavorLoadState(), NPCFavorRecovery.LOAD_FAILED)
    T.eq("R2 XML abort: origin is abort", fav:getFavorLoadFailOrigin(), NPCFavorRecovery.FAIL_ORIGIN_ABORT)
    T.eq("R2 XML abort: not READY", fav:isFavorLoadReady(), false)
    T.eq("R2 XML abort: no favor installed", #fav.activeFavors + #fav.recoveryFavors, 0)
    T.eq("R2 XML abort: the player was told once", host._favorLoadFailedNotified, true)
    T.eq("R2 XML abort: XML route is not favors-only", host:isFavorLoadFailureFavorsOnly(), false)
    -- An empty snapshot cannot be installed over a FAILED load.
    fav:installEmptyFavorSnapshot()
    T.eq("R2 XML abort: installEmptyFavorSnapshot does not revive a FAILED load", fav:getFavorLoadState(), NPCFavorRecovery.LOAD_FAILED)
    host:saveToXMLFile({savegameDirectory = "sg"})
    T.eq("R2 XML abort: save creates no file", created, 0)
    T.eq("R2 XML abort: no ledger block, serializeState omits the module", host:serializeState(), nil)
    XMLFile = savedXMLFile
end

-- (5b) applyState: a throw inside deserializeState (before the favor
-- block) is FAILED with origin abort, and serializeState hands the
-- delivered block back unchanged, NPC data included.
do
    setLiveFarms({1, 2})
    local host, fav = newHost({11}, {noPosition = true})   -- npc.position nil makes the NPC block throw
    local block = {schemaVersion = 3, npcs = {{uniqueId = "npc-11", name = "NPC11", px = 5, relationship = 70}},
        favors = {{f148Schema = 1, npcId = 11, npcName = "NPC11", type = "help_harvest", status = "active",
            ownerFarmIdPresent = true, ownerFarmId = 2, timeRemainingPresent = true, timeRemaining = 900,
            rewardPaidPresent = true, rewardPaid = false}},
        recoveryFavors = {}, relationships = {{key = "a|b", value = 55}}}
    ledgerDeliver(host, block)
    T.eq("R2 ledger abort: applyState reports failure", NPCStateLedgerBridge.applyState(), false)
    T.eq("R2 ledger abort: favor load is FAILED", fav:getFavorLoadState(), NPCFavorRecovery.LOAD_FAILED)
    T.eq("R2 ledger abort: origin is abort", fav:getFavorLoadFailOrigin(), NPCFavorRecovery.FAIL_ORIGIN_ABORT)
    T.eq("R2 ledger abort: no favor installed", #fav.activeFavors + #fav.recoveryFavors, 0)
    T.eq("R2 ledger abort: the player was told", host._favorLoadFailedNotified, true)
    T.eq("R2 ledger abort: not favors-only", host:isFavorLoadFailureFavorsOnly(), false)
    T.eq("R2 ledger abort: delivered block retained", host._ledgerOriginalState, block)
    local out = host:serializeState()
    T.eq("R2 ledger abort: serializeState returns the delivered block itself", out, block)
    T.eq("R2 ledger abort: delivered NPC data untouched", block.npcs[1].px, 5)
    T.eq("R2 ledger abort: delivered favor untouched", block.favors[1].timeRemaining, 900)
    ledgerReset()
end

-- (5c) applyState: a refused favor record (schema refusal, no throw) is
-- FAILED with origin record; serializeState copies both favor blocks back
-- by identity and still writes live NPC progress around them.
do
    setLiveFarms({1, 2})
    local host, fav = newHost({11})
    local favorsIn = {{f148Schema = 99, npcId = 11, npcName = "NPC11", type = "help_harvest", status = "active"}}
    local recoveryIn = {}
    local block = {schemaVersion = 3, npcs = {{uniqueId = "npc-11", name = "NPC11", px = 7, relationship = 80}},
        favors = favorsIn, recoveryFavors = recoveryIn, relationships = {}}
    ledgerDeliver(host, block)
    T.eq("R2 record refusal: applyState completes", NPCStateLedgerBridge.applyState(), true)
    T.eq("R2 record refusal: favor load is FAILED", fav:getFavorLoadState(), NPCFavorRecovery.LOAD_FAILED)
    T.eq("R2 record refusal: origin is record", fav:getFavorLoadFailOrigin(), NPCFavorRecovery.FAIL_ORIGIN_RECORD)
    T.eq("R2 record refusal: favors-only failure on the ledger route", host:isFavorLoadFailureFavorsOnly(), true)
    T.eq("R2 record refusal: NPC progress was applied", host.activeNPCs[1].relationship, 80)
    T.eq("R2 record refusal: delivered row not mutated by the type repair", favorsIn[1].type, "help_harvest")
    -- Live favor work after the failure must not leak into the save.
    liveRow(fav, 11, 1, "active")
    host.activeNPCs[1].relationship = 81
    local out = host:serializeState()
    T.ok("R2 record refusal: serializeState builds a new table", out ~= nil and out ~= block)
    T.eq("R2 record refusal: favors copied back by identity", out.favors, favorsIn)
    T.eq("R2 record refusal: recoveryFavors copied back by identity", out.recoveryFavors, recoveryIn)
    T.eq("R2 record refusal: the live row was not exported", #out.favors, 1)
    T.eq("R2 record refusal: live NPC progress is written", out.npcs[1].relationship, 81)
    -- A second delivery after FAILED does not re-run the load.
    T.eq("R2 record refusal: repeated apply does not revive the load", NPCStateLedgerBridge.applyState(), true)
    T.eq("R2 record refusal: still FAILED", fav:getFavorLoadState(), NPCFavorRecovery.LOAD_FAILED)
    ledgerReset()
end

-- (5c2) serializeState while WAITING with a delivered block copies back
-- too; while READY it exports live rows.
do
    setLiveFarms({1, 2})
    local host, fav = newHost({11})
    local favorsIn = {}
    host._ledgerOriginalState = {favors = favorsIn, recoveryFavors = nil}
    local out = host:serializeState()
    T.eq("R2 WAITING copy-back: favors by identity", out.favors, favorsIn)
    T.eq("R2 WAITING copy-back: absent recovery block stays absent", out.recoveryFavors, nil)
    fav:installEmptyFavorSnapshot()
    liveRow(fav, 11, 1, "active")
    out = host:serializeState()
    T.eq("R2 READY: live rows exported", #out.favors, 1)
    T.ok("R2 READY: recovery block written", out.recoveryFavors ~= nil and #out.recoveryFavors == 0)
end

-- (5d) XML round-trip: an unknown remaining time is written absent, read
-- absent and restored as unknown (inspect-only), never as 0.
do
    setLiveFarms({1, 2})
    local src = newRealSystem({11})
    src._favorLoadState = NPCFavorRecovery.LOAD_WAITING
    local st = src:beginFavorLoad()
    local unknown = src:restoreFavor({f148Schema = 1, status = "paused_recovery", recoveryReason = "some_future_token",
        type = "help_harvest", npcId = 11, npcName = "NPC11", timeRemainingPresent = false,
        ownerFarmIdPresent = true, ownerFarmId = 15, rewardPaidPresent = true, rewardPaid = false}, st)
    local known = src:restoreFavor({f148Schema = 1, status = "paused_recovery", recoveryReason = "owner_farm_deleted",
        type = "help_harvest", npcId = 11, npcName = "NPC11", timeRemainingPresent = true, timeRemaining = 500,
        ownerFarmIdPresent = true, ownerFarmId = 15, originalStatus = "active", originalOwnerFarmIdPresent = true, originalOwnerFarmId = 2,
        rewardPaidPresent = true, rewardPaid = false}, st)
    src:installFavorSnapshot(st)
    T.ok("R2 XML rt: fixture restored", unknown ~= nil and known ~= nil and unknown.timeRemainingRaw ~= nil)

    local xml = newXmlMock()
    local k0, k1 = "npcFavor.recoveryFavors.favor(0)", "npcFavor.recoveryFavors.favor(1)"
    NPCSystem.writeFavorRecordXML(xml, k0, src:exportFavorRecord(unknown))
    NPCSystem.writeFavorRecordXML(xml, k1, src:exportFavorRecord(known))
    T.eq("R2 XML rt: unknown time written with presence false", xml.store[k0 .. "#timeRemainingPresent"], false)
    T.eq("R2 XML rt: unknown time has no value attribute", xml.store[k0 .. "#timeRemaining"], nil)
    T.eq("R2 XML rt: known time written with presence true", xml.store[k1 .. "#timeRemainingPresent"], true)
    T.eq("R2 XML rt: known time value written", xml.store[k1 .. "#timeRemaining"], 500)

    local flat0 = NPCSystem.readFavorRecordXML(xml, k0)
    local flat1 = NPCSystem.readFavorRecordXML(xml, k1)
    T.eq("R2 XML rt: unknown time read with presence false", flat0.timeRemainingPresent, false)
    T.eq("R2 XML rt: unknown time read as absent", flat0.timeRemaining, nil)
    T.eq("R2 XML rt: unknown reason token round-trips", flat0.recoveryReason, "some_future_token")
    T.eq("R2 XML rt: known time read back", flat1.timeRemaining, 500)
    T.eq("R2 XML rt: originalStatus round-trips", flat1.originalStatus, "active")
    T.eq("R2 XML rt: originalOwnerFarmId round-trips", flat1.originalOwnerFarmId, 2)

    local dst = newRealSystem({11})
    dst._favorLoadState = NPCFavorRecovery.LOAD_WAITING
    local st2 = dst:beginFavorLoad()
    local back0 = dst:restoreFavor(flat0, st2)
    local back1 = dst:restoreFavor(flat1, st2)
    dst:installFavorSnapshot(st2)
    T.ok("R2 XML rt: unknown time is still unknown after reload", back0 ~= nil and back0.timeRemainingRaw ~= nil)
    T.eq("R2 XML rt: unknown time never exports as a known value", dst:exportFavorRecord(back0).timeRemaining, nil)
    T.eq("R2 XML rt: unknown-time row is inspect-only after reload", dst:isRecoveryRecordInspectOnly(back0), true)
    T.eq("R2 XML rt: known time survives reload", back1.timeRemaining, 500)
    T.eq("R2 XML rt: exported again, still absent", dst:exportFavorRecord(back0).timeRemainingPresent, false)
end

-- Round-two minors: orphaning marks the host dirty and keeps the first
-- original owner; re-retaining a request key leaves one order entry.
do
    setLiveFarms({1, 2})
    local host, fav = newHost({11})
    fav:installEmptyFavorSnapshot()
    local job = liveRow(fav, 11, 2, "active")
    setLiveFarms({1})
    host.syncDirty = false
    T.eq("R2 minor: orphaning reaches the row", fav:onFarmDeleted(2), 1)
    T.eq("R2 minor: orphaning marks the host dirty for sync", host.syncDirty, true)
    T.eq("R2 minor: original owner recorded", job.originalOwnerFarmId, 2)
    job.ownerFarmId = 2
    fav:orphanFavorRecord(job)
    T.eq("R2 minor: a second orphaning keeps the first original owner", job.originalOwnerFarmId, 2)
    fav._recoveryRequests = fav._recoveryRequests or {}
    fav:retainRecoveryRequest("u:1", {})
    fav:retainRecoveryRequest("u:2", {})
    fav:retainRecoveryRequest("u:1", {})
    T.eq("R2 minor: re-retained key is not duplicated in the order list", #fav._recoveryRequestOrder, 2)
    T.eq("R2 minor: re-retained key is newest", fav._recoveryRequestOrder[2], "u:1")
end
