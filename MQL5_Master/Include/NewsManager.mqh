//+------------------------------------------------------------------+
//|                                                  NewsManager.mqh |
//|                                  Copyright 2026, Master Strategy |
//+------------------------------------------------------------------+
#property strict

struct NewsEvent
{
    datetime utc_time;
    string   currency;
    string   title;
    string   impact;
};

class CNewsManager
{
private:
    NewsEvent m_events[];
    bool      m_liveEnabled;
    int       m_blockMinutesBefore;
    int       m_blockMinutesAfter;
    string    m_csvFileName;
    
    int       m_brokerUtcOffset; // Broker time offset from ForexFactory (EST/EDT is UTC-5/UTC-4, Broker usually UTC+2/UTC+3)
    
    string    ExtractXMLTag(string xml, string tag);

public:
              CNewsManager(bool enableLive, int minsBefore, int minsAfter, int brokerOffsetHours = 7, string csvName = "triad_red_news.csv");
             ~CNewsManager();
             
    bool      DownloadAndParse();
    bool      LoadFromCSV();
    bool      IsNewsBlockActive(string symbol);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CNewsManager::CNewsManager(bool enableLive, int minsBefore, int minsAfter, int brokerOffsetHours, string csvName)
{
    m_liveEnabled = enableLive;
    m_blockMinutesBefore = minsBefore;
    m_blockMinutesAfter = minsAfter;
    m_brokerUtcOffset = brokerOffsetHours;
    m_csvFileName = csvName;
    ArrayResize(m_events, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CNewsManager::~CNewsManager()
{
    ArrayResize(m_events, 0);
}

//+------------------------------------------------------------------+
//| Extract XML Tag                                                  |
//+------------------------------------------------------------------+
string CNewsManager::ExtractXMLTag(string xml, string tag)
{
    string open_tag = "<"+tag+"><![CDATA[";
    string close_tag = "]]></"+tag+">";
    int start = StringFind(xml, open_tag);
    if(start == -1)
    {
        open_tag = "<"+tag+">";
        close_tag = "</"+tag+">";
        start = StringFind(xml, open_tag);
        if(start == -1) return "";
    }
    
    start += StringLen(open_tag);
    int end = StringFind(xml, close_tag, start);
    if(end == -1) return "";
    
    return StringSubstr(xml, start, end - start);
}

//+------------------------------------------------------------------+
//| Download and Parse XML from ForexFactory                         |
//+------------------------------------------------------------------+
bool CNewsManager::DownloadAndParse()
{
    if(!m_liveEnabled) 
    {
        Print("NEWS MANAGER: Live News Download Bypassed (Backtest Mode Active). Attempting to load from CSV.");
        return LoadFromCSV();
    }
    
    string url="https://nfs.faireconomy.media/ff_calendar_thisweek.xml";
    char post[], result[];
    string headers;
    
    Print("NEWS MANAGER: Downloading live calendar from ForexFactory...");
    int res = WebRequest("GET", url, NULL, NULL, 5000, post, 0, result, headers);
    
    if(res == -1)
    {
        Print("NEWS ERROR: WebRequest failed. Please allow ", url, " in MT5 Options.");
        return false;
    }
    
    string xml = CharArrayToString(result);
    int handle = FileOpen(m_csvFileName, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
    
    if(handle == INVALID_HANDLE) 
    {
        Print("NEWS ERROR: Failed to open CSV for writing: ", m_csvFileName);
        return false;
    }
    
    int pos = 0;
    while((pos = StringFind(xml, "<event>", pos)) != -1)
    {
        int end_pos = StringFind(xml, "</event>", pos);
        if(end_pos == -1) break;
        
        string event_str = StringSubstr(xml, pos, end_pos - pos);
        pos = end_pos;
        
        string impact = ExtractXMLTag(event_str, "impact");
        if(impact != "High") continue; // We only care about RED news
        
        string date = ExtractXMLTag(event_str, "date");
        string time_str = ExtractXMLTag(event_str, "time");
        string country = ExtractXMLTag(event_str, "country");
        string title = ExtractXMLTag(event_str, "title");
        
        // Basic mapping mm-dd-yyyy to yyyy.mm.dd
        string formatted_date = StringSubstr(date, 6, 4) + "." + StringSubstr(date, 0, 2) + "." + StringSubstr(date, 3, 2);
        FileWrite(handle, formatted_date+" "+time_str, country, impact, title);
    }
    
    FileWrite(handle, "2030.01.01 00:00", "ALL", "COVERAGE", "End of File Coverage");
    FileClose(handle);
    
    Print("NEWS MANAGER: Live calendar downloaded and parsed to CSV.");
    return LoadFromCSV();
}

//+------------------------------------------------------------------+
//| Load News from CSV                                               |
//+------------------------------------------------------------------+
bool CNewsManager::LoadFromCSV()
{
    ArrayResize(m_events, 0);
    int handle = FileOpen(m_csvFileName, FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ, ',');
    if(handle == INVALID_HANDLE)
    {
        Print("NEWS ERROR: Cannot load CSV ", m_csvFileName, ". News filtering will be disabled.");
        return false;
    }
    
    while(!FileIsEnding(handle))
    {
        string time_text = FileReadString(handle);
        if(FileIsEnding(handle) && time_text == "") break;
        
        string currency = FileReadString(handle);
        string impact = FileReadString(handle);
        string title = FileReadString(handle);
        
        datetime event_time = ParseAMPMTime(time_text); // CRITICAL FIX: Handle ForexFactory AM/PM
        
        // V4 UPGRADE: Align ForexFactory EST/EDT time to Broker Server Time (typically +7 hours)
        event_time = event_time + (m_brokerUtcOffset * 3600);
        
        int size = ArraySize(m_events);
        ArrayResize(m_events, size + 1);
        m_events[size].utc_time = event_time;
        m_events[size].currency = currency;
        m_events[size].impact = impact;
        m_events[size].title = title;
    }
    
    FileClose(handle);
    Print("NEWS MANAGER: Successfully loaded ", ArraySize(m_events), " high-impact events from CSV.");
    return true;
}

//+------------------------------------------------------------------+
//| Check if News Block is Active for a specific symbol              |
//+------------------------------------------------------------------+
bool CNewsManager::IsNewsBlockActive(string symbol)
{
    if(ArraySize(m_events) == 0) return false;
    
    datetime current_time = TimeCurrent();
    string base = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
    string quote = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
    
    // Fallback for custom symbols or missing API data
    if(base == "" || quote == "")
    {
        base = StringSubstr(symbol, 0, 3);
        quote = StringSubstr(symbol, 3, 3);
    }
    
    for(int i = 0; i < ArraySize(m_events); i++)
    {
        if(m_events[i].currency == "ALL" || m_events[i].currency == base || m_events[i].currency == quote || (m_events[i].currency == "USD" && (base == "XAU" || base == "GOLD")))
        {
            // Time distance in seconds
            long diff = (long)m_events[i].utc_time - (long)current_time;
            
            // If the event is in the future, check if we are within the 'Before' block
            if(diff > 0 && diff <= (m_blockMinutesBefore * 60))
            {
                Print("NEWS FILTER BLOCK: Approaching High-Impact News (", m_events[i].title, "). Blocked for symbol: ", symbol);
                return true;
            }
            
            // If the event is in the past, check if we are within the 'After' block
            if(diff <= 0 && MathAbs(diff) <= (m_blockMinutesAfter * 60))
            {
                Print("NEWS FILTER BLOCK: High-Impact News recently passed (", m_events[i].title, "). Blocked for symbol: ", symbol);
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Custom StringToTime with AM/PM Support                           |
//+------------------------------------------------------------------+
datetime ParseAMPMTime(string time_text)
{
    // time_text format: "2026.09.30 8:30am" or "2026.09.30 12:30pm" or "2030.01.01 00:00"
    if(StringFind(time_text, "am") == -1 && StringFind(time_text, "pm") == -1)
        return StringToTime(time_text);
        
    string cleanStr = time_text;
    bool isPM = (StringFind(time_text, "pm") != -1);
    bool isAM = (StringFind(time_text, "am") != -1);
    
    StringReplace(cleanStr, "am", "");
    StringReplace(cleanStr, "pm", "");
    
    // Split into Date and Time
    string parts[];
    StringSplit(cleanStr, ' ', parts);
    if(ArraySize(parts) < 2) return StringToTime(cleanStr);
    
    // Split Time into Hour and Minute
    string timeParts[];
    StringSplit(parts[1], ':', timeParts);
    if(ArraySize(timeParts) < 2) return StringToTime(cleanStr);
    
    int hour = (int)StringToInteger(timeParts[0]);
    int minute = (int)StringToInteger(timeParts[1]);
    
    if(isPM && hour < 12) hour += 12;
    if(isAM && hour == 12) hour = 0;
    
    string hourStr = IntegerToString(hour);
    if(hour < 10) hourStr = "0" + hourStr;
    string minStr = IntegerToString(minute);
    if(minute < 10) minStr = "0" + minStr;
    
    string finalStr = parts[0] + " " + hourStr + ":" + minStr + ":00";
    return StringToTime(finalStr);
}

