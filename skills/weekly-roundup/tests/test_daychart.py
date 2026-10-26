"""daychart.py (week and archive bar charts) and build_archive.py's `days` handling."""
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(HERE))
import daychart  # noqa: E402

DAYS = [{"date": f"2026-10-{4 + k:02d}", "label": lab, "total_pct": 0, "segments": []}
        for k, lab in enumerate(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])]
DAYS[1] = {**DAYS[1], "total_pct": 12.3, "segments": [
    {"project": "Alpha", "person": "Jet", "color": "#e5484d", "pct": 10.0},
    {"project": "Beta", "person": "Jaxon", "color": "#2f80ed", "pct": 2.3}]}


def test_week_chart():
    h = daychart.week_html(DAYS, solo=False)
    assert h.startswith('<div class="barchart-wrap"><h2 class="sub">Usage by day</h2>')
    assert re.findall(r'<span style="bottom:[^"]*">(\d+)%</span>', h) == ["0", "5", "10", "15"]  # 12.3 -> 15
    assert h.count('class="bc-grid"') == 3 and h.count('class="bc-col"') == 7
    assert 'title="Alpha · Jet · 10.0%"' in h and "background:#e5484d" in h
    assert h.index("Alpha") < h.index("Beta")  # largest first (drawn at the bottom)
    assert 'style="height:82.00%"' in h  # 12.3 / 15
    assert "Colors match the projects pie above." in h and "legend" not in h
    assert 'title="Alpha · 10.0%"' in daychart.week_html(DAYS, solo=True)
    # segments carry the pie slice name; the week chart (not the archive) gets the click script
    assert 'data-name="Alpha · Jet"' in h and 'data-name="Alpha"' in daychart.week_html(DAYS, solo=True)
    assert 'class="bc bc-wk"' in h and h.count("<script>") == 1 and "scrollIntoView" in h


def test_archive_chart_and_days_required(tmp_path):
    old = {"weekStart": "2026-09-27", "label": "Sep 27–Oct 4, 2026", "url": "u0", "projectCount": 1,
           "totalCost": 1.0, "slices": []}
    h = daychart.archive_html([{**old, "weekStart": "2026-10-04", "label": "Oct 4–11, 2026", "days": DAYS}, old])
    assert h.index("Sep 27–Oct 4<") < h.index("Oct 4–11<")  # oldest left, year dropped
    assert h.count("no daily data") == 1 and h.count('class="bc-week"') == 2
    assert "scrollLeft=s.scrollWidth" in h and "bc-wk" not in h and "scrollIntoView" not in h
    week = tmp_path / "w.json"
    week.write_text(json.dumps({**old, "weekStart": "2026-10-04"}))
    base = tmp_path / "base.html"
    base.write_text('<script type="application/json" id="weeks-data">' + json.dumps([old]) + "</script>")
    weeks_file = HERE / "archive_weeks.json"
    saved = weeks_file.read_text()
    try:
        r = subprocess.run([sys.executable, str(HERE / "build_archive.py"), "--base", str(base), "--add", str(week),
                            "--out", str(tmp_path / "a.html")], capture_output=True, text=True)
        assert r.returncode != 0 and "days" in r.stderr
        out = tmp_path / "o.json"
        out.write_text(json.dumps({"days": DAYS}))
        r = subprocess.run([sys.executable, str(HERE / "build_archive.py"), "--base", str(base), "--add", str(week),
                            "--days-from", str(out), "--out", str(tmp_path / "a.html")], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        page = (tmp_path / "a.html").read_text()
        assert "Usage by day" in page and "no daily data" in page and 'title="Alpha · Jet · 10.0%"' in page
        weeks = json.loads(weeks_file.read_text())
        assert weeks[0] == old and weeks[1]["days"] == DAYS
    finally:
        weeks_file.write_text(saved)
