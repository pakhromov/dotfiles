# dulcepan

A screenshot tool for Wayland compositors. Requires ext-image-capture-source-v1
and ext-image-copy-capture-v1 support.

Discuss in [#eclairs on Libera.Chat].

[#eclairs on Libera.Chat]: https://web.libera.chat/#eclairs

## Building

```sh
meson setup build/
ninja -C build/
```

## Configuration

dulcepan will try to load a configuration file from
`$XDG_CONFIG_DIRS/dulcepan.cfg`, which is a set of `key=value` pairs. See the
example configuration file `dulcepan.cfg` for more information.

## Usage

See `dulcepan -h`.

## License

GPL-3.0-only

See `LICENSE` for more information.

Copyright © 2026 Kirill Primak
