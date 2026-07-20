local _, ns = ...

------------------------------------------------------------------------
-- Flag labels. Hearthstone, Trade Goods, and Junk pull Blizzard's
-- localized strings; the rest are literal English because the game's
-- singular class names read awkwardly as bag categories.
------------------------------------------------------------------------

local function classInfo(classID)
	if GetItemClassInfo then return GetItemClassInfo(classID) end
end

local function flagLabel(flag)
	local FLAG = ns.FLAG
	if     flag == FLAG.HEARTHSTONE then return GetItemInfo(6948) or "Hearthstone"
	elseif flag == FLAG.GEAR        then return "Gear"
	elseif flag == FLAG.CONSUMABLE  then return "Consumables"
	elseif flag == FLAG.TRADE_GOODS then return classInfo(7)  or "Trade Goods"
	elseif flag == FLAG.REAGENT     then return "Reagents"
	elseif flag == FLAG.JUNK        then return BAG_FILTER_JUNK or "Junk"
	elseif flag == FLAG.QUEST       then return "Quest Items"
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
-- Right-click context menu on bag portraits.
--
-- MenuUtil.CreateContextMenu is the same menu system and skin as the
-- unit-portrait right-click menu (MenuStyle2, common-dropdown-c-bg): it
-- opens at the cursor, keeps itself on screen, closes on ESC, click-out,
-- or when the owning portrait hides, and checkbox rows refresh in place
-- so the menu stays open while toggling. Vanilla's variant shows a
-- yellow checkmark when an option is on and nothing when it's off (see
-- Blizzard_Menu/Vanilla/MenuVariants.lua) -- the native on/off cue known
-- from the tracking and unit menus.
------------------------------------------------------------------------

local function showBagMenu(anchor, frame)
	local bag = frame:GetID()

	MenuUtil.CreateContextMenu(anchor, function(_, root)
		root:CreateTitle("Sorted Bags")

		for _, flag in ipairs(ns.FLAG_DEFAULT_ORDER) do
			local f = flag
			root:CreateCheckbox(flagLabel(f),
				function() return ns.hasBagFlag(bag, f) end,
				function()
					ns.toggleBagFlag(bag, f)
					dimPortrait(frame)
				end)
		end

		root:CreateDivider()
		root:CreateCheckbox("Ignore Bag",
			function() return ns.isIgnored(bag) end,
			function()
				ns.toggleIgnored(bag)
				dimPortrait(frame)
			end)

		-- Global options live on the backpack menu only -- they apply to
		-- everything, so duplicating them on every bag would be noise.
		if bag == 0 then
			root:CreateDivider()
			root:CreateTitle("General Options")
			root:CreateCheckbox("Sort Right to Left",
				function() return SortedBagsDB.rightToLeft and true or false end,
				function()
					SortedBagsDB.rightToLeft = not SortedBagsDB.rightToLeft
				end)
			root:CreateCheckbox("Loot Right to Left",
				function() return not C_Container.GetInsertItemsLeftToRight() end,
				function()
					C_Container.SetInsertItemsLeftToRight(not C_Container.GetInsertItemsLeftToRight())
				end)
			root:CreateCheckbox("Also Sort Bank",
				function() return SortedBagsDB.sortBank and true or false end,
				function()
					SortedBagsDB.sortBank = not SortedBagsDB.sortBank
				end)
		end
	end)
end

------------------------------------------------------------------------
-- Portrait click handler. Backpack: left-click sorts, right-click menu.
-- Other bags: right-click menu only.
--
-- We bind directly to Blizzard's $parentPortraitButton instead of layering
-- our own overlay on top: an overlay child with mouse enabled took OnEnter
-- (tooltips worked) but, for reasons that aren't worth chasing, didn't
-- deliver LeftButton OnClick reliably here, while RightButton did.
-- PortraitButton is a regular Button with no OnClick of its own in the
-- 1.15.x XML, so SetScript("OnClick") is a safe addition.
--
-- ContainerFrame1..13 are also a pool in Classic Era 1.15.x:
-- GetOpenFrame() hands the first hidden frame to whichever bag opens
-- next, so the same ContainerFrameN can host the backpack one show and
-- bag #2 the next. That means we can't bake "is this the backpack?" into
-- a closure at attach time — re-read frame:GetID() on every click / hover.
------------------------------------------------------------------------

local function attachPortraitClick(frame)
	if not frame or frame.SortedBagsPortraitHook then return end
	local pb = _G[frame:GetName() .. "PortraitButton"]
	if not pb then return end

	pb:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")

	local function isBackpack() return frame:GetID() == 0 end

	-- Dim overlay for hover/press feedback on the backpack only.
	-- SetVertexColor on the native portrait texture is silently no-op'd in
	-- Classic Era 1.15 (the C_Container.SetBagPortraitTexture pipeline
	-- ignores subsequent Lua color changes), so paint a dim layer on top.
	-- Masked to the same circular alpha Blizzard uses so the dim matches
	-- the portrait socket.
	local dim = pb:CreateTexture(nil, "OVERLAY")
	dim:SetColorTexture(0, 0, 0, 1)
	dim:SetAllPoints(pb)
	dim:SetAlpha(0)
	pcall(function()
		local mask = pb:CreateMaskTexture()
		mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask",
			"CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		mask:SetAllPoints(dim)
		dim:AddMaskTexture(mask)
	end)

	pb:SetScript("OnClick", function(self, button)
		if button == "LeftButton" then
			if isBackpack() then ns.Sort() end
			return
		end
		if button == "MiddleButton" then
			ns.DeleteCheapestJunk()
			return
		end
		showBagMenu(self, frame)
	end)

	pb:SetScript("OnEnter", function(self)
		if isBackpack() then dim:SetAlpha(0.3) end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if isBackpack() then
			GameTooltip:SetText("Sort Bags")
			GameTooltip:AddLine("Left Click: Sort Bags", 1, 1, 1, true)
			GameTooltip:AddLine("Right Click: Bag Categories & Options", 1, 1, 1, true)
			GameTooltip:AddLine("Middle Click: Delete Cheapest Junk Item", 1, 1, 1, true)
		else
			GameTooltip:SetText("Sorted Bags")
			GameTooltip:AddLine("Right Click: Bag Categories", 1, 1, 1, true)
			GameTooltip:AddLine("Middle Click: Delete Cheapest Junk Item", 1, 1, 1, true)
		end
		GameTooltip:Show()
	end)
	pb:SetScript("OnLeave", function()
		dim:SetAlpha(0)
		GameTooltip:Hide()
	end)
	-- OnMouseDown / OnMouseUp give a stronger "pressed" dim distinct from hover.
	-- OnClick fires on release, so this feedback runs in parallel with sort/menu.
	pb:SetScript("OnMouseDown", function()
		if isBackpack() then dim:SetAlpha(0.55) end
	end)
	pb:SetScript("OnMouseUp", function(self)
		if isBackpack() and self:IsMouseOver() then
			dim:SetAlpha(0.3)
		else
			dim:SetAlpha(0)
		end
	end)

	frame.SortedBagsPortraitHook = true
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
