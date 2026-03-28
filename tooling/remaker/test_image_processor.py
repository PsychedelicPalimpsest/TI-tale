import pytest
from PIL import Image
import numpy as np
import os
import sys

# Add the directory containing the modules to the path
sys.path.insert(0, os.path.dirname(__file__))

from image_processor import process_image, _ordered_dither

@pytest.fixture
def sample_image():
    # Create a small RGBA image for testing
    img_array = np.zeros((10, 10, 4), dtype=np.uint8)
    img_array[0:5, 0:5] = [255, 0, 0, 255] # Red, opaque
    img_array[5:10, 5:10] = [0, 255, 0, 128] # Green, semi-transparent
    img_array[0:5, 5:10] = [0, 0, 255, 0] # Blue, transparent
    return Image.fromarray(img_array)

def test_scaling(sample_image):
    config = {"scale_x": 2.0, "scale_y": 0.5, "scaling_alg": "nearest"}
    result = process_image(sample_image, config)
    assert result.size == (20, 5)

def test_alpha_thresholding(sample_image):
    config = {"alpha_threshold": 150}
    result = process_image(sample_image, config)
    r, g, b, a = result.split()
    # The semi-transparent pixel (alpha=128) should become 0
    # The opaque pixel (alpha=255) should remain 255
    a_array = np.array(a)
    assert a_array[0, 0] == 255
    assert a_array[6, 6] == 0

def test_grayscale_mode_average(sample_image):
    config = {"grayscale_mode": "average"}
    result = process_image(sample_image, config)
    assert result.mode == "RGBA"

def test_gamma_correction(sample_image):
    config = {"gamma": 2.2}
    result = process_image(sample_image, config)
    assert result.mode == "RGBA"

def test_quantization_algorithms(sample_image):
    for alg in ["threshold", "floyd-steinberg", "ordered", "none"]:
        config = {"quantization": alg}
        result = process_image(sample_image, config)
        assert result.mode == "RGBA"

def test_gamma_only_debug(sample_image):
    config = {"grayscale_mode": "gamma_only"}
    result = process_image(sample_image, config)
    assert result.mode == "RGBA"

def test_brightness_contrast(sample_image):
    config = {"brightness": 1.5, "contrast": 1.5}
    result = process_image(sample_image, config)
    assert result.mode == "RGBA"

def test_ordered_dither(sample_image):
    gray = sample_image.convert("L")
    result = _ordered_dither(gray)
    assert result.mode == "L"
