-- =========================================================
-- FS25 NPC Favor Mod - NPC List Dialog
-- =========================================================
-- MessageDialog subclass that displays all active NPCs in a
-- styled popup table with per-column elements, color coding,
-- and per-row "Go" buttons to teleport to an NPC.
--
-- Shown via: DialogLoader.show("NPCListDialog", "setNPCSystem", g_NPCSystem)
-- =========================================================

NPCListDialog = NPCListDialog or {}
local NPCListDialog_mt = Class(NPCListDialog, MessageDialog)

NPCListDialog.MAX_ROWS = 16

-- Column suffixes matching XML id pattern: r{N}{suffix}
NPCListDialog.COLUMNS = {"num", "name", "act", "dist", "rel", "farm"}

function NPCListDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or NPCListDialog_mt)
    self.npcSystem   = nil
    self.rowDescriptor = {}  -- rowNum -> { revision, personId, canGoTo, kind } (RSF-F357: never an array index)
    self.currentPage = 1
    self.totalPages  = 1
    return self
end

function NPCListDialog:onCreate()
    local ok, err = pcall(function()
        NPCListDialog:superClass().onCreate(self)
    end)
    if not ok then
        print("[NPC Favor] NPCListDialog:onCreate() error: " .. tostring(err))
    end
end

function NPCListDialog:setNPCSystem(npcSystem)
    self.npcSystem = npcSystem
end

function NPCListDialog:onOpen()
    local ok, err = pcall(function()
        NPCListDialog:superClass().onOpen(self)
    end)
    if not ok then
        print("[NPC Favor] NPCListDialog:onOpen() error: " .. tostring(err))
        return
    end
    self.currentPage = 1  -- always start on page 1
    self:updateDisplay()
end

--- RSF-F357: the rows come from the copied roster view (live, waiting, presence
--- and opaque rows), never from the active array; a descriptor holds the
--- snapshot revision and the durable number, so a reordered roster can never
--- send a button to somebody else.
function NPCListDialog:rosterRows()
    local sys = self.npcSystem
    if sys == nil or sys.getNeighbourRosterView == nil then return {}, nil end
    local view = sys:getNeighbourRosterView()
    return view.rows or {}, view
end

function NPCListDialog:updateDisplay()
    local sys = self.npcSystem
    if not sys then
        if self.titleText then self.titleText:setText("NPC System Not Available") end
        return
    end

    local rows, view = self:rosterRows()
    local totalNPCs = #rows
    self.totalPages = math.max(1, math.ceil(totalNPCs / self.MAX_ROWS))
    self.currentPage = math.min(self.currentPage, self.totalPages)

    local pageStart = (self.currentPage - 1) * self.MAX_ROWS + 1
    local pageEnd   = self.currentPage * self.MAX_ROWS

    -- Reset row->descriptor mapping
    self.rowDescriptor = {}

    -- Title
    if self.titleText then
        local live = 0
        for _, r in ipairs(rows) do if r.kind == "LIVE" then live = live + 1 end end
        local state = ""
        if view ~= nil and view.snapshotState ~= "CURRENT" then
            state = "  [" .. tostring(view.snapshotState) .. "]"
        end
        self.titleText:setText(string.format("NPC Roster  (%d/%d)%s",
            live, sys.settings and sys.settings.maxNPCs or 0, state))
    end

    -- Subtitle
    if self.subtitleText then
        local gameTime = sys:getCurrentGameTime()
        local hour = math.floor(gameTime / 60) % 24
        local min = math.floor(gameTime) % 60
        self.subtitleText:setText(string.format("Game Time: %02d:%02d", hour, min))
    end

    -- Clear all rows
    for i = 1, self.MAX_ROWS do
        self:clearRow(i)
    end

    -- Fill rows for current page only
    local rowIdx = 0
    for i, r in ipairs(rows) do
        if i >= pageStart and i <= pageEnd then
            rowIdx = rowIdx + 1
            self:fillRow(rowIdx, r, view, sys)
        end
    end

    -- Hide unused row backgrounds
    for i = rowIdx + 1, self.MAX_ROWS do
        local bg = self["r" .. i .. "bg"]
        if bg then bg:setVisible(false) end
    end

    -- Bottom divider
    if self.bottomDivider then
        self.bottomDivider:setVisible(rowIdx > 0)
    end

    -- Footer: hint on single page, page indicator on multi-page
    if self.footerText then
        if self.totalPages > 1 then
            self.footerText:setText(string.format("Page %d / %d", self.currentPage, self.totalPages))
        else
            self.footerText:setText("Click Go to teleport  |  Press E near NPC to interact")
        end
    end

    -- Prev / Next button visibility
    local showPrev = self.totalPages > 1 and self.currentPage > 1
    local showNext = self.totalPages > 1 and self.currentPage < self.totalPages
    if self.prevBtnBg  then self.prevBtnBg:setVisible(showPrev)  end
    if self.prevBtnTxt then self.prevBtnTxt:setVisible(showPrev) end
    if self.prevBtn    then self.prevBtn:setVisible(showPrev)    end
    if self.nextBtnBg  then self.nextBtnBg:setVisible(showNext)  end
    if self.nextBtnTxt then self.nextBtnTxt:setVisible(showNext) end
    if self.nextBtn    then self.nextBtn:setVisible(showNext)    end
end

--- Clear a row's cells, hide its background and Go button layers.
function NPCListDialog:clearRow(rowNum)
    local prefix = "r" .. rowNum
    for _, col in ipairs(self.COLUMNS) do
        local elem = self[prefix .. col]
        if elem then
            elem:setText("")
            elem:setVisible(false)
        end
    end
    local bg = self[prefix .. "bg"]
    if bg then bg:setVisible(false) end
    -- 3-layer Go button: bg, text, hit
    local gobg = self[prefix .. "gobg"]
    if gobg then gobg:setVisible(false) end
    local gotxt = self[prefix .. "gotxt"]
    if gotxt then gotxt:setVisible(false) end
    local goBtn = self[prefix .. "go"]
    if goBtn then goBtn:setVisible(false) end
end

--- Fill a row from a copied roster row and color-code the cells.
function NPCListDialog:fillRow(rowNum, r, view, sys)
    local prefix = "r" .. rowNum

    -- The descriptor: revision, durable number and the action flag. Waiting,
    -- presence and opaque rows have no Go.
    self.rowDescriptor[rowNum] = {
        revision = view and view.revision or 0,
        personId = r.personId,
        canGoTo = r.canGoTo == true,
        kind = r.kind,
    }

    -- Show background
    local bg = self[prefix .. "bg"]
    if bg then bg:setVisible(true) end

    -- Show the 3-layer Go button only for a live durable person with a position
    local gobg = self[prefix .. "gobg"]
    if gobg then gobg:setVisible(r.canGoTo == true) end
    local gotxt = self[prefix .. "gotxt"]
    if gotxt then gotxt:setVisible(r.canGoTo == true) end
    local goBtn = self[prefix .. "go"]
    if goBtn then goBtn:setVisible(r.canGoTo == true) end

    -- # column: the durable number (or a dash for an opaque row)
    local numElem = self[prefix .. "num"]
    if numElem then
        numElem:setText(r.personId ~= nil and tostring(r.personId) or "-")
        numElem:setVisible(true)
    end

    -- Name column
    local nameElem = self[prefix .. "name"]
    if nameElem then
        nameElem:setText((r.name or "Unknown"):sub(1, 18))
        nameElem:setVisible(true)
        local live = sys:getNPCById(r.personId or -1)
        local pr, pg, pb = self:getPersonalityColor(live and live.personality or "")
        if r.kind ~= "LIVE" then pr, pg, pb = 0.6, 0.6, 0.65 end
        nameElem:setTextColor(pr, pg, pb, 1)
    end

    -- Activity column: the kind for a row that is not live, else the action
    local actElem = self[prefix .. "act"]
    if actElem then
        local action
        if r.kind == "LIVE" then
            local live = sys:getNPCById(r.personId or -1)
            action = (live and (live.currentAction or live.aiState)) or "idle"
        elseif r.kind == "WAITING" then
            action = "waiting"
        elseif r.kind == "PRESENCE" then
            action = "worker"
        else
            action = "kept"
        end
        actElem:setText(tostring(action):sub(1, 12))
        actElem:setVisible(true)
        if action == "idle" or action == "sleeping" or action == "resting" or action == "waiting" or action == "kept" then
            actElem:setTextColor(0.55, 0.55, 0.6, 1)
        elseif action == "walking" or action == "traveling" then
            actElem:setTextColor(0.5, 0.8, 0.5, 1)
        elseif action == "working" or action == "field work" or action == "worker" then
            actElem:setTextColor(0.9, 0.75, 0.3, 1)
        elseif action == "socializing" or action == "gathering" then
            actElem:setTextColor(0.5, 0.7, 0.9, 1)
        else
            actElem:setTextColor(0.75, 0.75, 0.75, 1)
        end
    end

    -- Distance column: only a row with a position
    local distElem = self[prefix .. "dist"]
    if distElem then
        distElem:setVisible(true)
        if r.position ~= nil and sys.playerPositionValid then
            local dx = r.position.x - sys.playerPosition.x
            local dz = r.position.z - sys.playerPosition.z
            local d = math.sqrt(dx * dx + dz * dz)
            distElem:setText(string.format("%.0fm", d))
            if d < 50 then
                distElem:setTextColor(0.3, 1, 0.3, 1)
            elseif d < 150 then
                distElem:setTextColor(0.8, 0.8, 0.8, 1)
            elseif d < 300 then
                distElem:setTextColor(0.6, 0.6, 0.6, 1)
            else
                distElem:setTextColor(0.4, 0.4, 0.45, 1)
            end
        else
            distElem:setText("-")
            distElem:setTextColor(0.4, 0.4, 0.45, 1)
        end
    end

    -- Relationship column: a missing trust is unavailable, never zero
    local relElem = self[prefix .. "rel"]
    if relElem then
        relElem:setVisible(true)
        if r.trust ~= nil then
            relElem:setText(tostring(math.floor(r.trust + 0.5)))
            local rr, rg, rb = self:getRelColor(r.trust)
            relElem:setTextColor(rr, rg, rb, 1)
        else
            relElem:setText("-")
            relElem:setTextColor(0.5, 0.5, 0.55, 1)
        end
    end

    -- Farm column: the house label, or the reason for a row that is not live
    local farmElem = self[prefix .. "farm"]
    if farmElem then
        local farmStr = "-"
        if r.kind == "LIVE" then
            local live = sys:getNPCById(r.personId or -1)
            if live and live.farmName then
                local fieldCount = live.assignedFields and #live.assignedFields or 0
                farmStr = fieldCount > 0 and string.format("%s (%d)", live.farmName, fieldCount) or live.farmName
            elseif r.houseLabel and r.houseLabel ~= "" then
                farmStr = r.houseLabel
            end
        elseif r.reasonKey and r.reasonKey ~= "" then
            farmStr = (g_i18n and g_i18n.hasText and g_i18n:hasText(r.reasonKey)) and g_i18n:getText(r.reasonKey) or r.reasonKey
        end
        farmElem:setText(farmStr:sub(1, 22))
        farmElem:setVisible(true)
        farmElem:setTextColor(0.6, 0.65, 0.7, 1)
    end
end

--- Teleport the player to the person a row named. RSF-F357: the descriptor's
--- durable number is resolved again against the current roster and its
--- current actionability; a row whose person is no longer eligible refreshes
--- and refuses rather than indexing whatever now occupies its position.
function NPCListDialog:teleportToRow(rowNum)
    local d = self.rowDescriptor[rowNum]
    if not d or not d.canGoTo or d.personId == nil then
        return
    end

    local sys = self.npcSystem or g_NPCSystem
    if not sys or sys.getNPCById == nil then return end

    local npc = sys:getNPCById(d.personId)
    if not npc or not npc.position or (sys.isPersonActionable ~= nil and not sys:isPersonActionable(npc)) then
        print(string.format("[NPC Favor] teleportToRow: person #%s is no longer a target; refreshing", tostring(d.personId)))
        self:updateDisplay()
        return
    end

    print(string.format("[NPC Favor] teleportToRow: row=%d -> person #%d -> %s at (%.0f, %.0f)",
        rowNum, d.personId, npc.name or "?", npc.position.x, npc.position.z))

    -- Close dialog first so the player can see where they land
    self:close()

    -- Smart teleport: context-aware positioning (Issue #6)
    local success, message = NPCTeleport.teleportToNPC(sys, npc)
    print("[NPC Favor] " .. (message or "Teleport attempted"))
end

-- Generate onClickRow1..onClickRow16 handlers dynamically
for i = 1, NPCListDialog.MAX_ROWS do
    NPCListDialog["onClickRow" .. i] = function(self)
        self:teleportToRow(i)
    end
end

--- Relationship value -> color.
function NPCListDialog:getRelColor(value)
    if value < 15 then
        return 0.9, 0.3, 0.3     -- Red (hostile)
    elseif value < 30 then
        return 0.9, 0.55, 0.25   -- Orange (unfriendly)
    elseif value < 50 then
        return 0.85, 0.85, 0.4   -- Yellow (neutral)
    elseif value < 70 then
        return 0.5, 0.85, 0.5    -- Green (friendly)
    elseif value < 85 then
        return 0.3, 0.75, 0.9    -- Cyan (close friend)
    else
        return 0.5, 0.6, 1       -- Blue (best friend)
    end
end

--- Personality -> name color.
function NPCListDialog:getPersonalityColor(personality)
    local colors = {
        hardworking = {0.4, 0.9, 0.4},
        lazy        = {0.9, 0.9, 0.3},
        social      = {0.9, 0.6, 0.3},
        loner       = {0.6, 0.6, 0.7},
        generous    = {0.3, 0.9, 0.6},
        greedy      = {0.9, 0.4, 0.4},
        friendly    = {0.4, 0.7, 0.95},
        grumpy      = {0.9, 0.5, 0.3},
    }
    local c = colors[personality] or {1, 1, 1}
    return c[1], c[2], c[3]
end

function NPCListDialog:onClickPrev()
    if self.currentPage > 1 then
        self.currentPage = self.currentPage - 1
        self:updateDisplay()
    end
end

function NPCListDialog:onClickNext()
    if self.currentPage < self.totalPages then
        self.currentPage = self.currentPage + 1
        self:updateDisplay()
    end
end

function NPCListDialog:onClickClose()
    self:close()
end

function NPCListDialog:onClose()
    NPCListDialog:superClass().onClose(self)
end

print("[NPC Favor] NPCListDialog loaded")
