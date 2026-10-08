param([string]$Repo = "$PSScriptRoot/../..", [string]$Out = "$PSScriptRoot/discovery-regressions.luau")
$ErrorActionPreference = 'Stop'
$src = [IO.File]::ReadAllText((Join-Path $Repo 'saveinstance.luau')).Replace("`r`n", "`n")
$a = $src.IndexOf('local function resolveExecutorFunctions()')
$b = $src.IndexOf('local global_container', $a)
if ($a -lt 0 -or $b -lt 0) { throw 'Missing executor discovery helper' }
$helper = $src.Substring($a, $b - $a)
foreach($forbidden in @('HttpGet', 'loadstring', 'determineCalllimit', 'getgc', 'getreg')) {
    if ($helper.Contains($forbidden)) { throw "Discovery includes forbidden operation: $forbidden" }
}
$head = @'
local checks, calls, waits = 0, 0, 0
local fixtureRoot, fixtureFallback, shared, _G
local failRoot, failFallback = false, false
local time = 0
local os = {clock = function() time += 0.025; return time end}
local task = {wait = function() waits += 1 end}
local function check(condition, message)
    assert(condition, message)
    checks += 1
end
local function helperTrap()
    calls += 1
    error("Discovery must never invoke executor helpers")
end
local getgenv = function()
    if failRoot then error("getgenv fixture failure") end
    return fixtureRoot
end
local getfenv = function()
    if failFallback then error("getfenv fixture failure") end
    return fixtureFallback
end
local methods = {"base64encode", "gethiddenproperty", "gethui", "getnilinstances", "getscriptbytecode", "protectgui"}
local function reset(root, fallback, sharedRoot, globalRoot)
    fixtureRoot, fixtureFallback = root, fallback
    shared, _G = sharedRoot, globalRoot
    failRoot, failFallback = false, false
    calls, waits, time = 0, 0, 0
end
'@
$tail = @'
-- Canonical names are selected by identity, never called.
local canonical = {}
for _, method in methods do canonical[method] = helperTrap end
reset(canonical)
local resolved = resolveExecutorFunctions()
for _, method in methods do check(resolved[method] == helperTrap, "canonical: " .. method) end
check(calls == 0, "canonical helpers were invoked")

-- Canonical names across all roots outrank fuzzy aliases in the first root.
local alias = function() error("alias must not execute") end
reset({custom_get_hidden_prop = alias}, {gethiddenproperty = helperTrap})
resolved = resolveExecutorFunctions()
check(resolved.gethiddenproperty == helperTrap, "canonical must outrank fuzzy alias across roots")
check(calls == 0, "cross-root helpers were invoked")
reset({gethiddenproperty = alias}, {gethiddenproperty = helperTrap})
check(resolveExecutorFunctions().gethiddenproperty == alias, "first canonical root wins")

-- Supported nested aliases preserve the old name matching rules.
reset({api = {
    custom_base64_encode = helperTrap,
    custom_get_hidden_prop = helperTrap,
    get_h_ui = helperTrap,
    get_nil_instances = helperTrap,
    get_script_bytecode = helperTrap,
    custom_protectgui = helperTrap,
}})
resolved = resolveExecutorFunctions()
for _, method in methods do check(resolved[method] == helperTrap, "nested alias: " .. method) end
check(calls == 0, "nested helpers were invoked")
reset({base64 = {encode = helperTrap}})
check(resolveExecutorFunctions().base64encode == helperTrap, "base64 parent context")
reset({gethiddenproperties = helperTrap, getscriptbytecodes = helperTrap, unprotectgui = helperTrap})
resolved = resolveExecutorFunctions()
check(resolved.gethiddenproperty == nil, "reject plural hidden-property alias")
check(resolved.getscriptbytecode == helperTrap, "retain original plural bytecode alias matching")
check(resolved.protectgui == nil, "reject unprotectgui")

reset({protect_ui = helperTrap})
check(resolveExecutorFunctions().protectgui == helperTrap, "retain protect_ui alias")
-- Missing/invalid roots and getter failures allow available roots to work.
reset(false, 3, {gethui = helperTrap}, {protectgui = helperTrap})
resolved = resolveExecutorFunctions()
check(resolved.gethui == helperTrap and resolved.protectgui == helperTrap, "invalid roots")
reset({}, {}, {getnilinstances = helperTrap})
failRoot, failFallback = true, true
check(resolveExecutorFunctions().getnilinstances == helperTrap, "failed environment getters")

-- Cycles terminate, and the first search remains bounded by depth ten.
local cycle = {}
cycle.self = cycle
cycle.api = {get_h_ui = helperTrap}
reset(cycle)
check(resolveExecutorFunctions().gethui == helperTrap, "cyclic roots")
local function nested(depth)
    local root, cursor = {}, nil
    cursor = root
    for _ = 2, depth do
        local child = {}
        cursor.child = child
        cursor = child
    end
    cursor.get_h_ui = helperTrap
    return root
end
reset(nested(10))
check(resolveExecutorFunctions().gethui == helperTrap, "depth ten included")
reset(nested(11))
check(resolveExecutorFunctions().gethui == nil, "depth eleven excluded")

-- A table reached deeply must be revisited from a shallower root.
local deep, cursor = {}, nil
cursor = deep
for _ = 2, 9 do
    local child = {}
    cursor.child = child
    cursor = child
end
local sharedTable = {nested = {get_h_ui = helperTrap}}
cursor.child = sharedTable -- first reached at depth ten
reset(deep, sharedTable)
check(resolveExecutorFunctions().gethui == helperTrap, "shared table revisited from shallow root")

-- Stringifying arbitrary table keys must not invoke hostile metamethods.
local poison = setmetatable({}, {__tostring = function() error("key tostring called") end})
reset({[poison] = helperTrap, api = {get_h_ui = helperTrap}})
local ok, safe = pcall(resolveExecutorFunctions)
check(ok and safe.gethui == helperTrap, "non-string keys cannot run tostring metamethods")

-- Large missing-name searches cooperate with the task scheduler.
local large = {}
for i = 1, 100 do large["value_" .. i] = i end
reset(large)
resolveExecutorFunctions()
check(waits > 0, "large search should yield")
check(calls == 0, "discovery cannot invoke helper functions")
print("PASS: " .. checks .. " source-extracted executor discovery assertions")
'@
[IO.File]::WriteAllText($Out, $head + "`n" + $helper + "`n" + $tail)
