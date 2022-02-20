require 'lib.moonloader'
local KEYS = {
    ['MENU'] = {press = VK_F3, hold = nil, menu = false, cursor = true},
    ['PREVIOUS'] = {press = VK_8, hold = VK_MENU, menu = false, cursor = true},
    ['STATE'] = {press = VK_9, hold = VK_MENU, menu = false, cursor = true},
    ['NEXT'] = {press = VK_0, hold = VK_MENU, menu = false, cursor = true},
}

local inicfg = require 'inicfg'
local directIni = 'SpotifyIntegrationByChapo123.ini'
local ini = inicfg.load(inicfg.load({
    main = {
        TOKEN = '',
        ignore_invalid_token = false
    },
}, directIni))
inicfg.save(ini, directIni)


function isBindPressed(t)
    return wasKeyPressed(t.press) and (t.hold == nil or isKeyDown(t.hold)) and (t.menu == false or renderWindow.state == true) and (t.cursor == true or not sampIsCursorActive())
end

local ffi = require('ffi')
local imgui = require 'mimgui'
local encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8
local notf = import 'imgui_notf.lua'
function notif(text)
    local duration = 1
    if notf then
        notf.addNotification(text, duration)
    end
end
local fa = require("fAwesome5")


local ignore_invalid_token = ini.main.ignore_invalid_token
local TOKEN = tostring(ini.main.TOKEN) --'BQBVvm1JN264jasUZ22TPDeBlUu-NRFUGJU9mwL5bKTjPlWqwCJ8QbkV1MkynWxHIDMkF3WRXvSJHyE-orfGeFWXnHSsSutmxaR3OAWDBvMTiaVESlKK9KNLPeo6ngUXKPI1fJmOT3E6SBIRSt9upQfH14pKLWMbVvcx7fVTZX79sszL'
local GET_TOKEN_URL = 'https://accounts.spotify.com/authorize?response_type=token&redirect_uri=https://token/&scope=user-modify-playback-state%20user-read-playback-state&client_id=5188d54a9433485b9b8f4bbd20bcb58f&client_secret=4f27cae79df548c18972e230a04e41d2'
local STATE = 'PAUSE'
local TOKEN_REDIRECT_URL = imgui.new.char[512]('')

--==[ ПЛАВНОЕ ПОЯВЛЕНИЕ ]==--
local ui_meta = {
    __index = function(self, v)
        if v == "switch" then
            local switch = function()
                if self.process and self.process:status() ~= "dead" then
                    return false -- // Предыдущая анимация ещё не завершилась!
                end
                self.timer = os.clock()
                self.state = not self.state

                self.process = lua_thread.create(function()
                    local bringFloatTo = function(from, to, start_time, duration)
                        local timer = os.clock() - start_time
                        if timer >= 0.00 and timer <= duration then
                            local count = timer / (duration / 100)
                            return count * ((to - from) / 100)
                        end
                        return (timer > duration) and to or from
                    end

                    while true do wait(0)
                        local a = bringFloatTo(0.00, 1.00, self.timer, self.duration)
                        self.alpha = self.state and a or 1.00 - a
                        if a == 1.00 then break end
                    end
                end)
                return true -- // Состояние окна изменено!
            end
            return switch
        end
 
        if v == "alpha" then
            return self.state and 1.00 or 0.00
        end
    end
}
local renderWindow = { state = false, duration = 0.5 } -- // Duration - это длительность анимации (в секундах)
setmetatable(renderWindow, ui_meta) -- // Устанавливаем выше созданную мета-таблицу в таблицу состояния первого окна
local tokenWindow = imgui.new.bool(false)

local headers = {}
local image = {
    file = getWorkingDirectory()..'\\resource\\spotifybychapo\\image.png',
    handle = nil,
    url = 'NONE',
}

local info = {
    ['main'] = {
        ['current_song'] = 'NONE',
        ['current_song_author'] = 'NONE',
    },
    ['duration'] = {
        ['current'] = 0,
        ['total'] = 0
    }
}
local DEBUG = false
function debugmsg(text)
    if DEBUG then
        print('[Spotify] [DEBUG] '..text)
    end
end

--==[ SPOTIFY ]==--
function spotify_update_info()
    if TOKEN ~= nil and TOKEN ~= '' then
        headers['Authorization'] = 'Bearer '..TOKEN
        asyncHttpRequest('GET', 'https://api.spotify.com/v1/me/player/currently-playing', {headers = headers},
        function(response)
            if response.status_code == 200 then
                local data = decodeJson(response.text)

                --==[ STATE ]==--
                STATE = data['is_playing'] and 'PLAY' or 'PAUSE'

                --==[ SONG NAME ]==--
                info['main']['current_song'] = data['item']['name']

                --==[ ARTISTS ]==--
                local artists = '' 
                for i = 1, #data['item']['artists'] do artists = artists..data['item']['artists'][i]['name']..(i ~= #data['item']['artists'] and ',' or '') end
                info['main']['current_song_author'] = artists

                --==[ DURATION ]==--
                info['duration']['current'] = data['progress_ms']
                info['duration']['total'] = data['item']['duration_ms']

                --==[ SONG IMAGE ]==--
                if data['item']['album']['images'][3] ~= nil then
                    local imgurl = data['item']['album']['images'][3]['url']
                    if image.url ~= imgurl or image.url == 'NONE' or image.handle == nil then
                        --os.remove(image.file)
                        local dlstatus = require('moonloader').download_status
                        downloadUrlToFile(imgurl, image.file, function (id, status, p1, p2)
                            if status == dlstatus.STATUSEX_ENDDOWNLOAD then
                                image.url = imgurl
                                image.handle = imgui.CreateTextureFromFile(image.file)--nil
                                debugmsg('Image updated!')
                            end
                        end)
                    end
                end
            else
                debugmsg('Error: code '..response.status_code, response.text)
                local data = decodeJson(response.text)
                if data['error'] ~= nil then
                    if data['error']['message'] == 'The access token expired' then
                        tokenWindow[0] = true
                    end
                end
            end
        end,
        function(err)
            debugmsg('Error, code '..err)
        end)
    else
        if tokenWindow[0] == false then
            tokenWindow[0] = true
        end
    end
end

local TOKEN_DIALOG = 1813
function convertDuration(ms)
    local seconds = math.floor(ms / 1000)
    local mins = math.floor(seconds / 60)
    seconds = seconds - mins * 60
    return mins..':'..(#tostring(seconds) == 1 and '0'..seconds or seconds)
end

--https://developer.spotify.com/console/player/

function getTokenFromUrl(url)
    --'https://token/#access_token=BQBhn0hVrFKss2x_uZNyZSg9A0nKuNfjc_0tSZZsXmKVzDk2zZXTXvk_W71Wl4i5XcW1UzSnhYUFOs39H8o44w8PIpkRbu5bcH7vE0LVeEadtQbLYc_yRfDVssg43zxwGYPeXP7xom58MA86tYPYnvipNG19wANwzqNNnyZ9XOrGPhLy&token_type=Bearer&expires_in=3600'
    local pattern = 'https://token/#access_token=(.+)&token_type=(.+)&expires_in=(%d+)'
    if url:find(pattern) then
        local token, type, expireTimeSecond = url:match(pattern)
        return true, token
    else
        return false, ''
    end
end

function getToken()
    lua_thread.create(function()
        sampShowDialog(TOKEN_DIALOG, 'Spotify TOKEN', 'Для работы скрипта необходим токен.\nЧерез 2 секунды откроется страница, нажмите "Разрешить".\nПосле перенаправления скопируйте адрес страницы и вставьте в поле ниже', 'Войти', 'Отмена', 3)
        wait(2000)    
        os.execute('explorer "https://accounts.spotify.com/authorize?response_type=token&redirect_uri=https://token/&scope=user-modify-playback-state%20user-read-playback-state&client_id=5188d54a9433485b9b8f4bbd20bcb58f&client_secret=4f27cae79df548c18972e230a04e41d2"')
    end)
    --https://accounts.spotify.com/authorize?response_type=token&redirect_uri=https://token/&scope=user-modify-playback-state%20user-read-playback-state&client_id=5188d54a9433485b9b8f4bbd20bcb58f&client_secret=4f27cae79df548c18972e230a04e41d2
end

function spotify(spotifyApiToken)
    local class = {}
    tokenReceive = {
        ['grant_type'] = 'client_credentials',
        ['client_id'] = '5188d54a9433485b9b8f4bbd20bcb58f',
        ['client_secret'] = '4f27cae79df548c18972e230a04e41d2'
    }
    
    function class:getToken()
        local TOKEN_RECEIVE_DATA = 'grant_type='..tokenReceive['grant_type']..'&client_id='..tokenReceive['client_id']..'&client_secret='..tokenReceive['client_secret']
        asyncHttpRequest('POST', 'https://accounts.spotify.com/api/token', {headers = {['Content-Type'] = 'application/x-www-form-urlencoded'}, data = TOKEN_RECEIVE_DATA}, 
            function(response) 
                if response.status_code == 200 then
                    local data = decodeJson(response.text)
                    if data['access_token'] ~= nil then
                        TOKEN = data['access_token']
                        debugmsg('[Spotify] [OK] token received: '..TOKEN) 
                    end
                else
                    debugmsg('[Spotify] [ERROR] Invalid response, code '..response.status_code) 
                end
            end, 
            function(err) 
                debugmsg('[Spotify] [ERROR] Token was not received: '..err) 
            end
        )
    end

    if spotifyApiToken ~= nil then
        if spotifyApiToken ~= '' then
            local headers = {}
            headers["Authorization"] = "Bearer "..spotifyApiToken
            headers["Content-Type"] = "application/json"
            headers["Content-Length"] = "0"

            local urls = {
                ['TRACK_NEXT'] = 'https://api.spotify.com/v1/me/player/next',
                ['TRACK_PREVIOUS'] = 'https://api.spotify.com/v1/me/player/previous',
                ['STATE_PLAY'] = 'https://api.spotify.com/v1/me/player/play',
                ['STATE_PAUSE'] = 'https://api.spotify.com/v1/me/player/pause',
                ['SET_VOLUME'] = 'https://api.spotify.com/v1/me/player/volume'
            }

            function class:SetVolume(int)
                headers['volume_percent'] = 0
                local params = {['volume_percent'] = 0}

                asyncHttpRequest('PUT', urls['SET_VOLUME'], {headers = headers, body=params}, function(response) debugmsg('VOLUME: '..response.status_code, response.text) end, function(err) debugmsg('ERROR: VOLUME'..err) end)
            end

            function class:TrackNext()
                asyncHttpRequest('POST', urls['TRACK_NEXT'], {headers = headers}, function(response) debugmsg('TRACK_NEXT: '..response.status_code) end, function(err) debugmsg('ERROR: '..err) end)
            end

            function class:TrackPrevious()
                asyncHttpRequest('POST', urls['TRACK_PREVIOUS'], {headers = headers}, function(response) debugmsg('TRACK_PREVIOUS: '..response.status_code) end, function(err) debugmsg('ERROR: '..err) end)
            end

            function class:Play()
                asyncHttpRequest('PUT', urls['STATE_PLAY'], {headers = headers}, function(response) debugmsg('STATE_PLAY: '..response.status_code) end, function(err) debugmsg('ERROR: '..err) end)
            end

            function class:Pause()
                asyncHttpRequest('PUT', urls['STATE_PAUSE'], {headers = headers}, function(response) debugmsg('STATE_PAUSE: '..response.status_code) end, function(err) debugmsg('ERROR: '..err) end)
            end
        else
            if tokenWindow[0] == false then
                tokenWindow[0] = true
            end
        end
    end
    spotify_update_info()
    return class
end




--==[ IMGUI ]==--
imgui.OnInitialize(function()
    imgui.SpotifyTheme()

    imgui.GetIO().IniFilename = nil

    local config = imgui.ImFontConfig()
    config.MergeMode = true
    local glyph_ranges = imgui.GetIO().Fonts:GetGlyphRangesCyrillic()
    local iconRanges = imgui.new.ImWchar[3](fa.min_range, fa.max_range, 0)
    imgui.GetIO().Fonts:AddFontFromFileTTF('trebucbd.ttf', 14.0, nil, glyph_ranges)
    icon = imgui.GetIO().Fonts:AddFontFromFileTTF('moonloader/resource/fonts/fa-solid-900.ttf', 32.0, config, iconRanges)
end)

function imgui.SpotifyTheme()
    imgui.GetStyle().WindowBorderSize = 2
    imgui.GetStyle().WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    imgui.GetStyle().Colors[imgui.Col.Border] = imgui.ImVec4(0.11, 0.73, 0.33, 1)
    imgui.GetStyle().Colors[imgui.Col.WindowBg]               = imgui.ImVec4(0.09, 0.09, 0.09, 1.00)

    imgui.GetStyle().Colors[imgui.Col.TitleBg]                = imgui.ImVec4(0.11, 0.73, 0.33, 1.00)
    imgui.GetStyle().Colors[imgui.Col.TitleBgActive]          = imgui.ImVec4(0.11, 0.73, 0.33, 1.00)

    imgui.GetStyle().Colors[imgui.Col.Button]                = imgui.ImVec4(0.11, 0.73, 0.33, 1.00)
    imgui.GetStyle().Colors[imgui.Col.ButtonHovered]         = imgui.ImVec4(0.12, 0.84, 0.38, 1.00)
    imgui.GetStyle().Colors[imgui.Col.ButtonActive]          = imgui.ImVec4(0.12, 0.84, 0.38, 1.00)

    

    imgui.GetStyle().FrameRounding = 100
    imgui.GetStyle().GrabRounding = 100
    imgui.GetStyle().Colors[imgui.Col.SliderGrab]             = imgui.ImVec4(0.11, 0.73, 0.33, 1.00)
    imgui.GetStyle().Colors[imgui.Col.SliderGrabActive]       = imgui.ImVec4(0.11, 0.73, 0.33, 1.00)

    imgui.GetStyle().Colors[imgui.Col.FrameBg]                = imgui.ImVec4(0.17, 0.17, 0.17, 1.00)
    imgui.GetStyle().Colors[imgui.Col.FrameBgHovered]         = imgui.ImVec4(0.17, 0.17, 0.17, 1.00)
    imgui.GetStyle().Colors[imgui.Col.FrameBgActive]          = imgui.ImVec4(0.17, 0.17, 0.17, 1.00)
end

local tokenFrame = imgui.OnFrame(
    function() return tokenWindow[0] end,
    function(player)
        local resX, resY = getScreenResolution()
        local sizeX, sizeY = 800, 265
        imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(sizeX, sizeY), imgui.Cond.FirstUseEver)
        imgui.Begin('Spotify Integration - TOKEN', tokenWindow, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse)
        
        local s = imgui.GetWindowSize()
        imgui.CenterText(u8'Для начала работы необходим токен, для его получения следуйте инструкции:')
        imgui.SetWindowFontScale(1)
        imgui.TextWrapped(u8'1. нажмите на кнопку "Дать доступ"\n2. после нажатия на кнопку у вас откроется страница, на которой необходимо нажать "ПРИНИМАЮ"\n3. После того как вас перенаправит на страницу, адрес которой начинается с "https://token/" введите ПОЛНЫЙ адрес страницы в поле ниже:')
        imgui.SetCursorPosX(5)
        
        if imgui.ButtonWithSettings(u8'Дать доступ', {rounding = 5},  imgui.ImVec2(sizeX - 10, 20)) then
            sampAddChatMessage('[Spotify] Через мгновение у вас откроется страница авторизации...', -1)
            os.execute('explorer "https://accounts.spotify.com/authorize?response_type=token&redirect_uri=https://token/&scope=user-modify-playback-state%20user-read-playback-state&client_id=5188d54a9433485b9b8f4bbd20bcb58f&client_secret=4f27cae79df548c18972e230a04e41d2"')
        end
        imgui.NewLine()
        imgui.CenterText(u8'Введите адрес страницы:')
        imgui.SetCursorPosX(5)
        imgui.PushItemWidth(sizeX - 10) imgui.InputText('##TOKEN_REDIRECT_URL', TOKEN_REDIRECT_URL, 512) imgui.PopItemWidth()
        imgui.SetCursorPosX(5)
        if imgui.ButtonWithSettings(u8'Проверить токен', {rounding = 5},  imgui.ImVec2(sizeX - 10, 20)) then
            local result, token = getTokenFromUrl(ffi.string(TOKEN_REDIRECT_URL))
            if result then
                sampAddChatMessage('[Spotify] Токен введен верно!', -1)
                TOKEN = token
                ini.main.TOKEN = TOKEN
                inicfg.save(ini, directIni)
                tokenWindow[0] = false
                renderWindow.state = true
            else
                sampAddChatMessage('[Spotify] Неверный токен!', -1)
                TOKEN_REDIRECT_URL = imgui.new.char[512]('')
            end
        end
        imgui.NewLine()
        imgui.SetCursorPosX(5)
        if imgui.ButtonWithSettings(u8'Закрыть и не показывать', {rounding = 5},  imgui.ImVec2(sizeX - 10, 20)) then
            ignore_invalid_token = true
        end
        
        imgui.End()
    end
)

local VOLUME = imgui.new.int(50)



local newFrame = imgui.OnFrame(
    function() return renderWindow.alpha > 0.00 end,
    function(self)
        local resX, resY = getScreenResolution()
        local sizeX, sizeY = 300, 100
        imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 4), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(sizeX, sizeY), imgui.Cond.FirstUseEver)
        self.HideCursor = not renderWindow.state
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, renderWindow.alpha)
        imgui.Begin('Spotify Integration', _, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize)
        
        local s = imgui.GetWindowSize()
        
        local imageSize = imgui.ImVec2(80, 80)
        imgui.SetCursorPos(imgui.ImVec2(10, 10))
        

        if image.handle ~= nil then
            imgui.Image(image.handle, imageSize)
        else
            imgui.Button('IMG', imageSize)
        end

        local timing = convertDuration(info['duration']['current'])..' / '..convertDuration(info['duration']['total'])
        local text = info['main']['current_song']..'\n'..info['main']['current_song_author']..'\n'
        imgui.SetCursorPos(imgui.ImVec2(5 + imageSize.x + 10, 10))
        imgui.TextWrapped(text)
        --imgui.Text('TOKEN '..TOKEN)
        
        local btnSettigs = {
            rounding = 100,
            color = imgui.ImVec4(0, 0, 0, 1),
            color_hovered = imgui.ImVec4(0, 0, 0, 0),
            color_active = imgui.ImVec4(0, 0, 0, 0)
        }

        local col = imgui.ImVec4(1, 1, 1, 1)
        local col_click = imgui.ImVec4(0.11, 0.73, 0.33, 1)


        local controlCenter = s.x / 2 - imgui.CalcTextSize(fa.ICON_FA_PAUSE_CIRCLE).x / 2
        imgui.SetCursorPosY(sizeY - imgui.CalcTextSize(fa.ICON_FA_PAUSE_CIRCLE).y - 8)

        imgui.SetCursorPosX(controlCenter) 
        if imgui.TextButton(STATE == 'PLAY' and fa.ICON_FA_PAUSE_CIRCLE or fa.ICON_FA_PLAY_CIRCLE, col, col_click) then 
            if STATE == 'PLAY' then
                spotify(TOKEN):Pause()
            else
                spotify(TOKEN):Play()
            end
            --STATE = STATE == 'PLAY' and 'PAUSE' or 'PLAY'
        end
        imgui.SameLine()
        imgui.SetCursorPosX(controlCenter - imgui.CalcTextSize(fa.ICON_FA_PAUSE_CIRCLE).x) 
        if imgui.TextButton(fa.ICON_FA_ANGLE_LEFT, col, col_click) then spotify(TOKEN):TrackPrevious() end
        imgui.SameLine()
        imgui.SetCursorPosX(controlCenter + imgui.CalcTextSize(fa.ICON_FA_PAUSE_CIRCLE).x + imgui.CalcTextSize(fa.ICON_FA_ANGLE_RIGHT).x) 
        if imgui.TextButton(fa.ICON_FA_ANGLE_RIGHT, col, col_click) then spotify(TOKEN):TrackNext() end
        

        imgui.SetCursorPos(imgui.ImVec2(sizeX - imgui.CalcTextSize(timing).x - 8, sizeY - imgui.CalcTextSize(timing).y - 8))
        imgui.Text(timing)

        --==[ VOLUME SLIDER ]==--
        --[[
        imgui.SetCursorPos(imgui.ImVec2(sizeX - 15, 10))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1, 1, 1, 0))
        if imgui.VSliderInt('##VOLUME', imgui.ImVec2(10, sizeY - 40), VOLUME, 0, 100) then
            spotify(TOKEN):SetVolume(VOLUME[0])
            sampAddChatMessage(type(VOLUME[0]), -1)
        end
        imgui.PopStyleColor()
        ]]
        

        imgui.End()
        imgui.PopStyleVar()
    end
)



function imgui.TextButton(text, color, colorHover)
    local c = imgui.GetCursorPos()
    imgui.TextColored(color, text)
    if imgui.IsItemHovered() then
        imgui.SetCursorPos(c)
        imgui.TextColored(colorHover, text)
    end
    return imgui.IsItemClicked()
end

function imgui.CenterText(text)
    imgui.SetCursorPosX(imgui.GetWindowSize().x / 2 - imgui.CalcTextSize(text).x / 2)
    imgui.Text(text)
end

local UPDATE_TIME = 900

function updateData()
    lua_thread.create(function()
        while true do
            wait(UPDATE_TIME)
            if renderWindow.state then
                spotify_update_info()
            end
        end
    end)
end

function main()
    while not isSampAvailable() do wait(0) end
    --if ini.main.TOKEN == '' then tokenWindow[0] = true end
    if not doesDirectoryExist(getWorkingDirectory()..'\\resource\\spotifybychapo') then createDirectory(getWorkingDirectory()..'\\resource\\spotifybychapo') end
    updateData()
    sampRegisterChatCommand('mimgui', function()
        renderWindow.state = not renderWindow.state
    end)
    sampRegisterChatCommand('spotify.token', function()
        tokenWindow[0] = not tokenWindow[0]
    end)
    while true do
        wait(0)
        if isBindPressed(KEYS['MENU']) then renderWindow.switch() end
        if isBindPressed(KEYS['PREVIOUS']) then spotify(TOKEN):TrackPrevious() notif('[Spotify]\nВоспроизведение предыдущей композиции') end
        if isBindPressed(KEYS['NEXT']) then spotify(TOKEN):TrackNext() notif('[Spotify]\nВоспроизведение следующей композиции') end
        if isBindPressed(KEYS['STATE'])     then 
            if STATE == 'PLAY' then
                spotify(TOKEN):Pause()
                notif('[Spotify]\nВоспроизведение приостановлено')
            else
                spotify(TOKEN):Play()
                notif('[Spotify]\nВоспроизведение возобновлено')
            end
        end

        if tokenWindow[0] and ignore_invalid_token == true then tokenWindow[0] = false end

        --local result, button, list, input = sampHasDialogRespond(TOKEN_DIALOG)
        --if result then
        --    if button == 1 and #input > 0 then
        --        sampAddChatMessage('Проверка токена, ожидайте...', -1)
        --        getTokenFromUrl(input)
        --    end
        --end
    end
end
function imgui.ButtonWithSettings(text, settings, size)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, settings.rounding or imgui.GetStyle().FrameRounding)
    imgui.PushStyleColor(imgui.Col.Button, settings.color or imgui.GetStyle().Colors[imgui.Col.Button])
    imgui.PushStyleColor(imgui.Col.ButtonHovered, settings.color_hovered or imgui.GetStyle().Colors[imgui.Col.ButtonHovered])
    imgui.PushStyleColor(imgui.Col.ButtonActive, settings.color_active or imgui.GetStyle().Colors[imgui.Col.ButtonActive])
    imgui.PushStyleColor(imgui.Col.Text, settings.color_text or imgui.GetStyle().Colors[imgui.Col.Text])
    local click = imgui.Button(text, size)
    imgui.PopStyleColor(4)
    imgui.PopStyleVar()
    return click
end

local effil = require 'effil' -- В начало скрипта

function asyncHttpRequest(method, url, args, resolve, reject)
   local request_thread = effil.thread(function (method, url, args)
      local requests = require 'requests'
      local result, response = pcall(requests.request, method, url, args)
      if result then
         response.json, response.xml = nil, nil
         return true, response
      else
         return false, response
      end
   end)(method, url, args)
   -- Если запрос без функций обработки ответа и ошибок.
   if not resolve then resolve = function() end end
   if not reject then reject = function() end end
   -- Проверка выполнения потока
   lua_thread.create(function()
      local runner = request_thread
      while true do
         local status, err = runner:status()
         if not err then
            if status == 'completed' then
               local result, response = runner:get()
               if result then
                  resolve(response)
               else
                  reject(response)
               end
               return
            elseif status == 'canceled' then
               return reject(status)
            end
         else
            return reject(err)
         end
         wait(0)
      end
   end)
end