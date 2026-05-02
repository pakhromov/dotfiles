CC      = cc
CFLAGS  = -O2 -Wall $(shell pkg-config --cflags wayland-client)
LDFLAGS = $(shell pkg-config --libs wayland-client)
PROTO   = /usr/share/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml
PROTO_H = wlr-layer-shell-unstable-v1-client-protocol.h
PROTO_C = wlr-layer-shell-unstable-v1-protocol.c

all: waypixel

waypixel: waypixel.c $(PROTO_H) $(PROTO_C)
	$(CC) $(CFLAGS) -o $@ waypixel.c $(PROTO_C) $(LDFLAGS)

$(PROTO_H): $(PROTO)
	wayland-scanner client-header $< $@

$(PROTO_C): $(PROTO)
	wayland-scanner private-code $< $@

clean:
	rm -f waypixel $(PROTO_H) $(PROTO_C)

.PHONY: all clean
