"""Build a debug Swift worker for installed ARM64 iOS simulators."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = Path(sys.argv[1]).resolve()
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
subprocess.run(['swift', 'build', '--target', 'SwiftStoreSyncHTTPTransport', '--triple',
                'arm64-apple-ios16.0-simulator', '--sdk', sdk], cwd=ROOT, check=True)
build = ROOT / '.build/arm64-apple-ios-simulator/debug'
modules = ['SwiftStoreProtocols', 'SwiftStoreMacros', 'SwiftStoreCore',
           'SwiftStoreChangeTracker', 'SwiftStoreSync', 'SwiftStoreSyncHTTPTransport']
objects = []
for module in modules:
    # SwiftPM leaves old objects behind when sources are deleted. Link only this build's outputs.
    output_map = json.loads((build / (module + '.build') / 'output-file-map.json').read_text())
    objects.extend(Path(output['object']) for output in output_map.values() if 'object' in output)
objects += list((build / 'SwiftStoreSQLiteSupport.build').glob('*.c.o'))
subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-target', 'arm64-apple-ios16.0-simulator',
                '-sdk', sdk, '-I', str(build / 'Modules'), '-Xcc',
                '-fmodule-map-file=' + str(build / 'SwiftStoreSQLiteSupport.build/module.modulemap'),
                '-Xcc', '-I' + str(ROOT / 'SwiftStoreSQLiteSupport/include'),
                '-load-plugin-executable', str(ROOT / '.build/arm64-apple-macosx/debug/SwiftStoreMacrosImpl-tool') + '#SwiftStoreMacrosImpl',
                str(Path(__file__).with_name('Worker.swift')), str(Path(__file__).with_name('Migrations.swift')), *map(str, objects), '-lsqlite3', '-o', str(OUTPUT)], check=True)
subprocess.run(['codesign', '-s', '-', str(OUTPUT)], check=True)
