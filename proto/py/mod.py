from packaging.version import Version


def newer(a: str, b: str) -> bool:
    return Version(a) > Version(b)
