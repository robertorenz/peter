#!/usr/bin/env python3
"""Boot the game in VICE and screenshot the startup splash, then the title.

  py -3 tools/splash_test.py

Saves build/splash_shot_N.png at intervals through the boot so both the
poster (~5s hold) and the screen after it are captured.
"""
import socket, subprocess, sys, time, os

HERE = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.join(HERE, "..", "build")
PRG = os.path.join(BUILD, "meadow.prg")

vice = subprocess.Popen([
    r"C:\vice\bin\x64sc.exe", "-remotemonitor", "+sound", "-silent", PRG])


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
    time.sleep(9)                      # autostart: LOAD + RUN
    for i, wait in enumerate((0, 2, 2, 4, 4)):
        time.sleep(wait)
        shot = os.path.join(BUILD, f"splash_shot_{i}.png").replace("\\", "/")
        mon([f'screenshot "{shot}" 2', "x"], linger=0.6)
        print(f"shot {i}: {os.path.exists(shot.replace('/', os.sep))}")
    mon(["quit"], linger=0.5)
    time.sleep(1)
finally:
    if vice.poll() is None:
        vice.kill()
