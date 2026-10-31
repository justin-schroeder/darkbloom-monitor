# Memory footprint

Measured 2026-10-31 against `83fed2f` (v1.5.1), Apple M4, 32 GiB RAM,
macOS 27.0.1, Apple Swift 6.4, Release builds. UI, MenuBarExtra and Swift Charts
are preserved; changes only address resource lifetimes and bounded buffers.

Kernel-reported `ri_phys_footprint` from `proc_pid_rusage`, in MiB (1,048,576 bytes).
Each result is the median of nine samples: three fresh launches, three one-second
samples per phase. RSS is also recorded by the benchmark, but is not the metric below.

| Phase | Before | After |
| --- | ---: | ---: |
| Startup, menu closed | 20.032 | 19.892 |
| Menu open | 38.454 | 37.782 |
| Menu closed | 37.845 | 37.860 |
| After five menu cycles | 37.860 | 36.923 |
| After opening and closing Preferences | **46.813** | **44.314** |

Post-Preferences footprint: **49,087,496 → 46,466,080 bytes**, a **5.34%** reduction.
Per-launch medians: 46.939 / 46.829 / 46.673 MiB before; 45.048 / 43.970 / 44.314 MiB after.
Startup is effectively unchanged. Allocator and framework caches remain; these are
fixture measurements, not an absolute minimum or a live-provider memory guarantee.

Lifetime checks:

- The closed Preferences hosting controller remained alive in 3/3 original runs;
  it was released in 3/3 patched runs. Retained hosting views after closing Preferences: **4 → 1**.
  The remaining view belongs to the existing MenuBarExtra.
- Ten hardware snapshots added **10 host-port send rights before, 0 after**.
  The regression test fails on the original code (13 versus 3 references) and passes after the fix.
- A direct CLI buffer check feeds 1 MiB, retains at most **16 KiB** of diagnostic payload,
  preserves the final error, and verifies **0 buffer bytes after completion**.
- `swift test`: **72 tests passed** (55 core, 17 menu support). Release bundle built;
  strict code-signature verification and Info.plist validation passed. Menu screenshots inspected.

## Reproduce

From the repository root, with an unlocked, idle macOS GUI session:

```sh
python3 scripts/profile-memory.py --ref 83fed2f --output .build/memory-profile/before.json
python3 scripts/profile-memory.py --output .build/memory-profile/after.json
swift test
./scripts/build-app.sh
```

The profiler builds a temporary source copy and uses isolated home directories,
1,000 synthetic earnings, a 168-hour ledger, an empty fleet and a local HTTP server.
It disables access to the installed fan helper. Real credentials and provider controls
are not used. JSON contains every sample; adjacent logs contain the weak-reference
check, and PNGs capture the menu after measurements. Live HTTPS and larger fleets can differ.

On macOS 27, the temporary test driver uses guarded presentation SPI to exercise the
original SwiftUI menu; see [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess/blob/main/Sources/MenuBarExtraAccess/NSStatusItem%2BExpandedInterfaceSession.swift).
That instrumentation is never included in the shipped app. `--idle-only` skips UI interaction.
