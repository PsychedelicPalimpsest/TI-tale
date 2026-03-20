from __future__ import annotations
from os import environ
from dotenv import load_dotenv
from os.path import abspath, exists, join, dirname, normpath
import json
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
import glob

# Paths
TOOLING_PATH = dirname(abspath(__file__))
ROOT_PATH = dirname(TOOLING_PATH)
DATA_PATH = join(ROOT_PATH, 'data')

# Load data
load_dotenv(join(ROOT_PATH, ".env"))
UNDERTALE = environ.get("UNDERTALE", "")

def get_val(node, name, default="0"):
    # Try attribute first, then child element
    val = node.get(name)
    if val is None:
        val = node.findtext(name)
    return val if val is not None else default

@dataclass
class Instance:
    objName: str
    x: int
    y: int
    name: str
    scaleX: float
    scaleY: float
    colour: int
    rotation: float

@dataclass
class Tile:
    bgName: str
    x: int
    y: int
    w: int
    h: int
    xo: int
    yo: int
    id: int
    name: str
    depth: int
    scaleX: float
    scaleY: float
    colour: int

@dataclass
class Background:
    name: str
    image_path: str
    width: int = 0
    height: int = 0

    @classmethod
    def load_background(cls, name: str) -> Background:
        bg_gmx = join(UNDERTALE, "background", f"{name}.background.gmx")
        if not exists(bg_gmx):
            found = glob.glob(join(UNDERTALE, "**", f"{name}.background.gmx"), recursive=True)
            if found:
                bg_gmx = found[0]
            else:
                raise FileNotFoundError(f"Background GMX not found: {name}")

        with open(bg_gmx, "r") as f:
            et = ET.fromstring(f.read())
            
        data_path = et.findtext("data", "")
        data_path = data_path.replace("\\", "/")
        image_path = normpath(join(dirname(bg_gmx), data_path))
        
        if not exists(image_path):
             image_path = join(dirname(bg_gmx), "images", f"{name}.png")

        return cls(
            name=name,
            image_path=image_path,
            width=int(get_val(et, "width", "0")),
            height=int(get_val(et, "height", "0"))
        )

@dataclass
class Sprite:
    name: str
    image_path: str
    xorig: int
    yorig: int
    width: int
    height: int

    @classmethod
    def load_sprite(cls, name: str) -> Sprite:
        spr_gmx = join(UNDERTALE, "sprites", f"{name}.sprite.gmx")
        if not exists(spr_gmx):
            found = glob.glob(join(UNDERTALE, "**", f"{name}.sprite.gmx"), recursive=True)
            if found:
                spr_gmx = found[0]
            else:
                raise FileNotFoundError(f"Sprite GMX not found: {name}")

        with open(spr_gmx, "r") as f:
            et = ET.fromstring(f.read())

        # Get the first frame
        frames = et.find("frames")
        if frames is None or len(frames) == 0:
            raise ValueError(f"No frames found for sprite: {name}")
        
        frame_node = frames[0]
        data_path = frame_node.text.replace("\\", "/")
        image_path = normpath(join(dirname(spr_gmx), data_path))

        return cls(
            name=name,
            image_path=image_path,
            xorig=int(get_val(et, "xorig", "0")),
            yorig=int(get_val(et, "yorig", "0")),
            width=int(get_val(et, "width", "0")),
            height=int(get_val(et, "height", "0"))
        )

@dataclass
class Object:
    name: str
    spriteName: str

    @classmethod
    def load_object(cls, name: str) -> Object:
        obj_gmx = join(UNDERTALE, "objects", f"{name}.object.gmx")
        if not exists(obj_gmx):
            found = glob.glob(join(UNDERTALE, "**", f"{name}.object.gmx"), recursive=True)
            if found:
                obj_gmx = found[0]
            else:
                # Some objects might not have GMX files or we just can't find them
                return cls(name=name, spriteName="")

        with open(obj_gmx, "r") as f:
            et = ET.fromstring(f.read())

        return cls(
            name=name,
            spriteName=et.findtext("spriteName", "")
        )

@dataclass
class View:
    visible: bool
    xview: int
    yview: int
    wview: int
    hview: int
    xport: int
    yport: int
    wport: int
    hport: int

@dataclass
class Room:
    name: str
    caption: str
    width: int
    height: int
    instances: list[Instance] = field(default_factory=list)
    tiles: list[Tile] = field(default_factory=list)
    views: list[View] = field(default_factory=list)
    loaded_from_file: bool = False

    @classmethod
    def load_room(cls, name: str) -> Room:
        room_path = join(UNDERTALE, "rooms", f"{name}.room.gmx")
        if not exists(room_path):
            if UNDERTALE and exists(UNDERTALE):
                found = glob.glob(join(UNDERTALE, "**", f"{name}.room.gmx"), recursive=True)
                if found:
                    room_path = found[0]
                else:
                    raise FileNotFoundError(f"Room file not found: {room_path}")
            else:
                raise FileNotFoundError(f"Room file not found: {room_path}")
            
        with open(room_path, "r") as f:
            et = ET.fromstring(f.read())

        room = cls(
            name=name,
            caption=get_val(et, "caption", ""),
            width=int(get_val(et, "width", "0")),
            height=int(get_val(et, "height", "0")),
            loaded_from_file=True
        )

        views_node = et.find("views")
        if views_node is not None:
            for view in views_node.findall("view"):
                room.views.append(View(
                    visible=get_val(view, "visible", "0") == "1",
                    xview=int(get_val(view, "xview", "0")),
                    yview=int(get_val(view, "yview", "0")),
                    wview=int(get_val(view, "wview", "0")),
                    hview=int(get_val(view, "hview", "0")),
                    xport=int(get_val(view, "xport", "0")),
                    yport=int(get_val(view, "yport", "0")),
                    wport=int(get_val(view, "wport", "0")),
                    hport=int(get_val(view, "hport", "0"))
                ))

        instances_node = et.find("instances")
        if instances_node is not None:
            for inst in instances_node.findall("instance"):
                room.instances.append(Instance(
                    objName=get_val(inst, "objName", ""),
                    x=int(get_val(inst, "x", "0")),
                    y=int(get_val(inst, "y", "0")),
                    name=get_val(inst, "name", ""),
                    scaleX=float(get_val(inst, "scaleX", "1.0")),
                    scaleY=float(get_val(inst, "scaleY", "1.0")),
                    colour=int(get_val(inst, "colour", "4294967295")),
                    rotation=float(get_val(inst, "rotation", "0.0"))
                ))

        tiles_node = et.find("tiles")
        if tiles_node is not None:
            for tile in tiles_node.findall("tile"):
                room.tiles.append(Tile(
                    bgName=get_val(tile, "bgName", ""),
                    x=int(get_val(tile, "x", "0")),
                    y=int(get_val(tile, "y", "0")),
                    w=int(get_val(tile, "w", "0")),
                    h=int(get_val(tile, "h", "0")),
                    xo=int(get_val(tile, "xo", "0")),
                    yo=int(get_val(tile, "yo", "0")),
                    id=int(get_val(tile, "id", "0")),
                    name=get_val(tile, "name", ""),
                    depth=int(get_val(tile, "depth", "0")),
                    scaleX=float(get_val(tile, "scaleX", "1.0")),
                    scaleY=float(get_val(tile, "scaleY", "1.0")),
                    colour=int(get_val(tile, "colour", "4294967295"))
                ))

        return room
