local addonName, ns = ...

SortedBags = ns

local BAG_CONTAINERS = {0, 1, 2, 3, 4}
ns.BAG_CONTAINERS = BAG_CONTAINERS

------------------------------------------------------------------------
-- Bag category flags (ported from Retail's Enum.BagSlotFlags, but bit
-- values are addon-local since Classic Era doesn't expose the native
-- C_Container.SetBagSlotFlag flow). A bag can carry any combination of
-- flags; items routed in Retail's canonical order (Hearthstone first by
-- explicit user preference; then Gear, Consumable, Trade Goods, Reagent,
-- Junk, Quest in the Retail order; Mount + Misc last).
------------------------------------------------------------------------

local FLAG = {
	HEARTHSTONE = 0x001,
	GEAR        = 0x002,
	CONSUMABLE  = 0x004,
	TRADE_GOODS = 0x008,
	REAGENT     = 0x010,
	JUNK        = 0x020,
	QUEST       = 0x040,
	MOUNT       = 0x080,
	MISC        = 0x100,
}
ns.FLAG = FLAG

local FLAG_DEFAULT_ORDER = {
	FLAG.HEARTHSTONE,
	FLAG.GEAR,
	FLAG.CONSUMABLE,
	FLAG.TRADE_GOODS,
	FLAG.REAGENT,
	FLAG.JUNK,
	FLAG.QUEST,
	FLAG.MOUNT,
	FLAG.MISC,
}
ns.FLAG_DEFAULT_ORDER = FLAG_DEFAULT_ORDER

local FLAG_ORDER = {}
for i, f in ipairs(FLAG_DEFAULT_ORDER) do FLAG_ORDER[f] = i end
local FLAG_UNKNOWN_RANK = #FLAG_DEFAULT_ORDER + 1

------------------------------------------------------------------------
-- Item → category flag. Junk check runs first so a gray sword lands in
-- the Junk bag, not the Gear bag — same precedence Retail uses.
------------------------------------------------------------------------

local function itemFilterFlag(itemID, classID, subClassID, quality)
	if itemID == 6948 then return FLAG.HEARTHSTONE end
	if quality == 0 then return FLAG.JUNK end
	if classID == 12 then return FLAG.QUEST end
	if classID == 2 or classID == 4 then return FLAG.GEAR end
	if classID == 0 then return FLAG.CONSUMABLE end
	if classID == 7 then return FLAG.TRADE_GOODS end
	if classID == 5 then return FLAG.REAGENT end
	if classID == 15 and subClassID == 5 then return FLAG.MOUNT end
	if classID == 1 or classID == 6 or classID == 9 or classID == 13 or classID == 15 then
		return FLAG.MISC
	end
	return 0
end

------------------------------------------------------------------------
-- SavedVariables
------------------------------------------------------------------------

local function ensureDB()
	SortedBagsDB = SortedBagsDB or {}
	SortedBagsDB.ignored = SortedBagsDB.ignored or {}
	SortedBagsDB.bagFlags = SortedBagsDB.bagFlags or {}
	if SortedBagsDB.rightToLeft     == nil then SortedBagsDB.rightToLeft     = false end
	if SortedBagsDB.lootRightToLeft == nil then SortedBagsDB.lootRightToLeft = false end
	-- Drop the legacy category-priority order from <0.6 saves.
	SortedBagsDB.categoryOrder = nil
end
ns.ensureDB = ensureDB

function ns.isIgnored(bag)
	return SortedBagsDB and SortedBagsDB.ignored and SortedBagsDB.ignored[bag] == true
end

function ns.setIgnored(bag, value)
	SortedBagsDB.ignored[bag] = value and true or nil
end

function ns.toggleIgnored(bag)
	ns.setIgnored(bag, not ns.isIgnored(bag))
end

function ns.getBagFlags(bag)
	return (SortedBagsDB and SortedBagsDB.bagFlags and SortedBagsDB.bagFlags[bag]) or 0
end

function ns.hasBagFlag(bag, flag)
	return bit.band(ns.getBagFlags(bag), flag) ~= 0
end

function ns.setBagFlag(bag, flag, on)
	local cur = ns.getBagFlags(bag)
	if on then
		cur = bit.bor(cur, flag)
	else
		cur = bit.band(cur, bit.bnot(flag))
	end
	SortedBagsDB.bagFlags[bag] = (cur ~= 0) and cur or nil
end

function ns.toggleBagFlag(bag, flag)
	ns.setBagFlag(bag, flag, not ns.hasBagFlag(bag, flag))
end

function ns.resetBag(bag)
	SortedBagsDB.bagFlags[bag] = nil
	SortedBagsDB.ignored[bag] = nil
end

------------------------------------------------------------------------
-- Specialty-bag item lists (ported from shirsig's SortBags v1.3.9).
-- Quivers only accept arrows, soul bags only accept shards, etc.
-- Hardware constraints from the bag itself — independent of user flags.
------------------------------------------------------------------------

local function arrayToSet(arr)
	local t = {}
	for i = 1, #arr do t[arr[i]] = true end
	return t
end

local SPECIALTY = {
	-- Soul bag
	{ containers = {22243, 22244, 21340, 21341, 21342, 211492},
	  items = arrayToSet({6265}) },
	-- Quiver (arrows)
	{ containers = {2101, 5439, 7278, 11362, 3573, 3605, 7371, 8217, 2662, 19319, 18714, 216514},
	  items = arrayToSet({2512, 2514, 2515, 3029, 3030, 3031, 3464, 9399, 10579, 11285, 12654, 18042, 19316, 24412, 24417, 28053, 28056, 30319, 30611, 31737, 31949, 32760, 33803, 34581}) },
	-- Ammo pouch (bullets / shot)
	{ containers = {2102, 5441, 7279, 11363, 3574, 3604, 7372, 8218, 2663, 19320, 216515},
	  items = arrayToSet({2516, 2519, 3033, 3465, 4960, 5568, 8067, 8068, 8069, 10512, 10513, 11284, 11630, 13377, 15997, 19317, 23772, 23773, 28060, 28061, 30612, 31735, 32761, 32882, 32883, 34582}) },
	-- Enchanting bag
	{ containers = {22246, 22248, 22249},
	  items = arrayToSet({6218, 6222, 6339, 6342, 6343, 6344, 6345, 6346, 6347, 6348, 6349, 6375, 6376, 6377, 10938, 10939, 10940, 10978, 10998, 11038, 11039, 11081, 11082, 11083, 11084, 11098, 11101, 11130, 11134, 11135, 11137, 11138, 11139, 11145, 11150, 11151, 11152, 11163, 11164, 11165, 11166, 11167, 11168, 11174, 11175, 11176, 11177, 11178, 11202, 11203, 11204, 11205, 11206, 11207, 11208, 11223, 11224, 11225, 11226, 11813, 14343, 14344, 16202, 16203, 16204, 16207, 16214, 16215, 16216, 16217, 16218, 16219, 16220, 16221, 16222, 16223, 16224, 16242, 16243, 16244, 16245, 16246, 16247, 16248, 16249, 16250, 16251, 16252, 16253, 16254, 16255, 17725, 18259, 18260, 19444, 19445, 19446, 19447, 19448, 19449, 20725, 20726, 20727, 20728, 20729, 20730, 20731, 20732, 20733, 20734, 20735, 20736, 20752, 20753, 20754, 20755, 20756, 20757, 20758, 22392, 22445, 22446, 22447, 22448, 22449, 22450, 22461, 22462, 22463, 22530, 22531, 22532, 22533, 22534, 22535, 22536, 22537, 22538, 22539, 22540, 22541, 22542, 22543, 22544, 22545, 22546, 22547, 22548, 22551, 22552, 22553, 22554, 22555, 22556, 22557, 22558, 22559, 22560, 22561, 22562, 22563, 22564, 22565, 24000, 24003, 25848, 25849, 28270, 28271, 28272, 28273, 28274, 28276, 28277, 28279, 28280, 28281, 28282, 33148, 33149, 33150, 33151, 33152, 33153, 33165, 33307, 34872, 35297, 35298, 35299, 35498, 35500, 35756, 186683, 7081, 12810, 7068, 7972, 12808, 7067, 7075, 7076, 7077, 7078, 7080, 7082, 12803, 21885, 22451, 22456, 22457, 22572, 22576, 22577, 22578, 23571, 23572, 21886, 22575, 21884, 22452, 22573, 22574}) },
	-- Herb bag
	{ containers = {22250, 22251, 22252},
	  items = arrayToSet({765, 785, 1401, 2263, 2447, 2449, 2450, 2452, 2453, 3355, 3356, 3357, 3358, 3369, 3818, 3819, 3820, 3821, 4625, 5013, 5056, 5168, 8831, 8836, 8838, 8839, 8845, 8846, 11018, 11020, 11022, 11024, 11040, 11514, 11951, 11952, 13463, 13464, 13465, 13466, 13467, 13468, 16205, 16208, 17034, 17035, 17036, 17037, 17038, 17760, 18297, 19727, 22094, 22147, 22710, 22785, 22786, 22787, 22788, 22789, 22790, 22791, 22792, 22793, 22794, 22795, 22797, 23329, 23501, 23788, 24245, 24246, 24401, 31300, 32468, 34465, 8153, 10286, 19726, 21886, 22575}) },
}

------------------------------------------------------------------------
-- Sort state
------------------------------------------------------------------------

local CONTAINERS
local model, itemStacks, itemSpecialties, itemSortKeys, itemFilterFlags
local touchedSlots
local process
local engine = CreateFrame("Frame", addonName .. "Engine", UIParent)
engine:Hide()

local function slotKey(container, position)
	return container * 100 + position
end

------------------------------------------------------------------------
-- Safety
------------------------------------------------------------------------

local function isSafeNow()
	if InCombatLockdown() then return false, "Cannot sort in combat." end
	if CursorHasItem() then return false, "Drop the item on your cursor first." end
	if MerchantFrame and MerchantFrame:IsShown() then return false, "Close the merchant first." end
	if BankFrame and BankFrame:IsShown() then return false, "Close the bank first." end
	if TradeFrame and TradeFrame:IsShown() then return false, "Cannot sort during trade." end
	if MailFrame and MailFrame:IsShown() then return false, "Close the mailbox first." end
	if AuctionFrame and AuctionFrame:IsShown() then return false, "Close the auction house first." end
	return true
end

------------------------------------------------------------------------
-- Lexicographic key compare
------------------------------------------------------------------------

local function LT(a, b)
	local i = 1
	while true do
		if a[i] and b[i] and a[i] ~= b[i] then
			return a[i] < b[i]
		elseif not a[i] and b[i] then
			return true
		elseif not b[i] then
			return false
		end
		i = i + 1
	end
end

------------------------------------------------------------------------
-- Container classification + item identity
------------------------------------------------------------------------

local function containerSpecialty(container)
	if container == 0 then return end
	local name = C_Container.GetBagName(container)
	if not name then return end
	for idx, info in ipairs(SPECIALTY) do
		for _, itemID in ipairs(info.containers) do
			if name == GetItemInfo(itemID) then return idx end
		end
	end
end

local function itemAt(container, slot)
	local link = C_Container.GetContainerItemLink(container, slot)
	if not link then return end

	local itemName, _, quality, _, _, _, _, stack, _, _, _, classID, subClassID = GetItemInfo(link)
	if not itemName then return end

	-- Item link is the identity. Different enchant / random suffix means a
	-- different link, which the server already treats as unstackable.
	local key = link
	local itemID = tonumber(strmatch(link, "item:(%d+)"))
	local flag = itemFilterFlag(itemID, classID, subClassID, quality)

	itemStacks[key] = stack or 1
	itemFilterFlags[key] = flag
	itemSortKeys[key] = {
		FLAG_ORDER[flag] or FLAG_UNKNOWN_RANK,
		subClassID or 0,
		-(quality or 0),
		itemName,
		key,
	}

	if itemID then
		for idx, info in ipairs(SPECIALTY) do
			if info.items[itemID] then
				itemSpecialties[key] = itemSpecialties[key] or {}
				itemSpecialties[key][idx] = true
			end
		end
	end

	return key
end

------------------------------------------------------------------------
-- Planner (four phases: specialty, per-flag, unassigned, spillover)
------------------------------------------------------------------------

local function buildPlan()
	model, itemStacks, itemSpecialties, itemSortKeys, itemFilterFlags = {}, {}, {}, {}, {}
	local counts = {}

	local function insert(t, v)
		if SortedBagsDB.rightToLeft then
			tinsert(t, v)
		else
			tinsert(t, 1, v)
		end
	end

	for _, container in ipairs(CONTAINERS) do
		local specialty = containerSpecialty(container)
		local bagFlags = ns.getBagFlags(container)
		local n = C_Container.GetContainerNumSlots(container) or 0
		for slot = 1, n do
			local entry = {
				container = container,
				position  = slot,
				specialty = specialty,
				bagFlags  = bagFlags,
			}
			local key = itemAt(container, slot)
			if key then
				local info = C_Container.GetContainerItemInfo(container, slot)
				if info and info.isLocked then return false end
				entry.item  = key
				entry.count = info and info.stackCount or 1
				counts[key] = (counts[key] or 0) + entry.count
			end
			insert(model, entry)
		end
	end

	local items = {}
	for k in pairs(counts) do tinsert(items, k) end
	sort(items, function(a, b) return LT(itemSortKeys[a], itemSortKeys[b]) end)

	local function assign(slot, key)
		local remaining = counts[key]
		if not remaining or remaining <= 0 then return false end
		local stack = itemStacks[key]
		local take
		if SortedBagsDB.rightToLeft and (remaining % stack) ~= 0 then
			take = remaining % stack
		else
			take = math.min(remaining, stack)
		end
		slot.targetItem  = key
		slot.targetCount = take
		counts[key] = remaining - take
		return true
	end

	-- Phase 1: specialty bags. Quivers / soul bags / etc. take their
	-- matching items first; ignores the user's bagFlags.
	for _, slot in ipairs(model) do
		if slot.specialty then
			for _, key in ipairs(items) do
				if itemSpecialties[key] and itemSpecialties[key][slot.specialty] and assign(slot, key) then
					break
				end
			end
		end
	end

	-- Phase 2: per-flag fill in Retail's canonical order. Each
	-- category-assigned bag claims its matching items before items can
	-- spill into other bags.
	for _, flag in ipairs(FLAG_DEFAULT_ORDER) do
		for _, slot in ipairs(model) do
			if not slot.specialty and not slot.targetItem
				and bit.band(slot.bagFlags, flag) ~= 0 then
				for _, key in ipairs(items) do
					if itemFilterFlags[key] == flag and assign(slot, key) then break end
				end
			end
		end
	end

	-- Phase 3: unassigned bags absorb whatever's left, in default sort order.
	for _, slot in ipairs(model) do
		if not slot.specialty and not slot.targetItem and slot.bagFlags == 0 then
			for _, key in ipairs(items) do
				if assign(slot, key) then break end
			end
		end
	end

	-- Phase 4: spillover — still-empty category slots take anything left.
	for _, slot in ipairs(model) do
		if not slot.specialty and not slot.targetItem then
			for _, key in ipairs(items) do
				if assign(slot, key) then break end
			end
		end
	end

	return true
end

------------------------------------------------------------------------
-- Move primitive. Cursor is left clean after every call.
-- The coroutine yields once per sortPass sweep, not per move, so this
-- runs many times back-to-back inside one frame.
------------------------------------------------------------------------

local function move(src, dst)
	-- One move per slot per sweep. Without this, two moves in the same frame
	-- can target the same slot before the server's lock state has propagated,
	-- silently dropping the second move and desyncing our model.
	local srcK = slotKey(src.container, src.position)
	local dstK = slotKey(dst.container, dst.position)
	if touchedSlots[srcK] or touchedSlots[dstK] then return false end

	local srcInfo = C_Container.GetContainerItemInfo(src.container, src.position)
	if not srcInfo or srcInfo.isLocked then return false end

	local dstInfo = C_Container.GetContainerItemInfo(dst.container, dst.position)
	if dstInfo and dstInfo.isLocked then return false end

	touchedSlots[srcK] = true
	touchedSlots[dstK] = true

	ClearCursor()
	C_Container.PickupContainerItem(src.container, src.position)
	if not CursorHasItem() then return false end

	C_Container.PickupContainerItem(dst.container, dst.position)

	-- Overflow / different-item swap: put the cursor remainder back.
	if CursorHasItem() then
		C_Container.PickupContainerItem(src.container, src.position)
		if CursorHasItem() then ClearCursor() end
	end

	if src.item == dst.item and dst.item ~= nil then
		local space = itemStacks[dst.item] - dst.count
		local moved = math.min(src.count, space)
		src.count = src.count - moved
		dst.count = dst.count + moved
		if src.count == 0 then src.item = nil end
	else
		src.item,  dst.item  = dst.item,  src.item
		src.count, dst.count = dst.count, src.count
	end

	return true
end

------------------------------------------------------------------------
-- Sort / Stack passes
------------------------------------------------------------------------

local function sortPass()
	local complete, moved
	repeat
		complete, moved = true, false
		touchedSlots = {}
		for _, dst in ipairs(model) do
			if dst.targetItem and (dst.item ~= dst.targetItem or (dst.count or 0) < dst.targetCount) then
				complete = false

				local sources, rank = {}, {}
				for _, src in ipairs(model) do
					local srcOK = src.item == dst.targetItem
						and src ~= dst
						and not (dst.item and src.specialty and not (itemSpecialties[dst.item] and itemSpecialties[dst.item][src.specialty]))
						and not (src.targetItem and src.item == src.targetItem and src.count <= src.targetCount)
					if srcOK then
						rank[src] = math.abs(src.count - dst.targetCount + (dst.item == dst.targetItem and dst.count or 0))
						tinsert(sources, src)
					end
				end
				sort(sources, function(a, b) return rank[a] < rank[b] end)

				for _, src in ipairs(sources) do
					if move(src, dst) then
						moved = true
						break
					end
				end
			end
		end
		coroutine.yield()
	until complete or not moved
	return complete
end

local function stackPass()
	touchedSlots = {}
	for _, src in ipairs(model) do
		if src.item and src.count < itemStacks[src.item] and src.item ~= src.targetItem then
			for _, dst in ipairs(model) do
				if dst ~= src
					and dst.item == src.item
					and dst.count < itemStacks[dst.item]
					and dst.item ~= dst.targetItem
				then
					if move(src, dst) then return end
				end
			end
		end
	end
end

------------------------------------------------------------------------
-- Public entry + engine
------------------------------------------------------------------------

function ns.Sort()
	if process and coroutine.status(process) == "suspended" then return end

	ensureDB()

	local ok, reason = isSafeNow()
	if not ok then
		print("|cffffff00[SortedBags]:|r " .. reason)
		return
	end

	CONTAINERS = {}
	for _, bag in ipairs(BAG_CONTAINERS) do
		if not ns.isIgnored(bag) then tinsert(CONTAINERS, bag) end
	end
	if #CONTAINERS == 0 then return end

	process = coroutine.create(function()
		while not buildPlan() do coroutine.yield() end
		while true do
			if InCombatLockdown() then return end
			if sortPass() then return end
			stackPass()
			coroutine.yield()
		end
	end)
	engine:Show()
end

engine:SetScript("OnUpdate", function(self)
	if not process then self:Hide(); return end
	if coroutine.status(process) == "suspended" then
		local ok, err = coroutine.resume(process)
		if not ok then
			geterrorhandler()(err)
			process = nil
			self:Hide()
		end
	end
	if coroutine.status(process) == "dead" then
		process = nil
		self:Hide()
	end
end)

------------------------------------------------------------------------
-- ADDON_LOADED + slash
------------------------------------------------------------------------

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, _, who)
	if who == addonName then
		ensureDB()
		boot:UnregisterEvent("ADDON_LOADED")
	end
end)

SLASH_SORTEDBAGS1 = "/sortbags"
SLASH_SORTEDBAGS2 = "/sortedbags"
SlashCmdList["SORTEDBAGS"] = function() ns.Sort() end
