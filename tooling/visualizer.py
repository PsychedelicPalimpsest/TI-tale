import arcade
import sys
from gml import Room, Instance, Tile, Background, Object, Sprite
import os

SCREEN_WIDTH = 800
SCREEN_HEIGHT = 600
SCREEN_TITLE = "GML Room Visualizer"

# Colors for different object types (randomish)
OBJ_COLORS = {}

def get_color(name):
    if not name:
        return arcade.color.GRAY
    if name not in OBJ_COLORS:
        import random
        # Seed it so same names get same colors
        random.seed(name)
        OBJ_COLORS[name] = (random.randint(50, 200), random.randint(50, 200), random.randint(50, 200))
    return OBJ_COLORS[name]

class Visualizer(arcade.Window):
    def __init__(self, room_name):
        super().__init__(SCREEN_WIDTH, SCREEN_HEIGHT, SCREEN_TITLE, resizable=True)
        self.room_name = room_name
        self.room = None
        
        # Camera for the room
        self.camera = None
        # Camera for GUI (static)
        self.gui_camera = None
        
        self.camera_x = 0
        self.camera_y = 0
        self.zoom = 1.0
        
        self.move_speed = 10
        self.zoom_speed = 0.05
        
        self.keys_pressed = set()
        self.instances_visible = True
        
        # Caches
        self.bg_textures = {}
        self.tile_textures = {}
        self.instance_sprites = {} # objName -> (texture, SpriteMeta)

    def get_tile_texture(self, tile: Tile):
        if not tile.bgName:
            return None
            
        cache_key = (tile.bgName, tile.xo, tile.yo, tile.w, tile.h)
        if cache_key in self.tile_textures:
            return self.tile_textures[cache_key]
            
        if tile.bgName not in self.bg_textures:
            try:
                bg_meta = Background.load_background(tile.bgName)
                if os.path.exists(bg_meta.image_path):
                    self.bg_textures[tile.bgName] = arcade.load_texture(bg_meta.image_path)
                else:
                    self.bg_textures[tile.bgName] = None
            except Exception as e:
                print(f"Error loading background {tile.bgName}: {e}")
                self.bg_textures[tile.bgName] = None
                
        base_tex = self.bg_textures.get(tile.bgName)
        if not base_tex:
            return None
            
        try:
            cropped = base_tex.crop(tile.xo, tile.yo, tile.w, tile.h)
            self.tile_textures[cache_key] = cropped
            return cropped
        except Exception as e:
            print(f"Error cropping tile {tile.bgName} at {tile.xo},{tile.yo}: {e}")
            return None

    def get_instance_sprite(self, objName: str):
        if objName in self.instance_sprites:
            return self.instance_sprites[objName]
            
        try:
            obj_meta = Object.load_object(objName)
            if not obj_meta.spriteName:
                self.instance_sprites[objName] = (None, None)
                return None, None
                
            spr_meta = Sprite.load_sprite(obj_meta.spriteName)
            if os.path.exists(spr_meta.image_path):
                tex = arcade.load_texture(spr_meta.image_path)
                self.instance_sprites[objName] = (tex, spr_meta)
                return tex, spr_meta
            else:
                print(f"Sprite image not found: {spr_meta.image_path}")
                self.instance_sprites[objName] = (None, None)
                return None, None
        except Exception as e:
            print(f"Error loading sprite for {objName}: {e}")
            self.instance_sprites[objName] = (None, None)
            return None, None

    def setup(self):
        try:
            self.room = Room.load_room(self.room_name)
            print(f"Loaded {self.room.name}: {self.room.width}x{self.room.height}")
        except Exception as e:
            print(f"Failed to load room: {e}")
            self.room = Room(self.room_name, "Error Loading Room", 2000, 2000)

        self.camera = arcade.camera.Camera2D()
        self.gui_camera = arcade.camera.Camera2D()
        
        if self.room:
             self.camera_x = self.room.width / 2
             self.camera_y = self.room.height / 2

    def on_draw(self):
        self.clear()
        
        # Room Camera
        self.camera.use()
        
        # Draw Room Boundary
        arcade.draw_lrbt_rectangle_outline(0, self.room.width, 0, self.room.height, arcade.color.WHITE, 2)
        
        # Draw Tiles (sorted by depth)
        sorted_tiles = sorted(self.room.tiles, key=lambda t: t.depth, reverse=True)
        for tile in sorted_tiles:
            tex = self.get_tile_texture(tile)
            w = tile.w * tile.scaleX
            h = tile.h * tile.scaleY
            center_x = tile.x + w/2
            center_y = self.room.height - (tile.y + h/2)
            
            if tex:
                arcade.draw_texture_rect(tex, arcade.Rect.from_kwargs(x=center_x, y=center_y, width=w, height=h))
            else:
                color = get_color(tile.bgName)
                arcade.draw_lrbt_rectangle_filled(tile.x, tile.x + w, self.room.height - (tile.y + h), self.room.height - tile.y, (*color, 150))

        # Draw Instances
        if self.instances_visible:
            for inst in self.room.instances:
                tex, spr_meta = self.get_instance_sprite(inst.objName)
                
                if tex and spr_meta:
                    # GM Instance (x, y) is where the sprite's ORIGIN (xorig, yorig) is placed.
                    # Sprite origin is relative to its top-left.
                    # x_topleft = inst.x - spr_meta.xorig * inst.scaleX
                    # y_topleft = inst.y - spr_meta.yorig * inst.scaleY
                    
                    # Arcade draw_texture_rect centers it.
                    # We need the center of the sprite in room coordinates.
                    # Center is (xorig + width/2, yorig + height/2) relative to top-left? 
                    # No, center relative to origin is: (width/2 - xorig, height/2 - yorig)
                    
                    w = spr_meta.width * inst.scaleX
                    h = spr_meta.height * inst.scaleY
                    
                    # Offset from origin (inst.x, inst.y) to center
                    off_x = (spr_meta.width/2 - spr_meta.xorig) * inst.scaleX
                    off_y = (spr_meta.height/2 - spr_meta.yorig) * inst.scaleY
                    
                    center_x = inst.x + off_x
                    # GM Y is down, so offset Y is inverted for Arcade Y-up
                    center_y = self.room.height - (inst.y + off_y)
                    
                    arcade.draw_texture_rect(
                        tex,
                        arcade.Rect.from_kwargs(x=center_x, y=center_y, width=w, height=h),
                        angle=-inst.rotation # arcade angle is degrees clockwise?
                    )
                else:
                    # Fallback to color square
                    x = inst.x
                    y = self.room.height - inst.y
                    color = get_color(inst.objName)
                    w = 16 * inst.scaleX
                    h = 16 * inst.scaleY
                    arcade.draw_rect_filled(
                        arcade.Rect.from_kwargs(x=x, y=y, width=w, height=h),
                        color,
                        tilt_angle=-inst.rotation
                    )

        # GUI Camera
        self.gui_camera.use()
        status = "LOADED" if self.room.loaded_from_file else "DUMMY"
        vis_status = "ON" if self.instances_visible else "OFF"
        arcade.draw_text(f"Room: {self.room.name} [{status}] | Tiles: {len(self.room.tiles)} | Instances: {len(self.room.instances)} (Visible: {vis_status})",
                         10, 50, arcade.color.WHITE, 12)
        arcade.draw_text(f"Camera: ({int(self.camera_x)}, {int(self.camera_y)}) | Zoom: {self.zoom:.2f}",
                         10, 30, arcade.color.WHITE, 12)
        arcade.draw_text("WASD to move, QE to zoom, I to toggle instances, ESC to exit", 10, 10, arcade.color.WHITE, 12)

    def on_update(self, delta_time):
        if arcade.key.W in self.keys_pressed:
            self.camera_y += self.move_speed / self.zoom
        if arcade.key.S in self.keys_pressed:
            self.camera_y -= self.move_speed / self.zoom
        if arcade.key.A in self.keys_pressed:
            self.camera_x -= self.move_speed / self.zoom
        if arcade.key.D in self.keys_pressed:
            self.camera_x += self.move_speed / self.zoom
            
        if arcade.key.Q in self.keys_pressed:
            self.zoom *= (1.0 + self.zoom_speed)
        if arcade.key.E in self.keys_pressed:
            self.zoom /= (1.0 + self.zoom_speed)
            self.zoom = max(0.001, self.zoom)

        self.camera.position = (self.camera_x, self.camera_y)
        self.camera.zoom = self.zoom

    def on_key_press(self, key, modifiers):
        self.keys_pressed.add(key)
        if key == arcade.key.ESCAPE:
            self.close()
        if key == arcade.key.I:
            self.instances_visible = not self.instances_visible

    def on_key_release(self, key, modifiers):
        if key in self.keys_pressed:
            self.keys_pressed.remove(key)

if __name__ == "__main__":
    room_name = "room_ruins1"
    if len(sys.argv) > 1:
        room_name = sys.argv[1]
        
    window = Visualizer(room_name)
    window.setup()
    arcade.run()
