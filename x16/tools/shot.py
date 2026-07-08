#!/usr/bin/env python3
"""Run PETER.PRG in x16emu for a few seconds, save the last GIF frame(s) as PNG.

  py -3 tools/shot.py [seconds] [out.png]

Optional env: SHOT_KEYS not supported by x16emu; this is a pure look-see.
Extracts the final frame (and quarter-point frames with -all) to build/.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
X16 = os.path.join(HERE, "..")
EMU = os.path.join(X16, "bin", "x16emu", "x16emu.exe")
PRG = os.path.join(X16, "build", "PETER.PRG")
GIF = os.path.join(X16, "build", "shot.gif")

def main():
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 5.0
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(X16, "build", "shot.png")
    if os.path.exists(GIF):
        os.remove(GIF)
    env = dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
    proc = subprocess.Popen(
        [EMU, "-prg", PRG, "-run", "-gif", GIF],
        cwd=os.path.join(X16, "build"), env=env,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(secs)
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
    time.sleep(0.5)

    from PIL import Image, ImageFile
    ImageFile.LOAD_TRUNCATED_IMAGES = True
    im = Image.open(GIF)
    frames = []
    count = 0
    try:
        while True:
            im.seek(count)
            frames.append(im.convert("RGB"))
            count += 1
    except (EOFError, OSError, IndexError):
        pass
    if not frames:
        sys.exit("no frames recorded")
    frames[-1].save(out)
    mid = out.replace(".png", "_mid.png")
    frames[len(frames) * 3 // 4].save(mid)
    print(f"{count} frames; last -> {out}, 75% -> {mid}")

if __name__ == "__main__":
    main()
