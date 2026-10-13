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
resources=subprocess.check_output([sys.argv[1],'dump','--values','resources',sys.argv[2]],text=True)
for name in ['network_security_config','data_extraction_rules','backup_rules']:
    # Release resource optimization renames ZIP entries (for example res/aB.xml).
    # Resolve the compiled path by logical resource name, rather than source path.
    entry=re.search(r'\bresource [^\n]*:xml/'+re.escape(name)+r':[^\n]*\n\s*\(string(?:8|16)\) "([^"]+)"',resources)
    assert entry, f'Missing compiled XML resource: {name}'
    xml=subprocess.check_output([sys.argv[1],'dump','xmltree',sys.argv[2],entry.group(1)],text=True)
    if name == 'network_security_config':
        assert 'E: base-config' in xml and re.search(r'cleartextTrafficPermitted.*0x0',xml)
        assert '127.0.0.1' in xml and 'localhost' in xml
        assert len(re.findall(r'E: domain \(',xml)) == 2
    else:
        expected=10 if name == 'data_extraction_rules' else 5
        assert len(re.findall(r'E: exclude \(',xml)) == expected
        for domain in ['root','file','database','sharedpref','external']:
            assert f'"{domain}"' in xml, f'Missing backup exclusion: {domain}'
print('Release APK security configuration checks passed')
PY
