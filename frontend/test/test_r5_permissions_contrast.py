import os
import re
import unittest

WORKSPACE_ROOT = r"C:\Users\tejas\projects\safesphere"
WORKSPACE = os.path.join(WORKSPACE_ROOT, "frontend") if os.path.exists(os.path.join(WORKSPACE_ROOT, "frontend", "pubspec.yaml")) else WORKSPACE_ROOT

class TestR5ThemingAndPermissions(unittest.TestCase):
    def test_pubspec_identity(self):
        with open(os.path.join(WORKSPACE, "pubspec.yaml"), "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("name: safesphere", content, "pubspec.yaml must define package name 'safesphere'")

    def test_android_manifest(self):
        with open(os.path.join(WORKSPACE, "android", "app", "src", "main", "AndroidManifest.xml"), "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn('android:label="SafeSphere"', content, "AndroidManifest must define label 'SafeSphere'")
        self.assertIn('android.permission.INTERNET', content, "Must declare INTERNET permission")
        self.assertIn('android.permission.ACCESS_FINE_LOCATION', content, "Must declare ACCESS_FINE_LOCATION permission")
        self.assertIn('android.permission.ACCESS_COARSE_LOCATION', content, "Must declare ACCESS_COARSE_LOCATION permission")
        self.assertIn('android.permission.CALL_PHONE', content, "Must declare CALL_PHONE permission")
        self.assertIn('android:scheme="tel"', content, "Must declare tel scheme in <queries>")

    def test_ios_plist(self):
        with open(os.path.join(WORKSPACE, "ios", "Runner", "Info.plist"), "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("<string>SafeSphere</string>", content, "Info.plist must declare SafeSphere display name")
        self.assertIn("NSLocationWhenInUseUsageDescription", content, "Must declare NSLocationWhenInUseUsageDescription")
        self.assertIn("NSLocationAlwaysAndWhenInUseUsageDescription", content, "Must declare NSLocationAlwaysAndWhenInUseUsageDescription")
        self.assertIn("<string>tel</string>", content, "Must declare tel in LSApplicationQueriesSchemes")

    def test_about_page_branding_and_contrast(self):
        with open(os.path.join(WORKSPACE, "lib", "pages", "about_page.dart"), "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn('"SafeSphere"', content, "AboutPage must display SafeSphere")
        self.assertNotIn('"Safety App"', content, "AboutPage must not use generic 'Safety App'")
        self.assertNotIn("Colors.black54", content, "AboutPage must not use low-contrast Colors.black54 in dark mode")
        self.assertNotIn("Colors.black45", content, "AboutPage must not use low-contrast Colors.black45 in dark mode")
        self.assertNotIn("Colors.black38", content, "AboutPage must not use low-contrast Colors.black38 in dark mode")

    def test_app_drawer_branding(self):
        with open(os.path.join(WORKSPACE, "lib", "widgets", "app_drawer.dart"), "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn('"SafeSphere"', content, "AppDrawer must display SafeSphere branding")

    def test_typing_text_substring_slicing(self):
        with open(os.path.join(WORKSPACE, "lib", "widgets", "typing_text.dart"), "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("widget.text.substring(0, _index)", content, "TypingText must use substring slicing for performance")

    def test_report_store_cached_status_counts(self):
        with open(os.path.join(WORKSPACE, "lib", "data", "report_store.dart"), "r", encoding="utf-8") as f:
            content = f.read()
        self.assertIn("_statusCounts", content, "ReportStore must cache status counts for O(1) queries")

if __name__ == "__main__":
    unittest.main()
