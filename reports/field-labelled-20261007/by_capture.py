import csv
from collections import defaultdict
R = "reports/field-labelled-20261007"
res = {r["id"]: r for r in csv.DictReader(open(f"{R}/results.csv"))}
g = defaultdict(list)
for t in csv.DictReader(open(f"{R}/capture_tags.csv")):
    g[t["capture"]].append(res[t["id"]])
for k, rows in g.items():
    pct = sorted(abs(float(r["pct_error"])) for r in rows)
    print(f'{k:18s} n={len(rows):2d} exact={sum(r["exact"]=="True" for r in rows)} '
          f'within_2={sum(int(r["abs_error"])<=2 for r in rows)} within_5pct={sum(p<=5 for p in pct)} '
          f'median_abs_pct={pct[len(pct)//2]} worst={pct[-1]}% ids_over_10pct={[r["id"] for r in rows if abs(float(r["pct_error"]))>10]}')
