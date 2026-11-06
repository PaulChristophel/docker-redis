"""Focused release selection and registry pinning checks."""

import copy
import unittest
from unittest.mock import patch
import update_redis_releases as updater


class UpdaterTests(unittest.TestCase):
    """Exercise compatibility and pin safety."""

    def test_series_and_preview_selection(self):
        """Select only newer stable patches in the configured series."""
        config = {
            "redis": [
                {"version": "8.10.3", "sha256": "old", "channel": "stable"},
                {"version": "9.0.0-rc1", "channel": "preview"},
            ]
        }
        releases = [
            {
                "tag_name": v,
                "prerelease": pre,
                "assets": [
                    {"name": "redis-full.tar.gz", "digest": "sha256:" + "a" * 64}
                ],
            }
            for v, pre in [
                ("8.10.4", False),
                ("8.10.5", True),
                ("8.12.0", False),
                ("9.0.0", False),
            ]
        ]
        self.assertEqual(len(updater.update_releases(config, releases)), 1)
        self.assertEqual(config["redis"][0]["version"], "8.10.4")
        self.assertEqual(config["redis"][0]["sha256"], "a" * 64)
        self.assertEqual(config["redis"][1]["version"], "9.0.0-rc1")
        self.assertEqual(updater.update_releases(config, releases), [])

    def test_missing_digest_does_not_change_entry(self):
        """Reject a release without the exact full-archive checksum."""
        config = {"redis": [{"version": "8.10.3", "channel": "stable"}]}
        before = copy.deepcopy(config)
        with self.assertRaises(RuntimeError):
            updater.update_releases(config, [{"tag_name": "8.10.4", "assets": []}])
        self.assertEqual(config, before)

    def test_registry_auth_and_digest(self):
        """Resolve the same tagged image using its registry bearer challenge."""
        from urllib.error import HTTPError

        err = HTTPError(
            "https://registry-1.docker.io",
            401,
            "Unauthorized",
            {
                "WWW-Authenticate": 'Bearer realm="https://auth.docker.io/token",service="registry.docker.io",scope="repository:opensuse/tumbleweed:pull"'
            },
            None,
        )
        failure = RuntimeError("auth required")
        failure.__cause__ = err
        with patch.object(
            updater,
            "fetch_response",
            side_effect=[
                failure,
                ("{}", {"docker-content-digest": "sha256:" + "b" * 64}),
            ],
        ), patch.object(updater, "fetch_text", return_value='{"token":"test"}'):
            self.assertEqual(
                updater.current_base_digest(
                    "docker.io/opensuse/tumbleweed:latest@sha256:" + "a" * 64
                ),
                "docker.io/opensuse/tumbleweed:latest@sha256:" + "b" * 64,
            )


if __name__ == "__main__":
    unittest.main()
