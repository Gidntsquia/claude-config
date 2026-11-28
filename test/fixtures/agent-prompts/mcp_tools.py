"""Print the tool name of every function an MCP server file decorates with @mcp.tool(): name= if given, else the function."""
import ast
import sys

for node in ast.walk(ast.parse(open(sys.argv[1], encoding="utf-8").read())):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        for dec in node.decorator_list:
            fn = dec.func if isinstance(dec, ast.Call) else dec
            if isinstance(fn, ast.Attribute) and fn.attr == "tool":
                named = [k.value.value for k in getattr(dec, "keywords", []) if k.arg == "name" and isinstance(k.value, ast.Constant)]
                print(named[0] if named else node.name)
