function openURL()
   local r = mp.command_native({
      name = "subprocess",
      args = { "wl-paste" },
      playback_only = false,
      capture_stdout = true,
      capture_stderr = true
   })

   if r.status < 0 then
      mp.osd_message("Failed getting clipboard data!")
      return
   end

   local url = r.stdout and r.stdout:match("^%s*(%S+)%s*$")

   if not url or url == "" then
      mp.osd_message("Clipboard empty")
      return
   end

   mp.osd_message("Opening URL:\n" .. url)
   mp.commandv("loadfile", url, "replace")
end

mp.add_key_binding("ctrl+v", openURL)
