local JSON = require("json")
local ltn12 = require("ltn12")
local socket = require("socket")
local base64 = require('ffi/sha2')
local http = require("socket.http")
local socket_url = require("socket.url")
local socketutil = require("socketutil")
local UIManager = require("ui/uimanager")
local RenderImage = require("ui/renderimage")
local ImageViewer = require("ui/widget/imageviewer")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

-- TODO: Implement a secure method to store and retrieve the API key
local function getOpenAIApiKey()
    -- This is a placeholder. In a real-world scenario, you'd retrieve this securely.
    return os.getenv("OPENAI_API_KEY") or "your_openai_api_key_here"
end

local function getUrlContent(context_prompt, url, timeout, maxtime)
    local parsed = socket_url.parse(url)
    if parsed.scheme ~= "http" and parsed.scheme ~= "https" then
        return false, "Unsupported protocol"
    end
    if not timeout then timeout = 60 end

    local requestBodyTable = {
        prompt = context_prompt,
        n = 1,
        size = "512x512",
        response_format = "b64_json"
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
    if response and response.data and response.data[1] and response.data[1].b64_json then
        return true, response.data[1].b64_json
    else
        return false, "Unexpected response format"
    end
end

local function generateImage(ui, highlightedText)
    -- OpenAI DALL-E API endpoint
    local success, data = getUrlContent(highlightedText, "https://api.openai.com/v1/images/generations")

    if not success then
        UIManager:show(InfoMessage:new{text = _("Failed to generate image: " .. tostring(data))})
        return
    end

    local img = base64.base64_to_bin(data)
    
    local bb = RenderImage:renderImageData(img, #img, true)

    local imgviewer = ImageViewer:new{
        image = bb,
        image_disposable = false,
        with_title_bar = true,
        fullscreen = true,
    }
    UIManager:show(imgviewer)
end

return generateImage