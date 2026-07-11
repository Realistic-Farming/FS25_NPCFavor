-- =========================================================
-- FS25 NPC Favor Mod - Favor Management Dialog
-- =========================================================
-- Displays active favors with ability to view details, cancel,
-- navigate to NPC, and manually complete (testing).
-- Modeled after NPCListDialog for FS25 compatibility
-- =========================================================

NPCFavorManagementDialog = {}
local NPCFavorManagementDialog_mt = Class(NPCFavorManagementDialog, MessageDialog)

NPCFavorManagementDialog.MAX_FAVORS = 5  -- Max visible favors

-- 3-layer button color definitions (normal + hover states)
NPCFavorManagementDialog.BTN_COLORS = {
    blue  = { BG = {0.12,0.2,0.35,0.95}, BG_H = {0.2,0.32,0.5,1}, TXT = {0.7,0.85,1,1}, TXT_H = {0.9,0.95,1,1} },
    red   = { BG = {0.35,0.12,0.12,0.95}, BG_H = {0.45,0.18,0.18,1}, TXT = {1,0.7,0.7,1}, TXT_H = {1,0.9,0.9,1} },
    green = { BG = {0.12,0.35,0.12,0.95}, BG_H = {0.18,0.45,0.18,1}, TXT = {0.7,1,0.7,1}, TXT_H = {0.9,1,0.9,1} },
}
NPCFavorManagementDialog.BTN_TYPE_MAP = { view="blue", cancel="red", goto="blue", complete="green" }

function NPCFavorManagementDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or NPCFavorManagementDialog_mt)
    self.npcSystem = nil
    self.favorIndices = {}  -- Maps row number to favor
    return self
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
    self:updateDisplay()
end

function NPCFavorManagementDialog:updateDisplay()
    local sys = self.npcSystem
    if not sys or not sys.favorSystem then
        -- Use safe access pattern
        local titleElem = self.titleText
        if titleElem and titleElem.setText then
            titleElem:setText("Favor System Not Available")
        end
        return
    end

    -- Reset favor mapping
    self.favorIndices = {}

    -- Title
    local titleElem = self.titleText
    if titleElem and titleElem.setText then
        local activeFavors = sys.favorSystem.activeFavors or {}
        titleElem:setText(string.format("Active Favors (%d)", #activeFavors))
    end

    -- Subtitle
    local subtitleElem = self.subtitleText
    if subtitleElem and subtitleElem.setText then
        local gameTime = sys:getCurrentGameTime()
        local hour = math.floor(gameTime / 60) % 24
        local min = math.floor(gameTime) % 60
        subtitleElem:setText(string.format("Game Time: %02d:%02d  |  Manage your active favors", 
            hour, min))
    end

    -- Clear all favor rows
    for i = 1, self.MAX_FAVORS do
        self:clearFavorRow(i)
    end

    -- Fill rows from active favors
    local activeFavors = sys.favorSystem.activeFavors or {}
    for i = 1, math.min(#activeFavors, self.MAX_FAVORS) do
        self:fillFavorRow(i, activeFavors[i], sys)
    end

    -- Footer
    local footerElem = self.footerText
    if footerElem and footerElem.setText then
        local totalFavors = #activeFavors
        if totalFavors > self.MAX_FAVORS then
            footerElem:setText(string.format(
                "Showing %d of %d favors  |  Cancel reduces relationship by 10", 
                self.MAX_FAVORS, totalFavors))
        else
            footerElem:setText("Cancel favor to reduce relationship by 10  |  Complete to finish manually")
        end
    end
end

--- Clear a favor row's elements
function NPCFavorManagementDialog:clearFavorRow(rowNum)
    local prefix = "favor" .. rowNum
    
    -- Hide background and border
    local border = self[prefix .. "border"]
    if border and border.setVisible then border:setVisible(false) end
    local bg = self[prefix .. "bg"]
    if bg and bg.setVisible then bg:setVisible(false) end
    
    -- Clear and hide text fields
    local fields = {"npc", "desc", "time", "reward"}
    for _, field in ipairs(fields) do
        local elem = self[prefix .. field]
        if elem then
            if elem.setText then elem:setText("") end
            if elem.setVisible then elem:setVisible(false) end
        end
    end
    
    -- Hide 3-layer buttons (bg + hit + txt)
    local buttons = {"view", "cancel", "goto", "complete"}
    for _, btn in ipairs(buttons) do
        local elem = self[prefix .. btn]
        if elem and elem.setVisible then elem:setVisible(false) end
        local bgElem = self[prefix .. btn .. "bg"]
        if bgElem and bgElem.setVisible then bgElem:setVisible(false) end
        local txtElem = self[prefix .. btn .. "txt"]
        if txtElem and txtElem.setVisible then txtElem:setVisible(false) end
    end
end

--- Fill a favor row with data
function NPCFavorManagementDialog:fillFavorRow(rowNum, favor, sys)
    local prefix = "favor" .. rowNum
    
    -- Store favor reference
    self.favorIndices[rowNum] = favor
    
    -- Show background and border
    local border = self[prefix .. "border"]
    if border and border.setVisible then border:setVisible(true) end
    local bg = self[prefix .. "bg"]
    if bg and bg.setVisible then bg:setVisible(true) end
    
    -- Get NPC for this favor
    local npc = sys:getNPCById(favor.npcId)
    local npcName = npc and npc.name or "Unknown NPC"
    local relationship = npc and npc.relationship or 0
    
    -- NPC Name + Relationship
    local npcElem = self[prefix .. "npc"]
    if npcElem then
        if npcElem.setText then
            npcElem:setText(string.format("%s (Rel: %d)", npcName, relationship))
        end
        if npcElem.setVisible then npcElem:setVisible(true) end
        -- Color by relationship
        if npcElem.setTextColor then
            local r, g, b = self:getRelationshipColor(relationship)
            npcElem:setTextColor(r, g, b, 1)
        end
    end
    
    -- Favor Description
    local descElem = self[prefix .. "desc"]
    if descElem then
        local desc = favor.description or favor.type or "Unknown favor"
        if descElem.setText then descElem:setText(desc:sub(1, 80)) end
        if descElem.setVisible then descElem:setVisible(true) end
        if descElem.setTextColor then descElem:setTextColor(0.9, 0.9, 0.9, 1) end
    end
    
    -- Time Remaining
    local timeElem = self[prefix .. "time"]
    if timeElem then
        local timeText = self:getTimeRemainingText(favor, sys)
        if timeElem.setText then timeElem:setText(timeText) end
        if timeElem.setVisible then timeElem:setVisible(true) end
        
        -- Color based on urgency
        if timeElem.setTextColor then
            local urgency = self:getTimeUrgency(favor, sys)
            if urgency > 0.7 then
                timeElem:setTextColor(0.9, 0.3, 0.3, 1)  -- Red - urgent
            elseif urgency > 0.4 then
                timeElem:setTextColor(0.9, 0.7, 0.3, 1)  -- Yellow - moderate
            else
                timeElem:setTextColor(0.5, 0.85, 0.5, 1)  -- Green - plenty of time
            end
        end
    end
    
    -- Reward
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
        if rewardElem.setText then rewardElem:setText(string.format("Reward: $%d", reward)) end
        if rewardElem.setVisible then rewardElem:setVisible(true) end
        if rewardElem.setTextColor then rewardElem:setTextColor(0.3, 0.9, 0.3, 1) end
    end
    
    -- Show 3-layer buttons (bg + hit + txt)
    local buttons = {"view", "cancel", "goto", "complete"}
    for _, btn in ipairs(buttons) do
        local elem = self[prefix .. btn]
        if elem and elem.setVisible then elem:setVisible(true) end
        local bgElem = self[prefix .. btn .. "bg"]
        if bgElem and bgElem.setVisible then bgElem:setVisible(true) end
        local txtElem = self[prefix .. btn .. "txt"]
        if txtElem and txtElem.setVisible then txtElem:setVisible(true) end
    end
end

--- Get time remaining text for a favor
function NPCFavorManagementDialog:getTimeRemainingText(favor, sys)
    if not favor.expiryTime then
        return "No time limit"
    end
    
    local currentTime = sys:getCurrentGameTime()
    local remaining = favor.expiryTime - currentTime
    
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
    if not favor.expiryTime or not favor.startTime then
        return 0
    end
    
    local currentTime = sys:getCurrentGameTime()
    local elapsed = currentTime - favor.startTime
    local total = favor.expiryTime - favor.startTime
    
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

-- Generate onClick handlers for View, Cancel, Goto, Complete for each favor
for i = 1, NPCFavorManagementDialog.MAX_FAVORS do
    -- View Details
    NPCFavorManagementDialog["onClickFavor" .. i .. "View"] = function(self)
        local favor = self.favorIndices[i]
        if not favor then return end
        
        local npc = self.npcSystem:getNPCById(favor.npcId)
        local npcName = npc and npc.name or "Unknown"
        
        local reward = 0
        if favor.reward then
            if type(favor.reward) == "table" then
                reward = favor.reward.amount or favor.reward.money or 0
            else
                reward = favor.reward
            end
        end
        
        local details = string.format(
            "=== Favor Details ===\nNPC: %s\nType: %s\nDescription: %s\nReward: $%d\nStatus: %s\n",
            npcName,
            favor.type or "Unknown",
            favor.description or "No description",
            reward,
            favor.status or "active"
        )
        
        print("[NPC Favor] " .. details)
    end
    
    -- Cancel Favor
    NPCFavorManagementDialog["onClickFavor" .. i .. "Cancel"] = function(self)
        local favor = self.favorIndices[i]
        if not favor or not self.npcSystem or not self.npcSystem.favorSystem then return end
        
        local npc = self.npcSystem:getNPCById(favor.npcId)
        local npcName = npc and npc.name or "Unknown"
        
        -- Cancel the favor
        self.npcSystem.favorSystem:abandonFavor(favor.id)
        
        -- Reduce relationship - FIXED METHOD NAME
        if npc and self.npcSystem.relationshipManager then
            self.npcSystem.relationshipManager:updateRelationship(npc.id, -10, "favor_cancelled")
        end
        
        -- Refresh display
        self:updateDisplay()
        
        print(string.format("[NPC Favor] Canceled favor from %s", npcName))
    end
    
    -- Go To NPC
    NPCFavorManagementDialog["onClickFavor" .. i .. "Goto"] = function(self)
        local favor = self.favorIndices[i]
        if not favor then return end
        
        local npc = self.npcSystem:getNPCById(favor.npcId)
        if not npc or not npc.position then
            print("[NPC Favor] Cannot teleport - NPC not found")
            return
        end
        
        -- Close dialog first
        self:close()

        -- Smart teleport: context-aware positioning (Issue #6)
        local success, message = NPCTeleport.teleportToNPC(self.npcSystem, npc)
        print("[NPC Favor] " .. (message or "Teleport attempted"))
    end
    
    -- Complete Favor (manual/testing)
    NPCFavorManagementDialog["onClickFavor" .. i .. "Complete"] = function(self)
        local favor = self.favorIndices[i]
        if not favor or not self.npcSystem or not self.npcSystem.favorSystem then return end
        
        local npc = self.npcSystem:getNPCById(favor.npcId)
        local npcName = npc and npc.name or "Unknown"

        -- Server-authoritative completion: send intent through NPCInteractionEvent so the
        -- server completes the NPC's active favor and pays favor.ownerFarmId exactly once.
        -- The old inline addMoney here double-paid the reward (completeFavor already pays
        -- it via applyFavorRewards) and the extra +15 relationship over-rewarded; both
        -- are removed. On host/single-player the send executes directly.
        if npc then
            local farmId = (g_currentMission and g_currentMission.player and g_currentMission.player.farmId) or 0
            NPCInteractionEvent.sendToServer(NPCInteractionEvent.ACTION_FAVOR_COMPLETE, npc.id, farmId, 0, "")
        end

        -- Refresh display
        self:updateDisplay()

        print(string.format("[NPC Favor] Requested server-authoritative completion of favor from %s", npcName))
    end
end

-- Generate hover handlers for 3-layer button pattern
for i = 1, NPCFavorManagementDialog.MAX_FAVORS do
    for _, btn in ipairs({"View", "Cancel", "Goto", "Complete"}) do
        NPCFavorManagementDialog["onFocusFavor" .. i .. btn] = function(self)
            self:applyBtnHover(i, btn:lower(), true)
        end
        NPCFavorManagementDialog["onLeaveFavor" .. i .. btn] = function(self)
            self:applyBtnHover(i, btn:lower(), false)
        end
    end
end

--- Apply hover effect to a 3-layer button
function NPCFavorManagementDialog:applyBtnHover(rowNum, btnName, isHovered)
    local colorType = self.BTN_TYPE_MAP[btnName]
    if not colorType then return end
    local colors = self.BTN_COLORS[colorType]
    if not colors then return end

    local prefix = "favor" .. rowNum .. btnName

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
    NPCFavorManagementDialog:superClass().onClose(self)
end

print("[NPC Favor] NPCFavorManagementDialog loaded")
