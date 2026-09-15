"""
Bronze layer: download the BC Surgical Wait Times files exactly as published.

Nothing is cleaned or reshaped here. The only job of this script is to get the
source files onto disk unchanged, and to write down where each one came from and
when it was fetched. Everything downstream reads from here, never from the web.

Source:  BC Data Catalogue, dataset "bc-surgical-wait-times"
Owner:   Health Sector Information Analysis and Reporting, BC Ministry of Health
Licence: Open Government Licence - British Columbia
"""
import re
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

def safe_filename(resource):
    """Derive a local filename for a resource from its published name.

    The download URL is deliberately not used. Its last segment is sometimes
    not a real filename (one is literally `___`), and it changes whenever a
    file is reissued. Naming every file from the resource name gives one rule
    for all of them.
    """
    slug = re.sub(r"[^A-Za-z0-9]+", "-", resource["name"]).strip("-").lower()
    extension = "." + resource.get("format", "xlsx").lower()
    return slug + extension

def download(resource):
    """Fetch one resource to data/raw and return a provenance record for it."""
    url = resource["url"]
    target = RAW_DIR / safe_filename(resource)

    response = requests.get(url, timeout=300)
    response.raise_for_status()
    target.write_bytes(response.content)

    # A checksum lets us tell later whether the Ministry restated the file.
    # The dataset description warns the data is subject to restating, so this
    # is not a theoretical concern.
    checksum = hashlib.sha256(response.content).hexdigest()

    return {
        "resource_id": resource["id"],
        "resource_name": resource.get("name"),
        "format": resource.get("format"),
        "source_url": url,
        # Forward slashes, so the committed manifest also resolves on Linux CI.
        "local_path": target.relative_to(RAW_DIR.parents[1]).as_posix(),
        "bytes": len(response.content),
        "sha256": checksum,
        "fetched_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


def main():
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    records = []
    for resource in list_resources():
        print(f"downloading {resource.get('name')} ...")
        record = download(resource)
        print(f"  -> {record['local_path']}  ({record['bytes']:,} bytes)")
        records.append(record)

    MANIFEST.write_text(json.dumps(records, indent=2))
    print(f"\n{len(records)} file(s) written. Manifest: {MANIFEST}")


if __name__ == "__main__":
    main()