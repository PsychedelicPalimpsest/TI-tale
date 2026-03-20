import arcade
import sys
from gml import Room, Instance, Tile, Background, Object, Sprite, DATA_PATH
import os
from PIL import Image

SCREEN_WIDTH = 960 # Scale 10x for visibility
SCREEN_HEIGHT = 640
SCREEN_TITLE = "GML Room Visualizer - TI-tale"

# Mapping functions to help with visualizer representation
def get_color(name):
    if not name:
        return arcade.color.GRAY
    import random
    random.seed(name)
    return (random.randint(50, 200), random.randint(50, 200), random.randint(50, 200))

class Visualizer(arcade.Window):
    def __init__(self, room_name):
        super().__init__(SCREEN_WIDTH, SCREEN_HEIGHT, SCREEN_TITLE, resizable=True)
        self.room_name = room_name
        self.room = None
        
        # Viewport constraints for TI-84 Plus (96x64)
        self.ti_width = 96
        self.ti_height = 64
        
        # Cameras
        self.camera = None # Editor camera (high-res)
        self.gui_camera = None # UI camera
        self.ti_camera = None # Internal low-res camera (FBO)
        
        self.camera_x = 0
        self.camera_y = 0
        self.zoom = 1.0
        
        self.viewport_x = 0
        self.viewport_y = 0
        
        self.move_speed = 5
        self.zoom_speed = 0.05
        
        self.keys_pressed = set()
        self.instances_visible = True
        self.ti_mode = False 
        self.lock_viewport = True
        self.lock_zoom = True
        self.auto_generate_ti_textures = False
        
        # TI-mode low-res rendering setup
        # Raw OpenGL texture for the framebuffer
        self.ti_gl_texture = self.ctx.texture((self.ti_width, self.ti_height), filter=(arcade.gl.NEAREST, arcade.gl.NEAREST))
        self.ti_framebuffer = self.ctx.framebuffer(color_attachments=[self.ti_gl_texture])
        # High-level texture for Arcade drawing
        self.ti_output_texture = arcade.Texture.create_empty("ti_output", (self.ti_width, self.ti_height))
        
        # Caches
        self.bg_textures = {}
        self.tile_textures = {}
        self.instance_sprites = {}
        self.generated_ti_textures = {}

        # Persistent sprite list for TI-mode full-screen view
        self.ti_fullscreen_sprite_list = arcade.SpriteList()
        self.ti_fullscreen_sprite_list.append(arcade.Sprite())

    def setup(self):
        for d in ["sprites", "backgrounds", "tiles"]:
            os.makedirs(os.path.join(DATA_PATH, d), exist_ok=True)

        try:
            self.room = Room.load_room(self.room_name)
            print(f"Loaded {self.room.name}: {self.room.width}x{self.room.height}")
        except Exception as e:
            print(f"Failed to load room: {e}")
            self.room = Room(self.room_name, "Error Loading Room", 2000, 2000)

        self.camera = arcade.camera.Camera2D()
        self.gui_camera = arcade.camera.Camera2D()
        
        # Initialize ti_camera with a 96x64 viewport and its own render target
        ti_vp = arcade.Rect.from_kwargs(x=48, y=32, width=96, height=64)
        self.ti_camera = arcade.camera.Camera2D(
            viewport=ti_vp,
            render_target=self.ti_framebuffer
        )

        if self.room:
             self.camera_x = self.room.width / 2
             self.camera_y = self.room.height / 2
             self.viewport_x = self.camera_x
             self.viewport_y = self.camera_y
        
        self.zoom = 1.0

    def get_local_path(self, type_dir, filename):
        return os.path.join(DATA_PATH, type_dir, filename)

    def _convert_to_ti_palette(self, image_path):
        if image_path in self.generated_ti_textures:
            return self.generated_ti_textures[image_path]

        try:
            img = Image.open(image_path).convert('RGBA')
        except FileNotFoundError:
            return None

        new_img = Image.new('RGBA', img.size)
        
        palette = [
            (0, 0, 0, 255),       # Black
            (85, 85, 85, 255),   # Dark Grey
            (170, 170, 170, 255), # Light Grey
            (255, 255, 255, 255)  # White
        ]

        for x in range(img.width):
            for y in range(img.height):
                r, g, b, a = img.getpixel((x, y))
                
                if a < 128:
                    new_img.putpixel((x, y), (0, 0, 0, 0))
                    continue
                    
                grey = (r + g + b) // 3
                
                if grey < 64: new_color = palette[0]
                elif grey < 128: new_color = palette[1]
                elif grey < 192: new_color = palette[2]
                else: new_color = palette[3]
                
                new_img.putpixel((x, y), new_color)

        texture = arcade.Texture(new_img, name=f"{os.path.basename(image_path)}-ti_generated")
        self.generated_ti_textures[image_path] = texture
        return texture

    def get_tile_texture(self, tile: Tile, force_ti=False):
        if not tile.bgName: return None
        is_ti = self.ti_mode or force_ti
        
        # Auto-generation adds another dimension to the cache key
        cache_key = (tile.bgName, tile.xo, tile.yo, tile.w, tile.h, is_ti, self.auto_generate_ti_textures if is_ti else False)
        if cache_key in self.tile_textures: return self.tile_textures[cache_key]
            
        tex = None
        if is_ti:
            local_png = self.get_local_path("tiles", f"{tile.bgName}.png")
            if not os.path.exists(local_png):
                local_png = self.get_local_path("backgrounds", f"{tile.bgName}.png")
            
            if os.path.exists(local_png):
                tex = arcade.load_texture(local_png)
            elif self.auto_generate_ti_textures:
                try:
                    bg_meta = Background.load_background(tile.bgName)
                    if os.path.exists(bg_meta.image_path):
                        tex = self._convert_to_ti_palette(bg_meta.image_path)
                except:
                    tex = None
        else:
            if tile.bgName not in self.bg_textures:
                try:
                    bg_meta = Background.load_background(tile.bgName)
                    if os.path.exists(bg_meta.image_path):
                        self.bg_textures[tile.bgName] = arcade.load_texture(bg_meta.image_path)
                    else:
                        self.bg_textures[tile.bgName] = None
                except: self.bg_textures[tile.bgName] = None
            tex = self.bg_textures.get(tile.bgName)

        if not tex: return None
        try:
            cropped = tex.crop(tile.xo, tile.yo, tile.w, tile.h)
            self.tile_textures[cache_key] = cropped
            return cropped
        except: return None

    def get_instance_sprite(self, objName: str, force_ti=False):
        is_ti = self.ti_mode or force_ti
        
        cache_key = (objName, is_ti, self.auto_generate_ti_textures if is_ti else False)
        if cache_key in self.instance_sprites: return self.instance_sprites[cache_key]
            
        tex, meta = None, None
        if is_ti:
            try:
                obj_meta = Object.load_object(objName)
                spr_name = obj_meta.spriteName or objName
                local_png = self.get_local_path("sprites", f"{spr_name}.png")
                
                if os.path.exists(local_png):
                    tex = arcade.load_texture(local_png)
                    meta = Sprite(spr_name, local_png, 0, 0, tex.width, tex.height)
                    try:
                        real_meta = Sprite.load_sprite(spr_name)
                        meta.xorig, meta.yorig = real_meta.xorig, real_meta.yorig
                    except: pass
                elif self.auto_generate_ti_textures:
                    spr_meta = Sprite.load_sprite(obj_meta.spriteName)
                    if os.path.exists(spr_meta.image_path):
                        tex = self._convert_to_ti_palette(spr_meta.image_path)
                        meta = spr_meta
            except: pass
        else:
            try:
                obj_meta = Object.load_object(objName)
                if obj_meta.spriteName:
                    spr_meta = Sprite.load_sprite(obj_meta.spriteName)
                    if os.path.exists(spr_meta.image_path):
                        tex = arcade.load_texture(spr_meta.image_path)
                        meta = spr_meta
            except: pass

        self.instance_sprites[cache_key] = (tex, meta)
        return tex, meta

    def render_scene(self, is_lowres=False):
        # Draw Room Boundary
        arcade.draw_lrbt_rectangle_outline(0, self.room.width, 0, self.room.height, arcade.color.WHITE, 1)

        sprite_list = arcade.SpriteList()

        # Draw Tiles (sorted by depth)
        sorted_tiles = sorted(self.room.tiles, key=lambda t: t.depth, reverse=True)
        for tile in sorted_tiles:
            tex = self.get_tile_texture(tile, force_ti=is_lowres)
            
            if is_lowres:
                w = (tex.width if tex else tile.w) * tile.scaleX
                h = (tex.height if tex else tile.h) * tile.scaleY
                cx = tile.x * 0.5 + w/2
                cy = (self.room.height * 0.5) - (tile.y * 0.5 + h/2)
            else:
                w, h = tile.w * tile.scaleX, tile.h * tile.scaleY
                cx, cy = tile.x + w/2, self.room.height - (tile.y + h/2)
            
            if tex:
                sprite = arcade.Sprite()
                sprite.texture = tex
                sprite.center_x, sprite.center_y = cx, cy
                sprite.width, sprite.height = w, h
                sprite_list.append(sprite)
            elif not is_lowres:
                color = get_color(tile.bgName)
                arcade.draw_lrbt_rectangle_filled(tile.x, tile.x + w, self.room.height - (tile.y + h), self.room.height - tile.y, (*color, 100))

        # Draw Instances
        if self.instances_visible:
            for inst in self.room.instances:
                tex, spr_meta = self.get_instance_sprite(inst.objName, force_ti=is_lowres)
                if tex and spr_meta:
                    if is_lowres:
                        w, h = spr_meta.width * inst.scaleX, spr_meta.height * inst.scaleY
                        off_x = (spr_meta.width/2 - spr_meta.xorig) * inst.scaleX
                        off_y = (spr_meta.height/2 - spr_meta.yorig) * inst.scaleY
                        cx = inst.x * 0.5 + off_x
                        cy = (self.room.height * 0.5) - (inst.y * 0.5 + off_y)
                    else:
                        w, h = spr_meta.width * inst.scaleX, spr_meta.height * inst.scaleY
                        off_x = (spr_meta.width/2 - spr_meta.xorig) * inst.scaleX
                        off_y = (spr_meta.height/2 - spr_meta.yorig) * inst.scaleY
                        cx, cy = inst.x + off_x, self.room.height - (inst.y + off_y)
                    
                    sprite = arcade.Sprite()
                    sprite.texture = tex
                    sprite.center_x, sprite.center_y = cx, cy
                    sprite.width, sprite.height = w, h
                    sprite.angle = -inst.rotation
                    sprite_list.append(sprite)
                elif not is_lowres:
                    color = get_color(inst.objName)
                    arcade.draw_rect_filled(arcade.Rect.from_kwargs(x=inst.x, y=self.room.height - inst.y, width=16, height=16), color)
        
        sprite_list.draw(filter=arcade.gl.NEAREST)

    def draw_pixel_grid(self, rect: arcade.Rect):
        # Draw a grid over the given rect, assuming it represents 96x64 pixels
        pw = rect.width / self.ti_width
        ph = rect.height / self.ti_height
        color = (0, 0, 0, 40)
        
        for x in range(self.ti_width + 1):
            lx = rect.left + x * pw
            arcade.draw_line(lx, rect.bottom, lx, rect.top, color, 1)
        for y in range(self.ti_height + 1):
            ly = rect.bottom + y * ph
            arcade.draw_line(rect.left, ly, rect.right, ly, color, 1)

    def on_draw(self):
        # 1. Update TI low-res buffer
        self.ti_camera.use()
        self.ti_camera.render_target.clear()
        # Viewport is at 0.5x scale in FBO space
        self.ti_camera.position = (self.viewport_x * 0.5, self.viewport_y * 0.5)
        self.ti_camera.zoom = 1.0 
        self.render_scene(is_lowres=True)
        
        # Update high-level texture from FBO bytes
        raw_data = self.ti_framebuffer.read(components=4)
        image = Image.frombytes("RGBA", (self.ti_width, self.ti_height), raw_data)
        image = image.transpose(Image.FLIP_TOP_BOTTOM)
        self.ti_output_texture.image = image

        # 2. Render final view
        if self.ti_mode and self.lock_zoom:
            # Full-screen TI view (upscaled)
            
            # Manually set up the main camera to be like the default
            self.camera.position = (self.width / 2, self.height / 2)
            self.camera.zoom = 1.0
            self.camera.use()
            
            self.clear()
            
            sprite = self.ti_fullscreen_sprite_list[0]
            sprite.texture = self.ti_output_texture
            sprite.center_x = self.width / 2
            sprite.center_y = self.height / 2
            sprite.width = self.width
            sprite.height = self.height
            self.ti_fullscreen_sprite_list.draw(filter=arcade.gl.NEAREST)

            out_rect = arcade.Rect.from_kwargs(x=self.width/2, y=self.height/2, width=self.width, height=self.height)
            self.draw_pixel_grid(out_rect)
        else:
            # Editor or PIP view
            self.use()
            self.clear()
            self.camera.position = (self.camera_x, self.camera_y)
            self.camera.zoom = self.zoom
            self.camera.use()
            self.render_scene(is_lowres=False)
            
            # Viewport Overlay
            # Note: The viewport rectangle is always 96x64 TI pixels. 
            # If assets are 0.5x, this represents 192x128 room pixels.
            v_w, v_h = self.ti_width * 2, self.ti_height * 2
            v_rect = arcade.Rect.from_kwargs(x=self.viewport_x, y=self.viewport_y, width=v_w, height=v_h)
            
            if self.ti_mode:
                # Dim background and show PIP
                arcade.draw_lrbt_rectangle_filled(0, self.room.width, 0, self.room.height, (0, 0, 0, 100))
                
                sprite_list = arcade.SpriteList()
                sprite = arcade.Sprite()
                sprite.texture = self.ti_output_texture
                sprite.center_x = v_rect.center_x
                sprite.center_y = v_rect.center_y
                sprite.width = v_rect.width
                sprite.height = v_rect.height
                sprite_list.append(sprite)
                sprite_list.draw(filter=arcade.gl.NEAREST)

                self.draw_pixel_grid(v_rect)
            
            arcade.draw_lrbt_rectangle_outline(v_rect.left, v_rect.right, v_rect.bottom, v_rect.top, arcade.color.YELLOW, 2)

        # 3. GUI
        self.gui_camera.use()
        mode_str = "TI-PIXEL-VIEW" if self.ti_mode else "EDITOR-VIEW"
        l_status = "LOCKED" if self.lock_viewport else "FREE"
        z_status = "LOCKED (0.5x)" if self.lock_zoom else "FREE"
        
        arcade.draw_text(f"Mode: {mode_str} (T) | Viewport: {l_status} (L) | Zoom: {z_status} (Z)", 10, 70, arcade.color.WHITE, 12)
        arcade.draw_text(f"Auto-Generate TI Textures: {'ON' if self.auto_generate_ti_textures else 'OFF'} (G)", 10, 50, arcade.color.WHITE, 12)
        arcade.draw_text(f"Camera: ({int(self.camera_x)}, {int(self.camera_y)}) | Viewport: ({int(self.viewport_x)}, {int(self.viewport_y)})", 10, 30, arcade.color.WHITE, 12)
        arcade.draw_text(f"Instances: {'ON' if self.instances_visible else 'OFF'} (I) | Editor Zoom: {self.zoom:.2f}", 10, 10, arcade.color.WHITE, 12)

    def on_update(self, delta_time):
        # Camera Movement
        if arcade.key.W in self.keys_pressed: self.camera_y += self.move_speed / self.zoom
        if arcade.key.S in self.keys_pressed: self.camera_y -= self.move_speed / self.zoom
        if arcade.key.A in self.keys_pressed: self.camera_x -= self.move_speed / self.zoom
        if arcade.key.D in self.keys_pressed: self.camera_x += self.move_speed / self.zoom
        
        # Viewport Movement
        if self.lock_viewport:
            self.viewport_x, self.viewport_y = self.camera_x, self.camera_y
        else:
            if arcade.key.UP in self.keys_pressed: self.viewport_y += self.move_speed
            if arcade.key.DOWN in self.keys_pressed: self.viewport_y -= self.move_speed
            if arcade.key.LEFT in self.keys_pressed: self.viewport_x -= self.move_speed
            if arcade.key.RIGHT in self.keys_pressed: self.viewport_x += self.move_speed
        
        # Zoom Lock logic
        if self.lock_zoom:
            # 96x64 TI Pixels = 192x128 Room Pixels (at 0.5x)
            # To fill 960x640 window, zoom must be 960 / 192 = 5.0
            self.zoom = 5.0
        else:
            if arcade.key.Q in self.keys_pressed: self.zoom *= 1.05
            if arcade.key.E in self.keys_pressed: self.zoom /= 1.05; self.zoom = max(0.001, self.zoom)

        self.camera.position = (self.camera_x, self.camera_y)
        self.camera.zoom = self.zoom

    def on_key_press(self, key, modifiers):
        self.keys_pressed.add(key)
        if key == arcade.key.ESCAPE: self.close()
        if key == arcade.key.I: self.instances_visible = not self.instances_visible
        if key == arcade.key.T: self.ti_mode = not self.ti_mode
        if key == arcade.key.L: self.lock_viewport = not self.lock_viewport
        if key == arcade.key.Z: self.lock_zoom = not self.lock_zoom
        if key == arcade.key.G: self.auto_generate_ti_textures = not self.auto_generate_ti_textures

    def on_key_release(self, key, modifiers):
        if key in self.keys_pressed: self.keys_pressed.remove(key)

if __name__ == "__main__":
    room_name = "room_ruins1"
    if len(sys.argv) > 1: room_name = sys.argv[1]
    window = Visualizer(room_name)
    window.setup()
    arcade.run()
