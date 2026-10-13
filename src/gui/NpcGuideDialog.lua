-- =========================================================
-- NPC Favor Field Guide - Field Guide
-- =========================================================
-- BUILD 19:15 (George CLOSED DESIGN 18:55 item 5): every Realistic Farming Esc page gets its own
-- guide, in its own mod, opened from the shared Help footer through this guest's onOpenHelp. The
-- chrome is SoilGuideDialog's so all of them read as one family; only the words differ.
-- Rows are { t = "H" | "B" | "S" | "COL", v = "text" }: header, body, spacer, column break.
-- =========================================================

---@class NpcGuideDialog
NpcGuideDialog = NpcGuideDialog or {}
local NpcGuideDialog_mt = Class(NpcGuideDialog, ScreenElement)

local GUIDE_MOD_DIR = (NPCFavorModDirectory or g_currentModDirectory)

NpcGuideDialog.INSTANCE = nil
NpcGuideDialog.GUI_NAME = "NpcGuideDialog"

NpcGuideDialog.SUBTITLES = {
    "Neighbours - what the mod adds and this page",
    "The Esc Page - roster, favours and detail cards",
    "Favours - accepting, doing and finishing them",
    "Standing - the seven levels and what they give",
    "Settings and FAQ - options panel and questions",
}

NpcGuideDialog.PAGE1 = {
    { t="H", v="LIVING NEIGHBOURS" },
    { t="B", v="This mod puts a small number of neighbour" },
    { t="B", v="farmers into your world. They live on their" },
    { t="B", v="own farms, work their fields and follow a" },
    { t="B", v="daily routine." },
    { t="S", v=" " },
    { t="B", v="Each neighbour keeps an opinion of you. It" },
    { t="B", v="starts at the bottom and only moves when you" },
    { t="B", v="deal with them. Do them a good turn and it" },
    { t="B", v="rises. Let them down and it falls." },
    { t="S", v=" " },
    { t="H", v="FAVOURS IN ONE LINE" },
    { t="B", v="A neighbour can ask you for help. That" },
    { t="B", v="request is a favour. Go and talk to them to" },
    { t="B", v="accept it, do the steps it asks for, and you" },
    { t="B", v="get paid and gain standing." },
    { t="S", v=" " },
    { t="COL", v="" },
    { t="H", v="THIS ESC PAGE" },
    { t="B", v="The page in front of you is the NPC Favor" },
    { t="B", v="part of the Realistic Farming screen. Pick" },
    { t="B", v="it from the module list on the left." },
    { t="S", v=" " },
    { t="B", v="The top table is the neighbour roster: who" },
    { t="B", v="they are, their standing, the benefits they" },
    { t="B", v="give you now, and your favour history with" },
    { t="B", v="them." },
    { t="S", v=" " },
    { t="B", v="The table under it lists favours, grouped" },
    { t="B", v="into Current, Available and Completed." },
    { t="S", v=" " },
    { t="B", v="Both tables scroll. Click any row and a" },
    { t="B", v="detail card opens on the right." },
    { t="S", v=" " },
    { t="B", v="This page only reports. You cannot accept" },
    { t="B", v="or finish a favour from here. That is done" },
    { t="B", v="out in the world." },
}

NpcGuideDialog.PAGE2 = {
    { t="H", v="FINDING THE PAGE" },
    { t="B", v="Press Escape, open the Realistic Farming" },
    { t="B", v="screen, then choose NPC Favor from the" },
    { t="B", v="module list." },
    { t="S", v=" " },
    { t="H", v="THE ROSTER TABLE" },
    { t="B", v="Four columns head the roster: Who, Standing," },
    { t="B", v="Benefits and History." },
    { t="S", v=" " },
    { t="B", v="Who is the neighbour's name." },
    { t="B", v="Standing shows their level and their score" },
    { t="B", v="out of 100." },
    { t="B", v="Benefits lists what that level gives you" },
    { t="B", v="right now." },
    { t="B", v="History is your success rate with them, as" },
    { t="B", v="a percentage and a completed out of total" },
    { t="B", v="count." },
    { t="S", v=" " },
    { t="B", v="The roster is sorted by standing, best" },
    { t="B", v="first. Long names are shortened to fit." },
    { t="S", v=" " },
    { t="COL", v="" },
    { t="H", v="THE FAVOURS TABLE" },
    { t="B", v="Its columns are Group, Who, What and" },
    { t="B", v="Urgency." },
    { t="S", v=" " },
    { t="B", v="Group is Current, Available or Completed." },
    { t="B", v="Current favours are the ones you have" },
    { t="B", v="accepted. Available ones are waiting for you" },
    { t="B", v="to go and accept them." },
    { t="B", v="Urgency is the time left. Completed rows" },
    { t="B", v="read done." },
    { t="S", v=" " },
    { t="H", v="THE DETAIL CARDS" },
    { t="B", v="Click a roster row and the upper card on the" },
    { t="B", v="right shows that neighbour in full, with the" },
    { t="B", v="whole benefits list and the history line." },
    { t="S", v=" " },
    { t="B", v="Click a favour row and the lower card shows" },
    { t="B", v="its group, the neighbour, the full request" },
    { t="B", v="and the urgency." },
}

NpcGuideDialog.PAGE3 = {
    { t="H", v="HOW A FAVOUR STARTS" },
    { t="B", v="Neighbours ask for help on their own as you" },
    { t="B", v="play. A new request shows on the favours HUD" },
    { t="B", v="and as Available on the Esc page." },
    { t="S", v=" " },
    { t="B", v="You can also offer help. Stand in front of a" },
    { t="B", v="neighbour, use the Talk to Neighbour action," },
    { t="B", v="then pick the offer button in the dialog." },
    { t="B", v="Offering needs a standing of at least 25." },
    { t="S", v=" " },
    { t="H", v="ACCEPTING" },
    { t="B", v="A request does nothing until you accept it." },
    { t="B", v="Walk up to the neighbour, talk to them and" },
    { t="B", v="press Accept Favor. On the HUD an entry you" },
    { t="B", v="have not taken yet says talk to accept." },
    { t="S", v=" " },
    { t="B", v="The clock starts when the request is made," },
    { t="B", v="not when you accept, so do not leave an" },
    { t="B", v="offer sitting for long." },
    { t="S", v=" " },
    { t="COL", v="" },
    { t="H", v="DOING THE WORK" },
    { t="B", v="Most favours are two or three steps, such as" },
    { t="B", v="going to a farm, out to a field, then back." },
    { t="B", v="A step ticks off when you get close enough" },
    { t="B", v="to its place, on foot or in a vehicle." },
    { t="S", v=" " },
    { t="B", v="The favours HUD points the way. Each entry" },
    { t="B", v="shows the neighbour, a needle pointing at" },
    { t="B", v="the next step, the distance, the step text," },
    { t="B", v="the time left and a progress bar." },
    { t="S", v=" " },
    { t="B", v="A few steps finish by talking to the" },
    { t="B", v="neighbour instead of by driving there." },
    { t="S", v=" " },
    { t="H", v="FINISHING AND FAILING" },
    { t="B", v="When the last step is done the favour" },
    { t="B", v="completes by itself. You are paid and your" },
    { t="B", v="standing with that neighbour rises. Finish" },
    { t="B", v="well inside the time limit for a bonus." },
    { t="S", v=" " },
    { t="B", v="Run out of time and it fails, costing you" },
    { t="B", v="standing. Cancelling from the Favor Menu" },
    { t="B", v="costs standing too." },
}

NpcGuideDialog.PAGE4 = {
    { t="H", v="THE SEVEN LEVELS" },
    { t="B", v="Every neighbour has a score from 0 to 100." },
    { t="B", v="That score sits in one of seven levels." },
    { t="S", v=" " },
    { t="B", v="Hostile, 0 to 9." },
    { t="B", v="Unfriendly, 10 to 24." },
    { t="B", v="Neutral, 25 to 39." },
    { t="B", v="Acquaintance, 40 to 59." },
    { t="B", v="Friend, 60 to 74." },
    { t="B", v="Close Friend, 75 to 89." },
    { t="B", v="Best Friend, 90 to 100." },
    { t="S", v=" " },
    { t="B", v="Everyone starts at the bottom. Trust has to" },
    { t="B", v="be earned." },
    { t="S", v=" " },
    { t="B", v="The number beside the level on the Esc page" },
    { t="B", v="is that score. The roster is sorted by it," },
    { t="B", v="best first." },
    { t="S", v=" " },
    { t="B", v="The Benefits column always shows what a" },
    { t="B", v="neighbour gives you at that level today." },
    { t="COL", v="" },
    { t="H", v="WHAT EACH LEVEL GIVES" },
    { t="B", v="Neutral lets you offer help and gives a" },
    { t="B", v="small trade discount." },
    { t="B", v="Acquaintance raises the discount and lets" },
    { t="B", v="you borrow equipment." },
    { t="B", v="Friend adds the chance they offer to help" },
    { t="B", v="you with your own work." },
    { t="B", v="Close Friend adds gifts from them." },
    { t="B", v="Best Friend gives the largest discount and" },
    { t="B", v="shared resources." },
    { t="S", v=" " },
    { t="H", v="MOVING THE SCORE" },
    { t="B", v="Completing a favour is the biggest steady" },
    { t="B", v="gain. Helping with work, trading and simply" },
    { t="B", v="speaking to them each day also help." },
    { t="S", v=" " },
    { t="B", v="Failing, abandoning or ignoring a favour" },
    { t="B", v="pushes the score back down, as does an" },
    { t="B", v="argument." },
    { t="S", v=" " },
    { t="B", v="Giving a gift needs a score of 30 and costs" },
    { t="B", v="money, but it lifts their opinion." },
}

NpcGuideDialog.PAGE5 = {
    { t="H", v="SETTINGS PANEL" },
    { t="B", v="Open the mod's settings panel with the NPC" },
    { t="B", v="Settings action, Right Shift and 7." },
    { t="S", v=" " },
    { t="B", v="It has three sections plus an admin page" },
    { t="B", v="with save and reset." },
    { t="S", v=" " },
    { t="H", v="WHAT YOU CAN CHANGE" },
    { t="B", v="NPC Behavior sets how many neighbours live" },
    { t="B", v="in the world, how often they ask for" },
    { t="B", v="favours, and the hours they work." },
    { t="S", v=" " },
    { t="B", v="Display turns the favours HUD, name tags," },
    { t="B", v="standing bars and map markers on or off," },
    { t="B", v="and sets the HUD size." },
    { t="S", v=" " },
    { t="B", v="Gameplay turns favours and gifts on or off," },
    { t="B", v="caps how many you can hold at once, sets" },
    { t="B", v="whether favours expire, and offers easy," },
    { t="B", v="normal or hard." },
    { t="COL", v="" },
    { t="H", v="THE OTHER SCREENS" },
    { t="B", v="Talk to Neighbour is the E key by default." },
    { t="B", v="The prompt appears when you stand near one." },
    { t="S", v=" " },
    { t="B", v="Favor Menu, Right Shift and 9, lists your" },
    { t="B", v="favours with time left and reward, and can" },
    { t="B", v="cancel one." },
    { t="S", v=" " },
    { t="B", v="NPC List, Right Shift and 8, is the roster" },
    { t="B", v="with distance and what each one is doing." },
    { t="S", v=" " },
    { t="B", v="All of these can be rebound under Options" },
    { t="B", v="and Controls." },
    { t="S", v=" " },
    { t="H", v="COMMON QUESTIONS" },
    { t="B", v="Nothing listed? No neighbours have spawned" },
    { t="B", v="yet, or the system is off in the panel." },
    { t="S", v=" " },
    { t="B", v="Can I finish a favour from the Esc page?" },
    { t="B", v="No. Go to the neighbour or the step place." },
    { t="S", v=" " },
    { t="B", v="Settings are stored with your savegame, so" },
    { t="B", v="save the game after changing them." },
}

NpcGuideDialog.PAGE_CONTENT = { NpcGuideDialog.PAGE1, NpcGuideDialog.PAGE2, NpcGuideDialog.PAGE3, NpcGuideDialog.PAGE4, NpcGuideDialog.PAGE5 }

-- -- Constructor ------------------------------------------

function NpcGuideDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or NpcGuideDialog_mt)
    self._contentLineEls = {}
    self._currentPage = 1
    return self
end

--- Loads the dialog into g_gui once. Safe to call twice, and safe to call when some other path has
--- already registered the same name.
function NpcGuideDialog.register(modDirectory)
    if g_gui == nil then return end
    if g_gui.guis ~= nil and g_gui.guis[NpcGuideDialog.GUI_NAME] ~= nil then return end
    if modDirectory ~= nil then GUIDE_MOD_DIR = modDirectory end
    if GUIDE_MOD_DIR == nil then return end
    NpcGuideDialog.INSTANCE = NpcGuideDialog.new()
    local ok, err = pcall(function()
        g_gui:loadGui(GUIDE_MOD_DIR .. "xml/gui/NpcGuideDialog.xml", NpcGuideDialog.GUI_NAME, NpcGuideDialog.INSTANCE)
    end)
    if not ok then
        print("[NPCFavor] NpcGuideDialog: loadGui failed: " .. tostring(err))
        NpcGuideDialog.INSTANCE = nil
    end
end

function NpcGuideDialog.show()
    if g_gui == nil then return end
    local loaded = g_gui.guis ~= nil and g_gui.guis[NpcGuideDialog.GUI_NAME] ~= nil
    if not loaded then
        NpcGuideDialog.register(GUIDE_MOD_DIR)
        loaded = g_gui.guis ~= nil and g_gui.guis[NpcGuideDialog.GUI_NAME] ~= nil
    end
    if not loaded then return end
    g_gui:showDialog(NpcGuideDialog.GUI_NAME)
end

-- -- Lifecycle --------------------------------------------

function NpcGuideDialog:onGuiSetupFinished()
    NpcGuideDialog:superClass().onGuiSetupFinished(self)
    self._elCol1 = self:getDescendantById("npcGuide_col1")
    self._elCol2 = self:getDescendantById("npcGuide_col2")
    self._elSubtitle = self:getDescendantById("npcGuide_subtitle")
end

function NpcGuideDialog:onOpen()
    NpcGuideDialog:superClass().onOpen(self)
    self._currentPage = 1
    self:_selectPage(1)
end

function NpcGuideDialog:onClose()
    NpcGuideDialog:superClass().onClose(self)
    self:_clearContent()
    self._currentPage = 1
end

-- -- Tabs -------------------------------------------------

function NpcGuideDialog:onClickTab1() self:_selectPage(1) end
function NpcGuideDialog:onClickTab2() self:_selectPage(2) end
function NpcGuideDialog:onClickTab3() self:_selectPage(3) end
function NpcGuideDialog:onClickTab4() self:_selectPage(4) end
function NpcGuideDialog:onClickTab5() self:_selectPage(5) end

function NpcGuideDialog:_selectPage(pageNum)
    if self._currentPage == pageNum and #self._contentLineEls > 0 then return end
    self:_clearContent()
    self._currentPage = pageNum
    if self._elSubtitle ~= nil then
        self._elSubtitle:setText(NpcGuideDialog.SUBTITLES[pageNum] or "")
    end
    self:_buildContent(pageNum)
end

-- -- Content ----------------------------------------------

function NpcGuideDialog:_buildContent(pageNum)
    local profileH = g_gui:getProfile("npcGuide_colHeader")
    local profileB = g_gui:getProfile("npcGuide_colBody")
    local profileS = g_gui:getProfile("npcGuide_colSpacer")
    if not profileH or not profileB then
        print("[NPCFavor] NpcGuideDialog: column profiles not found")
        return
    end
    local content = NpcGuideDialog.PAGE_CONTENT[pageNum]
    if content == nil then return end
    local currentBox = self._elCol1
    for _, row in ipairs(content) do
        if row.t == "COL" then
            if self._elCol1 ~= nil then self._elCol1:invalidateLayout() end
            currentBox = self._elCol2
        elseif currentBox ~= nil then
            local profile = (row.t == "H") and profileH
                         or (row.t == "S") and profileS
                         or profileB
            if profile ~= nil then
                local el = TextElement.new()
                el:loadProfile(profile, true)
                el:setText(row.v or "")
                currentBox:addElement(el)
                el:onGuiSetupFinished()
                table.insert(self._contentLineEls, { box = currentBox, el = el })
            end
        end
    end
    if self._elCol2 ~= nil then self._elCol2:invalidateLayout() end
end

function NpcGuideDialog:_clearContent()
    for _, entry in ipairs(self._contentLineEls or {}) do
        if entry.box ~= nil then
            entry.box:removeElement(entry.el)
        end
    end
    self._contentLineEls = {}
    if self._elCol1 ~= nil then self._elCol1:invalidateLayout() end
    if self._elCol2 ~= nil then self._elCol2:invalidateLayout() end
end

-- -- Button -----------------------------------------------

function NpcGuideDialog:onClickClose()
    g_gui:closeDialogByName(NpcGuideDialog.GUI_NAME)
end
