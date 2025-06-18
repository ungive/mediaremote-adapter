# Prints a live view of the currently playing media, which is updated
# whenever the song's metadata or the timeline position changes:
#
# (com.spotify.client) ▶ 00:46/04:58  Happier Than Ever - Billie Eilish

import subprocess
import threading
import time
import json
import sys

defaults = {
    "title": "?",
    "artist": "?",
    "timestampEpochMicros": int(time.time() * 1000000),
    "elapsedTimeMicros": 0,
    "playing": False,
    "durationMicros": 0,
}
line = ""
live = dict(defaults)


def stream():
    global live
    process = subprocess.Popen(
        ["media-control", "stream"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    for line in process.stdout:
        d = json.loads(line)
        p = d["payload"]
        if not d["diff"] and len(p) == 0:
            live = dict(defaults)
        else:
            p = {k: v for k, v in p.items() if v is not None}
            live.update(p)
        dump()


def format(duration):
    minutes = duration // 60000000
    seconds = (duration // 1000000) % 60
    return f"{minutes:02d}:{seconds:02d}"


def dump():
    global line
    current_epoch = int(time.time() * 1000000)
    time_diff = current_epoch - live["timestampEpochMicros"]
    total_time = live["elapsedTimeMicros"] + live["playing"] * time_diff
    sys.stdout.write("\r" + " " * len(line))
    sys.stdout.flush()
    icon = "\u25b6" if live["playing"] else "\u23f8"
    line = (
        "\r"
        + ("\u25b6" if live["playing"] else "\u23f8")
        + " "
        + format(total_time)
        + "/"
        + format(live["durationMicros"])
        + "  "
        + live["title"]
        + " - "
        + live["artist"]
    )
    sys.stdout.write(line)
    sys.stdout.flush()


if __name__ == "__main__":
    threading.Thread(target=stream, daemon=True).start()
    while True:
        dump()
        time.sleep(1)
