-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- Current implementation status and planned features:
--
-- PATHFINDING:
--   [x] Basic waypoint pathfinding (linear segments with variation)
--   [x] LRU path cache (50 paths, 60s cleanup cycle)
--   [x] Terrain height snapping (with fallback spiral search)
--   [x] Water detection and avoidance (reroutes to nearby land)
--   [ ] A* or navmesh pathfinding (currently uses simple linear waypoints)
--   [x] Building avoidance (NPCs steer around non-home buildings, safe positioning)
--   [x] Building avoidance in pathfinder (waypoints pushed out of building footprints)
--   [x] Steep terrain avoidance (max slope check, perpendicular rerouting, cliff blocking)
--   [x] Road-following via spline discovery (NPCs walk along roads/paths)
--   [ ] Dynamic path invalidation (if obstacle appears mid-path)
--
-- AI BEHAVIOR:
--   [x] State machine (idle, walking, working, driving, resting, socializing, traveling, gathering)
--   [x] Personality-driven decision making (hardworking, lazy, social traits)
--   [x] Player-NPC relationship tracking (affects behavior weights)
--   [x] Stuck detection and recovery (5s threshold, releases vehicle)
--   [x] Vehicle usage for long-distance travel (>100m auto-drive)
--   [x] Transport mode selection (walk/car/tractor based on distance and profession)
--   [x] Vehicle prop integration (visual car/tractor shown during commute, parked on arrival)
--   [x] Basic social interactions (NPCs find partners and face each other)
--   [x] Structured daily routine (schedule-driven AI with personality variations)
--   [x] Sleep/wake cycle (NPCs hidden at night, isSleeping flag for entity manager)
--   [x] Markov chain state transitions (transitionProbabilities used in makeAIDecision fallback)
--   [x] NPC-NPC relationships (compatibility matrix, friendship-driven social grouping)
--   [x] NPC memory system (encounter history, grudge tracking, sentiment analysis)
--   [x] Group activities (gathering, walking pairs, lunch clusters)
--   [x] Dynamic social graph (NPC-NPC relationships with compatibility drift)
--
-- ANIMATION & VISUALS:
--   [x] Animation state tracking (walk, work, rest, etc.)
--   [ ] Animation application to i3d nodes (states tracked but not rendered)
--   [ ] Animation blending (smooth transitions between walk/idle/work)
--   [ ] Facial expressions or mood indicators
--   [ ] Hand tool visuals (shovel, rake, etc. during work state)
--
-- AUDIO & FEEDBACK:
--   [x] Speech/dialogue system (NPC-NPC conversation topics shown as greeting text)
--   [ ] Sound effects (footsteps, work sounds, vehicle engine)
--   [ ] Ambient NPC chatter (background conversation sounds)
--
-- MULTIPLAYER:
--   [x] Sync dirty flag on state transitions (line 594-596)
--   [ ] Full multiplayer sync (NPC positions, states, vehicle assignments)
--   [ ] Authority resolution (what happens if two players interact with same NPC?)
--
-- PERFORMANCE:
--   [x] Path caching with LRU eviction
--   [ ] Spatial partitioning (only update NPCs near players)
--   [ ] LOD system (reduce update frequency for distant NPCs)
--   [ ] Async pathfinding (offload A* to background thread)
--
-- =========================================================
-- FS25 NPC Favor Mod - NPC AI System
-- =========================================================
-- Core AI behavior for NPC characters. Contains two classes:
--
--   NPCAI        — State machine driving NPC behavior (idle, walking,
--                  working, driving, resting, socializing, traveling,
--                  gathering). Handles decision-making, stuck detection,
--                  vehicle usage for long-distance travel, social
--                  interactions, and group formation (pairs, clusters).
--
--   NPCPathfinder — Waypoint-based pathfinding with road spline following,
--                   terrain awareness, water avoidance, and LRU path cache.
--
-- Yaw convention: FS25 uses atan2(dx, dz) where 0 = +Z (north).
-- Movement recovery: x += sin(yaw) * speed, z += cos(yaw) * speed.
-- =========================================================

NPCAI = {}
NPCAI_mt = Class(NPCAI)

--- Create a new NPCAI instance.
-- @param npcSystem  NPCSystem reference (provides settings, activeNPCs, scheduler, etc.)
-- @return NPCAI instance
function NPCAI.new(npcSystem)
    local self = setmetatable({}, NPCAI_mt)

    self.npcSystem = npcSystem       -- Back-reference to parent system
    self.pathfinder = NPCPathfinder.new()  -- Waypoint pathfinder with cache

    -- Canonical AI state constants (used as npc.aiState values)
    self.STATES = {
        IDLE = "idle",
        WALKING = "walking",
        WORKING = "working",
        DRIVING = "driving",
        RESTING = "resting",
        SOCIALIZING = "socializing",
        TRAVELING = "traveling",
        GATHERING = "gathering"
    }

    -- Markov chain transition probabilities: used as weight multipliers
    -- in the fallback decision system when the schedule doesn't apply.
    -- Key format: "fromState_to_toState"
    self.transitionProbabilities = {
        idle_to_walk = 0.3,
        idle_to_work = 0.4,
        idle_to_rest = 0.2,
        idle_to_socialize = 0.25,
        walk_to_idle = 0.1,
        walk_to_socialize = 0.15,
        work_to_idle = 0.05,
        work_to_rest = 0.1,
        rest_to_idle = 0.3,
        rest_to_walk = 0.2,
        socialize_to_idle = 0.2,
        socialize_to_walk = 0.15,
    }

    -- Movement mode speeds (m/s) — walk uses personality-based speed, run/sprint are fixed
    -- Real-world ref: walk ~1.4 m/s, jog ~3.5 m/s, sprint ~5.5 m/s
    -- Both run and sprint exceed the 2.5 m/s isRunning threshold in NPCEntity, so
    -- the run animation activates automatically. absSpeed drives playback rate variation.
    self.MOVE_SPEEDS = {
        walk    = nil,   -- uses npc.movementSpeed (personality-based 0.7-1.6)
        run     = 3.5,   -- triggers run animation (>2.5 threshold)
        sprint  = 5.5,   -- fast run, urgent movement
    }

    -- Personality-based daily schedule parameters.
    -- wake/sleep are hours (24h clock). lunchDuration in hours.
    -- workEnd is 17.5 (17:30) for all — smart departure handles actual leave time
    -- based on distance to home and commute speed.
    self.personalitySchedule = {
        hardworking = { wake = 5,    workStart = 5.5, lunchDuration = 0.5, workEnd = 17.5, sleep = 21 },
        lazy        = { wake = 7,    workStart = 8,   lunchDuration = 1.5, workEnd = 17.5, sleep = 23 },
        social      = { wake = 5.5,  workStart = 6.5, lunchDuration = 1.5, workEnd = 17.5, sleep = 22 },
        grumpy      = { wake = 5.5,  workStart = 6,   lunchDuration = 0.5, workEnd = 17.5, sleep = 21 },
        generous    = { wake = 5.5,  workStart = 6.5, lunchDuration = 1,   workEnd = 17.5, sleep = 22 },
        loner       = { wake = 6.5,  workStart = 7.5, lunchDuration = 0.75, workEnd = 17, sleep = 21.5 },
    }

    -- Default schedule for personalities not listed above
    self.defaultSchedule = { wake = 5.5, workStart = 6.5, lunchDuration = 1, workEnd = 17.5, sleep = 22 }

    return self
end

function NPCAI:update(dt)
    -- Update pathfinder
    self.pathfinder:update(dt)
end

--- Return the personality schedule table for the given NPC.
-- Falls back to self.defaultSchedule if personality is unknown.
-- @param npc  NPC data table
-- @return table  Schedule with keys: wake, workStart, lunchDuration, workEnd, sleep
function NPCAI:getPersonalitySchedule(npc)
    return self.personalitySchedule[npc.personality] or self.defaultSchedule
end

--- Calculate when this NPC should leave work to arrive home by target time.
-- Uses distance to home and evening movement speed to determine departure.
-- @param npc  NPC data table
-- @return number  Departure time as decimal hour (e.g., 16.75 = 4:45 PM)
function NPCAI:calculateDepartureTime(npc)
    local targetArrival = 17.5  -- 17:30 — sunset / end of day

    if not npc.homePosition or not npc.position then
        return targetArrival - 0.5  -- fallback: leave 30 min early
    end

    local dx = npc.homePosition.x - npc.position.x
    local dz = npc.homePosition.z - npc.position.z
    local distance = math.sqrt(dx * dx + dz * dz)

    -- Choose evening commute speed based on personality
    local commuteSpeed
    if npc.personality == "lazy" then
        commuteSpeed = self.MOVE_SPEEDS.run   -- 3.5 m/s (lazy jogs, doesn't sprint)
    elseif npc.personality == "hardworking" then
        commuteSpeed = self.MOVE_SPEEDS.run   -- 3.5 m/s (hardworking, steady jog)
    else
        -- 50/50 run or sprint for variety (seeded per NPC per day for consistency)
        local dayHash = 0
        if self.npcSystem.scheduler and self.npcSystem.scheduler.currentDay then
            dayHash = self.npcSystem.scheduler.currentDay
        end
        local npcHash = (npc.id or 0) + dayHash
        commuteSpeed = (npcHash % 2 == 0) and self.MOVE_SPEEDS.run or self.MOVE_SPEEDS.sprint
    end

    -- Store chosen speed for actual commute later
    npc._eveningCommuteSpeed = commuteSpeed

    -- Travel time in seconds, convert to hours
    -- Add 20% buffer for pathfinding detours
    local travelTimeSec = (distance / commuteSpeed) * 1.2
    local travelTimeHours = travelTimeSec / 3600

    -- Clamp: minimum 5 min, maximum 1.5 hours early
    travelTimeHours = math.max(5/60, math.min(1.5, travelTimeHours))

    local departureTime = targetArrival - travelTimeHours

    return departureTime
end

--- Determine what the NPC should be doing right now based on their
-- structured daily routine. Returns an activity string, a mapped
-- decision string, and a descriptive action string.
-- @param npc     NPC data table (needs npc.personality)
-- @param hour    Current game hour (0-23)
-- @param minute  Current game minute (0-59)
-- @return string activity, string decision, string action
--- Determine the day type based on the current game day.
-- @param day  Current game day number
-- @return string  "sunday", "saturday", or "weekday"
function NPCAI:getDayType(day)
    local dayOfWeek = (day or 1) % 7
    if dayOfWeek == 0 then return "sunday" end
    if dayOfWeek == 6 then return "saturday" end
    return "weekday"
end

function NPCAI:getScheduledActivity(npc, hour, minute)
    -- Delegate to NPCScheduler which has the canonical schedule templates.
    -- This eliminates duplicate schedule logic between NPCAI and NPCScheduler.
    if self.npcSystem and self.npcSystem.scheduler and self.npcSystem.scheduler.getActivityForCurrentTime then
        local activity = self.npcSystem.scheduler:getActivityForCurrentTime(npc)
        if activity then
            -- Map scheduler activity names to decision strings
            local activityToDecision = {
                -- Work activities
                field_preparation = "work",
                planting = "work",
                irrigation = "work",
                field_maintenance = "work",
                harvesting = "work",
                storage_work = "work",
                indoor_work = "work",
                equipment_repair = "work",
                equipment_maintenance = "work",
                planning = "work",
                work_shift = "work",
                chores = "work",
                -- Movement activities
                commute = "walk",
                commute_home = "go_home",
                -- Rest activities
                sleeping = "rest",
                sleep = "rest",
                break_heat = "rest",
                -- Social activities
                lunch_social = "socialize",
                evening_activities = "socialize",
                -- Idle activities
                personal_time = "idle",
                dinner_relax = "idle",
                leisure = "idle",
                lunch_break = "idle",
                breakfast = "idle",
                morning_routine = "idle",
            }
            local decision = activityToDecision[activity] or "idle"
            local displayAction = self.npcSystem.scheduler:getActivityDisplayName(activity) or activity
            return activity, decision, displayAction
        end
    end
    return nil, nil, nil
end

--- Check and update sleep/visibility state for an NPC.
-- Called from updateNPCState() BEFORE the state dispatch.
-- @param npc   NPC data table
-- @param hour  Current game hour (0-23)
function NPCAI:updateSleepState(npc, hour)
    local sched = self:getPersonalitySchedule(npc)
    local wake  = sched.wake
    local sleep = sched.sleep

    local shouldSleep = false
    if sleep >= 24 then
        shouldSleep = (hour < wake)
    else
        shouldSleep = (hour >= sleep or hour < wake)
    end

    if shouldSleep then
        if not npc.isSleeping then
            npc.isSleeping = true
            npc.canInteract = false  -- Prevent interaction while sleeping
            self:setState(npc, self.STATES.RESTING)
            npc.currentAction = "sleeping"

            -- Move NPC to their home position (go inside for the night)
            if npc.homePosition then
                npc.position.x = npc.homePosition.x
                npc.position.y = npc.homePosition.y or npc.position.y
                npc.position.z = npc.homePosition.z
            end

            -- Clear any active path (they're home now)
            npc.path = nil
            npc.targetPosition = nil

            -- Stop any active driving immediately. Without this, an NPC who falls
            -- asleep mid-commute leaves their real car running the base game's
            -- AI drive task with no one home to release it — the orphan-vehicle
            -- sweep in NPCSystem catches it ~15s later, but until then the
            -- engine keeps ticking AITaskDriveTo on a vehicle this NPC has
            -- already abandoned, which is what crashes AITaskDriveTo:update.
            npc.driveDestination = nil
            npc.driveCallback = nil
            if npc.currentVehicle then
                -- Tell the engine to stop the AI drive task so AITaskDriveTo
                -- won't crash later trying to index a nil vehicle reference.
                pcall(function()
                    if npc.currentVehicle.stopAI then
                        npc.currentVehicle:stopAI()
                    end
                end)
                npc.currentVehicle.isAvailable = true
                npc.currentVehicle.currentTask = nil
                npc.currentVehicle.driver = nil
                npc.currentVehicle = nil
            end
            if npc.realCar and self.npcSystem and self.npcSystem.removeNPCCar then
                pcall(function() self.npcSystem:removeNPCCar(npc) end)
            end

            if self.npcSystem.settings.debugMode then
                print(string.format("[NPC Favor] %s is going to sleep at home (hour=%d)", npc.name, hour))
            end
        end
    else
        if npc.isSleeping then
            npc.isSleeping = false
            -- Restore NPC visibility on wake
            local entityMgr = self.npcSystem.entityManager
            if entityMgr then
                local entity = entityMgr.npcEntities and entityMgr.npcEntities[npc.id]
                if entity and entity.node then
                    pcall(function() setVisibility(entity.node, true) end)
                end
                if entity and entity.isAnimatedCharacter and entity.humanModel and entity.humanModel.rootNode then
                    pcall(function() setVisibility(entity.humanModel.rootNode, true) end)
                end
            end
            self:setState(npc, self.STATES.IDLE)
            npc.currentAction = "waking up"
            if self.npcSystem.settings.debugMode then
                print(string.format("[NPC Favor] %s is waking up (hour=%d)", npc.name, hour))
            end
        end
    end
end

--- Per-frame AI update for a single NPC: sleep check, stuck detection, state dispatch.
-- @param npc  NPC data table (position, aiState, stuckTimer, etc.)
-- @param dt   Delta time in seconds
function NPCAI:updateNPCState(npc, dt)
    -- Sleep/wake check BEFORE state dispatch (controls visibility)
    local hour = self.npcSystem.scheduler:getCurrentHour()
    self:updateSleepState(npc, hour)

    -- If NPC is sleeping, reduce energy/hunger but skip other AI
    if npc.isSleeping then
        npc.currentAction = "sleeping"
        npc.stateTimer = (npc.stateTimer or 0) + dt
        if npc.needs then
            npc.needs.energy = math.max(0, npc.needs.energy - dt * 0.8)
            npc.needs.hunger = math.min(100, npc.needs.hunger + dt * 0.02)
        end
        return
    end

    -- Update needs system (runs every frame, lightweight)
    self:updateNeeds(npc, dt)

    -- SAFETY NET: If it's very late (23:00+) or very early (<4:00) and NPC is NOT
    -- sleeping and NOT in a special event, force them home and hidden.
    -- This prevents NPCs standing in fields at night due to stuck states.
    local inEvent = (self.npcSystem.eventScheduler and self.npcSystem.eventScheduler.activeEvent ~= nil)
    if not inEvent and (hour >= 23 or hour < 4) then
        -- Check if NPC is far from home
        local homeX = npc.homePosition and npc.homePosition.x or npc.position.x
        local homeZ = npc.homePosition and npc.homePosition.z or npc.position.z
        local dx = npc.position.x - homeX
        local dz = npc.position.z - homeZ
        local distFromHome = math.sqrt(dx * dx + dz * dz)

        if distFromHome > 20 then
            -- Teleport NPC home and force sleep
            npc.position.x = homeX
            npc.position.y = npc.homePosition and npc.homePosition.y or npc.position.y
            npc.position.z = homeZ
            npc.isSleeping = true
            self:setState(npc, self.STATES.RESTING)
            npc.currentAction = "sleeping"
            npc.path = nil
            npc.fieldWorkPath = nil
            npc.fieldWorkIndex = nil

            -- Stop any active AI job
            if npc.activeAIJob and self.npcSystem and self.npcSystem.stopNPCFieldWork then
                pcall(function() self.npcSystem:stopNPCFieldWork(npc) end)
            end

            -- Stop any active commute car too — same reasoning as updateSleepState:
            -- an un-released car keeps running the base game's AI drive task
            -- after this NPC has already moved on, which crashes AITaskDriveTo.
            npc.driveDestination = nil
            npc.driveCallback = nil
            if npc.currentVehicle then
                pcall(function()
                    if npc.currentVehicle.stopAI then
                        npc.currentVehicle:stopAI()
                    end
                end)
                npc.currentVehicle.isAvailable = true
                npc.currentVehicle.currentTask = nil
                npc.currentVehicle.driver = nil
                npc.currentVehicle = nil
            end
            if npc.realCar and self.npcSystem and self.npcSystem.removeNPCCar then
                pcall(function() self.npcSystem:removeNPCCar(npc) end)
            end

            if self.npcSystem.settings.debugMode then
                print(string.format("[NPC Favor] SAFETY NET: %s was %.0fm from home at %d:00 — teleported home",
                    npc.name or "?", distFromHome, hour))
            end
            return
        end
    end

    -- If NPC is talking to player (dialog open), freeze in place
    if npc.isTalking then
        npc.currentAction = "talking"
        npc.aiState = self.STATES.IDLE
        return
    end

    -- Only check stuck for movement states (idle/working/resting/socializing/gathering are MEANT to be stationary)
    local state = npc.aiState
    if state == self.STATES.WALKING or state == self.STATES.TRAVELING or state == self.STATES.DRIVING then
        if self:isNPCStuck(npc, dt) then
            self:handleStuckNPC(npc)
        end
    else
        -- Reset stuck timer for stationary states so it doesn't accumulate
        npc.stuckTimer = 0
    end

    -- Check current state and update accordingly
    if npc.aiState == self.STATES.IDLE then
        self:updateIdleState(npc, dt)
    elseif npc.aiState == self.STATES.WALKING then
        self:updateWalkingState(npc, dt)
    elseif npc.aiState == self.STATES.WORKING then
        self:updateWorkingState(npc, dt)
    elseif npc.aiState == self.STATES.DRIVING then
        self:updateDrivingState(npc, dt)
    elseif npc.aiState == self.STATES.RESTING then
        self:updateRestingState(npc, dt)
    elseif npc.aiState == self.STATES.SOCIALIZING then
        self:updateSocializingState(npc, dt)
    elseif npc.aiState == self.STATES.TRAVELING then
        self:updateTravelingState(npc, dt)
    elseif npc.aiState == self.STATES.GATHERING then
        self:updateGatheringState(npc, dt)
    end

    -- Player interaction checks (greeting and vehicle dodge)
    local playerPos = self.npcSystem.playerPosition
    local playerValid = self.npcSystem.playerPositionValid
    if playerValid and playerPos then
        pcall(function()
            self:checkPlayerGreeting(npc, playerPos, dt)
        end)
        pcall(function()
            self:checkVehicleReaction(npc, playerPos, dt)
        end)
    end

    -- Update dodge timer (NPC stepping aside from vehicle)
    if npc.dodgeTimer and npc.dodgeTimer > 0 then
        npc.dodgeTimer = npc.dodgeTimer - dt
        if npc.dodgeTimer <= 0 then
            npc.dodgeTimer = 0
            -- Resume normal action after dodge
            if npc.currentAction == "stepping aside" then
                npc.currentAction = npc.aiState
            end
        end
    end

    -- Update greeting timer
    if npc.greetingTimer and npc.greetingTimer > 0 then
        npc.greetingTimer = npc.greetingTimer - dt
        if npc.greetingTimer <= 0 then
            npc.greetingTimer = 0
            npc.greetingText = nil
            -- Restore action after greeting
            if npc.currentAction == "greeting" then
                npc.currentAction = npc.aiState
            end
        end
    end

    -- Update current action display from daily schedule
    -- Don't overwrite gathering, greeting, or dodge actions while active
    if npc.aiState ~= self.STATES.GATHERING
       and npc.currentAction ~= "greeting"
       and npc.currentAction ~= "stepping aside" then
        local minute = self.npcSystem.scheduler:getCurrentMinute()
        local _, _, schedAction = self:getScheduledActivity(npc, hour, minute)
        if schedAction then
            npc.currentAction = schedAction
        else
            npc.currentAction = npc.aiState
        end
    end

    -- Update state timer
    npc.stateTimer = (npc.stateTimer or 0) + dt

    -- =============================================
    -- CENTRALIZED POST-MOVEMENT VALIDATION
    -- Applied AFTER all state updates, catches ALL movement sources.
    -- This is the single choke point for building avoidance + cliff prevention.
    -- =============================================

    -- Track previous position for movement-based checks
    local prevX = npc._prevFrameX or npc.position.x
    local prevZ = npc._prevFrameZ or npc.position.z
    local movedX = npc.position.x - prevX
    local movedZ = npc.position.z - prevZ
    local movedDist = math.sqrt(movedX * movedX + movedZ * movedZ)

    -- 1) CLIFF PREVENTION: look ahead 3m in movement direction.
    --    If terrain rises >3m over 3m horizontal, block the movement.
    if movedDist > 0.001 and g_currentMission and g_currentMission.terrainRootNode then
        local dirX = movedX / movedDist
        local dirZ = movedZ / movedDist
        local lookAhead = 3.0  -- sample 3 meters ahead, not just the frame step

        local okCur, curY = pcall(getTerrainHeightAtWorldPos,
            g_currentMission.terrainRootNode, prevX, 0, prevZ)
        local aheadX = npc.position.x + dirX * lookAhead
        local aheadZ = npc.position.z + dirZ * lookAhead
        local okAhead, aheadY = pcall(getTerrainHeightAtWorldPos,
            g_currentMission.terrainRootNode, aheadX, 0, aheadZ)

        if okCur and curY and okAhead and aheadY then
            local rise = aheadY - curY
            -- Block if terrain rises more than 3m over the look-ahead distance (slope > 1.0)
            if rise > 3.0 then
                -- Revert to previous position — don't walk up the cliff
                npc.position.x = prevX
                npc.position.z = prevZ

                -- Try to redirect: find a direction that's not steep
                local bestX, bestZ = prevX, prevZ
                local bestRise = 999
                -- Try 8 compass directions
                for angle = 0, 7 do
                    local testAngle = angle * math.pi / 4
                    local testX = prevX + math.sin(testAngle) * 2
                    local testZ = prevZ + math.cos(testAngle) * 2
                    local okT, testY = pcall(getTerrainHeightAtWorldPos,
                        g_currentMission.terrainRootNode, testX, 0, testZ)
                    if okT and testY then
                        local testRise = testY - curY
                        if testRise < bestRise and testRise < 2.0 then
                            bestRise = testRise
                            bestX = testX
                            bestZ = testZ
                        end
                    end
                end

                if bestRise < 2.0 then
                    -- Move in the gentler direction instead
                    npc.position.x = bestX
                    npc.position.z = bestZ
                end

                -- Skip current waypoint if we have a path (it's probably on top of the cliff)
                if npc.path and #npc.path > 0 then
                    local wp = npc.path[1]
                    local okWP, wpY = pcall(getTerrainHeightAtWorldPos,
                        g_currentMission.terrainRootNode, wp.x, 0, wp.z)
                    if okWP and wpY and curY and (wpY - curY) > 3.0 then
                        table.remove(npc.path, 1)
                    end
                end
            end
        end
    end

    -- 2) BUILDING COLLISION: push NPC out of any non-home building every frame.
    --    This is the universal safety net — catches ALL movement sources.
    if self.npcSystem and self.npcSystem.classifiedBuildings then
        for _, entries in pairs(self.npcSystem.classifiedBuildings) do
            for _, building in ipairs(entries) do
                if building.placeable ~= npc.homeBuilding then
                    local bDx = npc.position.x - building.x
                    local bDz = npc.position.z - building.z
                    local bDist = math.sqrt(bDx * bDx + bDz * bDz)
                    local collisionRadius = (building.radius or 5) + 1  -- 1m margin

                    if bDist < collisionRadius and bDist > 0.1 then
                        -- Push NPC to the edge of the building radius
                        local pushDist = collisionRadius - bDist + 0.5  -- extra 0.5m clearance
                        local normX = bDx / bDist
                        local normZ = bDz / bDist
                        npc.position.x = npc.position.x + normX * pushDist
                        npc.position.z = npc.position.z + normZ * pushDist
                    elseif bDist <= 0.1 then
                        -- Dead center of building — escape in random direction
                        local angle = math.random() * math.pi * 2
                        npc.position.x = building.x + math.cos(angle) * (collisionRadius + 1)
                        npc.position.z = building.z + math.sin(angle) * (collisionRadius + 1)
                    end
                end
            end
        end
    end

    -- Save position for next frame's movement tracking
    npc._prevFrameX = npc.position.x
    npc._prevFrameZ = npc.position.z

    -- Universal terrain height snap: ensure EVERY NPC is grounded every frame
    -- regardless of AI state. Fixes NPCs floating/sinking on hilly terrain.
    if g_currentMission and g_currentMission.terrainRootNode then
        local okY, terrainH = pcall(getTerrainHeightAtWorldPos,
            g_currentMission.terrainRootNode, npc.position.x, 0, npc.position.z)
        if okY and terrainH then
            npc.position.y = terrainH + 0.05
        end
    end
end

function NPCAI:isNPCStuck(npc, dt)
    if not npc.lastPosition then
        npc.lastPosition = {x = npc.position.x, y = npc.position.y, z = npc.position.z}
        npc.stuckTimer = 0
        return false
    end
    
    local distance = VectorHelper.distance3D(
        npc.position.x, npc.position.y, npc.position.z,
        npc.lastPosition.x, npc.lastPosition.y, npc.lastPosition.z
    )
    
    if distance < 0.1 then
        npc.stuckTimer = (npc.stuckTimer or 0) + dt
    else
        npc.stuckTimer = 0
        npc.lastPosition = {x = npc.position.x, y = npc.position.y, z = npc.position.z}
    end
    
    return npc.stuckTimer > 5.0 -- Stuck if not moving for 5 seconds
end

--- Reset a stuck NPC: release vehicle, clear drive state, reset to IDLE.
-- @param npc  NPC data table
function NPCAI:handleStuckNPC(npc)
    if self.npcSystem.settings.debugMode then
        print(string.format("[NPC Favor] NPC %s stuck at (%.1f, %.1f, %.1f), resetting to idle",
            npc.name, npc.position.x, npc.position.y, npc.position.z))
    end

    -- Hide any active vehicle props before releasing the vehicle
    if npc.transportMode then
        local entityMgr = self.npcSystem.entityManager
        if entityMgr then
            if npc.transportMode == "drive_car" then
                pcall(function() entityMgr:showVehicleProp(npc, false) end)
            elseif npc.transportMode == "drive_tractor" then
                pcall(function() entityMgr:showTractorProp(npc, false) end)
            end
        end
        npc.transportMode = nil
        npc.driveSpeed = nil
    end

    -- Release vehicle if driving (prevents permanent vehicle lock)
    if npc.currentVehicle then
        self:stopDriving(npc, true)
    end

    -- Clear drive state (prevents orphaned callbacks)
    npc.driveDestination = nil
    npc.driveCallback = nil

    -- SECOND SAFETY NET: if stopDriving missed it for any reason, make sure
    -- the vehicle's AI task is explicitly terminated so AITaskDriveTo
    -- doesn't crash on a nil vehicle reference.
    if npc.currentVehicle then
        pcall(function()
            if npc.currentVehicle.stopAI then
                npc.currentVehicle:stopAI()
            end
        end)
        npc.currentVehicle.isAvailable = true
        npc.currentVehicle.currentTask = nil
        npc.currentVehicle.driver = nil
        npc.currentVehicle = nil
    end

    -- Reset to idle
    self:setState(npc, self.STATES.IDLE)

    -- Clear path
    npc.path = nil
    npc.targetPosition = nil

    -- Reset stuck timer
    npc.stuckTimer = 0
end

function NPCAI:updateIdleState(npc, dt)
    -- Building avoidance: if idle inside a non-home building, push outside
    if not npc._buildingCheckDone then
        local safeX, safeZ = self.npcSystem:getSafePosition(
            npc.position.x, npc.position.z, npc.homeBuilding)
        if safeX ~= npc.position.x or safeZ ~= npc.position.z then
            npc.position.x = safeX
            npc.position.z = safeZ
        end
        npc._buildingCheckDone = true
    end

    -- Personality-specific idle micro-behaviors (visual differentiation)
    self:updateIdleBehavior(npc, dt)

    -- NPC is idle, decide what to do next
    npc.idleTimer = (npc.idleTimer or 0) + dt

    -- Personality-specific idle duration before next decision
    local maxIdleTime = 3
    if npc.personality == "lazy" then
        maxIdleTime = 6       -- lazy NPCs stand around 2x longer
    elseif npc.personality == "hardworking" then
        maxIdleTime = 1.5     -- hardworking NPCs get restless fast
    elseif npc.personality == "social" then
        maxIdleTime = 2       -- social NPCs look for company quickly
    elseif npc.personality == "grumpy" then
        maxIdleTime = 4       -- grumpy NPCs linger but impatiently
    end

    if npc.idleTimer > maxIdleTime then
        npc.idleTimer = 0

        -- Decide next action: schedule-first, then weighted-random fallback
        local hour = self.npcSystem.scheduler:getCurrentHour()
        local minute = self.npcSystem.scheduler:getCurrentMinute()
        local timeOfDay = TimeHelper.getTimeOfDay(hour)

        local decision = self:makeAIDecision(npc, hour, timeOfDay)

        if decision == "work" and npc.assignedField then
            self:startWorking(npc)
        elseif decision == "walk" then
            -- During commute hours, try to form a walking pair
            if (hour >= 7 and hour < 8) or (hour >= 17 and hour < 18) then
                self:tryFormWalkingPair(npc)
            end
            -- Morning walks stay close to home
            local _, _, schedAction = self:getScheduledActivity(npc, hour, minute)
            local walkRange = 100
            if schedAction == "morning walk" then
                walkRange = 30
            elseif schedAction == "evening stroll" then
                walkRange = 50
            end
            self:startWalkingToRandomLocation(npc, walkRange)
        elseif decision == "socialize" then
            -- During lunch hour, try lunch cluster first
            local grouped = false
            if hour >= 12 and hour < 13 then
                grouped = self:tryFormLunchCluster(npc, hour)
            end
            if not grouped then
                grouped = self:tryFormGroup(npc)
            end
            if not grouped then
                local otherNPC = self:findSocialPartner(npc)
                if otherNPC then
                    self:startSocializing(npc, otherNPC)
                else
                    self:startWalkingToRandomLocation(npc, 50)
                end
            end
        elseif decision == "go_home" then
            self:goHome(npc)
        elseif decision == "rest" then
            self:setState(npc, self.STATES.RESTING)
        else
            -- Default: stay idle, wait a bit before next decision
            npc.idleTimer = maxIdleTime * 0.5
        end
    end
end

--- Update NPC needs based on current state and personality.
-- 4 needs (0 = satisfied, 100 = desperate):
--   energy: rises while awake, drops while sleeping
--   social: rises while alone, drops while socializing
--   hunger: rises over time, drops during meal slots
--   workSatisfaction: rises from working, drops from idle
-- Personality modifiers:
--   hardworking: gets work-unsatisfied faster when idle
--   lazy: energy drains faster (tires easily)
--   social: gets lonely faster when alone
-- @param npc  NPC data table
-- @param dt   Delta time in seconds
function NPCAI:updateNeeds(npc, dt)
    if not npc.needs then return end

    local state = npc.aiState
    local personality = npc.personality or "generous"

    -- Base rates (per second of real time)
    local energyRate = 0.08      -- fatigue accumulation while awake
    local socialRate = 0.06      -- loneliness while alone
    local hungerRate = 0.04      -- hunger over time
    local workSatRate = -0.03    -- work satisfaction decay when not working

    -- State-specific adjustments
    if state == self.STATES.WORKING then
        energyRate = 0.15         -- working is tiring
        workSatRate = -0.2        -- working satisfies work need (negative = decrease)
    elseif state == self.STATES.SOCIALIZING or state == self.STATES.GATHERING then
        socialRate = -0.3         -- socializing satisfies social need
        energyRate = 0.05         -- socializing is less tiring
    elseif state == self.STATES.RESTING then
        energyRate = -0.15        -- resting recovers energy
    elseif state == self.STATES.WALKING or state == self.STATES.TRAVELING then
        energyRate = 0.1
    end

    -- Check if it's a meal slot
    local hour = self.npcSystem.scheduler:getCurrentHour()
    local sched = self:getPersonalitySchedule(npc)
    local lunchStart = 12
    local lunchEnd = 12 + (sched.lunchDuration or 1)
    if hour >= lunchStart and hour < lunchEnd then
        hungerRate = -0.5         -- eating reduces hunger
    end

    -- Personality modifiers
    if personality == "hardworking" then
        workSatRate = workSatRate * 1.5  -- gets unsatisfied faster when idle
    elseif personality == "lazy" then
        energyRate = energyRate * 1.4    -- tires more quickly
        workSatRate = workSatRate * 0.5  -- doesn't care much about work
    elseif personality == "social" then
        socialRate = socialRate * 1.5    -- gets lonely faster
    elseif personality == "grumpy" then
        socialRate = socialRate * 0.5    -- doesn't mind being alone
    end

    -- Apply rates
    npc.needs.energy = math.max(0, math.min(100, npc.needs.energy + energyRate * dt))
    npc.needs.social = math.max(0, math.min(100, npc.needs.social + socialRate * dt))
    npc.needs.hunger = math.max(0, math.min(100, npc.needs.hunger + hungerRate * dt))
    npc.needs.workSatisfaction = math.max(0, math.min(100, npc.needs.workSatisfaction - workSatRate * dt))

    -- Update mood from needs
    self:updateMood(npc)
end

--- Derive NPC mood from their current needs.
-- Mood affects movement speed, social behavior, and greeting tone.
-- @param npc  NPC data table with needs
function NPCAI:updateMood(npc)
    if not npc.needs then return end

    -- Average of all needs (lower = more satisfied = happier)
    local avg = (npc.needs.energy + npc.needs.social + npc.needs.hunger +
                 (100 - npc.needs.workSatisfaction)) / 4

    local oldMood = npc.mood
    if avg < 30 then
        npc.mood = "happy"
    elseif avg < 60 then
        npc.mood = "neutral"
    elseif avg < 80 then
        npc.mood = "stressed"
    else
        npc.mood = "tired"
    end

    -- Apply mood-based speed modifier (clamped to +/- 20%)
    if npc.mood ~= oldMood and not npc._originalSpeed then
        if npc.mood == "happy" then
            npc.movementSpeed = npc.movementSpeed * 1.1
        elseif npc.mood == "tired" then
            npc.movementSpeed = npc.movementSpeed * 0.85
        end
    end
end

--- Personality-specific idle micro-behaviors for visual differentiation.
-- Social: slow rotation scanning for nearby NPCs
-- Hardworking: micro-pacing (small position shifts, fidgeting)
-- Lazy: no movement, extended stillness
-- Grumpy: face away from nearest NPC
-- @param npc  NPC data table
-- @param dt   Delta time in seconds
function NPCAI:updateIdleBehavior(npc, dt)
    npc._idleBehaviorTimer = (npc._idleBehaviorTimer or 0) + dt

    if npc.personality == "social" then
        -- Slow rotation scanning: look around for other NPCs every 2s
        if npc._idleBehaviorTimer > 2 then
            npc._idleBehaviorTimer = 0
            local scanAngle = (math.random() - 0.5) * math.pi * 0.5 -- +/- 45 degrees
            npc.rotation.y = npc.rotation.y + scanAngle
        end

    elseif npc.personality == "hardworking" then
        -- Micro-pacing: small position shifts every 1.5s (fidgeting)
        if npc._idleBehaviorTimer > 1.5 then
            npc._idleBehaviorTimer = 0
            local shift = 0.3
            npc.position.x = npc.position.x + (math.random() - 0.5) * shift
            npc.position.z = npc.position.z + (math.random() - 0.5) * shift
            -- Small rotation too
            npc.rotation.y = npc.rotation.y + (math.random() - 0.5) * 0.3
        end

    elseif npc.personality == "grumpy" then
        -- Face away from nearest NPC (antisocial body language)
        if npc._idleBehaviorTimer > 3 then
            npc._idleBehaviorTimer = 0
            local nearestDist = math.huge
            local nearestDx, nearestDz = 0, 0
            for _, otherNPC in ipairs(self.npcSystem.activeNPCs) do
                if otherNPC.id ~= npc.id and otherNPC.isActive then
                    local dx = otherNPC.position.x - npc.position.x
                    local dz = otherNPC.position.z - npc.position.z
                    local dist = math.sqrt(dx * dx + dz * dz)
                    if dist < nearestDist and dist < 20 then
                        nearestDist = dist
                        nearestDx = dx
                        nearestDz = dz
                    end
                end
            end
            if nearestDist < 20 then
                -- Face AWAY from nearest NPC
                npc.rotation.y = math.atan2(-nearestDx, -nearestDz)
            end
        end

    -- lazy: intentionally no micro-behavior (extended stillness IS the behavior)
    end
end

--- Decision for what an idle NPC should do next.
-- First checks the structured daily schedule via getScheduledActivity().
-- If a schedule slot matches, returns the mapped decision directly.
-- Falls through to the legacy weighted-random system only when no
-- schedule activity applies (e.g. unrecognized personality edge case).
-- @param npc       NPC data table
-- @param hour      Current game hour (0-23)
-- @param timeOfDay Time-of-day string from TimeHelper ("morning", "afternoon", etc.)
-- @return string   Decision key: "work", "walk", "socialize", "rest", "go_home", or "idle"
function NPCAI:makeAIDecision(npc, hour, timeOfDay)
    -- ---- Weather override: seek shelter in rain/storm ----
    local weatherFactor = 1.0
    if self.npcSystem.scheduler and self.npcSystem.scheduler.getWeatherFactor then
        weatherFactor = self.npcSystem.scheduler:getWeatherFactor()
    end
    if weatherFactor <= 0.5 then
        -- Storm or heavy rain: go home unless already working (hardworking push through)
        if npc.personality ~= "hardworking" or weatherFactor <= 0.3 then
            return "go_home"
        end
    elseif weatherFactor <= 0.7 then
        -- Light rain: 50% chance to go home if scheduled to walk
        local minute = self.npcSystem.scheduler:getCurrentMinute()
        local _, scheduledDecision, _ = self:getScheduledActivity(npc, hour, minute)
        if scheduledDecision == "walk" and math.random() < 0.5 then
            return "go_home"
        end
    end

    -- ---- Needs-based emergency override (threshold > 80) ----
    -- This preserves schedule-driven behavior 90%+ of the time,
    -- but allows occasional emergent deviations when needs are critical.
    if npc.needs then
        if npc.needs.energy > 80 then
            return "rest"  -- exhausted, must rest
        end
        if npc.needs.social > 80 and npc.personality ~= "grumpy" and npc.personality ~= "loner" then
            return "socialize"  -- desperately lonely
        end
        if npc.needs.hunger > 80 then
            return "go_home"  -- starving, go eat
        end
    end

    -- ---- Primary: structured daily schedule ----
    local minute = self.npcSystem.scheduler:getCurrentMinute()
    local activity, scheduledDecision, _ = self:getScheduledActivity(npc, hour, minute)

    if activity and scheduledDecision then
        -- Schedule says what to do; return the mapped decision
        return scheduledDecision
    end

    -- ---- Fallback: weighted-random selection with Markov influence ----
    local decisions = {}
    local weights = {}

    if hour >= 6 and hour < 18 then
        table.insert(decisions, "work")
        weights["work"] = 40
        table.insert(decisions, "walk")
        weights["walk"] = 30
        table.insert(decisions, "socialize")
        weights["socialize"] = 20
        table.insert(decisions, "rest")
        weights["rest"] = 10
    else
        table.insert(decisions, "go_home")
        weights["go_home"] = 60
        table.insert(decisions, "rest")
        weights["rest"] = 30
        table.insert(decisions, "walk")
        weights["walk"] = 10
    end

    -- Apply Markov chain transition weights based on current state
    local currentState = npc.aiState or "idle"
    for _, decision in ipairs(decisions) do
        local transKey = currentState .. "_to_" .. decision
        local transProb = self.transitionProbabilities[transKey]
        if transProb then
            weights[decision] = (weights[decision] or 0) * (1 + transProb)
        end
    end

    -- Personality modifiers
    if npc.personality == "hardworking" then
        weights["work"] = (weights["work"] or 0) * 2
        weights["rest"] = (weights["rest"] or 0) * 0.5
    elseif npc.personality == "lazy" then
        weights["work"] = (weights["work"] or 0) * 0.5
        weights["rest"] = (weights["rest"] or 0) * 2
    elseif npc.personality == "social" then
        weights["socialize"] = (weights["socialize"] or 0) * 2
    elseif npc.personality == "grumpy" then
        weights["socialize"] = (weights["socialize"] or 0) * 0.4
    end

    -- 4a: Mood-based weight modifiers
    if npc.mood then
        if npc.mood == "happy" then
            weights["socialize"] = (weights["socialize"] or 0) * 1.4
            weights["walk"] = (weights["walk"] or 0) * 1.3
        elseif npc.mood == "stressed" then
            weights["socialize"] = (weights["socialize"] or 0) * 0.5
            weights["go_home"] = (weights["go_home"] or 0) * 1.5
        elseif npc.mood == "tired" then
            weights["rest"] = (weights["rest"] or 0) * 2
            weights["work"] = (weights["work"] or 0) * 0.5
        end
    end

    -- Needs-based weight adjustments (below emergency threshold)
    if npc.needs then
        if npc.needs.energy > 50 then
            weights["rest"] = (weights["rest"] or 0) * (1 + npc.needs.energy / 100)
        end
        if npc.needs.social > 50 then
            weights["socialize"] = (weights["socialize"] or 0) * (1 + npc.needs.social / 100)
        end
        if npc.needs.workSatisfaction < 30 then
            weights["work"] = (weights["work"] or 0) * 1.5
        end
    end

    -- Relationship with player affects behavior
    if npc.relationship > 70 then
        weights["walk"] = (weights["walk"] or 0) * 1.5
    end

    -- Weighted random selection
    local totalWeight = 0
    for _, weight in pairs(weights) do
        totalWeight = totalWeight + weight
    end

    local randomValue = math.random() * totalWeight
    local currentWeight = 0

    for _, decision in ipairs(decisions) do
        currentWeight = currentWeight + (weights[decision] or 0)
        if randomValue <= currentWeight then
            return decision
        end
    end

    return "idle"
end

--- Find nearby idle/walking NPCs to socialize with.
-- Returns multiple NPCs when available so the caller can decide whether
-- to form a group, a pair, or fall back to solo socializing.
-- @param npc        The NPC looking for social partners
-- @param maxRange   Maximum search distance (default 50)
-- @return table     Array of suitable partner NPCs (may be empty)
function NPCAI:findSocialPartners(npc, maxRange)
    maxRange = maxRange or 50
    local partners = {}

    for _, otherNPC in ipairs(self.npcSystem.activeNPCs) do
        if otherNPC.id ~= npc.id and otherNPC.isActive then
            local distance = VectorHelper.distance3D(
                npc.position.x, npc.position.y, npc.position.z,
                otherNPC.position.x, otherNPC.position.y, otherNPC.position.z
            )

            -- Check if other NPC is close enough and willing to socialize
            if distance < maxRange then
                -- 4c: Friends always accepted; others use personality/mood check
                local isFriend = false
                if self.npcSystem.relationshipManager then
                    local relVal = self.npcSystem.relationshipManager:getNPCNPCValue(npc.id, otherNPC.id)
                    isFriend = relVal and relVal > 60
                end
                -- Stressed NPCs avoid socializing; friends override
                local moodWilling = (otherNPC.mood ~= "stressed") or isFriend
                local personalityWilling = otherNPC.personality == "social" or isFriend or math.random() < 0.3

                if moodWilling and personalityWilling then
                    if otherNPC.aiState == self.STATES.IDLE or otherNPC.aiState == self.STATES.WALKING then
                        table.insert(partners, otherNPC)
                    end
                end
            end
        end
    end

    -- Sort partners by NPC-NPC relationship value (friends first)
    if #partners > 1 and self.npcSystem.relationshipManager then
        local rm = self.npcSystem.relationshipManager
        table.sort(partners, function(a, b)
            local relA = rm:getNPCNPCValue(npc.id, a.id)
            local relB = rm:getNPCNPCValue(npc.id, b.id)
            return relA > relB
        end)
    end

    return partners
end

--- Convenience wrapper: returns a single social partner (backwards compatible).
-- @param npc  The NPC looking for a social partner
-- @return NPC table or nil if no suitable partner found
function NPCAI:findSocialPartner(npc)
    local partners = self:findSocialPartners(npc, 50)
    if #partners > 0 then
        return partners[1]
    end
    return nil
end

function NPCAI:updateWalkingState(npc, dt)
    if not npc.path or #npc.path == 0 then
        -- Reached destination — dissolve walking pair if any
        if npc.walkingPartner then
            npc.walkingPartner.walkingPartner = nil
            npc.walkingPartner = nil
        end
        self:setState(npc, self.STATES.IDLE)
        return
    end

    -- Walking partner logic: stay close to partner
    if npc.walkingPartner then
        local partner = npc.walkingPartner
        -- Check partner is still active and walking
        if not partner.isActive or
           (partner.aiState ~= self.STATES.WALKING and partner.aiState ~= self.STATES.TRAVELING) then
            -- Partner stopped or changed state, dissolve pair
            partner.walkingPartner = nil
            npc.walkingPartner = nil
        else
            -- Adjust position to stay within 2m of partner (follower logic)
            local pDx = partner.position.x - npc.position.x
            local pDz = partner.position.z - npc.position.z
            local pDist = math.sqrt(pDx * pDx + pDz * pDz)
            if pDist > 3 then
                -- Too far from partner, nudge toward them
                local nudge = 0.3 * dt * npc.movementSpeed
                npc.position.x = npc.position.x + (pDx / pDist) * nudge
                npc.position.z = npc.position.z + (pDz / pDist) * nudge
            end
            -- Match partner speed (use partner's movementSpeed if available)
            if partner.movementSpeed then
                npc.movementSpeed = partner.movementSpeed
            end
        end
    end

    -- Move along path
    local target = npc.path[1]
    local dx = target.x - npc.position.x
    local dz = target.z - npc.position.z
    local distance = math.sqrt(dx * dx + dz * dz)

    if distance < 1 then
        -- Reached this waypoint
        table.remove(npc.path, 1)
    else
        -- Move toward waypoint
        local speed = npc.movementSpeed * dt

        -- Get current terrain height
        local currentTerrainY = npc.position.y
        if g_currentMission and g_currentMission.terrainRootNode then
            local okH, h = pcall(getTerrainHeightAtWorldPos,
                g_currentMission.terrainRootNode, npc.position.x, 0, npc.position.z)
            if okH and h then
                currentTerrainY = h
            end
        end

        local moveX = (dx / distance) * speed
        local moveZ = (dz / distance) * speed

        local newX = npc.position.x + moveX
        local newZ = npc.position.z + moveZ

        -- =============================================
        -- STEEP TERRAIN CHECK: prevent walking up cliffs
        -- If the terrain ahead rises more than 3m over ~2m horizontal,
        -- try perpendicular directions; if all too steep, reverse.
        -- =============================================
        local canMoveForward = true
        if g_currentMission and g_currentMission.terrainRootNode then
            local okAhead, aheadY = pcall(getTerrainHeightAtWorldPos,
                g_currentMission.terrainRootNode, newX, 0, newZ)
            if okAhead and aheadY then
                local rise = aheadY - currentTerrainY
                local horizontalDist = math.sqrt(moveX * moveX + moveZ * moveZ)
                -- Only block uphill movement (rise > 0), allow walking downhill
                if rise > 3.0 or (horizontalDist > 0.01 and rise / math.max(horizontalDist, 0.01) > 1.5) then
                    canMoveForward = false

                    -- Try perpendicular directions (left and right of current heading)
                    local perpLX = -moveZ / math.max(horizontalDist, 0.01) * speed
                    local perpLZ =  moveX / math.max(horizontalDist, 0.01) * speed
                    local perpRX =  moveZ / math.max(horizontalDist, 0.01) * speed
                    local perpRZ = -moveX / math.max(horizontalDist, 0.01) * speed

                    -- Check left perpendicular
                    local leftX = npc.position.x + perpLX
                    local leftZ = npc.position.z + perpLZ
                    local okL, leftY = pcall(getTerrainHeightAtWorldPos,
                        g_currentMission.terrainRootNode, leftX, 0, leftZ)
                    local leftRise = (okL and leftY) and (leftY - currentTerrainY) or 999

                    -- Check right perpendicular
                    local rightX = npc.position.x + perpRX
                    local rightZ = npc.position.z + perpRZ
                    local okR, rightY = pcall(getTerrainHeightAtWorldPos,
                        g_currentMission.terrainRootNode, rightX, 0, rightZ)
                    local rightRise = (okR and rightY) and (rightY - currentTerrainY) or 999

                    -- Pick the direction with less elevation change
                    if leftRise < 3.0 and leftRise <= rightRise then
                        newX = leftX
                        newZ = leftZ
                        canMoveForward = true
                    elseif rightRise < 3.0 then
                        newX = rightX
                        newZ = rightZ
                        canMoveForward = true
                    else
                        -- All directions too steep — reverse direction (walk back downhill)
                        newX = npc.position.x - moveX
                        newZ = npc.position.z - moveZ
                        local okBack, backY = pcall(getTerrainHeightAtWorldPos,
                            g_currentMission.terrainRootNode, newX, 0, newZ)
                        local backRise = (okBack and backY) and (backY - currentTerrainY) or 999
                        if backRise < 3.0 then
                            canMoveForward = true
                        else
                            -- Completely stuck on all sides — skip this waypoint
                            table.remove(npc.path, 1)
                            return
                        end
                    end
                else
                    -- Gentle slope — slow down proportionally to steepness
                    if rise > 1 then
                        speed = speed * 0.7
                        moveX = (dx / distance) * speed
                        moveZ = (dz / distance) * speed
                        newX = npc.position.x + moveX
                        newZ = npc.position.z + moveZ
                    end
                end
            end
        end

        -- =============================================
        -- BUILDING AVOIDANCE: push NPC away from buildings
        -- Check both current position and next position.
        -- Uses an approach margin (radius + 2m) to start steering
        -- before the NPC actually enters the building footprint.
        -- =============================================

        -- First: if NPC is currently inside a building, push them out immediately
        if self.npcSystem and self.npcSystem.isPositionInsideBuilding then
            local insideNow, buildingNow = self.npcSystem:isPositionInsideBuilding(
                npc.position.x, npc.position.z, npc.homeBuilding)
            if insideNow and buildingNow then
                -- Emergency push: move NPC directly away from building center
                local pushDx = npc.position.x - buildingNow.x
                local pushDz = npc.position.z - buildingNow.z
                local pushDist = math.sqrt(pushDx * pushDx + pushDz * pushDz)
                if pushDist < 0.5 then
                    -- Dead center — pick random escape direction
                    local angle = math.random() * math.pi * 2
                    pushDx = math.cos(angle)
                    pushDz = math.sin(angle)
                    pushDist = 1
                end
                local escapeRadius = (buildingNow.radius or 5) + 3
                npc.position.x = buildingNow.x + (pushDx / pushDist) * escapeRadius
                npc.position.z = buildingNow.z + (pushDz / pushDist) * escapeRadius
                -- Recalculate movement from new position
                newX = npc.position.x
                newZ = npc.position.z
            end
        end

        -- Second: check if the next position enters or approaches a building
        if self.npcSystem and self.npcSystem.classifiedBuildings then
            local bestAvoidX, bestAvoidZ = newX, newZ
            local needsAvoidance = false

            for _, entries in pairs(self.npcSystem.classifiedBuildings) do
                for _, building in ipairs(entries) do
                    if building.placeable ~= npc.homeBuilding then
                        local bDx = newX - building.x
                        local bDz = newZ - building.z
                        local bDist = math.sqrt(bDx * bDx + bDz * bDz)
                        -- Use an approach margin: start steering when within radius + 2m
                        local avoidRadius = (building.radius or 5) + 2
                        if bDist < avoidRadius and bDist > 0.1 then
                            needsAvoidance = true
                            -- Calculate tangent direction (perpendicular to building direction)
                            local tangentX = -bDz / bDist
                            local tangentZ = bDx / bDist
                            -- Pick tangent that moves us roughly toward our target
                            local dot = tangentX * dx + tangentZ * dz
                            if dot < 0 then
                                tangentX = -tangentX
                                tangentZ = -tangentZ
                            end
                            -- Stronger avoidance: tangent movement + outward push
                            -- Push strength increases as NPC gets closer to building center
                            local pushStrength = 1.0 - (bDist / avoidRadius)  -- 0 at edge, 1 at center
                            local outwardX = (bDx / bDist) * speed * (0.5 + pushStrength)
                            local outwardZ = (bDz / bDist) * speed * (0.5 + pushStrength)
                            bestAvoidX = npc.position.x + tangentX * speed + outwardX
                            bestAvoidZ = npc.position.z + tangentZ * speed + outwardZ
                        end
                    end
                end
            end

            if needsAvoidance then
                newX = bestAvoidX
                newZ = bestAvoidZ
            end
        end

        npc.position.x = newX
        npc.position.z = newZ

        -- Update Y position to terrain height (clamp to ground)
        if g_currentMission and g_currentMission.terrainRootNode then
            local okY, newTerrainHeight = pcall(getTerrainHeightAtWorldPos,
                g_currentMission.terrainRootNode, npc.position.x, 0, npc.position.z)
            if okY and newTerrainHeight then
                npc.position.y = newTerrainHeight + 0.05
            end
        end

        -- Update rotation to face movement direction (FS25 yaw: atan2(dx, dz))
        if math.abs(dx) > 0.01 or math.abs(dz) > 0.01 then
            npc.rotation.y = math.atan2(dx, dz)
        end

        -- Update path visual if debug mode
        if self.npcSystem.settings.debugMode and npc.path and #npc.path > 0 then
            npc.currentPathSegment = {start = {x = npc.position.x, y = npc.position.y, z = npc.position.z},
                                     target = target}
        end
    end
end

--- Initialize field work traversal using NPCFieldWork module.
-- Delegates to NPCFieldWork:getWorkPattern() for boustrophedon rows,
-- personality-driven patterns, and multi-worker coordination.
-- Falls back to legacy implementation if NPCFieldWork unavailable.
-- @param npc  NPC data table with assignedField
function NPCAI:initFieldWork(npc)
    if not npc.assignedField or not npc.assignedField.center then return end

    -- Try new NPCFieldWork module first
    local fieldWork = self.npcSystem and self.npcSystem.fieldWork
    if fieldWork then
        local waypoints, slot = fieldWork:getWorkPattern(npc, npc.assignedField)
        if waypoints and #waypoints > 0 then
            npc.fieldWorkWaypoints = waypoints
            npc.fieldWorkPath = waypoints  -- backward compat for updateWorkingState
            npc.fieldWorkIndex = self:_findNearestWaypointIndex(npc, waypoints)
            npc.workTimer = 0
            npc.fieldWorkSlot = slot
            npc.fieldWorkPattern = "boustrophedon"
            npc._originalSpeed = npc._originalSpeed or npc.movementSpeed
            npc.movementSpeed = 1.8  -- field work speed
            return
        end
    end

    -- Fallback to legacy
    self:initFieldWorkLegacy(npc)
end

--- Legacy field work init (fallback).
-- 4 work patterns selected by personality:
--   1. Row traversal (hardworking default) — walk east-west rows
--   2. Spiral inward (generous) — edges to center
--   3. Perimeter walk (grumpy) — fence inspection
--   4. Spot check (lazy/social) — random inspection points
-- @param npc  NPC data table with assignedField
function NPCAI:initFieldWorkLegacy(npc)
    if not npc.assignedField or not npc.assignedField.center then return end

    local cx = npc.assignedField.center.x
    local cz = npc.assignedField.center.z
    local fieldSize = math.max(20, math.sqrt(npc.assignedField.size or 400))
    local halfSize = fieldSize * 0.4  -- stay within 80% of field

    npc.fieldWorkPath = {}

    -- Select work pattern based on personality
    local pattern = "rows"
    if npc.personality == "generous" then
        pattern = "spiral"
    elseif npc.personality == "grumpy" then
        pattern = "perimeter"
    elseif npc.personality == "lazy" or npc.personality == "social" then
        pattern = "spotcheck"
    end

    if pattern == "rows" then
        -- Row traversal: walk east-west rows across the field
        local rowSpacing = 6
        local rows = math.floor(halfSize * 2 / rowSpacing)
        local startZ = cz - halfSize
        for row = 0, math.min(rows, 12) do
            local rowZ = startZ + row * rowSpacing
            if row % 2 == 0 then
                table.insert(npc.fieldWorkPath, { x = cx - halfSize, z = rowZ })
                table.insert(npc.fieldWorkPath, { x = cx + halfSize, z = rowZ })
            else
                table.insert(npc.fieldWorkPath, { x = cx + halfSize, z = rowZ })
                table.insert(npc.fieldWorkPath, { x = cx - halfSize, z = rowZ })
            end
        end

    elseif pattern == "spiral" then
        -- Spiral inward: start at edges, work toward center
        local steps = 20
        for i = 0, steps do
            local t = i / steps
            local radius = halfSize * (1 - t)
            local angle = t * math.pi * 4  -- 2 full rotations
            table.insert(npc.fieldWorkPath, {
                x = cx + math.cos(angle) * radius,
                z = cz + math.sin(angle) * radius
            })
        end

    elseif pattern == "perimeter" then
        -- Perimeter walk: walk around the field edges (fence inspection)
        local corners = {
            { x = cx - halfSize, z = cz - halfSize },
            { x = cx + halfSize, z = cz - halfSize },
            { x = cx + halfSize, z = cz + halfSize },
            { x = cx - halfSize, z = cz + halfSize },
            { x = cx - halfSize, z = cz - halfSize },  -- close the loop
        }
        for _, corner in ipairs(corners) do
            table.insert(npc.fieldWorkPath, corner)
        end

    elseif pattern == "spotcheck" then
        -- Spot check: random inspection points scattered across field
        local numPoints = 6
        for _ = 1, numPoints do
            table.insert(npc.fieldWorkPath, {
                x = cx + (math.random() - 0.5) * halfSize * 2,
                z = cz + (math.random() - 0.5) * halfSize * 2
            })
        end
    end

    npc.fieldWorkIndex = self:_findNearestWaypointIndex(npc, npc.fieldWorkPath)
    npc.workTimer = 0
    npc.fieldWorkPattern = pattern

    -- Use tractor speed while working (slower than walking, like a tractor in field)
    npc._originalSpeed = npc._originalSpeed or npc.movementSpeed
    npc.movementSpeed = 1.8  -- tractor field speed
end

function NPCAI:updateWorkingState(npc, dt)
    npc.workTimer = (npc.workTimer or 0) + dt

    -- Storm check: interrupt field work in severe weather (every 30s)
    npc._weatherCheckTimer = (npc._weatherCheckTimer or 0) + dt
    if npc._weatherCheckTimer > 30 then
        npc._weatherCheckTimer = 0
        local wf = 1.0
        if self.npcSystem.scheduler and self.npcSystem.scheduler.getWeatherFactor then
            wf = self.npcSystem.scheduler:getWeatherFactor()
        end
        if wf <= 0.3 then
            -- Storm: everyone goes home
            self:goHome(npc)
            return
        elseif wf <= 0.5 and npc.personality ~= "hardworking" then
            -- Heavy rain: non-hardworking NPCs stop working
            self:goHome(npc)
            return
        end
    end

    -- Pause field work movement during greeting (NPC stops to say hi)
    if npc._greetingPause then
        if not npc.greetingTimer or npc.greetingTimer <= 0 then
            -- Greeting finished, resume work
            npc._greetingPause = nil
        else
            -- Still greeting — don't move, just stand and face player
            return
        end
    end

    -- Personality-based total work duration before taking a break
    local workDuration = 360  -- 6 minutes of field traversal
    if npc.personality == "hardworking" then
        workDuration = 600  -- 10 minutes
    elseif npc.personality == "lazy" then
        workDuration = 180  -- 3 minutes
    end

    -- Base-game AI drives the combo when a GoTo chain is active: follow its real
    -- position for HUD/proximity and skip our own kinematic row movement.
    if npc.goToActive then
        if npc.realTractor and npc.realTractor.rootNode then
            pcall(function()
                local wx, wy, wz = getWorldTranslation(npc.realTractor.rootNode)
                if wx then npc.position.x, npc.position.y, npc.position.z = wx, wy, wz end
            end)
        end
    else

    -- Move along field work rows
    if npc.fieldWorkPath and npc.fieldWorkIndex then
        local target = npc.fieldWorkPath[npc.fieldWorkIndex]
        if target then
            local dx = target.x - npc.position.x
            local dz = target.z - npc.position.z
            local dist = math.sqrt(dx * dx + dz * dz)

            if dist < 2 then
                -- Reached this row waypoint, advance to next
                npc.fieldWorkIndex = npc.fieldWorkIndex + 1
                if npc.fieldWorkIndex > #npc.fieldWorkPath then
                    -- Finished all rows, loop back to start
                    npc.fieldWorkIndex = 1
                end
            else
                -- Move toward row waypoint at tractor speed
                local speed = npc.movementSpeed * dt
                npc.position.x = npc.position.x + (dx / dist) * speed
                npc.position.z = npc.position.z + (dz / dist) * speed

                -- Clamp Y position to terrain height
                if g_currentMission and g_currentMission.terrainRootNode then
                    local okY, terrainY = pcall(getTerrainHeightAtWorldPos,
                        g_currentMission.terrainRootNode, npc.position.x, 0, npc.position.z)
                    if okY and terrainY then
                        npc.position.y = terrainY + 0.05
                    end
                end

                -- Face movement direction
                if math.abs(dx) > 0.01 or math.abs(dz) > 0.01 then
                    npc.rotation.y = math.atan2(dx, dz)
                end
            end
        end
    end

    -- Drive the real combo kinematically so it follows the field-work rows.
    -- The attached implement follows via its joint.
    if npc.usingComboFieldWork and npc.realTractor and npc.realTractor.rootNode then
        pcall(function()
            setTranslation(npc.realTractor.rootNode, npc.position.x, npc.position.y, npc.position.z)
            setRotation(npc.realTractor.rootNode, 0, npc.rotation.y, 0)
        end)
    end
    end  -- end of the "if npc.goToActive then ... else" block

    -- After work duration, decide next action
    if npc.workTimer > workDuration then
        npc.workTimer = 0

        local nextAction = math.random()
        if nextAction < 0.15 then
            -- Take a break (idle near field). Leaving WORKING despawns the on-demand
            -- field vehicle via setState; a fresh one spawns when work resumes.
            -- Release worker slot so another NPC can take the field
            local fieldWork = self.npcSystem and self.npcSystem.fieldWork
            if fieldWork and npc._fieldWorkFieldId then
                local npcId = npc.uniqueId or npc.id or npc.name
                fieldWork:releaseWorker(npc._fieldWorkFieldId, npcId)
                npc._fieldWorkFieldId = nil
            end
            npc.fieldWorkPath = nil
            npc.fieldWorkWaypoints = nil
            npc.fieldWorkIndex = nil
            npc.fieldWorkSlot = nil
            self:setState(npc, self.STATES.IDLE)
        else
            -- Continue working: keep existing path (it loops naturally via index reset at end)
            if not npc.fieldWorkPath or #npc.fieldWorkPath == 0 then
                self:initFieldWork(npc)
            end
            -- workTimer already reset to 0 above
        end
    end
end

--- Release field work worker slot for an NPC (helper for state transitions).
-- Safe to call even if NPC wasn't working a field.
-- @param npc  NPC data table
function NPCAI:_releaseFieldWorkSlot(npc)
    local fieldWork = self.npcSystem and self.npcSystem.fieldWork
    if fieldWork and npc._fieldWorkFieldId then
        local npcId = npc.uniqueId or npc.id or npc.name
        fieldWork:releaseWorker(npc._fieldWorkFieldId, npcId)
        npc._fieldWorkFieldId = nil
        npc.fieldWorkWaypoints = nil
        npc.fieldWorkSlot = nil
    end
end

--- Find the waypoint nearest to the NPC's current position.
-- Used when starting/resuming field work so the NPC doesn't teleport to index 1.
-- @param npc       NPC data table with .position {x, z}
-- @param waypoints Array of {x, z} waypoints
-- @return number   Best waypoint index (1-based)
function NPCAI:_findNearestWaypointIndex(npc, waypoints)
    if not waypoints or #waypoints == 0 then return 1 end
    if not npc or not npc.position then return 1 end

    -- Prefer row START waypoints (odd indices: 1, 3, 5...) so the NPC
    -- begins at a row start and walks the full row length, rather than
    -- starting mid-row or at a row end.
    local bestIdx = 1
    local bestDist = math.huge
    for i = 1, #waypoints, 2 do
        local dx = waypoints[i].x - npc.position.x
        local dz = waypoints[i].z - npc.position.z
        local d = dx * dx + dz * dz
        if d < bestDist then
            bestDist = d
            bestIdx = i
        end
    end
    return bestIdx
end

function NPCAI:updateDrivingState(npc, dt)
    if not npc.currentVehicle then
        self:setState(npc, self.STATES.IDLE)
        return
    end

    -- If NPC has a specific destination, drive toward it
    if npc.driveDestination then
        local dx = npc.driveDestination.x - npc.position.x
        local dz = npc.driveDestination.z - npc.position.z
        local dist = math.sqrt(dx * dx + dz * dz)

        if dist < 15 then
            -- Arrived at destination — handle vehicle prop parking before state change
            local destX = npc.driveDestination.x
            local destZ = npc.driveDestination.z
            local callback = npc.driveCallback
            npc.driveDestination = nil
            npc.driveCallback = nil

            -- Park the vehicle prop and restore NPC appearance
            self:handleDrivingArrival(npc, destX, destZ)

            self:stopDriving(npc, true)  -- Release vehicle without state change

            -- Let callback determine the next state
            if callback == "startWorking" then
                self:startWorking(npc)
            elseif callback == "goHome" then
                self:setState(npc, self.STATES.RESTING)
            else
                self:setState(npc, self.STATES.IDLE)
            end
            return
        end

        -- If commute vehicle is ready, hand control over to the game's AI driver
        if npc.realCar and npc.realCarPreparing then
            local ok, ready = pcall(function() return npc.realCar:getIsAIReadyToDrive() end)
            if ok and ready then
                npc.realCarPreparing = false
                pcall(function()
                    local destX = npc.driveDestination.x
                    local destZ = npc.driveDestination.z
                    local terrainY = getTerrainHeightAtWorldPos(g_terrainNode, destX, 0, destZ)
                    local ddx = destX - npc.position.x
                    local ddz = destZ - npc.position.z
                    local ddist = math.sqrt(ddx * ddx + ddz * ddz)
                    local dirX2 = ddist > 0.1 and ddx / ddist or 0
                    local dirZ2 = ddist > 0.1 and ddz / ddist or 1
                    -- 30 km/h speed cap matches driveSpeed for cars
                    npc.realCar:setAITarget(npc.realCarTask, destX, terrainY, destZ, dirX2, 0, dirZ2, 30)
                end)
            end
        end

        -- Drive toward destination at transport-mode-appropriate speed
        -- Cars: 8.3 m/s (~30 km/h), Tractors: 5.5 m/s (~20 km/h), Default: 5.0 m/s
        local baseSpeed = npc.driveSpeed or 5.0
        local speed = baseSpeed * dt
        local dirX = dx / dist
        local dirZ = dz / dist
        npc.position.x = npc.position.x + dirX * speed
        npc.position.z = npc.position.z + dirZ * speed
        npc.rotation.y = math.atan2(dirX, dirZ)

        -- Update terrain Y
        if g_currentMission and g_currentMission.terrainRootNode then
            local okY, h = pcall(getTerrainHeightAtWorldPos,
                g_currentMission.terrainRootNode, npc.position.x, 0, npc.position.z)
            if okY and h then
                npc.position.y = h + 0.05
            end
        end

        -- Update vehicle position
        if npc.currentVehicle then
            npc.currentVehicle.position = {
                x = npc.position.x, y = npc.position.y, z = npc.position.z
            }
        end

        -- Real commute vehicle stays at its spawn point (physics-owned).
        -- Teleporting it each frame fights the physics engine and causes clipping.
    else
        -- No destination — timer-based driving (existing fallback behavior)
        npc.vehicleTimer = (npc.vehicleTimer or 0) + dt

        local driveDuration = 20
        if npc.personality == "hardworking" then
            driveDuration = 30
        elseif npc.personality == "lazy" then
            driveDuration = 10
        end

        if npc.vehicleTimer > driveDuration then
            npc.vehicleTimer = 0
            self:stopDriving(npc)
        else
            local speed = 5.0 * dt
            local moveX = math.sin(npc.rotation.y) * speed
            local moveZ = math.cos(npc.rotation.y) * speed

            npc.position.x = npc.position.x + moveX
            npc.position.z = npc.position.z + moveZ

            -- Clamp Y position to terrain height
            if g_currentMission and g_currentMission.terrainRootNode then
                local okY, terrainY = pcall(getTerrainHeightAtWorldPos,
                    g_currentMission.terrainRootNode, npc.position.x, 0, npc.position.z)
                if okY and terrainY then
                    npc.position.y = terrainY + 0.05
                end
            end

            if npc.currentVehicle then
                npc.currentVehicle.position = {
                    x = npc.position.x, y = npc.position.y, z = npc.position.z
                }
            end

            -- Sync real commute vehicle to NPC logical position
            if npc.realCar and npc.realCar.rootNode then
                pcall(function()
                    setTranslation(npc.realCar.rootNode, npc.position.x, npc.position.y, npc.position.z)
                    setRotation(npc.realCar.rootNode, 0, npc.rotation.y, 0)
                end)
            end
        end
    end
end

function NPCAI:updateRestingState(npc, dt)
    -- If NPC is sleeping (night rest), don't break out via timer
    -- Sleep/wake transitions are handled by updateSleepState()
    if npc.isSleeping then
        return
    end

    -- NPC is resting (daytime break or tired)
    npc.restTimer = (npc.restTimer or 0) + dt

    local restDuration = 60
    if npc.personality == "lazy" then
        restDuration = 90
    elseif npc.personality == "hardworking" then
        restDuration = 30
    end

    if npc.restTimer > restDuration then
        npc.restTimer = 0
        self:setState(npc, self.STATES.IDLE)

        -- Show notification if resting at unusual time
        local hour = self.npcSystem.scheduler:getCurrentHour()
        if hour >= 8 and hour <= 16 and math.random() < 0.3 then
            self.npcSystem:showNotification(
                "NPC Resting",
                string.format("%s is well-rested and ready to work", npc.name)
            )
        end
    end
end

function NPCAI:updateSocializingState(npc, dt)
    -- NPC is talking with another NPC
    npc.socialTimer = (npc.socialTimer or 0) + dt
    
    local socialDuration = 15
    if npc.personality == "social" then
        socialDuration = 25
    elseif npc.personality == "loner" then
        socialDuration = 5
    end
    
    if npc.socialTimer > socialDuration then
        npc.socialTimer = 0
        self:setState(npc, self.STATES.IDLE)

        -- Update NPC-NPC relationship with social partner
        if npc.socialPartner then
            local partner = npc.socialPartner
            if partner and partner.isActive then
                -- Track NPC-NPC relationship change
                if self.npcSystem.relationshipManager then
                    self.npcSystem.relationshipManager:updateNPCNPCRelationship(npc, partner, "socialize")
                end
                -- Satisfy social need for both
                if npc.needs then npc.needs.social = math.max(0, npc.needs.social - 15) end
                if partner.needs then partner.needs.social = math.max(0, partner.needs.social - 15) end

                self.npcSystem:showNotification(
                    "NPC Socializing",
                    string.format("%s and %s finished their conversation",
                        npc.name, partner.name)
                )
            end
            npc.socialPartner = nil
        end
    end
end

function NPCAI:updateTravelingState(npc, dt)
    -- NPC is traveling to a distant location
    if not npc.path or #npc.path == 0 then
        self:setState(npc, self.STATES.IDLE)
        return
    end
    
    self:updateWalkingState(npc, dt)
    
    -- Check if reached destination
    if #npc.path == 0 then
        self:setState(npc, self.STATES.IDLE)
        
        -- Show arrival notification for long travels
        if npc.travelDistance and npc.travelDistance > 200 then
            self.npcSystem:showNotification(
                "NPC Travel",
                string.format("%s has arrived at the destination", npc.name)
            )
        end
    end
end

--- Transition an NPC to a new AI state, resetting relevant timers.
-- Flags multiplayer sync dirty on state change.
-- @param npc    NPC data table
-- @param state  Target state string (use self.STATES constants)
function NPCAI:setState(npc, state)
    local oldState = npc.aiState
    npc.aiState = state
    npc.currentAction = state
    npc.stateTimer = 0
    
    -- Reset building check flag on any state transition
    npc._buildingCheckDone = nil

    -- Restore original movement speed when leaving movement/work states
    if npc._originalSpeed and state ~= "walking" and state ~= "traveling" and state ~= "working" then
        npc.movementSpeed = npc._originalSpeed
        npc._originalSpeed = nil
        npc._movementMode = nil        -- clear movement mode
        npc._eveningCommuteSpeed = nil  -- clear cached commute speed
    end

    -- When leaving WORKING state: despawn the on-demand field-work vehicle entirely
    -- (it is re-spawned fresh next time so its equipment always matches the field).
    if oldState == "working" and state ~= "working" then
        npc.fieldWorkPath = nil
        npc.fieldWorkIndex = nil

        -- Despawn the real tractor + implement (stops AI, unseats NPC, deletes both).
        if npc.realTractor and self.npcSystem and self.npcSystem.removeNPCTractor then
            pcall(function() self.npcSystem:removeNPCTractor(npc) end)
        elseif npc.activeAIJob and self.npcSystem and self.npcSystem.stopNPCFieldWork then
            -- No vehicle but an AI job somehow active: stop it.
            pcall(function() self.npcSystem:stopNPCFieldWork(npc) end)
        end

        local entityMgr = self.npcSystem.entityManager
        if entityMgr then
            -- Reset NPC Y offset (step out of cab) but leave tractor visible in field
            local entity = entityMgr.npcEntities and entityMgr.npcEntities[npc.id]
            if entity then
                entity.npcYOffset = 0
            end
        end
    end

    -- State transition effects
    if oldState ~= state then
        -- Flag sync dirty for immediate multiplayer broadcast
        if self.npcSystem.syncDirty ~= nil then
            self.npcSystem.syncDirty = true
        end

        if self.npcSystem.settings.debugMode then
            print(string.format("NPC %s: %s -> %s", npc.name, oldState, state))
        end
        
        -- Reset timers for new state
        if state == self.STATES.IDLE then
            npc.idleTimer = 0
        elseif state == self.STATES.WORKING then
            npc.workTimer = 0
        elseif state == self.STATES.DRIVING then
            npc.vehicleTimer = 0
        elseif state == self.STATES.RESTING then
            npc.restTimer = 0
        elseif state == self.STATES.SOCIALIZING then
            npc.socialTimer = 0
            npc.socialPartner = nil
        elseif state == self.STATES.TRAVELING then
            npc.travelTimer = 0
        elseif state == self.STATES.GATHERING then
            npc.gatheringTimer = 0
        end
    end
end

--- Set an NPC's movement mode (walk/run/sprint), adjusting speed accordingly.
-- Walk restores the NPC's personality-based speed. Run and sprint use fixed
-- speeds that trigger the run animation (>2.5 m/s threshold in NPCEntity).
-- @param npc   NPC data table
-- @param mode  "walk", "run", or "sprint"
function NPCAI:setMovementMode(npc, mode)
    npc._originalSpeed = npc._originalSpeed or npc.movementSpeed
    npc._movementMode = mode

    if mode == "run" then
        npc.movementSpeed = self.MOVE_SPEEDS.run
    elseif mode == "sprint" then
        npc.movementSpeed = self.MOVE_SPEEDS.sprint
    else -- "walk"
        npc.movementSpeed = npc._originalSpeed
        npc._movementMode = "walk"
    end
end

--- Send an NPC to their assigned field. If already there, transitions to
-- WORKING state. Uses transport mode selection (walk/car/tractor) based
-- on distance and profession for the commute.
-- @param npc  NPC data table (requires npc.assignedField)
function NPCAI:startWorking(npc)
    if not npc.assignedField or not npc.assignedField.center then
        self:setState(npc, self.STATES.IDLE)
        return
    end

    local targetX = npc.assignedField.center.x
    local targetZ = npc.assignedField.center.z

    if self:isAtPosition(npc, targetX, targetZ, 40) then
        -- At field, start working
        self:setState(npc, self.STATES.WORKING)

        -- Drive a real combo across the field if we have one (hybrid/realistic),
        -- otherwise fall back to the tractor prop. Either way we traverse the
        -- field rows via initFieldWork below.
        -- On-demand: spawn field-work equipment matched to the field's CURRENT need
        -- (async). The spawn callback seats the NPC + starts the AI job, so we can't
        -- know the result synchronously. If a spawn is started we skip the tractor
        -- prop (the real one is on its way); if not (growing crop, caps reached, mode
        -- off) the NPC works on foot with the prop below, as before.
        local usingCombo = false
        local mode = self.npcSystem and self.npcSystem.settings and self.npcSystem.settings.npcVehicleMode
        if (mode == "realistic" or mode == "hybrid") and self.npcSystem.spawnFieldWorkVehicle then
            pcall(function()
                usingCombo = self.npcSystem:spawnFieldWorkVehicle(npc)
            end)
        end
        -- The spawn callback (activateNPCTractor) owns npc.goToActive / npc.usingComboFieldWork.

        if not usingCombo then
            -- No real combo: show the tractor prop instead
            npc.usingComboFieldWork = false
            npc.goToActive = false
            local entityMgr = self.npcSystem.entityManager
            if entityMgr then
                pcall(function() entityMgr:updateWorkingVisuals(npc, true) end)
            end
        end

        -- Field traversal path (rows) for the prop and the kinematic combo fallback
        self:initFieldWork(npc)

        if math.random() < 0.7 and self.npcSystem.settings.showNotifications then
            self.npcSystem:showNotification(
                "NPC Working",
                string.format("%s is working on their field", npc.name)
            )
        end
    else
        -- Morning exception: lazy NPCs running late jog to their field
        if npc.personality == "lazy" then
            local hour = 12
            if self.npcSystem.scheduler and self.npcSystem.scheduler.getCurrentHour then
                hour = self.npcSystem.scheduler:getCurrentHour()
            end
            local sched = self:getPersonalitySchedule(npc)
            if hour >= sched.workStart + 0.5 then
                self:setMovementMode(npc, "run")
                npc.currentAction = "rushing to work"
            end
        end

        -- Use transport mode selection for the commute to the field
        self:startCommute(npc, targetX, targetZ, "startWorking")
    end
end

--- Generate a path and start walking the NPC toward a target position.
-- Automatically switches to TRAVELING state if distance > 200m.
-- @param npc      NPC data table
-- @param targetX  Target X world position
-- @param targetZ  Target Z world position
function NPCAI:startWalkingTo(npc, targetX, targetZ)
    -- Generate path to target
    npc.path = self.pathfinder:findPath(
        npc.position.x, npc.position.z,
        targetX, targetZ
    )
    
    if not npc.path or #npc.path == 0 then
        -- Direct movement if pathfinding fails
        npc.path = {
            {x = targetX, y = 0, z = targetZ}
        }
    end
    
    npc.targetPosition = {x = targetX, y = 0, z = targetZ}
    
    -- Calculate travel distance
    if npc.path and #npc.path > 0 then
        local totalDistance = 0
        for i = 1, #npc.path - 1 do
            local p1 = npc.path[i]
            local p2 = npc.path[i + 1]
            totalDistance = totalDistance + VectorHelper.distance2D(p1.x, p1.z, p2.x, p2.z)
        end
        npc.travelDistance = totalDistance
        
        if totalDistance > 200 then
            self:setState(npc, self.STATES.TRAVELING)
        end
    end
end

function NPCAI:startWalkingToRandomLocation(npc, maxDistance)
    local targetX, targetZ

    -- 85% chance: walk toward a nearby building (natural town behavior)
    -- 15% chance: short random walk (crossing a road, wandering)
    local buildings = self.npcSystem:findNearbyBuildings(
        npc.position.x, npc.position.z, maxDistance)

    if #buildings > 0 and math.random() < 0.85 then
        -- Pick one of the closest 5 buildings
        local building = buildings[math.random(1, math.min(#buildings, 5))]
        -- Position OUTSIDE the building, not at a random offset from center
        targetX, targetZ = self.npcSystem:getExteriorPositionNear(
            building.x, building.z, building, npc.homeBuilding)
    else
        -- Short random walk (keeps NPCs from straying far into fields)
        local angle = math.random() * math.pi * 2
        local distance = math.random(10, math.min(30, maxDistance))
        targetX = npc.position.x + math.cos(angle) * distance
        targetZ = npc.position.z + math.sin(angle) * distance
    end

    -- Final safety check: ensure target is not inside a non-home building
    targetX, targetZ = self.npcSystem:getSafePosition(targetX, targetZ, npc.homeBuilding)

    self:startWalkingTo(npc, targetX, targetZ)

    -- Set appropriate state based on actual distance
    local dx = targetX - npc.position.x
    local dz = targetZ - npc.position.z
    local actualDist = math.sqrt(dx * dx + dz * dz)
    if actualDist > 100 then
        self:setState(npc, self.STATES.TRAVELING)
    else
        self:setState(npc, self.STATES.WALKING)
    end
end

--- Send an NPC home. Uses transport mode selection (walk/car/tractor) based
-- on distance and profession. Transitions to RESTING if already close to home.
-- @param npc  NPC data table (requires npc.homePosition)
function NPCAI:goHome(npc)
    -- Release field work slot if NPC was working a field
    self:_releaseFieldWorkSlot(npc)

    if not npc.homePosition then
        self:setState(npc, self.STATES.IDLE)
        return
    end

    local dx = npc.homePosition.x - npc.position.x
    local dz = npc.homePosition.z - npc.position.z
    local distance = math.sqrt(dx * dx + dz * dz)

    if distance < 10 then
        -- Already close to home
        self:setState(npc, self.STATES.RESTING)
        return
    end

    -- Determine commute speed based on time of day
    local hour = 12
    if self.npcSystem.scheduler and self.npcSystem.scheduler.getCurrentHour then
        hour = self.npcSystem.scheduler:getCurrentHour()
    end

    -- Evening commute (after 15:00): run or sprint home
    if hour >= 15 then
        local commuteSpeed = npc._eveningCommuteSpeed  -- set by calculateDepartureTime
        if not commuteSpeed then
            -- Fallback: personality-based choice
            if npc.personality == "lazy" then
                commuteSpeed = self.MOVE_SPEEDS.run
            else
                commuteSpeed = (math.random() < 0.5) and self.MOVE_SPEEDS.run or self.MOVE_SPEEDS.sprint
            end
        end
        npc._originalSpeed = npc._originalSpeed or npc.movementSpeed
        npc.movementSpeed = commuteSpeed
        npc._movementMode = commuteSpeed >= self.MOVE_SPEEDS.sprint and "sprint" or "run"
        npc.currentAction = "heading home"
    end

    -- Morning/midday commute: keep normal walk speed (no boost applied above)

    -- Use transport mode selection for the commute home
    self:startCommute(npc, npc.homePosition.x, npc.homePosition.z, "goHome")
end

--- Assign a vehicle to the NPC and transition to DRIVING state.
-- Caller should set npc.driveDestination/driveCallback AFTER this returns true.
-- @param npc      NPC data table
-- @param vehicle  Vehicle table from npc.assignedVehicles
-- @return boolean true if driving started successfully
function NPCAI:startDriving(npc, vehicle)
    if not vehicle or not vehicle.isAvailable then
        return false
    end
    
    npc.currentVehicle = vehicle
    vehicle.isAvailable = false
    vehicle.currentTask = "driving"
    vehicle.driver = npc
    
    self:setState(npc, self.STATES.DRIVING)
    
    -- Show notification
    if self.npcSystem.settings.showNotifications then
        self.npcSystem:showNotification(
            "NPC Driving",
            string.format("%s is now driving their %s", npc.name, vehicle.type)
        )
    end
    
    return true
end

--- Release the NPC's current vehicle and optionally skip state transition.
-- @param npc              NPC data table
-- @param skipStateChange  If true, caller is responsible for next state
--                         (prevents double-transition when a callback follows)
function NPCAI:stopDriving(npc, skipStateChange)
    if npc.currentVehicle then
        npc.currentVehicle.isAvailable = true
        npc.currentVehicle.currentTask = nil
        npc.currentVehicle.driver = nil
        npc.currentVehicle = nil
    end

    -- Remove real commute vehicle if it wasn't already cleaned up by handleDrivingArrival
    if npc.realCar and self.npcSystem.removeNPCCar then
        self.npcSystem:removeNPCCar(npc)
    end

    if not skipStateChange then
        self:setState(npc, self.STATES.IDLE)
    end

    -- Show notification
    if self.npcSystem.settings.showNotifications then
        self.npcSystem:showNotification(
            "NPC Driving",
            string.format("%s stopped driving", npc.name)
        )
    end
end

--- Pair two NPCs for socializing: face each other, set both to SOCIALIZING.
-- Generates a conversation topic displayed as speech bubbles.
-- @param npc       Initiating NPC
-- @param otherNPC  Target NPC
function NPCAI:startSocializing(npc, otherNPC)
    if not otherNPC or not otherNPC.isActive then
        self:setState(npc, self.STATES.IDLE)
        return
    end

    -- Face each other
    local dx = otherNPC.position.x - npc.position.x
    local dz = otherNPC.position.z - npc.position.z
    npc.rotation.y = math.atan2(dx, dz)
    otherNPC.rotation.y = math.atan2(-dx, -dz)

    -- Generate conversation topic for speech bubble display
    local topic = self:generateNPCConversationTopic(npc, otherNPC)
    npc.greetingText = topic
    npc.greetingTimer = 4.0  -- show for 4 seconds
    -- Partner gets a response after a short delay
    otherNPC.greetingText = self:generateNPCResponse(otherNPC, npc, topic)
    otherNPC.greetingTimer = 4.0

    -- Set both to socializing
    self:setState(npc, self.STATES.SOCIALIZING)
    npc.socialPartner = otherNPC

    -- Also set the other NPC to socializing
    local otherAI = self.npcSystem.aiSystem
    otherAI:setState(otherNPC, otherAI.STATES.SOCIALIZING)
    otherNPC.socialPartner = npc

    -- Record encounter with partner info
    if self.npcSystem.recordEncounter then
        self.npcSystem:recordEncounter(npc, "socialized", topic, otherNPC.name, "positive")
        self.npcSystem:recordEncounter(otherNPC, "socialized", topic, npc.name, "positive")
    end

    -- Show notification
    if self.npcSystem.settings.showNotifications then
        self.npcSystem:showNotification(
            "NPC Socializing",
            string.format("%s and %s: \"%s\"",
                npc.name, otherNPC.name, topic)
        )
    end
end

--- Generate a conversation topic for NPC-NPC interactions.
-- Topics vary by time, weather, personality, farm context, and relationship.
-- @param npc1  Initiating NPC
-- @param npc2  Responding NPC
-- @return string  Conversation topic
function NPCAI:generateNPCConversationTopic(npc1, npc2)
    local hour = self.npcSystem.scheduler:getCurrentHour()

    -- Weather-based topics
    local wf = 1.0
    if self.npcSystem.scheduler and self.npcSystem.scheduler.getWeatherFactor then
        wf = self.npcSystem.scheduler:getWeatherFactor()
    end
    if wf < 0.7 then
        local weatherTopics = {
            "Looks like rain is coming...",
            "Hope the crops can handle this weather.",
            "Should we head inside?",
            "My fields are getting soaked!",
        }
        if math.random() < 0.4 then
            return weatherTopics[math.random(#weatherTopics)]
        end
    end

    -- Time-based topics
    if hour >= 6 and hour < 9 then
        local morningTopics = {
            "Beautiful morning, isn't it?",
            "Ready for another day of work!",
            "Did you sleep well?",
            "Coffee first, then work.",
        }
        return morningTopics[math.random(#morningTopics)]
    elseif hour >= 12 and hour < 13 then
        local lunchTopics = {
            "What's for lunch today?",
            "I'm starving!",
            "Let's take a proper break.",
            "The food smells great!",
        }
        return lunchTopics[math.random(#lunchTopics)]
    elseif hour >= 17 and hour < 20 then
        local eveningTopics = {
            "Long day, huh?",
            "Good work today.",
            "Plans for the evening?",
            "Time to relax!",
        }
        return eveningTopics[math.random(#eveningTopics)]
    end

    -- Personality-influenced topics
    local personality = npc1.personality or "generous"
    local personalityTopics = {
        hardworking = {
            "The fields need attention.", "We should get more done tomorrow.",
            "Have you checked your equipment lately?", "Work keeps me going.",
        },
        lazy = {
            "Think we could take a longer break?", "Is it evening yet?",
            "I could use a nap.", "No rush, right?",
        },
        social = {
            "Have you heard the latest news?", "We should get the others together!",
            "It's nice to catch up!", "Everyone's been so busy lately.",
        },
        grumpy = {
            "What do YOU want?", "Hmph. Fine, let's talk.",
            "Make it quick.", "I've got things to do.",
        },
        generous = {
            "Need any help with your field?", "I've got extra supplies if you need.",
            "How are your crops doing?", "Let me know if I can help.",
        },
    }
    local topics = personalityTopics[personality] or {"Nice day."}
    return topics[math.random(#topics)]
end

--- Generate a response to a conversation topic based on personality.
-- @param responder  NPC responding
-- @param initiator  NPC who started the conversation
-- @param topic      The topic being discussed
-- @return string    Response text
function NPCAI:generateNPCResponse(responder, initiator, topic)
    local personality = responder.personality or "generous"
    local responses = {
        hardworking = {"Indeed!", "Back to work soon.", "Agreed.", "Let's keep at it."},
        lazy = {"Mm-hmm...", "Sure, sure.", "If you say so.", "*yawn*"},
        social = {"Oh, absolutely!", "Tell me more!", "Ha ha, yes!", "I know, right?"},
        grumpy = {"Whatever.", "Hmph.", "If you must.", "..."},
        generous = {"Of course!", "Happy to help!", "That's kind of you.", "Absolutely!"},
    }
    local pool = responses[personality] or {"Yeah."}
    return pool[math.random(#pool)]
end

-- =========================================================
-- Social Grouping Behaviors
-- =========================================================
-- NPCs can form small groups (chatting circles), walking pairs
-- (commute buddies), and lunch clusters (semicircles near buildings).
-- These use the GATHERING state for stationary group interactions.
-- =========================================================

--- Update handler for GATHERING state.
-- NPC walks toward their assigned gathering position, then stands
-- facing the group center. Timer-based dissolution varies by personality.
-- @param npc  NPC data table
-- @param dt   Delta time in seconds
function NPCAI:updateGatheringState(npc, dt)
    -- Support Step 9 event-based gatherings that use gatheringData instead
    -- of gatheringPosition/gatheringCenter. Mill about at the event location.
    if npc.gatheringData and not npc.gatheringPosition then
        npc.gatheringTimer = (npc.gatheringTimer or 0) + dt
        local gd = npc.gatheringData
        if gd.centerX and gd.centerZ then
            self:millAbout(npc, gd.centerX, gd.centerZ, gd.radius or 5, dt)
        end
        -- Event gatherings time out after 120 seconds
        if npc.gatheringTimer > 120 then
            npc.gatheringTimer = 0
            npc.gatheringData = nil
            self:setState(npc, self.STATES.IDLE)
        end
        return
    end

    if not npc.gatheringPosition or not npc.gatheringCenter then
        -- Invalid gathering data, return to idle
        self:clearGatheringData(npc)
        self:setState(npc, self.STATES.IDLE)
        return
    end

    -- Check if we've arrived at our gathering position (within 2m)
    local dx = npc.gatheringPosition.x - npc.position.x
    local dz = npc.gatheringPosition.z - npc.position.z
    local distToPos = math.sqrt(dx * dx + dz * dz)

    if distToPos > 2 then
        -- Walk toward gathering position
        local speed = npc.movementSpeed * dt
        local moveX = (dx / distToPos) * speed
        local moveZ = (dz / distToPos) * speed

        npc.position.x = npc.position.x + moveX
        npc.position.z = npc.position.z + moveZ

        -- Snap Y to terrain
        if g_currentMission and g_currentMission.terrainRootNode then
            local okY, h = pcall(getTerrainHeightAtWorldPos,
                g_currentMission.terrainRootNode, npc.position.x, 0, npc.position.z)
            if okY and h then
                npc.position.y = h + 0.05
            end
        end

        -- Face movement direction while walking
        if math.abs(dx) > 0.01 or math.abs(dz) > 0.01 then
            npc.rotation.y = math.atan2(dx, dz)
        end
    else
        -- Arrived at position — face the group center
        local cdx = npc.gatheringCenter.x - npc.position.x
        local cdz = npc.gatheringCenter.z - npc.position.z
        if math.abs(cdx) > 0.01 or math.abs(cdz) > 0.01 then
            npc.rotation.y = math.atan2(cdx, cdz)
        end

        -- Periodic speech bubbles while standing in the group.
        -- Each NPC has an independent staggered timer so they don't all
        -- speak simultaneously. Initialised with a random offset on first use.
        if npc.groupSpeechTimer == nil then
            npc.groupSpeechTimer = math.random() * 12  -- stagger: 0-12s before first bubble
        end
        npc.groupSpeechTimer = npc.groupSpeechTimer + dt
        if npc.groupSpeechTimer >= 14 then
            npc.groupSpeechTimer = -(math.random() * 6)  -- reset with 0-6s extra gap
            local partner = self:findNearestGatheringPartner(npc)
            npc.greetingText = self:generateNPCConversationTopic(npc, partner or npc)
            npc.greetingTimer = 4.0
        end
    end

    -- Update gathering timer
    npc.gatheringTimer = (npc.gatheringTimer or 0) + dt

    -- Determine duration based on personality
    local duration = 60 -- default
    if npc.personality == "social" then
        duration = 90
    elseif npc.personality == "grumpy" or npc.personality == "loner" then
        duration = 30
    end

    -- For lunch clusters, use a fixed duration (20-40 min game time scaled to real seconds)
    if npc.gatheringDuration then
        duration = npc.gatheringDuration
    end

    -- Set descriptive current action based on gathering type
    local gatherType = npc.gatheringType or "hanging out"
    if gatherType == "chatting" then
        npc.currentAction = "chatting"
    elseif gatherType == "lunching" then
        npc.currentAction = "lunching"
    else
        npc.currentAction = "hanging out"
    end

    -- Timer expired — dissolve and return to idle
    if npc.gatheringTimer >= duration then
        if self.npcSystem.settings.debugMode then
            print(string.format("[NPC Favor] %s finished %s (%.0fs)",
                npc.name, npc.currentAction, npc.gatheringTimer))
        end
        self:clearGatheringData(npc)
        self:setState(npc, self.STATES.IDLE)
    end
end

--- Clear all gathering-related data from an NPC.
-- @param npc  NPC data table
function NPCAI:clearGatheringData(npc)
    npc.gatheringPosition = nil
    npc.gatheringCenter = nil
    npc.gatheringType = nil
    npc.gatheringTimer = nil
    npc.gatheringDuration = nil
    npc.gatheringData = nil
    npc.groupSpeechTimer = nil
end

--- Find the nearest other NPC who is also in GATHERING state (a group-mate).
-- Used to pick a "conversation partner" for speech bubble generation during group gatherings.
-- @param npc  The NPC looking for a partner
-- @return NPC table or nil
function NPCAI:findNearestGatheringPartner(npc)
    if not self.npcSystem or not self.npcSystem.activeNPCs then return nil end
    local bestDist = 15
    local bestPartner = nil
    for _, other in ipairs(self.npcSystem.activeNPCs) do
        if other ~= npc and other.isActive and other.aiState == self.STATES.GATHERING then
            local dx = other.position.x - npc.position.x
            local dz = other.position.z - npc.position.z
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist < bestDist then
                bestDist = dist
                bestPartner = other
            end
        end
    end
    return bestPartner
end

--- Try to form a small chatting group of 3-4 NPCs (including the initiator).
-- Finds 2-3 other idle/walking NPCs within 30m, picks a center point,
-- and arranges everyone in a loose circle.
-- @param npc  The NPC initiating group formation
-- @return boolean  true if group was formed, false if not enough NPCs
function NPCAI:tryFormGroup(npc)
    -- Find available partners within 30m
    local partners = self:findSocialPartners(npc, 30)

    -- Need at least 2 others for a group (3 total including initiator)
    if #partners < 2 then
        return false
    end

    -- Cap at 3 partners (4 total including initiator)
    local groupMembers = { npc }
    for i = 1, math.min(3, #partners) do
        table.insert(groupMembers, partners[i])
    end

    -- Calculate center point (average of all positions)
    local centerX, centerZ = 0, 0
    for _, member in ipairs(groupMembers) do
        centerX = centerX + member.position.x
        centerZ = centerZ + member.position.z
    end
    centerX = centerX / #groupMembers
    centerZ = centerZ / #groupMembers

    -- Offset center slightly toward nearest building for a natural feel
    local buildings = self.npcSystem:findNearbyBuildings(centerX, centerZ, 30)
    if #buildings > 0 then
        local nearest = buildings[1]
        local bdx = nearest.x - centerX
        local bdz = nearest.z - centerZ
        local bDist = math.sqrt(bdx * bdx + bdz * bdz)
        if bDist > 1 then
            -- Move center 20% toward the building (but not inside it)
            centerX = centerX + (bdx / bDist) * math.min(3, bDist * 0.2)
            centerZ = centerZ + (bdz / bDist) * math.min(3, bDist * 0.2)
        end
    end

    -- Ensure gathering center is not inside a building
    centerX, centerZ = self.npcSystem:getSafePosition(centerX, centerZ, nil)

    -- Get terrain height at center
    local centerY = 0
    if g_currentMission and g_currentMission.terrainRootNode then
        local okY, h = pcall(getTerrainHeightAtWorldPos,
            g_currentMission.terrainRootNode, centerX, 0, centerZ)
        if okY and h then
            centerY = h + 0.05
        end
    end

    local gatheringCenter = { x = centerX, y = centerY, z = centerZ }

    -- Assign each member a position in a loose circle (~2m radius)
    local radius = 2
    local angleStep = (math.pi * 2) / #groupMembers
    for i, member in ipairs(groupMembers) do
        local angle = angleStep * (i - 1) + math.random() * 0.3 -- slight randomness
        local posX = centerX + math.cos(angle) * radius
        local posZ = centerZ + math.sin(angle) * radius

        member.gatheringPosition = { x = posX, z = posZ }
        member.gatheringCenter = gatheringCenter
        member.gatheringType = "chatting"
        member.gatheringTimer = 0
        member.gatheringDuration = nil -- use personality-based default
        self:setState(member, self.STATES.GATHERING)
    end

    -- Notification
    if self.npcSystem.settings.showNotifications then
        local names = {}
        for _, member in ipairs(groupMembers) do
            table.insert(names, member.name)
        end
        self.npcSystem:showNotification(
            "NPC Group",
            string.format("%s are chatting together", table.concat(names, ", "))
        )
    end

    if self.npcSystem.settings.debugMode then
        print(string.format("[NPC Favor] Group of %d formed at (%.1f, %.1f)",
            #groupMembers, centerX, centerZ))
    end

    return true
end

--- Try to pair the NPC with a nearby walking/traveling NPC for a walking pair.
-- Called during commute hours (7-8 AM and 5-6 PM). Sets walkingPartner on
-- both NPCs so they stay close during movement.
-- @param npc  The NPC looking for a walking partner
-- @return boolean  true if a pair was formed
function NPCAI:tryFormWalkingPair(npc)
    -- Skip if already paired
    if npc.walkingPartner then
        return false
    end

    for _, otherNPC in ipairs(self.npcSystem.activeNPCs) do
        if otherNPC.id ~= npc.id and otherNPC.isActive and not otherNPC.walkingPartner then
            local distance = VectorHelper.distance3D(
                npc.position.x, npc.position.y, npc.position.z,
                otherNPC.position.x, otherNPC.position.y, otherNPC.position.z
            )

            -- Find another NPC within 20m that is walking or traveling
            if distance < 20 and
               (otherNPC.aiState == self.STATES.WALKING or otherNPC.aiState == self.STATES.TRAVELING) then
                -- Form the pair
                npc.walkingPartner = otherNPC
                otherNPC.walkingPartner = npc

                if self.npcSystem.settings.debugMode then
                    print(string.format("[NPC Favor] Walking pair: %s & %s",
                        npc.name, otherNPC.name))
                end

                return true
            end
        end
    end

    return false
end

--- Try to form a lunch cluster near a building during lunch hours (12-1 PM).
-- Groups of 2-4 NPCs in a casual semicircle facing the nearest building.
-- @param npc   The NPC initiating the cluster
-- @param hour  Current game hour
-- @return boolean  true if cluster was formed
function NPCAI:tryFormLunchCluster(npc, hour)
    -- Only during lunch hour
    if hour < 12 or hour >= 13 then
        return false
    end

    -- Find nearby buildings to cluster around
    local buildings = self.npcSystem:findNearbyBuildings(
        npc.position.x, npc.position.z, 30)
    if #buildings == 0 then
        return false
    end

    -- Pick the closest building
    local building = buildings[1]

    -- Find NPCs near this building (within 20m of each other and the building)
    local candidates = {}
    table.insert(candidates, npc)

    for _, otherNPC in ipairs(self.npcSystem.activeNPCs) do
        if otherNPC.id ~= npc.id and otherNPC.isActive then
            local distToBuilding = VectorHelper.distance3D(
                otherNPC.position.x, otherNPC.position.y or 0, otherNPC.position.z,
                building.x, building.y or 0, building.z
            )
            local distToNPC = VectorHelper.distance3D(
                npc.position.x, npc.position.y, npc.position.z,
                otherNPC.position.x, otherNPC.position.y, otherNPC.position.z
            )

            if distToBuilding < 20 and distToNPC < 20 and
               (otherNPC.aiState == self.STATES.IDLE or otherNPC.aiState == self.STATES.WALKING) then
                table.insert(candidates, otherNPC)
                if #candidates >= 4 then break end -- max 4 in a cluster
            end
        end
    end

    -- Need at least 2 for a lunch cluster
    if #candidates < 2 then
        return false
    end

    -- Calculate cluster center: offset 3m from the building toward the NPCs
    local avgX, avgZ = 0, 0
    for _, c in ipairs(candidates) do
        avgX = avgX + c.position.x
        avgZ = avgZ + c.position.z
    end
    avgX = avgX / #candidates
    avgZ = avgZ / #candidates

    -- Direction from building to NPC group — position outside the building
    local bdx = avgX - building.x
    local bdz = avgZ - building.z
    local bDist = math.sqrt(bdx * bdx + bdz * bdz)
    local bRadius = building.radius or 5
    local centerX, centerZ
    if bDist > 1 then
        centerX = building.x + (bdx / bDist) * (bRadius + 3)
        centerZ = building.z + (bdz / bDist) * (bRadius + 3)
    else
        centerX = building.x + bRadius + 3
        centerZ = building.z
    end

    -- Ensure cluster center is not inside any building
    centerX, centerZ = self.npcSystem:getSafePosition(centerX, centerZ, nil)

    -- Get terrain height at center
    local centerY = 0
    if g_currentMission and g_currentMission.terrainRootNode then
        local okY, h = pcall(getTerrainHeightAtWorldPos,
            g_currentMission.terrainRootNode, centerX, 0, centerZ)
        if okY and h then
            centerY = h + 0.05
        end
    end

    local gatheringCenter = { x = centerX, y = centerY, z = centerZ }

    -- Calculate lunch duration: 20-40 minutes game time
    -- FS25 default time scale: environment.timeScale (often 120x)
    -- At 120x, 1 real second = 2 game minutes, so 20 game min = 10 real sec
    -- We'll use 30-60 real seconds as a reasonable range
    local lunchDuration = 30 + math.random() * 30 -- 30-60 real seconds

    -- Arrange in semicircle facing the building
    local facingAngle = math.atan2(building.x - centerX, building.z - centerZ)
    local arcSpread = math.pi * 0.8 -- ~144 degree arc (semicircle)
    local arcStart = facingAngle - arcSpread / 2
    local arcStep = arcSpread / math.max(1, #candidates - 1)
    local radius = 2

    for i, member in ipairs(candidates) do
        local angle = arcStart + arcStep * (i - 1)
        local posX = centerX + math.sin(angle) * radius
        local posZ = centerZ + math.cos(angle) * radius

        member.gatheringPosition = { x = posX, z = posZ }
        member.gatheringCenter = gatheringCenter
        member.gatheringType = "lunching"
        member.gatheringTimer = 0
        member.gatheringDuration = lunchDuration
        self:setState(member, self.STATES.GATHERING)
    end

    -- Notification
    if self.npcSystem.settings.showNotifications then
        local names = {}
        for _, member in ipairs(candidates) do
            table.insert(names, member.name)
        end
        self.npcSystem:showNotification(
            "NPC Lunch",
            string.format("%s are having lunch together", table.concat(names, ", "))
        )
    end

    if self.npcSystem.settings.debugMode then
        print(string.format("[NPC Favor] Lunch cluster of %d formed near building at (%.1f, %.1f)",
            #candidates, building.x, building.z))
    end

    return true
end

function NPCAI:isAtHome(npc)
    if not npc.homePosition then
        return false
    end
    
    return self:isAtPosition(npc, npc.homePosition.x, npc.homePosition.z, 10)
end

--- Check if NPC is within tolerance distance of a 2D position.
-- @param npc        NPC data table
-- @param x          Target X
-- @param z          Target Z
-- @param tolerance  Max distance (default 5)
-- @return boolean
function NPCAI:isAtPosition(npc, x, z, tolerance)
    local dx = x - npc.position.x
    local dz = z - npc.position.z
    local distance = math.sqrt(dx * dx + dz * dz)

    return distance <= (tolerance or 5)
end

-- NOTE: updateGatheringState is defined in the "Social Grouping Behaviors"
-- section above. It handles both Step 8 group formations (gatheringPosition/
-- gatheringCenter) and Step 9 event-based gatherings (gatheringData).

-- =========================================================
-- Dynamic Event Behavior Support (Step 9)
-- =========================================================
-- These methods implement NPC behavior during emergent events
-- triggered by NPCSystem:updateEventScheduler(). Each event
-- type has distinct behavior patterns. Events do not override
-- player interaction -- NPCs can still be talked to.
-- =========================================================

--- Start event-specific behavior for an NPC.
-- Routes to the appropriate behavior based on event type.
-- @param npc        NPC data table
-- @param eventType  Event type string: "party", "harvest", "market", "sunday_rest", "rain_shelter"
-- @param eventData  Event-specific data table
function NPCAI:startEventBehavior(npc, eventType, eventData)
    if not npc or not npc.isActive then
        return
    end

    eventData = eventData or {}

    if eventType == "party" then
        -- Walk to host location, then socialize
        npc.currentAction = "partying"
        local targetX = eventData.targetX or npc.position.x
        local targetZ = eventData.targetZ or npc.position.z
        self:startWalkingTo(npc, targetX, targetZ)
        self:setState(npc, self.STATES.WALKING)

        -- After arriving, the NPC will transition to socializing via idle decision
        -- Store event data for the gathering behavior after arrival
        npc.gatheringData = {
            centerX = targetX,
            centerZ = targetZ,
            radius = 3,
            eventType = "party",
        }

    elseif eventType == "harvest" then
        -- Walk to field, then walk in rows using NPCFieldWork if available
        npc.currentAction = "harvesting"
        local field = eventData.field
        if field and field.center then
            local fieldWork = self.npcSystem and self.npcSystem.fieldWork
            if fieldWork then
                local waypoints, slot = fieldWork:getWorkPattern(npc, field)
                if waypoints and #waypoints > 0 then
                    npc.fieldWorkWaypoints = waypoints
                    npc.fieldWorkPath = waypoints
                    npc.fieldWorkIndex = self:_findNearestWaypointIndex(npc, waypoints)
                    npc.fieldWorkSlot = slot
                    npc._originalSpeed = npc._originalSpeed or npc.movementSpeed
                    npc.movementSpeed = 1.8
                    self:setState(npc, self.STATES.WORKING)
                else
                    self:walkFieldRows(npc, field, eventData.rowIndex or 0)
                end
            else
                self:walkFieldRows(npc, field, eventData.rowIndex or 0)
            end
        else
            -- Fallback: just set idle
            self:setState(npc, self.STATES.IDLE)
        end

    elseif eventType == "market" then
        -- Walk to shop area, mill about
        npc.currentAction = "at market"
        local centerX = eventData.centerX or npc.position.x
        local centerZ = eventData.centerZ or npc.position.z
        local radius = eventData.radius or 8

        -- Walk to market area first
        local angle = math.random() * math.pi * 2
        local offset = math.random() * radius * 0.5
        local targetX = centerX + math.cos(angle) * offset
        local targetZ = centerZ + math.sin(angle) * offset
        self:startWalkingTo(npc, targetX, targetZ)
        self:setState(npc, self.STATES.WALKING)

        -- Store mill-about data for when NPC arrives
        npc.gatheringData = {
            centerX = centerX,
            centerZ = centerZ,
            radius = radius,
            eventType = "market",
        }

    elseif eventType == "sunday_rest" then
        -- Stay near home or visit neighbors
        npc.currentAction = "day off"
        local phase = eventData.phase or "morning"

        if phase == "morning" then
            -- Mill about near home
            local homeX = eventData.homeX or npc.position.x
            local homeZ = eventData.homeZ or npc.position.z
            npc.gatheringData = {
                centerX = homeX,
                centerZ = homeZ,
                radius = 10,
                eventType = "sunday_rest",
            }
            self:setState(npc, self.STATES.GATHERING)
        elseif phase == "visit" then
            -- Walk to neighbor's home
            local targetX = eventData.targetX or npc.position.x
            local targetZ = eventData.targetZ or npc.position.z
            self:startWalkingTo(npc, targetX, targetZ)
            self:setState(npc, self.STATES.WALKING)

            npc.gatheringData = {
                centerX = targetX,
                centerZ = targetZ,
                radius = 5,
                eventType = "sunday_visit",
            }
        end

    elseif eventType == "rain_shelter" then
        -- Walk to nearest building at increased speed
        npc.currentAction = "sheltering"
        local targetX = eventData.targetX or npc.position.x
        local targetZ = eventData.targetZ or npc.position.z

        -- Increase movement speed (hurrying through rain) -- 1.5x normal
        if not npc._originalSpeed then
            npc._originalSpeed = npc.movementSpeed
        end
        npc.movementSpeed = npc._originalSpeed * 1.5

        self:startWalkingTo(npc, targetX, targetZ)
        self:setState(npc, self.STATES.WALKING)

        -- After arriving, cluster near the building
        npc.gatheringData = {
            centerX = targetX,
            centerZ = targetZ,
            radius = 3,
            eventType = "shelter",
        }

    else
        if self.npcSystem.settings.debugMode then
            print(string.format("[NPC Favor] Unknown event type '%s' for NPC %s",
                tostring(eventType), npc.name or "?"))
        end
    end
end

--- DEPRECATED: Use NPCFieldWork:getWorkPattern() instead.
-- Generate a zigzag path across a field for harvest behavior.
-- NPCs walk in parallel rows across the field. Each NPC gets a
-- lateral offset based on their rowIndex to simulate parallel work.
-- @param npc       NPC data table
-- @param field     Field data table with .center and .size
-- @param rowIndex  Row index (0, 1, 2...) for lateral offset between NPCs
function NPCAI:walkFieldRows(npc, field, rowIndex)
    if not field or not field.center then
        self:setState(npc, self.STATES.IDLE)
        return
    end

    rowIndex = rowIndex or 0
    local cx = field.center.x
    local cz = field.center.z

    -- Estimate field half-size from field.size (area in sq meters) or use default
    local fieldSize = 50  -- default half-width in meters
    if field.size and field.size > 0 then
        fieldSize = math.sqrt(field.size) / 2
        fieldSize = math.max(15, math.min(100, fieldSize))  -- clamp to reasonable range
    end

    -- Lateral offset for parallel rows (5m between workers)
    local lateralOffset = rowIndex * 5

    -- Generate zigzag waypoints: walk east-west across field, step north each pass
    local path = {}
    local numPasses = 4  -- number of zigzag passes
    local stepZ = (fieldSize * 2) / numPasses

    for pass = 0, numPasses - 1 do
        local z = cz - fieldSize + pass * stepZ + lateralOffset
        local startX, endX

        if pass % 2 == 0 then
            startX = cx - fieldSize
            endX = cx + fieldSize
        else
            startX = cx + fieldSize
            endX = cx - fieldSize
        end

        -- Snap Y to terrain
        local startY = self:getTerrainHeightSafe(startX, z)
        local endY = self:getTerrainHeightSafe(endX, z)

        table.insert(path, {x = startX, y = startY, z = z})
        table.insert(path, {x = endX, y = endY, z = z})
    end

    if #path > 0 then
        npc.path = path
        npc.targetPosition = path[#path]
        npc.currentAction = "harvesting"
        self:setState(npc, self.STATES.WALKING)
    else
        self:setState(npc, self.STATES.IDLE)
    end
end

--- Mill-about behavior: NPC wanders randomly within a radius of a center point.
-- Used during market, party, and gathering events. NPC picks a random nearby
-- point, walks to it, pauses briefly, then picks another.
-- @param npc      NPC data table
-- @param centerX  Center X of the mill-about area
-- @param centerZ  Center Z of the mill-about area
-- @param radius   Maximum wander radius in meters
-- @param dt       Delta time in seconds
function NPCAI:millAbout(npc, centerX, centerZ, radius, dt)
    radius = radius or 5

    -- Initialize mill-about timer if not set
    npc.millAboutTimer = (npc.millAboutTimer or 0) + (dt or 0)
    npc.millAboutPause = npc.millAboutPause or 0

    -- If pausing, count down
    if npc.millAboutPause > 0 then
        npc.millAboutPause = npc.millAboutPause - (dt or 0)

        -- Occasionally face toward center while pausing
        if math.random() < 0.02 then
            local dx = centerX - npc.position.x
            local dz = centerZ - npc.position.z
            if math.abs(dx) > 0.1 or math.abs(dz) > 0.1 then
                npc.rotation.y = math.atan2(dx, dz)
            end
        end
        return
    end

    -- If no path or path completed, pick a new random point
    if not npc.path or #npc.path == 0 then
        local angle = math.random() * math.pi * 2
        local dist = math.random() * radius
        local targetX = centerX + math.cos(angle) * dist
        local targetZ = centerZ + math.sin(angle) * dist

        -- Snap to terrain
        local targetY = self:getTerrainHeightSafe(targetX, targetZ)

        npc.path = {{x = targetX, y = targetY, z = targetZ}}
        npc.targetPosition = {x = targetX, y = targetY, z = targetZ}

        -- Set a pause after reaching the target (3-5 seconds)
        npc.millAboutNextPause = 3 + math.random() * 2
    else
        -- Walk toward the current path target
        self:updateWalkingState(npc, dt or 0)

        -- If path just emptied (arrived), set pause
        if not npc.path or #npc.path == 0 then
            npc.millAboutPause = npc.millAboutNextPause or 4
            npc.millAboutNextPause = 3 + math.random() * 2
        end
    end
end

--- Get terrain height safely (utility for event methods).
-- @param x  World X
-- @param z  World Z
-- @return number  Y position snapped to terrain (default 0)
function NPCAI:getTerrainHeightSafe(x, z)
    if g_currentMission and g_currentMission.terrainRootNode then
        local ok, h = pcall(getTerrainHeightAtWorldPos,
            g_currentMission.terrainRootNode, x, 0, z)
        if ok and h then
            return h + 0.05
        end
    end
    return 0
end

-- =========================================================
-- Feature 8a: Player Greeting System
-- =========================================================
-- When the player comes within 10m, NPCs turn to face them and
-- display a greeting based on time of day, relationship, personality,
-- and recent encounter memory.

--- Check if NPC should greet the player and generate greeting text.
function NPCAI:checkPlayerGreeting(npc, playerPos, dt)
    if not npc or not playerPos then return end

    local dx = playerPos.x - npc.position.x
    local dz = playerPos.z - npc.position.z
    local distance = math.sqrt(dx * dx + dz * dz)

    if distance > 10 then return end

    local gameTime = self.npcSystem:getCurrentGameTime()
    local lastGreeting = npc.lastGreetingTime or 0
    if gameTime - lastGreeting < 60000 then return end

    if npc.currentAction == "stepping aside" then return end
    if npc.aiState == self.STATES.DRIVING then return end

    npc.lastGreetingTime = gameTime

    if math.abs(dx) > 0.01 or math.abs(dz) > 0.01 then
        npc.rotation.y = math.atan2(dx, dz)
    end

    local greeting = self:generateGreeting(npc, gameTime)
    npc.greetingText = greeting
    npc.greetingTimer = 3.0
    npc.currentAction = "greeting"

    -- Pause field work if NPC is working on foot (not in vehicle)
    -- NPC will stop walking their rows, face the player, show greeting,
    -- then resume work exactly where they left off after ~3 seconds.
    if npc.aiState == self.STATES.WORKING and not npc.currentVehicle then
        npc._greetingPause = true
    end

    if self.npcSystem.recordEncounter then
        self.npcSystem:recordEncounter(npc, "talked", "greeting", nil, "positive")
    end
end

--- Generate a context-appropriate greeting string for an NPC.
function NPCAI:generateGreeting(npc, gameTime)
    if npc.encounters and #npc.encounters > 0 then
        local lastEncounter = npc.encounters[1]
        if lastEncounter then
            if lastEncounter.type == "favor_completed" then
                return "Thanks again for the help!"
            elseif lastEncounter.type == "favor_failed" then
                return "I'm still waiting on that favor..."
            elseif lastEncounter.type == "gift_given" then
                return "That was very generous of you!"
            elseif lastEncounter.type == "helped" then
                return "I appreciate what you did!"
            end
        end
    end

    if npc.personality == "grumpy" then
        local grumpyGreetings = {"What do you want?", "Hmph.", "*grunt*", "..."}
        return grumpyGreetings[math.random(1, #grumpyGreetings)]
    end

    local relationship = npc.relationship or 50
    local townRep = self.npcSystem.townReputation or 50
    if townRep > 70 then
        relationship = math.min(100, relationship + 10)
    elseif townRep < 30 then
        relationship = math.max(0, relationship - 10)
    end

    if relationship > 70 then
        local warmGreetings = {
            "Great to see you!", "Hey there, friend!", "Always a pleasure!",
            "Good to see you again!", "Welcome back!"
        }
        return warmGreetings[math.random(1, #warmGreetings)]
    elseif relationship < 30 then
        local coldGreetings = {"Hmm.", "Oh. It's you.", "...", "What now?"}
        return coldGreetings[math.random(1, #coldGreetings)]
    end

    -- Player vehicle context: acknowledge if player is in a vehicle
    local isInVehicle = false
    pcall(function()
        if g_localPlayer and g_localPlayer.getIsInVehicle and g_localPlayer:getIsInVehicle() then
            isInVehicle = true
        end
    end)
    if isInVehicle then
        local vehicleGreetings = {
            "Nice ride!", "Watch the speed there!", "Careful with that thing!",
            "Looking busy today!", "Hard at work, I see!"
        }
        if math.random() < 0.4 then
            return vehicleGreetings[math.random(1, #vehicleGreetings)]
        end
    end

    -- NPC state-aware greetings
    if npc.aiState == "working" then
        local workGreetings = {"Can't talk long, busy working!", "Fields won't tend themselves!", "Just taking a quick break."}
        if math.random() < 0.3 then
            return workGreetings[math.random(1, #workGreetings)]
        end
    end

    -- Mood-aware greetings
    if npc.mood == "tired" then
        return "I'm so tired today..."
    elseif npc.mood == "stressed" then
        return "Not the best day..."
    elseif npc.mood == "happy" then
        local happyGreetings = {"What a great day!", "Feeling wonderful!", "Life is good!"}
        return happyGreetings[math.random(1, #happyGreetings)]
    end

    local hour = 12
    pcall(function() hour = self.npcSystem.scheduler:getCurrentHour() end)

    if hour >= 5 and hour < 12 then
        return "Morning!"
    elseif hour >= 12 and hour < 17 then
        return "Good afternoon!"
    elseif hour >= 17 and hour < 21 then
        return "Evening!"
    else
        return "Hello there"
    end
end

-- =========================================================
-- Feature 8b: Vehicle Reaction System
-- =========================================================

--- Check if player is driving a vehicle near the NPC and make NPC dodge.
function NPCAI:checkVehicleReaction(npc, playerPos, dt)
    if not npc or not playerPos then return end
    if npc.dodgeTimer and npc.dodgeTimer > 0 then return end
    if npc.aiState == self.STATES.DRIVING or npc.aiState == self.STATES.RESTING then return end

    local dx = playerPos.x - npc.position.x
    local dz = playerPos.z - npc.position.z
    local distance = math.sqrt(dx * dx + dz * dz)
    if distance > 15 then return end

    local isInVehicle = false
    local playerSpeed = 0

    pcall(function()
        if g_localPlayer and g_localPlayer.getIsInVehicle and g_localPlayer:getIsInVehicle() then
            isInVehicle = true
            local sys = self.npcSystem
            sys._prevPlayerPos = sys._prevPlayerPos or {x = playerPos.x, y = playerPos.y, z = playerPos.z}
            sys._playerSpeedTimer = (sys._playerSpeedTimer or 0) + dt
            if sys._playerSpeedTimer > 0.1 then
                local pdx = playerPos.x - sys._prevPlayerPos.x
                local pdz = playerPos.z - sys._prevPlayerPos.z
                local posDelta = math.sqrt(pdx * pdx + pdz * pdz)
                playerSpeed = posDelta / sys._playerSpeedTimer
                sys._prevPlayerPos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
                sys._playerSpeedTimer = 0
            end
        end
    end)

    if not isInVehicle then return end
    if playerSpeed < 2.8 then return end

    local sys = self.npcSystem
    local prevPos = sys._prevPlayerPos or playerPos
    local moveDirX = playerPos.x - (prevPos.x or playerPos.x)
    local moveDirZ = playerPos.z - (prevPos.z or playerPos.z)
    local moveDirLen = math.sqrt(moveDirX * moveDirX + moveDirZ * moveDirZ)

    if moveDirLen < 0.01 then
        moveDirX = npc.position.x - playerPos.x
        moveDirZ = npc.position.z - playerPos.z
        moveDirLen = math.sqrt(moveDirX * moveDirX + moveDirZ * moveDirZ)
    end
    if moveDirLen < 0.01 then return end

    local perpX = -moveDirZ / moveDirLen
    local perpZ = moveDirX / moveDirLen

    local testX1 = npc.position.x + perpX * 2
    local testZ1 = npc.position.z + perpZ * 2
    local testX2 = npc.position.x - perpX * 2
    local testZ2 = npc.position.z - perpZ * 2
    local dist1 = math.sqrt((testX1 - playerPos.x)^2 + (testZ1 - playerPos.z)^2)
    local dist2 = math.sqrt((testX2 - playerPos.x)^2 + (testZ2 - playerPos.z)^2)

    local dodgeX, dodgeZ
    if dist1 > dist2 then dodgeX, dodgeZ = perpX, perpZ
    else dodgeX, dodgeZ = -perpX, -perpZ end

    local dodgeDist = 2 + math.random() * 1
    npc.position.x = npc.position.x + dodgeX * dodgeDist
    npc.position.z = npc.position.z + dodgeZ * dodgeDist

    if g_currentMission and g_currentMission.terrainRootNode then
        local okY, newY = pcall(getTerrainHeightAtWorldPos,
            g_currentMission.terrainRootNode, npc.position.x, 0, npc.position.z)
        if okY and newY then npc.position.y = newY + 0.05 end
    end

    npc.rotation.y = math.atan2(dx, dz)
    npc.currentAction = "stepping aside"
    npc.dodgeTimer = 3.0

    if self.npcSystem.settings.debugMode then
        print(string.format("[NPC Favor] %s stepped aside from vehicle (speed=%.1f m/s)",
            npc.name or "?", playerSpeed))
    end
end

-- =========================================================
-- Vehicle Commuting & Transport Mode
-- =========================================================
-- NPCs choose between walking, driving a car, or driving a tractor
-- based on distance and profession. The entity manager provides
-- visual props (car/tractor i3d nodes) that are shown during the
-- commute and parked at the destination on arrival.
--
-- Speed constants:
--   Walking:       ~1.4 m/s (npc.movementSpeed, default)
--   Car driving:    8.3 m/s (~30 km/h)
--   Tractor driving: 5.5 m/s (~20 km/h)
-- =========================================================

--- Choose how the NPC should travel based on distance and profession.
-- @param npc       NPC data table
-- @param distance  Distance to destination in meters
-- @return string   "walk", "drive_car", or "drive_tractor"
function NPCAI:chooseTransportMode(npc, distance)
    -- If NPC has a real tractor and is far from field, they can drive
    if npc.realTractor and distance > 100
       and self.npcSystem and self.npcSystem.settings
       and self.npcSystem.settings.npcVehicleMode == "realistic" then
        return "drive_tractor"
    end

    -- Vehicle commute for long distances — only if a commute vehicle pool exists
    if distance > 150 and self.npcSystem and self.npcSystem.settings
       and self.npcSystem.settings.npcDriveVehicles
       and self.npcSystem.COMMUTE_VEHICLE_POOL
       and #self.npcSystem.COMMUTE_VEHICLE_POOL > 0 then
        return "drive_car"
    end

    return "walk"
end

--- Start commuting to a destination using the chosen transport mode.
-- Shows the appropriate vehicle prop, sets movement speed, and initiates driving.
-- Falls back to walking if vehicle prop is unavailable.
-- @param npc       NPC data table
-- @param targetX   Destination X world position
-- @param targetZ   Destination Z world position
-- @param callback  Callback string for arrival ("startWorking", "goHome", etc.)
function NPCAI:startCommute(npc, targetX, targetZ, callback)
    local dx = targetX - npc.position.x
    local dz = targetZ - npc.position.z
    local distance = math.sqrt(dx * dx + dz * dz)

    local mode = self:chooseTransportMode(npc, distance)

    if mode == "walk" then
        -- Walk there, with speed boost for commute distances
        -- Skip generic 2× boost if a movement mode is already set (e.g. evening run/sprint)
        if distance > 100 and not npc._movementMode then
            -- Temporarily boost speed for long walks (brisk commute)
            npc._originalSpeed = npc._originalSpeed or npc.movementSpeed
            npc.movementSpeed = npc._originalSpeed * 2.0  -- brisk walk / jog
            npc.currentAction = "commuting"
        end
        self:startWalkingTo(npc, targetX, targetZ)
        if distance > 200 then
            self:setState(npc, self.STATES.TRAVELING)
        else
            self:setState(npc, self.STATES.WALKING)
        end
        return
    end

    -- Try to get a vehicle from assigned vehicles for the DRIVING state
    local vehicle = nil
    if npc.assignedVehicles and #npc.assignedVehicles > 0 then
        for _, v in ipairs(npc.assignedVehicles) do
            if v.isAvailable then
                vehicle = v
                break
            end
        end
    end

    -- If no assigned vehicle available, create a virtual vehicle entry for the commute
    -- (the visual prop is handled by the entity manager, the "vehicle" here is just state)
    if not vehicle then
        vehicle = {
            type = (mode == "drive_tractor") and "tractor" or "car",
            isAvailable = true,
            isVirtualCommute = true
        }
    end

    local started = self:startDriving(npc, vehicle)
    if not started then
        -- Driving failed, fall back to walking
        self:startWalkingTo(npc, targetX, targetZ)
        self:setState(npc, self.STATES.WALKING)
        return
    end

    -- Set driving destination and callback
    npc.driveDestination = { x = targetX, z = targetZ }
    npc.driveCallback = callback
    npc.transportMode = mode

    -- Set appropriate movement speed based on transport mode
    if mode == "drive_car" then
        npc.driveSpeed = 8.3    -- ~30 km/h
        npc.currentAction = "driving car"
    else
        npc.driveSpeed = 5.5    -- ~20 km/h
        npc.currentAction = "driving tractor"
    end

    -- Show the appropriate vehicle prop via entity manager
    local entityMgr = self.npcSystem.entityManager
    if entityMgr then
        if mode == "drive_car" then
            pcall(function()
                entityMgr:showVehicleProp(npc, true)
            end)
        elseif mode == "drive_tractor" then
            pcall(function()
                entityMgr:showTractorProp(npc, true)
            end)
        end
    end

    -- Hide walking character — real commute vehicle takes over visually.
    -- Restored by removeNPCCar on arrival or if spawn fails.
    pcall(function()
        local ent = entityMgr and entityMgr.npcEntities and entityMgr.npcEntities[npc.id]
        if ent and ent.node then setVisibility(ent.node, false) end
    end)

    -- Spawn the commute vehicle (async). driveDestination is already set above
    -- so spawnNPCCar can offset the spawn point away from the home building.
    if self.npcSystem.spawnNPCCar then
        npc.pendingVehicleLoad = true
        self.npcSystem:spawnNPCCar(npc, nil)
    end
end

--- Handle NPC arrival after a vehicle commute.
-- Hides the driving vehicle, parks it near the destination, and restores
-- normal NPC appearance (ground level, canInteract = true).
-- @param npc       NPC data table
-- @param destX     Arrival X position
-- @param destZ     Arrival Z position
function NPCAI:handleDrivingArrival(npc, destX, destZ)
    local mode = npc.transportMode or "drive_car"
    local entityMgr = self.npcSystem.entityManager

    if entityMgr then
        -- Calculate a parking position 5-8m from the destination
        local parkOffset = 5 + math.random() * 3
        local parkAngle = math.random() * math.pi * 2
        local parkX = destX + math.cos(parkAngle) * parkOffset
        local parkZ = destZ + math.sin(parkAngle) * parkOffset

        if mode == "drive_car" then
            -- Park the car prop near the destination
            pcall(function()
                entityMgr:parkVehicle(npc, parkX, parkZ)
            end)
        elseif mode == "drive_tractor" then
            -- Hide the tractor prop (tractors don't "park" in town, they stay at field)
            pcall(function()
                entityMgr:showTractorProp(npc, false)
            end)
        end
    end

    -- Remove real commute vehicle before restoring NPC appearance
    if npc.realCar and self.npcSystem.removeNPCCar then
        self.npcSystem:removeNPCCar(npc)
    end

    -- Clean up transport state
    npc.transportMode = nil
    npc.driveSpeed = nil
    npc.canInteract = true
end

-- =========================================================
-- NPCPathfinder — Waypoint-based pathfinding with LRU cache
-- =========================================================
-- Generates linear paths with intermediate waypoints for long
-- distances, random perpendicular variation for natural movement,
-- terrain height snapping, water avoidance, and path optimization
-- (removes waypoints with < 30° direction change).
-- =========================================================

NPCPathfinder = {}
NPCPathfinder_mt = Class(NPCPathfinder)

--- Create a new NPCPathfinder.
-- @return NPCPathfinder instance with empty path cache
function NPCPathfinder.new()
    local self = setmetatable({}, NPCPathfinder_mt)
    
    -- Pathfinding settings
    self.maxPathLength = 1000
    self.avoidWater = true
    self.avoidSteepSlopes = true
    self.maxSlope = 30 -- degrees
    
    -- Cache for frequently used paths
    self.pathCache = {}
    self.cacheSize = 50

    -- Road spline data (populated once at map load via discoverRoadSplines)
    self.roadSplines = {}
    self.pedestrianSplines = {}
    self.splinesDiscovered = false

    return self
end

--- Find a path from start to end, using cache if available.
-- Long distances get intermediate waypoints with perpendicular variation.
-- @param startX  Start X world position
-- @param startZ  Start Z world position
-- @param endX    End X world position
-- @param endZ    End Z world position
-- @return table  Array of {x, y, z} waypoints
function NPCPathfinder:findPath(startX, startZ, endX, endZ)
    -- Check cache first
    local cacheKey = string.format("%.1f_%.1f_%.1f_%.1f", startX, startZ, endX, endZ)
    if self.pathCache[cacheKey] then
        return self:clonePath(self.pathCache[cacheKey])
    end

    -- Try road-following path first (spline-based)
    if self.splinesDiscovered and #self.roadSplines > 0 then
        local roadPath = self:findRoadPath(startX, startZ, endX, endZ)
        if roadPath and #roadPath > 1 then
            self:cachePath(cacheKey, roadPath)
            return roadPath
        end
    end

    -- Calculate direct distance
    local directDistance = VectorHelper.distance2D(startX, startZ, endX, endZ)
    
    -- Simple pathfinding for now - direct line with obstacle avoidance
    local path = {}
    
    -- Add start point
    local startY = 0
    if g_currentMission and g_currentMission.terrainRootNode then
        local okS, hS = pcall(getTerrainHeightAtWorldPos, g_currentMission.terrainRootNode, startX, 0, startZ)
        if okS and hS then startY = hS end
    end
    table.insert(path, {x = startX, y = startY, z = startZ})
    
    -- For long distances, add intermediate points
    if directDistance > 50 then
        local segments = math.min(5, math.floor(directDistance / 50))
        for i = 1, segments do
            local t = i / (segments + 1)
            local x = startX + (endX - startX) * t
            local z = startZ + (endZ - startZ) * t

            -- Add random variation to avoid straight lines
            if segments > 1 and i < segments then
                local perpendicularX, perpendicularZ = VectorHelper.getPerpendicular(endX - startX, endZ - startZ)
                local variation = math.random(-10, 10)
                x = x + perpendicularX * variation / directDistance
                z = z + perpendicularZ * variation / directDistance
            end

            -- Push waypoint out of buildings (if NPCSystem is available)
            local npcSys = getfenv(0)["g_NPCSystem"]
            if npcSys and npcSys.getSafePosition then
                local safeX, safeZ = npcSys:getSafePosition(x, z, nil)
                x = safeX
                z = safeZ
            end

            -- Steep terrain check: if this waypoint is on a cliff relative to the
            -- previous point, nudge it sideways to find a gentler route
            local prevPoint = path[#path]
            local y = self:getSafeTerrainHeight(x, z)
            if prevPoint then
                local rise = math.abs(y - prevPoint.y)
                local hDist = math.sqrt((x - prevPoint.x)^2 + (z - prevPoint.z)^2)
                if hDist > 0.1 and rise / hDist > 1.5 then
                    -- Try nudging perpendicular to find gentler terrain
                    local perpX = -(z - prevPoint.z) / hDist
                    local perpZ =  (x - prevPoint.x) / hDist
                    local bestX, bestZ, bestY, bestRise = x, z, y, rise
                    for _, offset in ipairs({15, -15, 30, -30}) do
                        local tryX = x + perpX * offset
                        local tryZ = z + perpZ * offset
                        local tryY = self:getSafeTerrainHeight(tryX, tryZ)
                        local tryRise = math.abs(tryY - prevPoint.y)
                        if tryRise < bestRise then
                            bestX, bestZ, bestY, bestRise = tryX, tryZ, tryY, tryRise
                        end
                    end
                    x, z, y = bestX, bestZ, bestY
                end
            end

            table.insert(path, {x = x, y = y, z = z})
        end
    end
    
    -- Add end point
    local endY = self:getSafeTerrainHeight(endX, endZ)
    table.insert(path, {x = endX, y = endY, z = endZ})
    
    -- Optimize path (remove unnecessary points)
    path = self:optimizePath(path)

    -- Smooth corners with Bezier curves (3k: smoother NPC walking paths)
    if #path >= 3 and VectorHelper.smoothPath then
        local smoothed = VectorHelper.smoothPath(path, 4)
        -- Re-apply terrain heights to smoothed points
        if smoothed and #smoothed > 0 then
            for _, pt in ipairs(smoothed) do
                pt.y = self:getSafeTerrainHeight(pt.x, pt.z)
            end
            path = smoothed
        end
    end

    -- Cache the path
    self:cachePath(cacheKey, path)
    
    return path
end

function NPCPathfinder:getSafeTerrainHeight(x, z)
    if not g_currentMission or not g_currentMission.terrainRootNode then
        return 0
    end

    local terrainRoot = g_currentMission.terrainRootNode
    local okH, height = pcall(getTerrainHeightAtWorldPos, terrainRoot, x, 0, z)
    if not okH then height = nil end

    if not height then
        -- Fallback: use nearby terrain height
        for offset = 1, 10 do
            for angle = 0, math.pi * 2, math.pi / 4 do
                local checkX = x + math.cos(angle) * offset
                local checkZ = z + math.sin(angle) * offset
                local okC, checkHeight = pcall(getTerrainHeightAtWorldPos, terrainRoot, checkX, 0, checkZ)
                if okC and checkHeight then
                    return checkHeight
                end
            end
        end
        return 0
    end

    -- Check if location is in water (getWaterTypeAtWorldPos may not exist)
    if self.avoidWater then
        local okW, waterType = pcall(function()
            return getWaterTypeAtWorldPos(terrainRoot, x, 0, z)
        end)
        if okW and waterType and waterType > 0 then
            -- Try to find nearby land
            for offset = 5, 50, 5 do
                for angle = 0, math.pi * 2, math.pi / 8 do
                    local checkX = x + math.cos(angle) * offset
                    local checkZ = z + math.sin(angle) * offset
                    local okCH, checkHeight = pcall(getTerrainHeightAtWorldPos, terrainRoot, checkX, 0, checkZ)
                    local okCW, checkWater = pcall(function()
                        return getWaterTypeAtWorldPos(terrainRoot, checkX, 0, checkZ)
                    end)
                    if okCH and checkHeight and (not okCW or not checkWater or checkWater == 0) then
                        return checkHeight
                    end
                end
            end
        end
    end

    return height
end

function NPCPathfinder:optimizePath(path)
    if #path <= 2 then
        return path
    end
    
    local optimized = {}
    table.insert(optimized, path[1])
    
    for i = 2, #path - 1 do
        local prev = optimized[#optimized]
        local current = path[i]
        local next = path[i + 1]
        
        -- Check if current point is necessary
        local angle1 = VectorHelper.angleBetween(prev.x, prev.z, current.x, current.z)
        local angle2 = VectorHelper.angleBetween(current.x, current.z, next.x, next.z)
        local angleDiff = math.abs(angle1 - angle2)
        
        -- Keep point if it causes significant direction change
        if angleDiff > math.pi / 6 then -- 30 degrees
            table.insert(optimized, current)
        end
    end
    
    table.insert(optimized, path[#path])
    
    return optimized
end

function NPCPathfinder:cachePath(key, path)
    -- Add to cache
    self.pathCache[key] = self:clonePath(path)
    
    -- Limit cache size
    local keys = {}
    for k in pairs(self.pathCache) do
        table.insert(keys, k)
    end
    
    if #keys > self.cacheSize then
        -- Remove oldest entries (simplified: remove random ones)
        while #keys > self.cacheSize do
            local removeKey = table.remove(keys, math.random(1, #keys))
            self.pathCache[removeKey] = nil
        end
    end
end

function NPCPathfinder:clonePath(path)
    local clone = {}
    for _, point in ipairs(path) do
        table.insert(clone, {
            x = point.x,
            y = point.y,
            z = point.z
        })
    end
    return clone
end

function NPCPathfinder:update(dt)
    -- One-time spline discovery at map load
    if not self.splinesDiscovered then
        self:discoverRoadSplines()
        self.splinesDiscovered = true
    end

    -- Clean old cache entries periodically
    self.cacheCleanupTimer = (self.cacheCleanupTimer or 0) + dt
    if self.cacheCleanupTimer > 60 then -- Clean every minute
        self.cacheCleanupTimer = 0

        -- Count cache entries (# operator doesn't work on hash tables in Lua 5.1)
        local keys = {}
        for k in pairs(self.pathCache) do
            table.insert(keys, k)
        end

        -- Evict oldest half when cache exceeds 2x limit
        if #keys > self.cacheSize then
            local removeCount = #keys - self.cacheSize
            for i = 1, removeCount do
                self.pathCache[keys[i]] = nil
            end
        end
    end
end

-- =========================================================
-- Road Spline Discovery & Following
-- =========================================================
-- NPCs discover road/pedestrian splines from the scene graph
-- at map load and use them for natural road-following movement
-- instead of straight-line pathfinding.
-- =========================================================

--- Discover road and pedestrian splines from the scene graph.
-- Runs once at map load. Traverses the scene root to find
-- trafficSystem and pedestrianSystem transform groups, then
-- caches all valid spline nodes for pathfinding.
function NPCPathfinder:discoverRoadSplines()
    self.roadSplines = {}
    self.pedestrianSplines = {}

    local okRoot, rootNode = pcall(getRootNode)
    if not okRoot or not rootNode then
        print("[NPC Favor] Could not get root node for spline discovery")
        return
    end

    local trafficGroup = nil
    local pedestrianGroup = nil

    -- Find trafficSystem and pedestrianSystem transform groups
    local okChildren, numChildren = pcall(getNumOfChildren, rootNode)
    if not okChildren or not numChildren then
        print("[NPC Favor] Could not enumerate root children for spline discovery")
        return
    end

    for i = 0, numChildren - 1 do
        local okChild, child = pcall(getChildAt, rootNode, i)
        if okChild and child then
            local okName, name = pcall(getName, child)
            if okName and name then
                if name == "trafficSystem" then
                    trafficGroup = child
                elseif name == "pedestrianSystem" then
                    pedestrianGroup = child
                end
            end
        end
    end

    -- Also search one level deeper (some maps nest under a map root node)
    if not trafficGroup and not pedestrianGroup then
        for i = 0, numChildren - 1 do
            local okChild, child = pcall(getChildAt, rootNode, i)
            if okChild and child then
                local okSub, numSub = pcall(getNumOfChildren, child)
                if okSub and numSub then
                    for j = 0, numSub - 1 do
                        local okGrandchild, grandchild = pcall(getChildAt, child, j)
                        if okGrandchild and grandchild then
                            local okName, name = pcall(getName, grandchild)
                            if okName and name then
                                if name == "trafficSystem" then
                                    trafficGroup = grandchild
                                elseif name == "pedestrianSystem" then
                                    pedestrianGroup = grandchild
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local roadCount = 0
    local pedCount = 0

    -- Collect splines from pedestrian system
    if pedestrianGroup then
        local okPC, pedChildren = pcall(getNumOfChildren, pedestrianGroup)
        if okPC and pedChildren then
            for i = 0, pedChildren - 1 do
                local okNode, node = pcall(getChildAt, pedestrianGroup, i)
                if okNode and node then
                    local okLen, length = pcall(getSplineLength, node)
                    if okLen and length and length > 0 then
                        local okN, splineName = pcall(getName, node)
                        local entry = {
                            node = node,
                            length = length,
                            name = okN and splineName or ("pedSpline_" .. i),
                            isPedestrian = true,
                            sideOffset = 0
                        }
                        table.insert(self.roadSplines, entry)
                        table.insert(self.pedestrianSplines, entry)
                        pedCount = pedCount + 1
                    end
                end
            end
        end
    end

    -- Collect splines from traffic system
    if trafficGroup then
        local okTC, trafficChildren = pcall(getNumOfChildren, trafficGroup)
        if okTC and trafficChildren then
            for i = 0, trafficChildren - 1 do
                local okNode, node = pcall(getChildAt, trafficGroup, i)
                if okNode and node then
                    local okLen, length = pcall(getSplineLength, node)
                    if okLen and length and length > 0 then
                        local okN, splineName = pcall(getName, node)
                        local entry = {
                            node = node,
                            length = length,
                            name = okN and splineName or ("roadSpline_" .. i),
                            isPedestrian = false,
                            sideOffset = 2.5  -- Walk on roadside, not center lane
                        }
                        table.insert(self.roadSplines, entry)
                        roadCount = roadCount + 1
                    end
                end
            end
        end
    end

    print(string.format("[NPC Favor] Discovered %d road splines, %d pedestrian splines",
        roadCount, pedCount))
end

--- Find the nearest cached spline to a world position.
-- @param x        World X
-- @param y        World Y
-- @param z        World Z
-- @param maxDist  Maximum search distance (default 50)
-- @return table   {spline=entry, t=parameter, distance=dist} or nil
function NPCPathfinder:findNearestSpline(x, y, z, maxDist)
    maxDist = maxDist or 50
    local best = nil
    local bestDist = maxDist

    for _, spline in ipairs(self.roadSplines) do
        local okT, t = pcall(getClosestSplinePosition, spline.node, x, y, z)
        if okT and t then
            local okPos, sx, sy, sz = pcall(getSplinePosition, spline.node, t)
            if okPos and sx and sy and sz then
                local dx = x - sx
                local dy = y - sy
                local dz = z - sz
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dist < bestDist then
                    bestDist = dist
                    best = {
                        spline = spline,
                        t = t,
                        distance = dist
                    }
                end
            end
        end
    end

    return best
end

--- Get a walkable position along a spline, with side offset for traffic splines.
-- For traffic splines (sideOffset > 0), computes a perpendicular offset so
-- NPCs walk on the roadside rather than in the center lane.
-- @param spline  Spline entry table from self.roadSplines
-- @param t       Spline parameter (0-1)
-- @return x, y, z  World position snapped to terrain
function NPCPathfinder:getSplineWalkPosition(spline, t)
    -- Clamp t to valid range
    t = math.max(0, math.min(1, t))

    local okPos, sx, sy, sz = pcall(getSplinePosition, spline.node, t)
    if not okPos or not sx then
        return nil, nil, nil
    end

    -- Apply side offset for traffic splines (walk on roadside, not center)
    if spline.sideOffset and spline.sideOffset > 0 then
        local okDir, dx, dy, dz = pcall(getSplineDirection, spline.node, t)
        if okDir and dx and dz then
            -- Perpendicular in XZ plane: rotate direction 90 degrees
            local perpX = -dz
            local perpZ = dx
            -- Normalize the perpendicular vector
            local perpLen = math.sqrt(perpX * perpX + perpZ * perpZ)
            if perpLen > 0.001 then
                perpX = perpX / perpLen
                perpZ = perpZ / perpLen
            end
            sx = sx + perpX * spline.sideOffset
            sz = sz + perpZ * spline.sideOffset
        end
    end

    -- Snap Y to terrain height
    if g_currentMission and g_currentMission.terrainRootNode then
        local okH, h = pcall(getTerrainHeightAtWorldPos,
            g_currentMission.terrainRootNode, sx, 0, sz)
        if okH and h then
            sy = h + 0.05
        end
    end

    return sx, sy, sz
end

--- Build a road-following path between two world positions using cached splines.
-- Finds the nearest spline to start and end, then generates waypoints along
-- the spline at ~5m intervals. Returns nil if no suitable spline is found
-- (caller should fall through to direct-line pathfinding).
-- @param startX  Start X world position
-- @param startZ  Start Z world position
-- @param endX    End X world position
-- @param endZ    End Z world position
-- @return table  Array of {x, y, z} waypoints, or nil
function NPCPathfinder:findRoadPath(startX, startZ, endX, endZ)
    -- Get terrain Y for start/end
    local startY = self:getSafeTerrainHeight(startX, startZ)
    local endY = self:getSafeTerrainHeight(endX, endZ)

    -- Find nearest spline to start and end positions
    local startResult = self:findNearestSpline(startX, startY, startZ, 50)
    local endResult = self:findNearestSpline(endX, endY, endZ, 50)

    -- If either position has no nearby spline, fall through to direct path
    if not startResult or not endResult then
        return nil
    end

    -- For now, only handle same-spline routing (multi-spline routing is future work)
    if startResult.spline.node ~= endResult.spline.node then
        return nil
    end

    local spline = startResult.spline
    local startT = startResult.t
    local endT = endResult.t

    -- Build the 3-phase path
    local path = {}

    -- Phase 1: Walk from start position to the road entry point
    local entryX, entryY, entryZ = self:getSplineWalkPosition(spline, startT)
    if not entryX then
        return nil
    end
    table.insert(path, {x = startX, y = startY, z = startZ})
    table.insert(path, {x = entryX, y = entryY, z = entryZ})

    -- Phase 2: Follow spline from startT to endT at ~5m intervals
    -- Determine direction: choose shorter path along spline
    local forwardDist   -- distance going startT -> endT (increasing t)
    local backwardDist  -- distance going startT -> endT (decreasing t)
    local isClosed = false
    local okClosed, closed = pcall(getIsSplineClosed, spline.node)
    if okClosed and closed then
        isClosed = true
    end

    if isClosed then
        -- For closed splines, both directions are valid
        if endT >= startT then
            forwardDist = (endT - startT) * spline.length
            backwardDist = (1 - endT + startT) * spline.length
        else
            forwardDist = (1 - startT + endT) * spline.length
            backwardDist = (startT - endT) * spline.length
        end
    else
        -- For open splines, only forward/backward along the line
        forwardDist = math.abs(endT - startT) * spline.length
        backwardDist = forwardDist  -- same distance either way on open spline
    end

    -- Choose direction: positive step = increasing t, negative = decreasing t
    local goForward
    if isClosed then
        goForward = (forwardDist <= backwardDist)
    else
        goForward = (endT >= startT)
    end

    -- Calculate step size in t-parameter space (~5m intervals)
    local stepDist = 5  -- meters between waypoints
    local stepT = stepDist / spline.length
    if stepT < 0.001 then stepT = 0.001 end

    -- Generate waypoints along the spline
    local currentT = startT
    local reachedEnd = false
    local maxSteps = math.ceil(spline.length / stepDist) + 1  -- safety limit

    for _ = 1, maxSteps do
        if reachedEnd then break end

        -- Advance t
        if goForward then
            currentT = currentT + stepT
            -- Check if we passed the end
            if isClosed then
                if currentT > 1 then currentT = currentT - 1 end
                -- Detect arrival: check if we crossed endT
                local prevT = currentT - stepT
                if prevT < 0 then prevT = prevT + 1 end
                if (prevT <= endT and currentT >= endT) or
                   (prevT > currentT and (currentT >= endT or prevT <= endT)) then
                    currentT = endT
                    reachedEnd = true
                end
            else
                if currentT >= endT then
                    currentT = endT
                    reachedEnd = true
                end
            end
        else
            currentT = currentT - stepT
            -- Check if we passed the end
            if isClosed then
                if currentT < 0 then currentT = currentT + 1 end
                local prevT = currentT + stepT
                if prevT > 1 then prevT = prevT - 1 end
                if (prevT >= endT and currentT <= endT) or
                   (prevT < currentT and (currentT <= endT or prevT >= endT)) then
                    currentT = endT
                    reachedEnd = true
                end
            else
                if currentT <= endT then
                    currentT = endT
                    reachedEnd = true
                end
            end
        end

        local wx, wy, wz = self:getSplineWalkPosition(spline, currentT)
        if wx then
            table.insert(path, {x = wx, y = wy, z = wz})
        end
    end

    -- Phase 3: Walk from road exit point to final destination
    local exitX, exitY, exitZ = self:getSplineWalkPosition(spline, endT)
    if exitX then
        -- Only add exit if it differs from last waypoint (avoid duplicate)
        local lastWP = path[#path]
        if lastWP then
            local dxE = exitX - lastWP.x
            local dzE = exitZ - lastWP.z
            if math.sqrt(dxE * dxE + dzE * dzE) > 1 then
                table.insert(path, {x = exitX, y = exitY, z = exitZ})
            end
        end
    end

    -- Add final destination
    table.insert(path, {x = endX, y = endY, z = endZ})

    return path
end