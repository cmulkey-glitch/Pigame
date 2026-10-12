"""Zip the sideloadable app: dist/roku-dashboard.zip with manifest at the archive root.

    python3 roku-dashboard/tools/package.py

Upload it at http://<roku-ip> (Development Application Installer). Roku's limit is 4 MB.
"""
import os
import zipfile

app = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
out = os.path.join(app, '..', 'dist', 'roku-dashboard.zip')
os.makedirs(os.path.dirname(out), exist_ok=True)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.write(os.path.join(app, 'manifest'), 'manifest')
    for top in ('source', 'components', 'images', 'data'):
        for dirpath, _, files in os.walk(os.path.join(app, top)):
            for name in sorted(files):
                path = os.path.join(dirpath, name)
                z.write(path, os.path.relpath(path, app))
size = os.path.getsize(out)
print(f'{os.path.normpath(out)}: {size / 1024:.0f} KB ({size / (4 * 1024 * 1024):.0%} of the 4 MB limit)')
