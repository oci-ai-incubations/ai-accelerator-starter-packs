#!/usr/bin/env python3
"""
CDP file upload utility for ORM hidden file inputs.

Usage:
    python3 cdp_upload.py <websocket_url> <file_path>

Arguments:
    websocket_url   The CDP WebSocket debugger URL for the target page
                    (obtained from http://localhost:<port>/json/list)
    file_path       Absolute path to the file to upload

Exit codes:
    0  SUCCESS — file input was found and set
    1  ERROR — no file input found, or an unexpected error occurred

Example:
    python3 cdp_upload.py ws://localhost:9222/devtools/page/ABC /tmp/stack.zip
"""

import json
import sys
import threading
import time
import websocket


def send_command(ws, cmd_id, method, params=None):
    """Send a CDP command and return the command ID (response handled separately)."""
    msg = {"id": cmd_id, "method": method, "params": params or {}}
    ws.send(json.dumps(msg))
    return cmd_id


def wait_for_result(results, cmd_id, timeout=10):
    """Block until a result with the given command ID is available."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if cmd_id in results:
            return results.pop(cmd_id)
        time.sleep(0.05)
    raise TimeoutError(f"No CDP response for command id={cmd_id} within {timeout}s")


def find_file_input(node):
    """
    Recursively search a CDP DOM node tree for an input[type="file"].

    CDP returns nodes with a 'children' list. Shadow roots and iframe
    contentDocuments are included when pierce=True is used in getDocument.
    Returns the nodeId of the first matching input, or None.
    """
    if node.get("nodeName", "").upper() == "INPUT":
        attrs = node.get("attributes", [])
        # attributes is a flat list: [name, value, name, value, ...]
        attr_dict = {}
        for i in range(0, len(attrs) - 1, 2):
            attr_dict[attrs[i].lower()] = attrs[i + 1]
        if attr_dict.get("type", "").lower() == "file":
            return node["nodeId"]

    # Recurse into children
    for child in node.get("children", []):
        result = find_file_input(child)
        if result is not None:
            return result

    # Recurse into content document (iframes)
    content_doc = node.get("contentDocument")
    if content_doc:
        result = find_file_input(content_doc)
        if result is not None:
            return result

    return None


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <websocket_url> <file_path>", file=sys.stderr)
        sys.exit(1)

    ws_url = sys.argv[1]
    file_path = sys.argv[2]

    # Shared state between the WebSocket thread and main thread
    results = {}
    lock = threading.Lock()

    def on_message(ws_conn, message):
        data = json.loads(message)
        if "id" in data:
            with lock:
                results[data["id"]] = data

    def on_error(ws_conn, error):
        print(f"WebSocket error: {error}", file=sys.stderr)

    # suppress_origin=True omits the Origin header, bypassing CDP's origin check
    print("Connecting to CDP...")
    ws_conn = websocket.WebSocketApp(
        ws_url,
        on_message=on_message,
        on_error=on_error,
    )

    # Run WebSocket in a background thread
    ws_thread = threading.Thread(
        target=lambda: ws_conn.run_forever(suppress_origin=True),
        daemon=True,
    )
    ws_thread.start()

    # Give the connection a moment to establish
    time.sleep(0.5)

    cmd_id = 1

    # Step 1: Enable the DOM domain
    print("Enabling DOM...")
    send_command(ws_conn, cmd_id, "DOM.enable")
    wait_for_result(results, cmd_id)
    cmd_id += 1

    # Step 2: Get the full document with pierce=True to include iframes
    print("Getting document...")
    send_command(ws_conn, cmd_id, "DOM.getDocument", {"depth": -1, "pierce": True})
    response = wait_for_result(results, cmd_id)
    cmd_id += 1

    if "error" in response:
        print(f"ERROR: DOM.getDocument failed: {response['error']}", file=sys.stderr)
        ws_conn.close()
        sys.exit(1)

    root_node = response["result"]["root"]

    # Step 3: Recursively find the file input node
    print("Searching for file input (pierce=True)...")
    node_id = find_file_input(root_node)

    if node_id is None:
        print("ERROR: No input[type=\"file\"] found in the page DOM (including iframes)", file=sys.stderr)
        ws_conn.close()
        sys.exit(1)

    print(f"Found file input node: {node_id}")

    # Step 4: Set the file on the input element via CDP
    print("Setting file input files...")
    send_command(
        ws_conn,
        cmd_id,
        "DOM.setFileInputFiles",
        {"nodeId": node_id, "files": [file_path]},
    )
    response = wait_for_result(results, cmd_id)
    cmd_id += 1

    if "error" in response:
        print(f"ERROR: DOM.setFileInputFiles failed: {response['error']}", file=sys.stderr)
        ws_conn.close()
        sys.exit(1)

    print(f"SUCCESS: file input set to {file_path}")
    ws_conn.close()
    sys.exit(0)


if __name__ == "__main__":
    main()
