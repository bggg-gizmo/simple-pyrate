"""Rebuild the original synthesized Blackwake ambience. No external sounds."""
from pathlib import Path
import math
import random
import struct
import wave

rate = 22050
duration = 18
size = rate * duration
rng = random.Random(2020)
twopi = 2.0 * math.pi
white = [rng.uniform(-1, 1) for _ in range(size)]
channels = []
for offset in (0, size // 11):
    slow = mid = fast = 0.0
    samples = []
    # The warm-up pass starts every filter from the tail of the same noise loop.
    for i in range(-rate * 3, size):
        src = white[(i + offset) % size]
        slow += .018 * (src - slow)
        mid += .068 * (src - mid)
        fast += .29 * (src - fast)
        if i < 0:
            continue
        phase = twopi * i / size
        tide = .55 + .26 * math.sin(2 * phase - .80) + .14 * math.sin(3 * phase + 1.1 + offset / size)
        wash = (0.32 * slow + .11 * mid + .031 * (fast - mid)) * tide
        rumble = .006 * math.sin(42 * phase + .22 * math.sin(2 * phase)) + .005 * math.sin(80 * phase)
        wind = .0065 * math.sin(111 * phase + .9 * math.sin(2 * phase)) * (.45 + .30 * math.sin(phase))
        samples.append(round(32767 * (wash + rumble + wind)))
    channels.append(samples)
with wave.open(str(Path(__file__).with_name("Night-Sea.wav")), "wb") as wav:
    wav.setnchannels(2)
    wav.setsampwidth(2)
    wav.setframerate(rate)
    interleaved = [max(-32768, min(32767, val)) for pair in zip(*channels) for val in pair]
    wav.writeframes(struct.pack(f"<{len(interleaved)}h", *interleaved))
