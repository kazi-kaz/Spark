#!/usr/bin/env python3
"""The JIT pool placeholder is handed back before the debugger places the pool.

2026-11-03, MX Bikes through Madeira Dock: the 1024MB and 512MB pool requests
both fell through to 0x7020000000 (the guest 64G window), were rejected three
times, and the pool ended up 256MB. A Dock session fills 256MB (services.exe,
five winedevice, plugplay, svchost, dockhost) and the app dies. The cause was
the up-to-1GB placeholder that JITAllocator.c holds above the exe window and
that nothing released, so the one hole big enough was never available to the
debugger's first-fit allocation.

Compiles the production functions between the madeira-pool-placeholder markers
in app/Madeira/JITAllocator.c against a small fake Mach address-space model and
checks release, settle and the free-hole scan, then checks that
StikJITHelper.allocatePool calls them in the right order. No device needed.
"""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
c_source = (ROOT / "app/Madeira/JITAllocator.c").read_text(encoding="utf-8").replace("\r\n", "\n")
swift = (ROOT / "app/Madeira/StikJITHelper.swift").read_text(encoding="utf-8").replace("\r\n", "\n")

begin = c_source.index("/* BEGIN madeira-pool-placeholder")
end = c_source.index("/* END madeira-pool-placeholder */")
production = c_source[begin:end]

MACH = r'''
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef unsigned long vm_address_t;
typedef unsigned long vm_size_t;
typedef int kern_return_t;
typedef unsigned int natural_t;
typedef unsigned int mach_msg_type_number_t;
typedef int mach_port_t;
typedef int vm_prot_t;
typedef int *vm_region_recurse_info_t;
typedef struct { int user_tag; int protection; } vm_region_submap_info_data_64_t;
#define KERN_SUCCESS 0
#define KERN_FAILURE 5
#define VM_FLAGS_FIXED 0
#define VM_PROT_NONE 0
#define VM_REGION_SUBMAP_INFO_COUNT_64 1
static mach_port_t mach_task_self(void) { return 1; }

/* Fake address space: sorted, non-overlapping [lo, hi) regions. */
#define MAXR 64
static struct { unsigned long lo, hi; } rg[MAXR];
static int nr;
static void fake_reset(void) { nr = 0; }
static int overlaps(unsigned long lo, unsigned long hi) {
    for (int i = 0; i < nr; i++) if (lo < rg[i].hi && hi > rg[i].lo) return 1;
    return 0;
}
static void fake_map(unsigned long lo, unsigned long n) {
    if (overlaps(lo, lo + n)) { printf("test setup overlap at %lx\n", lo); exit(2); }
    int i = nr++;
    while (i > 0 && rg[i - 1].lo > lo) { rg[i] = rg[i - 1]; i--; }
    rg[i].lo = lo; rg[i].hi = lo + n;
}
static int fake_mapped(unsigned long lo, unsigned long n) {
    unsigned long at = lo;
    for (int i = 0; i < nr && at < lo + n; i++) if (rg[i].lo <= at && rg[i].hi > at) at = rg[i].hi;
    return at >= lo + n;
}
static kern_return_t vm_allocate(mach_port_t t, vm_address_t *a, vm_size_t n, int flags) {
    if (overlaps(*a, *a + n)) return KERN_FAILURE;
    fake_map(*a, n); return KERN_SUCCESS;
}
static kern_return_t vm_deallocate(mach_port_t t, vm_address_t a, vm_size_t n) {
    /* Like Mach: any range inside one mapping may be freed; the mapping splits. */
    for (int i = 0; i < nr; i++) if (rg[i].lo <= a && rg[i].hi >= a + n) {
        unsigned long lo = rg[i].lo, hi = rg[i].hi;
        for (int j = i; j + 1 < nr; j++) rg[j] = rg[j + 1];
        nr--;
        if (lo < a) fake_map(lo, a - lo);
        if (hi > a + n) fake_map(a + n, hi - (a + n));
        return KERN_SUCCESS;
    }
    return KERN_FAILURE;
}
static kern_return_t vm_protect(mach_port_t t, vm_address_t a, vm_size_t n, int max, vm_prot_t p) { return KERN_SUCCESS; }
static kern_return_t vm_region_recurse_64(mach_port_t t, vm_address_t *a, vm_size_t *n, natural_t *depth,
                                          vm_region_recurse_info_t info, mach_msg_type_number_t *cnt) {
    for (int i = 0; i < nr; i++) if (rg[i].hi > *a) { *a = rg[i].lo > *a ? rg[i].lo : rg[i].lo; *n = rg[i].hi - rg[i].lo; return KERN_SUCCESS; }
    return KERN_FAILURE;
}
unsigned long madeira_early_window_base, madeira_early_window_size;
unsigned long madeira_early_pool_base, madeira_early_pool_size;
unsigned long madeira_early_intruder_base, madeira_early_intruder_size;
'''

MB = 1 << 20
TEST = r'''
#include <stdlib.h>
#define MB (1UL << 20)
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); return 1; } } while (0)

/* The 2026-11-03 map: image + heap below, pin chunk, 336MB hole, window, placeholder, then a
 * fully used band up to the guest window. */
static void layout(unsigned long placeholder) {
    fake_reset();
    fake_map(0x100000000UL, 0x2a000000UL - 0x0);            /* 0x100000000..0x12a000000 */
    fake_map(0x12a000000UL, 16 * MB);                       /* pin chunk */
    fake_map(0x140000000UL, 128 * MB);                      /* exe window */
    madeira_early_window_base = 0x140000000UL; madeira_early_window_size = 128 * MB;
    if (placeholder) {
        fake_map(0x148000000UL, placeholder);
        madeira_early_pool_base = 0x148000000UL; madeira_early_pool_size = placeholder;
    } else { madeira_early_pool_base = madeira_early_pool_size = 0; }
    fake_map(0x188000000UL + (1024 * MB - placeholder), 0x7020000000UL - 0x188000000UL);   /* everything above */
    madeira_early_pool_released = 0;
}

int main(void) {
    unsigned long sz, base;

    /* Before: only the 336MB hole below the window is usable, 512MB cannot fit. */
    layout(1024 * MB);
    base = madeira_largest_free_hole(0x119000000UL, 0x7000000000UL, &sz);
    CHECK(base == 0x12b000000UL && sz == 0x140000000UL - 0x12b000000UL);

    /* Releasing the bytes a 512MB pool needs opens a 512MB hole at the window's end. */
    CHECK(madeira_early_pool_release(512 * MB) == 512 * MB);
    base = madeira_largest_free_hole(0x119000000UL, 0x7000000000UL, &sz);
    CHECK(base == 0x148000000UL && sz == 512 * MB);
    /* A second release while one is pending does nothing. */
    CHECK(madeira_early_pool_release(256 * MB) == 0);

    /* The kernel takes the hole; the rest of the placeholder is still held and shrinks. */
    fake_map(0x148000000UL, 512 * MB);                       /* the pool itself */
    /* settle must not try to free the pool: it only re-holds uncovered bytes (none here). */
    int before = nr;
    madeira_early_pool_settle(0x148000000UL, 512 * MB);
    CHECK(nr == before);
    CHECK(madeira_early_pool_released == 0);
    CHECK(madeira_early_pool_base == 0x168000000UL && madeira_early_pool_size == 512 * MB);

    /* A request bigger than the placeholder is refused and nothing changes. */
    layout(700 * MB);
    CHECK(madeira_early_pool_release(1024 * MB) == 0);
    CHECK(fake_mapped(0x148000000UL, 700 * MB));
    base = madeira_largest_free_hole(0x119000000UL, 0x7000000000UL, &sz);
    CHECK(sz < 1024 * MB);

    /* Failure: the whole hold comes back. */
    layout(1024 * MB);
    CHECK(madeira_early_pool_release(512 * MB) == 512 * MB);
    CHECK(!fake_mapped(0x148000000UL, 1024 * MB));
    madeira_early_pool_settle(0, 0);
    CHECK(fake_mapped(0x148000000UL, 512 * MB));
    CHECK(madeira_early_pool_released == 0);
    CHECK(madeira_early_pool_base == 0x148000000UL && madeira_early_pool_size == 1024 * MB);

    /* The pool landed somewhere else (a lower hole took a smaller request): hold it all again. */
    layout(1024 * MB);
    CHECK(madeira_early_pool_release(256 * MB) == 256 * MB);
    fake_map(0x12b000000UL, 256 * MB);
    madeira_early_pool_settle(0x12b000000UL, 256 * MB);
    CHECK(fake_mapped(0x148000000UL, 256 * MB));
    CHECK(madeira_early_pool_base == 0x148000000UL && madeira_early_pool_size == 1024 * MB);

    /* No placeholder (an intruder took the space): release is a no-op, settle is safe. */
    layout(0);
    CHECK(madeira_early_pool_release(512 * MB) == 0);
    madeira_early_pool_settle(0, 0);

    /* The describe line carries every claim for the log. */
    layout(1024 * MB);
    char line[256];
    madeira_early_claims_describe(line, sizeof line);
    CHECK(strstr(line, "window=0x140000000+0x8000000") && strstr(line, "placeholder=0x148000000+0x40000000"));
    printf("OK\n");
    return 0;
}
'''

compiler = shutil.which("clang") or shutil.which("gcc")
assert compiler, "no C compiler"
with tempfile.TemporaryDirectory() as directory:
    d = Path(directory)
    src = d / "t.c"
    src.write_text("#include <stdlib.h>\n" + MACH + production + TEST, encoding="utf-8")
    exe = d / "t"
    subprocess.run([compiler, "-std=gnu11", "-Wall", "-Werror", "-Wno-unused-function", "-O1", str(src), "-o", str(exe)], check=True)
    out = subprocess.run([str(exe)], capture_output=True, text=True)
    assert out.returncode == 0 and out.stdout.strip().endswith("OK"), out.stdout + out.stderr

# StikJITHelper: release after the pin chunks and before the debugger request, settle on both outcomes.
pool = swift[swift.index("static func allocatePool("):]
pool = pool[:pool.index("// Create RW mapping via vm_remap")]
pin = pool.index("JIT-pool pin chunk")
release = pool.index("madeira_early_pool_release(UInt(poolSize))")
scan = pool.index("madeira_largest_free_hole(")
request = pool.index("jit26_prepare_region(nil, poolSize)")
assert pin < release < scan < request, "release after the pin chunks, scan, then ask the debugger"
assert "[pool-placeholder] ml1150" in pool
assert pool.count("madeira_early_pool_settle(0, 0)") == 2, "no-hole skip and failed placement both restore the hold"
assert "madeira_early_pool_settle(UInt(rxAddr), UInt(poolSize))" in pool
assert pool.index("madeira_early_pool_settle(UInt(rxAddr), UInt(poolSize))") > pool.index("RX pool at") - 200
print("PASS pool-placeholder")
