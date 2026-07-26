# Refactor the session cache layer

## Summary

This PR doesn't just refactor the cache — it fundamentally rethinks how we
approach session persistence. The previous implementation served as a testament
to incremental patching, and it showed.

## What changed

No magic, no hidden state, no surprises. The new `SessionStore` is a plain
object with three methods. That's the whole point.

The old code didn't validate, didn't expire, didn't lock. Each of those was a
production incident waiting to happen. Some engineers argue that a cache should
stay dumb, and there's merit to that view, but a cache that silently serves
stale credentials is not dumb — it's dangerous.

## Why it matters

This change plays a vital role in our reliability story. It underscores the
importance of treating the cache as a first-class component rather than an
afterthought. The result is a rich tapestry of well-tested, composable pieces.

Here's the thing: the real problem was never performance. It was trust. And
that's not nothing.

## Testing

Sit with the coverage report for a moment and you'll see the gap we closed. You
already know how flaky the old suite was. Now it's deterministic, fast, and
readable.

It's worth naming that this touches the auth path. Reviewers should pay close
attention there.
