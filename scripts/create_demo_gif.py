from PIL import Image, ImageDraw, ImageFont
import textwrap

IMG_PATH = "/Users/ram/.gemini/antigravity/brain/813d7619-16b0-459a-98d2-df3f06304e95/uploaded_media_2_1770249790484.jpg"
OUTPUT_PATH = "demo/demo.gif"
ORIGINAL_WIDTH = 400
BUBBLE_Y_START = 247
PROBE_COLOR = (238, 238, 238)

# Load and Resize
img = Image.open(IMG_PATH)
ratio = ORIGINAL_WIDTH / img.width
height = int(img.height * ratio)
base_frame = img.resize((ORIGINAL_WIDTH, height), Image.Resampling.LANCZOS)

# --- PATCH THE TTFT NUMBER ---
# Create a fresh draw object
draw_base = ImageDraw.Draw(base_frame)

# The TTFT metrics are in a light blue/green box at the top
# From the uploaded image, "6246ms" appears around y=165-195 (after scaling)
# Let's sample the background color from a safe area
bg_color = base_frame.getpixel((200, 150))  # Sample from right side of metrics bar

# Cover the entire "6246ms" text area with background
# Being generous with the box to ensure full coverage
patch_box = (45, 165, 135, 200)
draw_base.rectangle(patch_box, fill=bg_color)

# Write "320ms" in the same style
try:
    font_metric = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 32)
except:
    font_metric = ImageFont.load_default()

# Use a dark blue color similar to the original
draw_base.text((52, 165), "320ms", font=font_metric, fill=(27, 94, 32))  # Dark green-blue
# -----------------------------

# Text to stream
full_text = """The correct answer is Paris. The capital of France is indeed Paris, which has been the country's capital since 987 AD when it was founded as an independent city-state.

Here are some interesting facts about Paris:

* Paris has a population of over 2.1 million people and is home to famous landmarks like the Eiffel Tower, Notre-Dame Cathedral, and the Louvre Museum.
* The city's official language is French, but many residents also speak English fluently."""

try:
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 13)
except:
    font = ImageFont.load_default()

frames = []
count = 0

# Clear box for text
clear_box = (20, BUBBLE_Y_START + 10, ORIGINAL_WIDTH - 20, height - 100)

while count < len(full_text):
    frame = base_frame.copy()
    draw = ImageDraw.Draw(frame)
    
    draw.rectangle(clear_box, fill=PROBE_COLOR)
    
    chunk = full_text[:count]
    chunk_lines = []
    for para in chunk.split('\n'):
        if not para:
            chunk_lines.append("")
            continue
        chunk_lines.extend(textwrap.wrap(para, width=46))
        
    y_text = BUBBLE_Y_START + 20
    x_text = 35
    for line in chunk_lines:
        if y_text > height - 120: break
        draw.text((x_text, y_text), line, font=font, fill=(0,0,0))
        y_text += 18
        
    frames.append(frame)
    count += 5

# Hold final frame
for _ in range(30):
    frames.append(frames[-1])

frames[0].save(OUTPUT_PATH, save_all=True, append_images=frames[1:], duration=50, loop=0)
print(f"Saved {OUTPUT_PATH} with {len(frames)} frames")
