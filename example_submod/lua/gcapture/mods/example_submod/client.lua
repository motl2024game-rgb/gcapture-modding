-- client.lua: runs once on every client after the whole GCapture core is loaded
hook.Add("GCapture_ModsLoaded", "example_submod", function()
    print("[example_submod] loaded on client")
end)
