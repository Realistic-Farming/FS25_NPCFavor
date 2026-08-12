-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- RELATIONSHIP TIERS:
-- [x] Five-tier relationship system (stranger to best_friend)
-- [x] Color-coded relationship levels for UI display
-- [x] Per-tier benefits (discounts, favor access, equipment borrowing)
-- [ ] Seasonal relationship events (holidays, harvest festivals)
-- [ ] Rival NPC relationships (befriending one may upset another)
--
-- MOOD & DECAY:
-- [x] Temporary mood system with expiration timers
-- [x] Mood modifiers affecting relationship change magnitude
-- [x] Automatic cleanup of expired moods and old history
-- [x] Passive relationship decay over time for inactive NPCs
-- [ ] Weather/season influence on NPC mood baseline
-- [x] NPC memory of past slights with grudge mechanic
--
-- GIFTS & BENEFITS:
-- [x] Gift system with per-day limits and personality modifiers
-- [x] Trade discounts scaling with relationship tier
-- [x] Equipment borrowing unlocked at friend tier
-- [x] NPC-initiated gift giving at best_friend tier
-- [ ] Shared resource pools between best friends
-- [ ] Unlock exclusive items/vehicles through max relationship
-- =========================================================

-- =========================================================
-- FS25 NPC Favor Mod - Relationship Manager
-- =========================================================
-- Manages relationships between player and NPCs
-- =========================================================

NPCRelationshipManager = {}
NPCRelationshipManager_mt = Class(NPCRelationshipManager)

function NPCRelationshipManager.new(npcSystem)
    local self = setmetatable({}, NPCRelationshipManager_mt)
    
    self.npcSystem = npcSystem
    
    -- 7-tier relationship levels (aligned with NPCDialog:getRelationshipLevelName)
    -- NPCs start at 0 (hostile/stranger) and must earn trust through interaction.
    self.RELATIONSHIP_LEVELS = {
        {
            min = 0,   max = 9,
            name = "Hostile",
            color = {r = 0.8, g = 0.2, b = 0.2},
            benefits = {
                canAskFavor = false,
                favorFrequency = 0,
                giftEffectiveness = 0.3,
                discount = 0,
                helpChance = 0
            }
        },
        {
            min = 10,  max = 24,
            name = "Unfriendly",
            color = {r = 1.0, g = 0.3, b = 0.3},
            benefits = {
                canAskFavor = false,
                favorFrequency = 0.1,
                giftEffectiveness = 0.5,
                discount = 0,
                helpChance = 0
            }
        },
        {
            min = 25,  max = 39,
            name = "Neutral",
            color = {r = 1.0, g = 0.6, b = 0.3},
            benefits = {
                canAskFavor = true,
                favorFrequency = 0.3,
                giftEffectiveness = 0.7,
                discount = 5,
                helpChance = 5
            }
        },
        {
            min = 40,  max = 59,
            name = "Acquaintance",
            color = {r = 0.8, g = 0.8, b = 0.3},
            benefits = {
                canAskFavor = true,
                favorFrequency = 0.5,
                giftEffectiveness = 0.8,
                discount = 10,
                helpChance = 15,
                canBorrowEquipment = true
            }
        },
        {
            min = 60,  max = 74,
            name = "Friend",
            color = {r = 0.5, g = 0.8, b = 0.3},
            benefits = {
                canAskFavor = true,
                favorFrequency = 0.7,
                giftEffectiveness = 0.9,
                discount = 15,
                helpChance = 35,
                canBorrowEquipment = true,
                mayOfferHelp = true
            }
        },
        {
            min = 75,  max = 89,
            name = "Close Friend",
            color = {r = 0.3, g = 0.85, b = 0.3},
            benefits = {
                canAskFavor = true,
                favorFrequency = 0.85,
                giftEffectiveness = 1.0,
                discount = 18,
                helpChance = 55,
                canBorrowEquipment = true,
                mayOfferHelp = true,
                mayGiveGifts = true
            }
        },
        {
            min = 90,  max = 100,
            name = "Best Friend",
            color = {r = 0.3, g = 0.6, b = 1.0},
            benefits = {
                canAskFavor = true,
                favorFrequency = 1.0,
                giftEffectiveness = 1.2,
                discount = 20,
                helpChance = 75,
                canBorrowEquipment = true,
                mayOfferHelp = true,
                mayGiveGifts = true,
                sharedResources = true
            }
        }
    }
    
    -- Relationship change reasons with detailed effects
    self.CHANGE_REASONS = {
        FAVOR_COMPLETED = {
            value = 15, 
            description = "Completed a favor",
            moodEffect = "positive",
            duration = "permanent"
        },
        FAVOR_FAILED = {
            value = -10, 
            description = "Failed a favor",
            moodEffect = "negative",
            duration = "temporary",
            decayTime = 24 * 60 * 60 * 1000 -- 24 hours
        },
        FAVOR_ABANDONED = {
            value = -5, 
            description = "Abandoned a favor",
            moodEffect = "negative",
            duration = "temporary",
            decayTime = 12 * 60 * 60 * 1000 -- 12 hours
        },
        GIFT_GIVEN = {
            value = 5, 
            description = "Gave a gift",
            moodEffect = "positive",
            duration = "permanent",
            maxPerDay = 3
        },
        HELPED_WORK = {
            value = 8, 
            description = "Helped with work",
            moodEffect = "positive",
            duration = "permanent"
        },
        IGNORED_REQUEST = {
            value = -5, 
            description = "Ignored request",
            moodEffect = "negative",
            duration = "temporary",
            decayTime = 6 * 60 * 60 * 1000 -- 6 hours
        },
        ARGUMENT = {
            value = -15, 
            description = "Had an argument",
            moodEffect = "negative",
            duration = "temporary",
            decayTime = 48 * 60 * 60 * 1000 -- 48 hours
        },
        DAILY_INTERACTION = {
            value = 1, 
            description = "Daily interaction",
            moodEffect = "neutral",
            duration = "daily",
            maxPerDay = 1
        },
        TRADE_COMPLETED = {
            value = 3, 
            description = "Completed a trade",
            moodEffect = "positive",
            duration = "permanent"
        },
        EMERGENCY_HELP = {
            value = 25, 
            description = "Helped in emergency",
            moodEffect = "very_positive",
            duration = "permanent"
        }
    }
    
    -- Relationship history storage with decay system
    self.relationshipHistory = {} -- npcId -> array of changes
    self.dailyInteractionTracker = {} -- Tracks daily interactions per NPC
    self.giftTracker = {} -- Tracks gifts given per NPC per day
    
    -- Mood system for temporary relationship modifiers
    self.npcMoods = {} -- npcId -> {mood, modifier, expiration}

    -- 4l: Grudge system — persistent negative feelings from bad interactions
    -- npcId -> {count, lastSlightTime, severity}
    self.grudges = {}

    -- NPC-NPC relationship graph: keyed by canonical id pair "id1:id2" (lower id first)
    self.npcRelationships = {}

    -- Personality compatibility matrix: how much personalities drift toward liking/disliking
    -- Positive = compatible (drift toward friendship), Negative = incompatible (drift toward rivalry)
    self.personalityCompatibility = {
        hardworking = { hardworking = 0.2, lazy = -0.5, social = 0.1, grumpy = 0.1, generous = 0.3 },
        lazy        = { hardworking = -0.5, lazy = 0.3, social = 0.2, grumpy = 0.0, generous = 0.1 },
        social      = { hardworking = 0.1, lazy = 0.2, social = 0.5, grumpy = -0.3, generous = 0.3 },
        grumpy      = { hardworking = 0.1, lazy = 0.0, social = -0.3, grumpy = -0.2, generous = -0.1 },
        generous    = { hardworking = 0.3, lazy = 0.1, social = 0.3, grumpy = -0.1, generous = 0.4 },
    }

    return self
end

--- Get canonical key for an NPC-NPC relationship pair (lower id first).
-- @param id1  First NPC id
-- @param id2  Second NPC id
-- @return string  Canonical key "id1:id2"
function NPCRelationshipManager:getNPCPairKey(id1, id2)
    if id1 < id2 then
        return id1 .. ":" .. id2
    else
        return id2 .. ":" .. id1
    end
end

--- Get or create an NPC-NPC relationship record.
-- @param id1  First NPC id
-- @param id2  Second NPC id
-- @return table  {value, lastInteraction, interactionCount}
function NPCRelationshipManager:getNPCRelationship(id1, id2)
    local key = self:getNPCPairKey(id1, id2)
    if not self.npcRelationships[key] then
        self.npcRelationships[key] = {
            value = 50,              -- neutral start
            lastInteraction = 0,
            interactionCount = 0,
        }
    end
    return self.npcRelationships[key]
end

--- Update NPC-NPC relationship when they interact (socialize, gather, work together).
-- Applies personality compatibility drift.
-- @param npc1  First NPC data table
-- @param npc2  Second NPC data table
-- @param interactionType  "socialize", "work", "gather"
function NPCRelationshipManager:updateNPCNPCRelationship(npc1, npc2, interactionType)
    if not npc1 or not npc2 then return end
    local rel = self:getNPCRelationship(npc1.id, npc2.id)

    -- Base change from interaction
    local change = 1
    if interactionType == "work" then
        change = 2
    elseif interactionType == "gather" then
        change = 1.5
    end

    -- Apply personality compatibility drift
    local p1 = npc1.personality or "generous"
    local p2 = npc2.personality or "generous"
    local compat = 0
    if self.personalityCompatibility[p1] then
        compat = self.personalityCompatibility[p1][p2] or 0
    end
    change = change + compat

    -- Apply change (bounded 0-100)
    rel.value = math.max(0, math.min(100, rel.value + change))
    rel.lastInteraction = self.npcSystem:getCurrentGameTime()
    rel.interactionCount = rel.interactionCount + 1
end

--- Get the NPC-NPC relationship value for sorting social partners.
-- @param id1  First NPC id
-- @param id2  Second NPC id
-- @return number  Relationship value (0-100, 50 = neutral)
function NPCRelationshipManager:getNPCNPCValue(id1, id2)
    local key = self:getNPCPairKey(id1, id2)
    local rel = self.npcRelationships[key]
    return rel and rel.value or 50
end

function NPCRelationshipManager:updateRelationship(npcId, change, reason)
    local npc = self:getNPCById(npcId)
    if not npc then
        return false
    end
    
    -- Check daily limits
    if not self:canApplyRelationshipChange(npcId, reason, change) then
        if self.npcSystem.settings.debugMode then
            print(string.format("Relationship change blocked for %s: %s (daily limit reached)", 
                npc.name, reason))
        end
        return false
    end
    
    -- Store old value
    local oldValue = npc.relationship or 0
    local oldLevel = self:getRelationshipLevel(oldValue)
    
    -- Apply mood modifier if any
    local moodModifier = self:getMoodModifier(npcId)
    local effectiveChange = change
    if moodModifier ~= 0 then
        effectiveChange = math.floor(change * (1 + moodModifier))
        if self.npcSystem.settings.debugMode then
            print(string.format("Mood modifier applied: %+.0f%%", moodModifier * 100))
        end
    end
    
    -- Apply change with bounds
    local newValue = oldValue + effectiveChange
    newValue = math.max(0, math.min(100, newValue))
    
    npc.relationship = newValue

    -- [SF-10] NPC TREATMENT (B3): a relationship change moves the work-ethic
    -- OFFSET (helping raises diligence, damage lowers it), never the base
    -- workEthic. Bounded and symmetric.
    if NPCTreatment and NPCTreatment.adjustOffset then
        pcall(NPCTreatment.adjustOffset, NPCTreatment, npc, effectiveChange)
    end
    
    -- Store in history with full details
    local historyEntry = {
        time = g_currentMission.time,
        oldValue = oldValue,
        newValue = newValue,
        change = effectiveChange,
        baseChange = change,
        reason = reason or "unknown",
        moodModifier = moodModifier,
        location = {
            x = npc.position.x,
            y = npc.position.y,
            z = npc.position.z
        }
    }
    
    self:addRelationshipHistory(npcId, historyEntry)

    -- Show floating relationship change text (+1, -2, etc.)
    if self.npcSystem.interactionUI and self.npcSystem.interactionUI.addFloatingText then
        local text = string.format("%+d", effectiveChange)
        local r, g, b = 0.3, 1, 0.3  -- green for positive
        if effectiveChange < 0 then
            r, g, b = 1, 0.3, 0.3    -- red for negative
        end
        self.npcSystem.interactionUI:addFloatingText(
            npc.position.x, npc.position.y + 2.5, npc.position.z,
            text, r, g, b
        )
    end

    -- 4l: Track grudges from negative interactions
    if effectiveChange < 0 then
        local grudge = self.grudges[npcId]
        if not grudge then
            grudge = {count = 0, lastSlightTime = 0, severity = 0}
            self.grudges[npcId] = grudge
        end
        grudge.count = grudge.count + 1
        grudge.lastSlightTime = g_currentMission.time
        grudge.severity = math.min(5, grudge.severity + math.abs(effectiveChange) * 0.1)
    elseif effectiveChange > 0 and self.grudges[npcId] then
        -- Positive interactions slowly reduce grudge severity
        local grudge = self.grudges[npcId]
        grudge.severity = math.max(0, grudge.severity - 0.1)
        if grudge.severity <= 0 then
            self.grudges[npcId] = nil  -- Grudge fully forgiven
        end
    end

    -- Update daily trackers
    self:updateDailyTrackers(npcId, reason)

    -- Update mood based on change
    self:updateNPCMood(npcId, effectiveChange, reason)
    
    -- Check if level changed
    local newLevel = self:getRelationshipLevel(npc.relationship)
    if oldLevel.name ~= newLevel.name then
        self:onRelationshipLevelChange(npc, oldLevel, newLevel, historyEntry)
    end
    
    -- Debug output
    if self.npcSystem.settings.debugMode then
        print(string.format("Relationship update: %s %+d = %d (%s -> %s) [Reason: %s]", 
            npc.name, effectiveChange, npc.relationship, oldLevel.name, newLevel.name, reason))
    end
    
    -- Update NPC behavior based on new relationship
    self:updateNPCBehaviorForRelationship(npc, newLevel)
    
    return true
end

--- Admin-only: directly set relationship value, bypassing daily limits, mood, and grudges.
-- Preserves: bounds clamping (0-100), history, level-change detection, behavior updates.
-- @param npcId   NPC identifier
-- @param delta   Amount to add (positive or negative)
-- @return boolean success, number newValue
function NPCRelationshipManager:setRelationshipDirect(npcId, delta)
    local npc = self:getNPCById(npcId)
    if not npc then
        return false, 0
    end

    local oldValue = npc.relationship or 0
    local oldLevel = self:getRelationshipLevel(oldValue)

    -- Apply change with bounds clamping
    local newValue = math.max(0, math.min(100, oldValue + delta))
    npc.relationship = newValue

    -- Record in history
    local historyEntry = {
        time = g_currentMission.time,
        oldValue = oldValue,
        newValue = newValue,
        change = newValue - oldValue,
        baseChange = delta,
        reason = "admin_adjust",
        moodModifier = 0,
        location = {
            x = npc.position.x,
            y = npc.position.y,
            z = npc.position.z
        }
    }
    self:addRelationshipHistory(npcId, historyEntry)

    -- Check for level change
    local newLevel = self:getRelationshipLevel(newValue)
    if oldLevel.name ~= newLevel.name then
        self:onRelationshipLevelChange(npc, oldLevel, newLevel, historyEntry)
    end

    -- Update NPC behavior
    self:updateNPCBehaviorForRelationship(npc, newLevel)

    if self.npcSystem.settings.debugMode then
        print(string.format("[NPC Favor] Admin adjust: %s %+d = %d (%s -> %s)",
            npc.name, delta, newValue, oldLevel.name, newLevel.name))
    end

    return true, newValue
end

function NPCRelationshipManager:canApplyRelationshipChange(npcId, reason, change)
    local currentTime = g_currentMission.time
    local day = math.floor(currentTime / (24 * 60 * 60 * 1000))
    
    -- Initialize trackers for this NPC if needed
    if not self.dailyInteractionTracker[npcId] then
        self.dailyInteractionTracker[npcId] = {day = day, count = 0}
    end
    
    if not self.giftTracker[npcId] then
        self.giftTracker[npcId] = {day = day, count = 0}
    end
    
    -- Check if day has changed
    if self.dailyInteractionTracker[npcId].day ~= day then
        self.dailyInteractionTracker[npcId] = {day = day, count = 0}
    end
    
    if self.giftTracker[npcId].day ~= day then
        self.giftTracker[npcId] = {day = day, count = 0}
    end
    
    -- Check specific limits (reason strings are lowercase to match callers)
    if reason == "daily_interaction" then
        if self.dailyInteractionTracker[npcId].count >= 1 then
            return false
        end
        self.dailyInteractionTracker[npcId].count = self.dailyInteractionTracker[npcId].count + 1
        
    elseif reason == "gift_given" then
        local reasonData = self.CHANGE_REASONS.GIFT_GIVEN
        if self.giftTracker[npcId].count >= (reasonData.maxPerDay or 3) then
            return false
        end
        self.giftTracker[npcId].count = self.giftTracker[npcId].count + 1
    end
    
    return true
end

function NPCRelationshipManager:updateDailyTrackers(npcId, reason)
    -- This is called after the change is applied to update trackers
    -- Specific tracking is handled in canApplyRelationshipChange
end

function NPCRelationshipManager:getMoodModifier(npcId)
    if not self.npcMoods[npcId] then
        return 0
    end
    
    local mood = self.npcMoods[npcId]
    
    -- Check if mood has expired
    if mood.expiration and g_currentMission.time > mood.expiration then
        self.npcMoods[npcId] = nil
        return 0
    end
    
    local modifier = mood.modifier or 0

    -- 4l: Grudge penalty reduces positive relationship gains
    local grudge = self.grudges and self.grudges[npcId]
    if grudge and grudge.severity > 0 then
        modifier = modifier - grudge.severity * 0.1  -- up to -50% at max severity
    end

    return modifier
end

function NPCRelationshipManager:updateNPCMood(npcId, change, reason)
    local moodChange = 0
    change = change or 0

    -- Determine mood change based on relationship change
    if change > 0 then
        moodChange = 0.1 * (change / 10) -- Positive mood for positive changes
    elseif change < 0 then
        moodChange = -0.2 * (math.abs(change) / 10) -- Stronger negative mood for negative changes
    end
    
    -- Initialize mood if needed
    if not self.npcMoods[npcId] then
        self.npcMoods[npcId] = {
            value = 0,
            modifier = 0,
            expiration = nil
        }
    end
    
    -- Update mood value (-1 to 1 range)
    local mood = self.npcMoods[npcId]
    mood.value = math.max(-1, math.min(1, mood.value + moodChange))
    
    -- Calculate modifier from mood value
    mood.modifier = mood.value * 0.5 -- Mood affects relationship changes by +/- 50%
    
    -- Set expiration for temporary moods
    if moodChange ~= 0 then
        local decayTime = 2 * 60 * 60 * 1000 -- 2 hours decay time
        mood.expiration = g_currentMission.time + decayTime
    end
    
    -- Debug output
    if self.npcSystem.settings.debugMode and moodChange ~= 0 then
        local npc = self:getNPCById(npcId)
        if npc then
            print(string.format("NPC %s mood: %.2f -> %.2f (modifier: %+.0f%%)", 
                npc.name, mood.value - moodChange, mood.value, mood.modifier * 100))
        end
    end
end

function NPCRelationshipManager:getNPCById(npcId)
    for _, npc in ipairs(self.npcSystem.activeNPCs) do
        if npc.id == npcId then
            return npc
        end
    end
    return nil
end

function NPCRelationshipManager:getRelationshipLevel(value)
    for _, level in ipairs(self.RELATIONSHIP_LEVELS) do
        if value >= level.min and value <= level.max then
            return level
        end
    end
    
    -- Fallback
    return self.RELATIONSHIP_LEVELS[1]
end

function NPCRelationshipManager:addRelationshipHistory(npcId, change)
    if not self.relationshipHistory[npcId] then
        self.relationshipHistory[npcId] = {}
    end
    
    table.insert(self.relationshipHistory[npcId], change)
    
    -- Keep only last 100 entries
    if #self.relationshipHistory[npcId] > 100 then
        table.remove(self.relationshipHistory[npcId], 1)
    end
end

function NPCRelationshipManager:onRelationshipLevelChange(npc, oldLevel, newLevel, historyEntry)
    -- Show notification
    if self.npcSystem.settings.showNotifications then
        local message = ""
        local title = "Relationship Changed"
        
        if newLevel.min > oldLevel.min then
            -- Relationship improved
            title = "Relationship Improved!"
            message = string.format("Your relationship with %s has improved to %s!", 
                npc.name, newLevel.name)
            
            -- List benefits of new level
            if newLevel.benefits then
                local benefits = ""
                if newLevel.benefits.canAskFavor and not oldLevel.benefits.canAskFavor then
                    benefits = benefits .. "\n- Can now ask for favors"
                end
                if newLevel.benefits.canBorrowEquipment and not oldLevel.benefits.canBorrowEquipment then
                    benefits = benefits .. "\n- Can now borrow equipment"
                end
                if newLevel.benefits.discount > (oldLevel.benefits.discount or 0) then
                    benefits = benefits .. string.format("\n- %d%% discount on trades", newLevel.benefits.discount)
                end
                
                if benefits ~= "" then
                    message = message .. "\n\nNew benefits:" .. benefits
                end
            end
        else
            -- Relationship worsened
            title = "Relationship Worsened"
            message = string.format("Your relationship with %s has worsened to %s.", 
                npc.name, newLevel.name)
            
            -- List lost benefits
            if oldLevel.benefits then
                local lostBenefits = ""
                if oldLevel.benefits.canAskFavor and not newLevel.benefits.canAskFavor then
                    lostBenefits = lostBenefits .. "\n- Can no longer ask for favors"
                end
                if oldLevel.benefits.canBorrowEquipment and not newLevel.benefits.canBorrowEquipment then
                    lostBenefits = lostBenefits .. "\n- Can no longer borrow equipment"
                end
                if (oldLevel.benefits.discount or 0) > newLevel.benefits.discount then
                    lostBenefits = lostBenefits .. string.format("\n- Lost %d%% discount", 
                        (oldLevel.benefits.discount or 0) - newLevel.benefits.discount)
                end
                
                if lostBenefits ~= "" then
                    message = message .. "\n\nLost benefits:" .. lostBenefits
                end
            end
        end
        
        self.npcSystem:showNotification(title, message)
    end
    
    -- Update NPC behavior based on new relationship level
    self:updateNPCBehaviorForRelationship(npc, newLevel)
    
    -- Log for debugging
    if self.npcSystem.settings.debugMode then
        print(string.format("Relationship level change: %s (%s -> %s)", 
            npc.name, oldLevel.name, newLevel.name))
    end
end

function NPCRelationshipManager:updateNPCBehaviorForRelationship(npc, level)
    -- Update NPC's behavior based on relationship level benefits
    if level.benefits then
        npc.favorFrequencyMultiplier = level.benefits.favorFrequency or 1.0
        npc.conversationInterest = level.benefits.favorFrequency or 0.5
        npc.willHelpPlayer = level.benefits.helpChance and (math.random(1, 100) <= level.benefits.helpChance)
        npc.mayOfferGifts = level.benefits.mayGiveGifts or false
        npc.canBorrowEquipment = level.benefits.canBorrowEquipment or false
        npc.tradeDiscount = level.benefits.discount or 0
        
        -- Update AI personality modifiers
        if npc.aiPersonalityModifiers then
            -- Higher relationship makes NPC more helpful
            npc.aiPersonalityModifiers.generosity = 0.5 + (level.min / 100) * 0.5
            npc.aiPersonalityModifiers.sociability = 0.3 + (level.min / 100) * 0.7
        end
    end
    
    -- Update mood based on relationship level
    if level.min >= 60 then
        -- Friends+ have positive base mood toward player
        if not self.npcMoods[npc.id] then
            self.npcMoods[npc.id] = {
                value = 0.2,
                modifier = 0.1,
                expiration = nil
            }
        end
    elseif level.min <= 9 then
        -- Hostile NPCs have negative mood toward player
        if not self.npcMoods[npc.id] then
            self.npcMoods[npc.id] = {
                value = -0.1,
                modifier = -0.05,
                expiration = nil
            }
        end
    end
end

function NPCRelationshipManager:getRelationshipInfo(npcId)
    local npc = self:getNPCById(npcId)
    if not npc then
        return nil
    end
    
    local level = self:getRelationshipLevel(npc.relationship)
    local history = self.relationshipHistory[npcId] or {}
    local mood = self.npcMoods[npcId]
    
    -- Calculate statistics
    local totalChanges = #history
    local positiveChanges = 0
    local negativeChanges = 0
    local totalPositive = 0
    local totalNegative = 0
    
    for _, change in ipairs(history) do
        if change.change > 0 then
            positiveChanges = positiveChanges + 1
            totalPositive = totalPositive + change.change
        elseif change.change < 0 then
            negativeChanges = negativeChanges + 1
            totalNegative = totalNegative + math.abs(change.change)
        end
    end
    
    -- Calculate trend (last 10 changes)
    local trend = 0
    local recentChanges = math.min(10, #history)
    for i = #history, #history - recentChanges + 1, -1 do
        if i >= 1 then
            trend = trend + (history[i].change or 0)
        end
    end
    
    -- Estimate next favor time
    local nextFavorEstimate = self:estimateNextFavorTime(npc)
    
    return {
        npc = npc,
        value = npc.relationship,
        level = level,
        benefits = level.benefits,
        history = history,
        lastChange = #history > 0 and history[#history] or nil,
        nextFavorEstimate = nextFavorEstimate,
        
        -- Statistics
        statistics = {
            totalChanges = totalChanges,
            positiveChanges = positiveChanges,
            negativeChanges = negativeChanges,
            totalPositive = totalPositive,
            totalNegative = totalNegative,
            netChange = totalPositive - totalNegative,
            trend = trend,
            mood = mood
        }
    }
end

function NPCRelationshipManager:estimateNextFavorTime(npc)
    if not npc or npc.favorCooldown <= 0 then
        return "now"
    end
    
    -- Calculate time until next favor can be asked
    local hours = npc.favorCooldown / (60 * 60 * 1000)
    
    if hours < 1 then
        local minutes = hours * 60
        return string.format("%.0f minutes", minutes)
    elseif hours < 24 then
        return string.format("%.1f hours", hours)
    else
        local days = hours / 24
        if days < 7 then
            return string.format("%.1f days", days)
        else
            local weeks = days / 7
            return string.format("%.1f weeks", weeks)
        end
    end
end


function NPCRelationshipManager:giveGiftToNPC(npcId, giftType, giftValue)
    local npc = self:getNPCById(npcId)
    if not npc then
        return false
    end
    
    -- Check daily gift limit
    local currentTime = g_currentMission.time
    local day = math.floor(currentTime / (24 * 60 * 60 * 1000))
    
    if not self.giftTracker[npcId] then
        self.giftTracker[npcId] = {day = day, count = 0}
    end
    
    if self.giftTracker[npcId].day ~= day then
        self.giftTracker[npcId] = {day = day, count = 0}
    end
    
    local reasonData = self.CHANGE_REASONS.GIFT_GIVEN
    if self.giftTracker[npcId].count >= (reasonData.maxPerDay or 3) then
        if self.npcSystem.settings.showNotifications then
            self.npcSystem:showNotification(
                "Gift Not Accepted",
                string.format("%s has received enough gifts for today.", npc.name)
            )
        end
        return false
    end
    
    -- Calculate relationship change based on gift
    local baseChange = 0
    
    if giftType == "money" then
        baseChange = math.min(10, math.floor(giftValue / 100))
    elseif giftType == "crops" then
        baseChange = 5
    elseif giftType == "vehicle" then
        baseChange = 15
    elseif giftType == "tool" then
        baseChange = 8
    elseif giftType == "food" then
        baseChange = 3
    elseif giftType == "drink" then
        baseChange = 2
    else
        baseChange = 3
    end
    
    -- Apply personality modifier
    local personalityMod = 1.0
    if npc.personality == "generous" then
        personalityMod = 1.2 -- Appreciates gifts more
    elseif npc.personality == "greedy" then
        personalityMod = 1.5 -- Really appreciates valuable gifts
    elseif npc.personality == "stingy" then
        personalityMod = 0.8 -- Less appreciative
    elseif npc.personality == "grumpy" then
        personalityMod = 0.7 -- Hard to please
    end
    
    -- Apply relationship level effectiveness
    local level = self:getRelationshipLevel(npc.relationship)
    local effectiveness = level.benefits.giftEffectiveness or 1.0
    
    local totalChange = math.floor(baseChange * personalityMod * effectiveness)
    
    -- Update relationship
    local success = self:updateRelationship(npcId, totalChange, "gift_given")
    
    if success then
        -- Update gift tracker
        self.giftTracker[npcId].count = self.giftTracker[npcId].count + 1
        
        -- Show notification
        if self.npcSystem.settings.showNotifications then
            local giftName = giftType
            if giftType == "money" then
                giftName = string.format("$%d", giftValue)
            end
            
            self.npcSystem:showNotification(
                "Gift Given",
                string.format("%s appreciated your %s! (+%d relationship)", 
                    npc.name, giftName, totalChange)
            )
        end
        
        return true
    end
    
    return false
end

function NPCRelationshipManager:canAskForFavor(npcId)
    local npc = self:getNPCById(npcId)
    if not npc then
        return false
    end
    
    -- Check cooldown
    if npc.favorCooldown > 0 then
        return false
    end
    
    -- Check relationship level benefits
    local level = self:getRelationshipLevel(npc.relationship)
    if not level.benefits.canAskFavor then
        return false
    end
    
    -- Check if NPC is in a good mood (mood affects willingness)
    local moodModifier = self:getMoodModifier(npcId)
    local baseChance = level.benefits.favorFrequency or 0.5
    
    -- Adjust chance based on mood
    local adjustedChance = baseChance * (1 + moodModifier)
    
    -- Personality modifiers
    if npc.personality == "generous" then
        adjustedChance = adjustedChance * 0.8 -- Less likely to ask (more giving)
    elseif npc.personality == "greedy" then
        adjustedChance = adjustedChance * 1.5 -- More likely to ask
    elseif npc.personality == "friendly" then
        adjustedChance = adjustedChance * 1.2
    elseif npc.personality == "grumpy" then
        adjustedChance = adjustedChance * 0.7
    end
    
    -- Time of day factor (more likely during working hours)
    local hour = self.npcSystem.scheduler:getCurrentHour()
    if hour >= 8 and hour <= 18 then
        adjustedChance = adjustedChance * 1.3
    else
        adjustedChance = adjustedChance * 0.5
    end
    
    return math.random() < adjustedChance
end

function NPCRelationshipManager:getRelationshipColor(value)
    local level = self:getRelationshipLevel(value)
    return level.color
end


function NPCRelationshipManager:update(dt)
    self.updateTimer = (self.updateTimer or 0) + dt
    -- Run relationship housekeeping every 60 seconds (not every frame)
    if self.updateTimer >= 60 then
        self.updateTimer = 0
        for _, npc in ipairs(self.npcSystem.activeNPCs) do
            if npc.isActive then
                self:updateNPCMood(npc.id)
                local level = self:getRelationshipLevel(npc.relationship)
                self:updateNPCBehaviorForRelationship(npc, level)
            end
        end
        -- 4k: NPC-initiated gifts to player (best friends, rare chance)
        self:checkNPCGiftGiving()
        -- Cleanup expired moods and old history
        self:cleanupExpiredData()
    end
end

--- 4k: Check if any best-friend NPC wants to give the player a gift.
-- Only happens for relationships >= 75, with a small daily chance.
function NPCRelationshipManager:checkNPCGiftGiving()
    self._giftCheckDay = self._giftCheckDay or 0
    local currentDay = 1
    if TimeHelper and TimeHelper.getGameDay then
        currentDay = TimeHelper.getGameDay()
    end
    -- Only check once per game day
    if currentDay == self._giftCheckDay then return end
    self._giftCheckDay = currentDay

    for _, npc in ipairs(self.npcSystem.activeNPCs) do
        if npc.isActive and npc.relationship and npc.relationship >= 75 then
            -- 5% chance per day for close friends, 15% for best friends (90+)
            local chance = npc.relationship >= 90 and 0.15 or 0.05
            -- Generous NPCs give more often
            if npc.personality == "generous" then chance = chance * 2 end
            -- Grumpy NPCs almost never give
            if npc.personality == "grumpy" then chance = chance * 0.2 end

            if math.random() < chance then
                -- NPC gives player a small relationship boost + notification
                local giftBonus = math.random(2, 5)
                npc.relationship = math.min(100, npc.relationship + giftBonus)

                -- Set greeting text so player sees it
                local giftMessages = {
                    "I brought you something from the farm. Hope you like it!",
                    "Found this and thought of you. Here, take it!",
                    "A little something to show my appreciation.",
                }
                npc.greetingText = npc.name .. ": \"" .. giftMessages[math.random(1, #giftMessages)] .. "\""
                npc.greetingTimer = 6  -- visible for 6 seconds

                -- Floating text
                if self.npcSystem.interactionUI then
                    self.npcSystem.interactionUI:addFloatingText(
                        npc.position.x, npc.position.y + 2.5, npc.position.z,
                        "+" .. giftBonus .. " (gift!)", 0.9, 0.7, 0.2
                    )
                end

                if self.npcSystem.settings.debugMode then
                    print(string.format("[NPC Favor] %s gave player a gift (+%d relationship)", npc.name, giftBonus))
                end
            end
        end
    end
end

function NPCRelationshipManager:cleanupExpiredData()
    local currentTime = g_currentMission.time
    
    -- Clean up expired moods
    for npcId, mood in pairs(self.npcMoods) do
        if mood.expiration and currentTime > mood.expiration then
            self.npcMoods[npcId] = nil
        end
    end
    
    -- Clean up old history entries (older than 30 days)
    local thirtyDays = 30 * 24 * 60 * 60 * 1000
    for npcId, history in pairs(self.relationshipHistory) do
        for i = #history, 1, -1 do
            if currentTime - history[i].time > thirtyDays then
                table.remove(history, i)
            end
        end

        -- Remove empty history
        if #history == 0 then
            self.relationshipHistory[npcId] = nil
        end
    end

    -- Passive player-NPC relationship decay: -0.5 per in-game day for inactive NPCs
    -- Only applies to relationships above 25 (neutral), preventing decay below baseline
    -- Note: cleanupExpiredData() is called once per 60 real seconds from update()
    for _, npc in ipairs(self.npcSystem.activeNPCs) do
        if npc.isActive and npc.relationship and npc.relationship > 25 then
            local lastInteraction = npc.lastGreetingTime or 0
            local timeSince = currentTime - lastInteraction
            -- Decay if no interaction for 2+ in-game days
            local twoDays = 2 * 24 * 60 * 60 * 1000
            if timeSince > twoDays then
                local decayAmount = 0.008  -- ~0.5 per minute at 60s intervals
                npc.relationship = math.max(25, npc.relationship - decayAmount)
            end
        end
    end

    -- NPC-NPC relationship decay: idle pairs slowly drift toward neutral (50)
    if self.npcRelationships then
        for key, rel in pairs(self.npcRelationships) do
            local timeSince = currentTime - (rel.lastInteraction or 0)
            local threeDays = 3 * 24 * 60 * 60 * 1000
            if timeSince > threeDays then
                -- Drift toward 50 at 0.1 per check
                if rel.value > 50 then
                    rel.value = math.max(50, rel.value - 0.1)
                elseif rel.value < 50 then
                    rel.value = math.min(50, rel.value + 0.1)
                end
            end
        end
    end
end