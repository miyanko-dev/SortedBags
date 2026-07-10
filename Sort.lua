local addonName, ns = ...

SortedBags = ns

local BAG_CONTAINERS = {0, 1, 2, 3, 4}
ns.BAG_CONTAINERS = BAG_CONTAINERS

-- Bank base container (-1) plus the six bank bag slots (5..10). Only
-- sorted while the bank window is open — moves are server-rejected
-- otherwise.
local BANK_CONTAINERS = {BANK_CONTAINER or -1}
for i = 1, (NUM_BANKBAGSLOTS or 6) do
	tinsert(BANK_CONTAINERS, (NUM_BAG_SLOTS or 4) + i)
end

------------------------------------------------------------------------
-- Bag category flags. A bag can carry any combination. Bit values are
-- persisted in SortedBagsDB.bagFlags — don't change them. 0x080 is
-- reserved (was MOUNT before mounts were merged into MISC) so future
-- flags don't collide with legacy saves. Slot priority within a bag
-- comes from FLAG_DEFAULT_ORDER below.
------------------------------------------------------------------------

local FLAG = {
	HEARTHSTONE = 0x001,
	GEAR        = 0x002,
	CONSUMABLE  = 0x004,
	TRADE_GOODS = 0x008,
	REAGENT     = 0x010,
	JUNK        = 0x020,
	QUEST       = 0x040,
	MISC        = 0x100,
}
ns.FLAG = FLAG

local FLAG_DEFAULT_ORDER = {
	FLAG.HEARTHSTONE,
	FLAG.MISC,
	FLAG.REAGENT,
	FLAG.CONSUMABLE,
	FLAG.GEAR,
	FLAG.TRADE_GOODS,
	FLAG.QUEST,
	FLAG.JUNK,
}
ns.FLAG_DEFAULT_ORDER = FLAG_DEFAULT_ORDER

local FLAG_ORDER = {}
for i, f in ipairs(FLAG_DEFAULT_ORDER) do FLAG_ORDER[f] = i end
local FLAG_UNKNOWN_RANK = #FLAG_DEFAULT_ORDER + 1

------------------------------------------------------------------------
-- Item → category flag. Categories map to Blizzard's Enum.ItemClass
-- (literal IDs because Enum may not be populated at addon-load time in
-- 1.15.x):
--   0 Consumable   2 Weapon   4 Armor   5 Reagent   6 Projectile
--   7 Tradegoods   9 Recipe   12 Questitem   13 Key   15 Miscellaneous
-- Container/Projectile/Key/Miscellaneous all share the MISC bucket;
-- Classic Era 1.15.x can't reliably distinguish mount items from other
-- Misc items via subClassID. Quality 0 wins first so a gray sword lands
-- in Junk, not Gear — same precedence Retail uses.
------------------------------------------------------------------------

local function itemFilterFlag(itemID, classID, quality)
	if itemID == 6948 then return FLAG.HEARTHSTONE end
	if quality == 0 then return FLAG.JUNK end
	if classID == 12 then return FLAG.QUEST end
	if classID == 2 or classID == 4 then return FLAG.GEAR end
	if classID == 0 then return FLAG.CONSUMABLE end
	-- Recipes live with Trade Goods so a profession bag tagged Trade
	-- Goods picks them up alongside the cloth / herbs / ore.
	if classID == 7 or classID == 9 then return FLAG.TRADE_GOODS end
	if classID == 5 then return FLAG.REAGENT end
	if classID == 1 or classID == 6 or classID == 13 or classID == 15 then
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
	if SortedBagsDB.rightToLeft == nil then SortedBagsDB.rightToLeft = false end
	if SortedBagsDB.sortBank == nil then SortedBagsDB.sortBank = true end
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

-- Bag itemID → specialty index, so specialty detection is one inventory
-- lookup instead of comparing the bag name against every container's
-- GetItemInfo (which silently fails on item-cache misses).
local SPECIALTY_BY_BAG_ITEM = {}
for idx, info in ipairs(SPECIALTY) do
	for _, itemID in ipairs(info.containers) do
		SPECIALTY_BY_BAG_ITEM[itemID] = idx
	end
end

------------------------------------------------------------------------
-- Sort state
------------------------------------------------------------------------

local CONTAINERS
local model, itemStacks, itemSpecialties, itemSortKeys, itemFilterFlags
local touchedSlots
local process
local sortingBank = false
local noticeShown
local resumeSignal, resumeFallback = false, 0
local lastMoveAt = 0
local engine = CreateFrame("Frame", addonName .. "Engine", UIParent)
engine:Hide()

------------------------------------------------------------------------
-- Combat abort. Two paths can stop a running sort:
--   (a) the PLAYER_REGEN_DISABLED event handler — normal path, fires
--       between frames before the next coroutine resume.
--   (b) the InCombatLockdown check inside sortPass — covers the race
--       where the coroutine notices combat mid-sweep before the event
--       reaches us, so we don't wait a full sweep / yield to stop.
-- Both call showCombatAbortNotice, which is idempotent per sort so the
-- raid-warning fires exactly once. Bags are left in their partially-
-- sorted state on purpose — no rollback. Any in-flight cursor item is
-- dropped so the player can fight unobstructed.
------------------------------------------------------------------------

local function showCombatAbortNotice()
	if noticeShown then return end
	noticeShown = true
	if CursorHasItem() then ClearCursor() end
	RaidNotice_AddMessage(RaidWarningFrame, "Bag Sorting Stopped",
		{ r = 1, g = 0.1, b = 0.1 })
end

local function notify(msg)
	UIErrorsFrame:AddMessage(msg, 1.0, 0.1, 0.1)
end

local combatWatcher = CreateFrame("Frame")
combatWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
combatWatcher:SetScript("OnEvent", function()
	if not process then return end
	process = nil
	engine:Hide()
	showCombatAbortNotice()
end)

-- Walking away from the bank mid-sort: every further bank move is
-- server-rejected, so stop immediately instead of letting the stall
-- guard spin for five seconds.
local bankWatcher = CreateFrame("Frame")
bankWatcher:RegisterEvent("BANKFRAME_CLOSED")
bankWatcher:SetScript("OnEvent", function()
	if not process or not sortingBank then return end
	process = nil
	engine:Hide()
	if CursorHasItem() then ClearCursor() end
	notify("Bank closed, sorting stopped")
end)

local function slotKey(container, position)
	return container * 100 + position
end

------------------------------------------------------------------------
-- Safety
------------------------------------------------------------------------

local function isSafeNow()
	-- Merchant / mailbox / bank are safe: sorting only ever calls
	-- PickupContainerItem, and selling / attaching / depositing happens
	-- exclusively through UseContainerItem, which we never call.
	if InCombatLockdown() then return false, "Cannot sort in combat" end
	if CursorHasItem() then return false, "Drop the item on your cursor first" end
	if TradeFrame and TradeFrame:IsShown() then return false, "Cannot sort during trade" end
	if AuctionFrame and AuctionFrame:IsShown() then return false, "Close the auction house first" end
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
	-- Backpack (0) and bank base (-1) aren't inventory items.
	if container <= 0 then return end
	local invSlot = C_Container.ContainerIDToInventoryID(container)
	local bagItemID = invSlot and GetInventoryItemID("player", invSlot)
	if not bagItemID then return end
	return SPECIALTY_BY_BAG_ITEM[bagItemID]
end

local function itemAt(container, slot)
	local link = C_Container.GetContainerItemLink(container, slot)
	if not link then return end

	local itemName, _, quality, _, _, _, _, stack, _, _, _, classID, subClassID = GetItemInfo(link)
	if not itemName then
		-- GetItemInfo cache miss (common just after login / zoning in
		-- Classic Era). Return the link as an opaque key so the planner
		-- pins the slot in place rather than mistaking it for empty and
		-- shuffling another item on top.
		itemStacks[link] = 1
		itemFilterFlags[link] = 0
		return link, true
	end

	-- Item link is the identity. Different enchant / random suffix means a
	-- different link, which the server already treats as unstackable.
	local key = link
	local itemID = tonumber(strmatch(link, "item:(%d+)"))
	local flag = itemFilterFlag(itemID, classID, quality)

	itemStacks[key] = stack or 1
	itemFilterFlags[key] = flag
	-- classID comes before subClassID so weapons (classID 2) sort ahead of
	-- armor (classID 4) inside GEAR, and items inside MISC / JUNK group by
	-- their underlying class (containers, projectiles, keys, …).
	itemSortKeys[key] = {
		FLAG_ORDER[flag] or FLAG_UNKNOWN_RANK,
		classID or 0,
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

	return key, false
end

------------------------------------------------------------------------
-- Planner (four phases: specialty, per-flag, unassigned, spillover)
------------------------------------------------------------------------

local function buildPlan()
	model, itemStacks, itemSpecialties, itemSortKeys, itemFilterFlags = {}, {}, {}, {}, {}
	local counts = {}

	-- Container traversal order. rightToLeft now means "rightmost bag
	-- first" (backpack, bag1, ...); off means "leftmost bag first"
	-- (bag4, bag3, ..., backpack). Slots inside each bag are always
	-- visited top-left → bottom-right so items end up in slot order.
	local containerOrder = {}
	if SortedBagsDB.rightToLeft then
		for i = 1, #CONTAINERS do containerOrder[i] = CONTAINERS[i] end
	else
		for i = #CONTAINERS, 1, -1 do tinsert(containerOrder, CONTAINERS[i]) end
	end

	for _, container in ipairs(containerOrder) do
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
			local key, uncached = itemAt(container, slot)
			if key then
				local info = C_Container.GetContainerItemInfo(container, slot)
				local locked = uncached or (info and info.isLocked)
				entry.item  = key
				entry.count = info and info.stackCount or 1
				if locked then
					-- Pin locked / uncached items in place so the planner
					-- sorts around them. Classic Era can leave items
					-- locked after a failed in-combat equip or a dismissed
					-- BoE bind popup; the lock is server-side and only
					-- clears on relog. The previous build aborted the
					-- entire plan on any locked slot and retried forever,
					-- which made the sort button look dead until relog.
					entry.targetItem  = key
					entry.targetCount = entry.count
				else
					counts[key] = (counts[key] or 0) + entry.count
				end
			end
			tinsert(model, entry)
		end
	end

	local items = {}
	for k in pairs(counts) do tinsert(items, k) end
	sort(items, function(a, b) return LT(itemSortKeys[a], itemSortKeys[b]) end)

	local function assign(slot, key)
		local remaining = counts[key]
		if not remaining or remaining <= 0 then return false end
		local take = math.min(remaining, itemStacks[key])
		slot.targetItem  = key
		slot.targetCount = take
		counts[key] = remaining - take
		return true
	end

	-- Phase 1: specialty bags. Quivers / soul bags / etc. take their
	-- matching items first; ignores the user's bagFlags. Skip slots that
	-- already carry a targetItem (locked / uncached pins set above) so we
	-- don't overwrite the in-place reservation.
	for _, slot in ipairs(model) do
		if slot.specialty and not slot.targetItem then
			for _, key in ipairs(items) do
				if itemSpecialties[key] and itemSpecialties[key][slot.specialty] and assign(slot, key) then
					break
				end
			end
		end
	end

	-- Phase 2: per-bag fill. Walk each tagged bag's flags in the
	-- canonical FLAG_DEFAULT_ORDER, which puts Hearthstone first and
	-- Misc/Mounts second — so those items always claim a bag's earliest
	-- slots whenever the bag carries those tags. Slots inside the bag
	-- fill top-left → bottom-right because they were inserted into the
	-- model in slot 1..N order.
	for _, container in ipairs(containerOrder) do
		local bagFlags = ns.getBagFlags(container)
		if bagFlags ~= 0 then
			for _, flag in ipairs(FLAG_DEFAULT_ORDER) do
				if bit.band(bagFlags, flag) ~= 0 then
					for _, slot in ipairs(model) do
						if slot.container == container
							and not slot.specialty
							and not slot.targetItem
						then
							for _, key in ipairs(items) do
								if itemFilterFlags[key] == flag and assign(slot, key) then break end
							end
						end
					end
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

	-- Empty-but-locked destination: GetContainerItemInfo returns nil for
	-- empty slots, so the isLocked check above can't see a lock that's
	-- still pending from a move that just emptied it. The client rejects
	-- the drop and leaves the source item on the cursor — put it back and
	-- report failure instead of recording a swap that never happened.
	-- (Occupied slots are covered by the dstInfo.isLocked check.)
	if not dstInfo and CursorHasItem() then
		C_Container.PickupContainerItem(src.container, src.position)
		if CursorHasItem() then ClearCursor() end
		return false
	end

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

	lastMoveAt = GetTime()
	return true
end

------------------------------------------------------------------------
-- Sort / Stack passes
------------------------------------------------------------------------

-- Merge partial stacks that aren't sitting in their planned slot. Runs
-- inside every sweep and shares its touchedSlots, so merges execute in
-- parallel with sort moves instead of waiting for the sort to block —
-- merged stacks become clean sources for the next wave.
local function mergeStacks()
	for _, src in ipairs(model) do
		if src.item and src.count < itemStacks[src.item] and src.item ~= src.targetItem
			and not touchedSlots[slotKey(src.container, src.position)]
		then
			for _, dst in ipairs(model) do
				if dst ~= src
					and dst.item == src.item
					and dst.count < itemStacks[dst.item]
					and dst.item ~= dst.targetItem
				then
					if move(src, dst) then break end
				end
			end
		end
	end
end

local function sortPass()
	while true do
		-- Combat check once per sweep: a sweep runs synchronously, so
		-- InCombatLockdown can't flip mid-iteration. The notice is
		-- idempotent so the event handler won't double-alert.
		if InCombatLockdown() then
			showCombatAbortNotice()
			return
		end

		local complete = true
		touchedSlots = {}

		-- Index candidate sources by item once per sweep instead of
		-- rescanning the whole model for every destination. Slots mutated
		-- mid-sweep are always in touchedSlots, so stale entries are
		-- rejected at use time — same outcome as a fresh scan.
		local sourcesByItem = {}
		for _, src in ipairs(model) do
			if src.item and not (src.targetItem and src.item == src.targetItem and src.count <= src.targetCount) then
				local list = sourcesByItem[src.item]
				if not list then
					list = {}
					sourcesByItem[src.item] = list
				end
				tinsert(list, src)
			end
		end

		for _, dst in ipairs(model) do
			if dst.targetItem and (dst.item ~= dst.targetItem or (dst.count or 0) < dst.targetCount) then
				complete = false

				local candidates = sourcesByItem[dst.targetItem]
				if candidates and not touchedSlots[slotKey(dst.container, dst.position)] then
					local sources, rank = {}, {}
					for _, src in ipairs(candidates) do
						local srcOK = src ~= dst
							and not touchedSlots[slotKey(src.container, src.position)]
							and not (dst.item and src.specialty and not (itemSpecialties[dst.item] and itemSpecialties[dst.item][src.specialty]))
						if srcOK then
							-- Count distance first (splits/merges stay minimal
							-- for stackables), then prefer a mutual swap (src
							-- wants exactly what dst holds): one move settles
							-- two slots. For gear every distance is 0, so the
							-- swap preference decides there and cuts the lock
							-- round trips on gear-heavy inventories.
							local mutual = (src.targetItem and src.targetItem == dst.item) and 0 or 1
							rank[src] = math.abs(src.count - dst.targetCount + (dst.item == dst.targetItem and dst.count or 0)) * 2 + mutual
							tinsert(sources, src)
						end
					end
					sort(sources, function(a, b) return rank[a] < rank[b] end)

					for _, src in ipairs(sources) do
						if move(src, dst) then break end
					end
				end
			end
		end

		mergeStacks()

		if complete then return end
		coroutine.yield()
	end
end

------------------------------------------------------------------------
-- Public entry + engine
------------------------------------------------------------------------

function ns.Sort()
	-- Treat a suspended process whose engine isn't actually running as
	-- stale and fall through to a fresh sort. This guards against any
	-- code path that nils the engine without nilling process — without
	-- it, a stuck "in progress" state would silently swallow every click
	-- until /reload.
	if process and coroutine.status(process) == "suspended" and engine:IsShown() then
		return
	end

	ensureDB()

	local ok, reason = isSafeNow()
	if not ok then
		notify(reason)
		return
	end

	local function activeContainers(list)
		local out = {}
		for _, bag in ipairs(list) do
			if not ns.isIgnored(bag) then tinsert(out, bag) end
		end
		return out
	end

	-- Bags and bank sort as separate groups so items never cross the
	-- bag/bank boundary — sorting must not deposit or withdraw.
	local groups = {activeContainers(BAG_CONTAINERS)}
	sortingBank = SortedBagsDB.sortBank and BankFrame and BankFrame:IsShown() or false
	if sortingBank then tinsert(groups, activeContainers(BANK_CONTAINERS)) end

	noticeShown = false
	resumeSignal, resumeFallback = true, 0
	lastMoveAt = GetTime()
	process = coroutine.create(function()
		for _, group in ipairs(groups) do
			if #group > 0 then
				CONTAINERS = group
				buildPlan()
				sortPass()
			end
		end
	end)
	engine:Show()
end

-- After a batch of moves, nothing can progress until the server acks a
-- lock release, so resuming every frame just burns CPU on no-op sweeps.
-- ITEM_UNLOCKED / BAG_UPDATE_DELAYED mark exactly those acks; the 0.25s
-- fallback rescues the sort if an expected event never arrives.
engine:RegisterEvent("ITEM_UNLOCKED")
engine:RegisterEvent("BAG_UPDATE_DELAYED")
-- Bank base slots (container -1) signal through PLAYERBANKSLOTS_CHANGED
-- rather than BAG_UPDATE_DELAYED.
engine:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
engine:SetScript("OnEvent", function() resumeSignal = true end)

engine:SetScript("OnUpdate", function(self, elapsed)
	if not process then self:Hide(); return end

	resumeFallback = resumeFallback + elapsed
	if not resumeSignal and resumeFallback < 0.25 then return end
	resumeSignal, resumeFallback = false, 0

	-- A healthy sort moves something every lock round trip. Five seconds
	-- with zero moves means the plan can't be reached (mid-sort user
	-- interference, permanently locked slot); abort with a message
	-- instead of sweeping forever — the next click replans from live
	-- bag state.
	if GetTime() - lastMoveAt > 5 then
		process = nil
		self:Hide()
		if CursorHasItem() then ClearCursor() end
		notify("Bag sorting stalled, sort again to retry")
		return
	end

	if coroutine.status(process) == "suspended" then
		local ok, err = coroutine.resume(process)
		if not ok then
			geterrorhandler()(err)
			process = nil
			self:Hide()
			return
		end
	end
	-- The combat event handler can nil `process` mid-resume; guard so
	-- the dead-check below doesn't call coroutine.status(nil).
	if not process then self:Hide(); return end
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
