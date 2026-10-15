#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request


def get_token():
    p = subprocess.Popen(['git', 'credential', 'fill'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    out, _ = p.communicate('protocol=https\nhost=github.com\n\n')
    token = ''
    for line in out.splitlines():
        if line.startswith('password='):
            token = line.split('=', 1)[1]
    return token


def api_request(url, token, data=None, method='GET', content_type='application/json'):
    headers = {
        'Authorization': f'token {token}',
        'User-Agent': 'Python',
    }
    if content_type:
        headers['Content-Type'] = content_type
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    return urllib.request.urlopen(req)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tag', default='v2.1', help='Release tag')
    ap.add_argument('--repo', default='bmjubairdadu/MultiRoot-Flashable-ZIP', help='GitHub repository')
    args = ap.parse_args()

    token = get_token()
    if not token:
        print("ERROR: Could not retrieve GitHub token")
        sys.exit(1)

    tag = args.tag
    repo = args.repo

    # Update checksums in RELEASE_NOTES.md if SHA256SUMS.txt exists
    sums_file = 'dist/SHA256SUMS.txt'
    notes_file = 'dist/RELEASE_NOTES.md'
    if os.path.exists(sums_file) and os.path.exists(notes_file):
        with open(sums_file, 'r', encoding='utf-8') as f:
            sums_content = f.read().strip()
        with open(notes_file, 'r', encoding='utf-8') as f:
            notes = f.read()
        if '### 📦 Checksums (SHA-256)' in notes:
            notes = re.sub(
                r'### 📦 Checksums \(SHA-256\)\s*```text[\s\S]*?```',
                f'### 📦 Checksums (SHA-256)\n```text\n{sums_content}\n```',
                notes
            )
            with open(notes_file, 'w', encoding='utf-8') as f:
                f.write(notes)
    else:
        with open(notes_file, 'r', encoding='utf-8') as f:
            notes = f.read()

    # Check if release already exists
    rel = None
    try:
        resp = api_request(f'https://api.github.com/repos/{repo}/releases/tags/{tag}', token)
        rel = json.loads(resp.read().decode('utf-8'))
        print(f"Found existing release {tag} (ID: {rel['id']})")
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise

    payload = {
        'tag_name': tag,
        'target_commitish': 'main',
        'name': f'MultiRoot {tag}: Universal Root for Android (KernelPatch + Magisk)',
        'body': notes,
        'draft': False,
        'prerelease': False
    }

    if rel:
        print(f"Updating existing release {tag} metadata...")
        rel_id = rel['id']
        resp = api_request(
            f'https://api.github.com/repos/{repo}/releases/{rel_id}',
            token,
            data=json.dumps(payload).encode('utf-8'),
            method='PATCH'
        )
        rel = json.loads(resp.read().decode('utf-8'))
    else:
        print(f"Creating release {tag} on GitHub...")
        resp = api_request(
            f'https://api.github.com/repos/{repo}/releases',
            token,
            data=json.dumps(payload).encode('utf-8'),
            method='POST'
        )
        rel = json.loads(resp.read().decode('utf-8'))

    upload_url_base = rel['upload_url'].split('{')[0]

    files = [
        (f'dist/MultiRoot-{tag}-Recovery-Installer.zip', 'application/zip'),
        (f'dist/MultiRoot-{tag}-Uninstaller.zip', 'application/zip'),
        ('dist/SHA256SUMS.txt', 'text/plain')
    ]

    # Delete existing conflicting assets if they exist
    existing_assets = {a['name']: a['id'] for a in rel.get('assets', [])}
    for file_path, content_type in files:
        name = os.path.basename(file_path)
        if name in existing_assets:
            asset_id = existing_assets[name]
            print(f"Deleting older asset {name} (ID: {asset_id})...")
            del_req = urllib.request.Request(
                f'https://api.github.com/repos/{repo}/releases/assets/{asset_id}',
                headers={'Authorization': f'token {token}', 'User-Agent': 'Python'},
                method='DELETE'
            )
            urllib.request.urlopen(del_req)

    # Upload fresh assets
    for file_path, content_type in files:
        name = os.path.basename(file_path)
        if not os.path.exists(file_path):
            print(f"WARNING: File {file_path} not found, skipping.")
            continue
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

    print(f"\nSUCCESS: Release {tag} updated & published with all final assets!")
    print("Release URL:", rel['html_url'])


if __name__ == '__main__':
    main()
