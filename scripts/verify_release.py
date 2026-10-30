#!/usr/bin/env python3
"""Match a GitHub release response to every file in this verified build."""
import argparse
import hashlib
import json
from pathlib import Path
import re

if not __debug__:
    raise RuntimeError('Release validation requires Python without -O')


def verify_release(directory, release, commit, tag, draft):
    root = Path(directory)
    files = {p.name: p for p in root.iterdir()}
    assert files and all(p.is_file() and not p.is_symlink() for p in files.values()), 'unexpected local asset type'
    assert re.fullmatch(r'[0-9a-f]{40}', commit), 'invalid source commit'
    assert (root / 'SOURCE_COMMIT').read_text().strip() == commit, 'source commit mismatch'
    assert 'v' + (root / 'VERSION').read_text().strip() == tag, 'version/tag mismatch'
    digests = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in files.items()}
    manifest = {}
    for line in (root / 'SHA256SUMS').read_text().splitlines():
        match = re.fullmatch(r'([0-9a-f]{64})  \./([^/\\]+)', line)
        assert match, 'noncanonical attachment manifest'
        digest, name = match.groups()
        assert name not in manifest, 'duplicate attachment manifest entry'
        manifest[name] = digest
    assert set(manifest) == set(files) - {'SHA256SUMS'}, 'attachment manifest coverage mismatch'
    assert all(digests[name] == digest for name, digest in manifest.items()), 'local attachment hash mismatch'
    assert release['tag_name'] == tag and release['target_commitish'] == commit, 'release source mismatch'
    assert release['draft'] is draft and release['prerelease'] is True, 'unexpected release visibility/type'
    assets = release['assets']
    names = [asset['name'] for asset in assets]
    assert len(names) == len(set(names)) and set(names) == set(files), 'release attachment set mismatch'
    for asset in assets:
        name = asset['name']
        assert asset['state'] == 'uploaded', 'incomplete release attachment'
        assert asset['size'] == files[name].stat().st_size, 'release attachment size mismatch'
        assert asset['digest'] == 'sha256:' + digests[name], 'release attachment digest mismatch'
    print(f'PASS: {len(files)} {"draft" if draft else "public"} release assets match commit {commit}, including full manifest coverage')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory')
    parser.add_argument('metadata', type=Path)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--tag', required=True)
    visibility = parser.add_mutually_exclusive_group(required=True)
    visibility.add_argument('--draft', action='store_true')
    visibility.add_argument('--public', action='store_true')
    args = parser.parse_args()
    verify_release(args.directory, json.loads(args.metadata.read_text()), args.commit, args.tag, args.draft)
