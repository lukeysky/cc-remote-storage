local PROTOCOL = "secure_storage"
local MODEM_SIDE = "bottom"

local BUFFER = "minecraft:barrel_3"
local OUTPUT = "sophisticatedstorage:barrel_4"
local MANAGER_SIDE = "down"
local CACHE_TIME = 180

local ITEM_ROUTES = {
    ["minecraft:cobblestone"] = "storagedrawers:standard_drawers_1_90",
    ["minecraft:iron_nugget"] = "storagedrawers:fractional_drawers_3_9",
}

local INPUTS = {
    "sophisticatedstorage:barrel_0",
    "sophisticatedstorage:barrel_1",
    "sophisticatedstorage:barrel_2",
    "sophisticatedstorage:barrel_3",
}

local USERS = {
    [19] = "Michael",
    [21] = "Monitor"
}

rednet.open(MODEM_SIDE)

local manager =
    peripheral.find("inventoryManager") or
    peripheral.find("inventory_manager")

if not manager then
    error("No Inventory Manager found")
end

local cache = {}
local itemChestIndex = {}
local lastScan = 0
local scanning = false

local currentTab = "stock"
local scroll = 0
local logScroll = 0
local stockQuery = ""
local status = "Starting..."
local buttons = {}
local itemRows = {}
local logs = {}

local function now()
    return os.epoch("utc") / 1000
end

local function addLog(text)
    local stamp = textutils.formatTime(os.time(), true)
    table.insert(logs, 1, "[" .. stamp .. "] " .. text)

    while #logs > 100 do
        table.remove(logs)
    end

    status = text
end

local function clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function makeNiceName(name)
    name = name:gsub("^.+:", "")
    name = name:gsub("_", " ")

    return name:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest
    end)
end

local function addButton(id, x, y, text)
    local width = #text + 2

    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    write(" " .. text .. " ")

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)

    buttons[id] = {
        x1 = x,
        x2 = x + width - 1,
        y = y,
        text = text
    }
end

local function hitButton(x, y)
    for id, button in pairs(buttons) do
        if y == button.y and x >= button.x1 and x <= button.x2 then
            return id
        end
    end

    return nil
end

local function isInput(name)
    for _, input in ipairs(INPUTS) do
        if name == input then
            return true
        end
    end

    return false
end

local function isInventory(name)
    return peripheral.hasType(name, "inventory")
        and name ~= BUFFER
        and name ~= OUTPUT
        and not isInput(name)
end

local function getInventories()
    local inventories = {}

    for _, name in ipairs(peripheral.getNames()) do
        if isInventory(name) then
            table.insert(inventories, name)
        end
    end

    table.sort(inventories)
    return inventories
end

local function refreshCache()
    if scanning then
        return false
    end

    scanning = true
    addLog("Refreshing cache...")

    local items = {}
    local chestIndex = {}
    local inventories = getInventories()

    for i, invName in ipairs(inventories) do
        local inv = peripheral.wrap(invName)

        if inv then
            for _, item in pairs(inv.list()) do
                local key = item.name

                if not items[key] then
                    items[key] = {
                        name = item.name,
                        displayName = item.displayName or makeNiceName(item.name),
                        count = 0
                    }
                end

                items[key].count = items[key].count + item.count

                if not chestIndex[key] then
                    chestIndex[key] = {}
                end

                chestIndex[key][invName] = true
            end
        end

        if i % 4 == 0 then
            sleep(0)
        end
    end

    local result = {}

    for _, item in pairs(items) do
        table.insert(result, item)
    end

    table.sort(result, function(a, b)
        return a.displayName < b.displayName
    end)

    cache = result
    itemChestIndex = chestIndex
    lastScan = now()
    scanning = false

    addLog("Cache refreshed. " .. #cache .. " item types found.")

    return true
end

local function searchItems(query)
    query = string.lower(query or "")
    local results = {}

    for _, item in ipairs(cache) do
        local id = string.lower(item.name)
        local display = string.lower(item.displayName)

        if query == ""
            or string.find(id, query, 1, true)
            or string.find(display, query, 1, true)
        then
            table.insert(results, item)
        end
    end

    return results
end

local function putAwayItems()
    addLog("Put away started.")

    local movedTotal = 0
    local storage = getInventories()

    for _, inputName in ipairs(INPUTS) do
        local input = peripheral.wrap(inputName)

        if input then
            for slot, item in pairs(input.list()) do
                local remaining = item.count
                local matching = itemChestIndex[item.name] or {}

                local target = ITEM_ROUTES[item.name]

                -- First: assigned drawer/item route
                if target and peripheral.wrap(target) then
                    local moved = input.pushItems(target, slot, remaining)

                    if moved > 0 then
                        movedTotal = movedTotal + moved
                        remaining = remaining - moved
                        addLog("Routed " .. moved .. " " .. item.name .. " to " .. target)
                    end
                end

                -- Second: inventories already known to contain the same item
                for _, storageName in ipairs(storage) do
                    if remaining <= 0 then
                        break
                    end

                    if matching[storageName] then
                        local moved = input.pushItems(storageName, slot, remaining)

                        if moved > 0 then
                            movedTotal = movedTotal + moved
                            remaining = remaining - moved
                        end
                    end

                    sleep(0)
                end

                -- Third: fallback storage, but skip Storage Drawers
                for _, storageName in ipairs(storage) do
                    if remaining <= 0 then
                        break
                    end

                    if not storageName:find("^storagedrawers:") then
                        local moved = input.pushItems(storageName, slot, remaining)

                        if moved > 0 then
                            movedTotal = movedTotal + moved
                            remaining = remaining - moved
                        end
                    end

                    sleep(0)
                end
            end
        else
            addLog("Input missing: " .. inputName)
        end
    end

    if movedTotal > 0 then
        refreshCache()
    end

    addLog("Put away finished. Moved " .. movedTotal .. " items.")

    return movedTotal
end

local function moveToBuffer(itemName, amount)
    local remaining = amount

    for _, invName in ipairs(getInventories()) do
        local inv = peripheral.wrap(invName)

        if inv then
            for slot, item in pairs(inv.list()) do
                if item.name == itemName and remaining > 0 then
                    local moved = inv.pushItems(BUFFER, slot, remaining)
                    remaining = remaining - moved
                end

                if remaining <= 0 then
                    break
                end
            end
        end

        if remaining <= 0 then
            break
        end

        sleep(0)
    end

    return amount - remaining
end

local function moveToOutput(itemName, amount)
    local remaining = amount

    addLog("Output request: " .. amount .. " " .. itemName)

    for _, invName in ipairs(getInventories()) do
        local inv = peripheral.wrap(invName)

        if inv then
            for slot, item in pairs(inv.list()) do
                if item.name == itemName and remaining > 0 then
                    local moved = inv.pushItems(OUTPUT, slot, remaining)
                    remaining = remaining - moved
                end

                if remaining <= 0 then
                    break
                end
            end
        end

        if remaining <= 0 then
            break
        end

        sleep(0)
    end

    local movedTotal = amount - remaining

    if movedTotal > 0 then
        refreshCache()
    end

    addLog("Moved " .. movedTotal .. " of " .. itemName .. " to output.")

    return movedTotal
end

local function giveToPlayer(itemName, amount)
    return manager.addItemToPlayer(MANAGER_SIDE, {
        name = itemName,
        count = amount
    })
end

local function drawHeader()
    local w, h = term.getSize()

    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    write("Storage Server")
    term.setTextColor(colors.white)

    term.setCursorPos(1, 2)
    term.setTextColor(colors.lightGray)
    write("ID " .. os.getComputerID() .. " | Items " .. #cache)

    if scanning then
        write(" | Scanning")
    else
        write(" | Last " .. math.floor(now() - lastScan) .. "s")
    end

    buttons = {}

    term.setCursorPos(1, h)
    term.setTextColor(colors.gray)

    local line = status or ""
    if #line > w then
        line = line:sub(1, w - 3) .. "..."
    end

    write(line)
    term.setTextColor(colors.white)
end

local function drawStockTab()
    local w, h = term.getSize()

    itemRows = {}

    term.setCursorPos(1, 4)
    term.setTextColor(colors.white)
    write("Stock")

    addButton("search_stock", 8, 4, "Search")
    addButton("refresh", 19, 4, "Refresh")
    addButton("putaway", 31, 4, "PutAway")
    addButton("show_log", 43, 4, "Log")

    term.setCursorPos(1, 5)
    term.setTextColor(colors.lightGray)

    if stockQuery ~= "" then
        write("Filter: " .. stockQuery)
    else
        write("Showing all items")
    end

    local results = searchItems(stockQuery)
    local listTop = 7
    local listBottom = h - 2
    local visibleRows = listBottom - listTop + 1
    local maxScroll = math.max(0, #results - visibleRows)

    if scroll > maxScroll then scroll = maxScroll end
    if scroll < 0 then scroll = 0 end

    for row = 1, visibleRows do
        local index = scroll + row
        local item = results[index]

        if item then
            local line = item.displayName .. " x" .. item.count

            if #line > w then
                line = line:sub(1, w - 3) .. "..."
            end

            local y = listTop + row - 1
            term.setCursorPos(1, y)
            term.setTextColor(colors.white)
            write(line)

            itemRows[y] = item
        end
    end
end

local function drawLogTab()
    local w, h = term.getSize()

    term.setCursorPos(1, 4)
    term.setTextColor(colors.white)
    write("Log")

    addButton("back_stock", 7, 4, "Back")
    addButton("clear_log", 17, 4, "Clear")
    addButton("refresh", 28, 4, "Refresh")

    local listTop = 6
    local listBottom = h - 2
    local visibleRows = listBottom - listTop + 1
    local maxScroll = math.max(0, #logs - visibleRows)

    if logScroll > maxScroll then logScroll = maxScroll end
    if logScroll < 0 then logScroll = 0 end

    for row = 1, visibleRows do
        local index = logScroll + row
        local line = logs[index]

        if line then
            if #line > w then
                line = line:sub(1, w - 3) .. "..."
            end

            term.setCursorPos(1, listTop + row - 1)
            term.setTextColor(colors.lightGray)
            write(line)
        end
    end
end

local function drawUI()
    clear()
    drawHeader()

    if currentTab == "stock" then
        drawStockTab()
    elseif currentTab == "log" then
        drawLogTab()
    end
end

local function searchPrompt()
    clear()
    print("Search stock")
    print()
    write("Search: ")

    stockQuery = read() or ""
    scroll = 0
    currentTab = "stock"

    addLog("Stock search: " .. stockQuery)
end

local function outputSelectedItem(selected)
    clear()

    print("Output item to barrel")
    print("Output: " .. OUTPUT)
    print()
    print("Selected: " .. selected.displayName)
    print("Available: " .. selected.count)
    print()
    write("Amount: ")

    local amount = tonumber(read()) or 1
    amount = math.max(1, math.floor(amount))

    local moved = moveToOutput(selected.name, amount)

    print()
    print("Moved " .. moved .. " of " .. amount .. " to output barrel.")
    print("Press any key.")
    os.pullEvent("key")

    currentTab = "stock"
end

local function handleButton(id)
    if id == "search_stock" then
        searchPrompt()

    elseif id == "refresh" then
        refreshCache()

    elseif id == "putaway" then
        putAwayItems()

    elseif id == "show_log" then
        currentTab = "log"

    elseif id == "back_stock" then
        currentTab = "stock"

    elseif id == "clear_log" then
        logs = {}
        addLog("Log cleared.")
    end
end

local function serverUI()
    addLog("Server UI started.")

    while true do
        drawUI()

        local event, button, x, y = os.pullEvent()

        if event == "mouse_click" then
            local id = hitButton(x, y)

            if id then
                handleButton(id)

            elseif currentTab == "stock" and itemRows[y] then
                outputSelectedItem(itemRows[y])
            end

        elseif event == "mouse_scroll" then
            if currentTab == "stock" then
                scroll = scroll + button
            elseif currentTab == "log" then
                logScroll = logScroll + button
            end

        elseif event == "key" then
            if button == keys.q then
                clear()
                error("Server stopped by user", 0)

            elseif button == keys.s then
                currentTab = "stock"
                searchPrompt()

            elseif button == keys.o then
                addLog("Use the Stock screen and click an item to output it.")

            elseif button == keys.p then
                putAwayItems()

            elseif button == keys.r then
                refreshCache()

            elseif button == keys.l then
                currentTab = "log"

            elseif button == keys.up then
                if currentTab == "stock" then
                    scroll = scroll - 1
                elseif currentTab == "log" then
                    logScroll = logScroll - 1
                end

            elseif button == keys.down then
                if currentTab == "stock" then
                    scroll = scroll + 1
                elseif currentTab == "log" then
                    logScroll = logScroll + 1
                end
            end
        end
    end
end

local function rednetServer()
    addLog("Rednet server started on " .. MODEM_SIDE .. ".")

    while true do
        local sender, msg = rednet.receive(PROTOCOL)

        if not USERS[sender] then
            rednet.send(sender, {
                id = type(msg) == "table" and msg.id or nil,
                ok = false,
                error = "Unauthorized computer ID"
            }, PROTOCOL)

            addLog("Rejected unauthorized ID " .. tostring(sender))

        elseif type(msg) == "table" then
            local user = USERS[sender]

            if msg.type == "search" then
                rednet.send(sender, {
                    id = msg.id,
                    ok = true,
                    busy = scanning,
                    user = user,
                    results = searchItems(msg.query)
                }, PROTOCOL)

                addLog(user .. " searched: " .. tostring(msg.query or ""))

            elseif msg.type == "refresh" then
                refreshCache()

                rednet.send(sender, {
                    id = msg.id,
                    ok = true,
                    busy = scanning,
                    user = user,
                    results = searchItems("")
                }, PROTOCOL)

                addLog(user .. " refreshed cache.")

            elseif msg.type == "putaway" then
                local moved = putAwayItems()

                rednet.send(sender, {
                    id = msg.id,
                    ok = true,
                    user = user,
                    moved = moved,
                    results = searchItems("")
                }, PROTOCOL)

                addLog(user .. " ran put away. Moved " .. moved .. ".")

            elseif msg.type == "ticker" then
                rednet.send(sender, {
                    id = msg.id,
                    ok = true,
                    user = user,
                    results = searchItems("")
                }, PROTOCOL)

            elseif msg.type == "request" then
                local item = msg.item
                local count = tonumber(msg.count) or 1

                local moved = moveToBuffer(item, count)

                if moved > 0 then
                    giveToPlayer(item, moved)
                    refreshCache()
                end

                rednet.send(sender, {
                    id = msg.id,
                    ok = moved > 0,
                    user = user,
                    moved = moved,
                    requested = count,
                    item = item,
                    results = searchItems("")
                }, PROTOCOL)

                addLog(user .. " requested " .. moved .. "/" .. count .. " " .. tostring(item))

            else
                rednet.send(sender, {
                    id = msg.id,
                    ok = false,
                    error = "Unknown request type"
                }, PROTOCOL)

                addLog(user .. " sent unknown request: " .. tostring(msg.type))
            end
        end
    end
end

local function cacheLoop()
    refreshCache()

    while true do
        sleep(CACHE_TIME)
        putAwayItems()
        refreshCache()
    end
end

parallel.waitForAny(rednetServer, serverUI, cacheLoop)
