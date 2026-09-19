#!/bin/bash
# Ships with the package so the checks are repeatable: bash tools/audit_v10_defects.sh
# v1.0 defect sweep. Every count must be 0.
fail=0
chk() { n=$(eval "$2" 2>/dev/null | wc -l); printf "%-52s %s\n" "$1" "$([ "$n" -eq 0 ] && echo 'CLEAR' || echo "STILL PRESENT ($n)")"; [ "$n" -eq 0 ] || fail=1; }

chk "hard-coded plain-HTTP endpoint" "grep -rn '15\.184\.243\.127' lib/ --include=*.dart | grep -v app_config"
chk "unauthenticated request headers" "grep -rn \"headers: {'Content-Type': 'application/json'}\" lib/ | grep -v auth_headers_v11"
chk "unencrypted Hive box open" "grep -rn \"Hive.openBox('offline\" lib/ | grep -v secure_cache"
chk "dimensionless gyro threshold (= 20)" "grep -rn 'Threshold = 20' lib/services/gyroGame_services.dart"
chk "Delta-t via truncating inMilliseconds" "grep -rn 'inMilliseconds / 1000\|inMilliseconds / 1e3' lib/services/*.dart"
chk "tap rate integer division" "grep -rn '1 ~/ calculateTapDuration' lib/ | grep -v '^[^:]*:[0-9]*: *//'"
chk "tap drift axis typo" "grep -rn 'intededTapLocation.dx - actualTapLocation.dy' lib/"
chk "keystroke rate via Duration.inSeconds" "grep -rn 'totalDuration.inSeconds' lib/"
chk "empty updateCollecting stub" "grep -rn 'lets leave this for now' lib/"
chk "velocity assigned to endX/endY" "grep -rn \"'endX': details.velocity\" lib/ | grep -v '^[^:]*:[0-9]*: *///*'"
chk "magnitude series read as axes" "grep -rn 'ax = _accelerationData\[0\]' lib/"
chk "20-step data cap" "grep -rn '_maxDataEntries = 20;' lib/"
chk "Email column in export" "grep -rn \"'Email':\" bahri_admin/ | grep -v '#'"
chk "hard-coded credential path" "grep -rn 'E:/PhD Cyber' bahri_admin/lib/"
chk "SVG without viewBox" "grep -rn \"version=.1.1.>'\" lib/services/handwriting_services.dart"
echo
[ $fail -eq 0 ] && echo "ALL v1.0 DEFECTS CLOSED" || echo "SOME DEFECTS REMAIN"
exit $fail
