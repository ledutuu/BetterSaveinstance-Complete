# Worklog

## 2026-10-08 - Luau, asset URLs, and Volcano crash audit

- Baseline: origin/main `6820981`; saveinstance.lua and saveinstance.luau are identical (SHA256 440F7C7486697AC2C83094E2C9376DEFBB08E039FDF66E59392821DA3CCFD684).
- Report: Volcano updated for version-cec3ad5889b447cf; Roblox window closes after executing this script. Native crash is not yet reproduced and must not be reported fixed from static tests.
- Roblox LIVE WindowsPlayer endpoint returns 0.742.0.7421053 / version-cec3ad5889b447cf. WindowsStudio64 returns the same numeric version / version-9b554450a0fc4e65. The Studio Full API dump returns HTTP 200 with 940 classes. Matching the running client is preferred to blindly choosing a newer schema.
- Baseline main source and bundled Konstant compile using official Luau CLI 0.741. This does not verify executor native APIs or Studio import.
- Found: default SafeMode=true contradicts documentation and intentionally kicks; KillAllScripts=true invokes registry/GC enumeration, coroutine closing, and function hooks. A native crash remains a separate gate.
- Found: custom Konstant URL on Devraj2010isme/BetterSaveinstance returns 404; bundled file in this repository returns 200. Loading happens even when decompilation is disabled.
- Found: CompilationError is global and may persist between saves; Crashlog stays boolean when appendfile is absent and later gets called as a function; warn is overwritten globally; spinner is never stopped on success; Reflection filter initializes outside protected fallback; LinkedSource parsing guesses id/hash from trailing characters.
- Local Roblox logs have no matching recent Player crash (latest Player log is from August); no evidence sufficient to attribute the native crash to one API.
- Plan: scoped local fixes, compiler checks and regression harness, then deliver patched files plus a diagnostic preset. No live injection or upstream publication requested/performed.
- Runtime gate: retest in an authorized experience with the user's Volcano build and capture CRASHLOG last lines. Do not bypass permission denials or detection.

### Completed local repair and upstream comparison

- User clarified comparison source as https://github.com/luau/UniversalSynSaveInstance and explicitly requested additional agents. Three agents performed independent source review, upstream comparison, and regression testing.
- Upstream snapshot: `089986506e7ab9c50d7065d48b36e3bfbd5f78d7`; pinned source SHA256 `9C6F0E9851B054EE0F8876FBF23A07E61B81422678C951162A3210E7073C330A`, identical to the live source fetched earlier.
- Integrated cooperative task scheduling (one-second guard in long loops), per-save inherited-property caches separated by saveability, stop-filter isolation, namespaced script-cache reuse, and cache-only jobless behavior. Kept this fork's XML/chunk output, custom Konstant, attribute fixes, Terrain/Union behavior, and reference resolution.
- Fixed actual `noscripts` bug: alias resolves to Decompile, while serializer previously read nonexistent OPTIONS.noscripts. Canonical option precedence now makes conflicting aliases deterministic. Disabled scripts skip decompiler and compilation-error native reads unless explicit bytecode export requests them.
- Fixed custom decompiler URL/404 handling and local decompiler selection; CompilationError and warn are scoped locally; Crashlog disables itself if required functions are absent and stringifies warning arguments.
- Added outer yieldable xpcall wrapper with global serialization, owned-file cleanup, clear failure results, and fallback reset only after lock acquisition. Successful cleanup stops spinner/listeners and restores rendering. Late AntiIdle/SafeMode setup checks cleanup state.
- Reflection filter is lazy and protected for both fallback API generation and Content metadata. Empty/non-table cached dumps no longer prevent later sources. Failure emits a clear result/status.
- LinkedSource lookup now parses id/hash/version explicitly, keys cache by lookup query, uses the official Roblox raw-content endpoint, and does not fetch a new source in jobless mode. Explicit versions are preserved rather than silently upgraded.
- Review caught and repaired an intermediate shared-fallback race and lazy-filter scope issue. Extra regression harness reproduced delayed AntiIdle registration, now fixed. A later test counter error was repaired in the harness; not attributed to production code.
- Verification: original source-extracted disabled-decompile regression failed with exit 1 (`disabled scripts must not invoke native or remote decompilation`); patched core suite passes 43 assertions, lifecycle/API/lock suite passes 118, performance suite passes 46 (207 total). All 10 user-facing Lua/Luau source files compile with official Luau CLI 0.741. `git diff --check` passes; saveinstance.lua and saveinstance.luau are synchronized.
- Reproducible checks are included in Tools/Regression. Example: `./Tools/Regression/Run.ps1 -LuauCLI C:/path/to/luau.exe`. Tests extract actual source sections and mock Roblox/executor APIs; they do not prove whole-client runtime behavior or Studio import.
- Asset assessment: WindowsPlayer LIVE numeric/upload versions match the build reported by the user. API v2 is documented, but its metadata/location response differs from raw-content v1; changing a URL version alone does not upgrade an asset. Individual game's asset revisions were not supplied or tested. No proxy is used as a permission fallback.
- Not imported: upstream binary/compression pipeline, clipboard export, native-read persistent skip journal, and full collect/emit rewrite. They require separate format/dependency/runtime validation and may change this fork's preservation behavior.
- Delivery: patched source, diagnostic runner, license, documentation, tests and a full source ZIP in the outer workspace outputs directory. No upstream push, PR, live injection, or game restart performed.
- Remaining gate: native Volcano crash requires running the included diagnostic locally and reading BSI_DIAGNOSTIC.log plus the final CRASHLOG entry. Diagnostic deliberately omits decompiled/hidden/shared-string content; successful diagnosis export does not prove full Terrain/Union fidelity. Native crashes cannot be caught by pcall/xpcall.

### GitHub publication authorized

- User requested committing and pushing the completed source repair to GitHub.
- Publication target: origin/main of ledutuu/BetterSaveinstance-Complete. Fetched origin/main before publication; it matches baseline 6820981, with no intervening remote commits.
- Final pre-publication validation: 207 regression assertions pass; 10 Lua/Luau source files compile; source copies share SHA256 AEB76BD4461ACF368B6331C1AD076549785B5F735160F73B74E0669CA4A18F08; git diff --check passes.
- Scoped publication includes source copies, README, diagnostic runner, regression tools and this worklog. Generated harnesses, bundled CLI downloads, scratch files and output archives are excluded.
- Removed the performance builder's unused standalone -Run switch, which pointed to a non-distributed CLI path; use Tools/Regression/Run.ps1 with explicit -LuauCLI instead.
- Native Volcano crash and Studio fidelity remain unverified runtime gates. Publishing these source fixes is not runtime acceptance.
