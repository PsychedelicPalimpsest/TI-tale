import pytest
import os
import sys
import tempfile
import json
from unittest.mock import patch, MagicMock

# Add the directory containing the modules to the path
sys.path.insert(0, os.path.dirname(__file__))

from app import SpriteRemakerApp, STATE_FILE, RoomTree
import app

import asyncio

@pytest.fixture
def clean_state():
    if os.path.exists(STATE_FILE):
        os.remove(STATE_FILE)
    yield
    if os.path.exists(STATE_FILE):
        os.remove(STATE_FILE)

def test_app_startup(clean_state):
    async def run():
        test_app = SpriteRemakerApp()
        # Mock subprocess.Popen to prevent arcade window from launching
        with patch("subprocess.Popen"):
            async with test_app.run_test() as pilot:
                # Check default state
                assert test_app.state["scale_x"] == "0.5"
                assert test_app.state["grayscale_mode"] == "luminance"
                
                # The app should not show any notifications on startup
                assert not pilot.app._notifications
    asyncio.run(run())

def test_app_reset_settings(clean_state):
    async def run():
        test_app = SpriteRemakerApp()
        with patch("subprocess.Popen"):
            async with test_app.run_test() as pilot:
                # Change a setting
                test_app.state["scale_x"] = "2.0"
                
                # Click reset button
                test_app.action_reset_settings()
                
                # State should be back to default
                assert test_app.state["scale_x"] == "0.5"
    asyncio.run(run())

def test_app_get_config(clean_state):
    async def run():
        test_app = SpriteRemakerApp()
        with patch("subprocess.Popen"):
            async with test_app.run_test() as pilot:
                config = test_app.get_config()
                assert config is not None
                assert config["scale_x"] == 0.5
                
                # Set invalid config
                test_app.state["scale_x"] = "invalid"
                config = test_app.get_config()
                assert config is None
    asyncio.run(run())

def test_app_input_changes(clean_state):
    async def run():
        test_app = SpriteRemakerApp()
        with patch("subprocess.Popen"):
            async with test_app.run_test() as pilot:
                # Click on the scale_x input and type a new value
                input_widget = test_app.query_one("#scale_x")
                input_widget.focus()
                await pilot.press("end")
                for _ in range(5):
                    await pilot.press("backspace")
                await pilot.press("1", ".", "5")
                
                # Verify that the reactive state updated
                assert test_app.state["scale_x"] == "1.5"
                
                # Trigger a select change
                test_app.query_one("#scaling_alg").value = "box"
                await pilot.pause(0.1)
                assert test_app.state["scaling_alg"] == "box"
    asyncio.run(run())

def test_app_tree_search(clean_state):
    async def run():
        # Mock glob to return some fake room files
        with patch("app.glob.glob", return_value=["/dummy/room1.room.gmx", "/dummy/room2.room.gmx", "/dummy/boss.room.gmx"]), patch("subprocess.Popen"):
            test_app = SpriteRemakerApp()
            async with test_app.run_test() as pilot:
                # Tree should have nodes for room1, room2, boss
                tree = test_app.query_one("#room_tree", RoomTree)
                
                # Give focus to the tree
                tree.focus()
                
                # Type "boss"
                await pilot.press("b", "o", "s", "s")
                
                assert test_app.search_query == "boss"
                
                # room1 and room2 should be hidden, boss should be visible
                for node in tree.root.children:
                    if node.data["name"] == "boss":
                        assert node.display is True
                    else:
                        assert node.display is False
                        
                # Press escape to clear search
                await pilot.press("escape")
                assert test_app.search_query == ""
                for node in tree.root.children:
                    assert node.display is True
    asyncio.run(run())

def test_app_tree_selection_and_export(clean_state):
    async def run():
        with patch("app.glob.glob", return_value=["/dummy/room1.room.gmx"]), patch("subprocess.Popen"):
            test_app = SpriteRemakerApp()
            async with test_app.run_test() as pilot:
                tree = test_app.query_one("#room_tree", RoomTree)
                
                # Mock Room.load_room
                mock_room = MagicMock()
                mock_room.tiles = [MagicMock(bgName="bg1")]
                mock_room.instances = [MagicMock(objName="obj1")]
                
                # Mock Object.load_object
                mock_obj = MagicMock(spriteName="spr1")
                
                with patch("app.Room.load_room", return_value=mock_room), \
                     patch("app.Object.load_object", return_value=mock_obj), \
                     patch("os.path.exists", return_value=False): # For checking if remade
                    
                    room_node = tree.root.children[0]
                    # Expand the room node to trigger data loading
                    room_node.expand()
                    await pilot.pause(0.1) # allow time for tree to update
                    
                    # Now it should have Backgrounds and Sprites nodes
                    assert len(room_node.children) == 2
                    bg_container = room_node.children[0]
                    spr_container = room_node.children[1]
                    
                    bg_container.expand()
                    await pilot.pause(0.1)
                    bg_leaf = bg_container.children[0]
                    
                    # Select the background leaf
                    class MockEvent:
                        def __init__(self, node):
                            self.node = node
                    test_app.on_tree_node_selected(MockEvent(bg_leaf))
                    await pilot.pause(0.1)
                    
                    assert test_app.selected_asset == "bg1"
                    assert test_app.selected_type == "background"
                    
                    # Now test exporting the background
                    mock_bg = MagicMock(image_path="/dummy/bg1.png")
                    with patch("app.Background.load_background", return_value=mock_bg), \
                         patch("app.os.path.exists", return_value=True), \
                         patch("app.Image.open") as mock_img_open, \
                         patch("app.process_image") as mock_proc, \
                         patch("app.os.makedirs"):
                         
                        mock_proc.return_value = MagicMock()
                        
                        # Press export button
                        test_app.action_export()
                        
                        # Verify processing and save were called
                        mock_img_open.assert_called_with("/dummy/bg1.png")
                        mock_proc.assert_called_once()
                        mock_proc.return_value.save.assert_called_once()
                        
                        # Verify batch export
                        test_app.action_batch_export("background")
                        assert mock_proc.call_count == 2
    asyncio.run(run())
