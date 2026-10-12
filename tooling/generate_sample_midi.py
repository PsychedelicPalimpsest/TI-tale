#!/usr/bin/env python3
"""
generate_sample_midi.py - Generates a multi-track polyphonic MIDI song for testing.

Creates an 8-bar chiptune video game theme featuring:
- Track 1: Lead Melody (Active melodic line with chords and phrasing)
- Track 2: Bassline (Rhythmic walking bass)
- Track 3: Harmony / Accompaniment (Arpeggiated chords)
- Track 4: Percussion (Channel 10: Kick, Snare, Hi-Hat)
"""

from __future__ import annotations

import struct
from pathlib import Path


def vlq(val: int) -> bytes:
    buf = bytearray()
    buf.append(val & 0x7F)
    val >>= 7
    while val > 0:
        buf.append((val & 0x7F) | 0x80)
        val >>= 7
    return bytes(reversed(buf))


def generate_theme_midi(output_path: Path):
    division = 480  # ticks per quarter note
    tempo_us = 461538  # 130 BPM (~461.5 ms per quarter note)

    # Track 0: Conductor (Tempo & Time Signature)
    t0 = bytearray()
    t0.extend(vlq(0) + b"\xFF\x58\x04\x04\x02\x18\x08") # 4/4 time
    t0.extend(vlq(0) + b"\xFF\x51\x03" + struct.pack(">I", tempo_us)[1:]) # tempo
    t0.extend(vlq(0) + b"\xFF\x03\x09Conductor")
    t0.extend(vlq(division * 32) + b"\xFF\x2F\x00") # 8 bars = 32 beats

    # Track 1: Lead Melody (Channel 0)
    # 8-bar upbeat theme in C / Am
    # Notes: (start_beat, duration_beats, pitch)
    melody_notes = [
        # Bar 1: C5, E5, G5, E5
        (0.0, 0.75, 72), (1.0, 0.75, 76), (2.0, 0.75, 79), (3.0, 0.75, 76),
        # Bar 2: A5, G5, E5, D5
        (4.0, 1.0, 81), (5.5, 0.5, 79), (6.0, 1.0, 76), (7.0, 0.75, 74),
        # Bar 3: C5, D5, E5, G5
        (8.0, 0.75, 72), (9.0, 0.75, 74), (10.0, 0.75, 76), (11.0, 0.75, 79),
        # Bar 4: D5 (held)
        (12.0, 3.5, 74),
        # Bar 5: E5, G5, A5, C6
        (16.0, 0.75, 76), (17.0, 0.75, 79), (18.0, 0.75, 81), (19.0, 0.75, 84),
        # Bar 6: B5, A5, G5, E5
        (20.0, 1.0, 83), (21.5, 0.5, 81), (22.0, 1.0, 79), (23.0, 0.75, 76),
        # Bar 7: F5, G5, A5, B5
        (24.0, 0.75, 77), (25.0, 0.75, 79), (26.0, 0.75, 81), (27.0, 0.75, 83),
        # Bar 8: C6 (finish)
        (28.0, 3.8, 84),
    ]

    t1 = build_note_track(melody_notes, channel=0, program=80, name="Lead Melody", division=division)

    # Track 2: Bassline (Channel 1, Program 38 Synth Bass)
    # Steady 8th-note driving bass
    bass_notes = []
    # Bar 1-2: C3 (48), Bar 3-4: G2 (43), Bar 5-6: A2 (45), Bar 7: F2 (41), Bar 8: G2 (43)
    root_pattern = [
        (0.0, 48), (2.0, 48), (4.0, 48), (6.0, 55),
        (8.0, 43), (10.0, 43), (12.0, 43), (14.0, 50),
        (16.0, 45), (18.0, 45), (20.0, 45), (22.0, 52),
        (24.0, 41), (26.0, 41), (28.0, 48), (30.0, 43)
    ]
    for beat, pitch in root_pattern:
        bass_notes.append((beat, 0.8, pitch))
        bass_notes.append((beat + 1.0, 0.8, pitch + 12)) # Octave bounce

    t2 = build_note_track(bass_notes, channel=1, program=38, name="Bassline", division=division)

    # Track 3: Percussion (Channel 9, General MIDI Drums)
    # Kick on 1 & 3 (36), Snare on 2 & 4 (38), Hi-hat on every 8th note (42)
    drum_notes = []
    for bar in range(8):
        base_beat = bar * 4.0
        # Kicks
        drum_notes.append((base_beat + 0.0, 0.2, 36))
        drum_notes.append((base_beat + 2.0, 0.2, 36))
        # Snares
        drum_notes.append((base_beat + 1.0, 0.2, 38))
        drum_notes.append((base_beat + 3.0, 0.2, 38))
        # Hi-hats
        for step in range(8):
            drum_notes.append((base_beat + (step * 0.5), 0.1, 42))

    t3 = build_note_track(drum_notes, channel=9, program=0, name="Percussion", division=division)

    # Assemble SMF Format 1 file
    tracks = [t0, t1, t2, t3]
    header = b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks), division)
    content = bytearray(header)
    for trk_data in tracks:
        chunk = b"MTrk" + struct.pack(">I", len(trk_data)) + trk_data
        content.extend(chunk)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(content)
    print(f"Sample MIDI generated: {output_path} ({len(content)} bytes)")


def build_note_track(notes: list[tuple[float, float, int]], channel: int, program: int, name: str, division: int) -> bytearray:
    # Convert notes to timestamped on/off events
    events: list[tuple[int, bytes]] = []

    # Track name & program change
    events.append((0, b"\xFF\x03" + bytes([len(name)]) + name.encode("ascii")))
    events.append((0, bytes([0xC0 | channel, program])))

    for start_beat, dur_beats, pitch in notes:
        start_tick = int(round(start_beat * division))
        end_tick = int(round((start_beat + dur_beats) * division))
        # Note On
        events.append((start_tick, bytes([0x90 | channel, pitch, 90])))
        # Note Off
        events.append((end_tick, bytes([0x80 | channel, pitch, 0])))

    # Sort events by tick
    events.sort(key=lambda x: x[0])

    # Convert absolute ticks to delta ticks
    track_bytes = bytearray()
    last_tick = 0
    for tick, payload in events:
        delta = tick - last_tick
        track_bytes.extend(vlq(delta))
        track_bytes.extend(payload)
        last_tick = tick

    # End of track
    track_bytes.extend(vlq(0) + b"\xFF\x2F\x00")
    return track_bytes


def generate_chords_midi(output_path: Path):
    """Generates an 8-bar polyphonic chord progression with 4 simultaneous voices."""
    division = 480
    tempo_us = 500000  # 120 BPM

    t0 = bytearray()
    t0.extend(vlq(0) + b"\xFF\x58\x04\x04\x02\x18\x08")
    t0.extend(vlq(0) + b"\xFF\x51\x03" + struct.pack(">I", tempo_us)[1:])
    t0.extend(vlq(0) + b"\xFF\x03\x09Conductor")
    t0.extend(vlq(division * 16) + b"\xFF\x2F\x00")

    # 4 bars of 4-voice chords:
    # Bar 1: C major (C3=48, E4=64, G4=67, C5=72)
    # Bar 2: G major (G2=43, D4=62, G4=67, B4=71)
    # Bar 3: A minor (A2=45, C4=60, E4=64, A4=69)
    # Bar 4: F major (F2=41, C4=60, F4=65, A4=69)
    chord_notes = [
        # Bar 1: C Major triad + root
        (0.0, 3.8, 48), (0.0, 3.8, 64), (0.0, 3.8, 67), (0.0, 3.8, 72),
        # Bar 2: G Major
        (4.0, 3.8, 43), (4.0, 3.8, 62), (4.0, 3.8, 67), (4.0, 3.8, 71),
        # Bar 3: A Minor
        (8.0, 3.8, 45), (8.0, 3.8, 60), (8.0, 3.8, 64), (8.0, 3.8, 69),
        # Bar 4: F Major
        (12.0, 3.8, 41), (12.0, 3.8, 60), (12.0, 3.8, 65), (12.0, 3.8, 69),
    ]

    t1 = build_note_track(chord_notes, channel=0, program=0, name="Polyphonic Chords", division=division)
    tracks = [t0, t1]
    header = b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks), division)
    content = bytearray(header)
    for trk_data in tracks:
        content.extend(b"MTrk" + struct.pack(">I", len(trk_data)) + trk_data)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(content)
    print(f"Chord progression MIDI generated: {output_path} ({len(content)} bytes)")


if __name__ == "__main__":
    generate_theme_midi(Path("tooling/samples/adventure_theme.mid"))
    generate_chords_midi(Path("tooling/samples/chord_progression.mid"))
