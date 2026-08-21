#!/usr/bin/env python3
import json
import unittest

def is_bluetooth_card(card):
    if not card:
        return False
    name = card.get("name", "")
    driver = card.get("driver", "")
    props = card.get("properties", {})
    return (
        name.startswith("bluez_card.")
        or "bluez" in driver
        or props.get("device.api") == "bluez5"
        or props.get("device.bus") == "bluetooth"
    )

def format_bt_address(raw_address):
    if not raw_address:
        return ""
    addr = str(raw_address).upper()
    if addr.startswith("BLUEZ_CARD."):
        addr = addr[11:]
    if "_" in addr:
        addr = addr.replace("_", ":")
    return addr

def parse_profile_and_codec(key, desc, prof_val=None):
    group = ""
    group_name = ""
    group_icon = "tune"
    codec_key = ""
    codec_name = ""

    lower_key = (key or "").lower()

    if lower_key == "off":
        group = "off"
        group_name = "Off"
        group_icon = "power_off"
    elif lower_key.startswith("a2dp-sink") or lower_key.startswith("a2dp_sink"):
        group = "a2dp-sink"
        group_name = "A2DP (High Fidelity)"
        group_icon = "music_note"
    elif lower_key.startswith("a2dp-source") or lower_key.startswith("a2dp_source"):
        group = "a2dp-source"
        group_name = "A2DP Source"
        group_icon = "graphic_eq"
    elif (
        lower_key.startswith("headset-head-unit")
        or lower_key.startswith("headset_head_unit")
        or lower_key.startswith("hsp")
        or lower_key.startswith("hfp")
    ):
        group = "headset-head-unit"
        group_name = "HSP/HFP (Headset)"
        group_icon = "call"
    elif lower_key.startswith("bap-sink") or lower_key.startswith("bap_sink"):
        group = "bap-sink"
        group_name = "LE Audio (BAP)"
        group_icon = "hearing"
    else:
        parts = lower_key.split("-") if "-" in lower_key else lower_key.split("_")
        if len(parts) > 1:
            group = parts[0]
            group_name = desc or group
        else:
            group = lower_key or "default"
            group_name = desc or key or "Default"
        group_icon = "tune"

    meta_codec = ""
    if isinstance(prof_val, dict):
        props = prof_val.get("properties", {})
        meta_codec = props.get("bluez5.codec") or prof_val.get("codec") or ""

    codec_source = str(meta_codec).lower() if meta_codec else lower_key

    if "ldac" in codec_source:
        codec_key = "ldac"
        codec_name = "LDAC"
    elif "aptx_hd" in codec_source or "aptx-hd" in codec_source:
        codec_key = "aptx_hd"
        codec_name = "aptX HD"
    elif "aptx_ll" in codec_source or "aptx-ll" in codec_source:
        codec_key = "aptx_ll"
        codec_name = "aptX LL"
    elif "aptx" in codec_source:
        codec_key = "aptx"
        codec_name = "aptX"
    elif "aac" in codec_source:
        codec_key = "aac"
        codec_name = "AAC"
    elif "msbc" in codec_source:
        codec_key = "msbc"
        codec_name = "mSBC"
    elif "sbc_xq" in codec_source or "sbc-xq" in codec_source:
        codec_key = "sbc_xq"
        codec_name = "SBC-XQ"
    elif "sbc" in codec_source:
        codec_key = "sbc"
        codec_name = "SBC"
    elif "cvsd" in codec_source:
        codec_key = "cvsd"
        codec_name = "CVSD"
    elif "lc3_swb" in codec_source or "lc3-swb" in codec_source:
        codec_key = "lc3_swb"
        codec_name = "LC3-SWB"
    elif "lc3" in codec_source:
        codec_key = "lc3"
        codec_name = "LC3"
    elif "faststream" in codec_source:
        codec_key = "faststream"
        codec_name = "FastStream"
    else:
        if group == "off":
            codec_key = "off"
            codec_name = "Off"
        else:
            parts = lower_key.replace("_", "-").split("-")
            if len(parts) > 2:
                codec_key = parts[-1]
                codec_name = codec_key.upper()
            else:
                codec_key = "default"
                codec_name = "Default"

    return {
        "group": group,
        "groupName": group_name,
        "groupIcon": group_icon,
        "codecKey": codec_key,
        "codecName": codec_name,
    }

def process_cards_json(cards):
    bt_cards = {}
    for card in cards:
        if not card.get("name"):
            continue
        if is_bluetooth_card(card):
            props = card.get("properties", {})
            raw_addr = props.get("bluez5.address") or props.get("device.string") or card["name"]
            address = format_bt_address(raw_addr)
            active_profile_key = card.get("active_profile", "")

            available_profiles = card.get("profiles", {})
            group_map = {}

            for prof_key, prof_val in available_profiles.items():
                if prof_val and (prof_val.get("available") is False or prof_val.get("available") == "no"):
                    continue

                desc = prof_val.get("description", "") if prof_val else ""
                parsed = parse_profile_and_codec(prof_key, desc, prof_val)

                if parsed["group"] not in group_map:
                    group_map[parsed["group"]] = {
                        "id": parsed["group"],
                        "name": parsed["groupName"],
                        "icon": parsed["groupIcon"],
                        "codecs": [],
                    }

                if not any(c["key"] == prof_key for c in group_map[parsed["group"]]["codecs"]):
                    group_map[parsed["group"]]["codecs"].append({
                        "key": prof_key,
                        "codecKey": parsed["codecKey"],
                        "name": parsed["codecName"],
                        "description": desc or prof_key,
                    })

            profile_groups = list(group_map.values())

            active_group = ""
            active_group_name = ""
            active_codec_key = ""
            active_codec_name = ""

            if active_profile_key and active_profile_key in available_profiles:
                act_val = available_profiles[active_profile_key]
                act_desc = act_val.get("description", "") if act_val else ""
                active_parsed = parse_profile_and_codec(active_profile_key, act_desc, act_val)
                active_group = active_parsed["group"]
                active_group_name = active_parsed["groupName"]
                active_codec_key = active_parsed["codecKey"]
                active_codec_name = active_parsed["codecName"]

            if not active_group and profile_groups:
                active_group = profile_groups[0]["id"]
                active_group_name = profile_groups[0]["name"]

            current_group_obj = next((g for g in profile_groups if g["id"] == active_group), None)
            active_group_codecs = current_group_obj["codecs"] if current_group_obj else []

            if not active_codec_key and active_group_codecs:
                active_codec_key = active_group_codecs[0]["codecKey"]
                active_codec_name = active_group_codecs[0]["name"]

            card_info = {
                "cardName": card["name"],
                "address": address,
                "description": props.get("device.description") or card.get("description") or card["name"],
                "activeProfileKey": active_profile_key,
                "activeGroup": active_group,
                "activeGroupName": active_group_name,
                "activeCodecKey": active_codec_key,
                "activeCodecName": active_codec_name,
                "activeGroupCodecs": active_group_codecs,
                "profileGroups": profile_groups,
            }

            bt_cards[card["name"]] = card_info
            if address:
                bt_cards[address] = card_info

    return bt_cards


class TestPipeWireBluetoothAudio(unittest.TestCase):

    def setUp(self):
        self.mock_card_data = {
            "name": "bluez_card.00_11_22_33_44_55",
            "driver": "module-bluez5-device.c",
            "properties": {
                "device.api": "bluez5",
                "bluez5.address": "00:11:22:33:44:55",
                "device.description": "Test Headphones",
            },
            "active_profile": "a2dp-sink-ldac",
            "profiles": {
                "off": {"description": "Off", "available": True},
                "a2dp-sink": {"description": "High Fidelity Playback (A2DP Sink)", "available": True},
                "a2dp-sink-sbc": {"description": "High Fidelity Playback (A2DP Sink, codec SBC)", "available": True},
                "a2dp-sink-aac": {"description": "High Fidelity Playback (A2DP Sink, codec AAC)", "available": True},
                "a2dp-sink-ldac": {"description": "High Fidelity Playback (A2DP Sink, codec LDAC)", "available": True},
                "headset-head-unit-cvsd": {"description": "Headset Head Unit (HSP/HFP, codec CVSD)", "available": True},
                "headset-head-unit-msbc": {"description": "Headset Head Unit (HSP/HFP, codec mSBC)", "available": True},
            },
        }

    def test_codec_availability_changes(self):
        """Test codec availability toggles dynamically in PipeWire card profiles."""
        cards = process_cards_json([self.mock_card_data])
        card_info = cards["bluez_card.00_11_22_33_44_55"]
        a2dp_group = next(g for g in card_info["profileGroups"] if g["id"] == "a2dp-sink")
        codec_keys = [c["codecKey"] for c in a2dp_group["codecs"]]
        self.assertIn("ldac", codec_keys)
        self.assertIn("aac", codec_keys)
        self.assertIn("sbc", codec_keys)

        # Mark LDAC as unavailable
        modified_card = json.loads(json.dumps(self.mock_card_data))
        modified_card["profiles"]["a2dp-sink-ldac"]["available"] = False
        cards2 = process_cards_json([modified_card])
        card_info2 = cards2["bluez_card.00_11_22_33_44_55"]
        a2dp_group2 = next(g for g in card_info2["profileGroups"] if g["id"] == "a2dp-sink")
        codec_keys2 = [c["codecKey"] for c in a2dp_group2["codecs"]]
        self.assertNotIn("ldac", codec_keys2)
        self.assertIn("aac", codec_keys2)
        self.assertIn("sbc", codec_keys2)

        # Restore LDAC availability
        modified_card["profiles"]["a2dp-sink-ldac"]["available"] = True
        cards3 = process_cards_json([modified_card])
        card_info3 = cards3["bluez_card.00_11_22_33_44_55"]
        a2dp_group3 = next(g for g in card_info3["profileGroups"] if g["id"] == "a2dp-sink")
        codec_keys3 = [c["codecKey"] for c in a2dp_group3["codecs"]]
        self.assertIn("ldac", codec_keys3)

    def test_disconnect_reconnect(self):
        """Test Bluetooth disconnect and reconnect state resets."""
        # Connected state
        cards = process_cards_json([self.mock_card_data])
        self.assertIn("bluez_card.00_11_22_33_44_55", cards)
        self.assertIn("00:11:22:33:44:55", cards)

        # Disconnected state
        cards_empty = process_cards_json([])
        self.assertEqual(len(cards_empty), 0)

        # Reconnected state
        cards_reconnected = process_cards_json([self.mock_card_data])
        self.assertIn("bluez_card.00_11_22_33_44_55", cards_reconnected)
        card_info = cards_reconnected["bluez_card.00_11_22_33_44_55"]
        self.assertEqual(card_info["activeGroup"], "a2dp-sink")
        self.assertEqual(card_info["activeCodecKey"], "ldac")

    def test_hfp_a2dp_transitions(self):
        """Test transitions between A2DP and HFP/HSP headset profiles."""
        # Start in A2DP mode
        cards = process_cards_json([self.mock_card_data])
        card_info = cards["bluez_card.00_11_22_33_44_55"]
        self.assertEqual(card_info["activeGroup"], "a2dp-sink")
        self.assertEqual(card_info["activeCodecKey"], "ldac")

        # Switch active profile to HFP msbc
        hfp_card = json.loads(json.dumps(self.mock_card_data))
        hfp_card["active_profile"] = "headset-head-unit-msbc"
        cards_hfp = process_cards_json([hfp_card])
        card_info_hfp = cards_hfp["bluez_card.00_11_22_33_44_55"]
        self.assertEqual(card_info_hfp["activeGroup"], "headset-head-unit")
        self.assertEqual(card_info_hfp["activeGroupName"], "HSP/HFP (Headset)")
        self.assertEqual(card_info_hfp["activeCodecKey"], "msbc")
        self.assertEqual(card_info_hfp["activeCodecName"], "mSBC")

        # Switch back to A2DP aac
        a2dp_card = json.loads(json.dumps(self.mock_card_data))
        a2dp_card["active_profile"] = "a2dp-sink-aac"
        cards_a2dp = process_cards_json([a2dp_card])
        card_info_a2dp = cards_a2dp["bluez_card.00_11_22_33_44_55"]
        self.assertEqual(card_info_a2dp["activeGroup"], "a2dp-sink")
        self.assertEqual(card_info_a2dp["activeCodecKey"], "aac")
        self.assertEqual(card_info_a2dp["activeCodecName"], "AAC")

    def test_unsupported_codecs_and_fallback(self):
        """Test profile parsing gracefully handles unknown/unsupported codec names and malformed profiles."""
        card_data = json.loads(json.dumps(self.mock_card_data))
        card_data["profiles"]["a2dp-sink-custom_vendor_codec"] = {
            "description": "High Fidelity Playback (Custom Vendor)",
            "available": True,
        }
        card_data["active_profile"] = "a2dp-sink-custom_vendor_codec"

        cards = process_cards_json([card_data])
        card_info = cards["bluez_card.00_11_22_33_44_55"]
        self.assertEqual(card_info["activeGroup"], "a2dp-sink")
        self.assertIn("a2dp-sink-custom_vendor_codec", [c["key"] for c in card_info["activeGroupCodecs"]])
        self.assertTrue(len(card_info["profileGroups"]) > 0)


if __name__ == "__main__":
    unittest.main()
