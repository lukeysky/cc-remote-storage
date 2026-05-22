local PROTOCOL = "secure_storage"
local MODEM_SIDE = "top"
local BUFFER = "minecraft:chest_0" -- buffer chest next to Inventory Manager
local MANAGER_SIDE = "bottom"          -- side of buffer from Inventory Manager

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

local function scanItems()
    local items = {}

    for _, invName in ipairs(getInventories()) do
        local inv = peripheral.wrap(invName)

        for slot, item in pairs(inv.list()) do
            local key = item.name

            if not items[key] then
                items[key] = {
                    name = item.name,
                    displayName = item.displayName or item.name,
                    count = 0,
                }
            end

            items[key].count = items[key].count + item.count
        end
    end

    return items
end

local function searchItems(query)
    query = string.lower(query or "")
    local results = {}

    for name, data in pairs(scanItems()) do
        local display = string.lower(data.displayName or name)

        if string.find(string.lower(name), query, 1, true)
        or string.find(display, query, 1, true) then
            table.insert(results, data)
        end
    end

    table.sort(results, function(a, b)
        return a.displayName < b.displayName
    end)

    return results
end

local function moveToBuffer(itemName, amount)
    local remaining = amount
    local buffer = peripheral.wrap(BUFFER)

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
        count = amount,
    })
end

print("Secure storage server running.")
print("Computer ID:", os.getComputerID())

while true do
    local sender, msg = rednet.receive(PROTOCOL)

    if not AUTHORIZED[sender] then
        rednet.send(sender, {
            ok = false,
            error = "Unauthorized computer ID"
        }, PROTOCOL)

    elseif type(msg) == "table" then
        if msg.type == "search" then
            rednet.send(sender, {
                ok = true,
                results = searchItems(msg.query)
            }, PROTOCOL)

        elseif msg.type == "request" then
            local item = msg.item
            local count = tonumber(msg.count) or 1

            local moved = moveToBuffer(item, count)

            if moved > 0 then
                giveToPlayer(item, moved)
            end

            rednet.send(sender, {
                ok = moved == count,
                moved = moved,
                requested = count,
                item = item
            }, PROTOCOL)
        end
    end
end
