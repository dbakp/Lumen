"""Bind en_DK native labels to actual SDK dates/sources, at displayed minute precision."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
from zoneinfo import ZoneInfo

parser = argparse.ArgumentParser()
parser.add_argument('--prefix', required=True)
args = parser.parse_args()
base = Path(__file__).resolve().parent
prefix = args.prefix
assert re.fullmatch(r'health-daily-details-compact-largest-r[1-9][0-9]*', prefix)
readbacks = json.loads((base / (prefix + '-readbacks.json')).read_text())
assert len(readbacks) == 1
native_path = base / readbacks[0]['file']
native = json.loads(native_path.read_text())
sdk_path = base / (prefix + '-sdk-query.json')
sdk = json.loads(sdk_path.read_text())
labels = {'steps': 'Steps', 'activeEnergy': 'Active energy', 'restingEnergy': 'Resting energy',
          'exercise': 'Exercise', 'stand': 'Stand or roll hours', 'restingHR': 'Resting heart rate',
          'hrv': 'Heart rate variability', 'heartRate': 'Heart rate', 'respiratoryRate': 'Breathing rate',
          'spo2': 'Oxygen saturation', 'vo2max': 'VO₂ max', 'weight': 'Weight', 'bodyFat': 'Body fat',
          'calories': 'Food energy', 'protein': 'Protein', 'carbs': 'Carbohydrates', 'fat': 'Fat', 'water': 'Water'}
assert set(native['fullDetails']) == set(labels) == set(sdk['metrics']['readings'])
months = {name: index + 1 for index, name in enumerate(
    ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'])}
pattern = re.compile(r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+at\s+(\d{1,2})[.:](\d{2})')
zone = ZoneInfo('Europe/Copenhagen')

def sdk_minute(value):
    date = datetime.fromisoformat(value.replace('Z', '+00:00')).astimezone(zone)
    return [date.year, date.month, date.day, date.hour, date.minute]

def native_minutes(value):
    return [[int(year), months[month], int(day), int(hour), int(minute)]
            for day, month, year, hour, minute in pattern.findall(value)]

verified = {}
for key, expected_heading in labels.items():
    detail = native['fullDetails'][key]
    reading = sdk['metrics']['readings'][key]
    query = reading['healthQuery']
    assert detail['Heading'] == expected_heading, (key, detail['Heading'])
    dates = {}
    for field, sdk_field, caption in [('Checked', 'checkedAt', 'Checked'),
                                     ('Start', 'start', 'Query from'), ('End', 'end', 'Query through')]:
        assert detail[field].startswith(caption), (key, field, detail[field])
        expected = [sdk_minute(query[sdk_field])]
        assert native_minutes(detail[field]) == expected, (key, field, detail[field], expected)
        dates[field] = expected[0]
    components = reading['components']
    if components:
        assert len(components) == 1
        component = components[0]
        expected_source = ' + '.join(sorted({c['source'] for c in components}))
        assert detail['Source'] == expected_source, (key, detail['Source'], expected_source)
        period = detail['Period']
        if component['aggregation'] == 'latest':
            expected_dates = [component.get('lastSampleAt') or component.get('end') or component['start']]
            assert period.startswith('Recorded ')
        else:
            kind = {'average': 'Average', 'total': 'Total'}[component['aggregation']]
            assert period.startswith(kind + ' from ')
            expected_dates = [component['start']]
            if component.get('end'):
                expected_dates.append(component['end'])
                assert ' through ' in period
            assert ('Latest sample time is unavailable.' in period) == (component.get('lastSampleAt') is None)
        assert native_minutes(period) == [sdk_minute(value) for value in expected_dates], (key, period)
        dates['Period'] = native_minutes(period)
    verified[key] = dates
result = dict(status='passed', nativeReadback=native_path.name,
              nativeSHA256=hashlib.sha256(native_path.read_bytes()).hexdigest(),
              actualSDKQuery=sdk_path.name, sdkSHA256=hashlib.sha256(sdk_path.read_bytes()).hexdigest(),
              nativeLocale='en_DK', timezone='Europe/Copenhagen', displayedPrecision='minute',
              headingsVerified=18, queryDateFieldsVerified=54, sourceAndPeriodPairsVerified=3,
              verified=verified,
              scope='Independent native-label binding to actual SDK dates/source/aggregation. Full image review and whole-flow acceptance remain separate.')
(base / (prefix + '-metadata-audit.json')).write_text(json.dumps(result, indent=2) + '\n')
print('PASS18headings/54query-date labels/3source-period pairs bound to actual SDK output.')
