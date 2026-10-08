-- Full client export: decompilation and hidden geometry enabled.
-- Optional chunk argument pins the raw repository root.
local root = ... or "https://raw.githubusercontent.com/ledutuu/BetterSaveinstance-Complete/refs/heads/main/"
assert(type(root) == "string" and string.sub(root, -1) == "/", "Repository root must end in /")
assert(type(writefile) == "function", "writefile is required")
local logPath = "BSI_FULL_BOOT.log"
local entries = {}
local function stage(message)
    table.insert(entries, tostring(os.clock()) .. " " .. message)
    writefile(logPath, table.concat(entries, "\n") .. "\n")
    print("[BSI_FULL] " .. message)
end
stage("before main source download: " .. root)
local ok, err = xpcall(function()
    local source = game:HttpGet(root .. "saveinstance.luau", true)
    stage("before main source compilation")
    local compiled, compileError = loadstring(source, "BetterSaveinstance full export")
    assert(compiled, compileError)
    stage("before module initialization")
    local saveinstance = compiled()
    assert(type(saveinstance) == "function", "Expected saveinstance function")
    stage("before full save")
    local saveOK, saveError = saveinstance({
        mode = "full",
        FilePath = "MySavedGame_UnionFull.rbxlx",
        Decompile = true,
        decomptype = "custom",
        DecompileJobless = false,
        scriptcache = true,
        SaveCompilationErrors = false,
        SaveBytecode = false,
        SaveBytecodeIfDecompilerFails = false,
        IgnoreSpecialProperties = false,
        IgnoreSharedStrings = false,
        IgnoreSpecialStrings = false,
        IgnoreSpecialClassProperties = false,
        TreatUnionsAsParts = false,
        IgnoreDefaultProperties = false,
        DisableGethiddenpropertyFallback = false,
        DisableReflectionService = false,
        APICache = false,
        APIDumpSource = "auto",
        SafeMode = false,
        KillAllScripts = false,
        BoostFPS = false,
        ShutdownWhenDone = false,
        AntiIdle = false,
        ShowStatus = false,
        NilInstances = false,
        AlternativeWritefile = true,
        YieldInterval = 0.02,
        Crashlog = false,
        __DEBUG_MODE = false,
        TraceProgress = true,
        GeometryReport = true,
    })
    if saveOK then
        stage("Save completed: MySavedGame_UnionFull.rbxlx; inspect Union/Terrain geometry in Studio")
    else
        stage("Save failed: " .. tostring(saveError))
    end
end, function(message) return debug.traceback(tostring(message)) end)
if not ok then stage("Luau error: " .. tostring(err)) end
-- Native client/executor crashes are not recoverable via xpcall.
-- Full export fidelity depends on the executor's hidden-property/bytecode reads.
