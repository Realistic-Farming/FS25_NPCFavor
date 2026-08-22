-- =========================================================
-- FS25 NPC Favor Mod - NPC Admin List Dialog
-- =========================================================
-- Condensed NPC roster with per-row "Edit" buttons that open
-- NPCAdminEditDialog for relationship adjustment.
-- Admin/debug tool only (npcAdmin console command).
--
-- Columns: #, Name, Personality, Rel, Tier, [Edit]
-- 12 data rows with 3-layer Edit buttons and hover effects.
-- =========================================================

NPCAdminListDialog = NPCAdminListDialog or {}
local NPCAdminListDialog_mt = Class(NPCAdminListDialog, MessageDialog)

NPCAdminListDialog.MAX_ROWS = 12

-- Column suffixes matching XML id pattern: r{N}{suffix}
NPCAdminListDialog.COLUMNS = {"num", "name", "pers", "rel", "tier"}

-- Edit button hover colors
NPCAdminListDialog.EDIT_COLORS = {
    BG_NORMAL  = {0.12, 0.2, 0.35, 0.95},
    BG_HOVER   = {0.2, 0.32, 0.5, 1},
    TXT_NORMAL = {0.7, 0.85, 1, 1},
    TXT_HOVER  = {0.9, 0.95, 1, 1},
}

function NPCAdminListDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or NPCAdminListDialog_mt)
    self.npcSystem = nil
    self.rowNPCIndex = {}  -- rowNum -> activeNPCs index
    return self
end

function NPCAdminListDialog:onCreate()
    local ok, err = pcall(function()
        NPCAdminListDialog:superClass().onCreate(self)
    end)
    if not ok then
        print("[NPC Favor] NPCAdminListDialog:onCreate() error: " .. tostring(err))
    end
end

function NPCAdminListDialog:setNPCSystem(npcSystem)
    self.npcSystem = npcSystem
end

function NPCAdminListDialog:onOpen()
    local ok, err = pcall(function()
        NPCAdminListDialog:superClass().onOpen(self)
    end)
    if not ok then
        print("[NPC Favor] NPCAdminListDialog:onOpen() error: " .. tostring(err))
        return
    end
    self:updateDisplay()
end

function NPCAdminListDialog:updateDisplay()
    local sys = self.npcSystem
    if not sys then
        if self.titleText then self.titleText:setText("NPC System Not Available") end
        return
    end

    -- Reset row->NPC mapping
    self.rowNPCIndex = {}

    -- Title
    if self.titleText then
        self.titleText:setText(g_i18n:getText("npc_admin_title") or "NPC Admin Panel")
    end

    -- Clear all rows first
    for i = 1, self.MAX_ROWS do
        self:clearRow(i)
    end

    -- Count active NPCs and fill rows
    local rowIdx = 0
    if sys.activeNPCs then
        for i, npc in ipairs(sys.activeNPCs) do
            if npc.isActive and rowIdx < self.MAX_ROWS then
                rowIdx = rowIdx + 1
                self:fillRow(rowIdx, i, npc, sys)
            end
        end
    end

    -- Subtitle
    if self.subtitleText then
        if rowIdx > 0 then
            self.subtitleText:setText(string.format(
                g_i18n:getText("npc_admin_subtitle_fmt") or "%d active NPCs  |  Click Edit to adjust relationship",
                rowIdx
            ))
        else
            self.subtitleText:setText(g_i18n:getText("npc_admin_no_npcs") or "No active NPCs. NPCs will appear after initialization.")
        end
    end

    -- Footer
    if self.footerText then
        self.footerText:setText(g_i18n:getText("npc_admin_footer") or "Click Edit to adjust NPC relationship values")
    end

    -- Bottom divider visibility
    if self.bottomDivider then
        self.bottomDivider:setVisible(rowIdx > 0)
    end
end

--- Clear a row's cells, hide its background and Edit button layers.
function NPCAdminListDialog:clearRow(rowNum)
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
    -- 3-layer Edit button
    local editbg = self[prefix .. "editbg"]
    if editbg then editbg:setVisible(false) end
    local edittxt = self[prefix .. "edittxt"]
    if edittxt then edittxt:setVisible(false) end
    local editBtn = self[prefix .. "edit"]
    if editBtn then editBtn:setVisible(false) end
end

--- Fill a row with NPC data and color-code the cells.
function NPCAdminListDialog:fillRow(rowNum, npcIndex, npc, sys)
    local prefix = "r" .. rowNum

    -- Store NPC index for edit navigation
    self.rowNPCIndex[rowNum] = npcIndex

    -- Show background
    local bg = self[prefix .. "bg"]
    if bg then bg:setVisible(true) end

    -- Show 3-layer Edit button
    local editbg = self[prefix .. "editbg"]
    if editbg then editbg:setVisible(true) end
    local edittxt = self[prefix .. "edittxt"]
    if edittxt then
        edittxt:setVisible(true)
        edittxt:setText(g_i18n:getText("npc_admin_edit") or "Edit")
    end
    local editBtn = self[prefix .. "edit"]
    if editBtn then editBtn:setVisible(true) end

    -- # column
    local numElem = self[prefix .. "num"]
    if numElem then
        numElem:setText(tostring(npcIndex))
        numElem:setVisible(true)
    end

    -- Name column (personality-colored)
    local nameElem = self[prefix .. "name"]
    if nameElem then
        nameElem:setText((npc.name or "Unknown"):sub(1, 18))
        nameElem:setVisible(true)
        local pr, pg, pb = self:getPersonalityColor(npc.personality)
        nameElem:setTextColor(pr, pg, pb, 1)
    end

    -- Personality column
    local persElem = self[prefix .. "pers"]
    if persElem then
        persElem:setText(npc.personality or "unknown")
        persElem:setVisible(true)
        local pr, pg, pb = self:getPersonalityColor(npc.personality)
        persElem:setTextColor(pr, pg, pb, 0.8)
    end

    -- Relationship column (color coded)
    local relElem = self[prefix .. "rel"]
    if relElem then
        local rel = npc.relationship or 0
        relElem:setText(tostring(rel))
        relElem:setVisible(true)
        local rr, rg, rb = self:getRelColor(rel)
        relElem:setTextColor(rr, rg, rb, 1)
    end

    -- Tier column (color coded)
    local tierElem = self[prefix .. "tier"]
    if tierElem then
        local rel = npc.relationship or 0
        tierElem:setText(self:getRelationshipTierName(rel))
        tierElem:setVisible(true)
        local rr, rg, rb = self:getRelColor(rel)
        tierElem:setTextColor(rr, rg, rb, 1)
    end
end

-- =========================================================
-- Edit Navigation
-- =========================================================

--- Open the edit dialog for a specific row's NPC.
function NPCAdminListDialog:editNPC(rowNum)
    local npcIndex = self.rowNPCIndex[rowNum]
    if not npcIndex then return end

    local sys = self.npcSystem or g_NPCSystem
    if not sys or not sys.activeNPCs then return end

    local npc = sys.activeNPCs[npcIndex]
    if not npc then return end

    -- Close list first, then open edit dialog
    self:close()

    if DialogLoader and DialogLoader.show then
        -- Set NPC data before showing
        local editDialog = DialogLoader.getDialog("NPCAdminEditDialog")
        if editDialog then
            editDialog:setNPCData(npc, sys)
        end
        DialogLoader.show("NPCAdminEditDialog")
    end
end

-- Generate click handlers for all 12 rows dynamically
for i = 1, NPCAdminListDialog.MAX_ROWS do
    NPCAdminListDialog["onClickEdit" .. i] = function(self)
        self:editNPC(i)
    end
end

-- =========================================================
-- Hover Effects for Edit Buttons
-- =========================================================

function NPCAdminListDialog:applyEditHover(rowNum, isHovered)
    local prefix = "r" .. rowNum
    local bgElem = self[prefix .. "editbg"]
    local txtElem = self[prefix .. "edittxt"]
    if bgElem then
        local c = isHovered and self.EDIT_COLORS.BG_HOVER or self.EDIT_COLORS.BG_NORMAL
        bgElem:setImageColor(nil, c[1], c[2], c[3], c[4])
    end
    if txtElem then
        local c = isHovered and self.EDIT_COLORS.TXT_HOVER or self.EDIT_COLORS.TXT_NORMAL
        txtElem:setTextColor(c[1], c[2], c[3], c[4])
    end
end

-- Generate hover handlers for all 12 rows dynamically
for i = 1, NPCAdminListDialog.MAX_ROWS do
    NPCAdminListDialog["onEditFocus" .. i] = function(self)
        self:applyEditHover(i, true)
    end
    NPCAdminListDialog["onEditLeave" .. i] = function(self)
        self:applyEditHover(i, false)
    end
end

-- =========================================================
-- Color Helpers (matched from NPCListDialog)
-- =========================================================

function NPCAdminListDialog:getRelColor(value)
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

function NPCAdminListDialog:getPersonalityColor(personality)
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

function NPCAdminListDialog:getRelationshipTierName(value)
    if self.npcSystem and self.npcSystem.relationshipManager then
        local level = self.npcSystem.relationshipManager:getRelationshipLevel(value)
        if level then
            local nameMap = {
                ["Hostile"] = "npc_rel_hostile",
                ["Unfriendly"] = "npc_rel_unfriendly",
                ["Neutral"] = "npc_rel_neutral",
                ["Acquaintance"] = "npc_rel_acquaintance",
                ["Friend"] = "npc_rel_friend",
                ["Close Friend"] = "npc_rel_close_friend",
                ["Best Friend"] = "npc_rel_best_friend",
            }
            local key = nameMap[level.name]
            if key then
                return g_i18n:getText(key) or level.name
            end
            return level.name
        end
    end
    -- Fallback
    if value < 10 then return g_i18n:getText("npc_rel_hostile") or "Hostile"
    elseif value < 25 then return g_i18n:getText("npc_rel_unfriendly") or "Unfriendly"
    elseif value < 40 then return g_i18n:getText("npc_rel_neutral") or "Neutral"
    elseif value < 60 then return g_i18n:getText("npc_rel_acquaintance") or "Acquaintance"
    elseif value < 75 then return g_i18n:getText("npc_rel_friend") or "Friend"
    elseif value < 90 then return g_i18n:getText("npc_rel_close_friend") or "Close Friend"
    else return g_i18n:getText("npc_rel_best_friend") or "Best Friend"
    end
end

-- =========================================================
-- Close / Cleanup
-- =========================================================

function NPCAdminListDialog:onClickClose()
    self:close()
end

function NPCAdminListDialog:onClose()
    NPCAdminListDialog:superClass().onClose(self)
end

print("[NPC Favor] NPCAdminListDialog loaded")
