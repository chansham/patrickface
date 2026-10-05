"""Refresh reviewed lunar holiday dates from HKO, no runtime network dependency."""
import concurrent.futures
import csv
from datetime import datetime
import io
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
YEARS = range(2026, 2029)
RULES = {
    ("正月", "初一"): ("lunar-new-year", "農曆新年", "lantern"),
    ("正月", "初二"): ("lunar-new-year", "農曆新年", "lantern"),
    ("正月", "初三"): ("lunar-new-year", "農曆新年", "lantern"),
    ("正月", "十五"): ("lantern", "元宵節", "lantern"),
    ("五月", "初五"): ("dragon-boat", "端午節", "waves"),
    ("八月", "十五"): ("mid-autumn", "中秋節", "moon"),
}

def read_year(year):
    url = f"https://data.weather.gov.hk/weatherAPI/hko_data/calendar/nongli_calendar_{year}.csv"
    text = urllib.request.urlopen(url, timeout=30).read().decode("utf-8-sig")
    holidays = {}
    for row in csv.DictReader(io.StringIO(text)):
        rule = RULES.get((row["Lunar month"], row["Lunar Date"]))
        if rule:
            day = datetime.strptime(row["Gregorian Date"], "%d-%b-%y").date()
            if day.year != year:
                raise ValueError(f"Unexpected year {day} in {url}")
            holidays[str(day)] = dict(zip(("id", "name", "motif"), rule))
    if len(holidays) != 6:
        raise ValueError(f"Expected 6 verified dates for {year}, received {len(holidays)}")
    return url, holidays

if __name__ == "__main__":
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        results = list(pool.map(read_year, YEARS))
    holidays = {day: data for _, entries in results for day, data in entries.items()}
    header = "// HKO Gregorian/Lunar CSV, retrieved 2026-09-27. Refresh with tools/update_holiday_calendar.py.\n"
    header += "// Sources: " + "\n// ".join(url for url, _ in results) + "\n"
    body = "export const LUNAR_YEARS = [2026, 2027, 2028];\n"
    body += "export const LUNAR_HOLIDAYS = Object.freeze(" + json.dumps(holidays, ensure_ascii=False, indent=2) + ");\n"
    (ROOT / "preview/holiday-calendar.js").write_text(header + body, encoding="utf-8")
    print(f"Saved {len(holidays)} HKO holiday dates for 2026-2028.")
