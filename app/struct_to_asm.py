from subprocess import check_output
from os.path import abspath, dirname
from cffi import FFI

ffi = FFI()



def get_files():
    files = check_output(
        ["grep", "-rnF", "//#[ASM_EXPOSED]", dirname(abspath(__file__))],
    ).decode("utf-8").split("\n")
    return [
        [s.strip() for s in f.split(':')]
        for f in files if f and not 'struct_to_asm.py' in f 
    ]
print(get_files())
Poin
