"""Generate the original MIDI scores, their audio renders, and port SFX."""
from array import array
from math import pi, sin, exp, tanh
from pathlib import Path
from random import Random
from struct import pack
from subprocess import run
from tempfile import TemporaryDirectory
import wave

ROOT = Path(__file__).resolve().parent / "audio"
ROOT.mkdir(exist_ok=True)
RATE = 22050
TICKS = 480
SONGS = [
    ("lagoon-watch", 88, [62,65,69,67, 65,62,60,57, 62,65,69,72, 70,69,65,62,
                          58,62,65,69, 67,65,62,60, 57,60,64,69, 67,64,60,62], [50,46,53,50,46,48,45,50]),
    ("the-black-tide", 121, [57,60,64,69, 67,64,60,57, 55,59,62,67, 65,62,59,55,
                             53,57,60,65, 64,60,57,53, 55,59,64,71, 69,64,60,57], [45,45,43,43,41,41,40,45]),
    ("lantern-reach", 101, [64,67,71,74, 72,71,67,64, 62,66,69,72, 71,69,66,62,
                           60,64,67,72, 71,67,64,60, 59,63,66,71, 74,71,66,64], [52,52,50,50,48,48,47,52]),
    ("storm-corsairs", 137, [62,65,69,74, 72,74,77,76, 70,69,65,62, 65,69,70,74,
                             72,76,79,77, 76,72,69,64, 65,68,71,74, 72,69,65,62], [50,50,46,46,48,48,45,50]),
]

def vlq(n):
    out = [n & 127]
    while n > 127:
        n >>= 7
        out.insert(0, (n & 127) | 128)
    return bytes(out)

def track(events, length):
    data, last = bytearray(), 0
    for tick, priority, evt in sorted(events):
        data.extend(vlq(tick-last) + evt)
        last = tick
    data.extend(vlq(max(0, length-last)) + b"\xff\x2f\0")
    return b"MTrk" + pack(">I", len(data)) + data

def write_midi(path, bpm, notes, total):
    tempo = round(60000000/bpm)
    tracks = [track([(0,0,b"\xff\x51\x03"+tempo.to_bytes(3,"big"))],total)]
    for ch, program in enumerate((21,24,42,9)):
        events = [(0,0,bytes([0xc0|ch, program]))]
        for at, dur, channel, pitch, velocity in notes:
            if channel != ch:
                continue
            events += [(at,1,bytes([0x90|ch,pitch,velocity])),(at+dur,0,bytes([0x80|ch,pitch,0]))]
        tracks.append(track(events,total))
    path.write_bytes(b"MThd"+pack(">IHHH",6,1,len(tracks),TICKS)+b"".join(tracks))

def pcm(path, samples):
    with wave.open(str(path),"wb") as file:
        file.setparams((1,2,RATE,0,"NONE","not compressed"))
        file.writeframes(array("h",(int(tanh(s)*30000) for s in samples)).tobytes())

def render_song(name, bpm, melody, roots, scratch):
    notes, beats = [], 64
    for repeat in range(4):
        for bar, base in enumerate(roots):
            t=(repeat*16+bar*2)*TICKS
            notes.extend([(t,900,2,base-12,63),(t,450,1,base,73),(t+480,400,1,base+7,57)])
            if repeat%2:
                notes.extend([(t+240,195,1,base+12,51),(t+720,200,1,base+7,49),(t+480,180,3,base+19,46)])
        for i, pitch in enumerate(melody):
            notes.append(((repeat*16*TICKS)+i*240, 216 if i%4!=3 else 275, 0,
                          pitch+(12 if repeat==2 and i%4==0 else 0), 83 if i%4==0 else 66))
    total=beats*TICKS
    write_midi(ROOT/(name+".mid"),bpm,notes,total)
    sec=60/bpm/TICKS
    mix=[0.0]*(int(total*sec*RATE)+2205)
    for at,dur,ch,pitch,vel in notes:
        start=int(at*sec*RATE)
        width=dur*sec
        hz=2*pi*440*2**((pitch-69)/12)/RATE
        amp=(.105,.085,.095,.045)[ch]*vel/100
        for n in range(min(len(mix)-start,int((width+.10)*RATE))):
            t=n/RATE
            envelope=min(t/.018,1)*exp(-max(0,t-width)*36)
            phase=n*hz
            if ch==0:
                sample=(sin(phase)+.43*sin(2*phase)+.21*sin(3*phase))*(.83+.17*sin(t*39))
            elif ch==1:
                sample=(sin(phase)+.54*sin(2*phase)+.20*sin(3*phase))*exp(-5*t)
            elif ch==2:
                sample=(sin(phase)+.26*sin(2*phase))*(.9+.1*sin(t*32))
            else:
                sample=(sin(phase)+.21*sin(3.016*phase))*exp(-8*t)
            mix[start+n]+=amp*envelope*sample
    # A short cabin reflection and clean loop boundaries.
    for n in range(len(mix)-1,1874,-1):
        mix[n]=.91*mix[n]+.13*mix[n-1875]
    path=scratch/(name+".wav")
    pcm(path, mix)
    run(["ffmpeg","-nostdin","-v","error","-y","-i",str(path),"-c:a","libmp3lame","-b:a","48k",
         str(ROOT/(name+".mp3"))],check=True)

def render_effect(name, seconds, index):
    rng=Random(2520+index)
    buf, last = [], 0.0
    for n in range(int(RATE*seconds)):
        t=n/RATE; noise=rng.uniform(-1,1); last=.88*last+.12*noise
        if name=="cannon":
            val=.79*sin(2*pi*(65*t-14*t*t))*exp(-8*t)+.72*last*exp(-5*t)+.46*noise*exp(-45*t)
        elif name=="embers":
            val=(.42*noise*(.4+.6*sin(49*t)**10)+.46*last)*exp(-5*t)
        elif name in ("boats","aboard"):
            p=(t%(.24 if name=="boats" else .14))
            val=(.45*last+.2*noise+.17*sin(280*t))*exp(-11*p)*exp(-2.3*t)
        elif name=="cargo":
            val=sum(.51*exp(-35*(t-hit))*(sin(2*pi*102*(t-hit))+.27*noise)
                    for hit in (0,.16,.37) if t>=hit)
        elif name=="hoist":
            val=.40*(sin(2*pi*(300*t+185*t*t))+.34*sin(2*pi*640*t))*sin(pi*t/seconds)**2*exp(-1.6*t)
        else:
            val=(.48*sin(2*pi*84*t)+.64*last+.34*noise)*exp(-4*t)
        buf.append(val*min(1,t/.005,max(0,(seconds-t)/.04)))
    pcm(ROOT/(name+".wav"),buf)

def render_ship_bell(name, strikes):
    """Synthesize a struck bronze ship bell with inharmonic ringing modes."""
    gap, tail = 16317, 45500
    modes = ((1.00,.92,2.8), (1.98,.69,3.9), (2.42,.63,4.6),
             (2.95,.43,5.5), (4.14,.32,8.2), (5.34,.19,10.9), (6.58,.10,13.8))
    single = []
    for i in range(tail):
        t = i / RATE
        edge = min(1.0, t / .004, (tail - 1 - i) / (RATE * .036))
        metal = sum(amp * sin(2 * pi * 244 * ratio * t + k * .29) * exp(-damp * t)
                    for k, (ratio, amp, damp) in enumerate(modes))
        strike = (.42 * sin(2 * pi * 1720 * t) + .18 * sin(2 * pi * 2890 * t)) * exp(-102 * t)
        single.append(edge * (.44 * metal + strike))
    samples = [0.0] * ((strikes - 1) * gap + tail)
    for strike in range(strikes):
        strength = 1.0 - (strike % 3) * .035
        for i, value in enumerate(single):
            samples[strike * gap + i] += strength * value
    pcm(ROOT/(name+".wav"), samples)

if __name__ == "__main__":
    with TemporaryDirectory() as tmp:
        for song in SONGS:
            render_song(*song,Path(tmp))
    for i,(name,length) in enumerate(zip(("cannon","embers","boats","cargo","hoist","aboard","ruins"),(1.0,.55,.70,.58,.85,.55,.91))):
        render_effect(name,length,i)
    for name, strikes in (("ship-bell-start",3), ("ship-bell-port",2), ("ship-bell-finish",5)):
        render_ship_bell(name, strikes)
