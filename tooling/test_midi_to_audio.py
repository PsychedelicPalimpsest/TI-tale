#!/usr/bin/env python3
"""
test_midi_to_audio.py - Unit and Integration Tests for midi_to_audio.py.

Tests:
1. MIDI File Parser (Format 0 & 1, running status, tempo changes, note-on/off, metadata).
2. Waveform parameter calculation and micro-tuning (Square, Saw1, Saw2, Saw3).
3. Auto-transposition and pitch range detection.
4. Voice allocation strategies (Smart, Melody-Bass, Arpeggio, Track routing).
5. Percussion handling (Synthesized sweeps, custom pulse tables, disabled).
6. Custom instrument settings (allow vs disable).
7. Articulation gaps on repeated pitches.
8. Bytecode emission and optimization.
9. Code generation (Z80 assembly, C header, binary).
10. Assembler verification with z88dk-z80asm.
"""

from __future__ import annotations

import math
import shutil
import struct
import subprocess
import tempfile
import unittest
import sys
from pathlib import Path

tooling_dir = str(Path(__file__).parent.resolve())
if tooling_dir not in sys.path:
    sys.path.insert(0, tooling_dir)

from midi_to_audio import (
    BytecodeCompiler,
    ChannelSound,
    CustomInstrument,
    MelodyBassVoiceAllocator,
    NoteEvent,
    RetroArranger,
    SquareParams,
    SmartVoiceAllocator,
    TempoMap,
    TimeSlice,
    TrackSummary,
    VoiceType,
    calc_saw1_params,
    calc_saw2_params,
    calc_saw3_params,
    calc_square_params,
    detect_optimal_transposition,
    emit_asm,
    emit_binary,
    emit_c,
    freq_to_cents,
    generate_drum_instruments,
    midi_pitch_to_freq,
    midi_pitch_to_name,
    parse_midi_file,
    select_sections,
    OP_CH1_FAST,
    OP_CH1_INSTR,
    OP_CH1_SAW1,
    OP_CH1_SLOW,
    OP_CH1_SQUARE,
    OP_CH1_STOP,
    OP_CH2_INSTR,
    OP_CH2_SAW1,
    OP_CH2_SLOW,
    OP_CH2_SQUARE,
    OP_CH2_STOP,
    OP_JUMP,
    OP_STOP_SONG,
    OP_WAIT,
)


def create_in_memory_midi(tracks: list[list[tuple[int, bytes]]], division: int = 480) -> bytes:
    """Helper to synthesize SMF bytes from a list of tracks."""
    fmt = 0 if len(tracks) == 1 else 1
    header = b"MThd" + struct.pack(">IHHH", 6, fmt, len(tracks), division)
    body = bytearray(header)

    for trk_events in tracks:
        trk_buf = bytearray()
        for delta, event_bytes in trk_events:
            # write delta VLQ
            val = delta
            buf = bytearray()
            buf.append(val & 0x7F)
            val >>= 7
            while val > 0:
                buf.append((val & 0x7F) | 0x80)
                val >>= 7
            trk_buf.extend(reversed(buf))
            trk_buf.extend(event_bytes)

        # End of track marker
        trk_buf.extend(b"\x00\xFF\x2F\x00")
        chunk = b"MTrk" + struct.pack(">I", len(trk_buf)) + bytes(trk_buf)
        body.extend(chunk)

    return bytes(body)


class TestWaveformMath(unittest.TestCase):
    def test_midi_pitch_to_freq(self):
        self.assertAlmostEqual(midi_pitch_to_freq(69), 440.0, places=2)
        self.assertAlmostEqual(midi_pitch_to_freq(60), 261.63, places=2)
        self.assertAlmostEqual(midi_pitch_to_freq(48), 130.81, places=2)

    def test_midi_pitch_to_name(self):
        self.assertEqual(midi_pitch_to_name(60), "C4")
        self.assertEqual(midi_pitch_to_name(69), "A4")
        self.assertEqual(midi_pitch_to_name(36), "C2")

    def test_square_params_slow_clock(self):
        # Middle C ~ 261.63 Hz, 32768 / 261.63 ~ 125.2 ticks
        sq = calc_square_params(261.63, 32768.0, 0.5)
        self.assertEqual(sq.high_ticks + sq.low_ticks, 125)
        self.assertTrue(1 <= sq.high_ticks <= 255)
        self.assertTrue(1 <= sq.low_ticks <= 255)
        self.assertLess(abs(sq.cents_err), 25.0)

    def test_square_duty_cycles(self):
        sq_50 = calc_square_params(440.0, 32768.0, 0.5)
        self.assertEqual(sq_50.high_ticks, sq_50.low_ticks)

        sq_25 = calc_square_params(440.0, 32768.0, 0.25)
        self.assertLess(sq_25.high_ticks, sq_25.low_ticks)

    def test_saw1_params_accuracy(self):
        # A4 = 440 Hz
        saw = calc_saw1_params(440.0, 32768.0)
        self.assertTrue(1 <= saw.k_const <= 16)
        self.assertTrue(2 <= saw.m_max <= 255)
        self.assertLess(abs(saw.cents_err), 30.0)

    def test_saw2_params(self):
        saw2 = calc_saw2_params(440.0, 32768.0)
        self.assertTrue(2 <= saw2.m_max <= 255)
        self.assertGreater(saw2.actual_freq, 0.0)

    def test_saw3_params(self):
        saw3 = calc_saw3_params(440.0, 32768.0)
        self.assertTrue(2 <= saw3.m_max <= 255)
        self.assertGreater(saw3.actual_freq, 0.0)

    def test_optimal_transposition(self):
        low_notes = [NoteEvent(pitch=24, start_time=0, end_time=1, velocity=64, channel=0, track_idx=0)]
        shift = detect_optimal_transposition(low_notes)
        self.assertEqual(shift, 12)

        normal_notes = [NoteEvent(pitch=60, start_time=0, end_time=1, velocity=64, channel=0, track_idx=0)]
        self.assertEqual(detect_optimal_transposition(normal_notes), 0)


class TestMidiParser(unittest.TestCase):
    def setUp(self):
        self.temp_dir = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_parse_format_0_midi(self):
        events = [
            (0, b"\xFF\x51\x03\x07\xA1\x20"), # Tempo 500,000 us (120 bpm)
            (0, b"\x90\x3C\x50"),             # Note on C4
            (480, b"\x80\x3C\x00"),           # Note off C4
        ]
        midi_data = create_in_memory_midi([events], division=480)
        midi_path = self.temp_dir / "test0.mid"
        midi_path.write_bytes(midi_data)

        notes, summaries, total_sec = parse_midi_file(midi_path)
        self.assertEqual(len(notes), 1)
        self.assertEqual(notes[0].pitch, 60)
        self.assertAlmostEqual(notes[0].start_time, 0.0, places=3)
        self.assertAlmostEqual(notes[0].end_time, 0.5, places=3)
        self.assertAlmostEqual(total_sec, 0.5, places=3)

    def test_running_status_and_velocity_zero(self):
        events = [
            (0, b"\xFF\x51\x03\x07\xA1\x20"),
            (0, b"\x90\x3C\x40"), # Note on C4
            (240, b"\x3E\x40"),   # Running status Note on D4
            (240, b"\x3C\x00"),   # Running status Note off C4 (vel 0)
            (240, b"\x3E\x00"),   # Running status Note off D4 (vel 0)
        ]
        midi_data = create_in_memory_midi([events], division=480)
        midi_path = self.temp_dir / "running.mid"
        midi_path.write_bytes(midi_data)

        notes, _, _ = parse_midi_file(midi_path)
        self.assertEqual(len(notes), 2)
        self.assertEqual(notes[0].pitch, 60)
        self.assertEqual(notes[1].pitch, 62)

    def test_tempo_changes(self):
        events = [
            (0, b"\xFF\x51\x03\x07\xA1\x20"),   # 120 bpm (0.5s per 480 ticks)
            (0, b"\x90\x3C\x40"),
            (480, b"\x80\x3C\x00"),             # at t = 0.5s
            (0, b"\xFF\x51\x03\x03\xD0\x90"),   # 240 bpm (250,000 us = 0.25s per 480 ticks)
            (0, b"\x90\x40\x40"),
            (480, b"\x80\x40\x00"),             # duration = 0.25s, ends at t = 0.75s
        ]
        midi_data = create_in_memory_midi([events], division=480)
        midi_path = self.temp_dir / "tempo.mid"
        midi_path.write_bytes(midi_data)

        notes, _, total_sec = parse_midi_file(midi_path)
        self.assertEqual(len(notes), 2)
        self.assertAlmostEqual(notes[0].duration, 0.5, places=3)
        self.assertAlmostEqual(notes[1].duration, 0.25, places=3)
        self.assertAlmostEqual(total_sec, 0.75, places=3)


class TestRetroArrangement(unittest.TestCase):
    def test_held_melody_survives_new_harmony_notes(self):
        notes = [
            NoteEvent(72, 0, 1.0, 90, 0, 1),
            NoteEvent(48, 0, 1.0, 75, 1, 2),
            NoteEvent(64, 0.5, 1.0, 85, 2, 3),
            NoteEvent(67, 0.5, 1.0, 85, 2, 3),
        ]
        summaries = [
            TrackSummary(1, "lead", 0, 0, "Piano", 1, 72, 72, 72, False, "melody"),
            TrackSummary(2, "bass", 1, 32, "Bass", 1, 48, 48, 48, False, "bass"),
            TrackSummary(3, "chord", 2, 0, "Piano", 2, 64, 67, 65.5, False, "harmony"),
        ]
        slices = RetroArranger(notes, summaries).allocate()
        at_half = next(s for s in slices if s.time <= 0.55 < s.time + s.duration)
        self.assertEqual(at_half.ch1.pitch, 72)
        self.assertTrue(any(s.ch2.is_active and s.ch2.pitch == 48 for s in slices))

    def test_sustained_chord_becomes_measured_arpeggio(self):
        notes = [NoteEvent(p, 0, 3.0, 80, 0, 1) for p in (48, 51, 55, 58)]
        summary = TrackSummary(1, "piano", 0, 0, "Piano", 4, 48, 58, 53, False, "harmony")
        slices = RetroArranger(notes, [summary]).allocate()
        pitches = {s.ch1.pitch for s in slices if s.ch1.is_active}
        self.assertGreaterEqual(len(pitches), 3)
        self.assertTrue(any(s.ch2.is_active for s in slices))

    def test_quick_melody_turn_is_kept_separate_from_rolled_chords(self):
        notes = [NoteEvent(72, 0, 0.14, 90, 0, 1),
                 NoteEvent(74, 0.15, 0.29, 90, 0, 1)]
        summary = TrackSummary(1, "lead", 0, 0, "Piano", 2, 72, 74, 73, False, "melody")
        slices = RetroArranger(notes, [summary]).allocate()
        pitches = {s.ch1.pitch for s in slices if s.ch1.is_active}
        self.assertEqual(pitches, {72, 74})

    def test_loop_gap_releases_both_channels_before_restart(self):
        notes = [NoteEvent(72, 0, 1, 80, 0, 1),
                 NoteEvent(48, 0, 1, 80, 1, 2)]
        summaries = [TrackSummary(1, "lead", 0, 0, "Piano", 1, 72, 72, 72, False, "melody"),
                     TrackSummary(2, "bass", 1, 32, "Bass", 1, 48, 48, 48, False, "bass")]
        slices = RetroArranger(notes, summaries, song_length=1, loop_gap=0.08).allocate()
        self.assertFalse(slices[-1].ch1.is_active)
        self.assertFalse(slices[-1].ch2.is_active)

    def test_sections_join_at_new_bar_without_mutating_input(self):
        notes = [NoteEvent(60, 0, 2, 80, 0, 1),
                 NoteEvent(64, 4, 6, 80, 0, 1)]
        arranged, length = select_sections(notes, "0:1,5:6", 6)
        self.assertEqual(length, 2)
        self.assertEqual([(n.start_time, n.end_time) for n in arranged],
                         [(0, 1), (1, 2)])
        self.assertEqual(notes[1].start_time, 4)


class TestVoiceAllocation(unittest.TestCase):
    def test_smart_allocation_polyphony(self):
        # 3 notes playing simultaneously: C3 (48), E4 (64), G4 (67)
        notes = [
            NoteEvent(pitch=48, start_time=0.0, end_time=1.0, velocity=64, channel=0, track_idx=0),
            NoteEvent(pitch=64, start_time=0.0, end_time=1.0, velocity=64, channel=0, track_idx=0),
            NoteEvent(pitch=67, start_time=0.0, end_time=1.0, velocity=64, channel=0, track_idx=0),
        ]
        allocator = SmartVoiceAllocator(notes, [], quantize_fps=60.0)
        slices = allocator.allocate()
        self.assertTrue(len(slices) >= 1)

        # Ch1 should get highest note (G4 = 67), Ch2 should get bass root (C3 = 48)
        s0 = slices[0]
        self.assertTrue(s0.ch1.is_active)
        self.assertTrue(s0.ch2.is_active)
        self.assertEqual(s0.ch1.pitch, 67)
        self.assertEqual(s0.ch2.pitch, 48)

    def test_repeated_note_articulation(self):
        # Two consecutive identical notes
        notes = [
            NoteEvent(pitch=60, start_time=0.0, end_time=0.5, velocity=64, channel=0, track_idx=0),
            NoteEvent(pitch=60, start_time=0.5, end_time=1.0, velocity=64, channel=0, track_idx=0),
        ]
        allocator = SmartVoiceAllocator(notes, [], articulation_frames=1, quantize_fps=60.0)
        slices = allocator.allocate()

        # There should be an articulation rest between the two notes
        has_rest = any(s.ch1 is not None and not s.ch1.is_active for s in slices)
        self.assertTrue(has_rest, "Expected articulation rest between consecutive identical pitches.")

    def test_percussion_interleaving_synth(self):
        notes = [
            # Sustained bass note
            NoteEvent(pitch=40, start_time=0.0, end_time=1.0, velocity=64, channel=0, track_idx=0),
            # Kick drum on ch 9 at 0.2s
            NoteEvent(pitch=36, start_time=0.2, end_time=0.3, velocity=80, channel=9, track_idx=1, is_percussion=True),
        ]
        allocator = SmartVoiceAllocator(notes, [], percussion_mode="synth", allow_custom=False, quantize_fps=60.0)
        slices = allocator.allocate()

        has_kick_sweep = any(s.ch2 and s.ch2.is_sweep for s in slices)
        self.assertTrue(has_kick_sweep, "Expected synthesized kick drum sweep on Channel 2.")

    def test_percussion_custom_instruments(self):
        notes = [
            NoteEvent(pitch=38, start_time=0.0, end_time=0.1, velocity=80, channel=9, track_idx=0, is_percussion=True),
        ]
        allocator = SmartVoiceAllocator(notes, [], percussion_mode="custom", allow_custom=True, quantize_fps=60.0)
        slices = allocator.allocate()

        has_custom = any(s.ch2 and s.ch2.custom_inst_name == "drum_snare_table" for s in slices)
        self.assertTrue(has_custom, "Expected custom instrument drum snare table on Channel 2.")


class TestCompilerAndEmitters(unittest.TestCase):
    def test_bytecode_compiler_basic(self):
        s = TimeSlice(
            time=0.0,
            duration=0.5,
            ch1=ChannelSound(1, True, VoiceType.SQUARE, square_high=50, square_low=50, note_name="C4"),
            ch2=ChannelSound(2, False, note_name="Rest")
        )
        compiler = BytecodeCompiler(loop=False, allow_custom=False)
        instructions = compiler.compile([s])

        opcodes = [i.opcode for i in instructions]
        self.assertIn(OP_CH1_SLOW, opcodes)
        self.assertIn(OP_CH2_SLOW, opcodes)
        self.assertIn(OP_CH1_SQUARE, opcodes)
        self.assertIn(OP_CH2_STOP, opcodes)
        self.assertIn(OP_WAIT, opcodes)
        self.assertIn(OP_STOP_SONG, opcodes)

    def test_bytecode_compiler_looping(self):
        s = TimeSlice(
            time=0.0,
            duration=0.5,
            ch1=ChannelSound(1, True, VoiceType.SQUARE, square_high=50, square_low=50),
            ch2=ChannelSound(2, False)
        )
        compiler = BytecodeCompiler(loop=True, allow_custom=False)
        instructions = compiler.compile([s])

        opcodes = [i.opcode for i in instructions]
        self.assertIn(OP_JUMP, opcodes)
        self.assertNotIn(OP_STOP_SONG, opcodes)

    def test_emit_asm_and_c(self):
        s = TimeSlice(
            time=0.0,
            duration=0.25,
            ch1=ChannelSound(1, True, VoiceType.SAW1, saw_k=5, saw_m=25, note_name="C4"),
            ch2=ChannelSound(2, True, VoiceType.SQUARE, square_high=80, square_low=80, note_name="C3")
        )
        compiler = BytecodeCompiler(loop=False)
        instructions = compiler.compile([s])

        asm_out = emit_asm(instructions, "test_song", {}, loop=False)
        self.assertIn("PUBLIC test_song", asm_out)
        self.assertIn("DEFB $0A, $05, $19", asm_out) # saw1 K=5, M=25
        self.assertIn("DEFB $00", asm_out)          # stop

        c_out = emit_c(instructions, "test_song", loop=False)
        self.assertIn("const uint8_t test_song[] = {", c_out)
        self.assertIn("0x0A, 0x05, 0x19,", c_out)

    def test_emit_binary(self):
        s = TimeSlice(
            time=0.0,
            duration=0.25,
            ch1=ChannelSound(1, True, VoiceType.SQUARE, square_high=40, square_low=40),
            ch2=ChannelSound(2, False)
        )
        compiler = BytecodeCompiler(loop=False)
        instructions = compiler.compile([s])
        raw_bin = emit_binary(instructions)
        self.assertIsInstance(raw_bin, bytes)
        self.assertGreater(len(raw_bin), 5)

    def test_non_asm_output_rejects_unresolved_loop_address(self):
        loop = [BytecodeCompiler(loop=True).compile([TimeSlice(
            time=0, duration=0.5,
            ch1=ChannelSound(1, False), ch2=ChannelSound(2, False))])[-1]]
        with self.assertRaisesRegex(ValueError, "use ASM"):
            emit_binary(loop)
        with self.assertRaisesRegex(ValueError, "use ASM"):
            emit_c(loop, "loop_song", loop=True)


class TestAssemblerIntegration(unittest.TestCase):
    """Verifies that generated assembly code compiles with z88dk-z80asm."""
    def setUp(self):
        self.temp_dir = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_z88dk_assemble_generated_code(self):
        # Create a song with square, saw1, and wait
        s = TimeSlice(
            time=0.0,
            duration=0.5,
            ch1=ChannelSound(1, True, VoiceType.SAW1, saw_k=5, saw_m=30, note_name="C4"),
            ch2=ChannelSound(2, True, VoiceType.SQUARE, square_high=100, square_low=100, note_name="C3")
        )
        compiler = BytecodeCompiler(loop=False)
        instructions = compiler.compile([s])
        asm_code = emit_asm(instructions, "song_integration_test", {}, loop=False)

        asm_path = self.temp_dir / "song.asm"
        asm_path.write_text(asm_code, encoding="utf-8")
        bin_path = self.temp_dir / "song.bin"

        result = subprocess.run(
            ["z88dk-z80asm", "-b", str(asm_path), f"-o{bin_path}"],
            capture_output=True,
            text=True
        )
        self.assertEqual(result.returncode, 0, f"Assembler failed:\n{result.stderr}\n{result.stdout}")
        self.assertTrue(bin_path.exists())
        self.assertGreater(bin_path.stat().st_size, 0)


class TestAudioEmulator(unittest.TestCase):
    """Tests the software cycle-accurate audio emulator and comparison runner."""
    def setUp(self):
        self.temp_dir = Path(tempfile.mkdtemp())

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_emulator_square_render(self):
        from audio_emulator import AudioEngineEmulator
        # Channel 1: 440 Hz square (hi=37, lo=37 -> period=74 -> freq=442.8 Hz)
        # Wait 64 ticks (0.25s), then stop
        bytecode = bytes([
            OP_CH1_SLOW,
            OP_CH2_SLOW,
            OP_CH1_SQUARE, 37, 37,
            OP_WAIT, 64, 0,
            OP_STOP_SONG
        ])
        emu = AudioEngineEmulator(sample_rate=44100)
        emu.load_bytecode(bytecode)
        ch1, ch2, events = emu.render(max_duration_sec=2.0)

        self.assertGreater(len(ch1), 1000)
        self.assertGreater(len(ch2), 1000)
        # Ch1 active, Ch2 silent
        self.assertGreater(float(max(abs(ch1))), 0.5)
        self.assertAlmostEqual(float(max(abs(ch2))), 0.0, places=3)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0][1], 1) # Channel 1
        self.assertAlmostEqual(events[0][2], 32768.0 / 74.0, places=1)

    def test_emulator_saw_render(self):
        from audio_emulator import AudioEngineEmulator
        # Channel 2: saw1 (K=5, M=25), Wait 64 ticks (0.25s), Stop
        bytecode = bytes([
            OP_CH1_SLOW,
            OP_CH2_SLOW,
            OP_CH2_SAW1, 5, 25,
            OP_WAIT, 64, 0,
            OP_STOP_SONG
        ])
        emu = AudioEngineEmulator(sample_rate=44100)
        emu.load_bytecode(bytecode)
        ch1, ch2, events = emu.render(max_duration_sec=2.0)

        self.assertGreater(len(ch2), 1000)
        self.assertGreater(float(max(abs(ch2))), 0.5)
        self.assertAlmostEqual(float(max(abs(ch1))), 0.0, places=3)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0][1], 2) # Channel 2

    def test_emulator_custom_instrument(self):
        from audio_emulator import AudioEngineEmulator
        # Channel 2: custom instrument opcode 0x15
        bytecode = bytes([
            OP_CH2_INSTR, 0x00, 0x80, # table addr placeholder
            OP_WAIT, 32, 0,
            OP_STOP_SONG
        ])
        emu = AudioEngineEmulator(sample_rate=44100)
        custom_tables = {"drum_kick": [10, 20, 30, 0]}
        emu.load_bytecode(bytecode, custom_tables)
        ch1, ch2, events = emu.render(max_duration_sec=1.0)
        self.assertGreater(len(ch2), 500)
        self.assertEqual(len(events), 1)
        self.assertTrue(events[0][3]) # is_perc = True

    def test_emulator_midi_comparison(self):
        from audio_emulator import run_comparison, write_wav
        import wave

        # Synthesize a simple 2-track MIDI song:
        # Track 1: Melody (C5=72, E5=76)
        # Track 2: Bass (C3=48, G2=43)
        t0 = [
            (0, b"\xFF\x51\x03\x07\xA1\x20"), # 500,000 us (120 BPM)
        ]
        t1 = [
            (0, b"\x90\x48\x64"),   # C5 On
            (480, b"\x80\x48\x40"), # C5 Off
            (0, b"\x90\x4C\x64"),   # E5 On
            (480, b"\x80\x4C\x40"), # E5 Off
        ]
        t2 = [
            (0, b"\x91\x30\x64"),   # C3 On
            (480, b"\x81\x30\x40"), # C3 Off
            (0, b"\x91\x2B\x64"),   # G2 On
            (480, b"\x81\x2B\x40"), # G2 Off
        ]
        raw_midi = create_in_memory_midi([t0, t1, t2])
        midi_path = self.temp_dir / "simple_test.mid"
        midi_path.write_bytes(raw_midi)

        notes, track_summaries, total_sec = parse_midi_file(midi_path)
        allocator = SmartVoiceAllocator(notes, track_summaries)
        slices = allocator.allocate()
        compiler = BytecodeCompiler()
        instructions = compiler.compile(slices)
        bytecode = emit_binary(instructions)

        report, (e1, e2), (r1, r2) = run_comparison(midi_path, bytecode, sample_rate=22050)

        # Check key metrics
        self.assertLess(report.mean_pitch_cents_error, 25.0)
        self.assertLess(report.max_pitch_cents_error, 35.0)
        self.assertGreaterEqual(report.polyphony_coverage_pct, 90.0)
        self.assertGreater(report.waveform_correlation, 0.70)
        self.assertLess(abs(report.duration_midi_sec - report.duration_emulated_sec), 0.100)

        # Verify WAV export
        wav_path = self.temp_dir / "test.wav"
        write_wav(wav_path, e1, e2, sample_rate=22050)
        self.assertTrue(wav_path.exists())
        with wave.open(str(wav_path), "rb") as wf:
            self.assertEqual(wf.getnchannels(), 2)
            self.assertEqual(wf.getsampwidth(), 2)
            self.assertEqual(wf.getframerate(), 22050)

    def test_sweep_bytecode_emission(self):
        """Verify BytecodeCompiler emits sweep instructions when ChannelSound.is_sweep is True."""
        from midi_to_audio import OP_CH1_SQUARE_SWEEP, OP_CH2_SQUARE_SWEEP, OP_CH1_SAW_SWEEP
        s1 = ChannelSound(
            channel=1,
            is_active=True,
            voice=VoiceType.SQUARE,
            square_high=35,
            square_low=35,
            is_sweep=True,
            sweep_mask=0x03,
            sweep_param1=1,
            sweep_param2=1
        )
        s2 = ChannelSound(
            channel=2,
            is_active=True,
            voice=VoiceType.SQUARE,
            square_high=60,
            square_low=60,
            is_sweep=True,
            sweep_mask=0x07,
            sweep_param1=1,
            sweep_param2=1
        )
        slice_obj = TimeSlice(time=0.0, duration=1.0, ch1=s1, ch2=s2)
        compiler = BytecodeCompiler()
        instructions = compiler.compile([slice_obj])

        opcodes = [instr.opcode for instr in instructions]
        self.assertIn(OP_CH1_SQUARE, opcodes)
        self.assertIn(OP_CH1_SQUARE_SWEEP, opcodes)
        self.assertIn(OP_CH2_SQUARE, opcodes)
        self.assertIn(OP_CH2_SQUARE_SWEEP, opcodes)

        # Check operands of sweep instruction
        ch1_sweep = next(instr for instr in instructions if instr.opcode == OP_CH1_SQUARE_SWEEP)
        self.assertEqual(ch1_sweep.operands, [0x03, 1, 1])

    def test_pitch_decay_allocation(self):
        """Verify SmartVoiceAllocator marks sustained notes for pitch sweep decay."""
        note = NoteEvent(pitch=60, start_time=0.0, end_time=3.0, velocity=80, channel=0, track_idx=0, program=0)
        summary = TrackSummary(0, "Piano", 0, 0, "Piano", 1, 60, 60, 60.0, False, "melody")
        allocator = SmartVoiceAllocator(
            notes=[note],
            track_summaries=[summary],
            decay_mode="sweep",
            decay_threshold=0.5,
            decay_rate="medium"
        )
        slices = allocator.allocate()
        self.assertTrue(len(slices) > 0)
        sound = slices[0].ch1
        self.assertIsNotNone(sound)
        self.assertTrue(sound.is_sweep)
        self.assertEqual(sound.sweep_mask, 0x03)
        self.assertEqual(sound.sweep_param1, 1)
        self.assertEqual(sound.sweep_param2, 1)

    def test_emulator_pitch_sweep_frequency_descent(self):
        """Verify AudioEngineEmulator produces a continuously decreasing frequency during pitch sweep."""
        from audio_emulator import AudioEngineEmulator
        import numpy as np
        # Ch1: square hi=35, lo=35, followed by sweep mask=0x00 (+1, +1 per frame)
        # 60 frames = 1.0 second, period increases from 70 to 70 + 120 = 190.
        bytecode = bytes([
            0x03, 0x05,             # Slow mode
            0x08, 35, 35,           # Square hi=35, lo=35 (468 Hz)
            0x10, 0x00, 0x01, 0x01, # Square sweep mask=0, +1, +1
            0x01, 0x00, 0x01,       # Wait 256 ticks (1.0s)
            0x00                    # Stop
        ])
        emu = AudioEngineEmulator(sample_rate=44100)
        emu.load_bytecode(bytecode)
        ch1, ch2, _ = emu.render(max_duration_sec=1.5)

        # Divide into early and late windows
        win_size = int(44100 * 0.2)
        early = ch1[:win_size]
        late = ch1[int(44100 * 0.7):int(44100 * 0.9)]
        zc_early = np.count_nonzero((early[:-1] <= 0) & (early[1:] > 0)) / 0.2
        zc_late = np.count_nonzero((late[:-1] <= 0) & (late[1:] > 0)) / 0.2

        # Frequency must decrease significantly
        self.assertGreater(zc_early, zc_late + 100.0)

    def test_auto_decay_duty_cycling_no_pitch_sweep(self):
        """Verify decay_mode='auto' applies duty cycle volume decay WITHOUT pitch sweep."""
        note = NoteEvent(pitch=60, start_time=0.0, end_time=4.0, velocity=80, channel=0, track_idx=0, program=0)
        summary = TrackSummary(0, "Piano", 0, 0, "Piano", 1, 60, 60, 60.0, False, "melody")
        allocator = SmartVoiceAllocator(
            notes=[note],
            track_summaries=[summary],
            decay_mode="auto",
            decay_threshold=0.75
        )
        slices = allocator.allocate()
        self.assertGreater(len(slices), 1)

        # None of the slices should have is_sweep=True
        for s in slices:
            if s.ch1 and s.ch1.is_active:
                self.assertFalse(s.ch1.is_sweep, "auto decay must never apply pitch frequency sweeps to tonal notes")

        # Check duty cycle stepping: starts near 0.5, steps down, and ends with release
        active_slices = [s for s in slices if s.ch1 and s.ch1.is_active]
        first_duty = active_slices[0].ch1.square_high / (active_slices[0].ch1.square_high + active_slices[0].ch1.square_low)
        last_duty = active_slices[-1].ch1.square_high / (active_slices[-1].ch1.square_high + active_slices[-1].ch1.square_low)
        self.assertAlmostEqual(first_duty, 0.5, delta=0.05)
        self.assertLess(last_duty, first_duty)

        # The final slice before 4.0s should be released (inactive)
        self.assertFalse(slices[-1].ch1.is_active)

    def test_bass_folding_under_range(self):
        """Verify notes below pitch 36 are folded up by octave into valid hardware range."""
        low_note = NoteEvent(pitch=29, start_time=0.0, end_time=1.0, velocity=80, channel=0, track_idx=0)
        summary = TrackSummary(0, "Bass", 0, 32, "Bass", 1, 29, 29, 29.0, False, "bass")
        allocator = SmartVoiceAllocator(
            notes=[low_note],
            track_summaries=[summary]
        )
        self.assertGreaterEqual(low_note.pitch, 36)
        self.assertEqual(low_note.pitch, 41) # 29 + 12


if __name__ == "__main__":
    unittest.main()
