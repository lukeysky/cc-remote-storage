local PROTOCOL = "secure_storage"
local MODEM_SIDE = "back"
local SERVER_ID = 20 -- change this

rednet.open(MODEM_SIDE)

local scroll = 0
local results = {}
local itemRows = {}
local searchButton = nil

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

local function sendRequest(msg)
    rednet.send(SERVER_ID, msg, PROTOCOL)
    local _, response = rednet.receive(PROTOCOL, 5)
    return response
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
        scroll = 0
    else
        clear()
        print("No response from server.")
        sleep(2)
    end
end

local function drawUI()
    clear()

    local w, h = term.getSize()
    itemRows = {}
    searchButton = nil

    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    write("Remote Storage")
    term.setTextColor(colors.white)

    local listTop = 3
    local listBottom = h - 3
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

    searchButton = {
        x1 = 1,
        x2 = 10,
        y = h - 1
    }

    drawButton(1, h - 1, "Search", false)

    term.setCursorPos(12, h - 1)
    term.setTextColor(colors.lightGray)
    write("Scroll | Tap item | Q=Quit")

    term.setCursorPos(1, h)
    term.setTextColor(colors.gray)
    write("Showing " .. #results .. " items")
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

            drawButton(x, y, option.label, false)

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
                sendAmount(amount)
                return
            elseif button == keys.six or button == keys.q then
                return
            end
        end
    end
end

searchItems()

while true do
    drawUI()

    local event, button, x, y = os.pullEvent()

    if event == "mouse_click" then
        if searchButton
            and y == searchButton.y
            and x >= searchButton.x1
            and x <= searchButton.x2
        then
            searchItems()
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
        elseif button == keys.up then
            scroll = scroll - 1
        elseif button == keys.down then
            scroll = scroll + 1
        end
    end
end
