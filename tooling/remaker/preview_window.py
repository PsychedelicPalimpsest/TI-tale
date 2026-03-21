import arcade
import sys
import os
import time

class PreviewWindow(arcade.Window):
    def __init__(self, orig_path, proc_path):
        super().__init__(800, 400, "Live Preview", resizable=True)
        self.orig_path = orig_path
        self.proc_path = proc_path
        
        self.orig_tex = None
        self.proc_tex = None
        
        self.orig_mtime = 0
        self.proc_mtime = 0

        self.set_update_rate(1/30) # 30 fps
        arcade.set_background_color(arcade.color.DARK_GRAY)

    def on_update(self, delta_time):
        # Check if files changed
        try:
            import PIL.Image
            if os.path.exists(self.orig_path) and os.path.getsize(self.orig_path) > 0:
                mtime = os.path.getmtime(self.orig_path)
                if mtime != self.orig_mtime:
                    img = PIL.Image.open(self.orig_path).convert("RGBA")
                    img.load()
                    self.orig_tex = arcade.Texture(img, hash=f"orig_{mtime}")
                    self.orig_mtime = mtime
                    
            if os.path.exists(self.proc_path) and os.path.getsize(self.proc_path) > 0:
                mtime = os.path.getmtime(self.proc_path)
                if mtime != self.proc_mtime:
                    img = PIL.Image.open(self.proc_path).convert("RGBA")
                    img.load()
                    self.proc_tex = arcade.Texture(img, hash=f"proc_{mtime}")
                    self.proc_mtime = mtime
        except Exception as e:
            pass # File might be written to concurrently

    def on_draw(self):
        self.clear()
        
        # Draw split screen
        half_width = self.width / 2
        
        arcade.draw_text("Original", 10, self.height - 20, arcade.color.WHITE)
        arcade.draw_text("TI-84 Processed", half_width + 10, self.height - 20, arcade.color.WHITE)
        
        # Draw divider
        arcade.draw_line(half_width, 0, half_width, self.height, arcade.color.BLACK, 2)
        
        # Draw checkerboard background for transparency (optional, but let's just use dark gray for now)
        
        if self.orig_tex:
            scale = min((half_width - 40) / self.orig_tex.width, (self.height - 40) / self.orig_tex.height) if self.orig_tex.width > 0 else 1
            if scale > 1: scale = int(scale) # integer scaling for pixel art
            arcade.draw_texture_rect(self.orig_tex, arcade.Rect.from_kwargs(x=half_width/2, y=self.height/2, width=self.orig_tex.width*scale, height=self.orig_tex.height*scale), pixelated=True)
            
        if self.proc_tex:
            scale = min((half_width - 40) / self.proc_tex.width, (self.height - 40) / self.proc_tex.height) if self.proc_tex.width > 0 else 1
            if scale > 1: scale = int(scale)
            arcade.draw_texture_rect(self.proc_tex, arcade.Rect.from_kwargs(x=half_width + half_width/2, y=self.height/2, width=self.proc_tex.width*scale, height=self.proc_tex.height*scale), pixelated=True)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python preview_window.py <orig_img> <proc_img>")
        sys.exit(1)
    
    window = PreviewWindow(sys.argv[1], sys.argv[2])
    arcade.run()
