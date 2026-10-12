`song_raining_somewhere_else.asm` is a 128-beat retro arrangement of the
user-provided "It's Raining Somewhere Else" MIDI. It has a short chord intro,
then two melodic sections. The arranger uses a pulse lead, measured chord
arpeggios, and a regular bass line. The 2.7 KiB score fits on the first ROM
page and loops after about 78 seconds.

Regenerate it with:

```sh
python3 tooling/midi_to_audio.py \
  "/home/mitch/Downloads/undertale midi-20261011T231640Z-1-001/undertale midi/It_s Raining Somewhere Else.mid" \
  -o app/game/audio/song_raining_somewhere_else.asm \
  --format asm --name song_raining_somewhere_else --loop \
  --strategy arranged --sections '0:9.697,38.788:77.576,77.576:106.667' \
  --max-bytes 3100
```
