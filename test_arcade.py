import arcade
from arcade import gl

window = arcade.Window(800, 600, "test")
tex = arcade.Texture.create_empty("test", (16, 16))
print(f"Type of tex: {type(tex)}")
print(f"Attributes of tex: {dir(tex)}")
if hasattr(tex, 'texture'):
    print(f"Type of tex.texture: {type(tex.texture)}")
    print(f"Attributes of tex.texture: {dir(tex.texture)}")
window.close()
