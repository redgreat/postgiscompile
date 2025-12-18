import os
import sys
import types
import unittest

# 允许从项目根路径导入脚本
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MONITOR_DIR = os.path.join(ROOT, "monitor")
if MONITOR_DIR not in sys.path:
    sys.path.insert(0, MONITOR_DIR)

import monitor_pg  # noqa: E402


class TestConfigValidation(unittest.TestCase):
    """配置验证测试"""
    def test_validate_config_defaults(self):
        cfg = {
            "db": {"host": "localhost", "port": 5432, "dbname": "postgres", "user": "postgres"},
            "webhook": {"url": "https://example.invalid"},
            "thresholds": {}
        }
        out = monitor_pg.validate_config(cfg)
        self.assertIn("interval_seconds", out)
        self.assertIn("templates", out)
        self.assertIn("log_file", out)

    def test_missing_sections(self):
        with self.assertRaises(monitor_pg.ConfigError):
            monitor_pg.validate_config({})


class TestSeverity(unittest.TestCase):
    """严重级别计算测试"""
    def test_severity_calc(self):
        th = {"warning": 10, "critical": 20}
        self.assertEqual(monitor_pg.severity_of(5, th), None)
        self.assertEqual(monitor_pg.severity_of(12, th), "WARNING")
        self.assertEqual(monitor_pg.severity_of(25, th), "CRITICAL")


class TestMessageFormat(unittest.TestCase):
    """告警消息格式化测试"""
    def test_message(self):
        cfg = monitor_pg.validate_config({
            "db": {"host": "localhost", "port": 5432, "dbname": "postgres", "user": "postgres"},
            "webhook": {"url": "https://example.invalid"},
            "thresholds": {}
        })
        logger = monitor_pg.setup_logger("/tmp/monitor_pg_test.log")
        dummy_db = types.SimpleNamespace()
        sender = monitor_pg.AlertSender("https://example.invalid")
        mon = monitor_pg.Monitor(cfg, dummy_db, sender, logger)
        msg = mon.build_message("连接总数", 100, {"warning": 50}, "WARNING", "active=20 idle=80", "启用连接池")
        self.assertIn("PostgreSQL 监控告警", msg)
        self.assertIn("连接总数", msg)
        self.assertIn("WARNING", msg)


if __name__ == "__main__":
    unittest.main()

