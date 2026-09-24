--[[
    FS25_NPCFavor - Person dialog events (RSF-F357 section 9)

    Two requester-only Event classes, following NPCFavorRecoveryEvents:

      NPCPersonDialogRequestEvent   client -> server   (requestId, op, personId, cursor)
      NPCPersonDialogReplyEvent     server -> requester only (one copied view)

    The request carries intent and nothing else: no trust delta, reason, reward,
    favour content or owner. TALK, OFFER_HELP and VIEW name a durable person;
    VIEW_WORK names no person and carries only an optional cursor. The server
    re-resolves the actor from the requesting connection and replies through
    that Connection:sendEvent, never by broadcast. A listen server or single
    player runs the same dispatcher locally through the verified local host
    entry (g_server and g_localPlayer both present); a dedicated server has no
    local actor and no nil-connection bypass.

    The financial work actions (accept, complete, abandon) stay on
    NPCInteractionEvent with the requestId|token|recordRevision binding; their
    results come back through this reply class too, so the client has one
    private reply door.

    Both classes are sourced in main.lua's load block: InitEventClass refuses
    once g_currentMission exists, so nothing here is lazy.
]]

NPCPersonDialog = NPCPersonDialog or {}

NPCPersonDialog.OP_TALK       = 1
NPCPersonDialog.OP_OFFER_HELP = 2
NPCPersonDialog.OP_VIEW       = 3
NPCPersonDialog.OP_VIEW_WORK  = 4
NPCPersonDialog.OP_MIN = 1
NPCPersonDialog.OP_MAX = 4
NPCPersonDialog.OP_NAME = { "TALK", "OFFER_HELP", "VIEW", "VIEW_WORK" }
NPCPersonDialog.OP_CODE = { TALK = 1, OFFER_HELP = 2, VIEW = 3, VIEW_WORK = 4 }

-- Reply layout: header (requestId, kind, op, personId, farmId, result, messageKey, text, toneKey,
-- trust), the page fields, then at most 20 work rows.
-- Reply kinds
NPCPersonDialog.KIND_DIALOG    = 1
NPCPersonDialog.KIND_WORK_PAGE = 2
NPCPersonDialog.KIND_ACTION    = 3

-- Result codes (distinct outcomes; the client shows a matching copied result)
NPCPersonDialog.RESULT_OK          = 1
NPCPersonDialog.RESULT_REFUSED     = 2   -- actor, farm, person or distance refused
NPCPersonDialog.RESULT_DECLINED    = 3   -- the person declined the offer of help
NPCPersonDialog.RESULT_NO_WORK     = 4   -- nothing to offer right now
NPCPersonDialog.RESULT_OFFER       = 5   -- a pending offer view is attached
NPCPersonDialog.RESULT_ACCEPTED    = 6   -- accepted work view is attached
NPCPersonDialog.RESULT_LIMIT       = 7   -- Talk: the day's input was already applied
NPCPersonDialog.RESULT_STALE       = 8   -- the selection no longer matches
NPCPersonDialog.RESULT_BUSY        = 9   -- another farm's accepted work
NPCPersonDialog.RESULT_UNAVAILABLE = 10  -- readiness or exhaustion

NPCPersonDialog.WORK_PAGE_ROWS = 20

local function wireString(s)
    if type(s) ~= "string" then return "" end
    return s:sub(1, 10)
end

-- Bounded text: cut at 256 bytes on a UTF-8 character boundary.
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
NPCPersonDialog.textString = textString
NPCPersonDialog.wireString = wireString

local function i32(v)
    if type(v) ~= "number" or v ~= v then return 0 end
    if v > 2147483647 then return 2147483647 end
    if v < -2147483648 then return -2147483648 end
    return math.floor(v)
end

-- =========================================================
-- Request
-- =========================================================

NPCPersonDialogRequestEvent = NPCPersonDialogRequestEvent or {}
local NPCPersonDialogRequestEvent_mt = Class(NPCPersonDialogRequestEvent, Event)
InitEventClass(NPCPersonDialogRequestEvent, "NPCPersonDialogRequestEvent")

function NPCPersonDialogRequestEvent.emptyNew()
    local self = Event.new(NPCPersonDialogRequestEvent_mt)
    self.request = { requestId = "", op = 0, personId = 0, cursor = "" }
    return self
end

function NPCPersonDialogRequestEvent.new(request)
    local self = NPCPersonDialogRequestEvent.emptyNew()
    self.request = {
        requestId = wireString(request.requestId),
        op = request.op or 0,
        personId = request.personId or 0,
        cursor = wireString(request.cursor),
    }
    return self
end

function NPCPersonDialogRequestEvent:writeStream(streamId, connection)
    local r = self.request
    streamWriteString(streamId, r.requestId)
    streamWriteUInt8(streamId, r.op or 0)
    streamWriteInt32(streamId, i32(r.personId or 0))
    streamWriteString(streamId, r.cursor or "")
end

function NPCPersonDialogRequestEvent:readStream(streamId, connection)
    local r = {}
    r.requestId = wireString(streamReadString(streamId))
    r.op = streamReadUInt8(streamId)
    r.personId = streamReadInt32(streamId)
    r.cursor = wireString(streamReadString(streamId))
    self.request = r
    if r.op < NPCPersonDialog.OP_MIN or r.op > NPCPersonDialog.OP_MAX then
        print(string.format("[NPCFavor SECURITY] Invalid dialog operation: %d", r.op))
        return
    end
    self:run(connection)
end

function NPCPersonDialogRequestEvent:run(connection)
    if g_server == nil or g_NPCSystem == nil or connection == nil then return end
    if g_NPCSystem.serverPersonDialogRequest == nil then return end
    local reply = g_NPCSystem:serverPersonDialogRequest(connection, self.request)
    if reply ~= nil then
        connection:sendEvent(NPCPersonDialogReplyEvent.new(reply))
    end
end

--- Client entry. Executes locally on a listen host / SP through the verified
--- local host entry; a dedicated server has no local actor and returns false.
function NPCPersonDialogRequestEvent.sendRequest(request)
    if g_server ~= nil then
        if g_NPCSystem == nil or g_NPCSystem.serverPersonDialogRequest == nil then return false end
        local reply = g_NPCSystem:serverPersonDialogRequest(nil, request)
        if reply == nil then return false end
        NPCPersonDialogReplyEvent.dispatch(reply)
        return true
    end
    if g_client == nil then return false end
    g_client:getServerConnection():sendEvent(NPCPersonDialogRequestEvent.new(request))
    return true
end

-- =========================================================
-- Reply
-- =========================================================

NPCPersonDialogReplyEvent = NPCPersonDialogReplyEvent or {}
local NPCPersonDialogReplyEvent_mt = Class(NPCPersonDialogReplyEvent, Event)
InitEventClass(NPCPersonDialogReplyEvent, "NPCPersonDialogReplyEvent")

function NPCPersonDialogReplyEvent.emptyNew()
    local self = Event.new(NPCPersonDialogReplyEvent_mt)
    self.reply = nil
    return self
end

function NPCPersonDialogReplyEvent.new(reply)
    local self = NPCPersonDialogReplyEvent.emptyNew()
    self.reply = reply
    return self
end

-- One work row: the host session token and revision, the durable person or the
-- unproven flag, the saved name, status, description, progress, known time,
-- the offered reward, the next step and the action flags for THIS actor.
local function writeWorkRow(streamId, row)
    streamWriteString(streamId, wireString(row.token))
    streamWriteString(streamId, wireString(row.recordRevision))
    streamWriteBool(streamId, row.personIdPresent == true)
    streamWriteInt32(streamId, i32(row.personId or 0))
    streamWriteString(streamId, textString(row.npcName))
    streamWriteString(streamId, textString(row.status))
    streamWriteString(streamId, textString(row.type))
    streamWriteString(streamId, textString(row.description))
    streamWriteFloat32(streamId, row.progress or 0)
    streamWriteBool(streamId, row.timeKnown == true)
    streamWriteFloat32(streamId, row.timeRemainingMs or 0)
    streamWriteInt32(streamId, i32(row.rewardMoney or 0))
    streamWriteString(streamId, textString(row.nextStepText))
    streamWriteInt32(streamId, i32(row.nextStepId or 0))
    streamWriteBool(streamId, row.nextStepLocationPresent == true)
    streamWriteFloat32(streamId, row.nextStepX or 0)
    streamWriteFloat32(streamId, row.nextStepZ or 0)
    streamWriteBool(streamId, row.isDialogStep == true)
    streamWriteBool(streamId, row.isLoanRepayStep == true)
    streamWriteBool(streamId, row.awaitingConfirmation == true)
    streamWriteBool(streamId, row.loanAmountPresent == true)
    streamWriteInt32(streamId, i32(row.loanAmount or 0))
    streamWriteBool(streamId, row.recoveredFromLegacy == true)
    streamWriteBool(streamId, row.canAccept == true)
    streamWriteBool(streamId, row.canComplete == true)
    streamWriteBool(streamId, row.canAbandon == true)
    streamWriteBool(streamId, row.completed == true)
end

local function readWorkRow(streamId)
    local row = {}
    row.token = wireString(streamReadString(streamId))
    row.recordRevision = wireString(streamReadString(streamId))
    row.personIdPresent = streamReadBool(streamId)
    row.personId = streamReadInt32(streamId)
    row.npcName = textString(streamReadString(streamId))
    row.status = textString(streamReadString(streamId))
    row.type = textString(streamReadString(streamId))
    row.description = textString(streamReadString(streamId))
    row.progress = streamReadFloat32(streamId)
    row.timeKnown = streamReadBool(streamId)
    row.timeRemainingMs = streamReadFloat32(streamId)
    row.rewardMoney = streamReadInt32(streamId)
    row.nextStepText = textString(streamReadString(streamId))
    row.nextStepId = streamReadInt32(streamId)
    row.nextStepLocationPresent = streamReadBool(streamId)
    row.nextStepX = streamReadFloat32(streamId)
    row.nextStepZ = streamReadFloat32(streamId)
    row.isDialogStep = streamReadBool(streamId)
    row.isLoanRepayStep = streamReadBool(streamId)
    row.awaitingConfirmation = streamReadBool(streamId)
    row.loanAmountPresent = streamReadBool(streamId)
    row.loanAmount = streamReadInt32(streamId)
    row.recoveredFromLegacy = streamReadBool(streamId)
    row.canAccept = streamReadBool(streamId)
    row.canComplete = streamReadBool(streamId)
    row.canAbandon = streamReadBool(streamId)
    row.completed = streamReadBool(streamId)
    if not row.personIdPresent then row.personId = 0 end
    if not row.nextStepLocationPresent then row.nextStepX, row.nextStepZ = 0, 0 end
    if not row.loanAmountPresent then row.loanAmount = 0 end
    return row
end

function NPCPersonDialogReplyEvent:writeStream(streamId, connection)
    local r = self.reply or {}
    streamWriteString(streamId, wireString(r.requestId))
    streamWriteUInt8(streamId, r.kind or NPCPersonDialog.KIND_DIALOG)
    streamWriteUInt8(streamId, r.op or 0)
    streamWriteInt32(streamId, i32(r.personId or 0))
    streamWriteInt32(streamId, i32(r.farmId or 0))
    streamWriteUInt8(streamId, r.result or NPCPersonDialog.RESULT_REFUSED)
    streamWriteString(streamId, textString(r.messageKey))
    streamWriteString(streamId, textString(r.text))
    streamWriteString(streamId, textString(r.toneKey))
    streamWriteBool(streamId, r.trustPresent == true)
    streamWriteFloat32(streamId, r.trust or 0)
    -- Work page fields (zero for a dialog reply)
    streamWriteString(streamId, wireString(r.cursor))
    streamWriteString(streamId, wireString(r.nextCursor))
    streamWriteInt32(streamId, i32(r.total or 0))
    streamWriteBool(streamId, r.totalKnown == true)
    streamWriteFloat32(streamId, r.sampledTime or 0)
    streamWriteInt32(streamId, i32(r.completedCount or 0))
    streamWriteBool(streamId, r.completedKnown == true)
    local rows = r.rows or {}
    local n = math.min(#rows, NPCPersonDialog.WORK_PAGE_ROWS)
    streamWriteUInt8(streamId, n)
    for i = 1, n do writeWorkRow(streamId, rows[i]) end
end

function NPCPersonDialogReplyEvent:readStream(streamId, connection)
    local r = { rows = {} }
    r.requestId = wireString(streamReadString(streamId))
    r.kind = streamReadUInt8(streamId)
    r.op = streamReadUInt8(streamId)
    r.personId = streamReadInt32(streamId)
    r.farmId = streamReadInt32(streamId)
    r.result = streamReadUInt8(streamId)
    r.messageKey = textString(streamReadString(streamId))
    r.text = textString(streamReadString(streamId))
    r.toneKey = textString(streamReadString(streamId))
    r.trustPresent = streamReadBool(streamId)
    r.trust = streamReadFloat32(streamId)
    r.cursor = wireString(streamReadString(streamId))
    r.nextCursor = wireString(streamReadString(streamId))
    r.total = streamReadInt32(streamId)
    r.totalKnown = streamReadBool(streamId)
    r.sampledTime = streamReadFloat32(streamId)
    r.completedCount = streamReadInt32(streamId)
    r.completedKnown = streamReadBool(streamId)
    local n = streamReadUInt8(streamId)
    for _ = 1, n do r.rows[#r.rows + 1] = readWorkRow(streamId) end
    if not r.trustPresent then r.trust = nil end
    self.reply = r
    self:run(connection)
end

function NPCPersonDialogReplyEvent:run(connection)
    -- Client side only: a reply arriving on the server is ignored.
    if g_server ~= nil and connection ~= nil then return end
    NPCPersonDialogReplyEvent.dispatch(self.reply)
end

--- Hand a reply to the host's client adapter, which owns the private cache
--- and tells the open dialog.
function NPCPersonDialogReplyEvent.dispatch(reply)
    if g_NPCSystem ~= nil and g_NPCSystem.onPersonDialogReply ~= nil then
        g_NPCSystem:onPersonDialogReply(reply)
    end
end

print("[NPC Favor] NPCPersonDialogEvents loaded")
