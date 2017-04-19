#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define EXPORT __declspec(dllexport)

EXPORT uint64_t sysio_error(void *buffer, uint64_t size);
EXPORT int64_t sysio_open(const void *path, uint64_t mode);
EXPORT int64_t sysio_stdhandle(uint32_t id);

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
