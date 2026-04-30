-- electronic light instrument construction kit

-- local grid = grid
-- local clock = clock
-- local setmetatable = setmetatable
-- local table = table
-- local assert = assert
-- local ipairs = ipairs
-- local type = type
-- local print = print

local P = {}
-- XXX deprecated, what's the best way to control module privacy across versions?
-- setfenv(1, P)

EMPTY = -1

Instrument = {}

function Instrument.new(g)
  local n = setmetatable({}, { __index = Instrument })
  -- TODO what about multiple grids?
  g = g or (grid and grid.connect()) or nil
  if g ~= nil then
    n:connect_grid(g)
  end

  n.views_arr = {}
  n.views_by_name = {}
  n.active = nil
  n.clock = nil
  return n
end

function Instrument:connect_grid(g)
  if g == nil then
    return
  end

  self.grid = g
  self.grid.key = function (x, y, z)
    if self.before_key ~= nil then
      self.before_key(x, y, z)
    end
    if self.active ~= nil then
      self.active:key(x, y, z)
    end
  end
end


function Instrument:new_view(name, width, height)
  width = width or (self.grid and self.grid.device and self.grid.device.cols) or 8
  height = height or (self.grid and self.grid.device and self.grid.device.rows) or 8
  local v = P.View.new(width, height)
  table.insert(self.views_arr, v)

  if name ~= nil then
    self.views_by_name[name] = v
  end

  if self.active == nil then
    self.active = v
  end
  return v
end

function Instrument:tick()
  if self.active ~= nil then
    local view = self.active
    view:tick()
    if self.grid ~= nil then
      view:refresh(self.grid)
    end
  end
end

function Instrument:run(interval)
  interval = interval or 1/15
  -- if we are running in norns, clock global will be available
  if clock ~= nil then
    self.clock = clock.run(
      function()
        while true do
          clock.sleep(interval)
          self:tick()
        end
      end
    )
  else
    print("no clock available")
  end
end

function Instrument:switch_to(name)
  -- TODO clear entire grid before switching views to avoid stranded
  if type(name) == "number" then
    assert(name > 0 and name <= #self.views_arr, "view does not exist")
    self.active = self.views_arr[name]
  else
    assert(self.views_by_name[name] ~= nil, "view does not exist")
    self.active = self.views_by_name[name]
  end
  self:clear()
  return self.active
end

function Instrument:clear()
  if self.grid ~= nil then
    for y=1,self.grid.device.rows do
      for x=1,self.grid.device.cols do
        self.grid:led(x, y, 0)
      end
    end
  end
end



View = {}

function View.new(width, height)
  local w = setmetatable({}, { __index = View })
  w.height = (height or 8)
  w.width = (width or 8)
  w.boxes = {}
  -- build a matrix representing the view so we can
  -- address the box at any given coordinate
  w.lookup = {}
  for y=1,w.height do
    w.lookup[y] = {}
    for x=1,w.width do
      -- XXX since lua uses nil to mean "end of array" we need our
      -- own null-ish value to signify an empty space in the matrix
      w.lookup[y][x] = EMPTY
    end
  end
  -- XXX why need to force an initial render?
  w.dirty = true -- force an initial render
  return w
end

local function seq(box, absx, absy)
  return (absy - box.yoffset - 1) * box.width + (absx - box.xoffset)
end

function View:key(x, y, z)
  -- find box
  local box = self.lookup[y][x]
  if box == EMPTY then
    return
  end

  assert(box ~= nil, "programmer error")

  if z == 1 then
    box:keydown(seq(box, x, y))
  else
    box:keyup(seq(box, x, y))
  end

end

function View:refresh(grid)
  local needs_refresh = false
  for _, box in ipairs(self.boxes) do
    if self.dirty or box.dirty then
      needs_refresh = true

      local seq = 1
      for y=1,box.height do
        for x=1,box.width do
          grid:led(x+box.xoffset, y+box.yoffset, box.leds[seq])
          seq = seq + 1
        end
      end

      box.dirty = false
    end
  end
  self.dirty = false

  if needs_refresh then
    grid:refresh()
  end
end

function View:tick()
  for _, box in ipairs(self.boxes) do
    box:tick()
  end
end

function find_first_space(matrix, width, height)
  for y, row in ipairs(matrix) do
    for x, col in ipairs(row) do
      if matrix[y][x] == EMPTY  -- current position is open
        and x + width - 1 <= #row -- the width fits
        and y + height - 1 <= #matrix -- the height fits
      then
        -- is the rest of the required space clear?
        local all_clear = true
        for yy=1,height do
          for xx=1,width do
            if matrix[y+yy-1][x+xx-1] ~= EMPTY then
              all_clear = false
              break
            end
          end
        end
        if all_clear then
          return x, y
        end
      end
    end
  end
  -- no free space of required size could be located
  return nil, nil
end

-- create a new box and add it in the first open space
function View:new_box(width, height, keydown_cb, keyup_cb, tick_cb)
  -- find first open space
  local x, y = find_first_space(self.lookup, width, height)
  if x == nil and y == nil then
    -- error("no space for box")
    -- XXX swallowing the error rather than blowing up maybe makes
    -- things a little more flexible for writing for grids of
    -- different sizes? not confident in the decision here until
    -- feeling it out in practice some more
    print("no space for box")
    return nil
  end

  local b = Box.new(width, height, keydown_cb, keyup_cb, tick_cb)
  self:add_box(b, x, y)
  return b
end

function View:add_box(box, x, y)
  table.insert(self.boxes, box)
  -- XXX validate box width and height fits in space
  box.xoffset = 0
  box.yoffset = 0
  if x ~= nil and x > 0 then
    box.xoffset = x - 1
  end
  if y ~= nil and y > 0 then
    box.yoffset = y - 1
  end

  for y=1,box.height do
    for x=1,box.width do
      local absx = x + box.xoffset
      local absy = y + box.yoffset
      self.lookup[absy][absx] = box
    end
  end
end


Box = {}

function Box.new(width, height, keydown_cb, keyup_cb, tick_cb)
  local w = setmetatable({}, { __index = Box })
  w.width = (width or 4)
  w.height = (height or 4)

  -- floor brightness
  -- TODO configurable
  w.floor = 1

  w.leds = {}
  for i=1,w.width*w.height do
    table.insert(w.leds, w.floor)
  end

  -- render state
  w.dirty = true

  -- will mutate when added to a space
  w.xoffset = 0
  w.yoffset = 0


  -- event handlers
  w.tick = function (box) end
  w.keydown = function (box, seq) end
  w.keyup = function (box, seq) end
  if tick_cb ~= nil then
    w.tick = tick_cb
  end
  if keydown_cb ~= nil then
    w.keydown = keydown_cb
  end
  if keyup_cb ~= nil then
    w.keyup = keyup_cb
  end
  return w
end

function Box:led(seq, v)
  assert(seq <= self.width*self.height, "invalid seq: " .. seq)
  assert(v >= 0 and v <= 15, "led brightness 0 to 15")
  self.leds[seq] = math.max(v, self.floor)
  self.dirty = true
end

function Box:all(v)
  for i=1,self.width*self.height do
    self.leds[i] = math.max(v, self.floor)
  end
  self.dirty = true
end

function Box:seqlen()
  return self.width*self.height
end

P.Instrument = Instrument
P.View = View
P.Box = Box

-- XXX supposed to be private but exposed for unit test
P.EMPTY = EMPTY
P.find_first_space = find_first_space

eli = P
return P
