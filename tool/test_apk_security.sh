#!/usr/bin/env bash
set -euo pipefail
apk='build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'
aapt_bin="${ANDROID_HOME}/build-tools/36.0.0/aapt"
python3 - "$aapt_bin" "$apk" <<'PY'
import re,subprocess,sys
permissions=subprocess.check_output([sys.argv[1],'dump','permissions',sys.argv[2]],text=True)
for forbidden in ['READ_MEDIA_IMAGES','READ_MEDIA_VIDEO','RECORD_AUDIO','READ_CONTACTS','ACCESS_FINE_LOCATION','CAMERA']:
    assert 'android.permission.'+forbidden+"'" not in permissions, forbidden
manifest=subprocess.check_output([sys.argv[1],'dump','xmltree',sys.argv[2],'AndroidManifest.xml'],text=True)
assert re.search(r'android:allowBackup.*0x0',manifest), 'Backup enabled'
assert 'android:dataExtractionRules' in manifest
assert 'android:networkSecurityConfig' in manifest
for name in ['network_security_config','data_extraction_rules','backup_rules']:
    subprocess.check_output([sys.argv[1],'dump','xmltree',sys.argv[2],f'res/xml/{name}.xml'],text=True)
print('Release APK security configuration checks passed')
PY
