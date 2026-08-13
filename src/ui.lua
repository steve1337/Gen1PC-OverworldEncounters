-- Overworld Encounters - UI & HUD Module
-- Renders a small, natural Gen 1 UI box (7x3 or 7x2 tiles, see HUD SIZE) with true RGBA Poké Ball sprite rendering and clean pixel font counts.

local UIModule = {}

local CatchingModule = nil
local Options = nil
local Font = require("src.render.Font")
local PaletteFX = require("src.render.PaletteFX")
local ballImageCache = {}

-- HUD SIZE.  Both boxes are 7 tiles wide against the right edge of the 160x144
-- canvas; a Gen 1 box is whole tiles, so the choice is between the two heights
-- the tile grid offers.  ballDY / countDY are offsets from the box's top edge.
local LAYOUTS = {
  -- Rows 15-17: 3 tiles, leaving an interior row the 8px count clears cleanly.
  normal = { tx = 13, ty = 15, tw = 7, th = 3, ballDY = 4, countDY = 8 },
  -- Rows 16-17: 2 tiles, all border -- the ball and count sit over the lines.
  compact = { tx = 13, ty = 16, tw = 7, th = 2, ballDY = 0, countDY = 4 },
}

for _, hudLayout in pairs(LAYOUTS) do
  hudLayout.x, hudLayout.y = hudLayout.tx * 8, hudLayout.ty * 8
  hudLayout.w, hudLayout.h = hudLayout.tw * 8, hudLayout.th * 8
  hudLayout.ballX, hudLayout.ballY = 105, hudLayout.y + hudLayout.ballDY
  hudLayout.countX, hudLayout.countY = 125, hudLayout.y + hudLayout.countDY
end

local hudCanvas = nil
local shadeShader = nil

function UIModule.setCatchingModule(mod)
  CatchingModule = mod
end

function UIModule.setOptions(opts)
  Options = opts
end

local function getBallImage(ballType)
  local key = tostring(ballType or "POKE_BALL"):lower()
  if ballImageCache[key] == nil then
    local path = "mods/Gen1PC-OverworldEncounters-main/assets/sprites/ball_" .. key .. ".png"
    local ok, img = pcall(love.graphics.newImage, path)
    ballImageCache[key] = ok and img or false
  end
  return ballImageCache[key]
end

-- PaletteFX's shade remap, with the draw color folded in before the shade is
-- picked so a glyph tinted black lands on shade 3 whether it came off a tile
-- page or a TTF font pack (the engine's own shader ignores the color, which it
-- can afford to because it only ever runs over a finished canvas).  Same
-- c0..c3 uniforms, so PaletteFX.sendColors feeds it unchanged.
local function getShadeShader()
  if shadeShader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      extern vec3 c0; extern vec3 c1; extern vec3 c2; extern vec3 c3;
      vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
        vec4 p = Texel(tex, tc) * color;
        vec3 mapped = p.r > 0.83 ? c0 : (p.r > 0.5 ? c1 : (p.r > 0.17 ? c2 : c3));
        return vec4(mapped, p.a);
      }
    ]])
    shadeShader = ok and sh or false
  end
  return shadeShader or nil
end

-- The palette the engine would colorize this HUD with: the overworld puts its
-- map palette over the whole UI pass, which is why text boxes tint with the
-- region you are standing in.
local function hudPalette(game, ow)
  local ok, colors = pcall(function()
    local name = ow and ow.paletteNameFor and ow:paletteNameFor(ow.map)
    return name and PaletteFX.pal(game and game.data, name) or nil
  end)
  return (ok and colors) or PaletteFX.GRAYS
end

local function getHudLayout()
  local key = Options and Options:get("hud_size")
  return LAYOUTS[key] or LAYOUTS.normal
end

-- The HUD at full strength, in 160x144 canvas coordinates.  With a shader the
-- box and the count come out in the display mode's colors; the ball is real
-- RGBA art and steps outside the remap.
local function drawHud(lg, shader, hudLayout, selectedBall, count)
  if shader then lg.setShader(shader) end
  lg.setColor(1, 1, 1, 1)
  Font.drawBox(hudLayout.tx, hudLayout.ty, hudLayout.tw, hudLayout.th)

  if shader then lg.setShader() end
  local ballImg = getBallImage(selectedBall)
  if ballImg then
    lg.setColor(1, 1, 1, 1)
    lg.draw(ballImg, hudLayout.ballX, hudLayout.ballY)
  end

  if shader then lg.setShader(shader) end
  lg.setColor(0, 0, 0, 1)
  Font.draw("× " .. tostring(count), hudLayout.countX, hudLayout.countY)
  if shader then lg.setShader() end
end

-- Screen-space UI draw (160x144 Game Boy canvas)
function UIModule.drawScreen(game, ow)
  if not love or not love.graphics then return end
  -- Only draw while the overworld owns the screen.  A text box or menu is its
  -- own state drawn above the overworld, and the true-color rect below would
  -- exempt that corner of the finished frame from the palette pass, leaving the
  -- message box in raw DMG shades there (the stray white rectangle).
  local stack = game and game.stack
  if stack and stack.top and stack:top() ~= ow then return end
  -- Range is enforced by the option's min/max when the player edits it.
  local opacity = (Options and tonumber(Options:get("hud_opacity")) or 100) / 100
  if opacity <= 0 then return end

  local lg = love.graphics
  local hudLayout = getHudLayout()
  local selectedBall = CatchingModule and CatchingModule.getSelectedBall(game) or "POKE_BALL"
  local save = game and game.save
  local count = (save and save.inventory and save.inventory[selectedBall]) or 0

  -- Push full graphics state
  lg.push("all")

  local shader = getShadeShader()
  if shader then PaletteFX.sendColors(shader, hudPalette(game, ow)) end

  -- rebuilt when HUD SIZE changes the box under it
  if hudCanvas == nil
      or (hudCanvas and (hudCanvas:getWidth() ~= hudLayout.w
                         or hudCanvas:getHeight() ~= hudLayout.h)) then
    if hudCanvas and hudCanvas.release then hudCanvas:release() end
    local ok, cv = pcall(lg.newCanvas, hudLayout.w, hudLayout.h)
    hudCanvas = ok and cv or false
    if hudCanvas then hudCanvas:setFilter("nearest", "nearest") end
  end

  if shader and hudCanvas then
    -- Colorized here rather than at composite time, so the ball can opt out of
    -- the remap while the box and count still follow COLORS.  The rect then
    -- takes the engine's trueColor opt-out or the composite would remap these
    -- already-final pixels a second time.
    PaletteFX.markTrueColor(hudLayout.x, hudLayout.y, hudLayout.w, hudLayout.h)

    -- Fading has to happen when the finished HUD reaches the UI canvas, not
    -- while drawing it: the canvas is cleared transparent and composited with
    -- alphamultiply, so translucent pixels written into it are multiplied by
    -- their own alpha a second time and land far darker than the option asks
    -- for.  Drawing opaque into a scratch canvas and blitting it premultiplied
    -- puts the alpha in the alpha channel only, which survives the composite.
    local target = lg.getCanvas()
    lg.setCanvas(hudCanvas)
    lg.clear(0, 0, 0, 0)
    lg.push()
    lg.translate(-hudLayout.x, -hudLayout.y)
    drawHud(lg, shader, hudLayout, selectedBall, count)
    lg.pop()
    lg.setCanvas(target)

    lg.setBlendMode("alpha", "premultiplied")
    lg.setColor(1, 1, 1, opacity)
    lg.draw(hudCanvas, hudLayout.x, hudLayout.y)
  else
    -- No shader or no canvas (headless): leave the HUD in DMG shades and let
    -- the composite colorize it, which costs the ball its true colors.
    drawHud(lg, nil, hudLayout, selectedBall, count)
  end

  lg.pop()
end

return UIModule
