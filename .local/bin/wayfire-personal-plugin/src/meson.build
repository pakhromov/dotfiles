sources = ['personal.cpp']

personal_plugin = shared_module('personal', sources,
    dependencies: [wayfire],
    install: true, install_dir: join_paths(get_option('libdir'), 'wayfire'))

subdir('client')
