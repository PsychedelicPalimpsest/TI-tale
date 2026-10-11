# TI-tale app build

Run `make` from this directory to compile game assets and produce `out.8xk`.
Each `game/rooms/*.json` file declares an integer `page`, starting at 0 with no
gaps. Rooms on the same page are linked together. `gm_comp.py --compile-rooms`
generates each room's `.h` init code and the `rooms.h` / `rooms.inc` ID lists.
If a room has no `.c` file, the compiler creates a minimal one. A custom `.c`
file can define `room_entry()` and include its generated `.h`; set `on_entry`
to `true` in the room JSON to call it after placed instances are created.

The first room on page 0 starts at boot. Secondary pages are linked and packed
into the same flash app, with their room code and referenced objects and
sprites. Runtime room switching between pages is not wired up yet.

Each page starts with a 16 byte aligned room table. A record contains the
`RoomObj` create pointer, width, height, previous room ID, and next room ID,
then six padding bytes. Page 0's app header occupies the start of ROM, so its
table is fixed at `$4100`; the build fails if the header reaches that address.
Secondary page tables start at `$4000`. Room IDs encode
the page in the high byte and the table index in the low byte. The first and
last rooms use `0xffff` for a missing previous or next room. A room JSON can
override either link with a `prev` or `next` room ID name.
