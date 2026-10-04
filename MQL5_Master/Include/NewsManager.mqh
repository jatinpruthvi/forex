//+------------------------------------------------------------------+
//|                                                  NewsManager.mqh |
//|                                  Copyright 2026, Master Strategy |
//+------------------------------------------------------------------+
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
    
    int       m_brokerUtcOffset; // fallback NY -> server shift (winter calibration; used only if the terminal clocks are unusable)

    //--- #7: a load that produced nothing usable must not read as "no news".
    //--- The gate fails CLOSED while the calendar is unusable (the EA refuses to
    //--- init on a failed load; this is the belt-and-braces at the gate).
    bool      m_loadOk;
    bool      m_warnedNoCalendar;
    bool      m_warnedEmptyWeek;

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
    m_loadOk = false;
    m_warnedNoCalendar = false;
    m_warnedEmptyWeek = false;
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
//+------------------------------------------------------------------+
//| US daylight-saving check for a NEW YORK local timestamp           |
//|                                                                   |
//| The ForexFactory feed stamps its events in New York local time:   |
//| EST (UTC-5) in winter, EDT (UTC-4) from the second Sunday of      |
//| March 02:00 to the first Sunday of November 02:00.  Every         |
//| date-based translation of those stamps needs this offset - see    |
//| NewsServerShiftSeconds() below.                                   |
//+------------------------------------------------------------------+
bool IsNewYorkDst(const datetime nyLocalTime)
{
    MqlDateTime dt;
    if(!TimeToStruct(nyLocalTime, dt)) return false;

    MqlDateTime m;
    m.year = dt.year; m.mon = 3; m.day = 1; m.hour = 2; m.min = 0; m.sec = 0;
    datetime mar1 = StructToTime(m);
    MqlDateTime md;
    TimeToStruct(mar1, md);
    int daysToSun = (7 - md.day_of_week) % 7;          // day_of_week: 0 = Sunday
    datetime dstStart = mar1 + (datetime)((daysToSun + 7) * 86400);   // second Sunday

    MqlDateTime n;
    n.year = dt.year; n.mon = 11; n.day = 1; n.hour = 2; n.min = 0; n.sec = 0;
    datetime nov1 = StructToTime(n);
    MqlDateTime nd;
    TimeToStruct(nov1, nd);
    int daysToSun2 = (7 - nd.day_of_week) % 7;
    datetime dstEnd = nov1 + (datetime)(daysToSun2 * 86400);          // first Sunday

    return (nyLocalTime >= dstStart && nyLocalTime < dstEnd);
}

//+------------------------------------------------------------------+
//| Seconds to add to a New York LOCAL stamp to reach SERVER time     |
//|                                                                   |
//|     shift = server_offset - ny_offset                             |
//|                                                                   |
//| server_offset = TimeTradeServer() - TimeGMT(): the broker's own   |
//|   UTC offset, read live from the terminal.  Exact for EET/EEST    |
//|   servers that follow European DST, for fixed-offset servers and  |
//|   for half-hour zones (the engine reads the same clocks in        |
//|   EA_ServerGmtOffsetSeconds()).                                   |
//| ny_offset = -4 h while New York is on daylight time, -5 h         |
//|   otherwise, for the EVENT'S OWN date.                            |
//|                                                                   |
//| The delivered code added a constant offset calibrated on winter   |
//| (default 7 h = server+2 - NY-5).  That is only right while the    |
//| broker's offset and New York's move together: it misses by an     |
//| hour all summer on a fixed-offset server, and during the weeks    |
//| where the US and EU change dates differ on an EET/EEST server -   |
//| a 30-minute window can miss the release entirely.  When the       |
//| terminal clocks are unusable (|diff| >= 14 h, e.g. a mis-set       |
//| clock) the calibrated input is the fallback, as before.           |
//+------------------------------------------------------------------+
long NewsServerShiftSeconds(const datetime nyLocalTime, const int fallbackHours)
{
    long serverMinusGmt = (long)TimeTradeServer() - (long)TimeGMT();
    if(serverMinusGmt <= -(long)14 * 3600 || serverMinusGmt >= (long)14 * 3600)
        return (long)fallbackHours * 3600;                  // clocks unusable

    long nyOffsetSeconds = (IsNewYorkDst(nyLocalTime) ? -4 : -5) * (long)3600;
    return serverMinusGmt - nyOffsetSeconds;
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
        
        // #7: the feed's casing is not a contract.  The delivered exact compare
        // against "High" silently dropped every row if the feed ever shipped
        // "HIGH"/"high" - i.e. the news filter would go quietly inert.
        string impact = ExtractXMLTag(event_str, "impact");
        string imp = impact;
        StringTrimLeft(imp); StringTrimRight(imp); StringToLower(imp);
        if(imp != "high") continue; // RED news only
        
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
    m_loadOk = false;
    int handle = FileOpen(m_csvFileName, FILE_READ|FILE_CSV|FILE_ANSI|FILE_SHARE_READ, ',');
    if(handle == INVALID_HANDLE)
    {
        Print("NEWS ERROR: cannot load CSV ", m_csvFileName,
              " - the news gate will FAIL CLOSED (no new entries).");
        return false;
    }

    int rowsSeen = 0, badRows = 0, notHigh = 0;

    while(!FileIsEnding(handle))
    {
        string time_text = FileReadString(handle);
        if(FileIsEnding(handle) && time_text == "") break;
        
        string currency = FileReadString(handle);
        string impact = FileReadString(handle);
        string title = FileReadString(handle);
        rowsSeen++;

        // #7: impact compared case-insensitively (and trimmed); a hand-written
        // CSV with "HIGH" now behaves, and the 2030 coverage sentinel row
        // (impact "COVERAGE") is no longer loaded as a blocking event.
        string imp = impact;
        StringTrimLeft(imp); StringTrimRight(imp); StringToLower(imp);
        if(imp != "high") { notHigh++; continue; }
        
        datetime event_time = ParseAMPMTime(time_text); // CRITICAL FIX: Handle ForexFactory AM/PM

        // #8: a changed feed format used to make ParseAMPMTime() return 0 and the
        // event landed at 1970 + offset - a silent no-op (past events never
        // block).  Reject anything outside a sane calendar range and count it.
        if(event_time <= 0 ||
           event_time < (datetime)D'2000.01.01' || event_time >= (datetime)D'2100.01.01')
        {
            badRows++;
            continue;
        }
        
        // V5 FIX: translate the feed's New York local stamp to the broker's
        // server clock with the offset read LIVE from the terminal clocks; a
        // fixed winter calibration is an hour off whenever the broker's UTC
        // offset and New York's do not move together (see above).
        long shiftSeconds = NewsServerShiftSeconds(event_time, m_brokerUtcOffset);
        event_time = (datetime)((long)event_time + shiftSeconds);
        
        int size = ArraySize(m_events);
        ArrayResize(m_events, size + 1);
        m_events[size].utc_time = event_time;
        m_events[size].currency = currency;
        m_events[size].impact = impact;
        m_events[size].title = title;
    }
    
    FileClose(handle);

    //--- fail-closed state (#7): rows that existed but could not be parsed mean
    //--- the format changed under us - refuse rather than trade blind.  An empty
    //--- file is also refused; a file with only non-high rows is a legitimate
    //--- "quiet week" and loads fine with zero events.
    m_loadOk = (rowsSeen > 0 && badRows == 0);
    if(badRows > 0)
        Print("NEWS ERROR: ", badRows, " of ", rowsSeen, " row(s) in ", m_csvFileName,
              " could not be parsed - the feed format may have changed.  News gate FAILS CLOSED.");
    if(rowsSeen == 0)
        Print("NEWS ERROR: ", m_csvFileName, " contains no rows.  News gate FAILS CLOSED.");
    Print("NEWS MANAGER: loaded ", ArraySize(m_events), " high-impact event(s) from CSV (",
          notHigh, " non-high row(s) skipped, ", badRows, " unparseable).");
    return m_loadOk;
}

//+------------------------------------------------------------------+
//| Check if News Block is Active for a specific symbol              |
//+------------------------------------------------------------------+
bool CNewsManager::IsNewsBlockActive(string symbol)
{
    // #7: the delivered gate returned false when the event list was empty, so a
    // failed or unparseable calendar read as "no news" and the EA traded blind.
    if(!m_loadOk)
    {
        if(!m_warnedNoCalendar)
        {
            m_warnedNoCalendar = true;
            Print("NEWS FILTER: no usable calendar loaded - blocking new entries (fail closed).");
        }
        return true;
    }
    if(ArraySize(m_events) == 0)
    {
        if(!m_warnedEmptyWeek)
        {
            m_warnedEmptyWeek = true;
            Print("NEWS FILTER: calendar loaded but contains no high-impact events - no blackout windows.");
        }
        return false;
    }
    
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

