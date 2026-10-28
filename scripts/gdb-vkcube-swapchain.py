"""Pinned ARM64 vkcube call-site diagnostic; run inside GDB after starti."""
import pathlib
import struct
import gdb

pid = gdb.selected_inferior().pid
base = None
for line in pathlib.Path(f'/proc/{pid}/maps').read_text().splitlines():
    fields = line.split()
    if len(fields) >= 6 and fields[-1] == '/usr/bin/vkcube' and int(fields[2], 16) == 0:
        base = int(fields[0].split('-')[0], 16)
        break
if base is None:
    raise gdb.GdbError('Cannot locate vkcube ELF mapping')


class SwapchainEntry(gdb.Breakpoint):
    def stop(self):
        gdb.write('\n=== vkCreateSwapchainKHR call ===\n')
        address = int(gdb.parse_and_eval('$x1'))
        data = bytes(gdb.selected_inferior().read_memory(address, 104))
        def u32(offset):
            return struct.unpack_from('<I', data, offset)[0]
        gdb.write(f'sType={u32(0)} imageCount={u32(32)} format={u32(36)} '
                  f'colorSpace={u32(40)} extent={u32(44)}x{u32(48)} '
                  f'layers={u32(52)} usage={u32(56):#x} sharing={u32(60)} '
                  f'transform={u32(80):#x} alpha={u32(84):#x} presentMode={u32(88)}\n')
        gdb.execute('info symbol $x10')
        return False


class SwapchainReturn(gdb.Breakpoint):
    def stop(self):
        result = int(gdb.parse_and_eval('$w0')) & 0xffffffff
        if result & 0x80000000:
            result -= 0x100000000
        names = {0: 'VK_SUCCESS', -1: 'VK_ERROR_OUT_OF_HOST_MEMORY',
                 -2: 'VK_ERROR_OUT_OF_DEVICE_MEMORY', -3: 'VK_ERROR_INITIALIZATION_FAILED',
                 -4: 'VK_ERROR_DEVICE_LOST', -8: 'VK_ERROR_FEATURE_NOT_PRESENT',
                 -9: 'VK_ERROR_INCOMPATIBLE_DRIVER', -11: 'VK_ERROR_FORMAT_NOT_SUPPORTED',
                 -13: 'VK_ERROR_UNKNOWN',
                 -1000000000: 'VK_ERROR_SURFACE_LOST_KHR',
                 -1000000001: 'VK_ERROR_NATIVE_WINDOW_IN_USE_KHR',
                 -1000001004: 'VK_ERROR_OUT_OF_DATE_KHR',
                 -1000001005: 'VK_ERROR_INCOMPATIBLE_DISPLAY_KHR'}
        gdb.write(f'\n=== vkCreateSwapchainKHR result: {result} ({names.get(result, "unlisted VkResult")}) ===\n')
        gdb.write('Stopped before the vkcube assertion; debugger exit will end this diagnostic client.\n')
        return True


SwapchainEntry(f'*{base + 0xc7e0:#x}')
SwapchainReturn(f'*{base + 0xc7e4:#x}')
