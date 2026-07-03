#!/usr/bin/env python3

import argparse
import concurrent.futures
import html
import json
import os
import re
import signal
import subprocess
import sys
import urllib.request


_children = set()
_cue_re = re.compile(
    r"\[(?:music(?:\s+playing|\s+and\s+singing)?|singing(?:\s+and\s+music)?|instrumental|applause|cheering|laughter|humming|vocalizing)\s*\]",
    re.IGNORECASE,
)


def _stop_child(*_args):
    for child in list(_children):
        if child.poll() is not None:
            continue
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    raise SystemExit(1)


def _clean(value):
    value = html.unescape(str(value or ""))
    value = re.sub(r"<[^>]+>", "", value)
    return re.sub(r"\s+", " ", value.replace("\n", " ")).strip()


def _clean_caption(value):
    value = re.sub(r"^(?:>>\s*)+", "", _clean(value))
    value = _cue_re.sub(" ", value)
    value = re.sub(r"^[\s♪♫]+|[\s♪♫]+$", "", value)
    return re.sub(r"\s+", " ", value).strip()


def _tokens(value):
    ignored = {
        "official",
        "music",
        "video",
        "audio",
        "lyrics",
        "lyric",
        "visualizer",
        "visualiser",
        "topic",
    }
    return {word for word in re.findall(r"[\w]+", str(value or "").casefold()) if len(word) > 1 and word not in ignored}


def _caption_sets(entry):
    return entry.get("subtitles") or {}, entry.get("automatic_captions") or {}


def _has_json3(tracks):
    return any(item.get("ext") == "json3" and item.get("url") for item in tracks or [])


def _has_captions(entry):
    manual, automatic = _caption_sets(entry)
    return any(_has_json3(items) for items in manual.values()) or any(
        _has_json3(items) for key, items in automatic.items() if key != "live_chat"
    )


def _metadata_score(entry, title, artist, duration):
    candidate_title = str(entry.get("title") or "")
    candidate_meta = " ".join(
        str(entry.get(key) or "") for key in ("title", "track", "artist", "uploader", "channel")
    )
    title_tokens = _tokens(title)
    artist_tokens = _tokens(artist)
    candidate_tokens = _tokens(candidate_meta)
    title_overlap = len(title_tokens & candidate_tokens) / max(1, len(title_tokens))
    artist_overlap = len(artist_tokens & candidate_tokens) / max(1, len(artist_tokens)) if artist_tokens else 1.0
    if title_overlap < 0.5 or artist_overlap < 0.34:
        return None

    candidate_duration = int(entry.get("duration") or 0)
    duration_delta = abs(candidate_duration - duration) if duration > 0 and candidate_duration > 0 else 0
    if duration_delta > max(25, int(duration * 0.15)):
        return None

    manual, _automatic = _caption_sets(entry)
    manual_bonus = 8 if any(_has_json3(items) for items in manual.values()) else 0
    lyric_bonus = 4 if "lyric" in candidate_title.casefold() else 0
    official_bonus = 2 if "official" in candidate_title.casefold() else 0
    return title_overlap * 55 + artist_overlap * 30 + manual_bonus + lyric_bonus + official_bonus - duration_delta


def _candidate_score(entry, title, artist, duration):
    if not _has_captions(entry):
        return None
    return _metadata_score(entry, title, artist, duration)


def _pick_candidate(entries, title, artist, duration):
    ranked = []
    for entry in entries:
        score = _candidate_score(entry, title, artist, duration)
        if score is not None:
            ranked.append((score, entry))
    return max(ranked, key=lambda item: item[0])[1] if ranked else None


def _pick_caption(entry):
    manual, automatic = _caption_sets(entry)
    language = str(entry.get("language") or "").strip()

    def ordered_keys(captions):
        keys = [key for key in captions if key != "live_chat"]
        preferred = []
        if language:
            preferred.extend((f"{language}-orig", language))
        preferred.extend(key for key in keys if key.endswith("-orig"))
        preferred.extend(("en-orig", "en"))
        return list(dict.fromkeys(preferred + keys))

    for source_name, captions in (("manual", manual), ("automatic", automatic)):
        for key in ordered_keys(captions):
            for item in captions.get(key, []):
                if item.get("ext") == "json3" and item.get("url"):
                    return item["url"], key, source_name
    return None, "", ""


def _run_process(command, timeout):
    child = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    _children.add(child)
    try:
        stdout, stderr = child.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGTERM)
        child.communicate()
        raise RuntimeError("YouTube request timed out")
    finally:
        _children.discard(child)
    if not stdout.strip():
        raise RuntimeError(_clean(stderr) or "YouTube returned no data")
    return stdout


def _load_video(entry):
    video_id = entry.get("id")
    if not video_id:
        return None
    command = [
        "yt-dlp",
        "--ignore-config",
        "--no-warnings",
        "--socket-timeout",
        "8",
        "--no-check-formats",
        "--extractor-args",
        "youtube:skip=hls,dash",
        "--dump-single-json",
        f"https://www.youtube.com/watch?v={video_id}",
    ]
    try:
        return json.loads(_run_process(command, 14))
    except Exception:
        return None


def _run_search(query, title, artist, duration):
    command = [
        "yt-dlp",
        "--ignore-config",
        "--no-warnings",
        "--socket-timeout",
        "8",
        "--flat-playlist",
        "--playlist-items",
        "1:8",
        "--dump-single-json",
        f"ytsearch8:{query}",
    ]
    entries = json.loads(_run_process(command, 12)).get("entries") or []
    ranked = []
    for entry in entries:
        score = _metadata_score(entry, title, artist, duration)
        if score is not None:
            ranked.append((score, entry))
    candidates = [entry for _score, entry in sorted(ranked, key=lambda item: item[0], reverse=True)[:6]]
    if not candidates:
        return []

    loaded = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(4, len(candidates))) as executor:
        futures = [executor.submit(_load_video, entry) for entry in candidates]
        for future in concurrent.futures.as_completed(futures):
            entry = future.result()
            if entry:
                loaded.append(entry)
    return loaded


def _fetch_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.load(response)


def _parse_events(payload):
    lines = []
    for event in payload.get("events") or []:
        segments = event.get("segs") or []
        text = _clean_caption("".join(str(segment.get("utf8") or "") for segment in segments))
        if not text:
            continue

        start = int(event.get("tStartMs") or 0)
        duration = max(1, int(event.get("dDurationMs") or 0))
        if event.get("aAppend") and lines:
            previous = lines[-1]
            if text.casefold() not in previous["text"].casefold():
                previous["text"] = _clean(f"{previous['text']} {text}")
            previous["duration"] = max(previous["duration"], start + duration - previous["time"])
            continue

        syllables = []
        timed = [
            segment
            for segment in segments
            if segment.get("tOffsetMs") is not None and _clean_caption(segment.get("utf8"))
        ]
        for index, segment in enumerate(timed):
            word_start = start + int(segment.get("tOffsetMs") or 0)
            if index + 1 < len(timed):
                word_end = start + int(timed[index + 1].get("tOffsetMs") or 0)
            else:
                word_end = start + duration
            syllables.append(
                {
                    "time": word_start,
                    "duration": max(1, word_end - word_start),
                    "text": _clean_caption(segment.get("utf8")),
                }
            )

        if lines and lines[-1]["text"].casefold() == text.casefold():
            lines[-1]["duration"] = max(lines[-1]["duration"], start + duration - lines[-1]["time"])
            continue
        lines.append({"time": start, "duration": duration, "text": text, "syllabus": syllables})
    return lines


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--title", required=True)
    parser.add_argument("--artist", default="")
    parser.add_argument("--duration", type=int, default=0)
    args = parser.parse_args()

    query = " ".join(part for part in (args.artist, args.title, "lyrics") if part).strip()
    try:
        if not args.artist.strip() or args.duration > 900:
            raise RuntimeError("The active media does not look like a song")
        entries = _run_search(query, args.title, args.artist, args.duration)
        candidate = _pick_candidate(entries, args.title, args.artist, args.duration)
        if not candidate:
            raise RuntimeError("No duration-matched YouTube captions found")
        url, language, source_type = _pick_caption(candidate)
        if not url:
            raise RuntimeError("The matching YouTube result has no usable captions")
        lines = _parse_events(_fetch_json(url))
        if len(lines) < 4:
            raise RuntimeError("YouTube captions did not contain enough timed lines")
        result = {
            "success": True,
            "provider": "YouTube captions",
            "sourceTitle": candidate.get("title") or "",
            "videoId": candidate.get("id") or "",
            "language": language,
            "captionType": source_type,
            "lyrics": lines,
        }
    except Exception as error:
        result = {"success": False, "error": _clean(error)}
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
    return 0 if result["success"] else 1


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, _stop_child)
    signal.signal(signal.SIGINT, _stop_child)
    sys.exit(main())
