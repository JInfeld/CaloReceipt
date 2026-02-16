# Jac Language Reference (v0.10.2)

# 1. TYPES
int float str bool bytes any; list[T] dict[K,V] set[T] tuple; int|None for optionals (NOT int?)
`has x: int;` declares field; `has y: str = "default"` with default; `-> ReturnType` for functions
True/False capitalized (true/false pass syntax but FAIL at runtime)
Non-default attributes MUST come before defaults in same archetype.
WRONG: `node N { has x: int = 0; has y: str; }` RIGHT: `node N { has y: str; has x: int = 0; }`

# 2. CONTROL
```jac
if x > 0 { print("pos"); } elif x < 0 { print("neg"); } else { print("zero"); }
for i=0 to i<10 by i+=1 { print(i); }           # C-style
for x in items { print(x); }                      # Iteration
for (i, x) in enumerate(items) { print(i, x); }  # Parens required
while cond { stmt; }
match x { case 1: print("one"); case "hi": print("hi"); case _: print("other"); }
try { risky(); } except ValueError as e { print(e); } finally { cleanup(); }
```
match/case: COLON then statement. WRONG: `case 1 { stmt; }` WRONG: `case "hi": { stmt; }`
RIGHT: `case "hi": stmt;` RIGHT: `case "hi": if True { stmt1; stmt2; }`
No ternary `?:` -- use `result = ("yes") if cond else ("no");`
No `pass` keyword -- use `{}` or a comment. No `catch` -- use `except`.

# 3. FUNCTIONS
```jac
def add(x: int, y: int) -> int { return x + y; }
f = lambda x: int -> int : x * 2;                    # Expression form
f = lambda x: int -> int { return x * 2; };           # Block form (MUST return)
g = lambda x: int, y: int -> int : x + y;             # Multi-param
items.sort(key=lambda x: dict -> float : x["v"]);     # As argument
handler = lambda e: any -> None { input_val = e.target.value; };  # Assignment = block
noop = lambda e: any -> None { 0; };                   # Empty body (NOT {})
"hello" |> print;                                      # Pipe operator
```
`glob var: T = val;` at module level; access by name in functions. WRONG: `glob x;` inside function.
Top-level: only declarations. Executable statements MUST go in `with entry { }` or function body.
Docstrings go BEFORE declarations, not inside bodies. Never name abilities list/dict/str/int.
f-strings: `f"Hello {name}"` (server-side only, NOT in cl{}).

# 4. IMPORTS
```jac
import os;                            # Plain import (semicolon)
import from math { sqrt }             # Selective (NO semicolon after })
import from os { getenv }             # Works directly, no import:py needed
include utils;                        # C-style merge into current scope
```
WRONG: `import from math, sqrt;` WRONG: `import:py from os { path }` WRONG: `import:jac`
`__init__.jac` required for packages. Include uses FULL dotted paths.
WRONG: `include nodes;` (passes check, fails runtime) RIGHT: `include mypackage.nodes;`
`with entry { }` always runs on module load. `with entry:__main__ { }` only when file is main.

# 5. ARCHETYPES
```jac
node City { has name: str; has pop: int = 0; }
edge Road { has toll: bool = False; has distance: int = 0; }
walker Explorer { has results: list = []; can explore with City entry; }
obj Config { has debug: bool = False; def show { print(self.debug); } }
enum Color { RED = "red", GREEN = "green", BLUE = "blue" }
enum Status { PENDING, ACTIVE, DONE }                    # Auto values
obj Child(Parent) { }                                     # Inheritance
walker W(BaseW) { }                                       # Walker inheritance
```
`can` for abilities (with entry/exit); `def` for regular methods.
`impl W.explore { code }` for separate implementation blocks.
`has f: T by postinit; def postinit { self.f = val; }` for computed fields.
Reserved keywords: obj node walker edge enum can has -- NEVER use as variable names.
WRONG: `obj = json.loads(s);` RIGHT: `data = json.loads(s);`
Boolean NOT: `not x` (Python-style). WRONG: `!x` (JS `!` does NOT exist in Jac).

# 6. ACCESS
`:pub` `:priv` `:protect` on has/def/can/walker. `has:priv x: int;` or `has :priv x: int;` both valid.
`walker :pub W { }` = public endpoint (no auth). Without `:pub` = requires auth token.

# 7. GRAPH
```jac
a ++> b;                                  # Untyped forward connect
a +>: Friend(since=2020) :+> b;          # Typed forward connect
a <+: Road() :<+ b;                       # Backward typed connect
a del--> b;                               # Disconnect
people = [-->](?:Person);                 # Type filter
adults = [-->](?:Person, age > 18);       # Type+attr filter
old = [-->](?age > 18);                   # Attr filter only
friends = [->:Friend:since > 2020:->];   # Edge attr filter
neighbors = [city_a ->:Road:->];          # Variable node traversal
untyped = [node_var -->];                 # Untyped from variable
chained = [->:Road:->->:Bridge:->];      # Chained typed
back = [<-:Road:<-];                      # Backward typed traverse
root +>: E() :+> (end := A(val=10));      # Walrus assign on connect
```
Untyped connect returns list: `nodes = root ++> Node(); first = nodes[0];`
WRONG: `a ++> Edge() ++> b;` `[-->:E:]` `del a --> b;` `[-->:E1:->-->:E2:->]`
Always assign filter results to variable or use in expression -- never bare statement.

# 8. ABILITIES
```jac
node City {
    has name: str;
    can greet with Explorer entry {
        print(f"Explorer at {here.name}");
        visitor.results.append(here.name);
    }
}
walker Explorer {
    has results: list = [];
    can start with Root entry { visit [-->]; }
    can explore with City entry { report here.name; }
    can finish with Root exit { report self.results; }
}
```
`self` = current archetype instance; `here` = current node; `visitor` = visiting walker.
Root type: capital `Root` in event clauses. Backtick `root REMOVED.
Union: `can act with Root | City entry { }` for multiple node types.

# 9. WALKERS
```jac
result = root spawn Explorer();           # Spawn form 1
result = Explorer() spawn root;           # Spawn form 2
visit [-->];                              # Queue outgoing nodes
visit [->:Road:->];                       # Queue via typed edge
visit [-->] else { print("leaf"); }       # Fallback at dead ends
visit self.target;                        # Visit specific node
visit : 0 : [-->];                        # Visit first only (indexed)
report here.name;                         # Append to .reports
disengage;                                # Stop walker (exits SKIPPED)
skip;                                     # Skip to next queued node
```
`visit` QUEUES nodes -- code after visit continues executing in current node.
`report` appends to `.reports` array: `data = result.reports[0];` Always check before indexing.
`disengage` terminates walker; exit abilities for ancestor nodes will NOT execute.
Traversal is recursive DFS with deferred exits. root->A->B: Enter root, Enter A, Enter B, Exit B, Exit A, Exit root.
WRONG: `node spawn W();` (node is keyword) RIGHT: `root spawn W();` or `my_node spawn W();`

# 10. BY_LLM
```jac
import from byllm.lib { Model }
glob llm = Model(model_name="gpt-4o-mini");

obj Person {
    has name: str;
    has age: int;
}

# Semstring: default value REQUIRED before hint
# has desc: str = "" """hint for LLM""";

# Sem annotation (outside code or as comment):
# sem Person.name = "full legal name";

def extract(text: str) -> Person by llm();
def classify(text: str) -> str by llm;                   # No parens OK
def translate(text: str, lang: str) -> str by llm(temperature=0.7);

enum Sentiment { POSITIVE, NEGATIVE, NEUTRAL }
def get_sentiment(text: str) -> Sentiment by llm();       # Enum classification

with entry {
    p = extract("Alice is 30");
    inline_result = "Explain gravity" by llm;             # Inline
}
```
No import needed for `by llm` itself. Model import only for custom config.

# 11. FILE_JSON
```jac
import json;
with entry {
    f = open("data.json", "r");
    data = json.loads(f.read());       # NOT obj = json.loads(...)
    f.close();
    output = json.dumps(data, indent=2);
}
```
`obj` is a reserved keyword -- never use as variable name.

# 12. API
CLI: `jac start file.jac` (NOT `jac serve`). `jac check file.jac` for syntax checking.
ALL walkers register at `POST /walker/<WalkerName>`. `GET /walker/<Name>` returns metadata only.
`__specs__` is VESTIGIAL in 0.10.2 -- methods, path, path_prefix are IGNORED by server.
`:pub` on walker = public (no auth). Without `:pub` = requires auth token.
Auth endpoints: `POST /user/register` and `POST /user/login` for built-in tokens.
`:pub` walker root access is READ-ONLY. Graph writes silently fail when `here` is root.
Custom auth (OAuth/JWT): make ALL walkers `:pub`, handle auth manually in walker body.
SSO routes (`/sso/{platform}/{operation}`) and OpenAPI (`/docs`, `/openapi.json`) require jac-scale plugin.
Response format: `{"ok":true, "data":{"result":..., "reports":[...]}, "error":null, "meta":{...}}`
Client fetch: `response.data.reports[0]` for reported values.

# 13. WEBSOCKET
```jac
async walker :pub EchoMessage {
    async can echo with Root entry {
        report here;
    }
}
```
Connect: `ws://host/walker/EchoMessage`. Remove `:pub` for authenticated websocket.
`socket.notify_users(ids, msg);` `socket.notify_channels(names, msg);` `broadcast=True` for all clients.
Websocket walkers MUST be `async walker`.

# 14. WEBHOOKS
```jac
walker :pub WebhookHandler {
    # obj __specs__ { static has webhook: dict = {"type": "header", "name": "X-Sig"}; }
    can handle with Root entry { report "received"; }
}
```
Webhook config in `__specs__` may still be functional unlike methods/path.

# 15. SCHEDULER
```jac
walker ScheduledTask {
    # obj __specs__ {
    #     static has schedule: dict = {"trigger": "cron", "hour": "9"};
    #     static has private: bool = True;
    # }
    can run with Root entry { report "done"; }
}
```
Triggers: cron, interval, date. `private: bool = True` for private scheduled tasks.

# 16. ASYNC
```jac
async walker :pub AsyncW {
    async can work with Root entry { report "done"; }
}
future = flow expensive_fn();          # Thread pool (CPU-bound)
result = wait future;                  # Block until done
```
`async/await` = event loop (I/O-bound). `flow/wait` = thread pool (CPU-bound).
Task status: `task.__jac__.status;` `task.__jac__.reports;` `task.__jac__.error;`

# 17. PERMISSIONS
```jac
import from jaclang.runtimelib.access { WritePerm, ReadPerm, ConnectPerm, NoPerm }
node.__jac__.grant(target_root, WritePerm);
node.__jac__.revoke(target_root);
node.__jac__.check_access(target_root);
```
Levels: NoPerm < ReadPerm < ConnectPerm < WritePerm.

# 18. PERSISTENCE
Nodes connected to root auto-persist. `save(node);` `commit();` for explicit save.
`&id` for node references. `del node; commit();` to delete.

# 19. TESTING
```jac
test { assert 1 + 1 == 2; }
test { assert "hello".upper() == "HELLO"; }
```
0.10.2: names REMOVED. WRONG: `test "name" { }` WRONG: `test my_test { }`

# 20. STDLIB
Builtins: print len range type isinstance str int float list dict set tuple sorted reversed enumerate zip map filter abs min max round open input.
String: .upper() .lower() .strip() .split() .join() .replace() .startswith() .endswith() .format() f"..."
List: .append() .extend() .pop() .insert() .remove() .sort() .reverse() .index() .count()
Dict: .keys() .values() .items() .get() .update() .pop() .setdefault()

# 21. JSX/CLIENT
TWO approaches: (1) `.cl.jac` files = entire file is client-side. (2) `cl{}` blocks in `.jac` files.
`.cl.jac` files auto-compiled to JS. Do NOT include them via `include`.
```jac
cl import from react { useEffect }
cl import from "@jac/runtime" { Router, Routes, Route, Link }

cl {
    def:pub Counter() -> JsxElement {
        has count: int = 0;
        return <div>
            <p>Count: {count}</p>
            <button onClick={lambda e: any -> None { count = count + 1; }}>+</button>
        </div>;
    }
    def:pub app() -> JsxElement {
        return <Counter />;
    }
}
```
`has` inside component = reactive state (like useState). `can with entry { }` = useEffect mount.
`can with exit { }` = useEffect cleanup. `can with [dep] entry { }` = useEffect with dependency.
`async can with entry { }` for async mount effects.
`root spawn` in cl{} compiles to `await` POST to `/walker/<Name>`. Function MUST be `async def`.
JSX comprehensions: `{[<li>{item}</li> for item in items]}` compiles to `.map()`.
`{[<li>{x}</li> for x in items if x.active]}` compiles to `.filter().map()`.
Return type: `-> JsxElement` (NOT `-> any` which conflicts with builtin).
CSS: `import "./styles.css";` or `import '.styles.css';` (dot-prefix auto-converts).
cl{} JS rules: `.length` not `len()`; `String(x)` not `str(x)`; `parseInt(x)` not `int(x)`; `Math.min/max`; `.trim()` not `.strip()`; no `range()`; no f-strings (use `+`); no tuple unpacking; `className` not `class`.
`new` does NOT exist: WRONG `new Date()` RIGHT `Reflect.construct(Date, [val])`.
`None` compiles to `null` in cl{} context. Use `None` in Jac source.
`cl import` / `sv import` prefixes at TOP LEVEL (outside cl{} block) for cross-context imports.
`sv import from __main__ { MyWalker }` to import server walkers into client context.
`items.append(x)` not `items = items + [x]` in cl{} (list concat fails).

# 22. CLIENT_AUTH
```jac
cl import from "@jac/runtime" { jacSignup, jacLogin, jacLogout, jacIsLoggedIn }
cl {
    def:pub app() -> JsxElement {
        has isLoggedIn: bool = False;
        async def login(email: str, password: str) -> None {
            await jacLogin(email, password);
            isLoggedIn = jacIsLoggedIn();
        }
        return <div>{isLoggedIn if <p>Welcome</p> else <p>Please login</p>}</div>;
    }
}
```
Per-user graph isolation: each authenticated user gets their own root graph.

# 23. JAC.TOML
```toml
[project]
name = "myapp"
entry-point = "main.jac"

[dependencies]
python-dotenv = ">=1.0.0"
byllm = ">=0.1.0"

[dependencies.npm]
tailwindcss = "^4.0.0"
"@tailwindcss/postcss" = "^4.0.0"

[serve]
base_route_app = "app"
port = 8000

[plugins.client]
port = 5173
```
All npm deps in `[dependencies.npm]`. NEVER `npm install` in `.jac/client/`.
`base_route_app` must match `def:pub app` function name in your code.

# 24. FULLSTACK_SETUP
`jac create --use client` (NOT `--use fullstack`). `jac install` syncs all deps. `jac add --npm pkg`.
`.jac/` directory is auto-generated -- never modify manually.
`__init__.jac` in packages: use full dotted paths for includes.
Project structure: `main.jac` + `jac.toml` + optional `nodes.jac` `walkers.jac` `frontend.cl.jac`.

# 25. DEV_SERVER
`jac start --dev` for development with hot reload.
`--port` = Vite frontend (default 8000); `--api_port` = backend (default 8001, auto-proxied).
Proxy routes: `/walker/*` `/function/*` `/user/*` forwarded to backend.
`--no-client` to run backend only. `jac start file.jac` for production.

# 26. DEPLOY_ENV
```dockerfile
FROM python:3.11-slim
RUN pip install jaseci
COPY . /app
WORKDIR /app
CMD ["jac", "start", "main.jac"]
```
`jaseci` = full runtime (persistence/auth/plugins). `jaclang` = compiler only.
`jac start --scale` for scaled deployment (requires jac-scale plugin).
Env vars: `DATABASE_URL` `JAC_SECRET_KEY` `OPENAI_API_KEY`.
`.env` not auto-loaded. Use: `import from dotenv { load_dotenv }` then `glob _: bool = load_dotenv() or True;`

# PATTERN 1: Fullstack Counter (single-file with cl{})
```jac
# main.jac
node Counter { has count: int = 0; }

walker :pub GetCount {
    can get with Root entry {
        counts = [-->](?:Counter);
        if counts { report counts[0].count; }
        else { report 0; }
    }
}

walker :pub Increment {
    can inc with Root entry {
        counts = [-->](?:Counter);
        if counts { counts[0].count += 1; report counts[0].count; }
    }
}

with entry {
    root ++> Counter(count=0);
}

cl import from react { useEffect }

cl {
    def:pub app() -> JsxElement {
        has count: int = 0;

        async def fetchCount() -> None {
            result = root spawn GetCount();
            count = result.reports[0] if result.reports else 0;
        }

        async def doIncrement() -> None {
            result = root spawn Increment();
            count = result.reports[0] if result.reports else count;
        }

        can with entry {
            fetchCount();
        }

        return <div>
            <h1>Count: {count}</h1>
            <button onClick={lambda e: any -> None { doIncrement(); }}>+1</button>
        </div>;
    }
}
```
```toml
# jac.toml
[project]
name = "counter"
entry-point = "main.jac"
[serve]
base_route_app = "app"
```

# PATTERN 2: Walker Graph Traversal
```jac
node City { has name: str; has pop: int = 0; }
edge Road { has toll: bool = False; has distance: int = 0; }

walker FindReachable {
    has reachable: list = [];
    can start with Root entry { visit [-->]; }
    can explore with City entry {
        self.reachable.append(here.name);
        visit [->:Road:->];
    }
    can done with Root exit { report self.reachable; }
}

walker DeleteRoute {
    has from_city: str;
    has to_city: str;
    can start with Root entry { visit [-->]; }
    can find with City entry {
        if here.name == self.from_city {
            targets = [->:Road:->](?:City, name == self.to_city);
            for t in targets { here del--> t; }
            disengage;
        }
        visit [->:Road:->];
    }
}

with entry {
    a = City(name="NYC", pop=8000000);
    b = City(name="Boston", pop=700000);
    c = City(name="DC", pop=700000);
    root ++> a;
    a +>: Road(toll=True, distance=200) :+> b;
    a +>: Road(distance=230) :+> c;
    b +>: Road(distance=440) :+> c;

    result1 = root spawn FindReachable();
    print(result1.reports[0]);

    toll_roads = [a ->:Road:toll == True:->];
    print("Toll destinations:", toll_roads);

    short = [a ->:Road:distance < 250:->];
    print("Nearby:", short);

    root spawn DeleteRoute(from_city="NYC", to_city="Boston");
    result2 = root spawn FindReachable();
    print("After delete:", result2.reports[0]);
}
```

# PATTERN 3: API Todo CRUD
```jac
node Todo {
    has id: str;
    has title: str;
    has done: bool = False;
    has priority: str = "medium";
}

walker :pub ListTodos {
    has todos: list = [];
    can start with Root entry { visit [-->]; }
    can collect with Todo entry {
        self.todos.append({"id": here.id, "title": here.title,
            "done": here.done, "priority": here.priority});
    }
    can done with Root exit { report self.todos; }
}

walker :pub AddTodo {
    has title: str;
    has priority: str = "medium";
    can add with Root entry {
        import uuid;
        new_id = str(uuid.uuid4());
        nodes = here ++> Todo(id=new_id, title=self.title, priority=self.priority);
        report {"id": new_id, "title": self.title};
    }
}

walker :pub FilterTodos {
    has filter_by: str = "all";
    has results: list = [];
    can start with Root entry { visit [-->]; }
    can check with Todo entry {
        match self.filter_by {
            case "high": if here.priority == "high" { self.results.append(here.title); }
            case "done": if here.done { self.results.append(here.title); }
            case "pending": if not here.done { self.results.append(here.title); }
            case _: self.results.append(here.title);
        }
    }
    can done with Root exit { report self.results; }
}

with entry {
    print("Todo API ready");
}
```
All walkers auto-register: `POST /walker/ListTodos`, `POST /walker/AddTodo`, `POST /walker/FilterTodos`.
Client fetch: `fetch("/walker/ListTodos", {method:"POST"}).then(r => r.json()).then(d => d.data.reports[0])`

# COMMON ERRORS
WRONG: `true` / `false` -> RIGHT: `True` / `False`
WRONG: `entry { }` -> RIGHT: `with entry { }`
WRONG: `import from math, sqrt;` -> RIGHT: `import from math { sqrt }`
WRONG: `import:py from os { path }` -> RIGHT: `import from os { path }`
WRONG: `node spawn W();` -> RIGHT: `root spawn W();` (node is keyword)
WRONG: `a ++> Edge() ++> b;` -> RIGHT: `a +>: Edge() :+> b;`
WRONG: `[-->:E:]` -> RIGHT: `[->:E:->]`
WRONG: `[-->:E1:->-->:E2:->]` -> RIGHT: `[->:E1:->->:E2:->]`
WRONG: `del a --> b;` -> RIGHT: `a del--> b;`
WRONG: `` (`?Type) `` -> RIGHT: `(?:Type)`
WRONG: `` (`?Type:attr>v) `` -> RIGHT: `(?:Type, attr > v)`
WRONG: `` can act with `root entry `` -> RIGHT: `can act with Root entry`
WRONG: `test "name" { }` -> RIGHT: `test { }` (no names in 0.10.2)
WRONG: `test my_test { }` -> RIGHT: `test { }` (named tests removed)
WRONG: `obj = json.loads(s);` -> RIGHT: `data = json.loads(s);`
WRONG: `str?` -> RIGHT: `str | None`
WRONG: `jac serve file.jac` -> RIGHT: `jac start file.jac`
WRONG: `jac create --use fullstack` -> RIGHT: `jac create --use client`
WRONG: `static has auth: bool = False;` -> RIGHT: `walker :pub W { }`
WRONG: `<div class="x">` -> RIGHT: `<div className="x">`
WRONG: `len(items)` in cl{} -> RIGHT: `items.length`
WRONG: `str(x)` in cl{} -> RIGHT: `String(x)`
WRONG: `f"Hello {x}"` in cl{} -> RIGHT: `"Hello " + x`
WRONG: `items = items + [x]` in cl{} -> RIGHT: `items.append(x)`
WRONG: `lambda e: any -> None {}` -> RIGHT: `lambda e: any -> None { 0; }`
WRONG: `include nodes;` in __init__.jac -> RIGHT: `include mypackage.nodes;`
WRONG: `npm install` in .jac/client/ -> RIGHT: `jac add --npm pkgname`
WRONG: `print("x");` at top level -> RIGHT: `with entry { print("x"); }`
WRONG: `case 1 { stmt; }` -> RIGHT: `case 1: stmt;`
WRONG: `case "hi": { stmt; }` -> RIGHT: `case "hi": if True { stmt1; stmt2; }`
WRONG: `catch Error as e { }` -> RIGHT: `except Error as e { }`
WRONG: `result = x > 0 ? "y" : "n";` -> RIGHT: `result = ("y") if x > 0 else ("n");`
WRONG: `has x: int = 0; has y: str;` -> RIGHT: `has y: str; has x: int = 0;`
WRONG: `glob counter;` inside function -> RIGHT: just use `counter` directly
WRONG: `result.returns[0]` -> RIGHT: `result.reports[0]`
WRONG: `.map(lambda x -> ...)` in JSX -> RIGHT: `{[<li>{x}</li> for x in items]}`
WRONG: `pass` -> RIGHT: `{}` or comment
WRONG: `!x` -> RIGHT: `not x`
WRONG: `__specs__` methods/path -> RIGHT: IGNORED in 0.10.2; all walkers POST /walker/<Name>
WRONG: `new Date()` in cl{} -> RIGHT: `Reflect.construct(Date, [val])`
WRONG: `def:pub app() -> any` -> RIGHT: `def:pub app() -> JsxElement`
WRONG: `fetch("/api/todos")` -> RIGHT: `fetch("/walker/ListTodos", {method:"POST"})`