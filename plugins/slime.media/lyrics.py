#!/usr/bin/env python3
"""Lyrics for SlimeS-Karaoke, from LRCLIB (https://lrclib.net, free, no key).

  lyrics.py ARTIST TITLE [ALBUM] [SECONDS] [--refresh]

Prints JSON: {"status": "synced" | "plain" | "instrumental" | "none" | "error",
              "lines": [{"t": seconds, "text": "..."}],   (synced only)
              "plain": "..."}
Answers are cached in ~/.cache/slime-shell/lyrics/, so a song is only looked
up once (--refresh asks again). Only the artist, title, album and length are
sent.
"""
import hashlib
import json
import os
import re
import sys
import urllib.parse
import urllib.request

API = "https://lrclib.net/api"
AGENT = "slime-shell karaoke (https://github.com/DasPoxy/slime-shell)"
CACHE = os.path.expanduser("~/.cache/slime-shell/lyrics")
STAMP = re.compile(r"\[(\d+):(\d+(?:\.\d+)?)\]")


def fetch(path, params):
    url = API + path + "?" + urllib.parse.urlencode({k: v for k, v in params.items() if v})
    req = urllib.request.Request(url, headers={"User-Agent": AGENT})
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


WORD = re.compile(r"<(\d+):(\d+(?:\.\d+)?)>")


def parse_lrc(lrc):
    """Lines as {t, text}; with enhanced LRC (<mm:ss.xx> before words) also
    "words": [{t, text}] for word-by-word timing."""
    lines = []
    for raw in (lrc or "").splitlines():
        stamps = STAMP.findall(raw)
        body = STAMP.sub("", raw)
        words = []
        if WORD.search(body):
            parts = WORD.split(body)      # text, m, s, text, m, s, text…
            for i in range(1, len(parts) - 2, 3):
                w = parts[i + 2].strip()
                if w:
                    words.append({"t": int(parts[i]) * 60 + float(parts[i + 1]), "text": w})
        text = WORD.sub("", body).strip()
        text = re.sub(r"\s+", " ", text)
        for m, sec in stamps:
            line = {"t": int(m) * 60 + float(sec), "text": text}
            if words:
                line["words"] = words
            lines.append(line)
    lines.sort(key=lambda l: l["t"])
    return lines


def lyric_lines(hit):
    return [l for l in (hit.get("syncedLyrics") or hit.get("plainLyrics") or "").splitlines() if l.strip()]


def tidy(title):
    # "Song (Remastered 2011) - Live" -> "Song": players often decorate titles
    t = re.sub(r"\s*[\(\[][^\)\]]*(remaster|live|version|edit|mix|feat)[^\)\]]*[\)\]]", "", title, flags=re.I)
    return re.sub(r"\s+-\s+.*(remaster|live|version|edit|mix).*$", "", t, flags=re.I).strip()


def look_up(artist, title, album, seconds):
    hit = fetch("/get", {"artist_name": artist, "track_name": title, "album_name": album,
                         "duration": str(round(seconds)) if seconds else ""})
    if not hit and tidy(title) != title:
        hit = fetch("/get", {"artist_name": artist, "track_name": tidy(title)})
    # a suspiciously short entry (someone's test upload) doesn't count
    if hit and not hit.get("instrumental") and len(lyric_lines(hit)) < 5:
        hit = None
    if not hit:
        found = [h for h in (fetch("/search", {"track_name": tidy(title), "artist_name": artist}) or [])
                 if h.get("instrumental") or len(lyric_lines(h)) >= 5]
        # synced first, then the nearest in length
        found.sort(key=lambda h: (not h.get("syncedLyrics"), abs((h.get("duration") or 0) - seconds) if seconds else 0))
        hit = found[0] if found else None
    if not hit:
        return {"status": "none", "lines": [], "plain": ""}
    if hit.get("instrumental"):
        return {"status": "instrumental", "lines": [], "plain": ""}
    lines = parse_lrc(hit.get("syncedLyrics"))
    plain = hit.get("plainLyrics") or "\n".join(l["text"] for l in lines)
    if lines:
        return {"status": "synced", "lines": lines, "plain": plain}
    if plain:
        return {"status": "plain", "lines": [], "plain": plain}
    return {"status": "none", "lines": [], "plain": ""}


def main():
    args = [a for a in sys.argv[1:] if a != "--refresh"]
    refresh = "--refresh" in sys.argv
    artist, title = (args + ["", ""])[:2]
    album = args[2] if len(args) > 2 else ""
    seconds = float(args[3]) if len(args) > 3 and args[3] else 0
    if not title:
        print(json.dumps({"status": "none", "lines": [], "plain": ""}))
        return
    key = hashlib.sha1(f"{artist}\n{title}\n{album}".lower().encode()).hexdigest()
    path = os.path.join(CACHE, key + ".json")
    if not refresh and os.path.exists(path):
        with open(path) as f:
            print(f.read())
        return
    try:
        out = look_up(artist, title, album, seconds)
    except Exception as e:  # offline, timeouts: say so, don't cache
        print(json.dumps({"status": "error", "lines": [], "plain": "", "error": str(e)}))
        return
    os.makedirs(CACHE, exist_ok=True)
    with open(path, "w") as f:
        json.dump(out, f)
    print(json.dumps(out))


if __name__ == "__main__":
    main()
