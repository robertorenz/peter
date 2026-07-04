#!/usr/bin/env python3
"""Integration-test the scrolling world: boot the game in VICE with the
remote monitor on, teleport Peter east, then sample the VIC fine-scroll
register while the camera pans after him.  Changing xscroll values prove
pixel-smooth scrolling; the screenshot proves the view moved."""
import socket, subprocess, sys, time, os

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "..", "build")
PRG = os.path.join(BUILD, "meadow.prg")
SHOT = os.path.join(BUILD, "east.png").replace("\\", "/")

vice = subprocess.Popen([
    r"C:\vice\bin\x64sc.exe", "-remotemonitor", "-warp", "+sound",
    "-silent", PRG])

def mon(cmds, linger=0.5):
    s = socket.create_connection(("127.0.0.1", 6510), timeout=5)
    s.settimeout(2)
    time.sleep(0.3)
    out = b""
    for c in cmds:
        s.sendall((c + "\n").encode())
        time.sleep(linger)
        try:
            out += s.recv(65536)
        except socket.timeout:
            pass
    s.close()
    return out.decode(errors="replace")

try:
    time.sleep(15)                     # boot + autostart under warp
    # peter -> X=500 ($01f4): camera must pan ~180px east
    print(mon(["> 000b f4 01", "> 0008 ff", "x"], linger=0.6)[-60:])
    scrolls = []
    for _ in range(6):                 # sample xscroll mid-pan
        time.sleep(0.35)
        r = mon(["m d016 d016", "x"], linger=0.3)
        for line in r.splitlines():
            if "d016" in line.lower():
                scrolls.append(line.split()[1])
    print("d016 samples:", scrolls)
    time.sleep(3)
    print(mon([f'screenshot "{SHOT}" 2', "quit"], linger=0.8)[-60:])
    time.sleep(1)
finally:
    if vice.poll() is None:
        vice.kill()
print("shot exists:", os.path.exists(SHOT.replace("/", os.sep)))
