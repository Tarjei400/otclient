CharacterList = { }

-- private variables
local charactersWindow
local loadBox
local characterList
local errorBox
local waitingWindow
local updateWaitEvent
local resendWaitEvent

-- private functions
local function tryLogin(charInfo, tries)
  tries = tries or 1

  if tries > 4 then
    CharacterList.destroyLoadBox()
    displayErrorBox(tr('Error'), tr('Unable to logout.'))
    return
  end

  if g_game.isOnline() then
    if tries == 1 then
      g_game.safeLogout()
      loadBox = displayCancelBox(tr('Please wait'), tr('Logging out...'))
    end
    scheduleEvent(function() tryLogin(charInfo, tries+1) end, 250)
    return
  end

  CharacterList.destroyLoadBox()

  g_game.loginWorld(G.account, G.password, charInfo.worldName, charInfo.worldHost, charInfo.worldPort, charInfo.characterName)

  loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to game server...'))
  connect(loadBox, { onCancel = function()
                                  loadBox = nil
                                  g_game.cancelLogin()
                                  CharacterList.show()
                                end })

  -- save last used character
  g_settings.set('lastUsedCharacter', charInfo.characterName)
end

local function updateWait(timeStart, timeEnd)
  if waitingWindow then
    local time = g_clock.seconds()
    if time <= timeEnd then
      local percent = ((time - timeStart) / (timeEnd - timeStart)) * 100
      local timeStr = string.format("%.0f", timeEnd - time)

      local progressBar = waitingWindow:getChildById('progressBar')
      progressBar:setPercent(percent)

      local label = waitingWindow:getChildById('timeLabel')
      label:setText(tr('Trying to reconnect in %s seconds.', timeStr))

      updateWaitEvent = scheduleEvent(function() updateWait(timeStart, timeEnd) end, 1000 * progressBar:getPercentPixels() / 100 * (timeEnd - timeStart))
      return true
    end
  end

  if updateWaitEvent then
    updateWaitEvent:cancel()
    updateWaitEvent = nil
  end
end

local function resendWait()
  if waitingWindow then
    waitingWindow:destroy()
    waitingWindow = nil

    if updateWaitEvent then
      updateWaitEvent:cancel()
      updateWaitEvent = nil
    end

    if charactersWindow then
      local selected = characterList:getFocusedChild()
      if selected then
        local charInfo = { worldHost = selected.worldHost,
                           worldPort = selected.worldPort,
                           characterName = selected.characterName }
        tryLogin(charInfo)
      end
    end
  end
end

local function onLoginWait(message, time)
  CharacterList.destroyLoadBox()

  waitingWindow = g_ui.displayUI('waitinglist.otui')

  local label = waitingWindow:getChildById('infoLabel')
  label:setText(message)

  updateWaitEvent = scheduleEvent(function() updateWait(g_clock.seconds(), g_clock.seconds() + time) end, 0)
  resendWaitEvent = scheduleEvent(resendWait, time * 1000)
end

function onGameLoginError(message)
  CharacterList.destroyLoadBox()
  errorBox = displayErrorBox(tr("Login Error"), message)
  errorBox.onOk = function()
    errorBox = nil
    CharacterList.showAgain()
  end
end

function onGameConnectionError(message, code)
  CharacterList.destroyLoadBox()
  errorBox = displayErrorBox(tr("Login Error"), message)
  errorBox.onOk = function()
    errorBox = nil
    CharacterList.showAgain()
  end
end

-- public functions
function CharacterList.init()
  connect(g_game, { onLoginError = onGameLoginError })
  connect(g_game, { onConnectionError = onGameConnectionError })
  connect(g_game, { onGameStart = CharacterList.destroyLoadBox })
  connect(g_game, { onLoginWait = onLoginWait })
  connect(g_game, { onGameEnd = CharacterList.showAgain })

  if G.characters then
    CharacterList.create(G.characters, G.characterAccount)
  end
end

function CharacterList.terminate()
  disconnect(g_game, { onLoginError = onGameLoginError })
  disconnect(g_game, { onConnectionError = onGameConnectionError })
  disconnect(g_game, { onGameStart = CharacterList.destroyLoadBox })
  disconnect(g_game, { onLoginWait = onLoginWait })
  disconnect(g_game, { onGameEnd = CharacterList.showAgain })

  if charactersWindow then
    characterList = nil
    charactersWindow:destroy()
    charactersWindow = nil
  end

  if loadBox then
    g_game.cancelLogin()
    loadBox:destroy()
    loadBox = nil
  end

  if waitingWindow then
    waitingWindow:destroy()
    waitingWindow = nil
  end

  if updateWaitEvent then
    updateWaitEvent:cancel()
    updateWaitEvent = nil
  end

  if resendWaitEvent then
    resendWaitEvent:cancel()
    resendWaitEvent = nil
  end

  CharacterList = nil
end

function CharacterList.create(characters, account, otui)
  if not otui then otui = 'characterlist.otui' end

  if charactersWindow then
    charactersWindow:destroy()
  end

  charactersWindow = g_ui.displayUI(otui)
  characterList = charactersWindow:getChildById('characters')

  -- characters
  G.characters = characters
  G.characterAccount = account

  characterList:destroyChildren()
  local accountStatusLabel = charactersWindow:getChildById('accountStatusLabel')

  local focusLabel
  for i,characterInfo in ipairs(characters) do
    local widget = g_ui.createWidget('CharacterWidget', characterList)
    for key,value in pairs(characterInfo) do
      local subWidget = widget:getChildById(key)
      if subWidget then
        if key == 'outfit' then -- it's an exception
          subWidget:setOutfit(value)
        else
          local text = value
          if subWidget.baseText and subWidget.baseTranslate then
            text = tr(subWidget.baseText, text)
          elseif subWidget.baseText then
            text = string.format(subWidget.baseText, text)
          end
          subWidget:setText(text)
        end
      end
    end

    -- these are used by login
    widget.characterName = characterInfo.name
    widget.worldHost = characterInfo.worldIp
    widget.worldPort = characterInfo.worldPort

    connect(widget, { onDoubleClick = function () CharacterList.doLogin() return true end } )

    if i == 1 or g_settings.get('lastUsedCharacter') == widget.characterName then
      focusLabel = widget
    end
  end

  characterList:focusChild(focusLabel, ActiveFocusReason)

  -- account
  if account.premDays > 0 then
    accountStatusLabel:setText(tr("Account Status:\nPremium Account (%s) days left", account.premDays))
  else
    accountStatusLabel:setText(tr('Account Status:\nFree Account'))
  end
end

function CharacterList.destroy()
  charactersWindow:hide()

  if charactersWindow then
    characterList = nil
    charactersWindow:destroy()
    charactersWindow = nil
  end

  if EnterGame and not g_game.isOnline() then
    EnterGame.show()
  end
end

function CharacterList.show()
  if not loadBox and not errorBox and charactersWindow then
    charactersWindow:show()
    charactersWindow:raise()
    charactersWindow:focus()
  end
end

function CharacterList.hide()
  charactersWindow:hide()
end

function CharacterList.showAgain()
  if characterList and characterList:hasChildren() then
    CharacterList.show()
  end
end

function CharacterList.isVisible()
  if charactersWindow and charactersWindow:isVisible() then
    return true
  end
  return false
end

function CharacterList.doLogin()
  local selected = characterList:getFocusedChild()
  if selected then
    local charInfo = { worldHost = selected.worldHost,
                       worldPort = selected.worldPort,
                       characterName = selected.characterName }
    charactersWindow:hide()
    tryLogin(charInfo)
  else
    displayErrorBox(tr('Error'), tr('You must select a character to login!'))
  end
end

function CharacterList.destroyLoadBox()
  if loadBox then
    loadBox:destroy()
    loadBox = nil
  end
end

function CharacterList.cancelWait()
  if waitingWindow then
    waitingWindow:destroy()
    waitingWindow = nil
  end

  if updateWaitEvent then
      updateWaitEvent:cancel()
      updateWaitEvent = nil
  end

  if resendWaitEvent then
    resendWaitEvent:cancel()
    resendWaitEvent = nil
  end

  CharacterList.destroyLoadBox()
  CharacterList.showAgain()
end
