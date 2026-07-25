shared_module('my-activation',
    [
        'my-activation.cpp',
        'xdg-activation-v1-protocol.c',
    ],
    dependencies: [wayfire],
    include_directories: include_directories('.'),
    name_prefix: 'lib',
    install: true,
    install_dir: join_paths(get_option('libdir'), 'wayfire'),
    build_by_default: true,
)
