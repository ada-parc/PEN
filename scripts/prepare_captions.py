#!/usr/bin/env python3
"""Turn the raw caption exports in videos/<module>/ into site-ready files.

    python3 -I scripts/prepare_captions.py            # all configured videos

For each video listed in VIDEOS below this reads the raw .vtt export and writes:

    assets/captions/<module>/<slug>.vtt      cleaned captions (for <track>)
    transcripts/<module>/<slug>.txt          transcript paragraphs (blank-line separated)

What "cleaned" means (and nothing more):
  * the "ADA-PARC:" speaker prefix on every cue is dropped (one narrator);
  * a short, explicit list of unambiguous mishearings is fixed (FIXES);
  * cues of up to ~270 characters are re-cut into captions of at most two lines
    of 42 characters, with the original cue's time span shared out in proportion
    to text length (the export has no per-word timing, so inside a long cue the
    split is an estimate, usually within about a second);
  * CRLF line endings become LF.
Wording is otherwise left exactly as exported. Anything that looks wrong but is
not certain (the narrator's own slips, garbled sentences) is NOT changed here;
fix those by hand in the output after checking against the audio.

The raw exports stay in videos/ (gitignored with the video files). Re-run this
whenever a new export arrives.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# module dir -> [(raw file stem under videos/<module>/, output slug)]
VIDEOS = {
    "module_2": [
        ("M2 Demographics Transcript 2026", "demographics"),
        ("M2 Community Living Transcript 2026", "community-living"),
        ("M2 Community Participation Transcript 2026", "community-participation"),
        ("M2 Work and Economics Transcript 2026", "work-and-economics"),
        ("M2 City Data Transcript 2026", "city-data"),
        ("M2 Scorecards Transcript 2026", "scorecards"),
    ],
}

# Unambiguous fixes only: (pattern, replacement). The site is "ADA-PARC".
FIXES = [
    (r"\bADAPARC\b", "ADA-PARC"),
    (r"\bADA Park's\b", "ADA-PARC's"),
    (r"\bADA-part\b", "ADA-PARC"),
    (r"\bwork in economics\b", "work and economics"),
    (r"\bworking economics\b", "work and economics"),
    (r"\bgroup corridor\b", "group quarter"),
    (r"generate a map, A data table", "generate a map, a data table"),
]

MAX_LINE = 42
MAX_CUE = 84  # two lines


def ts(t):
    m = re.match(r"(\d+):(\d+):(\d+)\.(\d+)", t)
    h, mi, s, ms = (int(x) for x in m.groups())
    return h * 3600 + mi * 60 + s + ms / 1000


def fmt(sec):
    ms = int(round(sec * 1000))
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d}.{ms:03d}"


def read_cues(path):
    raw = path.read_text(encoding="utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
    cues = []
    for block in re.split(r"\n\s*\n", raw.strip()):
        lines = [l for l in block.split("\n") if l.strip()]
        timing = next((i for i, l in enumerate(lines) if "-->" in l), None)
        if timing is None:
            continue
        a, b = (x.strip() for x in lines[timing].split("-->"))
        text = " ".join(l.strip() for l in lines[timing + 1:])
        text = re.sub(r"^ADA-PARC:\s*", "", text)
        for pat, rep in FIXES:
            text = re.sub(pat, rep, text)
        text = re.sub(r"\s+", " ", text).strip()
        if text:
            cues.append((ts(a), ts(b.split()[0]), text))
    return cues


def sentences(text):
    # Keep "U.S." and similar from ending a sentence.
    t = text.replace("U.S.", "U․S․")
    parts = re.split(r"(?<=[.?!])\s+(?=[A-Z\"'(])", t)
    return [p.replace("․", ".") for p in parts if p]


def split_long(s):
    """Split one over-long sentence near its middle, preferring punctuation."""
    if len(s) <= MAX_CUE:
        return [s]
    mid = len(s) / 2
    punct = [m.end() for m in re.finditer(r"[,;:…]\s", s)]
    spaces = [m.start() for m in re.finditer(r" ", s)]
    pool = [p for p in punct if 20 < p < len(s) - 20] or spaces
    cut = min(pool, key=lambda p: abs(p - mid))
    return split_long(s[:cut].strip()) + split_long(s[cut:].strip())


def pack(pieces):
    out = []
    for p in pieces:
        if out and len(out[-1]) + 1 + len(p) <= MAX_CUE:
            out[-1] += " " + p
        else:
            out.append(p)
    return out


def two_lines(s):
    if len(s) <= MAX_LINE:
        return s
    spaces = [m.start() for m in re.finditer(r" ", s)]
    cut = min(spaces, key=lambda p: abs(p - len(s) / 2))
    return s[:cut] + "\n" + s[cut + 1:]


def caption_cues(cues):
    out = []
    for start, end, text in cues:
        pieces = pack([q for s in sentences(text) for q in split_long(s)])
        total = sum(len(p) for p in pieces)
        t = start
        for p in pieces:
            d = (end - start) * len(p) / total
            out.append((t, t + d, two_lines(p)))
            t += d
    return out


def paragraphs(cues, target=380):
    """Pack cue text into readable paragraphs, breaking only at sentence ends."""
    paras, cur = [], ""
    for _, _, text in cues:
        cur = (cur + " " + text).strip()
        if len(cur) >= target and re.search(r"[.?!][\"')]*$", cur):
            paras.append(cur)
            cur = ""
    if cur:
        paras.append(cur)
    return paras


def main():
    for module, items in VIDEOS.items():
        cap_dir = ROOT / "assets" / "captions" / module
        txt_dir = ROOT / "transcripts" / module
        cap_dir.mkdir(parents=True, exist_ok=True)
        txt_dir.mkdir(parents=True, exist_ok=True)
        for stem, slug in items:
            src = ROOT / "videos" / module / f"{stem}.vtt"
            if not src.exists():
                sys.exit(f"missing {src}")
            cues = read_cues(src)
            caps = caption_cues(cues)
            body = "\n\n".join(
                f"{i}\n{fmt(a)} --> {fmt(b)}\n{t}" for i, (a, b, t) in enumerate(caps, 1)
            )
            (cap_dir / f"{slug}.vtt").write_text("WEBVTT\n\n" + body + "\n", encoding="utf-8")
            (txt_dir / f"{slug}.txt").write_text("\n\n".join(paragraphs(cues)) + "\n", encoding="utf-8")
            longest = max(len(t.replace("\n", " ")) for _, _, t in caps)
            print(f"{module}/{slug}: {len(cues)} cues -> {len(caps)} captions (longest {longest} chars)")


if __name__ == "__main__":
    main()
