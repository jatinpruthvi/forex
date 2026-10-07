#!/usr/bin/env python3
"""Generate Glimpse (glimpse.wozart.com) summaries for YouTube video IDs.

Flow reverse-engineered from the site's own client:
  GET  /api/video?id=<ytid>                 -> metadata
  POST /api/generate {videoId,style,fresh}  -> {jobId}
  POST /api/generate/step {jobId,fresh}     -> advances job
  GET  /api/generate/status?jobId=          -> poll until done, yields slug
  GET  /v/<slug>                            -> server-rendered detail page
"""
import json, re, sys, time, html, urllib.request, urllib.error
from pathlib import Path

BASE = "https://glimpse.wozart.com"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36"
OUT = Path("glimpse")


def req(method, path, body=None, timeout=60):
    url = BASE + path
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("User-Agent", UA)
    r.add_header("Accept", "application/json")
    if data:
        r.add_header("Content-Type", "application/json")
    r.add_header("Referer", BASE + "/")
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")
    try:
        return 200, json.loads(raw)
    except Exception:
        return 200, raw


def generate(ytid, max_wait=300):
    code, d = req("POST", "/api/generate",
                  {"videoId": ytid, "style": "zen-minimal", "fresh": False})
    if code != 200 or not isinstance(d, dict):
        raise RuntimeError(f"generate failed {code}: {str(d)[:300]}")
    job = d.get("jobId") or d.get("job", {}).get("jobId")
    slug = d.get("slug")
    if slug:
        return slug
    if not job:
        raise RuntimeError(f"no jobId: {str(d)[:400]}")

    deadline = time.time() + max_wait
    slug = None
    while time.time() < deadline:
        req("POST", "/api/generate/step", {"jobId": job, "fresh": False}, timeout=90)
        code, st = req("GET", f"/api/generate/status?jobId={job}", timeout=60)
        if isinstance(st, dict):
            # find a slug anywhere in the payload
            blob = json.dumps(st)
            m = re.search(r'"(?:slug|shareSlug|path)"\s*:\s*"([a-z0-9]{6,12})"', blob)
            if m:
                slug = m.group(1)
                break
            status = str(st.get("status") or st.get("state") or "").lower()
            if status in ("done", "complete", "completed", "ready", "succeeded"):
                break
            if status in ("failed", "error"):
                raise RuntimeError(f"job failed: {str(st)[:300]}")
        time.sleep(3)
    return slug


def page_text(slug):
    code, raw = req("GET", f"/v/{slug}", timeout=60)
    if code != 200 or not isinstance(raw, str):
        raise RuntimeError(f"page {code}")
    return raw


def extract(slug, ytid):
    """Pull the readable detail out of the server-rendered /v/<slug> page."""
    h = page_text(slug)
    # Next.js RSC payload holds the structured data; also parse rendered DOM.
    m = re.search(r'<body([^>]*)>(.*?)</body>', h, re.S)
    body = m.group(2) if m else h
    body = re.sub(r"<script.*?</script>", "", body, flags=re.S)
    body = re.sub(r"<style.*?</style>", "", body, flags=re.S)
    # headings/paragraphs/list items in document order
    parts = []
    for tag, txt in re.findall(
        r"<(h1|h2|h3|h4|p|li|figcaption|blockquote)\b[^>]*>(.*?)</\1>", body, re.S
    ):
        t = re.sub(r"<[^>]+>", "", txt)
        t = html.unescape(t).strip()
        t = re.sub(r"\s+", " ", t)
        if t and t not in parts:
            parts.append(t)
    title_m = re.search(r"<title>(.*?)</title>", h, re.S)
    title = html.unescape(title_m.group(1)).strip() if title_m else slug
    return title, parts


def main():
    jobs = json.loads(Path(sys.argv[1]).read_text())
    OUT.mkdir(exist_ok=True)
    results = {}
    for ytid, slug_hint_title in jobs:
        ytid = ytid.strip()
        if not ytid:
            continue
        out_md = OUT / f"{ytid}.md"
        if out_md.exists() and out_md.stat().st_size > 200:
            print(f"SKIP {ytid} (exists)")
            continue
        try:
            print(f"GEN  {ytid} ...", flush=True)
            slug = generate(ytid)
            if not slug:
                raise RuntimeError("no slug resolved")
            title, parts = extract(slug, ytid)
            md = (
                f"# {title}\n\n"
                f"- YouTube: https://www.youtube.com/watch?v={ytid}\n"
                f"- Glimpse: {BASE}/v/{slug}\n\n"
                + "\n\n".join(parts)
                + "\n"
            )
            out_md.write_text(md, encoding="utf-8")
            results[ytid] = slug
            print(f"  OK  slug={slug} chars={len(md)}", flush=True)
        except Exception as e:
            print(f"  FAIL {ytid}: {e}", flush=True)
        time.sleep(4)
    Path("glimpse/slugs.json").write_text(json.dumps(results, indent=2))
    print("done", len(results))


if __name__ == "__main__":
    main()
