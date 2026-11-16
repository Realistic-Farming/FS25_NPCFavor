-- =========================================================
-- FS25 NPC Favor Mod - Favour pop-up event
-- =========================================================
-- Server to client: one favour pop-up ("New: ... needs help!", "Step 1 done:
-- ...", "Done: ...", "Failed: ...", "Cancelled: ...", "Perfect! ... bonus!",
-- "Favor accepted: ...") for the players it belongs to.
--
-- The pop-ups are raised inside the server's own favour sim. A dedicated
-- server has no screen, and a listen host's screen is not a joined player's,
-- so before this event a joined player saw none of them. The event carries a
-- kind, one number (the step id of a step pop-up) and one piece of text (the
-- favour's own words); the receiving machine resolves its own language and
-- colour from the kind, so no sentence of ours travels.
--
-- Who gets it is decided on the server (NPCFavorFlash.lua, flashAudience):
-- the players of the farm that owns the favour, both farms of a companion
-- favour, or every player with a farm for an offer nobody owns yet.
--
-- Pattern from: NPCPersonDialogReplyEvent (server to the requesting client).
-- =========================================================

NPCFavorFlashEvent = NPCFavorFlashEvent or {}
local NPCFavorFlashEvent_mt = Class(NPCFavorFlashEvent, Event)

InitEventClass(NPCFavorFlashEvent, "NPCFavorFlashEvent")

NPCFavorFlashEvent.KIND = {
    NEW_FAVOR = 1, STEP_DONE = 2, COMPLETED = 3, FAILED = 4, CANCELLED = 5, PERFECT = 6, ACCEPTED = 7,
}
NPCFavorFlashEvent.KIND_MAX = 7

-- The wording and colour of each kind, resolved on the machine that shows it.
NPCFavorFlashEvent.WORDING = {
    [1] = { key = "npc_hud_new_favor", fallback = "New: %s needs help!",  color = {1, 0.9, 0.3, 1} },
    [2] = { key = "npc_hud_step_done", fallback = "Step %d done: %s",     color = {0.3, 1, 0.3, 1} },
    [3] = { key = "npc_hud_completed", fallback = "Done: %s",             color = {0.3, 1, 0.3, 1} },
    [4] = { key = "npc_hud_failed",    fallback = "Failed: %s",           color = {1, 0.3, 0.3, 1} },
    [5] = { key = "npc_hud_cancelled", fallback = "Cancelled: %s",        color = {1, 0.5, 0.3, 1} },
    [6] = { key = "npc_hud_perfect",   fallback = "Perfect! %s bonus!",   color = {1, 1, 0.3, 1} },
    [7] = { key = nil,                 fallback = "Favor accepted: %s",   color = {0.3, 1, 0.3, 1} },
}

NPCFavorFlashEvent.TEXT_LIMIT = 200

--- Cut text to the wire limit on a character boundary (never mid UTF-8 sequence).
function NPCFavorFlashEvent.wireText(value)
    local s = tostring(value or "")
    local limit = NPCFavorFlashEvent.TEXT_LIMIT
    if #s <= limit then return s end
    local cut = limit
    while cut > 0 do
        local b = s:byte(cut + 1)
        if b == nil or b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return s:sub(1, cut)
end

--- The sentence and colour for a kind, on THIS machine. The same function builds
--- the host's own pop-up and the one a joined player's machine shows, so the two
--- read alike. Returns nil for a kind this build does not know.
function NPCFavorFlashEvent.compose(kind, n, text)
    local k = NPCFavorFlashEvent.WORDING[kind]
    if k == nil then return nil end
    local fmt = k.fallback
    if k.key ~= nil and g_i18n ~= nil then
        fmt = g_i18n:getText(k.key) or k.fallback
    end
    -- One builder for the translated wording and for the fallback, so a translation whose
    -- placeholders do not fit never leaves the pop-up without a sentence.
    local function build(f)
        if kind == NPCFavorFlashEvent.KIND.STEP_DONE then
            return string.format(f, tonumber(n) or 0, tostring(text or ""))
        end
        return string.format(f, tostring(text or ""))
    end
    local ok, msg = pcall(build, fmt)
    if not ok then
        msg = build(k.fallback)
    end
    return msg, k.color
end

function NPCFavorFlashEvent.emptyNew()
    local self = Event.new(NPCFavorFlashEvent_mt)
    self.kind = 0
    self.n = 0
    self.text = ""
    return self
end

function NPCFavorFlashEvent.new(kind, n, text)
    local self = NPCFavorFlashEvent.emptyNew()
    self.kind = kind or 0
    self.n = tonumber(n) or 0
    self.text = NPCFavorFlashEvent.wireText(text)
    return self
end

function NPCFavorFlashEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.kind)
    streamWriteInt32(streamId, self.n)
    streamWriteString(streamId, self.text)
end

function NPCFavorFlashEvent:readStream(streamId, connection)
    self.kind = streamReadUInt8(streamId)
    self.n = streamReadInt32(streamId)
    self.text = NPCFavorFlashEvent.wireText(streamReadString(streamId))
    if self.kind < 1 or self.kind > NPCFavorFlashEvent.KIND_MAX then
        print(string.format("[NPCFavor SECURITY] Invalid favour pop-up kind: %s", tostring(self.kind)))
        return
    end
    self:run(connection)
end

--- Client side only: a pop-up arriving on the server is ignored. The machine's
--- own favour HUD shows it.
function NPCFavorFlashEvent:run(connection)
    if g_server ~= nil and connection ~= nil then return end
    local sys = g_NPCSystem
    if sys == nil or sys.favorHUD == nil then return end
    local msg, color = NPCFavorFlashEvent.compose(self.kind, self.n, self.text)
    if msg == nil then return end
    sys.favorHUD:flashFavor(msg, color)
end

--- Server side: send one pop-up to every connected player the audience names.
--- audience nil means every player who belongs to an ordinary farm; otherwise a
--- set of farm ids. The host's own player (g_localPlayer) is skipped, because the
--- host's own screen is shown directly. Returns how many players were sent it.
function NPCFavorFlashEvent.sendTo(audience, kind, n, text)
    if g_server == nil then return 0 end
    local mission = g_currentMission
    local playerSystem = mission ~= nil and mission.playerSystem or nil
    if playerSystem == nil or type(playerSystem.players) ~= "table" then return 0 end
    local sent = 0
    for _, player in pairs(playerSystem.players) do
        if type(player) == "table" and player ~= g_localPlayer then
            local connection = player.connection
            if connection ~= nil and type(connection.sendEvent) == "function" then
                local ok, farmId = pcall(player.getFarmId, player)
                if ok and NPCFarmIdentity.isOrdinaryFarmId(farmId)
                    and (audience == nil or audience[farmId] == true) then
                    connection:sendEvent(NPCFavorFlashEvent.new(kind, n, text))
                    sent = sent + 1
                end
            end
        end
    end
    return sent
end

print("[NPC Favor] NPCFavorFlashEvent loaded")
