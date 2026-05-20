local _, ns = ...

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

	-- Global options only on the backpack menu — they apply to everything,
	-- so duplicating them on every bag would be noise.
	if menuBag == 0 then
		info = UIDropDownMenu_CreateInfo()
		info.text = ""
		info.isTitle = true
		info.notCheckable = true
		info.disabled = true
		UIDropDownMenu_AddButton(info, level)

		info = UIDropDownMenu_CreateInfo()
		info.text = "General Options"
		info.isTitle = true
		info.notCheckable = true
		UIDropDownMenu_AddButton(info, level)

		info = UIDropDownMenu_CreateInfo()
		info.text = "Sort right-to-left"
		info.isNotRadio = true
		info.keepShownOnClick = true
		info.checked = function() return SortedBagsDB.rightToLeft and true or false end
		info.func = function(_, _, _, checked)
			SortedBagsDB.rightToLeft = checked and true or false
		end
		UIDropDownMenu_AddButton(info, level)

		info = UIDropDownMenu_CreateInfo()
		info.text = "Loot fills right-to-left"
		info.isNotRadio = true
		info.keepShownOnClick = true
		info.checked = function() return not C_Container.GetInsertItemsLeftToRight() end
		info.func = function(_, _, _, checked)
			C_Container.SetInsertItemsLeftToRight(not checked)
		end
		UIDropDownMenu_AddButton(info, level)
	end

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
-- Portrait click overlay. Backpack: left-click sorts, right-click menu.
-- Other bags: right-click menu only.
------------------------------------------------------------------------

local function attachPortraitClick(frame)
	if not frame or frame.SortedBagsPortraitHook then return end
	local portrait = _G[frame:GetName() .. "Portrait"]
	if not portrait then return end

	local isBackpack = frame:GetID() == 0

	-- Blizzard's PortraitButton has no OnClick but still consumes mouse input
	-- (and its own OnEnter tooltip overrides ours). Disabling its mouse lets
	-- our overlay button receive every click and lets our tooltip show through.
	local pb = _G[frame:GetName() .. "PortraitButton"]
	if pb and pb.EnableMouse then pb:EnableMouse(false) end

	local btn = CreateFrame("Button", nil, frame)
	btn:SetAllPoints(portrait)
	btn:SetFrameLevel(frame:GetFrameLevel() + 5)
	if isBackpack then
		btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	else
		btn:RegisterForClicks("RightButtonUp")
	end

	btn:SetScript("OnClick", function(self, button)
		if button == "LeftButton" then
			ns.Sort()
			return
		end
		ensureBagMenu()
		menuFrame = frame
		menuBag   = frame:GetID()
		ToggleDropDownMenu(1, nil, bagMenu, self, 0, 0)
	end)

	-- Translucent black overlay for hover/press feedback — only on the backpack,
	-- since that's the one that actually acts as a sort button. Other bags just
	-- get the right-click category menu and shouldn't visually behave like
	-- buttons. SetVertexColor on the native portrait is silently no-op'd in
	-- Classic Era 1.15 (the C-side C_Container.SetBagPortraitTexture pipeline
	-- ignores subsequent Lua color changes), so we paint a thin dim layer on
	-- top instead. Masked to the same circular alpha Blizzard uses so the dim
	-- matches the portrait socket.
	local dim
	if isBackpack then
		dim = btn:CreateTexture(nil, "OVERLAY")
		dim:SetColorTexture(0, 0, 0, 1)
		dim:SetAllPoints(btn)
		dim:SetAlpha(0)
		pcall(function()
			local mask = btn:CreateMaskTexture()
			mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
				"CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
			mask:SetAllPoints(dim)
			dim:AddMaskTexture(mask)
		end)
	end

	btn:SetScript("OnEnter", function(self)
		if dim then dim:SetAlpha(0.3) end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if isBackpack then
			GameTooltip:SetText("SortedBags")
			GameTooltip:AddLine("Left-click to sort.", 1, 1, 1, true)
			GameTooltip:AddLine("Right-click for categories and options.", 1, 1, 1, true)
		else
			GameTooltip:SetText("SortedBags")
			GameTooltip:AddLine("Right-click to assign categories.", 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function(self)
		if dim then dim:SetAlpha(0) end
		GameTooltip:Hide()
	end)
	-- OnMouseDown / OnMouseUp give a stronger "pressed" dim distinct from hover.
	-- OnClick fires on release, so this feedback runs in parallel with sort/menu.
	if isBackpack then
		btn:SetScript("OnMouseDown", function(self)
			dim:SetAlpha(0.55)
		end)
		btn:SetScript("OnMouseUp", function(self)
			dim:SetAlpha(self:IsMouseOver() and 0.3 or 0)
		end)
	end

	frame.SortedBagsPortraitHook = btn

	-- Close our dropdown when the bag it belongs to is closed, otherwise
	-- the menu lingers floating after the bag window disappears.
	frame:HookScript("OnHide", function(self)
		if menuFrame == self then
			CloseDropDownMenus()
		end
	end)
end

------------------------------------------------------------------------
-- Hooks
------------------------------------------------------------------------

local function onContainerShown(frame)
	if not frame then return end
	attachPortraitClick(frame)
end

local function init()
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
