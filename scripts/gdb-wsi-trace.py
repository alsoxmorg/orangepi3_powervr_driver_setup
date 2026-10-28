"""Trace VkResult-returning vendor Mesa WSI helpers inside the client only."""
import gdb
import struct

gdb.execute('set breakpoint pending on')


def signed32(value):
    value &= 0xffffffff
    return value - 0x100000000 if value & 0x80000000 else value


class ResultReturn(gdb.FinishBreakpoint):
    def __init__(self, name):
        super().__init__(gdb.newest_frame(), internal=True)
        self.name = name

    def stop(self):
        result = signed32(int(gdb.parse_and_eval('$w0')))
        gdb.write(f'WSI TRACE return {self.name}: VkResult={result}\n')
        return False


class ResultEntry(gdb.Breakpoint):
    def __init__(self, name):
        super().__init__(name, internal=True)
        self.name = name

    def stop(self):
        gdb.write(f'WSI TRACE enter {self.name}\n')
        if self.name == 'wsi_create_image':
            install_image_stages()
        try:
            ResultReturn(self.name)
        except gdb.error as error:
            gdb.write(f'WSI TRACE cannot follow return: {error}\n')
        return False


class ImageStage(gdb.Breakpoint):
    def __init__(self, address, name, is_return=False):
        super().__init__(f'*{address:#x}', internal=True)
        self.name, self.is_return = name, is_return

    def stop(self):
        if self.is_return:
            result = signed32(int(gdb.parse_and_eval('$w0')))
            gdb.write(f'WSI TRACE image stage {self.name}: result={result}\n')
            return False
        gdb.write(f'WSI TRACE image stage {self.name}: call\n')
        if self.name == 'CreateImage':
            try:
                pointer = int(gdb.parse_and_eval('$x1'))
                data = bytes(gdb.selected_inferior().read_memory(pointer, 88))
                def u32(offset):
                    return struct.unpack_from('<I', data, offset)[0]
                gdb.write(f'WSI TRACE VkImageCreateInfo sType={u32(0)} flags={u32(16):#x} '
                          f'type={u32(20)} format={u32(24)} '
                          f'extent={u32(28)}x{u32(32)}x{u32(36)} '
                          f'mips={u32(40)} layers={u32(44)} samples={u32(48)} '
                          f'tiling={u32(52)} usage={u32(56):#x} '
                          f'sharing={u32(60)} initialLayout={u32(80)}\n')
                next_pointer = struct.unpack_from('<Q', data, 8)[0]
                visited = set()
                for _ in range(6):
                    if not next_pointer or next_pointer in visited:
                        break
                    visited.add(next_pointer)
                    header = bytes(gdb.selected_inferior().read_memory(next_pointer, 16))
                    gdb.write(f'WSI TRACE image pNext sType={struct.unpack_from("<I", header)[0]} address={next_pointer:#x}\n')
                    gdb.execute(f'x/8gx {next_pointer:#x}')
                    next_pointer = struct.unpack_from('<Q', header, 8)[0]
            except gdb.error as error:
                gdb.write(f'WSI TRACE image parameters unavailable: {error}\n')
        return False


image_stages_installed = False


def install_image_stages():
    global image_stages_installed
    if image_stages_installed:
        return
    base = int(gdb.parse_and_eval('(unsigned long)&wsi_create_image'))
    # Disassembled offsets in the SHA256-pinned vendor WSI library.
    for offset, name in ((0x5c, 'CreateImage'), (0x7c, 'AllocateImageMemory'),
                         (0x98, 'BindImageMemory'), (0xb8, 'FinishImage')):
        ImageStage(base + offset, name)
        ImageStage(base + offset + 4, name, is_return=True)
    image_stages_installed = True


class XcbReturn(gdb.FinishBreakpoint):
    def stop(self):
        pointer = int(gdb.parse_and_eval('$x0'))
        if pointer:
            try:
                data = bytes(gdb.selected_inferior().read_memory(pointer, 12))
                gdb.write(f'WSI TRACE XCB error: code={data[1]} major={data[10]} '
                          f'minor={int.from_bytes(data[8:10], "little")} '
                          f'resource={int.from_bytes(data[4:8], "little"):#x}\n')
            except gdb.error as error:
                gdb.write(f'WSI TRACE XCB error unreadable: {error}\n')
        return False


class XcbEntry(gdb.Breakpoint):
    def stop(self):
        try:
            XcbReturn(gdb.newest_frame(), internal=True)
        except gdb.error as error:
            gdb.write(f'WSI TRACE XCB return unavailable: {error}\n')
        return False


for name in ('pvr_mesa_wsi_common_create_swapchain', 'wsi_common_create_swapchain',
             'x11_surface_create_swapchain', 'wsi_swapchain_init', 'wsi_create_image',
             'wsi_create_native_image_mem', 'wsi_create_prime_image_mem'):
    ResultEntry(name)
XcbEntry('xcb_request_check', internal=True)
