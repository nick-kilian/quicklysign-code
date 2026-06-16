-- Hotkey: paste a clipboard image into a remote claude session over SSH.
--
-- Drop this into ~/.hammerspoon/init.lua (install Hammerspoon: brew install
-- --cask hammerspoon, then grant it Accessibility permission when prompted —
-- needed to simulate the paste keystroke). Reload Hammerspoon afterwards.
--
-- What it does on the hotkey (default ⌘⌃V):
--   1. runs scripts/paste-image.sh — captures the clipboard image, scp's it to
--      the workspace, and puts `@/home/coder/.clips/clip-<ts>.png` on the
--      clipboard;
--   2. on success, sends ⌘V so that `@path` lands in the focused input — i.e.
--      the claude prompt in your Warp/SSH tab. No second terminal window.
--
-- If the clipboard has no image, the script exits non-zero and nothing pastes
-- (you get a brief alert instead).

local PASTE_IMAGE = os.getenv("HOME") .. "/git/quicklysign-coder/scripts/paste-image.sh"

hs.hotkey.bind({ "cmd", "ctrl" }, "v", function()
  -- login shell so brew/pngpaste/scp/ssh are on PATH
  local t = hs.task.new("/bin/zsh", function(code, _stdout, stderr)
    if code == 0 then
      hs.eventtap.keyStroke({ "cmd" }, "v") -- paste the @path the script clipped
    else
      hs.alert.show("paste-image: " .. ((stderr or ""):gsub("%s+$", "")))
    end
  end, { "-lc", "'" .. PASTE_IMAGE .. "'" })
  t:start()
end)
