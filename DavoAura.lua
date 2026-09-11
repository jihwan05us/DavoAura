-- ============================================================
-- Config
-- ============================================================

local DEFAULTS = {
    auraName     = "Lifebloom",
    auraDuration = 15,
    pandemicPct  = 30,
    missingSize  = 48,
    refillSize   = 24,
    activeSize   = 24,
    offsetX      = 10,
    offsetY      = 10,
}

local cfg = {}

local function LoadConfig()
    DavoAuraDB = DavoAuraDB or {}
    for k, v in pairs(DEFAULTS) do
        cfg[k] = (DavoAuraDB[k] ~= nil) and DavoAuraDB[k] or v
    end
    cfg.auraPandemic = cfg.auraDuration * cfg.pandemicPct / 100
end

local function SaveConfig()
    DavoAuraDB = DavoAuraDB or {}
    for k, v in pairs(cfg) do
        DavoAuraDB[k] = v
    end
end

-- ============================================================
-- State
-- ============================================================

local trackedUnit    = nil
local expirationTime = nil
local groupType      = "SOLO"
local partyUnits     = { "player" }
local lastOnUpdate   = 0
local onUpdateActive = false

local STATE_MISSING      = 1
local STATE_NEEDS_REFILL = 2
local STATE_ACTIVE       = 3

-- ============================================================
-- Group
-- ============================================================

local function GetGroupType()
    if IsInRaid() then
        if GetNumGroupMembers() <= 10 then
            return "RBG_SMALL"
        end
        return "RAID"
    end
    if IsInGroup() then
        return "PARTY"
    end
    return "SOLO"
end

local function BuildPartyUnits(gt)
    local units = { "player" }
    if gt == "PARTY" then
        for i = 1, 4 do
            units[#units + 1] = "party" .. i
        end
    elseif gt == "RBG_SMALL" then
        for i = 1, 9 do
            units[#units + 1] = "raid" .. i
        end
    end
    return units
end

local function RefreshGroupCache()
    groupType  = GetGroupType()
    partyUnits = BuildPartyUnits(groupType)
end

-- ============================================================
-- Aura
-- ============================================================

local function FindAuraOnUnit(auraName, unit)
    if not UnitExists(unit) then return nil end
    local aura = AuraUtil.FindAuraByName(auraName, unit, "HELPFUL|PLAYER")
    if not aura then return nil end
    return aura.expirationTime
end

local function IsUnitTracked(unit)
    for _, u in ipairs(partyUnits) do
        if u == unit then return true end
    end
    return false
end

local function ScanAllUnits()
    for _, unit in ipairs(partyUnits) do
        local expTime = FindAuraOnUnit(cfg.auraName, unit)
        if expTime then
            trackedUnit    = unit
            expirationTime = expTime
            return
        end
    end
    trackedUnit    = nil
    expirationTime = nil
end

local function CheckUnit(unit)
    local expTime = FindAuraOnUnit(cfg.auraName, unit)
    if expTime then
        trackedUnit    = unit
        expirationTime = expTime
        return
    end
    if unit == trackedUnit then
        trackedUnit    = nil
        expirationTime = nil
    end
end

-- ============================================================
-- Frames
-- ============================================================

local iconFrame = CreateFrame("Frame", "DavoAuraFrame", UIParent)
iconFrame:SetSize(DEFAULTS.missingSize, DEFAULTS.missingSize)
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

local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
iconTex:SetAllPoints()
iconTex:SetTexture("Interface\\Icons\\Spell_Nature_Rejuvenation")

local cdFrame = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
cdFrame:SetAllPoints()
cdFrame:SetDrawSwipe(true)
cdFrame:SetHideCountdownNumbers(true)

local timerText = iconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
timerText:SetPoint("BOTTOM", iconFrame, "BOTTOM", 0, 2)

-- ============================================================
-- Display logic
-- ============================================================

local function GetUnitFrame(unit)
    if PartyFrame then
        for i = 1, 5 do
            local f = PartyFrame["MemberFrame" .. i]
            if f and f.unit == unit and f:IsShown() then
                return f
            end
        end
    end
    local ridx = tonumber(unit:match("^raid(%d+)$"))
    if ridx then
        local f = _G["CompactRaidFrame" .. ridx]
        if f and f:IsShown() then return f end
    end
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
        iconFrame:SetPoint("TOPRIGHT", uf, "TOPRIGHT", cfg.offsetX, cfg.offsetY)
    else
        iconFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function GetState()
    if not trackedUnit then
        return STATE_MISSING
    end
    if expirationTime - GetTime() <= cfg.auraPandemic then
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
    if groupType == "RAID" then
        iconFrame:Hide()
        EnableOnUpdate(false)
        return
    end

    local state = GetState()

    if groupType == "SOLO" and state ~= STATE_MISSING then
        iconFrame:Hide()
        EnableOnUpdate(false)
        return
    end

    if state == STATE_MISSING then
        iconFrame:SetSize(cfg.missingSize, cfg.missingSize)
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        SetGlow("red")
        cdFrame:SetCooldown(0, 0)
        timerText:SetText("")
        iconFrame:Show()
        EnableOnUpdate(false)

    elseif state == STATE_NEEDS_REFILL then
        iconFrame:SetSize(cfg.refillSize, cfg.refillSize)
        AnchorToUnit(trackedUnit)
        SetGlow("yellow")
        local remaining = expirationTime - GetTime()
        cdFrame:SetCooldown(expirationTime - cfg.auraDuration, cfg.auraDuration)
        timerText:SetText(string.format("%.1f", math.max(0, remaining)))
        iconFrame:Show()
        EnableOnUpdate(true)

    else
        iconFrame:SetSize(cfg.activeSize, cfg.activeSize)
        AnchorToUnit(trackedUnit)
        SetGlow(nil)
        local remaining = expirationTime - GetTime()
        cdFrame:SetCooldown(expirationTime - cfg.auraDuration, cfg.auraDuration)
        timerText:SetText(string.format("%.1f", math.max(0, remaining)))
        iconFrame:Show()
        EnableOnUpdate(true)
    end
end

-- ============================================================
-- Events
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name ~= "DavoAura" then return end
        LoadConfig()

    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshGroupCache()
        ScanAllUnits()
        UpdateDisplay()

    elseif event == "GROUP_ROSTER_UPDATE" then
        RefreshGroupCache()
        ScanAllUnits()
        UpdateDisplay()

    elseif event == "UNIT_AURA" then
        local unit = ...
        if not IsUnitTracked(unit) then return end
        CheckUnit(unit)
        UpdateDisplay()
    end
end)

-- ============================================================
-- Settings panel
-- ============================================================

local panel = CreateFrame("Frame", "DavoAuraSettings", UIParent, "BackdropTemplate")
panel:SetSize(300, 380)
panel:SetPoint("CENTER")
panel:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop",  panel.StopMovingOrSizing)
panel:Hide()

local panelTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
panelTitle:SetPoint("TOP", panel, "TOP", 0, -16)
panelTitle:SetText("DavoAura Settings")

local function CreateRow(parent, label, y)
    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)
    lbl:SetText(label)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(90, 20)
    eb:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    eb:SetAutoFocus(false)
    return eb
end

local inputs = {}
local y0, dy = -50, -30
inputs.auraName     = CreateRow(panel, "Aura Name",    y0 + dy * 0)
inputs.auraDuration = CreateRow(panel, "Duration (s)", y0 + dy * 1)
inputs.pandemicPct  = CreateRow(panel, "Pandemic %",   y0 + dy * 2)
inputs.missingSize  = CreateRow(panel, "Missing Size", y0 + dy * 3)
inputs.refillSize   = CreateRow(panel, "Refill Size",  y0 + dy * 4)
inputs.activeSize   = CreateRow(panel, "Active Size",  y0 + dy * 5)
inputs.offsetX      = CreateRow(panel, "Offset X",     y0 + dy * 6)
inputs.offsetY      = CreateRow(panel, "Offset Y",     y0 + dy * 7)

local detectBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
detectBtn:SetSize(130, 22)
detectBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y0 + dy * 8 + 5)
detectBtn:SetText("Detect Duration")
detectBtn:SetScript("OnClick", function()
    local name = inputs.auraName:GetText()
    for _, unit in ipairs(partyUnits) do
        local aura = AuraUtil.FindAuraByName(name, unit, "HELPFUL|PLAYER")
        if aura and aura.duration and aura.duration > 0 then
            inputs.auraDuration:SetText(string.format("%.0f", aura.duration))
            print("DavoAura: detected duration " .. aura.duration .. "s on " .. unit)
            return
        end
    end
    print("DavoAura: aura not found - cast it on someone first.")
end)

local saveBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
saveBtn:SetSize(80, 22)
saveBtn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 20, 16)
saveBtn:SetText("Save")
saveBtn:SetScript("OnClick", function()
    cfg.auraName     = inputs.auraName:GetText()
    cfg.auraDuration = tonumber(inputs.auraDuration:GetText()) or cfg.auraDuration
    cfg.pandemicPct  = tonumber(inputs.pandemicPct:GetText())  or cfg.pandemicPct
    cfg.missingSize  = tonumber(inputs.missingSize:GetText())  or cfg.missingSize
    cfg.refillSize   = tonumber(inputs.refillSize:GetText())   or cfg.refillSize
    cfg.activeSize   = tonumber(inputs.activeSize:GetText())   or cfg.activeSize
    cfg.offsetX      = tonumber(inputs.offsetX:GetText())      or cfg.offsetX
    cfg.offsetY      = tonumber(inputs.offsetY:GetText())      or cfg.offsetY
    cfg.auraPandemic = cfg.auraDuration * cfg.pandemicPct / 100
    SaveConfig()
    ScanAllUnits()
    UpdateDisplay()
    panel:Hide()
    print("DavoAura: settings saved.")
end)

local closeBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
closeBtn:SetSize(80, 22)
closeBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -20, 16)
closeBtn:SetText("Close")
closeBtn:SetScript("OnClick", function() panel:Hide() end)

local function OpenSettings()
    inputs.auraName:SetText(cfg.auraName)
    inputs.auraDuration:SetText(tostring(cfg.auraDuration))
    inputs.pandemicPct:SetText(tostring(cfg.pandemicPct))
    inputs.missingSize:SetText(tostring(cfg.missingSize))
    inputs.refillSize:SetText(tostring(cfg.refillSize))
    inputs.activeSize:SetText(tostring(cfg.activeSize))
    inputs.offsetX:SetText(tostring(cfg.offsetX))
    inputs.offsetY:SetText(tostring(cfg.offsetY))
    panel:Show()
end

-- ============================================================
-- Slash command
-- ============================================================

SLASH_DAVOAURA1 = "/da"
SlashCmdList["DAVOAURA"] = function(msg)
    local cmd = msg:lower():match("^%s*(.-)%s*$")
    if cmd == "config" or cmd == "" then
        OpenSettings()
    else
        print("DavoAura: /da config - open settings")
    end
end
