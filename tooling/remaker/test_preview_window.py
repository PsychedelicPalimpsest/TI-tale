import pytest
import os
import sys
from unittest.mock import patch, MagicMock

# Add the directory containing the modules to the path
sys.path.insert(0, os.path.dirname(__file__))

from preview_window import PreviewWindow

def test_preview_window_init():
    # Mock arcade.Window methods to avoid actually creating an OpenGL context
    with patch('arcade.Window.__init__'), patch('arcade.set_background_color'):
        window = PreviewWindow("orig.png", "proc.png")
        assert window.orig_path == "orig.png"
        assert window.proc_path == "proc.png"

def test_preview_window_on_update():
    with patch('arcade.Window.__init__'), patch('arcade.set_background_color'):
        window = PreviewWindow("orig.png", "proc.png")
        # Try updating with non-existent files to ensure no crashes
        window.on_update(0.1)
        assert window.orig_tex is None
        assert window.proc_tex is None
