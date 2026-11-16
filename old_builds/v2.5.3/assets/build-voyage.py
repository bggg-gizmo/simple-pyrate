"""Generate the original, compositable voyage art. Requires Python 3 + Inkscape to rebuild."""
from pathlib import Path
from math import sin, cos, pi
import random
import subprocess
import tempfile

DEST = Path(__file__).with_name("voyage")
DEST.mkdir(exist_ok=True)
PALETTE = {
    "moon": "#f6dbad", "mist": "#8cb9ad", "water": "#3e756d",
    "land": "#0b1922", "land_edge": "#23464b", "gold": "#edbb74",
}
DEFS = """
<linearGradient id="sky" x2="0" y2="1" gradientUnits="objectBoundingBox">
<stop stop-color="#09111f"/><stop offset=".58" stop-color="#263948"/><stop offset=".76" stop-color="#4a6564"/><stop offset="1" stop-color="#13252c"/>
</linearGradient>
<linearGradient id="sea" x2="0" y2="1"><stop stop-color="#395c61"/><stop offset=".28" stop-color="#17383f"/><stop offset="1" stop-color="#071822"/></linearGradient>
<radialGradient id="halo"><stop stop-color="#ecd5a9" stop-opacity=".61"/><stop offset=".25" stop-color="#bda883" stop-opacity=".35"/><stop offset=".56" stop-color="#95b1a9" stop-opacity=".12"/><stop offset="1" stop-color="#95b1a9" stop-opacity="0"/></radialGradient>
<linearGradient id="moon" x2=".75" y2="1"><stop stop-color="#fbebc9"/><stop offset=".55" stop-color="#e6c994"/><stop offset="1" stop-color="#a0a48b"/></linearGradient>
<linearGradient id="rock" x2=".75" y2="1"><stop stop-color="#2d5054"/><stop offset=".37" stop-color="#152d34"/><stop offset="1" stop-color="#08151e"/></linearGradient>
<linearGradient id="rig" x2=".7" y2="1"><stop stop-color="#cabb9e"/><stop offset=".32" stop-color="#918c73"/><stop offset="1" stop-color="#364a46"/></linearGradient>
<linearGradient id="saildark" x2=".55" y2="1"><stop stop-color="#718273"/><stop offset="1" stop-color="#283d3d"/></linearGradient>
<linearGradient id="hull" x2="0" y2="1"><stop stop-color="#60493a"/><stop offset=".34" stop-color="#292d2a"/><stop offset="1" stop-color="#08151b"/></linearGradient>
<linearGradient id="brick" x2=".7" y2="1"><stop stop-color="#49615d"/><stop offset=".5" stop-color="#273d40"/><stop offset="1" stop-color="#132629"/></linearGradient>
<radialGradient id="lamp"><stop stop-color="#ffe6a2" stop-opacity=".78"/><stop offset=".35" stop-color="#f9b468" stop-opacity=".34"/><stop offset="1" stop-color="#f0a850" stop-opacity="0"/></radialGradient>
<radialGradient id="fog"><stop stop-color="#92bab1" stop-opacity=".21"/><stop offset=".48" stop-color="#779e97" stop-opacity=".12"/><stop offset="1" stop-color="#9bc0b3" stop-opacity="0"/></radialGradient>
<clipPath id="moonclip"><circle cx="844" cy="110" r="57"/></clipPath>
"""

def path(d, fill="none", stroke=None, width=1, op=1):
    line = f' stroke="{stroke}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"' if stroke else ""
    return f'<path d="{d}" fill="{fill}"{line} opacity="{op}"/>'

def circle(x, y, r, fill, op=1):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" opacity="{op}"/>'

def ellipse(x, y, a, b, fill, op=1):
    return f'<ellipse cx="{x}" cy="{y}" rx="{a}" ry="{b}" fill="{fill}" opacity="{op}"/>'

def rect(x, y, w, h, fill, op=1):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" opacity="{op}"/>'

def group(items, transform="", opacity=1):
    return f'<g transform="{transform}" opacity="{opacity}">' + "".join(items) + '</g>'

def svg(w, h, items):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><defs>{DEFS}</defs>' + "".join(items) + '</svg>'

def render(name, w, h, items):
    target = DEST / (name + ".png")
    with tempfile.TemporaryDirectory(prefix="pyrate-svg-") as tmp:
        source = Path(tmp) / (name + ".svg")
        source.write_text(svg(w, h, items), encoding="utf-8")
        subprocess.run(["inkscape", str(source), "--export-background-opacity=0", f"--export-filename={target}"], check=True, capture_output=True)

rng = random.Random(2502)
sky = [rect(0,0,1200,390,"url(#sky)"),
       ellipse(844,112,350,227,"url(#halo)",.65),
       ellipse(834,117,155,110,"url(#halo)",.78)]
for i in range(175):
    x,y=rng.uniform(0,1200),rng.uniform(3,223)
    brightness=rng.uniform(.18,.84)
    if ((x-844)/77)**2+((y-107)/67)**2 < 1:
        continue
    r=rng.choices([.47,.72,1.05,1.7],[25,43,17,2])[0]
    sky.append(circle(round(x,1),round(y,1),r, "#f8e8c1" if i%3==0 else "#b0cec6", round(brightness,2)))
for x,y in [(476,55),(698,70),(1037,73),(1116,155),(745,29),(942,32),(156,61)]:
    sky.append(path(f"M{x-4},{y}h8 M{x},{y-4}v8",stroke="#a9c4bc",op=.57))
    sky.append(circle(x,y,1.3,"#f9e6bf"))
sky.append(circle(844,110,57,"url(#moon)"))
craters=[]
for i in range(25):
    x,y=rng.uniform(787,903),rng.uniform(54,166); r=rng.uniform(2,14)
    craters.append(ellipse(round(x,1),round(y,1),round(r,1),round(r*.58,1),"#746e61",.11))
craters += [path("M802,88 Q821,66 834,77 Q847,81 843,96 Q829,101 827,109 Q811,112 803,108 Z", "#786e60", op=.16),
            path("M872,123 Q896,111 904,126 L902,151 Q877,158 861,144 Z","#6a695f",op=.19)]
sky.append('<g clip-path="url(#moonclip)">'+"".join(craters)+"</g>")
for x,y,a,b,op in [(91,161,260,30,.38),(331,173,370,19,.46),(793,141,365,23,.33),(1059,113,209,19,.33)]:
    sky.append(ellipse(x,y,a,b,"url(#fog)",op))
sky += [path("M0,250 Q56,232 99,234 Q150,243 184,221 Q218,230 256,235 Q296,238 346,248 Q380,242 434,239 Q467,244 510,253 Q544,252 594,245 Q642,245 705,253 Q761,244 819,244 Q891,251 945,247 Q1005,236 1057,242 Q1104,230 1200,238 L1200,281 H0Z","#173039",op=.86),
        rect(0,253,1200,137,"url(#sea)"),ellipse(844,273,223,47,"url(#halo)",.45),
        path("M0,255 C290,250 370,256 570,254 S985,257 1200,252",stroke="#80988e",width=.8,op=.38)]
for i in range(250):
    y=rng.uniform(256,391); width=(y-252)/140; x=rng.uniform(-100,1250)
    l=rng.uniform(2,45)*(width+.35)
    color="#b1b19a" if abs(x-844)<(18+width*173) else ( "#80a29a" if i%3 else "#638481")
    sky.append(path(f"M{x:.1f},{y:.1f}q{l*.45:.2f},-1 {l:.2f},0",stroke=color,width=round(rng.uniform(.4,1.15),2),op=round(rng.uniform(.10,.52 if color=="#b1b19a" else .27),2)))
render("sea-and-sky",1200,390,sky)

lagoon = [
    path("M0,81 L23,102 L59,103 L85,133 L112,131 L133,149 L152,153 L180,181 L204,187 L216,206 L239,216 L279,219 L296,229 L331,238 L373,257 L414,267 L402,290 L314,308 L0,325Z","url(#rock)"),
    path("M0,143 L36,139 73,157 91,153 115,177 162,178 177,204 205,222 251,230 285,246 320,250 381,276 252,288 0,319Z","#0b1d26"),
    path("M1200,65 L1170,79 1149,103 1120,106 1096,145 1060,149 1050,167 1018,172 998,202 958,216 935,231 947,251 972,267 1040,280 1169,267 1200,265Z","url(#rock)"),
    path("M1200,120 L1160,144 1126,139 1117,164 1082,183 1063,182 1050,208 1017,207 988,238 1010,253 1072,257 1200,266Z","#0d2027"),
    path("M0,309 Q102,303 200,313 Q277,328 375,321 L432,329 398,343 224,365 0,373Z","#102931"),
    path("M1200,278 Q1155,274 1109,290 L1061,294 1041,308 1090,311 1200,306Z","#113039"),
]
for x,y,flip in [(30,108,1),(83,137,1),(145,156,1),(190,188,1),(251,228,1),(367,257,1),(1155,110,-1),(1120,141,-1),(1045,179,-1),(985,221,-1)]:
    lagoon.append(path(f"M{x},{y}q{20*flip},8 {40*flip},11 l{20*flip},15", stroke="#64817b",width=1.5,op=.34))
def pine(x,y,h,opacity):
    return group([path("M0,0 L-4,19 -2,18 -11,31 -6,29 -17,43 -7,40 -21,53 -1,48 -1,58 2,58 2,47 21,53 9,40 15,44 7,28 10,31 3,18 6,20Z","#071821")],f"translate({x},{y-h}) scale({h/58})",opacity)
for x,y,h in [(6,101,54),(23,112,31),(49,117,46),(74,134,29),(106,158,42),(128,158,24),(170,185,36),(222,222,20),(270,232,24),(1147,108,42),(1165,102,54),(1188,96,43),(1110,142,21),(1077,164,20),(1030,197,28)]:
    lagoon.append(pine(x,y,h,.95))
lagoon += [ellipse(155,257,181,16,"url(#fog)",.65),
           path("M210,269h98l75,13-19,8-68-12h-93z","#352e28",stroke="#655646",op=.87),
           path("M223,270v24 M248,274v27 M279,275v23 M310,278v22 M345,284v18 M368,285v18",stroke="#665345",width=2.4,op=.81)]
for x,y in [(222,272),(286,277),(358,285),(999,245)]:
    lagoon.extend([ellipse(x,y-6,19,17,"url(#lamp)",.88),path(f"M{x},{y-8}v16",stroke="#373633",width=2.4),rect(x-2,y-10,4,6,"#fad08a")])
render("lagoon",1200,390,lagoon)

ship = [
    path("M39,157 Q111,174 195,180 Q287,181 352,160 L383,145 372,171 Q352,191 322,203 Q213,224 103,205 L77,195 58,170Z","url(#hull)", "#887357", 1.9),
    path("M51,163 Q126,185 210,188 Q312,187 371,155 M85,188 Q215,217 352,177 M114,198 Q225,222 333,190",stroke="#a27b55",width=1.9,op=.75),
    path("M64,164 L60,132 111,138 130,172 M302,171 L308,157 356,147 371,153 M86,137 L79,124 110,131 118,144","url(#hull)","#948266",1.65),
    path("M89,43 L100,173 M169,15 L174,182 M263,27 L267,180 M315,68 L334,160 M356,159 L400,135",stroke="#ad9270",width=3),
    path("M72,61 L115,56 M68,96 L126,93 M63,127 L138,118 M107,48 L206,39 M101,90 L215,77 M93,132 L229,117 M223,61 L295,56 M214,100 L308,85 M210,137 L317,117",stroke="#c0a580",width=2.4),
    path("M81,63 L54,129 74,161 M172,26 L78,164 M171,26 L345,166 M265,42 L137,173 M265,42 L377,152 M316,71 L392,139 M89,53 L179,35 270,45 328,73",stroke="#657d77",width=1.05,op=.94),
    path("M112,50 Q156,51 204,42 Q206,66 216,80 Q159,83 106,88 Q121,70 112,50 Z","url(#rig)","#bfab86",1.03),
    path("M105,92 Q156,91 214,81 Q218,114 229,124 Q174,128 95,139 Q116,117 105,92Z","url(#rig)","#b9a585",1.12),
    path("M230,62 Q260,65 293,58 Q295,76 306,89 Q266,89 220,99 Q235,79 230,62Z","url(#saildark)","#ad9a7a",1.03),
    path("M220,99 Q266,102 307,91 Q312,113 321,124 Q275,132 215,142 Q229,119 220,99Z","url(#rig)","#beab85",1.08),
    path("M75,63 L114,58 Q116,74 123,93 L65,100 Q77,80 75,63Z","url(#saildark)","#a99a7d",1.02),
    path("M71,101 L124,97 Q127,113 137,121 L62,133 Q73,115 71,101Z","url(#saildark)","#938b73",1.03),
    path("M318,72 Q354,96 392,133 L338,153 Q347,119 318,72Z","url(#saildark)","#afa080",1.03),
    path("M128,59 Q143,73 129,83 M183,47 Q178,68 194,79 M126,99 Q140,115 123,133 M186,88 Q179,112 201,127 M248,68 Q252,83 245,91 M276,104 Q273,119 285,126 M329,85 Q362,112 369,133",stroke="#333e39",width=1.15,op=.48),
    path("M171,17 Q190,9 211,16 Q229,25 253,13 Q245,27 228,32 Q204,37 190,24 L171,29Z","#392a35","#a5867e",.85),
    path("M261,31 Q272,24 291,28 Q300,34 313,24 Q311,39 291,41 Q277,35 262,38Z","#1d333a","#869385",.7),
    path("M167,97 C154,98 149,107 155,114 L160,115 161,120 174,118 174,113 C181,106 177,97 167,97Z","#293a39",op=.82),
    circle(161,107,2.4,"#9e9479",.88),circle(171,106,2.4,"#9e9479",.88),
    path("M150,117l33,9 M182,115l-31,14",stroke="#293a39",width=2.5,op=.82),
]
for i in range(7):
    x=120+i*31; y=184+5*sin(i/6*pi)
    ship.extend([rect(x,y,14,8,"#0c151b"),path(f"M{x},{y}h14",stroke="#b18a63",width=.7,op=.82),
                 circle(x+8,y+4,1.6,"#b46f47",.91)])
for x,y in [(78,138),(90,142),(106,146),(199,189),(330,172),(365,151)]:
    ship.extend([ellipse(x,y,12,10,"url(#lamp)",.84),rect(x-1.8,y-2.1,3.6,4.2,"#ecc486")])
render("pyrate-ship",415,221,ship)

def tower(x,y,w,h,style,roof="#193338"):
    if style=="keep":
        outline=path(f"M{x},{y+h} V{y} h8 v-8 h8 v8 h10 v-8 h8 v8 h10 v-8 h8 v8 H{x+w} V{y+h}Z","url(#brick)","#799087",.92)
    elif style=="lighthouse":
        outline=path(f"M{x},{y+h} L{x+8},{y+12} H{x+w-8} L{x+w},{y+h} Z M{x+4},{y+11} L{x+w/2},{y-15} {x+w-4},{y+11}Z","url(#brick)","#8c9382",1.08)
    else:
        outline=path(f"M{x},{y+h} V{y+12} H{x+w} V{y+h}Z M{x-4},{y+14} L{x+w/2},{y-11} {x+w+4},{y+14}Z","url(#brick)","#738b82",.83)
    pieces=[outline]
    if style=="lighthouse":
        pieces += [ellipse(x+w/2,y+16,47,35,"url(#lamp)",.75),rect(x+w/2-6,y+11,12,12,"#fbe1a1",.8),path(f"M{x+2},{y+27}h{w-4}",stroke="#9b9b82",width=1.2)]
    for i in range(int((h-21)/13)):
        yy=y+33+i*13
        pieces.append(path(f"M{x+3},{yy}h{w-6} m{-w*.55},0v5",stroke="#859185",width=.55,op=.33))
    for xx in range(int(x+12),int(x+w-9),17):
        yy=y+32 if style!="lighthouse" else y+45
        pieces += [ellipse(xx+1,yy+2,11,10,"url(#lamp)",.85),path(f"M{xx},{yy}q2,-4 4,0v6h-4z","#dfad65",op=.89)]
    return pieces

styles = [
    ("ember-quay", 0, [("house",805,230,46,56),("house",857,212,38,80),("keep",903,174,57,112),("house",965,231,54,63),("keep",1024,153,54,127),("house",1091,207,47,88),("lighthouse",1149,176,35,115)]),
    ("bonewatch", 1, [("house",801,239,48,54),("keep",855,183,58,105),("keep",922,128,59,152),("house",989,216,47,73),("keep",1038,168,48,121),("house",1090,196,44,90),("keep",1141,140,55,150)]),
    ("lantern-reach", 2, [("house",803,225,45,61),("lighthouse",855,146,38,140),("house",902,236,48,58),("house",952,212,44,78),("house",1001,227,40,73),("keep",1048,191,66,104),("house",1120,211,67,79)]),
    ("ghostwater", 3, [("keep",798,207,49,87),("house",856,216,53,75),("lighthouse",918,172,40,119),("house",970,224,41,73),("keep",1017,170,63,123),("keep",1090,146,67,157),("house",1161,210,39,89)]),
]
for name,variant,buildings in styles:
    port=[path("M738,271 Q833,249 881,250 Q983,215 1126,230 L1200,195 V303 L1130,317 1024,319 933,302 839,311 752,306Z","url(#rock)")]
    for typ,x,y,w,h in buildings:
        port += tower(x,y,w,h,typ)
    port += [path("M785,279 Q900,272 987,273 Q1080,279 1200,266 L1200,299 Q1097,303 1001,297 Q889,297 781,305Z","url(#brick)","#748a80",1),
             path("M780,313 Q845,296 878,302 T1009,313 T1170,306 L1200,307 V339 Q1100,341 968,330 T780,331Z","#0d2328")]
    for i in range(15):
        x=799+28*i; y=285+3*sin(i/3)
        port.extend([path(f"M{x},{y-2}v14 m5,-14v14",stroke="#728780",width=.74,op=.49),
                     ellipse(x+1,y-10,12,12,"url(#lamp)",.8),
                     circle(x+1,y-10,1.7,"#eec675",.9)])
    for x,y in [(895,169),(1026,153),(1137,141)]:
        y += variant*4
        port.extend([path(f"M{x},{y}v-24",stroke="#7b756a",width=1.25),
                     path(f"M{x},{y-23}l21,3-14,5-7,-2z","#593943","#7a5556",.62)])
    render("port-"+str(variant),1200,390,port)

fog=[]
for x,y,a,b,op in [(110,260,210,48,.55),(386,253,277,35,.64),(795,247,315,27,.56),(1095,252,255,33,.46),
                   (113,318,315,37,.43),(696,316,381,31,.44),(1020,321,290,25,.31)]:
    fog.append(ellipse(x,y,a,b,"url(#fog)",op))
render("fog",1200,390,fog)
