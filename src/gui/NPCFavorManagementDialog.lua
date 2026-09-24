-- =========================================================
-- FS25 NPC Favor Mod - Favor Management Dialog
-- =========================================================
-- Displays active favors with ability to view details, cancel,
-- navigate to NPC, and manually complete.
-- RSF-F148: the same five row elements page over the active list, and a
-- Recovery mode shows the private server-validated recovery view with
-- Resume / Assign-and-resume, an explicit target-farm picker for
-- host/admin assignment, and YesNoDialog confirmation. Cancel is routed
-- through the server exactly like Done, with no extra local penalty.
-- Modeled after NPCListDialog for FS25 compatibility
-- =========================================================

NPCFavorManagementDialog = NPCFavorManagementDialog or {}
local NPCFavorManagementDialog_mt = Class(NPCFavorManagementDialog, MessageDialog)

NPCFavorManagementDialog.MAX_FAVORS = 5  -- Max visible favors per page
NPCFavorManagementDialog.INSTANCE = nil  -- open dialog receiving replies

-- 3-layer button color definitions (normal + hover states)
NPCFavorManagementDialog.BTN_COLORS = {
    blue  = { BG = {0.12,0.2,0.35,0.95}, BG_H = {0.2,0.32,0.5,1}, TXT = {0.7,0.85,1,1}, TXT_H = {0.9,0.95,1,1} },
    red   = { BG = {0.35,0.12,0.12,0.95}, BG_H = {0.45,0.18,0.18,1}, TXT = {1,0.7,0.7,1}, TXT_H = {1,0.9,0.9,1} },
    green = { BG = {0.12,0.35,0.12,0.95}, BG_H = {0.18,0.45,0.18,1}, TXT = {0.7,1,0.7,1}, TXT_H = {0.9,1,0.9,1} },
}
NPCFavorManagementDialog.BTN_TYPE_MAP = { view="blue", cancel="red", ["goto"]="blue", complete="green",
    modetoggle="blue", pageprev="blue", pagenext="blue", farmprev="blue", farmnext="blue" }

-- Mod-scoped i18n with Missing-reject (same shape as NPCDialog.getModText).
local MGMT_MOD_NAME = (NPCFavorModName or g_currentModName)
local function getModText(key, fallback)
    if key == nil or key == "" then return fallback end
    local text = nil
    local modEnv = g_modEnvironments and g_modEnvironments[MGMT_MOD_NAME]
    local i18n = (modEnv and modEnv.i18n) or g_i18n
    if i18n ~= nil then
        local ok, result = pcall(function() return i18n:getText(key) end)
        if ok and type(result) == "string" and result ~= "" and not result:find("^Missing") then
            text = result
        end
    end
    if type(text) ~= "string" or text == "" then return fallback end
    return text
end

-- =========================================================
-- Client request id allocator (bounded, never recycled in a session)
-- =========================================================

NPCFavorManagementDialog._nextRequestId = 1

function NPCFavorManagementDialog.allocateRequestId()
    local n = NPCFavorManagementDialog._nextRequestId or 1
    if n >= NPCFarmIdentity.WIRE_MAX then
        return nil  -- counter exhausted: commands unavailable until a fresh mission
    end
    NPCFavorManagementDialog._nextRequestId = n + 1
    return NPCFarmIdentity.encodeWireNumber(n)
end

function NPCFavorManagementDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or NPCFavorManagementDialog_mt)
    self.npcSystem = nil
    self.favorIndices = {}  -- Maps row number to favor (active mode) or view row (recovery mode)
    self.mode = "active"
    self.page = 1
    self.recoveryView = nil
    self.pendingViewRequestId = nil
    self.cursorStack = {}
    self.currentCursor = ""
    self.selectedFarmId = nil     -- explicit target farm id, never an index
    self.landOnLastPage = false
    self.footerMessage = nil
    return self
end

--- Index of the explicitly selected farm in the current eligible list, or nil.
function NPCFavorManagementDialog:selectedFarmEntry()
    local view = self.recoveryView
    if view == nil or self.selectedFarmId == nil then return nil, nil end
    for i, farm in ipairs(view.eligibleFarms) do
        if farm.farmId == self.selectedFarmId then return farm, i end
    end
    return nil, nil
end

function NPCFavorManagementDialog:onCreate()
    local ok, err = pcall(function()
        NPCFavorManagementDialog:superClass().onCreate(self)
    end)
    if not ok then
        print("[NPC Favor] NPCFavorManagementDialog:onCreate() error: " .. tostring(err))
    end
end

function NPCFavorManagementDialog:setNPCSystem(npcSystem)
    self.npcSystem = npcSystem
end

function NPCFavorManagementDialog:onOpen()
    local ok, err = pcall(function()
        NPCFavorManagementDialog:superClass().onOpen(self)
    end)
    if not ok then
        print("[NPC Favor] NPCFavorManagementDialog:onOpen() error: " .. tostring(err))
        return
    end
    NPCFavorManagementDialog.INSTANCE = self
    self.mode = "active"
    self.page = 1
    self.recoveryView = nil
    self.pendingViewRequestId = nil
    self.cursorStack = {}
    self.currentCursor = ""
    self.selectedFarmId = nil
    self.landOnLastPage = false
    self.footerMessage = nil
    -- RSF-F357: watch the shared work page while open and ask for it now.
    if self.npcSystem and self.npcSystem.watchPersonalWork and not self._watchingWork then
        self._watchingWork = true
        self.npcSystem:watchPersonalWork(true)
    end
    if self.npcSystem and self.npcSystem.requestPersonalWorkView then
        self.npcSystem:requestPersonalWorkView("")
    end
    self:updateDisplay()
    -- Ask for the recovery count so the toggle can show it.
    self:requestRecoveryView("")
end

-- =========================================================
-- Recovery view plumbing
-- =========================================================

function NPCFavorManagementDialog:requestRecoveryView(cursor)
    if NPCFavorRecoveryViewRequestEvent == nil then return end
    local requestId = NPCFavorManagementDialog.allocateRequestId()
    if requestId == nil then
        self.footerMessage = getModText("npc_recovery_unavailable", "Recovery is unavailable until the game is reloaded.")
        return
    end
    self.pendingViewRequestId = requestId
    self.currentCursor = cursor or ""
    NPCFavorRecoveryViewRequestEvent.sendRequest(requestId, cursor or "")
end

--- Static entry for a view reply (from the event or the local host path).
function NPCFavorManagementDialog.onRecoveryViewReply(reply)
    local dlg = NPCFavorManagementDialog.INSTANCE
    if dlg == nil or reply == nil then return end
    -- A stale response cannot overwrite a newer requested page.
    if dlg.pendingViewRequestId == nil or reply.requestId ~= dlg.pendingViewRequestId then return end
    dlg.pendingViewRequestId = nil
    local oldRevision = dlg.recoveryView and dlg.recoveryView.collectionRevision
    local oldSelectedName = nil
    if dlg.recoveryView ~= nil then
        local prev = dlg:selectedFarmEntry()
        oldSelectedName = prev and prev.name or nil
    end
    dlg.recoveryView = {
        requestId = reply.requestId,
        collectionRevision = reply.collectionRevision or "0",
        nextCursor = reply.nextCursor or "",
        unavailable = reply.unavailable == true,
        rows = reply.rows or {},
        eligibleFarms = reply.eligibleFarms or {},
        totalRows = reply.totalRows or #(reply.rows or {}),
        cursor = dlg.currentCursor or "",
    }
    -- On collection change reset to the first page and clear the selection.
    if oldRevision ~= nil and oldRevision ~= dlg.recoveryView.collectionRevision then
        dlg.page = 1
        dlg.selectedFarmId = nil
    end
    if dlg.landOnLastPage then
        dlg.page = dlg:getPageCount()
        dlg.landOnLastPage = false
    end
    -- The picker always starts at "Choose a farm" and never auto-selects. A
    -- selection is re-found by id in every reply and cleared when the farm is
    -- gone or renamed, so a reordered list can never silently pick another.
    if dlg.selectedFarmId ~= nil then
        local farm = dlg:selectedFarmEntry()
        if farm == nil or (oldSelectedName ~= nil and farm.name ~= oldSelectedName) then
            dlg.selectedFarmId = nil
        end
    end
    dlg:updateDisplay()
end

--- Static entry for a command result.
function NPCFavorManagementDialog.onRecoveryResult(reply)
    local dlg = NPCFavorManagementDialog.INSTANCE
    if dlg == nil or reply == nil then return end
    local key = reply.messageKey
    if key == nil or key == "" then
        if reply.result == NPCFavorRecovery.RESULT_OK then
            key = "npc_recovery_ok_resumed"
        else
            key = "npc_recovery_refused_stale"
        end
    end
    dlg.footerMessage = getModText(key, key)
    dlg.selectedFarmId = nil
    -- Refresh from the authoritative state; the UI never shows success early.
    dlg:requestRecoveryView(dlg.currentCursor or "")
    dlg:updateDisplay()
end

-- =========================================================
-- Display
-- =========================================================

local function setText(elem, text)
    if elem and elem.setText then elem:setText(text) end
end

local function setVisible(elem, visible)
    if elem and elem.setVisible then elem:setVisible(visible) end
end

function NPCFavorManagementDialog:setButtonVisible(name, visible)
    setVisible(self[name], visible)
    setVisible(self[name .. "bg"], visible)
    setVisible(self[name .. "txt"], visible)
end

--- RSF-F357 section 9b: active mode lists the owner's copied work page (this
--- farm's accepted work and the public offers), never the local favour
--- collections. Each row keeps the fields the row painter reads.
function NPCFavorManagementDialog:getPageItems()
    if self.mode == "recovery" then
        local view = self.recoveryView
        return (view and view.rows) or {}
    end
    local sys = self.npcSystem
    if not sys or sys.getPersonalWorkView == nil then return {} end
    local view = sys:getPersonalWorkView()
    self.workView = view
    if view == nil or (view.state ~= "CURRENT" and view.state ~= "LAST_CONFIRMED") then return {} end
    local items = {}
    for _, r in ipairs(view.rows or {}) do
        r.npcId = r.personIdPresent and r.personId or nil
        r.timeRemaining = r.timeRemainingMs
        r.reward = r.rewardMoney
        items[#items + 1] = r
    end
    return items
end

--- Static entry: the shared page changed (a reply arrived); repaint if open.
function NPCFavorManagementDialog.onPersonalWorkView()
    local dlg = NPCFavorManagementDialog.INSTANCE
    if dlg == nil or dlg.mode ~= "active" then return end
    dlg:updateDisplay()
end

--- Static entry: a work action from this dialog came back.
function NPCFavorManagementDialog.onWorkActionResult(reply)
    local dlg = NPCFavorManagementDialog.INSTANCE
    if dlg == nil or reply == nil then return end
    local key = reply.messageKey
    if key ~= nil and key ~= "" then
        dlg.footerMessage = getModText(key, key)
    end
    if dlg.npcSystem and dlg.npcSystem.requestPersonalWorkView then
        dlg.npcSystem:requestPersonalWorkView("")
    end
    dlg:updateDisplay()
end

function NPCFavorManagementDialog:getPageCount()
    local items = self:getPageItems()
    return math.max(1, math.ceil(#items / self.MAX_FAVORS))
end

function NPCFavorManagementDialog:updateDisplay()
    local sys = self.npcSystem
    if not sys or not sys.favorSystem then
        setText(self.titleText, "Favor System Not Available")
        return
    end

    self.favorIndices = {}
    local items = self:getPageItems()
    local pageCount = self:getPageCount()
    if self.page > pageCount then self.page = pageCount end
    if self.page < 1 then self.page = 1 end

    -- The server reports the total across every network page.
    local recoveryCount = (self.recoveryView and self.recoveryView.totalRows) or 0

    -- Title
    if self.mode == "recovery" then
        setText(self.titleText, string.format(getModText("npc_recovery_title", "Favor Recovery (%d)"), recoveryCount))
    else
        setText(self.titleText, string.format(getModText("npc_mgmt_title_active", "Active Favors (%d)"), #items))
    end

    -- Subtitle
    local gameTime = sys:getCurrentGameTime()
    local hour = math.floor(gameTime / 60) % 24
    local min = math.floor(gameTime) % 60
    local clock = string.format(getModText("npc_mgmt_game_time", "Game Time: %02d:%02d"), hour, min)
    if self.mode == "recovery" then
        setText(self.subtitleText, clock .. "  |  " ..
            getModText("npc_recovery_subtitle", "Paused and recovered favors. Nothing here runs or pays until you resume it."))
    else
        setText(self.subtitleText, clock .. "  |  " .. getModText("npc_mgmt_subtitle_active", "Manage your active favors"))
    end

    -- Mode toggle
    if self.mode == "recovery" then
        setText(self.modetoggletxt, getModText("npc_recovery_btn_active", "Active favors"))
    else
        setText(self.modetoggletxt, string.format(getModText("npc_recovery_btn_recovery", "Recovery (%d)"), recoveryCount))
    end
    self:setButtonVisible("modetoggle", true)

    -- Pager
    local hasMoreNetwork = self.mode == "recovery" and self.recoveryView ~= nil and self.recoveryView.nextCursor ~= ""
    local hasPrevNetwork = self.mode == "recovery" and #self.cursorStack > 0
    setText(self.pageText, string.format(getModText("npc_recovery_page", "Page %d / %d"), self.page, pageCount))
    setVisible(self.pageText, true)
    self:setButtonVisible("pageprev", self.page > 1 or hasPrevNetwork)
    self:setButtonVisible("pagenext", self.page < pageCount or hasMoreNetwork)

    -- Rows
    for i = 1, self.MAX_FAVORS do
        self:clearFavorRow(i)
    end
    local first = (self.page - 1) * self.MAX_FAVORS
    for i = 1, self.MAX_FAVORS do
        local item = items[first + i]
        if item ~= nil then
            if self.mode == "recovery" then
                self:fillRecoveryRow(i, item, sys)
            else
                self:fillFavorRow(i, item, sys)
            end
        end
    end

    -- Farm picker (host/admin assignment only)
    local view = self.recoveryView
    local pickerVisible = self.mode == "recovery" and view ~= nil and #view.eligibleFarms > 0
    if pickerVisible then
        local label
        local farm = self:selectedFarmEntry()
        if farm then
            label = string.format(getModText("npc_recovery_picker_selected", "Assign to: %s (#%d)"), farm.name, farm.farmId)
        else
            label = getModText("npc_recovery_picker_choose", "Assign to: Choose a farm")
        end
        setText(self.farmPickerLabel, label)
    end
    setVisible(self.farmPickerLabel, pickerVisible)
    self:setButtonVisible("farmprev", pickerVisible)
    self:setButtonVisible("farmnext", pickerVisible)

    -- Footer
    if self.footerMessage then
        setText(self.footerText, self.footerMessage)
    elseif self.mode == "recovery" then
        if view and view.unavailable then
            setText(self.footerText, getModText("npc_recovery_unavailable", "Recovery is unavailable until the game is reloaded."))
        elseif recoveryCount == 0 then
            setText(self.footerText, getModText("npc_recovery_empty", "No paused or recovered favors."))
        else
            setText(self.footerText, getModText("npc_recovery_footer",
                "Resume keeps saved progress and payments. Assign is for a deleted farm's job and needs an explicit target farm."))
        end
    else
        if #items > self.MAX_FAVORS then
            setText(self.footerText, string.format(getModText("npc_mgmt_footer_paging", "Showing %d of %d favors  |  Cancel applies the abandon penalty"),
                math.min(self.MAX_FAVORS, #items - first), #items))
        else
            setText(self.footerText, getModText("npc_mgmt_footer_active", "Cancel applies the abandon penalty  |  Done asks the neighbour to close the favor"))
        end
    end
end

--- Clear a favor row's elements
function NPCFavorManagementDialog:clearFavorRow(rowNum)
    local prefix = "favor" .. rowNum
    setVisible(self[prefix .. "border"], false)
    setVisible(self[prefix .. "bg"], false)
    local fields = {"npc", "desc", "time", "reward"}
    for _, field in ipairs(fields) do
        local elem = self[prefix .. field]
        if elem then
            setText(elem, "")
            setVisible(elem, false)
        end
    end
    local buttons = {"view", "cancel", "goto", "complete"}
    for _, btn in ipairs(buttons) do
        self:setButtonVisible(prefix .. btn, false)
    end
end

--- Fill a favor row with data (active mode)
function NPCFavorManagementDialog:fillFavorRow(rowNum, favor, sys)
    local prefix = "favor" .. rowNum
    self.favorIndices[rowNum] = favor

    setVisible(self[prefix .. "border"], true)
    setVisible(self[prefix .. "bg"], true)

    -- RSF-F357: the saved name from the row; trust only for a live durable
    -- person, never a zero for a waiting or unproven one.
    local npc = favor.npcId and sys:getNPCById(favor.npcId) or nil
    local npcName = (npc and npc.name) or favor.npcName or "Unknown NPC"
    local relationship = npc and npc.relationship or nil

    local npcElem = self[prefix .. "npc"]
    if npcElem then
        local tag = ""
        if favor.recoveredFromLegacy then
            tag = "  [" .. getModText("npc_recovery_tag_resumed", "Resumed") .. "]"
        elseif favor.status == "pending" then
            tag = "  [" .. getModText("npc_recovery_tag_pending", "Offer") .. "]"
        end
        local relText = relationship ~= nil and string.format("Rel: %d", relationship) or getModText("npc_recovery_unknown", "unknown")
        setText(npcElem, string.format("%s (%s)%s", npcName, relText, tag))
        setVisible(npcElem, true)
        if npcElem.setTextColor then
            local r, g, b = self:getRelationshipColor(relationship or 0)
            if relationship == nil then r, g, b = 0.6, 0.6, 0.65 end
            npcElem:setTextColor(r, g, b, 1)
        end
    end

    local descElem = self[prefix .. "desc"]
    if descElem then
        local desc = favor.description or favor.type or "Unknown favor"
        setText(descElem, desc:sub(1, 80))
        setVisible(descElem, true)
        if descElem.setTextColor then descElem:setTextColor(0.9, 0.9, 0.9, 1) end
    end

    local timeElem = self[prefix .. "time"]
    if timeElem then
        setText(timeElem, self:getTimeRemainingText(favor, sys))
        setVisible(timeElem, true)
        if timeElem.setTextColor then
            local urgency = self:getTimeUrgency(favor, sys)
            if urgency > 0.7 then
                timeElem:setTextColor(0.9, 0.3, 0.3, 1)
            elseif urgency > 0.4 then
                timeElem:setTextColor(0.9, 0.7, 0.3, 1)
            else
                timeElem:setTextColor(0.5, 0.85, 0.5, 1)
            end
        end
    end

    local rewardElem = self[prefix .. "reward"]
    if rewardElem then
        local reward = 0
        if favor.reward then
            if type(favor.reward) == "table" then
                reward = favor.reward.amount or favor.reward.money or 0
            else
                reward = favor.reward
            end
        end
        setText(rewardElem, string.format("Reward: $%d", reward))
        setVisible(rewardElem, true)
        if rewardElem.setTextColor then rewardElem:setTextColor(0.3, 0.9, 0.3, 1) end
    end

    setText(self[prefix .. "viewtxt"], getModText("npc_mgmt_btn_view", "View"))
    setText(self[prefix .. "gototxt"], getModText("npc_mgmt_btn_goto", "Go To"))
    self:setButtonVisible(prefix .. "view", true)
    self:setButtonVisible(prefix .. "goto", true)
    setText(self[prefix .. "canceltxt"], getModText("npc_mgmt_btn_cancel", "Cancel"))
    setText(self[prefix .. "completetxt"], getModText("npc_mgmt_btn_done", "Done"))
    -- The row's own flags for this actor decide the buttons; a recovered row
    -- keeps its F148 door (the handlers redirect).
    local accepted = favor.status == "active" or favor.status == "in_progress"
    self:setButtonVisible(prefix .. "cancel", accepted and (favor.canAbandon == true or favor.recoveredFromLegacy == true))
    self:setButtonVisible(prefix .. "complete", accepted and (favor.canComplete == true or favor.recoveredFromLegacy == true))
end

--- Format a frozen game-millisecond duration directly (no mission clock).
local function formatMs(ms)
    if type(ms) ~= "number" or ms ~= ms then return "?" end
    if ms < 0 then ms = 0 end
    local totalMinutes = math.floor(ms / 60000)
    local hours = math.floor(totalMinutes / 60)
    local mins = totalMinutes % 60
    return string.format("%dh %02dm", hours, mins)
end

local function triText(v)
    if v == 1 then return getModText("npc_recovery_yes", "yes") end
    if v == 0 then return getModText("npc_recovery_no", "no") end
    return getModText("npc_recovery_unknown", "unknown")
end

function NPCFavorManagementDialog:reasonLabel(reason)
    if reason == nil or reason == "" then return "" end
    local keys = {
        legacy_acceptance_unknown = "npc_recovery_reason_legacy_acceptance_unknown",
        owner_unresolved = "npc_recovery_reason_owner_unresolved",
        invalid_record = "npc_recovery_reason_invalid_record",
        owner_farm_deleted = "npc_recovery_reason_owner_farm_deleted",
    }
    local key = keys[reason]
    if key then return getModText(key, reason) end
    -- Saved tokens are not UI copy: show a fixed label and log the token.
    print(string.format("[NPC Favor] Recovery row carries an unrecognised reason token '%s' (inspect only)", tostring(reason)))
    return getModText("npc_recovery_reason_unknown_token", "Unrecognised record")
end

function NPCFavorManagementDialog:farmLabel(farmId)
    local farm = NPCFarmIdentity.getLiveFarm(farmId)
    if farm ~= nil and NPCFarmIdentity.isOrdinaryFarmId(farmId) then
        return string.format("%s (#%d)", tostring(farm.name or ""), farmId)
    end
    return getModText("npc_recovery_owner_unknown", "owner unknown")
end

--- Fill a row from a recovery view row (recovery mode)
function NPCFavorManagementDialog:fillRecoveryRow(rowNum, row, sys)
    local prefix = "favor" .. rowNum
    self.favorIndices[rowNum] = row

    setVisible(self[prefix .. "border"], true)
    setVisible(self[prefix .. "bg"], true)

    local npc = sys:getNPCById(row.npcId)
    local npcName = (npc and npc.name) or row.npcName or "Unknown NPC"
    local relationship = npc and npc.relationship or 0

    local npcElem = self[prefix .. "npc"]
    if npcElem then
        local tag
        if row.status == NPCFavorRecovery.STATUS_PAUSED then
            tag = getModText("npc_recovery_tag_paused", "Paused")
        else
            tag = getModText("npc_recovery_tag_resumed", "Resumed")
        end
        setText(npcElem, string.format("%s (Rel: %d)  [%s]", npcName, relationship, tag))
        setVisible(npcElem, true)
        if npcElem.setTextColor then
            local r, g, b = self:getRelationshipColor(relationship)
            npcElem:setTextColor(r, g, b, 1)
        end
    end

    local descElem = self[prefix .. "desc"]
    if descElem then
        local desc = row.description or row.type or "Unknown favor"
        local reason = self:reasonLabel(row.recoveryReason)
        if reason ~= "" then desc = desc .. "  |  " .. reason end
        setText(descElem, desc:sub(1, 110))
        setVisible(descElem, true)
        if descElem.setTextColor then descElem:setTextColor(0.9, 0.9, 0.9, 1) end
    end

    local timeElem = self[prefix .. "time"]
    if timeElem then
        local timeText
        if row.timeKnown then
            timeText = string.format(getModText("npc_recovery_time", "Remaining: %s (%d%% done)"),
                formatMs(row.timeRemaining), math.floor(row.progress or 0))
        else
            timeText = getModText("npc_recovery_time_unknown", "Remaining time unavailable")
        end
        if not row.fieldKnown and row.type == "help_harvest" then
            timeText = timeText .. "  |  " .. getModText("npc_recovery_field_unknown", "field unknown, no field protection")
        end
        setText(timeElem, timeText)
        setVisible(timeElem, true)
        if timeElem.setTextColor then timeElem:setTextColor(0.8, 0.8, 0.6, 1) end
    end

    local rewardElem = self[prefix .. "reward"]
    if rewardElem then
        local parts = { getModText("npc_recovery_owner", "Owner: ") .. self:farmLabel(row.ownerFarmId) }
        if row.type == "loan_money" then
            local amount = (row.loanAmount and row.loanAmount >= 0) and string.format("$%d", row.loanAmount)
                or getModText("npc_recovery_unknown", "unknown")
            parts[#parts + 1] = string.format(getModText("npc_recovery_loan", "Loan %s, lent: %s, repaid: %s"),
                amount, triText(row.loanAmountDeducted), triText(row.repaymentCollected))
        end
        parts[#parts + 1] = string.format(getModText("npc_recovery_reward_paid", "Reward paid: %s"), triText(row.rewardPaid))
        if row.inspectOnly and row.unavailableKey ~= "" then
            parts[#parts + 1] = getModText(row.unavailableKey, row.unavailableKey)
        end
        setText(rewardElem, table.concat(parts, "  |  "))
        setVisible(rewardElem, true)
        if rewardElem.setTextColor then rewardElem:setTextColor(0.75, 0.85, 0.95, 1) end
    end

    setText(self[prefix .. "viewtxt"], getModText("npc_mgmt_btn_view", "View"))
    setText(self[prefix .. "gototxt"], getModText("npc_mgmt_btn_goto", "Go To"))
    self:setButtonVisible(prefix .. "view", true)
    self:setButtonVisible(prefix .. "goto", npc ~= nil)

    -- Cancel = token ABANDON for a live recovered row only.
    setText(self[prefix .. "canceltxt"], getModText("npc_mgmt_btn_cancel", "Cancel"))
    self:setButtonVisible(prefix .. "cancel", row.canAbandon == true)

    -- Complete slot: Resume / Assign / Done, or hidden for inspect-only rows.
    local completeLabel = nil
    if row.canComplete then
        completeLabel = getModText("npc_mgmt_btn_done", "Done")
    elseif row.knownOwnerResumable then
        completeLabel = getModText("npc_recovery_btn_resume", "Resume")
    elseif row.assignable then
        completeLabel = getModText("npc_recovery_btn_assign", "Assign")
    end
    if completeLabel then
        setText(self[prefix .. "completetxt"], completeLabel)
        self:setButtonVisible(prefix .. "complete", true)
    else
        self:setButtonVisible(prefix .. "complete", false)
    end
end

--- Get time remaining text for a favor (active mode, mission clock)
function NPCFavorManagementDialog:getTimeRemainingText(favor, sys)
    if not favor.expirationGameTime then
        return "No time limit"
    end
    local currentTime = sys:getCurrentGameTime()
    local remaining = favor.expirationGameTime - currentTime
    if remaining < 0 then
        return "EXPIRED"
    elseif remaining < 60 then
        return string.format("%.0f minutes left", remaining)
    else
        local hours = math.floor(remaining / 60)
        local mins = math.floor(remaining % 60)
        return string.format("%dh %dm left", hours, mins)
    end
end

--- Get time urgency (0-1, where 1 is most urgent)
function NPCFavorManagementDialog:getTimeUrgency(favor, sys)
    if not favor.expirationGameTime or not favor.startTime then
        return 0
    end
    local currentTime = sys:getCurrentGameTime()
    local elapsed = currentTime - favor.startTime
    local total = favor.expirationGameTime - favor.startTime
    if total <= 0 then return 1 end
    return elapsed / total
end

--- Get relationship color
function NPCFavorManagementDialog:getRelationshipColor(value)
    if value < 15 then
        return 0.9, 0.3, 0.3
    elseif value < 30 then
        return 0.9, 0.55, 0.25
    elseif value < 50 then
        return 0.85, 0.85, 0.4
    elseif value < 70 then
        return 0.5, 0.85, 0.5
    elseif value < 85 then
        return 0.3, 0.75, 0.9
    else
        return 0.5, 0.6, 1
    end
end

-- =========================================================
-- Recovery commands
-- =========================================================

--- Build the immutable confirmation context for a view row.
function NPCFavorManagementDialog:buildCommandContext(row, op)
    local view = self.recoveryView
    if view == nil or row == nil then return nil end
    local ctx = {
        token = row.token,
        recordRevision = row.recordRevision,
        collectionRevision = view.collectionRevision,
        originatingViewRequestId = view.requestId,
        op = op,
        targetFarmId = nil,
        targetFarmName = nil,
        row = row,
    }
    if op == NPCFavorRecovery.OP_ASSIGN_AND_RESUME then
        local farm = self:selectedFarmEntry()
        if farm == nil then return nil end
        ctx.targetFarmId = farm.farmId
        ctx.targetFarmName = farm.name
    end
    return ctx
end

function NPCFavorManagementDialog:sendRecoveryCommand(ctx)
    if ctx == nil or NPCFavorRecoveryCommandEvent == nil then return false end
    -- Only the still-current record / view / selection sends the command.
    local view = self.recoveryView
    if view == nil or view.requestId ~= ctx.originatingViewRequestId
        or view.collectionRevision ~= ctx.collectionRevision then
        self.footerMessage = getModText("npc_recovery_refused_stale", "That record changed. The list has been refreshed.")
        self:requestRecoveryView(self.currentCursor or "")
        return false
    end
    local requestId = NPCFavorManagementDialog.allocateRequestId()
    if requestId == nil then
        self.footerMessage = getModText("npc_recovery_unavailable", "Recovery is unavailable until the game is reloaded.")
        self:updateDisplay()
        return false
    end
    return NPCFavorRecoveryCommandEvent.sendCommand({
        requestId = requestId,
        collectionRevision = ctx.collectionRevision,
        recordRevision = ctx.recordRevision,
        token = ctx.token,
        op = ctx.op,
        targetFarmId = ctx.targetFarmId,
        originatingViewRequestId = ctx.originatingViewRequestId,
    })
end

--- YesNoDialog callback: (target, yes, callbackArgs). Only yes == true with a
--- still-current context sends anything; no, cancel or close leaves the record.
function NPCFavorManagementDialog:onConfirmRecovery(yes, ctx)
    if yes ~= true or ctx == nil then return end
    self:sendRecoveryCommand(ctx)
end

function NPCFavorManagementDialog:confirmRecovery(ctx)
    if ctx == nil then return end
    local row = ctx.row
    local npc = self.npcSystem and self.npcSystem:getNPCById(row.npcId)
    local npcName = (npc and npc.name) or row.npcName or "?"
    local lines = {}
    if ctx.op == NPCFavorRecovery.OP_ASSIGN_AND_RESUME then
        lines[#lines + 1] = string.format(getModText("npc_recovery_confirm_assign",
            "Assign this favor to %s (#%d) and resume it?"), ctx.targetFarmName or "?", ctx.targetFarmId or -1)
    elseif ctx.op == NPCFavorRecovery.OP_RESUME then
        lines[#lines + 1] = getModText("npc_recovery_confirm_resume", "Resume this favor for your farm?")
    elseif ctx.op == NPCFavorRecovery.OP_COMPLETE then
        lines[#lines + 1] = getModText("npc_recovery_confirm_complete", "Ask the neighbour to close this recovered favor?")
    else
        lines[#lines + 1] = getModText("npc_recovery_confirm_abandon", "Cancel this recovered favor? The abandon penalty applies.")
    end
    lines[#lines + 1] = string.format("%s: %s", npcName, row.description or row.type or "")
    if row.timeKnown then
        lines[#lines + 1] = string.format(getModText("npc_recovery_time", "Remaining: %s (%d%% done)"),
            formatMs(row.timeRemaining), math.floor(row.progress or 0))
    else
        lines[#lines + 1] = getModText("npc_recovery_time_unknown", "Remaining time unavailable")
    end
    if row.type == "loan_money" then
        local amount = (row.loanAmount and row.loanAmount >= 0) and string.format("$%d", row.loanAmount)
            or getModText("npc_recovery_unknown", "unknown")
        lines[#lines + 1] = string.format(getModText("npc_recovery_loan", "Loan %s, lent: %s, repaid: %s"),
            amount, triText(row.loanAmountDeducted), triText(row.repaymentCollected))
    end
    lines[#lines + 1] = string.format(getModText("npc_recovery_reward_paid", "Reward paid: %s"), triText(row.rewardPaid))
    lines[#lines + 1] = getModText("npc_recovery_confirm_no_money", "Resuming moves no money by itself.")

    if YesNoDialog == nil or YesNoDialog.show == nil then
        self.footerMessage = getModText("npc_recovery_unavailable", "Recovery is unavailable until the game is reloaded.")
        self:updateDisplay()
        return
    end
    local shown = YesNoDialog.show(self.onConfirmRecovery, self, table.concat(lines, "\n"),
        getModText("npc_recovery_confirm_title", "Favor recovery"), nil, nil, nil, nil, nil, ctx)
    if shown == nil then
        self.footerMessage = getModText("npc_recovery_unavailable", "Recovery is unavailable until the game is reloaded.")
        self:updateDisplay()
    end
end

-- =========================================================
-- Header controls
-- =========================================================

function NPCFavorManagementDialog:onClickModeToggle()
    if self.mode == "recovery" then
        self.mode = "active"
    else
        self.mode = "recovery"
        self.cursorStack = {}
        self:requestRecoveryView("")
    end
    self.page = 1
    self.footerMessage = nil
    self.selectedFarmId = nil
    self:updateDisplay()
end

function NPCFavorManagementDialog:onClickPagePrev()
    if self.page > 1 then
        self.page = self.page - 1
    elseif self.mode == "recovery" and #self.cursorStack > 0 then
        local prevCursor = table.remove(self.cursorStack)
        self.landOnLastPage = true   -- land on the last displayed page of that network page
        self:requestRecoveryView(prevCursor)
    end
    self:updateDisplay()
end

function NPCFavorManagementDialog:onClickPageNext()
    if self.page < self:getPageCount() then
        self.page = self.page + 1
    elseif self.mode == "recovery" and self.recoveryView and self.recoveryView.nextCursor ~= "" then
        table.insert(self.cursorStack, self.recoveryView.cursor or "")
        self.page = 1
        self:requestRecoveryView(self.recoveryView.nextCursor)
    end
    self:updateDisplay()
end

function NPCFavorManagementDialog:cycleFarm(step)
    local view = self.recoveryView
    if view == nil or #view.eligibleFarms == 0 then return end
    local n = #view.eligibleFarms
    local _, idx = self:selectedFarmEntry()
    if idx == nil then
        idx = (step > 0) and 1 or n
    else
        idx = idx + step
        if idx < 1 or idx > n then idx = nil end  -- back to "Choose a farm"
    end
    self.selectedFarmId = idx and view.eligibleFarms[idx].farmId or nil
    self:updateDisplay()
end

function NPCFavorManagementDialog:onClickFarmPrev() self:cycleFarm(-1) end
function NPCFavorManagementDialog:onClickFarmNext() self:cycleFarm(1) end

-- =========================================================
-- Row buttons
-- =========================================================

-- Generate onClick handlers for View, Cancel, Goto, Complete for each row
for i = 1, NPCFavorManagementDialog.MAX_FAVORS do
    -- View Details
    NPCFavorManagementDialog["onClickFavor" .. i .. "View"] = function(self)
        local favor = self.favorIndices[i]
        if not favor then return end
        local npc = self.npcSystem:getNPCById(favor.npcId)
        local npcName = npc and npc.name or favor.npcName or "Unknown"
        local reward = 0
        if type(favor.reward) == "table" then
            reward = favor.reward.amount or favor.reward.money or 0
        elseif type(favor.reward) == "number" then
            reward = favor.reward
        end
        local details = string.format(
            "=== Favor Details ===\nNPC: %s\nType: %s\nDescription: %s\nReward: $%d\nStatus: %s\nOwner: %s\nReason: %s\n",
            npcName,
            favor.type or "Unknown",
            favor.description or "No description",
            reward,
            favor.status or "active",
            tostring(favor.ownerFarmId),
            tostring(favor.recoveryReason or "")
        )
        print("[NPC Favor] " .. details)
    end

    -- Cancel Favor: server-routed exactly like Done (RSF-F148). abandonFavor
    -- applies its own half penalty on the server; the old extra local -10 is gone.
    NPCFavorManagementDialog["onClickFavor" .. i .. "Cancel"] = function(self)
        local favor = self.favorIndices[i]
        if not favor or not self.npcSystem or not self.npcSystem.favorSystem then return end

        if self.mode == "recovery" then
            if favor.canAbandon then
                self:confirmRecovery(self:buildCommandContext(favor, NPCFavorRecovery.OP_ABANDON))
            end
            return
        end

        if favor.recoveredFromLegacy == true then
            -- A resumed row on the host: redirect to the exact token command.
            self.mode = "recovery"
            self.page = 1
            self:requestRecoveryView("")
            self.footerMessage = getModText("npc_recovery_dialog_use_view",
                "This is a recovered favor. Finish or cancel it from the Favor menu.")
            self:updateDisplay()
            return
        end

        -- RSF-F357: bound to the work shown (token and revision), sent through
        -- the adapter; the server re-resolves person, owner and record.
        if favor.npcId ~= nil and self.npcSystem.requestWorkAction ~= nil then
            local sent, why = self.npcSystem:requestWorkAction("ABANDON_WORK", favor.npcId,
                { token = favor.token, recordRevision = favor.recordRevision })
            if not sent then
                self.footerMessage = getModText(why or "npc_dialog_unavailable", "Unavailable right now.")
            else
                self.footerMessage = getModText("npc_dialog_pending", "Asking the neighbour...")
            end
        end
        self:updateDisplay()
    end

    -- Go To NPC: only a live durable person named by number has a position
    NPCFavorManagementDialog["onClickFavor" .. i .. "Goto"] = function(self)
        local favor = self.favorIndices[i]
        if not favor or favor.npcId == nil then return end
        local npc = self.npcSystem:getNPCById(favor.npcId)
        if not npc or not npc.position or (self.npcSystem.isPersonActionable ~= nil and not self.npcSystem:isPersonActionable(npc)) then
            print("[NPC Favor] Cannot teleport - NPC not found")
            return
        end
        self:close()
        local success, message = NPCTeleport.teleportToNPC(self.npcSystem, npc)
        print("[NPC Favor] " .. (message or "Teleport attempted"))
    end

    -- Complete / Resume / Assign
    NPCFavorManagementDialog["onClickFavor" .. i .. "Complete"] = function(self)
        local favor = self.favorIndices[i]
        if not favor or not self.npcSystem or not self.npcSystem.favorSystem then return end

        if self.mode == "recovery" then
            if favor.canComplete then
                self:confirmRecovery(self:buildCommandContext(favor, NPCFavorRecovery.OP_COMPLETE))
            elseif favor.knownOwnerResumable then
                self:confirmRecovery(self:buildCommandContext(favor, NPCFavorRecovery.OP_RESUME))
            elseif favor.assignable then
                local ctx = self:buildCommandContext(favor, NPCFavorRecovery.OP_ASSIGN_AND_RESUME)
                if ctx == nil then
                    self.footerMessage = getModText("npc_recovery_pick_farm_first", "Choose a target farm first.")
                    self:updateDisplay()
                    return
                end
                self:confirmRecovery(ctx)
            end
            return
        end

        if favor.recoveredFromLegacy == true then
            self.mode = "recovery"
            self.page = 1
            self:requestRecoveryView("")
            self.footerMessage = getModText("npc_recovery_dialog_use_view",
                "This is a recovered favor. Finish or cancel it from the Favor menu.")
            self:updateDisplay()
            return
        end

        -- RSF-F357: bound to the work shown; the server re-derives the
        -- completion condition from its own record.
        if favor.npcId ~= nil and self.npcSystem.requestWorkAction ~= nil then
            local sent, why = self.npcSystem:requestWorkAction("COMPLETE_WORK", favor.npcId,
                { token = favor.token, recordRevision = favor.recordRevision })
            if not sent then
                self.footerMessage = getModText(why or "npc_dialog_unavailable", "Unavailable right now.")
            else
                self.footerMessage = getModText("npc_dialog_pending", "Asking the neighbour...")
            end
        end
        self:updateDisplay()
    end
end

-- Generate hover handlers for 3-layer button pattern
for i = 1, NPCFavorManagementDialog.MAX_FAVORS do
    for _, btn in ipairs({"View", "Cancel", "Goto", "Complete"}) do
        NPCFavorManagementDialog["onFocusFavor" .. i .. btn] = function(self)
            self:applyBtnHover("favor" .. i, btn:lower(), true)
        end
        NPCFavorManagementDialog["onLeaveFavor" .. i .. btn] = function(self)
            self:applyBtnHover("favor" .. i, btn:lower(), false)
        end
    end
end

for _, btn in ipairs({"ModeToggle", "PagePrev", "PageNext", "FarmPrev", "FarmNext"}) do
    NPCFavorManagementDialog["onFocus" .. btn] = function(self)
        self:applyBtnHover("", btn:lower(), true)
    end
    NPCFavorManagementDialog["onLeave" .. btn] = function(self)
        self:applyBtnHover("", btn:lower(), false)
    end
end

--- Apply hover effect to a 3-layer button
function NPCFavorManagementDialog:applyBtnHover(rowPrefix, btnName, isHovered)
    local colorType = self.BTN_TYPE_MAP[btnName]
    if not colorType then return end
    local colors = self.BTN_COLORS[colorType]
    if not colors then return end

    local prefix = rowPrefix .. btnName

    local bgElem = self[prefix .. "bg"]
    if bgElem and bgElem.setImageColor then
        local c = isHovered and colors.BG_H or colors.BG
        bgElem:setImageColor(nil, c[1], c[2], c[3], c[4])
    end

    local txtElem = self[prefix .. "txt"]
    if txtElem and txtElem.setTextColor then
        local c = isHovered and colors.TXT_H or colors.TXT
        txtElem:setTextColor(c[1], c[2], c[3], c[4])
    end
end

function NPCFavorManagementDialog:onClickClose()
    self:close()
end

function NPCFavorManagementDialog:onClose()
    if NPCFavorManagementDialog.INSTANCE == self then
        NPCFavorManagementDialog.INSTANCE = nil
    end
    if self._watchingWork and self.npcSystem and self.npcSystem.watchPersonalWork then
        self._watchingWork = false
        self.npcSystem:watchPersonalWork(false)
    end
    NPCFavorManagementDialog:superClass().onClose(self)
end

print("[NPC Favor] NPCFavorManagementDialog loaded")
