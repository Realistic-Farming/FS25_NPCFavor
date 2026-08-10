-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- [x] World-space interaction hint with pulse animation
-- [x] NPC name + relationship level display above NPC
-- [x] Corner HUD favor list with progress bars
-- [x] Time-remaining color coding (green/yellow/red)
-- [x] Time-of-day aware greetings
-- [x] Personality-aware conversation topics
-- [x] Localized conversation topics (all strings use g_i18n:getText with fallbacks)
-- [ ] Thought bubbles above NPCs showing their current activity
-- [ ] Exclamation mark icon when NPC has a new favor to offer
-- [ ] Question mark icon when NPC has pending favor objective nearby
-- [ ] Minimap integration (favor locations shown on minimap)
-- [ ] Favor tracking waypoints (navigate to favor objectives)
-- [ ] Animated interaction prompt (bouncing icon instead of just text pulse)
-- [ ] Favor completion celebration effect (particles/sound/screen flash)
-- [ ] Consolidate getPersonalityColor() duplication with NPCDialog.lua
-- [ ] Speech bubble UI for casual NPC comments (not dialog, just ambient)
-- [ ] Proximity-based auto-greet (NPC waves/nods when you pass nearby)
-- [ ] Favor priority markers (urgent favors pulse faster or show warning icon)
-- [ ] Distance indicator in favor list (how far away is the favor location)
-- [ ] Favor category icons (delivery, repair, social, etc.)
-- [x] Relationship change notifications ("+5 with John" floating text)
-- [ ] NPC portrait thumbnails in favor list
-- [ ] Collapsible favor list (toggle expand/collapse with keybind)
-- [ ] Sound effects for interaction hint appearance/disappearance
-- [ ] Custom icon overlays for different NPC states (working, idle, available)
-- [ ] Timer countdown warnings (notification when favor expires in 30 min)
-- [ ] Favor chain indicators (show if completing this unlocks another)
-- =========================================================

-- =========================================================
-- FS25 NPC Favor Mod - Interaction UI (HUD + Helper Methods)
-- =========================================================
-- Two responsibilities:
--
-- 1) World-space HUD rendering (called every frame from update):
--    - Floating "Press [E] to talk" hint above nearby NPCs (with pulse animation)
--    - NPC name + relationship level below the hint
--    - Corner HUD showing active favors list with progress bars and time-to-expire
--
-- 2) Helper methods called by NPCDialog.lua for dialog content:
--    - getGreetingForNPC()          — Time-of-day + relationship greeting
--    - getRandomConversationTopic() — Personality-aware random dialog
--    - getWorkStatusMessage()       — AI state description in NPC voice
--    - getPersonalityColor()        — RGB color per personality trait
--
-- Dialog rendering itself is handled by gui/NPCDialog.xml + src/gui/NPCDialog.lua.
--
-- FS25 overlay API: createImageOverlay() → setOverlayColor(id,...) → renderOverlay(id,...)
-- FS25 project() API: project(worldX, worldY, worldZ) → screenX, screenY, screenZ (0-1 normalized)
-- =========================================================

NPCInteractionUI = {}
NPCInteractionUI_mt = Class(NPCInteractionUI)

-- Mod-scoped i18n with Missing-reject (same class as MDMUtil.getModText / NPCDialog).
local NPC_UI_MOD_NAME = g_currentModName
local function getModText(key, fallback)
    if key == nil or key == "" then
        return fallback
    end
    local text = nil
    local modEnv = g_modEnvironments and g_modEnvironments[NPC_UI_MOD_NAME]
    local i18n = (modEnv and modEnv.i18n) or g_i18n
    if i18n ~= nil then
        local ok, result = pcall(function() return i18n:getText(key) end)
        if ok and type(result) == "string" and result ~= "" then
            text = result
        end
    end
    if type(text) ~= "string" or text == "" then
        return fallback
    end
    local lower = text:lower()
    if lower == tostring(key):lower()
        or text == ("$l10n_" .. key)
        or lower:find("^missing%s")
        or lower:find("^missing_")
        or lower:find("^missing '")
    then
        return fallback
    end
    return text
end

--- Create a new NPCInteractionUI instance.
-- @param npcSystem  NPCSystem reference (provides settings, favorSystem, scheduler, etc.)
-- @return NPCInteractionUI instance
function NPCInteractionUI.new(npcSystem)
    local self = setmetatable({}, NPCInteractionUI_mt)

    self.npcSystem = npcSystem           -- Back-reference to parent system

    -- World-space interaction hint state
    self.interactionHintVisible = false  -- Whether the hint is currently shown
    self.interactionHintNPC = nil        -- NPC the hint is attached to
    self.interactionHintTimer = 0        -- Accumulator for pulse animation

    -- HUD color palette (RGBA)
    self.UI_COLORS = {
        TEXT = {1, 1, 1, 1},                -- Standard white text
        TEXT_DIM = {0.8, 0.8, 0.8, 1},      -- Subdued text (relationship level)
        FAVOR_EASY = {0.3, 0.8, 0.3, 1},    -- Green: > 6 hours remaining
        FAVOR_MEDIUM = {0.8, 0.8, 0.3, 1},  -- Yellow: 2-6 hours remaining
        FAVOR_HARD = {0.8, 0.3, 0.3, 1}     -- Red: < 2 hours remaining
    }

    -- HUD text sizes (normalized screen height)
    self.UI_SIZES = {
        TEXT_SMALL = 0.014,
        TEXT_MEDIUM = 0.016
    }

    self.inputCooldown = 0       -- Debounce timer for input events
    self.animationTime = 0       -- Global animation accumulator

    -- 1x1 pixel overlay for drawing colored rectangles (FS25 requires overlay ID)
    self.bgOverlay = nil
    if createImageOverlay then
        self.bgOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end

    -- Floating text popups (e.g. "+1", "-2" relationship changes)
    self.floatingTexts = {}  -- {text, x, y, timer, r, g, b}

    return self
end

--- Add a floating text popup at a world position.
-- @param worldX  World X position
-- @param worldY  World Y position
-- @param worldZ  World Z position
-- @param text    Text to display (e.g. "+1")
-- @param r,g,b   Color values
function NPCInteractionUI:addFloatingText(worldX, worldY, worldZ, text, r, g, b)
    table.insert(self.floatingTexts, {
        text = text,
        worldX = worldX,
        worldY = worldY,
        worldZ = worldZ,
        timer = 2.0,  -- display for 2 seconds
        r = r or 0.3, g = g or 1, b = b or 0.3,
    })
end

-- =========================================================
-- Update Loop (logic only — no rendering here)
-- =========================================================

function NPCInteractionUI:update(dt)
    if self.inputCooldown > 0 then
        self.inputCooldown = self.inputCooldown - dt
    end
    self.animationTime = self.animationTime + dt

    -- Update hint timer (no rendering)
    if self.interactionHintVisible and self.interactionHintNPC then
        self.interactionHintTimer = self.interactionHintTimer + dt
    else
        self.interactionHintTimer = 0
    end

    -- Update floating text timers
    if self.floatingTexts then
        for i = #self.floatingTexts, 1, -1 do
            local ft = self.floatingTexts[i]
            ft.timer = ft.timer - dt
            ft.worldY = ft.worldY + dt * 0.5  -- float upward
            if ft.timer <= 0 then
                table.remove(self.floatingTexts, i)
            end
        end
    end
end

-- =========================================================
-- Draw Loop (rendering only — called from FSBaseMission.draw)
-- =========================================================
-- FS25 requires all renderOverlay/renderText calls to happen
-- inside draw callbacks, NOT update callbacks.

function NPCInteractionUI:draw()
    -- Skip NPC HUD rendering when a full-screen overlay is covering the screen.
    -- FS25 ingameMap.state: 1=hidden, 2=round minimap, 3=square minimap, 4=large map
    if g_currentMission then
        if g_currentMission.paused then
            return
        end
        -- Large map overlay
        local hud = g_currentMission.hud
        if hud and hud.ingameMap and hud.ingameMap.state == 4 then
            return
        end
        -- ESC / in-game menu open
        local igm = g_currentMission.inGameMenu
        if igm and igm.isOpen then
            return
        end
    end
    -- Any GUI dialog (shop, settings, our own NPC dialogs, etc.)
    if g_gui and g_gui.currentGui ~= nil then
        return
    end

    -- World-space interaction hint above NPC
    self:drawInteractionHint()

    -- Speech bubbles above NPCs with active greetingText
    self:drawSpeechBubbles()

    -- Name tags above NPC heads (within 15m)
    if self.npcSystem.settings.showNames then
        self:drawNameTags()
    end

    -- Floating relationship change text (+1, -2, etc.)
    self:drawFloatingTexts()

    -- NOTE: Favor list rendering moved to NPCFavorHUD (moveable HUD module).
    -- drawFavorList() method is kept below as reference but no longer called here.
end

--- Draw speech bubbles above NPCs who have active greeting/conversation text.
-- Renders for both player-greetings and NPC-NPC conversations.
function NPCInteractionUI:drawSpeechBubbles()
    if not self.npcSystem or not self.npcSystem.activeNPCs then return end

    for _, npc in ipairs(self.npcSystem.activeNPCs) do
        if npc.isActive and npc.greetingText and npc.greetingTimer and npc.greetingTimer > 0 then
            -- Check distance from player (only render within 30m)
            if self.npcSystem.playerPositionValid and self.npcSystem.playerPosition then
                local dx = npc.position.x - self.npcSystem.playerPosition.x
                local dz = npc.position.z - self.npcSystem.playerPosition.z
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist < 30 then
                    self:drawSpeechBubble(npc)
                end
            end
        end
    end
end

--- Draw a single speech bubble above an NPC.
-- @param npc  NPC data table with greetingText set
function NPCInteractionUI:drawSpeechBubble(npc)
    local worldY = npc.position.y + 2.3  -- above the name tag
    local screenX, screenY = self:projectWorldToScreen(npc.position.x, worldY, npc.position.z)
    if not screenX or not screenY then return end

    -- Fade out in the last second
    local alpha = math.min(1, npc.greetingTimer / 1.0)

    -- Background bubble
    if self.bgOverlay then
        local textLen = string.len(npc.greetingText) or 10
        local bubbleW = math.min(0.25, textLen * 0.005 + 0.04)
        local bubbleH = 0.022
        setOverlayColor(self.bgOverlay, 0.05, 0.05, 0.08, 0.75 * alpha)
        renderOverlay(self.bgOverlay, screenX - bubbleW / 2, screenY - 0.003, bubbleW, bubbleH)
    end

    -- Text
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(false)
    setTextColor(1, 1, 1, alpha)
    renderText(screenX, screenY, self.UI_SIZES.TEXT_SMALL, npc.greetingText)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

--- Draw name tags above NPC heads (visible within 15m).
-- Shows NPC name with personality-colored text.
function NPCInteractionUI:drawNameTags()
    if not self.npcSystem or not self.npcSystem.activeNPCs then return end
    if not self.npcSystem.playerPositionValid or not self.npcSystem.playerPosition then return end

    for _, npc in ipairs(self.npcSystem.activeNPCs) do
        -- Skip inactive, sleeping, or NPCs already showing interaction hint
        local skipNPC = not npc.isActive or npc.isSleeping
            or (npc == self.interactionHintNPC and self.interactionHintVisible)

        if not skipNPC then
            local dx = npc.position.x - self.npcSystem.playerPosition.x
            local dz = npc.position.z - self.npcSystem.playerPosition.z
            local dist = math.sqrt(dx * dx + dz * dz)

            if dist < 15 then
                -- Scale Y offset by distance: 1.8m up close, rising to 2.6m at 15m
                -- so the name tag doesn't sink onto the NPC's head at range
                local distFactor = math.min(1, dist / 15)
                local worldY = npc.position.y + 1.8 + distFactor * 0.8
                local screenX, screenY = self:projectWorldToScreen(npc.position.x, worldY, npc.position.z)
                if screenX and screenY then
                    -- Fade based on distance (fully opaque within 8m, fading to 0 at 15m)
                    local alpha = math.min(1, (15 - dist) / 7)

                    -- Name in personality color
                    local color = self:getPersonalityColor(npc.personality)
                    setTextAlignment(RenderText.ALIGN_CENTER)
                    setTextBold(false)
                    setTextColor(color[1], color[2], color[3], alpha)
                    renderText(screenX, screenY, self.UI_SIZES.TEXT_SMALL, npc.name or "")

                    -- Mood indicator below name (if mood is not neutral)
                    if npc.mood and npc.mood ~= "neutral" then
                        local moodIcons = {happy = "+", stressed = "!", tired = "~"}
                        local moodIcon = moodIcons[npc.mood]
                        if moodIcon then
                            local moodColors = {
                                happy = {0.3, 0.9, 0.3},
                                stressed = {0.9, 0.5, 0.2},
                                tired = {0.6, 0.6, 0.8},
                            }
                            local mc = moodColors[npc.mood] or {0.7, 0.7, 0.7}
                            setTextColor(mc[1], mc[2], mc[3], alpha * 0.8)
                            renderText(screenX, screenY - 0.015, self.UI_SIZES.TEXT_SMALL * 0.8, moodIcon)
                        end
                    end

                    setTextAlignment(RenderText.ALIGN_LEFT)
                end
            end
        end
    end
end

--- Draw floating relationship change text (+1, -2, etc.).
function NPCInteractionUI:drawFloatingTexts()
    if not self.floatingTexts then return end

    for _, ft in ipairs(self.floatingTexts) do
        local screenX, screenY = self:projectWorldToScreen(ft.worldX, ft.worldY, ft.worldZ)
        if screenX and screenY then
            local alpha = math.min(1, ft.timer / 0.5)  -- fade in last 0.5s
            setTextAlignment(RenderText.ALIGN_CENTER)
            setTextBold(true)
            setTextColor(ft.r, ft.g, ft.b, alpha)
            renderText(screenX, screenY, self.UI_SIZES.TEXT_MEDIUM, ft.text)
            setTextBold(false)
            setTextAlignment(RenderText.ALIGN_LEFT)
        end
    end
end

-- =========================================================
-- World-Space Interaction Hint (above NPC head)
-- =========================================================

function NPCInteractionUI:drawInteractionHint()
    if not self.interactionHintVisible or not self.interactionHintNPC then
        return
    end

    local npc = self.interactionHintNPC
    local x, y, z = npc.position.x, npc.position.y + 2.0, npc.position.z

    local screenX, screenY = self:projectWorldToScreen(x, y, z)

    if screenX and screenY then
        local pulse = 0.5 + 0.5 * math.sin(self.interactionHintTimer * 3)
        local text = g_i18n:getText("npc_interact_hint") -- or "Press [E] to talk"

        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextBold(true)
        setTextColor(1, 1, pulse, 1)
        renderText(screenX, screenY + 0.05, self.UI_SIZES.TEXT_MEDIUM, text)
        setTextBold(false)

        -- Draw NPC name and relationship level
        if self.npcSystem.settings.showNames then
            local relationship = self.npcSystem.relationshipManager:getRelationshipColor(npc.relationship)
            setTextColor(relationship.r, relationship.g, relationship.b, 1)
            renderText(screenX, screenY, self.UI_SIZES.TEXT_SMALL, npc.name)

            local level = self.npcSystem.relationshipManager:getRelationshipLevel(npc.relationship)
            setTextColor(self.UI_COLORS.TEXT_DIM[1], self.UI_COLORS.TEXT_DIM[2],
                        self.UI_COLORS.TEXT_DIM[3], self.UI_COLORS.TEXT_DIM[4])
            renderText(screenX, screenY - 0.02, self.UI_SIZES.TEXT_SMALL * 0.9, level.name)
        end

        setTextAlignment(RenderText.ALIGN_LEFT)
    end
end

function NPCInteractionUI:showInteractionHint(npc, distance)
    if distance < 2 then
        self:hideInteractionHint()
        return
    end

    self.interactionHintVisible = true
    self.interactionHintNPC = npc
    self.interactionHintTimer = 0
end

function NPCInteractionUI:hideInteractionHint()
    self.interactionHintVisible = false
    self.interactionHintNPC = nil
end

-- =========================================================
-- Corner HUD: Active Favors List
-- =========================================================

function NPCInteractionUI:updateFavorList()
    self.favorListNeedsUpdate = true
end

--- Draw the corner HUD showing active favors with progress bars.
-- Color-coded by time remaining: green (>6h), yellow (2-6h), red (<2h).
-- Shows up to 5 favors with an overflow count.
function NPCInteractionUI:drawFavorList()
    if not self.npcSystem.settings.showFavorList then
        return
    end

    local favors = self.npcSystem.favorSystem:getActiveFavors()
    if #favors == 0 then
        return
    end

    if not self.bgOverlay then
        return
    end

    local startX = 0.02
    local startY = 0.7
    local lineHeight = 0.02
    local maxFavors = 5

    -- Draw background using overlay (FS25 requires overlay ID as first arg)
    local bgHeight = math.min(#favors, maxFavors) * lineHeight + 0.03
    setOverlayColor(self.bgOverlay, 0.1, 0.1, 0.1, 0.7)
    renderOverlay(self.bgOverlay, startX - 0.01, startY - bgHeight + 0.02, 0.25, bgHeight)

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
    setTextBold(true)
    renderText(startX, startY, self.UI_SIZES.TEXT_MEDIUM, g_i18n:getText("npc_hud_active_favors") or "Active Favors:")
    setTextBold(false)

    for i = 1, math.min(#favors, maxFavors) do
        local favor = favors[i]
        local yPos = startY - (i * lineHeight)

        local timeRemaining = favor.timeRemaining or 0
        local hours = timeRemaining / (60 * 60 * 1000)

        local timeText
        if hours < 1 then
            timeText = string.format("%.0fm", hours * 60)
        else
            timeText = string.format("%.1fh", hours)
        end

        local npcName = favor.npcName
        if string.len(npcName) > 12 then
            npcName = string.sub(npcName, 1, 10) .. "..."
        end

        local text = string.format("%s - %s [%s]",
            npcName,
            string.sub(favor.description, 1, 20) .. (string.len(favor.description) > 20 and "..." or ""),
            timeText)

        local textColor = self.UI_COLORS.TEXT
        if hours < 2 then
            textColor = self.UI_COLORS.FAVOR_HARD
        elseif hours < 6 then
            textColor = self.UI_COLORS.FAVOR_MEDIUM
        else
            textColor = self.UI_COLORS.FAVOR_EASY
        end

        setTextColor(textColor[1], textColor[2], textColor[3], textColor[4])

        if favor.progress and favor.progress > 0 then
            text = text .. string.format(" (%d%%)", favor.progress)
        end

        renderText(startX, yPos, self.UI_SIZES.TEXT_SMALL, text)

        if favor.progress and favor.progress > 0 then
            local barWidth = 0.1
            local barHeight = 0.005
            local barY = yPos - 0.008

            -- Background bar
            setOverlayColor(self.bgOverlay, 0.1, 0.1, 0.1, 0.8)
            renderOverlay(self.bgOverlay, startX, barY, barWidth, barHeight)

            -- Progress bar
            local progressWidth = barWidth * (favor.progress / 100)
            setOverlayColor(self.bgOverlay, textColor[1], textColor[2], textColor[3], 0.8)
            renderOverlay(self.bgOverlay, startX, barY, progressWidth, barHeight)
        end
    end

    if #favors > maxFavors then
        local yPos = startY - ((maxFavors + 1) * lineHeight)
        setTextColor(0.7, 0.7, 0.7, 1)
        renderText(startX, yPos, self.UI_SIZES.TEXT_SMALL * 0.9,
                   string.format(g_i18n:getText("npc_hud_and_more") or "...and %d more", #favors - maxFavors))
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
end

-- =========================================================
-- Helper Methods (called by NPCDialog.lua)
-- =========================================================

--- Get RGB color for a personality trait (for text coloring).
-- NOTE: Duplicated in NPCDialog:getPersonalityColor(). See note there.
-- @param personality  Personality string (e.g., "hardworking", "lazy")
-- @return table  {r, g, b} color values
function NPCInteractionUI:getPersonalityColor(personality)
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
    return colors[personality] or {0.8, 0.8, 0.8}
end

--- Generate a time-of-day greeting adjusted by relationship level.
-- Low relationship = curt/dismissive, high = warm/friendly.
-- @param npc  NPC data table (uses npc.relationship)
-- @return string  Greeting text
function NPCInteractionUI:getGreetingForNPC(npc)
    local hour = self.npcSystem.scheduler:getCurrentHour()
    local relationship = npc.relationship

    -- 4i: Birthday check
    if npc.birthdayMonth and npc.birthdayDay and self.npcSystem.scheduler then
        local currentMonth = self.npcSystem.scheduler.currentMonth or 1
        local currentDay = self.npcSystem.scheduler.currentDay or 1
        if currentMonth == npc.birthdayMonth and currentDay == npc.birthdayDay then
            if relationship >= 40 then
                return "It's my birthday today! Thanks for stopping by to celebrate!"
            else
                return "It's my birthday, actually. Nice of you to visit."
            end
        end
    end

    local timeGreeting = ""
    if hour < 12 then
        timeGreeting = getModText("npc_greeting_morning", "Good morning")
    elseif hour < 18 then
        timeGreeting = getModText("npc_greeting_afternoon", "Good afternoon")
    else
        timeGreeting = getModText("npc_greeting_evening", "Good evening")
    end

    -- Mood-aware greeting prefix
    local moodPrefix = ""
    if npc.mood == "happy" then
        moodPrefix = "What a great day! "
    elseif npc.mood == "stressed" then
        moodPrefix = "Been a rough day... "
    elseif npc.mood == "tired" then
        moodPrefix = "*yawn* "
    end

    -- Greeting tiers aligned with 7-tier relationship system:
    -- 0-9 Hostile, 10-24 Unfriendly, 25-39 Neutral, 40-59 Acquaintance,
    -- 60-74 Friend, 75-89 Close Friend, 90-100 Best Friend
    if relationship < 10 then
        return moodPrefix .. string.format(getModText("npc_greeting_hostile", "%s. ...Do I know you?"), timeGreeting)
    elseif relationship < 25 then
        return moodPrefix .. string.format(getModText("npc_greeting_unfriendly", "%s. Need something?"), timeGreeting)
    elseif relationship < 40 then
        return moodPrefix .. string.format(getModText("npc_greeting_neutral", "%s. What can I do for you?"), timeGreeting)
    elseif relationship < 60 then
        return moodPrefix .. getModText("npc_dialog_hello", "Hello there, neighbor!")
    elseif relationship < 75 then
        return moodPrefix .. string.format(getModText("npc_greeting_friendly", "%s, friend! How are you?"), timeGreeting)
    elseif relationship < 90 then
        return moodPrefix .. string.format(getModText("npc_greeting_close_friend", "%s! Always great to see you!"), timeGreeting)
    else
        return moodPrefix .. string.format(getModText("npc_greeting_best_friend", "%s, my good friend! Great to see you!"), timeGreeting)
    end
end

--- Pick a random conversation topic based on relationship level and personality.
-- @param npc  NPC data table
-- @return string  Conversation line
function NPCInteractionUI:getRandomConversationTopic(npc)
    local topics = {}

    -- Conversation depth scales with relationship (strangers get small talk)
    if npc.relationship < 25 then
        topics = {
            g_i18n:getText("npc_topic_weather") or "The weather has been nice lately, hasn't it?",
            g_i18n:getText("npc_topic_farm") or "How's your farm doing?",
            g_i18n:getText("npc_topic_crops") or "Seen any good crops this season?"
        }
    elseif npc.relationship < 60 then
        topics = {
            g_i18n:getText("npc_topic_family") or "How's the family doing?",
            g_i18n:getText("npc_topic_weekend") or "Got any plans for the weekend?",
            g_i18n:getText("npc_topic_market") or "The market prices have been good this season."
        }
    else
        topics = {
            g_i18n:getText("npc_topic_friend") or "Good to see you, friend! How have you been?",
            g_i18n:getText("npc_topic_harvest_memory") or "Remember that time we helped each other with harvest?",
            g_i18n:getText("npc_topic_best_neighbor") or "You're one of the best neighbors I've had!"
        }
    end

    if npc.personality == "farmer" or npc.personality == "hardworking" then
        table.insert(topics, g_i18n:getText("npc_topic_fields_good") or "The fields are looking good this year.")
        table.insert(topics, g_i18n:getText("npc_topic_harvest_busy") or "Harvest season is always busy but rewarding.")
    elseif npc.personality == "social" then
        table.insert(topics, g_i18n:getText("npc_topic_other_neighbors") or "Have you talked to the other neighbors lately?")
        table.insert(topics, g_i18n:getText("npc_topic_gathering") or "We should have a neighborhood gathering sometime!")
    elseif npc.personality == "loner" then
        table.insert(topics, g_i18n:getText("npc_topic_quiet_day") or "Quiet day today. I like it that way.")
    end

    -- Inject context-aware topics from companion mods
    local npcSys = self.npcSystem

    -- FS25_RandomWorldEvents — NPC reacts to the active world event
    local rwe = npcSys and npcSys.rweManager
    if rwe and rwe.EVENT_STATE and rwe.EVENT_STATE.activeEvent then
        local ev = rwe.EVENT_STATE.activeEvent
        local rweTopics = {
            market_boom        = "Prices are fantastic right now — have you been selling? The markets are on fire!",
            market_crash       = "Terrible week for prices... I'm holding back my grain until things improve.",
            export_opportunity = "Word is there's huge demand overseas right now. Perfect time to sell everything you've got!",
            economic_crisis    = "Things are tough all around. I've been cutting back wherever I can.",
            government_subsidy = "Did you hear about the subsidies? Government helping out farmers for once!",
            price_fixing       = "Something feels off with the markets lately. Prices don't make sense.",
            crop_yield_penalty = "My crops are struggling this season. I've never seen yields this poor.",
            crop_yield_bonus   = "What a harvest! My fields produced more than I expected. Wonderful season!",
            harvest_bonus      = "Couldn't have asked for better harvesting conditions. Everything went smoothly!",
            harvest_penalty    = "Lost a lot during harvest this year. Weather and timing just didn't cooperate.",
            seed_growth_bonus  = "Crops shot up faster than usual this year. Ideal growing conditions!",
            seed_growth_penalty = "Slow growth this year. I'm worried some crops won't be ready in time.",
            fertilizer_bonus   = "The fertilizer is working amazingly well this season. Rich soil makes all the difference.",
            fertilizer_penalty = "I've been losing nutrients out of my fields faster than I can replace them.",
            disease_scare      = "Keep an eye on your animals — there's a disease scare going around.",
            feed_shortage      = "Animal feed is getting expensive and hard to come by. Stock up when you can.",
        }
        local evTopic = rweTopics[ev]
        if evTopic then
            table.insert(topics, evTopic)
            table.insert(topics, evTopic)  -- double weight so event topic comes up often
        end
    end

    -- FS25_MarketDynamics — NPC mentions market conditions
    local md = npcSys and npcSys.marketDynamicsManager
    if md and md.marketEngine then
        local hasGoodPrices, hasBadPrices = false, false
        for _, entry in pairs(md.marketEngine.prices) do
            if entry.current and entry.base and entry.base > 0 then
                local pct = (entry.current - entry.base) / entry.base
                if pct > 0.12 then hasGoodPrices = true end
                if pct < -0.12 then hasBadPrices = true end
            end
        end
        if hasGoodPrices then
            table.insert(topics, "The commodity prices are looking really strong. Don't wait too long to sell!")
        elseif hasBadPrices then
            table.insert(topics, "I'd hold off selling anything major right now. Prices are below where I want them.")
        end
    end

    if #topics == 0 then
        return "Nice to see you!"
    end
    return topics[math.random(1, #topics)]
end

--- Get a first-person description of the NPC's current activity.
-- @param npc  NPC data table
-- @return string  Work status message in NPC's voice
function NPCInteractionUI:getWorkStatusMessage(npc)
    if not npc.currentAction then
        return getModText("npc_work_nothing", "I'm not doing much right now.")
    end

    local messages = {
        idle = getModText("npc_work_idle", "I'm taking a break at the moment."),
        walking = getModText("npc_work_walking", "Just getting some exercise."),
        working = getModText("npc_work_working", "Working on the field. It's hard work but someone's got to do it!"),
        driving = getModText("npc_work_driving", "Making some deliveries with my vehicle."),
        resting = getModText("npc_work_resting", "Taking it easy for a while."),
        socializing = getModText("npc_work_socializing", "Chatting with a neighbor."),
        traveling = getModText("npc_work_traveling", "Heading somewhere important.")
    }

    -- Status line only. AskWork appends scheduler:getScheduleSummary once (no double schedule).
    return messages[npc.currentAction] or getModText("npc_work_busy", "I'm keeping busy.")
end

--- Get upcoming schedule entries for an NPC (next 3 activities).
-- Prefer scheduler:getScheduleSummary for dialog AskWork; this helper remains for other callers.
-- @param npc  NPC data table
-- @return string  Formatted upcoming schedule, or nil
function NPCInteractionUI:getUpcomingSchedule(npc)
    if not self.npcSystem or not self.npcSystem.scheduler then return nil end

    local scheduler = self.npcSystem.scheduler
    local schedule = scheduler:getScheduleForNPC(npc)
    if not schedule then return nil end

    local currentHour = scheduler:getCurrentHour()
    -- Find upcoming slots (sorted by time, starting after current hour)
    local upcoming = {}
    for _, slot in ipairs(schedule) do
        if slot.start > currentHour and #upcoming < 3 then
            table.insert(upcoming, slot)
        end
    end

    if #upcoming == 0 then return nil end

    local parts = {getModText("npc_schedule_plans", "My plans:")}
    for _, slot in ipairs(upcoming) do
        local activityName = slot.activity or "idle"
        local displayName = scheduler:getActivityDisplayName(activityName) or activityName
        table.insert(parts, string.format("  %d:00 - %s", math.floor(slot.start), displayName))
    end
    return table.concat(parts, "\n")
end

-- =========================================================
-- Utility
-- =========================================================

--- Project a 3D world position to 2D screen coordinates (0-1 normalized).
-- @param worldX  World X position
-- @param worldY  World Y position
-- @param worldZ  World Z position
-- @return number, number  screenX, screenY (or nil, nil if behind camera or off-screen)
function NPCInteractionUI:projectWorldToScreen(worldX, worldY, worldZ)
    -- FS25 project() takes 3 args (no camera node) and returns normalized 0-1 coords + depth
    if not project then
        return nil, nil
    end

    -- First check: is the point actually in front of the camera?
    -- project() can return valid-looking screenX/screenY for points behind the camera
    -- (the projection math mirrors them), so we need to verify using the camera's
    -- forward vector dot product with the direction to the target.
    local camX, camY, camZ
    local dirX, dirY, dirZ
    local ok = pcall(function()
        local cam = getCamera()
        if cam and cam ~= 0 then
            camX, camY, camZ = getWorldTranslation(cam)
            dirX, dirY, dirZ = localDirectionToWorld(cam, 0, 0, -1)
        end
    end)

    if ok and camX and dirX then
        -- Vector from camera to target
        local toX = worldX - camX
        local toY = worldY - camY
        local toZ = worldZ - camZ
        -- Dot product: positive = in front, negative = behind
        local dot = toX * dirX + toY * dirY + toZ * dirZ
        if dot <= 0 then
            return nil, nil
        end
    end

    local screenX, screenY, screenZ = project(worldX, worldY, worldZ)

    -- screenZ check: must be within view frustum (0 < z < 1)
    -- and screen coords must be within visible area
    if screenX and screenY and screenZ and screenZ > 0 and screenZ < 1
        and screenX >= -0.1 and screenX <= 1.1
        and screenY >= -0.1 and screenY <= 1.1 then
        return screenX, screenY
    end

    return nil, nil
end

-- =========================================================
-- Cleanup
-- =========================================================

function NPCInteractionUI:delete()
    self:hideInteractionHint()
    if self.bgOverlay then
        delete(self.bgOverlay)
        self.bgOverlay = nil
    end
end
