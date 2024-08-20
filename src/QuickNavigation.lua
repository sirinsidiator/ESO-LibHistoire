local internal = LibHistoire.internal

local ENTRIES_PER_PAGE = 100

local function SwitchPageWithoutRequest(history, page)
    local wasAutoRequestEnabled = history.autoRequestEnabled
    history.autoRequestEnabled = false
    history:SetCurrentPage(page)
    history.autoRequestEnabled = wasAutoRequestEnabled
end

local function HasSubcategories(category)
    local info = GUILD_HISTORY_MANAGER.GetEventCategoryInfo(category)
    return info and #info.subcategories > 1
end

local function GetFirstPageWithGaps(history)
    local numVisibleEvents = GetOldestGuildHistoryEventIndexForUpToDateEventsWithoutGaps(history.guildId,
        history.selectedEventCategory) or 1
    local page = zo_ceil(numVisibleEvents / ENTRIES_PER_PAGE)

    local startIndex = (page - 1) * ENTRIES_PER_PAGE + 1
    local endIndex = startIndex + ENTRIES_PER_PAGE - 1

    local guildData = GUILD_HISTORY_MANAGER:GetGuildData(history.guildId)
    local eventCategoryData = guildData:GetEventCategoryData(history.selectedEventCategory)
    if eventCategoryData:CanHaveRedactedEvents() or HasSubcategories(history.selectedEventCategory) then
        if page > 1 then
            local exactStartIndex = eventCategoryData:GetStartingIndexForPage(page, ENTRIES_PER_PAGE,
                history.selectedSubcategoryIndex)
            local stopAtLastPage = not exactStartIndex
            while page > 1 and (not exactStartIndex or exactStartIndex > startIndex) do
                page = page - 1
                exactStartIndex = eventCategoryData:GetStartingIndexForPage(page, ENTRIES_PER_PAGE,
                    history.selectedSubcategoryIndex)
                if exactStartIndex and stopAtLastPage then
                    break
                end
            end
        end
        startIndex, endIndex = eventCategoryData:GetStartingAndEndingIndexForPage(page, ENTRIES_PER_PAGE,
            history.selectedSubcategoryIndex)
    end

    return page, startIndex, endIndex
end

local function OnShowPreviousPage(history)
    if IsShiftKeyDown() then
        SwitchPageWithoutRequest(history, 1)
        return true
    end
end

local function OnShowNextPage(history)
    if IsShiftKeyDown() then
        local page, startIndex, endIndex = GetFirstPageWithGaps(history)

        if startIndex and endIndex then
            history.cachedEventIndicesByPage[page] = {
                startIndex = startIndex,
                endIndex = endIndex
            }
        end

        SwitchPageWithoutRequest(history, page)
        return true
    end
end


function internal:InitializeQuickNavigation()
    ZO_PreHook(ZO_GuildHistory_Shared, "ShowPreviousPage", OnShowPreviousPage)
    ZO_PreHook(ZO_GuildHistory_Shared, "ShowNextPage", OnShowNextPage)
end
