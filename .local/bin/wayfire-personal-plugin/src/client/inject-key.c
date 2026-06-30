/*
 * inject-key <KEY_NAME> [MOD_NAME ...]
 * Sends personal/inject-key to Wayfire via $WAYFIRE_SOCKET.
 * Key names use the Linux input event convention: KEY_ESC, KEY_V, etc.
 * Examples:
 *   inject-key KEY_ESC
 *   inject-key KEY_V KEY_LEFTCTRL
 *   inject-key KEY_V KEY_LEFTCTRL KEY_LEFTALT
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <libevdev/libevdev.h>

static int write_all(int fd, const void *buf, size_t len)
{
    const char *p = buf;
    while (len > 0)
    {
        ssize_t n = write(fd, p, len);
        if (n <= 0) return -1;
        p   += n;
        len -= (size_t)n;
    }
    return 0;
}

static int read_all(int fd, void *buf, size_t len)
{
    char *p = buf;
    while (len > 0)
    {
        ssize_t n = read(fd, p, len);
        if (n <= 0) return -1;
        p   += n;
        len -= (size_t)n;
    }
    return 0;
}

int main(int argc, char *argv[])
{
    if (argc < 2)
    {
        fprintf(stderr, "Usage: inject-key <KEY_NAME> [MOD_NAME ...]\n");
        fprintf(stderr, "Example: inject-key KEY_V KEY_LEFTCTRL\n");
        return 1;
    }

    int keycode = libevdev_event_code_from_name(EV_KEY, argv[1]);
    if (keycode < 0)
    {
        fprintf(stderr, "Unknown key: %s\n", argv[1]);
        return 1;
    }

    int modcodes[16];
    int nmod = argc - 2;
    if (nmod > 16) nmod = 16;
    for (int i = 0; i < nmod; i++)
    {
        modcodes[i] = libevdev_event_code_from_name(EV_KEY, argv[2 + i]);
        if (modcodes[i] < 0)
        {
            fprintf(stderr, "Unknown key: %s\n", argv[2 + i]);
            return 1;
        }
    }

    const char *sock_path = getenv("WAYFIRE_SOCKET");
    if (!sock_path)
    {
        fprintf(stderr, "WAYFIRE_SOCKET is not set. Is the 'ipc' plugin loaded?\n");
        return 1;
    }

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); return 1; }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path) - 1);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0)
    {
        perror("connect");
        close(fd);
        return 1;
    }

    char msg[256];
    int pos = snprintf(msg, sizeof(msg),
        "{\"method\":\"personal/inject-key\",\"data\":{\"keycode\":%d", keycode);

    if (nmod > 0)
    {
        pos += snprintf(msg + pos, sizeof(msg) - pos, ",\"modifiers\":[");
        for (int i = 0; i < nmod; i++)
            pos += snprintf(msg + pos, sizeof(msg) - pos, "%s%d", i ? "," : "", modcodes[i]);
        pos += snprintf(msg + pos, sizeof(msg) - pos, "]");
    }

    pos += snprintf(msg + pos, sizeof(msg) - pos, "}}");

    uint32_t len = (uint32_t)pos;
    if (write_all(fd, &len, sizeof(len)) != 0 || write_all(fd, msg, len) != 0)
    {
        perror("write");
        close(fd);
        return 1;
    }

    uint32_t resp_len;
    if (read_all(fd, &resp_len, sizeof(resp_len)) != 0)
    {
        perror("read header");
        close(fd);
        return 1;
    }

    char *resp = malloc(resp_len + 1);
    if (!resp) { close(fd); return 1; }

    if (read_all(fd, resp, resp_len) != 0)
    {
        perror("read body");
        free(resp);
        close(fd);
        return 1;
    }

    resp[resp_len] = '\0';
    close(fd);

    int is_error = strstr(resp, "\"error\"") != NULL;
    if (is_error) fprintf(stderr, "%s\n", resp);

    free(resp);
    return is_error ? 1 : 0;
}
