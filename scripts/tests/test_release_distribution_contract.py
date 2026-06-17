import plistlib
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
INFO_PLIST = REPO / "TokenAtlas" / "App" / "Info.plist"
PUBLISH_APPCAST = REPO / "scripts" / "publish-appcast.sh"
UPDATE_APPCAST = REPO / "scripts" / "update-appcast.py"
RELEASE_BUILD = REPO / "scripts" / "release-build.sh"
RENDER_DMG_BACKGROUND = REPO / "scripts" / "render-dmg-background.swift"
RELEASE_WORKFLOW = REPO / ".github" / "workflows" / "release.yml"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class ReleaseDistributionContractTests(unittest.TestCase):
    def test_info_plist_enables_signed_sparkle_updates(self) -> None:
        with INFO_PLIST.open("rb") as fh:
            info = plistlib.load(fh)

        self.assertEqual(
            info["SUFeedURL"],
            "https://can4hou6joeng4.github.io/TokenAtlas/appcast.xml",
        )
        self.assertRegex(info["SUPublicEDKey"], r"^[A-Za-z0-9+/=]{40,}$")
        self.assertTrue(info["SUEnableAutomaticChecks"])

    def test_app_runtime_and_appcast_publisher_share_feed_url(self) -> None:
        with INFO_PLIST.open("rb") as fh:
            feed_url = plistlib.load(fh)["SUFeedURL"]

        self.assertIn(f'FEED_URL="{feed_url}"', read(PUBLISH_APPCAST))
        self.assertIn(f'FEED_URL = "{feed_url}"', read(UPDATE_APPCAST))

    def test_release_workflow_warns_when_appcast_cannot_be_published(self) -> None:
        workflow = read(RELEASE_WORKFLOW)

        self.assertIn("SPARKLE_PRIVATE_ED_KEY: ${{ secrets.SPARKLE_PRIVATE_ED_KEY }}", workflow)
        self.assertIn(
            "installed apps won't auto-update to this release",
            workflow,
        )
        self.assertIn("if: steps.sparkle.outputs.enabled == 'true'", workflow)
        self.assertIn("bash scripts/publish-appcast.sh", workflow)

    def test_dmg_builder_creates_drag_install_layout(self) -> None:
        script = read(RELEASE_BUILD)

        self.assertIn('cp -R "$APP" "$stage/"', script)
        self.assertIn('ln -s /Applications "$stage/Applications"', script)
        self.assertIn('swift scripts/render-dmg-background.swift "$stage/.background/dmg-background.png"', script)
        self.assertIn("set the bounds of container window to {160, 90, 1520, 930}", script)
        self.assertIn('set position of item "TokenAtlas.app" to {410, 490}', script)
        self.assertIn('set position of item "Applications" to {950, 490}', script)
        self.assertIn('hdiutil convert "$rw_dmg" -format UDZO', script)

    def test_dmg_background_matches_finder_window_geometry(self) -> None:
        renderer = read(RENDER_DMG_BACKGROUND)

        self.assertIn("static let size = CGSize(width: 1360, height: 840)", renderer)
        self.assertIn("Drag TokenAtlas to Applications", renderer)
        self.assertIn("Future releases arrive through Sparkle updates", renderer)
        self.assertIn("static let appPad = CGRect(x: 300, y: 392, width: 220, height: 196)", renderer)
        self.assertIn("static let applicationsPad = CGRect(x: 840, y: 392, width: 220, height: 196)", renderer)


if __name__ == "__main__":
    unittest.main()
