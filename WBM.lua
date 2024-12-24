local WBM = {}
local frame = CreateFrame("Frame")

-- State, Config, and Cooldown Management
WBM.state = {inCombat = false, hasLoggedIn = false, enterTime = nil, inRestrictedArea = false}
WBM.config = {
    gracePeriod = 5,
    loginGracePeriod = 5
}
WBM.grace = {}

local function removeOldBuffs(now)
    for key, expiry in pairs(WBM.grace) do
        if expiry < now then
            WBM.grace[key] = nil
        end
    end
end

local function checkArea()
    local inInstance, instanceType = IsInInstance()
    WBM.state.inRestrictedArea =
        inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "pvp")

    if WBM.state.inRestrictedArea then
        frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    else
        frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
end

local function isInGroup(sourceGUID)
    for i = 1, GetNumGroupMembers() do
        local unitID = IsInRaid() and "raid" .. i or "party" .. i
        if UnitGUID(unitID) == sourceGUID then
            return true
        end
    end
    return false
end

function WBM:shouldProcessEvent()
    return self.state.hasLoggedIn == false and self.state.inCombat == false and not self.state.inRestrictedArea
end

function WBM:OnCombatEvent(...)
    local _, subEvent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, _, _, _, spellName = ...
    local now = GetTime()

	local spell = Spell:CreateFromSpellID(spellName)
	
    if subEvent == "SPELL_AURA_APPLIED" or subEvent == "SPELL_AURA_REFRESH" then
	
		removeOldBuffs(now)

		if not sourceName or bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_NPC) > 0 then
			return
		end

		if bit.band(sourceFlags, COMBATLOG_OBJECT_TYPE_PET) > 0 then
			return
		end

		if sourceGUID == UnitGUID("player") then
			return
		end

		if isInGroup(sourceGUID) then
			return
		end

		if destGUID == UnitGUID("player") and not WBM.grace[sourceGUID] then
			WBM.grace[sourceGUID] = now + WBM.config.gracePeriod
			print(sourceName .. " buffed you with " .. spell:GetSpellName())
		end
	else
		return
	end
end

function WBM:OnEvent(event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        self:OnCombatEvent(CombatLogGetCurrentEventInfo())
    elseif event == "PLAYER_REGEN_DISABLED" then
        self.state.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.state.inCombat = false
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        checkArea()
        if event == "PLAYER_ENTERING_WORLD" then
            self.state.hasLoggedIn = true
            C_Timer.After(
                self.config.loginGracePeriod,
                function()
                    self.state.hasLoggedIn = false
                end
            )
        end
    end
end

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:SetScript(
    "OnEvent",
    function(_, event, ...)
        WBM:OnEvent(event, ...)
    end
)

C_Timer.NewTicker(
    600,
    function()
        removeOldBuffs(GetTime())
    end
)

