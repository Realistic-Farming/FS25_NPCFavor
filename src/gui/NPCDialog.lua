-- =========================================================
-- TODO / FUTURE VISION
-- =========================================================
-- [x] 5 action buttons with 3-layer hover effects (Bitmap bg + invisible Button + Text)
-- [x] Relationship level display (0-100) with color coding (red→orange→yellow→green→blue)
-- [x] Personality-colored NPC name (8 personality types with distinct colors)
-- [x] Active favor progress display (shows %, time remaining, rewards)
-- [x] Rich relationship info with benefits and next-level unlocks (7-tier system)
-- [x] Response area that reveals on button clicks (hidden by default)
-- [x] Dynamic button text based on context ("Check favor progress" vs "Ask for favor")
-- [x] Relationship trend indicators (trending up/down)
-- [x] Favor statistics (completed, failed, success rate %)
-- [x] Greeting message generation based on personality
-- [ ] NPC portrait/avatar image in dialog (top-left corner, 128x128 circular frame?)
-- [ ] Branching dialog trees (not just single-action buttons — choose response A/B/C)
-- [ ] Dialog history / conversation log (scrollable panel showing past 5-10 exchanges)
-- [ ] Animated text reveal (typewriter effect for NPC responses, not instant)
-- [x] NPC mood indicator (happy/neutral/angry face icon next to name, changes based on recent interactions)
-- [x] Gift selection UI (choose from multiple gift types: money, crops, equipment, not just $500 hardcoded)
-- [ ] Favor acceptance/rejection dialog (player chooses which favor to accept from multiple offers)
-- [ ] Audio cues (sound effects on button hover/click, NPC voice samples on greet/respond?)
-- [ ] Consolidate getPersonalityColor() duplication with NPCInteractionUI (shared utility file?)
-- [x] Relationship decay warning ("You haven't talked to [NPC] in 3 days, relationship may drop")
-- [ ] Special event indicators (birthday, festival, holiday-specific dialog options)
-- [x] NPC schedule display ("Ask about plans" → shows their next 3 activities with timestamps)
-- [ ] Context-aware action buttons (if player owns borrowed equipment, show "Return equipment")
-- [ ] Multi-page response area (for long relationship info, add pagination or scrolling)
-- [x] Localization support (all hardcoded strings moved to translation files)
-- [ ] Favor quest details panel (expanded view with objectives, map markers, progress bars)
-- [x] NPC backstory/bio section ("Learn more about [NPC]" → shows personality traits, likes/dislikes)
-- [ ] Comparison view (show multiple NPCs' relationships side-by-side for prioritizing gifts/favors)
-- [ ] Accessibility features (keyboard navigation, colorblind-friendly relationship colors, larger text option)
-- =========================================================

-- =========================================================
-- FS25 NPC Favor Mod - NPC Interaction Dialog
-- =========================================================
-- MessageDialog subclass for face-to-face NPC conversations.
--
-- UI pattern: 3-layer buttons (Bitmap background + invisible Button
-- for hit detection + Text label) with color-shift hover effects.
-- XML binds onFocus/onLeave → per-button focus/leave handlers here.
--
-- 5 action buttons:
--   Talk             — Random conversation topic, +1 relationship (once per day)
--   Ask about work   — Shows NPC's current AI activity
--   Ask for favor    — Generate/check favor (requires Neutral 25+)
--   Give gift        — Spend $500 for relationship boost (requires Neutral 30+)
--   Relationship info — Shows level, benefits, next unlock, favor stats
--
-- Opened via NPCFavorGUI → DialogLoader pattern.
-- =========================================================

NPCDialog = {}
local NPCDialog_mt = Class(NPCDialog, MessageDialog)

-- Button color constants
NPCDialog.COLORS = {
    BTN_NORMAL   = {0.15, 0.15, 0.18, 1},     -- Default dark
    BTN_HOVER    = {0.22, 0.28, 0.38, 1},      -- Highlighted blue-ish on hover
    BTN_DISABLED = {0.08, 0.08, 0.08, 0.6},    -- Greyed out
    TXT_NORMAL   = {1, 1, 1, 1},               -- White text
    TXT_HOVER    = {0.7, 0.9, 1, 1},           -- Bright blue-white on hover
    TXT_DISABLED = {0.4, 0.4, 0.4, 1},         -- Grey text
}

--- Create a new NPCDialog instance.
-- @param target     Callback target for MessageDialog
-- @param custom_mt  Optional metatable override (defaults to NPCDialog_mt)
-- @return NPCDialog instance
function NPCDialog.new(target, custom_mt)
    local self = MessageDialog.new(target, custom_mt or NPCDialog_mt)

    self.npc = nil           -- Currently displayed NPC data table
    self.npcSystem = nil     -- NPCSystem reference (for subsystem access)

    -- Per-button enabled state — disabled buttons ignore hover effects
    self.buttonEnabled = {
        Talk = true,
        Work = true,
        Favor = false,
        Gift = false,
        Rel = true,
    }

    self.giftPanelVisible = false   -- True while the 3-tier gift selection panel is shown

    return self
end

function NPCDialog:onCreate()
    local ok, err = pcall(function()
        NPCDialog:superClass().onCreate(self)
    end)
    if not ok then
        print("[NPC Favor] NPCDialog:onCreate() superClass FAILED: " .. tostring(err))
    end
end

function NPCDialog:setNPCData(npc, npcSystem)
    self.npc = npc
    self.npcSystem = npcSystem
end

function NPCDialog:onOpen()
    local ok, err = pcall(function()
        NPCDialog:superClass().onOpen(self)
    end)
    if not ok then
        print("[NPC Favor] NPCDialog:onOpen() superClass FAILED: " .. tostring(err))
        return
    end

    -- Hide response area until an action is clicked
    if self.responseBg then
        self.responseBg:setVisible(false)
    end
    if self.responseText then
        self.responseText:setVisible(false)
    end

    -- Hide gift selection panel; initialize button texts from i18n
    self:hideGiftPanel()
    if self.giftSelectTitle   then self.giftSelectTitle:setText(g_i18n:getText("npc_gift_panel_title") or "Choose a gift:") end
    if self.btnGiftSmallText  then self.btnGiftSmallText:setText(g_i18n:getText("npc_gift_small_btn") or "Small Gift ($200)  +2 rel") end
    if self.btnGiftStandardText then self.btnGiftStandardText:setText(g_i18n:getText("npc_gift_standard_btn") or "Standard Gift ($500)  +5 rel") end
    if self.btnGiftGenerousText then self.btnGiftGenerousText:setText(g_i18n:getText("npc_gift_generous_btn") or "Generous Gift ($1,000)  +10 rel") end
    if self.btnGiftCancelText then self.btnGiftCancelText:setText(g_i18n:getText("npc_gift_cancel_btn") or "Cancel") end

    if self.npc and self.npcSystem then
        local ok2, err2 = pcall(function()
            self:updateDisplay()
            self:updateButtonStates()
        end)
        if not ok2 then
            print("[NPC Favor] NPCDialog:onOpen() updateDisplay FAILED: " .. tostring(err2))
        end
    end
end

-- =========================================================
-- Display
-- =========================================================

function NPCDialog:updateDisplay()
    local npc = self.npc
    if not npc then return end

    if self.npcNameText then
        self.npcNameText:setText(npc.name or g_i18n:getText("npc_dialog_unknown_npc") or "Unknown NPC")
    end

    if self.npcPersonalityText then
        local personality = npc.personality or "unknown"
        -- 4g: Show mood indicator alongside personality
        local moodIcon = ""
        if npc.mood then
            local moodSymbols = {happy = " [+]", neutral = "", stressed = " [!]", tired = " [~]"}
            moodIcon = moodSymbols[npc.mood] or ""
        end
        self.npcPersonalityText:setText("(" .. personality .. moodIcon .. ")")
        local color = self:getPersonalityColor(personality)
        -- Tint by mood: green=happy, orange=stressed, blue=tired
        if npc.mood == "happy" then
            self.npcPersonalityText:setTextColor(0.3, 0.9, 0.3, 1)
        elseif npc.mood == "stressed" then
            self.npcPersonalityText:setTextColor(0.9, 0.6, 0.2, 1)
        elseif npc.mood == "tired" then
            self.npcPersonalityText:setTextColor(0.5, 0.5, 0.8, 1)
        else
            self.npcPersonalityText:setTextColor(color[1], color[2], color[3], 1)
        end
    end

    if self.greetingText then
        local greeting = self:getGreeting()
        -- 3h: Append relationship decay warning if NPC hasn't been talked to recently
        local decayWarning = self:getDecayWarning()
        if decayWarning then
            greeting = greeting .. "\n" .. decayWarning
        end
        self.greetingText:setText("\"" .. greeting .. "\"")
    end

    if self.relationshipText then
        local relValue = npc.relationship or 0
        local levelName = self:getRelationshipLevelName(relValue)
        self.relationshipText:setText(string.format(g_i18n:getText("npc_dialog_relationship_fmt") or "Relationship: %d/100 (%s)", relValue, levelName))
        local r, g, b = self:getRelationshipColor(relValue)
        self.relationshipText:setTextColor(r, g, b, 1)
    end
end

-- =========================================================
-- Button State Management
-- =========================================================

function NPCDialog:updateButtonStates()
    local npc = self.npc
    if not npc then return end

    local relationship = npc.relationship or 0

    -- Talk - always enabled
    self:setButtonEnabled("Talk", true, g_i18n:getText("npc_dialog_btn_talk") or "Talk")

    -- Ask about work - always enabled
    self:setButtonEnabled("Work", true, g_i18n:getText("npc_dialog_btn_work") or "Ask about work")

    -- Ask for favor - needs Neutral relationship (25+)
    local favorEnabled = relationship >= 25
    local favorText = g_i18n:getText("npc_dialog_btn_favor") or "Ask for favor"

    if favorEnabled and self.npcSystem and self.npcSystem.favorSystem then
        local sys = self.npcSystem.favorSystem
        if sys.getPendingFavorForNPC and sys:getPendingFavorForNPC(npc.id) then
            favorText = g_i18n:getText("npc_dialog_btn_favor_accept") or "Accept Favor"
        elseif sys.getActiveFavorForNPC then
            local active = sys:getActiveFavorForNPC(npc.id)
            if active and active.steps then
                local readyStep = nil
                for _, step in ipairs(active.steps) do
                    if not step.completed and (step.isDialogStep or step.isLoanRepayStep) then
                        local priorDone = true
                        for _, s2 in ipairs(active.steps) do
                            if s2.id < step.id and not s2.completed then
                                priorDone = false
                                break
                            end
                        end
                        if priorDone then
                            readyStep = step
                            break
                        end
                    end
                end
                if readyStep and readyStep.isLoanRepayStep then
                    local loanAmt = (active.taskData and active.taskData.loanAmount) or 5000
                    favorText = string.format(g_i18n:getText("npc_favor_loan_repay_btn") or "Collect Repayment ($%d)", loanAmt)
                elseif readyStep then
                    favorText = g_i18n:getText("npc_dialog_btn_favor_complete") or "Complete favor"
                else
                    favorText = g_i18n:getText("npc_dialog_btn_favor_progress") or "Check favor progress"
                end
            end
        end
    end

    -- No active or pending favor — show "Offer help" to let player initiate
    if favorEnabled and favorText == (g_i18n:getText("npc_dialog_btn_favor") or "Ask for favor") then
        favorText = g_i18n:getText("npc_dialog_btn_offer_help") or "Offer help"
    end

    if not favorEnabled then
        favorText = g_i18n:getText("npc_dialog_btn_favor_locked") or "Offer help (need Neutral 25+)"
    end
    self:setButtonEnabled("Favor", favorEnabled, favorText)

    -- Give gift - needs relationship >= 30
    local giftEnabled = relationship >= 30
    local giftText = giftEnabled and (g_i18n:getText("npc_dialog_btn_gift") or "Give gift ($500)") or (g_i18n:getText("npc_dialog_btn_gift_locked") or "Give gift (need Neutral 30+)")
    self:setButtonEnabled("Gift", giftEnabled, giftText)

    -- Relationship info - always enabled
    self:setButtonEnabled("Rel", true, g_i18n:getText("npc_dialog_btn_relationship") or "Relationship info")
end

--- Set a 3-layer button's enabled/disabled state
function NPCDialog:setButtonEnabled(suffix, enabled, text)
    self.buttonEnabled[suffix] = enabled

    local bgElement = self["btn" .. suffix .. "Bg"]
    local textElement = self["btn" .. suffix .. "Text"]

    if bgElement then
        local c = enabled and self.COLORS.BTN_NORMAL or self.COLORS.BTN_DISABLED
        bgElement:setImageColor(nil, c[1], c[2], c[3], c[4])
    end

    if textElement then
        textElement:setText(text)
        local c = enabled and self.COLORS.TXT_NORMAL or self.COLORS.TXT_DISABLED
        textElement:setTextColor(c[1], c[2], c[3], c[4])
    end
end

-- =========================================================
-- Hover Effects (onFocus/onLeave from XML)
-- =========================================================

--- Apply hover highlight to a button's background and text
function NPCDialog:applyHover(suffix, isHovered)
    if not self.buttonEnabled[suffix] then return end

    local bgElement = self["btn" .. suffix .. "Bg"]
    local textElement = self["btn" .. suffix .. "Text"]

    if bgElement then
        local c = isHovered and self.COLORS.BTN_HOVER or self.COLORS.BTN_NORMAL
        bgElement:setImageColor(nil, c[1], c[2], c[3], c[4])
    end

    if textElement then
        local c = isHovered and self.COLORS.TXT_HOVER or self.COLORS.TXT_NORMAL
        textElement:setTextColor(c[1], c[2], c[3], c[4])
    end
end

-- Per-button focus/leave handlers (called by XML onFocus/onLeave)
function NPCDialog:onBtnTalkFocus()  self:applyHover("Talk", true)  end
function NPCDialog:onBtnTalkLeave()  self:applyHover("Talk", false) end
function NPCDialog:onBtnWorkFocus()  self:applyHover("Work", true)  end
function NPCDialog:onBtnWorkLeave()  self:applyHover("Work", false) end
function NPCDialog:onBtnFavorFocus() self:applyHover("Favor", true)  end
function NPCDialog:onBtnFavorLeave() self:applyHover("Favor", false) end
function NPCDialog:onBtnGiftFocus()  self:applyHover("Gift", true)  end
function NPCDialog:onBtnGiftLeave()  self:applyHover("Gift", false) end
function NPCDialog:onBtnRelFocus()   self:applyHover("Rel", true)   end
function NPCDialog:onBtnRelLeave()   self:applyHover("Rel", false)  end

-- Gift tier hover handlers
function NPCDialog:onBtnGiftSmallFocus()    self:applyGiftHover("Small",    true)  end
function NPCDialog:onBtnGiftSmallLeave()    self:applyGiftHover("Small",    false) end
function NPCDialog:onBtnGiftStandardFocus() self:applyGiftHover("Standard", true)  end
function NPCDialog:onBtnGiftStandardLeave() self:applyGiftHover("Standard", false) end
function NPCDialog:onBtnGiftGenerousFocus() self:applyGiftHover("Generous", true)  end
function NPCDialog:onBtnGiftGenerousLeave() self:applyGiftHover("Generous", false) end
function NPCDialog:onBtnGiftCancelFocus()   self:applyGiftHover("Cancel",   true)  end
function NPCDialog:onBtnGiftCancelLeave()   self:applyGiftHover("Cancel",   false) end

--- Apply hover highlight to a gift-panel button.
function NPCDialog:applyGiftHover(suffix, isHovered)
    local bgEl   = self["btnGift" .. suffix .. "Bg"]
    local textEl = self["btnGift" .. suffix .. "Text"]
    local isCancel = suffix == "Cancel"

    if bgEl then
        local c = isHovered
            and (isCancel and {0.28, 0.12, 0.12, 1} or {0.18, 0.28, 0.18, 1})
            or  (isCancel and {0.17, 0.09, 0.09, 1} or {0.10, 0.17, 0.10, 1})
        bgEl:setImageColor(nil, c[1], c[2], c[3], c[4])
    end
    if textEl then
        local c = isHovered
            and (isCancel and {1, 0.65, 0.65, 1} or {0.7, 1, 0.7, 1})
            or  (isCancel and {0.8, 0.5, 0.5, 1} or {0.6, 0.95, 0.6, 1})
        textEl:setTextColor(c[1], c[2], c[3], 1)
    end
end

-- =========================================================
-- Gift Panel Show / Hide
-- =========================================================

local ACTION_SUFFIXES = {"Talk", "Work", "Favor", "Gift", "Rel"}
local GIFT_SUFFIXES   = {"Small", "Standard", "Generous", "Cancel"}

--- Hide the five action buttons and reveal the gift-tier selection panel.
function NPCDialog:showGiftPanel()
    self.giftPanelVisible = true
    for _, s in ipairs(ACTION_SUFFIXES) do
        if self["btn"..s.."Bg"]   then self["btn"..s.."Bg"]:setVisible(false)   end
        if self["btn"..s]         then self["btn"..s]:setVisible(false)          end
        if self["btn"..s.."Text"] then self["btn"..s.."Text"]:setVisible(false)  end
    end
    if self.giftSelectTitle then self.giftSelectTitle:setVisible(true) end
    for _, s in ipairs(GIFT_SUFFIXES) do
        if self["btnGift"..s.."Bg"]   then self["btnGift"..s.."Bg"]:setVisible(true)   end
        if self["btnGift"..s]         then self["btnGift"..s]:setVisible(true)          end
        if self["btnGift"..s.."Text"] then self["btnGift"..s.."Text"]:setVisible(true)  end
    end
end

--- Hide the gift-tier selection panel and restore the five action buttons.
function NPCDialog:hideGiftPanel()
    self.giftPanelVisible = false
    for _, s in ipairs(ACTION_SUFFIXES) do
        if self["btn"..s.."Bg"]   then self["btn"..s.."Bg"]:setVisible(true)   end
        if self["btn"..s]         then self["btn"..s]:setVisible(true)          end
        if self["btn"..s.."Text"] then self["btn"..s.."Text"]:setVisible(true)  end
    end
    if self.giftSelectTitle then self.giftSelectTitle:setVisible(false) end
    for _, s in ipairs(GIFT_SUFFIXES) do
        if self["btnGift"..s.."Bg"]   then self["btnGift"..s.."Bg"]:setVisible(false)   end
        if self["btnGift"..s]         then self["btnGift"..s]:setVisible(false)          end
        if self["btnGift"..s.."Text"] then self["btnGift"..s.."Text"]:setVisible(false)  end
    end
end

-- =========================================================
-- Response Area
-- =========================================================

function NPCDialog:setResponse(text)
    if self.responseBg then
        self.responseBg:setVisible(true)
    end
    if self.responseText then
        self.responseText:setVisible(true)
        self.responseText:setText(text or "")
    end
end

-- =========================================================
-- Button Click Handlers
-- =========================================================

--- "Talk" button: pick a random conversation topic, award +1 relationship.
-- Daily limit: only the first talk per in-game day awards relationship points.
function NPCDialog:onClickTalk()
    if not self.npc or not self.npcSystem then return end

    local topic = self.npcSystem.interactionUI:getRandomConversationTopic(self.npc)

    local tonePrefix = ""
    if self.npcSystem.favorSystem then
        local memory = self.npcSystem.favorSystem:analyzeEncounterHistory(self.npc)
        local score = memory.memoryScore
        if score > 0.6 then
            tonePrefix = "It's always good to see you. "
        elseif score < -0.6 then
            tonePrefix = "Hmm. You again. "
        elseif score < -0.2 then
            tonePrefix = "Oh. Hi. "
        end
    end

    if self.npcSystem.relationshipManager then
        local success = self.npcSystem.relationshipManager:updateRelationship(self.npc.id, 1, "daily_interaction")
        if success then
            local info = self.npcSystem.relationshipManager:getRelationshipInfo(self.npc.id)
            if info then
                self.npc.relationship = info.value
            end
            self:setResponse(self.npc.name .. ": \"" .. tonePrefix .. topic .. "\"")
        else
            self:setResponse(self.npc.name .. ": \"" .. tonePrefix .. topic .. "\"\n(Already chatted today — no relationship change)")
        end
    else
        self:setResponse(self.npc.name .. ": \"" .. tonePrefix .. topic .. "\"")
    end

    self:updateDisplay()
    self:updateButtonStates()
end

--- "Ask about work" button: show the NPC's current activity and today's schedule.
function NPCDialog:onClickAskWork()
    if not self.npc or not self.npcSystem then return end

    local message = self.npcSystem.interactionUI:getWorkStatusMessage(self.npc)
    local schedulePart = ""
    if self.npcSystem.scheduler then
        local summary = self.npcSystem.scheduler:getScheduleSummary(self.npc)
        if summary and summary ~= "" then
            schedulePart = "\n" .. summary
        end
    end
    self:setResponse(self.npc.name .. ": \"" .. message .. "\"" .. schedulePart)
end

--- "Ask for favor" / "Accept Favor" / "Check progress" button.
-- Requires relationship >= 25.
-- Flow: (1) pending favor → accept + show first step, (2) active favor → show current step + progress,
--        (3) no favor → generate for this NPC, accept immediately, show first step.
function NPCDialog:onClickFavor()
    if not self.npc or not self.npcSystem then return end

    local relationship = self.npc.relationship or 0
    if relationship < 25 then return end

    local sys = self.npcSystem.favorSystem
    if not sys then return end

    -- Build a one-line summary of the first incomplete step with distance.
    local function stepSummary(favor)
        if favor.steps and #favor.steps > 0 then
            for _, step in ipairs(favor.steps) do
                if not step.completed then
                    local distTxt = ""
                    if step.location and self.npcSystem.playerPositionValid then
                        local pp = self.npcSystem.playerPosition
                        local dx = step.location.x - pp.x
                        local dz = (step.location.z or 0) - pp.z
                        local dist = math.sqrt(dx * dx + dz * dz)
                        distTxt = string.format(" (%.0fm away)", dist)
                    end
                    return (step.description or "Next step") .. distTxt
                end
            end
        end
        return favor.description or "Complete the task"
    end

    -- 1) Pending favor waiting for the player to accept
    local pending = sys:getPendingFavorForNPC(self.npc.id)
    if pending then
        -- Stamp the owning farm at accept with the acting player's farm. On host/SP this
        -- local accept IS the server-side accept. On a client we also send the accept to
        -- the server via NPCInteractionEvent, which validates the farm against the
        -- connection and stamps its authoritative favor copy's ownerFarmId to match.
        local farmId = (g_currentMission.player and g_currentMission.player.farmId) or 0
        local accepted = sys:acceptFavorForNPC(self.npc.id, farmId)
        if g_server == nil then
            NPCInteractionEvent.sendToServer(NPCInteractionEvent.ACTION_FAVOR_ACCEPT, self.npc.id, farmId, 0, "")
        end
        if accepted then
            self:setResponse(string.format(
                "%s: \"Thank you! I really need your help. First: %s\"",
                self.npc.name, stepSummary(accepted)))
            self:updateButtonStates()
            return
        end
    end

    -- 2a) Active favor awaiting final confirmation (e.g. watch_property patrol complete)
    local active = sys:getActiveFavorForNPC(self.npc.id)
    if active and active.awaitingConfirmation then
        local tooFar = false
        if self.npc.homePosition and self.npcSystem.playerPositionValid then
            local pp = self.npcSystem.playerPosition
            local dx = self.npc.homePosition.x - pp.x
            local dz = self.npc.homePosition.z - pp.z
            if math.sqrt(dx * dx + dz * dz) > 50 then
                tooFar = true
            end
        end
        if tooFar then
            self:setResponse(self.npc.name .. ": \"Come find me — I need to see you in person to close this out!\"")
        else
            active.awaitingConfirmation = false
            self:requestCompleteFavor()
            self:setResponse(self.npc.name .. ": \"Thank you so much for watching my property! Here's your reward.\"")
        end
        self:updateButtonStates()
        return
    end

    -- 2b) Active loan_money favor — player collects the NPC's repayment
    if active and active.type == "loan_money" and active.steps then
        for _, step in ipairs(active.steps) do
            if not step.completed and step.isLoanRepayStep then
                local loanAmount = (active.taskData and active.taskData.loanAmount) or 5000
                -- The loan principal is returned server-side in applyFavorRewards
                -- (repaymentCollected guard); the client only sends the completion intent.
                step.completed = true
                self:requestCompleteFavor()
                self:setResponse(string.format(
                    "%s: \"Here's your $%d back — and a little extra for your trouble!\"",
                    self.npc.name, loanAmount))
                self:updateButtonStates()
                return
            end
        end
    end

    -- 2c) Dialog-step or loan-repay step ready to be completed via dialog
    if active and active.steps then
        local readyStep = nil
        for _, step in ipairs(active.steps) do
            if not step.completed and (step.isDialogStep or step.isLoanRepayStep) then
                local priorDone = true
                for _, s2 in ipairs(active.steps) do
                    if s2.id < step.id and not s2.completed then
                        priorDone = false
                        break
                    end
                end
                if priorDone then
                    readyStep = step
                    break
                end
            end
        end
        if readyStep then
            if readyStep.isLoanRepayStep then
                local loanAmount = (active.taskData and active.taskData.loanAmount) or 5000
                -- Loan principal returned server-side (repaymentCollected guard); the
                -- client only sends the completion intent.
                readyStep.completed = true
                self:requestCompleteFavor()
                self:setResponse(string.format(
                    "%s: \"Here's your $%d back — and a little extra for your trouble!\"",
                    self.npc.name, loanAmount))
            else
                readyStep.completed = true
                self:requestCompleteFavor()
                self:setResponse(self.npc.name .. ": \"" .. (g_i18n:getText("npc_dialog_favor_completed_confirm") or "Thanks so much for your help! Here's your reward.") .. "\"")
            end
            self:updateButtonStates()
            return
        end
    end

    -- 2d) Generic active / in-progress favor — show next step
    if active then
        local progress = active.progress or 0
        self:setResponse(string.format(
            "%s: \"Thanks for working on it! Next: %s [%d%% done]\"",
            self.npc.name, stepSummary(active), progress))
        self:updateButtonStates()
        return
    end

    -- 3) No favor — player offers help. Generate a favor with personality-aware decline chance.
    local personality = self.npc.personality or "friendly"
    local result = sys:generateFavorForNPC(self.npc, true)

    if result == "declined" then
        -- Personality-flavored refusal
        local refusals = {
            grumpy      = "I don't need your help. I manage fine on my own.",
            greedy      = "Hmm... I'll pass for now. Come back when I have something worth your time.",
            generous    = "That's very kind, but I'm all sorted today. Maybe another time!",
            friendly    = "Oh! Thanks for offering — I'm good for now, but I'll remember this!",
            hardworking = "Appreciate it, but I've got everything under control.",
        }
        local msg = refusals[personality] or "I'm alright for now, but thank you."
        self:setResponse(self.npc.name .. ": \"" .. msg .. "\"")

    elseif result then
        -- Personality-flavored acceptance
        local acceptances = {
            grumpy      = "Fine. I suppose I could use a hand. Don't make a mess of it. First: %s",
            greedy      = "Well, since you're offering... %s. And don't expect a small reward.",
            generous    = "Oh, that's so thoughtful of you! I'd love the help. First: %s",
            friendly    = "Really? That's amazing, thank you! Let's start with: %s",
            hardworking = "Good timing — I could use the extra hands. Here's what needs doing: %s",
        }
        local template = acceptances[personality] or "Yes, I could use help! First: %s"
        local responseText = string.format(self.npc.name .. ": \"" .. template .. "\"", stepSummary(result))
        if self.npcSystem.favorSystem then
            local memory = self.npcSystem.favorSystem:analyzeEncounterHistory(self.npc)
            if memory.completedFavorCount >= 3 then
                responseText = responseText .. " You've helped before — I trust you'll come through again."
            end
        end
        self:setResponse(responseText)
    else
        self:setResponse(self.npc.name .. ": \"I don't need anything right now — but thanks for asking!\"")
    end

    self:updateButtonStates()
end


--- Send a server-authoritative "complete this NPC's active favor" intent through the
-- mod's own NPCInteractionEvent. The server resolves the favor, completes it, and pays
-- favor.ownerFarmId exactly once (idempotency flags). The client never calls addMoney
-- and never flips favor.status; it only shows optimistic dialog text and is re-synced.
-- On host/single-player sendToServer executes directly, so behaviour is unchanged there.
function NPCDialog:requestCompleteFavor()
    if not self.npc then return end
    local farmId = (g_currentMission.player and g_currentMission.player.farmId) or 0
    NPCInteractionEvent.sendToServer(NPCInteractionEvent.ACTION_FAVOR_COMPLETE, self.npc.id, farmId, 0, "")
end

--- "Give gift" button: open the gift tier selection panel.
-- Requires relationship >= 30. Actual execution is in onClickGiftSmall/Standard/Generous.
function NPCDialog:onClickGift()
    if not self.npc or not self.npcSystem then return end
    local relationship = self.npc.relationship or 0
    if relationship < 30 then return end

    self:showGiftPanel()
    self:setResponse(string.format(
        g_i18n:getText("npc_gift_select_prompt") or "What would you like to give %s?",
        self.npc.name
    ))
end

--- Execute a gift of the given amount, deducting money and updating relationship.
-- Called by the three tier handlers below.
function NPCDialog:executeGift(amount)
    if not self.npc or not self.npcSystem then return end

    -- Advisory client-side balance check (UI only). The server re-checks the balance
    -- authoritatively before it deducts, so this just avoids a pointless round-trip.
    local farmId = (g_currentMission.player and g_currentMission.player.farmId) or 0
    local farm = g_farmManager and g_farmManager:getFarmById(farmId)
    local balance = farm and farm.money or 0
    if balance < amount then
        self:setResponse(g_i18n:getText("npc_gift_insufficient_funds") or "You don't have enough money for this gift.")
        self:hideGiftPanel()
        return
    end

    -- Server-authoritative: serverGiveGift deducts the gift from the acting farm (after
    -- its own balance re-check) and applies the relationship gain, then syncs it back.
    -- The client sends intent only; it does not deduct money or mutate relationship here.
    NPCInteractionEvent.sendToServer(NPCInteractionEvent.ACTION_GIFT, self.npc.id, farmId, amount, "money")

    -- Optimistic thank-you text; the relationship value re-syncs from the server.
    local thanks = {
        hardworking = "Much appreciated! I can put this to good use.",
        lazy        = "Oh nice, thanks! That's really kind of you.",
        social      = "You're the best! I'll tell everyone how generous you are!",
        grumpy      = "Hmph. Well... thanks, I guess.",
        generous    = "Thank you! I'll find a way to return the favor.",
    }
    local thankMsg = thanks[self.npc.personality] or (g_i18n:getText("npc_dialog_gift_thanks") or "Thank you for the gift!")
    self:setResponse(self.npc.name .. ": \"" .. thankMsg .. "\"")

    self:hideGiftPanel()
    self:updateDisplay()
    self:updateButtonStates()
end

function NPCDialog:onClickGiftSmall()    self:executeGift(200)  end
function NPCDialog:onClickGiftStandard() self:executeGift(500)  end
function NPCDialog:onClickGiftGenerous() self:executeGift(1000) end

function NPCDialog:onClickGiftCancel()
    self:hideGiftPanel()
    self:setResponse(g_i18n:getText("npc_gift_cancelled") or "Maybe another time!")
end

--- "Relationship info" button: show level, benefits, next unlock, favor stats.
-- Displays 7-tier relationship system with unlock progression.
function NPCDialog:onClickRelationship()
    if not self.npc or not self.npcSystem then return end

    local info = nil
    if self.npcSystem.relationshipManager then
        info = self.npcSystem.relationshipManager:getRelationshipInfo(self.npc.id)
    end

    if not info then
        self:setResponse(g_i18n:getText("npc_rel_no_info") or "No relationship information available.")
        return
    end

    -- Favor statistics
    local completedFavors = 0
    local failedFavors = 0

    if self.npcSystem.favorSystem then
        local ok1, completed = pcall(function() return self.npcSystem.favorSystem:getCompletedFavors() end)
        if ok1 and completed then
            for _, favor in ipairs(completed) do
                if favor.npcId == self.npc.id then
                    completedFavors = completedFavors + 1
                end
            end
        end
        local ok2, failed = pcall(function() return self.npcSystem.favorSystem:getFailedFavors() end)
        if ok2 and failed then
            for _, favor in ipairs(failed) do
                if favor.npcId == self.npc.id then
                    failedFavors = failedFavors + 1
                end
            end
        end
    end

    local totalFavors = completedFavors + failedFavors
    local successRate = totalFavors > 0 and math.floor((completedFavors / totalFavors) * 100) or 0

    -- Current benefits
    local benefits = (info.level and info.level.benefits) or (info.benefits) or {}
    local benefitList = {}
    if benefits.discount and benefits.discount > 0 then
        table.insert(benefitList, string.format(g_i18n:getText("npc_rel_benefit_discount") or "%d%% discount", benefits.discount))
    end
    if benefits.canAskFavor then
        table.insert(benefitList, g_i18n:getText("npc_rel_benefit_favors") or "can ask favors")
    end
    if benefits.canBorrowEquipment then
        table.insert(benefitList, g_i18n:getText("npc_rel_benefit_borrow") or "borrow equipment")
    end
    if benefits.mayOfferHelp then
        table.insert(benefitList, g_i18n:getText("npc_rel_benefit_help") or "may offer help")
    end
    if benefits.mayGiveGifts then
        table.insert(benefitList, g_i18n:getText("npc_rel_benefit_gifts") or "gives gifts")
    end
    if benefits.sharedResources then
        table.insert(benefitList, g_i18n:getText("npc_rel_benefit_shared") or "shared resources")
    end
    local benefitStr = #benefitList > 0 and table.concat(benefitList, ", ") or (g_i18n:getText("npc_rel_benefit_none") or "none")

    -- Next level info
    local currentValue = info.value or 0
    local nextLevelStr = ""
    -- Thresholds aligned with getRelationshipLevelName()
    local levelThresholds = {
        { min = 0,  name = g_i18n:getText("npc_rel_hostile") or "Hostile" },
        { min = 10, name = g_i18n:getText("npc_rel_unfriendly") or "Unfriendly", unlock = g_i18n:getText("npc_rel_unlock_basic") or "basic interaction" },
        { min = 25, name = g_i18n:getText("npc_rel_neutral") or "Neutral", unlock = g_i18n:getText("npc_rel_unlock_favors") or "ask favors, 5% discount" },
        { min = 40, name = g_i18n:getText("npc_rel_acquaintance") or "Acquaintance", unlock = g_i18n:getText("npc_rel_unlock_borrow") or "borrow equipment, 10% discount" },
        { min = 60, name = g_i18n:getText("npc_rel_friend") or "Friend", unlock = g_i18n:getText("npc_rel_unlock_help") or "NPC offers help, 15% discount" },
        { min = 75, name = g_i18n:getText("npc_rel_close_friend") or "Close Friend", unlock = g_i18n:getText("npc_rel_unlock_gifts") or "gifts, shared resources, 18% discount" },
        { min = 90, name = g_i18n:getText("npc_rel_best_friend") or "Best Friend", unlock = g_i18n:getText("npc_rel_unlock_full") or "full benefits, 20% discount" }
    }
    for _, lvl in ipairs(levelThresholds) do
        if currentValue < lvl.min then
            local needed = lvl.min - currentValue
            nextLevelStr = string.format(g_i18n:getText("npc_rel_next_fmt") or "Next: %s at %d (+%d) - unlocks: %s",
                lvl.name, lvl.min, needed, lvl.unlock or "")
            break
        end
    end
    if nextLevelStr == "" then
        nextLevelStr = g_i18n:getText("npc_rel_max_reached") or "MAX level reached!"
    end

    -- Trend info
    local trendStr = ""
    if info.statistics and info.statistics.trend then
        local trend = info.statistics.trend
        if trend > 0 then
            trendStr = " " .. (g_i18n:getText("npc_rel_trend_up") or "(trending up)")
        elseif trend < 0 then
            trendStr = " " .. (g_i18n:getText("npc_rel_trend_down") or "(trending down)")
        end
    end

    -- Build response
    local levelName = info.level and info.level.name or self:getRelationshipLevelName(currentValue)

    -- 4h: Include backstory at high relationship
    local backstoryStr = ""
    if currentValue >= 40 then
        backstoryStr = "\n" .. self:getBackstory(self.npc)
    end

    self:setResponse(string.format(
        "%s (%s) | %s: %d/100%s | Benefits: %s | %s | Favors: %d done, %d failed (%d%%)%s",
        self.npc.name,
        self.npc.personality or "?",
        levelName,
        currentValue,
        trendStr,
        benefitStr,
        nextLevelStr,
        completedFavors,
        failedFavors,
        successRate,
        backstoryStr
    ))
end

function NPCDialog:onClickClose()
    self:close()
end

function NPCDialog:onClose()
    -- Unfreeze the NPC so they resume AI behavior
    if self.npc then
        self.npc.isTalking = false
    end
    NPCDialog:superClass().onClose(self)
    self.npc = nil
end

-- =========================================================
-- Helper Functions
-- =========================================================

function NPCDialog:getGreeting()
    if not self.npc or not self.npcSystem then
        return g_i18n:getText("npc_dialog_hello_generic") or "Hello there!"
    end
    if self.npcSystem.interactionUI then
        return self.npcSystem.interactionUI:getGreetingForNPC(self.npc)
    end
    return g_i18n:getText("npc_dialog_hello") or "Hello there, neighbor!"
end

--- Check if this NPC's relationship is at risk of decaying.
-- Returns a warning string if the NPC hasn't been interacted with recently
-- and their relationship is above the decay threshold (25).
function NPCDialog:getDecayWarning()
    if not self.npc or not self.npcSystem then return nil end
    local npc = self.npc
    if not npc.relationship or npc.relationship <= 25 then return nil end

    local currentTime = self.npcSystem:getCurrentGameTime()
    local lastInteraction = npc.lastGreetingTime or 0
    if lastInteraction == 0 then return nil end

    local timeSince = currentTime - lastInteraction
    local oneDay = 24 * 60 * 60 * 1000
    local daysSince = timeSince / oneDay

    if daysSince >= 1.5 then
        local daysText = math.floor(daysSince)
        return string.format(
            g_i18n:getText("npc_decay_warning") or "(You haven't talked in %d days — relationship may decay!)",
            daysText
        )
    end
    return nil
end

--- Get RGB color for a personality trait (for display text coloring).
-- NOTE: Duplicated in NPCInteractionUI:getPersonalityColor(). Both kept because
-- NPCDialog (MessageDialog subclass) can't easily access NPCInteractionUI at
-- render time without adding a dependency. Consider consolidating if refactored.
-- @param personality  Personality string (e.g., "hardworking", "lazy")
-- @return table  {r, g, b} color values
function NPCDialog:getPersonalityColor(personality)
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

--- Map a relationship value (0-100) to a human-readable level name.
-- 7 tiers: Hostile(0), Unfriendly(10), Neutral(25), Acquaintance(40),
-- Friend(60), Close Friend(75), Best Friend(90).
-- @param value  Relationship value (0-100)
-- @return string  Level name
function NPCDialog:getRelationshipLevelName(value)
    if value < 10 then return g_i18n:getText("npc_rel_hostile") or "Hostile"
    elseif value < 25 then return g_i18n:getText("npc_rel_unfriendly") or "Unfriendly"
    elseif value < 40 then return g_i18n:getText("npc_rel_neutral") or "Neutral"
    elseif value < 60 then return g_i18n:getText("npc_rel_acquaintance") or "Acquaintance"
    elseif value < 75 then return g_i18n:getText("npc_rel_friend") or "Friend"
    elseif value < 90 then return g_i18n:getText("npc_rel_close_friend") or "Close Friend"
    else return g_i18n:getText("npc_rel_best_friend") or "Best Friend"
    end
end

--- Generate a short backstory/bio for an NPC based on their personality and farm.
-- All user-visible strings are localized via g_i18n.
-- @param npc  NPC data table
-- @return string  Backstory text
function NPCDialog:getBackstory(npc)
    if not npc then return "" end

    local personalityBios = {
        hardworking = g_i18n:getText("npc_backstory_hardworking") or "Known around town as an early riser who never misses a day in the fields.",
        lazy        = g_i18n:getText("npc_backstory_lazy")        or "Prefers a leisurely pace. Often found relaxing in the shade.",
        social      = g_i18n:getText("npc_backstory_social")      or "The neighborhood's most talkative resident. Knows everyone's business.",
        grumpy      = g_i18n:getText("npc_backstory_grumpy")      or "Not much for small talk, but respected for straight-shooting honesty.",
        generous    = g_i18n:getText("npc_backstory_generous")    or "Always first to lend a hand or share from the harvest.",
    }

    local bio = personalityBios[npc.personality] or (g_i18n:getText("npc_backstory_default") or "A quiet member of the community.")

    if npc.farmName then
        bio = bio .. " " .. string.format(g_i18n:getText("npc_backstory_farm_fmt") or "Works at %s.", npc.farmName)
        if npc.assignedFields and #npc.assignedFields > 0 then
            bio = bio .. " " .. string.format(g_i18n:getText("npc_backstory_fields_fmt") or "Tends %d field(s).", #npc.assignedFields)
        end
    end

    if npc.age then
        bio = string.format(g_i18n:getText("npc_backstory_age_fmt") or "Age %d.", npc.age) .. " " .. bio
    end

    return bio
end

function NPCDialog:getRelationshipColor(value)
    if value < 20 then
        return 1, 0.3, 0.3
    elseif value < 40 then
        return 1, 0.6, 0.3
    elseif value < 60 then
        return 1, 0.85, 0.3
    elseif value < 80 then
        return 0.3, 0.85, 0.3
    else
        return 0.3, 0.6, 1
    end
end

print("[NPC Favor] NPCDialog loaded")
