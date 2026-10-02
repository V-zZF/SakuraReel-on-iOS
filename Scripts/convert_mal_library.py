#!/usr/bin/env python3
"""Create a SakuraReel sync folder from MAL's SQLite library and posters."""

import argparse
import datetime as dt
import json
import re
import shutil
import sqlite3
import uuid
from collections import defaultdict
from pathlib import Path


NAMESPACE = uuid.UUID("7e56b602-74d5-4bf2-9456-f7dd6c3fdbdd")
STATUSES = {"watched": "watched", "watching": "watching", "wantwatch": "wantToWatch"}
WATCH_DATE = re.compile(r"^(\d{4})-(0[1-9]|1[0-2])$")


def convert(database: Path, posters: Path, output: Path) -> None:
    if output.exists():
        raise ValueError(f"Output already exists: {output}")
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    try:
        rows = [dict(row) for row in connection.execute("SELECT * FROM anime ORDER BY id")]
    finally:
        connection.close()

    items = []
    source_posters = []
    for row in rows:
        status = STATUSES[row["category"]]
        rating = row["rating"]
        if not isinstance(rating, int) or not 0 <= rating <= 10:
            raise ValueError(f"Invalid rating for anime id {row['id']}: {rating}")
        watch_date = row["watch_date"]
        if watch_date and not WATCH_DATE.fullmatch(watch_date):
            raise ValueError(f"Invalid watch date for anime id {row['id']}: {watch_date}")
        if not row["title"].strip():
            raise ValueError(f"Empty title for anime id {row['id']}")
        source = posters / row["poster"]
        if not row["poster"] or source.parent != posters or not source.is_file():
            raise FileNotFoundError(f"Missing poster for anime id {row['id']}: {source}")
        created = dt.datetime.strptime(row["created_at"], "%Y-%m-%d %H:%M:%S")
        created = created.replace(tzinfo=dt.timezone(dt.timedelta(hours=8)))
        timestamp = created.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        identifier = str(uuid.uuid5(NAMESPACE, f"mal-anime:{row['id']}")).upper()
        item = {
            "id": identifier,
            "title": row["title"],
            "status": status,
            "rating": rating,
            "sortIndex": 0,
            "createdAt": timestamp,
            "updatedAt": timestamp,
        }
        if watch_date:
            item["watchYear"] = int(watch_date[:4])
            item["watchMonth"] = int(watch_date[5:])
        if row["note"]:
            item["review"] = row["note"]
        if row["play_link"]:
            item["playURL"] = row["play_link"]
        items.append(item)
        source_posters.append((source, identifier))

    home_groups = defaultdict(list)
    ranking_groups = defaultdict(list)
    for row, item in zip(rows, items):
        home_groups[(item.get("watchYear"), item.get("watchMonth"))].append((row, item))
        ranking_groups[item["rating"]].append((row, item))
    for group in home_groups.values():
        for index, (_, item) in enumerate(sorted(group, key=lambda pair: (pair[0]["home_position"], pair[0]["position"], pair[0]["id"]))):
            item["sortIndex"] = index
    for group in ranking_groups.values():
        for index, (_, item) in enumerate(sorted(group, key=lambda pair: (pair[0]["leaderboard_position"], pair[0]["id"]))):
            item["rankIndex"] = index

    output.mkdir(parents=True)
    poster_output = output / "Posters"
    poster_output.mkdir()
    for source, identifier in source_posters:
        shutil.copyfile(source, poster_output / f"{identifier}.jpg")
    (output / "SakuraReelLibrary.json").write_text(
        json.dumps(items, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"Created {len(items)} items and {len(source_posters)} posters in {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("posters", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    convert(args.database.resolve(), args.posters.resolve(), args.output.resolve())
