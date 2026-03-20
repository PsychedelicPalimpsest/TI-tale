import arcade
from arcade import gl

window = arcade.Window(800, 600, "test")
gl_tex = window.ctx.texture((16, 16))
print(f"Type of gl_tex: {type(gl_tex)}")
print(f"Attributes of gl_tex: {dir(gl_tex)}")
if hasattr(gl_tex, 'filter'):
    print(f"Current filter: {gl_tex.filter}")
    gl_tex.filter = (gl.NEAREST, gl.NEAREST)
    print(f"New filter: {gl_tex.filter}")
window.close()
