import argparse
import json
import re
from pathlib import Path


def flatten_records(obj):
    if isinstance(obj, dict):
        if isinstance(obj.get("data"), list):
            for item in obj["data"]:
                yield from flatten_records(item)
        elif "kind" in obj and "data" in obj:
            yield obj
        else:
            for value in obj.values():
                yield from flatten_records(value)
    elif isinstance(obj, list):
        for item in obj:
            yield from flatten_records(item)


def deep_get(obj, path):
    cur = obj
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def first_present(obj, paths):
    for path in paths:
        value = deep_get(obj, path)
        if value not in ("", None, [], {}):
            return value
    return ""


def walk_dicts(obj):
    if isinstance(obj, dict):
        yield obj
        for value in obj.values():
            yield from walk_dicts(value)
    elif isinstance(obj, list):
        for item in obj:
            yield from walk_dicts(item)


def looks_like_resource(d):
    if not isinstance(d, dict):
        return False

    rid = d.get("id", "")
    return (
        ("name" in d and "type" in d)
        or ("properties" in d and isinstance(d["properties"], dict))
        or (isinstance(rid, str) and "/subscriptions/" in rid)
        or ("defaultHostName" in d)
    )


def find_resource_payload(record):
    data = record.get("data", {})
    if not isinstance(data, dict):
        return {}

    # Best case: the top-level data object is already the resource payload
    if looks_like_resource(data):
        return data

    # Otherwise search nested dicts and pick the first resource-like object
    for candidate in walk_dicts(data):
        if candidate is data:
            continue
        if looks_like_resource(candidate):
            return candidate

    return data


def extract_subid(value):
    if not isinstance(value, str):
        return ""
    match = re.search(r"/subscriptions/([^/]+)", value, re.IGNORECASE)
    return match.group(1) if match else value


def extract_rg(value):
    if not isinstance(value, str):
        return ""
    match = re.search(r"/resourceGroups/([^/]+)", value, re.IGNORECASE)
    return match.group(1) if match else ""


def get_state(resource, record_data):
    return (
        first_present(resource, [
            "properties.state",
            "state",
            "properties.provisioningState",
            "provisioningState",
            "status",
        ])
        or first_present(record_data, [
            "properties.state",
            "state",
            "properties.provisioningState",
            "provisioningState",
            "status",
        ])
    )


def get_default_hostname(resource, record_data):
    host = first_present(resource, [
        "properties.defaultHostName",
        "defaultHostName",
    ])
    if host:
        return host

    enabled = first_present(resource, [
        "properties.enabledHostnames",
        "enabledHostnames",
        "properties.hostNames",
        "hostNames",
    ])
    if isinstance(enabled, list) and enabled:
        return enabled[0]

    enabled = first_present(record_data, [
        "properties.defaultHostName",
        "defaultHostName",
        "properties.enabledHostnames",
        "enabledHostnames",
        "properties.hostNames",
        "hostNames",
    ])
    if isinstance(enabled, list) and enabled:
        return enabled[0]

    return enabled if isinstance(enabled, str) else ""


def build_rows(records):
    rows = []

    for record in records:
        kind = record.get("kind", "")
        record_data = record.get("data", {}) if isinstance(record.get("data"), dict) else {}
        resource = find_resource_payload(record)

        rid = first_present(resource, ["id"]) or first_present(record_data, ["id"])
        subid = (
            first_present(resource, ["subscriptionId", "subscriptionID", "subId"])
            or first_present(record_data, ["subscriptionId", "subscriptionID", "subId"])
            or extract_subid(rid)
        )

        rg = (
            first_present(resource, ["resourceGroupName", "resourceGroup", "rg", "resource_group"])
            or first_present(record_data, ["resourceGroupName", "resourceGroup", "rg", "resource_group"])
            or extract_rg(rid)
            or extract_rg(first_present(record_data, ["resourceGroupId"]))
        )

        tenant = (
            first_present(resource, ["tenantId", "tenantID", "tenant"])
            or first_present(record_data, ["tenantId", "tenantID", "tenant"])
        )

        name = (
            first_present(resource, ["name", "displayName"])
            or first_present(record_data, ["name", "displayName"])
        )

        rtype = (
            first_present(resource, ["type", "kind"])
            or first_present(record_data, ["type", "kind"])
        )

        location = (
            first_present(resource, ["location", "region"])
            or first_present(record_data, ["location", "region"])
        )

        row = {
            "Kind": kind,
            "Name": name,
            "Type": rtype,
            "Id": rid,
            "RG": rg,
            "SubId": subid,
            "TenantId": tenant,
            "Location": location,
            "State": get_state(resource, record_data),
            "DefaultHostName": get_default_hostname(resource, record_data),
        }
        rows.append(row)

    return rows


def print_vertical(rows):
    if not rows:
        print("No matching records found.")
        return

    fields = [
        "Kind",
        "Name",
        "Type",
        "Id",
        "RG",
        "SubId",
        "TenantId",
        "Location",
        "State",
        "DefaultHostName",
    ]

    for index, row in enumerate(rows, 1):
        print(f"[{index}]")
        for field in fields:
            value = row.get(field, "")
            if value not in ("", None):
                print(f"{field}: {value}")
        print("-" * 80)


def main():
    parser = argparse.ArgumentParser(
        description="Summarize Azure export JSON files in a readable vertical format."
    )
    parser.add_argument("json_file", help="Path to JSON file")
    parser.add_argument("--kind", help="Filter by exact kind, e.g. AZFunctionApp")
    args = parser.parse_args()

    path = Path(args.json_file)
    with path.open("r", encoding="utf-8") as handle:
        obj = json.load(handle)

    records = list(flatten_records(obj))
    rows = build_rows(records)

    if args.kind:
        rows = [row for row in rows if row["Kind"] == args.kind]

    print_vertical(rows)


if __name__ == "__main__":
    main()