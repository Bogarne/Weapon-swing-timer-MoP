local addonName, addonTable = ...
local WST = {}
_G[addonName] = WST

-------------------------------------------------------
-- Настройки по умолчанию
-------------------------------------------------------
local defaults = {
    width = 220,
    height = 14,
    spacing = 6,
    texture = "Interface\\TARGETINGFRAME\\UI-StatusBar",
    colorMH = { r = 1, g = 0, b = 0, a = 1 },
    colorOH = { r = 0, g = 0.45, b = 1, a = 1 },
    colorRanged = { r = 1, g = 1, b = 0, a = 1 },
    showOutOfCombat = false,
    position = { "CENTER", "UIParent", "CENTER", 0, -200 },
    locked = true,
    animationOffset = 0.25,
}

local DB
local mh, oh, ranged, holder

-------------------------------------------------------
-- Вспомогательные функции
-------------------------------------------------------
local function ApplyBackdrop(frame)
    frame.bgTex = frame:CreateTexture(nil, "BACKGROUND")
    frame.bgTex:SetAllPoints()
    frame.bgTex:SetColorTexture(0.06, 0.06, 0.06, 0.85)
    frame.borderTex = frame:CreateTexture(nil, "BORDER")
    frame.borderTex:SetPoint("TOPLEFT", -1, 1)
    frame.borderTex:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.borderTex:SetColorTexture(0, 0, 0, 1)
end

local function CreateBar(name, parent, color)
    local f = CreateFrame("Frame", name, parent)
    f:SetSize(DB.width, DB.height)
    ApplyBackdrop(f)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture(DB.texture)
    bar:SetStatusBarColor(color.r, color.g, color.b, color.a)
    local txt = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("CENTER")
    txt:SetText(name)
    f.bar = bar
    f.text = txt

    local tick = bar:CreateTexture(nil, "OVERLAY")
    tick:SetColorTexture(1, 1, 1, 1)
    tick:SetSize(2, DB.height)
    tick:Hide()
    f.tick = tick

    return f
end

-------------------------------------------------------
-- Проверка оружия
-------------------------------------------------------
local function HasMainHandWeapon()
    local _, class = UnitClass("player")
    if class == "HUNTER" then
        local itemID = GetInventoryItemID("player", 16)
        if not itemID then return false end
        
        local itemEquipLoc = select(9, GetItemInfo(itemID))
        if itemEquipLoc then
            return itemEquipLoc ~= "INVTYPE_RANGED" and itemEquipLoc ~= "INVTYPE_RANGEDRIGHT"
        end
    end
    return GetInventoryItemID("player", 16) ~= nil
end

local function HasOffHandWeapon()
    return GetInventoryItemID("player", 17) ~= nil
end

local function IsRangedHunter()
    local _, class = UnitClass("player")
    if class ~= "HUNTER" then return false end
    
    local itemID = GetInventoryItemID("player", 16)
    if not itemID then return false end
    
    local itemEquipLoc = select(9, GetItemInfo(itemID))
    if itemEquipLoc then
        return itemEquipLoc == "INVTYPE_RANGED" or itemEquipLoc == "INVTYPE_RANGEDRIGHT"
    end
    
    return true
end

-------------------------------------------------------
-- Swing data
-------------------------------------------------------
local swingData = {
    MH = { active=false, start=0, dur=0, lastSwingTime=0 },
    OH = { active=false, start=0, dur=0, lastSwingTime=0 },
    Ranged = { active=false, start=0, dur=0, lastSwingTime=0 },
}

-------------------------------------------------------
-- UI
-------------------------------------------------------
holder = CreateFrame("Frame", addonName.."Holder", UIParent)
holder:SetMovable(true)
holder:RegisterForDrag("LeftButton")
holder:SetScript("OnDragStart", function(self) if not DB.locked then self:StartMoving() end end)
holder:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
    local relName = relativeTo and relativeTo:GetName() or "UIParent"
    DB.position = { point, relName, relativePoint, xOfs, yOfs }
end)

local function UpdateBarsVisibility()
    local hasMH, hasOH, hasRanged = HasMainHandWeapon(), HasOffHandWeapon(), IsRangedHunter()
    
    local inCombat = InCombatLockdown()
    local showMH = hasMH and (swingData.MH.active or inCombat)
    local showOH = hasOH and (swingData.OH.active or inCombat)
    local showRanged = hasRanged and (swingData.Ranged.active or inCombat)
    
    if DB.showOutOfCombat then
        showMH = hasMH
        showOH = hasOH
        showRanged = hasRanged
    end
    
    mh:SetShown(showMH)
    oh:SetShown(showOH)
    ranged:SetShown(showRanged)
    
    local visible = {}
    if showMH then table.insert(visible, mh) end
    if showOH then table.insert(visible, oh) end
    if showRanged then table.insert(visible, ranged) end
    
    local prev
    for i, frame in ipairs(visible) do
        frame:ClearAllPoints()
        if i == 1 then
            frame:SetPoint("TOP", holder, "TOP")
        else
            frame:SetPoint("TOP", prev, "BOTTOM", 0, -DB.spacing)
        end
        prev = frame
    end
    
    if #visible > 0 then
        holder:SetSize(DB.width, DB.height * #visible + DB.spacing * math.max(#visible-1,0))
        holder:Show()
    else
        holder:SetSize(DB.width, DB.height)
        holder:Hide()
    end
end

local function InitializeUI()
    mh = CreateBar(addonName.."_MH", holder, DB.colorMH)
    oh = CreateBar(addonName.."_OH", holder, DB.colorOH)
    ranged = CreateBar(addonName.."_Ranged", holder, DB.colorRanged)
    
    if DB.locked then holder:EnableMouse(false) else holder:EnableMouse(true) end
    holder:Hide()
end

-------------------------------------------------------
-- Swing logic
-------------------------------------------------------
local function StartSwing(hand, speed)
    if not speed or speed <= 0 then return end
    
    local d = swingData[hand]
    if not d then return end
    
    d.active = true
    d.start = GetTime()
    d.dur = speed
    d.lastSwingTime = d.start
    
    UpdateBarsVisibility()
end

local function StopSwing(hand)
    local d = swingData[hand]
    if not d then return end
    d.active = false
end

local function UpdateSwing()
    local now = GetTime()
    local needsUpdate = false
    
    for hand, data in pairs(swingData) do
        local frame = (hand=="MH" and mh) or (hand=="OH" and oh) or (hand=="Ranged" and ranged)
        if frame then
            if data.active then
                local elapsed = now - data.start
                local remaining = data.dur - elapsed
                
                if remaining <= 0 then
                    StopSwing(hand)
                    frame.bar:SetValue(0)
                    frame.text:SetText(hand.." ready")
                    frame.tick:Hide()
                    needsUpdate = true
                else
                    frame.bar:SetMinMaxValues(0, data.dur)
                    frame.bar:SetValue(remaining)
                    frame.text:SetFormattedText("%s: %.1f", hand, remaining)

                    if hand == "Ranged" then
                        local offset = math.min(DB.animationOffset, data.dur - 0.05)
                        local tickPos = DB.width * (offset / data.dur)
                        frame.tick:ClearAllPoints()
                        frame.tick:SetPoint("LEFT", frame.bar, "LEFT", tickPos, 0)
                        frame.tick:Show()
                    else
                        frame.tick:Hide()
                    end
                end
            else
                if InCombatLockdown() or DB.showOutOfCombat then
                    frame.bar:SetValue(0)
                    frame.text:SetText(hand.." ready")
                    frame.tick:Hide()
                end
            end
        end
    end
    
    if needsUpdate then
        UpdateBarsVisibility()
    end
end

-------------------------------------------------------
-- Events
-------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("UNIT_ATTACK_SPEED")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")

local initialized = false
f:SetScript("OnEvent", function(self,event,...)
    if event=="PLAYER_ENTERING_WORLD" then
        if initialized then return end
        initialized=true
        if not WST_DB then WST_DB={} end
        for k,v in pairs(defaults) do
            if WST_DB[k]==nil then
                WST_DB[k]=type(v)=="table" and CopyTable(v) or v
            end
        end
        DB=WST_DB

        holder:ClearAllPoints()
        local pos = DB.position
        if type(pos) ~= "table" or #pos < 3 or type(pos[2]) ~= "string" then
            pos = defaults.position
        end
        local relFrame = _G[pos[2]] or UIParent
        holder:SetPoint(pos[1], relFrame, pos[3], pos[4] or 0, pos[5] or -200)

        InitializeUI()
        print("|cff00ff00WST (MoP):|r Initialized")

    elseif event=="PLAYER_EQUIPMENT_CHANGED" then
        UpdateBarsVisibility()

    elseif event=="UNIT_ATTACK_SPEED" then
        local unit=...
        if unit=="player" then
            local mhSpeed, ohSpeed = UnitAttackSpeed("player")
            if swingData.MH.active and mhSpeed then swingData.MH.dur = mhSpeed end
            if swingData.OH.active and ohSpeed then swingData.OH.dur = ohSpeed end
        end

    elseif event=="COMBAT_LOG_EVENT_UNFILTERED" then
        local args = {CombatLogGetCurrentEventInfo()}
        local sourceGUID = args[4]
        if sourceGUID~=UnitGUID("player") then return end
        
        local subEvent = args[2]
        local now = GetTime()

        if subEvent=="SWING_DAMAGE" or subEvent=="SWING_MISSED" then
            local mhSpeed, ohSpeed = UnitAttackSpeed("player")
            
            local timeSinceMH = now - swingData.MH.lastSwingTime
            local timeSinceOH = now - swingData.OH.lastSwingTime
            
            if HasMainHandWeapon() and HasOffHandWeapon() then
                if timeSinceMH >= timeSinceOH then
                    if mhSpeed and mhSpeed > 0 then
                        StartSwing("MH", mhSpeed)
                    end
                else
                    if ohSpeed and ohSpeed > 0 then
                        StartSwing("OH", ohSpeed)
                    end
                end
            else
                if HasMainHandWeapon() and mhSpeed and mhSpeed > 0 then
                    StartSwing("MH", mhSpeed)
                end
                if HasOffHandWeapon() and ohSpeed and ohSpeed > 0 then
                    StartSwing("OH", ohSpeed)
                end
            end
            
        elseif subEvent=="RANGE_DAMAGE" or subEvent=="RANGE_MISSED" then
            local rangedSpeed = UnitRangedDamage("player")
            if IsRangedHunter() and rangedSpeed and rangedSpeed > 0 then
                StartSwing("Ranged", rangedSpeed)
            end
        end

    elseif event=="PLAYER_REGEN_ENABLED" then
        if not DB.showOutOfCombat then 
            holder:Hide()
        end
        
    elseif event=="PLAYER_REGEN_DISABLED" then
        UpdateBarsVisibility()
    end
end)

f:SetScript("OnUpdate", function(self, elapsed)
    UpdateSwing()
end)

-------------------------------------------------------
-- Chat commands
-------------------------------------------------------
SLASH_WST1="/wst"
SlashCmdList["WST"]=function(msg)
    msg=msg:lower()
    if msg=="unlock" then
        DB.locked=false
        holder:EnableMouse(true)
        print("|cff00ff00WST:|r Drag with LMB.")
    elseif msg=="lock" then
        DB.locked=true
        holder:EnableMouse(false)
        print("|cff00ff00WST:|r Locked.")
    else
        print("|cff00ff00WST:|r /wst unlock | /wst lock")
    end
end