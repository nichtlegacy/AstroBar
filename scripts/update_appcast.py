#!/usr/bin/env python3
"""Insert or replace one release entry in the Sparkle appcast.

Signs the DMG with Sparkle's `sign_update` (private EdDSA key lives in the
login keychain) and writes the resulting item into appcast.xml, newest first.
Re-running for a version that already exists replaces that entry instead of
appending a duplicate.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from email.utils import format_datetime
from datetime import datetime, timezone
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC_NS = "http://purl.org/dc/elements/1.1/"

ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", DC_NS)


def sign(sign_update: Path, dmg: Path) -> tuple[str, str]:
    """Return (edSignature, length) for the DMG."""
    result = subprocess.run(
        [str(sign_update), str(dmg)],
        capture_output=True,
        text=True,
        check=True,
    )
    output = result.stdout.strip()
    signature = re.search(r'sparkle:edSignature="([^"]+)"', output)
    length = re.search(r'length="([^"]+)"', output)
    if not signature or not length:
        raise SystemExit(f"could not parse sign_update output: {output!r}")
    return signature.group(1), length.group(1)


def empty_appcast(title: str) -> ET.ElementTree:
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = title
    ET.SubElement(channel, "description").text = f"Most recent changes for {title}."
    ET.SubElement(channel, "language").text = "en"
    return ET.ElementTree(rss)


def build_item(args, signature: str, length: str, notes: str | None) -> ET.Element:
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {args.version}"
    ET.SubElement(item, "pubDate").text = format_datetime(datetime.now(timezone.utc))
    ET.SubElement(item, f"{{{SPARKLE_NS}}}version").text = str(args.build)
    ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString").text = args.version
    ET.SubElement(item, f"{{{SPARKLE_NS}}}minimumSystemVersion").text = args.min_system
    if notes:
        ET.SubElement(item, "description").text = notes
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": args.url,
            "type": "application/octet-stream",
            f"{{{SPARKLE_NS}}}edSignature": signature,
            "length": length,
        },
    )
    return item


def render_notes(path: Path | None) -> str | None:
    if path is None:
        return None
    if not path.exists():
        return None
    lines = [line.rstrip() for line in path.read_text().splitlines()]
    bullets = [line.lstrip("-* ").strip() for line in lines if line.strip().startswith(("-", "*"))]
    if bullets:
        body = "".join(f"<li>{b}</li>" for b in bullets)
        return f"<ul>{body}</ul>"
    return "".join(f"<p>{line}</p>" for line in lines if line.strip())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--appcast", default="appcast.xml", type=Path)
    parser.add_argument("--dmg", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--url", required=True, help="public download URL of the DMG")
    parser.add_argument("--min-system", default="14.0")
    parser.add_argument("--notes", type=Path, help="markdown release notes, bullets become <li>")
    parser.add_argument(
        "--sign-update",
        type=Path,
        default=Path(".build/artifacts/sparkle/Sparkle/bin/sign_update"),
    )
    parser.add_argument("--channel-title", default="AstroBar")
    args = parser.parse_args()

    if not args.dmg.exists():
        raise SystemExit(f"error: {args.dmg} not found")
    if not args.sign_update.exists():
        raise SystemExit(
            f"error: sign_update not found at {args.sign_update}, run 'swift package resolve' first"
        )

    signature, length = sign(args.sign_update, args.dmg)

    if args.appcast.exists():
        tree = ET.parse(args.appcast)
    else:
        tree = empty_appcast(args.channel_title)

    channel = tree.getroot().find("channel")
    if channel is None:
        raise SystemExit(f"error: {args.appcast} has no <channel> element")

    for existing in channel.findall("item"):
        version = existing.find(f"{{{SPARKLE_NS}}}shortVersionString")
        if version is not None and version.text == args.version:
            channel.remove(existing)

    item = build_item(args, signature, length, render_notes(args.notes))

    first_item_index = next(
        (i for i, child in enumerate(channel) if child.tag == "item"),
        len(channel),
    )
    channel.insert(first_item_index, item)

    ET.indent(tree, space="  ")
    tree.write(args.appcast, encoding="utf-8", xml_declaration=True)
    with args.appcast.open("a") as handle:
        handle.write("\n")

    print(f"appcast updated: {args.version} (build {args.build}) -> {args.url}")


if __name__ == "__main__":
    main()
