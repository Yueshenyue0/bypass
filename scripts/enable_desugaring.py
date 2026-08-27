#!/usr/bin/env python3
# 为 flutter_local_notifications 启用 core library desugaring
# 用法：python3 scripts/enable_desugaring.py
import sys

p = 'android/app/build.gradle.kts'
try:
    s = open(p).read()
except FileNotFoundError:
    print('[desugar] ERROR: build.gradle.kts not found')
    sys.exit(1)

changed = False

# 1) compileOptions (desugaring) 插入到 android { 之后
if 'isCoreLibraryDesugaringEnabled' not in s:
    s = s.replace(
        'android {',
        'android {\n'
        '    compileOptions {\n'
        '        isCoreLibraryDesugaringEnabled = true\n'
        '        sourceCompatibility = JavaVersion.VERSION_11\n'
        '        targetCompatibility = JavaVersion.VERSION_11\n'
        '    }',
        1,
    )
    changed = True

# 2) coreLibraryDesugaring 依赖插入到 dependencies { 之后
if 'coreLibraryDesugaring' not in s:
    s = s.replace(
        'dependencies {',
        'dependencies {\n'
        '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")',
        1,
    )
    changed = True

open(p, 'w').write(s)
print('[desugar] enabled' if changed else '[desugar] already enabled')
