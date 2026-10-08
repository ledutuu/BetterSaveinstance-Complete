-- Paste this entire file into a fresh Roblox executor session.
-- An optional chunk argument pins the raw repository root for both downloads.
local root = ... or "https://raw.githubusercontent.com/ledutuu/BetterSaveinstance-Complete/refs/heads/main/"
assert(type(writefile) == "function", "writefile is required for bootstrap logs")
local entries = {}
local function stage(message)
    table.insert(entries, tostring(os.clock()) .. " " .. message)
    print("[BSI_BOOT] " .. message)
    writefile("BSI_BOOT.log", table.concat(entries, "\n") .. "\n")
end
stage("before runner download: " .. root)
local ok, err = xpcall(function()
    local source = game:HttpGet(root .. "diagnose-volcano.luau", true)
    stage("before runner compilation")
    local runner, compileError = loadstring(source, "BSI diagnostic runner")
    assert(runner, compileError)
    stage("before runner execution")
    runner(root)
    stage("runner returned")
end, function(message) return debug.traceback(tostring(message)) end)
if not ok then stage("Luau error: " .. tostring(err)) end
