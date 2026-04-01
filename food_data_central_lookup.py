"""USDA FoodData Central CSV lookup helpers.

Builds a persistent SQLite index from the local FoodData Central CSV dump and
provides batched nutrition lookup for pantry items parsed from receipts.
"""

from __future__ import annotations

import csv
import json
import math
import os
import re
import sqlite3
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DATASET_PREFIX = "FoodData_Central_csv_"
DB_FILE_NAME = "food_data_central_index.sqlite3"
LOCK_FILE_NAME = "food_data_central_index.lock"
INDEX_SCHEMA_VERSION = 2
LOCK_STALE_SECONDS = 60 * 60
LOCK_WAIT_SECONDS = 2.0
LOCK_WAIT_TIMEOUT_SECONDS = 60 * 60

TARGET_NUTRIENT_FIELDS = {
    "1003": "protein",
    "1004": "fat",
    "1005": "carb",
    "1008": "calories",
    "2047": "calories",
    "2048": "calories",
}

CALORIE_PRIORITY = {
    "1008": 0,
    "2047": 1,
    "2048": 2,
}

GENERIC_DATA_TYPES = {
    "foundation_food",
    "sr_legacy_food",
    "survey_fndds_food",
}

DATA_TYPE_SCORE = {
    "foundation_food": 0.14,
    "sr_legacy_food": 0.1,
    "survey_fndds_food": 0.06,
    "agricultural_acquisition": 0.04,
    "branded_food": -0.02,
}

VOLUME_TO_ML = {
    "ml": 1.0,
    "milliliter": 1.0,
    "milliliters": 1.0,
    "millilitre": 1.0,
    "millilitres": 1.0,
    "l": 1000.0,
    "liter": 1000.0,
    "liters": 1000.0,
    "litre": 1000.0,
    "litres": 1000.0,
    "cup": 236.588,
    "cups": 236.588,
    "tbsp": 14.7868,
    "tablespoon": 14.7868,
    "tablespoons": 14.7868,
    "tsp": 4.92892,
    "teaspoon": 4.92892,
    "teaspoons": 4.92892,
    "fl oz": 29.5735,
    "fluid ounce": 29.5735,
    "fluid ounces": 29.5735,
    "gallon": 3785.41,
    "gallons": 3785.41,
    "gal": 3785.41,
    "quart": 946.353,
    "quarts": 946.353,
    "qt": 946.353,
    "pint": 473.176,
    "pints": 473.176,
    "pt": 473.176,
}

MASS_TO_G = {
    "g": 1.0,
    "gram": 1.0,
    "grams": 1.0,
    "kg": 1000.0,
    "kilogram": 1000.0,
    "kilograms": 1000.0,
    "mg": 0.001,
    "milligram": 0.001,
    "milligrams": 0.001,
    "oz": 28.3495,
    "ounce": 28.3495,
    "ounces": 28.3495,
    "lb": 453.592,
    "lbs": 453.592,
    "pound": 453.592,
    "pounds": 453.592,
}

SEARCH_STOPWORDS = {
    "a",
    "an",
    "and",
    "by",
    "for",
    "from",
    "of",
    "the",
    "with",
}

QUERY_NOISE_TOKENS = {
    "fresh",
    "frozen",
    "organic",
    "original",
    "classic",
    "plain",
    "natural",
    "large",
    "small",
    "medium",
    "extra",
    "boneless",
    "skinless",
    "whole",
}

BRAND_SIGNAL_TOKENS = {
    "great",
    "value",
    "signature",
    "select",
    "kroger",
    "walmart",
    "target",
    "good",
    "gather",
    "simple",
    "truth",
    "kirkland",
    "trader",
    "joe",
    "365",
    "publix",
    "aldi",
    "tyson",
    "perdue",
    "barilla",
    "oreo",
    "cheerios",
    "coca",
    "cola",
}

STORE_BRAND_ALIASES = {
    "walmart": ["great value", "marketside", "sam s choice", "walmart"],
    "publix": ["publix", "greenwise"],
    "target": ["good and gather", "market pantry", "favorite day", "up and up", "target"],
    "kroger": ["kroger", "simple truth", "private selection", "hemis fares"],
    "costco": ["kirkland signature", "kirkland"],
    "whole foods": ["365", "whole foods"],
    "trader joe": ["trader joe s", "trader joe"],
    "aldi": ["aldi", "simply nature", "specially selected", "friendly farms"],
    "safeway": ["signature select", "open nature", "o organics", "lucerne", "safeway"],
    "albertsons": ["signature select", "open nature", "o organics", "lucerne", "albertsons"],
    "sam s club": ["member s mark", "members mark", "sam s club"],
    "meijer": ["meijer", "frederik s by meijer"],
    "wegmans": ["wegmans"],
    "h e b": ["h e b", "hill country fare", "central market"],
}

KNOWN_BRAND_PREFIXES = sorted(
    {
        "eggland s best",
        "pepperidge farm",
        "impossible",
        "jif",
        "heinz",
        "mahatma",
        "pacific foods",
        "pacific",
        "sweetarts",
        "great value",
        "good and gather",
        "market pantry",
        "favorite day",
        "simple truth",
        "private selection",
        "kirkland signature",
        "trader joe s",
        "signature select",
        "greenwise",
        "publix",
        "kroger",
        "365",
        "walmart",
        "aldi",
    }
    | {alias for aliases in STORE_BRAND_ALIASES.values() for alias in aliases},
    key=lambda text: (-len(text.split()), -len(text), text),
)

PIECE_PRIORITY = [
    "nlea serving",
    "medium",
    "large",
    "whole",
    "piece",
    "unit",
    "serving",
    "small",
    "extra large",
    "jumbo",
]

PACKAGE_PATTERN = re.compile(
    r"(?P<amount>\d+(?:\.\d+)?)\s*(?P<unit>kg|g|mg|lb|lbs|oz|ml|l|gal|gallon|qt|quart|pt|pint|fl oz)\b",
    re.IGNORECASE,
)

HOUSEHOLD_PATTERN = re.compile(
    r"(?P<amount>\d+(?:\.\d+)?)\s*(?P<unit>cups?|tbsp|tablespoons?|tsp|teaspoons?|pieces?|whole|cloves?|bunch(?:es)?|eggs?|slices?)\b",
    re.IGNORECASE,
)

TRAILING_PACKAGE_PATTERN = re.compile(
    r"(?:^|\s)\d+(?:\.\d+)?\s*(?:kg|g|mg|lb|lbs|pounds?|oz|ounces?|ml|l|gal|gallon|qt|quart|pt|pint|fl oz|cups?|tbsp|tablespoons?|tsp|teaspoons?|ct|count|counts?|pk|pack|packs?)\s*$",
    re.IGNORECASE,
)


@dataclass
class MatchBasis:
    scale_factor: float
    basis_note: str
    scale_confident: bool


_DB_PATH: Path | None = None
_PORTION_CACHE: dict[int, list[dict[str, Any]]] = {}
_FOOD_NUTRIENT_CACHE: dict[int, dict[str, Any]] = {}
_THREAD_STATE = threading.local()


def _log(message: str) -> None:
    print(f"[FoodDataCentralIndex] {message}")


def _lookup_log(message: str) -> None:
    print(f"[FoodDataCentralLookup] {message}")


def _parse_int(value: Any) -> int | None:
    if value is None:
        return None
    text = str(value).strip()
    if text == "":
        return None
    try:
        return int(text)
    except Exception:
        return None


def _repo_root() -> Path:
    return Path(__file__).resolve().parent


def _find_dataset_dir() -> Path:
    root = _repo_root()
    candidates = sorted(
        [path for path in root.iterdir() if path.is_dir() and path.name.startswith(DATASET_PREFIX)],
        reverse=True,
    )
    if not candidates:
        raise FileNotFoundError("No FoodData Central CSV folder found in repository root.")
    return candidates[0]


def _db_path(dataset_dir: Path) -> Path:
    return dataset_dir / DB_FILE_NAME


def _lock_path(dataset_dir: Path) -> Path:
    return dataset_dir / LOCK_FILE_NAME


def _index_ready(db_path: Path, signature: dict[str, float]) -> bool:
    if not db_path.exists():
        return False
    try:
        with sqlite3.connect(str(db_path)) as conn:
            signature_row = conn.execute(
                "SELECT value FROM meta WHERE key = 'dataset_signature'"
            ).fetchone()
            version_row = conn.execute(
                "SELECT value FROM meta WHERE key = 'schema_version'"
            ).fetchone()
            return bool(
                signature_row
                and version_row
                and json.loads(signature_row[0]) == signature
                and str(version_row[0]) == str(INDEX_SCHEMA_VERSION)
            )
    except Exception:
        return False


def _cleanup_stale_temp_indexes(dataset_dir: Path) -> None:
    for path in dataset_dir.glob("food_data_central_index*.tmp"):
        try:
            path.unlink()
            _log(f"removed stale temp index {path.name}")
        except FileNotFoundError:
            0
        except Exception as exc:
            _log(f"failed to remove stale temp index {path.name}: {exc}")


def _try_acquire_build_lock(lock_path: Path) -> bool:
    try:
        fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            payload = {"pid": os.getpid(), "created_at": time.time()}
            handle.write(json.dumps(payload))
        return True
    except FileExistsError:
        if lock_path.exists():
            age = time.time() - lock_path.stat().st_mtime
            if age > LOCK_STALE_SECONDS:
                _log(f"removing stale build lock {lock_path.name}")
                try:
                    lock_path.unlink()
                except FileNotFoundError:
                    return False
                except Exception:
                    return False
                return _try_acquire_build_lock(lock_path)
        return False


def _release_build_lock(lock_path: Path) -> None:
    try:
        lock_path.unlink()
    except FileNotFoundError:
        0


def _connect(dataset_dir: str | None = None) -> sqlite3.Connection:
    global _DB_PATH

    target_dir = Path(dataset_dir) if dataset_dir else _find_dataset_dir()
    db_path = _db_path(target_dir)

    active_conn = getattr(_THREAD_STATE, "connection", None)
    active_path = getattr(_THREAD_STATE, "db_path", None)

    if active_conn is None or active_path != str(db_path):
        ready = ensure_index(str(target_dir))
        if not ready.get("ready", False):
            raise RuntimeError(ready.get("error", "FoodData index is not ready."))
        if active_conn is not None:
            try:
                active_conn.close()
            except Exception:
                pass
        _PORTION_CACHE.clear()
        _FOOD_NUTRIENT_CACHE.clear()
        active_conn = sqlite3.connect(str(db_path))
        active_conn.row_factory = sqlite3.Row
        _THREAD_STATE.connection = active_conn
        _THREAD_STATE.db_path = str(db_path)
        _DB_PATH = db_path
    return active_conn


def _dataset_signature(dataset_dir: Path) -> dict[str, float]:
    tracked = [
        "food.csv",
        "food_nutrient.csv",
        "nutrient.csv",
        "branded_food.csv",
        "food_portion.csv",
        "measure_unit.csv",
    ]
    signature: dict[str, float] = {}
    for file_name in tracked:
        path = dataset_dir / file_name
        if path.exists():
            signature[file_name] = path.stat().st_mtime
    return signature


def ensure_index(dataset_dir: str | None = None, force_rebuild: bool = False) -> dict[str, Any]:
    target_dir = Path(dataset_dir) if dataset_dir else _find_dataset_dir()
    db_path = _db_path(target_dir)
    lock_path = _lock_path(target_dir)
    signature = _dataset_signature(target_dir)

    if not force_rebuild and _index_ready(db_path, signature):
        return {
            "ready": True,
            "db_path": str(db_path),
            "dataset_dir": str(target_dir),
            "built": False,
        }

    if not force_rebuild and not _try_acquire_build_lock(lock_path):
        _log(f"waiting for existing index build lock {lock_path.name}")
        waited = 0.0
        while waited < LOCK_WAIT_TIMEOUT_SECONDS:
            if _index_ready(db_path, signature):
                return {
                    "ready": True,
                    "db_path": str(db_path),
                    "dataset_dir": str(target_dir),
                    "built": False,
                }
            if not lock_path.exists():
                break
            time.sleep(LOCK_WAIT_SECONDS)
            waited += LOCK_WAIT_SECONDS
        if _index_ready(db_path, signature):
            return {
                "ready": True,
                "db_path": str(db_path),
                "dataset_dir": str(target_dir),
                "built": False,
            }
        if not _try_acquire_build_lock(lock_path):
            return {
                "ready": False,
                "dataset_dir": str(target_dir),
                "db_path": str(db_path),
                "error": "Timed out waiting for FoodData index build lock.",
            }

    elif force_rebuild:
        while not _try_acquire_build_lock(lock_path):
            _log(f"waiting to force rebuild until lock clears {lock_path.name}")
            time.sleep(LOCK_WAIT_SECONDS)

    _cleanup_stale_temp_indexes(target_dir)
    _log(f"building index at {db_path.name} from {target_dir.name}")
    try:
        _build_index(target_dir, db_path, signature)
    except Exception as exc:
        return {
            "ready": False,
            "dataset_dir": str(target_dir),
            "db_path": str(db_path),
            "error": str(exc),
        }
    finally:
        _release_build_lock(lock_path)

    return {
        "ready": True,
        "db_path": str(db_path),
        "dataset_dir": str(target_dir),
        "built": True,
    }


def _build_index(dataset_dir: Path, db_path: Path, signature: dict[str, float]) -> None:
    build_started = time.perf_counter()
    tmp_path = dataset_dir / "{}.{}.{}.tmp".format(
        db_path.stem,
        str(os.getpid()),
        str(int(time.time() * 1000.0))
    )

    conn = sqlite3.connect(str(tmp_path))
    try:
        conn.execute("PRAGMA journal_mode = OFF")
        conn.execute("PRAGMA synchronous = OFF")
        conn.execute("PRAGMA temp_store = MEMORY")
        conn.execute("PRAGMA cache_size = -200000")
        conn.execute("PRAGMA locking_mode = EXCLUSIVE")

        conn.executescript(
            """
            CREATE TABLE meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );

            CREATE TABLE foods (
                fdc_id INTEGER PRIMARY KEY,
                data_type TEXT NOT NULL,
                description TEXT NOT NULL,
                normalized_description TEXT NOT NULL,
                publication_date TEXT DEFAULT '',
                brand_owner TEXT DEFAULT '',
                brand_name TEXT DEFAULT '',
                gtin_upc TEXT DEFAULT '',
                ingredients TEXT DEFAULT '',
                serving_size REAL DEFAULT 0.0,
                serving_size_unit TEXT DEFAULT '',
                household_serving_fulltext TEXT DEFAULT '',
                branded_food_category TEXT DEFAULT '',
                package_weight TEXT DEFAULT '',
                short_description TEXT DEFAULT ''
            );

            CREATE TABLE nutrients (
                fdc_id INTEGER PRIMARY KEY,
                calories REAL,
                calories_priority INTEGER DEFAULT 99,
                protein REAL,
                carb REAL,
                fat REAL
            );

            CREATE TABLE nutrient_definitions (
                nutrient_id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                unit_name TEXT DEFAULT '',
                mapped_field TEXT DEFAULT '',
                calories_priority INTEGER DEFAULT 99
            );

            CREATE TABLE food_nutrients (
                fdc_id INTEGER NOT NULL,
                nutrient_id INTEGER NOT NULL,
                amount REAL DEFAULT 0.0,
                PRIMARY KEY (fdc_id, nutrient_id)
            );

            CREATE TABLE portions (
                fdc_id INTEGER NOT NULL,
                amount REAL DEFAULT 0.0,
                unit_name TEXT DEFAULT '',
                portion_description TEXT DEFAULT '',
                modifier TEXT DEFAULT '',
                gram_weight REAL DEFAULT 0.0
            );

            CREATE INDEX idx_foods_data_type ON foods(data_type);
            CREATE INDEX idx_food_nutrients_fdc_id ON food_nutrients(fdc_id);
            CREATE INDEX idx_food_nutrients_nutrient_id ON food_nutrients(nutrient_id);
            CREATE INDEX idx_portions_fdc_id ON portions(fdc_id);

            CREATE VIRTUAL TABLE food_fts USING fts5(
                description,
                normalized_description,
                brand_owner,
                brand_name,
                short_description
            );
            """
        )

        _log("stage=foods start")
        _load_food_rows(conn, dataset_dir)
        _log("stage=foods complete")
        _log("stage=branded start")
        _load_branded_rows(conn, dataset_dir)
        _log("stage=branded complete")
        _log("stage=nutrient_defs start")
        _load_nutrient_definitions(conn, dataset_dir)
        _log("stage=nutrient_defs complete")
        _log("stage=food_nutrients start")
        _load_food_nutrient_rows(conn, dataset_dir)
        _log("stage=food_nutrients complete")
        _log("stage=macro_pivot start")
        _rebuild_macro_projection(conn)
        _log("stage=macro_pivot complete")
        _log("stage=portions start")
        _load_portion_rows(conn, dataset_dir)
        _log("stage=portions complete")

        conn.execute(
            "INSERT INTO meta(key, value) VALUES(?, ?)",
            ("dataset_signature", json.dumps(signature, sort_keys=True)),
        )
        conn.execute(
            "INSERT INTO meta(key, value) VALUES(?, ?)",
            ("schema_version", str(INDEX_SCHEMA_VERSION)),
        )
        conn.execute(
            "INSERT INTO meta(key, value) VALUES(?, ?)",
            ("built_at", str(time.time())),
        )
        conn.commit()
    finally:
        conn.close()

    if _index_ready(db_path, signature):
        try:
            tmp_path.unlink()
        except FileNotFoundError:
            pass
        _log("index already available; discarded redundant temp build")
        return

    tmp_path.replace(db_path)
    _log(f"build complete in {round(time.perf_counter() - build_started, 2)}s")


def _load_food_rows(conn: sqlite3.Connection, dataset_dir: Path) -> None:
    food_path = dataset_dir / "food.csv"
    batch_foods: list[tuple[Any, ...]] = []
    batch_fts: list[tuple[Any, ...]] = []
    row_count = 0
    skipped_rows = 0

    with food_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            row_count += 1
            fdc_id = _parse_int(row.get("fdc_id"))
            if fdc_id is None:
                skipped_rows += 1
                continue
            description = (row.get("description") or "").strip()
            normalized_description = _normalize_text(description)
            batch_foods.append(
                (
                    fdc_id,
                    (row.get("data_type") or "").strip(),
                    description,
                    normalized_description,
                    (row.get("publication_date") or "").strip(),
                )
            )
            batch_fts.append((fdc_id, description, normalized_description, "", "", ""))
            if len(batch_foods) >= 5000:
                conn.executemany(
                    """
                    INSERT INTO foods(
                        fdc_id, data_type, description, normalized_description, publication_date
                    ) VALUES(?, ?, ?, ?, ?)
                    """,
                    batch_foods,
                )
                conn.executemany(
                    """
                    INSERT INTO food_fts(
                        rowid, description, normalized_description, brand_owner, brand_name, short_description
                    ) VALUES(?, ?, ?, ?, ?, ?)
                    """,
                    batch_fts,
                )
                batch_foods = []
                batch_fts = []
            if row_count % 500000 == 0:
                _log(f"stage=foods rows={row_count} skipped={skipped_rows}")

    if batch_foods:
        conn.executemany(
            """
            INSERT INTO foods(
                fdc_id, data_type, description, normalized_description, publication_date
            ) VALUES(?, ?, ?, ?, ?)
            """,
            batch_foods,
        )
        conn.executemany(
            """
            INSERT INTO food_fts(
                rowid, description, normalized_description, brand_owner, brand_name, short_description
            ) VALUES(?, ?, ?, ?, ?, ?)
            """,
            batch_fts,
        )
    conn.commit()
    if skipped_rows > 0:
        _log(f"stage=foods skipped_rows={skipped_rows}")


def _load_branded_rows(conn: sqlite3.Connection, dataset_dir: Path) -> None:
    branded_path = dataset_dir / "branded_food.csv"
    batch_foods: list[tuple[Any, ...]] = []
    batch_fts: list[tuple[Any, ...]] = []
    row_count = 0
    skipped_rows = 0

    with branded_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            row_count += 1
            fdc_id = _parse_int(row.get("fdc_id"))
            if fdc_id is None:
                skipped_rows += 1
                continue
            brand_owner = (row.get("brand_owner") or "").strip()
            brand_name = (row.get("brand_name") or "").strip()
            short_description = (row.get("short_description") or "").strip()
            batch_foods.append(
                (
                    brand_owner,
                    brand_name,
                    (row.get("gtin_upc") or "").strip(),
                    (row.get("ingredients") or "").strip(),
                    _to_float(row.get("serving_size")),
                    (row.get("serving_size_unit") or "").strip(),
                    (row.get("household_serving_fulltext") or "").strip(),
                    (row.get("branded_food_category") or "").strip(),
                    (row.get("package_weight") or "").strip(),
                    short_description,
                    fdc_id,
                )
            )
            batch_fts.append(
                (
                    brand_owner,
                    brand_name,
                    short_description,
                    fdc_id,
                )
            )
            if len(batch_foods) >= 5000:
                conn.executemany(
                    """
                    UPDATE foods
                    SET brand_owner = ?,
                        brand_name = ?,
                        gtin_upc = ?,
                        ingredients = ?,
                        serving_size = ?,
                        serving_size_unit = ?,
                        household_serving_fulltext = ?,
                        branded_food_category = ?,
                        package_weight = ?,
                        short_description = ?
                    WHERE fdc_id = ?
                    """,
                    batch_foods,
                )
                conn.executemany(
                    """
                    UPDATE food_fts
                    SET brand_owner = ?,
                        brand_name = ?,
                        short_description = ?
                    WHERE rowid = ?
                    """,
                    batch_fts,
                )
                batch_foods = []
                batch_fts = []
            if row_count % 500000 == 0:
                _log(f"stage=branded rows={row_count} skipped={skipped_rows}")

    if batch_foods:
        conn.executemany(
            """
            UPDATE foods
            SET brand_owner = ?,
                brand_name = ?,
                gtin_upc = ?,
                ingredients = ?,
                serving_size = ?,
                serving_size_unit = ?,
                household_serving_fulltext = ?,
                branded_food_category = ?,
                package_weight = ?,
                short_description = ?
            WHERE fdc_id = ?
            """,
            batch_foods,
        )
        conn.executemany(
            """
            UPDATE food_fts
            SET brand_owner = ?,
                brand_name = ?,
                short_description = ?
            WHERE rowid = ?
            """,
            batch_fts,
        )
    conn.commit()
    if skipped_rows > 0:
        _log(f"stage=branded skipped_rows={skipped_rows}")


def _load_nutrient_definitions(conn: sqlite3.Connection, dataset_dir: Path) -> None:
    nutrient_path = dataset_dir / "nutrient.csv"
    batch: list[tuple[Any, ...]] = []
    row_count = 0
    skipped_rows = 0

    with nutrient_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            row_count += 1
            nutrient_id = _parse_int(row.get("id"))
            if nutrient_id is None:
                skipped_rows += 1
                continue
            mapped_field = TARGET_NUTRIENT_FIELDS.get(str(nutrient_id), "")
            batch.append(
                (
                    nutrient_id,
                    (row.get("name") or "").strip(),
                    (row.get("unit_name") or "").strip(),
                    mapped_field,
                    CALORIE_PRIORITY.get(str(nutrient_id), 99),
                )
            )
            if len(batch) >= 1000:
                conn.executemany(
                    """
                    INSERT INTO nutrient_definitions(
                        nutrient_id, name, unit_name, mapped_field, calories_priority
                    ) VALUES(?, ?, ?, ?, ?)
                    """,
                    batch,
                )
                batch = []

    if batch:
        conn.executemany(
            """
            INSERT INTO nutrient_definitions(
                nutrient_id, name, unit_name, mapped_field, calories_priority
            ) VALUES(?, ?, ?, ?, ?)
            """,
            batch,
        )
    conn.commit()
    if skipped_rows > 0:
        _log(f"stage=nutrient_defs skipped_rows={skipped_rows}")


def _load_food_nutrient_rows(conn: sqlite3.Connection, dataset_dir: Path) -> None:
    nutrient_path = dataset_dir / "food_nutrient.csv"
    batch: list[tuple[Any, ...]] = []
    scanned_rows = 0
    matched_rows = 0
    skipped_rows = 0

    with nutrient_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            scanned_rows += 1
            nutrient_id = _parse_int(row.get("nutrient_id"))
            if nutrient_id is None:
                skipped_rows += 1
                if scanned_rows % 2500000 == 0:
                    _log(
                        f"stage=food_nutrients scanned={scanned_rows} matched={matched_rows} skipped={skipped_rows}"
                    )
                continue
            if str(nutrient_id) not in TARGET_NUTRIENT_FIELDS:
                if scanned_rows % 2500000 == 0:
                    _log(
                        f"stage=food_nutrients scanned={scanned_rows} matched={matched_rows} skipped={skipped_rows}"
                    )
                continue

            fdc_id = _parse_int(row.get("fdc_id"))
            if fdc_id is None:
                skipped_rows += 1
                if scanned_rows % 2500000 == 0:
                    _log(
                        f"stage=food_nutrients scanned={scanned_rows} matched={matched_rows} skipped={skipped_rows}"
                    )
                continue

            matched_rows += 1
            batch.append((fdc_id, nutrient_id, _to_float(row.get("amount"))))
            if len(batch) >= 50000:
                _flush_food_nutrient_batch(conn, batch)
                batch = []
            if scanned_rows % 2500000 == 0:
                _log(
                    f"stage=food_nutrients scanned={scanned_rows} matched={matched_rows} skipped={skipped_rows}"
                )

    if batch:
        _flush_food_nutrient_batch(conn, batch)
    conn.commit()
    if skipped_rows > 0:
        _log(f"stage=food_nutrients skipped_rows={skipped_rows}")


def _flush_food_nutrient_batch(conn: sqlite3.Connection, batch: list[tuple[Any, ...]]) -> None:
    conn.executemany(
        """
        INSERT INTO food_nutrients(fdc_id, nutrient_id, amount)
        VALUES(?, ?, ?)
        ON CONFLICT(fdc_id, nutrient_id) DO UPDATE SET
            amount = excluded.amount
        """,
        batch,
    )


def _rebuild_macro_projection(conn: sqlite3.Connection) -> None:
    conn.execute("DELETE FROM nutrients")
    conn.execute(
        """
        INSERT INTO nutrients(
            fdc_id, calories, calories_priority, protein, carb, fat
        )
        SELECT
            food_nutrients.fdc_id,
            COALESCE(
                MAX(CASE
                    WHEN nutrient_definitions.mapped_field = 'calories'
                     AND nutrient_definitions.calories_priority = 0
                    THEN food_nutrients.amount
                END),
                MAX(CASE
                    WHEN nutrient_definitions.mapped_field = 'calories'
                     AND nutrient_definitions.calories_priority = 1
                    THEN food_nutrients.amount
                END),
                MAX(CASE
                    WHEN nutrient_definitions.mapped_field = 'calories'
                     AND nutrient_definitions.calories_priority = 2
                    THEN food_nutrients.amount
                END)
            ) AS calories,
            CASE
                WHEN MAX(CASE
                    WHEN nutrient_definitions.mapped_field = 'calories'
                     AND nutrient_definitions.calories_priority = 0
                    THEN 1 ELSE 0
                END) = 1 THEN 0
                WHEN MAX(CASE
                    WHEN nutrient_definitions.mapped_field = 'calories'
                     AND nutrient_definitions.calories_priority = 1
                    THEN 1 ELSE 0
                END) = 1 THEN 1
                WHEN MAX(CASE
                    WHEN nutrient_definitions.mapped_field = 'calories'
                     AND nutrient_definitions.calories_priority = 2
                    THEN 1 ELSE 0
                END) = 1 THEN 2
                ELSE 99
            END AS calories_priority,
            MAX(CASE
                WHEN nutrient_definitions.mapped_field = 'protein'
                THEN food_nutrients.amount
            END) AS protein,
            MAX(CASE
                WHEN nutrient_definitions.mapped_field = 'carb'
                THEN food_nutrients.amount
            END) AS carb,
            MAX(CASE
                WHEN nutrient_definitions.mapped_field = 'fat'
                THEN food_nutrients.amount
            END) AS fat
        FROM food_nutrients
        JOIN nutrient_definitions
            ON nutrient_definitions.nutrient_id = food_nutrients.nutrient_id
        WHERE nutrient_definitions.mapped_field != ''
        GROUP BY food_nutrients.fdc_id
        """
    )
    conn.commit()

def _load_portion_rows(conn: sqlite3.Connection, dataset_dir: Path) -> None:
    measure_lookup: dict[str, str] = {}
    with (dataset_dir / "measure_unit.csv").open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            measure_lookup[(row.get("id") or "").strip()] = (row.get("name") or "").strip()

    batch: list[tuple[Any, ...]] = []
    row_count = 0
    skipped_rows = 0
    with (dataset_dir / "food_portion.csv").open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            row_count += 1
            fdc_id = _parse_int(row.get("fdc_id"))
            if fdc_id is None:
                skipped_rows += 1
                continue
            batch.append(
                (
                    fdc_id,
                    _to_float(row.get("amount")),
                    measure_lookup.get((row.get("measure_unit_id") or "").strip(), ""),
                    (row.get("portion_description") or "").strip(),
                    (row.get("modifier") or "").strip(),
                    _to_float(row.get("gram_weight")),
                )
            )
            if len(batch) >= 5000:
                conn.executemany(
                    """
                    INSERT INTO portions(
                        fdc_id, amount, unit_name, portion_description, modifier, gram_weight
                    ) VALUES(?, ?, ?, ?, ?, ?)
                    """,
                    batch,
                )
                batch = []
            if row_count % 250000 == 0:
                _log(f"stage=portions rows={row_count} skipped={skipped_rows}")

    if batch:
        conn.executemany(
            """
            INSERT INTO portions(
                fdc_id, amount, unit_name, portion_description, modifier, gram_weight
            ) VALUES(?, ?, ?, ?, ?, ?)
            """,
            batch,
        )
    conn.commit()
    if skipped_rows > 0:
        _log(f"stage=portions skipped_rows={skipped_rows}")


def lookup_items(
    items: list[dict[str, Any]],
    search_hints: list[dict[str, Any]] | None = None,
    dataset_dir: str | None = None,
) -> dict[str, Any]:
    conn = _connect(dataset_dir)
    hint_map = _build_hint_map(search_hints or [])
    results: list[dict[str, Any]] = []

    for index, item in enumerate(items):
        result = _lookup_single_item(conn, item, hint_map.get(_normalize_text(str(item.get("name", "")))))
        result["input_index"] = index
        results.append(result)

    return {
        "ok": True,
        "results": results,
        "db_path": str(_DB_PATH or ""),
    }


def _build_hint_map(search_hints: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    hint_map: dict[str, dict[str, Any]] = {}
    for row in search_hints:
        original_name = _normalize_text(str(row.get("original_name", "")))
        if original_name == "":
            continue
        hint_map[original_name] = row
    return hint_map


def _build_search_context(
    raw_name: str,
    item: dict[str, Any],
    hint: dict[str, Any] | None,
) -> dict[str, Any]:
    raw_normalized = _strip_trailing_package_amount(_normalize_text(raw_name))
    hint = hint or {}

    brand_name = _normalize_text(str(hint.get("brand_name", "")))
    food_name = _strip_trailing_package_amount(_normalize_text(str(hint.get("food_name", ""))))
    search_name = _strip_trailing_package_amount(_normalize_text(str(hint.get("search_name", ""))))

    if brand_name and not food_name:
        stripped_food = _strip_prefix_phrase(raw_normalized, brand_name)
        if stripped_food:
            food_name = stripped_food

    if not brand_name:
        inferred_brand, inferred_food = _split_known_brand_prefix(raw_normalized)
        if inferred_brand and inferred_food:
            brand_name = inferred_brand
            if not food_name:
                food_name = inferred_food

    if not food_name:
        food_name = raw_normalized

    food_name = _strip_trailing_package_amount(food_name) or food_name
    generic_food_name = _strip_noise_tokens(food_name) or food_name
    store_name = str(item.get("store_name") or hint.get("store_name") or "").strip()
    store_brand_aliases = _store_brand_aliases(store_name)
    if brand_name:
        store_brand_aliases = [alias for alias in store_brand_aliases if alias != brand_name]

    primary_query = search_name or " ".join([part for part in [brand_name, food_name] if part]).strip() or raw_normalized

    return {
        "raw_name": raw_name,
        "raw_normalized": raw_normalized,
        "brand_name": brand_name,
        "food_name": food_name,
        "generic_food_name": generic_food_name,
        "store_name": store_name,
        "store_brand_aliases": store_brand_aliases,
        "has_explicit_brand": bool(brand_name),
        "primary_query": primary_query,
    }


def _strip_trailing_package_amount(text: str) -> str:
    normalized = _normalize_text(text)
    if normalized == "":
        return ""
    return TRAILING_PACKAGE_PATTERN.sub("", normalized).strip()


def _lookup_single_item(
    conn: sqlite3.Connection,
    item: dict[str, Any],
    hint: dict[str, Any] | None,
) -> dict[str, Any]:
    raw_name = str(item.get("name", "")).strip()
    quantity = _safe_positive(item.get("quantity"), 1.0)
    unit = str(item.get("unit", "PIECE")).upper().strip() or "PIECE"
    search_context = _build_search_context(raw_name, item, hint)
    preferred_types = _preferred_data_types(hint, search_context)
    queries = _query_variants(raw_name, hint, search_context)

    candidate_by_fdc: dict[int, dict[str, Any]] = {}
    attempted_queries: list[str] = []
    for query in queries:
        if query == "":
            continue
        attempted_queries.append(query)
        for row in _search_candidates(conn, query, preferred_types):
            fdc_id = _parse_int(row.get("fdc_id"))
            if fdc_id is None:
                continue
            existing = candidate_by_fdc.get(fdc_id)
            if existing is None or float(row["raw_rank"]) < float(existing["raw_rank"]):
                candidate_by_fdc[fdc_id] = row

    scored_candidates: list[dict[str, Any]] = []
    normalized_query = _singularize_text(_normalize_text(search_context.get("primary_query", raw_name)))
    scoring_query = _singularize_text(
        str(search_context.get("generic_food_name") or search_context.get("food_name") or normalized_query)
    )
    query_tokens = _stem_tokens(scoring_query)
    for candidate in candidate_by_fdc.values():
        candidate_fdc_id = _parse_int(candidate.get("fdc_id"))
        if candidate_fdc_id is None:
            continue
        portions = _portions_for_food(conn, candidate_fdc_id)
        basis = _scale_basis(candidate, portions, quantity, unit)
        score = _candidate_score(
            candidate=candidate,
            query=normalized_query,
            query_tokens=query_tokens,
            search_context=search_context,
            preferred_types=preferred_types,
            basis=basis,
        )
        if basis.scale_factor <= 0.0:
            continue
        scored_candidates.append(
            {
                "candidate": candidate,
                "basis": basis,
                "score": score,
            }
        )

    scored_candidates.sort(key=lambda row: row["score"], reverse=True)
    best = scored_candidates[0] if scored_candidates else None
    if best is not None:
        best = _prefer_store_brand_candidate(best, scored_candidates, search_context)

    if best is None or float(best["score"]) < 0.52:
        best_candidate = best["candidate"] if best else None
        if best_candidate is None:
            _lookup_log(
                "item={} brand_name={} food_name={} store_name={} matched=false attempted_queries={}".format(
                    json.dumps(raw_name),
                    json.dumps(str(search_context.get("brand_name", ""))),
                    json.dumps(str(search_context.get("food_name", ""))),
                    json.dumps(str(search_context.get("store_name", ""))),
                    json.dumps(attempted_queries),
                )
            )
        else:
            _lookup_log(
                "item={} brand_name={} food_name={} store_name={} matched=false best_fdc_id={} best_description={} score={} attempted_queries={}".format(
                    json.dumps(raw_name),
                    json.dumps(str(search_context.get("brand_name", ""))),
                    json.dumps(str(search_context.get("food_name", ""))),
                    json.dumps(str(search_context.get("store_name", ""))),
                    (_parse_int(best_candidate.get("fdc_id")) or 0),
                    json.dumps(str(best_candidate.get("description", ""))),
                    round(float(best["score"]), 4),
                    json.dumps(attempted_queries),
                )
            )
        return {
            "matched": False,
            "name": raw_name,
            "quantity": quantity,
            "unit": unit,
            "protein": 0.0,
            "carb": 0.0,
            "fat": 0.0,
            "confidence": 0.0 if best is None else round(float(best["score"]), 4),
            "source_csv": "",
            "data_type": "" if best_candidate is None else str(best_candidate["data_type"]),
            "fdc_id": 0 if best_candidate is None else (_parse_int(best_candidate.get("fdc_id")) or 0),
            "matched_description": "" if best_candidate is None else str(best_candidate["description"]),
            "notes": (
                "No confident USDA CSV match"
                if best_candidate is None
                else "Best USDA CSV match was below confidence threshold"
            ),
            "attempted_queries": attempted_queries,
        }

    candidate = best["candidate"]
    basis = best["basis"]
    factor = max(0.0, float(basis.scale_factor))
    fdc_id = _parse_int(candidate.get("fdc_id")) or 0
    nutrient_payload = _macro_payload_for_food(conn, fdc_id)
    nutrient_amounts = dict(nutrient_payload["macro_amounts"])
    nutrient_rows = list(nutrient_payload["nutrient_rows"])
    serving_payload = _serving_payload_for_candidate(candidate, nutrient_amounts, portions, quantity, unit)
    protein = round(_to_float(nutrient_amounts.get("protein")) * factor, 2)
    carb = round(_to_float(nutrient_amounts.get("carb")) * factor, 2)
    fat = round(_to_float(nutrient_amounts.get("fat")) * factor, 2)
    scaled_calories = round(_to_float(nutrient_amounts.get("calories")) * factor, 2)

    _lookup_log(
        "item={} brand_name={} food_name={} store_name={} matched=true fdc_id={} data_type={} description={} nutrients={} scaled={} attempted_queries={}".format(
            json.dumps(raw_name),
            json.dumps(str(search_context.get("brand_name", ""))),
            json.dumps(str(search_context.get("food_name", ""))),
            json.dumps(str(search_context.get("store_name", ""))),
            fdc_id,
            json.dumps(str(candidate["data_type"])),
            json.dumps(str(candidate["description"])),
            json.dumps(nutrient_rows, sort_keys=True),
            json.dumps(
                {
                    "quantity": quantity,
                    "unit": unit,
                    "scale_factor": round(factor, 6),
                    "serving_size": str(serving_payload.get("serving_size_text", "")),
                    "serving_unit_key": str(serving_payload.get("serving_unit_key", "")),
                    "serving_count": round(_to_float(serving_payload.get("serving_count")), 4),
                    "calories": scaled_calories,
                    "protein": protein,
                    "carb": carb,
                    "fat": fat,
                },
                sort_keys=True,
            ),
            json.dumps(attempted_queries),
        )
    )

    return {
        "matched": True,
        "name": raw_name,
        "quantity": quantity,
        "unit": unit,
        "protein": protein,
        "carb": carb,
        "fat": fat,
        "calories": scaled_calories,
        "serving_size_text": str(serving_payload.get("serving_size_text", "")),
        "serving_unit_key": str(serving_payload.get("serving_unit_key", "")),
        "serving_count": float(serving_payload.get("serving_count", 0.0)),
        "serving_protein": float(serving_payload.get("protein", protein)),
        "serving_carb": float(serving_payload.get("carb", carb)),
        "serving_fat": float(serving_payload.get("fat", fat)),
        "serving_calories": float(serving_payload.get("calories", scaled_calories)),
        "confidence": round(float(best["score"]), 4),
        "source_csv": _source_csv_for_data_type(str(candidate["data_type"])),
        "data_type": str(candidate["data_type"]),
        "fdc_id": fdc_id,
        "matched_description": str(candidate["description"]),
        "notes": basis.basis_note,
        "attempted_queries": attempted_queries,
    }


def _search_candidates(
    conn: sqlite3.Connection,
    query: str,
    preferred_types: list[str],
) -> list[dict[str, Any]]:
    tokens = [token for token in _normalize_text(query).split() if token not in SEARCH_STOPWORDS]
    if not tokens:
        return []

    fts_query = " AND ".join([f"{token}*" for token in tokens])
    rows = conn.execute(
        """
        SELECT
            foods.fdc_id,
            foods.data_type,
            foods.description,
            foods.normalized_description,
            foods.brand_owner,
            foods.brand_name,
            foods.gtin_upc,
            foods.ingredients,
            foods.serving_size,
            foods.serving_size_unit,
            foods.household_serving_fulltext,
            foods.branded_food_category,
            foods.package_weight,
            foods.short_description,
            nutrients.calories,
            nutrients.protein,
            nutrients.carb,
            nutrients.fat,
            bm25(food_fts, 1.0, 0.8, 0.5, 0.5, 0.3) AS raw_rank
        FROM food_fts
        JOIN foods ON foods.fdc_id = food_fts.rowid
        LEFT JOIN nutrients ON nutrients.fdc_id = foods.fdc_id
        WHERE food_fts MATCH ?
          AND (
              nutrients.calories IS NOT NULL OR
              nutrients.protein IS NOT NULL OR
              nutrients.carb IS NOT NULL OR
              nutrients.fat IS NOT NULL
          )
        LIMIT 40
        """,
        (fts_query,),
    ).fetchall()

    if rows:
        return [dict(row) for row in rows]

    like_pattern = "%" + "%".join(tokens[:4]) + "%"
    fallback_rows = conn.execute(
        """
        SELECT
            foods.fdc_id,
            foods.data_type,
            foods.description,
            foods.normalized_description,
            foods.brand_owner,
            foods.brand_name,
            foods.gtin_upc,
            foods.ingredients,
            foods.serving_size,
            foods.serving_size_unit,
            foods.household_serving_fulltext,
            foods.branded_food_category,
            foods.package_weight,
            foods.short_description,
            nutrients.calories,
            nutrients.protein,
            nutrients.carb,
            nutrients.fat,
            99.0 AS raw_rank
        FROM foods
        LEFT JOIN nutrients ON nutrients.fdc_id = foods.fdc_id
        WHERE foods.normalized_description LIKE ?
          AND (
              nutrients.calories IS NOT NULL OR
              nutrients.protein IS NOT NULL OR
              nutrients.carb IS NOT NULL OR
              nutrients.fat IS NOT NULL
          )
        LIMIT 40
        """,
        (like_pattern,),
    ).fetchall()
    return [dict(row) for row in fallback_rows]


def _candidate_score(
    candidate: dict[str, Any],
    query: str,
    query_tokens: set[str],
    search_context: dict[str, Any],
    preferred_types: list[str],
    basis: MatchBasis,
) -> float:
    description_text = " ".join(
        [
            str(candidate.get("description", "")),
            str(candidate.get("short_description", "")),
        ]
    )
    brand_text = " ".join(
        [
            str(candidate.get("brand_owner", "")),
            str(candidate.get("brand_name", "")),
        ]
    )
    description_norm = _normalize_text(description_text)
    brand_norm = _normalize_text(brand_text)
    candidate_norm = _normalize_text(" ".join([description_text, brand_text]))
    candidate_tokens = _stem_tokens(description_norm if description_norm else candidate_norm)

    food_query = _singularize_text(
        str(search_context.get("generic_food_name") or search_context.get("food_name") or query)
    )
    brand_query = _normalize_text(str(search_context.get("brand_name", "")))
    store_brand_aliases = [
        _normalize_text(str(alias))
        for alias in search_context.get("store_brand_aliases", []) or []
        if _normalize_text(str(alias))
    ]

    coverage = 0.0
    if query_tokens:
        coverage = len(query_tokens & candidate_tokens) / float(len(query_tokens))

    exact_match = description_norm == food_query or candidate_norm == query
    prefix_match = description_norm.startswith(food_query) or candidate_norm.startswith(query)
    phrase_match = (food_query != "" and food_query in description_norm) or (query != "" and query in candidate_norm)
    terminal_match = bool(food_query) and (
        description_norm.endswith(food_query) or description_norm.startswith(food_query)
    )
    brand_exact_match = bool(brand_query) and (brand_norm == brand_query or candidate_norm.startswith(brand_query + " "))
    brand_match = bool(brand_query) and (brand_query in brand_norm or brand_query in candidate_norm)
    store_brand_match = any(alias in brand_norm or alias in candidate_norm for alias in store_brand_aliases)

    extra_tokens = max(0, len(candidate_tokens - query_tokens))
    extra_penalty = 0.03 * extra_tokens
    if len(query_tokens) <= 2:
        extra_penalty = 0.08 * extra_tokens
    extra_penalty = min(0.5 if len(query_tokens) <= 2 else 0.32, extra_penalty)

    score = coverage * 0.55
    if exact_match:
        score += 0.35
    elif prefix_match:
        score += 0.18
    elif phrase_match:
        score += 0.1

    if terminal_match:
        score += 0.08

    if brand_exact_match:
        score += 0.3
    elif brand_match:
        score += 0.2

    score -= extra_penalty

    data_type = str(candidate.get("data_type", ""))
    if brand_query:
        if data_type == "branded_food":
            score += 0.12
            if not brand_match:
                score -= 0.2
        elif data_type in GENERIC_DATA_TYPES:
            score += 0.03
    elif store_brand_aliases:
        if store_brand_match and data_type == "branded_food":
            score += 0.18
        elif store_brand_match:
            score += 0.08
        elif data_type == "branded_food":
            score -= 0.08
        elif data_type in GENERIC_DATA_TYPES:
            score += 0.08
    elif _has_brand_signal(str(search_context.get("raw_name", ""))):
        if data_type == "branded_food":
            score += 0.14
        elif data_type in GENERIC_DATA_TYPES:
            score += 0.04
    else:
        if data_type in GENERIC_DATA_TYPES:
            score += 0.14
        elif data_type == "branded_food":
            score -= 0.08

    score += DATA_TYPE_SCORE.get(data_type, 0.0)

    if preferred_types and data_type in preferred_types:
        score += max(0.05, 0.15 - (preferred_types.index(data_type) * 0.03))

    if basis.scale_confident:
        score += 0.06
    else:
        score -= 0.08

    if all(_to_float(candidate.get(field)) <= 0.0 for field in ("protein", "carb", "fat")):
        score -= 0.1

    raw_rank = _to_float(candidate.get("raw_rank"))
    if raw_rank <= 0.0:
        score += 0.04
    elif raw_rank >= 50.0:
        score -= 0.04

    return score


def _prefer_store_brand_candidate(
    best: dict[str, Any],
    scored_candidates: list[dict[str, Any]],
    search_context: dict[str, Any],
) -> dict[str, Any]:
    if bool(search_context.get("has_explicit_brand")):
        return best

    store_brand_aliases = list(search_context.get("store_brand_aliases", []) or [])
    if store_brand_aliases == []:
        return best

    best_score = float(best.get("score", 0.0))
    best_store_brand: dict[str, Any] | None = None
    for row in scored_candidates:
        candidate = row.get("candidate", {})
        if str(candidate.get("data_type", "")) != "branded_food":
            continue
        if not _candidate_matches_brand_aliases(candidate, store_brand_aliases):
            continue
        row_score = float(row.get("score", 0.0))
        if row_score < 0.78:
            continue
        if best_store_brand is None or row_score > float(best_store_brand.get("score", 0.0)):
            best_store_brand = row

    if best_store_brand is None:
        return best

    if best_store_brand is best:
        return best

    if best_score <= 0.0:
        return best_store_brand

    if float(best_store_brand.get("score", 0.0)) >= (best_score - 0.15):
        return best_store_brand
    return best


def _candidate_matches_brand_aliases(candidate: dict[str, Any], aliases: list[str]) -> bool:
    brand_norm = _normalize_text(
        " ".join(
            [
                str(candidate.get("brand_owner", "")),
                str(candidate.get("brand_name", "")),
            ]
        )
    )
    if brand_norm == "":
        return False
    return any(_normalize_text(alias) in brand_norm for alias in aliases if _normalize_text(alias))


def _brand_phrase_match(query: str, candidate: dict[str, Any]) -> bool:
    tokens = query.split()
    if len(tokens) < 2:
        return False
    prefix = " ".join(tokens[:2])
    haystacks = [
        _normalize_text(str(candidate.get("description", ""))),
        _normalize_text(str(candidate.get("brand_owner", ""))),
        _normalize_text(str(candidate.get("brand_name", ""))),
    ]
    return any(prefix in text for text in haystacks if text)


def _preferred_data_types(
    hint: dict[str, Any] | None,
    search_context: dict[str, Any],
) -> list[str]:
    if bool(search_context.get("has_explicit_brand")) or bool(search_context.get("store_brand_aliases")):
        default_order = [
            "branded_food",
            "foundation_food",
            "sr_legacy_food",
            "survey_fndds_food",
            "agricultural_acquisition",
        ]
    else:
        default_order = [
            "foundation_food",
            "sr_legacy_food",
            "survey_fndds_food",
            "agricultural_acquisition",
            "branded_food",
        ]

    if not hint:
        return default_order
    rows = hint.get("preferred_data_types", []) or []
    allowed = {
        "branded_food",
        "foundation_food",
        "sr_legacy_food",
        "survey_fndds_food",
        "agricultural_acquisition",
    }
    cleaned: list[str] = []
    for row in rows:
        data_type = str(row).strip().lower()
        if data_type in allowed and data_type not in cleaned:
            cleaned.append(data_type)
    for data_type in default_order:
        if data_type not in cleaned:
            cleaned.append(data_type)
    return cleaned


def _query_variants(
    raw_name: str,
    hint: dict[str, Any] | None,
    search_context: dict[str, Any],
) -> list[str]:
    base = _normalize_text(raw_name)
    brand_name = str(search_context.get("brand_name", ""))
    food_name = str(search_context.get("food_name", "")) or base
    generic_food_name = str(search_context.get("generic_food_name", "")) or food_name
    store_brand_aliases = list(search_context.get("store_brand_aliases", []) or [])
    variants: list[str] = []

    def add_variant(text: str) -> None:
        normalized = _normalize_text(text)
        if normalized and normalized not in variants:
            variants.append(normalized)

    if hint:
        add_variant(str(hint.get("search_name", "")))

    if brand_name != "":
        add_variant(f"{brand_name} {food_name}")
        if generic_food_name != food_name:
            add_variant(f"{brand_name} {generic_food_name}")
    elif generic_food_name != "":
        for alias in store_brand_aliases[:4]:
            add_variant(f"{alias} {food_name}")
            if generic_food_name != food_name:
                add_variant(f"{alias} {generic_food_name}")

    add_variant(food_name)
    add_variant(_singularize_text(food_name))
    add_variant(generic_food_name)
    add_variant(_singularize_text(generic_food_name))
    add_variant(base)
    add_variant(_singularize_text(base))
    add_variant(_strip_noise_tokens(base))
    add_variant(_singularize_text(_strip_noise_tokens(base)))

    base_tokens = base.split()
    if len(base_tokens) > 3:
        add_variant(" ".join(base_tokens[1:]))
    if len(base_tokens) > 4:
        add_variant(" ".join(base_tokens[2:]))

    if hint:
        for alias in hint.get("alternate_names", []) or []:
            add_variant(str(alias))

    return variants[:10]


def _strip_prefix_phrase(text: str, prefix: str) -> str:
    normalized_text = _normalize_text(text)
    normalized_prefix = _normalize_text(prefix)
    if normalized_text == normalized_prefix:
        return ""
    if normalized_text.startswith(normalized_prefix + " "):
        return normalized_text[len(normalized_prefix) + 1 :].strip()
    return ""


def _split_known_brand_prefix(text: str) -> tuple[str, str]:
    normalized_text = _normalize_text(text)
    for brand_prefix in KNOWN_BRAND_PREFIXES:
        remainder = _strip_prefix_phrase(normalized_text, brand_prefix)
        if remainder:
            return brand_prefix, remainder
    return "", ""


def _store_brand_aliases(store_name: str) -> list[str]:
    normalized_store = _normalize_text(store_name)
    if normalized_store == "":
        return []
    aliases: list[str] = []
    for store_key, store_aliases in STORE_BRAND_ALIASES.items():
        if store_key in normalized_store or normalized_store in store_key:
            for alias in store_aliases:
                normalized_alias = _normalize_text(alias)
                if normalized_alias and normalized_alias not in aliases:
                    aliases.append(normalized_alias)
    if normalized_store not in aliases:
        aliases.append(normalized_store)
    return aliases[:6]


def _singularize_text(text: str) -> str:
    tokens: list[str] = []
    for token in text.split():
        if len(token) > 4 and token.endswith("es"):
            tokens.append(token[:-2])
        elif len(token) > 3 and token.endswith("s"):
            tokens.append(token[:-1])
        else:
            tokens.append(token)
    return " ".join(tokens)


def _strip_noise_tokens(text: str) -> str:
    tokens = [token for token in text.split() if token not in QUERY_NOISE_TOKENS]
    return " ".join(tokens)


def _scale_basis(
    candidate: dict[str, Any],
    portions: list[dict[str, Any]],
    quantity: float,
    unit: str,
) -> MatchBasis:
    data_type = str(candidate.get("data_type", ""))
    if quantity <= 0.0:
        return MatchBasis(0.0, "Invalid quantity", False)

    if data_type == "branded_food":
        basis = _branded_scale_basis(candidate, portions, quantity, unit)
        if basis.scale_factor > 0.0:
            return basis

    generic_basis = _generic_scale_basis(candidate, portions, quantity, unit)
    if generic_basis.scale_factor > 0.0:
        return generic_basis

    if data_type == "branded_food":
        serving_size = _to_float(candidate.get("serving_size"))
        if serving_size > 0.0 and unit == "PIECE":
            return MatchBasis(
                scale_factor=quantity,
                basis_note="Used branded serving-size fallback: treated each pantry piece as one labeled serving.",
                scale_confident=False,
            )

    return MatchBasis(0.0, "Could not determine quantity basis", False)


def _branded_scale_basis(
    candidate: dict[str, Any],
    portions: list[dict[str, Any]],
    quantity: float,
    unit: str,
) -> MatchBasis:
    serving_size = _to_float(candidate.get("serving_size"))
    serving_unit = str(candidate.get("serving_size_unit", "")).strip()
    if serving_size <= 0.0 or serving_unit == "":
        return MatchBasis(0.0, "Branded record missing serving size", False)

    serving_grams = _serving_gram_weight(candidate, portions)
    total_grams = _total_grams_for_input(candidate, portions, quantity, unit)
    if total_grams > 0.0:
        if _direct_dimension_from_unit(quantity, unit) is not None and unit in {"LB", "OZ"}:
            basis_note = "Scaled branded USDA 100 g nutrient rows from direct mass quantity."
            scale_confident = True
        elif _portion_factor_from_rows(portions, quantity, unit) is not None:
            basis_note = "Scaled branded USDA 100 g nutrient rows using FoodData portion gram weights."
            scale_confident = True
        elif unit == "PIECE" and _best_package_dimension(candidate) is not None:
            basis_note = "Scaled branded USDA 100 g nutrient rows from package size converted to grams."
            scale_confident = False
        elif serving_grams > 0.0:
            basis_note = "Scaled branded USDA 100 g nutrient rows by converting pantry quantity into total grams through the labeled serving weight."
            scale_confident = True
        else:
            basis_note = "Scaled branded USDA 100 g nutrient rows from inferred gram weight."
            scale_confident = False
        return MatchBasis(
            scale_factor=total_grams / 100.0,
            basis_note=basis_note,
            scale_confident=scale_confident,
        )

    if unit == "PIECE" and serving_grams > 0.0:
        return MatchBasis(
            scale_factor=(quantity * serving_grams) / 100.0,
            basis_note="Scaled branded USDA 100 g nutrient rows as one labeled serving per pantry piece because total package size was unavailable.",
            scale_confident=False,
        )

    return MatchBasis(0.0, "Could not convert branded serving size to pantry unit", False)


def _generic_scale_basis(
    candidate: dict[str, Any],
    portions: list[dict[str, Any]],
    quantity: float,
    unit: str,
) -> MatchBasis:
    direct_dim = _direct_dimension_from_unit(quantity, unit)
    if direct_dim and direct_dim[0] == "mass":
        grams = direct_dim[1]
        return MatchBasis(
            scale_factor=grams / 100.0,
            basis_note="Scaled generic USDA record from direct mass quantity.",
            scale_confident=True,
        )

    grams = _portion_factor_from_rows(portions, quantity, unit)
    if grams is not None and grams > 0.0:
        return MatchBasis(
            scale_factor=grams / 100.0,
            basis_note="Scaled generic USDA record from FoodData portion weights.",
            scale_confident=True,
        )

    return MatchBasis(0.0, "No generic portion mapping found for pantry unit", False)


def _household_unit_basis(candidate: dict[str, Any]) -> tuple[str, float] | None:
    text = str(candidate.get("household_serving_fulltext", "")).strip()
    if text == "":
        return None
    match = HOUSEHOLD_PATTERN.search(text.lower())
    if not match:
        return None
    amount = _to_float(match.group("amount"))
    unit = _unit_key_from_text(match.group("unit"))
    if amount <= 0.0 or unit is None:
        return None
    return unit, amount


def _best_package_dimension(candidate: dict[str, Any]) -> tuple[str, float] | None:
    texts = [
        str(candidate.get("package_weight", "")),
        str(candidate.get("description", "")),
        str(candidate.get("short_description", "")),
    ]
    candidates: list[tuple[str, float]] = []
    for text in texts:
        for match in PACKAGE_PATTERN.finditer(text.lower()):
            amount = _to_float(match.group("amount"))
            unit = match.group("unit").strip().lower()
            dim = _convert_unit_amount(amount, unit)
            if dim:
                candidates.append(dim)
    if not candidates:
        return None
    mass = [row for row in candidates if row[0] == "mass"]
    if mass:
        return max(mass, key=lambda row: row[1])
    volume = [row for row in candidates if row[0] == "volume"]
    if volume:
        return max(volume, key=lambda row: row[1])
    return candidates[0]


def _serving_dimension(candidate: dict[str, Any]) -> tuple[str, float] | None:
    household_text = str(candidate.get("household_serving_fulltext", "")).strip()
    if household_text != "":
        match = HOUSEHOLD_PATTERN.search(household_text.lower())
        if match:
            amount = _to_float(match.group("amount"))
            unit = str(match.group("unit") or "").strip()
            if amount > 0.0 and unit != "":
                dim = _convert_unit_amount(amount, unit)
                if dim is not None:
                    return dim

    serving_size = _to_float(candidate.get("serving_size"))
    serving_unit = str(candidate.get("serving_size_unit", "")).strip()
    if serving_size > 0.0 and serving_unit != "":
        return _convert_unit_amount(serving_size, serving_unit)
    return None


def _serving_gram_weight(
    candidate: dict[str, Any],
    portions: list[dict[str, Any]],
) -> float:
    serving_size = _to_float(candidate.get("serving_size"))
    serving_unit = str(candidate.get("serving_size_unit", "")).strip()
    if serving_size > 0.0 and serving_unit != "":
        serving_dim = _convert_unit_amount(serving_size, serving_unit)
        if serving_dim is not None and serving_dim[0] == "mass":
            return serving_dim[1]

    household_text = str(candidate.get("household_serving_fulltext", "")).strip()
    household_unit_key = _serving_unit_key_from_text(household_text)
    household_amount = _serving_amount_from_text(household_text)
    if household_unit_key is not None and household_amount > 0.0:
        grams = _portion_factor_from_rows(portions, household_amount, household_unit_key)
        if grams is not None and grams > 0.0:
            return grams

    return 0.0


def _direct_dimension_from_unit(quantity: float, unit: str) -> tuple[str, float] | None:
    if unit == "LB":
        return "mass", quantity * MASS_TO_G["lb"]
    if unit == "OZ":
        return "mass", quantity * MASS_TO_G["oz"]
    if unit == "CUP":
        return "volume", quantity * VOLUME_TO_ML["cup"]
    if unit == "TBSP":
        return "volume", quantity * VOLUME_TO_ML["tbsp"]
    if unit == "TSP":
        return "volume", quantity * VOLUME_TO_ML["tsp"]
    return None


def _total_grams_for_input(
    candidate: dict[str, Any],
    portions: list[dict[str, Any]],
    quantity: float,
    unit: str,
) -> float:
    direct_dim = _direct_dimension_from_unit(quantity, unit)
    if direct_dim is not None and direct_dim[0] == "mass":
        return direct_dim[1]

    portion_grams = _portion_factor_from_rows(portions, quantity, unit)
    if portion_grams is not None and portion_grams > 0.0:
        return portion_grams

    serving_grams = _serving_gram_weight(candidate, portions)
    if serving_grams <= 0.0:
        return 0.0

    household = _household_unit_basis(candidate)
    if household is not None and household[0] == unit and household[1] > 0.0:
        return (quantity / household[1]) * serving_grams

    serving_dim = _serving_dimension(candidate)
    if (
        direct_dim is not None
        and serving_dim is not None
        and direct_dim[0] == serving_dim[0]
        and serving_dim[1] > 0.0
    ):
        return (direct_dim[1] / serving_dim[1]) * serving_grams

    if unit == "PIECE":
        package_dim = _best_package_dimension(candidate)
        if package_dim is not None:
            if package_dim[0] == "mass":
                return quantity * package_dim[1]
            if serving_dim is not None and package_dim[0] == serving_dim[0] and serving_dim[1] > 0.0:
                return quantity * (package_dim[1] / serving_dim[1]) * serving_grams
        return quantity * serving_grams

    return 0.0


def _portion_factor_from_rows(
    portions: list[dict[str, Any]],
    quantity: float,
    unit: str,
) -> float | None:
    if not portions:
        return None

    if unit == "PIECE":
        portion = _best_piece_portion(portions)
        if portion is None:
            return None
        return quantity * (_to_float(portion["gram_weight"]) / max(1.0, _to_float(portion["amount"])))

    aliases = {
        "CUP": ("cup",),
        "TBSP": ("tbsp", "tablespoon"),
        "TSP": ("tsp", "teaspoon"),
        "CLOVE": ("clove",),
        "BUNCH": ("bunch",),
    }.get(unit, ())

    best_row: dict[str, Any] | None = None
    for row in portions:
        row_text = _normalize_text(
            " ".join(
                [
                    str(row.get("unit_name", "")),
                    str(row.get("portion_description", "")),
                    str(row.get("modifier", "")),
                ]
            )
        )
        if any(alias in row_text for alias in aliases):
            best_row = row
            break

    if best_row is None:
        return None

    amount = max(1.0, _to_float(best_row.get("amount")))
    return quantity * (_to_float(best_row.get("gram_weight")) / amount)


def _best_piece_portion(portions: list[dict[str, Any]]) -> dict[str, Any] | None:
    normalized_rows = []
    for row in portions:
        text = _normalize_text(
            " ".join(
                [
                    str(row.get("unit_name", "")),
                    str(row.get("portion_description", "")),
                    str(row.get("modifier", "")),
                ]
            )
        )
        normalized_rows.append((row, text))

    for keyword in PIECE_PRIORITY:
        for row, text in normalized_rows:
            if keyword in text:
                return row

    for row, text in normalized_rows:
        if "cup" not in text and "tbsp" not in text and "tsp" not in text:
            return row
    return None


def _portions_for_food(conn: sqlite3.Connection, fdc_id: int) -> list[dict[str, Any]]:
    cached = _PORTION_CACHE.get(fdc_id)
    if cached is not None:
        return cached
    rows = conn.execute(
        """
        SELECT amount, unit_name, portion_description, modifier, gram_weight
        FROM portions
        WHERE fdc_id = ?
        """,
        (fdc_id,),
    ).fetchall()
    cached_rows = [dict(row) for row in rows]
    _PORTION_CACHE[fdc_id] = cached_rows
    return cached_rows


def _macro_payload_for_food(conn: sqlite3.Connection, fdc_id: int) -> dict[str, Any]:
    cached = _FOOD_NUTRIENT_CACHE.get(fdc_id)
    if cached is not None:
        return cached

    rows = conn.execute(
        """
        SELECT
            nutrient_definitions.nutrient_id,
            nutrient_definitions.name,
            nutrient_definitions.unit_name,
            nutrient_definitions.mapped_field,
            nutrient_definitions.calories_priority,
            food_nutrients.amount
        FROM food_nutrients
        JOIN nutrient_definitions
            ON nutrient_definitions.nutrient_id = food_nutrients.nutrient_id
        WHERE food_nutrients.fdc_id = ?
          AND nutrient_definitions.mapped_field != ''
        """,
        (fdc_id,),
    ).fetchall()

    macro_amounts: dict[str, float] = {
        "calories": 0.0,
        "protein": 0.0,
        "carb": 0.0,
        "fat": 0.0,
    }
    calorie_rows: list[tuple[int, float]] = []
    nutrient_rows: list[dict[str, Any]] = []
    for row in rows:
        mapped_field = str(row["mapped_field"])
        amount = _to_float(row["amount"])
        nutrient_rows.append(
            {
                "nutrient_id": int(row["nutrient_id"]),
                "name": str(row["name"]),
                "unit_name": str(row["unit_name"]),
                "mapped_field": mapped_field,
                "amount": amount,
            }
        )
        if mapped_field == "calories":
            calorie_rows.append((int(row["calories_priority"]), amount))
        elif mapped_field in macro_amounts:
            macro_amounts[mapped_field] = amount

    if calorie_rows:
        calorie_rows.sort(key=lambda item: item[0])
        macro_amounts["calories"] = calorie_rows[0][1]

    nutrient_rows.sort(key=lambda row: (str(row["mapped_field"]), int(row["nutrient_id"])))
    payload = {
        "macro_amounts": macro_amounts,
        "nutrient_rows": nutrient_rows,
    }
    _FOOD_NUTRIENT_CACHE[fdc_id] = payload
    return payload


def _serving_payload_for_candidate(
    candidate: dict[str, Any],
    nutrient_amounts: dict[str, float],
    portions: list[dict[str, Any]] | None = None,
    quantity: float = 0.0,
    unit: str = "",
) -> dict[str, Any]:
    household_text = str(candidate.get("household_serving_fulltext", "")).strip()
    serving_size = _to_float(candidate.get("serving_size"))
    serving_unit = str(candidate.get("serving_size_unit", "")).strip()
    portions = portions or []
    serving_dim = _serving_dimension(candidate)
    serving_grams = _serving_gram_weight(candidate, portions)

    factor = 0.0
    if serving_grams > 0.0:
        factor = serving_grams / 100.0
    elif serving_dim is not None and serving_dim[0] == "mass":
        factor = serving_dim[1] / 100.0

    if household_text != "" and factor > 0.0:
        payload = {
            "serving_size_text": household_text,
            "serving_unit_key": _serving_unit_key_from_text(household_text),
            "serving_amount": _serving_amount_from_text(household_text),
            "serving_gram_weight": serving_grams,
            "serving_dim_kind": "mass" if serving_grams > 0.0 else ("" if serving_dim is None else serving_dim[0]),
            "serving_dim_value": serving_grams if serving_grams > 0.0 else (0.0 if serving_dim is None else serving_dim[1]),
            "calories": round(_to_float(nutrient_amounts.get("calories")) * factor, 2),
            "protein": round(_to_float(nutrient_amounts.get("protein")) * factor, 2),
            "carb": round(_to_float(nutrient_amounts.get("carb")) * factor, 2),
            "fat": round(_to_float(nutrient_amounts.get("fat")) * factor, 2),
        }
        payload["serving_count"] = _derive_serving_count(candidate, portions, quantity, unit, payload)
        return payload

    if serving_size > 0.0 and serving_unit != "" and factor > 0.0:
        serving_text = "{} {}".format(_format_amount(serving_size), serving_unit)
        payload = {
            "serving_size_text": serving_text,
            "serving_unit_key": _serving_unit_key_from_text(serving_text),
            "serving_amount": serving_size if _serving_unit_key_from_text(serving_text) is not None else 0.0,
            "serving_gram_weight": serving_grams,
            "serving_dim_kind": "mass" if serving_grams > 0.0 else ("" if serving_dim is None else serving_dim[0]),
            "serving_dim_value": serving_grams if serving_grams > 0.0 else (0.0 if serving_dim is None else serving_dim[1]),
            "calories": round(_to_float(nutrient_amounts.get("calories")) * factor, 2),
            "protein": round(_to_float(nutrient_amounts.get("protein")) * factor, 2),
            "carb": round(_to_float(nutrient_amounts.get("carb")) * factor, 2),
            "fat": round(_to_float(nutrient_amounts.get("fat")) * factor, 2),
        }
        payload["serving_count"] = _derive_serving_count(candidate, portions, quantity, unit, payload)
        return payload

    portion_payload = _serving_payload_from_portions(portions, nutrient_amounts)
    if portion_payload is not None:
        portion_payload["serving_count"] = _derive_serving_count(candidate, portions, quantity, unit, portion_payload)
        return portion_payload

    return {
        "serving_size_text": "",
        "serving_unit_key": "",
        "serving_count": 0.0,
        "calories": round(_to_float(nutrient_amounts.get("calories")), 2),
        "protein": round(_to_float(nutrient_amounts.get("protein")), 2),
        "carb": round(_to_float(nutrient_amounts.get("carb")), 2),
        "fat": round(_to_float(nutrient_amounts.get("fat")), 2),
    }


def _serving_payload_from_portions(
    portions: list[dict[str, Any]],
    nutrient_amounts: dict[str, float],
) -> dict[str, Any] | None:
    row = _best_serving_portion(portions)
    if row is None:
        return None

    grams = _to_float(row.get("gram_weight"))
    if grams <= 0.0:
        return None

    serving_text = _portion_serving_text(row)
    if serving_text == "":
        serving_text = "{} g".format(_format_amount(grams))

    factor = grams / 100.0
    return {
        "serving_size_text": serving_text,
        "serving_unit_key": _portion_unit_key(row) or _serving_unit_key_from_text(serving_text),
        "serving_amount": max(1.0, _to_float(row.get("amount"))),
        "serving_gram_weight": grams,
        "serving_dim_kind": "mass",
        "serving_dim_value": grams,
        "calories": round(_to_float(nutrient_amounts.get("calories")) * factor, 2),
        "protein": round(_to_float(nutrient_amounts.get("protein")) * factor, 2),
        "carb": round(_to_float(nutrient_amounts.get("carb")) * factor, 2),
        "fat": round(_to_float(nutrient_amounts.get("fat")) * factor, 2),
    }


def _best_serving_portion(portions: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not portions:
        return None

    piece_portion = _best_piece_portion(portions)
    if piece_portion is not None and _to_float(piece_portion.get("gram_weight")) > 0.0:
        return piece_portion

    preferred_aliases = [
        ("slice", "slices"),
        ("cup",),
        ("tbsp", "tablespoon"),
        ("tsp", "teaspoon"),
        ("clove",),
        ("bunch",),
    ]

    normalized_rows: list[tuple[dict[str, Any], str]] = []
    for row in portions:
        text = _normalize_text(
            " ".join(
                [
                    str(row.get("unit_name", "")),
                    str(row.get("portion_description", "")),
                    str(row.get("modifier", "")),
                ]
            )
        )
        normalized_rows.append((row, text))

    for aliases in preferred_aliases:
        for row, text in normalized_rows:
            if _to_float(row.get("gram_weight")) <= 0.0:
                continue
            if any(alias in text for alias in aliases):
                return row

    for row in portions:
        if _to_float(row.get("gram_weight")) > 0.0:
            return row
    return None


def _portion_serving_text(row: dict[str, Any]) -> str:
    amount = _to_float(row.get("amount"))
    if amount <= 0.0:
        amount = 1.0

    label_parts: list[str] = []
    unit_name = str(row.get("unit_name", "")).strip()
    portion_description = str(row.get("portion_description", "")).strip()
    modifier = str(row.get("modifier", "")).strip()

    if unit_name:
        label_parts.append(unit_name)
    if portion_description and _normalize_text(portion_description) != _normalize_text(" ".join(label_parts)):
        label_parts.append(portion_description)
    joined_label = " ".join(label_parts).strip()
    if modifier and _normalize_text(modifier) not in _normalize_text(joined_label):
        label_parts.append(modifier)

    label = " ".join([part for part in label_parts if part]).strip()
    if label == "":
        return ""
    return "{} {}".format(_format_amount(amount), label).strip()


def _serving_unit_key_from_text(text: str) -> str | None:
    raw = str(text or "").strip()
    if raw == "":
        return None
    match = HOUSEHOLD_PATTERN.search(raw.lower())
    if match:
        return _unit_key_from_text(match.group("unit"))
    normalized = _normalize_text(raw)
    for token in normalized.split():
        unit_key = _unit_key_from_text(token)
        if unit_key is not None:
            return unit_key
    return None


def _serving_amount_from_text(text: str) -> float:
    raw = str(text or "").strip()
    if raw == "":
        return 0.0
    match = HOUSEHOLD_PATTERN.search(raw.lower())
    if match:
        return _to_float(match.group("amount"))
    return 0.0


def _portion_unit_key(row: dict[str, Any]) -> str | None:
    text = _normalize_text(
        " ".join(
            [
                str(row.get("unit_name", "")),
                str(row.get("portion_description", "")),
                str(row.get("modifier", "")),
            ]
        )
    )
    for token in text.split():
        unit_key = _unit_key_from_text(token)
        if unit_key is not None:
            return unit_key
    return None


def _total_dimension_for_input(
    candidate: dict[str, Any],
    portions: list[dict[str, Any]],
    quantity: float,
    unit: str,
) -> tuple[str, float] | None:
    total_grams = _total_grams_for_input(candidate, portions, quantity, unit)
    if total_grams > 0.0:
        return "mass", total_grams

    direct_dim = _direct_dimension_from_unit(quantity, unit)
    if direct_dim is not None:
        return direct_dim

    total_grams = _portion_factor_from_rows(portions, quantity, unit)
    if total_grams is not None and total_grams > 0.0:
        return "mass", total_grams

    if unit == "PIECE":
        package_dim = _best_package_dimension(candidate)
        if package_dim is not None:
            return package_dim[0], quantity * package_dim[1]

    return None


def _derive_serving_count(
    candidate: dict[str, Any],
    portions: list[dict[str, Any]],
    quantity: float,
    unit: str,
    serving_payload: dict[str, Any],
) -> float:
    if quantity <= 0.0:
        return 0.0

    serving_grams = _to_float(serving_payload.get("serving_gram_weight"))
    total_grams = _total_grams_for_input(candidate, portions, quantity, unit)
    if serving_grams > 0.0 and total_grams > 0.0:
        return total_grams / serving_grams

    serving_dim_kind = str(serving_payload.get("serving_dim_kind", "")).strip()
    serving_dim_value = _to_float(serving_payload.get("serving_dim_value"))
    total_dim = _total_dimension_for_input(candidate, portions, quantity, unit)
    if (
        total_dim is not None
        and serving_dim_kind != ""
        and serving_dim_value > 0.0
        and total_dim[0] == serving_dim_kind
    ):
        return total_dim[1] / serving_dim_value

    serving_unit_key = str(serving_payload.get("serving_unit_key", "")).strip()
    serving_amount = _to_float(serving_payload.get("serving_amount"))
    if serving_unit_key != "" and serving_amount > 0.0 and unit == serving_unit_key:
        return quantity / serving_amount

    household = _household_unit_basis(candidate)
    if household is not None and household[0] == unit and household[1] > 0.0:
        return quantity / household[1]

    if serving_grams > 0.0 and total_dim is not None and total_dim[0] == "mass" and total_dim[1] > 0.0:
        return total_dim[1] / serving_grams

    return 0.0


def _format_amount(amount: float) -> str:
    rounded = round(float(amount), 4)
    if abs(rounded - round(rounded)) < 0.0001:
        return str(int(round(rounded)))
    text = "{:.4f}".format(rounded)
    while "." in text and text.endswith("0"):
        text = text[:-1]
    if text.endswith("."):
        text = text[:-1]
    return text


def _source_csv_for_data_type(data_type: str) -> str:
    if data_type == "branded_food":
        return "food.csv + branded_food.csv + food_nutrient.csv"
    return "food.csv + food_nutrient.csv"


def _has_brand_signal(raw_name: str) -> bool:
    normalized = _normalize_text(raw_name)
    tokens = normalized.split()
    if any(token in BRAND_SIGNAL_TOKENS for token in tokens):
        return True
    return bool(re.search(r"\d", raw_name))


def _normalize_text(text: str) -> str:
    lowered = text.lower()
    lowered = lowered.replace("&", " and ")
    lowered = re.sub(r"[^a-z0-9]+", " ", lowered)
    return " ".join(lowered.split())


def _stem_tokens(text: str) -> set[str]:
    stems: set[str] = set()
    for token in text.split():
        if len(token) > 4 and token.endswith("es"):
            stems.add(token[:-2])
        elif len(token) > 3 and token.endswith("s"):
            stems.add(token[:-1])
        stems.add(token)
    return stems


def _convert_unit_amount(amount: float, unit_text: str) -> tuple[str, float] | None:
    normalized = _normalize_text(unit_text)
    if normalized in MASS_TO_G:
        return "mass", amount * MASS_TO_G[normalized]
    if normalized in VOLUME_TO_ML:
        return "volume", amount * VOLUME_TO_ML[normalized]
    return None


def _unit_key_from_text(unit_text: str) -> str | None:
    normalized = _normalize_text(unit_text)
    if normalized in {"cup", "cups"}:
        return "CUP"
    if normalized in {"tbsp", "tablespoon", "tablespoons"}:
        return "TBSP"
    if normalized in {"tsp", "teaspoon", "teaspoons"}:
        return "TSP"
    if normalized in {"piece", "pieces", "whole"}:
        return "PIECE"
    if normalized in {"egg", "eggs"}:
        return "PIECE"
    if normalized in {"slice", "slices"}:
        return "PIECE"
    if normalized in {"clove", "cloves"}:
        return "CLOVE"
    if normalized in {"bunch", "bunches"}:
        return "BUNCH"
    return None


def _safe_positive(value: Any, fallback: float) -> float:
    numeric = _to_float(value)
    if numeric <= 0.0:
        return fallback
    return numeric


def _to_float(value: Any) -> float:
    if value in (None, ""):
        return 0.0
    if isinstance(value, (int, float)):
        if math.isnan(value) or math.isinf(value):
            return 0.0
        return float(value)
    try:
        text = str(value).strip()
        if text == "":
            return 0.0
        return float(text)
    except Exception:
        return 0.0
