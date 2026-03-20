from os import environ
from dotenv import load_dotenv
from os.path import abspath, exists, join, dirname
import json
import xml.etree.ElementTree as ET
from dataclasses import dataclass

# Paths
TOOLING_PATH = dirname(abspath(__file__))
ROOT_PATH = dirname(TOOLING_PATH)
DATA_PATH = join(ROOT_PATH, 'data')

# Load data
load_dotenv(join(ROOT_PATH, ".env"))
UNDERTALE = environ.get("UNDERTALE", "")
ROOMS = json.load(open(join(DATA_PATH, "rooms.json")))
print(ROOT_PATH)


assert exists(UNDERTALE)

@dataclass
class Instance:
    pass


@dataclass
class Room:
    tree : ET.Element[str]

    @classmethod
    def load_room(cls, name : str) -> Room:
        et = ET.fromstring(open(
            join(UNDERTALE, "rooms", f"{name}.room.gmx")
        ).read())

        for child in et.find("instances"):
            assert child.tag == "instance"
            # todo

        for tile in et.find("tiles"):
            assert tile.tag == "tile"






Room.load_room("room_ruins1")

