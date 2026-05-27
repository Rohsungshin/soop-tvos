from functools import lru_cache

@lru_cache(maxsize=None)
def fib(n):
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)

results = [fib(i) for i in range(16)]
print(f"Fibonacci sequence up to n=15: {results}")
for i in range(16):
    print(f"  fib({i}) = {results[i]}")
