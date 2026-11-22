BitesCookBook = CreateFrame("Frame")
BitesCookBook.Options = {
	ShowCraftableFirstRank = true, -- In the reagent tooltip, show the first rank of the craftable item.
	ShowCraftableRankRange = true, -- In the reagent tooltip, also show the subsequent rank range of the craftable item.
	ShowCraftableFaction = true, -- Show the faction the recipe belongs to.
	ShowCraftableIcon = true, -- In the reagent tooltip, show the icon of the craftable item.
	ShowCraftableBuff = true, -- In the reagent tooltip, show the buff granted by the craftable item.
	GrayHighCraftables = false, -- In the reagent tooltip, gray out the craftable if it is too high rank.
	ColorCraftableByRank = true, -- In the reagent tooltip, color the craftable item by rank.
	MinRankCategory = 1, -- The minimum rank category to show in the reagent tooltip.
	MaxRankCategory = 5, -- The maximum rank category to show in the reagent tooltip.
	HasModifier = 0, -- 0 = no modifier, true = has modifier, false = has inverse modifier
	ModifierKey = "SHIFT", -- SHIFT, ALT, CTRL
}

BitesCookBook.ItemCache = {}
BitesCookBook.Tooltip = getglobal("BitesCookBookTooltip") or CreateFrame("GameTooltip", "BitesCookBookTooltip", nil, "GameTooltipTemplate")
BitesCookBook.Tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

function BitesCookBook:Print(string)
	DEFAULT_CHAT_FRAME:AddMessage("[BitesCookBook]: " .. tostring(string))
end

function BitesCookBook:ADDON_LOADED(eventName, addonName)
	eventName = eventName or event
	addonName = addonName or arg1
	if addonName ~= "BitesCookBook" then return end

	self.Recipes = BitesCookBook_RecipesClassic
	self.CraftablesForReagent = self:GetAllIngredients(self.Recipes)
	self.L = (BitesCookBook.Locales[GetLocale()] or BitesCookBook.Locales["enUS"])

	self:HookTooltips()
	self:RegisterEvent("VARIABLES_LOADED")
	self:RegisterEvent("CHAT_MSG_SKILL")
	self:RegisterEvent("SKILL_LINES_CHANGED")
	self:UnregisterEvent(eventName)
end

function BitesCookBook:VARIABLES_LOADED(eventName)
	eventName = eventName or event

	if not BitesCookBook_Cache then
		BitesCookBook_Cache = {
			Items = {},
			Buffs = {},
		}
	end
	if not BitesCookBook_Cache.Items then
		BitesCookBook_Cache.Items = {}
	end
	if not BitesCookBook_Cache.Buffs then
		BitesCookBook_Cache.Buffs = {}
	end

	self.ItemCache = BitesCookBook_Cache.Items

	for itemID, recipe in pairs(BitesCookBook_RecipesClassic) do
		local cachedBuff = BitesCookBook_Cache.Buffs[itemID]
		if cachedBuff then
			recipe.Buff = cachedBuff.Buff
			if cachedBuff.BuffIcon then
				recipe.BuffIcon = cachedBuff.BuffIcon
			end
		end
	end

	self:StartCacheItems()
	self:UnregisterEvent(eventName)
end

function BitesCookBook:SKILL_LINES_CHANGED(eventName)
	eventName = eventName or event

	if GetNumSkillLines() == 0 then
		return
	end

	self:UnregisterEvent(eventName)
	self.CookingSkillRank = self:GetSkillLevel("Cooking")
end

function BitesCookBook:CHAT_MSG_SKILL(eventName)
	self.CookingSkillRank = self:GetSkillLevel("Cooking")
end

function BitesCookBook.OnEvent()
	BitesCookBook[event](BitesCookBook, event, arg1)
end

BitesCookBook:RegisterEvent("ADDON_LOADED")
BitesCookBook:SetScript("OnEvent", BitesCookBook.OnEvent)

--------------------------------------------------------------------------------
-- Helper functions
--------------------------------------------------------------------------------

local wellFedIcon = "Interface\\Icons\\Spell_Misc_Food"

function BitesCookBook:SetBuff(recipe)
	local MAX_LINES = self.Tooltip:NumLines()
	for i = 1, MAX_LINES do
		local lineText = getglobal(self.Tooltip:GetName().."TextLeft"..i):GetText()
		if lineText then
			local _, _, wellFed = string.find(lineText, "well fed and gain (.-%.)")
			if wellFed then
				recipe.Buff = wellFed
				recipe.BuffIcon = recipe.BuffIcon or wellFedIcon
				return
			end

			local _, _, dragonBreathChili = string.find(lineText, "(Occasionally belch flame at enemies struck in melee for the next 10 min%.)")
			if dragonBreathChili then
				recipe.Buff = dragonBreathChili
				return
			end

			local _, _, fishStat, fishAmount, fishText = string.find(lineText, "[Aa]lso increases? your (.*) by (%d+) (for %d+ min%.)")
			if fishStat and fishAmount and fishText then
				local fishBuff = format("%s %s %s", fishAmount, fishStat, fishText)
				recipe.Buff = fishBuff
				return
			end

			local _, _, fishRegen = string.find(lineText, "[Aa]lso restores (.-%.)")
			if fishRegen then
				recipe.Buff = fishRegen
				return
			end
		end
	end
end

local CACHE_DELAY = 5

function BitesCookBook:BuildCacheQueue()
	local queue = {}
	local cachedCount = 0
	local total = 0

	for itemID, recipe in pairs(BitesCookBook_RecipesClassic) do
		total = total + 1
		local cachedBuff = BitesCookBook_Cache and BitesCookBook_Cache.Buffs and BitesCookBook_Cache.Buffs[itemID]

		if cachedBuff and cachedBuff.ItemName and self.ItemCache and self.ItemCache[cachedBuff.ItemName] then
			cachedCount = cachedCount + 1
		else
			local itemName, itemLink, itemQuality = GetItemInfo(itemID)
			if itemName and itemLink and itemQuality then
				self:StoreCachedRecipe(itemID, recipe, itemName, itemLink, itemQuality)
				cachedCount = cachedCount + 1
			else
				table.insert(queue, { itemID = itemID, recipe = recipe })
			end
		end
	end

	return queue, cachedCount, total
end

function BitesCookBook:StoreCachedRecipe(itemID, recipe, itemName, itemLink, itemQuality)
	local _, _, _, hex = GetItemQualityColor(tonumber(itemQuality))
	local hyperLink = hex .. "|H" .. itemLink .. "|h[" .. itemName .. "]|h" .. FONT_COLOR_CODE_CLOSE

	self.ItemCache[itemName] = hyperLink
	self.Tooltip:ClearLines()
	self.Tooltip:SetHyperlink("item:" .. itemID .. ":0:0:0")
	self:SetBuff(recipe)

	if BitesCookBook_Cache and BitesCookBook_Cache.Buffs then
		BitesCookBook_Cache.Buffs[itemID] = {
			ItemName = itemName,
			Buff = recipe.Buff,
			BuffIcon = recipe.BuffIcon,
		}
	end
end

function BitesCookBook:StartCacheItems()
	local queue, cachedCount, total = self:BuildCacheQueue()

	if table.getn(queue) == 0 then
		self:Print(format("Cached %d / %d recipes", cachedCount, total))
		return
	end

	self:Print(format("Caching %d / %d recipes...", cachedCount, total))

	local elapsed = 0
	local index = 1
	local retryWait = 0

	self:SetScript("OnUpdate", function()
		local dt = arg1 or 0

		if retryWait > 0 then
			retryWait = retryWait - dt
			return
		end

		elapsed = elapsed + dt
		if elapsed < CACHE_DELAY then
			return
		end
		elapsed = 0

		local entry = queue[index]
		if not entry then
			self:Print(format("Cached %d / %d recipes", cachedCount, total))
			self:SetScript("OnUpdate", nil)
			return
		end

		self.Tooltip:ClearLines()
		self.Tooltip:SetHyperlink("item:" .. entry.itemID .. ":0:0:0")

		local itemName, itemLink, itemQuality = GetItemInfo(entry.itemID)
		if itemName and itemLink and itemQuality then
			self:StoreCachedRecipe(entry.itemID, entry.recipe, itemName, itemLink, itemQuality)
			cachedCount = cachedCount + 1
			table.remove(queue, index)

			self:Print(format("Cached %d / %d recipes", cachedCount, total))

			if table.getn(queue) == 0 then
				self:SetScript("OnUpdate", nil)
			end
		else
			index = index + 1
		end

		if index > table.getn(queue) then
			if table.getn(queue) == 0 then
				self:SetScript("OnUpdate", nil)
			else
				index = 1
				retryWait = 10
				self:Print("Some recipes were not cached. Trying again in 10 seconds.")
			end
		end
	end)
end

local LAST_ITEM_IN_CLASSIC = 24283
function BitesCookBook:GetItemLinkByName(name)
	if self.ItemCache[name] then
		return self.ItemCache[name]
	end

	for itemID = 1, LAST_ITEM_IN_CLASSIC do
		local itemName, itemLink, itemQuality = GetItemInfo(itemID)
		if itemName == name and itemLink and itemQuality then
			local _, _, _, hex = GetItemQualityColor(tonumber(itemQuality))
			local hyperLink = hex.. "|H".. itemLink .."|h["..itemName.."]|h" .. FONT_COLOR_CODE_CLOSE
			self.ItemCache[name] = hyperLink
			return hyperLink
		end
	end
end

local skippedIngredients = {
	[2678] = true, -- Mild Spices
	[2692] = true, -- Hot Spices
	[3713] = true, -- Soothing Spices
	[1179] = true, -- Ice Cold Milk
	[4536] = true, -- Shiny Red Apple
	[159]  = true, -- Refreshing Spring Water
}

function BitesCookBook:GetAllIngredients(RecipeList)
	local Reagents = {}

	for recipeItemID, recipe in pairs(RecipeList) do
		for ingredientID, _ in pairs(recipe["Materials"]) do
			if not skippedIngredients[ingredientID] then
				if Reagents[ingredientID] == nil then
					Reagents[ingredientID] = {}
				end

				table.insert(Reagents[ingredientID], recipeItemID)
			end
		end
	end

	for ingredient, recipe_list in pairs(Reagents) do
		table.sort(recipe_list, function(a, b)
			return RecipeList[a]["Range"][1] > RecipeList[b]["Range"][1]
		end)
	end

	return Reagents
end

function BitesCookBook:GetSkillLevel(skillName)
	ExpandSkillHeader(0)

	for skillIndex = 1, GetNumSkillLines() do
		local skillLineName, _, _, skillRank = GetSkillLineInfo(skillIndex)

		if skillLineName == skillName then
			return skillRank
		end
	end

	return 0
end

function BitesCookBook:ConfigureSavedVariables()
	if BitesCookBook_SavedVariables == nil then
		BitesCookBook_SavedVariables = self.Options
	else
		for key, option_value in pairs(self.Options) do
			if BitesCookBook_SavedVariables[key] == nil then
				BitesCookBook_SavedVariables[key] = option_value
			end
		end

		for key, option_value in pairs(BitesCookBook_SavedVariables) do
			if self.Options[key] == nil then
				BitesCookBook_SavedVariables[key] = nil
			end
		end

		self.Options = BitesCookBook_SavedVariables
	end

	return
end