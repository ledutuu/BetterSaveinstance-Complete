-- Pass a raw GitHub repository root as a chunk argument to pin a source commit.
-- Diagnostic export omits decompiled scripts and hidden/shared-string data.
local log = "BSI_DIAGNOSTIC.log"
assert(type(writefile) == "function", "writefile is required for diagnostic logs")
local repoRoot = ... or "https://raw.githubusercontent.com/ledutuu/BetterSaveinstance-Complete/refs/heads/main/"
assert(type(repoRoot) == "string" and string.sub(repoRoot, -1) == "/", "Repository root must end in /")
local entries = { "BetterSaveinstance diagnostic; 2026-10-08" }
local function stage(message)
    table.insert(entries, tostring(os.clock()) .. " " .. message)
    writefile(log, table.concat(entries, "\n") .. "\n")
    print("[BSI_DIAG] " .. message)
end
local function runDiagnostic()
stage("before downloading source: " .. repoRoot)
local source = game:HttpGet(repoRoot .. "saveinstance.luau", true)
stage("before compiling source")
local compiled, compileError = loadstring(source, "BetterSaveinstance diagnostic")
assert(compiled, compileError)
stage("before module initialization")
local saveinstance = compiled()
assert(type(saveinstance) == "function", "Expected saveinstance function")
stage("module initialized; before diagnostic save")
local callOK, saveOK, err = pcall(saveinstance, {
    SafeMode = false,
    KillAllScripts = false,
    BoostFPS = false,
    ShutdownWhenDone = false,
    AntiIdle = false,
    ShowStatus = false,
    Decompile = false,
    SaveCompilationErrors = false,
    SaveBytecode = false,
    SaveBytecodeIfDecompilerFails = false,
    IgnoreSpecialProperties = true,
    DisableGethiddenpropertyFallback = true,
    DisableReflectionService = true,
    APICache = false,
    IgnoreSharedStrings = true,
    IgnoreSpecialStrings = true,
    IgnoreSpecialClassProperties = true,
    NilInstances = false,
    AlternativeWritefile = true,
    FilePath = "BSI_VOLCANO_DIAGNOSTIC.rbxlx",
    Crashlog = false,
    __DEBUG_MODE = false,
    TraceProgress = true,
    YieldInterval = 0.02,
})
if not callOK then
    stage("Luau error: " .. tostring(saveOK))
elseif not saveOK then
    stage("Save failed: " .. tostring(err))
else
    stage("Save completed; check BSI_VOLCANO_DIAGNOSTIC.rbxlx")
end
end
local runOK, runError = xpcall(runDiagnostic, function(message) return debug.traceback(tostring(message)) end)
if not runOK then stage("Diagnostic Luau error: " .. tostring(runError)) end
-- pcall cannot recover a native executor/client crash. The final persisted
-- stage and the last CRASHLOG entry locate the next runtime check.
