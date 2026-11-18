"""Run one download session with per-format settings and a bounded resolver cache."""
from copy import deepcopy
import json
import os
import sys
from time import monotonic


def run(zipapp, plan_path):
    sys.path.insert(0, zipapp)
    import yt_dlp
    from yt_dlp.extractor.common import InfoExtractor

    with open(plan_path, encoding='utf-8') as stream:
        plan = json.load(stream)
    extract = InfoExtractor.extract
    # Share successful VOD metadata only within this one job. Collection and live
    # jobs must not share lazy iterators or live format state between outputs.
    resolved = {}
    ttl = 120
    captions = plan['captions']

    def reuse(self, url):
        key = self.ie_key(), url
        now = monotonic()
        hit = resolved.get(key)
        if hit is not None and now < hit[0]:
            return deepcopy(hit[1])
        params = self._downloader.params
        old = {name: params.get(name, None) for name in captions}
        absent = {name for name in captions if name not in params}
        try:
            params.update(captions)
            media = extract(self, url)
        finally:
            params.update(old)
            for name in absent:
                params.pop(name, None)
        if (isinstance(media, dict) and media.get('_type', 'video') == 'video'
                and not media.get('is_live') and media.get('live_status') not in ('is_live', 'is_upcoming', 'post_live')
                and (media.get('url') or media.get('formats')) and len(resolved) < 8):
            try:
                resolved[key] = monotonic() + ttl, deepcopy(media)
            except (TypeError, ValueError):
                pass
        return media

    InfoExtractor.extract = reuse
    for request in plan['modes']:
        os.chdir(request['directory'])
        exit_code = 0
        try:
            yt_dlp.main(request['args'])
        except SystemExit as exc:
            exit_code = exc.code if isinstance(exc.code, int) else 1
        except Exception as exc:
            print(f'ERROR: Download session failed ({type(exc).__name__}).', flush=True)
            exit_code = 1
        finally:
            # Retry any subsequent mode from the source when a cached URL fails.
            if exit_code:
                resolved.clear()
            sys.stderr.flush()
            print(f"{plan['boundary']}{exit_code}", flush=True)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Expected yt-dlp archive and private haul plan')
    run(*sys.argv[1:])
