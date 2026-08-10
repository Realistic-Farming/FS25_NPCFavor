-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- FAVOR TYPES:
-- [x] Seven favor types across vehicle, fieldwork, transport, repair, delivery, financial, security
-- [x] Difficulty-scaled rewards and penalties per favor type
-- [x] Equipment and relationship requirements for favor eligibility
-- [x] Seasonal favors (snow clearing in winter, irrigation in summer)
-- [ ] Chain favors that unlock follow-up quests from the same NPC
-- [ ] Community favors involving multiple NPCs cooperating
--
-- GENERATION & TRACKING:
-- [x] Weighted random NPC selection based on relationship and personality
-- [x] Time-of-day probability scaling for favor generation
-- [x] Multi-step favor progression with location-based checkpoints
-- [x] Notification queue system with cooldown between messages
-- [ ] Favor journal UI showing active, completed, and failed history
-- [ ] Map markers for favor objectives and delivery destinations
--
-- COMPLETION & REWARDS:
-- [x] Favor completion with relationship and money rewards
-- [x] Failure and abandonment penalty system with reputation impact
-- [x] Statistics tracking (fastest completion, total earnings, etc.)
-- [x] Save/restore of active favors across game sessions
-- [x] Bonus rewards for completing favors ahead of deadline
-- [ ] Reputation system affecting all NPC interactions globally
-- [ ] Tiered reward multipliers for consecutive favor streaks
-- =========================================================

-- =========================================================
-- FS25 NPC Favor Mod - Favor System
-- =========================================================
-- Manages favor requests, tracking, and completion
-- =========================================================

NPCFavorSystem = {}
NPCFavorSystem_mt = Class(NPCFavorSystem)

-- Per-personality category weight multipliers for favor type selection.
-- Higher = that personality generates this category more often.
NPCFavorSystem.PERSONALITY_CATEGORY_WEIGHTS = {
    generous    = {animal_care = 2.0, repair = 1.5, fieldwork = 1.2},
    greedy      = {financial = 2.5, security = 1.8, delivery = 1.2},
    friendly    = {fieldwork = 1.8, delivery = 1.4, animal_care = 1.5, transport = 1.2},
    grumpy      = {repair = 1.6, security = 1.4, financial = 1.2},
    hardworking = {fieldwork = 2.0, delivery = 1.8, transport = 1.5, repair = 1.2},
}

-- Per-role category weight multipliers — layered on top of personality weights.
-- Shopkeepers skew toward delivery/social; farmhands toward fieldwork/equipment.
NPCFavorSystem.ROLE_CATEGORY_WEIGHTS = {
    farmer     = {fieldwork = 1.6, harvest = 1.5, equipment = 1.2, delivery = 1.0, repair = 1.1},
    farmhand   = {fieldwork = 1.9, harvest = 1.7, equipment = 1.5, delivery = 1.2, repair = 1.3},
    shopkeeper = {delivery = 1.8, financial = 1.6, social = 1.4, transport = 1.3, fieldwork = 0.5},
    worker     = {repair = 1.7, equipment = 1.5, delivery = 1.3, fieldwork = 0.9, financial = 1.1},
}

function NPCFavorSystem.new(npcSystem)
    local self = setmetatable({}, NPCFavorSystem_mt)
    
    self.npcSystem = npcSystem
    
    -- Favor definitions with expanded types
    self.favorTypes = {
        {
            id = "borrow_tractor",
            name = "npc_favor_borrow_tractor",
            description = "Borrow my tractor for a day",
            difficulty = 1,
            duration = 24, -- hours
            reward = {relationship = 15, money = 500, xp = 50},
            penalty = {relationship = -5, reputation = -10},
            requirements = {hasTractor = true, minRelationship = 20},
            category = "vehicle"
        },
        {
            id = "help_harvest",
            name = "npc_favor_help_harvest",
            description = "Help with harvesting my field",
            difficulty = 2,
            duration = 48,
            reward = {relationship = 20, money = 1000, xp = 100},
            penalty = {relationship = -10, reputation = -20},
            requirements = {hasHarvester = true, minRelationship = 30},
            category = "fieldwork"
        },
        {
            id = "transport_goods",
            name = "npc_favor_transport_goods",
            description = "Transport goods to market for me",
            difficulty = 1,
            duration = 12,
            reward = {relationship = 10, money = 300, xp = 30},
            penalty = {relationship = -3, reputation = -5},
            requirements = {hasTrailer = true, minRelationship = 10},
            category = "transport"
        },
        {
            id = "fix_fence",
            name = "npc_favor_fix_fence",
            description = "Fix my broken fence",
            difficulty = 1,
            duration = 6,
            reward = {relationship = 10, money = 200, xp = 25},
            penalty = {relationship = -2, reputation = -5},
            requirements = {minRelationship = 5},
            category = "repair"
        },
        {
            id = "deliver_seeds",
            name = "npc_favor_deliver_seeds",
            description = "Deliver seeds to my farm",
            difficulty = 2,
            duration = 36,
            reward = {relationship = 15, money = 700, xp = 60},
            penalty = {relationship = -7, reputation = -15},
            requirements = {hasTruck = true, minRelationship = 25},
            category = "delivery"
        },
        {
            id = "loan_money",
            name = "npc_favor_loan_money",
            description = "Loan me some money until next harvest",
            difficulty = 3,
            duration = 168, -- 7 days
            reward = {relationship = 25, money = 1500, xp = 150},
            penalty = {relationship = -25, reputation = -50},
            requirements = {minRelationship = 50, playerMoney = 5000},
            category = "financial"
        },
        {
            id = "watch_property",
            name = "npc_favor_watch_property",
            description = "Watch my property while I'm away",
            difficulty = 2,
            duration = 72,
            reward = {relationship = 18, money = 800, xp = 80},
            penalty = {relationship = -15, reputation = -30},
            requirements = {minRelationship = 40},
            category = "security"
        },
        {
            id = "water_animals",
            name = "npc_favor_water_animals",
            description = "Water my animals while I'm away",
            difficulty = 1,
            duration = 4,
            reward = {relationship = 8, money = 150, xp = 20},
            penalty = {relationship = -2, reputation = -5},
            requirements = {minRelationship = 10},
            category = "animal_care"
        },
        {
            id = "retrieve_equipment",
            name = "npc_favor_retrieve_equipment",
            description = "Retrieve my stuck equipment from the field",
            difficulty = 2,
            duration = 12,
            reward = {relationship = 15, money = 400, xp = 45},
            penalty = {relationship = -5, reputation = -10},
            requirements = {minRelationship = 20},
            category = "fieldwork"
        },
        {
            id = "pick_up_supplies",
            name = "npc_favor_pick_up_supplies",
            description = "Pick up supplies from the co-op for me",
            difficulty = 1,
            duration = 10,
            reward = {relationship = 12, money = 350, xp = 35},
            penalty = {relationship = -3, reputation = -8},
            requirements = {minRelationship = 15},
            category = "delivery"
        }
    }
    
    -- Active favors
    self.activeFavors = {} -- Player's active favors
    
    -- Player's favor history
    self.completedFavors = {}
    self.failedFavors = {}
    self.abandonedFavors = {}
    
    -- Statistics
    self.stats = {
        totalFavorsCompleted = 0,
        totalFavorsFailed = 0,
        totalRelationshipEarned = 0,
        totalMoneyEarned = 0,
        totalXPEarned = 0,
        fastestCompletion = nil,
        longestFavor = nil
    }
    
    -- Flash notifications route through favorHUD (no more messageCenter)
    
    return self
end

function NPCFavorSystem:update(dt)
    local currentGameTime = TimeHelper.getGameTimeMs()

    -- Update active favors using in-game clock (scales with game speed)
    for i = #self.activeFavors, 1, -1 do
        local favor = self.activeFavors[i]

        if favor.expirationGameTime then
            favor.timeRemaining = favor.expirationGameTime - currentGameTime
        end

        if favor.timeRemaining and favor.timeRemaining <= 0 then
            self:failFavor(favor.id, "time_expired")
            table.remove(self.activeFavors, i)
        else
            -- Check progress conditions
            self:checkFavorProgress(favor, dt)
        end
    end
    
    -- Random favor requests (with time-based probability)
    if self.npcSystem.settings.enableFavors then
        self:tryGenerateFavorRequest(dt)
    end
end

function NPCFavorSystem:tryGenerateFavorRequest(dt)
    -- Only try every few seconds for performance
    if not self.lastFavorAttemptTime then
        self.lastFavorAttemptTime = 0
    end
    
    local currentTime = g_currentMission and g_currentMission.time or 0
    if currentTime - self.lastFavorAttemptTime < 10000 then -- 10 seconds cooldown
        return
    end
    
    self.lastFavorAttemptTime = currentTime
    
    -- Check if we should generate a favor request
    if not self.npcSystem or not self.npcSystem.settings.enableFavors then
        return
    end
    
    -- Calculate probability based on time of day and number of active favors
    local hour = self.npcSystem.scheduler:getCurrentHour()
    local activeFavorCount = #self.activeFavors
    local maxActiveFavors = self.npcSystem.settings.maxNPCs * 2 -- Allow up to 2 favors per NPC

    -- Base probability scaled by favorFrequency setting (higher = less frequent)
    local freq = (self.npcSystem.settings and self.npcSystem.settings.favorFrequency) or 3
    local baseProbability = 0.05 / math.max(1, freq)
    local timeFactor = 1.0
    
    if hour >= 8 and hour <= 18 then
        timeFactor = 2.0 -- Double chance during work hours
    elseif hour >= 6 and hour <= 20 then
        timeFactor = 1.5
    end
    
    -- Reduce probability if we have many active favors
    local favorFactor = math.max(0.1, 1.0 - (activeFavorCount / maxActiveFavors))
    
    -- Note: dt is already in seconds (NPCSystem divides by 1000)
    -- This function gates on a 10-second cooldown (line 170), so no dt scaling needed
    local probability = baseProbability * timeFactor * favorFactor
    
    if math.random() < probability then
        self:generateFavorRequest()
    end
end

function NPCFavorSystem:generateFavorLocation(npc, favorType)
    -- Generate location data for the favor
    local location = {
        type = "point",
        x = npc.homePosition.x,
        y = npc.homePosition.y,
        z = npc.homePosition.z,
        radius = 50
    }
    
    -- Customize based on favor type
    if favorType.category == "transport" then
        location.type = "transport"
        location.start = {
            x = npc.homePosition.x,
            y = npc.homePosition.y,
            z = npc.homePosition.z
        }
        location.destination = self:findNearestSellPoint(npc.homePosition.x, npc.homePosition.z)
    elseif favorType.category == "fieldwork" and npc.assignedField and npc.assignedField.center then
        location.type = "field"
        location.x = npc.assignedField.center.x
        location.z = npc.assignedField.center.z
        location.fieldId = npc.assignedField.id
    end
    
    return location
end

function NPCFavorSystem:generateTaskData(favorType, npc)
    local taskData = {
        favorType = favorType.id,
        npcId = npc.id,
        createdTime = g_currentMission.time
    }
    
    if favorType.id == "borrow_tractor" then
        taskData.vehicleId = nil -- Will be assigned when NPC lends vehicle
        taskData.returnTime = g_currentMission.time + (24 * 60 * 60 * 1000)
    elseif favorType.id == "loan_money" then
        taskData.loanAmount = 5000
        taskData.loanAmountDeducted = false
    elseif favorType.id == "help_harvest" then
        taskData.fieldId = npc.assignedField and npc.assignedField.id
        taskData.requiredAmount = math.random(1000, 5000) -- liters
    elseif favorType.id == "transport_goods" then
        taskData.goodsType = "grain"
        taskData.amount = math.random(100, 500)
        taskData.startLocation = {
            x = npc.homePosition.x,
            y = npc.homePosition.y,
            z = npc.homePosition.z
        }
        taskData.destination = self:findNearestSellPoint(npc.homePosition.x, npc.homePosition.z)
    end
    
    return taskData
end

function NPCFavorSystem:findNearestSellPoint(x, z)
    -- Find the nearest sell/unloading point using FS25 storageSystem API
    if not g_currentMission or not g_currentMission.storageSystem then
        return {x = x + 500, y = 0, z = z + 500} -- Default far location
    end

    local sellPoints = {}

    -- Use FS25's unloading stations API (sell points are unloading stations)
    local ok, unloadingStations = pcall(function()
        return g_currentMission.storageSystem:getUnloadingStations()
    end)

    if ok and unloadingStations then
        for _, station in pairs(unloadingStations) do
            if station then
                local nodeId = station.rootNode or station.nodeId
                if nodeId then
                    local okPos, sx, sy, sz = pcall(getWorldTranslation, nodeId)
                    if okPos and sx then
                        table.insert(sellPoints, {
                            x = sx,
                            y = sy,
                            z = sz,
                            name = station:getName() or "Sell Point"
                        })
                    end
                end
            end
        end
    end

    -- Find nearest
    local nearest = nil
    local nearestDist = math.huge

    for _, point in ipairs(sellPoints) do
        local dist = VectorHelper.distance2D(x, z, point.x, point.z)
        if dist < nearestDist then
            nearestDist = dist
            nearest = point
        end
    end

    if nearest then
        return nearest
    end

    -- Fallback: random direction from NPC home
    local angle = math.random() * math.pi * 2
    return {x = x + math.cos(angle) * 500, y = 0, z = z + math.sin(angle) * 500}
end

function NPCFavorSystem:generateFavorRequest()
    if not self.npcSystem or #self.npcSystem.activeNPCs == 0 then
        return false
    end
    
    -- Find NPC who can ask for favor
    local candidateNPCs = {}
    local candidateWeights = {}
    
    for _, npc in ipairs(self.npcSystem.activeNPCs) do
        if npc.isActive and self:canNPCRequestFavor(npc) then
            table.insert(candidateNPCs, npc)
            
            -- Weight based on relationship (higher relationship = more likely to ask)
            local weight = 10 + (npc.relationship * 0.5)
            
            -- Personality modifiers
            if npc.personality == "generous" then
                weight = weight * 0.7
            elseif npc.personality == "greedy" then
                weight = weight * 1.5
            elseif npc.personality == "friendly" then
                weight = weight * 1.2
            elseif npc.personality == "grumpy" then
                weight = weight * 0.8
            end
            
            -- Time since last favor
            local timeSinceLastFavor = g_currentMission.time - (npc.lastFavorTime or 0)
            if timeSinceLastFavor > (24 * 60 * 60 * 1000) then -- More than 1 day
                weight = weight * 1.5
            end

            local npcMemory = self:analyzeEncounterHistory(npc)
            local memoryMod = npcMemory.memoryScore * 3
            weight = math.max(1, weight + memoryMod)

            candidateWeights[npc.id] = weight
        end
    end
    
    if #candidateNPCs == 0 then
        return false
    end
    
    -- Weighted random selection
    local totalWeight = 0
    for _, weight in pairs(candidateWeights) do
        totalWeight = totalWeight + weight
    end
    
    local randomValue = math.random() * totalWeight
    local currentWeight = 0
    local selectedNPC = nil
    
    for _, npc in ipairs(candidateNPCs) do
        currentWeight = currentWeight + candidateWeights[npc.id]
        if randomValue <= currentWeight then
            selectedNPC = npc
            break
        end
    end
    
    if not selectedNPC then
        selectedNPC = candidateNPCs[1] -- Fallback
    end

    local selectedMemory = self:analyzeEncounterHistory(selectedNPC)
    local declineChance = 0.0
    if selectedMemory.memoryScore < -0.5 then
        declineChance = 0.15
    elseif selectedMemory.memoryScore > 0.5 then
        declineChance = -0.10
    end
    if declineChance > 0 and math.random() < declineChance then
        return false
    end

    -- Select favor type based on NPC and player capabilities
    local availableFavors = {}
    for _, favorType in ipairs(self.favorTypes) do
        if self:checkFavorRequirements(selectedNPC, favorType) then
            table.insert(availableFavors, favorType)
        end
    end
    
    if #availableFavors == 0 then
        return false
    end
    
    -- Weight favor selection by difficulty and relationship
    local favorWeights = {}
    for _, favorType in ipairs(availableFavors) do
        local weight = 10 - favorType.difficulty -- Easier favors more likely
        
        -- Higher relationship allows for more difficult favors
        if selectedNPC.relationship > 50 then
            weight = weight + (favorType.difficulty * 0.5)
        end
        
        -- Personality-preferred favor categories
        local categoryBoost = NPCFavorSystem.PERSONALITY_CATEGORY_WEIGHTS[selectedNPC.personality]
        if categoryBoost then
            local boost = categoryBoost[favorType.category]
            if boost then weight = weight * boost end
        end

        -- Role-preferred favor categories (stacked on top of personality)
        local roleBoost = NPCFavorSystem.ROLE_CATEGORY_WEIGHTS[selectedNPC.role]
        if roleBoost then
            local boost = roleBoost[favorType.category]
            if boost then weight = weight * boost end
        end

        -- 4j: Seasonal favor weighting
        local season = nil
        if self.npcSystem.scheduler and self.npcSystem.scheduler.getCurrentSeason then
            season = self.npcSystem.scheduler:getCurrentSeason()
        end
        if season then
            local category = favorType.category or ""
            if season == "autumn" and (category == "harvest" or category == "delivery" or category == "field") then
                weight = weight * 2.0  -- Harvest season: more field/delivery requests
            elseif season == "spring" and (category == "field" or category == "planting") then
                weight = weight * 1.8  -- Spring: more planting/field prep requests
            elseif season == "winter" and (category == "repair" or category == "maintenance" or category == "social") then
                weight = weight * 1.5  -- Winter: more indoor/repair requests
            elseif season == "summer" and (category == "delivery" or category == "social") then
                weight = weight * 1.3  -- Summer: more social/delivery requests
            end
        end

        local favorMemoryMod = selectedMemory.memoryScore * 3
        weight = math.max(1, weight + favorMemoryMod)

        favorWeights[favorType.id] = weight
    end
    
    -- Weighted random selection for favor type
    totalWeight = 0
    for _, weight in pairs(favorWeights) do
        totalWeight = totalWeight + weight
    end
    
    randomValue = math.random() * totalWeight
    currentWeight = 0
    local selectedFavorType = nil
    
    for _, favorType in ipairs(availableFavors) do
        currentWeight = currentWeight + favorWeights[favorType.id]
        if randomValue <= currentWeight then
            selectedFavorType = favorType
            break
        end
    end
    
    if not selectedFavorType then
        selectedFavorType = availableFavors[1] -- Fallback
    end
    
    -- Create and request favor
    local favor = self:createFavor(selectedNPC, selectedFavorType.id)
    if favor then
        -- Add to player's active favors
        table.insert(self.activeFavors, favor)
        
        -- Set NPC cooldown
        local cooldownDays = self.npcSystem.settings.favorFrequency
        if selectedNPC.personality == "greedy" then
            cooldownDays = math.max(1, cooldownDays - 1) -- Greedy NPCs ask more often
        elseif selectedNPC.personality == "generous" then
            cooldownDays = cooldownDays + 1 -- Generous NPCs ask less often
        end
        
        selectedNPC.favorCooldown = cooldownDays * 300  -- 5 real-seconds per "day" (dt is real seconds)
        selectedNPC.lastFavorTime = g_currentMission.time
        
        -- Flash notification on HUD
        if self.npcSystem.favorHUD then
            local msg = string.format(g_i18n:getText("npc_hud_new_favor") or "New: %s needs help!", selectedNPC.name)
            self.npcSystem.favorHUD:flashFavor(msg, {1, 0.9, 0.3, 1})
        end
        
        -- Log for debugging
        if self.npcSystem.settings.debugMode then
            print(string.format("Favor requested: %s asks for %s (Difficulty: %d)",
                selectedNPC.name, selectedFavorType.description, selectedFavorType.difficulty))
        end
        
        return true
    end
    
    return false
end

function NPCFavorSystem:canNPCRequestFavor(npc)
    -- Check basic conditions
    if not npc.isActive then
        return false
    end
    
    -- Check cooldown
    if npc.favorCooldown > 0 then
        return false
    end
    
    -- Check relationship threshold
    if npc.relationship < 10 then -- Minimum relationship to ask for favors
        return false
    end
    
    -- Check if NPC has asked too many favors recently
    local recentFavorCount = 0
    for _, favor in ipairs(self.activeFavors) do
        if favor.npcId == npc.id then
            recentFavorCount = recentFavorCount + 1
        end
    end
    
    if recentFavorCount >= 2 then
        return false -- NPC already has 2 active favors with player
    end
    
    -- Personality-based checks
    if npc.personality == "grumpy" and npc.relationship < 40 then
        return false -- Grumpy NPCs need higher relationship
    end
    
    return true
end

function NPCFavorSystem:createFavor(npc, favorTypeId)
    local favorType = nil
    for _, ft in ipairs(self.favorTypes) do
        if ft.id == favorTypeId then
            favorType = ft
            break
        end
    end
    
    if not favorType then
        return nil
    end
    
    -- Generate unique ID
    local favorId = #self.activeFavors + #self.completedFavors + #self.failedFavors + 1
    
    local favor = {
        id = favorId,
        npcId = npc.id,
        npcName = npc.name,
        type = favorType.id,
        name = favorType.name,
        description = favorType.description,
        difficulty = favorType.difficulty,
        category = favorType.category,
        
        -- Status
        status = "pending", -- pending, active, in_progress, completed, failed, abandoned
        progress = 0,
        progressDetails = {},
        
        -- Time management (uses in-game clock so timers scale with game speed)
        createdTime = TimeHelper.getGameTimeMs(),
        expirationGameTime = TimeHelper.getGameTimeMs() + (favorType.duration * 60 * 60 * 1000),
        timeRemaining = favorType.duration * 60 * 60 * 1000,
        estimatedCompletionTime = nil,
        
        -- Requirements
        requirements = favorType.requirements,
        
        -- Rewards and penalties
        reward = favorType.reward,
        penalty = favorType.penalty,
        
        -- Location info (where favor needs to be done)
        location = self:generateFavorLocation(npc, favorType),
        
        -- Specific task data
        taskData = self:generateTaskData(favorType, npc),
        
        -- Tracking
        startTime = nil,
        completionTime = nil,
        completionDuration = nil,
        
        -- Player notes
        playerNotes = "",
        priority = 1, -- 1-5 priority level
        
        -- Multi-step favors
        currentStep = 1,
        totalSteps = 1,
        steps = self:generateFavorSteps(favorType, npc)
    }
    
    return favor
end

function NPCFavorSystem:checkFavorRequirements(npc, favorType)
    -- Check relationship requirement
    if favorType.requirements.minRelationship and npc.relationship < favorType.requirements.minRelationship then
        return false
    end
    
    -- Check player money requirement
    if favorType.requirements.playerMoney then
        if not g_currentMission or not g_currentMission.player then
            return false
        end
        local playerMoney = g_currentMission.player.money or 0
        if playerMoney < favorType.requirements.playerMoney then
            return false
        end
    end
    
    -- Check equipment requirements
    -- Note: hasTractor / hasHarvester / hasTrailer / hasTruck requirements are intentionally
    -- not enforced here. NPC vehicle props are not functional yet (see roadmap), so
    -- npc.assignedVehicles is always empty and those checks would silently block three
    -- favor types from ever generating. The relationship gate is sufficient for now.

    return true
end

function NPCFavorSystem:generateFavorSteps(favorType, npc)
    local steps = {}
    local home = npc.homePosition

    if not home then
        return {{id = 1, description = "Complete the task", completed = false, location = nil}}
    end

    if favorType.id == "borrow_tractor" then
        local fieldPos = (npc.assignedField and npc.assignedField.center) or {
            x = home.x + math.random(60, 120) * (math.random(2) == 1 and 1 or -1),
            y = home.y,
            z = home.z + math.random(60, 120) * (math.random(2) == 1 and 1 or -1)
        }
        steps = {
            {id = 1, description = "Pick up tractor keys at NPC's farm",   completed = false, location = home},
            {id = 2, description = "Drive tractor out to the field",        completed = false, location = fieldPos},
            {id = 3, description = "Return tractor to NPC's farm",          completed = false, location = home}
        }

    elseif favorType.id == "fix_fence" then
        -- Materials are ~50-80m away; fence is ~18m off from the farm entrance
        local angle1 = math.random() * math.pi * 2
        local dist1  = 50 + math.random() * 30
        local materialsPos = {
            x = home.x + math.cos(angle1) * dist1,
            y = home.y,
            z = home.z + math.sin(angle1) * dist1
        }
        local angle2 = angle1 + (math.pi * 0.5)
        local fencePos = {
            x = home.x + math.cos(angle2) * 18,
            y = home.y,
            z = home.z + math.sin(angle2) * 18
        }
        steps = {
            {id = 1, description = "Meet at NPC's farm to assess the damage", completed = false, location = home},
            {id = 2, description = "Collect repair materials nearby",          completed = false, location = materialsPos},
            {id = 3, description = "Repair the fence",                         completed = false, location = fencePos}
        }

    elseif favorType.id == "help_harvest" then
        local fieldPos = (npc.assignedField and npc.assignedField.center) or {
            x = home.x + math.random(40, 100) * (math.random(2) == 1 and 1 or -1),
            y = home.y,
            z = home.z + math.random(40, 100) * (math.random(2) == 1 and 1 or -1)
        }
        steps = {
            {id = 1, description = "Go to the field",                     completed = false, location = fieldPos},
            {id = 2, description = "Transport harvest back to storage",    completed = false, location = home}
        }

    elseif favorType.id == "transport_goods" then
        local sellPoint = self:findNearestSellPoint(home.x, home.z)
        if VectorHelper.distance2D(home.x, home.z, sellPoint.x, sellPoint.z) > 1000 then
            local a = math.random() * math.pi * 2
            sellPoint = {x = home.x + math.cos(a) * 500, y = 0, z = home.z + math.sin(a) * 500}
        end
        steps = {
            {id = 1, description = "Load goods at NPC's farm",  completed = false, location = home},
            {id = 2, description = "Deliver to market",          completed = false, location = sellPoint}
        }

    elseif favorType.id == "deliver_seeds" then
        local sellPoint = self:findNearestSellPoint(home.x, home.z)
        if VectorHelper.distance2D(home.x, home.z, sellPoint.x, sellPoint.z) > 1000 then
            local a = math.random() * math.pi * 2
            sellPoint = {x = home.x + math.cos(a) * 500, y = 0, z = home.z + math.sin(a) * 500}
        end
        steps = {
            {id = 1, description = "Pick up seeds at the co-op",     completed = false, location = sellPoint},
            {id = 2, description = "Deliver seeds to NPC's farm",    completed = false, location = home}
        }

    elseif favorType.id == "water_animals" then
        local angle = math.random() * math.pi * 2
        local waterPos = {
            x = home.x + math.cos(angle) * 20,
            y = home.y,
            z = home.z + math.sin(angle) * 20
        }
        steps = {
            {id = 1, description = "Go to NPC's farm",    completed = false, location = home},
            {id = 2, description = "Water the animals",   completed = false, location = waterPos}
        }

    elseif favorType.id == "retrieve_equipment" then
        local equipPos = (npc.assignedField and npc.assignedField.center) or {
            x = home.x + math.random(80, 130) * (math.random(2) == 1 and 1 or -1),
            y = home.y,
            z = home.z + math.random(80, 130) * (math.random(2) == 1 and 1 or -1)
        }
        steps = {
            {id = 1, description = "Find the stuck equipment in the field", completed = false, location = equipPos},
            {id = 2, description = "Bring it back to NPC's farm",           completed = false, location = home}
        }

    elseif favorType.id == "pick_up_supplies" then
        local sellPoint = self:findNearestSellPoint(home.x, home.z)
        if VectorHelper.distance2D(home.x, home.z, sellPoint.x, sellPoint.z) > 1000 then
            local a = math.random() * math.pi * 2
            sellPoint = {x = home.x + math.cos(a) * 400, y = 0, z = home.z + math.sin(a) * 400}
        end
        steps = {
            {id = 1, description = "Pick up supplies at the co-op",     completed = false, location = sellPoint},
            {id = 2, description = "Deliver supplies to NPC's farm",    completed = false, location = home}
        }

    elseif favorType.id == "watch_property" then
        steps = {
            {id = 1, description = "Go to NPC's property",              completed = false, location = home},
            {id = 2, description = "Talk to NPC to complete the watch", completed = false, location = home, isDialogStep = true}
        }

    elseif favorType.id == "loan_money" then
        steps = {
            {id = 1, description = "Meet NPC at their farm to hand over the money", completed = false, location = home},
            {id = 2, description = "Wait for NPC to repay the loan",                completed = false, location = home,
                isLoanRepayStep = true}
        }

    else
        steps = {
            {id = 1, description = "Complete the task at NPC's farm", completed = false, location = home}
        }
    end

    return steps
end

function NPCFavorSystem:checkFavorProgress(favor, dt)
    if not favor or not self.npcSystem then
        return
    end

    -- Don't auto-complete pending favors — player must accept them first
    if favor.status == "pending" then
        return
    end

    -- Safety check for player position
    local playerPos = self.npcSystem.playerPosition
    if not playerPos or not self.npcSystem.playerPositionValid then
        return
    end
    
    -- Multi-step favor progress
    if favor.steps and #favor.steps > 0 then
        local completedSteps = 0

        for _, step in ipairs(favor.steps) do
            if not step.completed and not step.isDialogStep and not step.isLoanRepayStep and step.location then
                -- Ground distance (XZ) so completion matches what the player reads on the
                -- HUD arrow, which is XZ only (NPCFavorHUD:getDistanceInfo). A 3D check
                -- also counted the Y delta, so a bad step.location.y (reload, y=0 sell
                -- point fallback) could hold a step open at HUD 0m and stall the favor.
                local distance = VectorHelper.distance2D(
                    playerPos.x, playerPos.z,
                    step.location.x or 0, step.location.z or 0)

                if distance < 30 then
                    if favor.type == "loan_money" and step.id == 1
                        and not (favor.taskData and favor.taskData.loanAmountDeducted) then
                        local loanAmount = (favor.taskData and favor.taskData.loanAmount) or 5000
                        -- This sim loop runs only under `if self.isServer`, so this is
                        -- already server-authoritative. Pay the owning farm (stamped at
                        -- accept), not the local player, which is nil on a dedicated
                        -- server. Guarded by loanAmountDeducted so it disburses once.
                        local farmId = favor.ownerFarmId or self:resolveOwnerFarmId(favor)
                        favor.ownerFarmId = farmId
                        g_currentMission:addMoney(-loanAmount, farmId, MoneyType.OTHER, true)
                        if favor.taskData then favor.taskData.loanAmountDeducted = true end
                    end

                    step.completed = true

                    -- Flash notification on HUD (queueNotification never existed;
                    -- all favor notifications route through favorHUD:flashFavor)
                    if self.npcSystem.favorHUD then
                        local fmt = g_i18n:getText("npc_hud_step_done") or "Step %d done: %s"
                        local msg = string.format(fmt, step.id, step.description or "")
                        self.npcSystem.favorHUD:flashFavor(msg, {0.3, 1, 0.3, 1})
                    end
                end
            end

            if step.completed then
                completedSteps = completedSteps + 1
            end
        end

        -- Update overall progress
        local newProgress = (completedSteps / #favor.steps) * 100
        if newProgress > favor.progress then
            favor.progress = newProgress
        end

        if completedSteps == #favor.steps then
            favor.progress = 100
            self:completeFavor(favor.id)
        end
    end
end



function NPCFavorSystem:completeFavor(favorId)
    local favor = self:getFavorById(favorId)
    if not favor or favor.status == "completed" then
        return false
    end

    -- Server-authoritative: the status flip and all money happen only on the
    -- server/host. Clients reach completion by sending intent through
    -- NPCInteractionEvent, never by flipping status or paying money locally. In
    -- single-player the host is the server, so this never blocks SP.
    if g_server == nil then
        return false
    end

    -- Calculate completion time
    favor.completionTime = g_currentMission.time
    if favor.startTime then
        favor.completionDuration = favor.completionTime - favor.startTime
    end
    
    -- Update status
    favor.status = "completed"
    favor.progress = 100
    
    -- Move to completed list
    table.insert(self.completedFavors, favor)
    
    -- Remove from active list
    for i, f in ipairs(self.activeFavors) do
        if f.id == favorId then
            table.remove(self.activeFavors, i)
            break
        end
    end
    
    -- Apply rewards
    self:applyFavorRewards(favor)
    
    -- Update statistics
    self:updateStats(favor)
    
    -- Update UI
    if self.npcSystem.interactionUI then
        self.npcSystem.interactionUI:updateFavorList()
    end
    
    -- Flash notification on HUD
    if self.npcSystem.favorHUD then
        local msg = string.format(g_i18n:getText("npc_hud_completed") or "Done: %s", favor.description or favor.npcName)
        self.npcSystem.favorHUD:flashFavor(msg, {0.3, 1, 0.3, 1})
    end

    return true
end

function NPCFavorSystem:failFavor(favorId, reason)
    local favor = self:getFavorById(favorId)
    if not favor then
        return false
    end
    
    -- Update status
    favor.status = "failed"
    favor.failureTime = g_currentMission.time
    favor.failureReason = reason or "unknown"
    
    -- Move to failed list
    table.insert(self.failedFavors, favor)
    
    -- Remove from active list
    for i, f in ipairs(self.activeFavors) do
        if f.id == favorId then
            table.remove(self.activeFavors, i)
            break
        end
    end
    
    -- Apply penalties
    self:applyFavorPenalties(favor)
    
    -- Update NPC stats
    local npc = self:getNPCFromFavor(favorId)
    if npc then
        npc.totalFavorsFailed = (npc.totalFavorsFailed or 0) + 1
    end
    
    -- Update UI
    if self.npcSystem.interactionUI then
        self.npcSystem.interactionUI:updateFavorList()
    end
    
    -- Flash notification on HUD
    if self.npcSystem.favorHUD then
        local msg = string.format(g_i18n:getText("npc_hud_failed") or "Failed: %s", favor.description or favor.npcName)
        self.npcSystem.favorHUD:flashFavor(msg, {1, 0.3, 0.3, 1})
    end
    
    return true
end

function NPCFavorSystem:abandonFavor(favorId)
    local favor = self:getFavorById(favorId)
    if not favor then
        return false
    end
    
    -- Update status
    favor.status = "abandoned"
    favor.abandonTime = g_currentMission.time
    
    -- Move to abandoned list
    table.insert(self.abandonedFavors, favor)
    
    -- Remove from active list
    for i, f in ipairs(self.activeFavors) do
        if f.id == favorId then
            table.remove(self.activeFavors, i)
            break
        end
    end
    
    -- Apply penalties (smaller than for failure)
    if favor.penalty then
        local npc = self:getNPCFromFavor(favorId)
        if npc and favor.penalty.relationship then
            self.npcSystem.relationshipManager:updateRelationship(
                npc.id, 
                math.floor(favor.penalty.relationship * 0.5), -- Half penalty for abandonment
                "favor_abandoned"
            )
        end
    end
    
    -- Update NPC stats
    local npc = self:getNPCFromFavor(favorId)
    if npc then
        npc.totalFavorsFailed = (npc.totalFavorsFailed or 0) + 1
    end
    
    -- Update UI
    if self.npcSystem.interactionUI then
        self.npcSystem.interactionUI:updateFavorList()
    end
    
    -- Flash notification on HUD
    if self.npcSystem.favorHUD then
        local msg = string.format(g_i18n:getText("npc_hud_cancelled") or "Cancelled: %s", favor.description or favor.npcName)
        self.npcSystem.favorHUD:flashFavor(msg, {1, 0.5, 0.3, 1})
    end
    
    return true
end

function NPCFavorSystem:applyFavorRewards(favor)
    if not favor.reward then
        return
    end
    
    -- Find NPC
    local npc = nil
    for _, n in ipairs(self.npcSystem.activeNPCs) do
        if n.id == favor.npcId then
            npc = n
            break
        end
    end
    
    if npc then
        -- Update relationship
        if favor.reward.relationship then
            self.npcSystem.relationshipManager:updateRelationship(
                npc.id, 
                favor.reward.relationship,
                "favor_completed"
            )
        end
        
        -- Every payout targets the owning farm (stamped at accept), never the local
        -- player, so rewards land correctly on a dedicated server. Resolve+persist a
        -- default for any legacy favor that predates farm-attribution.
        local farmId = favor.ownerFarmId or self:resolveOwnerFarmId(favor)
        favor.ownerFarmId = farmId
        local payMoney = not favor.rewardPaid

        -- Return the loan principal to the owning farm when a loan favor completes
        -- (the NPC pays you back). Guarded by repaymentCollected so a reconnect or a
        -- double-complete cannot collect it twice. Replaces the old inline dialog payout.
        if favor.type == "loan_money" and not favor.repaymentCollected then
            local loanAmount = (favor.taskData and favor.taskData.loanAmount) or 5000
            g_currentMission:addMoney(loanAmount, farmId, MoneyType.OTHER, true)
            favor.repaymentCollected = true
        end

        -- Give money reward (guarded by rewardPaid; the perfect bonus below shares the
        -- same guard so the whole reward payout is one idempotent unit).
        if favor.reward.money and payMoney then
            g_currentMission:addMoney(favor.reward.money, farmId, MoneyType.OTHER, true)
        end

        -- Give XP (if XP system exists)
        if favor.reward.xp then
            -- Implementation depends on game's XP system
            -- Example: if g_currentMission.player.addXP then
            --     g_currentMission.player:addXP(favor.reward.xp)
            -- end
        end
        
        -- Update NPC stats
        npc.totalFavorsCompleted = (npc.totalFavorsCompleted or 0) + 1

        -- 4m: Bonus rewards for perfect completion
        -- Perfect = completed well before deadline (>50% time remaining)
        local isPerfect = false
        if favor.completionDuration and favor.expirationTime and favor.createdTime then
            local totalTime = favor.expirationTime - favor.createdTime
            local timeUsed = favor.completionDuration
            if totalTime > 0 and timeUsed < totalTime * 0.5 then
                isPerfect = true
            end
        end

        if isPerfect then
            local bonusRel = math.ceil((favor.reward.relationship or 0) * 0.5)
            local bonusMoney = math.ceil((favor.reward.money or 0) * 0.25)

            if bonusRel > 0 then
                self.npcSystem.relationshipManager:updateRelationship(
                    npc.id, bonusRel, "perfect_completion"
                )
            end
            if bonusMoney > 0 and payMoney then
                g_currentMission:addMoney(bonusMoney, farmId, MoneyType.OTHER, true)
            end

            -- Flash notification for perfect completion
            if self.npcSystem.favorHUD then
                local msg = string.format(g_i18n:getText("npc_hud_perfect") or "Perfect! %s bonus!",
                    string.format("+%d rel, +$%d", bonusRel, bonusMoney))
                self.npcSystem.favorHUD:flashFavor(msg, {1, 1, 0.3, 1})
            end

            if self.npcSystem.settings.debugMode then
                print(string.format("PERFECT favor completion bonus: +%d rel, +%d money for %s",
                    bonusRel, bonusMoney, npc.name))
            end
        end

        -- Mark the reward payout done once (covers both the reward and the perfect
        -- bonus), so a replayed completion cannot pay either a second time.
        if payMoney then
            favor.rewardPaid = true
        end

        -- Log for debugging
        if self.npcSystem.settings.debugMode then
            print(string.format("Favor rewards applied: +%d relationship, +%d money for %s%s",
                favor.reward.relationship or 0, favor.reward.money or 0, npc.name,
                isPerfect and " (PERFECT)" or ""))
        end
    end
end

function NPCFavorSystem:applyFavorPenalties(favor)
    if not favor.penalty then
        return
    end
    
    -- Find NPC
    local npc = nil
    for _, n in ipairs(self.npcSystem.activeNPCs) do
        if n.id == favor.npcId then
            npc = n
            break
        end
    end
    
    if npc then
        -- Update relationship
        if favor.penalty.relationship then
            self.npcSystem.relationshipManager:updateRelationship(
                npc.id, 
                favor.penalty.relationship,
                "favor_failed"
            )
        end
        
        -- Apply reputation penalty (if reputation system exists)
        if favor.penalty.reputation then
            -- Implementation depends on game's reputation system
        end
        
        -- Log for debugging
        if self.npcSystem.settings.debugMode then
            print(string.format("Favor penalties applied: %d relationship for %s",
                favor.penalty.relationship or 0, npc.name))
        end
    end
end

function NPCFavorSystem:updateStats(favor)
    -- Update statistics
    self.stats.totalFavorsCompleted = self.stats.totalFavorsCompleted + 1
    
    if favor.reward then
        self.stats.totalRelationshipEarned = self.stats.totalRelationshipEarned + (favor.reward.relationship or 0)
        self.stats.totalMoneyEarned = self.stats.totalMoneyEarned + (favor.reward.money or 0)
        self.stats.totalXPEarned = self.stats.totalXPEarned + (favor.reward.xp or 0)
    end
    
    -- Update fastest completion
    if favor.completionDuration then
        if not self.stats.fastestCompletion or favor.completionDuration < self.stats.fastestCompletion.duration then
            self.stats.fastestCompletion = {
                favorId = favor.id,
                npcName = favor.npcName,
                duration = favor.completionDuration,
                type = favor.type
            }
        end
        
        -- Update longest favor
        if not self.stats.longestFavor or favor.completionDuration > self.stats.longestFavor.duration then
            self.stats.longestFavor = {
                favorId = favor.id,
                npcName = favor.npcName,
                duration = favor.completionDuration,
                type = favor.type
            }
        end
    end
end

function NPCFavorSystem:getFailureReasonText(reason)
    local reasons = {
        time_expired = "Time expired",
        player_cancelled = "Cancelled by player",
        npc_unavailable = "NPC became unavailable",
        requirements_not_met = "Requirements no longer met",
        unknown = "Unknown reason"
    }
    
    return reasons[reason] or reasons.unknown
end

function NPCFavorSystem:getActiveFavors()
    return self.activeFavors
end

--- Return the pending (unaccepted) favor for a specific NPC, or nil.
function NPCFavorSystem:getPendingFavorForNPC(npcId)
    for _, favor in ipairs(self.activeFavors) do
        if favor.npcId == npcId and favor.status == "pending" then
            return favor
        end
    end
    return nil
end

--- Return the active/in-progress favor for a specific NPC, or nil.
function NPCFavorSystem:getActiveFavorForNPC(npcId)
    for _, favor in ipairs(self.activeFavors) do
        if favor.npcId == npcId and (favor.status == "active" or favor.status == "in_progress") then
            return favor
        end
    end
    return nil
end

--- Resolve the owning farm for a favor whose ownerFarmId is missing. Used to migrate
-- in-flight favors saved before farm-attribution existed, and as a defensive default.
-- Prefers the host / single-player local farm; on a dedicated server (no local player)
-- falls back to the first valid non-spectator farm, then to farm 1. Logs the default so
-- a migrated favor is traceable.
function NPCFavorSystem:resolveOwnerFarmId(favor)
    local farmId = nil
    if g_currentMission and g_currentMission.player and g_currentMission.player.farmId
        and g_currentMission.player.farmId ~= FarmManager.SPECTATOR_FARM_ID then
        farmId = g_currentMission.player.farmId
    elseif g_farmManager and g_farmManager.getFarms then
        for _, farm in ipairs(g_farmManager:getFarms()) do
            if farm.farmId and farm.farmId ~= FarmManager.SPECTATOR_FARM_ID then
                farmId = farm.farmId
                break
            end
        end
    end
    farmId = farmId or 1
    print(string.format("[NPC Favor] Favor '%s' (npc %s) had no owner farm; defaulted to farm %d",
        tostring(favor and favor.type or "?"), tostring(favor and favor.npcId or "?"), farmId))
    return farmId
end

--- Transition the pending favor for npcId to active (player has accepted it).
-- @param npcId  the NPC whose pending favor is being accepted
-- @param farmId (optional) the acting user's farm, validated server-side by
--        NPCInteractionEvent:run. Stamped as favor.ownerFarmId so every money site
--        pays the accepting farm, never the local player (nil on a dedicated server).
-- @return the favor table if found, nil otherwise
function NPCFavorSystem:acceptFavorForNPC(npcId, farmId)
    for _, favor in ipairs(self.activeFavors) do
        if favor.npcId == npcId and favor.status == "pending" then
            favor.status = "active"
            favor.startTime = TimeHelper.getGameTimeMs()
            if farmId and farmId ~= FarmManager.SPECTATOR_FARM_ID then
                favor.ownerFarmId = farmId
            elseif not favor.ownerFarmId then
                favor.ownerFarmId = self:resolveOwnerFarmId(favor)
            end
            if self.npcSystem.favorHUD then
                local msg = string.format("Favor accepted: %s", favor.description or favor.name or "")
                self.npcSystem.favorHUD:flashFavor(msg, {0.3, 1.0, 0.3, 1})
            end
            return favor
        end
    end
    return nil
end

--- Force-generate a favor specifically for a given NPC (used from the dialog).
-- Skips weighted NPC-selection and cooldown checks (player is talking to this NPC directly).
-- @param npc  NPC data table
-- @return favor table if created, nil if no eligible favor types
-- Generates a favor for a specific NPC.
-- playerInitiated: if true, the player offered help — applies personality decline chance,
-- marks the favor, and adds a 15% reward bonus.
-- Returns the created favor, or nil if the NPC already has one, has nothing eligible,
-- or (when playerInitiated) the NPC declines.
function NPCFavorSystem:generateFavorForNPC(npc, playerInitiated)
    if not npc or not npc.isActive then return nil end

    -- If this NPC already has any favor (pending or active), don't create another
    for _, favor in ipairs(self.activeFavors) do
        if favor.npcId == npc.id then return nil end
    end

    -- Personality-based decline when player proactively offers
    if playerInitiated then
        local declineChance = 0
        if npc.personality == "grumpy" then declineChance = 0.35
        elseif npc.personality == "greedy" then declineChance = 0.10
        elseif npc.personality == "generous" then declineChance = 0.05
        end
        if math.random() < declineChance then
            return "declined"  -- sentinel: caller shows personality-flavored refusal
        end
    end

    local available = {}
    for _, favorType in ipairs(self.favorTypes) do
        if self:checkFavorRequirements(npc, favorType) then
            table.insert(available, favorType)
        end
    end
    if #available == 0 then return nil end

    -- Personality + role weighted selection
    local weights = {}
    local totalWeight = 0
    local categoryBoost = NPCFavorSystem.PERSONALITY_CATEGORY_WEIGHTS[npc.personality] or {}
    local roleBoost = NPCFavorSystem.ROLE_CATEGORY_WEIGHTS[npc.role] or {}
    for _, ft in ipairs(available) do
        local w = 10 - ft.difficulty
        local pBoost = categoryBoost[ft.category]
        if pBoost then w = w * pBoost end
        local rBoost = roleBoost[ft.category]
        if rBoost then w = w * rBoost end
        weights[ft.id] = math.max(0.1, w)
        totalWeight = totalWeight + weights[ft.id]
    end

    local roll = math.random() * totalWeight
    local cum = 0
    local selectedType = available[1]
    for _, ft in ipairs(available) do
        cum = cum + weights[ft.id]
        if roll <= cum then selectedType = ft; break end
    end

    local favor = self:createFavor(npc, selectedType.id)
    if favor then
        if playerInitiated then
            favor.playerInitiated = true
            -- 15% reward bonus for player proactively offering help
            if favor.reward then
                favor.reward.relationship = math.ceil((favor.reward.relationship or 0) * 1.15)
                favor.reward.money        = math.ceil((favor.reward.money or 0) * 1.15)
            end
        end
        table.insert(self.activeFavors, favor)
        local cooldownDays = (self.npcSystem.settings and self.npcSystem.settings.favorFrequency) or 3
        npc.favorCooldown = cooldownDays * 300
    end
    return favor
end

--- Restore an active favor from saved data (called during loadFromXMLFile).
-- Reconstructs the favor structure from minimal saved fields and re-inserts it
-- into the active favors list with recalculated expiration time.
-- @param savedFavor  Table with npcId, npcName, type, description, timeRemaining, progress, reward
function NPCFavorSystem:restoreFavor(savedFavor)
    if not savedFavor or not savedFavor.type or savedFavor.type == "" then
        return
    end

    -- Look up the favor type definition
    local favorType = nil
    for _, ft in ipairs(self.favorTypes) do
        if ft.id == savedFavor.type then
            favorType = ft
            break
        end
    end

    -- Resolve NPC (id first, then name) so generateFavorSteps can use homePosition.
    -- Favors restore after NPCs on both XML and StateLedger load paths.
    local npc = nil
    if self.npcSystem and self.npcSystem.activeNPCs then
        local npcId = savedFavor.npcId
        if npcId ~= nil then
            for _, candidate in ipairs(self.npcSystem.activeNPCs) do
                if candidate.id == npcId then
                    npc = candidate
                    break
                end
            end
        end
        if not npc then
            local npcName = savedFavor.npcName
            if npcName and npcName ~= "" then
                for _, candidate in ipairs(self.npcSystem.activeNPCs) do
                    if candidate.name == npcName then
                        npc = candidate
                        break
                    end
                end
            end
        end
    end

    -- Regenerate steps (save does not persist the step list). Empty steps soft-locks
    -- progress checks, HUD next-step arrow, and Complete dialog after reload.
    local steps = {}
    if favorType then
        if not npc then
            print(string.format(
                "[NPC Favor] restoreFavor: NPC id=%s name=%s missing; regenerating steps with fallback",
                tostring(savedFavor.npcId), tostring(savedFavor.npcName)))
            npc = {
                id = savedFavor.npcId or 0,
                name = savedFavor.npcName or "",
                homePosition = nil,
                assignedField = nil,
            }
        end
        steps = self:generateFavorSteps(favorType, npc)
    else
        print(string.format(
            "[NPC Favor] restoreFavor: unknown favor type '%s'; using one-step fallback",
            tostring(savedFavor.type)))
        steps = {{id = 1, description = "Complete the task", completed = false, location = nil}}
    end

    -- Map saved progress percent onto completed step flags (same ratio as checkFavorProgress).
    -- Do not call completeFavor here even at 100% — leave confirmation / dialog paths intact.
    local n = #steps
    local savedProgress = tonumber(savedFavor.progress) or 0
    local done = 0
    if n > 0 then
        done = math.floor((savedProgress / 100) * n + 0.5)
        if done < 0 then
            done = 0
        elseif done > n then
            done = n
        end
        for i = 1, done do
            steps[i].completed = true
        end
    end

    local currentStep = 1
    if n > 0 then
        currentStep = steps[n].id or n
        for i, step in ipairs(steps) do
            if not step.completed then
                currentStep = step.id or i
                break
            end
        end
    end

    -- Resolve NPC (id first, then name) so generateFavorSteps can use homePosition.
    -- Favors restore after NPCs on both XML and StateLedger load paths.
    local npc = nil
    if self.npcSystem and self.npcSystem.activeNPCs then
        local npcId = savedFavor.npcId
        if npcId ~= nil then
            for _, candidate in ipairs(self.npcSystem.activeNPCs) do
                if candidate.id == npcId then
                    npc = candidate
                    break
                end
            end
        end
        if not npc then
            local npcName = savedFavor.npcName
            if npcName and npcName ~= "" then
                for _, candidate in ipairs(self.npcSystem.activeNPCs) do
                    if candidate.name == npcName then
                        npc = candidate
                        break
                    end
                end
            end
        end
    end

    -- Regenerate steps (save does not persist the step list). Empty steps soft-locks
    -- progress checks, HUD next-step arrow, and Complete dialog after reload.
    local steps = {}
    if favorType then
        if not npc then
            print(string.format(
                "[NPC Favor] restoreFavor: NPC id=%s name=%s missing; regenerating steps with fallback",
                tostring(savedFavor.npcId), tostring(savedFavor.npcName)))
            npc = {
                id = savedFavor.npcId or 0,
                name = savedFavor.npcName or "",
                homePosition = nil,
                assignedField = nil,
            }
        end
        steps = self:generateFavorSteps(favorType, npc)
    else
        print(string.format(
            "[NPC Favor] restoreFavor: unknown favor type '%s'; using one-step fallback",
            tostring(savedFavor.type)))
        steps = {{id = 1, description = "Complete the task", completed = false, location = nil}}
    end

    -- Map saved progress percent onto completed step flags (same ratio as checkFavorProgress).
    -- Do not call completeFavor here even at 100% — leave confirmation / dialog paths intact.
    local n = #steps
    local savedProgress = tonumber(savedFavor.progress) or 0
    local done = 0
    if n > 0 then
        done = math.floor((savedProgress / 100) * n + 0.5)
        if done < 0 then
            done = 0
        elseif done > n then
            done = n
        end
        for i = 1, done do
            steps[i].completed = true
        end
    end

    local currentStep = 1
    if n > 0 then
        currentStep = steps[n].id or n
        for i, step in ipairs(steps) do
            if not step.completed then
                currentStep = step.id or i
                break
            end
        end
    end

    local currentGameTime = TimeHelper.getGameTimeMs()

    local favor = {
        id = #self.activeFavors + #self.completedFavors + #self.failedFavors + 1,
        npcId = savedFavor.npcId or 0,
        npcName = savedFavor.npcName or "",
        type = savedFavor.type,
        name = favorType and favorType.name or savedFavor.type,
        description = savedFavor.description or (favorType and favorType.description or ""),
        difficulty = favorType and favorType.difficulty or 1,
        category = favorType and favorType.category or "misc",

        status = "active",
        progress = savedProgress,
        progressDetails = {},

        createdTime = currentGameTime,
        expirationGameTime = currentGameTime + (savedFavor.timeRemaining or 0),
        timeRemaining = savedFavor.timeRemaining or 0,
        estimatedCompletionTime = nil,

        requirements = favorType and favorType.requirements or {},
        reward = favorType and favorType.reward or (type(savedFavor.reward) == "table" and savedFavor.reward or { relationship = 10, money = tonumber(savedFavor.reward) or 0, xp = 0 }),
        penalty = favorType and favorType.penalty or { relationship = -5, reputation = -10 },

        location = nil,
        taskData = {
            loanAmount          = savedFavor.loanAmount or nil,
            loanAmountDeducted  = savedFavor.loanAmountDeducted or false,
        },
        ownerFarmId          = savedFavor.ownerFarmId,
        rewardPaid           = savedFavor.rewardPaid or false,
        repaymentCollected   = savedFavor.repaymentCollected or false,
        awaitingConfirmation = savedFavor.awaitingConfirmation or false,
        startTime = currentGameTime,
        completionTime = nil,
        completionDuration = nil,
        playerNotes = "",
        priority = 1,
        currentStep = currentStep,
        totalSteps = n > 0 and n or 1,
        steps = steps
    }

    -- Migrate legacy in-flight favors saved before farm-attribution: give them an
    -- owning farm once (logged in resolveOwnerFarmId) so their money lands correctly.
    if not favor.ownerFarmId then
        favor.ownerFarmId = self:resolveOwnerFarmId(favor)
    end

    table.insert(self.activeFavors, favor)
end

function NPCFavorSystem:getCompletedFavors()
    return self.completedFavors
end

function NPCFavorSystem:getFailedFavors()
    return self.failedFavors
end


function NPCFavorSystem:getFavorById(favorId)
    -- Check active favors
    for _, favor in ipairs(self.activeFavors) do
        if favor.id == favorId then
            return favor
        end
    end
    
    -- Check completed favors
    for _, favor in ipairs(self.completedFavors) do
        if favor.id == favorId then
            return favor
        end
    end
    
    -- Check failed favors
    for _, favor in ipairs(self.failedFavors) do
        if favor.id == favorId then
            return favor
        end
    end
    
    -- Check abandoned favors
    for _, favor in ipairs(self.abandonedFavors) do
        if favor.id == favorId then
            return favor
        end
    end
    
    return nil
end

function NPCFavorSystem:getNPCFromFavor(favorId)
    local favor = self:getFavorById(favorId)
    if not favor then
        return nil
    end

    for _, npc in ipairs(self.npcSystem.activeNPCs) do
        if npc.id == favor.npcId then
            return npc
        end
    end

    return nil
end

function NPCFavorSystem:analyzeEncounterHistory(npc)
    local result = {
        recentInteractionCount = 0,
        giftCount = 0,
        ignoredCount = 0,
        completedFavorCount = 0,
        failedFavorCount = 0,
        averageTone = 0,
        memoryScore = 0,
    }

    if not npc or not npc.encounters or #npc.encounters == 0 then
        return result
    end

    local currentTime = (g_currentMission and g_currentMission.time) or 0
    local sevenDaysMs = 7 * 24 * 60 * 60 * 1000
    local totalTone = 0
    local toneCount = 0
    local weightedScore = 0
    local totalWeight = 0

    for i, enc in ipairs(npc.encounters) do
        local age = currentTime - (enc.time or 0)
        local recencyWeight = 1.0 / i

        if age <= sevenDaysMs then
            result.recentInteractionCount = result.recentInteractionCount + 1
        end

        local encType = enc.type or ""
        if encType == "gift_given" then
            result.giftCount = result.giftCount + 1
        elseif encType == "favor_completed" then
            result.completedFavorCount = result.completedFavorCount + 1
        elseif encType == "favor_failed" then
            result.failedFavorCount = result.failedFavorCount + 1
        elseif encType == "ignored" then
            result.ignoredCount = result.ignoredCount + 1
        end

        local sentiment = enc.sentiment or "neutral"
        local toneValue = 0
        if sentiment == "positive" then
            toneValue = 1
        elseif sentiment == "negative" then
            toneValue = -1
        end
        totalTone = totalTone + toneValue
        toneCount = toneCount + 1

        local contribution = toneValue * recencyWeight
        if encType == "gift_given" or encType == "favor_completed" then
            contribution = contribution + (0.3 * recencyWeight)
        elseif encType == "favor_failed" or encType == "ignored" then
            contribution = contribution - (0.3 * recencyWeight)
        end

        weightedScore = weightedScore + contribution
        totalWeight = totalWeight + recencyWeight
    end

    if toneCount > 0 then
        result.averageTone = totalTone / toneCount
    end

    if totalWeight > 0 then
        local raw = weightedScore / totalWeight
        result.memoryScore = math.max(-1, math.min(1, raw))
    end

    return result
end

--- Fire a context-driven favor request for a specific NPC, biased toward a category.
-- Called by NPCScheduler on severe weather or other world events.
-- @param npc      Target NPC (must be active and not already have a favor)
-- @param context  String hint: "weather_emergency", "missed_delivery", or "equipment_failure"
-- @return favor table or nil
function NPCFavorSystem:triggerContextualFavor(npc, context)
    if not npc or not npc.isActive then return nil end
    if not self:canNPCRequestFavor(npc) then return nil end

    -- Category bias by context
    local urgentCategories = {
        weather_emergency  = {"repair", "fieldwork", "animal_care"},
        missed_delivery    = {"delivery", "transport"},
        equipment_failure  = {"repair", "equipment"},
    }
    local biasCategories = urgentCategories[context] or {"repair"}

    -- Build candidate list restricted to biased categories where possible
    local preferred, fallback = {}, {}
    for _, ft in ipairs(self.favorTypes) do
        if self:checkFavorRequirements(npc, ft) then
            local isPreferred = false
            for _, cat in ipairs(biasCategories) do
                if ft.category == cat then isPreferred = true; break end
            end
            if isPreferred then
                table.insert(preferred, ft)
            else
                table.insert(fallback, ft)
            end
        end
    end

    local pool = #preferred > 0 and preferred or fallback
    if #pool == 0 then return nil end

    local selectedType = pool[math.random(#pool)]
    local favor = self:createFavor(npc, selectedType.id)
    if favor then
        favor.isUrgent = true
        favor.urgentContext = context
        table.insert(self.activeFavors, favor)
        local cooldownDays = (self.npcSystem.settings and self.npcSystem.settings.favorFrequency) or 3
        npc.favorCooldown = cooldownDays * 300

        if self.npcSystem.settings and self.npcSystem.settings.debugMode then
            print(string.format("[NPC Favor] Contextual favor '%s' triggered for %s (context: %s)",
                selectedType.id, npc.name, context))
        end
    end
    return favor
end

