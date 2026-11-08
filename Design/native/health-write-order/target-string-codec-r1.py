"""Only the two predeclared synthetic NSString values; exact UTF16LE, no normalization."""
OLD_TEXT = "Synthetic persisted old value e\u0301 🫖"
NEW_TEXT = "Synthetic newer saved value e\u0301 🫖"
OLD = OLD_TEXT.encode('utf-16-le')
NEW = NEW_TEXT.encode('utf-16-le')
def encode(value):
    assert type(value) is str and len(value) <= 2048
    raw=value.encode('utf-16-le',errors='strict')
    assert len(raw)<=4096
    return raw
