-- ============================================================
-- DavoAura - Lifebloom tracker
-- Aura detection copied exactly from SweepyBoop/RaidFrames/BuffHelper.lua
-- Only visualization is changed (size, position, glow, timer)
-- ============================================================

local AURA_IDS = { [33763] = true, [290754] = true }
local SIZE     = 26
local PANDEMIC = 4.5  -- 15s * 0.3

-- issecretvalue() is a Blizzard global (retail only); mirrors SB's IsSecretValue
local function IsSecretValue(v)
    return issecretvalue(v)
end

-- SB's own IsGroupUnit (includes "player"; WoW built-in may not)
local function IsGroupUnit(unit)
    if not unit then return false end
    return unit == "player"
        or unit == "pet"
        or string.match(unit, "^party%d+$")    ~= nil
        or string.match(unit, "^partypet%d+$") ~= nil
        or string.match(unit, "^raid%d+$")     ~= nil
        or string.match(unit, "^raidpet%d+$")  ~= nil
end

-- SB's IsFrameVisible with secret-value guard
local function IsFrameVisible(frame)
    local shown = frame:IsShown()
    return (not IsSecretValue(shown)) and shown
end

-- ============================================================
-- AuraButton init - called once per button by AuraContainer
-- (SB: InitializeAuraButton; visualization changed for DavoAura)
-- ============================================================

local function InitButton(button)
    button:SetSize(SIZE, SIZE)
    button:SetMouseMotionEnabled(false)

    local iconTex = button:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(button)
    button:SetIcon(iconTex)  -- AuraContainer sets actual icon texture

    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    cd:SetDrawBling(false)
    cd:SetReverse(true)
    cd:SetDrawSwipe(true)
    cd:SetSwipeColor(0, 0, 0, 0.5)
    cd:SetDrawEdge(false)
    -- do NOT set noCooldownCount or SetHideCountdownNumbers:
    -- let CooldownFrameTemplate show its built-in timer text
    button:SetDurationCooldown(cd)
    button.davoCD = cd

    -- Resize the built-in cooldown FontString (via GetRegions, same as SB)
    for i = 1, cd:GetNumRegions() do
        local region = select(i, cd:GetRegions())
        if region and region:GetObjectType() == "FontString" then
            region:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            break
        end
    end

    -- Animated proc glow (ActionButtonSpellAlertTemplate), yellow tinted.
    -- Driven manually from OnUpdate since AddPandemicRegion only supports plain textures.
    local glow = CreateFrame("Frame", nil, button, "ActionButtonSpellAlertTemplate")
    glow:SetSize(SIZE * 1.4, SIZE * 1.4)
    glow:SetPoint("CENTER", button, "CENTER", 0, 0)
    if glow.ProcStartFlipbook then glow.ProcStartFlipbook:SetVertexColor(1, 0.85, 0, 1) end
    if glow.ProcLoopFlipbook  then glow.ProcLoopFlipbook:SetVertexColor(1, 0.85, 0, 1)  end
    if glow.ProcAltGlow       then glow.ProcAltGlow:SetVertexColor(1, 0.85, 0, 1)       end
    glow:SetScript("OnHide", function(self)
        if self.ProcLoop and self.ProcLoop:IsPlaying() then self.ProcLoop:Stop() end
    end)
    glow:Hide()

    -- OnUpdate on glow frame (our own frame, not AuraContainer-managed)
    glow.tick   = 0
    glow.inGlow = false
    glow:SetScript("OnUpdate", function(self, elapsed)
        self.tick = self.tick + elapsed
        if self.tick < 0.1 then return end
        self.tick = 0
        local startMs, durMs = cd:GetCooldownTimes()
        if not durMs or durMs == 0 then return end
        local remaining = (startMs + durMs) / 1000 - GetTime()
        if remaining > 0 and remaining <= PANDEMIC then
            if not self.inGlow then
                self.inGlow = true
                self:Show()
                if self.ProcStartAnim then self.ProcStartAnim:Play() end
            end
        else
            if self.inGlow then
                self.inGlow = false
                self:Hide()
                if self.ProcStartAnim then self.ProcStartAnim:Stop() end
            end
        end
    end)
end

-- ============================================================
-- Frame pool and AuraContainer lifecycle
-- Copied from SB: cufPool, EnsureContainers, ActivateContainer,
-- UpdateFrame, RefreshAllFrames, TrackFrame
-- ============================================================

local cufPool           = {}
local usingRealAuraData = true  -- false only in Edit Mode (AURA_DATA_PROVIDER_SWITCH)

local function ShouldTrackFrameName(name)
    if not name then return false end
    return string.sub(name, 1, 17) == "CompactPartyFrame"
        or string.sub(name, 1, 11) == "CompactRaid"
end

-- SB: EnsureContainers - creates root + AuraContainer, attaches to frame
local function EnsureContainer(frame)
    if frame.davoContainer then return frame.davoContainer end

    -- Intermediate root frame (SB pattern: helper.root)
    local root = CreateFrame("Frame", nil, frame)
    root:SetSize(1, 1)
    root:SetFrameLevel(frame:GetFrameLevel() + 10)
    root:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1, -1)

    local container = CreateFrame("AuraContainer", nil, root, "CustomAuraContainerTemplate")
    container:Hide()  -- OnShow requests full aura refresh (SB pattern)
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
            includeSpellIDs      = AURA_IDS,
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

-- SB: HideHelper
local function HideContainer(frame)
    if frame.davoContainer then
        frame.davoContainer:Hide()
    end
end

-- SB: ActivateContainer
local function ActivateContainer(container, unit, forceRefresh)
    if container:GetUnit() ~= unit then
        container:SetUnit(unit)
    elseif forceRefresh then
        container:UpdateAllAuras()
    end
    container:Show()
end

-- SB: UpdateFrame (guards copied exactly, minus profile/class checks)
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

-- SB: RefreshAllFrames
local function RefreshAllFrames(forceRefresh)
    for frame in pairs(cufPool) do
        UpdateFrame(frame, forceRefresh)
    end
end

-- SB: TrackFrame
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
-- Events (copied from SB: SetupRaidFrameAuraModule + AuraContainerLifecycle)
-- ============================================================

-- AURA_DATA_PROVIDER_SWITCH: false = Edit Mode fake data, NOT arena restriction
local providerFrame = CreateFrame("Frame")
providerFrame:RegisterEvent("AURA_DATA_PROVIDER_SWITCH")
providerFrame:SetScript("OnEvent", function(_, _, isReal)
    usingRealAuraData = isReal and true or false
    RefreshAllFrames()
end)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event)
    C_Timer.After(0, function()
        RefreshAllFrames(true)
    end)
end)
