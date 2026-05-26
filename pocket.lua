local PROTOCOL = "secure_storage"

local MODEM_SIDE = "back"
local SERVER_ID = 20

rednet.open(MODEM_SIDE)

local scroll = 0
local results = {}
local itemRows = {}
local searchButton = nil
local refreshButton = nil
local putAwayButton = nil
local requestId = 0
local status = "Loading..."

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

local function drawButton(x, y, text)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    write(" " .. text .. " ")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function sendRequest(msg)
    requestId = requestId + 1
    msg.id = requestId

    rednet.send(SERVER_ID, msg, PROTOCOL)

    local timeout = os.startTimer(15)

    while true do
        local event, a, b, c = os.pullEvent()

        if event == "rednet_message" then
            if a == SERVER_ID
                and c == PROTOCOL
                and type(b) == "table"
                and b.id == requestId
            then
                return b
            end

        elseif event == "timer" and a == timeout then
            return nil
        end
    end
end

local function loadItems(query)
    status = "Searching..."

    local response = sendRequest({
        type = "search",
        query = query or ""
    })

    if response and response.ok then
        results = response.results or {}
        scroll = 0

        if response.busy then
            status = "Server scanning. Showing cached results."
        else
            status = "Loaded " .. #results .. " items."
        end

        return true
    end

    if response and response.error then
        status = response.error
    else
        status = "No response from server."
    end

    return false
end

local function refreshItems()
    status = "Refreshing..."

    local response = sendRequest({
        type = "refresh"
    })

    if response and response.ok then
        results = response.results or {}
        scroll = 0

        if response.busy then
            status = "Server still scanning."
        else
            status = "Refreshed " .. #results .. " items."
        end

        return true
    end

    if response and response.error then
        status = response.error
    else
        status = "Refresh failed."
    end

    return false
end

local function putAwayItems()
    status = "Putting away..."

    local response = sendRequest({
        type = "putaway"
    })

    if response and response.ok then
        results = response.results or {}
        scroll = 0
        status = "Put away moved " .. tostring(response.moved or 0) .. " items."
        return true
    end

    if response and response.error then
        status = response.error
    else
        status = "Put away failed."
    end

    return false
end

local function searchItems()
    clear()
    print("Search storage")
    print()
    write("Search: ")

    local query = read()
    loadItems(query)
end

local function drawUI()
    clear()

    local w, h = term.getSize()
    itemRows = {}

    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    write("Remote Storage")
    term.setTextColor(colors.white)

    local listTop = 3
    local listBottom = h - 4
    local visibleRows = listBottom - listTop + 1
    local maxScroll = math.max(0, #results - visibleRows)

    if scroll > maxScroll then scroll = maxScroll end
    if scroll < 0 then scroll = 0 end

    for row = 1, visibleRows do
        local index = scroll + row
        local item = results[index]

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

    local buttonY = h - 2

    searchButton = { x1 = 1, x2 = 10, y = buttonY }
    refreshButton = { x1 = 12, x2 = 23, y = buttonY }
    putAwayButton = { x1 = 25, x2 = 34, y = buttonY }

    drawButton(1, buttonY, "Search")
    drawButton(12, buttonY, "Refresh")
    drawButton(25, buttonY, "PutAway")

    term.setCursorPos(1, h - 1)
    term.setTextColor(colors.lightGray)
    write("Tap item | S search | R refresh | P put | Q quit")

    term.setCursorPos(1, h)
    term.setTextColor(colors.gray)

    local text = status or ""
    if #text > w then
        text = text:sub(1, w - 3) .. "..."
    end

    write(text)
    term.setTextColor(colors.white)
end

local function requestItem(item)
    local display = item.displayName or niceName(item.name)
    local buttons = {}

    local function drawAmountScreen()
        clear()

        term.setCursorPos(1, 1)
        term.setTextColor(colors.yellow)
        write(display)

        term.setCursorPos(1, 2)
        term.setTextColor(colors.white)
        write("Available: " .. item.count)

        buttons = {}

        local options = {
            { label = "1", amount = 1 },
            { label = "16", amount = 16 },
            { label = "32", amount = 32 },
            { label = "64", amount = 64 },
            { label = "Custom", amount = "custom" },
            { label = "Cancel", amount = "cancel" },
        }

        local y = 4

        for _, option in ipairs(options) do
            local x = 2
            local width = #option.label + 2

            drawButton(x, y, option.label)

            table.insert(buttons, {
                x1 = x,
                x2 = x + width - 1,
                y = y,
                amount = option.amount
            })

            y = y + 2
        end
    end

    local function sendAmount(amount)
        status = "Requesting..."

        local response = sendRequest({
            type = "request",
            item = item.name,
            count = amount
        })

        if response and response.ok then
            results = response.results or results
            status = "Delivered " .. tostring(response.moved or 0) .. " of " .. tostring(response.requested or amount) .. "."
        elseif response and response.moved then
            results = response.results or results
            status = "Delivered " .. tostring(response.moved or 0) .. " of " .. tostring(response.requested or amount) .. "."
        elseif response and response.error then
            status = response.error
        elseif response then
            status = "Could not deliver item."
        else
            status = "Request failed."
        end
    end

    while true do
        drawAmountScreen()

        local event, button, x, y = os.pullEvent()

        if event == "mouse_click" then
            for _, b in ipairs(buttons) do
                if y == b.y and x >= b.x1 and x <= b.x2 then
                    if b.amount == "cancel" then
                        return

                    elseif b.amount == "custom" then
                        clear()
                        print(display)
                        print("Available: " .. item.count)
                        print()
                        write("Amount: ")

                        local amount = tonumber(read()) or 1
                        amount = math.max(1, math.floor(amount))

                        sendAmount(amount)
                        return

                    else
                        sendAmount(b.amount)
                        return
                    end
                end
            end

        elseif event == "key" then
            if button == keys.one then
                sendAmount(1)
                return

            elseif button == keys.two then
                sendAmount(16)
                return

            elseif button == keys.three then
                sendAmount(32)
                return

            elseif button == keys.four then
                sendAmount(64)
                return

            elseif button == keys.five then
                clear()
                print(display)
                print("Available: " .. item.count)
                print()
                write("Amount: ")

                local amount = tonumber(read()) or 1
                amount = math.max(1, math.floor(amount))

                sendAmount(amount)
                return

            elseif button == keys.six or button == keys.q then
                return
            end
        end
    end
end

loadItems("")

while true do
    drawUI()

    local event, button, x, y = os.pullEvent()

    if event == "mouse_click" then
        if searchButton and y == searchButton.y and x >= searchButton.x1 and x <= searchButton.x2 then
            searchItems()

        elseif refreshButton and y == refreshButton.y and x >= refreshButton.x1 and x <= refreshButton.x2 then
            refreshItems()

        elseif putAwayButton and y == putAwayButton.y and x >= putAwayButton.x1 and x <= putAwayButton.x2 then
            putAwayItems()

        elseif itemRows[y] then
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

        elseif button == keys.r then
            refreshItems()

        elseif button == keys.p then
            putAwayItems()

        elseif button == keys.up then
            scroll = scroll - 1

        elseif button == keys.down then
            scroll = scroll + 1
        end
    end
end
