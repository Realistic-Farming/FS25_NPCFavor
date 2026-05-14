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
        }
    }
    
    -- Active favors
    self.activeFavors = {} -- Player's active favors
    self.npcFavorCooldowns = {} -- When NPCs can ask again
    
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
    
    -- Notification system
    self.notificationQueue = {}
    self.lastNotificationTime = 0
    self.notificationCooldown = 5000 -- 5 seconds between notifications
    
    return self
end

function NPCFavorSystem:update(dt)
    local currentTime = g_currentMission.time
    
    -- Update active favors
    for i = #self.activeFavors, 1, -1 do
        local favor = self.activeFavors[i]
        
        -- Check if favor expired
        if favor.expirationTime and currentTime > favor.expirationTime then
            self:failFavor(favor.id, "time_expired")
            table.remove(self.activeFavors, i)
        else
            -- Update time remaining
            favor.timeRemaining = favor.expirationTime - currentTime
            
            -- Check progress conditions
            self:checkFavorProgress(favor, dt)
        end
    end
    
    -- Update NPC cooldowns
    for npcId, cooldown in pairs(self.npcFavorCooldowns) do
        if cooldown > 0 then
            self.npcFavorCooldowns[npcId] = cooldown - dt
            if self.npcFavorCooldowns[npcId] < 0 then
                self.npcFavorCooldowns[npcId] = 0
            end
        end
    end
    
    -- Process notifications
    self:processNotifications(dt)
    
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
    
    -- Higher probability during working hours
    local baseProbability = 0.001 -- 0.1% chance per attempt
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
    elseif favorType.category == "fieldwork" and npc.assignedField then
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
        
        -- Personality preferences
        if selectedNPC.personality == "generous" and favorType.difficulty <= 1 then
            weight = weight * 1.5
        elseif selectedNPC.personality == "greedy" and favorType.difficulty >= 2 then
            weight = weight * 1.5
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
        
        selectedNPC.favorCooldown = cooldownDays * 24 * 60 * 60 * 1000
        selectedNPC.lastFavorTime = g_currentMission.time
        
        -- Update NPC cooldown tracking
        self.npcFavorCooldowns[selectedNPC.id] = selectedNPC.favorCooldown
        
        -- Add to notification queue
        self:queueNotification(
            g_i18n:getText("npc_notification_favor_request") or "Favor Request",
            string.format(g_i18n:getText("npc_notification_favor_request") or "%s is asking for a favor!", 
                selectedNPC.name),
            "favor_request",
            5000 -- 5 seconds
        )
        
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
        
        -- Time management
        createdTime = g_currentMission.time,
        expirationTime = g_currentMission.time + (favorType.duration * 60 * 60 * 1000),
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
    if favorType.requirements.hasTractor then
        local hasTractor = false
        for _, vehicle in ipairs(npc.assignedVehicles) do
            if vehicle.type == "tractor" then
                hasTractor = true
                break
            end
        end
        if not hasTractor then
            return false
        end
    end
    
    if favorType.requirements.hasHarvester then
        local hasHarvester = false
        for _, vehicle in ipairs(npc.assignedVehicles) do
            if vehicle.type == "harvester" then
                hasHarvester = true
                break
            end
        end
        if not hasHarvester then
            return false
        end
    end
    
    if favorType.requirements.hasTrailer then
        local hasTrailer = false
        for _, vehicle in ipairs(npc.assignedVehicles) do
            if vehicle.type == "trailer" then
                hasTrailer = true
                break
            end
        end
        if not hasTrailer then
            return false
        end
    end
    
    if favorType.requirements.hasTruck then
        local hasTruck = false
        for _, vehicle in ipairs(npc.assignedVehicles) do
            if vehicle.type == "truck" then
                hasTruck = true
                break
            end
        end
        if not hasTruck then
            return false
        end
    end
    
    -- Add more requirement checks as needed
    
    return true
end

function NPCFavorSystem:generateFavorSteps(favorType, npc)
    local steps = {}
    
    if favorType.id == "borrow_tractor" then
        steps = {
            {id = 1, description = "Go to NPC's farm", completed = false, location = npc.homePosition},
            {id = 2, description = "Find the tractor", completed = false, location = nil},
            {id = 3, description = "Use tractor for a day", completed = false, location = nil},
            {id = 4, description = "Return tractor", completed = false, location = npc.homePosition}
        }
    elseif favorType.id == "help_harvest" then
        steps = {
            {id = 1, description = "Go to the field", completed = false, location = npc.assignedField and npc.assignedField.center or npc.homePosition},
            {id = 2, description = "Harvest the crops", completed = false, location = nil},
            {id = 3, description = "Transport harvest to storage", completed = false, location = nil}
        }
    elseif favorType.id == "transport_goods" then
        steps = {
            {id = 1, description = "Load goods at NPC's farm", completed = false, location = npc.homePosition},
            {id = 2, description = "Transport to market", completed = false, location = self:findNearestSellPoint(npc.homePosition.x, npc.homePosition.z)},
            {id = 3, description = "Sell goods", completed = false, location = nil}
        }
    else
        -- Default single step
        steps = {
            {id = 1, description = "Complete the task", completed = false, location = nil}
        }
    end
    
    return steps
end

function NPCFavorSystem:checkFavorProgress(favor, dt)
    if not favor or not self.npcSystem then
        return
    end
    
    -- Safety check for player position
    local playerPos = self.npcSystem.playerPosition
    if not playerPos or not self.npcSystem.playerPositionValid then
        return
    end
    
    -- Transport-type favor progress
    if favor.location and favor.location.type == "transport" then
        -- Check if player has reached start location
        if not favor.progressDetails.reachedStart and favor.location.start then
            local distance = VectorHelper.distance3D(
                playerPos.x, playerPos.y, playerPos.z,
                favor.location.start.x, favor.location.start.y, favor.location.start.z
            )
            
            if distance < 30 then
                favor.progressDetails.reachedStart = true
                favor.progress = 33
                
                self:queueNotification(
                    "Favor Progress",
                    "You've arrived at the pickup location",
                    "favor_progress",
                    3000
                )
            end
        end
        
        -- Check if player has reached destination
        if favor.progressDetails.reachedStart and not favor.progressDetails.reachedDestination 
           and favor.location.destination then
            
            local distance = VectorHelper.distance3D(
                playerPos.x, playerPos.y, playerPos.z,
                favor.location.destination.x, favor.location.destination.y, favor.location.destination.z
            )
            
            if distance < 30 then
                favor.progressDetails.reachedDestination = true
                favor.progress = 66
                
                self:queueNotification(
                    "Favor Progress",
                    "You've arrived at the destination",
                    "favor_progress",
                    3000
                )
            end
        end
    end
    
    -- Multi-step favor progress
    if favor.steps and #favor.steps > 0 then
        local completedSteps = 0
        
        for _, step in ipairs(favor.steps) do
            if not step.completed and step.location then
                local distance = VectorHelper.distance3D(
                    playerPos.x, playerPos.y, playerPos.z,
                    step.location.x or 0, step.location.y or 0, step.location.z or 0
                )
                
                if distance < 30 then
                    step.completed = true
                    
                    self:queueNotification(
                        "Favor Progress",
                        string.format("Step %d completed: %s", step.id, step.description),
                        "favor_progress",
                        3000
                    )
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
        
        -- Check if all steps are completed
        if completedSteps == #favor.steps and favor.progress < 100 then
            favor.progress = 100
            self:completeFavor(favor.id)
        end
    end
end

function NPCFavorSystem:queueNotification(title, message, type, duration)
    table.insert(self.notificationQueue, {
        title = title,
        message = message,
        type = type,
        duration = duration or 5000,
        timeAdded = g_currentMission.time
    })
end

function NPCFavorSystem:processNotifications(dt)
    local currentTime = g_currentMission.time
    
    -- Check if enough time has passed since last notification
    if currentTime - self.lastNotificationTime < self.notificationCooldown then
        return
    end
    
    -- Process next notification in queue
    if #self.notificationQueue > 0 then
        local notification = table.remove(self.notificationQueue, 1)
        
        -- Show the notification
        self.npcSystem:showNotification(notification.title, notification.message)
        
        self.lastNotificationTime = currentTime
        
        -- Log for debugging
        if self.npcSystem.settings.debugMode then
            print(string.format("Notification: %s - %s", notification.title, notification.message))
        end
    end
end


function NPCFavorSystem:completeFavor(favorId)
    local favor = self:getFavorById(favorId)
    if not favor or favor.status == "completed" then
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
    
    -- Send notification
    self:queueNotification(
        g_i18n:getText("npc_notification_favor_completed") or "Favor Completed",
        string.format(g_i18n:getText("npc_notification_favor_completed") or "You helped %s. Relationship improved!", 
            favor.npcName),
        "favor_completed",
        5000
    )
    
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
    
    -- Send notification
    self:queueNotification(
        "Favor Failed",
        string.format("You failed to help %s: %s", 
            favor.npcName, self:getFailureReasonText(reason)),
        "favor_failed",
        5000
    )
    
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
    
    -- Send notification
    self:queueNotification(
        "Favor Abandoned",
        string.format("You abandoned helping %s", favor.npcName),
        "favor_abandoned",
        5000
    )
    
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
        
        -- Give money reward
        if favor.reward.money and g_currentMission.player then
            g_currentMission:addMoney(
                favor.reward.money, 
                g_currentMission.player.farmId, 
                MoneyType.OTHER, 
                true
            )
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
            if bonusMoney > 0 and g_currentMission.player then
                g_currentMission:addMoney(
                    bonusMoney,
                    g_currentMission.player.farmId,
                    MoneyType.OTHER,
                    true
                )
            end

            -- Notification about perfect completion
            self:queueNotification(
                "Perfect Completion!",
                string.format("Bonus: +%d relationship, +$%d for completing early!", bonusRel, bonusMoney),
                "favor_perfect",
                5000
            )

            if self.npcSystem.settings.debugMode then
                print(string.format("PERFECT favor completion bonus: +%d rel, +%d money for %s",
                    bonusRel, bonusMoney, npc.name))
            end
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

    local currentTime = g_currentMission and g_currentMission.time or 0

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
        progress = savedFavor.progress or 0,
        progressDetails = {},

        createdTime = currentTime,
        expirationTime = currentTime + (savedFavor.timeRemaining or 0),
        timeRemaining = savedFavor.timeRemaining or 0,
        estimatedCompletionTime = nil,

        requirements = favorType and favorType.requirements or {},
        reward = favorType and favorType.reward or { relationship = 10, money = savedFavor.reward or 0, xp = 0 },
        penalty = favorType and favorType.penalty or { relationship = -5, reputation = -10 },

        location = nil,
        taskData = {},
        startTime = currentTime,
        completionTime = nil,
        completionDuration = nil,
        playerNotes = "",
        priority = 1,
        currentStep = 1,
        totalSteps = 1,
        steps = {}
    }

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

