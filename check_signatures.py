import arcade
import inspect

print(f"Arcade version: {arcade.__version__}")

# Check load_texture signature
sig = inspect.signature(arcade.load_texture)
print(f"load_texture signature: {sig}")

# Check draw_texture_rect signature
sig = inspect.signature(arcade.draw_texture_rect)
print(f"draw_texture_rect signature: {sig}")

# Check Texture.create_empty signature
sig = inspect.signature(arcade.Texture.create_empty)
print(f"Texture.create_empty signature: {sig}")
