import re

files = [
    'MQL5/Experts/TRIAD_GOD_COMBO/TRIAD_GOD_COMBO_V1.mq5',
    'MQL5/Experts/FIVE_M5_EXHAUST/FIVE_M5_EXHAUST_V1.mq5',
    'MQL5/Experts/GOLD_SWING/GOLD_SWING_V1.mq5'
]

for file_path in files:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Force rewrite of all variations
    content = re.sub(r'#include\s*<.*?GEMINI_ROI_MODULE\.mqh>', '#include "../GEMINI_ROI_MODULE.mqh"', content)
    content = re.sub(r'#include\s*".*?GEMINI_ROI_MODULE\.mqh"', '#include "../GEMINI_ROI_MODULE.mqh"', content)
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
