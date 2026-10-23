"""Browser-compatible HTTP transport shared by the R CLI and Shiny worker."""
from curl_cffi import requests

HEADERS = {
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': 'https://www.holstein.ca/',
    'X-Requested-With': 'XMLHttpRequest',
}


class LookupHTTPClient:
    def __init__(self):
        # The profile supplies matching browser headers and TLS/HTTP settings.
        self.session = requests.Session(impersonate='chrome', headers=HEADERS)

    def fetch(self, url):
        response = self.session.get(url, timeout=60)
        return {
            'status': response.status_code,
            'body': response.text,
            'challenge': response.headers.get('cf-mitigated') == 'challenge',
            'ray_id': response.headers.get('cf-ray', ''),
            'retry_after': response.headers.get('retry-after', ''),
        }
