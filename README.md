![docs](lib/doc.png)

@chailight extensions

Global Clock
------------
By default, this version uses the norns global clock.
Use the Clock options to determine whether takt syncs to Ableton Link, external Crow input or sends out MIDI clock, or modular clock via a Crow output

MIDI chord output
-----------------
You can select chord output instead of note output on a MIDI track.
On the MIDI page, use E2 to scroll to the next setting after the note selection tile. Instead of selecting the next tile, you should see the note symbol above the selected note value light up. Use E3 to scroll to the right to select a chord type (M = major, m = minor, etc). The selected note value will be the root of the chord. Chord inversions are currently not supported. If your selected device supports polyphonic playback, then you'll get a chord instead of a single note. 
Chord types and root notes can be adjusted per step just like any other parameter lock.

Just Friends, w/syn and crow support
------------------------------------
On the Parameters page, ensure that your JF, w/syn or crow output options are set to on.
On the MIDI page, use E2 to scroll to the Device tile. Use E3 to scroll past the first four MIDI device number selections. Depending on which i2c devices are enabled in Parameters, you'll be able to select JF, w/syn or crow.
This track will send out notes to the selected device.
