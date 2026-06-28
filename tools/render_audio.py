#!/usr/bin/env python3
"""
Render MIDI files to WAV with a small dependency-free synth (numpy only), so the
browser game can play them via <audio>. Tone is a soft triangle+harmonics voice
with an ADSR envelope (matches the game's WebAudio aesthetic). Percussion
(channel 10) is rendered as short filtered-noise hits.
"""
import os, sys, wave, struct, glob
import numpy as np
import mido

SR = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT  = os.path.join(ROOT, "audio")
os.makedirs(OUT, exist_ok=True)

def notes_from_midi(path, cap=None):
    mid = mido.MidiFile(path)
    t = 0.0
    on = {}
    evs = []
    for msg in mid:                       # delta times already in seconds
        t += msg.time
        if cap and t > cap: break
        if msg.type == "note_on" and msg.velocity > 0:
            on[(msg.channel, msg.note)] = (t, msg.velocity)
        elif msg.type in ("note_off",) or (msg.type == "note_on" and msg.velocity == 0):
            k = (msg.channel, msg.note)
            if k in on:
                s, v = on.pop(k)
                evs.append((s, max(0.05, t - s), msg.note, v, msg.channel))
    # close any hanging notes
    for (ch, note), (s, v) in on.items():
        evs.append((s, 0.3, note, v, ch))
    return evs

def adsr(n, sr=SR):
    a = int(0.012*sr); d = int(0.06*sr); r = int(0.12*sr)
    env = np.ones(n)
    a = min(a, n);
    if a: env[:a] = np.linspace(0, 1, a)
    if d and a+d <= n: env[a:a+d] = np.linspace(1, 0.8, d)
    else: env[a:] = 0.8
    rr = min(r, n)
    if rr: env[-rr:] *= np.linspace(1, 0, rr)
    return env

def voice(freq, dur, vel, ch):
    n = int(dur*SR)
    if n <= 0: return np.zeros(0)
    tt = np.arange(n)/SR
    if ch == 9:                            # percussion: noise burst
        w = np.random.uniform(-1, 1, n) * np.exp(-tt*18)
        return w * (vel/127) * 0.5
    # tonal voice: fundamental + soft odd/even harmonics
    w  = 0.55*np.sin(2*np.pi*freq*tt)
    w += 0.22*np.sin(2*np.pi*2*freq*tt)
    w += 0.11*np.sin(2*np.pi*3*freq*tt)
    w += 0.05*np.sin(2*np.pi*4*freq*tt)
    return w * adsr(n) * (0.20 + 0.55*vel/127)

def render(path, out, cap=None):
    evs = notes_from_midi(path, cap=cap)
    if not evs:
        print("  (no notes)", os.path.basename(path)); return False
    total = max(s+d for s,d,_,_,_ in evs) + 0.4
    buf = np.zeros(int(total*SR)+1, dtype=np.float32)
    for s, d, note, vel, ch in evs:
        freq = 440.0*2**((note-69)/12)
        w = voice(freq, d, vel, ch)
        i = int(s*SR)
        buf[i:i+len(w)] += w
    # normalize and soft-limit
    peak = np.max(np.abs(buf)) or 1.0
    buf = np.tanh(buf/peak*1.1) * 0.85
    pcm = (buf*32767).astype(np.int16)
    with wave.open(out, "w") as wf:
        wf.setnchannels(1); wf.setsampwidth(2); wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())
    print(f"  {os.path.basename(out):28s} {len(evs):4d} notes  {len(pcm)/SR:5.1f}s  {os.path.getsize(out)//1024} KB")
    return True

# curated playlist: clean leitmotifs + the pre-existing arrangements + a full-score excerpt
JOBS = [
    ("themes/01_peter.mid",       "01_peter.wav",        None),
    ("themes/02_duck.mid",        "02_duck.wav",         None),
    ("themes/03_bird.mid",        "03_bird.wav",         None),
    ("themes/04_cat.mid",         "04_cat.wav",          None),
    ("themes/05_grandfather.mid", "05_grandfather.wav",  None),
    ("themes/06_wolf.mid",        "06_wolf.wav",         None),
    ("themes/07_hunters.mid",     "07_hunters.wav",      None),
    ("themes/PeterAndTheWolf_FULL.mid", "full_excerpt.wav", 70),
    ("Peter-En-De-Wolf.mid",      "peter-en-de-wolf.wav", 75),
    ("Wolf - Choosing a Wolf.mid","wolf-choosing.wav",   75),
]

def main():
    made = []
    for src, dst, cap in JOBS:
        sp = os.path.join(ROOT, src)
        if not os.path.exists(sp):
            print("  missing:", src); continue
        if render(sp, os.path.join(OUT, dst), cap=cap):
            made.append(dst)
    # write the playlist the game will read
    with open(os.path.join(OUT, "playlist.json"), "w") as f:
        import json; json.dump(made, f, indent=0)
    print("\nplaylist:", made)

if __name__ == "__main__":
    main()
