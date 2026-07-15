sources = ['my-rules.cpp']

my_rules_plugin = shared_module('my-rules', sources,
    dependencies: [wayfire],
    install: true, install_dir: join_paths(get_option('libdir'), 'wayfire'))

subdir('client')
