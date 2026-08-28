#!/usr/bin/env python3
"""为 flutter_local_notifications 启用 desugaring（不修改 AGP/Gradle 版本）"""
import re, sys

APP = 'android/app/build.gradle.kts'

try:
    with open(APP) as f:
        s = f.read()
except FileNotFoundError:
    print('[desugar] ERROR: build.gradle.kts not found')
    sys.exit(1)

changes = []

# 1) 在现有 compileOptions 里加 isCoreLibraryDesugaringEnabled
if 'isCoreLibraryDesugaringEnabled' not in s:
    if 'compileOptions {' in s:
        s = s.replace(
            'compileOptions {',
            'compileOptions {\n'
            '        isCoreLibraryDesugaringEnabled = true',
            1,
        )
        changes.append('desugaring flag in compileOptions')
    else:
        print('[desugar] ERROR: compileOptions block not found')
        sys.exit(1)

# 2) 追加 dependencies 块（模板里没有 dependencies，追加到末尾）
if 'coreLibraryDesugaring' not in s:
    s += '\ndependencies {\n'
    s += '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n'
    s += '}\n'
    changes.append('coreLibraryDesugaring dependency')

with open(APP, 'w') as f:
    f.write(s)

print(f'[desugar] {" | ".join(changes) if changes else "already enabled"}')