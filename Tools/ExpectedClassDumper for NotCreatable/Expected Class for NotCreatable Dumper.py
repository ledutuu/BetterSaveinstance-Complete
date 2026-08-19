# Dumps all "Class" category properties where the expected class isn't Instance
import requests, os, re

def fetch(vh=None):
    resp, vh = get_api_response(vh)
    s = f"{vh}\n\n"
    for c in resp.json()["Classes"]:
        cname = c["Name"]
        added = False
        for m in c["Members"]:
            if m["MemberType"] == "Property":
                ser = m["Serialization"]
                vt = m["ValueType"]
                if ser["CanLoad"] and ser["CanSave"] and \
                   vt["Category"] == "Class" and vt["Name"] != "Instance":
                    s += f"{cname}.{m['Name']} {{{vt['Name']}}}\n"
                    added = True
        if added: s += "\n"
    return s

if __name__ == "__main__":
    try:
        content = fetch(sys.argv[1] if len(sys.argv) > 1 else None)
        print(content)
        write_dump_file(content, "Dump", os.path.dirname(__file__))
    except Exception as e:
        print(f"Error: {e}")