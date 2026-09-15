project(
  'dulcepan',
  'c',
  version: '1.0.3',
  license: 'GPL-3.0-only',
  default_options: [
    'c_std=c11',
    'warning_level=3',
  ],
)

add_project_arguments(
  [
    '-D_POSIX_C_SOURCE=200809L',
  ],
  language: 'c',
)

cc = meson.get_compiler('c')

big_endian = target_machine.endian() == 'big'

add_project_arguments(cc.get_supported_arguments([
  '-Wconversion',
  '-Wendif-labels',
  '-Wimplicit-fallthrough=2',
  '-Wlogical-op',
  '-Wmissing-include-dirs',
  '-Wmissing-prototypes',
  '-Wold-style-definition',
  '-Wpointer-arith',
  '-Woverflow',
  '-Wshadow',
  '-Wstrict-aliasing=2',
  '-Wstrict-prototypes',
  '-Wundef',

  '-Wno-unused-parameter',

  '-DDP_BIG_ENDIAN=@0@'.format(big_endian.to_int()),
]), language: 'c')

m = cc.find_library('m')

wayland_client = dependency('wayland-client')
wayland_protos = dependency('wayland-protocols', version: '>=1.37')

cairo = dependency('cairo')
pixman = dependency('pixman-1')
spng = dependency('spng', fallback: 'libspng')
xkbcommon = dependency(
  'xkbcommon',
  fallback: 'libxkbcommon',
  default_options: [
    'enable-tools=false',
    'enable-x11=false',
    'enable-docs=false',
    'enable-xkbregistry=false',
  ],
)

sfdo_basedir = dependency(
  'libsfdo-basedir',
  version: '>=0.1.0',
  fallback: 'libsfdo',
  default_options: [
    'default_library=static',
    'examples=false',
  ],
)

subdir('protocols')
subdir('src')

executable(
  meson.project_name(),
  src,
  dependencies: [
    client_protos,
    m,
    wayland_client,
    cairo,
    pixman,
    spng,
    xkbcommon,
    sfdo_basedir,
  ],
  install: true,
)

install_data(
  'dulcepan.cfg',
  install_dir: join_paths(get_option('sysconfdir'), 'xdg'),
)
