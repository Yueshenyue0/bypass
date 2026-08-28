#!/usr/bin/env python3
"""一键配置 Android 项目所需的 AGP / Gradle / compileSdk / desugaring"""
import re, sys

APP = 'android/app/build.gradle.kts'
ROOT = 'android/build.gradle.kts'
WRAPPER = 'android/gradle/wrapper/gradle-wrapper.properties'

# 1) app/build.gradle.kts: compileSdk=35 + compileOptions + coreLibraryDesugaring
with open(APP) as f:
    app = f.read()

changes = []

# compileSdk → 35
m = re.search(r'compileSdk\s*=\s*(\d+)', app)
if m and int(m.group(1)) < 35:
    app = app.replace(m.group(0), 'compileSdk = 35')
    changes.append('compileSdk → 35')

# compileOptions（desugaring）
if 'isCoreLibraryDesugaringEnabled' not in app:
    app = app.replace(
        'android {',
        'android {\n'
        '    compileOptions {\n'
        '        isCoreLibraryDesugaringEnabled = true\n'
        '        sourceCompatibility = JavaVersion.VERSION_11\n'
        '        targetCompatibility = JavaVersion.VERSION_11\n'
        '    }',
        1,
    )
    changes.append('compileOptions (desugaring)')

# coreLibraryDesugaring 依赖
# 找到第一个 dependencies 块
dep_match = re.search(r'^dependencies\s*\{', app, re.MULTILINE)
if dep_match and 'coreLibraryDesugaring' not in app:
    pos = dep_match.end()
    # 在 { 后面加一行
    app = app[:pos] + '\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")' + app[pos:]
    changes.append('coreLibraryDesugaring dependency')

with open(APP, 'w') as f:
    f.write(app)

# 2) root build.gradle.kts: AGP 8.11.1+
with open(ROOT) as f:
    root = f.read()

# 找 AGP 版本（com.android.application 或 com.android.tools.build:gradle）
agp_versions = re.findall(r'com\.android\.tools\.build:gradle[:\s]+([\d.]+)', root)
agp_versions += re.findall(r'com\.android\.application".*?version\s*=\s*"([\d.]+)"', root)
if agp_versions:
    latest = max(agp_versions, key=lambda v: tuple(int(x) for x in v.split('.')))
    if latest < '8.11.1':
        root = root.replace(latest, '8.11.1')
        changes.append(f'AGP {latest} → 8.11.1')
else:
    # 尝试 plugin block 写法，例如 id("com.android.application") version "8.7.3"
    # 或 id 'com.android.application' version '8.7.3'
    m2 = re.search(r'id\s*\(\s*["\']com\.android\.application["\']\s*\)\s*version\s*["\']([\d.]+)["\']', root)
    if not m2:
        m2 = re.search(r"id\s+['\"]com\.android\.application['\"]\s+version\s+['\"]([\d.]+)['\"]", root)
    if m2:
        cur = m2.group(1)
        if tuple(int(x) for x in cur.split('.')) < (8, 11, 1):
            root = root.replace(cur, '8.11.1')
            changes.append(f'AGP {cur} → 8.11.1')

with open(ROOT, 'w') as f:
    f.write(root)

# 3) Gradle wrapper → 8.13（AGP 8.11.1 要求 Gradle 8.13+）
try:
    with open(WRAPPER) as f:
        wr = f.read()
    if 'gradle-8.13' not in wr and 'gradle-9' not in wr:
        wr = re.sub(
            r'distributionUrl=.*gradle-(\d+\.\d+)(?:\.\d+)?(?:-all|-bin)\.zip',
            r'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-all.zip',
            wr,
        )
        with open(WRAPPER, 'w') as f:
            f.write(wr)
        changes.append('Gradle wrapper → 8.13')
except FileNotFoundError:
    pass

print(f'[android-prep] {" | ".join(changes) if changes else "already configured"}')