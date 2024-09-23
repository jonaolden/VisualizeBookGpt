local JSON = require("json")
local ltn12 = require("ltn12")
local socket = require("socket")
local http = require("socket.http")
local socket_url = require("socket.url")
local socketutil = require("socketutil")
local UIManager = require("ui/uimanager")
local ImageViewer = require("ui/widget/imageviewer")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

-- TODO: Implement a secure method to store and retrieve the API key
local function getOpenAIApiKey()
    -- This is a placeholder. In a real-world scenario, you'd retrieve this securely.
    return os.getenv("OPENAI_API_KEY") or "your_openai_api_key_here"
end

local function getUrlContent(prompt, url, timeout, maxtime)
    local parsed = socket_url.parse(url)
    if parsed.scheme ~= "http" and parsed.scheme ~= "https" then
        return false, "Unsupported protocol"
    end
    if not timeout then timeout = 60 end

    local requestBodyTable = {
        model = "dall-e-3",
        prompt = prompt,
        n = 1,
        size = "1024x1024",
        quality = "standard"
    }

    local requestBody = JSON.encode(requestBodyTable)

    local sink = {}
    socketutil:set_timeout(timeout, maxtime or 60)
    local request = {
        url     = url,
        method  = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. getOpenAIApiKey()
        },
        source  = ltn12.source.string(requestBody),
        sink    = ltn12.sink.table(sink),
    }

    local code, headers, status = socket.skip(1, http.request(request))
    socketutil:reset_timeout()
    local content = table.concat(sink)

    if code == socketutil.TIMEOUT_CODE or
       code == socketutil.SSL_HANDSHAKE_CODE or
       code == socketutil.SINK_TIMEOUT_CODE
    then
        return false, "Request timed out"
    end
    if headers == nil then
        return false, "Network or remote server unavailable"
    end
    if not code or code < 200 or code > 299 then
        local error_message = "Remote server error or unavailable"
        if content then
            local error_response = JSON.decode(content)
            if error_response and error_response.error then
                error_message = error_response.error.message or error_message
            end
        end
        return false, error_message
    end

    local response = JSON.decode(content)
    if response and response.data and response.data[1] and response.data[1].url then
        return true, response.data[1].url
    else
        return false, "Unexpected response format"
    end
end

local function downloadImage(url)
    local response = {}
    local request, code, responseHeaders = http.request {
        url = url,
        method = "GET",
        sink = ltn12.sink.table(response)
    }
    
    if code ~= 200 then
        return nil, "Failed to download image: HTTP " .. tostring(code)
    end
    
    return table.concat(response)
end

local function generateImage(ui, highlightedText)
    -- OpenAI DALL-E API endpoint
    local success, data = getUrlContent(highlightedText, "https://api.openai.com/v1/images/generations")

    if not success then
        UIManager:show(InfoMessage:new{text = _("Failed to generate image: " .. tostring(data))})
        return
    end

    -- Download the image from the URL
    local imageData, error = downloadImage(data)
    if not imageData then
        UIManager:show(InfoMessage:new{text = _("Failed to download image: " .. tostring(error))})
        return
    end

    -- Create a temporary file to store the image
    local tempFilePath = "/tmp/generated_image.png"
    local file = io.open(tempFilePath, "wb")
    if file then
        file:write(imageData)
        file:close()

        local imgviewer = ImageViewer:new{
            file = tempFilePath,
            with_title_bar = true,
            fullscreen = true,
        }
        UIManager:show(imgviewer)
    else
        UIManager:show(InfoMessage:new{text = _("Failed to save image temporarily")})
    end
end

return generateImage