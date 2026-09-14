# Gamemaker bundle system:
# * We break the data into two types:
#   * Transient objects: Things like objects, sprites, scripts that are used in many
#                        rooms. These may be put into any/all pages. They do not care
#                        where they are
#   * Local objects: Rooms, they live in a set page.
# 
# * All local objects know that they use, and dependency graphs are resolved during compilation
#   to ensure rooms have all their objects on-page. 
#    * HACK: When objects are 'persistant', we add a rom-page shim to all the events, 
#             these are rare enough a few dozen cycles is worth it.       
# * Stages of compilation:
#   * Transient object compilation: Compile objects and sprites
#   * Local object compilation: Rooms get compiled, with all the dependencies attached
#


import sys
from os.path import join, abspath, dirname
from os import walk
import multiprocessing, subprocess, time

CORE_COUNT = None # Set to a number to override

GAME_DIR = join(dirname(abspath(__file__)), "game")
APP_DIR = dirname(abspath(__file__))
TRANSIENT_TYPES = [
    "objects", "sprites"
]


def get_transients(dirs = None):
    ret = []
    for ttype in dirs or TRANSIENT_TYPES:
        for (dirname, _, files) in walk(join(GAME_DIR, ttype)):
            ret += [join(dirname, f) for f in files if f.endswith(".json")]
    return ret
def list_transients():
    print(", ".join(get_transients()))


def _compile(command_gen):
    nproc = CORE_COUNT or multiprocessing.cpu_count()
    procs = []
    
    while True:
        procs = [p for p in procs if p.poll() is None]
        try:
            if len(procs) < nproc:
                cmd = next(command_gen)
                print("$", "  ".join(cmd))
                procs.append(subprocess.Popen(cmd, cwd=APP_DIR))
                continue
        except StopIteration:
            if not procs:
                break
        time.sleep(0.1)



def check_compilation(json_path):
    pass

def compile_transients():
    for jso in get_transients(["sprites"]):
        print(jso)


    if False: yield 



def main():
    if len(sys.argv) >= 2:
        if "--list-transients" == sys.argv[1]:
            list_transients()
        elif "--compile-transients" == sys.argv[1]:
            _compile(compile_transients())
        else:
            print("unknown operation")


if __name__ == "__main__":
    main()

