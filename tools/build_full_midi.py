#!/usr/bin/env python3
"""
Stage 2 of the full-score OMR pipeline.

Takes every per-page MusicXML that Audiveris produced (omr/xml/p_NN.mxl) and:
  1. converts each page to a multi-track MIDI  -> omr/mid/p_NN.mid
  2. concatenates all pages, in order, into one playable MIDI of the whole work
     -> themes/PeterAndTheWolf_FULL.mid   (all recognised staves mixed)

Honest caveats: Audiveris does not name instruments (parts are by staff position)
and recognition on a dense 14-stave score is imperfect, so this is a rough
machine transcription of the entire piece, not a clean edition.
"""
import os, glob, sys
import music21 as m21
import mido

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
XML  = os.path.join(ROOT, "omr", "xml")
MID  = os.path.join(ROOT, "omr", "mid")
OUT  = os.path.join(ROOT, "themes", "PeterAndTheWolf_FULL.mid")
os.makedirs(MID, exist_ok=True)

def page_files():
    fs = glob.glob(os.path.join(XML, "p_*.mxl")) + glob.glob(os.path.join(XML, "p_*.xml"))
    # de-dup by basename, prefer .mxl
    seen = {}
    for f in fs:
        b = os.path.splitext(os.path.basename(f))[0]
        if b not in seen or f.endswith(".mxl"):
            seen[b] = f
    return [seen[b] for b in sorted(seen)]

def convert_pages():
    out = []
    for f in page_files():
        b = os.path.splitext(os.path.basename(f))[0]
        midp = os.path.join(MID, b + ".mid")
        try:
            sc = m21.converter.parse(f)
            sc.write("midi", midp)
            nparts = len(sc.parts)
            nnotes = len(sc.flatten().notes)
            out.append((b, midp, nparts, nnotes))
            print(f"  {b}: parts={nparts} notes={nnotes}")
        except Exception as e:
            print(f"  {b}: SKIP ({type(e).__name__}: {str(e)[:60]})")
    return out

def merge(pages):
    """concatenate page MIDIs cleanly back-to-back, parts spread over orchestral channels"""
    TPB = 480
    GAP = TPB                                   # one-beat breath between pages
    # channels (skip 9 = GM percussion) with an orchestral program each
    CH   = [0,1,2,3,4,5,6,7,8,10,11,12,13,14,15]
    PROG = {0:73,1:68,2:71,3:70,4:60,5:56,6:57,7:47,8:48,10:48,11:48,12:42,13:43,14:49,15:45}

    events = []                                 # (abs_tick, order, mido.Message)
    gstart = 0
    total_notes = 0
    for b, midp, _, _ in pages:
        try:
            pm = mido.MidiFile(midp)
        except Exception:
            continue
        sf = TPB / pm.ticks_per_beat
        page_end = 0
        # each source track (a staff/part) -> its own orchestral channel
        for ti, tr in enumerate(pm.tracks):
            ch = CH[ti % len(CH)]
            t = 0
            for msg in tr:
                t += msg.time
                if msg.type in ("note_on", "note_off"):
                    at = gstart + int(t*sf)
                    events.append((at, len(events),
                        mido.Message(msg.type, note=msg.note,
                                     velocity=msg.velocity, channel=ch)))
                    if msg.type == "note_on" and msg.velocity > 0: total_notes += 1
                    page_end = max(page_end, at)
        gstart = page_end + GAP

    events.sort(key=lambda e: (e[0], e[1]))
    full = mido.MidiFile(ticks_per_beat=TPB)
    track = mido.MidiTrack(); full.tracks.append(track)
    track.append(mido.MetaMessage("track_name", name="Peter and the Wolf (full OMR)", time=0))
    track.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(100), time=0))
    for ch, prog in PROG.items():
        track.append(mido.Message("program_change", program=prog, channel=ch, time=0))
    prev = 0
    for at, _, msg in events:
        msg.time = at - prev; prev = at
        track.append(msg)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    full.save(OUT)
    return total_notes, full.length

def main():
    pages = convert_pages()
    if not pages:
        print("No MusicXML pages found yet in", XML); sys.exit(1)
    notes, length = merge(pages)
    print(f"\nFULL piece: {len(pages)} pages merged, ~{notes} notes, {length:.0f}s -> {os.path.relpath(OUT, ROOT)}")

if __name__ == "__main__":
    main()
