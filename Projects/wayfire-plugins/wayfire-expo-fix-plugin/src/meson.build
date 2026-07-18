sources = ['expo-fix.cpp', 'expo-fix-wall.cpp']

deps = [wayfire]
if glm.found()
	deps += glm
endif

expo_fix_plugin = shared_module('expo-fix', sources,
    dependencies: deps,
    install: true, install_dir: join_paths(get_option('libdir'), 'wayfire'))
