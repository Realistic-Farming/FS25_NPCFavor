-- =========================================================
-- FS25 NPC Favor Mod - Moveable Favor List HUD
-- =========================================================
-- Standalone HUD module for the active favors list.
-- Supports drag-to-move and corner-resize via right-click
-- edit mode toggle. Features compass direction + distance
-- per favor row, and flash notifications for favor events.
--
-- Cursor toggle approach inspired by ClickToSwitch
-- (Courseplay.devTeam, https://github.com/Courseplay/ClickToSwitch)
--
-- Position/scale are persisted via NPCSettings (XML save/load).
-- Drag/resize state is runtime-only — never persisted.
-- =========================================================

-- BUILD 17:57 + ATTN 18:02 (Wizard hot-reload law, FS25-HotReload-Guide.md Part 1):
-- reuse the existing class table on Ctrl+R reload so updated methods land on the
-- table live metatables already reference, instead of orphaning it.
NPCFavorHUD = NPCFavorHUD or {}
NPCFavorHUD_mt = Class(NPCFavorHUD)

local function getBaseGameRenderer()
    local hud = (g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD
    return hud ~= nil and hud.renderer or nil
end

-- =========================================================
-- Constructor
-- =========================================================

function NPCFavorHUD.new(npcSystem)
    local self = setmetatable({}, NPCFavorHUD_mt)

    self.npcSystem = npcSystem

    -- Position (normalized 0–1, top-left anchor of the HUD box)
    -- BUILD 12:25 (Sam DESIGN 12:23): Active Favors factory default is
    -- Middle-Left-Top in the suite's non-overlap layout. Saved drag XML wins.
    -- Wizard 2026-08-21: factory home is the suite layout Wizard arranged
    -- in-game (left column). Saved settings still win on load.
    self.posX = 0.024167
    self.posY = 0.712592

    -- Scale multiplier applied to all dimensions and text
    self.scale = 1.200786   -- factory suite layout (Wizard 2026-08-22)

    -- Edit/drag state (runtime only, never persisted)
    self.editMode = false
    self.dragging = false
    self.dragOffsetX = 0
    self.dragOffsetY = 0

    -- Resize state (runtime only, never persisted)
    self.resizing = false
    self.resizeStartMouseX = 0
    self.resizeStartMouseY = 0
    self.resizeStartScale = 1.0

    -- Resize config
    self.RESIZE_HANDLE_SIZE = 0.008  -- corner handle hit area (normalized)
    self.MIN_SCALE = 0.5
    self.MAX_SCALE = 2.0

    -- Width multiplier (adjusted by edge-drag, independent of scale)
    self.widthMult = 0.517187   -- factory suite layout (Wizard 2026-08-22)
    self.MIN_WIDTH_MULT = 0.5
    self.MAX_WIDTH_MULT = 2.0
    self.edgeDragging = nil  -- nil, "left", or "right"
    self.edgeDragStartX = 0
    self.edgeDragStartWidth = 1.0

    -- Hover state for visual feedback
    self.hoverCorner = nil  -- nil, "bl", "br", "tl", "tr"

    -- Animation timer for pulsing edit-mode border
    self.animTimer = 0

    -- Camera lock state (saved rotation for edit mode freeze)
    self.savedCamRotX = nil
    self.savedCamRotY = nil
    self.savedCamRotZ = nil

    -- Flash notification system
    self.flashQueue = {}
    self.activeFlash = nil

    -- Quick-action buttons removed from the HUD — List (F7), Favors (F6), and
    -- Admin (via NPC Settings panel) are already reachable without them.
    self.hudButtons = {}
    self.hudButtonRects = {}

    -- Color palette
    self.COLORS = {
        BG          = {0.10, 0.10, 0.10, 0.70},
        BORDER      = {0.30, 0.50, 0.90, 0.80},
        HEADER      = {1.00, 1.00, 1.00, 1.00},
        TEXT        = {1.00, 1.00, 1.00, 1.00},
        TEXT_DIM    = {0.80, 0.80, 0.80, 1.00},
        TIME_OK     = {0.30, 0.80, 0.30, 1.00},
        TIME_WARN   = {0.80, 0.80, 0.30, 1.00},
        TIME_URGENT = {0.80, 0.30, 0.30, 1.00},
        BAR_BG      = {0.10, 0.10, 0.10, 0.80},
        HINT        = {0.70, 0.80, 1.00, 0.90},
        DIST_CLOSE  = {0.30, 0.90, 0.30, 1.00},
        DIST_MED    = {0.90, 0.90, 0.30, 1.00},
        DIST_FAR    = {0.70, 0.70, 0.70, 1.00},
        FLASH_BG    = {0.15, 0.15, 0.15, 0.85},
        SHADOW              = {0.00, 0.00, 0.00, 0.40},
        BORDER_NORMAL       = {0.35, 0.40, 0.50, 0.50},
        RESIZE_HANDLE       = {0.30, 0.50, 0.90, 0.60},
        RESIZE_HANDLE_HOVER = {0.50, 0.70, 1.00, 0.90},
        RESIZE_ACTIVE       = {0.30, 0.80, 0.30, 0.80},
    }

    -- Base dimensions (before scale)
    self.BASE_WIDTH = 0.28
    self.BASE_LINE_HEIGHT = 0.016
    self.BASE_FAVOR_HEIGHT = 0.038
    self.BASE_HEADER_HEIGHT = 0.025
    self.BASE_PADDING = 0.01
    self.BASE_TEXT_SMALL = 0.013
    self.BASE_TEXT_MEDIUM = 0.016
    self.BASE_FLASH_HEIGHT = 0.025
    self.MAX_FAVORS = 5

    -- 1x1 pixel overlay for colored rectangles
    self.bgOverlay = nil
    if createImageOverlay then
        self.bgOverlay = createImageOverlay("dataS/menu/base/graph_pixel.dds")
    end

    return self
end

-- =========================================================
-- Settings Integration
-- =========================================================

function NPCFavorHUD:loadFromSettings(settings)
    if not settings then return end
    self.posX = settings.favorHudPosX or 0.024167
    self.posY = settings.favorHudPosY or 0.712592
    self.scale = settings.favorHudScale or 1.200786
    self.widthMult = settings.favorHudWidthMult or 0.517187
    self:clampPosition()
end

function NPCFavorHUD:saveToSettings(settings)
    if not settings then return end
    settings.favorHudPosX = self.posX
    settings.favorHudPosY = self.posY
    settings.favorHudScale = self.scale
    settings.favorHudWidthMult = self.widthMult
end

-- =========================================================
-- Edit Mode (right-click toggle)
-- =========================================================

function NPCFavorHUD:toggleEditMode()
    if self.editMode then
        self:exitEditMode()
    else
        self:enterEditMode()
    end
end

function NPCFavorHUD:enterEditMode()
    self.editMode = true
    self.dragging = false

    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(true)
    end

    -- Save camera rotation so we can freeze it each frame
    if getCamera then
        local cam = getCamera()
        if cam and cam ~= 0 and getRotation then
            self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ = getRotation(cam)
        end
    end

    print("[NPC Favor] HUD edit mode enabled — drag the favor list to reposition")
end

function NPCFavorHUD:exitEditMode()
    -- 2026-08-22 (Wizard): while MasterHUD suite edit is ON, the suite owns this
    -- session - only the suite exit (bridge sets _suiteExiting) may end it. The
    -- in-vehicle auto-exit in main.lua used to kill the favor HUD's edit one frame
    -- after the suite entered it (log 18:45:07.588 enabled -> .599 disabled).
    local mh = (g_currentMission ~= nil and g_currentMission.masterHUD) or g_masterHUD
    if mh ~= nil and mh.isLayoutEditMode ~= nil and mh:isLayoutEditMode() and not self._suiteExiting then
        return
    end
    self.editMode = false
    self.dragging = false
    self.resizing = false
    self.edgeDragging = nil
    self.hoverCorner = nil

    -- Release camera lock
    self.savedCamRotX = nil
    self.savedCamRotY = nil
    self.savedCamRotZ = nil

    if g_inputBinding and g_inputBinding.setShowMouseCursor then
        g_inputBinding:setShowMouseCursor(false)
    end

    self:saveToSettings(self.npcSystem.settings)

    print("[NPC Favor] HUD edit mode disabled — position saved")
end

-- =========================================================
-- Mouse Event (drag logic)
-- =========================================================

function NPCFavorHUD:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    if not self.editMode then return false end

    -- Check button clicks (edit mode only, left-click)
    if isDown and button == 1 then
        local btn = self:hitTestButton(posX, posY)
        if btn then
            print("[NPC Favor] HUD button clicked: " .. btn.id)
            self:exitEditMode()
            DialogLoader.show(btn.action, "setNPCSystem", self.npcSystem)
            return true
        end
    end

    -- Left-click down: start edge-drag, corner-resize, or body-drag
    if isDown and button == 1 then
        -- Check edge handles first (width resize)
        local edge = self:hitTestEdge(posX, posY)
        if edge then
            print("[NPC Favor] HUD edge-drag started — edge=" .. edge .. " widthMult=" .. string.format("%.2f", self.widthMult))
            self.edgeDragging = edge
            self.dragging = false
            self.resizing = false
            self.edgeDragStartX = posX
            self.edgeDragStartWidth = self.widthMult
            return true
        end

        -- Check corner handles (uniform scale resize)
        local corner = self:hitTestCorner(posX, posY)
        if corner then
            print("[NPC Favor] HUD resize started — corner=" .. corner .. " scale=" .. string.format("%.2f", self.scale))
            self.resizing = true
            self.dragging = false
            self.edgeDragging = nil
            self.resizeStartMouseX = posX
            self.resizeStartMouseY = posY
            self.resizeStartScale = self.scale
            return true
        end

        -- Fall through to drag if click is on body
        local hudX, hudY, hudW, hudH = self:getHUDRect()
        if posX >= hudX and posX <= hudX + hudW and posY >= hudY and posY <= hudY + hudH then
            print("[NPC Favor] HUD drag started — pos=" .. string.format("%.3f,%.3f", self.posX, self.posY))
            self.dragging = true
            self.resizing = false
            self.edgeDragging = nil
            self.dragOffsetX = posX - self.posX
            self.dragOffsetY = posY - self.posY
        end
    end

    -- Left-click up: end drag, resize, or edge-drag
    if isUp and button == 1 then
        if self.dragging or self.resizing or self.edgeDragging then
            local mode = self.edgeDragging and ("edge-" .. self.edgeDragging) or (self.resizing and "resize" or "drag")
            print("[NPC Favor] HUD " .. mode .. " ended — pos=" .. string.format("%.3f,%.3f", self.posX, self.posY) .. " scale=" .. string.format("%.2f", self.scale) .. " width=" .. string.format("%.2f", self.widthMult))
            self.dragging = false
            self.resizing = false
            self.edgeDragging = nil
            self:clampPosition()
            self:saveToSettings(self.npcSystem.settings)
        end
    end

    -- Track movement during drag/resize/edge-drag
    if self.dragging then
        self.posX = posX - self.dragOffsetX
        self.posY = posY - self.dragOffsetY
        self:clampPosition()
    end

    if self.resizing then
        local dx = posX - self.resizeStartMouseX
        local dy = posY - self.resizeStartMouseY
        -- Use distance from HUD center: dragging AWAY = grow, TOWARD = shrink
        local diagonal = math.sqrt(dx * dx + dy * dy) * 2.0
        local hudX, hudY, hudW, hudH = self:getHUDRect()
        local cx, cy = hudX + hudW / 2, hudY + hudH / 2
        local startDist = math.sqrt((self.resizeStartMouseX - cx)^2 + (self.resizeStartMouseY - cy)^2)
        local currDist = math.sqrt((posX - cx)^2 + (posY - cy)^2)
        if currDist < startDist then
            diagonal = -diagonal
        end
        local newScale = self.resizeStartScale + diagonal
        self.scale = math.max(self.MIN_SCALE, math.min(self.MAX_SCALE, newScale))
        self:clampPosition()
    end

    if self.edgeDragging then
        local dx = posX - self.edgeDragStartX
        -- Right edge: drag right = wider. Left edge: drag left = wider.
        if self.edgeDragging == "left" then dx = -dx end
        local sensitivity = 3.0  -- multiplier for drag-to-width feel
        local newMult = self.edgeDragStartWidth + dx * sensitivity
        self.widthMult = math.max(self.MIN_WIDTH_MULT, math.min(self.MAX_WIDTH_MULT, newMult))
        self:clampPosition()
    end

    return true
end

-- =========================================================
-- Geometry Helpers
-- =========================================================

function NPCFavorHUD:getHUDRect()
    local s = self.scale
    local w = self.BASE_WIDTH * self.widthMult * s
    local pad = self.BASE_PADDING * s

    local favorCount = 0
    if self.npcSystem and self.npcSystem.favorSystem then
        local favors = self.npcSystem.favorSystem:getActiveFavors()
        if favors then
            favorCount = math.min(#favors, self.MAX_FAVORS)
        end
    end

    if favorCount == 0 and self.editMode then
        favorCount = 1
    end

    local favorBlockH = self.BASE_FAVOR_HEIGHT * s
    local headerH = self.BASE_HEADER_HEIGHT * s
    local contentShift = 0.005 * s
    local h = headerH + contentShift + favorCount * favorBlockH + pad * 2

    if self.npcSystem and self.npcSystem.favorSystem then
        local favors = self.npcSystem.favorSystem:getActiveFavors()
        if favors and #favors > self.MAX_FAVORS then
            h = h + self.BASE_LINE_HEIGHT * s
        end
    end

    local x = self.posX - pad
    local y = self.posY - h + pad

    return x, y, w + pad * 2, h
end

function NPCFavorHUD:clampPosition()
    local s = self.scale
    local w = self.BASE_WIDTH * self.widthMult * s + self.BASE_PADDING * s * 2
    local h = self.BASE_HEADER_HEIGHT * s + self.BASE_FAVOR_HEIGHT * s + self.BASE_PADDING * s * 2

    self.posX = math.max(0.01, math.min(1.0 - w + 0.01, self.posX))
    self.posY = math.max(h + 0.01, math.min(0.99, self.posY))
end

-- =========================================================
-- Resize Handle Geometry
-- =========================================================

function NPCFavorHUD:getResizeHandleRects()
    local hudX, hudY, hudW, hudH = self:getHUDRect()
    local hs = self.RESIZE_HANDLE_SIZE
    return {
        bl = {x = hudX,             y = hudY,             w = hs, h = hs},
        br = {x = hudX + hudW - hs, y = hudY,             w = hs, h = hs},
        tl = {x = hudX,             y = hudY + hudH - hs, w = hs, h = hs},
        tr = {x = hudX + hudW - hs, y = hudY + hudH - hs, w = hs, h = hs},
    }
end

function NPCFavorHUD:hitTestCorner(posX, posY)
    local handles = self:getResizeHandleRects()
    for key, rect in pairs(handles) do
        if posX >= rect.x and posX <= rect.x + rect.w
           and posY >= rect.y and posY <= rect.y + rect.h then
            return key
        end
    end
    return nil
end

-- =========================================================
-- Edge Hit-Testing (left/right border for width resize)
-- =========================================================

function NPCFavorHUD:hitTestEdge(posX, posY)
    local hudX, hudY, hudW, hudH = self:getHUDRect()
    local edgeW = 0.008  -- hit area width for edge grab
    -- Left edge
    if posX >= hudX - edgeW / 2 and posX <= hudX + edgeW / 2
       and posY >= hudY and posY <= hudY + hudH then
        return "left"
    end
    -- Right edge
    if posX >= hudX + hudW - edgeW / 2 and posX <= hudX + hudW + edgeW / 2
       and posY >= hudY and posY <= hudY + hudH then
        return "right"
    end
    return nil
end

-- =========================================================
-- HUD Button Hit-Testing
-- =========================================================

function NPCFavorHUD:hitTestButton(posX, posY)
    for _, btn in ipairs(self.hudButtons) do
        local rect = self.hudButtonRects[btn.id]
        if rect and posX >= rect.x and posX <= rect.x + rect.w
           and posY >= rect.y and posY <= rect.y + rect.h then
            return btn
        end
    end
    return nil
end

function NPCFavorHUD:isPointerOverHUD(posX, posY)
    local x, y, w, h = self:getHUDRect()
    return posX >= x and posX <= x + w and posY >= y and posY <= y + h
end

-- =========================================================
-- Flash Notification System
-- =========================================================

function NPCFavorHUD:flashFavor(message, color)
    table.insert(self.flashQueue, {
        message = message or "",
        color = color or {1, 0.9, 0.3, 1},
        timer = 0,
        duration = 4
    })
end

-- =========================================================
-- Compass & Distance Helpers
-- =========================================================

function NPCFavorHUD:getPlayerPosition()
    if self.npcSystem and self.npcSystem.playerPositionValid then
        local pp = self.npcSystem.playerPosition
        return pp.x, pp.y, pp.z
    end
    return nil, nil, nil
end

function NPCFavorHUD:getCompassDirection(playerX, playerZ, npcX, npcZ)
    local dx = npcX - playerX
    local dz = npcZ - playerZ
    local angle = math.atan2(dx, dz)
    if angle < 0 then angle = angle + 2 * math.pi end
    local degrees = math.deg(angle)

    local dirKeys = {
        "npc_hud_compass_n", "npc_hud_compass_ne", "npc_hud_compass_e", "npc_hud_compass_se",
        "npc_hud_compass_s", "npc_hud_compass_sw", "npc_hud_compass_w", "npc_hud_compass_nw"
    }
    local fallback = {"N", "NE", "E", "SE", "S", "SW", "W", "NW"}
    local index = math.floor((degrees + 22.5) / 45) % 8 + 1
    return g_i18n:getText(dirKeys[index]) or fallback[index]
end

function NPCFavorHUD:getDistanceInfo(playerX, playerZ, npcX, npcZ)
    local dx = npcX - playerX
    local dz = npcZ - playerZ
    local dist = math.sqrt(dx * dx + dz * dz)

    -- Raw angle (radians, 0 = +Z north, increases clockwise)
    local angle = math.atan2(dx, dz)

    local compass = self:getCompassDirection(playerX, playerZ, npcX, npcZ)

    local distText
    if dist < 1000 then
        distText = string.format("%s %dm", compass, math.floor(dist))
    else
        distText = string.format("%s %.1fkm", compass, dist / 1000)
    end

    local color
    if dist < 100 then
        color = self.COLORS.DIST_CLOSE
    elseif dist <= 500 then
        color = self.COLORS.DIST_MED
    else
        color = self.COLORS.DIST_FAR
    end

    return distText, color, angle, dist
end

-- =========================================================
-- Compass Needle Rendering
-- =========================================================

--- Arrow shape defined as grid offsets (pointing north/up).
-- Each {x, y} is a grid cell; (0,0) is center. +Y = up, +X = right.
-- Rendered as small rectangles, rotated by angle via 2D rotation matrix.
NPCFavorHUD.ARROW_DOTS = {
    -- Arrowhead
    { 0,  3},                       -- tip
    {-1,  2}, { 0,  2}, { 1,  2},   -- head row 1
    {-2,  1},            { 2,  1},   -- head wings
    -- Shaft
    { 0,  0},
    { 0, -1},
    { 0, -2},
}

--- Draw a small compass needle indicator at (cx, cy).
-- Renders a pixel-art arrow shape composed of small rectangles,
-- rotated smoothly to point toward the NPC. Each "pixel" of the
-- arrow is a tiny overlay square whose position is computed via
-- 2D rotation — the overlay system never needs to rotate anything.
-- @param cx  Center X in normalized screen coords
-- @param cy  Center Y in normalized screen coords
-- @param angle  Direction angle in radians (0 = north/+Z)
-- @param color  {r, g, b, a} for the arrow dots
function NPCFavorHUD:drawCompassNeedle(cx, cy, angle, color)
    if not self.bgOverlay then return end

    local s = self.scale
    local ar = (g_screenWidth or 1920) / (g_screenHeight or 1080)

    -- Background (visually square dark box)
    local bgH = 0.022 * s
    local bgW = bgH / ar
    setOverlayColor(self.bgOverlay, 0.15, 0.15, 0.15, 0.80)
    renderOverlay(self.bgOverlay, cx - bgW / 2, cy - bgH / 2, bgW, bgH)

    -- Grid unit size: arrow spans ~6 units tall, fill ~70% of box
    local unit = bgH * 0.105
    local unitW = unit / ar         -- aspect-corrected width
    local dotH = unit * 0.95        -- dot slightly smaller than grid for gaps
    local dotW = dotH / ar

    -- Precompute rotation (clockwise by angle)
    local cosA = math.cos(angle)
    local sinA = math.sin(angle)

    -- Render each dot of the arrow shape, rotated
    setOverlayColor(self.bgOverlay, color[1], color[2], color[3], color[4] or 1)
    for _, dot in ipairs(self.ARROW_DOTS) do
        local gx, gy = dot[1], dot[2]
        -- Rotate grid position: clockwise rotation maps north-arrow to angle
        local rx = gx * cosA + gy * sinA
        local ry = -gx * sinA + gy * cosA
        -- Convert to screen coords (aspect-correct X)
        local px = cx + rx * unitW
        local py = cy + ry * unit
        renderOverlay(self.bgOverlay, px - dotW / 2, py - dotH / 2, dotW, dotH)
    end
end

--- Draw a small centered dot when the NPC is within proximity (< 3m).
-- Replaces the directional arrow to avoid erratic atan2 angles at near-zero distance.
-- @param cx  Center X in normalized screen coords
-- @param cy  Center Y in normalized screen coords
-- @param color  {r, g, b, a} for the dot
function NPCFavorHUD:drawProximityDot(cx, cy, color)
    if not self.bgOverlay then return end
    local s = self.scale
    local ar = (g_screenWidth or 1920) / (g_screenHeight or 1080)
    local bgH = 0.022 * s
    local bgW = bgH / ar
    -- Background box (same as needle)
    setOverlayColor(self.bgOverlay, 0.15, 0.15, 0.15, 0.80)
    renderOverlay(self.bgOverlay, cx - bgW / 2, cy - bgH / 2, bgW, bgH)
    -- Centered dot (indicates NPC is right here)
    local dotH = bgH * 0.35
    local dotW = dotH / ar
    setOverlayColor(self.bgOverlay, color[1], color[2], color[3], color[4] or 1)
    renderOverlay(self.bgOverlay, cx - dotW / 2, cy - dotH / 2, dotW, dotH)
end

-- =========================================================
-- Update (per-frame logic, dt in seconds)
-- =========================================================

function NPCFavorHUD:update(dt)
    self.animTimer = self.animTimer + dt

    -- Per-frame edit mode enforcement
    if self.editMode then
        -- Re-assert cursor visibility (engine may reset it)
        if g_inputBinding and g_inputBinding.setShowMouseCursor then
            g_inputBinding:setShowMouseCursor(true)
        end

        -- Freeze camera rotation by resetting to saved values each frame.
        -- The Player's update processes mouse input and rotates the camera,
        -- but our appended update runs after — so we slam it back.
        if self.savedCamRotX and getCamera and setRotation then
            local cam = getCamera()
            if cam and cam ~= 0 then
                setRotation(cam, self.savedCamRotX, self.savedCamRotY, self.savedCamRotZ)
            end
        end
    end

    -- Flash timer processing
    if self.activeFlash then
        self.activeFlash.timer = self.activeFlash.timer + dt
        if self.activeFlash.timer >= self.activeFlash.duration then
            self.activeFlash = nil
        end
    end
    if not self.activeFlash and #self.flashQueue > 0 then
        self.activeFlash = table.remove(self.flashQueue, 1)
    end

    -- Auto-exit edit mode if any GUI overlay or dialog opens
    if self.editMode then
        if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then
            self:exitEditMode()
        end
    end

    -- Hover detection for resize handles
    if self.editMode and not self.dragging and not self.resizing then
        if g_inputBinding and g_inputBinding.mousePosXLast and g_inputBinding.mousePosYLast then
            self.hoverCorner = self:hitTestCorner(g_inputBinding.mousePosXLast, g_inputBinding.mousePosYLast)
        else
            self.hoverCorner = nil
        end
    elseif not self.editMode then
        self.hoverCorner = nil
    end
end

-- =========================================================
-- Draw (called every frame from NPCSystem:draw)
-- =========================================================

function NPCFavorHUD:draw()
    -- Don't draw over ESC menu, dialogs, or any GUI overlay
    if g_gui and (g_gui:getIsGuiVisible() or g_gui:getIsDialogVisible()) then
        return
    end

    -- Always draw flash notification even when favor list is hidden
    if self.activeFlash and self.bgOverlay then
        self:drawFlash()
    end

    if not self.npcSystem.settings.showFavorList and not self.editMode then
        return
    end

    if not self.bgOverlay then
        return
    end

    local favors = {}
    if self.npcSystem.favorSystem then
        favors = self.npcSystem.favorSystem:getActiveFavors() or {}
    end

    if #favors == 0 and not self.editMode then
        return
    end

    local s = self.scale
    local pad = self.BASE_PADDING * s
    local contentShift = 0.005 * s  -- small downward shift for breathing room
    local lineH = self.BASE_LINE_HEIGHT * s
    local favorBlockH = self.BASE_FAVOR_HEIGHT * s
    local headerH = self.BASE_HEADER_HEIGHT * s
    local textSmall = self.BASE_TEXT_SMALL * s
    local textMedium = self.BASE_TEXT_MEDIUM * s
    local w = self.BASE_WIDTH * self.widthMult * s

    local visibleCount = math.min(#favors, self.MAX_FAVORS)
    if visibleCount == 0 and self.editMode then
        visibleCount = 1
    end

    local hasOverflow = #favors > self.MAX_FAVORS
    local btnRowH = 0.020 * s  -- button height (0.014) + margins
    local bgH = headerH + contentShift + visibleCount * favorBlockH + btnRowH + pad * 2
    if hasOverflow then
        bgH = bgH + lineH
    end

    -- Background
    local bgX = self.posX - pad
    local bgY = self.posY - bgH + pad
    local bgW = w + pad * 2

    local renderer = getBaseGameRenderer()
    local usedNativePanel = renderer ~= nil and renderer.renderPanel ~= nil
        and renderer:renderPanel(bgX, bgY, bgW, bgH, self.COLORS.BG[4])
    if not usedNativePanel then
        -- Standalone fallback: retain the original graph_pixel shadow, fill and border.
        local shadowOff = 0.002 * s
        setOverlayColor(self.bgOverlay, self.COLORS.SHADOW[1], self.COLORS.SHADOW[2], self.COLORS.SHADOW[3], self.COLORS.SHADOW[4])
        renderOverlay(self.bgOverlay, bgX + shadowOff, bgY - shadowOff, bgW, bgH)

        setOverlayColor(self.bgOverlay, self.COLORS.BG[1], self.COLORS.BG[2], self.COLORS.BG[3], self.COLORS.BG[4])
        renderOverlay(self.bgOverlay, bgX, bgY, bgW, bgH)

        local bwNormal = 0.001
        setOverlayColor(self.bgOverlay, self.COLORS.BORDER_NORMAL[1], self.COLORS.BORDER_NORMAL[2], self.COLORS.BORDER_NORMAL[3], self.COLORS.BORDER_NORMAL[4])
        renderOverlay(self.bgOverlay, bgX, bgY + bgH - bwNormal, bgW, bwNormal)       -- top
        renderOverlay(self.bgOverlay, bgX, bgY, bgW, bwNormal)                         -- bottom
        renderOverlay(self.bgOverlay, bgX, bgY, bwNormal, bgH)                         -- left
        renderOverlay(self.bgOverlay, bgX + bgW - bwNormal, bgY, bwNormal, bgH)        -- right
    end

    -- Edit mode: pulsing border + resize handles
    if self.editMode then
        local pulse = 0.5 + 0.5 * math.sin(self.animTimer * 4)
        local borderAlpha = 0.4 + 0.4 * pulse
        local bw = 0.002

        -- Border color: green when resizing/edge-dragging, blue otherwise
        local borderColor = self.COLORS.BORDER
        if self.resizing or self.edgeDragging then
            borderColor = self.COLORS.RESIZE_ACTIVE
        end
        setOverlayColor(self.bgOverlay, borderColor[1], borderColor[2], borderColor[3], borderAlpha)
        renderOverlay(self.bgOverlay, bgX, bgY + bgH - bw, bgW, bw)
        renderOverlay(self.bgOverlay, bgX, bgY, bgW, bw)
        renderOverlay(self.bgOverlay, bgX, bgY, bw, bgH)
        renderOverlay(self.bgOverlay, bgX + bgW - bw, bgY, bw, bgH)

        -- Edge width handles (left and right borders, taller strips)
        local edgeHandleW = 0.004
        local edgeInset = bgH * 0.15  -- inset from top/bottom so they don't overlap corners
        local edgeH = bgH - edgeInset * 2
        local edgeY = bgY + edgeInset
        local leftEdgeColor = self.edgeDragging == "left" and self.COLORS.RESIZE_ACTIVE or self.COLORS.RESIZE_HANDLE
        local rightEdgeColor = self.edgeDragging == "right" and self.COLORS.RESIZE_ACTIVE or self.COLORS.RESIZE_HANDLE
        setOverlayColor(self.bgOverlay, leftEdgeColor[1], leftEdgeColor[2], leftEdgeColor[3], leftEdgeColor[4])
        renderOverlay(self.bgOverlay, bgX - edgeHandleW / 2, edgeY, edgeHandleW, edgeH)
        setOverlayColor(self.bgOverlay, rightEdgeColor[1], rightEdgeColor[2], rightEdgeColor[3], rightEdgeColor[4])
        renderOverlay(self.bgOverlay, bgX + bgW - edgeHandleW / 2, edgeY, edgeHandleW, edgeH)

        -- Corner resize handles
        local handles = self:getResizeHandleRects()
        for key, rect in pairs(handles) do
            local hc
            if self.resizing then
                hc = self.COLORS.RESIZE_ACTIVE
            elseif self.hoverCorner == key then
                hc = self.COLORS.RESIZE_HANDLE_HOVER
            else
                hc = self.COLORS.RESIZE_HANDLE
            end
            setOverlayColor(self.bgOverlay, hc[1], hc[2], hc[3], hc[4])
            renderOverlay(self.bgOverlay, rect.x, rect.y, rect.w, rect.h)
        end
    end

    -- Header (offset down by padding so it doesn't overlap status bar above)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    setTextColor(self.COLORS.HEADER[1], self.COLORS.HEADER[2], self.COLORS.HEADER[3], self.COLORS.HEADER[4])
    renderText(self.posX, self.posY - pad - contentShift, textMedium, g_i18n:getText("npc_hud_active_favors") or "Active Favors:")
    setTextBold(false)

    -- Get player position once for all compass calculations
    local playerX, _, playerZ = self:getPlayerPosition()

    -- Get camera heading via forward vector (same atan2 convention as dirAngle)
    local camAngle = 0
    if getCamera and localDirectionToWorld then
        local cam = getCamera()
        if cam and cam ~= 0 then
            local ok, fwdX, _, fwdZ = pcall(localDirectionToWorld, cam, 0, 0, -1)
            if ok and fwdX then
                camAngle = math.atan2(fwdX, fwdZ)
            end
        end
    end

    -- Favor entries (or drag hint)
    if #favors == 0 and self.editMode then
        setTextColor(self.COLORS.HINT[1], self.COLORS.HINT[2], self.COLORS.HINT[3], self.COLORS.HINT[4])
        local hintText = g_i18n:getText("npc_hud_drag_hint") or "Drag to move | Corners to resize"
        local scaleText = string.format(" (%d%%)", math.floor(self.scale * 100 + 0.5))
        renderText(self.posX, self.posY - pad - contentShift - headerH, textSmall, hintText .. scaleText)
    else
        for i = 1, visibleCount do
            local favor = favors[i]
            local baseY = self.posY - pad - contentShift - headerH - (i - 1) * favorBlockH
            local line1Y = baseY
            local line2Y = baseY - lineH

            local timeRemaining = favor.timeRemaining or 0
            local hours = timeRemaining / (60 * 60 * 1000)

            -- Time text
            local timeText
            if hours < 1 then
                timeText = string.format("%.0fm", hours * 60)
            else
                timeText = string.format("%.1fh", hours)
            end

            -- Time-based color
            local textColor = self.COLORS.TEXT
            if hours < 2 then
                textColor = self.COLORS.TIME_URGENT
            elseif hours < 6 then
                textColor = self.COLORS.TIME_WARN
            else
                textColor = self.COLORS.TIME_OK
            end

            -- Line 1: NPC name (left) + compass/distance (right)
            local npcName = favor.npcName or "NPC"
            if string.len(npcName) > 16 then
                npcName = string.sub(npcName, 1, 14) .. ".."
            end

            setTextAlignment(RenderText.ALIGN_LEFT)
            setTextBold(true)
            setTextColor(textColor[1], textColor[2], textColor[3], textColor[4])
            renderText(self.posX, line1Y, textSmall, npcName)
            setTextBold(false)

            -- Compass needle + distance (right side of line 1)
            -- Active/in_progress: point to first incomplete step; pending: point to NPC
            if playerX then
                local targetX, targetZ
                if favor.status ~= "pending" and favor.steps and #favor.steps > 0 then
                    for _, step in ipairs(favor.steps) do
                        if not step.completed and step.location then
                            targetX = step.location.x
                            targetZ = step.location.z
                            break
                        end
                    end
                end
                if not targetX then
                    local npc = self.npcSystem:getNPCById(favor.npcId)
                    local npcPos = npc and npc.position
                    if npcPos then targetX, targetZ = npcPos.x, npcPos.z end
                end
                if targetX then
                    local distText, distColor, dirAngle, dist = self:getDistanceInfo(playerX, playerZ, targetX, targetZ)

                    -- Compass needle indicator (camera-relative direction)
                    local ar = (g_screenWidth or 1920) / (g_screenHeight or 1080)
                    local needleSize = 0.022 * s
                    local needleW = needleSize / ar
                    local needleCX = self.posX + w - needleW / 2
                    local needleCY = line1Y + textSmall * 0.35
                    if dist and dist >= 3 then
                        self:drawCompassNeedle(needleCX, needleCY, camAngle - dirAngle, distColor)
                    else
                        self:drawProximityDot(needleCX, needleCY, distColor)
                    end

                    -- Distance text (left of needle)
                    setTextAlignment(RenderText.ALIGN_RIGHT)
                    setTextColor(distColor[1], distColor[2], distColor[3], distColor[4])
                    renderText(needleCX - needleW / 2 - 0.003 * s, line1Y, textSmall, distText)
                end
            end

            -- Line 2: Current step description for active/in_progress, or "(talk to accept)" for pending
            local desc
            if favor.status == "pending" then
                desc = "(talk to accept) " .. (favor.description or "")
            elseif favor.steps and #favor.steps > 0 then
                for _, step in ipairs(favor.steps) do
                    if not step.completed then
                        desc = step.description
                        break
                    end
                end
                desc = desc or (favor.description or "")
            else
                desc = favor.description or ""
            end
            if string.len(desc) > 34 then
                desc = string.sub(desc, 1, 32) .. ".."
            end

            setTextAlignment(RenderText.ALIGN_LEFT)
            setTextColor(self.COLORS.TEXT_DIM[1], self.COLORS.TEXT_DIM[2], self.COLORS.TEXT_DIM[3], self.COLORS.TEXT_DIM[4])
            renderText(self.posX, line2Y, textSmall * 0.9, desc)

            setTextAlignment(RenderText.ALIGN_RIGHT)
            setTextColor(textColor[1], textColor[2], textColor[3], textColor[4])
            renderText(self.posX + w, line2Y, textSmall * 0.9, timeText)

            -- Progress bar (below line 2, only when progress > 0)
            if favor.progress and favor.progress > 0 then
                local barWidth = w * 0.6
                local barHeight = (6 / 1080) * s
                local barY = line2Y - 0.007 * s

                local barColor = {textColor[1], textColor[2], textColor[3], 0.8}
                local usedNativeBar = renderer ~= nil and renderer.renderProgressBar ~= nil
                    and renderer:renderProgressBar(self.posX, barY, barWidth, barHeight,
                        favor.progress / 100, barColor)
                if not usedNativeBar then
                    setOverlayColor(self.bgOverlay, self.COLORS.BAR_BG[1], self.COLORS.BAR_BG[2], self.COLORS.BAR_BG[3], self.COLORS.BAR_BG[4])
                    renderOverlay(self.bgOverlay, self.posX, barY, barWidth, barHeight)

                    local progressWidth = barWidth * (favor.progress / 100)
                    setOverlayColor(self.bgOverlay, textColor[1], textColor[2], textColor[3], 0.8)
                    renderOverlay(self.bgOverlay, self.posX, barY, progressWidth, barHeight)
                end

                setTextAlignment(RenderText.ALIGN_LEFT)
                setTextColor(self.COLORS.TEXT_DIM[1], self.COLORS.TEXT_DIM[2], self.COLORS.TEXT_DIM[3], self.COLORS.TEXT_DIM[4])
                renderText(self.posX + barWidth + 0.005 * s, barY, textSmall * 0.8, string.format("%d%%", favor.progress))
            end
        end
    end

    -- Overflow count
    if hasOverflow then
        local yPos = self.posY - pad - contentShift - headerH - visibleCount * favorBlockH
        setTextAlignment(RenderText.ALIGN_LEFT)
        setTextColor(self.COLORS.TEXT_DIM[1], self.COLORS.TEXT_DIM[2], self.COLORS.TEXT_DIM[3], self.COLORS.TEXT_DIM[4])
        renderText(self.posX, yPos, textSmall * 0.9,
            string.format(g_i18n:getText("npc_hud_and_more") or "...and %d more", #favors - self.MAX_FAVORS))
    end

    -- Version watermark (bottom-right corner, very small and dim)
    local versionY = bgY + 0.003 * s
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(0.4, 0.4, 0.4, 0.4)
    local ver = (g_NPCFavorMod and g_NPCFavorMod.version) or "?"
    renderText(self.posX + w - 0.002 * s, versionY, textSmall * 0.6, "FS25_NPCFavor v" .. ver)


    -- Reset text state
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

-- =========================================================
-- Flash Rendering (above the HUD box)
-- =========================================================

function NPCFavorHUD:drawFlash()
    if not self.activeFlash or not self.bgOverlay then return end

    local s = self.scale
    local textSize = self.BASE_TEXT_SMALL * s
    local lineSpacing = textSize * 1.3
    local pad = self.BASE_PADDING * s
    local w = self.BASE_WIDTH * self.widthMult * s

    -- Split message into lines (handles \n from multi-line notifications)
    local lines = {}
    local msg = self.activeFlash.message or ""
    for line in (msg .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then
            table.insert(lines, line)
        end
    end
    if #lines == 0 then
        lines = {msg}
    end

    -- Dynamic height based on line count
    local flashH = pad + #lines * lineSpacing + pad * 0.5
    local flashX = self.posX - pad
    local flashW = w + pad * 2
    local flashY = self.posY + 0.008

    -- Fade in (first 0.3s), pulse during middle, fade out (last 1s)
    local t = self.activeFlash.timer
    local d = self.activeFlash.duration
    local alpha = 1.0
    if t < 0.3 then
        alpha = t / 0.3
    elseif t > d - 1.0 then
        alpha = math.max(0, (d - t) / 1.0)
    end

    local pulse = 0.7 + 0.3 * math.sin(t * 6)
    local textAlpha = alpha * pulse

    -- Flash background (dynamic height)
    setOverlayColor(self.bgOverlay, self.COLORS.FLASH_BG[1], self.COLORS.FLASH_BG[2], self.COLORS.FLASH_BG[3], self.COLORS.FLASH_BG[4] * alpha)
    renderOverlay(self.bgOverlay, flashX, flashY, flashW, flashH)

    -- Colored accent bar on the left edge
    local c = self.activeFlash.color
    setOverlayColor(self.bgOverlay, c[1], c[2], c[3], (c[4] or 1) * alpha)
    renderOverlay(self.bgOverlay, flashX, flashY, 0.003, flashH)

    -- Render each line (top to bottom within the flash box)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    setTextColor(c[1], c[2], c[3], textAlpha)
    for i, line in ipairs(lines) do
        local lineY = flashY + flashH - pad - i * lineSpacing
        -- First line is bold, rest are normal weight and slightly dimmer
        if i > 1 then
            setTextBold(false)
            setTextColor(c[1], c[2], c[3], textAlpha * 0.8)
        end
        renderText(flashX + 0.008, lineY, textSize, line)
    end
    setTextBold(false)

    -- Reset text state
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

-- =========================================================
-- Cleanup
-- =========================================================

function NPCFavorHUD:delete()
    if self.editMode then
        if g_inputBinding and g_inputBinding.setShowMouseCursor then
            g_inputBinding:setShowMouseCursor(false)
        end
        self.editMode = false
        self.dragging = false
        self.resizing = false
        self.edgeDragging = nil
        self.hoverCorner = nil
        self.savedCamRotX = nil
        self.savedCamRotY = nil
        self.savedCamRotZ = nil
    end

    if self.bgOverlay then
        delete(self.bgOverlay)
        self.bgOverlay = nil
    end

end

-- =========================================================
-- BUILD 17:57 + ATTN 18:02 (hot-reload guide Part 2): force-patch the live
-- instance after a Ctrl+R reload - mission.npcFavorSystem published in main.lua; holds .favorHUD.
if g_currentMission ~= nil and g_currentMission.npcFavorSystem ~= nil and g_currentMission.npcFavorSystem.favorHUD ~= nil then
    local inst = g_currentMission.npcFavorSystem.favorHUD
    for k, v in pairs(NPCFavorHUD) do
        if type(v) == "function" then
            inst[k] = v
        end
    end
end
