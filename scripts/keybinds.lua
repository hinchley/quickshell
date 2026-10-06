-- Lists every keybind declared in a Hyprland Lua config, one per line:
--   <keys><TAB><description>
--
-- The config is executed against a stub `hl` table that records hl.bind()
-- calls and ignores everything else, so loops and helper functions in the
-- config expand exactly as they do in Hyprland.
--
-- Usage: lua keybinds.lua <path-to-hyprland.lua>

local binds = {}

-- Stand-in for any hl.* value: indexable and callable, always yields another stub.
local stub
stub = setmetatable({}, {
  __index = function() return stub end,
  __call  = function() return stub end,
})

local hl = setmetatable({
  bind = function(keys, _, opts)
    binds[#binds + 1] = { keys = keys, description = type(opts) == "table" and opts.description or "" }
  end,
}, { __index = function() return stub end })

local path = arg[1]
if not path then
  io.stderr:write("usage: keybinds.lua <hyprland.lua>\n")
  os.exit(2)
end

local chunk, err = loadfile(path, "t", setmetatable({ hl = hl }, { __index = _G }))
if not chunk then
  io.stderr:write(err .. "\n")
  os.exit(1)
end

local ok, run_err = pcall(chunk)
if not ok then
  io.stderr:write(tostring(run_err) .. "\n")
  os.exit(1)
end

for _, bind in ipairs(binds) do
  local description = tostring(bind.description):gsub("%s+", " ")
  print(bind.keys .. "\t" .. description)
end
