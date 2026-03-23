import numpy as np
from PIL import Image, ImageEnhance
import os

TI_PALETTE_RGBA = [
    (0, 0, 0, 255),       # Black
    (85, 85, 85, 255),    # Dark Grey
    (170, 170, 170, 255), # Light Grey
    (255, 255, 255, 255), # White
    (173, 216, 230, 0)    # Transparent (Light Blue placeholder, we'll keep alpha 0 internally)
]

# A pure PIL palette image for the 4 colors
def create_palette_image():
    pal_img = Image.new("P", (1, 1))
    # Fill palette with the 4 shades of grey (RGB)
    palette_data = [
        0, 0, 0,
        85, 85, 85,
        170, 170, 170,
        255, 255, 255
    ]
    # Pad to 256 colors
    palette_data.extend([0] * (256 * 3 - len(palette_data)))
    pal_img.putpalette(palette_data)
    return pal_img

TI_PAL_IMG = create_palette_image()

RESAMPLING_METHODS = {
    "nearest": Image.Resampling.NEAREST,
    "box": Image.Resampling.BOX,
    "bilinear": Image.Resampling.BILINEAR,
    "hamming": Image.Resampling.HAMMING,
    "bicubic": Image.Resampling.BICUBIC,
    "lanczos": Image.Resampling.LANCZOS,
}

# Bayer matrix for ordered dithering
BAYER_MATRIX_4X4 = np.array([
    [ 0,  8,  2, 10],
    [12,  4, 14,  6],
    [ 3, 11,  1,  9],
    [15,  7, 13,  5]
]) / 16.0

def _ordered_dither(img: Image.Image) -> Image.Image:
    """Applies ordered dithering using a 4x4 Bayer matrix to a grayscale image, mapping to 4 colors."""
    arr = np.array(img, dtype=np.float32) / 255.0  # Range 0.0 - 1.0
    h, w = arr.shape
    
    # Repeat the bayer matrix over the whole image
    bayer = np.tile(BAYER_MATRIX_4X4, (int(np.ceil(h / 4)), int(np.ceil(w / 4))))
    bayer = bayer[:h, :w]
    
    # The 4 color levels are roughly 0.0, 0.33, 0.66, 1.0. 
    # We want 3 intervals. We multiply by 3, add the bayer matrix offset (centered around 0.5), and floor.
    # bayer matrix is 0 to 15/16. Let's shift it to -0.5 to +0.5
    bayer_shifted = bayer - 0.5
    
    # Scale pixel values to 0-3 range
    val = arr * 3.0
    
    # Add dithering noise
    dithered = np.clip(np.round(val + bayer_shifted), 0, 3)
    
    # Map back to 0-255
    out = (dithered * (255 / 3)).astype(np.uint8)
    return Image.fromarray(out)

def process_image(img: Image.Image, config: dict) -> Image.Image:
    """
    Processes an image based on the provided configuration dictionary.
    
    config keys:
    - scale_x: float (e.g., 0.5)
    - scale_y: float (e.g., 0.5)
    - scaling_alg: str ('nearest', 'box', 'bilinear', 'bicubic', 'lanczos')
    - brightness: float (1.0 = normal)
    - contrast: float (1.0 = normal)
    - grayscale_mode: str ('luminance', 'average')
    - alpha_threshold: int (0-255, alpha < this becomes transparent)
    - quantization: str ('threshold', 'floyd-steinberg', 'ordered')
    """
    img = img.convert("RGBA")
    
    # 1. Scaling
    scale_x = config.get("scale_x", 1.0)
    scale_y = config.get("scale_y", 1.0)
    if scale_x != 1.0 or scale_y != 1.0:
        new_w = max(1, int(img.width * scale_x))
        new_h = max(1, int(img.height * scale_y))
        resample = RESAMPLING_METHODS.get(config.get("scaling_alg", "nearest"), Image.Resampling.NEAREST)
        img = img.resize((new_w, new_h), resample)

    # Separate alpha channel after scaling
    r, g, b, a = img.split()
    
    # 2. Alpha Thresholding
    alpha_thresh = config.get("alpha_threshold", 128)
    a_arr = np.array(a)
    a_arr = np.where(a_arr >= alpha_thresh, 255, 0).astype(np.uint8)
    a_clean = Image.fromarray(a_arr)

    # Recombine to RGB for color processing
    rgb_img = Image.merge("RGB", (r, g, b))

    # 3. Brightness & Contrast
    if config.get("brightness", 1.0) != 1.0:
        enhancer = ImageEnhance.Brightness(rgb_img)
        rgb_img = enhancer.enhance(config.get("brightness", 1.0))
    if config.get("contrast", 1.0) != 1.0:
        enhancer = ImageEnhance.Contrast(rgb_img)
        rgb_img = enhancer.enhance(config.get("contrast", 1.0))

    # 4. Grayscale Conversion
    mode = config.get("grayscale_mode", "luminance")
    if mode == "average":
        arr = np.array(rgb_img, dtype=np.uint16)
        avg = (arr[:,:,0] + arr[:,:,1] + arr[:,:,2]) // 3
        gray_img = Image.fromarray(avg.astype(np.uint8))
    else: # 'luminance' or 'gamma_only'
        gray_img = rgb_img.convert("L")

    # 5. Gamma Correction
    gamma = config.get("gamma", 1.0)
    if gamma != 1.0 and gamma > 0:
        inv_gamma = 1.0 / gamma
        table = [int(((i / 255.0) ** inv_gamma) * 255) for i in range(256)]
        gray_img = gray_img.point(table)

    # If in gamma debug mode, we can return the raw gamma-adjusted image now
    if config.get("grayscale_mode") == "gamma_only":
        final_rgba = Image.new("RGBA", gray_img.size)
        final_rgba.paste(gray_img.convert("RGB"), mask=a_clean)
        return final_rgba

    # 6. Quantization / Dithering
    quant_alg = config.get("quantization", "threshold")
    
    if quant_alg == "floyd-steinberg":
        gray_img = gray_img.convert("RGB").quantize(palette=TI_PAL_IMG, dither=Image.Dither.FLOYDSTEINBERG)
        gray_img = gray_img.convert("L")
    elif quant_alg == "ordered":
        gray_img = _ordered_dither(gray_img)
    elif quant_alg != "none": # threshold is the default
        gray_img = gray_img.convert("RGB").quantize(palette=TI_PAL_IMG, dither=Image.Dither.NONE)
        gray_img = gray_img.convert("L")
    
    # 7. Re-apply Transparency
    final_rgba = Image.new("RGBA", gray_img.size)
    final_rgba.paste(gray_img.convert("RGB"), mask=a_clean)
    
    return final_rgba
