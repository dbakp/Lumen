#!/usr/bin/env python3
"""Place synthetic fixtures in the chosen simulator's Files provider, never a physical device."""
import argparse
import datetime
import pathlib
import plistlib
import uuid
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('simulator', help='CoreSimulator device UUID')
args = parser.parse_args()
fixture_day = (datetime.datetime.now().astimezone().date() - datetime.timedelta(days=1)).isoformat()
today = datetime.datetime.now().astimezone().date().isoformat()
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
        (folder / 'Lumen-confidence-zero.csv').write_text(f'date,metric,value,unit,source\n{today},steps,0,count,Synthetic zero fixture\n{today},exercise,0,min,Synthetic zero fixture\n{today},water,0,ml,Synthetic zero fixture\n')
        health_xml = '<HealthData><Record type="HKQuantityTypeIdentifierStepCount" value="8421" unit="count" startDate="2026-10-28 10:00:00 +0000" endDate="2026-10-28 10:00:00 +0000" sourceName="Synthetic ZIP Watch"/><Record type="HKQuantityTypeIdentifierDietaryWater" value="250" unit="ml" startDate="2026-10-28 11:00:00 +0000" endDate="2026-10-28 11:00:00 +0000" sourceName="Synthetic ZIP bottle"/></HealthData>'
        with zipfile.ZipFile(folder / 'Lumen-health-export.zip', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('apple_health_export/export.xml', health_xml)
            archive.writestr('apple_health_export/export_cda.xml', 'Excluded clinical record fixture')
            archive.writestr('apple_health_export/workout-routes/test.gpx', 'Excluded route fixture')
        workout = '<Workout workoutActivityType="HKWorkoutActivityTypeRunning" sourceName="Synthetic workout Watch" startDate="2026-10-28 10:00:00 +0000" endDate="2026-10-28 11:00:00 +0000" duration="45" durationUnit="min"/>'
        signals = ''.join(f'<Record type="HKQuantityTypeIdentifier{kind}" value="{value}" unit="{unit}" startDate="2026-10-28 12:00:00 +0000" endDate="2026-10-28 12:00:00 +0000" sourceName="Synthetic vitals Watch"/>' for kind, value, unit in [('OxygenSaturation', '0.98', '%'), ('BodyFatPercentage', '0.23', '%'), ('RespiratoryRate', '15', 'count/min'), ('VO2Max', '44', 'ml/(kg*min)'), ('BodyMassIndex', '22', 'count'), ('HeartRate', '80', 'count/min')])
        with zipfile.ZipFile(folder / 'Lumen-workouts-vitals.zip', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('apple_health_export/export.xml', ('<HealthData>' + workout + signals + '</HealthData>').replace('2026-10-28', fixture_day))
        (folder / 'Lumen-health-invalid.zip').write_bytes(b'Not a ZIP archive')
        print(f'Synthetic fixtures ready (XML {target.stat().st_size:,} bytes; CSV {small.stat().st_size} bytes).')
        break
else:
    raise SystemExit('Files provider is not initialized. Open Files in the simulator and try again.')
