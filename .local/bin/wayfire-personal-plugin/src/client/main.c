/*
 * Minimal IPC client: connects to $WAYFIRE_SOCKET and calls
 * "personal/hide-cursor". No Python, no libraries beyond libc.
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>

static int write_all(int fd, const void *buf, size_t len)
{
    const char *p = buf;
    while (len > 0)
    {
        ssize_t n = write(fd, p, len);
        if (n <= 0)
        {
            return -1;
        }

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
        if (n <= 0)
        {
            return -1;
        }

        p   += n;
        len -= (size_t)n;
    }

    return 0;
}

int main(void)
{
    const char *sock_path = getenv("WAYFIRE_SOCKET");
    if (!sock_path)
    {
        fprintf(stderr, "WAYFIRE_SOCKET is not set. Is the 'ipc' plugin loaded?\n");
        return 1;
    }

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0)
    {
        perror("socket");
        return 1;
    }

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

    static const char msg[] = "{\"method\":\"personal/hide-cursor\",\"data\":{}}";
    uint32_t len = (uint32_t)strlen(msg);

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
    if (!resp)
    {
        close(fd);
        return 1;
    }

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
    if (is_error)
    {
        fprintf(stderr, "%s\n", resp);
    }

    free(resp);
    return is_error ? 1 : 0;
}
