-- LibHistoire & its files © sirinsidiator                      --
-- Distributed under The Artistic License 2.0 (see LICENSE)     --
------------------------------------------------------------------

local lib = LibHistoire
local internal = lib.internal
local logger = internal.logger

local GuildHistoryAdapter = ZO_Object:Subclass()
internal.class.GuildHistoryAdapter = GuildHistoryAdapter

function GuildHistoryAdapter:New(...)
    local object = ZO_Object.New(self)
    object:Initialize(...)
    return object
end

function GuildHistoryAdapter:Initialize()
    local guildSelectionProxy = {
        SetGuildId = function(_, guildId)
            internal:FireCallbacks(internal.callback.SELECTED_GUILD_CHANGED, guildId)
        end
    }
    local guildWindows = GUILD_SELECTOR.guildWindows
    guildWindows[#guildWindows + 1] = guildSelectionProxy

    local function OnSelectionChanged(control, data, selected, reselectingDuringRebuild)
        if selected then
            internal:FireCallbacks(internal.callback.SELECTED_CATEGORY_CHANGED, data.categoryId)
        end
    end

    self.nodesByCategory = {}
    local categoryTree = GUILD_HISTORY.categoryTree
    local root = categoryTree.rootNode
    for i = 1, #root.children do
        local child = root.children[i]
        self.nodesByCategory[child.data] = child.children[1]
        for j = 1, #child.children do
            local leaf = child.children[j]
            SecurePostHook(leaf, "selectionFunction", OnSelectionChanged)
        end
    end
end

function GuildHistoryAdapter:SelectGuildByIndex(guildIndex)
    GUILD_SELECTOR:SelectGuildByIndex(guildIndex)
end

function GuildHistoryAdapter:SelectCategory(category)
    local node = self.nodesByCategory[category]
    if node then
        GUILD_HISTORY.categoryTree:SelectNode(node)
    end
end
