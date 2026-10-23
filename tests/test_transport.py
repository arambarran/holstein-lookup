"""Offline transport contracts; no requests to Holstein."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import Mock, patch

MODULE = Path(__file__).resolve().parents[1] / 'R' / 'python' / 'holstein_http.py'
spec = importlib.util.spec_from_file_location('holstein_http', MODULE)
http = importlib.util.module_from_spec(spec)
spec.loader.exec_module(http)


class TransportTests(unittest.TestCase):
    def test_network_errors_report_type_and_retryability_without_secrets(self):
        for error, retryable in [
            (http.Timeout('secret credentials'), True),
            (http.ConnectionError('secret credentials'), True),
            (http.SSLError('secret credentials'), False),
            (http.RequestException('secret credentials'), False),
        ]:
            with self.subTest(error=type(error).__name__):
                session = Mock()
                session.get.side_effect = error
                with patch.object(http.requests, 'Session', return_value=session):
                    result = http.LookupHTTPClient().fetch('https://www.holstein.ca/')
                self.assertEqual(result['retryable'], retryable)
                self.assertEqual(result['error'], type(error).__name__)
                self.assertNotIn('secret', str(result))

    def test_search_and_detail_share_a_browser_session(self):
        session = Mock()
        session.get.return_value = Mock(status_code=200, text='{"Data":[]}', headers={})
        with patch.object(http.requests, 'Session', return_value=session) as factory:
            client = http.LookupHTTPClient()
            first = client.fetch('https://www.holstein.ca/en/AIS/ReadAnimalSearchGrid?q=001')
            client.fetch('https://www.holstein.ca/en/AIS/AIS?animalId=123')
        factory.assert_called_once()
        self.assertEqual(factory.call_args.kwargs['impersonate'], 'chrome')
        self.assertNotIn('User-Agent', factory.call_args.kwargs['headers'])
        self.assertEqual(session.get.call_count, 2)
        self.assertEqual(session.get.call_args.kwargs['timeout'], 60)
        self.assertEqual(first['status'], 200)
        self.assertEqual(first['body'], '{"Data":[]}')

    def test_response_preserves_diagnostics_without_cookies(self):
        session = Mock()
        session.get.return_value = Mock(status_code=403, text='challenge', headers={
            'cf-mitigated': 'challenge', 'cf-ray': 'sample-YYZ',
            'retry-after': '120', 'set-cookie': 'secret',
        })
        with patch.object(http.requests, 'Session', return_value=session):
            response = http.LookupHTTPClient().fetch('https://www.holstein.ca/')
        self.assertEqual(response['challenge'], True)
        self.assertEqual(response['ray_id'], 'sample-YYZ')
        self.assertEqual(response['retry_after'], '120')
        self.assertNotIn('secret', str(response))


if __name__ == '__main__':
    unittest.main()
