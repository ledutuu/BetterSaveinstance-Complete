param(
    [string]$Repo = "$PSScriptRoot/../..",
    [string]$Out = "$PSScriptRoot/startup-regressions.luau"
)
$ErrorActionPreference = 'Stop'
$src = [IO.File]::ReadAllText((Join-Path $Repo 'saveinstance.luau')).Replace("`r`n", "`n")
function Slice([string]$start, [string]$end) {
    $a = $src.IndexOf($start)
    if ($a -lt 0) { throw "Missing start: $start" }
    $b = $src.IndexOf($end, $a + $start.Length)
    if ($b -lt 0) { throw "Missing end: $end" }
    return $src.Substring($a, $b - $a)
}
$crashlog = Slice "`tlocal Crashlog = OPTIONS.Crashlog" "`tif __DEBUG_MODE and type(__DEBUG_MODE)"
if (-not $crashlog.Contains('TraceStage')) { throw 'Startup trace source is not ready yet' }
$filename = Slice "`t`tlocal PlaceName = game.PlaceId" "`t`tif mode ~= ""scripts"" then"
$head = @'
local checks = 0
local function check(value, reason)
    assert(value, reason)
    checks += 1
end
local function exerciseCrashlog(mode)
    local OPTIONS = {
        Crashlog = true, __DEBUG_MODE = false, Decompile = false,
        SafeMode = false, KillAllScripts = false, AntiIdle = false,
        ReadSharedStrings = false, IgnoreSharedStrings = true,
        DisableGethiddenpropertyFallback = true, FilePath = "diagnostic",
        ShowStatus = false, IgnoreSpecialProperties = true,
        DisableReflectionService = true, APICache = false,
    }
    local files, written, appended = {}, {}, {}
    local warn = function() end
    local originalWarn = warn
    local writefile = mode ~= "missing-write" and function(path, content)
        files[path] = content
        written[#written + 1] = {path = path, content = content}
    end or nil
    local appendfile = mode ~= "missing-append" and function(path, content)
        if mode == "append-error" then error("append fixture error") end
        appended[#appended + 1] = {path = path, content = content}
    end or nil
    local game = {PlaceId = 123}
    local service = {HttpService = {GenerateGUID = function() return "fixture-guid" end}}
    local DateTime = {now = function() return {UnixTimestampMillis = 7} end}
    local session = {}
    local EXECUTOR_NAME, FULL_VERSION = "Volcano", "0.742.0.7421053"
'@
$traceTail = @'
    local stageFile = "CRASHLOG_fixture-guid_STAGE.txt"
    if mode == "missing-write" or mode == "missing-append" then
        check(Crashlog == false and warn == originalWarn, "unavailable Crashlog APIs disable wrapper on " .. mode)
        return
    end
    check(type(Crashlog) == "function" and type(TraceStage) == "function", "Crashlog exports local trace helper")
    check(type(files[stageFile]) == "string", "startup creates persistent stage companion")
    local optionsSeen = false
    for _, entry in written do
        if entry.path == stageFile and string.find(entry.content, "Decompile=false", 1, true)
            and string.find(entry.content, "ShowStatus=false", 1, true)
            and string.find(entry.content, "IgnoreSpecialProperties=true", 1, true)
            and string.find(entry.content, "DisableReflectionService=true", 1, true)
            and string.find(entry.content, "APICache=false", 1, true) then
            optionsSeen = true
        end
    end
    check(optionsSeen, "startup trace captures resolved diagnostic options")
    TraceStage("fixture-stage")
    check(string.find(files[stageFile], "fixture-stage", 1, true), "phase update persists with writefile")
    check(#appended == 0, "phase markers do not invoke appendfile")
    local ok, err = pcall(Crashlog, "fixture warning")
    if mode == "append-error" then
        check(not ok and string.find(err, "append fixture error", 1, true), "append failure remains observable")
        local lastStage = string.lower(files[stageFile])
        check(string.find(lastStage, "appendfile", 1, true) and string.find(lastStage, "begin", 1, true), "append failure preserves first-append BEGIN stage")
        check(#appended == 0, "failed append writes no log line")
    else
        check(ok and #appended == 1, "ordinary log call appends exactly one line")
        local lastStage = string.lower(files[stageFile])
        check(string.find(lastStage, "appendfile", 1, true) and string.find(lastStage, "ok", 1, true), "first successful append records OK stage")
        TraceStage("after-first-append")
        Crashlog("second fixture warning")
        check(#appended == 2 and string.find(files[stageFile], "after-first-append", 1, true), "later appends preserve current phase")
    end
end
exerciseCrashlog("normal")
exerciseCrashlog("append-error")
exerciseCrashlog("missing-append")
exerciseCrashlog("missing-write")
local function exerciseFilename(path, model, metadataError)
    local metadataCalls = 0
    local game = {PlaceId = 123, GetFullName = function() return "DataModel" end}
    local service = {MarketplaceService = {GetProductInfoAsync = function(_, id)
        metadataCalls += 1
        check(id == 123, "filename metadata lookup uses place ID")
        if metadataError then error("metadata fixture error") end
        return {Name = "Roblox Fixture"}
    end}}
    local FilePath, IsModel = path, model
    local OPTIONS = {AvoidFileOverwrite = false}
    local ToSaveInstance = nil
    local tmp = {}
    local CustomOptions_valid = {}
    local mode = "full"
    local GLOBAL_ENV = {}
    local session = {}
    local isfile = nil
    local placename
    local TraceStage = function() end
'@
$filenameTail = @'
    check(GLOBAL_ENV[placename] == true and session.placename == placename, "filename block claims only resolved file")
    return placename, metadataCalls
end
local name, calls = exerciseFilename("work/diagnostic", false, false)
check(name == "work/diagnostic.rbxlx" and calls == 0, "explicit FilePath adds extension and avoids metadata lookup")
name, calls = exerciseFilename("work/diagnostic.rbxlx", false, false)
check(name == "work/diagnostic.rbxlx" and calls == 0, "explicit extension is preserved without metadata lookup")
name, calls = exerciseFilename("work/diagnostic", true, false)
check(name == "work/diagnostic.rbxmx" and calls == 0, "explicit model FilePath avoids metadata lookup")
name, calls = exerciseFilename(false, false, false)
check(name == "place 123 Roblox Fixture.rbxlx" and calls == 1, "default filename retains place metadata")
name, calls = exerciseFilename(false, true, false)
check(name == "model 123 Roblox Fixture DataModel.rbxmx" and calls == 1, "default model filename retains metadata")
name, calls = exerciseFilename(false, false, true)
check(name == "place 123.rbxlx" and calls == 1, "metadata failure retains place-ID filename fallback")
print("PASS: " .. checks .. " startup source-extracted regression assertions")
'@
$progressHead = @'
local function exerciseProgressIO(mode)
    local clockNow = 0
    local os = {clock = function() return clockNow end}
    local files, writes = {}, {}
    local OPTIONS = {
        TraceProgress = mode ~= "disabled", Crashlog = mode == "fallback",
        __DEBUG_MODE = false, Decompile = false, ShowStatus = false,
        IgnoreSpecialProperties = true, DisableReflectionService = true, APICache = false,
    }
    local writefile = mode ~= "missing-write" and function(path, content)
        files[path] = content
        table.insert(writes, {path = path, content = content})
    end or nil
    local appendfile = nil
    local warnings = 0
    local warn = function() warnings += 1 end
    local originalWarn = warn
    local game = {PlaceId = 123}
    local service = {HttpService = {GenerateGUID = function() return "progress-guid" end}}
    local session = {}
    local EXECUTOR_NAME, FULL_VERSION = "Volcano", "0.742.0.7421053"
'@
$progressTail = @'
    return {
        files = files, writes = writes, crashlog = Crashlog, debugMode = __DEBUG_MODE,
        warn = warn, warnings = warnings, originalWarn = originalWarn, trace = TraceStage, property = TracePropertyProgress,
        setTime = function(value) clockNow = value end,
    }
end
local progressPath = "CRASHLOG_progress-guid_STAGE.txt"
for _, mode in {"normal", "fallback"} do
    local state = exerciseProgressIO(mode)
    check(state.crashlog == false and state.debugMode == false and state.warn == state.originalWarn,
        "progress-only tracing avoids debug promotion and warn wrapping on " .. mode)
    check(#state.writes == 1 and state.files["CRASHLOG_progress-guid"] == nil,
        "progress-only creates stage companion without main Crashlog or appendfile on " .. mode)
    check(string.find(state.files[progressPath], "TraceProgress=true", 1, true)
        and string.find(state.files[progressPath], "Decompile=false", 1, true), "progress config persists")
    state.trace("fixture-progress-stage")
    check(string.find(state.files[progressPath], "fixture-progress-stage", 1, true)
        and string.find(state.files[progressPath], "ShowStatus=false", 1, true), "progress stage accepts phase strings and retains config")
end
for _, mode in {"disabled", "missing-write"} do
    local state = exerciseProgressIO(mode)
    state.trace("ignored")
    state.property({ClassName = "Part"}, "Ignored")
    check(#state.writes == 0 and next(state.files) == nil, "disabled/unavailable tracing causes no file IO on " .. mode)
    check(state.crashlog == false and state.debugMode == false and state.warn == state.originalWarn,
        "disabled/unavailable tracing preserves debug and warning state on " .. mode)
    check(state.warnings == (mode == "missing-write" and 1 or 0), "missing-write warning uses original warn")
end
local state = exerciseProgressIO("normal")
local instance = setmetatable({ClassName = "Part"}, {__index = function(_, key)
    error("Unexpected instance lookup: " .. tostring(key))
end})
state.property(instance, "First")
check(#state.writes == 2 and string.find(state.files[progressPath], "PROPERTY_PROGRESS class=Part property=First reads=1", 1, true),
    "first property progress writes immediately without GetFullName")
for i = 1, 200 do state.property(instance, "Burst" .. i) end
check(#state.writes == 2, "property burst avoids per-property disk writes")
state.setTime(0.499999)
state.property(instance, "BeforeBoundary")
check(#state.writes == 2, "property sampling excludes time before 0.5s")
state.setTime(0.5)
state.property(instance, "AtBoundary")
check(#state.writes == 3 and string.find(state.files[progressPath], "property=AtBoundary", 1, true), "property sampling includes exact 0.5s boundary")
state.setTime(0.999999)
state.property(instance, "NextBeforeBoundary")
check(#state.writes == 3, "property sampling limits successive interval")
state.setTime(1)
state.property(instance, "NextBoundary")
check(#state.writes == 4 and string.find(state.files[progressPath], "property=NextBoundary", 1, true)
    and string.find(state.files[progressPath], "TraceProgress=true", 1, true), "subsequent sampled property retains latest event and config")
print("PASS: " .. checks .. " startup assertions including progress tracing")
'@
[IO.File]::WriteAllText($Out, $head + "`n" + $crashlog + "`n" + $traceTail + "`n" + $filename + "`n" + $filenameTail + "`n" + $progressHead + "`n" + $crashlog + "`n" + $progressTail)
