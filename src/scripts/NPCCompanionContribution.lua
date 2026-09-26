-- =========================================================
-- FS25 NPC Favor Mod - Companion contribution, host core (NPC-204)
-- =========================================================
-- A companion mod can introduce its own people as real neighbours and have one
-- of them ask one addressed farm for one simple two-step job: the companion
-- REPORTs that the work happened, then the farmer TALKs to the neighbour to
-- finish. NPCFavor stays the only owner of the person, the job, trust and
-- money (Implementation v1.1 sections 3.1 to 3.7, the host core).
--
-- The verbs are published on the mission handle as NPCSystem methods (see
-- NPCSystem.lua); this file is the favour owner's half. Every verb answers a
-- table { result, reason, ... }; malformed input refuses before anything is
-- written. Contributed kinds never enter favorTypes, so no built-in roll,
-- step builder or recovery path can select them.
--
-- The work surface ships behind NPCReleaseGate (LOCKED unless the player opts
-- in). Registration and person claims stay available while it is LOCKED;
-- offers, acceptance and advancing reports refuse; pending offers are
-- withdrawn without fault and accepted work is held with its clock stopped,
-- returning by itself when the surface reads OPEN again.
--
-- Recovery (3.8, 3.9): held work always has the owning farm's LET_GO, a
-- no-fault close, including while LOCKED. Paused work resumes through the
-- contributed Resume, never resumeRecoveryRecord. A waiting person's pending
-- offer, and every row of a deleted or reused farm number, close without fault.
--
-- Save and load (3.10): accepted and held work saves its contribution block
-- beside the F148 row in both writers (pending offers do not), with the
-- favour-number high-water; it reloads held in Recovery until its companion
-- declares the kind again. Any other contribution schema stays inert.
-- =========================================================

NPCCompanion = NPCCompanion or {}

NPCCompanion.API_VERSION         = 1
NPCCompanion.CONTRIBUTION_SCHEMA = 1
NPCCompanion.MAX_PEOPLE          = 4
NPCCompanion.MAX_KINDS           = 16
NPCCompanion.MAX_PRIOR_VERSIONS  = 8
NPCCompanion.HOUR_MS             = 3600000
-- The host's ordinary ask floor and the grumpy personality floor, as
-- NPCFavorSystem:canNPCRequestFavor applies them.
NPCCompanion.ASK_FLOOR           = 10
NPCCompanion.GRUMPY_FLOOR        = 40

NPCCompanion.SURFACE_OPEN   = "OPEN"
NPCCompanion.SURFACE_LOCKED = "LOCKED"

NPCCompanion.READY        = "READY"
NPCCompanion.WAIT         = "WAIT"
NPCCompanion.REFUSED      = "REFUSED"
NPCCompanion.OFFERED      = "OFFERED"
NPCCompanion.DONE         = "DONE"
NPCCompanion.ALREADY_DONE = "ALREADY_DONE"
NPCCompanion.CLOSED       = "CLOSED"
NPCCompanion.NO_MATCH     = "NO_MATCH"
NPCCompanion.UNAVAILABLE  = "UNAVAILABLE"

NPCCompanion.HOLD_WORK_OFF               = "WORK_OFF"
NPCCompanion.HOLD_COMPANION_MISSING      = "COMPANION_MISSING"
NPCCompanion.HOLD_COMPANION_INCOMPATIBLE = "COMPANION_INCOMPATIBLE"

NPCCompanion.STEP_REPORT = "REPORT"
NPCCompanion.STEP_TALK   = "TALK"
NPCCompanion.TARGET_FIELD = "FIELD"
NPCCompanion.TARGET_NONE  = "NONE"

-- Host-owned outcomes a provider may send but never declare.
NPCCompanion.RESERVED_OUTCOMES = { target_gone = true, need_passed = true }
NPCCompanion.CATEGORIES = {
    fieldwork = true, transport = true, repair = true, delivery = true, animal_care = true, social = true,
}

-- Host generic copy for the existing doors. The locale keys and the provider
-- text proof arrive with the views and text slice (section 3.11).
NPCCompanion.GENERIC_DESC        = "A neighbour asked your farm for help"
NPCCompanion.GENERIC_STEP_REPORT = "Do the work"
NPCCompanion.GENERIC_STEP_TALK   = "Talk to the neighbour"

local PAUSED = "paused_recovery"
local ACTIVE_STATUS = { active = true, in_progress = true }

local function answer(result, reason, extra)
    local a = { result = result, reason = reason }
    if extra ~= nil then
        for k, v in pairs(extra) do a[k] = v end
    end
    return a
end

local function isInt(value)
    return NPCFarmIdentity.isInteger(value)
end

local function intIn(value, lo, hi)
    return isInt(value) and value >= lo and value <= hi
end

local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function grammar(value, lo, hi)
    return type(value) == "string" and #value >= lo and #value <= hi and value:match("^[a-z0-9_]+$") ~= nil
end

local function onlyKeys(t, allowed)
    for k in pairs(t) do
        if allowed[k] ~= true then return false end
    end
    return true
end

local function nowMs()
    if TimeHelper ~= nil and TimeHelper.getGameTimeMs ~= nil then
        return TimeHelper.getGameTimeMs()
    end
    return (g_currentMission and g_currentMission.time) or 0
end

local function removeFrom(list, record)
    for i = #(list or {}), 1, -1 do
        if list[i] == record then
            table.remove(list, i)
            return true
        end
    end
    return false
end

local function contains(list, record)
    for _, candidate in ipairs(list or {}) do
        if candidate == record then return true end
    end
    return false
end

--- A deterministic text form of a validated declaration: identity compares
--- every declared field, not a subset.
local function canonical(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. canonical(value[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

function NPCCompanion.isContributed(favor)
    return type(favor) == "table" and type(favor.contribution) == "table"
end

function NPCCompanion.validNamespace(value)
    return grammar(value, 3, 32)
end

function NPCCompanion.validKey(value)
    return grammar(value, 1, 32)
end

local function validTextKey(value)
    return value == nil or (type(value) == "string" and #value >= 1 and #value <= 64
        and value:match("^[%w_%.]+$") ~= nil)
end

-- A target key names a companion-side target (a field number, a spot id): a
-- bounded token, never written into taskData.fieldId.
local function validTargetKey(value)
    return type(value) == "string" and #value >= 1 and #value <= 32 and value:match("^[%w_%.:%-]+$") ~= nil
end

--- The kind id travels in `type` so hasActiveFavorOfType matches it.
function NPCCompanion.kindId(namespace, kindKey)
    return namespace .. ":" .. kindKey
end

local SPEC_KEYS = { namespace = true, modName = true, apiVersion = true }
local DECL_KEYS = {
    kindKey = true, version = true, acceptsVersions = true, titleKey = true, descriptionKey = true,
    category = true, difficulty = true, offerHours = true, workHours = true, minTrust = true,
    reward = true, penalty = true, addressing = true, offeredPerson = true, targetKind = true, steps = true,
}
local REWARD_KEYS = { relationship = true, money = true }
local PENALTY_KEYS = { relationship = true }
local REPORT_STEP_KEYS = { kind = true, outcome = true, textKey = true }
local TALK_STEP_KEYS = { kind = true, textKey = true }
local REQUEST_KEYS = { personKey = true, addressedFarmId = true, targetKey = true }
local REPORT_KEYS = { favorId = true, outcome = true, farmId = true }

--- Validate a declaration into a fresh table built from declared keys only
--- (the host's own deep copy). Returns the copy, or nil and a reason.
function NPCCompanion.validateDeclaration(decl)
    if type(decl) ~= "table" or not onlyKeys(decl, DECL_KEYS) then return nil, "bad_declaration" end
    if not NPCCompanion.validKey(decl.kindKey) then return nil, "bad_kind_key" end
    if not intIn(decl.version, 1, 65535) then return nil, "bad_version" end
    local accepts = {}
    if decl.acceptsVersions ~= nil then
        if type(decl.acceptsVersions) ~= "table" or #decl.acceptsVersions > NPCCompanion.MAX_PRIOR_VERSIONS then
            return nil, "bad_version"
        end
        local n = 0
        for _ in pairs(decl.acceptsVersions) do n = n + 1 end
        if n ~= #decl.acceptsVersions then return nil, "bad_version" end
        for i, v in ipairs(decl.acceptsVersions) do
            if not intIn(v, 1, 65535) then return nil, "bad_version" end
            accepts[i] = v
        end
    end
    if not validTextKey(decl.titleKey) or not validTextKey(decl.descriptionKey) then return nil, "bad_text_key" end
    if NPCCompanion.CATEGORIES[decl.category] ~= true then return nil, "bad_category" end
    if not intIn(decl.difficulty, 1, 3) then return nil, "bad_difficulty" end
    if not intIn(decl.offerHours, 1, 24) then return nil, "bad_offer_time" end
    if not intIn(decl.workHours, 1, 72) then return nil, "bad_work_time" end
    if not intIn(decl.minTrust, 0, 100) then return nil, "bad_trust" end
    local reward, penalty = decl.reward, decl.penalty
    if type(reward) ~= "table" or not onlyKeys(reward, REWARD_KEYS)
        or not intIn(reward.relationship, 0, 20) or not intIn(reward.money, 0, 1000) then
        return nil, "bad_reward"
    end
    if type(penalty) ~= "table" or not onlyKeys(penalty, PENALTY_KEYS) or not intIn(penalty.relationship, -15, 0) then
        return nil, "bad_penalty"
    end
    if decl.addressing ~= "ADDRESSED" then return nil, "bad_addressing" end
    if decl.offeredPerson ~= "OWN_PERSON" then return nil, "bad_offered_person" end
    if decl.targetKind ~= NPCCompanion.TARGET_FIELD and decl.targetKind ~= NPCCompanion.TARGET_NONE then
        return nil, "bad_target_kind"
    end
    -- Exactly one REPORT outcome followed by exactly one TALK step.
    local steps = decl.steps
    if type(steps) ~= "table" or #steps ~= 2 then return nil, "bad_steps" end
    local count = 0
    for _ in pairs(steps) do count = count + 1 end
    if count ~= 2 then return nil, "bad_steps" end
    local report, talk = steps[1], steps[2]
    if type(report) ~= "table" or not onlyKeys(report, REPORT_STEP_KEYS) or report.kind ~= NPCCompanion.STEP_REPORT
        or not validTextKey(report.textKey) then
        return nil, "bad_steps"
    end
    if not NPCCompanion.validKey(report.outcome) then return nil, "bad_outcome" end
    if NPCCompanion.RESERVED_OUTCOMES[report.outcome] then return nil, "reserved_outcome" end
    if type(talk) ~= "table" or not onlyKeys(talk, TALK_STEP_KEYS) or talk.kind ~= NPCCompanion.STEP_TALK
        or not validTextKey(talk.textKey) then
        return nil, "bad_steps"
    end
    return {
        kindKey = decl.kindKey, version = decl.version, acceptsVersions = accepts,
        titleKey = decl.titleKey, descriptionKey = decl.descriptionKey,
        category = decl.category, difficulty = decl.difficulty,
        offerHours = decl.offerHours, workHours = decl.workHours, minTrust = decl.minTrust,
        reward = { relationship = reward.relationship, money = reward.money },
        penalty = { relationship = penalty.relationship },
        addressing = decl.addressing, offeredPerson = decl.offeredPerson, targetKind = decl.targetKind,
        reportOutcome = report.outcome, reportTextKey = report.textKey, talkTextKey = talk.textKey,
    }
end

--- A held or saved row binds to a declaration with an accepted version, the
--- same target kind and the same REPORT outcome (the two-step structure is
--- fixed in version 1). Presentation text may change.
function NPCCompanion.compatible(kind, contribution)
    if type(kind) ~= "table" or type(contribution) ~= "table" then return false end
    local versionOK = kind.version == contribution.kindVersion
    for _, v in ipairs(kind.acceptsVersions or {}) do
        if v == contribution.kindVersion then versionOK = true end
    end
    return versionOK and kind.targetKind == contribution.targetKind
        and kind.reportOutcome == contribution.reportOutcome
end

-- =========================================================
-- State owned by the favour system
-- =========================================================

function NPCFavorSystem:companionState()
    if self._companion == nil then
        self._companion = { providers = {}, kinds = {}, surface = nil }
    end
    return self._companion
end

function NPCFavorSystem:getCompanionProvider(namespace)
    local provider = self:companionState().providers[namespace]
    if provider ~= nil and provider.active == true then return provider end
    return nil
end

--- The runtime predicate for the companion work surface (section 3.7).
function NPCFavorSystem:isCompanionSurfaceOpen()
    local settings = self.npcSystem and self.npcSystem.settings
    return NPCReleaseGate.isSystemLive(NPCReleaseGate.COMPANION_WORK, settings)
end

--- Read the surface. A change, or the first read, re-evaluates every open
--- contributed row: LOCKED withdraws pending offers without fault and holds
--- accepted work; OPEN returns lock-held work by itself.
function NPCFavorSystem:readCompanionSurface()
    local surface = self:isCompanionSurfaceOpen() and NPCCompanion.SURFACE_OPEN or NPCCompanion.SURFACE_LOCKED
    local st = self:companionState()
    if st.surface ~= surface then
        st.surface = surface
        if surface ~= NPCCompanion.SURFACE_OPEN then
            for _, favor in ipairs(self:collectContributed(nil, true)) do
                if favor.status == "pending" then self:closeContributionNoFault(favor, "surface_locked") end
            end
        end
        self:reevaluateContributedWork(nil)
    end
    return surface
end

--- Open contributed rows in both collections, optionally one provider's,
--- collected first so a caller may move or close them.
function NPCFavorSystem:collectContributed(namespace, includePending)
    local out = {}
    for _, list in ipairs({ self.activeFavors or {}, self.recoveryFavors or {} }) do
        for _, favor in ipairs(list) do
            if NPCCompanion.isContributed(favor)
                and (namespace == nil or favor.contribution.namespace == namespace)
                and (includePending or favor.status ~= "pending") then
                out[#out + 1] = favor
            end
        end
    end
    return out
end

function NPCFavorSystem:findContributedFavor(favorId)
    for _, favor in ipairs(self.activeFavors or {}) do
        if favor.id == favorId and NPCCompanion.isContributed(favor) then return favor, "active" end
    end
    for _, favor in ipairs(self.recoveryFavors or {}) do
        if favor.id == favorId and NPCCompanion.isContributed(favor) then return favor, "recovery" end
    end
    return nil, nil
end

--- One open obligation per neighbour: any contributed row, in either
--- collection, bound to this same proved durable person. A row with no proved
--- person never occupies a namesake.
function NPCFavorSystem:isPersonHeldByContribution(npcId)
    if npcId == nil then return false end
    for _, list in ipairs({ self.activeFavors or {}, self.recoveryFavors or {} }) do
        for _, favor in ipairs(list) do
            if NPCCompanion.isContributed(favor) and favor.npcId == npcId
                and favor.personRefKind == "durable" and favor.personUnproven ~= true then
                return true
            end
        end
    end
    return false
end

--- No-fault close: out of its collection, token retired, revision bumped, and
--- no relationship, money, penalty, encounter, failure count or history.
function NPCFavorSystem:closeContributionNoFault(favor, reason)
    if not removeFrom(self.activeFavors, favor) then
        removeFrom(self.recoveryFavors, favor)
    end
    self:retireRecoveryToken(favor)
    self:bumpRecordRevision(favor)
    favor.status = "closed"
    favor.contributionClosed = reason or "closed"
    if self.npcSystem ~= nil then self.npcSystem.syncDirty = true end
end

-- =========================================================
-- Hold and re-evaluation (the hold half of section 3.8, which 3.1 and 3.7 use)
-- =========================================================

--- The hold reason for an accepted row, in the brief's order, or nil.
function NPCFavorSystem:contributionHoldFor(favor)
    local st = self:companionState()
    if st.surface ~= NPCCompanion.SURFACE_OPEN then return NPCCompanion.HOLD_WORK_OFF end
    local c = favor.contribution
    if self:getCompanionProvider(c.namespace) == nil then return NPCCompanion.HOLD_COMPANION_MISSING end
    local kind = st.kinds[NPCCompanion.kindId(c.namespace, c.kindKey)]
    if kind == nil then return NPCCompanion.HOLD_COMPANION_MISSING end
    if not NPCCompanion.compatible(kind, c) then return NPCCompanion.HOLD_COMPANION_INCOMPATIBLE end
    return nil
end

--- Move accepted work into Recovery held, clock frozen, following the pattern
--- of pauseWorkForPerson. A row already in Recovery keeps any F148 or F357
--- pause beside the hold.
function NPCFavorSystem:holdContributedFavor(favor, reason)
    if removeFrom(self.activeFavors, favor) then
        favor.originalStatus = favor.status
        favor.originalOwnerFarmId = favor.originalOwnerFarmId or favor.ownerFarmId
        if favor.expirationGameTime ~= nil then
            favor.timeRemaining = favor.expirationGameTime - nowMs()
        end
        favor.expirationGameTime = nil
        favor.status = PAUSED
        favor.contributionHeld = true
        favor.contributionHoldReason = reason
        self:retireRecoveryToken(favor)
        self:bumpRecordRevision(favor)
        table.insert(self.recoveryFavors, favor)
        self:assignRecoveryToken(favor)
        return
    end
    if favor.contributionHeld ~= true or favor.contributionHoldReason ~= reason then
        favor.contributionHeld = true
        favor.contributionHoldReason = reason
        self:bumpRecordRevision(favor)
    end
end

--- The hold clears. The row returns to active work only with no independent
--- pause, the owning farm ordinary and the same proved person actionable; an
--- away neighbour gives F357's pause instead. A spent remainder closes without
--- fault rather than resuming into an immediate penalised failure. Resuming
--- never stamps recoveredFromLegacy.
function NPCFavorSystem:releaseContributedHold(favor)
    favor.contributionHeld = false
    favor.contributionHoldReason = nil
    if favor.recoveryReason ~= nil or favor.personUnproven == true then
        self:bumpRecordRevision(favor)
        return "paused"
    end
    local remaining = favor.timeRemaining
    if favor.timeRemainingRaw ~= nil or not finite(remaining) or remaining <= 0 then
        self:closeContributionNoFault(favor, "time_spent")
        return "closed"
    end
    if not NPCFarmIdentity.isOrdinaryFarmId(favor.ownerFarmId) then
        self:closeContributionNoFault(favor, "owner_gone")
        return "closed"
    end
    if self:resolveFavorPerson(favor) == nil then
        favor.recoveryReason = NPCFavorRecovery.REASON_NEIGHBOUR_UNAVAILABLE
        favor.resumable = true
        self:bumpRecordRevision(favor)
        return "paused"
    end
    removeFrom(self.recoveryFavors, favor)
    favor.status = (favor.originalStatus == "in_progress") and "in_progress" or "active"
    favor.originalStatus = nil
    favor.originalOwnerFarmId = nil
    favor.expirationGameTime = nowMs() + remaining
    self:retireRecoveryToken(favor)
    self:bumpRecordRevision(favor)
    table.insert(self.activeFavors, favor)
    self:assignRecoveryToken(favor)
    return "active"
end

function NPCFavorSystem:classifyContributedFavor(favor)
    if not NPCCompanion.isContributed(favor) or favor.status == "pending" then return nil end
    local hold = self:contributionHoldFor(favor)
    if hold ~= nil then
        self:holdContributedFavor(favor, hold)
        return hold
    end
    if favor.contributionHeld == true then
        return self:releaseContributedHold(favor)
    end
    return nil
end

function NPCFavorSystem:reevaluateContributedWork(namespace)
    local rows = self:collectContributed(namespace, false)
    for _, favor in ipairs(rows) do
        self:classifyContributedFavor(favor)
    end
    if #rows > 0 and self.npcSystem ~= nil then self.npcSystem.syncDirty = true end
end

-- =========================================================
-- 3.1 Provider registration
-- =========================================================

function NPCFavorSystem:registerCompanionProvider(spec)
    if type(spec) ~= "table" or not onlyKeys(spec, SPEC_KEYS) then return answer(NPCCompanion.REFUSED, "bad_spec") end
    if not NPCCompanion.validNamespace(spec.namespace) then return answer(NPCCompanion.REFUSED, "bad_namespace") end
    if spec.apiVersion ~= NPCCompanion.API_VERSION then return answer(NPCCompanion.REFUSED, "api_version") end
    local modName = spec.modName
    if type(modName) ~= "string" or #modName < 1 or #modName > 64 then return answer(NPCCompanion.REFUSED, "bad_mod") end
    -- The native loaded-mod table (AnimalSystem.lua:246 reads it the same way).
    if g_modIsLoaded == nil or g_modIsLoaded[modName] == nil then
        return answer(NPCCompanion.REFUSED, "mod_not_loaded")
    end
    local st = self:companionState()
    local surface = self:readCompanionSurface()
    local existing = st.providers[spec.namespace]
    if existing ~= nil then
        -- The first loaded mod owns a namespace for the mission.
        if existing.modName ~= modName then return answer(NPCCompanion.REFUSED, "namespace_taken") end
        if existing.active == true then
            return answer(NPCCompanion.READY, "already_registered", { apiVersion = NPCCompanion.API_VERSION, surface = surface })
        end
        existing.active = true
    else
        st.providers[spec.namespace] = { namespace = spec.namespace, modName = modName,
            apiVersion = NPCCompanion.API_VERSION, active = true }
    end
    -- Held work stays COMPANION_MISSING until its kind is declared again.
    self:reevaluateContributedWork(spec.namespace)
    return answer(NPCCompanion.READY, "registered", { apiVersion = NPCCompanion.API_VERSION, surface = surface })
end

function NPCFavorSystem:unregisterCompanionProvider(namespace)
    if not NPCCompanion.validNamespace(namespace) then return answer(NPCCompanion.REFUSED, "bad_namespace") end
    local st = self:companionState()
    local provider = self:getCompanionProvider(namespace)
    if provider == nil then return answer(NPCCompanion.NO_MATCH, "not_registered") end
    provider.active = false
    for id, kind in pairs(st.kinds) do
        if kind.namespace == namespace then st.kinds[id] = nil end
    end
    for _, favor in ipairs(self:collectContributed(namespace, true)) do
        if favor.status == "pending" then self:closeContributionNoFault(favor, "provider_gone") end
    end
    self:readCompanionSurface()
    self:reevaluateContributedWork(namespace)
    return answer(NPCCompanion.DONE, "unregistered")
end

-- =========================================================
-- 3.3 Work declaration
-- =========================================================

function NPCFavorSystem:registerFavorType(namespace, declaration)
    if not NPCCompanion.validNamespace(namespace) then return answer(NPCCompanion.REFUSED, "bad_namespace") end
    if self:getCompanionProvider(namespace) == nil then return answer(NPCCompanion.REFUSED, "provider_unknown") end
    local kind, why = NPCCompanion.validateDeclaration(declaration)
    if kind == nil then return answer(NPCCompanion.REFUSED, why) end
    kind.namespace = namespace
    local id = NPCCompanion.kindId(namespace, kind.kindKey)
    local st = self:companionState()
    local existing = st.kinds[id]
    if existing ~= nil then
        if canonical(existing) == canonical(kind) then
            return answer(NPCCompanion.READY, "already_declared", { kindId = id })
        end
        return answer(NPCCompanion.REFUSED, "redeclared_changed")
    end
    local count = 0
    for _, other in pairs(st.kinds) do
        if other.namespace == namespace then count = count + 1 end
    end
    if count >= NPCCompanion.MAX_KINDS then return answer(NPCCompanion.REFUSED, "kind_limit") end
    st.kinds[id] = kind
    -- A compatible declaration binds held rows; an incompatible one holds them.
    self:readCompanionSurface()
    self:reevaluateContributedWork(namespace)
    return answer(NPCCompanion.READY, "declared", { kindId = id })
end

-- =========================================================
-- 3.4 Offer
-- =========================================================

function NPCFavorSystem:requestFavorOffer(namespace, kindKey, request)
    if not NPCCompanion.validNamespace(namespace) then return answer(NPCCompanion.REFUSED, "bad_namespace") end
    if not NPCCompanion.validKey(kindKey) then return answer(NPCCompanion.REFUSED, "bad_kind_key") end
    if type(request) ~= "table" or not onlyKeys(request, REQUEST_KEYS) then return answer(NPCCompanion.REFUSED, "bad_request") end
    if not NPCCompanion.validKey(request.personKey) then return answer(NPCCompanion.REFUSED, "bad_person_key") end
    local farmId = request.addressedFarmId
    if not NPCFarmIdentity.isOrdinaryFarmId(farmId) then return answer(NPCCompanion.REFUSED, "bad_farm") end
    if self:getCompanionProvider(namespace) == nil then return answer(NPCCompanion.REFUSED, "provider_unknown") end
    local id = NPCCompanion.kindId(namespace, kindKey)
    local kind = self:companionState().kinds[id]
    if kind == nil then return answer(NPCCompanion.REFUSED, "kind_undeclared") end
    if kind.targetKind == NPCCompanion.TARGET_FIELD then
        if not validTargetKey(request.targetKey) then return answer(NPCCompanion.REFUSED, "bad_target") end
    elseif request.targetKey ~= nil then
        return answer(NPCCompanion.REFUSED, "bad_target")
    end
    if self:readCompanionSurface() ~= NPCCompanion.SURFACE_OPEN then return answer(NPCCompanion.REFUSED, "surface_locked") end
    if not self:isFavorLoadReady() then return answer(NPCCompanion.WAIT, "favor_load_waiting") end

    -- The person: live, unique, durable and this provider's own.
    local sys = self.npcSystem
    local people = sys and sys.people
    if people == nil or not people:isReady() then return answer(NPCCompanion.WAIT, "people_loading") end
    local matches = people:peopleWithToken(NPCPersonRoster.providerPersonToken(namespace, request.personKey))
    if #matches == 0 then return answer(NPCCompanion.REFUSED, "person_unknown") end
    if #matches > 1 or matches[1].providerConflict then return answer(NPCCompanion.UNAVAILABLE, "identity_conflict") end
    local npc = matches[1]
    if npc.live ~= true or not self:isPersonActionable(npc) then return answer(NPCCompanion.WAIT, "person_waiting") end

    -- An identical request while its offer is still pending answers with it.
    for _, favor in ipairs(self.activeFavors or {}) do
        local c = favor.contribution
        if NPCCompanion.isContributed(favor) and favor.status == "pending" and favor.npcId == npc.id
            and c.namespace == namespace and c.kindKey == kindKey and c.addressedFarmId == farmId
            and c.targetKey == request.targetKey then
            return answer(NPCCompanion.OFFERED, "already_offered", { favorId = favor.id })
        end
    end

    -- The ordinary social gates of canNPCRequestFavor on that person.
    if not npc.isActive then return answer(NPCCompanion.WAIT, "person_inactive") end
    if (npc.favorCooldown or 0) > 0 then return answer(NPCCompanion.WAIT, "cooldown") end
    local floor = math.max(kind.minTrust, NPCCompanion.ASK_FLOOR)
    if (npc.relationship or 0) < floor then return answer(NPCCompanion.WAIT, "trust_low") end
    if npc.personality == "grumpy" and (npc.relationship or 0) < NPCCompanion.GRUMPY_FLOOR then
        return answer(NPCCompanion.WAIT, "trust_low")
    end
    -- Occupancy replaces the per-person count and the recovery reservation.
    for _, favor in ipairs(self.activeFavors or {}) do
        if favor.npcId == npc.id then return answer(NPCCompanion.WAIT, "person_busy") end
    end
    if self:isNPCReservedByRecovery(npc.id) then return answer(NPCCompanion.WAIT, "person_busy") end
    for _, favor in ipairs(self.recoveryFavors or {}) do
        if NPCCompanion.isContributed(favor) and favor.npcId == npc.id then
            return answer(NPCCompanion.WAIT, "person_busy")
        end
    end

    local now = nowMs()
    local offerMs = kind.offerHours * NPCCompanion.HOUR_MS
    local favor = {
        id = self:allocateFavorId(),
        npcId = npc.id,
        npcName = npc.name,
        type = id,
        name = "",
        description = NPCCompanion.GENERIC_DESC,
        difficulty = kind.difficulty,
        category = kind.category,
        status = "pending",
        progress = 0,
        progressDetails = {},
        createdTime = now,
        expirationGameTime = now + offerMs,
        timeRemaining = offerMs,
        requirements = {},
        reward = { relationship = kind.reward.relationship, money = kind.reward.money },
        penalty = { relationship = kind.penalty.relationship },
        taskData = {},
        playerNotes = "",
        priority = 1,
        currentStep = 1,
        totalSteps = 2,
        -- Steps come only from the declaration: REPORT is not a dialog step
        -- and has no location, TALK is the dialog step.
        steps = {
            { id = 1, contributionStep = NPCCompanion.STEP_REPORT, description = NPCCompanion.GENERIC_STEP_REPORT,
              completed = false, isDialogStep = false },
            { id = 2, contributionStep = NPCCompanion.STEP_TALK, description = NPCCompanion.GENERIC_STEP_TALK,
              completed = false, isDialogStep = true },
        },
        rewardPaid = false,
        rewardPaidPresent = true,
        repaymentCollected = false,
        repaymentCollectedPresent = true,
        loanAmountPresent = false,
        loanAmountDeductedPresent = false,
        ownerFarmIdPresent = false,
        recordRevision = 0,
        f148Schema = 1,
        personRefKind = "durable",
        contributionWorkMs = kind.workHours * NPCCompanion.HOUR_MS,
        contribution = {
            schema = NPCCompanion.CONTRIBUTION_SCHEMA,
            namespace = namespace,
            kindKey = kindKey,
            kindVersion = kind.version,
            targetKind = kind.targetKind,
            targetKey = request.targetKey,
            addressedFarmId = farmId,
            reportOutcome = kind.reportOutcome,
            reportDone = false,
        },
    }
    table.insert(self.activeFavors, favor)
    self:assignRecoveryToken(favor)
    -- A contributed offer does not set favorCooldown.
    if sys ~= nil then sys.syncDirty = true end
    return answer(NPCCompanion.OFFERED, "offered", { favorId = favor.id })
end

-- =========================================================
-- 3.5 Acceptance
-- =========================================================

--- Accept the exact pending contributed row for its addressed farm. Called by
--- NPCSystem:serverAcceptContributedFavor after the event's actor, farm,
--- request-gate and distance checks. Returns ok and a reason token.
function NPCFavorSystem:acceptContributedFavor(favorId, recordRevision, personId, farmId)
    if g_server == nil then return false, "not_server" end
    if not self:isFavorLoadReady() then return false, "unavailable" end
    if self:readCompanionSurface() ~= NPCCompanion.SURFACE_OPEN then return false, "surface_locked" end
    local favor, collection = self:findContributedFavor(favorId)
    if favor == nil or collection ~= "active" or favor.status ~= "pending" then return false, "stale" end
    if (favor.recordRevision or 0) ~= recordRevision then return false, "stale" end
    local now = nowMs()
    if finite(favor.expirationGameTime) and favor.expirationGameTime <= now then return false, "stale" end
    if favor.npcId ~= personId or favor.personRefKind ~= "durable" or self:resolveFavorPerson(favor) == nil then
        return false, "person"
    end
    if not NPCFarmIdentity.isOrdinaryFarmId(farmId) or farmId ~= favor.contribution.addressedFarmId then
        return false, "not_addressed"
    end
    local workMs = favor.contributionWorkMs
    if not finite(workMs) or workMs <= 0 then return false, "stale" end
    favor.status = "active"
    favor.ownerFarmId = farmId
    favor.ownerFarmIdPresent = true
    favor.startTime = now
    favor.expirationGameTime = now + workMs
    favor.timeRemaining = workMs
    favor.contributionWorkMs = nil
    self:bumpRecordRevision(favor)
    if self.npcSystem ~= nil and self.npcSystem.favorHUD ~= nil and self:mayFlashFavor(favor) then
        local msg = string.format("Favor accepted: %s", favor.description or "")
        self.npcSystem.favorHUD:flashFavor(msg, {0.3, 1.0, 0.3, 1})
    end
    return true, "accepted"
end

-- =========================================================
-- 3.6 Report, completion
-- =========================================================

function NPCFavorSystem:reportFavorStep(namespace, report)
    if not NPCCompanion.validNamespace(namespace) then return answer(NPCCompanion.REFUSED, "bad_namespace") end
    if type(report) ~= "table" or not onlyKeys(report, REPORT_KEYS) then return answer(NPCCompanion.REFUSED, "bad_request") end
    if not isInt(report.favorId) or report.favorId < 1 then return answer(NPCCompanion.REFUSED, "bad_request") end
    if not NPCCompanion.validKey(report.outcome) then return answer(NPCCompanion.REFUSED, "bad_outcome") end
    if not NPCFarmIdentity.isOrdinaryFarmIdShape(report.farmId) then return answer(NPCCompanion.REFUSED, "bad_farm") end
    if not self:isFavorLoadReady() then return answer(NPCCompanion.WAIT, "favor_load_waiting") end
    if self:getCompanionProvider(namespace) == nil then return answer(NPCCompanion.REFUSED, "provider_unknown") end
    local surface = self:readCompanionSurface()
    local favor, collection = self:findContributedFavor(report.favorId)
    if favor == nil or favor.contribution.namespace ~= namespace then return answer(NPCCompanion.NO_MATCH, "no_match") end
    local c = favor.contribution
    local pending = favor.status == "pending"
    local farmOf = pending and c.addressedFarmId or favor.ownerFarmId
    if farmOf ~= report.farmId then return answer(NPCCompanion.NO_MATCH, "no_match") end

    -- The reserved outcomes remove the whole obligation without fault. While
    -- LOCKED, pending offers were already withdrawn.
    if NPCCompanion.RESERVED_OUTCOMES[report.outcome] then
        if pending and surface ~= NPCCompanion.SURFACE_OPEN then return answer(NPCCompanion.NO_MATCH, "no_match") end
        self:closeContributionNoFault(favor, report.outcome)
        return answer(NPCCompanion.CLOSED, report.outcome)
    end

    if surface ~= NPCCompanion.SURFACE_OPEN then return answer(NPCCompanion.REFUSED, "surface_locked") end
    if self:companionState().kinds[NPCCompanion.kindId(namespace, c.kindKey)] == nil then
        return answer(NPCCompanion.REFUSED, "kind_undeclared")
    end
    if pending then return answer(NPCCompanion.NO_MATCH, "not_accepted") end
    if collection ~= "active" or not ACTIVE_STATUS[favor.status] or self:isFavorInRecovery(favor) then
        return answer(NPCCompanion.REFUSED, "job_paused")
    end
    if report.outcome ~= c.reportOutcome then return answer(NPCCompanion.REFUSED, "wrong_outcome") end
    if c.reportDone == true then return answer(NPCCompanion.ALREADY_DONE, "already_done") end
    local step = favor.steps and favor.steps[1]
    if type(step) ~= "table" or step.contributionStep ~= NPCCompanion.STEP_REPORT then
        return answer(NPCCompanion.UNAVAILABLE, "bad_record")
    end
    step.completed = true
    c.reportDone = true
    favor.currentStep = 2
    self:bumpRecordRevision(favor)
    if self.npcSystem ~= nil then self.npcSystem.syncDirty = true end
    return answer(NPCCompanion.DONE, "reported")
end

--- The guarded transition of completeFavor for contributed work, called only
--- by the TALK adapter. Pays once through applyFavorRewards' contributed mode.
function NPCFavorSystem:completeContributedFavor(favorId)
    local favor, collection = self:findContributedFavor(favorId)
    if favor == nil or collection ~= "active" or not ACTIVE_STATUS[favor.status] then return false end
    if self:isFavorInRecovery(favor) then return false end
    if not NPCFarmIdentity.isOrdinaryFarmId(favor.ownerFarmId) then return false end
    if self:resolveFavorPerson(favor) == nil then return false end
    if g_server == nil then return false end

    favor.completionTime = g_currentMission.time
    if favor.startTime then
        favor.completionDuration = favor.completionTime - favor.startTime
    end
    favor.status = "completed"
    favor.progress = 100
    self:retireRecoveryToken(favor)
    removeFrom(self.activeFavors, favor)
    table.insert(self.completedFavors, favor)

    self:applyFavorRewards(favor)
    self:updateStats(favor)

    if self.npcSystem.interactionUI then
        self.npcSystem.interactionUI:updateFavorList()
    end
    if self.npcSystem.favorHUD and self:mayFlashFavor(favor) then
        local msg = string.format(g_i18n:getText("npc_hud_completed") or "Done: %s", favor.description or favor.npcName)
        self.npcSystem.favorHUD:flashFavor(msg, {0.3, 1, 0.3, 1})
    end
    return true
end

-- =========================================================
-- 3.8 Recovery commands and 3.9 farm lifecycle
-- =========================================================

local function hasLiveJob(self, npcId)
    for _, live in ipairs(self.activeFavors or {}) do
        if live.npcId == npcId then return true end
    end
    return false
end

--- The contributed Resume predicate: the owning farm, a live proved person,
--- known positive remaining time, complete payment facts, no contribution hold,
--- not person_unproven, and no other open job on the person. Returns nil when
--- resumable, else the refusal key.
function NPCFavorSystem:contributedResumeRefusal(actor, favor)
    local R = NPCFavorRecovery
    if actor == nil or not NPCFarmIdentity.isOrdinaryFarmId(favor.ownerFarmId)
        or actor.farmId == nil or actor.farmId ~= favor.ownerFarmId then
        return "npc_recovery_refused_not_owner"
    end
    if favor.contributionHeld == true then return "npc_recovery_refused_not_resumable" end
    if favor.personUnproven == true or favor.recoveryReason == R.REASON_PERSON_UNPROVEN then
        return "npc_recovery_unavail_person"
    end
    if favor.timeRemainingRaw ~= nil or not finite(favor.timeRemaining) or favor.timeRemaining <= 0 then
        return "npc_recovery_unavail_time"
    end
    if not R.paymentFactsKnown(favor) then return "npc_recovery_unavail_facts" end
    if self:resolveFavorPerson(favor) == nil then return "npc_recovery_unavail_waiting" end
    if hasLiveJob(self, favor.npcId) then return "npc_recovery_refused_live_job" end
    return nil
end

--- LET_GO is for held work the farmer cannot resume: a contribution hold, or a
--- person that could not be proved.
function NPCFavorSystem:contributedLetGoAllowed(favor)
    return favor.contributionHeld == true or favor.personUnproven == true
        or favor.recoveryReason == NPCFavorRecovery.REASON_PERSON_UNPROVEN
end

--- One recovery command on a contributed row whose exact record and revision
--- the caller has already resolved. Returns a result code and a message key.
function NPCFavorSystem:contributedRecoveryCommand(actor, op, favor)
    local R = NPCFavorRecovery
    -- A lock or a provider change takes effect before anything is decided.
    self:readCompanionSurface()
    if op == R.OP_RESUME then
        if not contains(self.recoveryFavors, favor) or favor.status ~= PAUSED then
            return R.RESULT_NO_LONGER_PAUSED, "npc_recovery_no_longer_paused"
        end
        local hold = self:contributionHoldFor(favor)
        if hold ~= nil then self:holdContributedFavor(favor, hold) end
        local refusal = self:contributedResumeRefusal(actor, favor)
        if refusal ~= nil then return R.RESULT_REFUSED, refusal end
        removeFrom(self.recoveryFavors, favor)
        favor.status = (favor.originalStatus == "in_progress") and "in_progress" or "active"
        favor.originalStatus = nil
        favor.originalOwnerFarmId = nil
        favor.recoveryReason = nil
        favor.resumable = nil
        favor.expirationGameTime = nowMs() + favor.timeRemaining
        self:retireRecoveryToken(favor)
        self:bumpRecordRevision(favor)
        table.insert(self.activeFavors, favor)
        self:assignRecoveryToken(favor)
        if self.npcSystem ~= nil then self.npcSystem.syncDirty = true end
        return R.RESULT_OK, "npc_recovery_ok_resumed"
    elseif op == R.OP_LET_GO then
        -- The verified owning farm only; masters get no exception. Available
        -- while the surface is LOCKED.
        if actor == nil or not NPCFarmIdentity.isOrdinaryFarmId(favor.ownerFarmId)
            or actor.farmId == nil or actor.farmId ~= favor.ownerFarmId then
            return R.RESULT_REFUSED, "npc_recovery_refused_not_owner"
        end
        if not contains(self.recoveryFavors, favor) or favor.status ~= PAUSED then
            return R.RESULT_NO_LONGER_PAUSED, "npc_recovery_no_longer_paused"
        end
        if not self:contributedLetGoAllowed(favor) then
            return R.RESULT_REFUSED, "npc_recovery_refused_operation"
        end
        self:closeContributionNoFault(favor, "let_go")
        return R.RESULT_OK, "npc_contrib_let_go"
    end
    -- ASSIGN, COMPLETE and ABANDON never act on companion work.
    return R.RESULT_REFUSED, "npc_recovery_refused_operation"
end

--- 3.9: close, without fault, every open contributed row in either collection
--- whose owning or addressed farm is this farm number.
function NPCFavorSystem:closeContributionsForFarm(farmId)
    local closed = 0
    for _, favor in ipairs(self:collectContributed(nil, true)) do
        if favor.ownerFarmId == farmId or favor.contribution.addressedFarmId == farmId then
            self:closeContributionNoFault(favor, "farm_gone")
            closed = closed + 1
        end
    end
    return closed
end

-- =========================================================
-- 3.10 Save and load
-- =========================================================

--- A deep copy of a saved row or block (primitives and nested tables).
function NPCCompanion.copyRow(row)
    if type(row) ~= "table" then return row end
    local out = {}
    for k, v in pairs(row) do out[k] = NPCCompanion.copyRow(v) end
    return out
end

--- The saved contribution block of one accepted or held row (both writers).
--- The copied reward rides in the ordinary rewardRelationship / rewardMoney.
function NPCCompanion.exportBlock(favor)
    local c = favor.contribution
    return {
        schema = c.schema,
        namespace = c.namespace,
        kindKey = c.kindKey,
        kindVersion = c.kindVersion,
        targetKind = c.targetKind,
        targetKey = c.targetKey,
        addressedFarmId = c.addressedFarmId,
        reportOutcome = c.reportOutcome,
        reportDone = c.reportDone == true,
        held = favor.contributionHeld == true,
        holdReason = favor.contributionHoldReason,
        penaltyRelationship = (type(favor.penalty) == "table" and favor.penalty.relationship) or 0,
    }
end

--- Decode a schema 1 block into a live contribution, or nil when it is any
--- other schema or does not hold together. Nothing here trusts the save.
function NPCCompanion.decodeBlock(block)
    if type(block) ~= "table" or block.schema ~= NPCCompanion.CONTRIBUTION_SCHEMA then return nil end
    if not NPCCompanion.validNamespace(block.namespace) or not NPCCompanion.validKey(block.kindKey) then return nil end
    if not intIn(block.kindVersion, 1, 65535) then return nil end
    if block.targetKind == NPCCompanion.TARGET_FIELD then
        if not validTargetKey(block.targetKey) then return nil end
    elseif block.targetKind ~= NPCCompanion.TARGET_NONE or block.targetKey ~= nil then
        return nil
    end
    if not NPCFarmIdentity.isOrdinaryFarmIdShape(block.addressedFarmId) then return nil end
    if not NPCCompanion.validKey(block.reportOutcome) or NPCCompanion.RESERVED_OUTCOMES[block.reportOutcome] then return nil end
    if type(block.reportDone) ~= "boolean" then return nil end
    if not intIn(block.penaltyRelationship, -15, 0) then return nil end
    return {
        schema = NPCCompanion.CONTRIBUTION_SCHEMA,
        namespace = block.namespace,
        kindKey = block.kindKey,
        kindVersion = block.kindVersion,
        targetKind = block.targetKind,
        targetKey = block.targetKey,
        addressedFarmId = block.addressedFarmId,
        reportOutcome = block.reportOutcome,
        reportDone = block.reportDone,
    }
end

local function knownBool(present, value)
    if present == true and type(value) == "boolean" then return value, true end
    return nil, false
end

--- An unsupported or broken contribution row: kept in Recovery, inspect-only,
--- never decoded, paid, resumed or reassigned, and written back as it was read.
local function inertRecord(saved)
    return {
        npcId = saved.npcId or 0,
        npcName = saved.npcName or "",
        type = tostring(saved.type or ""),
        name = "",
        description = (type(saved.description) == "string") and saved.description or "",
        status = PAUSED,
        recoveryReason = NPCFavorRecovery.REASON_INVALID_RECORD,
        resumable = false,
        progress = 0,
        progressDetails = {},
        createdTime = nowMs(),
        timeRemaining = 0,
        timeRemainingRaw = "contribution_unsupported",
        requirements = {},
        reward = {},
        penalty = {},
        taskData = {},
        steps = {},
        currentStep = 1,
        totalSteps = 1,
        ownerFarmId = (saved.ownerFarmIdPresent == true) and saved.ownerFarmId or nil,
        ownerFarmIdPresent = saved.ownerFarmIdPresent == true and saved.ownerFarmId ~= nil,
        rewardPaidPresent = false,
        repaymentCollectedPresent = false,
        loanAmountPresent = false,
        loanAmountDeductedPresent = false,
        recoveredFromLegacy = false,
        recordRevision = 0,
        f148Schema = NPCFavorRecovery.SCHEMA,
        contributionInert = true,
        inertSavedRow = NPCCompanion.copyRow(saved),
    }
end

--- Restore one saved row that carries a contribution block (section 3.10).
--- Returns the record and its collection, or nil and a reason. A schema 1
--- accepted or held job rebuilds its two fixed steps from the block and enters
--- Recovery held: WORK_OFF while the surface is LOCKED, otherwise
--- COMPANION_MISSING until its kind is declared and compatible (the
--- re-evaluation after the snapshot installs does the rest). Any saved F148 or
--- F357 pause reason is kept.
function NPCFavorSystem:restoreContributedFavor(saved)
    local c = NPCCompanion.decodeBlock(saved.contribution)
    local st = saved.status
    if c ~= nil and st == "pending" then
        -- A companion offer is never saved; one found in a save is not restored.
        return nil, "withdrawn"
    end
    local original = st
    if st == PAUSED then original = saved.originalStatus end
    local ownerShape = saved.ownerFarmIdPresent == true and NPCFarmIdentity.isOrdinaryFarmIdShape(saved.ownerFarmId)
    if c == nil or not ACTIVE_STATUS[original] or not ownerShape then
        return inertRecord(saved), "recovery"
    end
    -- 3.9: work whose owning or addressed farm is gone closes without fault.
    if not NPCFarmIdentity.isOrdinaryFarmId(saved.ownerFarmId) or not NPCFarmIdentity.isOrdinaryFarmId(c.addressedFarmId) then
        return nil, "withdrawn"
    end

    local timeRemaining = (saved.timeRemainingPresent == true) and saved.timeRemaining or nil
    local timeOk = finite(timeRemaining)
    local rewardPaid, rewardPaidKnown = knownBool(saved.rewardPaidPresent, saved.rewardPaid)
    local repayment, repaymentKnown = knownBool(saved.repaymentCollectedPresent, saved.repaymentCollected)
    local kind = self:companionState().kinds[NPCCompanion.kindId(c.namespace, c.kindKey)]
    local description = saved.description
    if type(description) ~= "string" or description == "" then description = NPCCompanion.GENERIC_DESC end
    local reason = nil
    if st == PAUSED and type(saved.recoveryReason) == "string" and saved.recoveryReason ~= "" then
        reason = saved.recoveryReason
    end
    local record = {
        id = nil,
        npcId = saved.npcId or 0,
        npcName = saved.npcName or "",
        type = NPCCompanion.kindId(c.namespace, c.kindKey),
        name = "",
        description = description,
        difficulty = kind and kind.difficulty or 1,
        category = kind and kind.category or "misc",
        status = PAUSED,
        originalStatus = original,
        progress = c.reportDone and 50 or 0,
        progressDetails = {},
        createdTime = nowMs(),
        expirationGameTime = nil,
        timeRemaining = timeOk and timeRemaining or 0,
        timeRemainingRaw = (not timeOk) and tostring(saved.timeRemaining) or nil,
        requirements = {},
        reward = { relationship = tonumber(saved.rewardRelationship) or 0, money = tonumber(saved.rewardMoney) or 0 },
        penalty = { relationship = saved.contribution.penaltyRelationship },
        taskData = {},
        ownerFarmId = saved.ownerFarmId,
        ownerFarmIdPresent = true,
        rewardPaid = rewardPaid,
        rewardPaidPresent = rewardPaidKnown,
        repaymentCollected = repayment,
        repaymentCollectedPresent = repaymentKnown,
        loanAmountPresent = false,
        loanAmountDeductedPresent = false,
        awaitingConfirmation = false,
        recoveredFromLegacy = false,
        recoveryReason = reason,
        resumable = (reason ~= nil and saved.resumable == true) or nil,
        originalOwnerFarmId = (saved.originalOwnerFarmIdPresent == true) and saved.originalOwnerFarmId or nil,
        recordRevision = 0,
        playerNotes = "",
        priority = 1,
        currentStep = c.reportDone and 2 or 1,
        totalSteps = 2,
        steps = {
            { id = 1, contributionStep = NPCCompanion.STEP_REPORT, description = NPCCompanion.GENERIC_STEP_REPORT,
              completed = c.reportDone, isDialogStep = false },
            { id = 2, contributionStep = NPCCompanion.STEP_TALK, description = NPCCompanion.GENERIC_STEP_TALK,
              completed = false, isDialogStep = true },
        },
        f148Schema = NPCFavorRecovery.SCHEMA,
        contribution = c,
        contributionHeld = true,
        contributionHoldReason = self:isCompanionSurfaceOpen() and NPCCompanion.HOLD_COMPANION_MISSING
            or NPCCompanion.HOLD_WORK_OFF,
    }
    return record, "recovery"
end

--- After F357's person proof: a person that could not be proved gives the
--- held row the person_unproven reason beside its hold (LET_GO is then its
--- exit). A provider person merely waiting for her companion's claim adds
--- nothing: the hold already covers that wait, and if she is still away when
--- the hold clears, the row takes F357's neighbour pause then.
function NPCFavorSystem:finishRestoredContribution(record)
    if record.recoveryReason ~= nil then return end
    if record.personUnproven == true then
        record.recoveryReason = NPCFavorRecovery.REASON_PERSON_UNPROVEN
        record.resumable = false
    end
end

--- A contributed row's notice shows only on the addressed or owning farm's
--- own HUD; a dedicated server (no ordinary local farm) shows none.
function NPCFavorSystem:mayFlashFavor(favor)
    if not NPCCompanion.isContributed(favor) then return true end
    local localFarm = NPCFarmIdentity.localClaimFarmId()
    if localFarm == nil then return false end
    return localFarm == favor.ownerFarmId or localFarm == favor.contribution.addressedFarmId
end
