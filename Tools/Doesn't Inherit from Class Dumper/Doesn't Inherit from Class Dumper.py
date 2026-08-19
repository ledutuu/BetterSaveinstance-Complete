# Dumps instances that don't inherit from Instance (objects that arem't instances)
# The class to check from can be changed

import requests
import os
import re

def check_inh(name, mapping, target):
    curr = mapping.get(name)
    while curr:
        if curr["Name"] == target: return True
        curr = mapping.get(curr["Superclass"])
    return False

def fetch(vh=None):
    resp, vh = get_api_response(vh)
    classes = resp.json()["Classes"]
    mapping = {c["Name"]: c for c in classes}
    s = f"{vh}\n\n"
    for target in ["Object", "Instance"]:
        s += f"Classes that do NOT inherit from {target}:\n" + "-" * 40 + "\n"
        found = False
        for c in classes:
            if not check_inh(c["Name"], mapping, target):
                s += f"{c['Name']} does not inherit from {target}\n"
                found = True
        if not found: s += f"All classes inherit from {target}\n"
        s += "\n"
    return s

if __name__ == "__main__":
    try:
        content = fetch(sys.argv[1] if len(sys.argv) > 1 else None)
        print(content)
        write_dump_file(content, "Dump", os.path.dirname(__file__))
    except Exception as e:
        print(f"Error: {e}")