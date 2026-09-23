#import "PatternScanner.h"
#include <mach/mach.h>
#include <string.h>
namespace PS {
static inline int hexc(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    return -1;
}
static bool compile(const char *sig, uint8_t *bytes, uint8_t *mask, size_t *len) {
    size_t n = 0; const char *p = sig;
    while (*p) {
        while (*p == ' ') p++;
        if (!*p) break;
        if (*p == '?' || *p == 'x' || *p == 'X') {
            bytes[n] = 0; mask[n] = 0; n++;
            while (*p && *p != ' ') p++;
        } else {
            int hi = hexc(p[0]); int lo = hexc(p[1]);
            if (hi < 0 || lo < 0) return false;
            bytes[n] = (hi << 4) | lo; mask[n] = 0xFF; n++;
            p += 2;
        }
    }
    *len = n; return n > 0;
}
static uintptr_t scanRange(const uint8_t *base, size_t size,
                           const uint8_t *bytes, const uint8_t *mask, size_t len) {
    if (size < len) return 0;
    for (size_t i = 0; i <= size - len; i++) {
        bool ok = true;
        for (size_t j = 0; j < len; j++) if (mask[j] && base[i + j] != bytes[j]) { ok = false; break; }
        if (ok) return (uintptr_t)(base + i);
    }
    return 0;
}
static uintptr_t scanImage(const struct mach_header_64 *hdr, intptr_t slide, const char *sig) {
    uint8_t bytes[512]; uint8_t mask[512]; size_t len;
    if (!compile(sig, bytes, mask, &len)) return 0;
    if (len > sizeof(bytes)) return 0;
    const uint8_t *base = (const uint8_t *)hdr;
    const struct load_command *lc = (const struct load_command *)(base + sizeof(struct mach_header_64));
    for (uint32_t i = 0; i < hdr->ncmds && lc; i++) {
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strcmp(seg->segname, "__TEXT") == 0) {
                uintptr_t segAddr = (uintptr_t)seg->vmaddr + slide;
                uintptr_t r = scanRange((const uint8_t *)segAddr, seg->vmsize, bytes, mask, len);
                if (r) return r;
            }
        }
        lc = (const struct load_command *)((uint8_t *)lc + lc->cmdsize);
    }
    return 0;
}
uintptr_t scanMain(const char *sig) {
    const struct mach_header_64 *hdr = (const struct mach_header_64 *)_dyld_get_image_header(0);
    return scanImage(hdr, _dyld_get_image_vmaddr_slide(0), sig);
}
uintptr_t scanAll(const char *sig) {
    uint32_t n = _dyld_image_count();
    for (uint32_t i = 0; i < n; i++) {
        const struct mach_header_64 *hdr = (const struct mach_header_64 *)_dyld_get_image_header(i);
        uintptr_t r = scanImage(hdr, _dyld_get_image_vmaddr_slide(i), sig);
        if (r) return r;
    }
    return 0;
}
}
