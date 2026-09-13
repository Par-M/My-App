def test_probe_routes():
    from app.main import app
    import json
    paths = sorted({getattr(r, "path", "") for r in app.routes})
    interesting = [p for p in paths if "focus" in p or "reflect" in p or "habit" in p]
    # Print explicitly - pytest shows stdout only on failure
    assert interesting == ["this-will-never-match"], json.dumps(interesting)
