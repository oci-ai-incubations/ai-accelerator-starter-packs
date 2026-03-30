#!/usr/bin/env python3
"""Undeploy all Ingress-type blueprint deployments via the Corrino API.

Usage: python3 undeploy_blueprints.py <api_url> <username> <password>

This script is called by the Terraform destroy-time provisioner to cleanly
undeploy blueprint workloads before the Corrino control plane is torn down.
"""

import json
import ssl
import sys
import time
import urllib.request
from urllib.error import HTTPError
from urllib.parse import urlencode


def main():
    if len(sys.argv) != 4:
        print("Usage: python3 undeploy_blueprints.py <api_url> <username> <password>")
        sys.exit(1)

    api_url = sys.argv[1].rstrip("/")
    username = sys.argv[2]
    password = sys.argv[3]

    # Disable SSL verification for self-signed certs in test environments
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    # Step 1: Login to the Corrino API
    try:
        login_data = urlencode({"username": username, "password": password}).encode()
        login_req = urllib.request.Request(
            api_url + "/login/",
            data=login_data,
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            method="POST",
        )
        login_resp = urllib.request.urlopen(login_req, context=ctx)
        token = json.load(login_resp).get("token") if login_resp else None
    except Exception as e:
        print("API not reachable, skipping undeploy:", e)
        sys.exit(0)

    if not token:
        print("No token, skipping undeploy.")
        sys.exit(0)

    # Step 2: Fetch workspace recipes
    try:
        ws_req = urllib.request.Request(
            api_url + "/workspace/",
            headers={"Authorization": "Token %s" % token},
            method="GET",
        )
        ws = json.load(urllib.request.urlopen(ws_req, context=ctx))
        recipes = ws.get("recipes") or {}
    except Exception as e:
        print("No workspace, skipping undeploy:", e)
        sys.exit(0)

    # Step 3: Filter for Ingress-type recipes with a deployment-uuid
    uuids = [
        r.get("deployment-uuid", "")
        for r in recipes.values()
        if r.get("type") == "Ingress" and r.get("deployment-uuid")
    ]

    # Step 4: Undeploy each deployment
    for uuid in uuids:
        try:
            undeploy_req = urllib.request.Request(
                api_url + "/undeploy/",
                data=json.dumps({"deployment_uuid": uuid}).encode(),
                headers={
                    "Authorization": "Token %s" % token,
                    "Content-Type": "application/json",
                },
                method="POST",
            )
            urllib.request.urlopen(undeploy_req, context=ctx)
            print("Undeploy %s succeeded" % uuid)
        except HTTPError as e:
            if e.code == 404:
                print("Deployment %s not found (already undeployed)" % uuid)
            else:
                print("Undeploy %s failed: %s" % (uuid, e))
                sys.exit(1)
        except Exception as e:
            print("Undeploy %s failed: %s" % (uuid, e))
            sys.exit(1)

    # Step 5: Poll workspace until recipes clear
    if uuids:
        print("Waiting for workspace recipes to clear...")
        for attempt in range(60):
            try:
                ws_req = urllib.request.Request(
                    api_url + "/workspace/",
                    headers={"Authorization": "Token %s" % token},
                    method="GET",
                )
                ws = json.load(urllib.request.urlopen(ws_req, context=ctx))
                recipes = ws.get("recipes") or {}
                if not recipes:
                    print("Workspace recipes cleared after %ds." % (attempt * 10))
                    break
                print(
                    "  Attempt %d: %d recipe(s) remaining, waiting 10s..."
                    % (attempt + 1, len(recipes))
                )
            except Exception as e:
                print("  Poll failed:", e)
            time.sleep(10)
        else:
            print("Timeout waiting for workspace to clear.")
            sys.exit(1)

    print("Undeploy complete.")


if __name__ == "__main__":
    main()
