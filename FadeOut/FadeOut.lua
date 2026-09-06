FadeOut = {}
local addon = FadeOut

-- ===================== Tunables =====================

addon.DEFAULT_FADE_ALPHA = 0.25   -- default idle opacity (0-1)
addon.DEFAULT_EXIT_DELAY = 1.0    -- default seconds to wait after combat ends
addon.MAX_EXIT_DELAY     = 20     -- upper bound offered on the delay slider
addon.FADE_OUT_TIME      = 3      -- seconds, out-of-combat fade
addon.FADE_IN_TIME       = 0.2    -- seconds, combat/mouseover fade
addon.REFRESH_FADE_TIME  = 0.15   -- seconds, quick re-fade when a slider is dragged
local POLL_INTERVAL      = 0.15   -- how often to check mouseover, in seconds

-- ===================== Trackable frames =====================
-- key       : internal id, used for saved settings
-- label     : shown in the GUI
-- frameName : global frame name to fade

addon.trackable = {
    { key = "mainbar",        label = "Main Action Bar",   frameName = "MainMenuBar" },
    { key = "bottomleftbar",  label = "Bottom Left Bar",   frameName = "MultiBarBottomLeft" },
    { key = "bottomrightbar", label = "Bottom Right Bar",  frameName = "MultiBarBottomRight" },
    { key = "rightbar",       label = "Right Bar",         frameName = "MultiBarRight" },
    { key = "rightbar2",      label = "Right Bar 2",       frameName = "MultiBarLeft" },
    { key = "petbar",         label = "Pet Action Bar",    frameName = "PetActionBarFrame" },
    { key = "stancebar",      label = "Stance Bar",        frameName = "StanceBarFrame" },
    { key = "bags",           label = "Backpack Button",   frameName = "MainMenuBarBackpackButton" },
    { key = "minimap",        label = "Minimap",           frameName = "Minimap" },
    { key = "chat",           label = "Chat Frame",        frameName = "ChatFrame1" },
    { key = "playerframe",    label = "Player Frame",      frameName = "PlayerFrame" },
    { key = "targetframe",    label = "Target Frame",      frameName = "TargetFrame" },
    { key = "partyframe",     label = "Party Frame",       frameName = "PartyMemberFrame1" },
    { key = "buffs",          label = "Buffs",             frameName = "BuffFrame" },
    { key = "durability",     label = "Durability Frame",  frameName = "DurabilityFrame" },
    { key = "watchframe",     label = "Quest Tracker",     frameName = "WatchFrame" },
}

-- runtime[key] = { frame = <frame ref>, state = "in" | "out" | nil }
addon.runtime = {}

local inCombat = false
local combatExitTimer = nil -- countdown in seconds, nil == not counting down

local mainFrame = CreateFrame("Frame", "FadeOutMainFrame")

-- ===================== Saved variables =====================

local function GetDB()
    if not FadeOutDB then
        FadeOutDB = {}
    end
    if not FadeOutDB.enabled then
        FadeOutDB.enabled = {}
    end
    if FadeOutDB.fadeAlpha == nil then
        FadeOutDB.fadeAlpha = addon.DEFAULT_FADE_ALPHA
    end
    if FadeOutDB.exitDelay == nil then
        FadeOutDB.exitDelay = addon.DEFAULT_EXIT_DELAY
    end
    return FadeOutDB
end

local function IsEnabled(key)
    local db = GetDB()
    if db.enabled[key] == nil then
        return true -- default: on
    end
    return db.enabled[key]
end

local function SetEnabled(key, val)
    local db = GetDB()
    db.enabled[key] = val
end

-- ===================== Mouseover detection =====================

-- Walks up from whatever is directly under the cursor to see if it is
-- (or is nested inside) the given frame. This is what lets hovering over
-- a button on an action bar correctly count as hovering the bar itself.
local function IsMouseOverFrame(frame)
    local focus = GetMouseFocus()
    while focus do
        if focus == frame then
            return true
        end
        local ok, parent = pcall(focus.GetParent, focus)
        if not ok or not parent then break end
        focus = parent
    end
    return false
end

-- ===================== Fade application =====================

local function ApplyState(entry, desiredIn)
    local frame = entry.frame
    if not frame then return end

    if desiredIn then
        if entry.state ~= "in" then
            entry.state = "in"
            UIFrameFadeIn(frame, addon.FADE_IN_TIME, frame:GetAlpha(), 1)
        end
    else
        if entry.state ~= "out" then
            entry.state = "out"
            local db = GetDB()
            UIFrameFadeOut(frame, addon.FADE_OUT_TIME, frame:GetAlpha(), db.fadeAlpha)
        end
    end
end

-- Forces a frame back to fully visible, e.g. right after it's disabled
-- in the config so it doesn't get stuck half-faded.
local function ResetFrame(key)
    local rt = addon.runtime[key]
    if rt and rt.frame and rt.frame:IsShown() then
        UIFrameFadeIn(rt.frame, addon.FADE_IN_TIME, rt.frame:GetAlpha(), 1)
        rt.state = "in"
    end
end

-- When the idle opacity slider changes, snap any currently-faded frames
-- to the new target quickly instead of waiting for the next state change.
local function RefreshFadedFrames()
    local db = GetDB()
    for _, rt in pairs(addon.runtime) do
        if rt.state == "out" and rt.frame and rt.frame:IsShown() then
            UIFrameFadeOut(rt.frame, addon.REFRESH_FADE_TIME, rt.frame:GetAlpha(), db.fadeAlpha)
        end
    end
end

-- ===================== Main loop =====================

local elapsedSince = 0
mainFrame:SetScript("OnUpdate", function(self, elapsed)
    -- post-combat delay countdown, ticks every frame for accurate timing
    if combatExitTimer then
        combatExitTimer = combatExitTimer - elapsed
        if combatExitTimer <= 0 then
            combatExitTimer = nil
            inCombat = false
        end
    end

    elapsedSince = elapsedSince + elapsed
    if elapsedSince < POLL_INTERVAL then return end
    elapsedSince = 0

    for _, entry in ipairs(addon.trackable) do
        local rt = addon.runtime[entry.key]
        if rt and rt.frame and IsEnabled(entry.key) then
            -- Respect the game's own visibility choice: if Blizzard (or the
            -- player's bar settings) has this frame hidden, leave it alone.
            -- Fading it in would force it to Show(), overriding that choice.
            if rt.frame:IsShown() then
                local hovered = IsMouseOverFrame(rt.frame)
                local desiredIn = inCombat or hovered
                ApplyState(rt, desiredIn)
            else
                rt.state = nil -- so it re-initializes cleanly if it reappears
            end
        end
    end
end)

-- ===================== Setup =====================

local function InitRuntime()
    local db = GetDB()
    for _, entry in ipairs(addon.trackable) do
        local frame = _G[entry.frameName]
        if frame then
            addon.runtime[entry.key] = { frame = frame, state = nil }
            if IsEnabled(entry.key) and frame:IsShown() then
                if inCombat then
                    frame:SetAlpha(1)
                    addon.runtime[entry.key].state = "in"
                else
                    frame:SetAlpha(db.fadeAlpha)
                    addon.runtime[entry.key].state = "out"
                end
            end
        end
    end
end

mainFrame:RegisterEvent("PLAYER_LOGIN")
mainFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
mainFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

mainFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        GetDB()
        InitRuntime()
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        combatExitTimer = nil -- cancel any pending fade-out
    elseif event == "PLAYER_REGEN_ENABLED" then
        local db = GetDB()
        if db.exitDelay and db.exitDelay > 0 then
            combatExitTimer = db.exitDelay
        else
            inCombat = false
        end
    end
end)

-- ===================== Public API (used by FadeOut_Config.lua) =====================

addon.GetDB = GetDB
addon.IsEnabled = IsEnabled
addon.SetEnabled = SetEnabled
addon.ResetFrame = ResetFrame
addon.RefreshFadedFrames = RefreshFadedFrames
