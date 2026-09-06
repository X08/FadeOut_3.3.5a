local addon = FadeOut

-- ===================== Layout constants =====================
-- Each section's height is tracked explicitly so the checkbox list always
-- starts right after the sliders, instead of a guessed fixed offset that
-- drifts out of sync (and leaves dead space) whenever the sliders change.

local TOP_PADDING     = 16   -- space above the title
local TITLE_BLOCK     = 34   -- title + subtitle
local SLIDER_GAP      = 26   -- gap from subtitle to first slider
local SLIDER_BLOCK    = 46   -- one slider: label + bar + value text
local SLIDER_SPACING  = 18   -- gap between the two sliders
local LIST_GAP        = 24   -- gap from last slider to the checkbox list
local CHECKBOX_HEIGHT = 22
local BOTTOM_PADDING  = 20

local SLIDER1_Y = -(TOP_PADDING + TITLE_BLOCK + SLIDER_GAP)
local SLIDER2_Y = SLIDER1_Y - SLIDER_BLOCK - SLIDER_SPACING
local LIST_START_Y = SLIDER2_Y - SLIDER_BLOCK - LIST_GAP

local FRAME_WIDTH = 260
local FRAME_HEIGHT = TOP_PADDING + TITLE_BLOCK + SLIDER_GAP
    + SLIDER_BLOCK + SLIDER_SPACING + SLIDER_BLOCK + LIST_GAP
    + (#addon.trackable * CHECKBOX_HEIGHT) + BOTTOM_PADDING

local configFrame

local function CreateConfigFrame()
    if configFrame then return configFrame end

    local db = addon.GetDB()

    local f = CreateFrame("Frame", "FadeOutConfigFrame", UIParent)
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -TOP_PADDING)
    title:SetText("FadeOut")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -6)
    subtitle:SetText("Checked items fade out of combat")

    -- Idle opacity slider (0-100%)
    local alphaSlider = CreateFrame("Slider", "FadeOutAlphaSlider", f, "OptionsSliderTemplate")
    alphaSlider:SetPoint("TOP", 0, SLIDER1_Y)
    alphaSlider:SetWidth(200)
    alphaSlider:SetMinMaxValues(0, 100)
    alphaSlider:SetValueStep(1)
    if alphaSlider.SetObeyStepOnDrag then alphaSlider:SetObeyStepOnDrag(true) end
    _G[alphaSlider:GetName().."Low"]:SetText("0%")
    _G[alphaSlider:GetName().."High"]:SetText("100%")
    _G[alphaSlider:GetName().."Text"]:SetText("Idle Opacity")

    local alphaValueText = alphaSlider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    alphaValueText:SetPoint("TOP", alphaSlider, "BOTTOM", 0, 0)
    local initialAlphaPct = math.floor(db.fadeAlpha * 100 + 0.5)
    alphaValueText:SetText(initialAlphaPct.."%")
    alphaSlider:SetValue(initialAlphaPct)
    alphaSlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5)
        local db2 = addon.GetDB()
        db2.fadeAlpha = value / 100
        alphaValueText:SetText(value.."%")
        addon.RefreshFadedFrames()
    end)

    -- Post-combat delay slider (0 to MAX_EXIT_DELAY seconds)
    local delaySlider = CreateFrame("Slider", "FadeOutDelaySlider", f, "OptionsSliderTemplate")
    delaySlider:SetPoint("TOP", 0, SLIDER2_Y)
    delaySlider:SetWidth(200)
    delaySlider:SetMinMaxValues(0, addon.MAX_EXIT_DELAY)
    delaySlider:SetValueStep(0.5)
    if delaySlider.SetObeyStepOnDrag then delaySlider:SetObeyStepOnDrag(true) end
    _G[delaySlider:GetName().."Low"]:SetText("0s")
    _G[delaySlider:GetName().."High"]:SetText(addon.MAX_EXIT_DELAY.."s")
    _G[delaySlider:GetName().."Text"]:SetText("Post-Combat Delay")

    local delayValueText = delaySlider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    delayValueText:SetPoint("TOP", delaySlider, "BOTTOM", 0, 0)
    delayValueText:SetText(string.format("%.1fs", db.exitDelay))
    delaySlider:SetValue(db.exitDelay)
    delaySlider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / 0.5 + 0.5) * 0.5
        local db2 = addon.GetDB()
        db2.exitDelay = value
        delayValueText:SetText(string.format("%.1fs", value))
    end)

    -- Checkbox list
    local yOffset = LIST_START_Y
    for _, entry in ipairs(addon.trackable) do
        local cb = CreateFrame("CheckButton", "FadeOutCheck"..entry.key, f, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 20, yOffset)
        local text = _G[cb:GetName().."Text"]
        text:SetText(entry.label)
        cb:SetChecked(addon.IsEnabled(entry.key))
        cb:SetScript("OnClick", function(self)
            local checked = self:GetChecked() and true or false
            addon.SetEnabled(entry.key, checked)
            if not checked then
                addon.ResetFrame(entry.key)
            end
        end)
        yOffset = yOffset - CHECKBOX_HEIGHT
    end

    -- New frames default to shown; start hidden so the first /fadeout opens
    -- it instead of instantly closing it.
    f:Hide()

    configFrame = f
    return f
end

SLASH_FADEOUT1 = "/fadeout"
SlashCmdList["FADEOUT"] = function(msg)
    local f = CreateConfigFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end
