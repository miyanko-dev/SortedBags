local _, ns = ...

------------------------------------------------------------------------
-- Junk deletion (middle-click on a bag portrait). Finds the lowest
-- value grey or white stack across all player bags and routes it
-- through Blizzard's DELETE_ITEM confirmation — the same popup native
-- deletion uses. Its OnAccept calls DeleteCursorItem() and its
-- OnCancel calls ClearCursor(), which returns the picked-up stack to
-- its original slot, so No / ESC is always safe.
--
-- Stack value = unit price × stack count, because deleting destroys
-- the whole stack. Unit price is Auctionator's scanned auction price
-- when it has one, otherwise vendor price — greys can't be auctioned,
-- so they always price by vendor value.
------------------------------------------------------------------------

local HEARTHSTONE_ID = 6948

local function unitValue(link, sellPrice)
	local api = Auctionator and Auctionator.API and Auctionator.API.v1
	if api and api.GetAuctionPriceByItemLink then
		local price = api.GetAuctionPriceByItemLink("SortedBags", link)
		if price then return price end
	end
	return sellPrice or 0
end

function ns.DeleteCheapestJunk()
	if CursorHasItem() then
		ns.notify("Drop the item on your cursor first")
		return
	end

	-- A running sort owns the cursor and the bag layout; pulling a stack
	-- out from under it would desync its model until the stall guard trips.
	if ns.IsSorting() then
		ns.notify("Wait for bag sorting to finish")
		return
	end

	local best
	for _, bag in ipairs(ns.BAG_CONTAINERS) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local link = info and info.hyperlink

			-- Quest items and the Hearthstone are zero-vendor-value
			-- whites that must never win "cheapest". Uncached items
			-- (GetItemInfo miss) are skipped — they can't be valued.
			if link and not info.isLocked and info.itemID ~= HEARTHSTONE_ID then
				local name, _, quality, _, _, _, _, _, _, _, sellPrice, classID = GetItemInfo(link)
				if name and (quality == 0 or quality == 1) and classID ~= 12 then
					local value = unitValue(link, sellPrice) * (info.stackCount or 1)
					if not best or value < best.value then
						best = { bag = bag, slot = slot, name = name, value = value }
					end
				end
			end
		end
	end

	if not best then
		ns.notify("No grey or white items to delete")
		return
	end

	ClearCursor()
	C_Container.PickupContainerItem(best.bag, best.slot)
	if not CursorHasItem() then return end

	-- If the popup can't show, don't strand the stack on the cursor —
	-- ClearCursor returns it to its slot, same as the dialog's OnCancel.
	if not StaticPopup_Show("DELETE_ITEM", best.name) then
		ClearCursor()
	end
end
