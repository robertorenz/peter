#!/usr/bin/env python3
"""
Transcribe the character leitmotifs from Prokofiev's *Peter and the Wolf*
(the composer's own "character motives" reference page of the score) into one
MIDI file per character, and emit a JS note-table the in-browser game can play.

These are transcriptions of the principal MELODIC line of each short motif —
faithful to the score's key, register and character, and easy to edit.
"""
import os, json
import mido
from mido import Message, MidiFile, MidiTrack, MetaMessage, bpm2tempo

HERE = os.path.dirname(os.path.abspath(__file__))
OUT  = os.path.join(HERE, "..", "themes")
os.makedirs(OUT, exist_ok=True)

# note name -> MIDI number
_STEP = {"C":0,"D":2,"E":4,"F":5,"G":7,"A":9,"B":11}
def m(n):
    if n is None: return None
    if isinstance(n, (list, tuple)): return [m(x) for x in n]
    name=n[0].upper(); i=1; acc=0
    while i<len(n) and n[i] in "#b":
        acc += 1 if n[i]=="#" else -1; i+=1
    octave=int(n[i:])
    return 12*(octave+1)+_STEP[name]+acc

# Each theme: GM program, bpm, beats-per-bar, and a list of (note, beats).
# note = "C5" | ["C3","E3","G3"] (chord) | None (rest)
THEMES = {
 "01_peter": dict(program=48, bpm=144, beat=4, color="strings", notes=[      # Vl.I, C major, jaunty
    ("G4",1),("C5",1),("C5",.5),("D5",.5),("E5",1),
    ("D5",1),("E5",1),("C5",2),
    ("E5",1),("F5",1),("G5",.5),("F5",.5),("E5",1),
    ("D5",1),("C5",2),(None,1),
    ("G4",1),("C5",1),("E5",1),("G5",1),
    ("A5",1),("G5",1),("E5",1),("C5",1),
    ("D5",1),("B4",1),("D5",1),("F5",1),
    ("E5",2),("C5",2),
 ]),
 "02_duck": dict(program=68, bpm=92, beat=3, color="oboe", notes=[           # Oboe, 3/4, G minor, waddling
    ("D5",1),("C5",.5),("Bb4",.5),("C5",1),
    ("D5",1.5),("C5",.5),("Bb4",1),
    ("A4",1),("Bb4",.5),("C5",.5),("A4",1),
    ("G4",2),(None,1),
    ("Bb4",1),("A4",.5),("G4",.5),("F4",1),
    ("G4",1.5),("A4",.5),("Bb4",1),
    ("A4",1),("G4",.5),("F#4",.5),("G4",1),
    ("G4",3),
 ]),
 "03_bird": dict(program=73, bpm=152, beat=4, color="flute", notes=[         # Flute, Allegro, high & quick
    ("E6",.25),("F6",.25),("E6",.25),("F6",.25),("E6",.25),("F6",.25),("E6",.25),("F6",.25),
    ("E6",.25),("Eb6",.25),("D6",.25),("Db6",.25),("C6",.5),("B5",.5),
    ("A5",.25),("B5",.25),("C6",.25),("D6",.25),("E6",.25),("F6",.25),("G6",.25),("A6",.25),
    ("G6",.5),("E6",.5),("C6",1),
    ("D6",.25),("E6",.25),("D6",.25),("E6",.25),("D6",.25),("E6",.25),("D6",.25),("E6",.25),
    ("F6",.5),("D6",.5),("B5",.5),("G5",.5),
    ("C6",2),(None,2),
 ]),
 "04_cat": dict(program=71, bpm=112, beat=4, color="clarinet", notes=[       # Clarinet, sly staccato
    ("C4",.5),("E4",.5),("G4",.5),("E4",.5),("G4",.5),("A4",.5),("G4",1),
    ("F4",.5),("A4",.5),("C5",.5),("A4",.5),("G#4",.5),("A4",.5),("E4",1),
    ("E4",.5),("G4",.5),("B4",.5),("G4",.5),("A#4",.5),("B4",.5),("G4",1),
    ("A4",.5),("F4",.5),("D4",.5),("F4",.5),("E4",2),
 ]),
 "05_grandfather": dict(program=70, bpm=88, beat=4, color="bassoon", notes=[ # Bassoon, low grumble, D major
    ("D3",.5),(None,.5),("D3",.5),("E3",.5),("F#3",.5),("E3",.5),("D3",1),
    ("A2",.5),("D3",.5),("F#3",.5),("E3",.5),("D3",1),("A2",1),
    ("D3",1/3),("E3",1/3),("F#3",1/3),("G3",1),("F#3",1),("E3",1),
    ("D3",2),("A2",2),
 ]),
 "06_wolf": dict(program=60, bpm=76, beat=4, color="horn", notes=[           # 3 Horns, ominous chromatic chords
    (["C3","Eb3","G3"],1),(["C3","E3","G3"],1),(["Db3","F3","Ab3"],1),(["C3","Eb3","G3"],1),
    (["D3","F3","Ab3"],1),(["C3","Eb3","G3"],1),(["B2","D3","F3"],2),
    (["C3","Eb3","Gb3"],1),(["C3","Eb3","G3"],1),(["Db3","F3","Ab3"],1),(["C3","Eb3","G3"],1),
    (["Ab2","C3","Eb3"],2),(["G2","B2","D3"],2),
 ]),
 "07_hunters": dict(program=56, bpm=120, beat=4, color="march", notes=[      # Hunters' march (woodwinds + timpani)
    ("A4",.75),("A4",.25),("A4",1),("D5",1),("A4",1),
    ("Bb4",1),("A4",1),("G4",1),("F4",1),
    ("A4",.75),("A4",.25),("A4",1),("D5",1),("F5",1),
    ("E5",2),("A4",2),
 ], timpani=[                                                                # bass drum / kettledrum (ch10)
    ("D2",1),("A2",1),("D2",1),("A2",1),
    ("D2",1),("D2",1),("A2",2),
    ("D2",1),("A2",1),("D2",1),("D2",1),
    ("A2",2),("D2",2),
 ]),
}

TPB = 480  # ticks per beat

def add_line(track, notes, program, ch=0, vel=80):
    track.append(Message("program_change", program=program, channel=ch, time=0))
    for note, beats in notes:
        dur = int(beats*TPB)
        if note is None:
            track.append(Message("note_off", note=0, velocity=0, channel=ch, time=dur)); continue
        ns = note if isinstance(note, list) else [note]
        for k,p in enumerate(ns):
            track.append(Message("note_on", note=p, velocity=vel, channel=ch, time=0))
        track.append(Message("note_off", note=ns[0], velocity=0, channel=ch, time=dur))
        for p in ns[1:]:
            track.append(Message("note_off", note=p, velocity=0, channel=ch, time=0))

def build_midi(name, spec):
    mid = MidiFile(ticks_per_beat=TPB)
    tr = MidiTrack(); mid.tracks.append(tr)
    tr.append(MetaMessage("track_name", name=name.split("_",1)[1].title(), time=0))
    tr.append(MetaMessage("set_tempo", tempo=bpm2tempo(spec["bpm"]), time=0))
    tr.append(MetaMessage("time_signature", numerator=spec["beat"], denominator=4, time=0))
    add_line(tr, [(m(n),b) for n,b in spec["notes"]], spec["program"], ch=0, vel=85)
    if "timpani" in spec:
        tt = MidiTrack(); mid.tracks.append(tt)
        # General MIDI percussion: ch9 (0-based). Use 47 (Low-Mid Tom) ~ timpani feel
        for note, beats in spec["timpani"]:
            dur=int(beats*TPB)
            tt.append(Message("note_on", note=47, velocity=100, channel=9, time=0))
            tt.append(Message("note_off", note=47, velocity=0, channel=9, time=dur))
    path=os.path.join(OUT, name+".mid")
    mid.save(path)
    return path

def to_js(spec):
    """convert to [[midiOrNull, frames], ...] at 60fps for the in-browser synth (melody only)"""
    fpb = 3600.0/spec["bpm"]   # frames per beat (60 fps)
    seq=[]
    for n,b in spec["notes"]:
        if n is None: midi=0
        elif isinstance(n,list): midi=m(n[-1])   # top voice for the synth
        else: midi=m(n)
        seq.append([midi, round(b*fpb)])
    return dict(bpm=spec["bpm"], notes=seq)

def main():
    js={}
    for name,spec in THEMES.items():
        p=build_midi(name,spec)
        key=name.split("_",1)[1]
        js[key]=to_js(spec)
        print("wrote", os.path.relpath(p, os.path.join(HERE,"..")))
    with open(os.path.join(HERE,"themes_js.json"),"w") as f:
        json.dump(js,f,indent=0)
    print("wrote tools/themes_js.json  (", len(js), "themes )")

if __name__=="__main__":
    main()
