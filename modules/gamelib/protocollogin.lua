-- @docclass
ProtocolLogin = extends(Protocol)

LoginServerError = 10
LoginServerMotd = 20
LoginServerUpdateNeeded = 30
LoginServerCharacterList = 100
LoginServerExtendedCharacterList = 101

function ProtocolLogin:login(host, port, accountName, accountPassword)
  if string.len(host) == 0 or port == nil or port == 0 then
    signalcall(self.onError, self, tr("You must enter a valid server address and port."))
    return
  end

  self.accountName = accountName
  self.accountPassword = accountPassword
  self.connectCallback = sendLoginPacket

  self:connect(host, port)
end

function ProtocolLogin:cancelLogin()
  self:disconnect()
end

function ProtocolLogin:sendLoginPacket()
  local msg = OutputMessage.create()
  msg:addU8(ClientOpcodes.ClientEnterAccount)
  msg:addU16(g_game.getOsType())
  msg:addU16(g_game.getClientVersion())

  msg:addU32(g_things.getDatSignature())
  msg:addU32(g_sprites.getSprSignature())
  msg:addU32(PIC_SIGNATURE)

  local paddingBytes = 128
  msg:addU8(0) -- first RSA byte must be 0
  paddingBytes = paddingBytes - 1

  -- xtea key
  self:generateXteaKey()
  local xteaKey = self:getXteaKey()
  msg:addU32(xteaKey[1])
  msg:addU32(xteaKey[2])
  msg:addU32(xteaKey[3])
  msg:addU32(xteaKey[4])
  paddingBytes = paddingBytes - 16

  if g_game.getFeature(GameProtocolChecksum) then
    self:enableChecksum()
  end

  if g_game.getFeature(GameAccountNames) then
    msg:addString(self.accountName)
    msg:addString(self.accountPassword)
    paddingBytes = paddingBytes - (4 + string.len(self.accountName) + string.len(self.accountPassword))
  else
    msg:addU32(tonumber(self.accountName))
    msg:addString(self.accountPassword)
    paddingBytes = paddingBytes - (6 + string.len(self.accountPassword))
  end

  msg:addPaddingBytes(paddingBytes, 0)
  msg:encryptRsa(128)

  self:send(msg)
  self:enableXteaEncryption()
  self:recv()
end

function ProtocolLogin:onConnect()
  self:sendLoginPacket()
end

function ProtocolLogin:onRecv(msg)
  while not msg:eof() do
    local opcode = msg:getU8()
    if opcode == LoginServerError then
      self:parseError(msg)
    elseif opcode == LoginServerMotd then
      self:parseMotd(msg)
    elseif opcode == LoginServerUpdateNeeded then
      signalcall(self.onError, self, tr("Client needs update. Verify your spr/dat/pic versions."))
    elseif opcode == LoginServerCharacterList then
      self:parseCharacterList(msg)
    elseif opcode == LoginServerExtendedCharacterList then
      self:parseExtendedCharacterList(msg)
    else
      self:parseOpcode(opcode, msg)
    end
  end
  self:disconnect()
end

function ProtocolLogin:parseError(msg)
  local errorMessage = msg:getString()
  signalcall(self.onError, self, errorMessage)
end

function ProtocolLogin:parseMotd(msg)
  local motd = msg:getString()
  signalcall(self.onMotd, self, motd)
end

function ProtocolLogin:parseCharacterList(msg)
  local characters = {}
  local charactersCount = msg:getU8()
  for i=1,charactersCount do
    local character = {}
    character.name = msg:getString()
    character.worldName = msg:getString()
    character.worldIp = iptostring(msg:getU32())
    character.worldPort = msg:getU16()
    characters[i] = character
  end

  local account = {}
  account.premDays = msg:getU16()
  signalcall(self.onCharacterList, self, characters, account)
end

function ProtocolLogin:parseExtendedCharacterList(msg)
  local characters = msg:getTable()
  local account = msg:getTable()
  local otui = msg:getString()
  signalcall(self.onCharacterList, self, characters, account, otui)
end

function ProtocolLogin:parseOpcode(opcode, msg)
  signalcall(self.onOpcode, self, opcode, msg)
end
