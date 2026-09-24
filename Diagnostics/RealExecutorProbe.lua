-- Real Executor capability probe for Re Adventures diagnostics
-- Read-only: does not hook, fire remotes, or modify game state.

local env = (getgenv and getgenv()) or _G

local function pick(name)
    local v = rawget(env, name)
    if type(v) == "function" then return v end

    local ok, fallback = pcall(function()
        return _G[name]
    end)
    if ok and type(fallback) == "function" then
        return fallback
    end

    return nil
end

local function nested(root, ...)
    local current = root
    for i = 1, select("#", ...) do
        if type(current) ~= "table" then return nil end
        current = rawget(current, select(i, ...))
    end
    return current
end

local debugTable = rawget(env, "debug") or debug

local capabilities = {
    executor = "Real / unknown version",
    decompile = type(pick("decompile")) == "function",
    getscriptbytecode = type(pick("getscriptbytecode")) == "function",
    getscriptclosure = type(pick("getscriptclosure")) == "function",
    getsenv = type(pick("getsenv")) == "function",
    getgc = type(pick("getgc")) == "function",
    getloadedmodules = type(pick("getloadedmodules")) == "function",
    getscripts = type(pick("getscripts")) == "function",
    getnilinstances = type(pick("getnilinstances")) == "function",
    getconnections = type(pick("getconnections")) == "function",
    hookfunction = type(pick("hookfunction")) == "function",
    hookmetamethod = type(pick("hookmetamethod")) == "function",
    getnamecallmethod = type(pick("getnamecallmethod")) == "function",
    writefile = type(pick("writefile")) == "function",
    readfile = type(pick("readfile")) == "function",
    makefolder = type(pick("makefolder")) == "function",
    setclipboard = type(pick("setclipboard")) == "function",
    debug_getconstants = type(debugTable) == "table" and type(nested(debugTable, "getconstants")) == "function",
    debug_getprotos = type(debugTable) == "table" and type(nested(debugTable, "getprotos")) == "function",
    debug_getupvalues = type(debugTable) == "table" and type(nested(debugTable, "getupvalues")) == "function",
}

local order = {
    "decompile",
    "getscriptbytecode",
    "getscriptclosure",
    "getsenv",
    "getgc",
    "getloadedmodules",
    "getscripts",
    "getnilinstances",
    "getconnections",
    "hookfunction",
    "hookmetamethod",
    "getnamecallmethod",
    "debug_getconstants",
    "debug_getprotos",
    "debug_getupvalues",
    "writefile",
    "readfile",
    "makefolder",
    "setclipboard",
}

print("========================================")
print(" REAL EXECUTOR CAPABILITY PROBE")
print("========================================")
for _, key in ipairs(order) do
    print(string.format("%-24s %s", key .. ":", tostring(capabilities[key])))
end
print("========================================")

local HttpService = game:GetService("HttpService")
local encoded = HttpService:JSONEncode(capabilities)

local writefileFn = pick("writefile")
local makefolderFn = pick("makefolder")
local isfolderFn = pick("isfolder")
local setclipboardFn = pick("setclipboard")

local path
if writefileFn then
    local folder = "CatEmpire"
    local diagnostics = folder .. "/Diagnostics"

    if makefolderFn then
        if not isfolderFn or not isfolderFn(folder) then
            pcall(makefolderFn, folder)
        end
        if not isfolderFn or not isfolderFn(diagnostics) then
            pcall(makefolderFn, diagnostics)
        end
    end

    path = diagnostics .. "/real_capabilities.json"
    local ok = pcall(writefileFn, path, encoded)
    if ok then
        print("[Probe] Saved:", path)
    else
        path = nil
    end
end

if not path and setclipboardFn then
    pcall(setclipboardFn, encoded)
    print("[Probe] JSON copied to clipboard.")
end

return capabilities
