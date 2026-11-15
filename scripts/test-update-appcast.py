#!/usr/bin/env python3
"""Offline invariants for the stable/beta update feed publication step."""
import base64
import importlib.util
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

spec = importlib.util.spec_from_file_location("appcast", Path(__file__).with_name("update-appcast.py"))
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)


def feed(version, build, channel="", displayed_version=None):
    root = ET.Element("rss", version="2.0")
    content = ET.SubElement(root, "channel")
    ET.SubElement(content, "title").text = "Maspice"
    item = ET.SubElement(content, "item")
    ET.SubElement(item, "title").text = version
    ET.SubElement(item, appcast.field("version")).text = str(build)
    ET.SubElement(item, appcast.field("shortVersionString")).text = displayed_version or version
    if channel:
        ET.SubElement(item, appcast.field("channel")).text = channel
    ET.SubElement(item, "enclosure", {
        "url": f"https://github.com/BeriBeli/spice-mac/releases/download/v{version}/Maspice.app.zip",
        "length": "1234", appcast.field("edSignature"): base64.b64encode(bytes(64)).decode(),
    })
    return ET.ElementTree(root)


class FeedPublicationTests(unittest.TestCase):
    def test_beta_preserves_stable_item_and_archive_signature(self):
        stable = feed("0.6.1", 34)
        signature = stable.getroot().find("channel/item/enclosure").attrib.copy()
        merged = appcast.merge(stable, feed("0.6.2-beta.1", 35, "beta", "0.6.2"), "0.6.2-beta.1")
        items = merged.getroot().findall("channel/item")
        self.assertEqual([i.findtext(appcast.field("channel"), "") for i in items], ["beta", ""])
        self.assertEqual(items[1].find("enclosure").attrib, signature)
        self.assertEqual(items[0].findtext(appcast.field("shortVersionString")), "0.6.2-beta.1")

    def test_beta_without_channel_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "beta channel"):
            appcast.merge(feed("0.6.1", 34), feed("0.6.2-beta.1", 35), "0.6.2-beta.1")

    def test_stable_after_beta_and_idempotent_republication(self):
        merged = appcast.merge(feed("0.6.2-beta.1", 35, "beta"), feed("0.6.2", 36), "0.6.2")
        merged = appcast.merge(merged, feed("0.6.2", 36), "0.6.2")
        items = merged.getroot().findall("channel/item")
        self.assertEqual(len(items), 2)
        self.assertIsNone(items[0].find(appcast.field("channel")))

    def test_build_regression_and_archive_replacement_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "backwards"):
            appcast.merge(feed("0.6.2", 36), feed("0.6.2-beta.1", 35, "beta"), "0.6.2-beta.1")
        with self.assertRaisesRegex(ValueError, "different archive"):
            appcast.merge(feed("0.6.2-beta.1", 35, "beta"), feed("0.6.2", 35), "0.6.2")


if __name__ == "__main__":
    unittest.main()
