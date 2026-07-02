# 🐺 Peter and the Wolf

A small storybook game, inspired by Prokofiev's *Peter and the Wolf* — and by a childhood dream of "a wolf moving across the screen, looking for Peter."

You play **Peter**, sneaking through a green meadow to gather apples and slip home through the **gate** before the **wolf** sniffs you out.

Everything — the meadow, the trees, Peter, the wolf, and the music cues — is drawn and synthesized in code. **No image or sound files**, just a single `index.html`.

## ▶️ Play

Open `index.html` in any modern browser. That's it.

The game **fills the whole browser window**: on big screens everything — the meadow,
the HUD, the story cards — scales up together (with the canvas re-rendered at full
resolution, so it stays crisp), and on small screens it shrinks to fit.

### 🖥️ Windows exe

A standalone desktop build (game + orchestral music, no browser needed) lives in
`desktop/`. To build the portable exe:

```
cd desktop
npm install
npm run dist        # → desktop/dist/PeterAndTheWolf.exe (single portable file)
```

`npm run dist` copies the current `index.html` and `audio/` from the repo root,
then packages them with Electron. `desktop/dist/win-unpacked/` holds the same app
as a folder if you prefer not to use the portable exe.

## 🎮 Controls

| Action | Keys |
| --- | --- |
| Move | `W` `A` `S` `D` or arrow keys |
| Tip-toe (quiet, slower) | hold `Shift` |
| Throw apple / search / spring the trap | `Space` |
| Pause | `P` |
| Mute / unmute | `M` |
| **Touch screens** | drag the **left half** to walk, tap the **right half** to act |

## ✨ Game feel

- **Three hearts** per level — the wolf nipping you costs a heart (with a knock-back
  and a moment of invulnerability) instead of ending the run outright.
- **The wolf pounces**: when it gets close it crouches with a flashing **❗**, then
  leaps in a straight line — sidestep the telegraph to survive.
- **Score, stars & best**: apples, speed and hearts kept all earn points; each level
  ends with a ★-rating and your best total is saved between sessions.
- **A real capture scene**: setting the trap tosses the rope over the oak's branch,
  where the noose dangles and sways; springing it plays a full cutscene — the rope
  snaps around the wolf's tail, yanks it under the branch and **hauls it up into the
  tree**, upside-down and kicking, while Grandpa hurries over and the branch creaks.
- **The Triumphal Procession**: after every capture, a letterboxed, skippable parade
  cutscene plays to the Hunters' March — Peter marches in front with a golden pennant,
  the bird loops overhead, **two hunters carry the sleeping wolf slung from a pole**,
  and Grandpa, the cat and the duck follow through a sunset meadow under falling
  confetti. Press `Space` (or tap) to skip.
- **A minimap** in the corner of every big scrolling level shows friends, foes and the goal.
- **Each level has its own light**: day meadow, golden afternoon with drifting leaves,
  blue dusk, and a night forest full of fireflies.
- **A living meadow**: cloud shadows drift across the grass, soft sun shafts and sunlit
  patches warm the day levels, wind waves ripple through swaying grass and real petaled
  flowers, butterflies flutter between blooms, dragonflies hover and dart, pollen floats
  in the light, an occasional dove glides overhead, fireflies wink at dusk and by night,
  a pair of hunters sometimes patrols through the trees, and the pond glitters around a
  drifting lily pad.
- **Character acting**: Peter blinks and his cap tassel swings as he runs, the wolf's
  ear flicks and its hunting eye pulses red, and both kick up little dust puffs at full
  speed. The cat is a proper ginger tabby with a swishing tail, and Grandpa potters
  about near the oak, cane tapping.
- **The wolf fears the hunters**: when the patrol wanders near, the wolf breaks off
  whatever it's doing and slinks away, tail tucked between its legs — use the moment
  to breathe (or to set your trap).
- Particles, screen shake and hurt-blinks make every splat, pickup and close call land.

## 🎯 How to win

1. **Collect every apple** scattered in the meadow.
2. Then choose your ending:
   - **Escape** — slip home through the **gate** on the right, *or*
   - **Hero's ending** — once the apples are gathered, the rope flips up **over the
     old oak's branch** and hangs as a **snare**. Lure the wolf underneath and press
     `Space` — the noose snags its **tail** and hoists it up into the tree, where it
     dangles upside-down, flailing and swinging, just like in the story.
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
