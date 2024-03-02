-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryAdapter = ZO_InitializingObject:Subclass()
internal.class.GuildHistoryAdapter = GuildHistoryAdapter

function GuildHistoryAdapter:Initialize(history, cache)
    self.history = history
    self.cache = cache
    self.selectedCategoryCache = cache:GetCategoryCache(history.guildId, history.selectedEventCategory)

    local function RefreshSelectedCategoryCache()
        local selectedCategoryCache = cache:GetCategoryCache(history.guildId, history.selectedEventCategory)
        if selectedCategoryCache ~= self.selectedCategoryCache then
            self.selectedCategoryCache = selectedCategoryCache
            internal:FireCallbacks(internal.callback.SELECTED_CATEGORY_CACHE_CHANGED, selectedCategoryCache)
        end
    end

    local guildSelectionProxy = {
        SetGuildId = RefreshSelectedCategoryCache
    }
    local guildWindows = GUILD_SELECTOR.guildWindows
    guildWindows[#guildWindows + 1] = guildSelectionProxy

    local function OnSelectionChanged(control, data, selected, reselectingDuringRebuild)
        if selected then
            RefreshSelectedCategoryCache()
        end
    end

    self.nodesByCategory = {}
    local categoryTree = history.categoryTree
    local root = categoryTree.rootNode
    for i = 1, #root.children do
        local child = root.children[i]
        if child.children then
            self.nodesByCategory[child.data.eventCategory] = child.children[1]
            for j = 1, #child.children do
                local leaf = child.children[j]
                SecurePostHook(leaf, "selectionFunction", OnSelectionChanged)
            end
        else
            self.nodesByCategory[child.data.eventCategory] = child
            SecurePostHook(child, "selectionFunction", OnSelectionChanged)
        end
    end
end

function GuildHistoryAdapter:SelectGuildByIndex(guildIndex)
    GUILD_SELECTOR:SelectGuildByIndex(guildIndex)
end

function GuildHistoryAdapter:SelectCategory(category)
    local node = self.nodesByCategory[category]
    if node then
        self.history.categoryTree:SelectNode(node)
    end
end

function GuildHistoryAdapter:GetSelectedCategoryCache()
    return self.selectedCategoryCache
end
