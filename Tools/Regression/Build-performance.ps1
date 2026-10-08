param(
    [string]$Repo = "$PSScriptRoot/../..",
    [string]$Out = "$PSScriptRoot/performance-regressions.luau"
)
$ErrorActionPreference = 'Stop'
$src = [IO.File]::ReadAllText((Join-Path $Repo 'saveinstance.luau')).Replace("`r`n", "`n")
function Slice([string]$start, [string]$end) {
    $a = $src.IndexOf($start)
    if ($a -lt 0) { throw "Missing source helper start: $start" }
    $b = $src.IndexOf($end, $a + $start.Length)
    if ($b -lt 0) { throw "Missing source helper end: $end" }
    return $src.Substring($a, $b - $a)
}
$yieldHelpers = Slice "`tlocal lastYield =" "`tlocal LoadingText, LoadingThread, IsLoading"
$inheritedHelpers = Slice "`tlocal inheritedPropertyLists =" "`tlocal function save_cache()"
$head = @'
local checks = 0
local function check(value, reason)
    assert(value, reason)
    checks += 1
end
local function sameProperties(actual, expected, reason)
    check(#actual == #expected, reason .. " count")
    for i, value in expected do
        check(actual[i] == value, reason .. " item " .. i)
    end
end
local arrayCalls = 0
local function ArrayToDict(values)
    arrayCalls += 1
    local dict = {}
    for _, value in values do dict[value] = true end
    return dict
end
local base, mid, leaf = {Name = "Base"}, {Name = "Mid"}, {Name = "Leaf"}
local nbase, nmid, nleaf = {Name = "NBase"}, {Name = "NMid"}, {Name = "NLeaf"}
local ClassList = {
    Base = {Properties = {base}, NotSaveableProperties = {nbase}},
    Mid = {Superclass = "Base", Properties = {mid}, NotSaveableProperties = {nmid}},
    Leaf = {Superclass = "Mid", Properties = {leaf}, NotSaveableProperties = {nleaf}},
}
local function makePropertyReader()
'@
$inheritTail = @'
    return GetInheritedProps
end
local inherited = makePropertyReader()
local all = inherited("Leaf")
sameProperties(all, {leaf, mid, base}, "leaf-to-base order")
check(all == inherited("Leaf"), "normal properties reuse cached list")
check(all == inherited("Leaf", false), "nil and false select same normal cache")
check(all[1] == leaf, "cache retains metadata object identity")
leaf.CanRead = false
check(inherited("Leaf")[1].CanRead == false, "cached properties preserve read metadata mutations")
local notSaveable = inherited("Leaf", true)
sameProperties(notSaveable, {nleaf, nmid, nbase}, "non-saveable ancestry")
check(notSaveable == inherited("Leaf", true), "non-saveable properties reuse their own cache")
check(notSaveable ~= all, "normal and non-saveable lists are separate")
local stopAtMid = inherited("Leaf", false, {"Mid"})
sameProperties(stopAtMid, {leaf}, "stop before immediate ancestor")
check(arrayCalls == 1, "stop dictionary built once per filtered call")
local stopAtBase = inherited("Leaf", false, {"Base"})
sameProperties(stopAtBase, {leaf, mid}, "stop before deeper ancestor")
check(arrayCalls == 2, "deep stop dictionary built once per filtered call")
sameProperties(inherited("Leaf", true, {"Mid"}), {nleaf}, "stop filter uses non-saveable properties")
check(arrayCalls == 3, "non-saveable stop dictionary built once")
sameProperties(inherited("Leaf", false, {}), {leaf, mid, base}, "empty stop list preserves complete ancestry")
check(all == inherited("Leaf") and notSaveable == inherited("Leaf", true), "filtered calls do not contaminate common caches")
local reader2 = makePropertyReader()
check(reader2("Leaf") ~= all, "new save has a fresh list cache")
sameProperties(reader2("Leaf"), {leaf, mid, base}, "new save retains property order")
local unknown = inherited("Unknown")
check(#unknown == 0 and unknown == inherited("Unknown"), "unknown classes cache empty property lists")
local function makeYieldHelpers(fail)
    local elapsed, waits = 0, 0
    local os = {clock = function() return elapsed end}
    local task = {wait = function()
        waits += 1
        if fail then error("thread cannot be yielded") end
    end}
'@
$yieldTail = @'
    return {
        due = yieldIfDue,
        wait = wait_for_render,
        advance = function(seconds) elapsed += seconds end,
        waits = function() return waits end,
    }
end
local scheduling = makeYieldHelpers(false)
scheduling.due()
check(scheduling.waits() == 0, "fresh helper does not yield immediately")
scheduling.advance(0.01)
scheduling.due()
check(scheduling.waits() == 0, "short work does not yield")
scheduling.advance(30)
scheduling.due()
check(scheduling.waits() == 1, "elapsed long work yields cooperatively")
scheduling.due()
check(scheduling.waits() == 1, "successful yield resets elapsed guard")
scheduling.advance(30)
scheduling.due()
check(scheduling.waits() == 2, "later due work yields again")
scheduling.advance(30)
scheduling.wait()
check(scheduling.waits() == 3, "explicit render wait uses cooperative task wait")
scheduling.due()
check(scheduling.waits() == 3, "explicit render wait resets elapsed guard")
local denied = makeYieldHelpers(true)
denied.advance(30)
local ok = pcall(denied.due)
check(ok and denied.waits() == 1, "non-yieldable thread failure remains protected")
denied.due()
check(denied.waits() == 1, "protected failure resets elapsed guard")
denied.advance(30)
ok = pcall(denied.due)
check(ok and denied.waits() == 2, "later protected failure also remains bounded")
check(makeYieldHelpers(false).waits() == 0, "new save has fresh scheduling state")
print("PASS: " .. checks .. " source-extracted performance regression assertions")
'@
[IO.File]::WriteAllText($Out, $head + "`n" + $inheritedHelpers + "`n" + $inheritTail + "`n" + $yieldHelpers + "`n" + $yieldTail)
Write-Output "Built $Out from $Repo/saveinstance.luau"
