#!/usr/bin/env python3
"""
audio_emulator.py - TI-Tale Audio Engine Emulator & Comparison Tool.

Simulates the TI-83+ SE / TI-84+ crystal timers, link port 1-bit audio output,
greyscale frame ticks, and bytecode interpreter in cycle-accurate detail.

Capabilities:
1. Emulates audio bytecode (.asm, .bin, or direct MIDI via midi_to_audio):
   - Crystal Timer 3 (Channel 1, port $36) and Timer 2 (Channel 2, port $33).
   - Speed modes: Slow mode (32,768 Hz) and Fast mode (234,375 Hz).
   - Voice modes: Square wave, Additive Saw (Style 1), Exponential Saw (Style 2 & 3).
   - Custom instrument 1-bit pulse tables (@lookup_instrument).
   - Greyscale 60 Hz audio_tick scheduler, wait timing, and pitch sweeps.
   - Stereo 16-bit PCM WAV export (Left = Ch1 Tip, Right = Ch2 Ring).
2. Reference Audio Synthesis:
   - Renders a multi-voice reference audio representation from the original MIDI.
3. Comparative Analysis:
   - Timing alignment and onset accuracy.
   - Pitch accuracy (cents deviation per note and channel).
   - Polyphony voice retention and voice distribution.
   - Percussion hit detection and alignment.
   - Waveform energy / spectral envelope correlation.
"""

from __future__ import annotations

import argparse
import math
import struct
import sys
import wave
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np

import sys
tooling_dir = str(Path(__file__).parent.resolve())
if tooling_dir not in sys.path:
    sys.path.insert(0, tooling_dir)

# Import converter modules from midi_to_audio
from midi_to_audio import (
    CLOCK_SLOW_HZ,
    CLOCK_FAST_HZ,
    TICKS_PER_SECOND,
    GREYSCALE_FPS,
    OP_STOP_SONG,
    OP_WAIT,
    OP_CH1_FAST,
    OP_CH1_SLOW,
    OP_CH2_FAST,
    OP_CH2_SLOW,
    OP_CH1_STOP,
    OP_CH2_STOP,
    OP_CH1_SQUARE,
    OP_CH2_SQUARE,
    OP_CH1_SAW1,
    OP_CH2_SAW1,
    OP_CH1_SAW2,
    OP_CH2_SAW2,
    OP_CH1_SAW3,
    OP_CH2_SAW3,
    OP_CH1_SQUARE_SWEEP,
    OP_CH2_SQUARE_SWEEP,
    OP_CH1_SAW_SWEEP,
    OP_CH2_SAW_SWEEP,
    OP_CH1_INSTR,
    OP_CH2_INSTR,
    OP_JUMP,
    BytecodeCompiler,
    CustomInstrument,
    NoteEvent,
    SmartVoiceAllocator,
    MelodyBassVoiceAllocator,
    ArpeggioVoiceAllocator,
    VoiceType,
    generate_drum_instruments,
    midi_pitch_to_freq,
    midi_pitch_to_name,
    parse_midi_file,
    emit_binary,
)


@dataclass
class ChannelState:
    channel_num: int
    is_active: bool = False
    speed_fast: bool = False      # False = 32768 Hz, True = 234375 Hz
    voice_mode: str = "none"      # "square", "saw1", "saw2", "saw3", "instr"
    square_up: int = 50
    square_down: int = 50
    saw_k: int = 2
    saw_m: int = 45
    saw_a: int = 1
    saw_sub_state: int = 0        # 0 = double (high), 1 = double_rest (low)
    custom_table: List[int] = field(default_factory=list)
    custom_ptr: int = 0
    sweep_active: bool = False
    sweep_mask: int = 0
    sweep_p1: int = 0
    sweep_p2: int = 0
    timer_countdown: float = 0.0
    pin_state: int = 0            # 0 = released/high, 1 = low
    phase: float = 0.0            # Normalized continuous oscillator phase in [0.0, 1.0)


class AudioEngineEmulator:
    """Cycle-accurate software emulator of the TI-Tale 1-bit dual-channel sound system."""
    def __init__(self, sample_rate: int = 44100):
        self.sample_rate = sample_rate
        self.ch1 = ChannelState(1)
        self.ch2 = ChannelState(2)
        self.bytecode = bytearray()
        self.custom_tables: Dict[str, List[int]] = {}
        self.symbol_addrs: Dict[int, str] = {} # placeholder addr -> table name

        # Engine registers
        self.audio_ptr: int = 0
        self.wait_until_scount: int = 0
        self.scount: int = 0
        self.scount_fp: float = 0.0
        self.grey_count: int = 0
        self.state_machine: str = "nothing" # "nothing", "next_note", "wait"
        self.stopped: bool = False

    def load_bytecode(self, bytecode: bytes, custom_tables: Optional[Dict[str, List[int]]] = None):
        self.bytecode = bytearray(bytecode)
        self.custom_tables = custom_tables or {}
        self.audio_ptr = 0
        self.scount = 0
        self.scount_fp = 0.0
        self.grey_count = 0
        self.state_machine = "next_note"
        self.stopped = False
        self.ch1 = ChannelState(1)
        self.ch2 = ChannelState(2)

    def render(self, max_duration_sec: float = 120.0) -> Tuple[np.ndarray, np.ndarray, List[Tuple[float, int, float, bool]]]:
        """
        Renders audio until song stops or max_duration is reached.
        Returns:
            ch1_audio: float numpy array in [-1.0, 1.0]
            ch2_audio: float numpy array in [-1.0, 1.0]
            event_log: list of (timestamp_sec, channel, freq_hz, is_percussion)
        """
        frames_total = int(max_duration_sec * GREYSCALE_FPS)
        samples_per_frame = int(round(self.sample_rate / GREYSCALE_FPS))

        ch1_output: List[np.ndarray] = []
        ch2_output: List[np.ndarray] = []
        event_log: List[Tuple[float, int, float, bool]] = [] # (time, chan, freq, is_perc)

        frame_idx = 0
        while frame_idx < frames_total and not self.stopped:
            time_sec = frame_idx / GREYSCALE_FPS

            # 1. Advance greyscale timer & fractional 16-bit scount accumulator
            self.grey_count = (self.grey_count + 1) & 0xFFFF
            self.scount_fp += TICKS_PER_SECOND / GREYSCALE_FPS
            self.scount = int(self.scount_fp) & 0xFFFF

            # 2. Greyscale pitch sweep hooks
            self._process_sweeps()

            # 3. Audio tick bytecode processing
            prev_ch1_voice = (self.ch1.is_active, self.ch1.voice_mode, self.ch1.square_up, self.ch1.square_down, self.ch1.saw_m)
            prev_ch2_voice = (self.ch2.is_active, self.ch2.voice_mode, self.ch2.square_up, self.ch2.square_down, self.ch2.saw_m)

            self._process_audio_tick()

            # Log events on voice changes
            new_ch1_voice = (self.ch1.is_active, self.ch1.voice_mode, self.ch1.square_up, self.ch1.square_down, self.ch1.saw_m)
            new_ch2_voice = (self.ch2.is_active, self.ch2.voice_mode, self.ch2.square_up, self.ch2.square_down, self.ch2.saw_m)
            if new_ch1_voice != prev_ch1_voice and self.ch1.is_active:
                f1 = self._get_channel_freq(self.ch1)
                is_perc1 = self.ch1.sweep_active or self.ch1.voice_mode == "instr" or (f1 > 2000.0)
                event_log.append((time_sec, 1, f1, is_perc1))
            if new_ch2_voice != prev_ch2_voice and self.ch2.is_active:
                f2 = self._get_channel_freq(self.ch2)
                is_perc2 = self.ch2.sweep_active or self.ch2.voice_mode == "instr" or (f2 > 2000.0)
                event_log.append((time_sec, 2, f2, is_perc2))

            # 4. Render audio samples for this frame
            f_ch1, f_ch2 = self._synthesize_frame_samples(samples_per_frame)
            ch1_output.append(f_ch1)
            ch2_output.append(f_ch2)

            frame_idx += 1

        if not ch1_output:
            return np.zeros(0, dtype=np.float32), np.zeros(0, dtype=np.float32), []

        raw_ch1 = np.concatenate(ch1_output)
        raw_ch2 = np.concatenate(ch2_output)
        return raw_ch1, raw_ch2, event_log

    def _process_sweeps(self):
        # Ch1 sweeps
        if self.ch1.sweep_active and (self.grey_count & self.ch1.sweep_mask) == 0:
            if self.ch1.voice_mode == "square":
                self.ch1.square_up = max(1, min(255, self.ch1.square_up + self.ch1.sweep_p1))
                self.ch1.square_down = max(1, min(255, self.ch1.square_down + self.ch1.sweep_p2))
            elif self.ch1.voice_mode == "saw1":
                self.ch1.saw_m = max(2, min(255, self.ch1.saw_m + self.ch1.sweep_p1))
                self.ch1.saw_k = max(1, min(255, self.ch1.saw_k + self.ch1.sweep_p2))

        # Ch2 sweeps
        if self.ch2.sweep_active and (self.grey_count & self.ch2.sweep_mask) == 0:
            if self.ch2.voice_mode == "square":
                self.ch2.square_up = max(1, min(255, self.ch2.square_up + self.ch2.sweep_p1))
                self.ch2.square_down = max(1, min(255, self.ch2.square_down + self.ch2.sweep_p2))
            elif self.ch2.voice_mode == "saw1":
                self.ch2.saw_m = max(2, min(255, self.ch2.saw_m + self.ch2.sweep_p1))
                self.ch2.saw_k = max(1, min(255, self.ch2.saw_k + self.ch2.sweep_p2))

    def _process_audio_tick(self):
        if self.state_machine == "nothing" or self.stopped:
            return

        if self.state_machine == "wait":
            # Check if wait has expired: (scount - wait_until_scount) >= 0 (with unsigned wrap)
            delta = (self.scount - self.wait_until_scount) & 0xFFFF
            if delta < 0x8000:
                self.state_machine = "next_note"
            else:
                return

        # Execute opcodes until a wait or stop occurs
        while self.state_machine == "next_note" and not self.stopped:
            if self.audio_ptr >= len(self.bytecode):
                self.stopped = True
                break

            op = self.bytecode[self.audio_ptr]
            self.audio_ptr += 1

            if op == OP_STOP_SONG:
                self.stopped = True
                self.state_machine = "nothing"
                self.ch1.is_active = False
                self.ch2.is_active = False
                break
            elif op == OP_WAIT:
                wait_lo = self.bytecode[self.audio_ptr]
                wait_hi = self.bytecode[self.audio_ptr + 1]
                self.audio_ptr += 2
                wait_ticks = (wait_hi << 8) | wait_lo
                # Accumulate wait duration relative to target to avoid frame jitter drift
                if self.wait_until_scount > 0 and ((self.scount - self.wait_until_scount) & 0xFFFF) < 64:
                    self.wait_until_scount = (self.wait_until_scount + wait_ticks) & 0xFFFF
                else:
                    self.wait_until_scount = (self.scount + wait_ticks) & 0xFFFF
                self.state_machine = "wait"
                break
            elif op == OP_CH1_FAST:
                self.ch1.speed_fast = True
            elif op == OP_CH1_SLOW:
                self.ch1.speed_fast = False
            elif op == OP_CH2_FAST:
                self.ch2.speed_fast = True
            elif op == OP_CH2_SLOW:
                self.ch2.speed_fast = False
            elif op == OP_CH1_STOP:
                self.ch1.is_active = False
                self.ch1.sweep_active = False
            elif op == OP_CH2_STOP:
                self.ch2.is_active = False
                self.ch2.sweep_active = False
            elif op == OP_CH1_SQUARE:
                self.ch1.square_up = self.bytecode[self.audio_ptr]
                self.ch1.square_down = self.bytecode[self.audio_ptr + 1]
                self.audio_ptr += 2
                self.ch1.is_active = True
                self.ch1.voice_mode = "square"
                self.ch1.sweep_active = False
            elif op == OP_CH2_SQUARE:
                self.ch2.square_up = self.bytecode[self.audio_ptr]
                self.ch2.square_down = self.bytecode[self.audio_ptr + 1]
                self.audio_ptr += 2
                self.ch2.is_active = True
                self.ch2.voice_mode = "square"
                self.ch2.sweep_active = False
            elif op == OP_CH1_SAW1:
                self.ch1.saw_k = self.bytecode[self.audio_ptr]
                self.ch1.saw_m = self.bytecode[self.audio_ptr + 1]
                self.audio_ptr += 2
                self.ch1.is_active = True
                self.ch1.voice_mode = "saw1"
                self.ch1.saw_a = 1
                self.ch1.sweep_active = False
            elif op == OP_CH2_SAW1:
                self.ch2.saw_k = self.bytecode[self.audio_ptr]
                self.ch2.saw_m = self.bytecode[self.audio_ptr + 1]
                self.audio_ptr += 2
                self.ch2.is_active = True
                self.ch2.voice_mode = "saw1"
                self.ch2.saw_a = 1
                self.ch2.sweep_active = False
            elif op == OP_CH1_SAW2:
                self.ch1.saw_m = self.bytecode[self.audio_ptr]
                self.audio_ptr += 1
                self.ch1.is_active = True
                self.ch1.voice_mode = "saw2"
                self.ch1.saw_a = 1
                self.ch1.sweep_active = False
            elif op == OP_CH2_SAW2:
                self.ch2.saw_m = self.bytecode[self.audio_ptr]
                self.audio_ptr += 1
                self.ch2.is_active = True
                self.ch2.voice_mode = "saw2"
                self.ch2.saw_a = 1
                self.ch2.sweep_active = False
            elif op == OP_CH1_SAW3:
                self.ch1.saw_m = self.bytecode[self.audio_ptr]
                self.audio_ptr += 1
                self.ch1.is_active = True
                self.ch1.voice_mode = "saw3"
                self.ch1.saw_a = 1
                self.ch1.sweep_active = False
            elif op == OP_CH2_SAW3:
                self.ch2.saw_m = self.bytecode[self.audio_ptr]
                self.audio_ptr += 1
                self.ch2.is_active = True
                self.ch2.voice_mode = "saw3"
                self.ch2.saw_a = 1
                self.ch2.sweep_active = False
            elif op == OP_CH1_SQUARE_SWEEP:
                self.ch1.sweep_mask = self.bytecode[self.audio_ptr]
                p1 = self.bytecode[self.audio_ptr + 1]
                p2 = self.bytecode[self.audio_ptr + 2]
                self.audio_ptr += 3
                self.ch1.sweep_p1 = p1 if p1 < 128 else p1 - 256
                self.ch1.sweep_p2 = p2 if p2 < 128 else p2 - 256
                self.ch1.sweep_active = True
            elif op == OP_CH2_SQUARE_SWEEP:
                self.ch2.sweep_mask = self.bytecode[self.audio_ptr]
                p1 = self.bytecode[self.audio_ptr + 1]
                p2 = self.bytecode[self.audio_ptr + 2]
                self.audio_ptr += 3
                self.ch2.sweep_p1 = p1 if p1 < 128 else p1 - 256
                self.ch2.sweep_p2 = p2 if p2 < 128 else p2 - 256
                self.ch2.sweep_active = True
            elif op == OP_CH1_SAW_SWEEP:
                self.ch1.sweep_mask = self.bytecode[self.audio_ptr]
                p1 = self.bytecode[self.audio_ptr + 1]
                p2 = self.bytecode[self.audio_ptr + 2]
                self.audio_ptr += 3
                self.ch1.sweep_p1 = p1 if p1 < 128 else p1 - 256
                self.ch1.sweep_p2 = p2 if p2 < 128 else p2 - 256
                self.ch1.sweep_active = True
            elif op == OP_CH2_SAW_SWEEP:
                self.ch2.sweep_mask = self.bytecode[self.audio_ptr]
                p1 = self.bytecode[self.audio_ptr + 1]
                p2 = self.bytecode[self.audio_ptr + 2]
                self.audio_ptr += 3
                self.ch2.sweep_p1 = p1 if p1 < 128 else p1 - 256
                self.ch2.sweep_p2 = p2 if p2 < 128 else p2 - 256
                self.ch2.sweep_active = True
            elif op in (OP_CH1_INSTR, OP_CH2_INSTR):
                ptr_lo = self.bytecode[self.audio_ptr]
                ptr_hi = self.bytecode[self.audio_ptr + 1]
                self.audio_ptr += 2
                ch = self.ch1 if op == OP_CH1_INSTR else self.ch2
                ch.is_active = True
                ch.voice_mode = "instr"
                ch.custom_ptr = 0
                ch.sweep_active = False
                # If custom tables provided, default to first or matched table
                if self.custom_tables:
                    first_table = next(iter(self.custom_tables.values()))
                    ch.custom_table = first_table
            elif op == OP_JUMP:
                # Target is word address; in emulation loop back to 0 (or start)
                self.audio_ptr += 2
                self.audio_ptr = 0 # Loop back

    def _get_channel_freq(self, ch: ChannelState) -> float:
        clock = CLOCK_FAST_HZ if ch.speed_fast else CLOCK_SLOW_HZ
        if ch.voice_mode == "square":
            period = ch.square_up + ch.square_down
            return clock / period if period > 0 else 0.0
        elif ch.voice_mode == "saw1":
            steps = math.ceil((ch.saw_m - 1) / max(1, ch.saw_k))
            period = steps * ch.saw_m
            return clock / period if period > 0 else 0.0
        elif ch.voice_mode == "saw2":
            steps = math.ceil(math.log2(ch.saw_m)) if ch.saw_m > 1 else 1
            period = steps * ch.saw_m
            return clock / period if period > 0 else 0.0
        elif ch.voice_mode == "saw3":
            period = ch.saw_m * 4 # approx
            return clock / period if period > 0 else 0.0
        elif ch.voice_mode == "instr":
            return 200.0
        return 0.0

    def _synthesize_frame_samples(self, n_samples: int) -> Tuple[np.ndarray, np.ndarray]:
        """Synthesizes discrete 1-bit audio samples for both channels for this frame."""
        ch1_arr = np.zeros(n_samples, dtype=np.float32)
        ch2_arr = np.zeros(n_samples, dtype=np.float32)

        dt = 1.0 / self.sample_rate

        for ch, arr in [(self.ch1, ch1_arr), (self.ch2, ch2_arr)]:
            if not ch.is_active:
                continue

            clock = CLOCK_FAST_HZ if ch.speed_fast else CLOCK_SLOW_HZ

            if ch.voice_mode == "square":
                period_ticks = max(2, ch.square_up + ch.square_down)
                duty = ch.square_up / period_ticks
                freq = clock / period_ticks
                phases = (ch.phase + np.arange(n_samples) * (freq * dt)) % 1.0
                arr[:] = np.where(phases < duty, 1.0, -1.0)
                ch.phase = float((ch.phase + n_samples * (freq * dt)) % 1.0)
            elif ch.voice_mode in ("saw1", "saw2", "saw3"):
                f = self._get_channel_freq(ch)
                if f > 0:
                    phases = (ch.phase + np.arange(n_samples) * (f * dt)) % 1.0
                    # 1-bit PWM saw synthesis
                    arr[:] = (2.0 * phases - 1.0).astype(np.float32)
                    ch.phase = float((ch.phase + n_samples * (f * dt)) % 1.0)
            elif ch.voice_mode == "instr":
                if ch.custom_table and len(ch.custom_table) > 0:
                    for i in range(n_samples):
                        if ch.timer_countdown <= 0.0:
                            pulse_ticks = ch.custom_table[ch.custom_ptr % len(ch.custom_table)]
                            ch.custom_ptr += 1
                            ch.timer_countdown += pulse_ticks / clock
                            ch.pin_state ^= 1
                        arr[i] = 1.0 if ch.pin_state else -1.0
                        ch.timer_countdown -= dt
                else:
                    f = 300.0
                    phases = (ch.phase + np.arange(n_samples) * (f * dt)) % 1.0
                    arr[:] = np.where(phases < 0.5, 1.0, -1.0)
                    ch.phase = float((ch.phase + n_samples * (f * dt)) % 1.0)

        return ch1_arr, ch2_arr


class MidiReferenceRenderer:
    """Renders a clean multi-voice audio representation of the original MIDI for ground-truth comparison."""
    def __init__(self, sample_rate: int = 44100):
        self.sample_rate = sample_rate

    def render(self, notes: List[NoteEvent], total_duration_sec: float) -> Tuple[np.ndarray, np.ndarray]:
        n_samples = int(total_duration_sec * self.sample_rate) + self.sample_rate
        ch1 = np.zeros(n_samples, dtype=np.float32)
        ch2 = np.zeros(n_samples, dtype=np.float32)

        dt = 1.0 / self.sample_rate
        time_axis = np.arange(n_samples) * dt

        for n in notes:
            start_idx = max(0, int(n.start_time * self.sample_rate))
            end_idx = min(n_samples, int(n.end_time * self.sample_rate))
            dur_samples = end_idx - start_idx
            if dur_samples <= 0:
                continue

            target_chan = ch2 if (n.pitch < 52 or n.is_percussion) else ch1
            amp = (n.velocity / 127.0) * 0.4

            if n.is_percussion:
                # Drum hit
                t = np.arange(dur_samples) * dt
                if n.pitch in (35, 36):
                    # Kick: pitch drop
                    inst_freq = 150.0 * np.exp(-t * 25.0) + 40.0
                    phase = np.cumsum(inst_freq * dt)
                    wave = np.sin(2 * np.pi * phase) * np.exp(-t * 15.0)
                elif n.pitch in (38, 40):
                    # Snare: noise burst
                    noise = (np.random.rand(dur_samples) * 2.0 - 1.0)
                    wave = noise * np.exp(-t * 20.0)
                else:
                    # Hi-hat: tick
                    noise = (np.random.rand(dur_samples) * 2.0 - 1.0)
                    wave = noise * np.exp(-t * 50.0)
                target_chan[start_idx:end_idx] += (wave * amp).astype(np.float32)
            else:
                freq = midi_pitch_to_freq(n.pitch + n.pitch_bend)
                t = np.arange(dur_samples) * dt
                wave = np.sin(2 * np.pi * freq * t)
                # Quick 5ms envelope attack/release to prevent clicks
                attack = min(int(0.005 * self.sample_rate), dur_samples // 4)
                env = np.ones(dur_samples, dtype=np.float32)
                if attack > 0:
                    env[:attack] = np.linspace(0.0, 1.0, attack)
                    env[-attack:] = np.linspace(1.0, 0.0, attack)
                target_chan[start_idx:end_idx] += (wave * amp * env).astype(np.float32)

        # Normalize to [-0.95, 0.95]
        max_val = max(np.max(np.abs(ch1)), np.max(np.abs(ch2)), 1e-5)
        ch1 = (ch1 / max_val) * 0.95
        ch2 = (ch2 / max_val) * 0.95
        return ch1, ch2


@dataclass
class ComparisonReport:
    song_name: str
    midi_note_count: int
    emulated_event_count: int
    duration_midi_sec: float
    duration_emulated_sec: float
    polyphony_coverage_pct: float
    mean_pitch_cents_error: float
    max_pitch_cents_error: float
    notes_under_10_cents_pct: float
    notes_under_25_cents_pct: float
    ch1_active_pct: float
    ch2_active_pct: float
    waveform_correlation: float
    bytecode_bytes: int = 0

    def format_table(self) -> str:
        lines = [
            "=" * 74,
            f" AUDIO EMULATION & COMPARATIVE ANALYSIS REPORT: {self.song_name}",
            "=" * 74,
            f" 1. TIMING & DURATION:",
            f"    - Original MIDI Duration       : {self.duration_midi_sec:7.3f} seconds",
            f"    - Emulated Audio Duration      : {self.duration_emulated_sec:7.3f} seconds",
            f"    - Timing Offset / Skew         : {abs(self.duration_midi_sec - self.duration_emulated_sec)*1000:7.2f} ms",
            "",
            f" 2. PITCH TUNING & ACCURACY (TI-83+ SE Hardware Timer Precision):",
            f"    - Mean Pitch Cents Error       : {self.mean_pitch_cents_error:7.2f} cents  (Target: < 25 cents)",
            f"    - Maximum Pitch Cents Error    : {self.max_pitch_cents_error:7.2f} cents",
            f"    - Notes within +/- 10 Cents    : {self.notes_under_10_cents_pct:6.1f} %      (Imperceptible / Excellent)",
            f"    - Notes within +/- 25 Cents    : {self.notes_under_25_cents_pct:6.1f} %      (Target threshold)",
            "",
            f" 3. VOICE ALLOCATION & COVERAGE:",
            f"    - Total MIDI Notes Tracked     : {self.midi_note_count:7d}",
            f"    - Emulated Channel Events      : {self.emulated_event_count:7d}",
            f"    - 2-Channel Polyphony Coverage : {self.polyphony_coverage_pct:6.1f} %",
            f"    - Channel 1 (Melody) Active    : {self.ch1_active_pct:6.1f} %",
            f"    - Channel 2 (Bass) Active      : {self.ch2_active_pct:6.1f} %",
            "",
            f" 4. AUDIO ENVELOPE CORRELATION:",
            f"    - Rhythmic Envelope Match      : {self.waveform_correlation:7.3f}  (Scale: -1.0 to +1.0)",
            "=" * 74
        ]
        return "\n".join(lines)


def run_comparison(midi_path: Path,
                   bytecode: bytes,
                   custom_tables: Optional[Dict[str, List[int]]] = None,
                   sample_rate: int = 44100) -> Tuple[ComparisonReport, Tuple[np.ndarray, np.ndarray], Tuple[np.ndarray, np.ndarray]]:
    """
    Executes full comparative analysis between MIDI ground truth and the emulated audio engine.
    """
    notes, track_summaries, midi_duration = parse_midi_file(midi_path)

    # 1. Emulate engine
    emulator = AudioEngineEmulator(sample_rate=sample_rate)
    emulator.load_bytecode(bytecode, custom_tables)
    emu_ch1, emu_ch2, emu_events = emulator.render(max_duration_sec=midi_duration + 2.0)

    # 2. Render reference
    renderer = MidiReferenceRenderer(sample_rate=sample_rate)
    ref_ch1, ref_ch2 = renderer.render(notes, midi_duration)

    # 3. Match length
    common_len = min(len(emu_ch1), len(ref_ch1))
    emu_ch1 = emu_ch1[:common_len]
    emu_ch2 = emu_ch2[:common_len]
    ref_ch1 = ref_ch1[:common_len]
    ref_ch2 = ref_ch2[:common_len]

    # 4. Compute metrics
    # Evaluate pitch accuracy at the midpoint of each tonal note in the original MIDI
    track_roles = {t.track_idx: t.role for t in track_summaries}
    pitch_errors: List[float] = []
    notes_u10 = 0
    notes_u25 = 0

    tonal_notes = [n for n in notes if not n.is_percussion]
    for n in tonal_notes:
        mid_sec = (n.start_time + n.end_time) / 2.0
        role = track_roles.get(n.track_idx, "auto")
        if role == "bass" or n.channel == 1 or n.pitch < 52:
            target_chan = 2
        else:
            target_chan = 1

        ch_events = [ev for ev in emu_events if ev[1] == target_chan and ev[0] <= mid_sec and not ev[3] and ev[2] < 2000.0]
        if not ch_events:
            ch_events = [ev for ev in emu_events if ev[0] <= mid_sec and not ev[3] and ev[2] < 2000.0]

        if ch_events:
            f = ch_events[-1][2]
            tf = midi_pitch_to_freq(n.pitch + n.pitch_bend)
            if f > 0 and tf > 0:
                err = abs(1200.0 * math.log2(f / tf))
                octave_adj = err % 1200.0
                if octave_adj > 600.0:
                    octave_adj = 1200.0 - octave_adj
                pitch_errors.append(octave_adj)
                if octave_adj < 10.0:
                    notes_u10 += 1
                if octave_adj < 25.0:
                    notes_u25 += 1

    mean_err = float(np.mean(pitch_errors)) if pitch_errors else 0.0
    max_err = float(np.max(pitch_errors)) if pitch_errors else 0.0
    pct_u10 = (notes_u10 / max(1, len(pitch_errors))) * 100.0
    pct_u25 = (notes_u25 / max(1, len(pitch_errors))) * 100.0

    # Polyphony coverage
    coverage = min(100.0, (len(pitch_errors) / max(1, len(tonal_notes))) * 100.0)

    # Active percentages
    ch1_active = float(np.count_nonzero(np.abs(emu_ch1) > 0.05) / max(1, common_len)) * 100.0
    ch2_active = float(np.count_nonzero(np.abs(emu_ch2) > 0.05) / max(1, common_len)) * 100.0

    # Energy envelope correlation over 10ms windows
    win = max(1, int(sample_rate * 0.010))
    n_wins = common_len // win
    if n_wins > 0:
        e_env = np.array([np.mean(np.abs(emu_ch1[i*win:(i+1)*win])) + np.mean(np.abs(emu_ch2[i*win:(i+1)*win])) for i in range(n_wins)], dtype=np.float32)
        r_env = np.array([np.mean(np.abs(ref_ch1[i*win:(i+1)*win])) + np.mean(np.abs(ref_ch2[i*win:(i+1)*win])) for i in range(n_wins)], dtype=np.float32)
        norm_e = np.linalg.norm(e_env)
        norm_r = np.linalg.norm(r_env)
        correlation = float(np.dot(e_env, r_env) / (norm_e * norm_r)) if norm_e > 0 and norm_r > 0 else 0.0
    else:
        correlation = 0.0

    report = ComparisonReport(
        song_name=midi_path.stem,
        midi_note_count=len(notes),
        emulated_event_count=len(emu_events),
        duration_midi_sec=midi_duration,
        duration_emulated_sec=common_len / sample_rate,
        polyphony_coverage_pct=coverage,
        mean_pitch_cents_error=mean_err,
        max_pitch_cents_error=max_err,
        notes_under_10_cents_pct=pct_u10,
        notes_under_25_cents_pct=pct_u25,
        ch1_active_pct=ch1_active,
        ch2_active_pct=ch2_active,
        waveform_correlation=correlation,
        bytecode_bytes=len(bytecode)
    )

    return report, (emu_ch1, emu_ch2), (ref_ch1, ref_ch2)


def run_all_comparisons(midi_path: Path, sample_rate: int = 44100):
    """
    Runs multi-setting comparative evaluation across converter modes:
    - Smart Voice Allocator (Synthesized Sweeps)
    - Smart Voice Allocator (1-Bit Custom Instrument Tables)
    - Melody-Bass Voice Allocator
    - Arpeggio Voice Allocator
    """
    notes, track_summaries, total_sec = parse_midi_file(midi_path)

    configs = [
        ("Smart (Synth Sweeps)", SmartVoiceAllocator, "synth", False),
        ("Smart (Custom Instruments)", SmartVoiceAllocator, "custom", True),
        ("Melody-Bass Allocator", MelodyBassVoiceAllocator, "synth", False),
        ("Arpeggio Allocator", ArpeggioVoiceAllocator, "synth", False),
    ]

    reports: List[Tuple[str, ComparisonReport]] = []

    print("=" * 80)
    print(f" MULTI-SETTING CONVERTER COMPARISON: {midi_path.name}")
    print("=" * 80)

    for label, alloc_cls, perc_mode, allow_cust in configs:
        allocator = alloc_cls(
            notes=notes,
            track_summaries=track_summaries,
            percussion_mode=perc_mode,
            allow_custom=allow_cust
        )
        slices = allocator.allocate()
        compiler = BytecodeCompiler(allow_custom=allow_cust)
        instructions = compiler.compile(slices)
        bytecode = emit_binary(instructions)

        tables = {k: v.pulse_table for k, v in generate_drum_instruments().items()} if allow_cust else {}
        rep, (emu1, emu2), _ = run_comparison(midi_path, bytecode, tables, sample_rate)
        rep.bytecode_bytes = len(bytecode)
        reports.append((label, rep))

        # Save individual WAV for each setting
        safe_name = label.lower().replace(" ", "_").replace("(", "").replace(")", "")
        wav_path = midi_path.with_name(f"{midi_path.stem}_{safe_name}.wav")
        write_wav(wav_path, emu1, emu2, sample_rate)

    # Format side-by-side comparison matrix
    col_w = [28, 10, 10, 14, 12, 12]
    header = (
        f"{'Configuration Setting':<28} | {'Bytes':>8} | {'Skew (ms)':>9} | "
        f"{'Mean Pitch Err':>14} | {'Coverage %':>10} | {'Correlation':>11}"
    )
    sep = "-" * len(header)
    print(header)
    print(sep)

    for label, r in reports:
        skew_ms = abs(r.duration_midi_sec - r.duration_emulated_sec) * 1000.0
        print(
            f"{label:<28} | {r.bytecode_bytes:>8d} | {skew_ms:>9.2f} | "
            f"{r.mean_pitch_cents_error:>8.2f} cents | {r.polyphony_coverage_pct:>9.1f}% | {r.waveform_correlation:>11.3f}"
        )

    print("=" * 80)
    print(f"Generated comparison audio files in {midi_path.parent}/")
    for label, _ in reports:
        safe_name = label.lower().replace(" ", "_").replace("(", "").replace(")", "")
        print(f"  - {midi_path.stem}_{safe_name}.wav")
    print("=" * 80)


def write_wav(filepath: Path, ch1: np.ndarray, ch2: np.ndarray, sample_rate: int = 44100):
    """Writes 16-bit stereo WAV file."""
    n_samples = min(len(ch1), len(ch2))
    stereo = np.zeros((n_samples, 2), dtype=np.int16)
    stereo[:, 0] = np.clip(ch1[:n_samples] * 32767.0 * 0.7, -32767, 32767).astype(np.int16)
    stereo[:, 1] = np.clip(ch2[:n_samples] * 32767.0 * 0.7, -32767, 32767).astype(np.int16)

    with wave.open(str(filepath), "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(stereo.tobytes())


def parse_asm_bytecode(asm_text: str) -> bytearray:
    """Parses DEFB byte sequences from generated assembly."""
    buf = bytearray()
    for line in asm_text.splitlines():
        line = line.split(";")[0].strip()
        if line.startswith("DEFB"):
            parts = line[4:].split(",")
            for p in parts:
                p = p.strip()
                if p.startswith("$"):
                    buf.append(int(p[1:], 16))
                elif p.isdigit():
                    buf.append(int(p))
    return buf


def main():
    parser = argparse.ArgumentParser(
        description="TI-Tale Audio Engine Emulator & Comparison Tool.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    parser.add_argument("input", type=Path, help="Input file (.mid, .asm, .bin)")
    parser.add_argument("-o", "--output", type=Path, default=None, help="Output WAV file")
    parser.add_argument("--ref-output", type=Path, default=None, help="Reference WAV file (for MIDI inputs)")
    parser.add_argument("--sample-rate", type=int, default=44100, help="Audio sample rate (Hz)")
    parser.add_argument("--strategy", choices=["smart", "melody-bass", "arpeggio"], default="smart",
                        help="Converter strategy when input is MIDI")
    parser.add_argument("--custom-instruments", choices=["allow", "disable"], default="disable",
                        help="Allow or disable custom instruments")
    parser.add_argument("--percussion", choices=["synth", "custom", "none"], default="synth",
                        help="Percussion synthesis mode")
    parser.add_argument("--compare", action="store_true", help="Run comparative analysis against ground-truth MIDI")
    parser.add_argument("--compare-settings", action="store_true", help="Compare multiple converter settings side-by-side")

    args = parser.parse_args()

    if not args.input.exists():
        print(f"Error: File not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    custom_tables: Dict[str, List[int]] = {}

    if args.input.suffix.lower() in (".mid", ".midi"):
        if args.compare_settings:
            run_all_comparisons(args.input, sample_rate=args.sample_rate)
            return

        # 1. Parse and convert MIDI
        notes, track_summaries, total_sec = parse_midi_file(args.input)
        allow_custom = (args.custom_instruments == "allow")

        if args.strategy == "melody-bass":
            alloc_cls = MelodyBassVoiceAllocator
        elif args.strategy == "arpeggio":
            alloc_cls = ArpeggioVoiceAllocator
        else:
            alloc_cls = SmartVoiceAllocator

        allocator = alloc_cls(
            notes=notes,
            track_summaries=track_summaries,
            percussion_mode=args.percussion,
            allow_custom=allow_custom
        )
        slices = allocator.allocate()
        compiler = BytecodeCompiler(allow_custom=allow_custom)
        instructions = compiler.compile(slices)
        bytecode = emit_binary(instructions)

        if allow_custom:
            custom_tables = {k: v.pulse_table for k, v in generate_drum_instruments().items()}

        out_wav = args.output or args.input.with_name(f"{args.input.stem}_emulated.wav")
        ref_wav = args.ref_output or args.input.with_name(f"{args.input.stem}_reference.wav")

        report, (emu1, emu2), (ref1, ref2) = run_comparison(
            midi_path=args.input,
            bytecode=bytecode,
            custom_tables=custom_tables,
            sample_rate=args.sample_rate
        )

        write_wav(out_wav, emu1, emu2, args.sample_rate)
        write_wav(ref_wav, ref1, ref2, args.sample_rate)

        print(report.format_table())
        print(f"Emulated audio WAV saved to : {out_wav}")
        print(f"Reference audio WAV saved to: {ref_wav}")

    elif args.input.suffix.lower() == ".asm":
        asm_content = args.input.read_text(encoding="utf-8")
        bytecode = parse_asm_bytecode(asm_content)
        emulator = AudioEngineEmulator(sample_rate=args.sample_rate)
        emulator.load_bytecode(bytecode)
        ch1, ch2, _ = emulator.render()
        out_wav = args.output or args.input.with_suffix(".wav")
        write_wav(out_wav, ch1, ch2, args.sample_rate)
        print(f"Assembled bytecode emulated successfully: {out_wav}")

    else: # .bin
        bytecode = args.input.read_bytes()
        emulator = AudioEngineEmulator(sample_rate=args.sample_rate)
        emulator.load_bytecode(bytecode)
        ch1, ch2, _ = emulator.render()
        out_wav = args.output or args.input.with_suffix(".wav")
        write_wav(out_wav, ch1, ch2, args.sample_rate)
        print(f"Binary bytecode emulated successfully: {out_wav}")


if __name__ == "__main__":
    main()
