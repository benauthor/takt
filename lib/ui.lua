-- takt ui @its_your_bedtime

local ui = {

    reel = {
        pos = { x = 28, y = 21 },  -- default
        left  = { {}, {}, {}, {}, {}, {} },
        right = { {}, {}, {}, {}, {}, {} },
    },
    tape = { 
        tension = 30,
        flutter = { on = false, amount = 60 }
    },
    playhead = {
        height = 35,
        brightness = 0,
    },
}

local speed = 0.2


local function update_reel()
  for i=1, 6 do
    ui.reel.left[i].velocity = util.linlin(0, 1, 0.01, (speed / 1.9) / (1 / 2), 0.15)
    ui.reel.left[i].position = (ui.reel.left[i].position - ui.reel.left[i].velocity) % (math.pi * 2)
    ui.reel.left[i].x = 30 + ui.reel.left[i].orbit * math.cos(ui.reel.left[i].position)
    ui.reel.left[i].y = 25 + ui.reel.left[i].orbit * math.sin(ui.reel.left[i].position)
    ui.reel.right[i].velocity = util.linlin(0, 1, 0.01, (speed / 1.5) / (1 / 2), 0.15)
    ui.reel.right[i].position = (ui.reel.right[i].position - ui.reel.right[i].velocity) % (math.pi * 2)
    ui.reel.right[i].x = 95 + ui.reel.right[i].orbit * math.cos(ui.reel.right[i].position)
    ui.reel.right[i].y = 25 + ui.reel.right[i].orbit * math.sin(ui.reel.right[i].position)
  end
end


ui.init  = function()
for i=1, 6 do
    ui.reel.right[i].orbit = math.fmod(i,2)~=0 and 3 or 9
    ui.reel.right[i].position = i <= 2 and 0 or i <= 4 and 2 or 4
    ui.reel.right[i].velocity = util.linlin(0, 1, 0.01, speed, 1)
    ui.reel.left[i].orbit = math.fmod(i,2)~=0 and 3 or 9
    ui.reel.left[i].position = i <= 2 and 3 or i <= 4 and 5 or 7.1
    ui.reel.left[i].velocity = util.linlin(0, 1, 0.01, speed * 3, 0.2)
end
update_reel()
end


local music = require 'musicutil'

local function get_step(x) return (x * 16) - 15 end

local function set_brightness(n, i) screen.level(i == n and 6 or 2) end

local function metro_icon(x, y, pos)
  local metroicon = pos % 4
  screen.level(0)
  screen.move(x + 2, y + 5)
  screen.line(x + 7, y)
  screen.line(x + 12, y + 5)
  screen.line(x + 3, y + 5)
  screen.stroke()
  screen.move(x + 7, y + 3)
  screen.line(metroicon <= 1 and (x + 4) or (x + 10), y ) 
  screen.stroke()

end

local dividers  = { '1/8', '1/4', '1/2', '3/4', '--', '3/2', '2x' } 


function ui.head(params_data, data, view, k1, rules, PATTERN_REC) -- , selected, data[data.pattern].track, data, data.ui_index)
  local tr = data.selected[1]
  local s = data.selected[2]
  local pos = data[data.pattern].track.pos[tr]
  
  screen.level((not view.sampling and data.ui_index == -6 ) and 5 or 2)  
  screen.rect(1, 0, 20, 7)
  screen.fill()
  screen.level(0)
  
  screen.font_size(6)
  screen.font_face(25)
  
  
  if not s then 
    screen.move(2,6)
    screen.text(PATTERN_REC and 'P!' or 'P')
    screen.move(17,6)
    screen.text_right(data.pattern or nil )
    screen.stroke()
    
  else
    screen.move(11,6)
    screen.text_center( tr ..':' .. s )
  end

    screen.level((not view.sampling and data.ui_index == (not s and -5 or -3) ) and 5 or 2)  
    screen.rect(22, 0, 20, 7)
    screen.fill()
    screen.level(0)
    screen.move(31,6)
  
  if s then 
    


  else
    screen.text_center( 'TR ' .. tr )
  end
  
  screen.stroke()
  
  if s then 
    local rule_name = rules[params_data.rule][1]
    
    screen.level((not view.sampling and data.ui_index == -2 ) and 5 or 2)  
    screen.rect(43, 0, 41, 7)
    screen.fill()
    screen.level(0)
    if string.len(rule_name) < 5 then
      screen.move(45, 6)
      screen.text('RULE')
      screen.move(82, 6)
      screen.text_right(rule_name)
    else
      screen.move(45, 6)
      screen.text(rule_name)
    end
    
  else
    screen.level((not view.sampling and data.ui_index == -4) and 5 or 2)  
    screen.rect(43, 0, 25, 7)
    screen.fill()
    screen.level(0)
    metro_icon(42,1, pos)
    screen.move(66, 6)
    screen.text_right(data[data.pattern].bpm)
    
    
  end

  screen.stroke()
  
  if not s then
    screen.level((not view.sampling and data.ui_index == -3) and 5 or 2)  
    screen.rect(69, 0, 15, 7)
    screen.fill()
    screen.level(0)
    screen.move(76,6)
    screen.text_center(dividers[data[data.pattern].track.div[tr]])
    screen.stroke()
  end
  
  if not k1 then
    screen.level((not view.sampling and data.ui_index == -1) and 5 or 2)  
    screen.rect(85, 0, 9, 7)
    screen.fill()
    screen.level(0)
    screen.move(89,6)
    screen.text_center(params_data.retrig)
    screen.stroke()
  
      
      for i = 1, 16 do
        local offset_y = i <= 8 and 0 or 4
        local offset_x = i <= 8 and 0 or 8
        
        local st = s and get_step(data.selected[2]) or data[data.pattern].track.pos[tr]
        
        screen.level((not view.sampling and data.ui_index == 0) and 5 or 2)
    
        local step = data[data.pattern][data.selected[1]][st + (i - 1 )]
        
        if step == 1 then
          screen.rect(92 + ((i - offset_x) * 4), offset_y + 1, 2, 2) 
          screen.stroke()
        else
          screen.rect(91 + ((i - offset_x) * 4), offset_y, 3, 3) 
          screen.fill()
        end
    end
  else
    screen.level(data.ui_index == -2 and 5 or 2)  
    screen.rect(85, 0, 20, 7)
    screen.fill()
    screen.level(0)
    screen.move(89,6)
    --screen.text_center('SETTINGS')
    screen.stroke()    
    
    screen.level(data.ui_index == -1 and 5 or 2)  
    screen.rect(106, 0, 20, 7)
    screen.fill()
    screen.level(0)
    screen.move(89,6)
    --screen.text_center('SETTINGS')
    screen.stroke()

  end
end

function ui.draw_env(x, y, t, params_data, ui_index)
    local atk, dec, sus, rel
    atk = params_data.attack
    dec = params_data.decay+ 0.4
    sus = params_data.sustain
    rel = params_data.release
    

    local sy = util.clamp(y - (sus * 10) + 2, 0, y )
    local attack_peak = x + atk * 2
    
    screen.level(2)
    screen.rect(x - 1, y - 15, 40, 16)
    screen.stroke()
    
    
    screen.level(ui_index == 9 and 15 or 1)
    screen.move(x,y)
    screen.line(attack_peak, y - 14)
    screen.stroke()
    screen.level(ui_index == 10 and 15 or 1)
    screen.move(attack_peak, y - 14)
    screen.line(x + ((atk / 2) + dec) * 3 + 2, sy)
    screen.stroke()
    screen.level(ui_index == 11 and 15 or 1 )
    screen.move(x + ((atk / 2) + dec) * 3 + 2, sy)
    screen.line(util.clamp(x + (rel) * 3 + 24, 0,  x+38), sy )
    screen.stroke()
    screen.level(ui_index == 12 and 15 or 1)
    screen.move(util.clamp(x + ( rel) * 3 + 24, 2, x+38), sy)
    screen.line(util.clamp(x + ( rel) * 2 + 38, 0, x+38), y)
    screen.stroke()
  
end

function ui.draw_filter(x, y, params_data, ui_index)

    screen.level(2)
    screen.rect(x - 1, y - 15, 40, 16)
    screen.stroke()

    local sample = params_data.sample
    local cut = params_data.cutoff / 1200
    local res = params_data.resonance


    screen.level(1)
    if params_data.ftype == 1 then
        local t = x + cut * 2
        screen.level(ui_index == 17 and 15 or 1)
        screen.move(x - 1, y - 9)
        screen.line(t + 2, y - 9 - (res * 5))
        screen.stroke()
        screen.level(ui_index == 18 and 15 or 1)
        screen.move(t + 2, y - 9 - (res * 5))
        screen.line(t + 4, y)
        screen.stroke()
        

  elseif params_data.ftype == 2 then
        cut =  17 - cut
        local t = x + cut * 2
        screen.level( ui_index == 18 and 15 or 1)
        screen.move(t - 1, y)
        screen.line(t + 1 , y - 9 - (res * 5))
        screen.stroke()
        screen.move(t  + 1 , y - 9 - (res * 5))
        screen.level(ui_index == 17 and 15 or 1)
        screen.line(t  + (38 - (cut * 2)), y - 9)
        screen.stroke()
  end
    

end

function ui.draw_mode(x, y, mode, index)
    set_brightness(4, index)
    screen.rect(x - 3, y - 15, 20, 17)
    screen.fill()
    screen.level(0)
    screen.move(x ,y - 8)
    screen.text('MODE')
    screen.stroke()
    screen.level(0)

  if mode == 1 then -- loop
      
      screen.move(x + 2, y)
      screen.line(x + 4, y)
      screen.move(x + 4, y + 1)
      screen.line(x + 7, y + 1)
      screen.move(x + 7, y)
      screen.line(x + 9, y)
      screen.move(x + 10, y - 1)
      screen.line(x + 10, y - 3)
      screen.move(x + 7, y - 3)
      screen.line(x + 9, y - 3)
      screen.move(x + 4, y - 4)
      screen.line(x + 7, y - 4)
      screen.move(x + 2, y - 3)
      screen.line(x + 4, y - 3)
      screen.move(x + 3, y - 2)
      screen.line(x + 3, y - 6)
      screen.move(x + 3, y - 2)
      screen.line(x + 6, y - 2)
      
    elseif mode == 2 then -- inf loop
      
      screen.move(x - 1, y)
      screen.line(x + 1, y)
      screen.move(x + 1, y + 1)
      screen.line(x + 4, y + 1)
      screen.move(x + 4, y)
      screen.line(x + 6, y)
      screen.move(x + 7, y - 1)
      screen.line(x + 7, y - 3)
      screen.move(x + 4, y - 3)
      screen.line(x + 6, y - 3)
      screen.move(x + 1, y - 4)
      screen.line(x + 4, y - 4)
      screen.move(x - 1, y - 3)
      screen.line(x + 1, y - 3)
      screen.move(x , y - 2)
      screen.line(x , y - 6)
      screen.move(x , y - 2)
      screen.line(x + 3, y - 2)
      
      screen.move(x + 8, y)
      screen.font_size(8)
      screen.font_face(1)
      screen.text('∞')
      screen.font_size(6)
      screen.font_face(25)
      
    elseif mode == 3 then -- gated
      
      screen.move(x + 4, y + 1)
      screen.line(x + 4, y - 6)
      screen.move(x + 4, y - 5 )
      screen.line(x + 6, y - 5)
      screen.move(x + 6, y + 1)
      screen.line(x + 6, y - 6)
      screen.move(x + 6, y + 1)
      screen.line(x + 10, y + 1)
    
    elseif mode == 1 then -- oneshot
    
      screen.move(x + 1, y - 2)
      screen.line(x + 10, y - 2)
      screen.move(x + 8, y - 5)
      screen.line(x + 11, y - 2)
      screen.move(x + 8, y  )
      screen.line(x + 11, y - 3)
      
    end
    screen.stroke()
end


function ui.draw_note(x, y, params_data, ui_index, count, lock)
  set_brightness(count and count or 2, ui_index)
  screen.rect(x,  y, 20, 17)
  screen.fill()

  local offset = 0
  if count then offset = 2 end
  
  screen.level(0)
  screen.rect(x + 6 - offset, y + 6, 3, 2)
  screen.rect(x + 7 - offset, y + 6, 3, 1)
  screen.rect(x + 9 - offset, y +2, 1, 4)
  screen.rect(x + 10 - offset, y + 3, 1, 1)
  screen.rect(x + 11 - offset, y + 4, 1, 1)
  screen.fill()
  
  local note_name
  if count then
    note_name = params_data['note_' .. count]
  else
    note_name = params_data.note
  end
  
  local oct = math.floor(note_name / 12 - 2) == 0 and '' or math.floor(note_name / 12 - 2)
  screen.level(0)
  if count then 
    screen.move(x + 12, y + 8)
    screen.text(count)
    screen.stroke()
  end
  
  local lvl = lock == true and 15 or 0 --

  screen.level(lvl)
  screen.move(x + 9, y + 15)
  screen.text_center(oct ..  music.note_num_to_name(note_name):gsub('♯', '#'))
  screen.stroke()
 
end

function ui.draw_pan(x, y, params_data, ui_index, menu_index, lock)
  set_brightness(menu_index, ui_index)
  screen.rect(x,  y, 20, 17)
  screen.fill()

  local offset = 0
  if count then offset = 2 end
  screen.level(0)
  screen.move(x + 9, y + 7)
  screen.text_center('PAN')
  
  local pan = params_data.pan * 5

  
  local lvl = lock == true and 15 or 0 --

  screen.move(x + 4, y + 13)
  screen.line(x + 15, y + 13)
  screen.stroke()
  screen.level(lvl)
  screen.rect(x + 9 + pan, y + 10, 1, 5)

  screen.fill()
 
end


function ui.tile(index, name, value, ui_index, lock)
  
  local x = index > 14 and (21 * index) - 314
          or (index == 13 or index == 14) and (21 * index) - 188
          or index > 6 and (21 * index) - 146
          or (21 * index) - 20
          
  local y = index > 14 and 44 or index > 6 and 26 or 8
  local x_ext =  index == 4 and 6 or index == 3 and 2 or 0
  
  
  set_brightness(index, ui_index)
  screen.rect(x , y,  20, 17)
  screen.fill()
  screen.level(0) 
  screen.move( x  + 10, y + 7)
  screen.text_center(name)
  screen.move( x  + 10,y + 15)
  
  local lvl = lock == true and 15 or 0 --
  screen.level(lvl)
  
  if (index == 3 or index == 4) and type(value) == 'number' then value = util.round(value / 10000, 0.1) end
  if type(value) == 'number' then value = util.round(value, value % 1 == 0 and 1 or 0.1) end
  if string.len(tostring(value)) > 4 then value = util.round(value, 1) end
  
  screen.text_center(value)
  screen.stroke()
  
end

local name_lookup = {
  ['SMP'] = 'sample',
  ['NOTE'] = 'note',
  ['STRT'] = 'start',
  ['END'] = 's_end',
  ['LFO1'] = 'freq_lfo1',
  ['LFO2'] = 'freq_lfo2',
  ['VOL'] = 'vol',
  ['PAN'] = 'pan',
  ['ENV'] = 'env',
  ['LFO1'] = 'amp_lfo1',
  ['LFO2'] = 'amp_lfo2',
  ['SR'] = 'sr',
  ['TYPE'] = 'ftype',
  ['LFO1'] = 'cut_lfo1',
  ['LFO2'] = 'cut_lfo2',
}


function ui.main_screen(params_data, data)
    local sr_types = { '8k', '16k', '26k', '32k', '48k' }
    local f_types = { 'LPF', 'HPF' } 
  
    local tile = { 
      {1, 'SMP',  params_data.sample },
      {2, 'NOTE', function(_, _, lock) ui.draw_note(22, 8, params_data, data.ui_index, false, lock) end },
      {3, 'STRT', params_data.start },
      {4, 'END',   params_data.s_end }, -- function() ui.draw_mode(67, 23, params_data.rev, data.ui_index) end },
      {5, 'FM1', params_data.freq_lfo1 },
      {6, 'FM2', params_data.freq_lfo2 },
      {7, 'VOL', params_data.vol },
      {8, 'PAN', function(_, _, lock) ui.draw_pan(22, 26, params_data, data.ui_index, 8, lock) end},--params_data.pan },
      {9, 'ENV', function(lock)  ui.draw_env(45, 42, 'AMP', params_data, data.ui_index) end },
      {13, 'AM1', params_data.amp_lfo1 },
      {14, 'AM2', params_data.amp_lfo2 },
      {15, 'SR', sr_types[params_data.sr] },
      {16, 'TYPE', f_types[params_data.ftype] },
      {17, 'FILTER', function(lock) ui.draw_filter(45, 60, params_data, data.ui_index) end },
      {19, 'CM1', params_data.cut_lfo1 },
      {20, 'CM2', params_data.cut_lfo2 },

}
   for k, v in pairs(tile) do
        
        local lock = false
        if params_data.default then
          if v[2] == 'SR' then
            lock = sr_types[params_data.default[name_lookup[v[2]]]] ~= v[3] and true or false
          elseif v[2] == 'TYPE' then
            lock = f_types[params_data.default[name_lookup[v[2]]]] ~= v[3] and true or false
          else
            lock = params_data.default[name_lookup[v[2]]] ~= params_data[name_lookup[v[2]]]  and true or false
          end
        end
        
        
      if v[3] and type(v[3]) == 'function' then
        v[3](v[1], v[2], lock)
      elseif v[3] then
        ui.tile(v[1], v[2], v[3], data.ui_index, lock or false)
      end
    end
end

local function draw_reel(x, y, reverse)
  local flutter = ui.tape.flutter
  local right = ui.reel.right
  local left = ui.reel.left
  
  local l = util.round(speed * 10)
  if l < 0 then
    l = math.abs(l) + 4
  elseif l >= 4 then
    l = 4
  elseif l == 0 then
    l = reverse and 5 or 1
  end
  screen.level(2)
  screen.line_width(1.2)
  
  local pos = { 1, 3, 5}
  
  for i = 1, 3 do
    screen.move((x + right[pos[i]].x) - 30, (y + right[pos[i]].y) - 20)
    screen.line((x + right[pos[i] + 1].x) - 30, (y + right[pos[i] + 1].y) - 20)
    screen.stroke()
    
    screen.move((x + left[pos[i]].x) +5, (y + left[pos[i]].y) - 20)
    screen.line((x + left[pos[i] + 1].x) +5, (y + left[pos[i] + 1].y) - 20)
    screen.stroke()
  end
  screen.line_width(1)
  --
  screen.level(2)
  screen.circle(x + 35, y + 5, 11)
  screen.stroke()
  screen.circle(x + 65, y + 5, 11)
  screen.stroke()
  
end


local function tile_x(x)
  return 21 * (x) + 1 
end

function ui.sampling(params_data, data, pos, len, active)
  local modes = {'ST', 'L+R', 'L', 'R'}
  local sources = {'EXT', 'INT' } 
  local src = sources[data.sampling.source]
  local mode = modes[data.sampling.mode] 
  local rec = data.sampling.rec and 'ON' or 'OFF'
  local play = data.sampling.play and 'ON' or 'OFF'
  
  set_brightness(-1, data.ui_index)
  
  screen.rect(tile_x(4), 8,  20, 17)
  screen.fill()
  screen.level(0) 
  screen.move( tile_x(4)  + 10, 8 + 7)
  screen.text_center('MODE')
  screen.move( tile_x(4)  + 10, 8 + 15)
  screen.text_center(mode)

  set_brightness(0, data.ui_index)
  screen.rect(tile_x(5) , 8,  20, 17)
  screen.fill()
  screen.level(0) 
  screen.move( tile_x(5)  + 10, 8 + 7)
  screen.text_center('SRC')
  screen.move( tile_x(5) + 10, 8 + 15)
  screen.text_center(src)


  set_brightness(1, data.ui_index)
  if data.sampling.rec then screen.level(15) end
  screen.rect( tile_x(0) , 26,  20, 17)
  screen.fill()
  

  screen.level(0) 
  
  screen.circle( tile_x(0)  + 10, 26 + 9, 4.5)
  if data.sampling.rec then
    screen.circle( tile_x(0)  + 10, 26 + 9, 5)
    screen.fill() 
  else 
    screen.circle( tile_x(0)  + 10, 26 + 9, 4.5)
    screen.stroke() 
  end


  set_brightness(2, data.ui_index)
  screen.rect( tile_x(1) , 26,  20, 17)
  screen.fill()
  screen.level(0) 
  
  screen.move(tile_x(1) + 7, 31)
  screen.line(tile_x(1) + 7 + 8, 31 + 8 * 0.5)
  screen.line(tile_x(1) + 7, 31 + 8)
  screen.close()
  if data.sampling.play then screen.fill() 
  else screen.stroke() end

  screen.line_width(1)


  set_brightness(3, data.ui_index)
  screen.rect( tile_x(2) , 26,  20, 17)
  screen.fill()
  screen.level(0) 
  
  screen.rect( tile_x(2) + 5, 26 + 3, 12, 12)
  screen.stroke()
  set_brightness(3, data.ui_index)
  
  screen.rect( tile_x(2) + 16, 26 + 2,1,1)
  screen.fill()

  screen.level(0)  
  screen.rect( tile_x(2) + 7, 26 + 3,8,4)
  screen.stroke()
  
  screen.rect( tile_x(2) + 11, 26 + 3,2,2)
  screen.fill()
  
  screen.move( tile_x(2) + 10, 26 + 13)
  screen.text_center(data.sampling.slot)
  
  set_brightness(4, data.ui_index)
  screen.rect( tile_x(0) , 44,  20, 17)
  screen.fill()
  screen.level(0) --- disp lock
  screen.move( tile_x(0)  + 10, 44 + 7)
  screen.text_center('STRT')
  screen.move( tile_x(0) + 10, 44 + 15)
  screen.text_center(data.sampling.start)

  set_brightness(5, data.ui_index)
  screen.rect( tile_x(1) , 44,  20, 17)
  screen.fill()
  screen.level(0) --- disp lock
  screen.move( tile_x(1)  + 10, 44 + 7)
  screen.text_center('END')
  screen.move( tile_x(1) + 10, 44 + 15)
  screen.text_center(util.round(len, 0.1))

  set_brightness(6, data.ui_index)
  screen.rect( tile_x(2) , 44,  20, 17)
  screen.fill()
  screen.level(0)
  
  screen.move( tile_x(2) + 10, 44 + 15)
  screen.rect(tile_x(2) + 7, 44 + 7, 8, 8)
  screen.rect(tile_x(2) + 6, 44 + 5, 10, 2)
  
  screen.stroke()

  screen.rect(tile_x(2) + 9, 44 + 3, 1, 1)
  screen.rect(tile_x(2) + 10, 44 + 2, 1, 1)
  screen.rect(tile_x(2) + 11, 44 + 3, 1, 1)
  
  
  screen.rect(tile_x(2) + 8, 44 + 8, 1, 5)
  screen.rect(tile_x(2) + 10, 44 + 8, 1, 5)
  screen.rect(tile_x(2) + 12, 44 + 8, 1, 5)
  
  screen.fill()
  
  set_brightness(6, data.ui_index)
  screen.rect(tile_x(2) + 6, 44 + 14, 1, 1)
  screen.rect(tile_x(2) + 14, 44 + 14, 1, 1)
  screen.rect(tile_x(2) + 5, 44 + 4, 1, 1)
  screen.rect(tile_x(2) + 15, 44 + 4, 1, 1)
  
  screen.fill()

  screen.level(2)
  screen.rect(1 , 8,  83, 17)
  
  screen.fill()
  screen.rect(65, 27, 61 , 34 )
  screen.stroke()
  screen.level(0)
  screen.move(3, 15)
  screen.text('L')
  screen.move(3, 23)
  screen.text('R')
  screen.stroke()
  screen.rect(8, 10, data.in_l, 5)
  screen.rect(8, 18, data.in_r, 5)
  screen.fill()
  screen.level(2)
  screen.stroke()
  
  if active then update_reel() end
  draw_reel(45, 38)
  screen.stroke()
  
  screen.level(5)
  screen.rect(65 , 58, 1+ util.clamp(pos, 0, 59), 2)
  screen.fill()
  screen.level(0)
  screen.rect(65 , 58, util.clamp(data.sampling.start, 0, 59), 2)
  
  screen.fill()

  
end


return ui