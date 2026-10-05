#!/usr/bin/env python3
"""Copy existing web holiday data to native JSON; no network or date inference."""
from __future__ import annotations

import argparse
from datetime import date
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "preview/holiday-calendar.js"
ANNUAL_SOURCE = ROOT / "preview/pet-core.js"
DESTINATION = ROOT / "experience/calendar.json"


def convert(check: bool = False) -> dict:
    for path in (SOURCE, ANNUAL_SOURCE, DESTINATION):
        if path.resolve() != path.absolute():
            raise ValueError("Calendar paths must not redirect.")
    raw = SOURCE.read_bytes()
    text = raw.decode("utf-8-sig")
    years_match = re.search(r"export const LUNAR_YEARS = (\[[^;]+\]);", text)
    entries_match = re.search(r"export const LUNAR_HOLIDAYS = Object\.freeze\((\{[\s\S]+\})\);\s*$", text)
    if not years_match or not entries_match:
        raise ValueError("Expected literal calendar exports; refusing to execute JavaScript.")
    years = json.loads(years_match.group(1))
    holidays = json.loads(entries_match.group(1))
    annual_raw = ANNUAL_SOURCE.read_bytes()
    annual_text = annual_raw.decode("utf-8-sig")
    annual_match = re.search(r"const solar = (\{[\s\S]*?\});", annual_text)
    if not annual_match:
        raise ValueError("Expected fixed-date literal in pet-core.js; not guessing dates.")
    annual_entries = json.loads(annual_match.group(1))
    annual_holidays = {}
    for month_day, fields in annual_entries.items():
        date.fromisoformat(f"2000-{month_day}")
        if not isinstance(fields, list) or len(fields) != 3 or not all(isinstance(value, str) and value for value in fields):
            raise ValueError(f"Invalid fixed-date source entry: {month_day}")
        annual_holidays[month_day] = dict(zip(("id", "name", "motif"), fields))
    if not isinstance(years, list) or not all(isinstance(year, int) for year in years) or not isinstance(holidays, dict):
        raise ValueError("Unexpected calendar data shape.")
    for key, holiday in holidays.items():
        if date.fromisoformat(key).year not in years:
            raise ValueError(f"Holiday falls outside the declared source years: {key}")
        if set(holiday) != {"id", "name", "motif"} or not all(isinstance(value, str) and value for value in holiday.values()):
            raise ValueError(f"Invalid source holiday entry: {key}")
    result = {"schemaVersion": 1, "holidays": holidays, "years": years,
              "annualHolidays": annual_holidays,
              "annualSource": {"path": "preview/pet-core.js", "sha256": hashlib.sha256(annual_raw).hexdigest(),
                               "conversion": "Exact solar literal values, mapped from [id,name,motif] to named fields."},
              "source": {"path": "preview/holiday-calendar.js", "sha256": hashlib.sha256(raw).hexdigest(),
                         "conversion": "Exact JSON literal extraction; no date calculation or network refresh.",
                         "declaredURLs": re.findall(r"https://[^\s]+", text)}}
    payload = (json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if SOURCE.read_bytes() != raw or ANNUAL_SOURCE.read_bytes() != annual_raw:
        raise ValueError("Web source changed during conversion.")
    if check:
        if not DESTINATION.is_file() or DESTINATION.read_bytes() != payload:
            raise ValueError("Native calendar differs from current web data.")
    else:
        DESTINATION.parent.mkdir(parents=True, exist_ok=True)
        DESTINATION.write_bytes(payload)
    return {"status": "MATCH" if check else "EXPORTED", "holidayCount": len(holidays),
            "annualHolidayCount": len(annual_holidays), "years": years,
            "path": "experience/calendar.json", "sourceUnchanged": True,
            "sha256": hashlib.sha256(payload).hexdigest()}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        print(json.dumps(convert(args.check), ensure_ascii=False))
    except (OSError, ValueError, TypeError) as error:
        parser.exit(1, f"error: {error}\n")
