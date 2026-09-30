-- CAT EMPIRE - RE Adventures Use 10 Dump
-- Lightweight launcher for Diagnostics/RemoteLogger.lua.
-- Run this, click the native "Use 10" button once, then export the log.

local Env = (getgenv and getgenv()) or _G

local REMOTE_LOGGER_URL =
    "https://raw.githubusercontent.com/DanoninCat/DanoninScript/main/Diagnostics/RemoteLogger.lua"

local ok, api = pcall(function()
    return loadstring(game:HttpGet(REMOTE_LOGGER_URL, true))()
end)

if not ok then
    warn("[Use10Dump] Failed to start RemoteLogger:", api)
    return
end

local state = Env.__CAT_EMPIRE_REMOTE_LOGGER_STATE
local logger = state and state.api or api

if not logger then
    warn("[Use10Dump] RemoteLogger API unavailable")
    return
end

pcall(function()
    logger:Clear()
end)

pcall(function()
    logger:SetEndpointsOnly(true)
end)

pcall(function()
    logger:SetCaptureIncoming(false)
end)

pcall(function()
    logger:Start()
end)

print("============================================================")
print("[Use10Dump] READY")
print("[Use10Dump] 1. Open the same Star/Capsule shown in the inventory.")
print("[Use10Dump] 2. Click the game's native 'Use 10' button ONE time.")
print("[Use10Dump] 3. Wait about 2 seconds.")
print("[Use10Dump] 4. Run:")
print("getgenv().__CAT_EMPIRE_REMOTE_LOGGER_STATE.api:Stop()")
print("getgenv().__CAT_EMPIRE_REMOTE_LOGGER_STATE.api:Export()")
print("[Use10Dump] Send me the generated remote_log_*.txt file.")
print("============================================================")

local status
pcall(function()
    status = logger:Status()
end)

if status then
    print("[Use10Dump] Log file:", status.filePath or "memory/clipboard")
    print("[Use10Dump] InvokeServer hook:", tostring(
        status.directHooks and status.directHooks.invokeServer
    ))
end

return logger
