local _, ns = ...

local SORT_ICON    = 135464
local OPTIONS_ICON = 134063

------------------------------------------------------------------------
-- Flag labels. Pull from Blizzard's localized class names so the menu
-- auto-localizes; fall back to literal English if a string is missing.
------------------------------------------------------------------------

local function classInfo(classID)
	if GetItemClassInfo then return GetItemClassInfo(classID) end
end

local function ignoreLabel()
	return BAG_FILTER_IGNORE or "Ignore Sorting"
end

local function flagLabel(flag)
	local FLAG = ns.FLAG
	if     flag == FLAG.HEARTHSTONE then return GetItemInfo(6948) or "Hearthstone"
	elseif flag == FLAG.GEAR        then return "Gear"
	elseif flag == FLAG.CONSUMABLE  then return classInfo(0)  or "Consumable"
	elseif flag == FLAG.TRADE_GOODS then return classInfo(7)  or "Trade Goods"
	elseif flag == FLAG.REAGENT     then return classInfo(5)  or "Reagent"
	elseif flag == FLAG.JUNK        then return BAG_FILTER_JUNK or "Junk"
	elseif flag == FLAG.QUEST       then return classInfo(12) or "Quest"
	elseif flag == FLAG.MISC        then return "Misc / Mounts"
	end
	return tostring(flag)
end

------------------------------------------------------------------------
-- Portrait dimming: full grey when ignored, subtle desaturate when the
-- bag has any category flag, otherwise normal.
------------------------------------------------------------------------

local function dimPortrait(frame)
	if not frame then return end
	local portrait = _G[frame:GetName() .. "Portrait"]
	if not portrait then return end
	local bag = frame:GetID()
	if ns.isIgnored(bag) then
		portrait:SetVertexColor(0.45, 0.45, 0.45)
	elseif ns.getBagFlags(bag) ~= 0 then
		portrait:SetVertexColor(0.85, 0.85, 0.85)
	else
		portrait:SetVertexColor(1, 1, 1)
	end
end

------------------------------------------------------------------------
-- Shared right-click dropdown on bag portraits
------------------------------------------------------------------------

local bagMenu, menuFrame, menuBag

local function buildBagMenu(_, level)
	if not menuBag then return end
	level = level or 1

	local info = UIDropDownMenu_CreateInfo()
	info.text = "SortedBags"
	info.isTitle = true
	info.notCheckable = true
	UIDropDownMenu_AddButton(info, level)

	for _, flag in ipairs(ns.FLAG_DEFAULT_ORDER) do
		local f = flag
		info = UIDropDownMenu_CreateInfo()
		info.text = flagLabel(f)
		info.isNotRadio = true
		info.keepShownOnClick = true
		-- Function form so UIDropDownMenu_Refresh re-reads the saved state
		-- after a click instead of using a stale boolean captured at build.
		info.checked = function() return ns.hasBagFlag(menuBag, f) end
		info.func = function(_, _, _, checked)
			ns.setBagFlag(menuBag, f, checked)
			dimPortrait(menuFrame)
		end
		UIDropDownMenu_AddButton(info, level)
	end

	-- Blank separator
	info = UIDropDownMenu_CreateInfo()
	info.text = ""
	info.isTitle = true
	info.notCheckable = true
	info.disabled = true
	UIDropDownMenu_AddButton(info, level)

	info = UIDropDownMenu_CreateInfo()
	info.text = ignoreLabel()
	info.isNotRadio = true
	info.keepShownOnClick = true
	info.checked = function() return ns.isIgnored(menuBag) end
	info.func = function(_, _, _, checked)
		ns.setIgnored(menuBag, checked)
		dimPortrait(menuFrame)
	end
	UIDropDownMenu_AddButton(info, level)

	info = UIDropDownMenu_CreateInfo()
	info.text = "Reset bag categories"
	info.notCheckable = true
	info.func = function()
		ns.resetBag(menuBag)
		dimPortrait(menuFrame)
		CloseDropDownMenus()
	end
	UIDropDownMenu_AddButton(info, level)

	info = UIDropDownMenu_CreateInfo()
	info.text = CLOSE or "Close"
	info.notCheckable = true
	info.func = function() CloseDropDownMenus() end
	UIDropDownMenu_AddButton(info, level)
end

local function ensureBagMenu()
	if bagMenu then return bagMenu end
	bagMenu = CreateFrame("Frame", "SortedBagsBagMenu", UIParent, "UIDropDownMenuTemplate")
	UIDropDownMenu_Initialize(bagMenu, buildBagMenu, "MENU")
	return bagMenu
end

------------------------------------------------------------------------
-- Portrait click overlay
------------------------------------------------------------------------

local function attachPortraitClick(frame)
	if not frame or frame.SortedBagsPortraitHook then return end
	local portrait = _G[frame:GetName() .. "Portrait"]
	if not portrait then return end

	local btn = CreateFrame("Button", nil, frame)
	btn:SetAllPoints(portrait)
	btn:SetFrameLevel(frame:GetFrameLevel() + 5)
	btn:RegisterForClicks("RightButtonUp")

	btn:SetScript("OnClick", function(self)
		ensureBagMenu()
		menuFrame = frame
		menuBag   = frame:GetID()
		ToggleDropDownMenu(1, nil, bagMenu, self, 0, 0)
	end)

	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("SortedBags")
		GameTooltip:AddLine("Right-click to assign categories.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)

	frame.SortedBagsPortraitHook = btn
	dimPortrait(frame)

	-- Close our dropdown when the bag it belongs to is closed, otherwise
	-- the menu lingers floating after the bag window disappears.
	frame:HookScript("OnHide", function(self)
		if menuFrame == self then
			CloseDropDownMenus()
		end
	end)
end

------------------------------------------------------------------------
-- Config panel (just the two right-to-left toggles now)
------------------------------------------------------------------------

local sortButton, configButton, configPanel

local function makeCheckbox(parent, name, label, getCurrent, setCurrent)
	local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	local fs = cb.Text or cb.text or _G[name .. "Text"]
	if fs then
		fs:SetText(label)
		fs:SetFontObject("GameFontHighlight")
	end
	cb:SetChecked(getCurrent() and true or false)
	cb:SetScript("OnClick", function(self)
		setCurrent(self:GetChecked() and true or false)
	end)
	return cb
end

local function buildConfigPanel()
	if configPanel then return configPanel end

	local f = CreateFrame("Frame", "SortedBagsConfigPanel", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(280, 120)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:Hide()

	if f.TitleText then f.TitleText:SetText("SortedBags Options") end

	local sortCheck = makeCheckbox(f, "SortedBagsReverseSortCheck", "Sort right-to-left",
		function() return SortedBagsDB.rightToLeft end,
		function(v) SortedBagsDB.rightToLeft = v end)
	sortCheck:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -34)

	local lootCheck = makeCheckbox(f, "SortedBagsReverseLootCheck", "Loot fills right-to-left",
		function() return not C_Container.GetInsertItemsLeftToRight() end,
		function(v) C_Container.SetInsertItemsLeftToRight(not v) end)
	lootCheck:SetPoint("TOPLEFT", sortCheck, "BOTTOMLEFT", 0, -2)

	-- Re-read live state on every show — the user may have toggled loot
	-- direction via /run or the native UI since the panel was built.
	f:HookScript("OnShow", function()
		sortCheck:SetChecked(SortedBagsDB.rightToLeft and true or false)
		lootCheck:SetChecked(not C_Container.GetInsertItemsLeftToRight())
	end)

	configPanel = f
	return f
end

local function toggleConfigPanel()
	ns.ensureDB()
	local panel = buildConfigPanel()
	if panel:IsShown() then
		panel:Hide()
	else
		panel:Show()
	end
end
ns.toggleConfigPanel = toggleConfigPanel

------------------------------------------------------------------------
-- Backpack buttons (gear + sort)
------------------------------------------------------------------------

local function attachConfigButton()
	if configButton or not ContainerFrame1 then return end

	local btn = CreateFrame("Button", "SortedBagsConfigButton", ContainerFrame1)
	btn:SetSize(20, 20)
	btn:SetPoint("RIGHT", ContainerFrame1CloseButton, "LEFT", 2, 0)
	btn:SetFrameLevel(ContainerFrame1:GetFrameLevel() + 10)

	btn:SetNormalTexture(OPTIONS_ICON)
	btn:SetPushedTexture(OPTIONS_ICON)
	local pushed = btn:GetPushedTexture()
	if pushed then pushed:SetVertexColor(0.7, 0.7, 0.7) end

	local hl = btn:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture(OPTIONS_ICON)
	hl:SetBlendMode("ADD")
	hl:SetAlpha(0.3)
	hl:SetAllPoints(btn)

	btn:SetScript("OnClick", toggleConfigPanel)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("SortedBags Options")
		GameTooltip:AddLine("Also available via /sb.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)

	configButton = btn
end

local function attachSortButton()
	if sortButton or not ContainerFrame1 then return end

	local btn = CreateFrame("Button", "SortedBagsSortButton", ContainerFrame1)
	btn:SetSize(20, 20)
	btn:SetPoint("RIGHT", SortedBagsConfigButton, "LEFT", -4, 0)
	btn:SetFrameLevel(ContainerFrame1:GetFrameLevel() + 10)

	btn:SetNormalTexture(SORT_ICON)
	btn:SetPushedTexture(SORT_ICON)
	local pushed = btn:GetPushedTexture()
	if pushed then pushed:SetVertexColor(0.7, 0.7, 0.7) end

	local hl = btn:CreateTexture(nil, "HIGHLIGHT")
	hl:SetTexture(SORT_ICON)
	hl:SetBlendMode("ADD")
	hl:SetAlpha(0.3)
	hl:SetAllPoints(btn)

	btn:SetScript("OnClick", function() ns.Sort() end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Sort Bags")
		GameTooltip:AddLine("Right-click a bag's portrait to assign categories.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)

	sortButton = btn
end

------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------

local function onContainerShown(frame)
	if not frame then return end
	attachPortraitClick(frame)
end

local function init()
	attachConfigButton()
	attachSortButton()

	if ContainerFrame1Name then
		ContainerFrame1Name:SetText("")
		ContainerFrame1Name:Hide()
	end

	if type(ContainerFrame_OnShow) == "function" then
		hooksecurefunc("ContainerFrame_OnShow", function(self) onContainerShown(self) end)
	end
	if type(ContainerFrame_GenerateFrame) == "function" then
		hooksecurefunc("ContainerFrame_GenerateFrame", function(frame) onContainerShown(frame) end)
	end

	for i = 1, (NUM_CONTAINER_FRAMES or 13) do
		local frame = _G["ContainerFrame" .. i]
		if frame and frame:IsShown() then onContainerShown(frame) end
	end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
	init()
	boot:UnregisterEvent("PLAYER_LOGIN")
end)

------------------------------------------------------------------------
-- /sb slash command
------------------------------------------------------------------------

SLASH_SORTEDBAGSCONFIG1 = "/sb"
SlashCmdList["SORTEDBAGSCONFIG"] = function() toggleConfigPanel() end
