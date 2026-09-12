-- ============================================================
-- DavoAura - Lifebloom tracker
-- ============================================================

local AURA_IDS      = { 33763, 290754 }
local AURA_DURATION = 15
local PANDEMIC      = AURA_DURATION * 0.3  -- 4.5s
local SIZE          = 30

-- ============================================================
-- AuraButton initialization (called once per button by AuraContainer)
-- ============================================================

local function InitButton(button)
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
    cd:SetDrawEdge(false)
    cd:SetHideCountdownNumbers(true)
    cd.noCooldownCount = true
    button:SetDurationCooldown(cd)
    button.davoCD = cd

    local timerTxt = button:CreateFontString(nil, "OVERLAY")
    timerTxt:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    timerTxt:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
    button.davoTimerTxt = timerTxt

    -- 2px inward yellow border shown during pandemic window
    local glow = CreateFrame("Frame", nil, button, "BackdropTemplate")
    glow:SetPoint("TOPLEFT",     button, "TOPLEFT",      2, -2)
    glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2,  2)
    glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    glow:SetBackdropBorderColor(1, 0.85, 0, 1)
    glow:SetFrameLevel(button:GetFrameLevel() + 2)
    glow:Hide()
    button.davoGlow = glow

    -- Throttled OnUpdate: refresh timer text and pandemic glow every 0.1s
    button.davoTick = 0
    button:HookScript("OnUpdate", function(self, elapsed)
        self.davoTick = self.davoTick + elapsed
        if self.davoTick < 0.1 then return end
        self.davoTick = 0
        local start, duration = self.davoCD:GetCooldownTimes()
        if not duration or duration == 0 then return end
        local remaining = (start + duration) / 1000 - GetTime()
        if remaining < 0 then remaining = 0 end
        self.davoTimerTxt:SetText(string.format("%.1f", remaining))
        if remaining <= PANDEMIC then
            self.davoGlow:Show()
        else
            self.davoGlow:Hide()
        end
    end)
end

-- ============================================================
-- Frame pool (keyed by compact frame object, mirrors SB cufPool)
-- ============================================================

local cufPool = {}

local function ShouldTrackFrameName(name)
    if not name then return false end
    return string.sub(name, 1, 17) == "CompactPartyFrame"
        or string.sub(name, 1, 11) == "CompactRaid"
end

-- ============================================================
-- AuraContainer per party frame
-- ============================================================

local function EnsureContainer(frame)
    if frame.davoContainer then return frame.davoContainer end

    local container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    container:Hide()
    container:SetFrameLevel(frame:GetFrameLevel() + 5)
    container:SetSize(SIZE, SIZE)
    container:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1, -1)
    container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
    container:SetFlowLayoutAnchorPoint("TOPLEFT")
    container:SetFlowLayoutGrowthDirection(
        AnchorUtil.FlowDirection.Right,
        AnchorUtil.FlowDirection.Down
    )
    container:AddAuraGroup("Lifebloom", "HELPFUL|PLAYER", {
        maxFrameCount = 1,
        candidateFilters = {
            includeSpellIDs = AURA_IDS,
            isFromPlayerOrPlayerPet = true,
        },
        sortMethod    = AuraContainerSortMethod.Expiration,
        sortDirection = AuraContainerSortDirection.Normal,
        initializeFrame = InitButton,
        layout = {
            groupSpacing  = 0,
            elementWidth  = SIZE,
            elementHeight = SIZE,
        },
    })

    frame.davoContainer = container
    return container
end

local function HideContainer(frame)
    if frame.davoContainer then
        frame.davoContainer:Hide()
    end
end

local function UpdateFrame(frame, forceRefresh)
    if not frame or frame:IsForbidden() then return end

    local unit = frame.displayedUnit or frame.unit
    if not unit
        or not UnitExists(unit)
        or (not IsGroupUnit(unit) and not UnitIsUnit(unit, "player")) then
        HideContainer(frame)
        return
    end

    local canAssist = UnitCanAssist("player", unit)
    if not canAssist then
        HideContainer(frame)
        return
    end

    local container = EnsureContainer(frame)
    if container:GetUnit() ~= unit then
        container:SetUnit(unit)
    elseif forceRefresh then
        container:UpdateAllAuras()
    end
    container:Show()
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

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function()
    C_Timer.After(0, function()
        RefreshAllFrames(true)
    end)
end)
