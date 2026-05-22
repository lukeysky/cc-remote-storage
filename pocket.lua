local PROTOCOL = "secure_storage"
local MODEM_SIDE = "back"
local SERVER_ID = 1 -- change to your storage computer ID

rednet.open(MODEM_SIDE)

local function clear(title)
    term.clear()
    term.setCursorPos(1, 1)
    print("=== " .. title .. " ===")
    print()
end

local function sendRequest(msg)
    rednet.send(SERVER_ID, msg, PROTOCOL)
    local _, response = rednet.receive(PROTOCOL, 5)
    return response
end

local function searchUI()
    clear("Storage Search")

    write("Search: ")
    local query = read()

    local response = sendRequest({
        type = "search",
        query = query
    })

    if not response or not response.ok then
        print("No response or error.")
        sleep(2)
        return
    end

    local results = response.results

    clear("Results")

    if #results == 0 then
        print("No items found.")
        sleep(2)
        return
    end

    for i, item in ipairs(results) do
        print(i .. ". " .. item.displayName)
        print("   Count: " .. item.count)
    end

    print()
    write("Choose item number or blank: ")
    local choice = tonumber(read())

    if not choice or not results[choice] then
        return
    end

    local selected = results[choice]

    write("Amount: ")
    local amount = tonumber(read()) or 1

    local request = sendRequest({
        type = "request",
        item = selected.name,
        count = amount
    })

    clear("Request Result")

    if request and request.moved then
        print("Requested: " .. request.requested)
        print("Delivered: " .. request.moved)
    else
        print("Request failed.")
    end

    sleep(3)
end

while true do
    clear("Remote Storage")

    print("Server ID: " .. SERVER_ID)
    print()
    print("[1] Search items")
    print("[2] Exit")
    print()

    write("> ")
    local choice = read()

    if choice == "1" then
        searchUI()
    elseif choice == "2" then
        clear("Goodbye")
        break
    end
end
