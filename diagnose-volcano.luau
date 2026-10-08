-- Run with this patched saveinstance.luau in the executor's workspace.
-- Diagnostic export omits decompiled scripts and hidden/shared-string data.
local log = "BSI_DIAGNOSTIC.log"
assert(type(readfile) == "function", "Place patched saveinstance.luau in the executor workspace; readfile is required")
assert(type(writefile) == "function" and type(appendfile) == "function", "writefile and appendfile are required for diagnostic logs")
writefile(log, "BetterSaveinstance diagnostic; 2026-10-08\n")
local function stage(message)
    appendfile(log, tostring(os.clock()) .. " " .. message .. "\n")
    print("[BSI_DIAG] " .. message)
end
stage("before reading patched source")
local source = readfile("saveinstance.luau")
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
    IgnoreSharedStrings = true,
    IgnoreSpecialStrings = true,
    IgnoreSpecialClassProperties = true,
    NilInstances = false,
    AlternativeWritefile = true,
    FilePath = "BSI_VOLCANO_DIAGNOSTIC.rbxlx",
    Crashlog = true,
})
if not callOK then
    stage("Luau error: " .. tostring(saveOK))
elseif not saveOK then
    stage("Save failed: " .. tostring(err))
else
    stage("Save completed; check BSI_VOLCANO_DIAGNOSTIC.rbxlx")
end
-- pcall cannot recover a native executor/client crash. The final persisted
-- stage and the last CRASHLOG entry locate the next runtime check.
