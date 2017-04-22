#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define EXPORT __declspec(dllexport)

enum {
    NEWIO_READ      = 1 << 0,
    NEWIO_WRITE     = 1 << 1,
    NEWIO_APPEND    = 1 << 2,
    NEWIO_CREATE    = 1 << 3,
    NEWIO_EXCLUSIVE = 1 << 4,
    NEWIO_TRUNCATE  = 1 << 5,
};

struct buffer
{
    uint8_t *bytes;
    uint32_t size;
    uint32_t pos;
};

struct dynbuffer
{
    union {
        struct buffer as_buffer;
        struct {
            uint8_t *bytes;
            uint32_t size;
            uint32_t pos;
            uint32_t blocksize;
            uint32_t limit;
        };
    };
};

EXPORT uint32_t p6io2_oserror(void *bytes, uint32_t size);
EXPORT intptr_t p6io2_stdhandle(uint32_t id);
EXPORT intptr_t p6io2_open(const void *path, uint32_t mode);
EXPORT int32_t p6io2_close(intptr_t fd);
EXPORT int64_t p6io2_getsize(intptr_t fd);
EXPORT int64_t p6io2_getpos(intptr_t fd);

EXPORT void p6io2_buffer_resize(struct buffer *buf, uint32_t size);
EXPORT void p6io2_buffer_discard(struct buffer *buf);
EXPORT int32_t p6io2_buffer_fill(struct buffer *buf, intptr_t fd, _Bool retry);
EXPORT void p6io2_buffer_shift(struct buffer *buf, uint32_t count);

EXPORT int32_t p6io2_dynbuffer_refill(
    struct dynbuffer *buf, intptr_t fd,  uint32_t n, _Bool retry);
EXPORT void p6io2_dynbuffer_drain(struct dynbuffer *src, struct buffer *dest);

uint32_t p6io2_oserror(void *bytes, uint32_t size)
{
    DWORD n = FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM, NULL, GetLastError(),
        LANG_USER_DEFAULT, bytes, (DWORD)(size / 2), NULL);

    return n * 2;
}

intptr_t p6io2_stdhandle(uint32_t id)
{
    HANDLE fh = GetStdHandle((DWORD)-(10 + id));
    return (intptr_t)fh;
}

intptr_t p6io2_open(const void *path, uint32_t mode)
{
    DWORD access = 0;
    DWORD disposition = 0;

    switch(mode & (NEWIO_READ | NEWIO_WRITE | NEWIO_APPEND)) {
        case 0:
        case NEWIO_READ:
        access = FILE_READ_DATA;
        break;

        case NEWIO_WRITE:
        access = FILE_WRITE_DATA;
        break;

        case NEWIO_READ | NEWIO_WRITE:
        access = FILE_READ_DATA | FILE_WRITE_DATA;
        break;

        case NEWIO_APPEND:
        case NEWIO_APPEND | NEWIO_WRITE:
        access = FILE_APPEND_DATA;
        break;

        case NEWIO_APPEND | NEWIO_READ:
        case NEWIO_APPEND | NEWIO_WRITE | NEWIO_READ:
        access = FILE_READ_DATA | FILE_APPEND_DATA;
        break;
    }

    switch(mode & (NEWIO_CREATE | NEWIO_EXCLUSIVE | NEWIO_TRUNCATE)) {
        case 0:
        disposition = OPEN_EXISTING;
        break;

        case NEWIO_CREATE:
        disposition = OPEN_ALWAYS;
        break;

        case NEWIO_CREATE | NEWIO_TRUNCATE:
        disposition = CREATE_ALWAYS;
        break;

        case NEWIO_EXCLUSIVE:
        case NEWIO_EXCLUSIVE | NEWIO_CREATE:
        case NEWIO_EXCLUSIVE | NEWIO_TRUNCATE:
        case NEWIO_EXCLUSIVE | NEWIO_CREATE | NEWIO_TRUNCATE:
        disposition = CREATE_NEW;
        break;

        case NEWIO_TRUNCATE:
        if(mode & NEWIO_APPEND) {
            SetLastError(ERROR_INVALID_PARAMETER);
            return (intptr_t)INVALID_HANDLE_VALUE;
        }
        disposition = TRUNCATE_EXISTING;
        access |= GENERIC_WRITE;
        break;
    }

    HANDLE fh = CreateFileW(path, access, 0, NULL, disposition,
        FILE_ATTRIBUTE_NORMAL, NULL);

    return (intptr_t)fh;
}

int32_t p6io2_close(intptr_t fd)
{
    HANDLE fh = (HANDLE)fd;
    BOOL ok = CloseHandle(fh);
    return ok ? 0 : -1;
}

int64_t p6io2_getsize(intptr_t fd)
{
    HANDLE fh = (HANDLE)fd;
    LARGE_INTEGER size;
    BOOL ok = GetFileSizeEx(fh, &size);
    return ok ? size.QuadPart : -1;
}

int64_t p6io2_getpos(intptr_t fd)
{
    HANDLE fh = (HANDLE)fd;
    static const LARGE_INTEGER ZERO;
    LARGE_INTEGER pos;
    BOOL ok = SetFilePointerEx(fh, ZERO, &pos, FILE_CURRENT);
    return ok ? pos.QuadPart : -1;
}

void p6io2_buffer_resize(struct buffer *buf, uint32_t size)
{
    buf->bytes = realloc(buf->bytes, size);
    buf->size = size;
}

void p6io2_buffer_discard(struct buffer *buf) {
    free(buf->bytes);
    buf->bytes = NULL;
    buf->size = 0;
}

static int32_t fill(struct buffer *buf, intptr_t fd, uint32_t n, _Bool retry)
{
    DWORD want = n;
    if(want == 0) return 1;

    HANDLE fh = (HANDLE)fd;
    DWORD read;

    if(retry) for(;;) {
        BOOL ok = ReadFile(fh, buf->bytes + buf->pos, want, &read, NULL);
        if(!ok) return -1;
        if(read == 0) return 0;

        buf->pos += read;
        want -= read;
        if(want == 0) return 1;
    }
    else {
        BOOL ok = ReadFile(fh, buf->bytes + buf->pos, want, &read, NULL);
        if(!ok) return -1;

        buf->pos += read;
        return read == want;
    }
}

void p6io2_buffer_shift(struct buffer *buf, uint32_t count)
{
    uint32_t rest = buf->pos - count;
    memmove(buf->bytes, buf->bytes + count, rest);
    buf->pos = rest;
}

static void dynresize(struct dynbuffer *buf)
{
    if(buf->size <= buf->limit) return;
    uint32_t bs = buf->blocksize;
    uint32_t size = ((buf->pos + bs - 1) / bs) * bs;
    buf->bytes = realloc(buf->bytes, size);
    buf->size = size;
}

int32_t p6io2_buffer_fill(struct buffer *buf, intptr_t fd, _Bool retry)
{
    return fill(buf, fd, buf->size - buf->pos, retry);
}

int32_t p6io2_dynbuffer_refill(
    struct dynbuffer *buf, intptr_t fd, uint32_t n, _Bool retry)
{
    if(n <= buf->pos) return 1;

    uint32_t bs = buf->blocksize;
    uint32_t want = ((n + bs - 1) / bs) * bs;

    if(want > buf->size) {
        buf->bytes = realloc(buf->bytes, want);
        buf->size = want;
    }

    int32_t rv = fill(&buf->as_buffer, fd, want - buf->pos, retry);
    if(rv != 1) dynresize(buf);
    return rv;
}

void p6io2_dynbuffer_drain(struct dynbuffer *src, struct buffer *dst)
{
    uint32_t available = src->pos;
    uint32_t missing = dst->size - dst->pos;
    uint32_t count = available < missing ? available : missing;
    if(count == 0) return;

    memcpy(dst->bytes + dst->pos, src->bytes, count);
    memmove(src->bytes, src->bytes + count, src->pos - count);
    dst->pos += count;
    src->pos -= count;

    dynresize(src);
}
