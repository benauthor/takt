-- takt v2.2
-- @its_your_bedtime
--
-- parameter locking sequencer
--

local eli = include('lib/eli')
local sampler = include('lib/sampler')
local browser = include('lib/browser')
local timber = include('lib/timber_takt')
local takt_utils = include('lib/_utils')
local ui = include('lib/ui')
local linn = include('lib/linn')
local beatclock = require 'beatclock'
local music = require 'musicutil'
local fileselect = require('fileselect')
local textentry = require('textentry')
--
local midi_clock
local midi_out_devices = {}
local REC_CC = 38
--
local blink = 1
local ALT, SHIFT, MOD, PATTERN_REC, K1_HELD, K3_HELD, ptn_copy, ptn_change_pending = false, false, false, false, false, false, false, false
local redraw_params = {}
local copy = { false, false }
local freq_map = controlspec.WIDEFREQ
local amp_map = controlspec.DB
      amp_map.maxval = 16
local send_map = controlspec.new(-48, 0, 'db', 0, -48, "dB")--.DB
local sidechain_map = controlspec.new(-99, 0, 'db', 0, -99, "dB")--.DB
local threshold_map  = controlspec.new(0.01, 1, "exp", 0.001, 0.1, "")
local time_map = controlspec.new(0.0001, 5, 'exp', 0, 0.1, 's')

--
local ei = eli.Instrument.new()
local g = ei.grid
-- every keypress pings the screen, resetting the screensaver timer
ei.before_key = function(x, y, z) screen.ping() end

local views = {}
views.steps = ei:new_view("steps")
views.midi = ei:new_view("midi")
views.notes = ei:new_view("notes")
views.sampling = ei:new_view("sampling")
views.patterns = ei:new_view("patterns")

-- forward-declared so the controls closures bind to these locals (assigned later)
local controlkeydownfns, controlkeyupfns

local controls = eli.Box.new(16, 1)
controls.keydown = function(box, seq)
  if controlkeydownfns[seq] then
    controlkeydownfns[seq]()
  else
      print("unmapped control keydown")
  end
end
controls.keyup = function(box, seq)
  if controlkeyupfns[seq] then
    controlkeyupfns[seq]()
  else
    print("unmapped control keyup")
  end

end

for _, v in pairs(views) do
  v:add_box(controls, 1, 8)
end



-- `tr` is a track index 1..14:
--   1..7  -- engine tracks; trigger the timber sampler engine
--   8..14 -- midi tracks; send note/cc to the configured midi device
-- Per-track state lives on `data[data.pattern][tr]` (substep flags + per-step
-- params, with the track-default params keyed by the *string* `tostring(tr)`)
-- and on `data[data.pattern].track.{div,mute,pos,start,len,cycle}[tr]`.
-- The grid is only 7 rows tall, so the steps and midi views show one range at
-- a time; `data.selected.track` (also a `tr` value) decides which.
local function is_engine(tr) return tr < 8 end
local function is_midi(tr)   return tr > 7 end

local data = { pattern = 1, ui_index = 1, selected = { track = 1, step = false }, metaseq = { from = 1, to = 1, div = 1}, [1] = takt_utils.make_default_pattern() }
local choke = { 1, 2, 3, 4, 5, 6, 7, {},{},{},{},{},{},{}, ['8rt'] = {},['9rt'] = {},['10rt'] = {},['11rt'] = {}, ['12rt'] = {}, ['13rt'] = {},['14rt'] = {} }
local dividers  = { [1] = 16, [2] = 8, [3] = 4, [4] = 3, [5] = 2, [6] = 1.5, [7] = 1,}
local midi_dividers  = { [1] = 16, [2] = 8, [3] = 4, [4] = 3, [5] = 1, [6] = 0.666, [7] = 0.545,}
local sampling_actions = {[-1] = function()end,[0]=function()end, [1] = sampler.rec, [2] = sampler.play, [3] = sampler.save_and_load, [4] = sampler.clear, [5] = sampler.play, [6] = sampler.play }
local lfo_1, lfo_2 = {[5] = true, [13] = true,  }, {[6] = true, [14] = true,  }

-- `data.ui_index` is the screen navigation cursor — which tile/parameter is
-- focused for editing with encoder 3. It means different things per view,
-- indexed against per-view param tables:
--   steps    -> step_params       (1..20)  sample, note, start, end, fm1/2,
--                                          vol, pan, adsr, am1/2, qual, mode,
--                                          filter freq/res, delay, reverb
--   midi     -> midi_step_params  (1..18)  note, vel, len, ch, dev, pgm,
--                                          + 6 cc values, 6 cc numbers
--   patterns -> params_fx         (1..18)  comp, reverb, delay, lfo 1/2
--   sampling -> sampling_params   (-1..6)  mode, source, save, rec, play,
--                                          clear, start, length
-- Negative indices flip to track-level / global params:
--   ui_index < 1 + K1 not held -> trig_params  (-3..0:  div, rule, retrig, offset)
--   ui_index < 1 + K1 held     -> track_params (-6..-1: ptn, track-step, bpm,
--                                                       scale, midi sync, sidechain)
-- The dispatcher in `steps_enc3` picks the right table at runtime.
--
-- `last_index` is a stash for the swap that happens when entering sampling /
-- patterns views: their index ranges don't overlap with the step views, so
-- `set_view` saves the current ui_index here, resets to 1, and restores on
-- the way back to a step-grid view.
local last_index = 1
local last_engine_track, last_midi_track = 1, 8


local param_ids = {
  ['quality'] = "quality", ['start_frame'] = "start_frame", ['end_frame'] = "end_frame", ['loop_start_frame'] = "loop_start_frame", ['loop_end_frame'] = "loop_end_frame",
  ['freq_mod_lfo_1'] = "freq_mod_lfo_1", ['play_mode'] = 'play_mode', ['detune_cents'] = 'detune_cents',
  ['freq_mod_lfo_2'] = "freq_mod_lfo_2", ['filter_type'] = "filter_type", ['filter_freq'] = "filter_freq", ['filter_resonance'] = "filter_resonance",
  ['filter_freq_mod_lfo_1'] = "filter_freq_mod_lfo_1", ['filter_freq_mod_lfo_2'] = "filter_freq_mod_lfo_2", ['pan'] = "pan", ['amp'] = "amp",
  ['amp_mod_lfo_1'] = "amp_mod_lfo_1", ['amp_mod_lfo_2'] = "amp_mod_lfo_2", ['amp_env_attack'] = "amp_env_attack", ['amp_env_decay'] = "amp_env_decay",
  ['amp_env_sustain'] = "amp_env_sustain", ['amp_env_release'] = "amp_env_release", ['reverb_send'] = "reverb_send", ["delay_send"] = 'delay_send', ['sidechain_send'] = 'sidechain_send'

}

local rules = {
  [0] =  { 'OFF', function() return true end },
  [1] =  { '10%', function() return 10 >= math.random(100) and true or false end },
  [2] =  { '20%', function() return 20 >= math.random(100) and true or false end },
  [3] =  { '30%', function() return 30 >= math.random(100) and true or false end },
  [4] =  { '50%', function() return 50 >= math.random(100) and true or false end },
  [5] =  { '60%', function() return 60 >= math.random(100) and true or false end },
  [6] =  { '70%', function() return 70 >= math.random(100) and true or false end },
  [7] =  { '90%', function() return 90 >= math.random(100) and true or false end },
  [8] =  {'/ 2', function(tr, step) return data[data.pattern].track.cycle[tr] % 2 == 0 and true or false  end },
  [9] =  {'/ 3', function(tr, step) return data[data.pattern].track.cycle[tr] % 3 == 0 and true or false  end },
  [10] = {'/ 4', function(tr, step) return data[data.pattern].track.cycle[tr] % 4 == 0 and true or false  end },
  [11] = {'/ 5', function(tr, step) return data[data.pattern].track.cycle[tr] % 5 == 0 and true or false  end },
  [12] = {'/ 6', function(tr, step) return data[data.pattern].track.cycle[tr] % 6 == 0 and true or false  end },
  [13] = {'/ 7', function(tr, step) return data[data.pattern].track.cycle[tr] % 7 == 0 and true or false  end },
  [14] = {'/ 8', function(tr, step) return data[data.pattern].track.cycle[tr] % 8 == 0 and true or false  end },
  [15] = {'RND NOTE', function(tr, step)
    data[data.pattern][tr].params[step].note = math.random(24,120) return true end },
  [16] = {'+- NOTE', function(tr, step)
    data[data.pattern][tr].params[step].note = util.clamp(data[data.pattern][tr].params[step].note + math.random(-20,20),24,120) return true end },
  [17] = {'RND START', function(tr, step)
    if is_engine(tr) then
      local max_frame = params:lookup_param("end_frame_" .. data[data.pattern][tr].params[step].sample).controlspec.maxval
      data[data.pattern][tr].params[step].start_frame = math.random(0, max_frame)
      data[data.pattern][tr].params[step].loop_start = math.random(0, max_frame)
      end
    return true end },
  [18] = {'RND ST-EN', function(tr, step)
    if is_engine(tr) then
      local max_frame = params:lookup_param("end_frame_" .. data[data.pattern][tr].params[step].sample).controlspec.maxval
      data[data.pattern][tr].params[step].start_frame = math.random(0, max_frame)
      data[data.pattern][tr].params[step].end_frame = math.random(0, max_frame)
      data[data.pattern][tr].params[step].loop_start_frame = data[data.pattern][tr].params[step].start_frame
      data[data.pattern][tr].params[step].loop_end_frame = data[data.pattern][tr].params[step].end_frame
    end
    return true end },
}

--- utils, load/save

local function to_id(x, y)
  return  x + ((y - 1) * 16)
end

local function pattern_exists(x, y)
  return  data[x + ((y - 1) * 16)] ~= nil and true or false
end

local function set_enc_res(fine, coarse)
  return K3_HELD and coarse or fine
end

local function reset_positions()
  for i = 1, 14 do
    data[data.pattern].track.pos[i] = 0
  end
end

local prev_mix_val = -1
local prev_level_val = 0

local function comp_shut(state)
    if state then
        print('run')
        params:set('takt_comp_mix', prev_mix_val)
        params:set('takt_comp_level', prev_level_val)
    elseif not state then
        print('stop')
        prev_mix_val = params:get('takt_comp_mix')
        prev_level_val = params:get('takt_comp_level')
        params:set('takt_comp_mix', -1)
        params:set('takt_comp_level', -99)
    end

end

local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, getmetatable(orig))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

local function load_project(pth)

  sequencer_metro:stop()
  midi_clock:stop()
  engine.noteOffAll()
  redraw_metro:stop()
  comp_shut(sequencer_metro.is_running)

  if string.find(pth, '.tkt') ~= nil then
    local saved = tab.load(pth)
    if saved ~= nil then
      print("data found")
      for k,v in pairs(saved[2]) do
        data[k] = v
      end
      -- re-init metatables (`data` is sparse — pattern slots can be deleted —
      -- so iterate via pairs and skip the non-numeric keys like `pattern`).
      for t in pairs(data) do
        if type(t) == "number" then
          for l = 1, 14 do
            for k = 1, 256 do
              data[t][l].params[k] = saved[2][t][l].params[k]
              setmetatable(data[t][l].params[k], {__index = data[t][l].params[tostring(l)]})
            end
          end
        end
      end

        if saved[1] then params:read(norns.state.data .. saved[1] .. ".pset") end
        reset_positions()
    else
        print("no data")
    end
  end
  redraw_metro:start()
end

local function save_project(txt)
  sequencer_metro:stop()
  midi_clock:stop()
  redraw_metro:stop()
  engine.noteOffAll()
  comp_shut(sequencer_metro.is_running)
  if txt then
    tab.save({ txt, data }, norns.state.data .. txt ..".tkt")
    params:write( norns.state.data .. txt .. ".pset")
  else
    print("save cancel")
  end
  redraw_metro:start()
end

-- views

local function set_view(x)
  if sampler.rec then return end
  if ei.active == views.notes and views[x] ~= views.notes then
    PATTERN_REC = false
  end
  ei:switch_to(x)
  if ei.active == views.sampling or ei.active == views.patterns then
    last_index = data.ui_index
    data.ui_index = 1
    ui.start_polls()
  else
    data.ui_index = last_index
    ui.stop_polls()
  end
end

--- steps

local function get_step(x)
  return (x * 16) - 15
end

local function get_params(tr, step, lock)
    if not step then
      return data[data.pattern][tr].params[tostring(tr)]
    else
      local res = data[data.pattern][tr].params[step]
      if lock then
        res.default = data[data.pattern][tr].params[tostring(tr)]
      end
      return data[data.pattern][tr].params[step] -- res
    end
end

local function set_locks(step_param)
    for k, v in pairs(step_param) do
      if param_ids[k] ~= nil then
        params:set(k  .. '_' .. step_param.sample, v)
      end
    end
end
local function set_cc(step_param)
  for i = 1, 6 do
    local cc = step_param['cc_' .. i]
    local val = step_param['cc_' .. i .. '_val']
    if val > -1 then
      midi_out_devices[step_param.device]:cc(cc, val, step_param.channel)
    end
  end
end

local function move_params(tr, src, dst )
  local s = data[data.pattern][tr].params[src]
  data[data.pattern][tr].params[dst] = s
end

local function clear_substeps(tr, s )
  for l = s, s + 15 do
    data[data.pattern][tr][l] = 0
    data[data.pattern][tr].params[l] = {}
    setmetatable(data[data.pattern][tr].params[l], {__index =  data[data.pattern][tr].params[tostring(tr)]})
  end
end

local function move_substep(tr, step, t)
   for s = step, step + 15 do
    data[data.pattern][tr][s] = (s == t) and 1 or 0
    move_params(tr, step, (s == t) and s or step)
   end
end

local function make_retrigs(tr, step, t)
    local t = 16 - t
    local offset = data[data.pattern][tr].params[step].offset
    local params = data[data.pattern][tr].params[step]
    local st = step + 1

    for s = st + offset, (st + 14) - offset do
      if t == 16 then
        data[data.pattern][tr][s] = 0
      elseif s % t == 1 then
        data[data.pattern][tr][s] = s - offset == st and 1 or 0
      else
        data[data.pattern][tr][s] = ((s + offset) % t == 0) and 1 or 0
        data[data.pattern][tr].params[s] = params
      end
    end
end

local function have_substeps(tr, step)
    local st = get_step(step)
    for s = st, st + 15 do
      if data[data.pattern][tr][s] == 1 then
        return s
      end
    end
end

local function place_note(tr, step, note)
  data[data.pattern][tr][step] = 1
  data[data.pattern][tr].params[step].lock = 1
  data[data.pattern][tr].params[step].note = note
end

--- tracks

local function is_lock()
  return data.selected.step or tostring(data.selected.track)
end

local function tr_change(tr)
  data.selected.track = tr
  if is_engine(tr) then last_engine_track = tr end
  if is_midi(tr) then last_midi_track = tr end
  redraw_params[1] = get_params(tr)
  redraw_params[2] = redraw_params[1]
end

local function get_sample()
  return data[data.pattern][data.selected.track].params[is_lock()].sample
end

local function sample_not_loaded(n)
  return params:get('sample_' .. n) == '-'
end

local function sync_tracks(tr)
    for i=1, 14 do
      if data[data.pattern].track.div[i] == data[data.pattern].track.div[tr] then
        data[data.pattern].track.pos[i] = data[data.pattern].track.pos[tr]
      end
    end
end

local function mute_track(tr)

  data[data.pattern].track.mute[tr] = not data[data.pattern].track.mute[tr]
  if data[data.pattern].track.mute[tr] and is_engine(tr) then
    engine.noteOff(choke[tr])
  else
    print('midi mute')
  end

end

local function set_div(tr, div)
  data[data.pattern].track.div[tr] = div
  data[data.pattern][tr].params[tostring(tr)].div = div
  sync_tracks(tr)
end

local function set_bpm(n)
    data[data.pattern].bpm = n
    sequencer_metro.time = 60 / (data[data.pattern].bpm * 2)  / 16 --[[ppqn]] / 4
    midi_clock:bpm_change( util.round(data[data.pattern].bpm / midi_dividers[util.clamp(data[data.pattern].sync_div, 1, 7)]))
end

local function set_loop(tr, start, len)
    data[data.pattern].track.start[tr] = get_step(start)
    data[data.pattern].track.len[tr] = get_step(len) + 15
    sync_tracks(tr)
end

local function get_tr_start( tr )
  return math.ceil(data[data.pattern].track.start[tr] / 16)
end

local function get_tr_len( tr )
  return math.ceil(data[data.pattern].track.len[tr] / 16)
end

local function get_sample_len(tr, s)
  local maxval = params:lookup_param("end_frame_" .. data[data.pattern][tr].params[s].sample).controlspec.maxval
  data[data.pattern][tr].params[s].end_frame = maxval
  data[data.pattern][tr].params[s].loop_end_frame = maxval
end

local function get_sample_start(tr, s)
  local minval = params:lookup_param("start_frame_" .. data[data.pattern][tr].params[s].sample).controlspec.minval
  data[data.pattern][tr].params[s].start_frame = minval
  data[data.pattern][tr].params[s].loop_start_frame = minval
end
--- copy / settings

local function copy_step(src, dst)
    for i = 0, 15 do
      data[data.pattern][dst[1]][get_step(dst[2]) + i] = data[data.pattern][src[1]][get_step(src[2]) + i]
      data[data.pattern][dst[1]].params[get_step(dst[2]) + i] = deepcopy(data[data.pattern][src[1]].params[get_step(src[2]) + i])
    end
end

local function copy_pattern(src, dst)
    data[dst] = deepcopy(data[src])
end

local function change_filter_type()
  local tr = data.selected.track
  local p = is_lock()
  p = type(p) == 'string' and p or get_step(p)
  local ft = data[data.pattern][tr].params[p].filter_type
  data[data.pattern][tr].params[p].filter_type = (ft % 2) + 1
end

local function choke_group(tr, sample)
  if sample == choke[tr] then
      engine.noteOff(tr)
  end
end

local function kill_all_midi()
  for id = 1, 4 do
    for ch = 1, 16 do
      for note = 0, 127 do
         midi_out_devices[id]:note_off(note, 0, ch)
      end
    end
  end
end

local function notes_off_midi()
  for i = 8, 14 do
      if choke[i][6] then
        midi_out_devices[choke[i][1]]:note_off(choke[i][2], choke[i][3], choke[i][4])
      end
  end
end

-- seq
local m_div = function(div) return  div == 1 and 2 or div^2 end

local function change_pattern(pt)
  if data[pt] == nil then
    data[pt] = takt_utils.make_default_pattern()
  end
    data.pattern = pt
end

local function metaseq(stage)
    if data[data.pattern].track.pos[1] == data[data.pattern].track.len[1] - 1 then

        if ptn_change_pending then
          change_pattern(ptn_change_pending)
          ptn_change_pending = false
        end

      if (data.metaseq.to and data.metaseq.from) then
          change_pattern(data.pattern < data.metaseq.to and data.pattern + 1 or data.metaseq.from)
          set_bpm(data[data.pattern].bpm)
      end
    end
end

local function advance_step(tr, counter)
  local start = data[data.pattern].track.start[tr]
  local len = data[data.pattern].track.len[tr]
  data[data.pattern].track.pos[tr] = util.clamp((data[data.pattern].track.pos[tr] + 1) % (len ), start, len) -- voice pos
  data[data.pattern].track.cycle[tr] = counter % 256 == 0 and data[data.pattern].track.cycle[tr] + 1 or data[data.pattern].track.cycle[tr]  --data[data.pattern].track.cycle[tr]
end

local function seqrun(counter)
  for tr = 1, 14 do

      local div = data[data.pattern].track.div[tr]

      if (div ~= 6 and counter % dividers[div] == 0)
      or (div == 6 and counter % dividers[div] >= 0.5) then

        advance_step(tr, counter)

        local mute = data[data.pattern].track.mute[tr]
        local pos = data[data.pattern].track.pos[tr]
        local trig = data[data.pattern][tr][pos]

        if is_midi(tr) and choke[tr][6] then
          if pos > choke[tr][5] + choke[tr][6] then
            midi_out_devices[choke[tr][1]]:note_off(choke[tr][2], choke[tr][3], choke[tr][4])
          end
        end

        if trig == 1 and not mute then

          set_locks(data[data.pattern][tr].params[tostring(tr)])

          local step_param = get_params(tr, pos, true)

          data[data.pattern].track.div[tr] = step_param.div ~= data[data.pattern].track.div[tr] and step_param.div or data[data.pattern].track.div[tr]

          if rules[step_param.rule][2](tr, pos) then

            step_param = step_param.lock ~= 1 and get_params(tr) or step_param

            if tr == data.selected.track then
              redraw_params[1] = step_param
              redraw_params[2] = step_param
            end

            if is_engine(tr) then

              set_locks(step_param)
              choke_group(tr, step_param.sample)
              engine.noteOn(tr, music.note_num_to_freq(step_param.note), 1, step_param.sample)
              choke[tr] = step_param.sample

            else

              set_cc(step_param)

              if step_param.program_change >= 0 then
                midi_out_devices[step_param.device]:program_change(step_param.program_change, step_param.channel)
              end

              midi_out_devices[step_param.device]:note_on( step_param.note, step_param.velocity, step_param.channel )
              choke[tr] = { step_param.device, step_param.note, step_param.velocity, step_param.channel, pos, step_param.length}
            end
          end
       end
    end
  end

end

local function midi_event(d)

  local msg = midi.to_msg(d)
  local tr = data.selected.track

  local pos = data[data.pattern].track.pos[tr]

  -- REC TOGGLE
  if msg.cc == REC_CC and msg.val == 127 then
    PATTERN_REC = not PATTERN_REC
  -- Note off
  elseif msg.type == "note_off" then
    --engine.noteOff(tr)
  -- Note on
  elseif msg.type == "note_on" then
    if ei.active ~= views.sampling then
      if is_engine(tr) then
        engine.noteOff(tr)
        engine.noteOn(tr, music.note_num_to_freq(msg.note), msg.vel / 127, data[data.pattern][tr].params[tostring(tr)].sample)
      end
      if sequencer_metro.is_running and PATTERN_REC then
        place_note(tr, pos, msg.note)
      end
    end
  end

end

---

-- Helpers for the param-edit tables below. Most entries just want to nudge a
-- single field on the active step's params and clamp it; a handful (volume,
-- sends, filter freq) read/write through a controlspec-shaped `map` so the
-- delta can be applied in normalized 0..1 space rather than the raw value's
-- own scale.
local function bump(tr, s, name, d, min, max, scale)
  local p = data[data.pattern][tr].params[s]
  p[name] = util.clamp(p[name] + d * (scale or 1), min, max)
end

local function bump_mapped(tr, s, name, map, d, scale, min, max)
  local p = data[data.pattern][tr].params[s]
  local v = util.clamp(map:unmap(p[name]) + d * (scale or 1), min or 0, max or 1)
  p[name] = map:map(v)
end

local track_params = {
  [-6] = function(tr, s, d) -- ptn
      local pt = (util.clamp(data.pattern + d, 1, 64))
      change_pattern(pt)
      data.metaseq.from = false --data.pattern
      data.metaseq.to = false --data.pattern
  end,
  [-5] = function(tr, s, d) -- rnd
        local offset = ei.active == views.midi and 7 or 0
        data.selected.track = util.clamp(data.selected.track + d, 1 + offset, 7 + offset)
        tr_change(data.selected.track)
  end,
  [-4] = function(tr, s, d) -- global bpm
      set_bpm(util.clamp(data[data.pattern].bpm + d, 1, 999))
  end,
  [-3] = function(tr, s, d) -- track scale

      local div = data[data.pattern].track.div[tr]
      data[data.pattern].track.div[tr] = util.clamp(data[data.pattern].track.div[tr] + d, 1, 7)
      data[data.pattern][tr].params[tostring(tr)].div = data[data.pattern].track.div[tr]
      if div ~= data[data.pattern].track.div[tr] then sync_tracks(tr) end

  end,
  [-2] = function(tr, s, d) -- midi out bpm scale
    data[data.pattern].sync_div = util.clamp(data[data.pattern].sync_div + d, 0, 7)
    if data[data.pattern].sync_div == 0 then midi_clock.send = false else midi_clock.send = true end
end,
[-1] = function(tr, s, d) -- sidechain
     data[data.pattern][tr].params[tostring(tr)].sidechain_send = util.clamp(data[data.pattern][tr].params[tostring(tr)].sidechain_send + d, -99, 0 )
end,
}


local midi_step_params = {
  [1]  = function(tr, s, d) bump(tr, s, 'note',           d,  25, 127) end,
  [2]  = function(tr, s, d) bump(tr, s, 'velocity',       d,   0, 127) end,
  [3]  = function(tr, s, d) bump(tr, s, 'length',         d,   1, 256) end,
  [4]  = function(tr, s, d) bump(tr, s, 'channel',        d,   1,  16) end,
  [5]  = function(tr, s, d) bump(tr, s, 'device',         d,   1,   4) end,
  [6]  = function(tr, s, d) bump(tr, s, 'program_change', d,  -1, 127) end,
  [7]  = function(tr, s, d) bump(tr, s, 'cc_1_val',       d,  -1, 127) end,
  [8]  = function(tr, s, d) bump(tr, s, 'cc_2_val',       d,  -1, 127) end,
  [9]  = function(tr, s, d) bump(tr, s, 'cc_3_val',       d,  -1, 127) end,
  [10] = function(tr, s, d) bump(tr, s, 'cc_4_val',       d,  -1, 127) end,
  [11] = function(tr, s, d) bump(tr, s, 'cc_5_val',       d,  -1, 127) end,
  [12] = function(tr, s, d) bump(tr, s, 'cc_6_val',       d,  -1, 127) end,
  [13] = function(tr, s, d) bump(tr, s, 'cc_1',           d,   1, 127) end,
  [14] = function(tr, s, d) bump(tr, s, 'cc_2',           d,   1, 127) end,
  [15] = function(tr, s, d) bump(tr, s, 'cc_3',           d,   1, 127) end,
  [16] = function(tr, s, d) bump(tr, s, 'cc_4',           d,   1, 127) end,
  [17] = function(tr, s, d) bump(tr, s, 'cc_5',           d,   1, 127) end,
  [18] = function(tr, s, d) bump(tr, s, 'cc_6',           d,   1, 127) end,
}

local step_params = {
  [1]  = function(tr, s, d) bump(tr, s, 'sample', d, 1, 99) end,
  [2]  = function(tr, s, d)
    if K3_HELD then
      bump(tr, s, 'detune_cents', d, -100, 100)
    else
      bump(tr, s, 'note', d, 25, 127)
    end
  end,
  [3]  = function(tr, s, d) -- start: scrub through the sample's start_frame controlspec in 0..1 space
    local p = data[data.pattern][tr].params[s]
    local pspec = params:lookup_param("start_frame_" .. p.sample).controlspec
    local v = util.clamp(pspec:unmap(p.start_frame) + (d / set_enc_res(200, 1000)), 0, 1)
    p.start_frame = pspec:map(v)
    p.loop_start_frame = pspec:map(v)
  end,
  [4]  = function(tr, s, d) -- len: same idea against end_frame
    local p = data[data.pattern][tr].params[s]
    local pspec = params:lookup_param("end_frame_" .. p.sample).controlspec
    local v = util.clamp(pspec:unmap(p.end_frame) + (d / set_enc_res(200, 1000)), 0, 1)
    p.end_frame = pspec:map(v)
    p.loop_end_frame = pspec:map(v)
  end,
  [5]  = function(tr, s, d) bump(tr, s, 'freq_mod_lfo_1',        d, 0, 1, 1/100) end,
  [6]  = function(tr, s, d) bump(tr, s, 'freq_mod_lfo_2',        d, 0, 1, 1/100) end,
  [7]  = function(tr, s, d) bump_mapped(tr, s, 'amp',         amp_map,  d, 1/200) end,
  [8]  = function(tr, s, d) bump(tr, s, 'pan',                   d, -1, 1, 1/20) end,
  [9]  = function(tr, s, d) bump(tr, s, 'amp_env_attack',        d, 0,    5, 1/50) end,
  [10] = function(tr, s, d) bump(tr, s, 'amp_env_decay',         d, 0.01, 5, 1/50) end,
  [11] = function(tr, s, d) bump(tr, s, 'amp_env_sustain',       d, 0,    1, 1/50) end,
  [12] = function(tr, s, d) bump(tr, s, 'amp_env_release',       d, 0,   10, 1/10) end,
  [13] = function(tr, s, d) bump(tr, s, 'amp_mod_lfo_1',         d, 0, 1, 1/100) end,
  [14] = function(tr, s, d) bump(tr, s, 'filter_freq_mod_lfo_2', d, 0, 1, 1/100) end,
  [15] = function(tr, s, d) bump(tr, s, 'quality',               d, 1, 5) end,
  [16] = function(tr, s, d) bump(tr, s, 'play_mode',             d, 1, 4) end,
  [17] = function(tr, s, d) bump_mapped(tr, s, 'filter_freq', freq_map, d, 1/200, 0.1, 1) end,
  [18] = function(tr, s, d) bump(tr, s, 'filter_resonance',      d, 0, 1, 1/20) end,
  [19] = function(tr, s, d) bump_mapped(tr, s, 'delay_send',  send_map, d, 1/200) end,
  [20] = function(tr, s, d) bump_mapped(tr, s, 'reverb_send', send_map, d, 1/200) end,
}

local sampling_params = {
  [-1] = function(d)sampler.mode = util.clamp(sampler.mode + d, 1, 4) sampler.set_mode() end,
  [0] = function(d) sampler.source = util.clamp(sampler.source + d, 1, 2) sampler.set_source() end,
  [3] = function(d) sampler.slot = util.clamp(sampler.slot + d, 1, 100) end,
  [5] = function(d) sampler.start = util.clamp(sampler.start + d / (20), 0, sampler.length) sampler.set_start(sampler.start) end,
  [6] = function(d) sampler.length = util.clamp(sampler.length + d / (20), sampler.start, sampler.rec_length) end,
  [4] = function(d) end, --play
  [1] = function(d) end, --save
  [2] = function(d) end, --clear
  [7] = function(d) end, --clear
}

local trig_params = {
  [-3] = function(tr, s, d) --
    data[data.pattern][tr].params[s].div = util.clamp(data[data.pattern][tr].params[s].div + d, 1, 7)
  end,
  [-2] = function(tr, s, d) -- rule
      data[data.pattern][tr].params[s].rule = util.clamp(data[data.pattern][tr].params[s].rule + d, 0, #rules)
  end,
  [-1] = function(tr, s, d) -- retrig
      data[data.pattern][tr].params[s].retrig = util.clamp(data[data.pattern][tr].params[s].retrig + d, 0, 15)
      make_retrigs(tr, s, data[data.pattern][tr].params[s].retrig)
  end,
  [0] = function(tr, s, d) -- offset
      data[data.pattern][tr].params[s + data[data.pattern][tr].params[s].offset].offset = util.clamp(data[data.pattern][tr].params[s].offset + d, 0, 15)
      move_substep(tr, s, s + data[data.pattern][tr].params[s].offset)
      data[data.pattern][tr].params[s].retrig = 0
  end,
}

controlkeydownfns = {
  [1] = function() -- start / stop,
    if sequencer_metro.is_running then
      sequencer_metro:stop()
      midi_clock:stop()
      notes_off_midi()
    else
      sequencer_metro:start()
      midi_clock:start()
    end
    if MOD then
      engine.noteOffAll()
      reset_positions()
      kill_all_midi()
    end
    comp_shut(sequencer_metro.is_running)
  end,
  [3] = function() -- pattern record toggle
    -- TODO notes view will have a different control box; for now PATTERN_REC
    -- toggles whenever the sequencer is running, regardless of active view.
    if sequencer_metro.is_running then
      PATTERN_REC = not PATTERN_REC
    end
  end,
  [5] = function() -- steps view
    set_view('steps')
    tr_change(last_engine_track)
  end,
  [6] = function() -- steps midi view
    set_view('midi')
    tr_change(last_midi_track)
  end,
  [8] = function()
    set_view('notes')
  end,
  [10] = function()
    set_view('sampling')
  end,
  [11] = function()
    set_view('patterns')
  end,
  [13] = function()
    MOD = true
  end,
  [15] = function()
    ALT = true
  end,
  [16] = function()
    SHIFT = true
  end,
}

controlkeyupfns = {
  [13] = function(z)
    MOD = false
    copy = { false, false }
  end,
  [15] = function(z)
    ALT = false
  end,
  [16] = function(z)
    SHIFT = false
  end,
}

-- controls row 8 LEDs: transport state, view selection, modifiers.
-- (controls box itself is created up top so it can be added to all views,
-- but its tick callback needs `data`/`views`/`sequencer_metro` etc. in scope.)
controls.floor = 0
controls.tick = function(box)
  local glow = util.clamp(blink, 5, 15)
  local in_notes = ei.active == views.notes
  box:all(0)
  box:led(1, sequencer_metro.is_running and 15 or 6)
  box:led(3, (in_notes and PATTERN_REC) and glow
              or in_notes and 6
              or 0)
  box:led(5, (in_notes and is_engine(data.selected.track) or ei.active == views.steps) and 15 or 6)
  box:led(6, (in_notes and is_midi(data.selected.track) or ei.active == views.midi) and 15 or 6)
  box:led(8, in_notes and 15 or 6)
  box:led(10, ei.active == views.sampling and 15 or 6)
  box:led(11, ei.active == views.patterns and 15 or 6)
  box:led(13, MOD and glow or 6)
  box:led(15, ALT and glow or 6)
  box:led(16, SHIFT and glow or 6)
end

-- patterns view: 16x4 pattern grid at row 1, 16x1 metaseq-div selector at row 6
do
  local patterns_grid = eli.Box.new(16, 4)
  local metaseq_div = eli.Box.new(16, 1)
  views.patterns:add_box(patterns_grid, 1, 1)
  views.patterns:add_box(metaseq_div, 1, 6)

  local hold_count = 0
  local first_id

  patterns_grid.keydown = function(box, seq)
    hold_count = hold_count + 1
    local id = seq -- box seq matches to_id(x, y) for a 16-wide box at origin
    if SHIFT then
      if data.pattern ~= id then
        data[id] = nil
      end
    elseif MOD then
      if not ptn_copy then
        ptn_copy = id
      else
        copy_pattern(ptn_copy, id)
      end
    else
      if hold_count == 1 then
        first_id = id
        if ptn_change_pending then
          change_pattern(ptn_change_pending)
          ptn_change_pending = false
        else
          ptn_change_pending = id
        end
        data.metaseq.from = false
        data.metaseq.to = false
        ptn_copy = false
      elseif hold_count == 2 then
        data.metaseq.from = first_id
        data.metaseq.to = id
      end
    end
  end

  patterns_grid.keyup = function(box, seq)
    hold_count = math.max(0, hold_count - 1)
  end

  metaseq_div.keydown = function(box, seq)
    data.metaseq.div = seq
  end

  patterns_grid.tick = function(box)
    local glow = util.clamp(blink, 5, 14)
    local from, to = data.metaseq.from, data.metaseq.to
    for y = 1, 4 do
      for x = 1, 16 do
        local id = to_id(x, y)
        local seq = (y - 1) * 16 + x
        local level =
          (id == ptn_change_pending and sequencer_metro.is_running and glow)
          or ((from and to) and id == data.pattern and glow)
          or (id >= (from or data.pattern) and id <= (to or data.pattern) and 9)
          or (data.pattern == id and 15)
          or (pattern_exists(x, y) and 6)
          or 2
        box:led(seq, level)
      end
    end
  end

  metaseq_div.tick = function(box)
    for x = 1, 16 do
      box:led(x, x == data.metaseq.div and 15 or 2)
    end
  end
end

-- step grid: 16x7 step matrix shared between `steps` and `midi` views.
-- Also added to `sampling` view (legacy behavior — sampling has no grid UI of
-- its own, the step grid stays live underneath the sampling screen).
do
  local step_grid = eli.Box.new(16, 7)
  step_grid.floor = 0 -- step cells default to off, not floor brightness
  views.steps:add_box(step_grid, 1, 1)
  views.midi:add_box(step_grid, 1, 1)
  views.sampling:add_box(step_grid, 1, 1)

  local hold_row = {0, 0, 0, 0, 0, 0, 0}
  local first_x  = {0, 0, 0, 0, 0, 0, 0}
  local press_down_time = 0

  local function decode(seq)
    local x = ((seq - 1) % 16) + 1
    local gy = math.floor((seq - 1) / 16) + 1
    local tr = is_midi(data.selected.track) and gy + 7 or gy
    return x, gy, tr
  end

  step_grid.keydown = function(box, seq)
    local x, gy, tr = decode(seq)
    hold_row[gy] = hold_row[gy] + 1

    if SHIFT then
      if x == 16 then
        mute_track(tr)
      elseif x < 8 then
        set_div(tr, x)
      end
    elseif ALT then
      if hold_row[gy] == 1 then
        first_x[gy] = x
      elseif hold_row[gy] == 2 then
        set_loop(tr, first_x[gy], x)
      end
    elseif MOD then
      if not copy[1] then
        copy = { tr, x }
      else
        copy_step(copy, { tr, x })
      end
    else
      data.selected = { track = tr, step = x }
      press_down_time = util.time()
    end
  end

  step_grid.keyup = function(box, seq)
    local x, gy, tr = decode(seq)
    hold_row[gy] = math.max(0, hold_row[gy] - 1)
    if SHIFT or ALT or MOD then return end

    data.selected = { track = tr, step = false }
    tr_change(tr)
    if data.ui_index < 1 then data.ui_index = 1 end

    local held = (util.time() - press_down_time) > 0.3
    local cond = have_substeps(tr, x)
    local sx = get_step(x)
    if not cond then
      data[data.pattern][tr][sx] = 1
    elseif cond and not held then
      clear_substeps(tr, sx)
    end
  end

  step_grid.tick = function(box)
    box:all(0)
    local sel_tr = data.selected.track
    local sel_step = data.selected.step
    local pat = data[data.pattern]
    local midi_offset = is_midi(sel_tr) and 7 or 0

    for gy = 1, 7 do
      local tr = gy + midi_offset
      for x = 1, 16 do
        local seq = (gy - 1) * 16 + x
        if SHIFT then
          if x < 8 then
            box:led(seq, x == 5 and 6 or 3)
          end
          if x == pat.track.div[tr] then
            box:led(seq, 15)
          end
          if x == 16 then
            box:led(seq, pat.track.mute[tr] and 15 or 6)
          end
        elseif ALT then
          local t_start = get_tr_start(tr)
          local t_len = get_tr_len(tr)
          if x >= t_start and x <= t_len then
            box:led(seq, 3)
          end
        else
          if have_substeps(tr, x) then
            local t_start = get_tr_start(tr)
            local t_len = get_tr_len(tr)
            local level = (sel_tr == tr and sel_step == x and 15)
              or ((x < t_start or x > t_len) and 5)
              or (pat.track.mute[tr] and 5)
              or 10
            box:led(seq, level)
          end
        end
      end

      -- playhead
      if sequencer_metro.is_running and not SHIFT then
        local pos_x = math.ceil(pat.track.pos[tr] / 16)
        if pos_x >= 1 and pos_x <= 16 and not pat.track.mute[tr] then
          local seq = (gy - 1) * 16 + pos_x
          box:led(seq, have_substeps(tr, pos_x) and 15 or 6)
        end
      end
    end
  end
end

-- notes view: 16x7 linn-style music keyboard. Pressing a key plays a note on
-- the currently selected track (engine track triggers the sampler engine,
-- midi track sends note-on to the configured midi device). When PATTERN_REC
-- is on and the sequencer is running, the note is recorded onto the current
-- step. Modifier overlays (SHIFT/ALT/MOD) are intentionally not handled here
-- — notes view is a pure keyboard surface.
do
  local notes_keyboard = eli.Box.new(16, 7)
  views.notes:add_box(notes_keyboard, 1, 1)

  local last_seq = 0 -- focus highlight; replaces linn's private `focus` table

  notes_keyboard.keydown = function(box, seq)
    local x = ((seq - 1) % 16) + 1
    local gy = math.floor((seq - 1) / 16) + 1
    local tr = data.selected.track
    local track_default = data[data.pattern][tr].params[tostring(tr)]
    local note = linn.grid_key(x, gy, 1, track_default.device and midi_out_devices[track_default.device])
    if not note then return end

    last_seq = seq
    if is_engine(tr) then
      engine.noteOn(tr, music.note_num_to_freq(note), 1, track_default.sample)
    end
    if sequencer_metro.is_running and PATTERN_REC then
      place_note(tr, data[data.pattern].track.pos[tr], note)
    end
  end

  notes_keyboard.keyup = function(box, seq)
    local x = ((seq - 1) % 16) + 1
    local gy = math.floor((seq - 1) / 16) + 1
    local tr = data.selected.track
    local device = data[data.pattern][tr].params[tostring(tr)].device
    linn.grid_key(x, gy, 0, device and midi_out_devices[device])
    last_seq = 0
  end

  notes_keyboard.tick = function(box)
    box:all(0)
    for seq = 1, 16 * 7 do
      box:led(seq, linn.note_at(seq).l)
    end
    box:led(16, 3) -- top-right corner marker (legacy: g:led(16, 1, 3))
    if last_seq > 0 then
      box:led(last_seq, 10)
    end
  end
end

local params_fx = {
  [1] = function(d) params:set('takt_comp_level', params:get('takt_comp_level') + d) end,
  [2] = function(d) params:set('takt_comp_mix', params:get('takt_comp_mix') + d / 50) end,
  [3] = function(d)
    local val = threshold_map:unmap(params:get('takt_comp_threshold'))
    params:set('takt_comp_threshold', threshold_map:map(util.clamp(val + d /200, 0.001, 1 )))
  end,
  [4] = function(d) params:set('comp_slopebelow', params:get('comp_slopebelow') + d / 100) end,
  [5] = function(d) params:set('comp_slopeabove', params:get('comp_slopeabove') + d / 100) end,
  [6] = function(d) params:set('comp_clamptime', params:get('comp_clamptime') + d / 100)  end,
  [7] = function(d) params:set('comp_relaxtime', params:get('comp_relaxtime') + d / 100) end,
  [8] = function(d) params:set('reverb_time', params:get('reverb_time') + d / 5) end,
  [9] = function(d) params:set('reverb_size', params:get('reverb_size') + d / 50) end,
  [10] = function(d) params:set('reverb_damp', params:get('reverb_damp') + d / 100) end,
  [11] = function(d) params:set('reverb_diff', params:get('reverb_diff') + d / 100) end,
  [12] = function(d) params:set('delay_level', params:get('delay_level') + d) end,
  [13] = function(d)
    local val = time_map:unmap(params:get('delay_time'))
    params:set('delay_time', time_map:map(util.clamp(val + d /100, 0.001, 1 )))
  end,
  [14] = function(d) params:set('delay_feedback', params:get('delay_feedback') + d / 50) end,
  [15] = function(d) params:set('lfo_1_freq', params:get('lfo_1_freq') + d / 10) end,
  [16] = function(d) params:set('lfo_1_wave_shape', params:get('lfo_1_wave_shape') + d) end,
  [17] = function(d) params:set('lfo_2_freq', params:get('lfo_2_freq') + d / 10) end,
  [18] = function(d) params:set('lfo_2_wave_shape', params:get('lfo_2_wave_shape') + d) end,
}

-- per-view norns front-panel handlers --------------------------------------
-- Shared helpers; the wrappers in `enc` / `key` dispatch to the active view's
-- `:enc` / `:key` (set per-view below).

local function track_select_enc(d)
  local offset = is_midi(data.selected.track) and 7 or 0
  data.selected.track = util.clamp(data.selected.track + d, 1 + offset, 7 + offset)
  tr_change(data.selected.track)
end

-- enc(2) ui_index navigation for step-grid-style views; `upper` is the upper
-- bound when not holding K1 (steps/notes = 20, midi/patterns = 18).
local function steps_enc2(d, upper)
  if K1_HELD then
    data.ui_index = util.clamp(data.ui_index + d, -6, -1)
  else
    data.ui_index = util.clamp(data.ui_index + d, data.selected.step and -3 or 1, upper)
  end
end

-- enc(3) step / track / trig param edit (steps, midi, notes share this).
local function steps_enc3(d)
  local tr = data.selected.track
  local p = is_lock()
  local t = type(p) == 'number' and get_step(p) or p
  data[data.pattern][tr].params[t].lock = data.selected.step and 1 or 0
  if type(t) == 'number' then
    -- step held: fetch the per-step entry and snapshot the track default onto it
    redraw_params[1] = get_params(tr, t, true)
  else
    -- no step held: just the track default — `t` is its key, but passing it
    -- through `get_params(tr, t, true)` would write a self-referential
    -- `.default` onto the track default itself.
    redraw_params[1] = get_params(tr)
  end
  redraw_params[2] = redraw_params[1]
  if K1_HELD then
    track_params[data.ui_index](tr, p, d)
  else
    local params_t = data.ui_index < 1 and trig_params or is_engine(tr) and step_params or midi_step_params
    if type(p) == 'string' then
      params_t[data.ui_index](tr, p, d)
    else
      if data.ui_index > 0 then
        for i = t, t + 15 do params_t[data.ui_index](tr, i, d) end
      else
        params_t[data.ui_index](tr, t, d)
      end
    end
    if ei.active == views.notes then set_locks(get_params(tr)) end
  end
end

-- key(1) ui_index reset, common to step-grid-style views.
local function steps_key1()
  data.ui_index = K1_HELD and -4 or 1
end

-- key(3) engine-track shortcuts (sample loading, filter type, lfo/send jumps).
local function steps_key3(z)
  if data.ui_index == 1 and z == 1 then
    local sample_id = data[data.pattern][data.selected.track].params[is_lock()].sample
    browser.enter(_path.audio, timber.load_sample, sample_id)
  elseif (data.ui_index == 3 or data.ui_index == 4) and z == 1 and sample_not_loaded(get_sample()) then
    local sample_id = data[data.pattern][data.selected.track].params[is_lock()].sample
    browser.enter(_path.audio, timber.load_sample, sample_id)
  elseif (data.ui_index == 17 or data.ui_index == 18) and z == 1 then
    change_filter_type()
  elseif lfo_1[data.ui_index] then
    set_view('patterns')
    data.ui_index = 15
  elseif lfo_2[data.ui_index] then
    set_view('patterns')
    data.ui_index = 17
  elseif data.ui_index == 19 then
    set_view('patterns')
    data.ui_index = 12
  elseif data.ui_index == 20 then
    set_view('patterns')
    data.ui_index = 8
  end
end

-- Per-view enc/key handlers, dispatched by view instance.
local view_enc, view_key = {}, {}

view_enc[views.steps] = function(n, d)
  if n == 1 then track_select_enc(d)
  elseif n == 2 then steps_enc2(d, 20)
  elseif n == 3 then steps_enc3(d)
  end
end

view_enc[views.midi] = function(n, d)
  if n == 1 then track_select_enc(d)
  elseif n == 2 then steps_enc2(d, 18)
  elseif n == 3 then steps_enc3(d)
  end
end

-- notes view shares the steps view's enc handler (same upper bound, same
-- step_params dispatch). The `set_locks(...)` call inside `steps_enc3` is
-- gated on `ei.active == views.notes` so behavior diverges only when relevant.
view_enc[views.notes] = view_enc[views.steps]

view_enc[views.patterns] = function(n, d)
  if n == 1 then
    track_select_enc(d)
  elseif n == 2 then
    if K1_HELD then
      data.ui_index = util.clamp(data.ui_index + d, -1, -1)
    else
      data.ui_index = util.clamp(data.ui_index + d, data.selected.step and -3 or 1, 18)
    end
  elseif n == 3 then
    if K1_HELD then
      track_params[-1](data.selected.track, tostring(data.selected.track), d)
    else
      params_fx[data.ui_index](d)
    end
  end
end

view_enc[views.sampling] = function(n, d)
  if n == 1 then
    track_select_enc(d)
  elseif n == 2 then
    if not sampler.rec then
      data.ui_index = util.clamp(data.ui_index + d, -1, 6)
    end
  elseif n == 3 then
    sampling_params[data.ui_index](d)
  end
end

view_key[views.steps] = function(n, z)
  if n == 1 then steps_key1()
  elseif n == 3 then steps_key3(z)
  end
end

view_key[views.midi] = function(n, z)
  if n == 1 then steps_key1() end
  -- midi view doesn't trigger the engine-track K3 shortcuts (sample browser,
  -- filter type, lfo/send jumps) — those only apply to engine tracks.
end

view_key[views.notes] = view_key[views.steps]

view_key[views.patterns] = function(n, z)
  if n == 1 then
    data.ui_index = K1_HELD and -1 or 1
  end
  -- n == 2 and n == 3 are no-ops in patterns view.
end

view_key[views.sampling] = function(n, z)
  if n == 1 then
    data.ui_index = 1 -- K1_HELD doesn't reach a special branch in sampling
  elseif n == 3 then
    sampling_actions[data.ui_index](z)
    if z == 1 and ((data.ui_index == 1 and sampler.rec) or data.ui_index == 4) then
      ui.waveform = {}
    end
  end
end

function init()

  for i = 1, 4 do
      midi_out_devices[i] = midi.connect(i)
      midi_out_devices[i].event = midi_event
  end

  math.randomseed(os.time())

    params:add_trigger('save_p', "< Save project" )
    params:set_action('save_p', function(x) textentry.enter(save_project,  'new') end)
    params:add_trigger('load_p', "> Load project" )
    params:set_action('load_p', function(x) fileselect.enter(norns.state.data, load_project) end)
    params:add_trigger('new', "+ New" )
    params:set_action('new', function(x) init() end)
    params:add_separator()

    redraw_params[1] = data[1][1].params[tostring(1)]
    redraw_params[2] = data[1][1].params[tostring(1)]

    timber.init()
    sampler.init()
    ui.init()

    norns.encoders.set_sens(1, 3)
    norns.encoders.set_sens(2, 4)
    norns.encoders.set_sens(3, 3)
    norns.encoders.set_accel(1, false)
    norns.encoders.set_accel(2, false)
    norns.encoders.set_accel(3, true)

    sequencer_metro = metro.init()
    sequencer_metro.time = 60 / (data[data.pattern].bpm * 2) / 16 --[[ppqn]] / 4
    sequencer_metro.event = function(stage) seqrun(stage) if stage % m_div(data.metaseq.div) == 0 then metaseq(stage) end end

    redraw_metro = metro.init(function(stage) redraw(stage) ei:tick() blink = (blink + 1) % 17 end, 1/30)
    redraw_metro:start()
    midi_clock = beatclock:new()
    midi_clock.on_step = function() end
    midi_clock:bpm_change( util.round(data[data.pattern].bpm / midi_dividers[util.clamp(data[data.pattern].sync_div, 1, 7)]))
    midi_clock.send = false
end

function enc(n, d)
  if browser.open then
    browser.enc(n, d)
    return
  end
  local h = view_enc[ei.active]
  if h then h(n, d) end
end

function key(n, z)
  K1_HELD = (n == 1 and z == 1) and true or false
  K3_HELD = (n == 3 and z == 1) and true or false
  if browser.open then
    browser.key(n, z)
    return
  end
  local h = view_key[ei.active]
  if h then h(n, z) end
end

-- screen redraw fn
function redraw(stage)

  local tr = data.selected.track
  local pos = data[data.pattern].track.pos[tr]
  local params_data = get_params(tr, sequencer_metro.is_running and pos or false, true)



  if data.selected.step then
    redraw_params[1] = get_params(data.selected.track, get_step(data.selected.step), true)
  elseif not data.selected.step then
    redraw_params[1] = redraw_params[2]
  end

  screen.clear()

  ui.head(redraw_params[1], data, ei.active == views.sampling, K1_HELD, rules, PATTERN_REC, browser.preview)

  if ei.active == views.sampling then
    local pos = sampler.get_pos()
    ui.sampling(sampler, data.ui_index, pos)
  elseif ei.active == views.patterns then
    ui.patterns(data.pattern, data.metaseq, data.ui_index, stage)
  else
    if is_engine(data.selected.track) then
      local meta = timber.get_meta(redraw_params[1].sample)
      -- length hack
      local max_len = meta.num_frames
      if params_data.end_frame == 2000000000 and meta.waveform[2] ~= nil then
        get_sample_len(tr, is_lock())
      elseif params_data.end_frame > max_len then
        get_sample_len(tr, is_lock())
      elseif params_data.start_frame > max_len then
        get_sample_start(tr, is_lock())
      end
      ui.main_screen(redraw_params[1], data.ui_index, meta)
      if browser.open then browser.redraw() end
    else
      ui.midi_screen(redraw_params[1], data.ui_index, data[data.pattern].track, data[data.pattern])
    end
  end
  screen.update()
end
