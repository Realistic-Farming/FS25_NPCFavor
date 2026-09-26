--[[
    FS25_NPCFavor - Favor recovery events (RSF-F148)

    A bounded request/response view for the open native management dialog,
    not a background shared-state service. Four Event classes:

      NPCFavorRecoveryViewRequestEvent   client -> server   (requestId, cursor)
      NPCFavorRecoveryViewReplyEvent     server -> requester only
      NPCFavorRecoveryCommandEvent       client -> server   (exact-record envelope)
      NPCFavorRecoveryResultEvent        server -> requester only

    The server resolves the actor from the requesting connection and replies
    through that Connection:sendEvent, never by broadcast. On a listen server
    or single player the same code runs locally through the verified local
    host entry (g_server and g_localPlayer both present). A dedicated server
    has no local actor and no nil-connection bypass.

    Wire numbers (request ids, revisions, tokens) are bounded ASCII decimal
    strings validated by NPCFarmIdentity before they are decoded.
]]

local function wireString(s)
    if type(s) ~= "string" then return "" end
    return s:sub(1, 10)
end

-- Bounded text: cut at 256 bytes on a UTF-8 character boundary so a split
-- multibyte sequence never reaches the wire.
local function textString(s)
    if type(s) ~= "string" then return "" end
    if #s <= 256 then return s end
    local cut = 256
    while cut > 0 do
        local b = s:byte(cut + 1)
        if b == nil or b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return s:sub(1, cut)
end

-- =========================================================
-- View request
-- =========================================================

NPCFavorRecoveryViewRequestEvent = NPCFavorRecoveryViewRequestEvent or {}
local NPCFavorRecoveryViewRequestEvent_mt = Class(NPCFavorRecoveryViewRequestEvent, Event)
InitEventClass(NPCFavorRecoveryViewRequestEvent, "NPCFavorRecoveryViewRequestEvent")

function NPCFavorRecoveryViewRequestEvent.emptyNew()
    local self = Event.new(NPCFavorRecoveryViewRequestEvent_mt)
    self.requestId = ""
    self.cursor = ""
    return self
end

function NPCFavorRecoveryViewRequestEvent.new(requestId, cursor)
    local self = NPCFavorRecoveryViewRequestEvent.emptyNew()
    self.requestId = wireString(requestId)
    self.cursor = wireString(cursor)
    return self
end

function NPCFavorRecoveryViewRequestEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.requestId)
    streamWriteString(streamId, self.cursor)
end

function NPCFavorRecoveryViewRequestEvent:readStream(streamId, connection)
    self.requestId = wireString(streamReadString(streamId))
    self.cursor = wireString(streamReadString(streamId))
    self:run(connection)
end

function NPCFavorRecoveryViewRequestEvent:run(connection)
    if g_server == nil or g_NPCSystem == nil or connection == nil then return end
    if not NPCFarmIdentity.validWireNumber(self.requestId) then return end
    if self.cursor ~= "" and not NPCFarmIdentity.validToken(self.cursor) then return end
    local reply = g_NPCSystem:serverRecoveryView(connection, self.requestId, self.cursor)
    if reply ~= nil then
        connection:sendEvent(NPCFavorRecoveryViewReplyEvent.new(reply))
    end
end

--- Client entry: ask for a page. Executes locally on a listen host / SP.
function NPCFavorRecoveryViewRequestEvent.sendRequest(requestId, cursor)
    if g_server ~= nil then
        if g_NPCSystem == nil then return false end
        local reply = g_NPCSystem:serverRecoveryView(nil, requestId, cursor or "")
        if reply == nil then return false end
        NPCFavorRecoveryViewReplyEvent.dispatch(reply)
        return true
    end
    if g_client == nil then return false end
    g_client:getServerConnection():sendEvent(NPCFavorRecoveryViewRequestEvent.new(requestId, cursor or ""))
    return true
end

-- =========================================================
-- View reply
-- =========================================================

NPCFavorRecoveryViewReplyEvent = NPCFavorRecoveryViewReplyEvent or {}
local NPCFavorRecoveryViewReplyEvent_mt = Class(NPCFavorRecoveryViewReplyEvent, Event)
InitEventClass(NPCFavorRecoveryViewReplyEvent, "NPCFavorRecoveryViewReplyEvent")

NPCFavorRecoveryViewReplyEvent.MAX_ROWS = 20
NPCFavorRecoveryViewReplyEvent.MAX_FARMS = 16

function NPCFavorRecoveryViewReplyEvent.emptyNew()
    local self = Event.new(NPCFavorRecoveryViewReplyEvent_mt)
    self.reply = { requestId = "", collectionRevision = "0", nextCursor = "", unavailable = false, rows = {}, eligibleFarms = {} }
    return self
end

function NPCFavorRecoveryViewReplyEvent.new(reply)
    local self = NPCFavorRecoveryViewReplyEvent.emptyNew()
    self.reply = reply
    return self
end

local function writeRow(streamId, row)
    streamWriteString(streamId, wireString(row.token))
    streamWriteString(streamId, wireString(row.recordRevision))
    streamWriteInt32(streamId, row.npcId or 0)
    streamWriteString(streamId, textString(row.npcName))
    streamWriteString(streamId, textString(row.type))
    streamWriteString(streamId, textString(row.description))
    streamWriteString(streamId, textString(row.status))
    streamWriteFloat32(streamId, row.progress or 0)
    streamWriteFloat32(streamId, row.timeRemaining or 0)
    streamWriteBool(streamId, row.timeKnown == true)
    streamWriteInt32(streamId, row.ownerFarmId or -1)
    streamWriteBool(streamId, row.ownerKnown == true)
    streamWriteString(streamId, textString(row.recoveryReason))
    streamWriteBool(streamId, row.resumable == true)
    streamWriteBool(streamId, row.knownOwnerResumable == true)
    streamWriteBool(streamId, row.assignable == true)
    streamWriteBool(streamId, row.inspectOnly == true)
    streamWriteString(streamId, textString(row.unavailableKey))
    local loanAmount = row.loanAmount or -1
    if loanAmount ~= loanAmount or loanAmount > 2147483647 or loanAmount < -2147483648 then loanAmount = -1 end
    streamWriteInt32(streamId, math.floor(loanAmount))
    streamWriteUInt8(streamId, row.loanAmountDeducted or 2)
    streamWriteUInt8(streamId, row.rewardPaid or 2)
    streamWriteUInt8(streamId, row.repaymentCollected or 2)
    streamWriteBool(streamId, row.fieldKnown == true)
    streamWriteBool(streamId, row.recoveredFromLegacy == true)
    streamWriteBool(streamId, row.canComplete == true)
    streamWriteBool(streamId, row.canAbandon == true)
    -- NPC-204 3.11
    streamWriteString(streamId, textString(row.pauseReason))
    streamWriteBool(streamId, row.contributionHeld == true)
    streamWriteString(streamId, textString(row.contributionHoldReason))
    streamWriteBool(streamId, row.canLetGo == true)
end

local function readRow(streamId)
    local row = {}
    row.token = wireString(streamReadString(streamId))
    row.recordRevision = wireString(streamReadString(streamId))
    row.npcId = streamReadInt32(streamId)
    row.npcName = textString(streamReadString(streamId))
    row.type = textString(streamReadString(streamId))
    row.description = textString(streamReadString(streamId))
    row.status = textString(streamReadString(streamId))
    row.progress = streamReadFloat32(streamId)
    row.timeRemaining = streamReadFloat32(streamId)
    row.timeKnown = streamReadBool(streamId)
    row.ownerFarmId = streamReadInt32(streamId)
    row.ownerKnown = streamReadBool(streamId)
    row.recoveryReason = textString(streamReadString(streamId))
    row.resumable = streamReadBool(streamId)
    row.knownOwnerResumable = streamReadBool(streamId)
    row.assignable = streamReadBool(streamId)
    row.inspectOnly = streamReadBool(streamId)
    row.unavailableKey = textString(streamReadString(streamId))
    row.loanAmount = streamReadInt32(streamId)
    row.loanAmountDeducted = streamReadUInt8(streamId)
    row.rewardPaid = streamReadUInt8(streamId)
    row.repaymentCollected = streamReadUInt8(streamId)
    row.fieldKnown = streamReadBool(streamId)
    row.recoveredFromLegacy = streamReadBool(streamId)
    row.canComplete = streamReadBool(streamId)
    row.canAbandon = streamReadBool(streamId)
    row.pauseReason = textString(streamReadString(streamId))
    row.contributionHeld = streamReadBool(streamId)
    row.contributionHoldReason = textString(streamReadString(streamId))
    row.canLetGo = streamReadBool(streamId)
    return row
end

function NPCFavorRecoveryViewReplyEvent:writeStream(streamId, connection)
    local r = self.reply
    streamWriteString(streamId, wireString(r.requestId))
    streamWriteString(streamId, wireString(r.collectionRevision))
    streamWriteString(streamId, wireString(r.nextCursor))
    streamWriteBool(streamId, r.unavailable == true)
    streamWriteInt32(streamId, r.totalRows or 0)
    local rows = r.rows or {}
    local n = math.min(#rows, NPCFavorRecoveryViewReplyEvent.MAX_ROWS)
    streamWriteUInt8(streamId, n)
    for i = 1, n do writeRow(streamId, rows[i]) end
    local farms = r.eligibleFarms or {}
    local fn = math.min(#farms, NPCFavorRecoveryViewReplyEvent.MAX_FARMS)
    streamWriteUInt8(streamId, fn)
    for i = 1, fn do
        streamWriteInt32(streamId, farms[i].farmId or -1)
        streamWriteString(streamId, textString(farms[i].name))
    end
end

function NPCFavorRecoveryViewReplyEvent:readStream(streamId, connection)
    local r = { rows = {}, eligibleFarms = {} }
    r.requestId = wireString(streamReadString(streamId))
    r.collectionRevision = wireString(streamReadString(streamId))
    r.nextCursor = wireString(streamReadString(streamId))
    r.unavailable = streamReadBool(streamId)
    r.totalRows = streamReadInt32(streamId)
    local n = streamReadUInt8(streamId)
    for _ = 1, n do r.rows[#r.rows + 1] = readRow(streamId) end
    local fn = streamReadUInt8(streamId)
    for _ = 1, fn do
        local farmId = streamReadInt32(streamId)
        local name = textString(streamReadString(streamId))
        r.eligibleFarms[#r.eligibleFarms + 1] = { farmId = farmId, name = name }
    end
    self.reply = r
    self:run(connection)
end

function NPCFavorRecoveryViewReplyEvent:run(connection)
    -- Client side only: a reply arriving on the server is ignored.
    if g_server ~= nil and connection ~= nil then return end
    NPCFavorRecoveryViewReplyEvent.dispatch(self.reply)
end

--- Hand a reply to whoever is listening (the management dialog).
function NPCFavorRecoveryViewReplyEvent.dispatch(reply)
    if NPCFavorManagementDialog ~= nil and NPCFavorManagementDialog.onRecoveryViewReply ~= nil then
        NPCFavorManagementDialog.onRecoveryViewReply(reply)
    end
end

-- =========================================================
-- Command
-- =========================================================

NPCFavorRecoveryCommandEvent = NPCFavorRecoveryCommandEvent or {}
local NPCFavorRecoveryCommandEvent_mt = Class(NPCFavorRecoveryCommandEvent, Event)
InitEventClass(NPCFavorRecoveryCommandEvent, "NPCFavorRecoveryCommandEvent")

function NPCFavorRecoveryCommandEvent.emptyNew()
    local self = Event.new(NPCFavorRecoveryCommandEvent_mt)
    self.cmd = { requestId = "", collectionRevision = "", recordRevision = "", token = "", op = 0,
                 targetFarmId = nil, originatingViewRequestId = "" }
    return self
end

function NPCFavorRecoveryCommandEvent.new(cmd)
    local self = NPCFavorRecoveryCommandEvent.emptyNew()
    self.cmd = {
        requestId = wireString(cmd.requestId),
        collectionRevision = wireString(cmd.collectionRevision),
        recordRevision = wireString(cmd.recordRevision),
        token = wireString(cmd.token),
        op = cmd.op or 0,
        targetFarmId = cmd.targetFarmId,
        originatingViewRequestId = wireString(cmd.originatingViewRequestId),
    }
    return self
end

function NPCFavorRecoveryCommandEvent:writeStream(streamId, connection)
    local c = self.cmd
    streamWriteString(streamId, c.requestId)
    streamWriteString(streamId, c.collectionRevision)
    streamWriteString(streamId, c.recordRevision)
    streamWriteString(streamId, c.token)
    streamWriteUInt8(streamId, c.op or 0)
    streamWriteInt32(streamId, c.targetFarmId or -1)
    streamWriteString(streamId, c.originatingViewRequestId or "")
end

function NPCFavorRecoveryCommandEvent:readStream(streamId, connection)
    local c = {}
    c.requestId = wireString(streamReadString(streamId))
    c.collectionRevision = wireString(streamReadString(streamId))
    c.recordRevision = wireString(streamReadString(streamId))
    c.token = wireString(streamReadString(streamId))
    c.op = streamReadUInt8(streamId)
    local target = streamReadInt32(streamId)
    c.targetFarmId = (target >= 0) and target or nil
    c.originatingViewRequestId = wireString(streamReadString(streamId))
    self.cmd = c

    -- Operation whitelist before dispatch; anything else is dropped.
    if c.op < NPCFavorRecovery.OP_MIN or c.op > NPCFavorRecovery.OP_MAX then
        print(string.format("[NPCFavor SECURITY] Invalid recovery operation: %d", c.op))
        return
    end
    self:run(connection)
end

function NPCFavorRecoveryCommandEvent:run(connection)
    if g_server == nil or g_NPCSystem == nil or connection == nil then return end
    local reply = g_NPCSystem:serverRecoveryCommand(connection, self.cmd)
    if reply ~= nil then
        connection:sendEvent(NPCFavorRecoveryResultEvent.new(reply))
    end
end

--- Client entry: send one confirmed command. Executes locally on a listen host / SP.
function NPCFavorRecoveryCommandEvent.sendCommand(cmd)
    if g_server ~= nil then
        if g_NPCSystem == nil then return false end
        local reply = g_NPCSystem:serverRecoveryCommand(nil, cmd)
        if reply == nil then return false end
        NPCFavorRecoveryResultEvent.dispatch(reply)
        return true
    end
    if g_client == nil then return false end
    g_client:getServerConnection():sendEvent(NPCFavorRecoveryCommandEvent.new(cmd))
    return true
end

-- =========================================================
-- Result
-- =========================================================

NPCFavorRecoveryResultEvent = NPCFavorRecoveryResultEvent or {}
local NPCFavorRecoveryResultEvent_mt = Class(NPCFavorRecoveryResultEvent, Event)
InitEventClass(NPCFavorRecoveryResultEvent, "NPCFavorRecoveryResultEvent")

function NPCFavorRecoveryResultEvent.emptyNew()
    local self = Event.new(NPCFavorRecoveryResultEvent_mt)
    self.reply = { requestId = "", op = 0, result = 0, messageKey = "" }
    return self
end

function NPCFavorRecoveryResultEvent.new(reply)
    local self = NPCFavorRecoveryResultEvent.emptyNew()
    self.reply = reply
    return self
end

function NPCFavorRecoveryResultEvent:writeStream(streamId, connection)
    local r = self.reply
    streamWriteString(streamId, wireString(r.requestId))
    streamWriteUInt8(streamId, r.op or 0)
    streamWriteUInt8(streamId, r.result or 0)
    streamWriteString(streamId, textString(r.messageKey))
end

function NPCFavorRecoveryResultEvent:readStream(streamId, connection)
    local r = {}
    r.requestId = wireString(streamReadString(streamId))
    r.op = streamReadUInt8(streamId)
    r.result = streamReadUInt8(streamId)
    r.messageKey = textString(streamReadString(streamId))
    self.reply = r
    self:run(connection)
end

function NPCFavorRecoveryResultEvent:run(connection)
    if g_server ~= nil and connection ~= nil then return end
    NPCFavorRecoveryResultEvent.dispatch(self.reply)
end

function NPCFavorRecoveryResultEvent.dispatch(reply)
    -- The NPC dialog claims a result for a command it sent; otherwise the
    -- management dialog shows it.
    if NPCDialog ~= nil and NPCDialog.onRecoveryResult ~= nil and NPCDialog.onRecoveryResult(reply) then
        return
    end
    if NPCFavorManagementDialog ~= nil and NPCFavorManagementDialog.onRecoveryResult ~= nil then
        NPCFavorManagementDialog.onRecoveryResult(reply)
    end
end
