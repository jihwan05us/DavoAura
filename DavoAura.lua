-- ============================================================
-- Config (edit these to tune)
-- ============================================================

local AURA_IDS      = { [33763] = true, [290754] = true }
local AURA_DURATION = 15
local PANDEMIC      = AURA_DURATION * 0.3
local SIZE_ACTIVE   = 30

-- ============================================================
-- State
-- ============================================================

local trackedUnit    = nil
local expirationTime = nil
local lastOnUpdate   = 0
local onUpdateActive = false

local ALL_UNITS = { "player", "party1", "party2", "party3", "party4" }

-- ============================================================
-- Aura
-- ============================================================

local function FindAuraOnUnit(unit)
    if not UnitExists(unit) then return nil end
    for i = 1, 255 do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not auraData or not auraData.name then return nil end
        if AURA_IDS[auraData.spellId] then
            return auraData.expirationTime, auraData.icon
        end
    end
    return nil
end

local function IsUnitTracked(unit)
    for _, u in ipairs(ALL_UNITS) do
        if u == unit then return true end
    end
    return false
end

local function ScanAllUnits()
    for _, unit in ipairs(ALL_UNITS) do
        local expTime, iconID = FindAuraOnUnit(unit)
        if expTime then
            trackedUnit    = unit
            expirationTime = expTime
            return iconID
        end
    end
    trackedUnit    = nil
    expirationTime = nil
    return nil
end

local function CheckUnit(unit)
    local expTime, iconID = FindAuraOnUnit(unit)
    if expTime then
        trackedUnit    = unit
        expirationTime = expTime
        return iconID
    end
    if unit == trackedUnit then
        trackedUnit    = nil
        expirationTime = nil
    end
    return nil
end

-- ============================================================
-- Fonts
-- ============================================================

local timerFont = CreateFont("DavoAuraTimerFont")
timerFont:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")

-- ============================================================
-- Per-frame icon (attached directly to compact party frame)
-- ============================================================

local unitFrameMap = {}

-- Invisible ticker frame for OnUpdate
local tickFrame = CreateFrame("Frame")

local function EnsureIcon(frame)
    if frame.davoAuraIcon then return frame.davoAuraIcon end

    local icon = CreateFrame("Frame", nil, frame)
    icon:SetSize(SIZE_ACTIVE, SIZE_ACTIVE)
    icon:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1, -1)
    icon:Hide()

    local glow = CreateFrame("Frame", nil, icon, "BackdropTemplate")
    glow:SetPoint("TOPLEFT",     icon, "TOPLEFT",      2, -2)
    glow:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2,  2)
    glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    glow:Hide()
    icon.glow = glow

    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    icon.tex = tex

    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawSwipe(true)
    cd:SetHideCountdownNumbers(true)
    icon.cd = cd

    local text = icon:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(timerFont)
    text:SetPoint("BOTTOM", icon, "BOTTOM", 0, 2)
    icon.text = text

    frame.davoAuraIcon = icon
    return icon
end

local function RegisterFrame(frame)
    if not frame or frame:IsForbidden() then return end
    local unit = frame.displayedUnit or frame.unit
    if not unit then return end
    unitFrameMap[unit] = frame
    EnsureIcon(frame)
end

local function TrackCompactFrame(frame)
    if not frame or frame:IsForbidden() then return end
    local name = frame:GetName()
    if not name then return end
    if string.sub(name, 1, 17) ~= "CompactPartyFrame"
    and string.sub(name, 1, 11) ~= "CompactRaid" then return end
    RegisterFrame(frame)
end

hooksecurefunc("CompactUnitFrame_SetUnit",       TrackCompactFrame)
hooksecurefunc("CompactUnitFrame_UpdateAll",     TrackCompactFrame)
hooksecurefunc("CompactUnitFrame_UpdateVisible", TrackCompactFrame)

local function ScanExistingFrames()
    if CompactPartyFrame and CompactPartyFrame.memberUnitFrames then
        for _, frame in ipairs(CompactPartyFrame.memberUnitFrames) do
            RegisterFrame(frame)
        end
    end
    if CompactRaidFrameContainer and CompactRaidFrameContainer.ApplyToFrames then
        CompactRaidFrameContainer:ApplyToFrames("all", RegisterFrame)
    end
end

-- ============================================================
-- Display
-- ============================================================

local function HideAllIcons()
    for _, frame in pairs(unitFrameMap) do
        if frame.davoAuraIcon then
            frame.davoAuraIcon:Hide()
        end
    end
end

local function RefreshIconTexture(iconID)
    if not iconID then return end
    for _, frame in pairs(unitFrameMap) do
        if frame.davoAuraIcon then
            frame.davoAuraIcon.tex:SetTexture(iconID)
        end
    end
end

local UpdateDisplay

local function EnableOnUpdate(enable)
    if enable == onUpdateActive then return end
    if enable then
        tickFrame:SetScript("OnUpdate", function(self, elapsed)
            lastOnUpdate = lastOnUpdate + elapsed
            if lastOnUpdate < 0.1 then return end
            lastOnUpdate = 0
            UpdateDisplay()
        end)
        onUpdateActive = true
    else
        tickFrame:SetScript("OnUpdate", nil)
        onUpdateActive = false
        lastOnUpdate   = 0
    end
end

UpdateDisplay = function()
    HideAllIcons()

    if not trackedUnit then
        EnableOnUpdate(false)
        return
    end

    local frame = unitFrameMap[trackedUnit]
    if not frame or not frame.davoAuraIcon then
        EnableOnUpdate(false)
        return
    end

    local remaining = expirationTime - GetTime()
    local icon = frame.davoAuraIcon

    icon.cd:SetCooldown(expirationTime - AURA_DURATION, AURA_DURATION)
    icon.text:SetText(string.format("%.1f", math.max(0, remaining)))

    if remaining <= PANDEMIC then
        icon.glow:SetBackdropBorderColor(1, 0.85, 0, 1)
        icon.glow:Show()
    else
        icon.glow:Hide()
    end

    icon:Show()
    EnableOnUpdate(true)
end

-- ============================================================
-- Events
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")

local function FullRefresh()
    ScanExistingFrames()
    local iconID = ScanAllUnits()
    RefreshIconTexture(iconID)
    UpdateDisplay()
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        C_Timer.After(0, FullRefresh)

    elseif event == "UNIT_AURA" then
        local unit = ...
        if not IsUnitTracked(unit) then return end
        local iconID = CheckUnit(unit)
        if iconID then RefreshIconTexture(iconID) end
        UpdateDisplay()
    end
end)
