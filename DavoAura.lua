-- ============================================================
-- DavoAura - Lifebloom tracker
-- Detection framework copied from SweepyBoop/RaidFrames/BuffHelper.lua
-- ============================================================

local AURA_IDS = { [33763] = true, [290754] = true }
local SIZE     = 26
local PANDEMIC = 4.5  -- 15s * 0.3

local function IsSecretValue(v)
    return issecretvalue(v)
end

local function IsGroupUnit(unit)
    if not unit then return false end
    return unit == "player"
        or unit == "pet"
        or string.match(unit, "^party%d+$")    ~= nil
        or string.match(unit, "^partypet%d+$") ~= nil
        or string.match(unit, "^raid%d+$")     ~= nil
        or string.match(unit, "^raidpet%d+$")  ~= nil
end

local function IsFrameVisible(frame)
    local shown = frame:IsShown()
    return (not IsSecretValue(shown)) and shown
end

-- ============================================================
-- Frame pool and AuraContainer lifecycle
-- Copied exactly from SweepyBoop/RaidFrames/BuffHelper.lua
-- ============================================================

local cufPool           = {}
local usingRealAuraData = true

local function ShouldTrackFrameName(name)
    if not name then return false end
    return string.sub(name, 1, 17) == "CompactPartyFrame"
        or string.sub(name, 1, 11) == "CompactRaid"
end

local function EnsureContainer(frame)
    if frame.davoRoot then return frame.davoContainer end

    -- root: our own frame, parent of container + timer text + glow
    local root = CreateFrame("Frame", nil, frame)
    root:SetSize(SIZE, SIZE)
    root:SetFrameLevel(frame:GetFrameLevel() + 10)
    root:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1, -1)
    frame.davoRoot = root

    -- AuraContainer (SB pattern: hide first so OnShow triggers full aura refresh)
    local container = CreateFrame("AuraContainer", nil, root, "CustomAuraContainerTemplate")
    container:Hide()
    container:SetFrameLevel(root:GetFrameLevel())
    container:SetSize(SIZE, SIZE)
    container:SetPoint("TOPLEFT", root, "TOPLEFT")
    container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
    container:SetFlowLayoutAnchorPoint("TOPLEFT")
    container:SetFlowLayoutGrowthDirection(
        AnchorUtil.FlowDirection.Right,
        AnchorUtil.FlowDirection.Down
    )
    container:AddAuraGroup("Lifebloom", "HELPFUL|PLAYER", {
        maxFrameCount = 1,
        candidateFilters = {
            includeSpellIDs         = AURA_IDS,
            isFromPlayerOrPlayerPet = true,
        },
        sortMethod    = AuraContainerSortMethod.Expiration,
        sortDirection = AuraContainerSortDirection.Normal,
        initializeFrame = function(button)
            -- Exactly SB's InitializeAuraButton
            button:SetSize(SIZE, SIZE)
            button:SetMouseMotionEnabled(false)
            local iconTex = button:CreateTexture(nil, "ARTWORK")
            iconTex:SetAllPoints(button)
            button:SetIcon(iconTex)
            local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cd:SetAllPoints(button)
            cd:SetDrawBling(false)
            cd:SetReverse(true)
            cd:SetDrawSwipe(true)
            cd:SetSwipeColor(0, 0, 0, 0.5)
            cd:SetDrawEdge(true)
            cd:SetEdgeTexture("Interface\\Cooldown\\UI-HUD-ActionBar-LoC", 1, 1, 1, 1)
            cd:SetHideCountdownNumbers(true)
            cd.noCooldownCount = true
            button:SetDurationCooldown(cd)

            -- Pandemic glow: texture positioned OUTSIDE button bounds (SB pattern).
            -- Padding ratio copied from SB: SIZE * HIGHLIGHT_PADDING / HIGHLIGHT_BASE_SIZE = SIZE * 7/32
            local p = SIZE * 7 / 32
            local borderFrame = CreateFrame("Frame", nil, button)
            borderFrame:SetAllPoints(button)
            borderFrame:SetFrameStrata("HIGH")
            borderFrame:SetFixedFrameStrata(true)
            local glowTex = borderFrame:CreateTexture(nil, "OVERLAY")
            glowTex:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
            glowTex:SetBlendMode("ADD")
            glowTex:SetVertexColor(1, 0.85, 0, 0.9)
            glowTex:SetPoint("TOPLEFT",     button, "TOPLEFT",     -p,  p)
            glowTex:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT",  p, -p)
            button:AddPandemicRegion(glowTex)
        end,
        layout = {
            groupSpacing  = 0,
            elementWidth  = SIZE,
            elementHeight = SIZE,
        },
    })
    frame.davoContainer = container

    -- Timer text on a HIGH-strata frame parented to root (not the AuraContainer button)
    local textFrame = CreateFrame("Frame", nil, root)
    textFrame:SetAllPoints(root)
    textFrame:SetFrameStrata("HIGH")
    textFrame:SetFixedFrameStrata(true)
    local timerTxt = textFrame:CreateFontString(nil, "OVERLAY")
    timerTxt:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    timerTxt:SetPoint("BOTTOM", root, "BOTTOM", 0, 2)

    -- OnUpdate on textFrame (our own frame): reads expiry tracked via UNIT_AURA
    textFrame.tick = 0
    textFrame:SetScript("OnUpdate", function(self, elapsed)
        self.tick = self.tick + elapsed
        if self.tick < 0.1 then return end
        self.tick = 0
        local expiry = root.davoExpiry
        if not expiry then
            timerTxt:SetText("")
            return
        end
        local remaining = expiry - GetTime()
        if remaining <= 0 then
            timerTxt:SetText("")
            root.davoExpiry = nil
        else
            timerTxt:SetText(string.format("%.1f", remaining))
        end
    end)

    root.davoTimerTxt = timerTxt
    return container
end

-- Called from UNIT_AURA: update expiry time on the root for this unit
local function UpdateRootExpiry(unit)
    for frame in pairs(cufPool) do
        local u = frame.displayedUnit or frame.unit
        if u == unit and frame.davoRoot then
            -- Try to read aura expiration time (works outside arena)
            local auraData
            for _, spellID in ipairs({ 33763, 290754 }) do
                auraData = C_UnitAuras.GetUnitAuraBySpellID(unit, spellID, "HELPFUL|PLAYER")
                if auraData then break end
            end
            if auraData and auraData.expirationTime and auraData.expirationTime > 0 then
                frame.davoRoot.davoExpiry = auraData.expirationTime
            else
                frame.davoRoot.davoExpiry = nil
            end
        end
    end
end

local function HideContainer(frame)
    if frame.davoContainer then
        frame.davoContainer:Hide()
    end
    if frame.davoRoot then
        frame.davoRoot.davoExpiry = nil
    end
end

local function ActivateContainer(container, unit, forceRefresh)
    if container:GetUnit() ~= unit then
        container:SetUnit(unit)
    elseif forceRefresh then
        container:UpdateAllAuras()
    end
    container:Show()
end

local function UpdateFrame(frame, forceRefresh)
    if not frame or frame:IsForbidden() then return end

    local unit = frame.displayedUnit or frame.unit
    if not usingRealAuraData
        or not IsFrameVisible(frame)
        or not unit
        or not UnitExists(unit)
        or not IsGroupUnit(unit) then
        HideContainer(frame)
        return
    end

    local canAssist = UnitCanAssist("player", unit)
    if IsSecretValue(canAssist) or not canAssist then
        HideContainer(frame)
        return
    end

    local container = EnsureContainer(frame)
    ActivateContainer(container, unit, forceRefresh)
end

local function RefreshAllFrames(forceRefresh)
    for frame in pairs(cufPool) do
        UpdateFrame(frame, forceRefresh)
    end
end

local function TrackFrame(frame)
    if not frame or frame:IsForbidden() then return end
    local name = frame:GetName()
    if ShouldTrackFrameName(name) then
        cufPool[frame] = true
        UpdateFrame(frame)
    elseif cufPool[frame] then
        cufPool[frame] = nil
        HideContainer(frame)
    end
end

hooksecurefunc("CompactUnitFrame_UpdateAll",     TrackFrame)
hooksecurefunc("CompactUnitFrame_SetUnit",       TrackFrame)
hooksecurefunc("CompactUnitFrame_UpdateVisible", TrackFrame)

-- ============================================================
-- Events
-- ============================================================

local providerFrame = CreateFrame("Frame")
providerFrame:RegisterEvent("AURA_DATA_PROVIDER_SWITCH")
providerFrame:SetScript("OnEvent", function(_, _, isReal)
    usingRealAuraData = isReal and true or false
    RefreshAllFrames()
end)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" then
        UpdateRootExpiry(unit)
    else
        C_Timer.After(0, function()
            RefreshAllFrames(true)
        end)
    end
end)
