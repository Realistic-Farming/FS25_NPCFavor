-- =========================================================
-- FS25 NPC Favor Mod - Dialog Loader
-- =========================================================
-- Centralized dialog registration and management (UsedPlus pattern).
-- Dialogs are registered at startup but lazily loaded on first show.
--
-- Usage:
--   DialogLoader.register("MyDialog", MyDialogClass, "gui/MyDialog.xml")
--   DialogLoader.show("MyDialog", "setData", someData)
--   DialogLoader.close("MyDialog")
-- =========================================================

DialogLoader = DialogLoader or {}

-- Registry: name -> { class, xmlPath, instance, loaded }
DialogLoader.dialogs = {}

-- Mod directory (set once during init)
DialogLoader.modDirectory = nil

--- Initialize with the mod's base directory path.
-- @param modDir  Mod directory string (with trailing slash)
function DialogLoader.init(modDir)
    DialogLoader.modDirectory = modDir
end

--- Register a dialog class and XML path for lazy loading.
-- @param name        Unique dialog name (used as g_gui key)
-- @param dialogClass The Lua class table (must have .new())
-- @param xmlPath     Relative path from mod root to the XML layout file
function DialogLoader.register(name, dialogClass, xmlPath)
    if not name or not dialogClass or not xmlPath then
        print("[DialogLoader] ERROR: register() requires name, class, xmlPath")
        return
    end
    DialogLoader.dialogs[name] = {
        class = dialogClass,
        xmlPath = xmlPath,
        instance = nil,
        loaded = false
    }
end

--- Ensure a dialog is loaded into g_gui (lazy load on first use).
-- @param name  Dialog name
-- @return boolean  true if dialog is loaded and ready
function DialogLoader.ensureLoaded(name)
    local entry = DialogLoader.dialogs[name]
    if not entry then
        print("[DialogLoader] ERROR: Dialog '" .. tostring(name) .. "' not registered")
        return false
    end

    if entry.loaded then
        return true
    end

    if not g_gui then
        print("[DialogLoader] ERROR: g_gui not available")
        return false
    end

    local modDir = DialogLoader.modDirectory
    if not modDir then
        print("[DialogLoader] ERROR: modDirectory not set (call DialogLoader.init first)")
        return false
    end

    local ok, err = pcall(function()
        local instance = entry.class.new()
        g_gui:loadGui(modDir .. entry.xmlPath, name, instance)
        entry.instance = instance
        entry.loaded = true
    end)

    if not ok then
        print("[DialogLoader] ERROR loading '" .. name .. "': " .. tostring(err))
        return false
    end

    -- Verify
    if g_gui.guis and g_gui.guis[name] then
        print("[DialogLoader] '" .. name .. "' loaded OK")
        return true
    else
        print("[DialogLoader] WARNING: '" .. name .. "' loadGui completed but not found in g_gui.guis")
        entry.loaded = false
        return false
    end
end

--- Show a dialog, optionally calling a data-setter method first.
-- @param name        Dialog name
-- @param dataMethod  Optional: name of method to call on instance before showing (string)
-- @param ...         Arguments to pass to the data-setter method
-- @return boolean    true if dialog was shown
function DialogLoader.show(name, dataMethod, ...)
    if not DialogLoader.ensureLoaded(name) then
        return false
    end

    local entry = DialogLoader.dialogs[name]
    if not entry or not entry.instance then
        return false
    end

    -- Call data setter if specified
    if dataMethod and entry.instance[dataMethod] then
        local ok, err = pcall(entry.instance[dataMethod], entry.instance, ...)
        if not ok then
            print("[DialogLoader] ERROR calling " .. name .. ":" .. dataMethod .. "(): " .. tostring(err))
        end
    end

    -- Show dialog
    local ok, err = pcall(function()
        g_gui:showDialog(name)
    end)

    if not ok then
        print("[DialogLoader] ERROR showing '" .. name .. "': " .. tostring(err))
        return false
    end

    return true
end

--- Get the dialog instance (for direct method calls).
-- @param name  Dialog name
-- @return Dialog instance or nil
function DialogLoader.getDialog(name)
    local entry = DialogLoader.dialogs[name]
    if entry then
        return entry.instance
    end
    return nil
end

--- Close a dialog if it's currently visible.
-- @param name  Dialog name
function DialogLoader.close(name)
    local entry = DialogLoader.dialogs[name]
    if entry and entry.instance then
        pcall(function() entry.instance:close() end)
    end
end

--- Unload all dialogs (call on mod unload).
function DialogLoader.cleanup()
    for name, entry in pairs(DialogLoader.dialogs) do
        if entry.instance then
            pcall(function() entry.instance:close() end)
        end
        entry.instance = nil
        entry.loaded = false
    end
end

print("[NPC Favor] DialogLoader loaded")
