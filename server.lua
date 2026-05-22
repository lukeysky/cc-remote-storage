local PROTOCOL = "secure_storage"
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
