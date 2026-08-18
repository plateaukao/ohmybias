#!/usr/bin/env bash
set -euo pipefail

BRANCH="feature/android-ime"
COMMIT_MSG="chore(android): add android IME project + CI"

# Ensure we're in a git repo
if [ ! -d .git ]; then
  echo "請在已 clone 的 repo 根目錄執行此腳本（該目錄應包含 .git）。"
  exit 1
fi

# create and switch branch
git fetch origin
if git show-ref --quiet refs/heads/"$BRANCH"; then
  git checkout "$BRANCH"
else
  git checkout -b "$BRANCH"
fi

# Create directories
mkdir -p android/app/src/main/java/com/myorg/ohmybiasime
mkdir -p android/app/src/main/res/xml
mkdir -p android/app/src/main/res/layout
mkdir -p android/app/src/main/res/values
mkdir -p .github/workflows

# Write files (each file created with here-doc)
cat > android/settings.gradle <<'EOF'
rootProject.name = "ohmybias-android"
include ':app'
EOF

cat > android/build.gradle <<'EOF'
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:7.4.2'
        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:1.8.22"
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
EOF

cat > android/app/build.gradle <<'EOF'
plugins {
    id 'com.android.application'
    id 'kotlin-android'
}

android {
    compileSdk 33

    defaultConfig {
        applicationId "com.myorg.ohmybiasime"
        minSdk 21
        targetSdk 33
        versionCode 1
        versionName "0.1"
    }

    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_11
        targetCompatibility JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = '11'
    }
}

dependencies {
    implementation "org.jetbrains.kotlin:kotlin-stdlib:1.8.22"
}
EOF

cat > android/app/src/main/AndroidManifest.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest package="com.myorg.ohmybiasime"
    xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-sdk android:targetSdkVersion="33" android:minSdkVersion="21" />

    <application
        android:label="@string/app_name"
        android:allowBackup="true"
        android:supportsRtl="true">

        <service
            android:name=".MyInputMethodService"
            android:permission="android.permission.BIND_INPUT_METHOD"
            android:exported="true">
            <intent-filter>
                <action android:name="android.view.InputMethod" />
            </intent-filter>

            <meta-data
                android:name="android.view.im"
                android:resource="@xml/method"/>
        </service>

        <activity android:name=".SettingsActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

cat > android/app/src/main/res/xml/method.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<input-method xmlns:android="http://schemas.android.com/apk/res/android"
    android:settingsActivity="com.myorg.ohmybiasime.SettingsActivity"
    android:label="@string/app_name">
</input-method>
EOF

cat > android/app/src/main/res/xml/qwerty.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<Keyboard xmlns:android="http://schemas.android.com/apk/res/android"
    android:keyWidth="10%p"
    android:keyHeight="50dp"
    android:horizontalGap="0dp"
    android:verticalGap="0dp">

    <!-- Row 1 -->
    <Row>
        <Key android:codes="113" android:keyLabel="q" />
        <Key android:codes="119" android:keyLabel="w" />
        <Key android:codes="101" android:keyLabel="e" />
        <Key android:codes="114" android:keyLabel="r" />
        <Key android:codes="116" android:keyLabel="t" />
        <Key android:codes="121" android:keyLabel="y" />
        <Key android:codes="117" android:keyLabel="u" />
        <Key android:codes="105" android:keyLabel="i" />
        <Key android:codes="111" android:keyLabel="o" />
        <Key android:codes="112" android:keyLabel="p" />
    </Row>

    <!-- Row 2 -->
    <Row>
        <Key android:codes="97" android:keyLabel="a" />
        <Key android:codes="115" android:keyLabel="s" />
        <Key android:codes="100" android:keyLabel="d" />
        <Key android:codes="102" android:keyLabel="f" />
        <Key android:codes="103" android:keyLabel="g" />
        <Key android:codes="104" android:keyLabel="h" />
        <Key android:codes="106" android:keyLabel="j" />
        <Key android:codes="107" android:keyLabel="k" />
        <Key android:codes="108" android:keyLabel="l" />
        <Key android:codes="-5" android:keyLabel="⌫" android:keyWidth="10%p" />
    </Row>

    <!-- Row 3 -->
    <Row>
        <Key android:codes="122" android:keyLabel="z" />
        <Key android:codes="120" android:keyLabel="x" />
        <Key android:codes="99" android:keyLabel="c" />
        <Key android:codes="118" android:keyLabel="v" />
        <Key android:codes="98" android:keyLabel="b" />
        <Key android:codes="110" android:keyLabel="n" />
        <Key android:codes="109" android:keyLabel="m" />
        <Key android:codes="44" android:keyLabel="," />
        <Key android:codes="46" android:keyLabel="." />
        <Key android:codes="32" android:keyLabel="space" android:keyWidth="10%p" />
    </Row>

</Keyboard>
EOF

cat > android/app/src/main/res/layout/input_view.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="wrap_content">

    <KeyboardView
        android:id="@+id/keyboard"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:keyBackground="@android:drawable/btn_default"
        android:keyPreviewLayout="@layout/key_preview"
        android:labelTextSize="18sp"
        android:keyTextSize="18sp" />

</FrameLayout>
EOF

cat > android/app/src/main/res/layout/key_preview.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:orientation="vertical"
    android:layout_width="wrap_content"
    android:layout_height="wrap_content"
    android:padding="6dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="Key Preview"
        android:visibility="gone" />

</LinearLayout>
EOF

cat > android/app/src/main/java/com/myorg/ohmybiasime/SettingsActivity.kt <<'EOF'
package com.myorg.ohmybiasime

import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Bundle
import android.widget.SeekBar
import android.widget.Switch
import androidx.appcompat.app.AppCompatActivity

class SettingsActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_settings)

        val prefs = getSharedPreferences("ohmybias_prefs", MODE_PRIVATE)
        val sw = findViewById<Switch>(R.id.switch_sound)
        val sb = findViewById<SeekBar>(R.id.seek_volume)

        sw.isChecked = prefs.getBoolean("keySoundEnabled", false)
        sb.progress = prefs.getInt("keySoundVolume", 80)

        sw.setOnCheckedChangeListener { _, isChecked ->
            prefs.edit().putBoolean("keySoundEnabled", isChecked).apply()
        }
        sb.setOnSeekBarChangeListener(object: SeekBar.OnSeekBarChangeListener{
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                prefs.edit().putInt("keySoundVolume", progress).apply()
                // brief feedback tone
                val tg = ToneGenerator(AudioManager.STREAM_MUSIC, progress)
                tg.startTone(ToneGenerator.TONE_PROP_ACK, 60)
                tg.release()
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        })
    }
}
EOF

cat > android/app/src/main/res/layout/activity_settings.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:orientation="vertical"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:padding="16dp">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="OhMyBias IME 設定"
        android:textSize="20sp"
        android:paddingBottom="12dp" />

    <LinearLayout
        android:orientation="horizontal"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:paddingTop="8dp">
        <TextView
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="按鍵音效" />
        <Switch
            android:id="@+id/switch_sound"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginStart="16dp" />
    </LinearLayout>

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="音量"
        android:paddingTop="12dp" />
    <SeekBar
        android:id="@+id/seek_volume"
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:max="100" />

</LinearLayout>
EOF

cat > android/app/src/main/java/com/myorg/ohmybiasime/MyInputMethodService.kt <<'EOF'
package com.myorg.ohmybiasime

import android.inputmethodservice.InputMethodService
import android.inputmethodservice.Keyboard
import android.inputmethodservice.KeyboardView
import android.media.AudioManager
import android.media.ToneGenerator
import android.view.View
import android.view.inputmethod.InputConnection

class MyInputMethodService : InputMethodService(), KeyboardView.OnKeyboardActionListener {

    private lateinit var keyboardView: KeyboardView
    private lateinit var keyboard: Keyboard
    private var toneGenerator: ToneGenerator? = null

    override fun onCreate() {
        super.onCreate()
        val prefs = getSharedPreferences("ohmybias_prefs", MODE_PRIVATE)
        val vol = prefs.getInt("keySoundVolume", 80)
        toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, vol)
    }

    override fun onCreateInputView(): View {
        val view = layoutInflater.inflate(R.layout.input_view, null)
        keyboardView = view.findViewById(R.id.keyboard)
        keyboard = Keyboard(this, R.xml.qwerty)
        keyboardView.keyboard = keyboard
        keyboardView.isPreviewEnabled = false
        keyboardView.setOnKeyboardActionListener(this)
        return view
    }

    override fun onKey(primaryCode: Int, keyCodes: IntArray?) {
        val ic: InputConnection? = currentInputConnection
        if (ic == null) return
        when (primaryCode) {
            Keyboard.KEYCODE_DELETE -> ic.deleteSurroundingText(1, 0)
            Keyboard.KEYCODE_DONE -> ic.sendKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, android.view.KeyEvent.KEYCODE_ENTER))
            else -> {
                val code = primaryCode.toChar()
                ic.commitText(code.toString(), 1)
            }
        }

        // play tone if enabled
        val prefs = getSharedPreferences("ohmybias_prefs", MODE_PRIVATE)
        val enabled = prefs.getBoolean("keySoundEnabled", false)
        if (enabled) {
            val vol = prefs.getInt("keySoundVolume", 80)
            toneGenerator?.release()
            toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, vol)
            toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP, 40)
        }
    }

    override fun onPress(primaryCode: Int) {}
    override fun onRelease(primaryCode: Int) {}
    override fun onText(text: CharSequence?) {}
    override fun swipeDown() {}
    override fun swipeLeft() {}
    override fun swipeRight() {}
    override fun swipeUp() {}
}
EOF

cat > android/app/src/main/res/values/strings.xml <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">OhMyBias IME</string>
</resources>
EOF

cat > android/app/proguard-rules.pro <<'EOF'
apply plugin: 'com.android.application'

// placeholder proguard file
EOF

cat > .github/workflows/android-build.yml <<'EOF'
name: Build Android APK
on:
  push:
    branches:
      - feature/android-ime
  workflow_dispatch: {}

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up JDK 11
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '11'
      - name: Build with Gradle
        uses: gradle/gradle-build-action@v2
        with:
          arguments: ':app:assembleRelease'
          gradle-version: '7.5.1'
      - name: Upload APK
        uses: actions/upload-artifact@v3
        with:
          name: ohmybias-android-apk
          path: android/app/build/outputs/**/*.apk
EOF

# Add, commit, push
git add android .github/workflows/android-build.yml
if git commit -m "$COMMIT_MSG"; then
  echo "Committed changes"
else
  echo "No changes to commit"
fi

git push -u origin "$BRANCH"

echo "已 push 到 branch $BRANCH。請到 GitHub Actions 等待 build（artifact 名稱：ohmybias-android-apk）。"
