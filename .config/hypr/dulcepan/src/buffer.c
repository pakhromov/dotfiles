#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client-protocol.h>

#include "dulcepan.h"

static void fnv_1a_cont(uint64_t *h, const void *data, size_t len) {
	const uint8_t *bytes = data;
	for (size_t i = 0; i < len; i++) {
		*h = (*h * 0x00000100000001B3) ^ bytes[i];
	}
}

static void generate_name(char buffer[static 16]) {
	uint64_t h = 0xcbf29ce484222325;
	int pid = getpid();
	fnv_1a_cont(&h, &pid, sizeof(pid));
	struct timespec ts;
	clock_gettime(CLOCK_REALTIME, &ts);
	fnv_1a_cont(&h, &ts.tv_sec, sizeof(&ts.tv_sec));
	fnv_1a_cont(&h, &ts.tv_nsec, sizeof(&ts.tv_nsec));
	for (size_t i = 16; i-- > 0;) {
		buffer[i] = "0123456789abcdef"[h & 0xF];
		h >>= 4;
	}
}

struct wl_buffer *dp_buffer_create(struct dp_state *state, int32_t width, int32_t height,
		int32_t stride, uint32_t format, void **data, size_t *size) {
	*size = (size_t)(stride * height);

	static const char template[] = "dulcepan-";
	char name[sizeof(template) + 16] = {0};
	memcpy(name, template, sizeof(template) - 1);
	generate_name(&name[sizeof(template) - 1]);

	int fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
	if (fd < 0) {
		dp_log_fatal("shm_open() failed");
	}
	shm_unlink(name);

	if (ftruncate(fd, (off_t)*size) < 0) {
		dp_log_fatal("ftruncate() failed");
	}

	struct wl_shm_pool *pool = wl_shm_create_pool(state->shm, fd, (int32_t)*size);
	*data = mmap(NULL, (size_t)*size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (data == MAP_FAILED) {
		dp_log_fatal("mmap() failed");
	}

	struct wl_buffer *buffer =
			wl_shm_pool_create_buffer(pool, 0, width, height, (int32_t)stride, format);

	wl_shm_pool_destroy(pool);
	close(fd);

	return buffer;
}
