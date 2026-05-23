local PROTOCOL = "secure_storage"
local MODEM_SIDE = "top"

local BUFFER = "minecraft:barrel_3" -- change this
local MANAGER_SIDE = "down"          -- side of buffer from Inventory Manager
local CACHE_TIME = 20              -- seconds between rescans

local USERS = {
    [19] = "Michael", -- pocket computer ID = name
}

rednet.open(MODEM_SIDE)

local manager =
    peripheral.find("inventoryManager") or
    peripheral.find("inventory_manager")

if not manager then
    error("No Inventory Manager found")
end

local cache = {}
local lastScan = 0

local function makeNiceName(name)
    name = name:gsub("^.+:", "")
    name = name:gsub("_", " ")

    return name:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest
    end)
end

local function isInventory(name)
    return peripheral.hasType(name, "inventory") and name ~= BUFFER
end

local function getInventories()
    local inventories = {}

    for _, name in ipairs(peripheral.getNames()) do
        if isInventory(name) then
            table.insert(inventories, name)
        end
    end

    return inventories
end

local function scanItems()
    local items = {}

    for _, invName in ipairs(getInventories()) do
        local inv = peripheral.wrap(invName)

        for slot, item in pairs(inv.list()) do
            local key = item.name

            if not items[key] then
                items[key] = {
                    name = item.name,
                    displayName = item.displayName or makeNiceName(item.name),
                    count = 0
                }
            end

            items[key].count = items[key].count + item.count
        end
    end

    local result = {}

    for _, item in pairs(items) do
        table.insert(result, item)
    end

    table.sort(result, function(a, b)
        return a.displayName < b.displayName
    end)

    return result
end

local function getCachedItems()
    if os.clock() - lastScan > CACHE_TIME then
        cache = scanItems()
        lastScan = os.clock()
    end

    return cache
end

local function refreshCache()
    lastScan = 0
end

local function searchItems(query)
    query = string.lower(query or "")
    local results = {}

    for _, item in ipairs(getCachedItems()) do
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

local function moveToBuffer(itemName, amount)
    local remaining = amount

    for _, invName in ipairs(getInventories()) do
        local inv = peripheral.wrap(invName)

        for slot, item in pairs(inv.list()) do
            if item.name == itemName and remaining > 0 then
                local moved = inv.pushItems(BUFFER, slot, remaining)
                remaining = remaining - moved
            end
        end

        if remaining <= 0 then
            break
        end
    end

    return amount - remaining
end

local function giveToPlayer(itemName, amount)
    return manager.addItemToPlayer(MANAGER_SIDE, {
        name = itemName,
        count = amount
    })
end

print("Secure storage server running.")
print("Computer ID: " .. os.getComputerID())

while true do
    local sender, msg = rednet.receive(PROTOCOL)

    if not USERS[sender] then
        rednet.send(sender, {
            ok = false,
            error = "Unauthorized computer ID"
        }, PROTOCOL)

    elseif type(msg) == "table" then
        if msg.type == "search" then
            rednet.send(sender, {
                ok = true,
                user = USERS[sender],
                results = searchItems(msg.query)
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
                ok = moved > 0,
                user = USERS[sender],
                moved = moved,
                requested = count,
                item = item
            }, PROTOCOL)
        end
    end
endlocal PROTOCOL = "secure_storage"
local MODEM_SIDE = "top"

local BUFFER = "minecraft:chest_0" -- change this
local MANAGER_SIDE = "up"
local CACHE_TIME = 20

local USERS = {
    [12] = "Michael",
}

local CATEGORIES = {
    "All", "Blocks", "Ores", "Storage",
    "Redstone", "Tools", "Food", "Machines", "Other"
}

rednet.open(MODEM_SIDE)

local manager =
    peripheral.find("inventoryManager") or
    peripheral.find("inventory_manager")

if not manager then error("No Inventory Manager found") end

local cache = {}
local lastScan = 0
local selectedCategory = "All"
local searchQuery = ""
local scroll = 0
local tabButtons = {}

local function makeNiceName(name)
    name = name:gsub("^.+:", ""):gsub("_", " ")
    return name:gsub("(%a)([%w']*)", function(a, b)
        return a:upper() .. b
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
        or itemName:find("porkchop") or itemName:find("chicken")
        or itemName:find("carrot") or itemName:find("potato") then
        return "Food"
    elseif itemName:find("machine") or itemName:find("motor")
        or itemName:find("generator") or itemName:find("furnace")
        or itemName:find("crafter") then
        return "Machines"
    elseif itemName:find("stone") or itemName:find("dirt")
        or itemName:find("wood") or itemName:find("log")
        or itemName:find("planks") or itemName:find("glass")
        or itemName:find("brick") or itemName:find("block") then
        return "Blocks"
    else
        return "Other"
    end
end

local function isInventory(name)
    return peripheral.hasType(name, "inventory") and name ~= BUFFER
end

local function getInventories()
    local inventories = {}

    for _, name in ipairs(peripheral.getNames()) do
        if isInventory(name) then
            table.insert(inventories, name)
        end
    end

    return inventories
end

local function scanItems()
    local items = {}

    for _, invName in ipairs(getInventories()) do
        local inv = peripheral.wrap(invName)

        for slot, item in pairs(inv.list()) do
            local key = item.name

            if not items[key] then
                items[key] = {
                    name = item.name,
                    displayName = item.displayName or makeNiceName(item.name),
                    count = 0
                }
            end

            items[key].count = items[key].count + item.count
        end
    end

    local result = {}

    for _, item in pairs(items) do
        table.insert(result, item)
    end

    table.sort(result, function(a, b)
        return a.displayName < b.displayName
    end)

    return result
end

local function getCachedItems()
    if os.clock() - lastScan > CACHE_TIME then
        cache = scanItems()
        lastScan = os.clock()
    end

    return cache
end

local function refreshCache()
    lastScan = 0
end

local function searchItems(query)
    query = string.lower(query or "")
    local results = {}

    for _, item in ipairs(getCachedItems()) do
        local id = string.lower(item.name)
        local display = string.lower(item.displayName)

        if query == ""
            or string.find(id, query, 1, true)
            or string.find(display, query, 1, true) then
            table.insert(results, item)
        end
    end

    return results
end

local function moveToBuffer(itemName, amount)
    local remaining = amount

    for _, invName in ipairs(getInventories()) do
        local inv = peripheral.wrap(invName)

        for slot, item in pairs(inv.list()) do
            if item.name == itemName and remaining > 0 then
                local moved = inv.pushItems(BUFFER, slot, remaining)
                remaining = remaining - moved
            end
        end

        if remaining <= 0 then break end
    end

    return amount - remaining
end

local function giveToPlayer(itemName, amount)
    return manager.addItemToPlayer(MANAGER_SIDE, {
        name = itemName,
        count = amount
    })
end

local function serverLoop()
    while true do
        local sender, msg = rednet.receive(PROTOCOL)

        if not USERS[sender] then
            rednet.send(sender, {
                ok = false,
                error = "Unauthorized computer ID"
            }, PROTOCOL)

        elseif type(msg) == "table" then
            if msg.type == "search" then
                rednet.send(sender, {
                    ok = true,
                    user = USERS[sender],
                    results = searchItems(msg.query)
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
                    ok = moved > 0,
                    user = USERS[sender],
                    moved = moved,
                    requested = count,
                    item = item
                }, PROTOCOL)
            end
        end
    end
end

local function clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
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

local function getFilteredStock()
    local filtered = {}

    for _, item in ipairs(searchItems(searchQuery)) do
        if selectedCategory == "All" or getCategory(item.name) == selectedCategory then
            table.insert(filtered, item)
        end
    end

    return filtered
end

local function drawStockUI()
    clear()

    local w, h = term.getSize()
    local stock = getFilteredStock()
    tabButtons = {}

    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    write("Storage Stock")
    term.setTextColor(colors.white)

    term.setCursorPos(1, 2)
    write("Search: " .. (searchQuery == "" and "<none>" or searchQuery))

    local x = 1
    local y = 4

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

    local maxScroll = math.max(0, #stock - visibleRows)
    if scroll > maxScroll then scroll = maxScroll end
    if scroll < 0 then scroll = 0 end

    for row = 1, visibleRows do
        local item = stock[scroll + row]

        if item then
            local line = item.displayName .. " x" .. item.count

            if #line > w then
                line = line:sub(1, w - 3) .. "..."
            end

            term.setCursorPos(1, listTop + row - 1)
            write(line)
        end
    end

    term.setCursorPos(1, h - 1)
    term.setTextColor(colors.lightGray)
    write("Scroll | Tap tab | S=Search | R=Refresh")

    term.setCursorPos(1, h)
    term.setTextColor(colors.gray)
    write("Items: " .. #stock .. " | ID: " .. os.getComputerID())
    term.setTextColor(colors.white)
end

local function setSearch()
    clear()
    print("Search stock")
    print()
    write("Search: ")
    searchQuery = read()
    scroll = 0
end

local function uiLoop()
    while true do
        drawStockUI()

        local event, button, x, y = os.pullEvent()

        if event == "mouse_click" then
            for _, tab in ipairs(tabButtons) do
                if y == tab.y and x >= tab.x1 and x <= tab.x2 then
                    selectedCategory = tab.category
                    scroll = 0
                end
            end

        elseif event == "mouse_scroll" then
            scroll = scroll + button

        elseif event == "key" then
            if button == keys.s then
                setSearch()
            elseif button == keys.r then
                refreshCache()
            elseif button == keys.up then
                scroll = scroll - 1
            elseif button == keys.down then
                scroll = scroll + 1
            end
        end
    end
end

parallel.waitForAny(serverLoop, uiLoop)local PROTOCOL = "secure_storage"
local MODEM_SIDE = "top"

local BUFFER = "minecraft:chest_0" -- change this
local MANAGER_SIDE = "up"          -- side of buffer from Inventory Manager

local AUTHORIZED = {
    [12] = true, -- change to your pocket computer ID
}

rednet.open(MODEM_SIDE)

local manager =
    peripheral.find("inventoryManager") or
    peripheral.find("inventory_manager")

if not manager then
    error("No Inventory Manager found")
end

-- Build clean fallback names
local function makeNiceName(name)
    name = name:gsub("^.+:", "") -- remove mod prefix
    name = name:gsub("_", " ")

    return name:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest
    end)
end

local function isInventory(name)
    return peripheral.hasType(name, "inventory")
        and name ~= BUFFER
end

local function getInventories()
    local inventories = {}

    for _, name in ipairs(peripheral.getNames()) do
        if isInventory(name) then
            table.insert(inventories, name)
        end
    end

    return inventories
end

-- Scan all storage
local function scanItems()
    local items = {}

    for _, invName in ipairs(getInventories()) do
        local inv = peripheral.wrap(invName)

        for slot, item in pairs(inv.list()) do
            local key = item.name
            local display = item.displayName or makeNiceName(item.name)

            if not items[key] then
                items[key] = {
                    name = item.name,
                    displayName = display,
                    count = 0
                }
            end

            items[key].count = items[key].count + item.count
        end
    end

    local result = {}

    for _, item in pairs(items) do
        table.insert(result, item)
    end

    table.sort(result, function(a, b)
        return a.displayName < b.displayName
    end)

    return result
end

-- Search item list
local function searchItems(query)
    query = string.lower(query or "")
    local results = {}

    for _, item in ipairs(scanItems()) do
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

-- Move item to buffer chest
local function moveToBuffer(itemName, amount)
    local remaining = amount

    for _, invName in ipairs(getInventories()) do
        local inv = peripheral.wrap(invName)

        for slot, item in pairs(inv.list()) do
            if item.name == itemName and remaining > 0 then
                local moved = inv.pushItems(BUFFER, slot, remaining)
                remaining = remaining - moved
            end
        end

        if remaining <= 0 then
            break
        end
    end

    return amount - remaining
end

-- Deliver to linked player
local function giveToPlayer(itemName, amount)
    return manager.addItemToPlayer(MANAGER_SIDE, {
        name = itemName,
        count = amount
    })
end

print("Secure storage server running.")
print("Computer ID: " .. os.getComputerID())

while true do
    local sender, msg = rednet.receive(PROTOCOL)

    -- Security check
    if not AUTHORIZED[sender] then
        rednet.send(sender, {
            ok = false,
            error = "Unauthorized computer ID"
        }, PROTOCOL)

    elseif type(msg) == "table" then

        -- Search request
        if msg.type == "search" then
            rednet.send(sender, {
                ok = true,
                results = searchItems(msg.query)
            }, PROTOCOL)

        -- Item request
        elseif msg.type == "request" then
            local item = msg.item
            local count = tonumber(msg.count) or 1

            local moved = moveToBuffer(item, count)

            if moved > 0 then
                giveToPlayer(item, moved)
            end

            rednet.send(sender, {
                ok = moved > 0,
                moved = moved,
                requested = count,
                item = item
            }, PROTOCOL)
        end
    end
end
