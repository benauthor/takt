![docs](lib/doc.png)

keys:
k1: pressed -> standard norns menus
    when held, selects the global parameters
k2: underutilized!
k3: when held i think meant to control coarse/fine on parameter edits? not sure this applies everywhere

encoders:
e1: track select
e2: thing to edit
e3: value of thing

Notes:
- step mode:
  hold down MOD to copy step (press existing) and paste (press empty)
  ALT: loop a shorter portion of the sequence
  SHIFT: show mutes (rightmost column), set a step division (i'm not sure what ratios are TODO

- pattern mode:
  top 4 lines are available patterns
  you can sort of pattern chain by hold-down-start, press-end
  it's not a full arbitrary-order pattern chain, it's a contiguous range
  when not running need to double click to switch patterns? is this a bug or a feature?
  hold down MOD to copy pattern (press existing) and paste (press empty)
  ALT not active
  hold down SHIFT to delete pattern

- notes mode:
  press pattern record, i think it's not quantized, which is cool? even cooler if quant/unquant was switchable?
  MOD ALT SHIFT not active

- browser view?
- TODO explore sampler view better

- what's line 6 about? "metaseq"... need to read the code and understand better

TODOs:
- ergonomically, it would be cool if repeating a mode selection button would send you back to the previous. i.e. easily flip between sequence and pattern, sequence and notes, whatever

- when sequencer is running across multiple patterns editing a p lock is tricky, end up modifying the other pattern if you're not quick enough

- sampler mode:
  what to do with the grid? maybe it should selects sample slot?

- notes mode: what should norns screen show? i guess corresponding to selected track, either step or midi screen, you should be able to scroll through all of them

- it would be good to be able to increment patterns without leaving the step/midi screen?

- is global sequence length editable
