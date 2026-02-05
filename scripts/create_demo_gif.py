from PIL import Image, ImageDraw, ImageFont
import textwrap
import os

IMG_PATH = "/Users/ram/.gemini/antigravity/brain/813d7619-16b0-459a-98d2-df3f06304e95/uploaded_media_2_1770249790484.jpg"
OUTPUT_PATH = "demo/demo.gif"
ORIGINAL_WIDTH = 400
BUBBLE_Y_START = 247
BUBBLE_BG = (244, 244, 244) # Slightly lighter than probe to be safe, or stick to probe (238,238,238)
PROBE_COLOR = (238, 238, 238)

# Load and Resize
img = Image.open(IMG_PATH)
ratio = ORIGINAL_WIDTH / img.width
height = int(img.height * ratio)
base_frame = img.resize((ORIGINAL_WIDTH, height), Image.Resampling.LANCZOS)

# Metrics updating logic
# We need to overlay the "Speed" metric text.
# The metrics are at the top.
# Let's find the "33.0 tok/s" location.
# It's in the middle metric item.
# Top is around y=130?
# I'll overwrite the speed metric area with a white/green patch and write numbers? 
# Maybe too complex. The screenshot already says "33.0 tok/s".
# I'll just leave the metrics static (it's an "average" speed demo).
# Or I could animate it from 0 to 33.
# I'll keep it simple for now.

# Text to stream
full_text = """The correct answer is Paris. The capital of France is indeed Paris, which has been the country's capital since 987 AD when it was founded as an independent city-state.

Here are some interesting facts about Paris:

* Paris has a population of over 2.1 million people and is home to famous landmarks like the Eiffel Tower, Notre-Dame Cathedral, and the Louvre Museum.
* The city's official language is French, but many residents also speak English fluently."""

# Font
try:
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 13) # Size 13 matches screenshot approx
except:
    font = ImageFont.load_default()

# Wrap text
lines = []
for para in full_text.split('\n'):
    if not para:
        lines.append("")
        continue
    lines.extend(textwrap.wrap(para, width=50))

# Animation
frames = []
tokens_per_frame = 3 # Fast stream
total_chars = sum(len(l) for l in lines)
current_chars = 0

# Create frames
# We'll regenerate the lines progressively
flat_text = ""

# Pre-calculate bubble box to clear
# From y=247 to bottom (minus some margin)
clear_box = (20, BUBBLE_Y_START + 10, ORIGINAL_WIDTH - 20, height - 100)

count = 0
while count < len(full_text):
    frame = base_frame.copy()
    draw = ImageDraw.Draw(frame)
    
    # Clear the text area
    draw.rectangle(clear_box, fill=PROBE_COLOR)
    
    # Add text
    chunk = full_text[:count]
    
    # Draw text line by line
    y_text = BUBBLE_Y_START + 20
    x_text = 35
    
    # Manual wrap for the current chunk
    # We need to preserve newlines
    chunk_lines = []
    for para in chunk.split('\n'):
        if not para:
            chunk_lines.append("")
            continue
        chunk_lines.extend(textwrap.wrap(para, width=46))
        
    for line in chunk_lines:
        if y_text > height - 120: break # Clip
        draw.text((x_text, y_text), line, font=font, fill=(0,0,0))
        y_text += 18 # Line height
        
    frames.append(frame)
    
    # Speed up: Accelerate
    count += 5 # 5 chars per frame -> ~20fps -> 100 chars/sec -> 25 toks/sec. Close to 33.

# Add pause at end
for _ in range(30):
    frames.append(frames[-1])

# Save
frames[0].save(OUTPUT_PATH, save_all=True, append_images=frames[1:], duration=50, loop=0)
print(f"Saved {OUTPUT_PATH}")
