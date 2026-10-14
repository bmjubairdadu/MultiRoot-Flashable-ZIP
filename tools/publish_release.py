#!/usr/bin/env python3
import subprocess
import urllib.request
import json
import os
import sys

def main():
    p = subprocess.Popen(['git', 'credential', 'fill'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    out, _ = p.communicate('protocol=https\nhost=github.com\n\n')
    token = ''
    for line in out.splitlines():
        if line.startswith('password='):
            token = line.split('=', 1)[1]
    
    if not token:
        print("ERROR: Could not retrieve GitHub token")
        sys.exit(1)

    with open('dist/RELEASE_NOTES.md', 'r', encoding='utf-8') as f:
        notes = f.read()

    payload = {
        'tag_name': 'v2.1',
        'target_commitish': 'main',
        'name': 'MultiRoot v2.1: Universal Root for Android (KernelPatch + Magisk)',
        'body': notes,
        'draft': False,
        'prerelease': False
    }

    print("Creating release v2.1 on GitHub...")
    req = urllib.request.Request(
        'https://api.github.com/repos/bmjubairdadu/MultiRoot-Flashable-ZIP/releases',
        data=json.dumps(payload).encode('utf-8'),
        headers={
            'Authorization': f'token {token}',
            'User-Agent': 'Python',
            'Content-Type': 'application/json'
        },
        method='POST'
    )

    with urllib.request.urlopen(req) as resp:
        rel = json.loads(resp.read().decode('utf-8'))
        print('Created release:', rel['id'], rel['html_url'])
        upload_url_base = rel['upload_url'].split('{')[0]

    files = [
        ('dist/MultiRoot-v2.1-Recovery-Installer.zip', 'application/zip'),
        ('dist/MultiRoot-v2.1-Uninstaller.zip', 'application/zip'),
        ('dist/SHA256SUMS.txt', 'text/plain')
    ]

    for file_path, content_type in files:
        name = os.path.basename(file_path)
        size = os.path.getsize(file_path)
        print(f"Uploading {name} ({size} bytes)...")
        with open(file_path, 'rb') as f:
            file_data = f.read()
        
        upload_url = f"{upload_url_base}?name={name}"
        up_req = urllib.request.Request(
            upload_url,
            data=file_data,
            headers={
                'Authorization': f'token {token}',
                'User-Agent': 'Python',
                'Content-Type': content_type,
                'Content-Length': str(size)
            },
            method='POST'
        )
        with urllib.request.urlopen(up_req) as up_resp:
            asset = json.loads(up_resp.read().decode('utf-8'))
            print(f"Uploaded {name} successfully! (Asset ID: {asset['id']})")

    print("\nSUCCESS: Release v2.1 published with all assets!")
    print("Release URL:", rel['html_url'])

if __name__ == '__main__':
    main()
