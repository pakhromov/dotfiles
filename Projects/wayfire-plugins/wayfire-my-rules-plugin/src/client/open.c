/*
 * open [-w RC] [--single-app-id V | --single-title V] [--exclude-title V] [-e]
 *      <command> [args...]
 *
 * Launch-or-focus helper for the my-rules Wayfire plugin.
 *
 *   -w RC            Workspace to open the app on: two digits, 1-based,
 *                    first digit = row, second = column (12 = row 1, col 2).
 *   --single-app-id V  If a window whose app_id matches V exists, focus it
 *                      and exit instead of launching.
 *   --single-title V   Same, but match by window title.
 *   --exclude-title V  Skip candidates whose title contains V.
 *   -e               Match exactly instead of by substring.
 *
 * If no existing window is found (or no --single-* flag is given), the
 * target workspace is focused first, my-rules is told to leave the next
 * window alone, and only then is <command> spawned - so the window simply
 * maps on the right workspace. No waiting, no polling.
 *
 * Examples:
 *   open -w 12 --single-app-id firefox --exclude-title "Private Browsing" firefox
 *   open -w 13 --single-title "Private Browsing" firefox --private-window
 */
#include <ctype.h>
#include <fcntl.h>
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

static int ipc_connect(void)
{
    const char *sock_path = getenv("WAYFIRE_SOCKET");
    if (!sock_path)
    {
        fprintf(stderr, "WAYFIRE_SOCKET is not set. Is the 'ipc' plugin loaded?\n");
        return -1;
    }

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); return -1; }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, sock_path, sizeof(addr.sun_path) - 1);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0)
    {
        perror("connect");
        close(fd);
        return -1;
    }

    return fd;
}

/* Appends src to dst as a JSON string body, escaping '"' and '\'.
 * Returns new write position, or -1 on overflow. */
static int json_escape_append(char *dst, size_t cap, int pos, const char *src)
{
    for (; *src; src++)
    {
        if ((size_t)pos + 2 >= cap) return -1;
        if ((*src == '"') || (*src == '\\'))
        {
            dst[pos++] = '\\';
        }
        dst[pos++] = *src;
    }
    dst[pos] = '\0';
    return pos;
}

/* Sends one request, returns malloc'd response body (NUL-terminated), or NULL. */
static char *ipc_call(const char *msg)
{
    int fd = ipc_connect();
    if (fd < 0) return NULL;

    uint32_t len = (uint32_t)strlen(msg);
    if (write_all(fd, &len, sizeof(len)) != 0 || write_all(fd, msg, len) != 0)
    {
        perror("write");
        close(fd);
        return NULL;
    }

    uint32_t resp_len;
    if (read_all(fd, &resp_len, sizeof(resp_len)) != 0)
    {
        perror("read header");
        close(fd);
        return NULL;
    }

    char *resp = malloc((size_t)resp_len + 1);
    if (!resp) { close(fd); return NULL; }

    if (read_all(fd, resp, resp_len) != 0)
    {
        perror("read body");
        free(resp);
        close(fd);
        return NULL;
    }

    resp[resp_len] = '\0';
    close(fd);
    return resp;
}

static void usage(void)
{
    fprintf(stderr,
        "Usage: open [-w RC] [--single-app-id V | --single-title V]\n"
        "            [--exclude-title V] [-e] <command> [args...]\n");
}

int main(int argc, char *argv[])
{
    int row = 0, col = 0;
    const char *single_app_id = NULL;
    const char *single_title  = NULL;
    const char *exclude_title = NULL;
    int exact = 0;

    int i = 1;
    for (; i < argc; i++)
    {
        if (strcmp(argv[i], "-w") == 0 && i + 1 < argc)
        {
            const char *ws = argv[++i];
            if (strlen(ws) != 2 || !isdigit(ws[0]) || !isdigit(ws[1]) ||
                ws[0] == '0' || ws[1] == '0')
            {
                fprintf(stderr, "open: -w takes two 1-based digits (row, column), e.g. 12\n");
                return 1;
            }
            row = ws[0] - '0';
            col = ws[1] - '0';
        }
        else if (strcmp(argv[i], "--single-app-id") == 0 && i + 1 < argc)
        {
            single_app_id = argv[++i];
        }
        else if (strcmp(argv[i], "--single-title") == 0 && i + 1 < argc)
        {
            single_title = argv[++i];
        }
        else if (strcmp(argv[i], "--exclude-title") == 0 && i + 1 < argc)
        {
            exclude_title = argv[++i];
        }
        else if (strcmp(argv[i], "-e") == 0)
        {
            exact = 1;
        }
        else
        {
            break; /* start of the command */
        }
    }

    char **command = &argv[i];
    int command_len = argc - i;

    if (single_app_id && single_title)
    {
        fprintf(stderr, "open: --single-app-id and --single-title are mutually exclusive\n");
        return 1;
    }

    if (command_len == 0 && !single_app_id && !single_title)
    {
        usage();
        return 1;
    }

    char msg[1024];
    int pos;

    /* 1. Focus an existing window, if requested */
    if (single_app_id || single_title)
    {
        pos = snprintf(msg, sizeof(msg),
            "{\"method\":\"my-rules/focus-existing\",\"data\":{\"by\":\"%s\",\"exact\":%s,\"value\":\"",
            single_app_id ? "app_id" : "title", exact ? "true" : "false");
        pos = json_escape_append(msg, sizeof(msg), pos,
            single_app_id ? single_app_id : single_title);
        if (pos < 0) { fprintf(stderr, "open: arguments too long\n"); return 1; }

        if (exclude_title)
        {
            pos += snprintf(msg + pos, sizeof(msg) - pos, "\",\"exclude-title\":\"");
            pos  = json_escape_append(msg, sizeof(msg), pos, exclude_title);
            if (pos < 0) { fprintf(stderr, "open: arguments too long\n"); return 1; }
        }

        snprintf(msg + pos, sizeof(msg) - pos, "\"}}");

        char *resp = ipc_call(msg);
        if (!resp) return 1;

        if (strstr(resp, "\"error\""))
        {
            fprintf(stderr, "%s\n", resp);
            free(resp);
            return 1;
        }

        int found = strstr(resp, "\"found\":true") != NULL ||
                    strstr(resp, "\"found\": true") != NULL;
        free(resp);
        if (found)
        {
            return 0;
        }

        if (command_len == 0)
        {
            fprintf(stderr, "open: no matching window and no command to launch\n");
            return 1;
        }
    }

    /* 2. Switch workspace + claim the upcoming window */
    if (row > 0)
    {
        snprintf(msg, sizeof(msg),
            "{\"method\":\"my-rules/prepare-open\",\"data\":{\"row\":%d,\"col\":%d}}", row, col);
    }
    else
    {
        snprintf(msg, sizeof(msg), "{\"method\":\"my-rules/prepare-open\",\"data\":{}}");
    }

    char *resp = ipc_call(msg);
    if (!resp) return 1;
    if (strstr(resp, "\"error\""))
    {
        fprintf(stderr, "%s\n", resp);
        free(resp);
        return 1;
    }
    free(resp);

    /* 3. Spawn detached */
    pid_t pid = fork();
    if (pid < 0)
    {
        perror("fork");
        return 1;
    }

    if (pid == 0)
    {
        setsid();
        int devnull = open("/dev/null", O_RDWR);
        if (devnull >= 0)
        {
            dup2(devnull, STDIN_FILENO);
            dup2(devnull, STDOUT_FILENO);
            dup2(devnull, STDERR_FILENO);
            if (devnull > STDERR_FILENO)
            {
                close(devnull);
            }
        }

        execvp(command[0], command);
        _exit(127);
    }

    return 0;
}
