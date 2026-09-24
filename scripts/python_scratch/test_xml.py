import urllib.request
url = 'https://nfs.faireconomy.media/ff_calendar_thisweek.xml'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req) as response:
        data = response.read().decode('utf-8')
        print(data[:1000])
except Exception as e:
    print(f"Error: {e}")
