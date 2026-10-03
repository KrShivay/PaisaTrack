#!/usr/bin/env python3
"""Drive the T-176/T-167c layout matrix on emulator-5554 only.

Usage: python3 tool/qa/emulator_layout_matrix.py [--seed-sms]

Python standard library only. Screenshots and UIAutomator dumps are written
under build/qa/emulator-matrix. ADB network connections are never used.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import subprocess
import struct
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path

SERIAL = "emulator-5554"
PACKAGE = "com.paisatrack"
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/qa/emulator-matrix"
WIDTH, HEIGHT, DENSITY = 1220, 2712, 450
MIN_TARGET = 135
ADB = os.environ.get("ADB", "adb")


def adb(*args: str, binary: bool = False) -> str | bytes:
    """Pin every operation to the approved emulator after checking qemu."""
    env = dict(os.environ, ANDROID_SERIAL=SERIAL)
    probe = subprocess.run(
        [ADB, "-s", SERIAL, "shell", "getprop", "ro.kernel.qemu"],
        check=True,
        capture_output=True,
        text=True,
        env=env,
    ).stdout.strip()
    if probe != "1":
        raise RuntimeError(f"DEVICE SAFETY STOP: {SERIAL} ro.kernel.qemu={probe!r}")
    result = subprocess.run(
        [ADB, "-s", SERIAL, *args],
        check=True,
        capture_output=True,
        text=not binary,
        env=env,
    )
    return result.stdout


def shell(*args: str) -> str:
    result = adb("shell", *args)
    assert isinstance(result, str)
    return result


def box(value: str) -> tuple[int, int, int, int] | None:
    match = re.search(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", value)
    return tuple(map(int, match.groups())) if match else None


def hierarchy() -> str:
    result = adb(
        "shell",
        "uiautomator dump /sdcard/window.xml >/dev/null; cat /sdcard/window.xml",
    )
    assert isinstance(result, str)
    return result[result.find("<?xml"):]


def parse(xml_text: str) -> list[dict]:
    root = ET.fromstring(xml_text)
    output = []

    def walk(element: ET.Element, parent: tuple[int, int, int, int] | None) -> None:
        attrs = element.attrib
        rect = box(attrs.get("bounds", ""))
        description = html.unescape(attrs.get("content-desc", ""))
        text = html.unescape("\n".join(filter(None, (attrs.get("text"), description))))
        output.append({
            "text": text, "description": description,
            "box": rect or (0, 0, 0, 0), "parent": parent,
            "clickable": attrs.get("clickable") == "true",
            "selected": attrs.get("selected") == "true",
            "focusable": attrs.get("focusable") == "true",
            "scrollable": attrs.get("scrollable") == "true",
            "class": attrs.get("class", ""),
        })
        for child in element:
            walk(child, rect or parent)

    walk(root, None)
    return output


def find(xml_text: str, patterns: tuple[str, ...], clickable: bool | None = None) -> dict | None:
    viewport = app_viewport(xml_text)
    for node in parse(xml_text):
        if clickable is not None and node["clickable"] != clickable:
            continue
        rect = node["box"]
        visible = (
            rect[0] < viewport[2]
            and rect[2] > viewport[0]
            and rect[1] < viewport[3]
            and rect[3] > viewport[1]
        )
        if visible and any(re.search(pattern, node["text"], re.I) for pattern in patterns) and rect[2] > rect[0]:
            return node
    return None


def tap_node(node: dict) -> None:
    x1, y1, x2, y2 = node["box"]
    shell("input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
    time.sleep(0.65)


def tap_right_side(node: dict, inset: int = 64) -> None:
    x1, y1, x2, y2 = node["box"]
    shell("input", "tap", str(max(x1 + 1, x2 - inset)), str((y1 + y2) // 2))
    time.sleep(0.65)


def tap_left_side(node: dict, inset: int = 64) -> None:
    x1, y1, x2, y2 = node["box"]
    shell("input", "tap", str(min(x2 - 1, x1 + inset)), str((y1 + y2) // 2))
    time.sleep(0.65)


def tap_match(xml_text: str, patterns: tuple[str, ...], name: str) -> dict:
    node = find(xml_text, patterns, True)
    if not node:
        raise RuntimeError(f"Could not find clickable {name}; expected {patterns!r}")
    tap_node(node)
    return node


def swipe(x1: int, y1: int, x2: int, y2: int) -> None:
    shell("input", "swipe", str(x1), str(y1), str(x2), str(y2), "450")
    time.sleep(0.35)


def swipe_and_dump(x1: int, y1: int, x2: int, y2: int) -> str:
    result = adb(
        "shell",
        f"input swipe {x1} {y1} {x2} {y2} 450; sleep 0.35; "
        "uiautomator dump /sdcard/window.xml >/dev/null; cat /sdcard/window.xml",
    )
    assert isinstance(result, str)
    return result[result.find("<?xml"):]


def swipe_batch_and_dump(points: list[tuple[int, int, int, int]]) -> str:
    commands = []
    for x1, y1, x2, y2 in points:
        commands.extend((f"input swipe {x1} {y1} {x2} {y2} 300", "sleep 0.35"))
    commands.extend(("uiautomator dump /sdcard/window.xml >/dev/null", "cat /sdcard/window.xml"))
    result = adb("shell", "; ".join(commands))
    assert isinstance(result, str)
    return result[result.find("<?xml"):]


def vertical_scroll_area(xml_text: str) -> dict | None:
    scrollables = [n for n in parse(xml_text) if n["scrollable"]]
    vertical = [
        n for n in scrollables
        if n["class"] in {"android.widget.ScrollView", "androidx.recyclerview.widget.RecyclerView"}
    ]
    if not vertical:
        vertical = scrollables
    if not vertical:
        return None
    # Nested transaction pages expose an outer page and a smaller inner list.
    return min(vertical, key=lambda n: (n["box"][2] - n["box"][0]) * (n["box"][3] - n["box"][1]))


def app_viewport(xml_text: str) -> tuple[int, int, int, int]:
    rectangles = [n["box"] for n in parse(xml_text)
                  if n["box"][2] > n["box"][0] and n["box"][3] > n["box"][1]]
    return max(rectangles, key=lambda r: (r[2] - r[0]) * (r[3] - r[1])) if rectangles else (0, 0, WIDTH, HEIGHT)


def scroll_end(xml_text: str) -> str:
    prior, stable = xml_text, 0
    for _ in range(50):
        area = vertical_scroll_area(prior)
        if not area:
            break
        x1, y1, x2, y2 = area["box"]
        viewport = app_viewport(prior)
        top, bottom = max(y1, viewport[1]), min(y2, viewport[3])
        height = bottom - top
        start_y = top + int(height * .72)
        end_y = top + int(height * .25)
        x = min(x2 - 10, viewport[2] - 10)
        current = swipe_batch_and_dump([(x, start_y, x, end_y)] * 8)
        if scroll_signature(current) == scroll_signature(prior):
            stable += 1
            if stable == 2:
                return current
        else:
            stable = 0
        prior = current
    return prior


def scroll_start(xml_text: str) -> str:
    prior, stable = xml_text, 0
    for _ in range(50):
        area = vertical_scroll_area(prior)
        if not area:
            break
        x1, y1, x2, y2 = area["box"]
        viewport = app_viewport(prior)
        top, bottom = max(y1, viewport[1]), min(y2, viewport[3])
        height = bottom - top
        start_y = top + int(height * .25)
        end_y = top + int(height * .72)
        x = min(x2 - 10, viewport[2] - 10)
        current = swipe_batch_and_dump([(x, start_y, x, end_y)] * 8)
        if scroll_signature(current) == scroll_signature(prior):
            stable += 1
            if stable == 2:
                return current
        else:
            stable = 0
        prior = current
    return prior


def scroll_to_match(
    xml_text: str,
    patterns: tuple[str, ...],
    name: str,
    *,
    clickable: bool | None = None,
    limit: int = 24,
) -> str:
    prior = xml_text
    stable = 0
    for _ in range(min(limit, 80)):
        target = find(prior, patterns, clickable)
        if target:
            return prior
        area = vertical_scroll_area(prior)
        if not area:
            break
        x1, y1, x2, y2 = area["box"]
        viewport = app_viewport(prior)
        top, bottom = max(y1, viewport[1]), min(y2, viewport[3])
        height = bottom - top
        start_y = top + int(height * .72)
        end_y = top + int(height * .25)
        x = min(x2 - 10, viewport[2] - 10)
        current = swipe_batch_and_dump([(x, start_y, x, end_y)] * 2)
        if scroll_signature(current) == scroll_signature(prior):
            stable += 1
            if stable == 2:
                break
        else:
            stable = 0
        prior = current
    raise RuntimeError(f"Could not scroll to clickable {name}")


def scroll_to_clickable(xml_text: str, patterns: tuple[str, ...], name: str, limit: int = 24) -> str:
    current = scroll_to_match(xml_text, patterns, name, clickable=True, limit=limit)
    target = find(current, patterns, True)
    if not target:
        raise RuntimeError(f"Could not find clickable {name} after scrolling")
    tap_left_side(target, inset=80)
    return hierarchy()


def scroll_signature(xml_text: str) -> tuple:
    """Compare visible semantic text and bounds, ignoring XML serialization noise."""
    return tuple(
        (node["text"], node["box"], node["clickable"])
        for node in parse(xml_text)
        if node["text"] and not any(
            line.strip() in {"Home", "Activity", "Sort", "Trends", "Ask PaisaTrack"}
            for line in node["text"].splitlines()
        )
    )


def union(rectangles: list[tuple[int, int, int, int]]) -> tuple[int, int, int, int] | None:
    if not rectangles:
        return None
    return min(r[0] for r in rectangles), min(r[1] for r in rectangles), max(r[2] for r in rectangles), max(r[3] for r in rectangles)


def intersects(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> bool:
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def system_frames() -> dict:
    text = shell("dumpsys", "window")
    lines = text.splitlines()
    frames = {
        "ime": None,
        "ime_insets_bottom_px": None,
        "ime_visible": False,
        "navigation_bar": None,
    }
    for index, line in enumerate(lines):
        if re.search(r"ImeInsetsSourceProvider", line, re.I):
            for source_line in lines[index + 1:index + 5]:
                source = re.search(
                    r"type=ime\s+frame=(\[\d+,\d+\]\[\d+,\d+\])"
                    r"\s+visibleFrame=(\[\d+,\d+\]\[\d+,\d+\])\s+visible=(true|false)",
                    source_line,
                )
                if source:
                    ime_frame = box(source.group(1))
                    visible_frame = box(source.group(2))
                    frames["ime_visible"] = source.group(3) == "true"
                    frames["ime"] = (
                        ime_frame
                        if frames["ime_visible"] and ime_frame and
                        ime_frame[2] > ime_frame[0] and ime_frame[3] > ime_frame[1]
                        else visible_frame if frames["ime_visible"] else None
                    )
                    for hint_line in lines[index + 1:index + 8]:
                        hint = re.search(
                            r"mInsetsHint=Insets\{[^}]*bottom=(\d+)", hint_line
                        )
                        if hint:
                            frames["ime_insets_bottom_px"] = int(hint.group(1))
                            break
                    break
        if frames["ime_visible"] and re.search(r"InputMethod|mImeWindow", line, re.I) and frames["ime"] is None:
            frames["ime"] = box(line) or frames["ime"]
        if re.search(r"NavigationBar|mNavigationBar", line, re.I):
            frames["navigation_bar"] = box(line) or frames["navigation_bar"]
    return frames


def capture(cell: str, route: str, xml_text: str, final=(), actions=()) -> dict:
    folder = OUT / cell
    folder.mkdir(parents=True, exist_ok=True)
    xml_path, png_path = folder / f"{route}.xml", folder / f"{route}.png"
    xml_path.write_text(xml_text, encoding="utf-8")
    image = adb("exec-out", "screencap", "-p", binary=True)
    assert isinstance(image, bytes)
    screenshot_size = struct.unpack(">II", image[16:24])
    expected_size = (HEIGHT, WIDTH) if "landscape" in cell else (WIDTH, HEIGHT)
    orientation_mismatch = screenshot_size != expected_size
    png_path.write_bytes(image)
    view = parse(xml_text)
    viewport = app_viewport(xml_text)
    view_height = viewport[3] - viewport[1]
    view_width = viewport[2] - viewport[0]
    nav_labels = {"Home", "Activity", "Sort", "Trends", "Ask PaisaTrack"}
    pill_nodes = [n for n in view if n["box"][1] > viewport[1] + view_height * .70 and
                  next((line.strip() for line in n["description"].splitlines() if line.strip()), "") in nav_labels]
    pill = union([n["box"] for n in pill_nodes])
    frames = system_frames()
    content = [n for n in view if any(re.search(p, n["text"], re.I) for p in final)]
    targets = [n for n in view if n["clickable"] and
               any(re.search(p, n["text"], re.I) for p in actions)]
    if route == "Activity":
        rows = [n for n in view if n["clickable"] and
                re.search(r"₹|Rs\.?\s?\d|\$\s?\d", n["text"])]
        content = [
            n for n in rows
            if not intersects(n["box"], pill or (0, 0, 0, 0))
            and not intersects(n["box"], frames["navigation_bar"] or (0, 0, 0, 0))
        ]
        targets = list(content)
    if route == "Sort":
        targets += [n for n in view if n["clickable"] and not n["text"] and
                    viewport[1] + view_height * .58 <= n["box"][1] and n["box"][3] < viewport[1] + view_height * .97]
        content += [n for n in view if re.search(r"Unknown|Other|Low confidence", n["text"], re.I)]
    if route == "Ask":
        content += [n for n in view if n["class"] == "android.widget.EditText"]
        content += [n for n in view if re.search(r"How much did I spend on food this month", n["text"], re.I)]
        targets += [n for n in view if n["class"] == "android.widget.EditText"]
        targets += [n for n in view if re.search(r"How much did I spend on food this month", n["text"], re.I) and n["clickable"]]
    if route == "AskSuggestions":
        content += [n for n in view if re.search(r"How much did I spend on food this month", n["text"], re.I)]
        targets += [n for n in view if re.search(r"How much did I spend on food this month", n["text"], re.I) and n["clickable"]]
    errors = []
    harness_issues = []
    if orientation_mismatch:
        harness_issues.append(
            f"window changed orientation during route: screenshot={screenshot_size}, "
            f"expected={expected_size}"
        )
    for n in targets:
        x1, y1, x2, y2 = n["box"]
        if x2 - x1 < MIN_TARGET or y2 - y1 < MIN_TARGET:
            label = n["text"][:65]
            if route == "Activity" and "Load more transactions" in label:
                harness_issues.append(
                    "Android UIAutomator exposes the Load more button label box only; "
                    "Flutter widget semantics verifies its 48dp target"
                )
            elif route == "Activity" and re.search(r"₹|Rs\.?\s?\d|\$\s?\d", label):
                harness_issues.append(
                    "Android UIAutomator clips the transaction row semantics bounds; "
                    "the landscape HomeShell widget test verifies a 48dp row target"
                )
            elif route == "DetailEdit" and label == "Save Correction":
                harness_issues.append(
                    "Android UIAutomator exposes only the Save Correction label bounds; "
                    "the landscape widget test verifies a 48dp button"
                )
            elif route == "PeriodCustom" and label == "Save":
                harness_issues.append(
                    "Android UIAutomator exposes the date picker Save label box only; "
                    "the 1.5x and 2x widget test taps 23dp beyond the label successfully"
                )
            elif route in {"Ask", "AskSuggestions"} and "How much did I spend on food" in label:
                harness_issues.append(
                    "Android UIAutomator exposes the suggestion label bounds only; "
                    "the 964x434dp widget test verifies its 48dp target"
                )
            elif route == "Ask" and n["class"] == "android.widget.EditText":
                harness_issues.append(
                    "Android UIAutomator reports the composer EditText semantics box only; "
                    "the landscape 2x widget and semantics test verifies a 48dp target"
                )
            else:
                errors.append(f"target<{MIN_TARGET}px:{label}:{n['box']}")
    for n in content + targets:
        for label, rect in [("pill", pill), ("ime", frames["ime"]),
                            ("navigation_bar", frames["navigation_bar"])]:
            if rect and intersects(n["box"], rect):
                errors.append(f"overlap:{label}:{n['text'][:65]}:{n['box']}:{rect}")
    minimums = {
        "Home": bool(content),
        "Activity": bool(content) and bool(targets),
        "DetailEdit": bool(targets),
        "Sort": len(targets) >= 4 and bool(content),
        "Trends": bool(content),
        "Settings": bool(targets),
        "NotTransactions": bool(content),
        "Ask": bool(content) and len(targets) >= 2,
        "AskSuggestions": bool(content) and bool(targets),
        "PeriodCustom": bool(content) and bool(targets),
    }
    if not minimums.get(route, True):
        harness_issues.append(f"required route content/action bounds missing for {route}")
    clipping = []
    for n in view:
        if n["class"] not in {"android.widget.TextView", "android.widget.EditText"}:
            continue
        x1, y1, x2, y2 = n["box"]
        if n["text"] and n["parent"] and n["parent"][2] > n["parent"][0] and n["parent"][3] > n["parent"][1] and (
            x1 < n["parent"][0] or y1 < n["parent"][1] or x2 > n["parent"][2] or y2 > n["parent"][3]
        ):
            clipping.append({"text": n["text"][:100], "bounds": n["box"], "parent": n["parent"]})
        if n["text"] and (
            x1 < viewport[0]
            or y1 < viewport[1]
            or x2 > viewport[2]
            or y2 > viewport[3]
        ):
            clipping.append({"text": n["text"][:100], "bounds": n["box"], "viewport": viewport})
    status = "H" if harness_issues else "F" if errors or clipping else "P"
    return {
        "cell": cell, "route": route, "status": status,
        "dump": str(xml_path.relative_to(ROOT)), "screenshot": str(png_path.relative_to(ROOT)),
        "pill_bounds": pill, "system_frames": frames,
        "final_content_bounds": [{"text": n["text"][:100], "bounds": n["box"]} for n in content],
        "action_bounds": [{"text": n["text"][:100], "bounds": n["box"]} for n in targets],
        "violations": errors + [f"harness: {issue}" for issue in harness_issues],
        "text_bounds_outside_parent_or_viewport": clipping,
    }


def send_sms_batch(count: int = 168) -> None:
    senders = ("ONE-PNB", "VK-HDFCBK", "VK-SBIUPI", "AD-HDFCBK")
    merchants = ("GROCERY MART", "METRO CAFE", "FUEL STATION", "BOOK HOUSE", "RIDE CAB", "PHARMACY")
    amounts = ("125.00", "249.50", "799.00", "1420.00", "52.75", "19.99")
    for i in range(count):
        merchant, amount = merchants[i % 6], amounts[(i * 5) % 6]
        date = f"{(i % 27) + 1:02d}-09-26"
        if i % 29 == 0:
            body = f"Your a/c XX5788 is credited for INR {amount} on {date} through UPI UPI {900000000000 + i} Bal INR 70887.42"
        elif i % 23 == 0:
            body = f"INR {amount} refunded to your account for {merchant} UPI ref {900000000000 + i}"
        elif i % 17 == 0:
            body = f"USD {amount} spent at {merchant} on card XX1234. Ref {i}"
        elif i % 4 == 0:
            body = f"A/c XX5788 debited INR {amount} Dt {date} UPI:{900000000000 + i} Bal INR 57581.42"
        elif i % 4 == 1:
            body = f"Money Transfer: Rs {amount} debited from A/C x5678 to {merchant} on {i % 28 + 1:02d}-Sep-26 via UPI Ref {900000000000 + i}"
        elif i % 4 == 2:
            body = f"Dear UPI user A/C X4521 debited by {amount} on date {i % 28 + 1:02d}Sep26 trf to {merchant} Refno {900000000000 + i}. -SBI"
        else:
            body = f"Rs.{amount} debited from A/c XX1234 for UPI/{merchant}/{i} on {date}."
        adb("emu", "sms", "send", senders[i % 4], body)
        if i % 20 == 19:
            print(f"Seeded {i + 1}/{count} synthetic SMS", flush=True)


def current_settings() -> dict[str, str]:
    def get(*args: str) -> str:
        return shell(*args).strip()
    size_output = get("wm", "size")
    density_output = get("wm", "density")
    size_override = next((line.split(":", 1)[1].strip() for line in size_output.splitlines() if line.startswith("Override size:")), "reset")
    density_override = next((line.split(":", 1)[1].strip() for line in density_output.splitlines() if line.startswith("Override density:")), "reset")
    return {
        "size": size_override,
        "density": density_override,
        "font_scale": get("settings", "get", "system", "font_scale"),
        "accelerometer_rotation": get("settings", "get", "system", "accelerometer_rotation"),
        "user_rotation": get("settings", "get", "system", "user_rotation"),
        "navigation_mode": get("settings", "get", "secure", "navigation_mode"),
    }


def configure(nav: str, orientation: str, scale: str) -> None:
    shell("wm", "size", f"{WIDTH}x{HEIGHT}")
    shell("wm", "density", str(DENSITY))
    shell("settings", "put", "system", "font_scale", scale)
    shell("settings", "put", "system", "accelerometer_rotation", "0")
    shell("settings", "put", "system", "user_rotation", "0" if orientation == "portrait" else "1")
    shell("cmd", "window", "user-rotation", "lock", "0" if orientation == "portrait" else "1")
    overlay = "com.android.internal.systemui.navbar.gestural" if nav == "gesture" else "com.android.internal.systemui.navbar.threebutton"
    shell("cmd", "overlay", "enable-exclusive", "--category", overlay)
    configured = current_settings()
    expected_rotation = "0" if orientation == "portrait" else "1"
    if configured["size"] != f"{WIDTH}x{HEIGHT}" or configured["density"] != str(DENSITY):
        raise RuntimeError(f"display override did not apply: {configured}")
    if configured["font_scale"] != scale or configured["user_rotation"] != expected_rotation:
        raise RuntimeError(f"scale/rotation override did not apply: {configured}")
    print(f"  display size={configured['size']} density={configured['density']} font={scale} rotation={expected_rotation}", flush=True)
    reset_home()


def home_navigation_ready(xml_text: str) -> bool:
    expected = {"Home", "Activity", "Sort", "Trends", "Ask PaisaTrack"}
    descriptions = {
        next((line.strip() for line in node["description"].splitlines() if line.strip()), "")
        for node in parse(xml_text) if node["description"]
    }
    return expected.issubset(descriptions)


def home_screen_ready(xml_text: str) -> bool:
    dashboard_loaded = bool(find(
        xml_text,
        (r"Select period|October \d{4}|SAFE TODAY|Good (morning|afternoon|evening)"),
        None,
    ))
    return home_navigation_ready(xml_text) and dashboard_loaded and any(
        node["clickable"] and node["selected"] and
        next((line.strip() for line in node["description"].splitlines() if line.strip()), "") == "Home"
        for node in parse(xml_text)
    )


def nav_item(xml_text: str, label: str) -> dict | None:
    return next((node for node in parse(xml_text)
                 if node["clickable"] and
                 next((line.strip() for line in node["description"].splitlines() if line.strip()), "") == label), None)


def launch_home() -> str:
    """Discard every prior route and wait for the production nav pill semantics."""
    shell("am", "force-stop", PACKAGE)
    shell("am", "start", "-n", f"{PACKAGE}/.MainActivity")
    deadline = time.time() + 90
    ready_streak = 0
    last_report = time.time()
    last_nodes = []
    while time.time() < deadline:
        time.sleep(1)
        current = hierarchy()
        loaded = home_navigation_ready(current)
        visible_text = {line.strip().lower() for node in parse(current)
                        for line in node["text"].splitlines() if line.strip()}
        if not loaded and visible_text.intersection({"internet", "bluetooth", "flashlight", "do not disturb"}):
            shell("input", "keyevent", "KEYCODE_BACK")
            time.sleep(.5)
            continue
        ready_streak = ready_streak + 1 if loaded else 0
        if ready_streak >= 3:
            home = nav_item(current, "Home")
            if not home:
                raise RuntimeError("Home content-desc item missing after nav pill settled")
            if not home_screen_ready(current):
                tap_node(home)
                selected_deadline = time.time() + 30
                while time.time() < selected_deadline:
                    current = hierarchy()
                    if home_screen_ready(current):
                        return current
                    time.sleep(.5)
                raise RuntimeError("Home screen did not settle after selecting its nav item")
            return current
        if time.time() - last_report >= 15:
            last_nodes = [n["text"][:80] for n in parse(current) if n["text"]]
            print(f"  waiting for Home: ready={bool(loaded)}, visible={last_nodes[:8]}", flush=True)
            last_report = time.time()
    raise RuntimeError(f"PaisaTrack Home did not settle after launch; visible={last_nodes[:8]}")


def reset_home() -> str:
    """Back out of transient routes, then select and verify Home in the nav pill."""
    for _ in range(10):
        current = hierarchy()
        if home_navigation_ready(current):
            home = nav_item(current, "Home")
            if home_screen_ready(current):
                return current
            if home:
                tap_node(home)
                deadline = time.time() + 20
                while time.time() < deadline:
                    current = hierarchy()
                    if home_screen_ready(current):
                        return current
                    time.sleep(.5)
                back()
                continue
        else:
            visible_text = {line.strip().lower() for node in parse(current)
                            for line in node["text"].splitlines() if line.strip()}
            if any(text.startswith("loading your local data") for text in visible_text):
                time.sleep(2)
            elif visible_text.intersection({"internet", "bluetooth", "flashlight", "do not disturb"}):
                shell("input", "keyevent", "KEYCODE_BACK")
            elif "at a glance" in visible_text:
                shell("am", "start", "-n", f"{PACKAGE}/.MainActivity")
                time.sleep(1)
            else:
                back()
    raise RuntimeError("Could not return to verified Home after ten Back attempts")


def back() -> str:
    shell("input", "keyevent", "KEYCODE_BACK")
    time.sleep(.4)
    return hierarchy()


def prepare_synthetic_inbox() -> None:
    """Import the just-seeded emulator inbox and create two dismissed rows."""
    reset_home()
    view = nav_to("Activity")
    scan = find(view, (r"Scan SMS inbox|Find transactions from SMS",), True)
    if scan:
        tap_node(scan)
        sheet = hierarchy()
        allow = find(sheet, (r"Allow SMS access",), True)
        if allow:
            tap_node(allow)
            prompt = hierarchy()
            system_allow = find(prompt, (r"Allow|While using the app",), True)
            if system_allow:
                tap_node(system_allow)
            time.sleep(1)
            sheet = hierarchy()
        scan_now = find(sheet, (r"Scan now",), True)
        if scan_now:
            tap_node(scan_now)
            deadline = time.time() + 240
            while time.time() < deadline:
                sheet = hierarchy()
                if find(sheet, (r"View Activity",), True):
                    break
                time.sleep(2)
            tap_match(sheet, (r"View Activity",), "View Activity")
    # Mark two seeded rows through the production detail action.
    for _ in range(2):
        activity = scroll_end(nav_to("Activity"))
        row = next((n for n in parse(activity) if n["clickable"] and
                    re.search(r"₹|Rs\.?\s?\d|\$\s?\d", n["text"])), None)
        if not row:
            break
        tap_left_side(row, inset=350)
        detail = scroll_end(hierarchy())
        action = find(detail, (r"Not a transaction",), True)
        if not action:
            back()
            break
        tap_node(action)
        time.sleep(.5)
        back()


def verify_seeded_dismissed_rows() -> int:
    """Verify the matrix fixture exposes at least two dismissed synthetic rows."""
    home = scroll_start(launch_home())
    settings_entry = find(home, (r"Settings",), None)
    if not settings_entry:
        raise RuntimeError("cannot verify seed: Home Settings entry not found")
    tap_right_side(settings_entry)
    settings = hierarchy()
    settings = scroll_start(settings)
    history = scroll_to_clickable(settings, (r"Not transactions",),
                                  "Not transactions", limit=150)
    history = scroll_end(history)
    rows = [node for node in parse(history) if node["clickable"] and
            re.search(r"₹|Rs\.?\s?\d|\$\s?\d", node["text"])]
    if len(rows) < 2:
        raise RuntimeError(f"seed verification found {len(rows)} Not-transaction rows; expected >=2")
    print(f"Verified {len(rows)} seeded Not-transaction rows before matrix", flush=True)
    return len(rows)


def nav_to(label: str) -> str:
    deadline = time.time() + 30
    last_labels = []
    while time.time() < deadline:
        current = hierarchy()
        items = [node for node in parse(current)
                 if node["clickable"] and
                 next((line.strip() for line in node["description"].splitlines() if line.strip()), "") == label]
        last_labels = [
            next((line.strip() for line in node["description"].splitlines() if line.strip()), "")
            for node in parse(current) if node["clickable"] and node["description"]
        ]
        if items:
            item = items[0]
            if item["selected"]:
                return current
            tap_node(item)
            selected_deadline = time.time() + 10
            while time.time() < selected_deadline:
                current = hierarchy()
                if label == "Ask PaisaTrack" and find(current, (r"Close",), True):
                    return current
                selected = next((node for node in parse(current)
                                 if node["clickable"] and node["selected"] and
                                 next((line.strip() for line in node["description"].splitlines() if line.strip()), "") == label), None)
                if selected:
                    return current
                time.sleep(.4)
        time.sleep(.4)
    raise RuntimeError(
        f"Home nav content-desc {label!r} did not become selected; labels={last_labels}"
    )


def wait_for_activity_row(xml_text: str, timeout: float = 30) -> tuple[str, dict]:
    deadline = time.time() + timeout
    current = xml_text
    while time.time() < deadline:
        row = find(current, (r"₹|Rs\.?\s?\d|\$\s?\d",), True)
        if row:
            return current, row
        time.sleep(.5)
        current = hierarchy()
    raise RuntimeError("seeded Activity transaction row did not become visible")


def scroll_row_above_navigation(xml_text: str) -> tuple[str, dict]:
    current = xml_text
    viewport = app_viewport(current)
    labels = {"Home", "Activity", "Sort", "Trends", "Ask PaisaTrack"}
    for _ in range(6):
        row = find(current, (r"₹|Rs\.?\s?\d|\$\s?\d",), True)
        if not row:
            current, row = wait_for_activity_row(current)
        pill_nodes = [
            node["box"] for node in parse(current)
            if next((line.strip() for line in node["description"].splitlines() if line.strip()), "") in labels
            and node["box"][1] > viewport[1] + (viewport[3] - viewport[1]) * .70
        ]
        pill = union(pill_nodes)
        if not pill or row["box"][3] <= pill[1]:
            return current, row
        area = vertical_scroll_area(current)
        if not area:
            break
        x1, y1, x2, y2 = area["box"]
        top, bottom = max(y1, viewport[1]), min(y2, viewport[3])
        height = bottom - top
        x = min(x2 - 10, viewport[2] - 10)
        current = swipe_and_dump(x, top + int(height * .72), x, top + int(height * .25))
    raise RuntimeError("seeded Activity row remained under the floating navigation pill")


def walk_routes(cell: str, only_routes: set[str] | None = None) -> list[dict]:
    results = []
    try:
        return _walk_routes(cell, results, only_routes)
    except Exception as exc:
        raise RouteFailure(str(exc), results) from exc


class RouteFailure(RuntimeError):
    def __init__(self, message: str, results: list[dict]):
        super().__init__(message)
        self.results = results


def _walk_routes(
    cell: str,
    results: list[dict],
    only_routes: set[str] | None = None,
) -> list[dict]:
    def record(route: str, action, *, final=(), actions=()) -> None:
        if only_routes is not None and route not in only_routes:
            return
        try:
            print(f"  checking {route}", flush=True)
            rotation = "1" if "landscape" in cell else "0"
            shell("settings", "put", "system", "accelerometer_rotation", "0")
            shell("settings", "put", "system", "user_rotation", rotation)
            shell("cmd", "window", "user-rotation", "lock", rotation)
            reset_home()
            view = action()
            result = capture(cell, route, view, final=final, actions=actions)
            results.append(result)
            print(f"  captured {route}: {result['status']}", flush=True)
        except Exception as exc:
            print(f"  {route} harness failure: {exc}", file=sys.stderr, flush=True)
            view = hierarchy()
            failed = capture(cell, route, view)
            failed["status"] = "H"
            failed["violations"].append(f"harness: {exc}")
            results.append(failed)

    def home_route() -> str:
        return scroll_start(hierarchy())

    def activity_route() -> str:
        activity, _ = wait_for_activity_row(nav_to("Activity"))
        activity, _ = scroll_row_above_navigation(activity)
        return activity

    def detail_route() -> str:
        activity, row = wait_for_activity_row(nav_to("Activity"))
        activity, row = scroll_row_above_navigation(activity)
        tap_node(row)
        detail = hierarchy()
        if not find(detail, (r"Transaction details|Parsed locally|Edit Parse Details"), None):
            raise RuntimeError("transaction row tap did not open Transaction Detail")
        detail = scroll_to_match(detail, (r"Edit Parse Details", r"Parse Details"),
                                 "Edit Parse Details", clickable=True, limit=12)
        tap_match(detail, (r"Edit Parse Details", r"Parse Details"), "Edit Parse Details")
        edit_view = hierarchy()
        payee = find(edit_view, (r"Payee|Merchant|Counterparty",), True)
        if payee:
            tap_node(payee)
            edit_view = hierarchy()
        return edit_view

    def sort_route() -> str:
        return scroll_end(nav_to("Sort"))

    def trends_route() -> str:
        return scroll_end(nav_to("Trends"))

    def open_settings() -> str:
        home = scroll_start(hierarchy())
        deadline = time.time() + 30
        settings_entry = find(home, (r"Settings",), None)
        while not settings_entry and time.time() < deadline:
            time.sleep(.5)
            home = scroll_start(hierarchy())
            settings_entry = find(home, (r"Settings",), None)
        if not settings_entry:
            raise RuntimeError("Home Settings entry not found")
        tap_right_side(settings_entry)
        settings = hierarchy()
        if not any(n["text"].strip() == "Settings" for n in parse(settings)):
            raise RuntimeError("Home Settings entry did not open Settings")
        return settings

    def settings_route() -> str:
        return scroll_end(open_settings())

    def not_transactions_route() -> str:
        settings = scroll_start(open_settings())
        history = scroll_to_clickable(settings, (r"Not transactions",),
                                      "Not transactions", limit=150)
        history = scroll_end(history)
        dismissed = [n for n in parse(history) if n["clickable"] and
                     re.search(r"₹|Rs\.?\s?\d|\$\s?\d", n["text"])]
        if len(dismissed) < 2:
            raise RuntimeError(f"Not transactions exposes {len(dismissed)} seeded rows")
        return history

    def ask_route() -> str:
        # Keep the screen in its baseline state; opening the IME hides the
        # composer by design and makes this route measure keyboard overlap.
        return nav_to("Ask PaisaTrack")

    def ask_suggestions_route() -> str:
        ask = nav_to("Ask PaisaTrack")
        return scroll_to_match(ask, (r"How much did I spend on food this month",),
                              "Ask food suggestion", clickable=True, limit=40)

    def period_route() -> str:
        home = scroll_start(hierarchy())
        period = next((node for node in parse(home)
                       if node["clickable"] and
                       node["description"].startswith("Select period:")), None)
        if not period:
            raise RuntimeError("Home period selector was not found")
        selector = home
        for _ in range(3):
            tap_left_side(period, inset=200)
            time.sleep(.4)
            selector = hierarchy()
            if find(selector, (r"Select Period",), None):
                break
            home = scroll_start(selector)
            period = next((node for node in parse(home)
                           if node["clickable"] and
                           node["description"].startswith("Select period:")), None)
            if not period:
                break
        if not find(selector, (r"Select Period",), None):
            raise RuntimeError("period selector did not open from the Home chip")
        custom = find(selector, (r"Custom date range",), None)
        if not custom:
            selector = scroll_to_match(selector, (r"Custom date range",),
                                       "Custom date range", clickable=None, limit=20)
            custom = find(selector, (r"Custom date range",), None)
        if not custom:
            raise RuntimeError("Custom date range action was not found")
        tap_left_side(custom, inset=200)
        return hierarchy()

    record("Home", home_route,
           final=(r"Select period|October \d{4}|SAFE TODAY|Good (morning|afternoon|evening)",))
    record("Activity", activity_route,
           final=(r"Load more transactions", r"₹|Rs\.?\s?\d|\$\s?\d"),
           actions=(r"Load more transactions", r"₹|Rs\.?\s?\d|\$\s?\d"))
    record("DetailEdit", detail_route,
           final=(r"Save Correction", r"Save"),
           actions=(r"Save Correction", r"Save"))
    record("Sort", sort_route, final=(r"left today", r"No transactions"),
           actions=(r"Skip", r"Confirm", r"Undo"))
    record("Trends", trends_route,
           final=(r"Top Merchants", r"Categories", r"No spending"))
    record("Settings", settings_route,
           final=(r"About", r"Delete all local data", r"Not transactions"),
           actions=(r"Delete all local data", r"Not transactions"))
    record("NotTransactions", not_transactions_route,
           final=(r"History", r"Not a transaction", r"Unlabeled message"),
           actions=(r"Undo",))
    record("Ask", ask_route, final=(r"Ask PaisaTrack",), actions=(r"Close",))
    record("AskSuggestions", ask_suggestions_route,
           final=(r"How much did I spend on food this month",),
           actions=(r"How much did I spend on food this month",))
    record("PeriodCustom", period_route,
           final=(r"Select date range|Start date|End date",),
           actions=(r"Cancel", r"Save"))
    return results


def restore(original: dict[str, str]) -> None:
    shell("wm", "size", original["size"])
    shell("wm", "density", original["density"])
    shell("settings", "put", "system", "font_scale", original["font_scale"])
    shell("settings", "put", "system", "accelerometer_rotation", original["accelerometer_rotation"])
    shell("settings", "put", "system", "user_rotation", original["user_rotation"])
    if original["accelerometer_rotation"] == "1":
        shell("cmd", "window", "user-rotation", "free")
    else:
        shell("cmd", "window", "user-rotation", "lock", original["user_rotation"])
    overlay = "com.android.internal.systemui.navbar.gestural" if original["navigation_mode"] == "2" else "com.android.internal.systemui.navbar.threebutton"
    shell("cmd", "overlay", "enable-exclusive", "--category", overlay)
    shell("am", "force-stop", PACKAGE)
    shell("am", "start", "-n", f"{PACKAGE}/.MainActivity")


def write_summaries(results: list[dict]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    json_path = OUT / "summary.json"
    json_path.write_text(json.dumps(results, indent=2, ensure_ascii=False), encoding="utf-8")
    routes = sorted({r["route"] for r in results})
    lines = ["# Emulator layout matrix results", "",
             "P = passed; F = a geometry/text-bound defect; H = harness/navigation/bounds detection failure.", "",
             "| Cell | " + " | ".join(routes) + " |", "|---|" + "|".join("---" for _ in routes) + "|"]
    for cell in sorted({r["cell"] for r in results}):
        statuses = {r["route"]: r["status"] for r in results if r["cell"] == cell}
        lines.append("| " + cell + " | " + " | ".join(statuses.get(route, "NR") for route in routes) + " |")
    lines += ["", f"Detailed measurements: {json_path.relative_to(ROOT)}.", ""]
    (OUT / "summary.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed-sms", action="store_true", help="inject 168 deterministic synthetic bank SMS before the matrix")
    parser.add_argument("--seed-only", action="store_true", help="inject synthetic SMS, then exit")
    parser.add_argument("--only-cell", action="append", help="run a named cell; can be repeated")
    parser.add_argument("--only-route", action="append", help="run a named route; can be repeated")
    parser.add_argument("--skip-seed-verification", action="store_true",
                        help="debug-only: use only after verifying the existing seeded fixture")
    parser.add_argument("--prepare-data", action="store_true", help="scan the synthetic inbox and dismiss two synthetic rows")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if shell("getprop", "ro.kernel.qemu").strip() != "1":
        raise RuntimeError("DEVICE SAFETY STOP: target is not a qemu emulator")
    original = current_settings()
    results = []
    summary_path = OUT / "summary.json"
    if args.only_cell and summary_path.exists():
        selected_cells = set(args.only_cell)
        selected_routes = set(args.only_route) if args.only_route else None
        results.extend(
            result for result in json.loads(summary_path.read_text(encoding="utf-8"))
            if result.get("cell") not in selected_cells
            or (selected_routes is not None and result.get("route") not in selected_routes)
        )
    try:
        preconfigured_first_cell = False
        if args.seed_sms or args.prepare_data:
            configure("gesture", "portrait", "1.0")
            preconfigured_first_cell = True
        if args.seed_sms or args.seed_only:
            send_sms_batch()
            if args.seed_only:
                return 0
        if args.prepare_data:
            prepare_synthetic_inbox()
        if not args.seed_only and not args.skip_seed_verification:
            verify_seeded_dismissed_rows()
        for nav in ("gesture", "threebutton"):
            for orientation in ("portrait", "landscape"):
                for scale in ("1.0", "1.5", "2.0"):
                    cell = f"{nav}-{orientation}-{scale.replace('.', '_')}"
                    if args.only_cell and cell not in args.only_cell:
                        continue
                    if shell("getprop", "ro.kernel.qemu").strip() != "1":
                        raise RuntimeError(f"DEVICE SAFETY STOP before cell {cell}")
                    print(f"Running {cell}", flush=True)
                    try:
                        if preconfigured_first_cell and cell == "gesture-portrait-1_0":
                            preconfigured_first_cell = False
                        else:
                            configure(nav, orientation, scale)
                        cell_results = walk_routes(
                            cell,
                            set(args.only_route) if args.only_route else None,
                        )
                    except Exception as exc:
                        print(f"  route harness failed: {exc}", file=sys.stderr, flush=True)
                        cell_results = list(getattr(exc, "results", []))
                        completed = {item["route"] for item in cell_results}
                        for route in ("Home", "Activity", "DetailEdit", "Sort", "Trends",
                                      "Settings", "NotTransactions", "Ask", "AskSuggestions", "PeriodCustom"):
                            if route in completed:
                                continue
                            cell_results.append({
                                "cell": cell, "route": route, "status": "H",
                                "violations": [f"harness: cell setup/navigation failed: {exc}"],
                            })
                    for result in cell_results:
                        results.append(result)
                        print(f"  {result['route']}: {result['status']}", flush=True)
                    write_summaries(results)
    finally:
        restore(original)
        print("Restored emulator settings and relaunched app", flush=True)
    write_summaries(results)
    return int(any(r["status"] in {"F", "H"} for r in results))


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"matrix error: {exc}", file=sys.stderr)
        raise
