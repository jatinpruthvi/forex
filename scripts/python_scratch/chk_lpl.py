import csv
path = r'C:\Users\Mishay\AppData\Roaming\MetaQuotes\Terminal\930119AA53207C8778B41171FBFFB46F\MQL5\Files\ea_signal_dump.csv'
for idx, r in enumerate(csv.DictReader(open(path))):
    dist = float(r['dist'])
    tick_size = float(r['tick_size'])
    tick_val = float(r['tick_value'])
    lpl = float(r['loss_per_lot'])
    if tick_size > 0:
        expected = (dist / tick_size) * tick_val + 7.0
        if abs(lpl - expected) > 1e-4:
            print(f'Row {idx+2}: {r["symbol"]} lpl={lpl} expected={expected} dist={dist} tick_val={tick_val} tick_size={tick_size}')
            break
