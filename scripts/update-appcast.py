#!/usr/bin/env python3
"""Merge one generated, archive-signed release into the shared Sparkle feed."""
import argparse
import base64
import re
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-beta\.[1-9][0-9]*)?")


def field(name):
    return f"{{{SPARKLE}}}{name}"


def validate_item(item):
    version = item.findtext(field("shortVersionString"), "")
    build = item.findtext(field("version"), "")
    if not VERSION.fullmatch(version) or not re.fullmatch(r"[1-9][0-9]*", build):
        raise ValueError("invalid release version or integer build number")
    channel = item.findtext(field("channel"), "")
    if channel != ("beta" if "-beta." in version else ""):
        raise ValueError("beta releases must use the beta channel; stable releases must use the default channel")
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("release is missing an archive enclosure")
    prefix = f"https://github.com/BeriBeli/spice-mac/releases/download/v{version}/"
    if enclosure.get("url") != prefix + "Maspice.app.zip":
        raise ValueError("archive URL does not match the immutable release tag")
    signature = base64.b64decode(enclosure.get(field("edSignature"), ""), validate=True)
    if len(signature) != 64 or int(enclosure.get("length", "0")) <= 0:
        raise ValueError("release is missing an Ed25519 archive signature or length")
    return int(build)


def merge(existing, incoming, version):
    if not VERSION.fullmatch(version):
        raise ValueError("expected X.Y.Z or X.Y.Z-beta.N")
    channel = existing.getroot().find("channel")
    additions = incoming.getroot().findall("channel/item")
    if channel is None or len(additions) != 1:
        raise ValueError("expected an existing feed and exactly one generated release")
    item = additions[0]
    short_version = item.find(field("shortVersionString"))
    if short_version is None or short_version.text not in (version, version.split("-")[0]):
        raise ValueError("generated archive version does not match the requested release")
    short_version.text = version
    title = item.find("title")
    if title is not None:
        title.text = version
    build = validate_item(item)
    duplicate = None
    for previous in channel.findall("item"):
        previous_build = validate_item(previous)
        if previous_build > build:
            raise ValueError("new build number must not move backwards")
        if previous_build == build:
            if (previous.findtext(field("shortVersionString")) != version
                    or previous.find("enclosure").attrib != item.find("enclosure").attrib):
                raise ValueError("build number already belongs to a different archive")
            duplicate = previous
    if duplicate is not None:
        channel.remove(duplicate)
    channel.insert(1, item)
    ET.indent(existing, space="    ")
    return existing


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("existing", type=Path)
    parser.add_argument("incoming", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = merge(ET.parse(args.existing), ET.parse(args.incoming), args.version)
    # Parse and validate everything before touching the destination.
    result.write(args.output, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    main()
