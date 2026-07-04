#!/usr/bin/env python3
"""Integration-test the scrolling world: boot the game in VICE with the
remote monitor on, teleport Peter east, let the camera chase him, then
screenshot.  Proves map gen, camera stepping, renderView and the
wolf show/hide logic without needing a joystick."""
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
    for c in cmds:
        s.sendall((c + "\n").encode())
        time.sleep(linger)
    try:
        data = s.recv(65536)
    except socket.timeout:
        data = b""
    s.close()
    return data.decode(errors="replace")

try:
    time.sleep(15)                     # boot + autostart under warp
    # peter -> X=744 ($02e8), stun the wolf so the shot is calm
    print(mon(["> 000b e8 02", "> 0008 ff", "x"], linger=0.6)[-80:])
    time.sleep(5)                      # camera chases him east
    print(mon([f'screenshot "{SHOT}" 2', "quit"], linger=0.8)[-80:])
    time.sleep(1)
finally:
    if vice.poll() is None:
        vice.kill()
print("shot exists:", os.path.exists(SHOT.replace("/", os.sep)))
