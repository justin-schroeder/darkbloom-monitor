#!/usr/bin/env python3
"""Profile isolated Release builds; never reads the real provider's credentials.

Usage: python3 scripts/profile-memory.py [--ref HEAD] [--idle-only] --output .build/memory-profile/result.json
Requires an unlocked macOS GUI session. Three fresh launches, five menu cycles and a settings visit each.
"""

import argparse
import datetime as dt
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import statistics
import subprocess
import tempfile
import threading


PROBE = r'''
import AppKit
import Darwin

@MainActor
enum MemoryProbe {
    static let hostedViews = NSHashTable<NSView>.weakObjects()
    static weak var settingsController: NSViewController?
    static weak var state: AppState?

    static func start(_ appState: AppState) {
        state = appState
        if ProcessInfo.processInfo.environment["MEMORY_PROFILE_IDLE_ONLY"] == "1" {
            for second in 6...10 { schedule(second) { sample("cold") } }
            schedule(11) { NSApp.terminate(nil) }
            return
        }
        for (start, stage) in [(6, "cold"), (16, "open"), (22, "closed"), (36, "cycled"), (45, "settings_closed")] {
            for second in start..<(start + 3) {
                schedule(second) { sample(stage) }
            }
        }
        for second in [12, 20, 26, 27, 28, 29, 30, 31, 32, 33] {
            schedule(second) { toggleMenu() }
        }
        // Visual QA and settings lifetime checks run after all memory samples.
        schedule(40) {
            if let state { profilePreferences(state: state) }
        }
        schedule(42) {
            guard let window = NSApp.windows.first(where: { $0.title == "Darkbloom Monitor Preferences" }),
                  window.isVisible else { preconditionFailure("Settings did not open") }
            settingsController = window.contentViewController
            window.close()
        }
        schedule(43) { print("SETTINGS_RELEASED \(settingsController == nil)"); fflush(stdout) }
        schedule(48) { toggleMenu() }
        schedule(49) { capture() }
        schedule(50) { toggleMenu() }
        schedule(51) { NSApp.terminate(nil) }
    }

    static func schedule(_ seconds: Int, action: @escaping @MainActor () -> Void) {
        Timer.scheduledTimer(withTimeInterval: Double(seconds), repeats: false) { _ in
            Task { @MainActor in action() }
        }
    }

    static func descendants(_ view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return [view] + view.subviews.flatMap { descendants($0) }
    }

    static func toggleMenu() {
        let buttons = NSApp.windows.flatMap { descendants($0.contentView) }
            .compactMap { $0 as? NSStatusBarButton }
        guard let button = buttons.first else {
            fatalError("Missing status button")
        }
        if button.action != nil {
            button.performClick(nil)
        } else {
            // macOS 27 moved SwiftUI presentation to expanded interface sessions.
            // Test-only SPI, injected into the temporary build, never the shipped app.
            // Reference: github.com/orchetect/MenuBarExtraAccess (NSStatusItem+ExpandedInterfaceSession).
            let itemSelector = NSSelectorFromString("statusItem")
            let beginSelector = NSSelectorFromString("_beginExpandedInterfaceSession:")
            let sessionSelector = NSSelectorFromString("expandedInterfaceSession")
            guard let window = button.window, window.responds(to: itemSelector),
                  let item = window.perform(itemSelector)?.takeUnretainedValue() as? NSStatusItem,
                  item.responds(to: beginSelector), item.responds(to: sessionSelector)
            else { preconditionFailure("Cannot toggle this menu; use --idle-only") }
            if let session = item.perform(sessionSelector)?.takeUnretainedValue() as? NSObject {
                session.perform(NSSelectorFromString("cancel"))
            } else {
                NSApp.activate(ignoringOtherApps: true)
                typealias Begin = @convention(c) (NSStatusItem, Selector, TimeInterval) -> Void
                let begin = unsafeBitCast(item.method(for: beginSelector), to: Begin.self)
                begin(item, beginSelector, .greatestFiniteMagnitude)
            }
        }
    }

    static func sample(_ stage: String) {
        var usage = rusage_info_v0()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V0, $0)
            }
        }
        precondition(result == 0)
        let visible = NSApp.windows.filter {
            $0.isVisible && !String(describing: type(of: $0)).contains("StatusBar")
        }.count
        for view in NSApp.windows.flatMap({ descendants($0.contentView) })
            where String(describing: type(of: view)).contains("HostingView") {
            hostedViews.add(view)
        }
        let row: [String: Any] = [
            "stage": stage, "footprint_bytes": usage.ri_phys_footprint,
            "rss_bytes": usage.ri_resident_size, "visible_windows": visible,
            "live_hosting_views": hostedViews.allObjects.count, "windows": NSApp.windows.count
        ]
        let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        print("MEMORY " + String(decoding: data, as: UTF8.self))
        fflush(stdout)
        if stage == "open" && visible == 0 { exit(2) }
    }

    static func capture() {
        guard let path = ProcessInfo.processInfo.environment["MEMORY_PROFILE_IMAGE"],
              let view = NSApp.windows.first(where: {
                  $0.isVisible && !String(describing: type(of: $0)).contains("StatusBar")
              })?.contentView,
              let image = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: image)
        try! image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }
}
'''


def fixtures(home):
    now = dt.datetime.now(dt.timezone.utc)
    hour = now.replace(minute=0, second=0, microsecond=0)
    epoch = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)
    hours = [dict(hour=((hour - dt.timedelta(hours=i)) - epoch).total_seconds(),
                  jobs=40, microUSD=12000,
                  earningsByCategory={"base_reward": dict(entries=1, microUSD=2000),
                                      "test-model": dict(entries=40, microUSD=10000)})
             for i in reversed(range(168))]
    history = dict(accountID="memory-profile", hours=hours, coverageStartedAt=hours[0]["hour"],
                   coverageGaps=[], recentEarningIDs=list(range(1000)),
                   categorizedEarningIDs=list(range(1000)), lastIngestedAt=(now - epoch).total_seconds())
    ledger = home / "Library/Application Support/Darkbloom Monitor/activity-history.json"
    ledger.parent.mkdir(parents=True)
    ledger.write_text(json.dumps(history))
    state = home / ".darkbloom"
    state.mkdir()
    (state / "auth_token").write_text("synthetic-profile-token")
    (state / "daemon-state.json").write_text(json.dumps(dict(
        pid=os.getpid(), version="profile", written_at=now.timestamp(), started_at=now.timestamp() - 3600,
        current_model="test-model", trust=dict(trust_level="verified", status="online",
                                               reason="profile", received_at=now.timestamp()),
        stats=dict(requests_served=1000, tokens_generated=100000))))
    earnings = [dict(id=i, provider_id="profile-provider", provider_key="profile-key",
                     model="test-model", amount_micro_usd=250, prompt_tokens=20, completion_tokens=10,
                     created_at=(now - dt.timedelta(seconds=i * 60)).isoformat()) for i in range(1000)]
    return {
        "/v1/provider/account-earnings": dict(account_id="memory-profile", earnings=earnings,
            total_micro_usd=2016000, count=1000, history_limit=1000,
            available_balance_micro_usd=2016000, withdrawable_balance_micro_usd=2016000),
        "/v1/providers/attestation": [],
        "/v1/models/catalog": dict(models=[dict(id="test-model", display_name="Test model", active=True)]),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", help="Git revision; defaults to the working tree")
    parser.add_argument("--idle-only", action="store_true", help="Measure startup with the menu closed")
    parser.add_argument("--runs", type=int, default=3, choices=range(1, 11))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    with tempfile.TemporaryDirectory(prefix="darkbloom-memory-") as temporary:
        root = Path(temporary)
        source = root / "source"
        source.mkdir()
        if args.ref:
            archive = subprocess.check_output(["git", "archive", args.ref], cwd=repo)
            subprocess.run(["tar", "-x", "-C", str(source)], input=archive, check=True)
        else:
            shutil.copy(repo / "Package.swift", source)
            for name in ["Sources", "Resources", "Tests"]:
                shutil.copytree(repo / name, source / name)
        app_state = source / "Sources/DarkbloomMenu/AppState.swift"
        app_state.write_text(app_state.read_text().replace(
            "    func start() {", "    func start() {\n        MemoryProbe.start(self)"))
        (source / "Sources/DarkbloomMenu/MemoryProbe.swift").write_text(PROBE)
        menu = source / "Sources/DarkbloomMenu/MenuView.swift"
        menu.write_text(menu.read_text() + '''
@MainActor
func profilePreferences(state: AppState) {
    PreferencesWindow.show(preferences: MenuPreferencesStore(), state: state)
}
''')
        responses = {}

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                data = json.dumps(responses[self.path.split("?")[0]]).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *unused):
                pass

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        api = source / "Sources/DarkbloomCore/CoordinatorAPI.swift"
        api.write_text(api.read_text().replace("https://api.darkbloom.dev",
                                              f"http://127.0.0.1:{server.server_port}"))
        # Even a locally installed privileged helper must never be used by a profile.
        helper = source / "Sources/DarkbloomMenu/FanHelper.swift"
        helper.write_text(helper.read_text().replace("/Library/PrivilegedHelperTools/", str(root / "absent") + "/"))
        with output.with_suffix(".build.log").open("w") as log:
            subprocess.run(["swift", "build", "-c", "release", "--package-path", str(source)],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        app = root / "Memory Profile.app"
        macos = app / "Contents/MacOS"
        macos.mkdir(parents=True)
        shutil.copy(source / ".build/release/DarkbloomMenu", macos)
        info = plistlib.loads((source / "Resources/Info.plist").read_bytes())
        info["CFBundleIdentifier"] = "dev.darkbloom.memory-profile"
        info["NSAppTransportSecurity"] = {"NSAllowsLocalNetworking": True}
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
        for run in range(1, args.runs + 1):
            home = root / f"home-{run}"
            responses.clear()
            responses.update(fixtures(home))
            result = subprocess.run([str(macos / "DarkbloomMenu")],
                env=dict(os.environ, CFFIXED_USER_HOME=str(home),
                         MEMORY_PROFILE_IMAGE=str(output.with_suffix(f".run-{run}.png")),
                         MEMORY_PROFILE_IDLE_ONLY=str(int(args.idle_only))),
                capture_output=True, text=True, timeout=85)
            output.with_suffix(f".run-{run}.log").write_text(result.stdout + result.stderr)
            result.check_returncode()
            samples = [dict(json.loads(line[7:]), run=run) for line in result.stdout.splitlines()
                       if line.startswith("MEMORY ")]
            expected = 5 if args.idle_only else 15
            if len(samples) != expected:
                raise RuntimeError(f"Expected {expected} samples, got {len(samples)}")
            for sample in samples:
                expected_visible = sample["stage"] == "open"
                if bool(sample["visible_windows"]) != expected_visible:
                    raise RuntimeError(f"Menu did not reach expected state: {sample}")
            rows.extend(samples)
            print(f"Run {run}/{args.runs} complete", flush=True)
        server.shutdown()
    summary = {}
    for stage in (["cold"] if args.idle_only else ["cold", "open", "closed", "cycled", "settings_closed"]):
        values = [r["footprint_bytes"] for r in rows if r["stage"] == stage]
        summary[stage] = dict(median_bytes=statistics.median(values), min_bytes=min(values), max_bytes=max(values))
    report = dict(revision=args.ref or "working tree", machine=os.uname().machine,
                  os=subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip(),
                  swift=subprocess.check_output(["swift", "--version"], stderr=subprocess.STDOUT, text=True).strip(),
                  samples=rows, summary=summary)
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
