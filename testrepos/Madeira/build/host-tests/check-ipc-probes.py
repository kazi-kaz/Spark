#!/usr/bin/env python3
"""ml1161: the Steam IPC probe wrappers keep the real function bodies intact.

Each instrumented Nt* function has its body renamed through IOS_PROBE_DEF and a
public wrapper of the same name that calls the body first, only on iOS. The
section probe hooks sit on the current-process paths of map and unmap.
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[2]
files = {
    'wine/dlls/ntdll/unix/sync.c': ['NtSetEvent', 'NtPulseEvent', 'NtReleaseMutant', 'NtReleaseSemaphore',
                                    'NtWaitForSingleObject', 'NtWaitForMultipleObjects',
                                    'NtSignalAndWaitForSingleObject'],
    'wine/dlls/ntdll/unix/registry.c': ['NtQueryValueKey'],
    'build/ntdll-unix/process_ios.c': ['NtOpenProcess', 'NtQueryInformationProcess'],
    'build/ntdll-unix/server_ios.c': ['NtDuplicateObject'],
}
failed = False


def check(cond, what):
    global failed
    print(('PASS: ' if cond else 'FAIL: ') + what)
    failed |= not cond


for rel, names in files.items():
    text = (root / rel).read_text()
    check('#define IOS_PROBE_DEF(name) static NTSTATUS WINAPI ios_inner_##name' in text
          and '#define IOS_PROBE_DEF(name) NTSTATUS WINAPI name' in text, f'{rel}: IOS_PROBE_DEF has both branches')
    for name in names:
        check(text.count(f'IOS_PROBE_DEF({name})(') == 1, f'{name}: one body')
        wrapper = re.search(r'#ifdef WINE_IOS\nNTSTATUS WINAPI ' + name + r'\((.*?)\n\}\n#endif\n', text, re.S)
        check(wrapper is not None, f'{name}: the public wrapper is iOS-only')
        if wrapper:
            body = wrapper.group(1)
            call = body.find(f'ios_inner_{name}(')
            check(call >= 0 and body.find('ios_ipcprobe', 0, call) < 0, f'{name}: the wrapper calls the body before probing')
            check(body.rstrip().endswith('return ret;'), f'{name}: the wrapper returns the body\'s status')

virtual = (root / 'build/ntdll-unix/virtual_ios.c').read_text()
check('ios_secprobe_map( handle, *addr_ptr, *size_ptr, status );' in virtual, 'map view: probed after virtual_map_section')
unmap = virtual[virtual.index('static NTSTATUS unmap_view_of_section( HANDLE process, PVOID addr, ULONG flags )\n{'):]
unmap = unmap[:unmap.index('\n}\n')]
check(unmap.index('ios_secprobe_unmap( addr );') > unmap.index('server_queue_process_apc')
      and unmap.index('ios_secprobe_unmap( addr );') < unmap.index('server_enter_uninterrupted_section'),
      'unmap view: probed on the current-process path, outside the virtual mutex')
check('mach_vm_read_overwrite( mach_task_self()' in virtual, 'section bytes are read without faulting')

sync = (root / 'wine/dlls/ntdll/unix/sync.c').read_text()
check('ios_secprobe_note( *handle, attr, ret );' in sync and sync.count('ios_secprobe_note( *handle, attr, ret );') == 2,
      'NtCreateSection and NtOpenSection record Steam section handles')
check('ios_probe_has( nb, "steam3master" ) && !ios_steam_ipc_armed' in sync, 'a 32-bit Steam3Master open arms the probes')

print('check-ipc-probes: ' + ('FAIL' if failed else 'PASS'))
sys.exit(1 if failed else 0)
