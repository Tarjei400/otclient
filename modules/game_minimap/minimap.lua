DEFAULT_ZOOM = 60
MAX_FLOOR_UP = 0
MAX_FLOOR_DOWN = 15

navigating = false
minimapWidget = nil
minimapButton = nil
minimapWindow = nil

flagsPanel    = nil
flagWindow    = nil
nextFlagId    = 0
--[[
  Known Issue (TODO):
  If you move the minimap compass directions and
  you change floor it will not update the minimap.
]]
function init()
  g_ui.importStyle('flagwindow.otui')

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onAutomapFlag = addMapFlag
  })
  connect(LocalPlayer, { onPositionChange = center, 
                         onPositionChange = updateMapFlags })

  g_keyboard.bindKeyDown('Ctrl+M', toggle)

  minimapButton = TopMenu.addRightGameToggleButton('minimapButton', tr('Minimap') .. ' (Ctrl+M)', 'minimap.png', toggle)
  minimapButton:setOn(true)

  minimapWindow = g_ui.loadUI('minimap.otui', modules.game_interface.getRightPanel())
  minimapWindow:setContentMinimumHeight(64)
  minimapWindow:setContentMaximumHeight(256)

  minimapWidget = minimapWindow:recursiveGetChildById('minimap')
  g_mouse.bindAutoPress(minimapWidget, compassClick, nil, MouseRightButton)
  --g_mouse.bindAutoPress(minimapWidget, compassClick, nil, MouseLeftButton)
  minimapWidget.onMousePress = createThingMenu
  
  minimapWidget:setAutoViewMode(false)
  minimapWidget:setViewMode(1) -- mid view
  minimapWidget:setDrawMinimapColors(true)
  minimapWidget:setMultifloor(false)
  minimapWidget:setKeepAspectRatio(false)
  minimapWidget.onMouseRelease = onMinimapMouseRelease
  minimapWidget.onMouseWheel = onMinimapMouseWheel
  flagsPanel = minimapWindow:recursiveGetChildById('flagsPanel')

  reset()
  minimapWindow:setup()
  loadMapFlags()
  
  if g_game.isOnline() then
    addEvent(function() updateMapFlags() end)
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onAutomapFlag = addMapFlag
  })
  disconnect(LocalPlayer, { onPositionChange = center,
                            onPositionChange = updateMapFlags })

  destroyFlagWindow()
  saveMapFlags() 
  if g_game.isOnline() then
    saveMap()
  end

  g_keyboard.unbindKeyDown('Ctrl+M')

  minimapButton:destroy()
  minimapWindow:destroy()
end

function destroyFlagWindow()
  if flagWindow then
    flagWindow:destroy()
    flagWindow = nil
  end
end

function createThingMenu(widget, menuPosition, button)
  if not g_game.isOnline() then return end
  if button ~= MouseRightButton then return end
  local menu = g_ui.createWidget('PopupMenu')

  if widget == minimapWidget then
    menu:addOption(tr('Create mark'), function() 
                local position = minimapWidget:getPosition(menuPosition)
                if position then
                  showFlagDialog(position)
                end
              end)
  else
    menu:addOption(tr('Delete mark'), function()
                  widget:destroy()
              end)
  end
  
  menu:display(menuPosition)
end

function showFlagDialog(position)
  if flagWindow then return end
  if not position then return end
  flagWindow = g_ui.createWidget('FlagWindow', rootWidget)

  local positionLabel = flagWindow:getChildById('position')
  local description = flagWindow:getChildById('description')
  local okButton = flagWindow:getChildById('okButton')
  local cancelButton = flagWindow:getChildById('cancelButton')

  positionLabel:setText(tr('Position: %i %i %i', position.x, position.y, position.z))

  flagRadioGroup = UIRadioGroup.create()
  local flagCheckbox = {}
  for i = 1, 20 do
    local checkbox = flagWindow:getChildById('flag' .. i)
    table.insert(flagCheckbox, checkbox)
    checkbox.icon = i
    flagRadioGroup:addWidget(checkbox)
  end
  
  flagRadioGroup:selectWidget(flagCheckbox[1])
  
  
  cancelButton.onClick = function() 
      flagRadioGroup:destroy()
      destroyFlagWindow()
    end
  okButton.onClick = function() 
      addMapFlag(position, flagRadioGroup:getSelectedWidget().icon, description:getText())
      flagRadioGroup:destroy()
      destroyFlagWindow()
    end
end

function loadMapFlags()
  mapFlags = {}

  local flagSettings = g_settings.getNode('MapFlags')
  if flagSettings then
    for i = 1, #flagSettings do
      local flag = flagSettings[i]
      addMapFlag(flag.position, flag.icon, flag.description, flag.id, flag.version)
      
      if i == #flagSettings then
        nextFlagId = flag.id + 1
      end
    end
  end
end

function saveMapFlags()
  local flagSettings = {}
  
  for i = 1, flagsPanel:getChildCount() do
    local child = flagsPanel:getChildByIndex(i)
    
    table.insert(flagSettings, {  position = child.position,
                                  icon = child.icon,
                                  description = child.description,
                                  id = child.id,
                                  version = child.version })
  end

  g_settings.setNode('MapFlags', flagSettings)
end

function getFlagIconClip(id)
  return (((id)%10)*11) .. ' ' .. ((math.ceil(id/10+0.1)-1)*11) .. ' 11 11'
end

function addMapFlag(pos, icon, message, flagId, version)
  if not(icon >= 1 and icon <= 20) or not pos then
    return 
  end
  
  version = version or g_game.getClientVersion()
  -- Check if flag is set for that position
  for i = 1, flagsPanel:getChildCount() do
    local flag = flagsPanel:getChildByIndex(i)
    if flag.position.x == pos.x and flag.position.y == pos.y and flag.position.z == pos.z
        and version == flag.version then
      return
    end
  end 
  
  if not flagId then
    flagId = nextFlagId
    nextFlagId = nextFlagId + 1
  end
  
  local flagWidget = g_ui.createWidget('FlagWidget', flagsPanel)
  flagWidget:setIconClip(getFlagIconClip(icon - 1))
  flagWidget:setId('flag' .. flagId)
  flagWidget.position = pos
  flagWidget.icon = icon
  flagWidget.description = message
  if message and message:len() > 0 then
    flagWidget:setTooltip(tr(message))
  end
  flagWidget.id = flagId
  flagWidget.version = version
  updateMapFlag(flagId)
  flagWidget.onMousePress = createThingMenu
end

function getMapArea()
  return minimapWidget:getPosition( { x = 1 + minimapWidget:getX(), y = 1 + minimapWidget:getY() } ),
            minimapWidget:getPosition( { x = -2 + minimapWidget:getWidth() + minimapWidget:getX(), y = -2 + minimapWidget:getHeight() + minimapWidget:getY() } )
end

function isFlagVisible(flag, firstPosition, lastPosition)
  return flag.version == g_game.getClientVersion() and (minimapWidget:getZoom() >= 30 and minimapWidget:getZoom() <= 150) and flag.position.x >= firstPosition.x and flag.position.x <= lastPosition.x and flag.position.y >= firstPosition.y and flag.position.y <= lastPosition.y and flag.position.z == firstPosition.z
end

function updateMapFlag(id)  
  local firstPosition, lastPosition = getMapArea()
  if not firstPosition or not lastPosition then
    return
  end
  
  local flag = flagsPanel:getChildById('flag' .. id)
  if isFlagVisible(flag, firstPosition, lastPosition) then
    flag:setVisible(true)
    flag:setMarginLeft( -5 + (minimapWidget:getWidth() / (lastPosition.x - firstPosition.x)) * (flag.position.x - firstPosition.x))
    flag:setMarginTop( -5 + (minimapWidget:getHeight() / (lastPosition.y - firstPosition.y)) * (flag.position.y - firstPosition.y))
  else
    flag:setVisible(false)   
  end
end

function updateMapFlags()
  local firstPosition, lastPosition = getMapArea()
  if not firstPosition or not lastPosition then
    return
  end
  
  for i = 1, flagsPanel:getChildCount() do
    local flag = flagsPanel:getChildByIndex(i)
    if isFlagVisible(flag, firstPosition, lastPosition) then
      flag:setVisible(true)      
      flag:setMarginLeft( -5 + (minimapWidget:getWidth() / (lastPosition.x - firstPosition.x)) * (flag.position.x - firstPosition.x))
      flag:setMarginTop( -5 + (minimapWidget:getHeight() / (lastPosition.y - firstPosition.y)) * (flag.position.y - firstPosition.y))
    else
      flag:setVisible(false)   
    end
  end
end

function online()
  reset()
  loadMap()
  
  updateMapFlags()
end

function offline()
  saveMap()
end

function loadMap()
  local clientVersion = g_game.getClientVersion()
  local minimapFile = '/minimap_' .. clientVersion .. '.otcm'
  if g_resources.fileExists(minimapFile) then
    g_map.clean()
    g_map.loadOtcm(minimapFile)
  end
end

function saveMap()
  local clientVersion = g_game.getClientVersion()
  local minimapFile = '/minimap_' .. clientVersion .. '.otcm'
  g_map.saveOtcm(minimapFile)
end

function toggle()
  if minimapButton:isOn() then
    minimapWindow:close()
    minimapButton:setOn(false)
  else
    minimapWindow:open()
    minimapButton:setOn(true)
  end
end

function isClickInRange(position, fromPosition, toPosition)
  return (position.x >= fromPosition.x and position.y >= fromPosition.y and position.x <= toPosition.x and position.y <= toPosition.y)
end

function reset()
  local player = g_game.getLocalPlayer()
  if not player then return end
  minimapWidget:followCreature(player)
  minimapWidget:setZoom(DEFAULT_ZOOM)
end

function center()
  local player = g_game.getLocalPlayer()
  if not player then return end
  minimapWidget:followCreature(player)
  
  updateMapFlags()
end

function compassClick(self, mousePos, mouseButton, elapsed)
  if elapsed < 300 then return end

  navigating = true
  local px = mousePos.x - self:getX()
  local py = mousePos.y - self:getY()
  local dx = px - self:getWidth()/2
  local dy = -(py - self:getHeight()/2)
  local radius = math.sqrt(dx*dx+dy*dy)
  local movex = 0
  local movey = 0
  dx = dx/radius
  dy = dy/radius

  if dx > 0.5 then movex = 1 end
  if dx < -0.5 then movex = -1 end
  if dy > 0.5 then movey = -1 end
  if dy < -0.5 then movey = 1 end

  local cameraPos = minimapWidget:getCameraPosition()
  local pos = {x = cameraPos.x + movex, y = cameraPos.y + movey, z = cameraPos.z}
  minimapWidget:setCameraPosition(pos)
  
  updateMapFlags()
end

function onButtonClick(id)
  if id == "zoomIn" then
    minimapWidget:setZoom(math.max(minimapWidget:getMaxZoomIn(), minimapWidget:getZoom()-15))
  elseif id == "zoomOut" then
    minimapWidget:setZoom(math.min(minimapWidget:getMaxZoomOut(), minimapWidget:getZoom()+15))
  elseif id == "floorUp" then
    local pos = minimapWidget:getCameraPosition()
    pos.z = pos.z - 1
    if pos.z > MAX_FLOOR_UP then
      minimapWidget:setCameraPosition(pos)
    end
  elseif id == "floorDown" then
    local pos = minimapWidget:getCameraPosition()
    pos.z = pos.z + 1
    if pos.z < MAX_FLOOR_DOWN then
      minimapWidget:setCameraPosition(pos)
    end
  end
  
  updateMapFlags()
end

function onMinimapMouseRelease(self, mousePosition, mouseButton)
  if navigating then
    navigating = false
    return
  end
  local pos = self:getPosition(mousePosition)
  if pos and mouseButton == MouseLeftButton and self:isPressed() then
    local dirs = g_map.findPath(g_game.getLocalPlayer():getPosition(), pos, 127, PathFindFlags.AllowNullTiles)
    if #dirs == 0 then
      modules.game_textmessage.displayStatusMessage(tr('There is no way.'))
      return true
    end
    g_game.autoWalk(dirs)
    return true
  end
  return false
end

function onMinimapMouseWheel(self, mousePos, direction)
  if direction == MouseWheelUp then
    self:zoomIn()
  else
    self:zoomOut()
  end
  updateMapFlags()
end

function onMiniWindowClose()
  minimapButton:setOn(false)
end
