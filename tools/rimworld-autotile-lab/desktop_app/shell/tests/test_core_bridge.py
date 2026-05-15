import io
import json
import queue
import sys
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import core_bridge  # noqa: E402


class _FakePipe(io.StringIO):
    """StringIO subclass that lets a writer push lines and a reader iterate them."""

    def __init__(self) -> None:
        super().__init__()
        self._lock = threading.Lock()
        self._queue: queue.Queue[str | None] = queue.Queue()
        self._closed_event = threading.Event()

    def push_response(self, line: str) -> None:
        self._queue.put(line + "\n")

    def push_eof(self) -> None:
        self._queue.put(None)

    def __iter__(self):
        return self

    def __next__(self) -> str:
        item = self._queue.get()
        if item is None:
            raise StopIteration
        return item

    def read(self) -> str:
        return ""

    def write(self, data) -> int:
        return len(data)

    def flush(self) -> None:
        pass

    def close(self) -> None:
        self._closed_event.set()


class _FakeProcess:
    def __init__(self) -> None:
        self.stdin = _FakePipe()
        self.stdout = _FakePipe()
        self.stderr = _FakePipe()
        self._returncode: int | None = None
        self.terminated = False
        self.killed = False
        self.requests: list[str] = []
        original_write = self.stdin.write

        def capture_write(data: str) -> int:
            self.requests.append(data)
            return original_write(data)

        self.stdin.write = capture_write  # type: ignore[assignment]

    def poll(self) -> int | None:
        return self._returncode

    def terminate(self) -> None:
        self.terminated = True

    def kill(self) -> None:
        self.killed = True
        self._returncode = -9

    def wait(self, timeout: float | None = None) -> int:
        if self._returncode is None:
            self._returncode = 0
        return self._returncode


class CoreServerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fake = _FakeProcess()
        self.popen_patch = patch.object(
            core_bridge.subprocess, "Popen", return_value=self.fake
        )
        self.popen_patch.start()
        self.addCleanup(self.popen_patch.stop)

    def _make_server(self) -> core_bridge._CoreServer:
        server = core_bridge._CoreServer(Path("fake-binary"))
        self.addCleanup(server.stop)
        return server

    def test_submit_writes_request_and_dispatches_matching_response(self) -> None:
        server = self._make_server()
        response_queue = server.submit(7, {"id": 7, "mode": "draft"})
        self.fake.stdout.push_response(json.dumps({"id": 7, "ok": True, "manifest": {}}))

        line = response_queue.get(timeout=1.0)
        parsed = json.loads(line)

        self.assertEqual(parsed["id"], 7)
        self.assertTrue(parsed["ok"])
        self.assertIn('"id":7', self.fake.requests[0])

    def test_stale_response_is_dropped_after_unregister(self) -> None:
        server = self._make_server()
        response_queue = server.submit(11, {"id": 11})
        server.unregister(11)
        self.fake.stdout.push_response(json.dumps({"id": 11, "ok": True, "manifest": {}}))
        time.sleep(0.05)

        with self.assertRaises(queue.Empty):
            response_queue.get(timeout=0.1)

    def test_concurrent_responses_route_by_id(self) -> None:
        server = self._make_server()
        q1 = server.submit(1, {"id": 1})
        q2 = server.submit(2, {"id": 2})
        self.fake.stdout.push_response(json.dumps({"id": 2, "ok": True, "manifest": {"x": 2}}))
        self.fake.stdout.push_response(json.dumps({"id": 1, "ok": True, "manifest": {"x": 1}}))

        line2 = q2.get(timeout=1.0)
        line1 = q1.get(timeout=1.0)

        self.assertEqual(json.loads(line1)["manifest"]["x"], 1)
        self.assertEqual(json.loads(line2)["manifest"]["x"], 2)

    def test_stop_does_not_leak_pending_waiters(self) -> None:
        server = self._make_server()
        response_queue = server.submit(99, {"id": 99})

        server.stop()

        line = response_queue.get(timeout=1.0)
        self.assertEqual(line, "")
        self.assertTrue(self.fake.terminated or self.fake._returncode is not None)


class WaitForResponseTests(unittest.TestCase):
    class _AliveServer:
        def __init__(self, alive: bool = True) -> None:
            self._alive = alive

        def is_alive(self) -> bool:
            return self._alive

        def drain_stderr(self) -> str:
            return ""

    def test_cancel_event_raises_render_cancelled_without_killing(self) -> None:
        server = self._AliveServer(alive=True)
        cancel_event = threading.Event()
        cancel_event.set()
        empty_queue: queue.Queue[str] = queue.Queue()

        with patch.object(core_bridge, "stop_core_server") as stop_mock:
            with self.assertRaises(core_bridge.RenderCancelled):
                core_bridge._wait_for_response(server, empty_queue, cancel_event)

        stop_mock.assert_not_called()


if __name__ == "__main__":
    unittest.main()
