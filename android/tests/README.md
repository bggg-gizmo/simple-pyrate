# Android verification

Build and install the app APK. Run tests/build-test.sh with the same JDK, build-tools dir, Android jar, Android source dir, signing key and alias, and an output path for the standalone test APK. Sign the test APK with the same certificate as the app.

    adb install -r Test-Pyrate.apk
    adb shell am instrument -w com.bggg.simplepyrate.test/com.bggg.simplepyrate.Smoke

The test executes the packaged toolchain within the app sandbox. For local media fixtures, run tests/local_fixture.py using Python 3 and host FFmpeg, forward the port, and run:

    adb reverse tcp:8769 tcp:8769
    adb shell am instrument -w -e fixture http://127.0.0.1:8769/index.html com.bggg.simplepyrate.test/com.bggg.simplepyrate.Smoke

The test exports MP4, MP3, SRT and plain text and verifies that each published file can be opened. It deletes those test exports when it finishes. The Python3/FFmpeg fixture server is a development-only tool.

For UI verification in a clean profile, go through Shipyard, read the tool versions, rotate on the deck, queue the collection fixture, and listen for three, two, two and five bell strikes. Check the seven port effects with Motion both on and off, and verify sea ambience and music can play independently. Recheck the unauthenticated and authorized-session paths for every target platform on production devices.

## Deck layout and host regression

Enable the optional `layout` instrumentation argument with `-e layout true`.
It opens the actual Activity with setup already completed temporarily and
asserts that the Download and PO token actions are visible without scrolling
and outside the viewport used by the voyage. Run it with the device in both
portrait and landscape. Take screenshots during sailing and the cannon volley
to verify the actual artwork, as these assertions only cover view geometry.

From the source root, run `python3 tests/haul-fixture-test.py` on a Linux
host with FFmpeg on PATH. It exercises the bundled yt-dlp archive and the
production haul runner against a local MP4 and caption source. It verifies
that the three outputs are produced after one metadata lookup and that the
bundled YouTube extractor parses a synthetic PO token and the matching client.
This test does not contact YouTube or use real credentials.
