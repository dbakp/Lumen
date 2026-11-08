"""String confirmation timing; compose exact UTF16LE String predicates and separate UI protocol."""
import importlib.util
from pathlib import Path
BASE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('confirmation_target_parent',BASE/'target-string-evidence-r2.py')
_parent=importlib.util.module_from_spec(spec);spec.loader.exec_module(_parent)
for name in dir(_parent):
 if not name.startswith('_'):globals()[name]=getattr(_parent,name)
IMAGES=_parent.IMAGES+['confirmation-before-mutation']
