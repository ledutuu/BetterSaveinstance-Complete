param(
    [string]$Repo = "$PSScriptRoot/../..",
    [string]$Out = "$PSScriptRoot/extra-regressions.luau"
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
$api = Slice "`tFetchAPI = function(" "`t`tlocal classList ="
$api = $api.Substring($api.IndexOf("`n") + 1)
$filter = Slice "`t`tlocal reflectionFilter" "`t`t-- ! exact version match"
$content = Slice "`t`t`t`t`t`t`tif not ContentProperties then" "`t`t`t`t`t`t`tif ContentProperties[PropertyName]"
$spinner = Slice "`tlocal LoadingText, LoadingThread, IsLoading" "`tlocal function makeTimeoutHandler"
$cleanup = Slice "`tlocal Connections = {}" "`tdo`n`t`tlocal Players = service.Players"
$antiidle = Slice "`t`tif OPTIONS.AntiIdle then" "`t`tif not ClassList"
$finish = Slice "`t`tif not ClassList" "`t`telapse_t = os.clock() - elapse_t"
$wrapper = Slice 'local function synsaveinstance(CustomOptions, CustomOptions2)' 'return synsaveinstance'
$head = @'
local checks = 0
local function check(value, reason)
    assert(value, reason)
    checks += 1
end
local lastApiCalls
local function exerciseApi(mode, requestedSource)
    local calls = {capabilities = 0, classes = 0, mini = 0, warnings = 0, reads = 0, writes = 0, stages = {}}
    calls.http, calls.full = 0, 0
    lastApiCalls = calls
    local apiDumpSource = requestedSource or "full"
    if requestedSource == false then apiDumpSource = nil end
    local disableReflectionService = mode == "disable-reflection"
    local useAPICache = mode ~= "network-cache-disabled"
    local traceStage = function(stage) table.insert(calls.stages, stage) end
    local FULL_VERSION, CLIENT_VERSION = "0.742.0.7421053", 742
    local readfile = function()
        calls.reads += 1
        if mode == "cache" or mode == "empty-cache" or mode == "invalid-cache" or mode == "dual-cache" then return "cached" end
        error("cache missing")
    end
    local SecurityCapabilities = mode ~= "missing-capabilities" and {
        new = function(...)
            calls.capabilities += 1
            return {arguments = {...}}
        end,
    } or nil
    local Enum = {SecurityCapability = {GetEnumItems = function() return {"test"} end}}
    local reflection = {
        GetClasses = function(_, filter)
            calls.classes += 1
            check(filter.ExcludeDisplay and filter.ExcludeInherited, "Reflection filter flags")
            if mode == "reflection" then return {{Name = "Folder", Permits = {New = true}}} end
            error("Reflection unavailable")
        end,
        GetPropertiesOfClass = function() return {} end,
    }
    local service = {ReflectionService = reflection, HttpService = {
        JSONDecode = function(_, value)
            if value == "cached" then
                if mode == "empty-cache" then return {[FULL_VERSION] = {}} end
                if mode == "invalid-cache" then return {[FULL_VERSION] = "corrupt"} end
                return {[FULL_VERSION] = {{Name = "Folder", Members = {}}}}
            end
            if value == "empty-mini" then return {Classes = {}} end
            if value == "invalid-mini" then return {Classes = {{Name = "Folder"}}} end
            if value == "mini" then return {Classes = {{Name = "Folder", Members = {}}}} end
            if value == "version" then return {version = FULL_VERSION, clientVersionUpload = "version-fixture"} end
            if value == "full" then return {Classes = {{Name = "Folder", Members = {{Name = "Name", MemberType = "Property", Default = ""}}}}} end
            error("unexpected JSON fixture")
        end,
        JSONEncode = function() return "encoded-cache" end,
    }}
    local game = {HttpGet = function(_, url)
        calls.http += 1
        if string.find(mode, "network-cache-", 1, true) or string.find(mode, "dual-", 1, true) then
            if string.find(url, "clientsettingscdn.roblox.com", 1, true) then return "version" end
            if string.find(url, "-Full-API-Dump.json", 1, true) then calls.full += 1; return "full" end
        end
        if string.find(url, "Mini-API-Dump.json", 1, true) then
            calls.mini += 1
            if mode == "dual-mini-http-error" then error("mini fixture unavailable") end
            if mode == "dual-mini-empty" then return "empty-mini" end
            if mode == "dual-mini-invalid" then return "invalid-mini" end
            if mode == "all-fail" then error("mini unavailable") end
            return "mini"
        end
        error("network fixture unavailable")
    end}
    local warn = function() calls.warnings += 1 end
    local writefile = function() calls.writes += 1 end
'@
$apiTail = @'
    return API_Dump, calls
end
local dump, calls = exerciseApi("cache")
check(#dump == 1 and calls.capabilities == 0 and calls.classes == 0 and calls.mini == 0, "cached API avoids Reflection capability construction")
dump, calls = exerciseApi("reflection")
check(#dump == 1 and calls.capabilities == 1 and calls.classes == 1 and calls.mini == 0, "Reflection fallback remains usable")
dump, calls = exerciseApi("missing-capabilities")
check(#dump == 1 and calls.classes == 0 and calls.mini == 1, "missing SecurityCapabilities must preserve Mini API fallback")
dump, calls = exerciseApi("mini")
check(#dump == 1 and calls.classes == 1 and calls.mini == 1, "Reflection failure must preserve Mini API fallback")
dump, calls = exerciseApi("disable-reflection")
check(#dump == 1 and calls.capabilities == 0 and calls.classes == 0 and calls.mini == 1, "Reflection optout skips native capability and service APIs")
check(table.find(calls.stages, "API_FETCHER_3_BEGIN") and table.find(calls.stages, "API_FETCHER_4_END ok=true"), "API phases record skipped Reflection and successful fallback")
dump, calls = exerciseApi("network-cache-disabled")
check(#dump == 1 and calls.reads == 0 and calls.writes == 0 and calls.mini == 0, "APICache=false skips reads and writes while fetching full API")
dump, calls = exerciseApi("network-cache-enabled")
check(#dump == 1 and calls.reads == 1 and calls.writes == 1 and calls.mini == 0, "enabled API cache preserves full-dump cache write")
for _, mode in {"empty-cache", "invalid-cache"} do
    dump, calls = exerciseApi(mode)
    check(#dump == 1 and calls.classes == 1 and calls.mini == 1, "malformed cached API must preserve fallback on " .. mode)
end
local ok, err = pcall(exerciseApi, "all-fail")
check(not ok and string.find(err, "No usable Roblox API dump", 1, true), "all failed API sources report explicit initialization error")
local function selectedSource(calls, name)
    for _, stage in calls.stages do
        if string.find(stage, "API_SOURCE_SELECTED " .. name, 1, true) then return true end
    end
    return false
end
dump, calls = exerciseApi("dual-mini-ok", "AuTo")
check(#dump == 1 and calls.mini == 1 and calls.http == 1 and calls.full == 0
    and calls.reads == 0 and calls.writes == 0 and calls.capabilities == 0 and calls.classes == 0,
    "auto chooses Mini before Full, cache disk IO, or Reflection")
check(selectedSource(calls, "mini"), "auto trace identifies selected Mini source")
dump, calls = exerciseApi("dual-mini-ok", false)
check(#dump == 1 and calls.mini == 1 and calls.http == 1 and calls.reads == 0,
    "omitted APIDumpSource defaults to automatic Mini priority")
for _, mode in {"dual-mini-http-error", "dual-mini-empty", "dual-mini-invalid"} do
    dump, calls = exerciseApi(mode, "auto")
    check(#dump == 1 and calls.mini == 1 and calls.full == 1 and calls.reads == 1
        and calls.writes == 1 and calls.classes == 0,
        "auto falls back from unavailable Mini to usable Full on " .. mode)
    check(selectedSource(calls, "full"), "fallback trace identifies Full source on " .. mode)
end
ok, err = pcall(exerciseApi, "dual-mini-http-error", "MiNi")
check(not ok and lastApiCalls.http == 1 and lastApiCalls.mini == 1 and lastApiCalls.full == 0
    and lastApiCalls.reads == 0 and lastApiCalls.writes == 0 and lastApiCalls.classes == 0,
    "Mini-only failure never tries Full, cache, or Reflection")
dump, calls = exerciseApi("dual-mini-ok", "mini")
check(#dump == 1 and calls.http == 1 and selectedSource(calls, "mini"), "explicit Mini-only success")
dump, calls = exerciseApi("dual-mini-ok", "FuLl")
check(#dump == 1 and calls.mini == 0 and calls.full == 1 and calls.reads == 1 and calls.writes == 1,
    "explicit Full retains Full-first/cache behavior when Mini would succeed")
check(selectedSource(calls, "full"), "explicit Full trace identifies Full source")
dump, calls = exerciseApi("dual-cache", "full")
check(#dump == 1 and calls.reads == 1 and calls.http == 0 and selectedSource(calls, "cache"),
    "Full-first accepts version cache without network")
dump, calls = exerciseApi("reflection", "full")
check(selectedSource(calls, "reflection"), "readable source trace identifies Reflection fallback")
ok, err = pcall(exerciseApi, "dual-mini-ok", "unsupported")
check(not ok and string.find(tostring(err), "APIDumpSource", 1, true)
    and lastApiCalls.http == 0 and lastApiCalls.reads == 0 and lastApiCalls.writes == 0,
    "invalid source is rejected before HTTP or cache IO")
local function exerciseContent(mode)
    local built, lookedUp = 0, 0
    local disableReflectionService = mode == "disabled"
    local traceStage = function() end
    local SecurityCapabilities = mode ~= "missing-capabilities" and {new = function()
        built += 1
        return {}
    end} or nil
    local Enum = {SecurityCapability = {GetEnumItems = function() return {} end}}
    local service = setmetatable({}, {__index = function(_, key)
        if mode == "missing-service" or mode == "disabled" then error("Reflection service lookup unavailable") end
        return {GetPropertiesOfClass = function(_, name, filter)
            lookedUp += 1
            check(name == "MeshPart" and filter.ExcludeDisplay, "Content metadata uses Reflection filter")
            return {{Name = "MeshContent", Serialized = false}}
        end}
    end})
'@
$contentHead = @'
    local ClassName = "MeshPart"
    local ContentProperties
'@
$contentTail = @'
    if mode == "ok" then
        check(getReflectionFilter() == getReflectionFilter(), "Reflection filter is cached within one fetch")
        check(built == 1 and lookedUp == 1 and ContentProperties.MeshContent == false, "Content properties preserve explicit false and reuse filter")
    else
        check(type(ContentProperties) == "table" and next(ContentProperties) == nil, "missing Content Reflection metadata remains optional")
    end
end
exerciseContent("ok")
exerciseContent("missing-capabilities")
exerciseContent("missing-service")
exerciseContent("disabled")
local function exerciseLifecycle(mode)
    local cancelled, disconnected = {}, 0
    local renderingRestored, saveCalls = 0, 0
    local scheduled = {}
    local task = {
        spawn = function(callback)
            local thread = coroutine.create(callback)
            scheduled[#scheduled + 1] = thread
            local ok, err = coroutine.resume(thread)
            assert(ok, err)
            return thread
        end,
        wait = function() coroutine.yield() end,
        cancel = function(thread) cancelled[thread] = true end,
        delay = function() end,
    }
    local StatusText = mode ~= "no-spinner" and {Text = "saving"} or nil
    local wait_for_render = function() end
    local placename = "fixture.rbxlx"
    local GLOBAL_ENV = {[placename] = true}
    local session = {}
    local TraceStage = function() end
    local Color3 = {new = function(value) return value end}
    local service = {RunService = {Set3dRenderingEnabled = function(_, enabled)
        if enabled then renderingRestored += 1 end
    end}, GuiService = {ClearError = function() end}}
    local event = {Connect = function()
        return {Disconnect = function() disconnected += 1 end}
    end}
    local GetLocalPlayer = function()
        if mode == "delayed-idle" then coroutine.yield() end
        return {Idled = event}
    end
    local getconnections = mode == "delayed-idle-connections" and function()
        coroutine.yield()
        return {}
    end or nil
    local game = {}
    local OPTIONS = {AntiIdle = true, BoostFPS = true, APIDumpSource = "auto"}
    local apiCalls = 0
    local FetchAPI = function(_, _, _, source)
        apiCalls += 1
        check(source == "auto", "finish forwards API source preference")
        if mode == "api-error" then error("API fixture failure") end
        return {}, "mini"
    end
    local ClassList = (mode == "source-reuse" or mode == "source-change") and {} or nil
    local ClassListSource = mode == "source-change" and "full" or mode == "source-reuse" and "auto" or nil
    local ClassListDataSource = mode == "source-reuse" and "mini" or nil
    local warn = function() end
    local elapse_t
    local old_gethiddenproperty = nil
'@
# save_game must resolve the source-extracted local run_with_loading, not a global.
$lifecycleMiddle = @'
    Connect(event, function() end)
    if StatusText then run_with_loading("fixture", false, false, function() return true end) end
    local spinnerThread = LoadingThread
    local function save_game()
        saveCalls += 1
        if mode == "save-error" then
            return run_with_loading("fixture", false, false, function() error("save fixture failure") end)
        end
    end
'@
$lifecycleTail = @'
    if mode == "delayed-idle" or mode == "delayed-idle-connections" then
        for _, thread in scheduled do
            if not cancelled[thread] and coroutine.status(thread) == "suspended" then
                local ok, err = coroutine.resume(thread)
                assert(ok, err)
            end
        end
    end
    check(not IsLoading and LoadingThread == nil, "cleanup stops spinner on " .. mode)
    check(spinnerThread == nil or cancelled[spinnerThread], "cleanup cancels spinner task on " .. mode)
    check(anti_idle == nil, "cleanup removes AntiIdle handler on " .. mode)
    check(GLOBAL_ENV[placename] == nil, "cleanup clears save guard on " .. mode)
    check(disconnected == ((mode == "delayed-idle" or mode == "delayed-idle-connections") and 1 or 2), "cleanup disconnects tracked and AntiIdle listeners on " .. mode)
    check(renderingRestored == 1, "BoostFPS rendering is restored on " .. mode)
    check(saveCalls == (mode == "api-error" and 0 or 1), "completion path invokes saving only after API success on " .. mode)
    check(apiCalls == (mode == "source-reuse" and 0 or 1), "finish reuses only matching source preference on " .. mode)
    if mode ~= "api-error" then check(ClassListSource == "auto", "successful fetch/reuse records source preference on " .. mode) end
    if mode ~= "api-error" then check(ClassListDataSource == "mini", "successful fetch/reuse retains selected source on " .. mode) end
    local disconnectCount = disconnected
    session.cleanup()
    Connect(event, function() end)
    session.cleanup()
    check(disconnected == disconnectCount and anti_idle == nil, "cleanup stays idempotent and rejects late listeners on " .. mode)
end
for _, mode in {"success", "save-error", "api-error", "no-spinner", "delayed-idle", "delayed-idle-connections", "source-reuse", "source-change"} do
    exerciseLifecycle(mode)
end
'@
$wrapperHead = @'
local function exerciseWrapper(mode)
    local busyMarker, fallbackMarker = {}, {}
    local fileKey, externalKey = "owned.rbxlx", "external.rbxlx"
    local GLOBAL_ENV = {[externalKey] = busyMarker}
    local gethiddenproperty_fallback = fallbackMarker
    local implCalls, cleanupCalls, warnings = 0, 0, 0
    local warn = function() warnings += 1 end
    if mode == "busy" then GLOBAL_ENV.USSI = busyMarker end
    local saveinstanceImpl = function(first, second, session)
        implCalls += 1
        check(first == "options" and second == "options2", "wrapper forwards options")
        check(GLOBAL_ENV.USSI == true, "wrapper owns USSI during implementation")
        if mode == "initialization-error" then error("initialization fixture error") end
        if mode == "busy-file" then return false, "external file busy" end
        GLOBAL_ENV[fileKey] = true
        session.placename = fileKey
        session.cleanup = function()
            cleanupCalls += 1
            if mode == "cleanup-error" then error("cleanup fixture error") end
        end
        if mode == "owned-initialization-error" then error("initialization fixture error") end
        if mode == "returned-false" then return false, "save fixture error" end
        return true, "saved fixture"
    end
'@
$wrapperTail = @'
    local result, err = synsaveinstance("options", "options2")
    if mode == "busy" then
        check(not result and string.find(err, "already running", 1, true), "busy wrapper returns reason")
        check(implCalls == 0 and cleanupCalls == 0, "busy wrapper skips initialization and cleanup")
        check(GLOBAL_ENV.USSI == busyMarker and gethiddenproperty_fallback == fallbackMarker, "busy wrapper preserves another save's shared state")
    else
        check(implCalls == 1 and GLOBAL_ENV.USSI == nil, "wrapper releases USSI on " .. mode)
        check(gethiddenproperty_fallback == nil, "wrapper releases hidden-property fallback on " .. mode)
        check(GLOBAL_ENV[fileKey] == nil, "wrapper releases owned file on " .. mode)
        check(cleanupCalls == ((mode == "initialization-error" or mode == "busy-file") and 0 or 1), "wrapper invokes registered cleanup on " .. mode)
        if mode == "initialization-error" or mode == "owned-initialization-error" then
            check(result == false and string.find(err, "initialization fixture error", 1, true), "wrapper reports initialization traceback")
        elseif mode == "returned-false" then
            check(result == false and err == "save fixture error", "wrapper preserves returned-false save error")
        elseif mode == "busy-file" then
            check(result == false and err == "external file busy", "busy-file return is preserved")
        else
            check(result == true and err == "saved fixture", "wrapper preserves implementation success on " .. mode)
        end
        if mode == "cleanup-error" then check(warnings == 1, "cleanup error is warned once without blocking guard release") end
    end
    check(GLOBAL_ENV[externalKey] == busyMarker, "wrapper preserves externally owned file key on " .. mode)
end
for _, mode in {"busy", "initialization-error", "owned-initialization-error", "success", "returned-false", "busy-file", "cleanup-error"} do
    exerciseWrapper(mode)
end
print("PASS: " .. checks .. " extra source-extracted regression assertions")
'@
# API failure returns early in production; wrap just the completion snippet so the
# same postconditions are checked after that early return in this harness.
$wrappedFinish = "    local function finish()`n" + $finish + "`n    end`n    finish()`n"
[IO.File]::WriteAllText($Out, $head + "`n" + $api + "`n" + $apiTail + "`n" + $filter + "`n" + $contentHead + "`n" + $content + "`n" + $contentTail + "`n" + $spinner + "`n" + $cleanup + "`n" + $lifecycleMiddle + "`n" + $antiidle + "`n" + $wrappedFinish + "`n" + $lifecycleTail + "`n" + $wrapperHead + "`n" + $wrapper + "`n" + $wrapperTail)
