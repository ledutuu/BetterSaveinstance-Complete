param(
    [string]$Repo = "$PSScriptRoot/../..",
    [string]$Out = "$PSScriptRoot/geometry-regressions.luau"
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
$readers = Slice "`tlocal function filterPropVal" "`tlocal function ReturnItem"
$head = @'
local checks = 0
local function check(value, reason)
    assert(value, reason)
    checks += 1
end
local function exerciseRead(valueType, route, prior, flags)
    flags = flags or {}
    prior = prior or {}
    local __BREAK = {}
    local string_find = string.find
    local InstancesOverrides = {}
    local IgnoreSpecialStrings = flags.IgnoreStrings or false
    local IgnoreSpecialClassProperties = flags.IgnoreClass or false
    local EXECUTOR_NAME = flags.Executor or "Volcano"
    local __DEBUG_MODE, Crashlog = false, false
    local TracePropertyProgress = function() end
    local function ArrayToDict(items)
        local result = {}
        for _, item in items do result[item] = true end
        return result
    end
    local calls = {direct = 0, hidden = 0, ugc = 0, fallback = 0}
    local payload = valueType == "Content" and {SourceType = "Uri", Uri = "rbxassetid://123"}
        or valueType == "ContentId" and "rbxassetid://123" or "non-empty-geometry-payload"
    local function directRead(instance)
        calls.direct += 1
        if route == "success-throw-success" then
            if instance.Id == 2 then error("second geometry instance unavailable") end
            return payload
        end
        if route == "ugc-nil" or route == "fallback-throw" or instance.Id == 1 then
            error("first geometry instance unavailable")
        end
        return payload
    end
    local index = function(instance, name) return instance[name] end
    local gethiddenproperty = route == "hidden-nil" and function(instance)
        calls.hidden += 1
        if instance.Id == 1 then return nil end
        return payload
    end or nil
    local gethiddenproperty_fallback = route == "ugc-nil" and function(instance)
        calls.ugc += 1
        if instance.Id == 1 then return nil end
        return payload
    end or nil
    local customFallback = route == "fallback-throw" and function(instance)
        calls.fallback += 1
        if instance.Id == 1 then error("first custom fallback unavailable") end
        return payload
    end or nil
'@
$tail = @'
    local property = {
        Name = "GeometryPayload", ValueType = valueType,
        Category = flags.ClassCategory and "Class" or "DataType",
        CanRead = prior.CanRead, GHPFFailed = prior.GHPFFailed, Fallback = customFallback,
    }
    local results = {}
    local special = route == "hidden-nil"
    for id = 1, (route == "success-throw-success" and 3 or 2) do
        local instance = setmetatable({Id = id, ClassName = "MeshPart"}, {__index = function(instance, key)
            assert(key == "GeometryPayload", "unexpected instance lookup: " .. tostring(key))
            return directRead(instance)
        end})
        results[id] = ReadPropertyFull(instance, property, "GeometryPayload", special, property.Category, false)
    end
    return {
        first = results[1], second = results[2], third = results[3], calls = calls,
        property = property, payload = payload, sentinel = __BREAK, fallback = customFallback,
    }
end
for _, valueType in {"BinaryString", "SharedString", "Content", "ContentId"} do
    for _, route in {"ordinary", "hidden-nil", "ugc-nil", "fallback-throw"} do
        local state = exerciseRead(valueType, route)
        check(state.first == state.sentinel, "unreadable first geometry instance is skipped: " .. valueType .. "/" .. route)
        check(state.second == state.payload, "later readable geometry instance survives first failure: " .. valueType .. "/" .. route)
        local attempts = route == "hidden-nil" and state.calls.hidden
            or route == "ugc-nil" and state.calls.ugc
            or route == "fallback-throw" and state.calls.fallback or state.calls.direct
        check(attempts == 2, "geometry retries instance-dependent read/fallback: " .. valueType .. "/" .. route)
        check(state.property.CanRead == nil and state.property.GHPFFailed == nil
            and state.property.Fallback == state.fallback,
            "geometry failures preserve shared class metadata and custom fallback: " .. valueType .. "/" .. route)
    end
    for _, prior in {{CanRead = false}, {CanRead = true}, {CanRead = false, GHPFFailed = true}} do
        local state = exerciseRead(valueType, "ordinary", prior)
        check(state.first == state.sentinel and state.second == state.payload and state.calls.direct == 2,
            "geometry ignores stale class read status: " .. valueType)
        check(state.property.CanRead == prior.CanRead and state.property.GHPFFailed == prior.GHPFFailed,
            "geometry retry leaves prior shared status untouched: " .. valueType)
    end
    local state = exerciseRead(valueType, "ugc-nil", {CanRead = false, GHPFFailed = true})
    check(state.first == state.sentinel and state.second == state.payload and state.calls.ugc == 2,
        "geometry retries UGC despite stale shared GHPFFailed: " .. valueType)
    check(state.property.CanRead == false and state.property.GHPFFailed == true,
        "UGC retry preserves existing shared status: " .. valueType)
    state = exerciseRead(valueType, "success-throw-success")
    check(state.first == state.payload and state.second == state.sentinel and state.third == state.payload,
        "geometry success then failure then success remains protected and independent: " .. valueType)
    check(state.calls.direct == 3 and state.property.CanRead == nil,
        "geometry success cannot promote an unsafe shared CanRead fast path: " .. valueType)
end
for _, route in {"ordinary", "hidden-nil", "ugc-nil", "fallback-throw"} do
    local state = exerciseRead("string", route)
    check(state.first == state.sentinel and state.second == state.sentinel,
        "nongeometry retains shared failure caching: " .. route)
    local attempts = route == "hidden-nil" and state.calls.hidden
        or route == "ugc-nil" and state.calls.ugc
        or route == "fallback-throw" and state.calls.fallback or state.calls.direct
    check(attempts == 1, "nongeometry does not repeatedly invoke unavailable API: " .. route)
    if route == "ugc-nil" then check(state.property.GHPFFailed == true, "nongeometry UGC failure is cached") end
    if route == "fallback-throw" then check(state.property.Fallback == nil, "nongeometry failed custom fallback stays disabled") end
end
local state = exerciseRead("string", "hidden-nil", nil, {IgnoreStrings = true})
check(state.first == state.sentinel and state.second == state.sentinel and state.calls.hidden == 0,
    "intentional special string ignore avoids native calls")
state = exerciseRead("BinaryString", "hidden-nil", nil, {IgnoreClass = true, ClassCategory = true})
check(state.first == state.sentinel and state.second == state.sentinel and state.calls.hidden == 0,
    "intentional special class-property ignore remains effective for geometry")
state = exerciseRead("Content", "hidden-nil", nil, {Executor = "Nihon"})
check(state.first == state.sentinel and state.second == state.sentinel and state.calls.hidden == 0,
    "existing executor-specific special-property restriction remains effective")
print("PASS: " .. checks .. " source-extracted geometry property regression assertions")
'@
$report = Slice "`tlocal geometryFields =" "`tlocal function filterPropVal"
$writeReport = Slice "`t`tif OPTIONS.GeometryReport and writefile then" "`t`tTraceStage(ok and"
$reportHead = @'
local OPTIONS = {GeometryReport = false}
local getRef = function(instance) return instance.Ref end
'@
$reportTail = @'
local ignored, first, second, terrain = {Ref = "RBX0"}, {Ref = "RBX1"}, {Ref = "RBX2"}, {Ref = "RBX3"}
BeginGeometryReport(ignored, "UnionOperation", "disabled")
check(#geometryOrder == 0, "disabled report creates no records")
OPTIONS.GeometryReport = true
BeginGeometryReport(ignored, "MeshPart", "mesh")
check(#geometryOrder == 0, "report limits records to Union/Terrain families")
BeginGeometryReport(first, "UnionOperation", "name\twith\nnewlines")
BeginGeometryReport(second, "IntersectOperation", "second")
BeginGeometryReport(terrain, "Terrain", "Terrain")
check(#geometryOrder == 3, "each geometry instance has one independent record")
RecordGeometryProperty(first, "MeshData", "unreadable")
RecordGeometryProperty(second, "MeshData", "read", 37)
RecordGeometryProperty(second, "MeshData", "serialized", nil, 52)
RecordGeometryProperty(first, "AssetId", "serialized_null", 0, 13)
RecordGeometryProperty(terrain, "SmoothGrid", "empty", 0)
RecordGeometryProperty(terrain, "VoxelGridAssetContentMap", "unsupported_type")
RecordGeometryProperty(first, "Untracked", "read", 999)
RecordGeometryProperty(ignored, "MeshData", "read", 999)
local report = BuildGeometryReport()
check(string.find(report, "RBX1\tUnionOperation\tname with newlines\tMeshData\tunreadable\t0\t0", 1, true),
    "unreadable field is distinct and TSV names are escaped")
check(string.find(report, "RBX2\tIntersectOperation\tsecond\tMeshData\tserialized\t37\t52", 1, true),
    "serialized state preserves raw length and encoded length")
check(string.find(report, "\tAssetId\tserialized_null\t0\t13", 1, true), "null asset is explicit")
check(string.find(report, "\tChildData2\tnot_in_property_list\t0\t0", 1, true),
    "unvisited fields stay visible instead of claiming payload exists")
check(string.find(report, "\tSmoothGrid\tempty\t0\t0", 1, true), "empty payload is distinct")
check(string.find(report, "\tVoxelGridAssetContentMap\tunsupported_type\t0\t0", 1, true),
    "unsupported encoder is distinct")
check(not string.find(report, "999", 1, true) and not string.find(report, "rbxassetid", 1, true),
    "untracked instances/fields and raw asset payloads are absent")
RecordGeometryProperty(second, "MeshData", "empty", 0)
check(geometryRecords[second].States.MeshData[2] == 0 and geometryRecords[second].States.MeshData[3] == 0,
    "zero lengths replace earlier lengths rather than retaining stale data")
local placename = "Fixture.rbxlx"
local writes, warning = {}, nil
local warn = function(message) warning = message end
local writefile = function(path, value) table.insert(writes, {path, value}) end
'@
$writeTail = @'
check(#writes == 1 and writes[1][1] == "Fixture.rbxlx.geometry.tsv", "report uses one companion-file write")
check(writes[1][2] == BuildGeometryReport(), "final write uses actual collected report")
writefile = function() error("mock disk error") end
'@
$failureTail = @'
check(warning == "Geometry report write failed:", "report IO failure is contained and reported")
OPTIONS.GeometryReport = false
writefile = function() error("disabled report must not write") end
'@
$final = @'
check(true, "disabled final report avoids IO")
print("PASS: " .. checks .. " geometry assertions including companion reporting")
'@
[IO.File]::WriteAllText($Out, ($head, $readers, $tail, $reportHead, $report, $reportTail, $writeReport, $writeTail, $writeReport, $failureTail, $writeReport, $final) -join "`n")
