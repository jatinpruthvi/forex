def parse_xml_to_csv():
    import urllib.request
    import xml.etree.ElementTree as ET
    from datetime import datetime, timedelta
    
    url = 'https://nfs.faireconomy.media/ff_calendar_thisweek.xml'
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    
    with urllib.request.urlopen(req) as response:
        xml_data = response.read()
    
    root = ET.fromstring(xml_data)
    
    csv_rows = []
    
    # ForexFactory time is Eastern Time (EST/EDT)
    # We must convert to UTC
    for event in root.findall('event'):
        impact = event.find('impact').text
        if impact != 'High':
            continue
            
        currency = event.find('country').text
        date_str = event.find('date').text
        time_str = event.find('time').text
        title = event.find('title').text
        
        # MQL5 expects time_text, currency, impact, title
        print(f"{date_str} {time_str}, {currency}, {impact}, {title}")
        
parse_xml_to_csv()
