-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- ACTION TYPES:
-- [x] Favor accept, complete, and abandon actions
-- [x] Gift giving action with value and data payload
-- [x] RSF-F357: the remote relationship action is refused (arbitrary client trust
--     changes never reach the model); Talk goes through the dialog request path
-- [ ] Trade/barter action for NPC-to-player item exchange
-- [ ] Conversation action with dialogue tree state tracking
-- [ ] Hire/dismiss action for temporary NPC worker contracts
--
-- SECURITY & VALIDATION:
-- [x] Action type whitelist with MIN/MAX range check
-- [x] Farm ownership verification via g_currentMission:getFarmId(connection) (RSF-F148)
-- [x] NaN and infinity checks on numeric value field
-- [x] NPC existence validation before dispatch
-- [x] RSF-F357: the exact acting player (getPlayerByConnection or g_localPlayer),
--     15 m from THAT player, no farm-mate surrogate, no fail-open
-- [x] RSF-F357: work actions bind to the work shown (requestId|token|recordRevision)
-- [ ] Per-action rate limiting (max N interactions per minute per player)
-- [ ] Action-specific value range validation (gift value caps, etc.)
--
-- MULTIPLAYER:
-- [x] Client-to-server routing with sendToServer pattern
-- [x] RSF-F357: host/SP goes through the same verified local-host entry
-- [x] Data string truncation to 256 characters
-- [x] RSF-F357: result reply to the originating requester only
-- [ ] Spectator mode support (observe but cannot interact)
-- =========================================================

--[[
    FS25_NPCFavor - NPC Interaction Event

    Client-to-server routing for player interactions with NPCs.
    Handles favor accept/complete/abandon and gifts.

    Pattern from: SetPaymentConfigEvent sendToServer + execute
    OWASP: Input validation, farm ownership verification, action whitelist,
           NaN/infinity checks.

    RSF-F357: the verified actor rides from run() into execute(). The distance
    is measured from the exact acting player, never from the closest farm-mate,
    and an unknown position refuses. ACCEPT, COMPLETE and ABANDON carry a
    strictly parsed `requestId|token|recordRevision` binding to the record the
    UI showed, share the dialog request high-water per connection, and answer
    through NPCPersonDialogReplyEvent to the requester only.
]]

NPCInteractionEvent = NPCInteractionEvent or {}
local NPCInteractionEvent_mt = Class(NPCInteractionEvent, Event)

InitEventClass(NPCInteractionEvent, "NPCInteractionEvent")

-- Action type constants (whitelist)
NPCInteractionEvent.ACTION_FAVOR_ACCEPT = 1
NPCInteractionEvent.ACTION_FAVOR_COMPLETE = 2
NPCInteractionEvent.ACTION_FAVOR_ABANDON = 3
NPCInteractionEvent.ACTION_GIFT = 4
NPCInteractionEvent.ACTION_RELATIONSHIP = 5

NPCInteractionEvent.MIN_ACTION = 1
NPCInteractionEvent.MAX_ACTION = 5

NPCInteractionEvent.MAX_INTERACTION_DISTANCE = 15  -- metres, from the exact acting player

function NPCInteractionEvent.emptyNew()
    local self = Event.new(NPCInteractionEvent_mt)
    self.actionType = 0
    self.npcId = 0
    self.farmId = 0
    self.value = 0
    self.data = ""
    return self
end

function NPCInteractionEvent.new(actionType, npcId, farmId, value, data)
    local self = NPCInteractionEvent.emptyNew()
    self.actionType = actionType or 0
    self.npcId = npcId or 0
    self.farmId = farmId or 0
    self.value = value or 0
    self.data = data or ""
    return self
end

--[[
    Static function to send interaction from client to server.
    RSF-F357: a host or single player goes through the SAME verified local-host
    entry as a remote request (resolveActor(nil) refuses a dedicated server's
    nil local player); the result is dispatched to the local adapter exactly as
    a remote reply would be. A multiplayer client sends the event.
]]
function NPCInteractionEvent.sendToServer(actionType, npcId, farmId, value, data)
    if g_server ~= nil then
        local actor = NPCFarmIdentity.resolveActor(nil)
        if actor == nil then
            print("[NPCFavor SECURITY] Rejected local interaction: no verified local actor")
            return false
        end
        if actor.farmId == nil or actor.farmId ~= farmId then
            print(string.format("[NPCFavor SECURITY] Rejected local interaction: farm %s is not the acting farm %s",
                tostring(farmId), tostring(actor.farmId)))
            return false
        end
        local ok, reply = NPCInteractionEvent.execute(actionType, npcId, farmId, value, data, actor)
        if reply ~= nil and NPCPersonDialogReplyEvent ~= nil then
            NPCPersonDialogReplyEvent.dispatch(reply)
        end
        return ok
    end
    if g_client == nil then return false end
    g_client:getServerConnection():sendEvent(
        NPCInteractionEvent.new(actionType, npcId, farmId, value, data)
    )
    return true
end

function NPCInteractionEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.actionType)
    streamWriteInt32(streamId, self.npcId)
    streamWriteInt32(streamId, self.farmId)
    streamWriteFloat32(streamId, self.value)
    streamWriteString(streamId, (self.data or ""):sub(1, 256))
end

function NPCInteractionEvent:readStream(streamId, connection)
    self.actionType = streamReadUInt8(streamId)
    self.npcId = streamReadInt32(streamId)
    self.farmId = streamReadInt32(streamId)
    self.value = streamReadFloat32(streamId)
    self.data = streamReadString(streamId):sub(1, 256)

    -- OWASP Input Validation: Validate action type in whitelist range
    if self.actionType < NPCInteractionEvent.MIN_ACTION or self.actionType > NPCInteractionEvent.MAX_ACTION then
        print(string.format("[NPCFavor SECURITY] Invalid action type: %d", self.actionType))
        return -- Don't call run, silently drop
    end

    self:run(connection)
end

function NPCInteractionEvent:run(connection)
    -- OWASP Layer 1: Must run on server
    if g_server == nil then
        return
    end

    -- OWASP Layer 2: Verify the acting farm (RSF-F148).
    -- Native User carries no farmId field, so the old user.farmId comparison
    -- read nil and rejected every remote client. The real acting farm comes
    -- from g_currentMission:getFarmId(connection) through the verified actor
    -- resolver, must be an ordinary live farm, and must equal the claim. A nil
    -- connection on a dedicated server has no actor and is refused; no
    -- administrator bypass exists here.
    local actor = NPCFarmIdentity.resolveActor(connection)
    if actor == nil then
        print("[NPCFavor SECURITY] Rejected interaction: no verified actor for connection")
        return
    end
    if actor.farmId == nil then
        print(string.format("[NPCFavor SECURITY] Rejected interaction: acting farm %s is not an ordinary farm",
            tostring(actor.rawFarmId)))
        return
    end
    if actor.farmId ~= self.farmId then
        print(string.format("[NPCFavor SECURITY] Rejected interaction: farmId mismatch (claimed %d, actual %d)",
            self.farmId, actor.farmId))
        return
    end

    -- OWASP Layer 3: Delegate to execute with the verified actor; the result
    -- goes back to this connection only.
    local _, reply = NPCInteractionEvent.execute(self.actionType, self.npcId, self.farmId, self.value, self.data, actor)
    if reply ~= nil and connection ~= nil and NPCPersonDialogReplyEvent ~= nil then
        connection:sendEvent(NPCPersonDialogReplyEvent.new(reply))
    end
end

--- RSF-F357: the exact acting player's position, or nil when it cannot be
--- established. A remote actor is playerSystem:getPlayerByConnection; the
--- verified local host is g_localPlayer. Player:getPosition follows a player
--- in a vehicle (the state machine's own getter); the root node is the
--- fallback only when the getter is absent. Non-finite coordinates are nil.
function NPCInteractionEvent.actorPosition(actor)
    if actor == nil then return nil end
    local player = nil
    if actor.isLocal then
        player = g_localPlayer
    elseif actor.connection ~= nil and g_currentMission ~= nil and g_currentMission.playerSystem ~= nil
        and type(g_currentMission.playerSystem.getPlayerByConnection) == "function" then
        player = g_currentMission.playerSystem:getPlayerByConnection(actor.connection)
    end
    if player == nil then return nil end
    local x, y, z = nil, nil, nil
    if type(player.getPosition) == "function" then
        local ok, px, py, pz = pcall(player.getPosition, player)
        if ok then x, y, z = px, py, pz end
    elseif player.rootNode ~= nil and player.rootNode ~= 0 then
        local ok, px, py, pz = pcall(getWorldTranslation, player.rootNode)
        if ok then x, y, z = px, py, pz end
    end
    local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
    if not (finite(x) and finite(z)) then return nil end
    return x, (finite(y) and y or 0), z
end

--- Ground distance from the exact acting player to the person, or nil when
--- the actor's position cannot be established (never "far", never "near").
function NPCInteractionEvent.actorDistanceTo(actor, npc)
    if npc == nil or npc.position == nil then return nil end
    local px, _, pz = NPCInteractionEvent.actorPosition(actor)
    if px == nil then return nil end
    local nx, nz = npc.position.x, npc.position.z
    if type(nx) ~= "number" or type(nz) ~= "number" or nx ~= nx or nz ~= nz then return nil end
    local dx, dz = px - nx, pz - nz
    return math.sqrt(dx * dx + dz * dz)
end

--- Strictly parse `requestId|token|recordRevision`: three bounded decimal
--- wire numbers, the token strictly positive. Nothing else is accepted and
--- nothing is evaluated.
function NPCInteractionEvent.parseSelection(data)
    if type(data) ~= "string" then return nil end
    local a, b, c = data:match("^(%d+)|(%d+)|(%d+)$")
    if a == nil then return nil end
    if not NPCFarmIdentity.validWireNumber(a) or not NPCFarmIdentity.validToken(b)
        or not NPCFarmIdentity.validWireNumber(c) then
        return nil
    end
    return { requestId = a, token = tonumber(b), recordRevision = tonumber(c) }
end

--[[
    Execute the interaction logic for a verified actor. All input validation
    happens here.
    @return boolean success, table|nil reply (for the requester only)
]]
function NPCInteractionEvent.execute(actionType, npcId, farmId, value, data, actor)
    local sys = g_NPCSystem
    if sys == nil then
        return false, nil
    end

    -- The actor is not optional (RSF-F357): no verified actor, no mutation.
    if actor == nil or actor.farmId == nil or actor.farmId ~= farmId then
        print("[NPCFavor SECURITY] Rejected interaction: no verified actor for the acting farm")
        return false, nil
    end

    -- OWASP Input Validation: the acting farm must be an ordinary live farm.
    -- Spectator (0), guided tour (14) and invalid (15) are refused even when
    -- their farm objects exist (RSF-F148).
    if not NPCFarmIdentity.isOrdinaryFarmId(farmId) then
        print(string.format("[NPCFavor SECURITY] Farm is not an ordinary farm: %s", tostring(farmId)))
        return false, nil
    end

    -- The remote relationship action is not a trust writer any more: Talk goes
    -- through the dialog request path with the owner's own day and mood rules.
    if actionType == NPCInteractionEvent.ACTION_RELATIONSHIP then
        print("[NPCFavor SECURITY] Rejected client-supplied relationship change")
        return false, nil
    end

    -- OWASP Input Validation: NaN and bounds check on value
    if value ~= value then -- NaN check
        print("[NPCFavor SECURITY] Rejected NaN value")
        return false, nil
    end
    if math.abs(value) >= 1e9 then
        print("[NPCFavor SECURITY] Rejected out-of-bounds value")
        return false, nil
    end

    local isWorkAction = actionType == NPCInteractionEvent.ACTION_FAVOR_ACCEPT
        or actionType == NPCInteractionEvent.ACTION_FAVOR_COMPLETE
        or actionType == NPCInteractionEvent.ACTION_FAVOR_ABANDON

    -- Work actions bind to the work that was shown, and share the dialog
    -- request gate of this connection (stale, changed and replayed ids).
    local selection = nil
    if isWorkAction then
        selection = NPCInteractionEvent.parseSelection(data)
        if selection == nil then
            print("[NPCFavor SECURITY] Rejected work action: malformed selection")
            return false, nil
        end
    end

    local function reply(result, key, personId)
        return {
            requestId = selection and selection.requestId or "",
            kind = NPCPersonDialog and NPCPersonDialog.KIND_ACTION or 3,
            op = actionType,
            personId = personId or npcId,
            farmId = farmId,
            result = result,
            messageKey = key or "",
            text = "",
            rows = {},
        }
    end

    local gate, cached = nil, nil
    if isWorkAction and sys.dialogRequestGate ~= nil then
        local fingerprint = table.concat({ "work", tostring(actionType), tostring(npcId),
            tostring(selection.token), tostring(selection.recordRevision) }, "|")
        gate, cached = sys:dialogRequestGate(actor, selection.requestId, fingerprint)
        if gate == "replay" then
            return cached ~= nil and cached.result == (NPCPersonDialog and NPCPersonDialog.RESULT_OK or 1), cached
        elseif gate == "stale" then
            return false, nil
        elseif gate == "changed" then
            return false, reply(NPCPersonDialog.RESULT_REFUSED, "npc_dialog_refused_request_reuse")
        elseif gate == "exhausted" then
            return false, reply(NPCPersonDialog.RESULT_UNAVAILABLE, "npc_dialog_unavailable")
        end
    end

    local function finish(ok, r)
        if isWorkAction and sys.dialogRequestRecord ~= nil and r ~= nil then
            sys:dialogRequestRecord(actor, selection.requestId, r)
        end
        return ok, r
    end

    -- OWASP Input Validation: the person must be a unique live durable person.
    local npc = sys:getNPCById(npcId)
    if npc == nil or (sys.isPersonActionable ~= nil and not sys:isPersonActionable(npc)) then
        print(string.format("[NPCFavor SECURITY] Person not actionable: %d", npcId))
        return finish(false, isWorkAction and reply(NPCPersonDialog.RESULT_REFUSED, "npc_dialog_refused_person") or nil)
    end

    -- OWASP Layer 4: the exact acting player's distance. An unknown position
    -- refuses; another player on the farm is never borrowed.
    local dist = NPCInteractionEvent.actorDistanceTo(actor, npc)
    if dist == nil or dist > NPCInteractionEvent.MAX_INTERACTION_DISTANCE then
        print(string.format("[NPCFavor SECURITY] Rejected interaction: acting player %s NPC %d",
            dist == nil and "position unknown for" or string.format("too far (%.1fm) from", dist), npcId))
        return finish(false, isWorkAction and reply(NPCPersonDialog.RESULT_REFUSED, "npc_dialog_refused_far") or nil)
    end

    -- Dispatch to appropriate handler
    if actionType == NPCInteractionEvent.ACTION_FAVOR_ACCEPT then
        local ok, key, record = sys:serverAcceptFavor(npc, farmId, selection)
        local r = reply(ok and NPCPersonDialog.RESULT_ACCEPTED or NPCPersonDialog.RESULT_STALE, key)
        -- The accepted row rides with the answer so the dialog shows the work
        -- without a second request.
        if ok and record ~= nil and sys.describeWorkRow ~= nil then
            r.rows = { sys:describeWorkRow(record, actor) }
        end
        return finish(ok, r)

    elseif actionType == NPCInteractionEvent.ACTION_FAVOR_COMPLETE then
        local ok, key = sys:serverCompleteFavor(npc, farmId, selection)
        return finish(ok, reply(ok and NPCPersonDialog.RESULT_OK or NPCPersonDialog.RESULT_STALE, key))

    elseif actionType == NPCInteractionEvent.ACTION_FAVOR_ABANDON then
        local ok, key = sys:serverAbandonFavor(npc, farmId, selection)
        return finish(ok, reply(ok and NPCPersonDialog.RESULT_OK or NPCPersonDialog.RESULT_STALE, key))

    elseif actionType == NPCInteractionEvent.ACTION_GIFT then
        local ok = sys:serverGiveGift(npc, farmId, value, data)
        local r = {
            requestId = "", kind = NPCPersonDialog and NPCPersonDialog.KIND_ACTION or 3, op = actionType,
            personId = npcId, farmId = farmId,
            result = ok and NPCPersonDialog.RESULT_OK or NPCPersonDialog.RESULT_REFUSED,
            messageKey = ok and "npc_dialog_gift_ok" or "npc_dialog_gift_refused", text = "", rows = {},
            trustPresent = ok and type(npc.relationship) == "number", trust = ok and npc.relationship or 0,
        }
        return ok, r
    end

    return false, nil
end
