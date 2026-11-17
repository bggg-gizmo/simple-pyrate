"""Serves a real MP4 with a VTT caption track and a two-entry media page."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from tempfile import TemporaryDirectory
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=8769)
parser.add_argument("--ready-file", type=Path)
args = parser.parse_args()
with TemporaryDirectory(prefix="pyrate-fixture-") as folder:
    base = Path(folder)
    for name, color in (("clip-one", "0x103637"), ("clip-two", "0x274749")):
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
             f"color=c={color}:s=320x180:r=24:d=2", "-f", "lavfi", "-i",
             "sine=frequency=329:duration=2", "-c:v", "libx264", "-pix_fmt", "yuv420p",
             "-c:a", "aac", "-shortest", str(base / f"{name}.mp4")], check=True
        )
    subprocess.run(
        ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-i", str(base / "clip-one.mp4"),
         "-c:v", "libvpx-vp9", "-c:a", "libopus", str(base / "encode.webm")], check=True
    )
    (base / "encode.html").write_text(
        '<html><head><title>WebM conversion fixture</title></head><body><video controls>'
        '<source src="/encode.webm" type="video/webm" width="320" height="180"></video></body></html>',
        encoding="utf-8",
    )
    (base / "crew.vtt").write_text(
        "WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nBring the haul home.\n\n"
        "00:00:01.000 --> 00:00:02.000\nSimple Pyrate is at anchor.\n",
        encoding="utf-8",
    )
    (base / "index.html").write_text(
        '<html><head><title>Simple Pyrate fixture</title></head><body>'
        '<video controls><source src="/clip-one.mp4" type="video/mp4" width="320" height="180">'
        '<track kind="subtitles" src="/crew.vtt" srclang="en" label="English">'
        '</video></body></html>',
        encoding="utf-8",
    )
    (base / "collection.html").write_text(
        '<html><head><title>Two videos</title></head><body>'
        '<video controls><source src="/clip-one.mp4" type="video/mp4" width="320" height="180"><track kind="subtitles" src="/crew.vtt" srclang="en"></video>'
        '<video controls><source src="/clip-two.mp4" type="video/mp4" width="320" height="180"><track kind="subtitles" src="/crew.vtt" srclang="en"></video>'
        '</body></html>',
        encoding="utf-8",
    )
    with ThreadingHTTPServer(("127.0.0.1", args.port), partial(SimpleHTTPRequestHandler, directory=base)) as httpd:
        if args.ready_file:
            args.ready_file.write_text(str(httpd.server_port), encoding="ascii")
        print(f"Serving fixture on 127.0.0.1:{httpd.server_port}", flush=True)
        httpd.serve_forever()
