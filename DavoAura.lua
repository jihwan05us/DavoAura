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

-- Pool of tracked compact frames, keyed by frame object (like SB's cufPool)
local framePool = {}

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
-- Icon creation
-- ============================================================

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

-- ============================================================
-- Frame pool (mirrors SB's cufPool pattern)
-- ============================================================

local function ShouldTrackFrameName(name)
    if not name then return false end
    return string.sub(name, 1, 17) == "CompactPartyFrame"
        or string.sub(name, 1, 11) == "CompactRaid"
end

local function TrackFrame(frame)
    if not frame or frame:IsForbidden() then return end
    local name = frame:GetName()
    if ShouldTrackFrameName(name) then
        framePool[frame] = true
        EnsureIcon(frame)
    elseif framePool[frame] then
        framePool[frame] = nil
    end
end

hooksecurefunc("CompactUnitFrame_UpdateAll",     TrackFrame)
hooksecurefunc("CompactUnitFrame_SetUnit",       TrackFrame)
hooksecurefunc("CompactUnitFrame_UpdateVisible", TrackFrame)

-- ============================================================
-- Display
-- ============================================================

local UpdateDisplay

local tickFrame = CreateFrame("Frame")

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
    -- hide all icons first
    for frame in pairs(framePool) do
        if frame.davoAuraIcon then
            frame.davoAuraIcon:Hide()
        end
    end

    if not trackedUnit then
        EnableOnUpdate(false)
        return
    end

    -- find the frame whose current unit matches trackedUnit
    local targetFrame = nil
    for frame in pairs(framePool) do
        local unit = frame.displayedUnit or frame.unit
        if unit == trackedUnit then
            targetFrame = frame
            break
        end
    end

    if not targetFrame or not targetFrame.davoAuraIcon then
        EnableOnUpdate(false)
        return
    end

    local icon = targetFrame.davoAuraIcon
    local remaining = expirationTime - GetTime()

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

local function RefreshAll()
    local iconID = ScanAllUnits()
    if iconID then
        for frame in pairs(framePool) do
            if frame.davoAuraIcon then
                frame.davoAuraIcon.tex:SetTexture(iconID)
            end
        end
    end
    UpdateDisplay()
end

-- ============================================================
-- Events
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")

SLASH_DAVOAURA1 = "/da"
SlashCmdList["DAVOAURA"] = function()
    print("=== DavoAura Debug ===")
    print("trackedUnit:", trackedUnit)
    print("framePool count:", (function() local n=0; for _ in pairs(framePool) do n=n+1 end; return n end)())
    for frame in pairs(framePool) do
        local unit = frame.displayedUnit or frame.unit
        print("  frame:", frame:GetName(), "unit:", unit, "shown:", frame:IsShown())
    end
    for _, unit in ipairs(ALL_UNITS) do
        print("  UnitExists("..unit.."):", UnitExists(unit))
    end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        C_Timer.After(0, RefreshAll)

    elseif event == "UNIT_AURA" then
        local unit = ...
        if not IsUnitTracked(unit) then return end
        local iconID = CheckUnit(unit)
        if iconID then
            for frame in pairs(framePool) do
                if frame.davoAuraIcon then
                    frame.davoAuraIcon.tex:SetTexture(iconID)
                end
            end
        end
        UpdateDisplay()
    end
end)
