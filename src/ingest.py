"""
Bronze layer: download the BC Surgical Wait Times files exactly as published.

Nothing is cleaned or reshaped here. The only job of this script is to get the
source files onto disk unchanged, and to write down where each one came from and
when it was fetched. Everything downstream reads from here, never from the web.

Files are stored under the sha256 of their own bytes, so a version is never
overwritten by a later one. The Ministry restates this data, and a conclusion
drawn from a file that no longer exists cannot be checked. The checksum is both
the filename and the proof that the file is the one a result was computed from.

The manifest is the index: one record per version ever fetched, not one per
resource. Downstream reads the most recently fetched version of a resource.

Source:  BC Data Catalogue, dataset "bc-surgical-wait-times"
Owner:   Health Sector Information Analysis and Reporting, BC Ministry of Health
Licence: Open Government Licence - British Columbia
"""
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import requests

# The dataset's stable slug in the BC Data Catalogue. Resource download URLs
# change when files are reissued, so we resolve them through the API each run
# instead of hard-coding them.
CKAN_API = "https://catalogue.data.gov.bc.ca/api/3/action/package_show"
DATASET_ID = "bc-surgical-wait-times"

RAW_DIR = Path(__file__).resolve().parents[1] / "data" / "raw"
MANIFEST = RAW_DIR / "_manifest.json"


def list_resources():
    """Ask the catalogue what files currently exist for this dataset."""
    response = requests.get(CKAN_API, params={"id": DATASET_ID}, timeout=60)
    response.raise_for_status()
    payload = response.json()

    if not payload.get("success"):
        raise RuntimeError(f"Catalogue API returned success=false for {DATASET_ID}")

    resources = payload["result"]["resources"]
    # We only want the data files, not the HTML metadata link.
    return [r for r in resources if r.get("format", "").upper() in {"XLSX", "CSV"}]


def fetch(resource):
    """Download one resource, store it under its checksum, describe the version.

    Returns the record and whether the bytes were new to this machine. Identical
    bytes produce an identical filename, so a re-run of an unchanged file writes
    nothing and leaves the earlier copy exactly as it was.
    """
    url = resource["url"]

    response = requests.get(url, timeout=300)
    response.raise_for_status()

    checksum = hashlib.sha256(response.content).hexdigest()
    extension = "." + resource.get("format", "xlsx").lower()
    target = RAW_DIR / (checksum + extension)

    is_new = not target.exists()
    if is_new:
        target.write_bytes(response.content)

    record = {
        "resource_id": resource["id"],
        "resource_name": resource.get("name"),
        "format": resource.get("format"),
        "source_url": url,
        # Forward slashes, so the committed manifest also resolves on Linux CI.
        "local_path": target.relative_to(RAW_DIR.parents[1]).as_posix(),
        "bytes": len(response.content),
        "sha256": checksum,
    }
    return record, is_new


def load_manifest():
    """Every version fetched so far, or an empty history on a first run."""
    if not MANIFEST.exists():
        return []

    records = json.loads(MANIFEST.read_text())
    for record in records:
        # Manifests written before versions were kept recorded a single
        # fetched_at_utc per resource. Read one as a version seen once, so the
        # date the file was first held is not lost in the migration.
        if "first_fetched_at_utc" not in record:
            fetched = record.pop("fetched_at_utc", None)
            record["first_fetched_at_utc"] = fetched
            record["last_fetched_at_utc"] = fetched
    return records


def main():
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    # A version is a resource and a checksum together. The same file fetched
    # twice is one version seen twice, not two versions.
    history = {(r["resource_id"], r["sha256"]): r for r in load_manifest()}
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    new_versions = 0

    for resource in list_resources():
        print(f"fetching {resource.get('name')} ...")
        record, is_new_file = fetch(resource)
        key = (record["resource_id"], record["sha256"])

        if key in history:
            # Same bytes as a version already recorded. Refresh the catalogue
            # metadata, which can change while the file does not, and keep the
            # date this version was first seen.
            known = history[key]
            known.update(record)
            known["last_fetched_at_utc"] = now
            print(f"  unchanged since {known['first_fetched_at_utc']}"
                  f"  ({record['sha256'][:12]})")
        else:
            record["first_fetched_at_utc"] = now
            record["last_fetched_at_utc"] = now
            history[key] = record
            new_versions += 1
            print(f"  new version  {record['sha256'][:12]}"
                  f"  ({record['bytes']:,} bytes)"
                  f"{'' if is_new_file else ', bytes already on disk'}")

    versions = sorted(
        history.values(),
        key=lambda r: (r["resource_id"], r["first_fetched_at_utc"]),
    )
    MANIFEST.write_text(json.dumps(versions, indent=2))

    print(f"\n{new_versions} new version(s), {len(versions)} in the manifest: {MANIFEST}")


if __name__ == "__main__":
    main()
