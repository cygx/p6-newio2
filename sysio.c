#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define EXPORT __declspec(dllexport)

EXPORT uint64_t sysio_error(void *buffer, uint64_t size);
EXPORT int64_t sysio_open(const void *path, uint64_t mode);
EXPORT int64_t sysio_stdhandle(uint32_t id);
EXPORT int64_t sysio_read(int64_t fd, void *buffer,
    uint64_t offset, uint64_t count);
EXPORT void sysio_copy(void *dst, const void *src,
    uint64_t dstpos, uint64_t srcpos, uint64_t count);
EXPORT void sysio_move(void *dst, const void *src,
    uint64_t dstpos, uint64_t srcpos, uint64_t count);
EXPORT int64_t sysio_getsize(int64_t fd);
EXPORT int64_t sysio_getpos(int64_t fd);
EXPORT int64_t sysio_close(uint64_t fd);

enum {
    NEWIO_READ      = 1 << 0,
    NEWIO_WRITE     = 1 << 1,
    NEWIO_APPEND    = 1 << 2,
    NEWIO_CREATE    = 1 << 3,
    NEWIO_EXCLUSIVE = 1 << 4,
    NEWIO_TRUNCATE  = 1 << 5,
};

uint64_t sysio_error(void *buffer, uint64_t size)
{
    DWORD n = FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM, NULL, GetLastError(),
        LANG_USER_DEFAULT, buffer, (DWORD)(size / 2), NULL);

    return n * 2;
}

int64_t sysio_open(const void *path,  uint64_t mode)
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

int64_t sysio_stdhandle(uint32_t id)
{
    HANDLE fh = GetStdHandle((DWORD)-(10 + id));
    return (intptr_t)fh;
}

int64_t sysio_read(int64_t fd, void *buffer, uint64_t offset, uint64_t count)
{
    if(count > (DWORD)-1) {
        SetLastError(ERROR_INVALID_PARAMETER);
        return -1;
    }

    DWORD read;
    HANDLE fh = (HANDLE)(intptr_t)fd;
    BOOL ok = ReadFile(fh, (char *)buffer + offset, (DWORD)count, &read, NULL);

    return ok ? read : -1;
}

void sysio_copy(void *dst, const void *src,
    uint64_t dstpos, uint64_t srcpos, uint64_t count)
{
    memcpy((char *)dst + dstpos, (const char *)src + srcpos, (size_t)count);
}

void sysio_move(void *dst, const void *src,
    uint64_t dstpos, uint64_t srcpos, uint64_t count)
{
    memmove((char *)dst + dstpos, (const char *)src + srcpos, (size_t)count);
}

int64_t sysio_getsize(int64_t fd)
{
    HANDLE fh = (HANDLE)(intptr_t)fd;
    LARGE_INTEGER size;
    BOOL ok = GetFileSizeEx(fh, &size);
    return ok ? size.QuadPart : -1;
}

int64_t sysio_getpos(int64_t fd)
{
    HANDLE fh = (HANDLE)(intptr_t)fd;
    static const LARGE_INTEGER ZERO;
    LARGE_INTEGER pos;
    BOOL ok = SetFilePointerEx(fh, ZERO, &pos, FILE_CURRENT);
    return ok ? pos.QuadPart : -1;
}

int64_t sysio_close(uint64_t fd)
{
    HANDLE fh = (HANDLE)(intptr_t)fd;
    BOOL ok = CloseHandle(fh);
    return ok ? 0 : -1;
}
