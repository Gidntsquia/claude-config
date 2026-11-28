class FastMCP:
    def __init__(self, name, **kwargs):
        self.name = name
        self.tools = {}

    def tool(self, name=None, **kwargs):
        def register(fn):
            self.tools[name or fn.__name__] = fn
            return fn
        return register

    def run(self):
        raise SystemExit("the stand-in mcp package cannot serve")
