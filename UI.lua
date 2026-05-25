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
-- Right-click popover panel on bag portraits.
--
-- We use a small native panel (BackdropTemplate + thin tooltip border,
-- matching WhereToQuest/ChatScan's section style) populated with native
-- UICheckButtonTemplate rows. MenuUtil context menus would be more compact
-- but on Classic Era they suppress the unchecked checkbox box by design
-- (see Blizzard_Menu/Vanilla/MenuVariants.lua), which loses the visible
-- on/off cue. UICheckButtonTemplate keeps the boxed widget native players
-- expect from the Chat Settings dialog.
------------------------------------------------------------------------

local PANEL_WIDTH = 200
local PANEL_PAD_X = 12
local PANEL_PAD_TOP = 10
local PANEL_PAD_BOTTOM = 10
local TITLE_GAP = 6
local ROW_HEIGHT = 22
local DIVIDER_GAP = 10
local SECTION_LABEL_HEIGHT = 18

local panel

local function newCheckRow(parent)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(22, 22)
	-- Native template anchors LEFT→RIGHT x=-2 calibrated for the 32px default
	-- size where the texture's built-in whitespace yields the standard gap.
	-- At 22px we re-anchor with an explicit 4px offset to match the rest of
	-- the workspace (see WhereToQuest's range checkbox).
	local label = cb.text or _G[(cb:GetName() or "") .. "Text"]
		or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:ClearAllPoints()
	label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	label:SetFontObject("GameFontHighlight")
	cb.label = label
	return cb
end

local function newDivider(parent)
	local tex = parent:CreateTexture(nil, "ARTWORK")
	tex:SetColorTexture(1, 1, 1, 0.08)
	tex:SetHeight(1)
	return tex
end

local function newSectionLabel(parent)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetTextColor(0.85, 0.78, 0.55)
	return fs
end

local function ensurePanel()
	if panel then return panel end

	panel = CreateFrame("Frame", "SortedBagsOptions", UIParent, "BackdropTemplate")
	panel:SetFrameStrata("DIALOG")
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	panel:SetBackdrop({
		bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	panel:SetBackdropColor(0.08, 0.08, 0.08, 0.92)
	panel:SetBackdropBorderColor(0.4, 0.4, 0.4)
	panel:SetWidth(PANEL_WIDTH)
	panel:Hide()

	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.title:SetPoint("TOP", panel, "TOP", 0, -PANEL_PAD_TOP)
	panel.title:SetText("Sorted Bags")

	panel.checkRows = {}
	panel.dividers = {}
	panel.sectionLabels = {}

	-- Full-screen invisible catcher behind the panel. Any click outside the
	-- panel itself hides the popover, mirroring MenuUtil's click-out behavior.
	panel.catcher = CreateFrame("Button", nil, UIParent)
	panel.catcher:SetAllPoints(UIParent)
	panel.catcher:SetFrameStrata("FULLSCREEN_DIALOG")
	panel.catcher:RegisterForClicks("AnyDown")
	panel.catcher:SetScript("OnClick", function() panel:Hide() end)
	panel.catcher:Hide()

	-- Panel sits one strata above the catcher so its own clicks don't reach it.
	panel:SetFrameStrata("FULLSCREEN_DIALOG")
	panel:SetFrameLevel(panel.catcher:GetFrameLevel() + 10)

	-- Escape closes the popover via Blizzard's standard special-frames list.
	tinsert(UISpecialFrames, "SortedBagsOptions")

	panel:SetScript("OnHide", function() panel.catcher:Hide() end)

	return panel
end

local function showBagMenu(anchor, frame)
	local p = ensurePanel()
	local bag = frame:GetID()
	p.parentFrame = frame

	-- Hide all reusable widgets so successive opens with different row counts
	-- don't leave orphan UI behind.
	for _, cb in ipairs(p.checkRows) do cb:Hide() end
	for _, d in ipairs(p.dividers) do d:Hide() end
	for _, s in ipairs(p.sectionLabels) do s:Hide() end

	local checkIdx, divIdx, labelIdx = 0, 0, 0
	local y = -PANEL_PAD_TOP - TITLE_GAP - (p.title:GetStringHeight() or 14)

	local function placeCheckRow(text, isChecked, onClick)
		checkIdx = checkIdx + 1
		local cb = p.checkRows[checkIdx]
		if not cb then
			cb = newCheckRow(p)
			p.checkRows[checkIdx] = cb
		end
		cb:ClearAllPoints()
		cb:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD_X - 4, y)
		cb.label:SetText(text)
		cb:SetChecked(isChecked())
		cb:SetScript("OnClick", function(self)
			onClick(self:GetChecked() and true or false)
		end)
		cb:Show()
		y = y - ROW_HEIGHT
	end

	local function placeDivider()
		divIdx = divIdx + 1
		local d = p.dividers[divIdx]
		if not d then
			d = newDivider(p)
			p.dividers[divIdx] = d
		end
		y = y - DIVIDER_GAP / 2
		d:ClearAllPoints()
		d:SetPoint("LEFT", p, "LEFT", PANEL_PAD_X, y)
		d:SetPoint("RIGHT", p, "RIGHT", -PANEL_PAD_X, y)
		d:Show()
		y = y - DIVIDER_GAP / 2
	end

	local function placeSectionLabel(text)
		labelIdx = labelIdx + 1
		local fs = p.sectionLabels[labelIdx]
		if not fs then
			fs = newSectionLabel(p)
			p.sectionLabels[labelIdx] = fs
		end
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", p, "TOPLEFT", PANEL_PAD_X, y - 2)
		fs:SetText(text)
		fs:Show()
		y = y - SECTION_LABEL_HEIGHT
	end

	for _, flag in ipairs(ns.FLAG_DEFAULT_ORDER) do
		local f = flag
		placeCheckRow(flagLabel(f),
			function() return ns.hasBagFlag(bag, f) end,
			function(checked)
				ns.setBagFlag(bag, f, checked)
				dimPortrait(frame)
			end)
	end

	placeDivider()
	placeCheckRow(ignoreLabel(),
		function() return ns.isIgnored(bag) end,
		function(checked)
			ns.setIgnored(bag, checked)
			dimPortrait(frame)
		end)

	-- Global options live on the backpack menu only — they apply to
	-- everything, so duplicating them on every bag would be noise.
	if bag == 0 then
		placeDivider()
		placeSectionLabel("General Options")
		placeCheckRow("Sort right-to-left",
			function() return SortedBagsDB.rightToLeft and true or false end,
			function(checked)
				SortedBagsDB.rightToLeft = checked
			end)
		placeCheckRow("Loot fills right-to-left",
			function() return not C_Container.GetInsertItemsLeftToRight() end,
			function(checked)
				C_Container.SetInsertItemsLeftToRight(not checked)
			end)
	end

	y = y - PANEL_PAD_BOTTOM
	p:SetHeight(-y)

	p:ClearAllPoints()
	p:SetPoint("TOPLEFT", anchor, "BOTTOMRIGHT", 4, 0)

	p.catcher:Show()
	p:Show()
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

	pb:RegisterForClicks("LeftButtonUp", "RightButtonUp")

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
		showBagMenu(self, frame)
	end)

	pb:SetScript("OnEnter", function(self)
		if isBackpack() then dim:SetAlpha(0.3) end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Sorted Bags")
		if isBackpack() then
			GameTooltip:AddLine("Left-click to sort.", 1, 1, 1, true)
			GameTooltip:AddLine("Right-click for categories and options.", 1, 1, 1, true)
		else
			GameTooltip:AddLine("Right-click to assign categories.", 1, 1, 1, true)
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

	-- Close our popover when the bag it belongs to is closed, otherwise
	-- the panel lingers floating after the bag window disappears.
	frame:HookScript("OnHide", function(self)
		if panel and panel:IsShown() and panel.parentFrame == self then
			panel:Hide()
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
