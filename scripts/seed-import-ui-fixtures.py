#!/usr/bin/env python3
"""Place synthetic fixtures in the chosen simulator's Files provider, never a physical device."""
import argparse
import pathlib
import plistlib
import uuid
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('simulator', help='CoreSimulator device UUID')
args = parser.parse_args()
args.simulator = str(uuid.UUID(args.simulator)).upper()
root = pathlib.Path.home() / 'Library/Developer/CoreSimulator/Devices' / args.simulator / 'data/Containers/Shared/AppGroup'
if not root.is_dir():
    raise SystemExit('Simulator container not found. Boot the simulator first.')
for metadata in root.glob('*/.com.apple.mobile_container_manager.metadata.plist'):
    values = plistlib.loads(metadata.read_bytes())
    if values.get('MCMMetadataIdentifier') == 'group.com.apple.FileProvider.LocalStorage':
        folder = metadata.parent / 'File Provider Storage'
        folder.mkdir(exist_ok=True)
        target = folder / 'Lumen-import-cancellation.xml'
        record = '<Record type="HKQuantityTypeIdentifierStepCount" value="10" unit="count" startDate="2026-01-01 10:00:00 +0000" endDate="2026-01-01 10:01:00 +0000" sourceName="Synthetic test fixture"/>\n'
        with target.open('w') as output:
            output.write('<HealthData>\n')
            for _ in range(200_000):
                output.write(record)
            output.write('</HealthData>')
        small = folder / 'Lumen-import-small.csv'
        small.write_text('date,metric,value,unit,source\n2026-10-28,steps,8421,count,Synthetic test fixture\n2026-10-28,water,250,ml,Synthetic test fixture\n')
        health_xml = '<HealthData><Record type="HKQuantityTypeIdentifierStepCount" value="8421" unit="count" startDate="2026-10-28 10:00:00 +0000" endDate="2026-10-28 10:00:00 +0000" sourceName="Synthetic ZIP Watch"/><Record type="HKQuantityTypeIdentifierDietaryWater" value="250" unit="ml" startDate="2026-10-28 11:00:00 +0000" endDate="2026-10-28 11:00:00 +0000" sourceName="Synthetic ZIP bottle"/></HealthData>'
        with zipfile.ZipFile(folder / 'Lumen-health-export.zip', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('apple_health_export/export.xml', health_xml)
            archive.writestr('apple_health_export/export_cda.xml', 'Excluded clinical record fixture')
            archive.writestr('apple_health_export/workout-routes/test.gpx', 'Excluded route fixture')
        (folder / 'Lumen-health-invalid.zip').write_bytes(b'Not a ZIP archive')
        print(f'Synthetic fixtures ready (XML {target.stat().st_size:,} bytes; CSV {small.stat().st_size} bytes).')
        break
else:
    raise SystemExit('Files provider is not initialized. Open Files in the simulator and try again.')
