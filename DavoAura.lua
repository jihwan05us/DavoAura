-- ============================================================
-- Config (edit these to tune)
-- ============================================================

local AURA_NAME     = "Lifebloom"
local AURA_DURATION = 15
local PANDEMIC_PCT  = 30
local PANDEMIC      = AURA_DURATION * PANDEMIC_PCT / 100

local SIZE_MISSING  = 48
local SIZE_ACTIVE   = 36
local OFFSET_X      = 10
local OFFSET_Y      = 10

-- ============================================================
-- State
-- ============================================================

local trackedUnit    = nil
local expirationTime = nil
local lastOnUpdate   = 0
local onUpdateActive = false
local inGroup        = false

local STATE_MISSING      = 1
local STATE_NEEDS_REFILL = 2
local STATE_ACTIVE       = 3

local ALL_UNITS = { "player", "party1", "party2", "party3", "party4" }

local iconTex  -- forward declaration, assigned in Frames section
local function RefreshIcon(iconID)
    if iconTex and iconID then
        iconTex:SetTexture(iconID)
    end
end

-- ============================================================
-- Aura
-- ============================================================

local function FindAuraOnUnit(auraName, unit)
    if not UnitExists(unit) then return nil end
    for i = 1, 255 do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not auraData or not auraData.name then return nil end
        if auraData.name == auraName and auraData.sourceUnit == "player" then
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
        local expTime, iconID = FindAuraOnUnit(AURA_NAME, unit)
        if expTime then
            trackedUnit    = unit
            expirationTime = expTime
            RefreshIcon(iconID)
            return
        end
    end
    trackedUnit    = nil
    expirationTime = nil
end

local function CheckUnit(unit)
    local expTime, iconID = FindAuraOnUnit(AURA_NAME, unit)
    if expTime then
        trackedUnit    = unit
        expirationTime = expTime
        RefreshIcon(iconID)
        return
    end
    if unit == trackedUnit then
        trackedUnit    = nil
        expirationTime = nil
    end
end

local function RefreshInGroup()
    inGroup = UnitExists("party1")
end

-- ============================================================
-- Frames
-- ============================================================

local iconFrame = CreateFrame("Frame", "DavoAuraFrame", UIParent)
iconFrame:SetSize(SIZE_MISSING, SIZE_MISSING)
iconFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
iconFrame:Hide()

local glowFrame = CreateFrame("Frame", nil, iconFrame, "BackdropTemplate")
glowFrame:SetPoint("TOPLEFT",     iconFrame, "TOPLEFT",     -3,  3)
glowFrame:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT",  3, -3)
glowFrame:SetBackdrop({
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 3,
})
glowFrame:Hide()

iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
iconTex:SetAllPoints()

local cdFrame = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
cdFrame:SetAllPoints()
cdFrame:SetDrawSwipe(true)
cdFrame:SetHideCountdownNumbers(true)

local timerFont = CreateFont("DavoAuraTimerFont")
timerFont:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")

local timerText = iconFrame:CreateFontString(nil, "OVERLAY")
timerText:SetFontObject(timerFont)
timerText:SetPoint("BOTTOM", iconFrame, "BOTTOM", 0, 2)

-- ============================================================
-- Display
-- ============================================================

local unitFrameMap = {}

local function TrackCompactFrame(frame)
    if not frame or frame:IsForbidden() then return end
    local name = frame:GetName()
    if not name then return end
    if string.sub(name, 1, 17) ~= "CompactPartyFrame"
    and string.sub(name, 1, 11) ~= "CompactRaid" then return end
    local unit = frame.displayedUnit or frame.unit
    if unit then
        unitFrameMap[unit] = frame
    end
end

hooksecurefunc("CompactUnitFrame_SetUnit",       TrackCompactFrame)
hooksecurefunc("CompactUnitFrame_UpdateAll",     TrackCompactFrame)
hooksecurefunc("CompactUnitFrame_UpdateVisible", TrackCompactFrame)

local function ScanExistingFrames()
    if CompactPartyFrame and CompactPartyFrame.memberUnitFrames then
        for _, frame in ipairs(CompactPartyFrame.memberUnitFrames) do
            TrackCompactFrame(frame)
        end
    end
    if CompactRaidFrameContainer and CompactRaidFrameContainer.ApplyToFrames then
        CompactRaidFrameContainer:ApplyToFrames("all", TrackCompactFrame)
    end
end

local function GetUnitFrame(unit)
    local f = unitFrameMap[unit]
    if f and not f:IsForbidden() and f:IsShown() then return f end
    return nil
end

local function SetGlow(color)
    if color == "red" then
        glowFrame:SetBackdropBorderColor(1, 0.1, 0.1, 1)
        glowFrame:Show()
    elseif color == "yellow" then
        glowFrame:SetBackdropBorderColor(1, 0.85, 0, 1)
        glowFrame:Show()
    else
        glowFrame:Hide()
    end
end

local function AnchorToUnit(unit)
    local uf = GetUnitFrame(unit)
    iconFrame:ClearAllPoints()
    if uf then
        iconFrame:SetPoint("TOPRIGHT", uf, "TOPRIGHT", OFFSET_X, OFFSET_Y)
    else
        iconFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function GetState()
    if not trackedUnit then
        return STATE_MISSING
    end
    if expirationTime - GetTime() <= PANDEMIC then
        return STATE_NEEDS_REFILL
    end
    return STATE_ACTIVE
end

local UpdateDisplay

local function EnableOnUpdate(enable)
    if enable == onUpdateActive then return end
    if enable then
        iconFrame:SetScript("OnUpdate", function(self, elapsed)
            lastOnUpdate = lastOnUpdate + elapsed
            if lastOnUpdate < 0.1 then return end
            lastOnUpdate = 0
            UpdateDisplay()
        end)
        onUpdateActive = true
    else
        iconFrame:SetScript("OnUpdate", nil)
        onUpdateActive = false
        lastOnUpdate   = 0
    end
end

UpdateDisplay = function()
    local state = GetState()

    if not inGroup and state ~= STATE_MISSING then
        iconFrame:Hide()
        EnableOnUpdate(false)
        return
    end

    if state == STATE_MISSING then
        iconFrame:SetSize(SIZE_MISSING, SIZE_MISSING)
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        SetGlow("red")
        cdFrame:SetCooldown(0, 0)
        timerText:SetText("")
        iconFrame:Show()
        EnableOnUpdate(false)

    elseif state == STATE_NEEDS_REFILL then
        iconFrame:SetSize(SIZE_ACTIVE, SIZE_ACTIVE)
        AnchorToUnit(trackedUnit)
        SetGlow("yellow")
        local remaining = expirationTime - GetTime()
        cdFrame:SetCooldown(expirationTime - AURA_DURATION, AURA_DURATION)
        timerText:SetText(string.format("%.1f", math.max(0, remaining)))
        iconFrame:Show()
        EnableOnUpdate(true)

    else
        iconFrame:SetSize(SIZE_ACTIVE, SIZE_ACTIVE)
        AnchorToUnit(trackedUnit)
        SetGlow(nil)
        local remaining = expirationTime - GetTime()
        cdFrame:SetCooldown(expirationTime - AURA_DURATION, AURA_DURATION)
        timerText:SetText(string.format("%.1f", math.max(0, remaining)))
        iconFrame:Show()
        EnableOnUpdate(true)
    end
end

-- ============================================================
-- Events
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        ScanExistingFrames()
        RefreshInGroup()
        ScanAllUnits()
        UpdateDisplay()

    elseif event == "GROUP_ROSTER_UPDATE" then
        ScanExistingFrames()
        RefreshInGroup()
        ScanAllUnits()
        UpdateDisplay()

    elseif event == "UNIT_AURA" then
        local unit = ...
        if not IsUnitTracked(unit) then return end
        CheckUnit(unit)
        UpdateDisplay()
    end
end)
