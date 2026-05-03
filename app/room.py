import sys, os
from os.path import abspath, dirname, exists, join

PROJECT_ROOT = dirname(abspath(__file__))
ROOMS_DIR = join(PROJECT_ROOT, "rooms")


def parse_meta(room_file):
    room_inner = join(ROOMS_DIR, room_file)
    room_file =  room_inner if exists(room_inner) else room_file

    with open(room_file, "r") as f:
        cont = f.read()
    meta_start = cont.find("//[META]")
    if -1 == meta_start:
        return None
    meta = cont[cont[meta_start:].find("\n") + 1 :]
    end_meta = meta.find("//[/META]")
    if -1 == end_meta:
        raise Exception(
            f"Room {room_file} does NOT have the required metadata structure"
        )
    meta = meta[:end_meta]

    return {
        x.split("=")[0].strip().removeprefix("//").strip(): x.split("=")[1].strip()
        for x in meta.split("\n")
        if x.strip()
    }


def get_rooms():
    for maybe_room in os.listdir(ROOMS_DIR):
        if not maybe_room.endswith(".c"):
            continue

        meta = parse_meta(maybe_room)
        if meta is None:
            continue

        yield maybe_room, meta

def get_defines(room : str):
    meta = parse_meta(room)
    assert meta is not None

    if not 'ROOMID' in meta:
        raise Exception(f"A {room} MUST provide a ROOMID parameter!")
    return f'-DROOMID="{meta['ROOMID']}" -DROOMPAGE={int(meta.get("PAGE", "0"))}'


def all_rooms():
    return [room for room, _ in get_rooms()]
    


def rooms_with_page(page: int):
    return list(
        (room for room, meta in get_rooms() if int(meta.get("PAGE", "0")) == page)
    )

def generate_rooms_data():
    pages = {}
    for _, meta in get_rooms():
        pageid = str(meta.get('PAGE', '0'))
        
        lis = pages.get(pageid, [])
        lis.append(meta['ROOMID'])
        pages[pageid] = lis

    rooms_data = []
    for pageid, rooms in pages.items():
        rooms = list(sorted(rooms))
        pageid = int(pageid)
        rooms_data.append((pageid, list(enumerate(rooms))))
    return list(sorted(rooms_data, key=lambda x: x[0]))
    
def generate_rooms_h():
    out = "#pragma once\n// AUTOGENERATE FILE! Do not edit!\n\n"
    out += "typedef enum {\n"
    for page, rooms in generate_rooms_data():
        out += f"\t// Page {page} rooms\n"
        for room_id, room_name in rooms:
            out += f"\t{room_name} = {room_id} + ({page} << 9),\n"
        
    out += "} Room;\n"
    return out

def generate_rooms_inc():
    out  = "; AUTOGENERATE FILE! Do not edit!\n"
    out += "IFNDEF ROOMS_INC\nDEFINE ROOMS_INC\n"

    for page, rooms in generate_rooms_data():
        out += f"; Page {page} rooms\n"
        for room_id, room_name in rooms:
            out += f"\tDEFC {room_name} = {room_id} + ({page} << 9)\n"

    out += "ENDIF\n"
    return out

    


if __name__ == "__main__":
    mode = None if 1==len(sys.argv) else sys.argv[1]
    if "--with-page" == mode and len(sys.argv) == 3:
        print(" ".join(rooms_with_page(int(sys.argv[2]))))
    if "--list" == mode:
        print(" ".join(all_rooms()))
    elif "--room-defs" == mode and len(sys.argv) == 3:
        print(get_defines(sys.argv[2]))
    elif "--gen-room-h" == mode:
        print(generate_rooms_h())
    elif "--gen-room-inc" == mode:
        print(generate_rooms_inc())
