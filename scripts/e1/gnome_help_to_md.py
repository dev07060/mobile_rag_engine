#!/usr/bin/env python3
"""Convert downloaded GNOME Help pages to Markdown for the E1 bundle.

    python3 -I scripts/e1/gnome_help_to_md.py --raw <dir> --out example/assets/corpus/e1/gnome

<dir> holds pages saved as `<lang>__<page>.html`, fetched from
https://help.gnome.org/gnome-help/<page>.html (en) or <page>.html.ko (ko).
Only the article body is kept (title, sections, steps, notes); the language
menu, navigation trail, "More Information"/"See Also" link lists and the
footer are dropped. Authors, translators, copyright lines and the license are
copied into the Markdown header. GNOME Help is licensed CC BY-SA 3.0 Unported.

Korean pages on help.gnome.org fall back to English for untranslated
paragraphs. Blocks with no Hangul (and at least 20 letters) are removed from
Korean pages and the count is recorded in the header. Prints one line per page
with the share of Hangul among letters and the number of removed blocks.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import pathlib
import re
from html.parser import HTMLParser

BLOCK = {"p", "li", "h1", "h2", "h3", "pre", "dt", "dd", "td", "th", "div"}


class _Body(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.out: list[str] = []
        self.buf: list[str] = []
        self.kind = "p"
        self.in_article = False
        self.stop = False
        self.skip_depth = 0
        self.depth = 0
        self.list_stack: list[str] = []

    def _flush(self) -> None:
        text = re.sub(r"\s+", " ", "".join(self.buf)).strip()
        self.buf = []
        if not text:
            return
        if self.kind == "h1":
            self.out.append(f"# {text}")
        elif self.kind in ("h2", "h3"):
            self.out.append(f"## {text}")
        elif self.kind == "li":
            self.out.append(f"- {text}")
        else:
            self.out.append(text)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = a.get("class") or ""
        if tag == "article":
            self.in_article = True
            return
        if not self.in_article or self.stop:
            return
        if tag == "section" and "links" in cls.split():
            self._flush()
            self.stop = True
            return
        if self.skip_depth:
            self.skip_depth += 1
            return
        if tag in ("script", "style"):
            self.skip_depth = 1
            return
        if tag in BLOCK:
            self._flush()
            if tag in ("h1", "h2", "h3", "li"):
                self.kind = tag
            elif tag == "p":
                # a <p> inside <li> stays part of the list item
                self.kind = "li" if self.kind == "li" else "p"
        if tag == "br":
            self.buf.append(" ")

    def handle_endtag(self, tag):
        if not self.in_article or self.stop:
            return
        if self.skip_depth:
            self.skip_depth -= 1
            return
        if tag == "article":
            self._flush()
            self.in_article = False
            return
        if tag in BLOCK:
            self._flush()
            if tag in ("li", "h1", "h2", "h3"):
                self.kind = "p"

    def handle_data(self, data):
        if self.in_article and not self.stop and not self.skip_depth:
            self.buf.append(data)


def _credits(raw: str) -> dict:
    def items(cls: str) -> list[str]:
        m = re.search(rf'class="{cls}">(.*?)</ul>', raw, re.S)
        if not m:
            return []
        return [html.unescape(re.sub(r"<[^>]+>", "", x)).strip()
                for x in re.findall(r"<li>(.*?)</li>", m.group(1), re.S)]
    copyrights = [html.unescape(x).strip()
                  for x in re.findall(r'<div class="copyright">(.*?)</div>', raw, re.S)]
    lic = re.search(r'class="license".*?href="(https://creativecommons\.org/[^"]+)"', raw, re.S)
    return {
        "authors": items("credits-authors"),
        "editors": items("credits-editors"),
        "translators": items("credits-translators"),
        "copyright": copyrights,
        "license_url": lic.group(1) if lic else None,
    }


def hangul_share(text: str) -> float:
    letters = [c for c in text if c.isalpha()]
    if not letters:
        return 0.0
    return sum(1 for c in letters if "가" <= c <= "힣") / len(letters)


def convert(path: pathlib.Path) -> tuple[str, dict]:
    raw = path.read_text(encoding="utf-8")
    lang, page = path.stem.split("__", 1)
    p = _Body()
    p.feed(raw)
    lines = p.out
    dropped = 0
    if lang == "ko":
        # Untranslated paragraphs fall back to English on help.gnome.org.
        # Drop blocks with no Hangul and at least 20 letters; keep headings.
        kept = []
        for line in lines:
            letters = sum(c.isalpha() for c in line)
            if not line.startswith("#") and letters >= 20 and hangul_share(line) == 0:
                dropped += 1
                continue
            kept.append(line)
        lines = kept
    title = lines[0][2:] if lines and lines[0].startswith("# ") else page
    body = "\n\n".join(lines)
    url = f"https://help.gnome.org/gnome-help/{page}.html" + (".ko" if lang == "ko" else "")
    meta = {"page": page, "lang": lang, "url": url, "title": title,
            "raw_sha256": hashlib.sha256(raw.encode("utf-8")).hexdigest(),
            "dropped_untranslated_blocks": dropped, **_credits(raw)}
    return body, meta


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True, type=pathlib.Path)
    ap.add_argument("--out", required=True, type=pathlib.Path)
    ap.add_argument("--fetched", default="2026-11-14")
    args = ap.parse_args()
    metas = []
    for path in sorted(args.raw.glob("*__*.html")):
        body, meta = convert(path)
        if meta["license_url"] != "https://creativecommons.org/licenses/by-sa/3.0/":
            raise SystemExit(f"{path.name}: unexpected license {meta['license_url']}")
        share = hangul_share(body)
        meta["hangul_share"] = round(share, 3)
        print(f"{meta['lang']} {meta['page']:<28} chars={len(body):>5} hangul={share:.2f} dropped={meta['dropped_untranslated_blocks']}")
        header = [
            f"title: {meta['title']}",
            f"source_key: gnome_{meta['lang']}_{meta['page'].replace('-', '_')}",
            f"language: {meta['lang']}",
            "domain: app_manual",
            f"url: {meta['url']}",
            f"fetched: {args.fetched}",
            "license: CC BY-SA 3.0 Unported (https://creativecommons.org/licenses/by-sa/3.0/)",
            f"authors: {', '.join(meta['authors'] + meta['editors'])}",
        ]
        if meta["translators"]:
            header.append(f"translators: {', '.join(meta['translators'])}")
        changes = "article body converted to Markdown; navigation, link lists and footer removed"
        if meta["dropped_untranslated_blocks"]:
            changes += (f"; {meta['dropped_untranslated_blocks']} untranslated English "
                        "block(s) removed")
        header.append(f"changes: {changes}")
        out = args.out / meta["lang"] / f"gnome_{meta['lang']}_{meta['page']}.md"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text("\n".join(header) + "\n---\n\n" + body + "\n", encoding="utf-8")
        meta["file"] = str(out)
        meta["md_sha256"] = hashlib.sha256(out.read_bytes()).hexdigest()
        metas.append(meta)
    (args.out / "gnome_pages_v1.json").write_text(
        json.dumps({"source": "https://help.gnome.org/gnome-help/", "fetched": args.fetched,
                    "license": "CC BY-SA 3.0 Unported", "pages": metas},
                   ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
