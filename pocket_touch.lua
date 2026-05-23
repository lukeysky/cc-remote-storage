local PROTOCOL = "secure_storage"
local MODEM_SIDE = "back"
local SERVER_ID = 7 -- change this

rednet.open(MODEM_SIDE)

local CATEGORIES = {
    "All", "Blocks", "Ores", "Storage",
    "Redstone", "Tools", "Food", "Machines", "Other"
}

local selectedCategory = "All"
local scroll = 0
local results = {}
local shown = {}
local tabButtons = {}
local itemRows = {}

local function clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function niceName(name)
    name = name:gsub("^.+:", "")
    name = name:gsub("_", " ")

    return name:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest
    end)
end

local function getCategory(itemName)
    itemName = string.lower(itemName)

    if itemName:find("chest") or itemName:find("barrel") or itemName:find("shulker") then
        return "Storage"
    elseif itemName:find("ore") or itemName:find("ingot") or itemName:find("nugget")
        or itemName:find("diamond") or itemName:find("emerald") then
        return "Ores"
    elseif itemName:find("redstone") or itemName:find("repeater") or itemName:find("comparator")
        or itemName:find("piston") or itemName:find("lever") or itemName:find("button") then
        return "Redstone"
    elseif itemName:find("pickaxe") or itemName:find("axe") or itemName:find("shovel")
        or itemName:find("sword") or itemName:find("hoe") then
        return "Tools"
    elseif itemName:find("apple") or itemName:find("bread") or itemName:find("beef")
        or itemName:find("porkchop") or itemName:find("chicken") or itemName:find("carrot")
        or itemName:find("potato") then
        return "Food"
    elseif itemName:find("machine") or itemName:find("motor") or itemName:find("generator")
        or itemName:find("furnace") or itemName:find("crafter") then
        return "Machines"
    elseif itemName:find("stone") or itemName:find("dirt") or itemName:find("wood")
        or itemName:find("log") or itemName:find("planks") or itemName:find("glass")
        or itemName:find("brick") or itemName:find("block") then
        return "Blocks"
    else
        return "Other"
    end
end

local function sendRequest(msg)
    rednet.send(SERVER_ID, msg, PROTOCOL)
    local _, response = rednet.receive(PROTOCOL, 5)
    return response
end

local function filterResults()
    shown = {}

    for _, item in ipairs(results) do
        if selectedCategory == "All" or getCategory(item.name) == selectedCategory then
            table.insert(shown, item)
        end
    end
end

local function drawButton(x, y, text, selected)
    term.setCursorPos(x, y)

    if selected then
        term.setBackgroundColor(colors.blue)
    else
        term.setBackgroundColor(colors.gray)
    end

    term.setTextColor(colors.white)
    write(" " .. text .. " ")

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function drawUI()
    clear()

    local w, h = term.getSize()
    tabButtons = {}
    itemRows = {}

    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    write("Remote Storage")
    term.setTextColor(colors.white)

    local x = 1
    local y = 3

    for _, category in ipairs(CATEGORIES) do
        local width = #category + 2

        if x + width > w then
            y = y + 1
            x = 1
        end

        drawButton(x, y, category, category == selectedCategory)

        table.insert(tabButtons, {
            category = category,
            x1 = x,
            x2 = x + width - 1,
            y = y
        })

        x = x + width + 1
    end

    local listTop = y + 2
    local listBottom = h - 2
    local visibleRows = listBottom - listTop + 1

    filterResults()

    local maxScroll = math.max(0, #shown - visibleRows)
    if scroll > maxScroll then scroll = maxScroll end
    if scroll < 0 then scroll = 0 end

    for row = 1, visibleRows do
        local index = scroll + row
        local item = shown[index]

        if item then
            local display = item.displayName or niceName(item.name)
            local line = display .. " x" .. item.count

            if #line > w then
                line = line:sub(1, w - 3) .. "..."
            end

            local screenY = listTop + row - 1
            term.setCursorPos(1, screenY)
            term.setTextColor(colors.white)
            write(line)

            itemRows[screenY] = item
        end
    end

    term.setCursorPos(1, h - 1)
    term.setTextColor(colors.lightGray)
    write("Scroll | Tap item | S=Search | Q=Quit")

    term.setCursorPos(1, h)
    term.setTextColor(colors.gray)
    write("Showing " .. #shown .. " items")
    term.setTextColor(colors.white)
end

local function searchItems()
    clear()
    print("Search storage")
    print()

    write("Search: ")
    local query = read()

    local response = sendRequest({
        type = "search",
        query = query
    })

    if response and response.ok then
        results = response.results
        selectedCategory = "All"
        scroll = 0
    else
        clear()
        print("No response from server.")
        sleep(2)
    end
end

local function requestItem(item)
    local display = item.displayName or niceName(item.name)

    while true do
        clear()

        print(display)
        print("Available: " .. item.count)
        print()
        print("[1] 1")
        print("[2] 16")
        print("[3] 32")
        print("[4] 64")
        print("[5] Custom")
        print("[6] Cancel")
        print()

        write("> ")
        local choice = read()

        local amount = nil

        if choice == "1" then
            amount = 1
        elseif choice == "2" then
            amount = 16
        elseif choice == "3" then
            amount = 32
        elseif choice == "4" then
            amount = 64
        elseif choice == "5" then
            write("Amount: ")
            amount = tonumber(read()) or 1
        elseif choice == "6" or choice == "" then
            return
        end

        if amount then
            local response = sendRequest({
                type = "request",
                item = item.name,
                count = amount
            })

            clear()

            if response and response.moved then
                print("Requested: " .. response.requested)
                print("Delivered: " .. response.moved)
            else
                print("Request failed.")
            end

            sleep(2)
            return
        end
    end
end

searchItems()

while true do
    drawUI()

    local event, button, x, y = os.pullEvent()

    if event == "mouse_click" then
        for _, tab in ipairs(tabButtons) do
            if y == tab.y and x >= tab.x1 and x <= tab.x2 then
                selectedCategory = tab.category
                scroll = 0
            end
        end

        if itemRows[y] then
            requestItem(itemRows[y])
        end

    elseif event == "mouse_scroll" then
        scroll = scroll + button

    elseif event == "key" then
        if button == keys.q then
            clear()
            break
        elseif button == keys.s then
            searchItems()
        elseif button == keys.up then
            scroll = scroll - 1
        elseif button == keys.down then
            scroll = scroll + 1
        end
    end
end
