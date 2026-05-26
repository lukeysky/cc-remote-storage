local PROTOCOL = "secure_storage"
local MODEM_SIDE = "back"
local SERVER_ID = 7

local UPDATE_TIME = 60
local SCROLL_DELAY = 0.45
local TEXT_SCALE = 1
local LINE_COUNT = 4

rednet.open(MODEM_SIDE)

local monitor = peripheral.find("monitor")

if not monitor then
    error("No monitor found")
end

monitor.setTextScale(TEXT_SCALE)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)

local requestId = 0
local items = {}

local tickerLines = {
    " Loading... ",
    " Loading... ",
    " Loading... ",
    " Loading... "
}

local function clear()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    monitor.setCursorPos(1, 1)
end

local function sendRequest(msg)
    requestId = requestId + 1
    msg.id = requestId

    rednet.send(SERVER_ID, msg, PROTOCOL)

    local timeout = os.startTimer(8)

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

local function rebuildTicker()
    if #items == 0 then
        for i = 1, LINE_COUNT do
            tickerLines[i] = " No stock data... "
        end
        return
    end

    local lineParts = {}

    for i = 1, LINE_COUNT do
        lineParts[i] = {}
    end

    for i, item in ipairs(items) do
        local line = ((i - 1) % LINE_COUNT) + 1
        table.insert(lineParts[line], " " .. item.displayName .. " x" .. item.count .. " ")
    end

    for i = 1, LINE_COUNT do
        local text = table.concat(lineParts[i], "  |  ")

        if text == "" then
            text = " Empty "
        end

        tickerLines[i] = text .. "     " .. text
    end
end

local function updateStock()
    local response = sendRequest({
        type = "ticker"
    })

    if response and response.ok then
        items = response.results or {}
        rebuildTicker()
        return true
    end

    for i = 1, LINE_COUNT do
        tickerLines[i] = " Server not responding... "
    end

    return false
end

local function drawTickerLine(y, offset, color, text)
    local w, h = monitor.getSize()

    if y < 1 or y > h then
        return
    end

    monitor.setCursorPos(1, y)
    monitor.setTextColor(color)

    local line = ""

    for i = 1, w do
        local pos = ((offset + i - 2) % #text) + 1
        line = line .. text:sub(pos, pos)
    end

    monitor.write(line)
end

local function drawFrame(offset)
    local w, h = monitor.getSize()

    clear()

    monitor.setCursorPos(1, 1)
    monitor.setTextColor(colors.yellow)
    monitor.write("STORAGE STOCK")

    monitor.setTextColor(colors.gray)
    monitor.setCursorPos(math.max(1, w - 10), 1)
    monitor.write(os.date("%H:%M"))

    local startY = 3

    for i = 1, LINE_COUNT do
        local y = startY + i - 1
        local color = colors.white

        if i % 2 == 0 then
            color = colors.lightGray
        end

        drawTickerLine(y, offset, color, tickerLines[i])
    end
end

local function maxTickerLength()
    local longest = 1

    for i = 1, LINE_COUNT do
        if #tickerLines[i] > longest then
            longest = #tickerLines[i]
        end
    end

    return longest
end

updateStock()

local offset = 1
local lastUpdate = os.epoch("utc") / 1000

while true do
    drawFrame(offset)

    offset = offset + 1

    if offset > maxTickerLength() then
        offset = 1
    end

    local now = os.epoch("utc") / 1000

    if now - lastUpdate >= UPDATE_TIME then
        updateStock()
        lastUpdate = now
    end

    sleep(SCROLL_DELAY)
end
