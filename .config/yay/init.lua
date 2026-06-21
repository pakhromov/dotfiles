yay.opt.build_dir = "/tmp/yay-pavel" -- Build/cache directory for AUR packages.
yay.opt.clean_after = true -- Remove untracked files after install.
yay.opt.redownload = "no" -- PKGBUILD download mode: "no" | "yes" | "all".
yay.opt.rebuild = "no" -- Build mode: "no" | "yes" | "tree" | "all".
yay.opt.keep_src = false -- Keep pkg/ and src/ after successful builds.
yay.opt.remove_make = "yes" -- Remove makedepends mode: "no" | "yes" | "ask" | "askyes".
yay.opt.answer_clean = "None" --  yay v13.0.1+ Pre-select clean menu answer: "" | "All" | "None" | "Installed" | "NotInstalled" (also accepts menu syntax: ranges, ^n, "abort").
yay.opt.answer_diff = "None" --  yay v13.0.1+ Pre-select diff menu answer: "" | "All" | "None" | "Installed" | "NotInstalled" (also accepts menu syntax: ranges, ^n, "abort").
yay.opt.answer_edit = "None" --  yay v13.0.1+ Pre-select edit menu answer: "" | "All" | "None" | "Installed" | "NotInstalled" (also accepts menu syntax: ranges, ^n, "abort").
yay.opt.mflags = "--skippgpcheck" -- Extra flags passed to makepkg.
yay.opt.pgp_fetch = false -- Prompt to import unknown PGP keys from validpgpkeys.
yay.opt.sudo_loop = true -- Keep sudo session alive in the background during long builds
yay.opt.double_confirm = false -- Ask for confirmation before and after builds during upgrades.


--yay.opt.editor = os.getenv("EDITOR") or os.getenv("VISUAL") or "vi" -- Editor command used for PKGBUILD edits; empty uses VISUAL/EDITOR.
--yay.opt.editor_flags = "" -- Extra flags passed to the editor command.
--yay.opt.sort_by = "" -- AUR search sort field: "votes" | "popularity" | "name" | "base" | "submitted" | "modified" | "".
--yay.opt.search_by = "name-desc" -- AUR search field: "name" | "name-desc" | "maintainer" | "submitter" | "depends" | "makedepends" | "optdepends" | "checkdepends" | "provides" | --"conflicts" | "replaces" | "groups" | "keywords" | "comaintainers".
--yay.opt.request_split_n = 150 -- Max packages per AUR RPC request (use values > 0).
--yay.opt.completion_refresh_time = 7 -- Completion cache refresh days: -1 (never), 0 (always), >0 (every N days).
--yay.opt.max_concurrent_downloads = 1 -- Parallel PKGBUILD source downloads; 0 uses CPU count.
--yay.opt.bottom_up = true -- Show AUR packages before repo packages in mixed results.
--yay.opt.devel = false -- Check development/VCS packages on sysupgrade.
--yay.opt.provides = true -- Resolve matching providers when dependencies are ambiguous.
--yay.opt.clean_menu = true -- Show pre-build clean menu.
--yay.opt.diff_menu = true -- Show diff menu before building.
--yay.opt.edit_menu = false -- Show PKGBUILD edit menu before building.
--yay.opt.combined_upgrade = true -- Use combined repo+AUR upgrade flow on sysupgrade.
--yay.opt.use_ask = false -- Use pacman's --ask to auto-confirm known conflicts.
--yay.opt.batch_install = false -- Queue AUR package installs instead of installing each package immediately.
--yay.opt.separate_sources = true -- Separate query results by source (repo vs AUR).
--yay.opt.rpc = true -- Use AUR RPC for dependency/query operations.

