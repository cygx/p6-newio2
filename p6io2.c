#include <windows.h>
#include <stdint.h>
#include <string.h>

#define EXPORT __declspec(dllexport)

struct buffer
{
    uint8_t *bytes;
    uint32_t size;
    uint32_t pos;
};

struct dynbuffer
{
    union {
        struct buffer buffer;
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
EXPORT int64_t p6io2_stdhandle(uint32_t id);
EXPORT int32_t p6io2_close(int64_t fd);
EXPORT uint32_t p6io2_read(int64_t fd, struct buffer *buf, uint32_t n);

uint32_t p6io2_oserror(void *bytes, uint32_t size)
{
    DWORD n = FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM, NULL, GetLastError(),
        LANG_USER_DEFAULT, bytes, (DWORD)(size / 2), NULL);

    return n * 2;
}

int64_t p6io2_stdhandle(uint32_t id)
{
    HANDLE fh = GetStdHandle((DWORD)-(10 + id));
    return (intptr_t)fh;
}

int32_t p6io2_close(int64_t fd)
{
    HANDLE fh = (HANDLE)(intptr_t)fd;
    BOOL ok = CloseHandle(fh);
    return ok ? 0 : -1;   
}

uint32_t p6io2_read(int64_t fd, struct buffer *buf, uint32_t n)
{
    DWORD read;
    HANDLE fh = (HANDLE)(intptr_t)fd;
    BOOL ok = ReadFile(fh, buf->bytes + buf->pos, n, &read, NULL);
    if(!ok) return (uint32_t)-1;

    buf->pos += read;
    return read;
}
