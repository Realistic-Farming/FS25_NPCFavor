-- =========================================================
-- FS25 NPC Favor Mod - NPC Admin Edit Dialog
-- =========================================================
-- Per-NPC relationship editor with +1/+5/+10 and -1/-5/-10
-- adjustment buttons. Admin/debug tool only (npcAdmin command).
--
-- 3-layer button pattern with onFocus/onLeave hover effects.
-- Opened from NPCAdminListDialog when user clicks "Edit".
-- =========================================================

NPCAdminEditDialog = NPCAdminEditDialog or {}
local NPCAdminEditDialog_mt = Class(NPCAdminEditDialog, MessageDialog)

-- Hover color constants
NPCAdminEditDialog.COLORS = {
    INC_BG_NORMAL  = {0.12, 0.28, 0.12, 0.95},
    INC_BG_HOVER   = {0.18, 0.38, 0.18, 1},
    INC_TXT_NORMAL = {0.7, 1, 0.7, 1},
    INC_TXT_HOVER  = {0.9, 1, 0.9, 1},
    DEC_BG_NORMAL  = {0.28, 0.12, 0.12, 0.95},
    DEC_BG_HOVER   = {0.38, 0.18, 0.18, 1},
    DEC_TXT_NORMAL = {1, 0.7, 0.7, 1},
    DEC_TXT_HOVER  = {1, 0.9, 0.9, 1},
}

function NPCAdminEditDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or NPCAdminEditDialog_mt)
    self.npc = nil
    self.npcSystem = nil
    return self
end

function NPCAdminEditDialog:onCreate()
    local ok, err = pcall(function()
        NPCAdminEditDialog:superClass().onCreate(self)
    end)
    if not ok then
        print("[NPC Favor] NPCAdminEditDialog:onCreate() error: " .. tostring(err))
    end
end

function NPCAdminEditDialog:setNPCData(npc, npcSystem)
    self.npc = npc
    self.npcSystem = npcSystem
end

function NPCAdminEditDialog:onOpen()
    local ok, err = pcall(function()
        NPCAdminEditDialog:superClass().onOpen(self)
    end)
    if not ok then
        print("[NPC Favor] NPCAdminEditDialog:onOpen() error: " .. tostring(err))
        return
    end
    if self.statusText then
        self.statusText:setText("")
    end
    self:updateDisplay()
end

function NPCAdminEditDialog:updateDisplay()
    local npc = self.npc
    if not npc then return end

    -- NPC name
    if self.npcNameText then
        self.npcNameText:setText(npc.name or "Unknown")
    end

    -- Personality
    if self.npcPersonalityText then
        local personality = npc.personality or "unknown"
        self.npcPersonalityText:setText("(" .. personality .. ")")
        local pr, pg, pb = self:getPersonalityColor(personality)
        self.npcPersonalityText:setTextColor(pr, pg, pb, 1)
    end

    -- Relationship label
    if self.relLabel then
        self.relLabel:setText(g_i18n:getText("npc_admin_relationship_label") or "Relationship:")
    end

    -- Relationship value
    local relValue = npc.relationship or 0
    if self.relValueText then
        self.relValueText:setText(tostring(relValue))
        local rr, rg, rb = self:getRelColor(relValue)
        self.relValueText:setTextColor(rr, rg, rb, 1)
    end

    -- Tier name
    if self.tierNameText then
        local tierName = self:getRelationshipTierName(relValue)
        self.tierNameText:setText(tierName)
        local rr, rg, rb = self:getRelColor(relValue)
        self.tierNameText:setTextColor(rr, rg, rb, 1)
    end

    -- Section labels
    if self.incLabel then
        self.incLabel:setText(g_i18n:getText("npc_admin_increase") or "Increase Relationship")
    end
    if self.decLabel then
        self.decLabel:setText(g_i18n:getText("npc_admin_decrease") or "Decrease Relationship")
    end
end

-- =========================================================
-- Relationship Adjustment
-- =========================================================

function NPCAdminEditDialog:adjustRelationship(amount)
    if not self.npc or not self.npcSystem then return end

    local rm = self.npcSystem.relationshipManager
    if not rm then return end

    -- Re-fetch NPC to guard against despawn
    local npc = rm:getNPCById(self.npc.id)
    if not npc then
        if self.statusText then
            self.statusText:setText("NPC no longer available")
            self.statusText:setTextColor(1, 0.4, 0.4, 1)
        end
        return
    end

    local success, newValue = rm:setRelationshipDirect(npc.id, amount)
    if success then
        -- Keep our local reference in sync
        self.npc = npc

        -- Status feedback
        if self.statusText then
            local sign = amount >= 0 and "+" or ""
            local text = string.format(
                g_i18n:getText("npc_admin_adjusted") or "Adjusted: %s%d (now %d/100)",
                sign, amount, newValue
            )
            self.statusText:setText(text)
            if amount >= 0 then
                self.statusText:setTextColor(0.5, 1, 0.5, 1)
            else
                self.statusText:setTextColor(1, 0.5, 0.5, 1)
            end
        end

        self:updateDisplay()
    end
end

-- =========================================================
-- Click Handlers
-- =========================================================

function NPCAdminEditDialog:onClickInc1()   self:adjustRelationship(1)   end
function NPCAdminEditDialog:onClickInc5()   self:adjustRelationship(5)   end
function NPCAdminEditDialog:onClickInc10()  self:adjustRelationship(10)  end
function NPCAdminEditDialog:onClickDec1()   self:adjustRelationship(-1)  end
function NPCAdminEditDialog:onClickDec5()   self:adjustRelationship(-5)  end
function NPCAdminEditDialog:onClickDec10()  self:adjustRelationship(-10) end

-- =========================================================
-- Hover Effects (onFocus/onLeave from XML)
-- =========================================================

function NPCAdminEditDialog:applyIncHover(suffix, isHovered)
    local bgElem = self["btnInc" .. suffix .. "Bg"]
    local txtElem = self["btnInc" .. suffix .. "Text"]
    if bgElem then
        local c = isHovered and self.COLORS.INC_BG_HOVER or self.COLORS.INC_BG_NORMAL
        bgElem:setImageColor(nil, c[1], c[2], c[3], c[4])
    end
    if txtElem then
        local c = isHovered and self.COLORS.INC_TXT_HOVER or self.COLORS.INC_TXT_NORMAL
        txtElem:setTextColor(c[1], c[2], c[3], c[4])
    end
end

function NPCAdminEditDialog:applyDecHover(suffix, isHovered)
    local bgElem = self["btnDec" .. suffix .. "Bg"]
    local txtElem = self["btnDec" .. suffix .. "Text"]
    if bgElem then
        local c = isHovered and self.COLORS.DEC_BG_HOVER or self.COLORS.DEC_BG_NORMAL
        bgElem:setImageColor(nil, c[1], c[2], c[3], c[4])
    end
    if txtElem then
        local c = isHovered and self.COLORS.DEC_TXT_HOVER or self.COLORS.DEC_TXT_NORMAL
        txtElem:setTextColor(c[1], c[2], c[3], c[4])
    end
end

-- Per-button focus/leave handlers
function NPCAdminEditDialog:onFocusInc1()   self:applyIncHover("1", true)   end
function NPCAdminEditDialog:onLeaveInc1()   self:applyIncHover("1", false)  end
function NPCAdminEditDialog:onFocusInc5()   self:applyIncHover("5", true)   end
function NPCAdminEditDialog:onLeaveInc5()   self:applyIncHover("5", false)  end
function NPCAdminEditDialog:onFocusInc10()  self:applyIncHover("10", true)  end
function NPCAdminEditDialog:onLeaveInc10()  self:applyIncHover("10", false) end
function NPCAdminEditDialog:onFocusDec1()   self:applyDecHover("1", true)   end
function NPCAdminEditDialog:onLeaveDec1()   self:applyDecHover("1", false)  end
function NPCAdminEditDialog:onFocusDec5()   self:applyDecHover("5", true)   end
function NPCAdminEditDialog:onLeaveDec5()   self:applyDecHover("5", false)  end
function NPCAdminEditDialog:onFocusDec10()  self:applyDecHover("10", true)  end
function NPCAdminEditDialog:onLeaveDec10()  self:applyDecHover("10", false) end

-- =========================================================
-- Navigation
-- =========================================================

function NPCAdminEditDialog:onClickBack()
    self:close()
    -- Reopen the list dialog with fresh data
    if DialogLoader and DialogLoader.show then
        DialogLoader.show("NPCAdminListDialog", "setNPCSystem", self.npcSystem or g_NPCSystem)
    end
end

function NPCAdminEditDialog:onClose()
    NPCAdminEditDialog:superClass().onClose(self)
end

-- =========================================================
-- Color Helpers (matched from NPCListDialog)
-- =========================================================

function NPCAdminEditDialog:getRelColor(value)
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

function NPCAdminEditDialog:getPersonalityColor(personality)
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

function NPCAdminEditDialog:getRelationshipTierName(value)
    -- Use relationship manager if available for accurate tier lookup
    if self.npcSystem and self.npcSystem.relationshipManager then
        local level = self.npcSystem.relationshipManager:getRelationshipLevel(value)
        if level then
            -- Map tier name to i18n key
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

    -- Fallback: manual thresholds
    if value < 10 then return g_i18n:getText("npc_rel_hostile") or "Hostile"
    elseif value < 25 then return g_i18n:getText("npc_rel_unfriendly") or "Unfriendly"
    elseif value < 40 then return g_i18n:getText("npc_rel_neutral") or "Neutral"
    elseif value < 60 then return g_i18n:getText("npc_rel_acquaintance") or "Acquaintance"
    elseif value < 75 then return g_i18n:getText("npc_rel_friend") or "Friend"
    elseif value < 90 then return g_i18n:getText("npc_rel_close_friend") or "Close Friend"
    else return g_i18n:getText("npc_rel_best_friend") or "Best Friend"
    end
end

print("[NPC Favor] NPCAdminEditDialog loaded")
