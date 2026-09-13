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
-- FixedPixelGlow - copied verbatim from SB/Common/IconHelpers.lua
-- ============================================================

local function SetFixedPixelGlowDotPosition(dot, path, progress)
    local segmentCount = #path
    local scaled = (progress % 1) * segmentCount
    local index = math.floor(scaled) + 1
    local nextIndex = (index % segmentCount) + 1
    local segmentProgress = scaled - math.floor(scaled)
    local from = path[index]
    local to   = path[nextIndex]
    dot:ClearAllPoints()
    dot:SetPoint("CENTER", dot:GetParent(), "CENTER",
        from.x + (to.x - from.x) * segmentProgress,
        from.y + (to.y - from.y) * segmentProgress)
end

local function SetFixedPixelGlowSize(glow, width, height, padding)
    padding = padding or 2
    local halfWidth  = (width  / 2) + padding
    local halfHeight = (height / 2) + padding
    glow.path = {
        { x = -halfWidth, y =  halfHeight },
        { x =  halfWidth, y =  halfHeight },
        { x =  halfWidth, y = -halfHeight },
        { x = -halfWidth, y = -halfHeight },
    }
    for i = 1, #(glow.dots or {}) do
        SetFixedPixelGlowDotPosition(glow.dots[i], glow.path, glow.progress + glow.dots[i].offset)
    end
end

local function CreateFixedPixelGlow(parent, width, height, color, dotCount, dotSize, frequency, padding)
    width     = width     or 16
    height    = height    or width
    dotCount  = dotCount  or 8
    dotSize   = dotSize   or 2
    frequency = frequency or 0.25
    padding   = padding   or 2

    local glow = CreateFrame("Frame", nil, parent)
    glow:SetSize(1, 1)
    glow:SetPoint("CENTER", parent, "CENTER", 0, 0)
    glow.elapsed   = 0
    glow.progress  = 0
    glow.frequency = frequency
    glow.throttle  = 0.02
    glow.path      = {}
    glow.dots      = {}

    for i = 1, dotCount do
        local dot = glow:CreateTexture(nil, "OVERLAY")
        dot:SetColorTexture(color[1], color[2], color[3], color[4])
        dot:SetSize(dotSize, dotSize)
        dot.offset = (i - 1) / dotCount
        glow.dots[i] = dot
    end
    SetFixedPixelGlowSize(glow, width, height, padding)
    glow:Hide()
    return glow
end

local function ShowFixedPixelGlow(glow)
    if glow:IsShown() then return end
    glow.elapsed  = 0
    glow.progress = 0
    for i = 1, #glow.dots do
        SetFixedPixelGlowDotPosition(glow.dots[i], glow.path, glow.dots[i].offset)
    end
    glow:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < self.throttle then return end
        local step   = self.elapsed
        self.elapsed = 0
        self.progress = (self.progress + step * self.frequency) % 1
        for i = 1, #self.dots do
            SetFixedPixelGlowDotPosition(self.dots[i], self.path, self.progress + self.dots[i].offset)
        end
    end)
    glow:Show()
end

local function HideFixedPixelGlow(glow)
    if not glow then return end
    glow:SetScript("OnUpdate", nil)
    glow:Hide()
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

    local root = CreateFrame("Frame", nil, frame)
    root:SetSize(SIZE, SIZE)
    root:SetFrameLevel(frame:GetFrameLevel() + 10)
    root:SetPoint("TOPLEFT", frame, "TOPRIGHT", 1, -1)
    frame.davoRoot = root

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
        end,
        layout = {
            groupSpacing  = 0,
            elementWidth  = SIZE,
            elementHeight = SIZE,
        },
    })
    frame.davoContainer = container

    -- Timer text on HIGH-strata frame parented to root
    local textFrame = CreateFrame("Frame", nil, root)
    textFrame:SetAllPoints(root)
    textFrame:SetFrameStrata("HIGH")
    textFrame:SetFixedFrameStrata(true)
    local timerTxt = textFrame:CreateFontString(nil, "OVERLAY")
    timerTxt:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    timerTxt:SetPoint("BOTTOM", root, "BOTTOM", 0, 2)

    -- FixedPixelGlow parented to root (SB: CreateFixedPixelGlow pattern)
    local glow = CreateFixedPixelGlow(root, SIZE, SIZE, { 1, 0.85, 0, 1 }, 8, 2, 0.5, 3)
    glow:SetFrameLevel(root:GetFrameLevel() + 9)

    -- OnUpdate on textFrame: reads davoExpiry, updates timer and drives glow
    textFrame.tick   = 0
    textFrame.inGlow = false
    textFrame:SetScript("OnUpdate", function(self, elapsed)
        self.tick = self.tick + elapsed
        if self.tick < 0.1 then return end
        self.tick = 0
        local expiry = root.davoExpiry
        if not expiry then
            timerTxt:SetText("")
            if self.inGlow then
                self.inGlow = false
                HideFixedPixelGlow(glow)
            end
            return
        end
        local remaining = expiry - GetTime()
        if remaining <= 0 then
            timerTxt:SetText("")
            root.davoExpiry = nil
            if self.inGlow then
                self.inGlow = false
                HideFixedPixelGlow(glow)
            end
            return
        end
        timerTxt:SetText(string.format("%.1f", remaining))
        if remaining <= PANDEMIC then
            if not self.inGlow then
                self.inGlow = true
                ShowFixedPixelGlow(glow)
            end
        else
            if self.inGlow then
                self.inGlow = false
                HideFixedPixelGlow(glow)
            end
        end
    end)

    return container
end

local function UpdateRootExpiry(unit)
    for frame in pairs(cufPool) do
        local u = frame.displayedUnit or frame.unit
        if u == unit and frame.davoRoot then
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
    if frame.davoContainer then frame.davoContainer:Hide() end
    if frame.davoRoot then frame.davoRoot.davoExpiry = nil end
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
