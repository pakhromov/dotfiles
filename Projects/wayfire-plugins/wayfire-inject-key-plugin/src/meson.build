sources = ['inject-key.cpp']

inject_key_plugin = shared_module('inject-key', sources,
    dependencies: [wayfire],
    install: true, install_dir: join_paths(get_option('libdir'), 'wayfire'))

subdir('client')
