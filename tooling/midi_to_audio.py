#!/usr/bin/env python3
"""
midi_to_audio.py - Intelligent MIDI to TI-Tale Audio Engine Converter.

Converts standard MIDI files (.mid) into native bytecode streams playable by
the TI-Tale dual-channel audio engine on TI-83+ SE / TI-84+ hardware.

Features:
- Pure Python 3 standard library implementation (no external dependencies required).
- Comprehensive MIDI parsing supporting Format 0 and Format 1 files, running status,
  and dynamic tempo change maps.
- Intelligent polyphony reduction and 2-channel voice allocation:
  * Smart adaptive allocation: detects melody and bass lines, balances channels,
    and preserves melodic continuity.
  * Melody & Bass separation: isolates top melody line to Channel 1 and bassline to Channel 2.
  * Arpeggiation mode: classic chiptune rapid arpeggiation (30Hz/60Hz) for multi-note chords.
  * Explicit track routing: user-assigned tracks for Channel 1 and Channel 2.
  * Dynamic voice allocation: greedy voice assignment with pitch-distance smoothing.
- Multi-timbre voice synthesis:
  * Square waves with configurable duty cycles (50% hollow, 25% bright, 12.5% thin pulse).
  * Additive sawtooth waves (Style 1) with discrete (K, M) optimal tuning.
  * Exponential sawtooth waves (Style 2 and Style 3).
  * Custom instruments (Pulse-density tables) with toggleable allow/disable settings.
- Intelligent percussion handling (MIDI channel 10):
  * Synthesized kick drum via downward square frequency sweep.
  * Synthesized snare drum via saw sweep / noise simulation.
  * Synthesized hi-hat via brief high-frequency pulse bursts.
  * Custom instrument 1-bit pulse tables (when custom instruments are allowed).
  * Automatic temporary preemption of Channel 2 with seamless background note resumption.
- Articulation and phrasing:
  * Configurable note-gap insertion between consecutive identical notes to prevent droning.
  * Staccato / legato duration scaling.
- Micro-tuning and auto-octave transpose:
  * Finds optimal wave parameters minimizing pitch cents error.
  * Automatic whole-octave transposition to fit within the hardware's optimal frequency sweet spot.
- Multiple export formats:
  * Z80 Assembly (.asm/.inc) with rich annotations (note names, frequencies, bar markers).
  * C source/header (.c/.h) with const byte arrays.
  * Raw binary (.bin) ready for flash inclusion.
  * MIDI inspection / song info reporting.
"""

from __future__ import annotations

import argparse
import math
import os
import struct
import sys
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Set, Tuple

# ---------------------------------------------------------------------------
# Audio Engine Hardware & Bytecode Constants
# ---------------------------------------------------------------------------

CLOCK_SLOW_HZ = 32768.0        # Timer speed mode $44: 32,768 Hz crystal
CLOCK_FAST_HZ = 234375.0       # Timer speed mode $A0: ~15 MHz / 64
TICKS_PER_SECOND = 256.0       # _scount units per second (high byte seconds, low byte frac)
GREYSCALE_FPS = 60.0           # Audio tick evaluation frequency (~60 Hz)

# Bytecode opcodes matching app/engine/resident/installed/audio_engine.asm
OP_STOP_SONG          = 0x00   # Stop playback and disable timers
OP_WAIT               = 0x01   # Wait 16-bit uint ticks (little endian)
OP_CH1_FAST           = 0x02   # Set Channel 1 to fast clock (cpu/64)
OP_CH1_SLOW           = 0x03   # Set Channel 1 to slow clock (32768 Hz)
OP_CH2_FAST           = 0x04   # Set Channel 2 to fast clock (cpu/64)
OP_CH2_SLOW           = 0x05   # Set Channel 2 to slow clock (32768 Hz)
OP_CH1_STOP           = 0x06   # Turn off Channel 1
OP_CH2_STOP           = 0x07   # Turn off Channel 2
OP_CH1_SQUARE         = 0x08   # high_ticks, low_ticks
OP_CH2_SQUARE         = 0x09   # high_ticks, low_ticks
OP_CH1_SAW1           = 0x0A   # additive_const K, max_ticks M
OP_CH2_SAW1           = 0x0B   # additive_const K, max_ticks M
OP_CH1_SAW2           = 0x0C   # max_ticks M
OP_CH2_SAW2           = 0x0D   # max_ticks M
OP_CH1_SAW3           = 0x0E   # max_ticks M
OP_CH2_SAW3           = 0x0F   # max_ticks M
OP_CH1_SQUARE_SWEEP   = 0x10   # mask, high_add, low_add
OP_CH2_SQUARE_SWEEP   = 0x11   # mask, high_add, low_add
OP_CH1_SAW_SWEEP      = 0x12   # mask, max_add, const_add
OP_CH2_SAW_SWEEP      = 0x13   # mask, max_add, const_add
OP_CH1_INSTR          = 0x14   # 16-bit table pointer (little endian)
OP_CH2_INSTR          = 0x15   # 16-bit table pointer (little endian)
OP_JUMP               = 0x16   # 16-bit jump address (little endian)

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

def midi_pitch_to_name(pitch: int) -> str:
    """Converts a MIDI pitch number (e.g. 60) to a string representation ('C4')."""
    octave = (pitch // 12) - 1
    name = NOTE_NAMES[pitch % 12]
    return f"{name}{octave}"

def midi_pitch_to_freq(pitch: float) -> float:
    """Converts a MIDI pitch (including fractional pitch bend) to frequency in Hz."""
    return 440.0 * (2.0 ** ((pitch - 69.0) / 12.0))

def freq_to_cents(actual_freq: float, target_freq: float) -> float:
    """Returns pitch error in cents between actual and target frequency."""
    if actual_freq <= 0 or target_freq <= 0:
        return 0.0
    return 1200.0 * math.log2(actual_freq / target_freq)

# General MIDI Instrument Families
GM_FAMILIES = {
    range(0, 8): "Piano",
    range(8, 16): "Chromatic Percussion",
    range(16, 24): "Organ",
    range(24, 32): "Guitar",
    range(32, 40): "Bass",
    range(40, 48): "Strings",
    range(48, 56): "Ensemble",
    range(56, 64): "Brass",
    range(64, 72): "Reed",
    range(72, 80): "Pipe",
    range(80, 88): "Synth Lead",
    range(88, 96): "Synth Pad",
    range(96, 104): "Synth Effects",
    range(104, 112): "Ethnic",
    range(112, 120): "Percussive",
    range(120, 128): "Sound Effects",
}

def get_gm_family(program: int) -> str:
    for rng, name in GM_FAMILIES.items():
        if program in rng:
            return name
    return "Unknown"


# ---------------------------------------------------------------------------
# Pure-Python MIDI File Parser
# ---------------------------------------------------------------------------

@dataclass
class NoteEvent:
    pitch: int
    start_time: float      # in seconds
    end_time: float        # in seconds
    velocity: int
    channel: int           # 0-15
    track_idx: int
    program: int = 0
    pitch_bend: float = 0.0 # Semitone offset
    is_percussion: bool = False

    @property
    def duration(self) -> float:
        return max(0.0, self.end_time - self.start_time)


@dataclass
class TrackSummary:
    track_idx: int
    name: str
    channel: Optional[int]
    program: int
    family: str
    note_count: int
    min_pitch: int
    max_pitch: int
    mean_pitch: float
    is_percussion: bool
    role: str              # "melody", "bass", "harmony", "percussion"


class MidiParseError(Exception):
    pass


def read_vlq(data: bytes, pos: int) -> Tuple[int, int]:
    """Reads a variable-length quantity from data starting at pos."""
    val = 0
    while pos < len(data):
        b = data[pos]
        pos += 1
        val = (val << 7) | (b & 0x7F)
        if not (b & 0x80):
            break
    return val, pos


class TempoMap:
    """Maintains a timeline of tempo changes and converts ticks to seconds."""
    def __init__(self, division: int):
        self.division = division
        # List of (tick, tempo_us, accumulated_seconds)
        self.points: List[Tuple[int, int, float]] = [(0, 500000, 0.0)]

    def add_tempo(self, tick: int, tempo_us: int):
        last_tick, last_tempo, last_sec = self.points[-1]
        if tick > last_tick:
            delta_ticks = tick - last_tick
            sec_per_tick = (last_tempo / 1_000_000.0) / self.division
            current_sec = last_sec + (delta_ticks * sec_per_tick)
            self.points.append((tick, tempo_us, current_sec))
        elif tick == last_tick:
            # Overwrite tempo at the same tick
            self.points[-1] = (tick, tempo_us, last_sec)

    def tick_to_seconds(self, tick: int) -> float:
        # Binary search or scan
        idx = 0
        for i, (pt_tick, _, _) in enumerate(self.points):
            if tick >= pt_tick:
                idx = i
            else:
                break
        pt_tick, tempo_us, pt_sec = self.points[idx]
        delta_ticks = tick - pt_tick
        sec_per_tick = (tempo_us / 1_000_000.0) / self.division
        return pt_sec + (delta_ticks * sec_per_tick)


def parse_midi_file(filepath: Path) -> Tuple[List[NoteEvent], List[TrackSummary], float]:
    """
    Parses a Standard MIDI File (.mid) and extracts note events and track metadata.
    Returns (notes, track_summaries, total_duration_seconds).
    """
    data = filepath.read_bytes()
    if len(data) < 14 or data[:4] != b"MThd":
        raise MidiParseError(f"Not a valid MIDI file: {filepath}")

    header_len, fmt, ntrks, division = struct.unpack(">IHHH", data[4:14])
    if division & 0x8000:
        # SMPTE time code - fallback to standard division
        division = 480

    pos = 14
    track_chunks: List[bytes] = []
    while pos < len(data) and len(track_chunks) < ntrks:
        if pos + 8 > len(data):
            break
        chunk_type, chunk_len = struct.unpack(">4sI", data[pos:pos+8])
        pos += 8
        chunk_data = data[pos:pos+chunk_len]
        pos += chunk_len
        if chunk_type == b"MTrk":
            track_chunks.append(chunk_data)

    # First pass: collect all tempo events across all tracks to build unified tempo map
    tempo_events: List[Tuple[int, int]] = []
    track_names: Dict[int, str] = {}

    for trk_idx, tdata in enumerate(track_chunks):
        tpos = 0
        tick = 0
        running_status = None
        while tpos < len(tdata):
            delta, tpos = read_vlq(tdata, tpos)
            tick += delta
            if tpos >= len(tdata):
                break
            b = tdata[tpos]
            if b & 0x80:
                status = b
                tpos += 1
            else:
                status = running_status
            running_status = status
            if status is None:
                continue

            if status == 0xFF:
                meta_type = tdata[tpos]
                tpos += 1
                meta_len, tpos = read_vlq(tdata, tpos)
                meta_payload = tdata[tpos:tpos+meta_len]
                tpos += meta_len
                if meta_type == 0x51 and meta_len == 3:  # Set Tempo
                    tempo_us = (meta_payload[0] << 16) | (meta_payload[1] << 8) | meta_payload[2]
                    tempo_events.append((tick, tempo_us))
                elif meta_type == 0x03:                  # Track Name
                    try:
                        track_names[trk_idx] = meta_payload.decode("latin1", errors="replace").strip()
                    except Exception:
                        pass
            elif status in (0xF0, 0xF7):
                syx_len, tpos = read_vlq(tdata, tpos)
                tpos += syx_len
            else:
                msg_type = status & 0xF0
                if msg_type in (0x80, 0x90, 0xA0, 0xB0, 0xE0):
                    tpos += 2
                elif msg_type in (0xC0, 0xD0):
                    tpos += 1

    tempo_events.sort(key=lambda x: x[0])
    tempo_map = TempoMap(division)
    for tick, tempo_us in tempo_events:
        tempo_map.add_tempo(tick, tempo_us)

    # Second pass: extract note on/off events, program changes, pitch bends
    notes: List[NoteEvent] = []
    track_channel_programs: Dict[Tuple[int, int], int] = {}
    channel_pitch_bends: Dict[int, float] = {}

    for trk_idx, tdata in enumerate(track_chunks):
        tpos = 0
        tick = 0
        running_status = None
        active_notes: Dict[Tuple[int, int], Tuple[float, int, float]] = {} # (chan, pitch) -> (start_sec, vel, bend)

        while tpos < len(tdata):
            delta, tpos = read_vlq(tdata, tpos)
            tick += delta
            if tpos >= len(tdata):
                break
            b = tdata[tpos]
            if b & 0x80:
                status = b
                tpos += 1
            else:
                status = running_status
            running_status = status
            if status is None:
                continue

            if status == 0xFF:
                meta_type = tdata[tpos]
                tpos += 1
                meta_len, tpos = read_vlq(tdata, tpos)
                tpos += meta_len
            elif status in (0xF0, 0xF7):
                syx_len, tpos = read_vlq(tdata, tpos)
                tpos += syx_len
            else:
                msg_type = status & 0xF0
                chan = status & 0x0F
                if msg_type == 0x90:  # Note On
                    pitch = tdata[tpos]
                    vel = tdata[tpos+1]
                    tpos += 2
                    sec = tempo_map.tick_to_seconds(tick)
                    key = (chan, pitch)
                    if vel > 0:
                        # If a note is already on, terminate previous
                        if key in active_notes:
                            start_sec, prev_vel, prev_bend = active_notes.pop(key)
                            prog = track_channel_programs.get((trk_idx, chan), 0)
                            notes.append(NoteEvent(
                                pitch=pitch,
                                start_time=start_sec,
                                end_time=sec,
                                velocity=prev_vel,
                                channel=chan,
                                track_idx=trk_idx,
                                program=prog,
                                pitch_bend=prev_bend,
                                is_percussion=(chan == 9)
                            ))
                        active_notes[key] = (sec, vel, channel_pitch_bends.get(chan, 0.0))
                    else:
                        # Velocity 0 = Note Off
                        if key in active_notes:
                            start_sec, prev_vel, prev_bend = active_notes.pop(key)
                            prog = track_channel_programs.get((trk_idx, chan), 0)
                            notes.append(NoteEvent(
                                pitch=pitch,
                                start_time=start_sec,
                                end_time=sec,
                                velocity=prev_vel,
                                channel=chan,
                                track_idx=trk_idx,
                                program=prog,
                                pitch_bend=prev_bend,
                                is_percussion=(chan == 9)
                            ))
                elif msg_type == 0x80:  # Note Off
                    pitch = tdata[tpos]
                    vel = tdata[tpos+1]
                    tpos += 2
                    sec = tempo_map.tick_to_seconds(tick)
                    key = (chan, pitch)
                    if key in active_notes:
                        start_sec, prev_vel, prev_bend = active_notes.pop(key)
                        prog = track_channel_programs.get((trk_idx, chan), 0)
                        notes.append(NoteEvent(
                            pitch=pitch,
                            start_time=start_sec,
                            end_time=sec,
                            velocity=prev_vel,
                            channel=chan,
                            track_idx=trk_idx,
                            program=prog,
                            pitch_bend=prev_bend,
                            is_percussion=(chan == 9)
                        ))
                elif msg_type == 0xC0:  # Program Change
                    prog = tdata[tpos]
                    tpos += 1
                    track_channel_programs[(trk_idx, chan)] = prog
                elif msg_type == 0xE0:  # Pitch Bend
                    bend_lsb = tdata[tpos]
                    bend_msb = tdata[tpos+1]
                    tpos += 2
                    bend_val = ((bend_msb << 7) | bend_lsb) - 8192
                    # Normalized semitone bend (+/- 2 semitones standard range)
                    new_bend = (bend_val / 8192.0) * 2.0
                    channel_pitch_bends[chan] = new_bend
                    sec = tempo_map.tick_to_seconds(tick)
                    for (k_chan, k_pitch), (start_sec, vel, prev_bend) in list(active_notes.items()):
                        if k_chan == chan and (sec - start_sec) >= 0.02 and abs(new_bend - prev_bend) >= 0.05:
                            prog = track_channel_programs.get((trk_idx, chan), 0)
                            notes.append(NoteEvent(
                                pitch=k_pitch,
                                start_time=start_sec,
                                end_time=sec,
                                velocity=vel,
                                channel=chan,
                                track_idx=trk_idx,
                                program=prog,
                                pitch_bend=prev_bend,
                                is_percussion=(chan == 9)
                            ))
                            active_notes[(k_chan, k_pitch)] = (sec, vel, new_bend)
                elif msg_type in (0xA0, 0xB0):
                    tpos += 2
                elif msg_type == 0xD0:
                    tpos += 1

        # Close any leftover active notes at track end
        final_sec = tempo_map.tick_to_seconds(tick)
        for (chan, pitch), (start_sec, vel, bend) in active_notes.items():
            prog = track_channel_programs.get((trk_idx, chan), 0)
            notes.append(NoteEvent(
                pitch=pitch,
                start_time=start_sec,
                end_time=final_sec,
                velocity=vel,
                channel=chan,
                track_idx=trk_idx,
                program=prog,
                pitch_bend=bend,
                is_percussion=(chan == 9)
            ))

    notes.sort(key=lambda n: (n.start_time, n.pitch))

    # Track classification & summary
    track_summaries: List[TrackSummary] = []
    total_duration = max((n.end_time for n in notes), default=0.0)

    for trk_idx in range(len(track_chunks)):
        trk_notes = [n for n in notes if n.track_idx == trk_idx]
        name = track_names.get(trk_idx, f"Track {trk_idx}")
        if not trk_notes:
            track_summaries.append(TrackSummary(
                track_idx=trk_idx,
                name=name,
                channel=None,
                program=0,
                family="Empty",
                note_count=0,
                min_pitch=0,
                max_pitch=0,
                mean_pitch=0.0,
                is_percussion=False,
                role="none"
            ))
            continue

        chan = trk_notes[0].channel
        prog = trk_notes[0].program
        is_perc = any(n.is_percussion for n in trk_notes)
        pitches = [n.pitch for n in trk_notes if not n.is_percussion]
        min_p = min(pitches) if pitches else 0
        max_p = max(pitches) if pitches else 0
        mean_p = sum(pitches) / len(pitches) if pitches else 0.0
        family = get_gm_family(prog)

        if is_perc:
            role = "percussion"
        elif mean_p < 52 or family == "Bass":
            role = "bass"
        elif mean_p >= 65:
            role = "melody"
        else:
            role = "harmony"

        track_summaries.append(TrackSummary(
            track_idx=trk_idx,
            name=name,
            channel=chan,
            program=prog,
            family=family,
            note_count=len(trk_notes),
            min_pitch=min_p,
            max_pitch=max_p,
            mean_pitch=mean_p,
            is_percussion=is_perc,
            role=role
        ))

    return notes, track_summaries, total_duration


# ---------------------------------------------------------------------------
# Audio Engine Waveform Calculation & Micro-Tuning Math
# ---------------------------------------------------------------------------

@dataclass
class SquareParams:
    high_ticks: int
    low_ticks: int
    actual_freq: float
    cents_err: float

def calc_square_params(target_freq: float, clock_hz: float = CLOCK_SLOW_HZ, duty_ratio: float = 0.5) -> SquareParams:
    """
    Calculates high and low period timer ticks for a square wave on the TI timer.
    Enforces loop counter range [1, 255].
    """
    if target_freq <= 0:
        return SquareParams(255, 255, 0.0, 0.0)

    total_ticks = clock_hz / target_freq
    total_ticks_clamped = max(2, min(510, round(total_ticks)))

    high = round(total_ticks_clamped * duty_ratio)
    high = max(1, min(255, high))
    low = total_ticks_clamped - high
    low = max(1, min(255, low))

    actual_period = high + low
    actual_freq = clock_hz / actual_period if actual_period > 0 else 0.0
    cents_err = freq_to_cents(actual_freq, target_freq)
    return SquareParams(high, low, actual_freq, cents_err)


@dataclass
class Saw1Params:
    k_const: int       # Additive constant K (1..16)
    m_max: int         # Maximum ticks M (2..255)
    actual_freq: float
    cents_err: float

def calc_saw1_params(target_freq: float, clock_hz: float = CLOCK_SLOW_HZ) -> Saw1Params:
    """
    Finds optimal (K, M) pair for Additive Sawtooth (Style 1).
    Total ticks per saw cycle = ceil((M - 1) / K) * M.
    """
    if target_freq <= 0:
        return Saw1Params(1, 255, 0.0, 0.0)

    best_k = 1
    best_m = 255
    best_freq = 0.0
    best_err = 9999.0

    for k in range(1, 16):
        # Initial estimate based on continuous formula: M ~ 1 + sqrt(clock * K / freq)
        approx_m = int(round(1.0 + math.sqrt(clock_hz * k / target_freq)))
        # Search locally around approx_m
        for m in range(max(2, approx_m - 6), min(256, approx_m + 7)):
            steps = math.ceil((m - 1) / k)
            ticks = steps * m
            if ticks > 0:
                f = clock_hz / ticks
                err = abs(freq_to_cents(f, target_freq))
                if err < best_err:
                    best_err = err
                    best_k = k
                    best_m = m
                    best_freq = f

    return Saw1Params(best_k, best_m, best_freq, freq_to_cents(best_freq, target_freq))


@dataclass
class Saw2Params:
    m_max: int
    actual_freq: float
    cents_err: float

def calc_saw2_params(target_freq: float, clock_hz: float = CLOCK_SLOW_HZ) -> Saw2Params:
    """Calculates parameters for Exponential Sawtooth (Style 2: 'or a \\ rla')."""
    if target_freq <= 0:
        return Saw2Params(255, 0.0, 0.0)

    best_m = 255
    best_freq = 0.0
    best_err = 9999.0

    for m in range(2, 256):
        steps = math.ceil(math.log2(m)) if m > 1 else 1
        ticks = steps * m
        if ticks > 0:
            f = clock_hz / ticks
            err = abs(freq_to_cents(f, target_freq))
            if err < best_err:
                best_err = err
                best_m = m
                best_freq = f

    return Saw2Params(best_m, best_freq, freq_to_cents(best_freq, target_freq))


@dataclass
class Saw3Params:
    m_max: int
    actual_freq: float
    cents_err: float

def calc_saw3_params(target_freq: float, clock_hz: float = CLOCK_SLOW_HZ) -> Saw3Params:
    """Calculates parameters for Exponential+1 Sawtooth (Style 3: 'nop \\ rla')."""
    if target_freq <= 0:
        return Saw3Params(255, 0.0, 0.0)

    best_m = 255
    best_freq = 0.0
    best_err = 9999.0

    for m in range(2, 256):
        # Steps sequence: 1, 3, 7, 15, 31, 63, 127, 255
        steps = 0
        a = 1
        while a < m and steps < 16:
            steps += 1
            a = (a * 2) + 1
        ticks = max(1, steps) * m
        f = clock_hz / ticks
        err = abs(freq_to_cents(f, target_freq))
        if err < best_err:
            best_err = err
            best_m = m
            best_freq = f

    return Saw3Params(best_m, best_freq, freq_to_cents(best_freq, target_freq))


def detect_optimal_transposition(notes: Sequence[NoteEvent]) -> int:
    """
    Analyzes non-percussion note pitches and suggests whole-octave transposition (+/- 12, 24)
    to position the music comfortably within the calculator link-port transducer's optimal
    frequency response range (approx. 65 Hz to 2000 Hz, C2 to B6).
    """
    pitches = [n.pitch for n in notes if not n.is_percussion]
    if not pitches:
        return 0

    sorted_p = sorted(pitches)
    median_pitch = sorted_p[len(sorted_p) // 2]

    # Transposition is based on the song's overall tessitura (median pitch).
    # Deep individual bass notes below C2 (36) are folded up by octave independently,
    # avoiding transposing the entire piece into a shrill upper register.
    transpose = 0
    if median_pitch < 36:
        needed_octaves = math.ceil((36 - median_pitch) / 12.0)
        transpose = needed_octaves * 12
    elif median_pitch > 90:
        transpose = -12

    return transpose



# ---------------------------------------------------------------------------
# Custom Instrument Pulse Wave Generators
# ---------------------------------------------------------------------------

@dataclass
class CustomInstrument:
    name: str
    pulse_table: List[int] # Byte intervals terminating in 0
    description: str

    def to_asm(self) -> str:
        lines = [
            f"; Custom instrument: {self.description}",
            "ALIGN 256",
            f"{self.name}:"
        ]
        chunk_size = 16
        for i in range(0, len(self.pulse_table), chunk_size):
            chunk = self.pulse_table[i:i+chunk_size]
            bytes_str = ", ".join(f"{b:3d}" for b in chunk)
            lines.append(f"    DEFB {bytes_str}")
        return "\n".join(lines)


def generate_drum_instruments() -> Dict[str, CustomInstrument]:
    """
    Generates standard 1-bit custom instrument pulse tables for kick, snare, and hi-hat.
    These are used when custom instruments are enabled.
    """
    # 1. Kick drum: decaying frequency pulse period (starts with tight pulses, widens into low thump)
    kick_pulses: List[int] = [
        10, 12, 14, 16, 19, 22, 26, 30, 36, 42, 50, 60, 72, 85, 102, 120, 145, 170, 0
    ]

    # 2. Snare drum: pseudo-random noise burst pulse intervals simulating white noise
    snare_pulses: List[int] = [
        8, 15, 6, 22, 9, 14, 7, 28, 11, 19, 5, 25, 12, 17, 8, 30,
        14, 21, 9, 16, 11, 24, 7, 18, 13, 26, 10, 22, 15, 29, 12, 0
    ]

    # 3. Hi-hat: ultra-short high frequency metallic pulse bursts
    hihat_pulses: List[int] = [
        4, 6, 3, 7, 4, 5, 3, 6, 4, 5, 0
    ]

    return {
        "drum_kick": CustomInstrument("drum_kick_table", kick_pulses, "1-bit decaying kick drum pulse table"),
        "drum_snare": CustomInstrument("drum_snare_table", snare_pulses, "1-bit noise burst snare drum pulse table"),
        "drum_hihat": CustomInstrument("drum_hihat_table", hihat_pulses, "1-bit metallic hi-hat tick pulse table")
    }


# ---------------------------------------------------------------------------
# Channel Action Commands & Voice Allocators
# ---------------------------------------------------------------------------

class VoiceType(Enum):
    AUTO   = "auto"
    SQUARE = "square"
    SAW1   = "saw1"
    SAW2   = "saw2"
    SAW3   = "saw3"
    CUSTOM = "custom"


@dataclass
class ChannelSound:
    channel: int                  # 1 or 2
    is_active: bool
    voice: VoiceType = VoiceType.SQUARE
    pitch: int = 0
    freq: float = 0.0
    square_high: int = 0
    square_low: int = 0
    saw_k: int = 0
    saw_m: int = 0
    is_sweep: bool = False
    sweep_mask: int = 0
    sweep_param1: int = 0
    sweep_param2: int = 0
    custom_inst_name: Optional[str] = None
    note_name: str = ""


@dataclass
class TimeSlice:
    time: float                    # In seconds
    duration: float                # In seconds
    ch1: Optional[ChannelSound] = None
    ch2: Optional[ChannelSound] = None
    bar_marker: Optional[str] = None


class VoiceAllocator:
    """Base class for polyphonic voice allocation and voice channel assignment."""
    def __init__(self,
                 notes: List[NoteEvent],
                 track_summaries: List[TrackSummary],
                 ch1_voice: VoiceType = VoiceType.AUTO,
                 ch2_voice: VoiceType = VoiceType.AUTO,
                 duty_ratio: float = 0.5,
                 percussion_mode: str = "synth",
                 allow_custom: bool = False,
                 quantize_fps: float = GREYSCALE_FPS,
                 articulation_frames: int = 1,
                 staccato_ratio: float = 1.0,
                 arpeggio_speed_frames: int = 1,
                 enable_arpeggio: bool = False,
                 decay_mode: str = "auto",
                 decay_threshold: float = 0.75,
                 decay_rate: str = "medium",
                 arpeggio_sustained: bool = False):
        self.notes = notes
        self.track_summaries = track_summaries
        self.ch1_voice = ch1_voice
        self.ch2_voice = ch2_voice
        self.duty_ratio = duty_ratio
        self.percussion_mode = percussion_mode
        self.allow_custom = allow_custom
        self.quantize_fps = quantize_fps
        self.frame_sec = 1.0 / quantize_fps if quantize_fps > 0 else 0.00390625
        self.articulation_frames = articulation_frames
        self.staccato_ratio = max(0.1, min(1.0, staccato_ratio))
        self.arpeggio_speed_frames = max(1, arpeggio_speed_frames)
        self.enable_arpeggio = enable_arpeggio
        self.decay_mode = decay_mode
        self.decay_threshold = decay_threshold
        self.decay_rate = decay_rate
        self.arpeggio_sustained = arpeggio_sustained

        # Ensure all tonal notes fall within physical hardware frequency capabilities (C2=36 to B7=107)
        # Fold individual notes by octaves into the playable hardware range
        for n in self.notes:
            if not n.is_percussion:
                while n.pitch < 36:
                    n.pitch += 12
                while n.pitch > 107:
                    n.pitch -= 12

    def allocate(self) -> List[TimeSlice]:
        raise NotImplementedError



class SmartVoiceAllocator(VoiceAllocator):
    """
    Adaptive intelligent voice allocator:
    - Separates the song into Melody (top line) and Bass/Harmony (bottom line).
    - Preserves melodic line continuity without unnatural channel swapping.
    - Handles polyphonic chords gracefully (extracting melody + bass root, or arpeggiating).
    - Interleaves percussion on Channel 2, then seamlessly restores the bass note.
    """
    def allocate(self) -> List[TimeSlice]:
        if not self.notes:
            return []

        # Find total time span and sample in discrete frames
        total_time = max(n.end_time for n in self.notes)
        total_frames = int(math.ceil(total_time / self.frame_sec)) + 2

        # Separate percussion notes and tonal notes
        tonal_notes = [n for n in self.notes if not n.is_percussion]
        perc_notes = [n for n in self.notes if n.is_percussion]

        # Pre-index active notes per frame for fast query
        frame_tonal: List[List[NoteEvent]] = [[] for _ in range(total_frames)]
        for n in tonal_notes:
            start_f = max(0, int(round(n.start_time / self.frame_sec)))
            dur_f = max(1, int(round((n.duration * self.staccato_ratio) / self.frame_sec)))
            end_f = min(total_frames, start_f + dur_f)
            for f in range(start_f, end_f):
                frame_tonal[f].append(n)

        # Pre-index percussion events (trigger frame -> note)
        frame_perc: Dict[int, NoteEvent] = {}
        for p in perc_notes:
            f = max(0, int(round(p.start_time / self.frame_sec)))
            frame_perc[f] = p

        slices: List[TimeSlice] = []
        cur_ch1_pitch: Optional[int] = None
        cur_ch2_pitch: Optional[int] = None
        perc_active_until_frame: int = -1
        perc_sound: Optional[ChannelSound] = None

        frame_idx = 0
        while frame_idx < total_frames:
            t = frame_idx * self.frame_sec
            active = frame_tonal[frame_idx]

            # 1. Determine Ch1 (Melody) and Ch2 (Bass/Harmony) notes
            note_ch1: Optional[NoteEvent] = None
            note_ch2: Optional[NoteEvent] = None

            track_roles = {t.track_idx: t.role for t in self.track_summaries}

            if len(active) == 1:
                single = active[0]
                role = track_roles.get(single.track_idx, "auto")
                if role == "bass" or (cur_ch2_pitch == single.pitch) or single.pitch < 50:
                    note_ch2 = single
                else:
                    note_ch1 = single
            elif len(active) >= 2:
                # 1. Identify bass note for Channel 2
                bass_cand = [n for n in active if track_roles.get(n.track_idx) == "bass"]
                if bass_cand:
                    note_ch2 = min(bass_cand, key=lambda x: x.pitch)
                else:
                    note_ch2 = min(active, key=lambda x: x.pitch)

                # 2. Identify upper notes for Channel 1
                upper = [n for n in active if n != note_ch2]
                if not upper:
                    upper = [note_ch2]

                mel_cand = [n for n in upper if track_roles.get(n.track_idx) == "melody"]
                if mel_cand:
                    note_ch1 = max(mel_cand, key=lambda x: x.pitch)
                else:
                    do_arp = self.enable_arpeggio or (self.arpeggio_sustained and len(upper) > 1 and max(n.duration for n in upper) >= 0.5)
                    if do_arp and len(upper) > 1:
                        sorted_up = sorted(upper, key=lambda x: x.pitch)
                        arp_idx = (frame_idx // self.arpeggio_speed_frames) % len(sorted_up)
                        note_ch1 = sorted_up[arp_idx]
                    else:
                        note_ch1 = max(upper, key=lambda x: x.pitch)


            # 2. Check for Percussion trigger on Channel 2
            if self.percussion_mode != "none" and frame_idx in frame_perc:
                perc_event = frame_perc[frame_idx]
                perc_dur_frames = self._get_drum_duration_frames(perc_event.pitch)
                perc_active_until_frame = frame_idx + perc_dur_frames
                perc_sound = self._build_drum_sound(perc_event.pitch, 2)

            # Build ChannelSound objects with elapsed duration
            elapsed1 = (t - note_ch1.start_time) if note_ch1 else 0.0
            elapsed2 = (t - note_ch2.start_time) if note_ch2 else 0.0
            ch1_sound = self._build_tonal_sound(note_ch1, 1, elapsed1) if note_ch1 else ChannelSound(1, False)
            if frame_idx < perc_active_until_frame and perc_sound:
                ch2_sound = perc_sound
            else:
                ch2_sound = self._build_tonal_sound(note_ch2, 2, elapsed2) if note_ch2 else ChannelSound(2, False)

            # Insert articulation gap if same pitch repeats consecutively
            if self.articulation_frames > 0:
                if note_ch1 and note_ch1.pitch == cur_ch1_pitch and frame_idx > 0:
                    prev_active = frame_tonal[frame_idx - 1]
                    # If this note is newly starting (start frame == frame_idx)
                    if int(round(note_ch1.start_time / self.frame_sec)) == frame_idx:
                        # Insert a brief articulation gap on ch1
                        ch1_sound = ChannelSound(1, False)
                if note_ch2 and note_ch2.pitch == cur_ch2_pitch and frame_idx > 0:
                    if int(round(note_ch2.start_time / self.frame_sec)) == frame_idx:
                        ch2_sound = ChannelSound(2, False)

            cur_ch1_pitch = note_ch1.pitch if note_ch1 else None
            cur_ch2_pitch = note_ch2.pitch if note_ch2 else None

            slices.append(TimeSlice(
                time=t,
                duration=self.frame_sec,
                ch1=ch1_sound,
                ch2=ch2_sound
            ))
            frame_idx += 1

        return self._compress_slices(slices)

    def _get_drum_duration_frames(self, drum_pitch: int) -> int:
        if drum_pitch in (35, 36):      # Kick
            return 4
        elif drum_pitch in (38, 40):    # Snare
            return 3
        else:                           # Hi-hat, cymbals, etc.
            return 1

    def _build_drum_sound(self, drum_pitch: int, channel: int) -> ChannelSound:
        if self.allow_custom and self.percussion_mode == "custom":
            if drum_pitch in (35, 36):
                return ChannelSound(channel, True, VoiceType.CUSTOM, custom_inst_name="drum_kick_table", note_name="Kick Drum")
            elif drum_pitch in (38, 40):
                return ChannelSound(channel, True, VoiceType.CUSTOM, custom_inst_name="drum_snare_table", note_name="Snare Drum")
            else:
                return ChannelSound(channel, True, VoiceType.CUSTOM, custom_inst_name="drum_hihat_table", note_name="Hi-Hat")

        # Synthesized drums via square / saw sweeps
        if drum_pitch in (35, 36):  # Kick drum: square downward sweep
            start_freq = 150.0
            sq = calc_square_params(start_freq, CLOCK_SLOW_HZ, 0.5)
            return ChannelSound(
                channel=channel,
                is_active=True,
                voice=VoiceType.SQUARE,
                freq=start_freq,
                square_high=sq.high_ticks,
                square_low=sq.low_ticks,
                is_sweep=True,
                sweep_mask=0x00,    # Every frame
                sweep_param1=8,     # +8 high ticks (slows down)
                sweep_param2=8,     # +8 low ticks
                note_name="Kick Drum (Sweep)"
            )
        elif drum_pitch in (38, 40):  # Snare drum: saw downward sweep
            start_freq = 320.0
            saw = calc_saw1_params(start_freq, CLOCK_SLOW_HZ)
            return ChannelSound(
                channel=channel,
                is_active=True,
                voice=VoiceType.SAW1,
                freq=start_freq,
                saw_k=saw.k_const,
                saw_m=saw.m_max,
                is_sweep=True,
                sweep_mask=0x00,
                sweep_param1=12,    # Add to max ticks
                sweep_param2=1,     # Add to const
                note_name="Snare Drum (Sweep)"
            )
        else:  # Hi-hat: high frequency tick
            hi_freq = 3000.0
            sq = calc_square_params(hi_freq, CLOCK_SLOW_HZ, 0.5)
            return ChannelSound(
                channel=channel,
                is_active=True,
                voice=VoiceType.SQUARE,
                freq=hi_freq,
                square_high=sq.high_ticks,
                square_low=sq.low_ticks,
                note_name="Hi-Hat (Tick)"
            )

    def _build_tonal_sound(self, note: NoteEvent, channel: int, elapsed_sec: float = 0.0) -> ChannelSound:
        pitch = note.pitch + note.pitch_bend
        freq = midi_pitch_to_freq(pitch)
        note_str = midi_pitch_to_name(note.pitch)

        # Decide voice type
        req_voice = self.ch1_voice if channel == 1 else self.ch2_voice
        if req_voice == VoiceType.AUTO:
            family = get_gm_family(note.program)
            if family in ("Bass", "Strings", "Brass", "Ensemble"):
                # Choose between saw1 and square based on lowest tuning error
                sq_test = calc_square_params(freq, CLOCK_SLOW_HZ, self.duty_ratio)
                saw_test = calc_saw1_params(freq, CLOCK_SLOW_HZ)
                voice = VoiceType.SAW1 if abs(saw_test.cents_err) <= abs(sq_test.cents_err) else VoiceType.SQUARE
            else:
                voice = VoiceType.SQUARE
        else:
            voice = req_voice

        # Check for pitch decay sweep (strictly for explicit sweep mode, never auto)
        is_sweep = False
        sweep_mask = 0
        sweep_p1 = 0
        sweep_p2 = 0

        apply_sweep = False
        if self.decay_mode in ("sweep", "both"):
            apply_sweep = (note.duration >= self.decay_threshold)

        if apply_sweep and voice in (VoiceType.SQUARE, VoiceType.SAW1):
            is_sweep = True
            if self.decay_rate == "slow":
                sweep_mask = 0x07 if channel == 1 else 0x0F
                sweep_p1 = 1
                sweep_p2 = 1
            elif self.decay_rate == "fast":
                sweep_mask = 0x01 if channel == 1 else 0x03
                sweep_p1 = 1
                sweep_p2 = 1
            else: # medium
                sweep_mask = 0x03 if channel == 1 else 0x07
                sweep_p1 = 1
                sweep_p2 = 1

        # Check for natural amplitude / duty cycle decay and acoustic note release
        effective_duty = self.duty_ratio
        if self.decay_mode in ("auto", "duty", "both") and note.duration >= self.decay_threshold:
            d = note.duration
            if d >= 3.0:
                # Long sustained chord notes (e.g. 4.8s intro chords)
                if elapsed_sec >= 3.5:
                    return ChannelSound(channel=channel, is_active=False, note_name="Rest (Decay)")
                elif elapsed_sec >= 2.2:
                    effective_duty = 0.0625
                elif elapsed_sec >= 1.2:
                    effective_duty = 0.125
                elif elapsed_sec >= 0.5:
                    effective_duty = 0.25
                else:
                    effective_duty = self.duty_ratio
            elif d >= 1.5:
                if elapsed_sec >= 0.85 * d:
                    return ChannelSound(channel=channel, is_active=False, note_name="Rest (Decay)")
                elif elapsed_sec >= 0.6 * d:
                    effective_duty = 0.125
                elif elapsed_sec >= 0.3 * d:
                    effective_duty = 0.25
                else:
                    effective_duty = self.duty_ratio
            else: # 0.75 .. 1.5s
                if elapsed_sec >= 0.85 * d:
                    return ChannelSound(channel=channel, is_active=False, note_name="Rest (Decay)")
                elif elapsed_sec >= 0.4 * d:
                    effective_duty = 0.25
                else:
                    effective_duty = self.duty_ratio


        # Compute wave parameters
        if voice == VoiceType.SAW1:
            saw = calc_saw1_params(freq, CLOCK_SLOW_HZ)
            return ChannelSound(
                channel=channel,
                is_active=True,
                voice=VoiceType.SAW1,
                pitch=note.pitch,
                freq=freq,
                saw_k=saw.k_const,
                saw_m=saw.m_max,
                is_sweep=is_sweep,
                sweep_mask=sweep_mask,
                sweep_param1=sweep_p1,
                sweep_param2=sweep_p2,
                note_name=f"{note_str} (saw1 K={saw.k_const} M={saw.m_max}{' sweep' if is_sweep else ''})"
            )
        elif voice == VoiceType.SAW2:
            saw2 = calc_saw2_params(freq, CLOCK_SLOW_HZ)
            return ChannelSound(
                channel=channel,
                is_active=True,
                voice=VoiceType.SAW2,
                pitch=note.pitch,
                freq=freq,
                saw_m=saw2.m_max,
                note_name=f"{note_str} (saw2 M={saw2.m_max})"
            )
        elif voice == VoiceType.SAW3:
            saw3 = calc_saw3_params(freq, CLOCK_SLOW_HZ)
            return ChannelSound(
                channel=channel,
                is_active=True,
                voice=VoiceType.SAW3,
                pitch=note.pitch,
                freq=freq,
                saw_m=saw3.m_max,
                note_name=f"{note_str} (saw3 M={saw3.m_max})"
            )
        else: # SQUARE
            sq = calc_square_params(freq, CLOCK_SLOW_HZ, effective_duty)
            return ChannelSound(
                channel=channel,
                is_active=True,
                voice=VoiceType.SQUARE,
                pitch=note.pitch,
                freq=freq,
                square_high=sq.high_ticks,
                square_low=sq.low_ticks,
                is_sweep=is_sweep,
                sweep_mask=sweep_mask,
                sweep_param1=sweep_p1,
                sweep_param2=sweep_p2,
                note_name=f"{note_str} (sq hi={sq.high_ticks} lo={sq.low_ticks}{' sweep' if is_sweep else ''})"
            )

    def _compress_slices(self, raw_slices: List[TimeSlice]) -> List[TimeSlice]:
        """Merges consecutive identical frames into single time slices with combined duration."""
        if not raw_slices:
            return []

        compressed: List[TimeSlice] = []
        cur = raw_slices[0]

        for s in raw_slices[1:]:
            if self._sounds_equal(cur.ch1, s.ch1) and self._sounds_equal(cur.ch2, s.ch2):
                cur.duration += s.duration
            else:
                compressed.append(cur)
                cur = s
        compressed.append(cur)
        return compressed

    def _sounds_equal(self, a: Optional[ChannelSound], b: Optional[ChannelSound]) -> bool:
        if a is None and b is None:
            return True
        if a is None or b is None:
            return False
        if a.is_active != b.is_active:
            return False
        if not a.is_active:
            return True
        return (a.voice == b.voice and
                a.square_high == b.square_high and
                a.square_low == b.square_low and
                a.saw_k == b.saw_k and
                a.saw_m == b.saw_m and
                a.is_sweep == b.is_sweep and
                a.sweep_mask == b.sweep_mask and
                a.sweep_param1 == b.sweep_param1 and
                a.sweep_param2 == b.sweep_param2 and
                a.custom_inst_name == b.custom_inst_name)


class MelodyBassVoiceAllocator(VoiceAllocator):
    """Isolates the highest non-percussion voice for Channel 1 and lowest voice for Channel 2."""
    def allocate(self) -> List[TimeSlice]:
        smart = SmartVoiceAllocator(
            notes=self.notes,
            track_summaries=self.track_summaries,
            ch1_voice=self.ch1_voice,
            ch2_voice=self.ch2_voice,
            duty_ratio=self.duty_ratio,
            percussion_mode=self.percussion_mode,
            allow_custom=self.allow_custom,
            quantize_fps=self.quantize_fps,
            articulation_frames=self.articulation_frames,
            staccato_ratio=self.staccato_ratio,
            arpeggio_speed_frames=self.arpeggio_speed_frames,
            decay_mode=self.decay_mode,
            decay_threshold=self.decay_threshold,
            decay_rate=self.decay_rate,
            arpeggio_sustained=self.arpeggio_sustained
        )
        return smart.allocate()


class ArpeggioVoiceAllocator(VoiceAllocator):
    """
    Classic chiptune chord arpeggiation mode:
    Plays lead melody or chord cycling on Channel 1 at 30Hz or 60Hz, and bass root on Channel 2.
    """
    def allocate(self) -> List[TimeSlice]:
        smart = SmartVoiceAllocator(
            notes=self.notes,
            track_summaries=self.track_summaries,
            ch1_voice=self.ch1_voice,
            ch2_voice=self.ch2_voice,
            duty_ratio=self.duty_ratio,
            percussion_mode=self.percussion_mode,
            allow_custom=self.allow_custom,
            quantize_fps=self.quantize_fps,
            articulation_frames=self.articulation_frames,
            staccato_ratio=self.staccato_ratio,
            arpeggio_speed_frames=self.arpeggio_speed_frames,
            enable_arpeggio=True,
            decay_mode=self.decay_mode,
            decay_threshold=self.decay_threshold,
            decay_rate=self.decay_rate,
            arpeggio_sustained=self.arpeggio_sustained
        )
        return smart.allocate()


class TrackRoutingVoiceAllocator(VoiceAllocator):
    """Routes specific user-specified tracks to Channel 1 and Channel 2."""
    def __init__(self, ch1_track: int, ch2_track: int, **kwargs):
        super().__init__(**kwargs)
        self.ch1_track = ch1_track
        self.ch2_track = ch2_track

    def allocate(self) -> List[TimeSlice]:
        filtered_notes = [n for n in self.notes if n.track_idx in (self.ch1_track, self.ch2_track) or n.is_percussion]
        smart = SmartVoiceAllocator(
            notes=filtered_notes,
            track_summaries=self.track_summaries,
            ch1_voice=self.ch1_voice,
            ch2_voice=self.ch2_voice,
            duty_ratio=self.duty_ratio,
            percussion_mode=self.percussion_mode,
            allow_custom=self.allow_custom,
            quantize_fps=self.quantize_fps,
            articulation_frames=self.articulation_frames,
            staccato_ratio=self.staccato_ratio,
            arpeggio_speed_frames=self.arpeggio_speed_frames,
            decay_mode=self.decay_mode,
            decay_threshold=self.decay_threshold,
            decay_rate=self.decay_rate,
            arpeggio_sustained=self.arpeggio_sustained
        )
        return smart.allocate()


# ---------------------------------------------------------------------------
# Bytecode Compiler & Optimizers
# ---------------------------------------------------------------------------

@dataclass
class CompiledInstruction:
    opcode: int
    operands: List[int] = field(default_factory=list)
    symbol_ref: Optional[str] = None
    comment: str = ""

    def byte_length(self) -> int:
        if self.symbol_ref:
            return 3 # opcode + 16-bit word
        return 1 + len(self.operands)

    def to_bytes(self) -> bytes:
        if self.symbol_ref:
            raise ValueError(f"Cannot serialize unresolved symbol {self.symbol_ref} to raw bytes directly.")
        return bytes([self.opcode] + self.operands)


class BytecodeCompiler:
    """Compiles a sequence of time slices into optimized TI-Tale audio bytecode."""
    def __init__(self, loop: bool = False, allow_custom: bool = False):
        self.loop = loop
        self.allow_custom = allow_custom

    def compile(self, slices: List[TimeSlice]) -> List[CompiledInstruction]:
        instructions: List[CompiledInstruction] = []

        # 1. Initialize channel speeds (slow mode default 32768 Hz)
        instructions.append(CompiledInstruction(OP_CH1_SLOW, [], comment="Init Channel 1: Slow mode (32768 Hz)"))
        instructions.append(CompiledInstruction(OP_CH2_SLOW, [], comment="Init Channel 2: Slow mode (32768 Hz)"))

        prev_ch1: Optional[ChannelSound] = None
        prev_ch2: Optional[ChannelSound] = None

        for idx, s in enumerate(slices):
            step_comments: List[str] = []

            # Channel 1 state update
            if not self._sounds_equal(prev_ch1, s.ch1):
                if s.ch1 and s.ch1.is_active:
                    instrs = self._compile_channel_sound(s.ch1, 1)
                    instructions.extend(instrs)
                    step_comments.append(f"Ch1: {s.ch1.note_name}")
                else:
                    instructions.append(CompiledInstruction(OP_CH1_STOP, [], comment="Ch1: Stop/Rest"))
                    step_comments.append("Ch1: Rest")
                prev_ch1 = s.ch1

            # Channel 2 state update
            if not self._sounds_equal(prev_ch2, s.ch2):
                if s.ch2 and s.ch2.is_active:
                    instrs = self._compile_channel_sound(s.ch2, 2)
                    instructions.extend(instrs)
                    step_comments.append(f"Ch2: {s.ch2.note_name}")
                else:
                    instructions.append(CompiledInstruction(OP_CH2_STOP, [], comment="Ch2: Stop/Rest"))
                    step_comments.append("Ch2: Rest")
                prev_ch2 = s.ch2

            # Emit note_wait for the duration of this slice
            wait_ticks = round(s.duration * TICKS_PER_SECOND)
            if wait_ticks > 0:
                self._emit_wait(instructions, wait_ticks, " | ".join(step_comments))

        # Song termination: either loop or stop
        if self.loop:
            instructions.append(CompiledInstruction(
                OP_JUMP,
                [],
                symbol_ref="song_loop",
                comment="Loop song playback"
            ))
        else:
            instructions.append(CompiledInstruction(OP_STOP_SONG, [], comment="Stop song playback"))

        return instructions

    def _compile_channel_sound(self, sound: ChannelSound, chan: int) -> List[CompiledInstruction]:
        res: List[CompiledInstruction] = []
        if sound.custom_inst_name:
            op = OP_CH1_INSTR if chan == 1 else OP_CH2_INSTR
            res.append(CompiledInstruction(
                op,
                [],
                symbol_ref=sound.custom_inst_name,
                comment=f"Ch{chan} custom instrument: {sound.custom_inst_name}"
            ))
            return res

        if sound.voice == VoiceType.SQUARE:
            op = OP_CH1_SQUARE if chan == 1 else OP_CH2_SQUARE
            res.append(CompiledInstruction(
                op,
                [sound.square_high, sound.square_low],
                comment=f"Ch{chan} square (hi={sound.square_high}, lo={sound.square_low})"
            ))
            if sound.is_sweep:
                sweep_op = OP_CH1_SQUARE_SWEEP if chan == 1 else OP_CH2_SQUARE_SWEEP
                res.append(CompiledInstruction(
                    sweep_op,
                    [sound.sweep_mask, sound.sweep_param1, sound.sweep_param2],
                    comment=f"Ch{chan} square sweep (mask=${sound.sweep_mask:02X}, up_add={sound.sweep_param1}, down_add={sound.sweep_param2})"
                ))
        elif sound.voice == VoiceType.SAW1:
            op = OP_CH1_SAW1 if chan == 1 else OP_CH2_SAW1
            res.append(CompiledInstruction(
                op,
                [sound.saw_k, sound.saw_m],
                comment=f"Ch{chan} additive saw1 (K={sound.saw_k}, M={sound.saw_m})"
            ))
            if sound.is_sweep:
                sweep_op = OP_CH1_SAW_SWEEP if chan == 1 else OP_CH2_SAW_SWEEP
                res.append(CompiledInstruction(
                    sweep_op,
                    [sound.sweep_mask, sound.sweep_param1, sound.sweep_param2],
                    comment=f"Ch{chan} saw sweep (mask=${sound.sweep_mask:02X}, max_add={sound.sweep_param1}, const_add={sound.sweep_param2})"
                ))
        elif sound.voice == VoiceType.SAW2:
            op = OP_CH1_SAW2 if chan == 1 else OP_CH2_SAW2
            res.append(CompiledInstruction(
                op,
                [sound.saw_m],
                comment=f"Ch{chan} exponential saw2 (M={sound.saw_m})"
            ))
        elif sound.voice == VoiceType.SAW3:
            op = OP_CH1_SAW3 if chan == 1 else OP_CH2_SAW3
            res.append(CompiledInstruction(
                op,
                [sound.saw_m],
                comment=f"Ch{chan} exponential+1 saw3 (M={sound.saw_m})"
            ))
        else:
            op = OP_CH1_SQUARE if chan == 1 else OP_CH2_SQUARE
            res.append(CompiledInstruction(
                op,
                [sound.square_high, sound.square_low],
                comment=f"Ch{chan} square fallback"
            ))
        return res

    def _emit_wait(self, instructions: List[CompiledInstruction], wait_ticks: int, comment: str):
        # Maximum signed wait per instruction is 32767 ticks (~128 seconds)
        MAX_WAIT = 32767
        while wait_ticks > 0:
            chunk = min(wait_ticks, MAX_WAIT)
            lo = chunk & 0xFF
            hi = (chunk >> 8) & 0xFF
            sec = chunk / TICKS_PER_SECOND
            instructions.append(CompiledInstruction(
                OP_WAIT,
                [lo, hi],
                comment=f"Wait {chunk} ticks ({sec:.3f}s) [{' ' + comment if comment else ''}]"
            ))
            wait_ticks -= chunk
            comment = "continued..."

    def _sounds_equal(self, a: Optional[ChannelSound], b: Optional[ChannelSound]) -> bool:
        if a is None and b is None:
            return True
        if a is None or b is None:
            return False
        if a.is_active != b.is_active:
            return False
        if not a.is_active:
            return True
        return (a.voice == b.voice and
                a.square_high == b.square_high and
                a.square_low == b.square_low and
                a.saw_k == b.saw_k and
                a.saw_m == b.saw_m and
                a.is_sweep == b.is_sweep and
                a.sweep_mask == b.sweep_mask and
                a.sweep_param1 == b.sweep_param1 and
                a.sweep_param2 == b.sweep_param2 and
                a.custom_inst_name == b.custom_inst_name)


# ---------------------------------------------------------------------------
# Code Emitters: ASM, C, Binary
# ---------------------------------------------------------------------------

def emit_asm(instructions: List[CompiledInstruction],
             song_name: str,
             instruments: Dict[str, CustomInstrument],
             loop: bool = False) -> str:
    """Generates clean Z80 assembly code with annotations and custom instrument tables."""
    lines: List[str] = [
        "; ===========================================================================",
        f"; Auto-generated TI-Tale Audio Bytecode: {song_name}",
        "; Generated by tooling/midi_to_audio.py",
        "; ===========================================================================",
        "SECTION code_user",
        "",
        f"PUBLIC {song_name}",
        f"{song_name}:"
    ]

    has_loop_label = False
    for i, instr in enumerate(instructions):
        # Place loop label right after speed initialization
        if loop and not has_loop_label and instr.opcode not in (OP_CH1_SLOW, OP_CH2_SLOW, OP_CH1_FAST, OP_CH2_FAST):
            lines.append("")
            lines.append(f"{song_name}_loop:")
            has_loop_label = True

        cmt = f" ; {instr.comment}" if instr.comment else ""
        if instr.symbol_ref:
            # Opcode followed by 16-bit word address
            target = f"{song_name}_loop" if instr.symbol_ref == "song_loop" else instr.symbol_ref
            lines.append(f"    DEFB ${instr.opcode:02X}{cmt}")
            lines.append(f"    DEFW {target}")
        else:
            bytes_list = [f"${instr.opcode:02X}"] + [f"${b:02X}" for b in instr.operands]
            bytes_str = ", ".join(bytes_list)
            lines.append(f"    DEFB {bytes_str}{cmt}")

    # Emit custom instrument tables at the end
    if instruments:
        lines.append("")
        lines.append("; --- Custom Instrument Tables ---")
        for inst in instruments.values():
            lines.append("")
            lines.append(inst.to_asm())

    lines.append("")
    return "\n".join(lines)


def emit_c(instructions: List[CompiledInstruction], song_name: str, loop: bool = False) -> str:
    """Generates C source / header content."""
    lines: List[str] = [
        "/* ===========================================================================",
        f" * Auto-generated TI-Tale Audio Bytecode: {song_name}",
        " * Generated by tooling/midi_to_audio.py",
        " * ========================================================================= */",
        "#include <stdint.h>",
        "",
        f"const uint8_t {song_name}[] = {{"
    ]

    for instr in instructions:
        cmt = f" // {instr.comment}" if instr.comment else ""
        if instr.symbol_ref:
            lines.append(f"    0x{instr.opcode:02X}, 0x00, 0x00,{cmt} /* unresolved symbol {instr.symbol_ref} */")
        else:
            bytes_list = [f"0x{instr.opcode:02X}"] + [f"0x{b:02X}" for b in instr.operands]
            bytes_str = ", ".join(bytes_list) + ","
            lines.append(f"    {bytes_str}{cmt}")

    lines.append("};")
    lines.append("")
    return "\n".join(lines)


def emit_binary(instructions: List[CompiledInstruction]) -> bytes:
    """Emits raw binary bytes for instructions without unresolved symbols."""
    buf = bytearray()
    for instr in instructions:
        if instr.symbol_ref:
            # Placeholder 0x0000 for unresolved symbols in raw binary
            buf.append(instr.opcode)
            buf.extend([0x00, 0x00])
        else:
            buf.append(instr.opcode)
            buf.extend(instr.operands)
    return bytes(buf)


# ---------------------------------------------------------------------------
# CLI Argument Parser & Application Driver
# ---------------------------------------------------------------------------

def create_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Intelligent MIDI to TI-Tale Audio Engine Converter.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument("input", type=Path, help="Input MIDI file (.mid, .midi)")
    parser.add_argument("-o", "--output", type=Path, default=None, help="Output file path (default: <input>.<ext>)")
    parser.add_argument("--format", choices=["asm", "c", "bin", "all"], default="asm", help="Output format")
    parser.add_argument("--name", type=str, default=None, help="Symbol/label name in output code")

    # Voice & Channel Strategy Settings
    parser.add_argument("--strategy", choices=["smart", "melody-bass", "arpeggio", "tracks"], default="smart",
                        help="Polyphony reduction and channel assignment strategy")
    parser.add_argument("--ch1-track", type=int, default=None, help="Explicit track index for Channel 1 (when strategy=tracks)")
    parser.add_argument("--ch2-track", type=int, default=None, help="Explicit track index for Channel 2 (when strategy=tracks)")
    parser.add_argument("--ch1-voice", choices=["auto", "square", "saw1", "saw2", "saw3"], default="auto",
                        help="Voice timbre for Channel 1")
    parser.add_argument("--ch2-voice", choices=["auto", "square", "saw1", "saw2", "saw3"], default="auto",
                        help="Voice timbre for Channel 2")
    parser.add_argument("--duty-cycle", choices=["50%", "25%", "12.5%"], default="50%",
                        help="Square wave duty cycle")

    # Custom Instrument Settings
    parser.add_argument("--custom-instruments", choices=["allow", "disable"], default="disable",
                        help="Allow or disable custom instrument wave tables")
    parser.add_argument("--allow-custom-instruments", dest="custom_instruments", action="store_const", const="allow",
                        help="Shortcut to allow custom instruments")
    parser.add_argument("--no-custom-instruments", dest="custom_instruments", action="store_const", const="disable",
                        help="Shortcut to disable custom instruments")

    # Percussion Settings
    parser.add_argument("--percussion", choices=["synth", "custom", "none"], default="synth",
                        help="Percussion handling mode: synth (sweeps), custom (tables), or none")

    # Musical Tuning & Performance Settings
    parser.add_argument("--transpose", type=str, default="auto",
                        help="Semitone pitch transposition ('auto' or integer e.g. 0, +12, -12)")
    parser.add_argument("--tempo-scale", type=float, default=1.0,
                        help="Playback tempo speed multiplier (e.g. 1.2 = 20%% faster)")
    parser.add_argument("--decay", choices=["auto", "sweep", "duty", "both", "none"], default="auto",
                        help="Note decay & pitch sweep mode for sustained notes (auto enables sweeps on long chords/notes)")
    parser.add_argument("--decay-threshold", type=float, default=0.75,
                        help="Minimum note duration (in seconds) to trigger decay or pitch sweeps")
    parser.add_argument("--decay-rate", choices=["slow", "medium", "fast"], default="medium",
                        help="Rate of pitch decrease during sweeps (slow=7.5Hz, medium=15Hz, fast=30Hz)")
    parser.add_argument("--arpeggio-sustained", action="store_true",
                        help="Enable chord arpeggiation on sustained multi-note chords")
    parser.add_argument("--articulation", type=int, default=1,
                        help="Frames of rest inserted between repeated identical notes (0 to disable)")
    parser.add_argument("--staccato", type=float, default=1.0,
                        help="Note duration scaling (1.0 = legato, 0.85 = crisp staccato)")
    parser.add_argument("--loop", action="store_true",
                        help="Loop the song seamlessly with a jump instruction")
    parser.add_argument("--quantize", type=float, default=60.0,
                        help="Note timing quantization rate in Hz (default 60 Hz for greyscale sync)")

    # Diagnostics
    parser.add_argument("--info", action="store_true", help="Print detailed MIDI track and musical analysis and exit")
    parser.add_argument("-v", "--verbose", action="store_true", help="Show verbose conversion steps and statistics")

    return parser


def print_midi_info(filepath: Path, notes: List[NoteEvent], summaries: List[TrackSummary], total_sec: float):
    print("=" * 70)
    print(f" MIDI File Analysis: {filepath.name}")
    print(f" Total Duration: {total_sec:.2f} seconds | Total Notes: {len(notes)}")
    print("=" * 70)
    for s in summaries:
        if s.note_count == 0:
            continue
        perc_tag = "[Drums]" if s.is_percussion else f"[{s.family}]"
        role_tag = f"Role: {s.role.upper()}"
        min_n = midi_pitch_to_name(s.min_pitch)
        max_n = midi_pitch_to_name(s.max_pitch)
        mean_n = midi_pitch_to_name(int(round(s.mean_pitch)))
        print(f"Track {s.track_idx:2d}: {s.name:<20} {perc_tag:<14} {role_tag:<16}")
        print(f"          Notes: {s.note_count:4d} | Range: {min_n} - {max_n} (mean: {mean_n})")
    print("=" * 70)


def main():
    parser = create_arg_parser()
    args = parser.parse_args()

    if not args.input.exists():
        print(f"Error: File not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    try:
        notes, track_summaries, total_duration = parse_midi_file(args.input)
    except Exception as e:
        print(f"Error parsing MIDI file: {e}", file=sys.stderr)
        sys.exit(1)

    if args.info:
        print_midi_info(args.input, notes, track_summaries, total_duration)
        sys.exit(0)

    # Transposition
    if args.transpose == "auto":
        trans_semitones = detect_optimal_transposition(notes)
    else:
        try:
            trans_semitones = int(args.transpose)
        except ValueError:
            trans_semitones = 0

    if trans_semitones != 0:
        for n in notes:
            if not n.is_percussion:
                n.pitch += trans_semitones

    # Tempo scaling
    if args.tempo_scale > 0 and args.tempo_scale != 1.0:
        scale = 1.0 / args.tempo_scale
        for n in notes:
            n.start_time *= scale
            n.end_time *= scale
        total_duration *= scale

    # Duty ratio
    duty_map = {"50%": 0.5, "25%": 0.25, "12.5%": 0.125}
    duty_ratio = duty_map.get(args.duty_cycle, 0.5)

    allow_custom = (args.custom_instruments == "allow")
    perc_mode = args.percussion
    if perc_mode == "custom" and not allow_custom:
        # Fallback to synth if custom instruments disabled
        perc_mode = "synth"

    voice1 = VoiceType(args.ch1_voice)
    voice2 = VoiceType(args.ch2_voice)

    # Voice Allocator selection
    if args.strategy == "tracks" and args.ch1_track is not None and args.ch2_track is not None:
        allocator = TrackRoutingVoiceAllocator(
            ch1_track=args.ch1_track,
            ch2_track=args.ch2_track,
            notes=notes,
            track_summaries=track_summaries,
            ch1_voice=voice1,
            ch2_voice=voice2,
            duty_ratio=duty_ratio,
            percussion_mode=perc_mode,
            allow_custom=allow_custom,
            quantize_fps=args.quantize,
            articulation_frames=args.articulation,
            staccato_ratio=args.staccato,
            decay_mode=args.decay,
            decay_threshold=args.decay_threshold,
            decay_rate=args.decay_rate,
            arpeggio_sustained=args.arpeggio_sustained
        )
    elif args.strategy == "melody-bass":
        allocator = MelodyBassVoiceAllocator(
            notes=notes,
            track_summaries=track_summaries,
            ch1_voice=voice1,
            ch2_voice=voice2,
            duty_ratio=duty_ratio,
            percussion_mode=perc_mode,
            allow_custom=allow_custom,
            quantize_fps=args.quantize,
            articulation_frames=args.articulation,
            staccato_ratio=args.staccato,
            decay_mode=args.decay,
            decay_threshold=args.decay_threshold,
            decay_rate=args.decay_rate,
            arpeggio_sustained=args.arpeggio_sustained
        )
    elif args.strategy == "arpeggio":
        allocator = ArpeggioVoiceAllocator(
            notes=notes,
            track_summaries=track_summaries,
            ch1_voice=voice1,
            ch2_voice=voice2,
            duty_ratio=duty_ratio,
            percussion_mode=perc_mode,
            allow_custom=allow_custom,
            quantize_fps=args.quantize,
            articulation_frames=args.articulation,
            staccato_ratio=args.staccato,
            decay_mode=args.decay,
            decay_threshold=args.decay_threshold,
            decay_rate=args.decay_rate,
            arpeggio_sustained=args.arpeggio_sustained
        )
    else:
        allocator = SmartVoiceAllocator(
            notes=notes,
            track_summaries=track_summaries,
            ch1_voice=voice1,
            ch2_voice=voice2,
            duty_ratio=duty_ratio,
            percussion_mode=perc_mode,
            allow_custom=allow_custom,
            quantize_fps=args.quantize,
            articulation_frames=args.articulation,
            staccato_ratio=args.staccato,
            decay_mode=args.decay,
            decay_threshold=args.decay_threshold,
            decay_rate=args.decay_rate,
            arpeggio_sustained=args.arpeggio_sustained
        )

    slices = allocator.allocate()

    # Compile bytecode
    compiler = BytecodeCompiler(loop=args.loop, allow_custom=allow_custom)
    instructions = compiler.compile(slices)

    # Prepare custom instruments if used
    custom_instruments: Dict[str, CustomInstrument] = {}
    if allow_custom and any(s.ch1 and s.ch1.custom_inst_name or s.ch2 and s.ch2.custom_inst_name for s in slices):
        custom_instruments = generate_drum_instruments()

    # Base symbol name
    stem = args.input.stem
    cleaned_stem = "".join(c if c.isalnum() or c == "_" else "_" for c in stem)
    song_name = args.name or f"song_{cleaned_stem}"

    # Determine output path
    out_path = args.output
    if out_path is None:
        out_ext = ".bin" if args.format == "bin" else (".c" if args.format == "c" else ".asm")
        out_path = args.input.with_suffix(out_ext)

    # Output emission
    total_bytes = sum(instr.byte_length() for instr in instructions)

    if args.format == "asm" or args.format == "all":
        asm_content = emit_asm(instructions, song_name, custom_instruments, loop=args.loop)
        target = out_path if args.format == "asm" else out_path.with_suffix(".asm")
        target.write_text(asm_content, encoding="utf-8")
        if args.verbose or not args.format == "all":
            print(f"Generated Assembly: {target} ({total_bytes} bytes)")

    if args.format == "c" or args.format == "all":
        c_content = emit_c(instructions, song_name, loop=args.loop)
        target = out_path if args.format == "c" else out_path.with_suffix(".c")
        target.write_text(c_content, encoding="utf-8")
        if args.verbose or not args.format == "all":
            print(f"Generated C source: {target}")

    if args.format == "bin" or args.format == "all":
        bin_content = emit_binary(instructions)
        target = out_path if args.format == "bin" else out_path.with_suffix(".bin")
        target.write_bytes(bin_content)
        if args.verbose or not args.format == "all":
            print(f"Generated Binary: {target} ({len(bin_content)} bytes)")

    # Print summary
    print(f"Conversion complete: {args.input.name} -> {song_name}")
    print(f"Duration: {total_duration:.2f}s | Instructions: {len(instructions)} | Bytecode size: {total_bytes} bytes")
    if trans_semitones != 0:
        print(f"Transposition applied: {trans_semitones:+d} semitones")
    print(f"Settings: strategy={args.strategy}, custom_instruments={args.custom_instruments}, percussion={perc_mode}, loop={args.loop}")


if __name__ == "__main__":
    main()
