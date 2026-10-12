$compiler = "C:\Program Files\Fusion Markets MetaTrader 5\MetaEditor64.exe"
$src = "E:\Jatin-Project\Forex\forex\MQL5\Experts\GOLD_SWING\AllEnginesEA_GOLD_SWING.mq5"
$log = "E:\Jatin-Project\Forex\forex\MQL5\Experts\GOLD_SWING\AllEnginesEA_GOLD_SWING.log"
Start-Process -FilePath $compiler -ArgumentList "/compile:`"$src`" /log:`"$log`"" -Wait
Get-Content $log | Select-Object -Last 3
