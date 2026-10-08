param([string]$Repo = "$PSScriptRoot/../..", [string]$Out = "$PSScriptRoot/regressions.luau", [switch]$CrashOnly)
$ErrorActionPreference = 'Stop'
$src = [IO.File]::ReadAllText((Join-Path $Repo 'saveinstance.luau')).Replace("`r`n", "`n")
function Slice([string]$start, [string]$end) {
    $a = $src.IndexOf($start)
    if ($a -lt 0) { throw "Missing start: $start" }
    $b = $src.IndexOf($end, $a + $start.Length)
    if ($b -lt 0) { throw "Missing end: $end" }
    return $src.Substring($a, $b - $a)
}
$array = Slice 'local function arrayToDict' 'local service ='
$options = Slice "`tlocal OPTIONS = {" "`tif not writefile and not OPTIONS.Callback"
$decompiler = Slice "`tlocal getbytecode`n" "`tlocal function GetLocalPlayer()"
$crashlog = Slice "`tlocal Crashlog = OPTIONS.Crashlog" "`tif __DEBUG_MODE and type(__DEBUG_MODE)"
$linkedMatch = [regex]::Match($src, '(?s)local should_decompile = true.*?(?=\n[\t ]*if should_decompile then\n[\t ]*local isLocalScript)')
$head = @'
local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks += 1
end
'@
$resolve = @'
local function resolveOptions(CustomOptions, CustomOptions2)
    local EXECUTOR_NAME = "Volcano"
    local gethiddenproperty = function() end
'@ + "`n" + $options + @'
    return OPTIONS
end
local options = resolveOptions({noscripts = true})
check(options.Decompile == false, "noscripts inverse alias must disable Decompile")
check(resolveOptions({DecompileScripts = false}).Decompile == false, "DecompileScripts alias")
check(resolveOptions({dEcOmPiLe = false}).Decompile == false, "case insensitive options")
check(not options.SafeMode and not options.KillAllScripts and not options.ShutdownWhenDone, "non-destructive defaults")
check(resolveOptions({Decompile = false, noscripts = false}).Decompile == false, "canonical disabled option outranks inverse alias")
check(resolveOptions({Decompile = true, noscripts = true}).Decompile == true, "canonical enabled option outranks inverse alias")
check(resolveOptions({Decompile = false, DecompileScripts = true}).Decompile == false, "canonical option outranks normal alias")
check(resolveOptions({DecompileTimeout = 2, timeout = 99}).DecompileTimeout == 2, "canonical timeout outranks alias")
local function exercise(input, native, failFetch, seedCache)
    local OPTIONS = resolveOptions(input)
    local DecompileJobless = OPTIONS.DecompileJobless
    local ScriptCache = OPTIONS.scriptcache
    local calls = {bytecode = 0, native = 0, fetch = 0, warning = 0}
    local getscriptbytecode = function()
        calls.bytecode += 1
        return "\6data"
    end
    local base64encode = function(value) return value end
    local makeTimeoutHandler = function(_, f)
        return function(...) return pcall(f, ...) end
    end
    local decompile = native and function()
        calls.native += 1
        return "return 'native'"
    end or nil
    local game = {HttpGet = function()
        calls.fetch += 1
        if failFetch then error("HTTP 404") end
        return "fixture"
    end}
    local loadstring = function()
        return function()
            return {decompile = function() return "return 'custom'" end}
        end
    end
    local GLOBAL_ENV = {decompile = "preserved"}
    local __DEBUG_MODE = false
    local Crashlog = false
    local warn = function() calls.warning += 1 end
    local ldeccache = seedCache or {}
    local ldecompile, CompilationError
    local run_with_loading = function(_, _, _, f, ...) return f(...) end
'@ + "`n" + $decompiler + @'
    local script = {Name = "Test", GetFullName = function() return "Test" end}
    if CompilationError then CompilationError(script) end
    local result = ldecompile(script)
    check(GLOBAL_ENV.decompile == "preserved", "custom decompiler must not overwrite global")
    return calls, result
end
for _, input in {{noscripts = true}, {Decompile = false}, {DecompileScripts = false}} do
    local calls, result = exercise(input, true, false)
    check(calls.bytecode == 0 and calls.native == 0 and calls.fetch == 0, "disabled scripts must not invoke native or remote decompilation")
    check(result == "-- Decompiling is disabled", "disabled script output")
end
local calls, result = exercise({decomptype = "custom", scriptcache = false, SaveCompilationErrors = false}, true, false)
check(calls.fetch == 1 and calls.native == 0 and result == "return 'custom'", "selected custom decompiler")
calls, result = exercise({decomptype = "custom", scriptcache = false, SaveCompilationErrors = false}, true, true)
check(calls.warning == 1 and calls.native == 1 and result == "return 'native'", "HTTP failure should retain native decompiler")
calls, result = exercise({scriptcache = false, SaveCompilationErrors = false}, false, true)
check(calls.warning == 1 and string.find(result, "does NOT have a Decompiler", 1, true), "HTTP failure without native should emit placeholder")
calls = exercise({DecompileJobless = true, Decompile = false}, false, false)
check(calls.fetch == 0 and calls.bytecode == 0, "jobless disabled save")
calls, result = exercise({DecompileJobless = true}, true, false)
check(calls.fetch == 0 and calls.native == 0 and calls.bytecode == 1 and string.find(result, "Not found", 1, true), "jobless cache miss must not decompile")
calls, result = exercise({DecompileJobless = true}, false, false, {["\6data"] = "return 'cached'"})
check(calls.fetch == 0 and calls.native == 0 and result == "return 'cached'", "jobless can return cache without a native decompiler")
local function exerciseCrashlog(hasAppend)
    local OPTIONS = {Crashlog = true, __DEBUG_MODE = false}
    local lines = {}
    local warn = function() end
    local originalWarn = warn
    local writefile = function() end
    local appendfile = hasAppend and function(_, text) table.insert(lines, text) end or nil
    local game = {PlaceId = 123}
    local service = {HttpService = {GenerateGUID = function() return "test" end}}
    local DateTime = {now = function() return {UnixTimestampMillis = 1} end}
'@ + "`n" + $crashlog + @'
    if hasAppend then
        warn("test", true, {}, nil)
        check(type(Crashlog) == "function" and #lines == 1, "Crashlog must stringify arbitrary warning arguments")
        check(string.find(lines[1], "true", 1, true) and string.find(lines[1], "nil", 1, true), "warning log values")
    else
        check(Crashlog == false and warn == originalWarn, "Crashlog disabled when appendfile absent")
    end
end
exerciseCrashlog(true)
exerciseCrashlog(false)
'@
$parserStart = $src.IndexOf('local function parseLinkedSource')
$parser = ''
if (-not $CrashOnly) {
    $parserEnd = $src.IndexOf('--[', $parserStart)
    if($parserStart -lt 0 -or $parserEnd -lt 0) { throw 'Missing parser' }
    $parser = $src.Substring($parserStart, $parserEnd - $parserStart)
}
$tail = @'
local hash = string.rep("0", 32)
local cases = {
    {"rbxassetid://123", "123", "id", "id=123"},
    {"https://www.roblox.com/asset/?id=123&version=7", "123", "id", "id=123&version=7"},
    {"rbxassetid://0&hash=" .. hash, hash, "hash", "hash=" .. hash},
    {"https://www.roblox.com/asset/?hash=cd73dd2fe5e5013137231c227da3167e&id=0", "cd73dd2fe5e5013137231c227da3167e", "hash", "hash=cd73dd2fe5e5013137231c227da3167e"},
    {"123", "123", "id", "id=123"},
    {"unknown"},
}
for _, fixture in cases do
    local id, kind, query = parseLinkedSource(fixture[1])
    check(id == fixture[2] and kind == fixture[3] and query == fixture[4], "LinkedSource parser: " .. fixture[1])
end
print("PASS: " .. checks .. " source-extracted regression assertions")
'@
if (-not $CrashOnly) {
    if (-not $linkedMatch.Success) { throw 'Missing LinkedSource recovery block' }
    $linkedHarness = @'
local function exerciseLinked(jobless, cache, url)
    local instance = {LinkedSource = url, GetFullName = function() return "LinkedTest" end}
    local index = function(value, key) return value[key] end
    local ScriptCache = true
    local DecompileJobless = jobless
    local ldeccache = cache or {}
    local RecoveredScripts
    local value
    local calls = {}
    local game = {HttpGet = function(_, requested)
        table.insert(calls, requested)
        return "return 'linked'"
    end}
    local filterLinkedSource = function(source) return source == "return 'linked'" end
    local warn = function() end
'@ + "`n" + $linkedMatch.Value + @'
    return value, should_decompile, calls
end
local value, pending, requests = exerciseLinked(true, nil, "rbxassetid://123")
check(#requests == 0 and not pending and string.find(value, "Not found", 1, true), "jobless LinkedSource miss never downloads new source")
value, pending, requests = exerciseLinked(true, {["id=123"] = "return 'cached'"}, "rbxassetid://123")
check(#requests == 0 and not pending and value == "return 'cached'", "jobless LinkedSource cache hit")
value, pending, requests = exerciseLinked(false, nil, "https://www.roblox.com/asset/?id=123&version=7")
check(#requests == 1 and requests[1] == "https://assetdelivery.roblox.com/v1/asset/?id=123&version=7", "official raw-content URL preserves explicit asset version")
check(not pending and value == "return 'linked'", "successful LinkedSource retrieval")
value, pending, requests = exerciseLinked(false, {["id=123&version=7"] = "old"}, "https://www.roblox.com/asset/?id=123&version=8")
check(#requests == 1 and value == "return 'linked'", "different asset versions do not share cache entries")
'@
    $tail = $tail.Replace('print("PASS: " .. checks .. " source-extracted regression assertions")', $linkedHarness + "`n" + 'print("PASS: " .. checks .. " source-extracted regression assertions")')
}
if ($CrashOnly) {
    $resolve = $resolve.Substring(0, $resolve.IndexOf('local calls, result = exercise({decomptype'))
    $resolve = $resolve.Replace('check(not options.SafeMode and not options.KillAllScripts and not options.ShutdownWhenDone, "non-destructive defaults")', '')
    $tail = 'print("PASS: disabled-decompile regression")'
}
[IO.File]::WriteAllText($Out, $head + "`n" + $array + "`n" + $resolve + "`n" + $parser + "`n" + $tail)
