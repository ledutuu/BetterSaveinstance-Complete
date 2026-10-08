# Source-extracted regression checks

Run with the official Luau CLI:

```powershell
./Tools/Regression/Run.ps1 -LuauCLI C:/path/to/luau.exe
```

Generated harnesses are saved in ignored `build/regressions`. They execute the actual source blocks with mock Roblox/executor APIs.

- Core: option precedence, disabled/native/custom/jobless decompilation, HTTP failure fallback, Crashlog, LinkedSource id/hash/version parsing and retrieval.
- Extra: lazy Reflection filters, malformed API cache fallback, optional Content metadata, spinner/AntiIdle cleanup, rendering restoration, global/file lock ownership and initialization errors.
- Performance: property inheritance order, cache isolation and stop filters, cooperative scheduling.
- Startup: persistent first-append BEGIN/OK trace, diagnostic option metadata and explicit filename avoidance of Marketplace lookup.

These checks establish Luau control flow. Native executor crashes, Roblox import, Terrain/Union fidelity in Studio, and full game behavior require separate runtime checks.
