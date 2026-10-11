-- =========================================================
-- NpcLiveKeyLabel - truthful Controls chord for an InputAction
-- =========================================================
-- George-verified path (extract InputBinding / InputHelper):
--   g_inputBinding:getActionBindings() -> action:getActiveBindings()
--   prefer keyboard binding; build full chord from binding.axisNames
--   display via KeyboardHelper.getDisplayKeyName(Input[axisName])
-- Empty authoritative bindings -> localized Unbound (not factory default).
-- Non-keyboard-only bindings -> localized Keyboard unbound (not whole-action Unbound).
-- Missing API/data / malformed bindings / failed action lookup -> localized unavailable.
-- Action identity from getActionByName / nameActions only (not InputAction constants).
-- Never use single-axis helpers (lossy for chords).
-- Never present factory default as a live label.
-- =========================================================

NpcLiveKeyLabel = NpcLiveKeyLabel or {}

NpcLiveKeyLabel.STATUS_UNBOUND = "rf_live_key_unbound"
NpcLiveKeyLabel.STATUS_KEYBOARD_UNBOUND = "rf_live_key_keyboard_unbound"
NpcLiveKeyLabel.STATUS_UNAVAILABLE = "rf_live_key_unavailable"

local function localize(key, fallback)
    if g_i18n ~= nil then
        if type(g_i18n.hasText) == "function" then
            local ok, has = pcall(g_i18n.hasText, g_i18n, key)
            if ok and has then
                local ok2, text = pcall(g_i18n.getText, g_i18n, key)
                if ok2 and type(text) == "string" and text ~= "" and text ~= key then
                    return text
                end
            end
        end
        if type(g_i18n.getText) == "function" then
            local ok, text = pcall(g_i18n.getText, g_i18n, key)
            if ok and type(text) == "string" and text ~= "" and text ~= key then
                return text
            end
        end
    end
    return fallback
end

function NpcLiveKeyLabel.unboundText()
    return localize(NpcLiveKeyLabel.STATUS_UNBOUND, "Unbound")
end

function NpcLiveKeyLabel.keyboardUnboundText()
    return localize(NpcLiveKeyLabel.STATUS_KEYBOARD_UNBOUND, "Keyboard unbound")
end

function NpcLiveKeyLabel.unavailableText()
    return localize(NpcLiveKeyLabel.STATUS_UNAVAILABLE, "unavailable")
end

local function isKeyboardBinding(binding)
    if type(binding) ~= "table" then
        return false
    end
    if binding.isKeyboard == true then
        return true
    end
    if binding.isMouse == true or binding.isGamepad == true then
        return false
    end
    if type(binding.axisNames) ~= "table" or Input == nil then
        return false
    end
    if #binding.axisNames == 0 then
        return false
    end
    for _, axisName in ipairs(binding.axisNames) do
        if type(axisName) ~= "string" or Input[axisName] == nil then
            return false
        end
    end
    return true
end

local function bindingLooksMalformed(binding)
    if type(binding) ~= "table" then
        return true
    end
    if binding.axisNames ~= nil and type(binding.axisNames) ~= "table" then
        return true
    end
    if type(binding.axisNames) == "table" then
        for _, axisName in ipairs(binding.axisNames) do
            if type(axisName) ~= "string" then
                return true
            end
        end
    end
    return false
end

local function selectPrimaryKeyboardBinding(bindings)
    if type(bindings) ~= "table" then
        return nil
    end
    local selected = nil
    for _, binding in ipairs(bindings) do
        if isKeyboardBinding(binding) then
            local selectedIndex = selected ~= nil and tonumber(selected.index) or math.huge
            local bindingIndex = tonumber(binding.index) or math.huge
            local selectedPositive = selected ~= nil and selected.axisComponent == "+"
            local bindingPositive = binding.axisComponent == "+"
            if selected == nil
                or bindingIndex < selectedIndex
                or (bindingIndex == selectedIndex and bindingPositive and not selectedPositive) then
                selected = binding
            end
        end
    end
    return selected
end

local function displayNameForAxis(axisName)
    if axisName == nil or Input == nil or KeyboardHelper == nil then
        return nil
    end
    if type(KeyboardHelper.getDisplayKeyName) ~= "function" then
        return nil
    end
    local keyId = Input[axisName]
    if keyId == nil then
        return nil
    end
    local ok, name = pcall(KeyboardHelper.getDisplayKeyName, keyId)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function formatChord(binding)
    if binding == nil or type(binding.axisNames) ~= "table" or #binding.axisNames == 0 then
        return nil
    end
    local parts = {}
    for _, axisName in ipairs(binding.axisNames) do
        local name = displayNameForAxis(axisName)
        if name == nil then
            return nil
        end
        parts[#parts + 1] = name
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, " + ")
end

local function resolveActionObject(actionName)
    -- Engine-shaped identity only (InputBinding:getActionByName / nameActions).
    -- Do not fall back to InputAction[actionName]; that constant may not be the map key.
    if g_inputBinding == nil then
        return nil
    end
    if type(g_inputBinding.getActionByName) == "function" then
        local okA, a = pcall(g_inputBinding.getActionByName, g_inputBinding, actionName)
        if okA and a ~= nil then
            return a
        end
    end
    if type(g_inputBinding.nameActions) == "table" then
        local a = g_inputBinding.nameActions[actionName]
        if a ~= nil then
            return a
        end
    end
    return nil
end

function NpcLiveKeyLabel.resolve(actionName)
    if actionName == nil or actionName == "" then
        return NpcLiveKeyLabel.unavailableText(), "unavailable"
    end
    if g_inputBinding == nil or type(g_inputBinding.getActionBindings) ~= "function" then
        return NpcLiveKeyLabel.unavailableText(), "unavailable"
    end
    if KeyboardHelper == nil or type(KeyboardHelper.getDisplayKeyName) ~= "function" then
        return NpcLiveKeyLabel.unavailableText(), "unavailable"
    end
    if Input == nil then
        return NpcLiveKeyLabel.unavailableText(), "unavailable"
    end

    local okMap, actionBindings = pcall(g_inputBinding.getActionBindings, g_inputBinding)
    if not okMap or type(actionBindings) ~= "table" then
        return NpcLiveKeyLabel.unavailableText(), "unavailable"
    end

    local actionObject = resolveActionObject(actionName)
    if actionObject == nil then
        return NpcLiveKeyLabel.unavailableText(), "unavailable"
    end

    local bindings = actionBindings[actionObject]
    if bindings == nil and type(actionObject.getActiveBindings) == "function" then
        local okB, b = pcall(actionObject.getActiveBindings, actionObject)
        if okB then
            bindings = b
        end
    end
    if type(bindings) ~= "table" then
        return NpcLiveKeyLabel.unavailableText(), "unavailable"
    end

    if #bindings == 0 then
        return NpcLiveKeyLabel.unboundText(), "unbound"
    end

    for _, binding in ipairs(bindings) do
        if bindingLooksMalformed(binding) then
            return NpcLiveKeyLabel.unavailableText(), "unavailable"
        end
    end

    local keyboard = selectPrimaryKeyboardBinding(bindings)
    if keyboard == nil then
        -- Bindings exist but none are keyboard: do not imply the whole action is unbound.
        return NpcLiveKeyLabel.keyboardUnboundText(), "keyboard_unbound"
    end

    local chord = formatChord(keyboard)
    if chord == nil then
        return NpcLiveKeyLabel.unavailableText(), "unavailable"
    end
    return chord, "live"
end

function NpcLiveKeyLabel.get(actionName)
    local label = NpcLiveKeyLabel.resolve(actionName)
    return label
end

function NpcLiveKeyLabel.subscribe(target, callback)
    if g_messageCenter == nil or MessageType == nil or MessageType.INPUT_BINDINGS_CHANGED == nil then
        return nil
    end
    if type(callback) ~= "function" then
        return nil
    end
    local ok = pcall(g_messageCenter.subscribe, g_messageCenter, MessageType.INPUT_BINDINGS_CHANGED, callback, target)
    if not ok then
        return nil
    end
    return function()
        pcall(g_messageCenter.unsubscribe, g_messageCenter, MessageType.INPUT_BINDINGS_CHANGED, target)
    end
end
