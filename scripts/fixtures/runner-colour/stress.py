# The editor's colours (#585): Python a student might type, beyond the example content.
# Scored against the image's Shiki by scripts/check_runner_rules_against_the_site.py.

import math
from dataclasses import dataclass

# A comment with "quotes" and 'more'
@dataclass
class Point:
    """A point.

    With a docstring over lines."""
    x: float = 0.0
    y: float = 0.0

    def length(self) -> float:
        return math.sqrt(self.x ** 2 + self.y ** 2)

    @property
    def label(self):
        return f"({self.x:.2f}, {self.y!r}) {'nested'} {{braces}}"

def greet(name: str, times: int = 2, *args, **kwargs) -> None:
    for i in range(times):
        print(f"Hello, {name.upper()}! #{i + 1}", end="\n")
    if (n := len(name)) > 3 and not False or None is None:
        print('long', n, 0x1F, 0b101, 0o17, 1_000_000, 3.14e-2, 2j)
    text = r"raw \n string" + b"bytes".decode() + rb'\d'
    multi = '''single
triple'''
    while True:
        try:
            value = int(input("Number? "))
        except ValueError as error:
            print("bad", error)
            continue
        else:
            break
        finally:
            pass
    match value:
        case 1 | 2:
            print("small")
        case _:
            print(lambda v: v * 2)
    return None

async def fetch():
    await something()
    yield from range(3)
    global counter
    del counter
    assert counter in [1, 2], "msg"
total = sum([x for x in range(10) if x % 2 == 0])
print(f'{total=}', F"upper {total}", f"""tri {total}
line""")

x = "{} {name:>10} {0!r} {a.b[0]:{w}}".format(1)
y = "%d items, %(n)s, %-5.2f %%" % (3,)
b = b"\x41 %s {x}"
print("\x41 \u00e9 \U0001F600 \N{BULLET} \012 \d \\ \'")
r = r"\d+ \n {x} [a-z]+ (a|b)"
rb = rb'\d'
f = f"{x:{w}.{p}f} {n=} {d['k']} {{lit}} {v!r:>4}"
fr = Rf"\d{x}"
s = """{x} and \n done"""
u = u"\N{BULLET}"

@app.route("/x", methods=["GET"])
@dataclass(frozen=True)
@property
@functools.lru_cache(maxsize=None)
class A(Base, metaclass=Meta):
    def __init__(self, x: int = 0, *args, **kwargs) -> None:
        super().__init__()
        self.x = x
        obj.__class__.__name__
    @staticmethod
    def f(cls): return cls

match point:
    case (x, y):
        pass
    case Point(x=0, y=yy) if yy > 0:
        pass
    case [1, *rest]:
        pass
    case {"k": v}:
        pass
    case _:
        pass
class MyError(Exception):
    pass
raise MyError("bad")
try:
    raw_input("x")
except (ValueError, MyError) as e:
    print(e, file=sys.stderr)
x = lambda a, b=2: a + b
nums = [i ** 2 for i in range(10) if i % 2 == 0]
print(*nums, sep=", ", end="")
value = -3.5e10 + 0x_FF + 1_000j + .5 + 5.
a, *b = 1, 2, 3
def g(a, /, b, *, c): ...
global X
nonlocal y
print(type(x).__name__, len(x), isinstance(x, (int, float)), NotImplemented, Ellipsis, __name__, __file__)
assert x is not None and y not in z
x @= y; x //= 2; x **= 3; x >>= 1; x != y; x <> y
# TODO: fix HACK NOTE XXX BUG FIXME later
if x: y = 1 \
    + 2
async with a as b: await c
yield from d

print(
    "a",
    sep="",
)
def h(
    sep="",
):
    pass
x = foo(a=1,
        b=2)

a = f"""
total {x} and \n done
"""
b = """
total {x} and \n done
"""
c = r"""
total {x} and \n done
"""
d = "abc \
total {x} and \n done"
e = 'single\
continues'

a = r"^\d{2,3}[^a-z\]]*?(?P<name>\w+)(?:x|y)\.\s$ \b. \\ \n \t \x41 \1 (?=a)(?!b)(?<=c)(?#comment) {3} a{2}"
b = rf"\d{x}"
c = fr"\d{x}"
d = R"\d{x}"
e = br"\d"
f = Br"\d"
g = r'it\'s'
h = R'it\'s {0}'
i = r"[\d\s]+|[A-Z]"
j = "{:>{w}}".format(1)
k = f"{x:>{w}}"
l = f"{x!r}"
m = f'{x["a"]}'
n = f"{x:%Y-%m}"
o = f"{'a' if x else 'b'}"
p = f"{x}{y}"
q = "%s" % x + "%5d" % y + "%.2f%%" % z
r = 'a' 'b'
s = """
%s and {0}
"""

x = DATA[0] + CONST(1) + dict[str, int] + self.items[0] + str.upper("a") + Foo.BAR + x.CONST(2)
y = print[0] + len (x) + int (y) + range [3] + self[0] + self(1) + MyClass.method() + obj.attr
z: list[int] = []
w: dict = {}
class C(models.Model, abc.ABC, Generic[T]): pass
def f() -> list[int]: pass
q = [x for x in data if x.isupper()]
v = obj.print(1) + obj.len + obj.True

v = X + X1 + X_Y + _X + A_b + AB_c + MAX_n + _AB + __A + A1B + PI + Ab + A_ + XY_

a = r"[]"
b = r"[]a]"
c = r"a[]b"
d = r"[^]"
e = r"""x [] y
# comment here
z [a] # trailing
"""
f = r"x # not comment"
g = r"""a
[]b] c
"""
h = r'''{3} {x} a{1,} $1 \Z'''

def f():
    """Doc with {x} and %d and %% and \n"""
    '''Another {0} %s'''
    x = """Assigned {x} %d"""
    print("""Arg {x} %d""")
"""Module {x} %d"""
"single {x} %d"
