import os
import glob
import json
import subprocess
import shutil
from pathlib import Path
from PIL import Image

from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.widgets import Header, Footer, Tree, Select, Input, Label, Button
from textual.reactive import reactive
from textual.message import Message
from textual.validation import Number, Integer
from textual.events import Key, Event

# Assuming tooling is in PYTHONPATH
import sys
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))
from gml import UNDERTALE, Sprite, Background, DATA_PATH, Room, Object
from image_processor import process_image

STATE_FILE = os.path.join(os.path.dirname(__file__), "state.json")
TMP_ORIG = "/tmp/titale_remaker_orig.png"
TMP_PROC = "/tmp/titale_remaker_proc.png"

def load_state():
    # Default state for first-time run or if file is corrupted
    default_state = {
        "scale_x": "0.5",
        "scale_y": "0.5",
        "scaling_alg": "nearest",
        "brightness": "1.0",
        "contrast": "1.0",
        "gamma": "1.0",
        "grayscale_mode": "luminance",
        "alpha_threshold": "128",
        "quantization": "threshold"
    }
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r") as f:
                state = json.load(f)
                # Ensure all keys from default are present
                for key, value in default_state.items():
                    if key not in state:
                        state[key] = value
                return state
        except Exception:
            pass # Fallback to default state
    return default_state

def save_state(state):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)

class RoomTree(Tree):
    def _on_key(self, event: Key) -> None:
        # This is the correct event handling pattern.
        # We check for the keys we want to handle for search.
        if event.is_printable or event.key == "backspace" or (event.key == "escape" and self.app.search_query):
            app = self.app
            if event.is_printable:
                app.search_query += event.character
            elif event.key == "backspace":
                app.search_query = app.search_query[:-1]
            elif event.key == "escape":
                app.search_query = ""

            # Stop the event from propagating to the default Tree handler
            event.stop()
            event.prevent_default()

            # Now, perform the filtering logic
            query_display = app.query_one("#search_query_display", Label)
            if app.search_query:
                query_display.update(f"Search: {app.search_query}")
                query_display.remove_class("hidden")
                for node in self.root.children:
                    if node.data and node.data.get("is_room"):
                        node.display = app.search_query.lower() in node.label.plain.lower()
            else:
                # Reset and unhide all
                query_display.update("")
                query_display.add_class("hidden")
                for node in self.root.children:
                    if node.data and node.data.get("is_room"):
                        node.display = True
        else:
            # If it's not a key we handle, pass it to the default Tree navigation
            super()._on_key(event)

class SpriteRemakerApp(App):
    CSS = """
    Screen {
        layout: horizontal;
    }
    #sidebar {
        width: 30%;
        height: 100%;
        border-right: solid green;
    }
    #settings {
        width: 70%;
        height: 100%;
        padding: 1 2;
    }
    .setting-row {
        height: 3;
        margin-bottom: 1;
    }
    .label {
        width: 25;
        content-align: left middle;
    }
    .hidden {
        visibility: hidden;
    }
    Input {
        width: 20;
    }
    Select {
        width: 30;
    }
    Button {
        margin-top: 2;
        width: 100%;
        background: $success;
    }
    """
    
    BINDINGS = [
        ("q", "quit", "Quit"),
        ("s", "export", "Export to Data")
    ]

    def __init__(self):
        super().__init__()
        self.state = load_state()
        self.selected_asset = None
        self.selected_type = None # 'sprite' or 'background'
        self.selected_node = None
        self.preview_proc = None
        self.search_query = ""

    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal():
            with Vertical(id="sidebar"):
                yield RoomTree("Rooms", id="room_tree")
                yield Label("", id="search_query_display", classes="hidden")
            
            with VerticalScroll(id="settings"):
                yield Label("Scale X:")
                yield Input(value=self.state["scale_x"], id="scale_x", validators=[Number()])
                
                yield Label("Scale Y:")
                yield Input(value=self.state["scale_y"], id="scale_y", validators=[Number()])
                
                yield Label("Scaling Algorithm:")
                yield Select(
                    options=[("Nearest", "nearest"), ("Box", "box"), ("Bilinear", "bilinear"), ("Bicubic", "bicubic"), ("Lanczos", "lanczos")], 
                    value=self.state["scaling_alg"], 
                    id="scaling_alg"
                )
                
                yield Label("Brightness (1.0 = normal):")
                yield Input(value=self.state["brightness"], id="brightness", validators=[Number()])
                
                yield Label("Contrast (1.0 = normal):")
                yield Input(value=self.state["contrast"], id="contrast", validators=[Number()])

                yield Label("Gamma (1.0 = normal):")
                yield Input(value=self.state["gamma"], id="gamma", validators=[Number(minimum=0.1)])
                
                yield Label("Grayscale Mode:")
                yield Select(
                    options=[("Luminance", "luminance"), ("Average", "average"), ("Gamma Only (Debug)", "gamma_only")], 
                    value=self.state["grayscale_mode"], 
                    id="grayscale_mode"
                )
                
                yield Label("Alpha Threshold (0-255):")
                yield Input(value=self.state["alpha_threshold"], id="alpha_threshold", validators=[Integer(minimum=0, maximum=255)])
                
                yield Label("Quantization:")
                yield Select(
                    options=[("Threshold (Nearest Color)", "threshold"), ("Floyd-Steinberg Dithering", "floyd-steinberg"), ("Ordered Dithering (Bayer)", "ordered"), ("None (Raw Grayscale)", "none")], 
                    value=self.state["quantization"], 
                    id="quantization"
                )
                
                yield Button("Export Selected Asset to data/", id="btn_export")
                yield Button("Batch Apply to ALL Room Sprites", id="btn_batch_sprites", variant="primary")
                yield Button("Batch Apply to ALL Room Backgrounds", id="btn_batch_bgs", variant="primary")
                yield Button("Reset to Defaults", id="btn_reset", variant="warning")

        yield Footer()

    def on_mount(self) -> ComposeResult:
        tree = self.query_one("#room_tree", RoomTree)
        tree.root.expand()
        
        # Populate tree root with rooms
        if UNDERTALE and os.path.exists(UNDERTALE):
            room_files = glob.glob(os.path.join(UNDERTALE, "rooms", "*.room.gmx"))
            if not room_files:
                room_files = glob.glob(os.path.join(UNDERTALE, "**", "*.room.gmx"), recursive=True)
                
            for f in sorted(room_files):
                name = os.path.basename(f).replace(".room.gmx", "")
                # Add a dummy child so it shows as expandable
                node = tree.root.add(name, data={"is_room": True, "name": name})
                node.add_leaf("Loading...", data={"dummy": True})
        
        # Touch temp files
        open(TMP_ORIG, 'a').close()
        open(TMP_PROC, 'a').close()
        
        # Launch preview window
        preview_script = os.path.join(os.path.dirname(__file__), "preview_window.py")
        self.preview_proc = subprocess.Popen([sys.executable, preview_script, TMP_ORIG, TMP_PROC])

        # Trigger an initial render
        self.call_later(self.update_preview)

    def on_unmount(self):
        if self.preview_proc:
            self.preview_proc.terminate()

    def on_tree_node_expanded(self, event: Tree.NodeExpanded):
        node = event.node
        if node.data and node.data.get("is_room"):
            # Check if it has the dummy child
            if len(node.children) == 1 and node.children[0].data and node.children[0].data.get("dummy"):
                # Remove dummy
                node.children[0].remove()
                
                room_name = node.data["name"]
                try:
                    room_data = Room.load_room(room_name)
                except Exception:
                    node.add_leaf("Error loading room", data=None)
                    return
                
                # Backgrounds
                bgs = sorted(list(set(t.bgName for t in room_data.tiles if t.bgName)))
                if bgs:
                    bgs_node = node.add("Backgrounds", expand=False)
                    for bg in bgs:
                        remade = os.path.exists(os.path.join(DATA_PATH, "backgrounds", f"{bg}.png"))
                        label = f"[{'X' if remade else ' '}] {bg}"
                        bgs_node.add_leaf(label, data={"type": "background", "name": bg})
                        
                # Sprites
                sprites = set()
                for inst in room_data.instances:
                    try:
                        obj_meta = Object.load_object(inst.objName)
                        if obj_meta.spriteName:
                            sprites.add(obj_meta.spriteName)
                    except:
                        pass
                
                sprites = sorted(list(sprites))
                if sprites:
                    sprites_node = node.add("Sprites", expand=False)
                    for spr in sprites:
                        remade = os.path.exists(os.path.join(DATA_PATH, "sprites", f"{spr}.png"))
                        label = f"[{'X' if remade else ' '}] {spr}"
                        sprites_node.add_leaf(label, data={"type": "sprite", "name": spr})

    def on_tree_node_selected(self, event: Tree.NodeSelected):
        if event.node.data and "type" in event.node.data:
            self.selected_node = event.node
            self.selected_type = event.node.data["type"]
            self.selected_asset = event.node.data["name"]
            self.call_later(self.update_preview)

    def on_input_changed(self, event: Input.Changed):
        # Do not update on invalid input; the widget will turn red automatically
        if not event.validation_result.is_valid:
            return
        self.state[event.input.id] = event.value
        save_state(self.state)
        self.call_later(self.update_preview)

    def on_select_changed(self, event: Select.Changed):
        if event.value != Select.BLANK:
            self.state[event.select.id] = event.value
            save_state(self.state)
            self.call_later(self.update_preview)
    def get_config(self):
        try:
            return {
                "scale_x": float(self.state["scale_x"]),
                "scale_y": float(self.state["scale_y"]),
                "scaling_alg": self.state["scaling_alg"],
                "brightness": float(self.state["brightness"]),
                "contrast": float(self.state["contrast"]),
                "gamma": float(self.state["gamma"]),
                "grayscale_mode": self.state["grayscale_mode"],
                "alpha_threshold": int(self.state["alpha_threshold"]),
                "quantization": self.state["quantization"]
            }
        except ValueError:
            return None # Invalid input, ignore until user fixes


    def get_image_path(self):
        if not self.selected_asset:
            return None
        try:
            if self.selected_type == "sprite":
                meta = Sprite.load_sprite(self.selected_asset)
                return meta.image_path
            elif self.selected_type == "background":
                meta = Background.load_background(self.selected_asset)
                return meta.image_path
        except:
            return None
        return None

    def update_preview(self):
        if not self.selected_asset:
            return

        img_path = self.get_image_path()
        if not img_path or not os.path.exists(img_path):
            self.notify("Image path not found. Aborting.", severity="error")
            return
            
        config = self.get_config()
        if not config:
            self.notify("Invalid settings in input fields. Aborting.", severity="error")
            return

        try:
            img = Image.open(img_path)
            # Save a copy for the preview to load easily
            shutil.copyfile(img_path, TMP_ORIG)
            
            proc_img = process_image(img, config)
            proc_img.save(TMP_PROC, format="PNG")
        except Exception as e:
            self.notify(f"Preview Error: {str(e)}", severity="error")

    def on_button_pressed(self, event: Button.Pressed):
        if event.button.id == "btn_export":
            self.action_export()
        elif event.button.id == "btn_batch_sprites":
            self.action_batch_export("sprite")
        elif event.button.id == "btn_batch_bgs":
            self.action_batch_export("background")
        elif event.button.id == "btn_reset":
            self.action_reset_settings()
            
    def action_reset_settings(self):
        default_state = {
            "scale_x": "0.5",
            "scale_y": "0.5",
            "scaling_alg": "nearest",
            "brightness": "1.0",
            "contrast": "1.0",
            "gamma": "1.0",
            "grayscale_mode": "luminance",
            "alpha_threshold": "128",
            "quantization": "threshold"
        }
        self.state = default_state.copy()
        save_state(self.state)

        # Update all the widgets on screen
        self.query_one("#scale_x", Input).value = self.state["scale_x"]
        self.query_one("#scale_y", Input).value = self.state["scale_y"]
        self.query_one("#scaling_alg", Select).value = self.state["scaling_alg"]
        self.query_one("#brightness", Input).value = self.state["brightness"]
        self.query_one("#contrast", Input).value = self.state["contrast"]
        self.query_one("#gamma", Input).value = self.state["gamma"]
        self.query_one("#grayscale_mode", Select).value = self.state["grayscale_mode"]
        self.query_one("#alpha_threshold", Input).value = self.state["alpha_threshold"]
        self.query_one("#quantization", Select).value = self.state["quantization"]
        
        self.notify("Settings have been reset to default.")
        self.call_later(self.update_preview)

    def action_batch_export(self, asset_type: str):
        if not self.selected_node:
            self.notify("Please select an asset within a room first.", severity="error")
            return

        # Find the parent room of the currently selected node
        room_node = self.selected_node
        while room_node and not (room_node.data and room_node.data.get("is_room")):
            room_node = room_node.parent
        
        if not room_node:
            self.notify("Could not determine the current room.", severity="error")
            return

        config = self.get_config()
        if not config:
            self.notify("Invalid settings. Cannot batch process.", severity="error")
            return
            
        self.notify(f"Starting batch export for {asset_type}s in {room_node.data['name']}...")
        
        # Find the container node for the asset type (e.g., "Sprites" or "Backgrounds")
        asset_container_node = None
        for child in room_node.children:
            if child.label.plain.lower() == f"{asset_type}s":
                asset_container_node = child
                break
        
        if not asset_container_node:
            self.notify(f"No {asset_type}s found in this room.", severity="warning")
            return
            
        exported_count = 0
        for asset_node in asset_container_node.children:
            asset_name = asset_node.data["name"]
            
            try:
                # Get image path
                if asset_type == "sprite":
                    meta = Sprite.load_sprite(asset_name)
                    out_path = os.path.join(DATA_PATH, "sprites", f"{asset_name}.png")
                else: # background
                    meta = Background.load_background(asset_name)
                    out_path = os.path.join(DATA_PATH, "backgrounds", f"{asset_name}.png")
                
                img_path = meta.image_path
                if not os.path.exists(img_path):
                    continue

                # Process and save
                img = Image.open(img_path)
                proc_img = process_image(img, config)
                os.makedirs(os.path.dirname(out_path), exist_ok=True)
                proc_img.save(out_path)
                
                # Update UI
                asset_node.set_label(f"[X] {asset_name}")
                exported_count += 1
            except Exception as e:
                self.notify(f"Failed on {asset_name}: {e}", severity="error", duration=10)

        self.notify(f"Batch export complete! Processed {exported_count} {asset_type}s.")

    def action_export(self):
        img_path = self.get_image_path()
        if not img_path or not os.path.exists(img_path):
            return
            
        config = self.get_config()
        if not config:
            return

        try:
            img = Image.open(img_path)
            proc_img = process_image(img, config)
            
            # Determine output path
            if self.selected_type == "sprite":
                out_path = os.path.join(DATA_PATH, "sprites", f"{self.selected_asset}.png")
            else:
                out_path = os.path.join(DATA_PATH, "backgrounds", f"{self.selected_asset}.png")
                
            os.makedirs(os.path.dirname(out_path), exist_ok=True)
            proc_img.save(out_path)
            
            # Update tree node label
            if self.selected_node:
                self.selected_node.set_label(f"[X] {self.selected_asset}")
            
            self.notify(f"Exported {self.selected_asset} to {out_path}")
        except Exception as e:
            self.notify(f"Export Failed: {str(e)}", severity="error")

if __name__ == "__main__":
    app = SpriteRemakerApp()
    app.run()
