from pathlib import Path
import runpy
import traceback

status_dir = Path('.github/patch-status')
status_dir.mkdir(parents=True, exist_ok=True)
log_path = status_dir / 'filter-wiilink-game.log'

try:
    runpy.run_path('.github/scripts/filter_wiilink_game.py', run_name='__main__')
except BaseException:
    log_path.write_text(traceback.format_exc(), encoding='utf-8')
    raise
else:
    log_path.write_text('SUCCESS\n', encoding='utf-8')
