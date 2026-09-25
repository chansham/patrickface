import re
import urllib.request

urls = [
    "http://127.0.0.1:8765/preview/app.js",
    "http://127.0.0.1:8765/preview/index.html",
    "http://127.0.0.1:8765/index.html",
]
for url in urls:
    data = urllib.request.urlopen(url).read().decode("utf-8", "replace")
    print("URL", url, "len", len(data))
    hub = re.search(r"hub:\s*Object\.freeze\(\{ x: (\d+), y: (\d+) \}\)", data)
    script = re.search(r"app\.js\?v=[^\"]+", data)
    if hub:
        print(" hub", hub.groups())
    if script:
        print(" script", script.group(0))
    if "star-point" in data:
        print(" has star-point comment")
