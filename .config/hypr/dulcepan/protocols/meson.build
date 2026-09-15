wl_protocol_dir = wayland_protos.get_variable('pkgdatadir')
wayland_scanner = find_program('wayland-scanner')

wayland_scanner_code = generator(
  wayland_scanner,
  output: '@BASENAME@-protocol.c',
  arguments: ['private-code', '@INPUT@', '@OUTPUT@'],
)

wayland_scanner_client = generator(
  wayland_scanner,
  output: '@BASENAME@-protocol.h',
  arguments: ['client-header', '@INPUT@', '@OUTPUT@'],
)

client_protocols = [
  # cursor-shape-v1 dependency
  wl_protocol_dir / 'stable/tablet/tablet-v2.xml',
  wl_protocol_dir / 'stable/viewporter/viewporter.xml',
  # wlr-layer-shell-unstable-v1 dependency
  wl_protocol_dir / 'stable/xdg-shell/xdg-shell.xml',
  wl_protocol_dir / 'staging/cursor-shape/cursor-shape-v1.xml',
  # ext-image-capture-source-v1 dependency
  wl_protocol_dir / 'staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml',
  wl_protocol_dir / 'staging/ext-image-capture-source/ext-image-capture-source-v1.xml',
  wl_protocol_dir / 'staging/ext-image-copy-capture/ext-image-copy-capture-v1.xml',
  'wlr-layer-shell-unstable-v1.xml',
]

client_protos_src = []
client_protos_headers = []

foreach xml : client_protocols
  client_protos_src += wayland_scanner_code.process(xml)
  client_protos_headers += wayland_scanner_client.process(xml)
endforeach

lib_client_protos = static_library(
  'client_protos',
  client_protos_src + client_protos_headers,
  dependencies: [wayland_client]
)

client_protos = declare_dependency(
  link_with: lib_client_protos,
  sources: client_protos_headers,
)
