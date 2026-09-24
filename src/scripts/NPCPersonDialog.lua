-- =========================================================
-- FS25 NPC Favor - Person dialog: server dispatcher and client adapters (RSF-F357 section 9)
-- =========================================================
-- Author: TisonK
-- =========================================================
-- COPYRIGHT NOTICE:
-- All rights reserved. Unauthorized redistribution, copying,
-- or claiming this code as your own is strictly prohibited.
-- Original author: TisonK
-- =========================================================
-- Remote dialogs carry intent; host state alone mutates. Loaded directly after
-- NPCSystem.lua; every function here is a method on NPCSystem (the dispatcher and
-- the adapters live on the mission handle) or a helper in NPCPersonDialog.
--
-- SERVER: serverPersonDialogRequest resolves the actor from the connection, keeps
-- one latest request and reply per connection plus a monotonically increasing
-- request high-water mark (a larger id is a fresh validation; the latest id with
-- the identical request re-sends its result without rerolling a decline, crediting
-- Talk again or creating another offer; the same id with a changed request is
-- refused; older ids are stale and never executed). TALK applies the existing +1
-- daily_interaction input through the relationship owner's own day and mood rules.
-- OFFER_HELP keeps the current threshold, decline chance, reward and generation
-- rules but runs them on the server; an existing unaccepted offer is returned, not
-- duplicated. VIEW refreshes the dialog view for an entitled actor. VIEW_WORK is
-- the one farm-private read: the actor's own accepted work plus the positively
-- unaccepted offers, at most 20 rows per page, no proximity required.
--
-- CLIENT: the four adapters of section 9a and 9b. requestPersonDialogAction
-- allocates the request id and routes the operation (work actions through
-- NPCInteractionEvent, the rest through the request event); getPersonDialogView
-- and getPersonalWorkView return copied schema-1 views that read unavailable before
-- a valid reply, after an actor, farm or person change, or on failed readiness.
-- One shared work page, at most one outstanding request, a 2-second refresh while
-- something watches it, last-confirmed after two missed intervals.
-- =========================================================

NPCPersonDialog = NPCPersonDialog or {}

NPCPersonDialog.REFRESH_INTERVAL_MS = 2000
NPCPersonDialog.STALE_AFTER_MS = 4000
NPCPersonDialog.MAX_SESSIONS = 256

local ACTIVE_STATUS = { active = true, in_progress = true }

local function isFiniteNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function nowMs()
    if TimeHelper ~= nil and TimeHelper.getGameTimeMs ~= nil then return TimeHelper.getGameTimeMs() end
    return (g_currentMission and g_currentMission.time) or 0
end

local function textString(s)
    if NPCPersonDialog.textString ~= nil then return NPCPersonDialog.textString(s) end
    return tostring(s or ""):sub(1, 256)
end

-- =========================================================
-- Server: per-connection request gate
-- =========================================================

function NPCSystem:_dialogSessionFor(actor)
    self.dialogSessions = self.dialogSessions or {}
    self.dialogSessionOrder = self.dialogSessionOrder or {}
    local key = actor.connectionId
    local session = self.dialogSessions[key]
    if session == nil then
        session = { highWater = 0, latest = nil, connection = actor.connection }
        self.dialogSessions[key] = session
        self.dialogSessionOrder[#self.dialogSessionOrder + 1] = key
        while #self.dialogSessionOrder > NPCPersonDialog.MAX_SESSIONS do
            local oldest = table.remove(self.dialogSessionOrder, 1)
            self.dialogSessions[oldest] = nil
        end
    end
    return session
end

--- The gate every dialog request and work action passes. Returns one of
--- "fresh", "replay" (plus the retained reply), "changed", "stale", "exhausted".
--- A replay re-validates the current farm: a changed farm is not a replay.
function NPCSystem:dialogRequestGate(actor, requestId, fingerprint)
    if actor == nil or not NPCFarmIdentity.validWireNumber(requestId) then return "stale", nil end
    local id = tonumber(requestId)
    if id >= NPCFarmIdentity.WIRE_MAX then return "exhausted", nil end
    local session = self:_dialogSessionFor(actor)
    if id < session.highWater then return "stale", nil end
    if id == session.highWater and session.latest ~= nil then
        if session.latest.fingerprint ~= fingerprint then return "changed", nil end
        if session.latest.farmId ~= actor.farmId then return "changed", nil end
        return "replay", session.latest.reply
    end
    session.highWater = id
    session.latest = { fingerprint = fingerprint, farmId = actor.farmId, reply = nil }
    return "fresh", nil
end

--- Retain the reply of the latest request so an identical repeat replays it.
function NPCSystem:dialogRequestRecord(actor, requestId, reply)
    if actor == nil then return end
    local session = self:_dialogSessionFor(actor)
    if session.latest ~= nil and session.highWater == tonumber(requestId) then
        session.latest.reply = reply
    end
end

--- Disconnect or mission teardown clears the transient state.
function NPCSystem:clearDialogSession(connectionId)
    if self.dialogSessions == nil then return end
    if connectionId == nil then
        self.dialogSessions, self.dialogSessionOrder = {}, {}
        return
    end
    if self.dialogSessions[connectionId] ~= nil then
        self.dialogSessions[connectionId] = nil
        for i = #self.dialogSessionOrder, 1, -1 do
            if self.dialogSessionOrder[i] == connectionId then table.remove(self.dialogSessionOrder, i) end
        end
    end
end

-- =========================================================
-- Server: copied views
-- =========================================================

--- The next open step of a favour, for display.
local function nextStep(favor)
    if type(favor.steps) ~= "table" then return nil end
    for _, step in ipairs(favor.steps) do
        if type(step) == "table" and not step.completed then return step end
    end
    return nil
end

--- Whether the record's own facts allow completion through the dialog: every
--- earlier step done and the current one a dialog or loan-repay step, or the
--- existing awaiting-confirmation condition. Re-derived on the server; client
--- step flags are never trusted.
function NPCPersonDialog.completionEligible(favor)
    if type(favor) ~= "table" then return false, nil end
    if favor.awaitingConfirmation == true then return true, nil end
    if type(favor.steps) ~= "table" then return false, nil end
    for _, step in ipairs(favor.steps) do
        if type(step) == "table" and not step.completed then
            if step.isDialogStep or step.isLoanRepayStep then
                local priorDone = true
                for _, s2 in ipairs(favor.steps) do
                    if type(s2) == "table" and (s2.id or 0) < (step.id or 0) and not s2.completed then
                        priorDone = false
                        break
                    end
                end
                return priorDone, step
            end
            return false, step
        end
    end
    return false, nil
end

--- A positively clean unaccepted offer: pending, unowned, unpaid, unprogressed, unexpired.
function NPCPersonDialog.isPublicOffer(favor, now)
    if type(favor) ~= "table" or favor.status ~= "pending" then return false end
    if favor.ownerFarmId ~= nil or favor.ownerFarmIdPresent == true then return false end
    if favor.rewardPaid == true or favor.repaymentCollected == true then return false end
    if (favor.progress or 0) > 0 or favor.awaitingConfirmation == true then return false end
    if favor.recoveredFromLegacy == true then return false end
    if isFiniteNumber(favor.expirationGameTime) and now ~= nil and favor.expirationGameTime <= now then return false end
    return true
end

--- One copied work row for a verified actor. The person is named by durable
--- number only when the favour is durable and she is a unique live person;
--- otherwise the row carries the saved name and the unproven flag.
function NPCSystem:describeWorkRow(favor, actor)
    local fav = self.favorSystem
    local person = nil
    if favor.personRefKind == "durable" and fav ~= nil and fav.resolveFavorPerson ~= nil then
        person = fav:resolveFavorPerson(favor)
    end
    local now = nowMs()
    local step = nextStep(favor)
    local owned = ACTIVE_STATUS[favor.status] == true and actor.farmId ~= nil and favor.ownerFarmId == actor.farmId
    local offer = NPCPersonDialog.isPublicOffer(favor, now)
    local eligible = owned and person ~= nil and favor.recoveredFromLegacy ~= true and NPCPersonDialog.completionEligible(favor)
    local timeRemaining = favor.timeRemaining
    if isFiniteNumber(favor.expirationGameTime) then timeRemaining = favor.expirationGameTime - now end
    local reward = favor.reward
    local rewardMoney = (type(reward) == "table" and (reward.money or reward.amount or 0)) or (tonumber(reward) or 0)
    local td = favor.taskData or {}
    local row = {
        token = NPCFarmIdentity.encodeWireNumber(favor.recoveryToken) or "",
        recordRevision = NPCFarmIdentity.encodeWireNumber(favor.recordRevision or 0) or "0",
        personIdPresent = person ~= nil,
        personId = person ~= nil and person.id or 0,
        npcName = textString(favor.npcName or (person and person.name) or ""),
        status = tostring(favor.status or ""),
        type = tostring(favor.type or ""),
        description = textString(favor.description or ""),
        progress = isFiniteNumber(favor.progress) and favor.progress or 0,
        timeKnown = favor.timeRemainingRaw == nil and isFiniteNumber(timeRemaining),
        timeRemainingMs = (favor.timeRemainingRaw == nil and isFiniteNumber(timeRemaining)) and timeRemaining or 0,
        rewardMoney = isFiniteNumber(rewardMoney) and rewardMoney or 0,
        nextStepText = textString(step and step.description or ""),
        nextStepId = step and step.id or 0,
        nextStepLocationPresent = step ~= nil and type(step.location) == "table"
            and isFiniteNumber(step.location.x) and isFiniteNumber(step.location.z),
        nextStepX = 0, nextStepZ = 0,
        isDialogStep = step ~= nil and step.isDialogStep == true,
        isLoanRepayStep = step ~= nil and step.isLoanRepayStep == true,
        awaitingConfirmation = favor.awaitingConfirmation == true,
        loanAmountPresent = favor.loanAmountPresent == true and isFiniteNumber(td.loanAmount),
        loanAmount = (favor.loanAmountPresent == true and isFiniteNumber(td.loanAmount)) and td.loanAmount or 0,
        recoveredFromLegacy = favor.recoveredFromLegacy == true,
        canAccept = offer and person ~= nil,
        canComplete = eligible == true,
        canAbandon = owned and person ~= nil and favor.recoveredFromLegacy ~= true,
        completed = favor.status == "completed",
    }
    if row.nextStepLocationPresent then
        row.nextStepX, row.nextStepZ = step.location.x, step.location.z
    end
    return row
end

--- The farm-private work page: the actor's own active work and the public
--- offers, by token, at most 20 rows after the cursor, the total known for
--- this request. An unready favour load is UNAVAILABLE with no claimed zero.
function NPCSystem:serverPersonalWorkPage(actor, requestId, cursor)
    local fav = self.favorSystem
    local reply = {
        requestId = requestId, kind = NPCPersonDialog.KIND_WORK_PAGE, op = NPCPersonDialog.OP_VIEW_WORK,
        personId = 0, farmId = actor.farmId or 0, result = NPCPersonDialog.RESULT_UNAVAILABLE,
        messageKey = "", text = "", cursor = cursor or "", nextCursor = "", total = 0, totalKnown = false,
        sampledTime = nowMs(), completedCount = 0, completedKnown = false, rows = {},
    }
    if actor.farmId == nil then
        reply.messageKey = "npc_dialog_refused_farm"
        return reply
    end
    if fav == nil or (fav.isFavorLoadReady ~= nil and not fav:isFavorLoadReady())
        or (self.people ~= nil and not self.people:isReady()) or fav._recoveryCounterExhausted then
        reply.messageKey = "npc_work_view_unavailable"
        return reply
    end
    local now = nowMs()
    local visible = {}
    for _, favor in ipairs(fav.activeFavors or {}) do
        if favor.recoveryToken == nil and fav.assignRecoveryToken ~= nil then fav:assignRecoveryToken(favor) end
        local owned = ACTIVE_STATUS[favor.status] == true and favor.ownerFarmId == actor.farmId
        if favor.recoveryToken ~= nil and (owned or NPCPersonDialog.isPublicOffer(favor, now)) then
            visible[#visible + 1] = favor
        end
    end
    table.sort(visible, function(a, b) return a.recoveryToken < b.recoveryToken end)
    local after = (cursor ~= nil and cursor ~= "") and tonumber(cursor) or 0
    reply.total, reply.totalKnown = #visible, true
    for _, favor in ipairs(visible) do
        if favor.recoveryToken > after then
            if #reply.rows >= NPCPersonDialog.WORK_PAGE_ROWS then
                reply.nextCursor = reply.rows[#reply.rows].token
                break
            end
            reply.rows[#reply.rows + 1] = self:describeWorkRow(favor, actor)
        end
    end
    -- The owner's own completed count for this farm (a summary, not history).
    if type(fav.getCompletedFavors) == "function" then
        local count = 0
        for _, favor in ipairs(fav:getCompletedFavors() or {}) do
            if favor.ownerFarmId == actor.farmId then count = count + 1 end
        end
        reply.completedCount, reply.completedKnown = count, true
    end
    reply.result = NPCPersonDialog.RESULT_OK
    return reply
end

--- The copied dialog view of one person for an entitled actor: the pending
--- offer (token, revision, presentation) when there is one, or the actor
--- farm's accepted work, else nothing. Another farm's accepted work reads
--- BUSY, never its details.
function NPCSystem:serverPersonDialogView(actor, npc, requestId, op)
    local fav = self.favorSystem
    local reply = {
        requestId = requestId, kind = NPCPersonDialog.KIND_DIALOG, op = op, personId = npc.id,
        farmId = actor.farmId or 0, result = NPCPersonDialog.RESULT_NO_WORK, messageKey = "npc_dialog_no_work",
        text = "", trustPresent = isFiniteNumber(npc.relationship), trust = isFiniteNumber(npc.relationship) and npc.relationship or 0,
        cursor = "", nextCursor = "", total = 0, totalKnown = false, sampledTime = nowMs(),
        completedCount = 0, completedKnown = false, rows = {},
    }
    if fav == nil then return reply end
    local now = nowMs()
    for _, favor in ipairs(fav.activeFavors or {}) do
        if favor.npcId == npc.id then
            if favor.recoveryToken == nil and fav.assignRecoveryToken ~= nil then fav:assignRecoveryToken(favor) end
            if NPCPersonDialog.isPublicOffer(favor, now) then
                reply.rows[#reply.rows + 1] = self:describeWorkRow(favor, actor)
                reply.result, reply.messageKey = NPCPersonDialog.RESULT_OFFER, "npc_dialog_offer"
                return reply
            elseif ACTIVE_STATUS[favor.status] then
                if favor.ownerFarmId == actor.farmId then
                    reply.rows[#reply.rows + 1] = self:describeWorkRow(favor, actor)
                    reply.result, reply.messageKey = NPCPersonDialog.RESULT_ACCEPTED, "npc_dialog_accepted"
                else
                    reply.result, reply.messageKey = NPCPersonDialog.RESULT_BUSY, "npc_dialog_busy"
                end
                return reply
            end
        end
    end
    return reply
end

-- =========================================================
-- Server: the dispatcher
-- =========================================================

--- One request from a verified connection (nil is the verified local host).
--- @return table|nil reply, for the requester only
function NPCSystem:serverPersonDialogRequest(connection, request)
    if not self.isServer or type(request) ~= "table" then return nil end
    local actor = NPCFarmIdentity.resolveActor(connection)
    if actor == nil then return nil end
    local op = request.op
    if not NPCFarmIdentity.isInteger(op) or op < NPCPersonDialog.OP_MIN or op > NPCPersonDialog.OP_MAX then return nil end
    local requestId = request.requestId
    if not NPCFarmIdentity.validWireNumber(requestId) then return nil end
    local personId = request.personId
    local cursor = request.cursor or ""
    if cursor ~= "" and not NPCFarmIdentity.validToken(cursor) then return nil end

    local function refused(result, key)
        return { requestId = requestId, kind = NPCPersonDialog.KIND_DIALOG, op = op, personId = personId or 0,
            farmId = actor.farmId or 0, result = result, messageKey = key or "", text = "", rows = {},
            cursor = "", nextCursor = "", total = 0, totalKnown = false, sampledTime = nowMs() }
    end

    local fingerprint = table.concat({ tostring(op), tostring(personId or 0), tostring(cursor) }, "|")
    local gate, cached = self:dialogRequestGate(actor, requestId, fingerprint)
    if gate == "stale" then return nil end
    if gate == "replay" then return cached end
    if gate == "changed" then return refused(NPCPersonDialog.RESULT_REFUSED, "npc_dialog_refused_request_reuse") end
    if gate == "exhausted" then return refused(NPCPersonDialog.RESULT_UNAVAILABLE, "npc_dialog_unavailable") end

    local reply
    if op == NPCPersonDialog.OP_VIEW_WORK then
        if actor.farmId == nil then
            reply = refused(NPCPersonDialog.RESULT_REFUSED, "npc_dialog_refused_farm")
        else
            reply = self:serverPersonalWorkPage(actor, requestId, cursor)
        end
    else
        reply = self:_serverPersonScopedRequest(actor, op, personId, requestId, refused)
    end
    self:dialogRequestRecord(actor, requestId, reply)
    return reply
end

--- TALK, OFFER_HELP and VIEW: the actor's ordinary farm, person READY and
--- actionable, and the acting player's own distance are re-resolved before
--- anything happens.
function NPCSystem:_serverPersonScopedRequest(actor, op, personId, requestId, refused)
    if actor.farmId == nil then
        return refused(NPCPersonDialog.RESULT_REFUSED, "npc_dialog_refused_farm")
    end
    if self.people == nil or not self.people:isReady() then
        return refused(NPCPersonDialog.RESULT_UNAVAILABLE, "npc_person_loading")
    end
    local npc = self:getNPCById(personId)
    if npc == nil or not self:isPersonActionable(npc) then
        return refused(NPCPersonDialog.RESULT_REFUSED, "npc_dialog_refused_person")
    end
    local dist = NPCInteractionEvent ~= nil and NPCInteractionEvent.actorDistanceTo(actor, npc) or nil
    if dist == nil or dist > (NPCInteractionEvent and NPCInteractionEvent.MAX_INTERACTION_DISTANCE or 15) then
        return refused(NPCPersonDialog.RESULT_REFUSED, "npc_dialog_refused_far")
    end

    if op == NPCPersonDialog.OP_VIEW then
        return self:serverPersonDialogView(actor, npc, requestId, op)
    end

    if op == NPCPersonDialog.OP_TALK then
        local rm = self.relationshipManager
        local applied = false
        if rm ~= nil and rm.updateRelationship ~= nil then
            applied = rm:updateRelationship(npc.id, 1, "daily_interaction") == true
        end
        local topic = ""
        if self.interactionUI ~= nil and self.interactionUI.getRandomConversationTopic ~= nil then
            local ok, t = pcall(self.interactionUI.getRandomConversationTopic, self.interactionUI, npc)
            if ok and type(t) == "string" then topic = t end
        end
        local toneKey = ""
        if self.favorSystem ~= nil and self.favorSystem.analyzeEncounterHistory ~= nil then
            local ok, memory = pcall(self.favorSystem.analyzeEncounterHistory, self.favorSystem, npc)
            if ok and type(memory) == "table" then
                local score = memory.memoryScore or 0
                if score > 0.6 then toneKey = "npc_dialog_tone_warm"
                elseif score < -0.6 then toneKey = "npc_dialog_tone_cold"
                elseif score < -0.2 then toneKey = "npc_dialog_tone_cool" end
            end
        end
        local reply = self:serverPersonDialogView(actor, npc, requestId, op)
        reply.result = applied and NPCPersonDialog.RESULT_OK or NPCPersonDialog.RESULT_LIMIT
        reply.messageKey = applied and "npc_dialog_talk_ok" or "npc_dialog_talk_limit"
        reply.text = textString(topic)
        reply.toneKey = toneKey
        reply.trustPresent = isFiniteNumber(npc.relationship)
        reply.trust = isFiniteNumber(npc.relationship) and npc.relationship or 0
        if applied then self.syncDirty = true end
        return reply
    end

    if op == NPCPersonDialog.OP_OFFER_HELP then
        local fav = self.favorSystem
        if fav == nil or (fav.isFavorLoadReady ~= nil and not fav:isFavorLoadReady()) then
            return refused(NPCPersonDialog.RESULT_UNAVAILABLE, "npc_work_view_unavailable")
        end
        -- The current threshold and the existing offer come first: an existing
        -- unaccepted offer is returned, never duplicated; another farm's
        -- accepted work reads busy.
        local existing = self:serverPersonDialogView(actor, npc, requestId, op)
        if existing.result == NPCPersonDialog.RESULT_OFFER or existing.result == NPCPersonDialog.RESULT_ACCEPTED
            or existing.result == NPCPersonDialog.RESULT_BUSY then
            return existing
        end
        if (npc.relationship or 0) < 25 then
            return refused(NPCPersonDialog.RESULT_REFUSED, "npc_dialog_refused_relationship")
        end
        local result = fav:generateFavorForNPC(npc, true, actor.farmId)
        if result == "declined" then
            local r = refused(NPCPersonDialog.RESULT_DECLINED, "npc_dialog_declined")
            r.text = textString(npc.personality or "")
            return r
        end
        if result == nil then
            return refused(NPCPersonDialog.RESULT_NO_WORK, "npc_dialog_no_work")
        end
        if fav.assignRecoveryToken ~= nil then fav:assignRecoveryToken(result) end
        self.syncDirty = true
        local reply = self:serverPersonDialogView(actor, npc, requestId, op)
        reply.text = textString(npc.personality or "")
        return reply
    end

    return refused(NPCPersonDialog.RESULT_REFUSED, "npc_dialog_refused_operation")
end

-- =========================================================
-- Client adapters (section 9a and 9b)
-- =========================================================

function NPCSystem:_dialogClient()
    if self.dialogClient == nil then
        self.dialogClient = {
            nextRequestId = 1,
            exhausted = false,
            context = nil,          -- { personId, farmId }
            pending = nil,          -- { requestId, op, personId }
            lastReply = nil,        -- the latest matched reply for the context
            work = { rows = {}, total = nil, totalKnown = false, cursor = "", nextCursor = "", farmId = nil,
                     receivedAt = nil, requestedAt = nil, pendingRequestId = nil, state = "UNAVAILABLE",
                     reasonKey = "", completedCount = nil, completedKnown = false, sampledTime = 0 },
            watchers = 0,
            refreshTimerMs = 0,
        }
    end
    return self.dialogClient
end

--- The client request id allocator: monotonic for the mission, never reset
--- on a dialog open; exhaustion refuses further requests until reconnect.
function NPCSystem:allocateDialogRequestId()
    local c = self:_dialogClient()
    if c.exhausted or c.nextRequestId >= NPCFarmIdentity.WIRE_MAX then
        c.exhausted = true
        return nil
    end
    local id = c.nextRequestId
    c.nextRequestId = id + 1
    return NPCFarmIdentity.encodeWireNumber(id)
end

--- The dialog adapter's presentation context: opened for one person by the UI,
--- cleared on close. Delayed replies cannot reopen or retarget it.
function NPCSystem:beginPersonDialog(personId)
    local c = self:_dialogClient()
    c.context = { personId = personId, farmId = NPCFarmIdentity.localClaimFarmId() }
    c.pending = nil
    c.lastReply = nil
end

function NPCSystem:endPersonDialog()
    local c = self:_dialogClient()
    c.context = nil
    c.pending = nil
    c.lastReply = nil
end

--- Farm change, disconnect, mission change or host unavailability clears
--- every private view at once.
function NPCSystem:clearPrivateViews()
    local c = self:_dialogClient()
    c.context, c.pending, c.lastReply = nil, nil, nil
    c.work = { rows = {}, total = nil, totalKnown = false, cursor = "", nextCursor = "", farmId = nil,
               receivedAt = nil, requestedAt = nil, pendingRequestId = nil, state = "UNAVAILABLE",
               reasonKey = "", completedCount = nil, completedKnown = false, sampledTime = 0 }
end

local WORK_ACTIONS = {
    ACCEPT_OFFER = "ACTION_FAVOR_ACCEPT",
    COMPLETE_WORK = "ACTION_FAVOR_COMPLETE",
    ABANDON_WORK = "ACTION_FAVOR_ABANDON",
}

--- A work action bound to the work shown, from any reader (the face-to-face
--- dialog, the management dialog, the PDA): ACCEPT_OFFER, COMPLETE_WORK or
--- ABANDON_WORK with the row's token and revision, through the existing
--- work-action event. Returns true when a request was issued (pending).
function NPCSystem:requestWorkAction(operation, personId, selection)
    local c = self:_dialogClient()
    local actionName = WORK_ACTIONS[operation]
    if actionName == nil or NPCInteractionEvent == nil then return false, "npc_dialog_refused_operation" end
    local farmId = NPCFarmIdentity.localClaimFarmId()
    if farmId == nil then return false, "npc_dialog_refused_farm" end
    if self.people == nil or not self.people:isReady() then return false, "npc_person_loading" end
    if type(selection) ~= "table" or not NPCFarmIdentity.validToken(tostring(selection.token or ""))
        or not NPCFarmIdentity.validWireNumber(tostring(selection.recordRevision or "")) then
        return false, "npc_dialog_refused_stale"
    end
    local requestId = self:allocateDialogRequestId()
    if requestId == nil then return false, "npc_dialog_unavailable" end
    local data = requestId .. "|" .. tostring(selection.token) .. "|" .. tostring(selection.recordRevision)
    c.pending = { requestId = requestId, op = operation, personId = personId }
    local sent = NPCInteractionEvent.sendToServer(NPCInteractionEvent[actionName], personId, farmId, 0, data)
    if sent == false and c.pending ~= nil and c.pending.requestId == requestId then c.pending = nil end
    return sent ~= false
end

--- Section 9a: the UI entry. Routes ACCEPT_OFFER, COMPLETE_WORK and
--- ABANDON_WORK through the existing work-action event with the selection's
--- token and revision; TALK, OFFER_HELP and VIEW through the request event.
--- Returns true when a request was issued (pending, not success).
function NPCSystem:requestPersonDialogAction(operation, personId, selection)
    local c = self:_dialogClient()
    if c.context == nil or c.context.personId ~= personId then return false, "npc_dialog_unavailable" end
    local farmId = NPCFarmIdentity.localClaimFarmId()
    if farmId == nil or farmId ~= c.context.farmId then
        self:clearPrivateViews()
        return false, "npc_dialog_refused_farm"
    end
    if self.people == nil or not self.people:isReady() then return false, "npc_person_loading" end
    if WORK_ACTIONS[operation] ~= nil then
        return self:requestWorkAction(operation, personId, selection)
    end
    local requestId = self:allocateDialogRequestId()
    if requestId == nil then return false, "npc_dialog_unavailable" end
    local opCode = NPCPersonDialog.OP_CODE[operation]
    if opCode == nil or opCode == NPCPersonDialog.OP_VIEW_WORK then return false, "npc_dialog_refused_operation" end
    c.pending = { requestId = requestId, op = operation, personId = personId }
    local sent = NPCPersonDialogRequestEvent ~= nil
        and NPCPersonDialogRequestEvent.sendRequest({ requestId = requestId, op = opCode, personId = personId, cursor = "" })
    if not sent and c.pending ~= nil and c.pending.requestId == requestId then c.pending = nil end
    return sent == true
end

--- Section 9b: ask for the own-farm work page. At most one outstanding.
function NPCSystem:requestPersonalWorkView(cursor)
    local c = self:_dialogClient()
    local w = c.work
    local farmId = NPCFarmIdentity.localClaimFarmId()
    if farmId == nil then
        self:clearPrivateViews()
        return false
    end
    if w.farmId ~= nil and w.farmId ~= farmId then self:clearPrivateViews() w = c.work end
    self:_releaseLostWorkPage()
    if w.pendingRequestId ~= nil then return false end
    local requestId = self:allocateDialogRequestId()
    if requestId == nil then return false end
    w.pendingRequestId = requestId
    w.requestedAt = nowMs()
    w.cursor = cursor or ""
    w.farmId = farmId
    local sent = NPCPersonDialogRequestEvent ~= nil
        and NPCPersonDialogRequestEvent.sendRequest({ requestId = requestId, op = NPCPersonDialog.OP_VIEW_WORK, personId = 0, cursor = cursor or "" })
    if not sent then w.pendingRequestId = nil end
    return sent == true
end

--- A page request that never came back (a dropped reply, a stale id at the
--- host) does not block the door forever: after twice the stale interval the
--- outstanding id is released so the next request can go.
function NPCSystem:_releaseLostWorkPage()
    local w = self:_dialogClient().work
    if w.pendingRequestId ~= nil and w.requestedAt ~= nil
        and nowMs() - w.requestedAt > NPCPersonDialog.STALE_AFTER_MS * 2 then
        w.pendingRequestId = nil
    end
end

--- Copied rows of the work page.
local function copyRows(rows)
    local out = {}
    for i, r in ipairs(rows or {}) do
        local c = {}
        for k, v in pairs(r) do c[k] = v end
        out[i] = c
    end
    return out
end

--- Section 9b: the copied work page. CURRENT after a matching reply,
--- PENDING while a request is out and nothing is held, LAST_CONFIRMED when
--- a reply is older than two refresh intervals, UNAVAILABLE before any reply,
--- on a farm change or on failed readiness. A missing page never becomes zero.
function NPCSystem:getPersonalWorkView()
    local c = self:_dialogClient()
    local w = c.work
    local farmId = NPCFarmIdentity.localClaimFarmId()
    local view = { schema = 1, state = "UNAVAILABLE", farmId = farmId, rows = {}, total = nil, totalKnown = false,
        cursor = w.cursor or "", nextCursor = w.nextCursor or "", reasonKey = w.reasonKey or "",
        completedCount = nil, completedKnown = false, sampledTime = w.sampledTime or 0, ageMs = nil }
    if farmId == nil or (w.farmId ~= nil and w.farmId ~= farmId) then
        view.reasonKey = "npc_dialog_refused_farm"
        return view
    end
    if w.receivedAt == nil then
        view.state = (w.pendingRequestId ~= nil) and "PENDING" or "UNAVAILABLE"
        if view.state == "UNAVAILABLE" and view.reasonKey == "" then view.reasonKey = "npc_work_view_unavailable" end
        return view
    end
    view.rows = copyRows(w.rows)
    view.total, view.totalKnown = w.total, w.totalKnown
    view.completedCount, view.completedKnown = w.completedCount, w.completedKnown
    view.ageMs = nowMs() - w.receivedAt
    if w.state == "UNAVAILABLE" then
        view.state = "UNAVAILABLE"
    elseif view.ageMs > NPCPersonDialog.STALE_AFTER_MS and w.pendingRequestId ~= nil then
        view.state = "LAST_CONFIRMED"
        view.reasonKey = "npc_work_view_last_confirmed"
    else
        view.state = "CURRENT"
    end
    return view
end

--- Section 9a: the copied dialog view for the current local dialog and actor.
--- Unavailable before a valid reply, after an actor, farm or person change,
--- or on failed readiness.
function NPCSystem:getPersonDialogView(personId)
    local c = self:_dialogClient()
    local view = { schema = 1, personId = personId, pending = false, available = false, reasonKey = "",
        result = nil, messageKey = "", text = "", toneKey = "", trust = nil, offer = nil, work = nil, lastRequestId = nil }
    if c.context == nil or c.context.personId ~= personId then
        view.reasonKey = "npc_dialog_unavailable"
        return view
    end
    local farmId = NPCFarmIdentity.localClaimFarmId()
    if farmId == nil or farmId ~= c.context.farmId then
        view.reasonKey = "npc_dialog_refused_farm"
        return view
    end
    if self.people == nil or not self.people:isReady() then
        view.reasonKey = "npc_person_loading"
        return view
    end
    view.pending = c.pending ~= nil
    local r = c.lastReply
    if r == nil then return view end
    view.available = true
    view.lastRequestId = r.requestId
    view.result, view.messageKey, view.text, view.toneKey = r.result, r.messageKey or "", r.text or "", r.toneKey or ""
    view.trust = r.trustPresent and r.trust or nil
    local rows = copyRows(r.rows)
    local row = rows[1]
    if row ~= nil then
        if row.status == "pending" then view.offer = row else view.work = row end
    end
    view.op = r.op
    view.kind = r.kind
    return view
end

--- A reply from the server (or the verified local host). Matched against the
--- outstanding request, the context and the current farm; anything else is
--- dropped and leaves the button recoverable through VIEW or a retry.
function NPCSystem:onPersonDialogReply(reply)
    if type(reply) ~= "table" then return end
    local c = self:_dialogClient()
    local farmId = NPCFarmIdentity.localClaimFarmId()
    if farmId == nil or reply.farmId ~= farmId then return end

    if reply.kind == NPCPersonDialog.KIND_WORK_PAGE then
        local w = c.work
        if w.pendingRequestId == nil or reply.requestId ~= w.pendingRequestId then return end
        if w.farmId ~= nil and w.farmId ~= farmId then return end
        w.pendingRequestId = nil
        w.receivedAt = nowMs()
        w.sampledTime = reply.sampledTime or 0
        if reply.result == NPCPersonDialog.RESULT_OK then
            w.state = "CURRENT"
            w.rows = copyRows(reply.rows)
            w.total, w.totalKnown = reply.total, reply.totalKnown == true
            w.nextCursor = reply.nextCursor or ""
            w.completedCount, w.completedKnown = reply.completedCount, reply.completedKnown == true
            w.reasonKey = ""
        else
            w.state = "UNAVAILABLE"
            w.rows, w.total, w.totalKnown = {}, nil, false
            w.completedCount, w.completedKnown = nil, false
            w.reasonKey = reply.messageKey or "npc_work_view_unavailable"
        end
        if NPCFavorManagementDialog ~= nil and NPCFavorManagementDialog.onPersonalWorkView ~= nil then
            pcall(NPCFavorManagementDialog.onPersonalWorkView)
        end
        return
    end

    -- Action replies of a reader without a dialog context clear the pending
    -- mutation and refresh the shared page; dialog replies belong to the open
    -- dialog context only.
    if c.pending == nil or reply.requestId ~= c.pending.requestId then return end
    if c.context == nil then
        c.pending = nil
        if c.watchers > 0 then c.refreshTimerMs = NPCPersonDialog.REFRESH_INTERVAL_MS end
        if NPCFavorManagementDialog ~= nil and NPCFavorManagementDialog.onWorkActionResult ~= nil then
            pcall(NPCFavorManagementDialog.onWorkActionResult, reply)
        end
        return
    end
    if reply.personId ~= c.context.personId and reply.personId ~= 0 then return end
    c.pending = nil
    c.lastReply = reply
    -- Work changed on the server: refresh the shared page for its watchers.
    if reply.kind == NPCPersonDialog.KIND_ACTION and c.watchers > 0 then
        c.refreshTimerMs = NPCPersonDialog.REFRESH_INTERVAL_MS
    end
    if NPCDialog ~= nil and NPCDialog.onPersonDialogReply ~= nil then
        pcall(NPCDialog.onPersonDialogReply, reply)
    end
end

--- Watchers of the shared work page (the HUD, the management dialog, the PDA
--- guest) register interest; one adapter polls for all of them.
function NPCSystem:watchPersonalWork(on)
    local c = self:_dialogClient()
    if on then
        c.watchers = c.watchers + 1
        if c.watchers == 1 then c.refreshTimerMs = NPCPersonDialog.REFRESH_INTERVAL_MS end
    else
        c.watchers = math.max(0, c.watchers - 1)
    end
end

--- Called from NPCSystem:update on both sides (dt in milliseconds): the
--- 2-second presentation refresh while something watches, and the farm-change
--- clear. This is display timing, never a favour timer or an economic clock.
function NPCSystem:tickPersonalWork(dtMs)
    local c = self:_dialogClient()
    local farmId = NPCFarmIdentity.localClaimFarmId()
    if c.context ~= nil and c.context.farmId ~= farmId then self:clearPrivateViews() end
    if c.work.farmId ~= nil and c.work.farmId ~= farmId then self:clearPrivateViews() end
    self:_releaseLostWorkPage()
    if c.watchers <= 0 then return end
    c.refreshTimerMs = (c.refreshTimerMs or 0) + (dtMs or 0)
    if c.refreshTimerMs >= NPCPersonDialog.REFRESH_INTERVAL_MS then
        c.refreshTimerMs = 0
        -- A refresh queues behind a pending mutation and behind an outstanding page.
        if c.pending == nil and c.work.pendingRequestId == nil then
            self:requestPersonalWorkView("")
        end
    end
end

print("[NPC Favor] NPCPersonDialog loaded")
