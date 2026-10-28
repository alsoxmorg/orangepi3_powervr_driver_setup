"""Run inside GDB after a stop; account for the explicit ld.so launcher."""
import pathlib
import gdb


def inspect(command):
    try:
        gdb.execute(command)
    except gdb.error as error:
        gdb.write(f'{command}: {error}\n')


pid = gdb.selected_inferior().pid
if pid:
    try:
        mappings = pathlib.Path(f'/proc/{pid}/maps').read_text()
        gdb.write('\n=== Target memory mappings ===\n' + mappings)
        for line in mappings.splitlines():
            fields = line.split()
            if len(fields) >= 6 and fields[-1] == '/usr/bin/sway' and int(fields[2], 16) == 0:
                base = int(fields[0].split('-')[0], 16)
                inspect(f'add-symbol-file /usr/bin/sway -o {base:#x}')
                break
    except OSError as error:
        gdb.write(f'Cannot read target mappings: {error}\n')
    for command in (
        'thread apply all bt full', 'info registers', 'info symbol $pc',
        'info symbol $lr', 'x/12i $lr-24', 'x/32gx $sp',
        'x/16gx $x0', 'x/8gx *(void **)$x0', 'info sharedlibrary',
    ):
        inspect(command)
else:
    gdb.write('Inferior exited without a live stop; no crash memory remains.\n')
