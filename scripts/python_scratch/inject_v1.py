import re
import os

def inject_v1_features(file_path):
    if not os.path.exists(file_path):
        print(f"Skipping {file_path}, does not exist")
        return
        
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
        
    # Inject include at top
    if 'GEMINI_ROI_MODULE.mqh' not in content:
        content = re.sub(r'(#include <.*?>\n)', r'\1#include <../../GEMINI_ROI_MODULE.mqh>\n', content, count=1)
        
    # Inject InitGeminiKellySizing() in OnInit()
    if 'InitGeminiKellySizing();' not in content:
        content = re.sub(r'(int OnInit\(\)\s*\{)', r'\1\n   InitGeminiKellySizing();\n', content)
        
    # Inject RunGeminiROIModules() in OnTick() or OnTimer()
    # TRIAD uses OnTimer for primary loop, FIVE uses OnTick. We'll inject into both if present.
    if 'RunGeminiROIModules' not in content:
        content = re.sub(r'(void OnTick\(\)\s*\{)', r'\1\n   RunGeminiROIModules(InpMagic);\n', content)
        content = re.sub(r'(void OnTimer\(\)\s*\{)', r'\1\n   RunGeminiROIModules(InpMagic);\n', content)
        
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"Successfully injected V1 features into {file_path}")

inject_v1_features('MQL5/Experts/TRIAD_GOD_COMBO/TRIAD_GOD_COMBO_V1.mq5')
inject_v1_features('MQL5/Experts/FIVE_M5_EXHAUST/FIVE_M5_EXHAUST_V1.mq5')
inject_v1_features('MQL5/Experts/GOLD_SWING/GOLD_SWING_V1.mq5')
