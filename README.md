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

- A jaunty, Prokofiev-flavored **theme melody** loops while you play (all synthesized in code — press `M` to mute).
- The **🐦 bird** flutters near Peter and dive-bombs the wolf when it gives chase, breaking its focus.
- The **🦆 duck** paddles in the pond and dives underwater when the wolf prowls too close.

## 🐺 The wolf

The wolf has two moods:

- **Patrol** — it wanders the meadow calmly.
- **Hunt** — if it *sees* you (in the open, nearby) or *hears* you (running close by), its eyes glow red and it chases. Hide behind **trees** to break line of sight, and hold `Shift` to move quietly when it's near.

Each round adds more apples and a faster, sharper-eyed wolf.

## 🛠️ Built with

Plain HTML5 Canvas + a tiny WebAudio synth. No build step, no dependencies.

---

*Made to recreate a childhood dream.* 🍎
