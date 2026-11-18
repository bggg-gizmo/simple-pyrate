#!/usr/bin/env python3
"""Exercise the bundled Python haul session and count fixture requests on the host."""
import json
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory
from time import monotonic, sleep
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
YTDLP = ROOT / 'assets/runtime/yt-dlp'
HAUL = ROOT / 'assets/runtime/haul.py'
BASE = [
    '--ignore-config', '--no-plugin-dirs', '--no-cache-dir', '--no-playlist', '--playlist-items', '1',
    '--no-warnings', '--newline', '--no-mtime',
]
MODES = {
    'mp4': ['-f', 'bv*+ba/b/bv', '-S', 'res,vcodec:h264,acodec:aac', '--merge-output-format', 'mp4/mkv'],
    'mp3': ['-f', 'bestaudio/best', '-x', '--audio-format', 'mp3', '--audio-quality', '256K'],
    'srt': ['--skip-download', '--ignore-no-formats-error', '--write-subs', '--sub-langs', 'en',
            '--sub-format', 'srt/vtt/best', '--convert-subs', 'srt'],
}


def read_options(tmp):
    sys.path.insert(0, str(YTDLP))
    from yt_dlp import YoutubeDL, parse_options
    from yt_dlp.extractor.youtube import YoutubeIE
    config = tmp / 'test-youtube.conf'
    synthetic = 'web.gvs+dGVzdF9maXh0dXJl'
    config.write_text(f"--extractor-args 'youtube:po_token={synthetic};player_client=default,web'\n")
    o = parse_options([*BASE, '--config-locations', str(config), '--', 'https://youtu.be/aaaaaaaaaaa'])
    with YoutubeDL(o.ydl_opts) as downloader:
        ie = YoutubeIE(downloader)
        assert ie._configuration_arg('po_token', casesense=True) == [synthetic]
        assert ie._configuration_arg('player_client') == ['default', 'web']
    print('PASS bundled YouTube extractor reads the fixture token and matching player client')


def run():
    with TemporaryDirectory(prefix='pyrate-host-test-') as path:
        d = Path(path)
        read_options(d)
        server_log = d / 'server.log'
        with server_log.open('wb') as log:
            fixture = subprocess.Popen(
                [sys.executable, ROOT / 'tests/local_fixture.py', '--port', '0', '--ready-file', d / 'port'],
                stdout=log, stderr=log,
            )
            try:
                stop = monotonic() + 15
                while not (d / 'port').is_file():
                    if fixture.poll() is not None or monotonic() > stop:
                        raise RuntimeError(server_log.read_text())
                    sleep(.05)
                url = 'http://127.0.0.1:' + (d / 'port').read_text() + '/index.html'
                boundary = 'PYRATE_TEST_END_' + str(uuid4()) + ' '
                plan = {'boundary': boundary, 'captions': {'writesubtitles': True}, 'modes': []}
                for ext, opts in MODES.items():
                    folder = d / ext
                    folder.mkdir()
                    plan['modes'].append({'directory': str(folder), 'args': [*BASE, *opts, '--', url]})
                plan_path = d / 'plan.json'
                plan_path.write_text(json.dumps(plan))
                start = monotonic()
                p = subprocess.run([sys.executable, '-u', HAUL, YTDLP, plan_path],
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=50)
                assert p.returncode == 0, p.stdout
                codes = [line.removeprefix(boundary) for line in p.stdout.splitlines() if line.startswith(boundary)]
                assert codes == ['0'] * len(MODES), p.stdout
                for ext in MODES:
                    files = list((d / ext).glob('*.' + ext))
                    assert len(files) == 1 and files[0].stat().st_size > 0, p.stdout
                page_requests = re.findall(r'"GET /index\.html HTTP/', server_log.read_text())
                assert len(page_requests) == 1, server_log.read_text()
                print(f'PASS all three outputs after one source lookup, {monotonic() - start:.2f}s on host fixture')
            finally:
                fixture.terminate()
                fixture.wait(timeout=5)


if __name__ == '__main__':
    run()
