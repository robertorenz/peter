# 🐺 Peter and the Wolf

A small storybook game, inspired by Prokofiev's *Peter and the Wolf* — and by a childhood dream of "a wolf moving across the screen, looking for Peter."

You play **Peter**, sneaking through a green meadow to gather apples and slip home through the **gate** before the **wolf** sniffs you out.

Everything — the meadow, the trees, Peter, the wolf, and the music cues — is drawn and synthesized in code. **No image or sound files**, just a single `index.html`.

## ▶️ Play

Open `index.html` in any modern browser. That's it.

## 🎮 Controls

| Action | Keys |
| --- | --- |
| Move | `W` `A` `S` `D` or arrow keys |
| Tip-toe (quiet, slower) | hold `Shift` |
| Spring the rope-trap | `Space` |
| Pause | `P` |
| Mute / unmute | `M` |

## 🎯 How to win

1. **Collect every apple** scattered in the meadow.
2. Then choose your ending:
   - **Escape** — slip home through the **gate** on the right, *or*
   - **Hero's ending** — lure the wolf onto the **rope-trap by the old oak** and press `Space` to catch it by the tail, just like in the story.
3. Don't let the wolf **catch you** — and don't let its **suspicion meter** fill up.

## 🎵 Music & friends

- Each level plays the **actual Prokofiev character leitmotif**, transcribed from the
  orchestral score: **Peter's theme** (strings) in the Meadow, the **Duck's theme**
  (oboe) in the rescue. They're played by a small in-code synth, so no audio files
  are required (press `M` to mute).
- Prefer the real orchestral recording? Drop a `peter-theme.mp3` into this folder and
  the game will loop it instead of the synth.
- The **🐦 bird** flutters near Peter and dive-bombs the wolf when it gives chase, breaking its focus.
- The **🦆 duck** paddles in the pond and dives underwater when the wolf prowls too close.

## 🎼 The themes (MIDI)

The `themes/` folder holds one MIDI file per character, transcribed from Prokofiev's
own "character motives" reference page of the score:

| File | Character | Instrument |
| --- | --- | --- |
| `01_peter.mid` | Peter | Strings |
| `02_duck.mid` | The Duck (Sonia) | Oboe |
| `03_bird.mid` | The Bird (Sasha) | Flute |
| `04_cat.mid` | The Cat (Ivan) | Clarinet |
| `05_grandfather.mid` | Grandfather | Bassoon |
| `06_wolf.mid` | The Wolf | French Horns |
| `07_hunters.mid` | The Hunters | March + Timpani |

These are careful transcriptions of each motif's **principal melodic line** (not the full
orchestration) and are easy to edit. Regenerate them with:

```
python tools/make_themes.py
```

## 🎻 Full-score OMR transcription

The leitmotifs above are only the short motifs. To transcribe the **whole orchestral
score**, the full IMSLP PDF was run through real Optical Music Recognition:

```
Audiveris (PDF page -> MusicXML)  ->  music21 (MusicXML -> MIDI)  ->  merge
   tools/run_omr.ps1                    tools/build_full_midi.py
```

Outputs:
- `omr/mid/p_NN.mid` — one multi-track MIDI per score page (each recognised staff = a track).
- `themes/PeterAndTheWolf_FULL.mid` — all pages concatenated into one ~17-minute,
  15-channel orchestral MIDI.

**Honest limitations:** Audiveris recognised **48 of 76 pages** (dense pages with
crescendo "wedges" trip its MusicXML exporter); it does **not** label instruments, so
parts are by staff position, and OMR on a 14-stave score makes pitch/rhythm errors.
So this is a **rough machine transcription of the whole work**, not a clean edition —
useful as a draft to listen to and correct, not a finished score. Regenerate the merge
with `python tools/build_full_midi.py`.

## 🐺 The wolf

The wolf has two moods:

- **Patrol** — it wanders the meadow calmly.
- **Hunt** — if it *sees* you (in the open, nearby) or *hears* you (running close by), its eyes glow red and it chases. Hide behind **trees** to break line of sight, and hold `Shift` to move quietly when it's near.

Each round adds more apples and a faster, sharper-eyed wolf.

Both Peter and the wolf are drawn with shaded, gradient-lit sprites (rosy cheeks and
a tasseled cap for Peter; a two-tone muzzle, pointed ears, bushy tail and glowing eyes
for the wolf) rather than flat shapes, to match the polish of the meadow scenery.

## 🛠️ Built with

Plain HTML5 Canvas + a tiny WebAudio synth. No build step, no dependencies.

---

*Made to recreate a childhood dream.* 🍎
