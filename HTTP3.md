# Strap in, your sites are getting an F1 engine

We’re rolling out a meaningful upgrade across BOA/Omega8.cc nodes: HTTP/3 and KTLS support.

If you run Drupal sites that should feel fast and responsive (and stay that way during spikes), this is genuinely good news. It’s not a “new feature in the control panel” kind of update — it’s the kind that improves the *experience* visitors have without you touching a single line of code.


## Why this is a big deal

Nearly everything on the web is encrypted now (HTTPS). That’s great for security, but it also means every visit involves extra work just to establish and maintain that secure connection.

The upgrades are all about making secure browsing feel lighter and faster.

### What visitors should notice

* Faster “start” to loading (especially for first-time or returning visits after a while)
* Smoother browsing on mobile and Wi-Fi (fewer annoying stalls when the connection quality changes)
* More consistent performance during traffic spikes (less overhead spent on transport/encryption, more resources left for actual Drupal work)

### Why it matters for *your server* too

* More efficient HTTPS handling can mean lower CPU pressure in the busiest parts of the request path.
* That translates into more headroom for PHP-FPM, caches, and database work when it really counts.

In short: faster for users, more efficient for servers, and no application changes required.

<img width="1050" height="1218" alt="screenshot 2026-02-05 at 10 35 06" src="https://github.com/user-attachments/assets/4e179e7b-97ac-4808-ace6-b0f29e6b66a8" />

## What’s being enabled (friendly version)

### HTTP/3

HTTP/3 is the newest “dialect” browsers can use to talk to your site. It’s designed for today’s reality: phones, roaming, Wi-Fi, variable quality connections.

When a visitor’s browser supports HTTP/3, it can:

* connect more quickly,
* recover better from “internet wobble,”
* and keep page loads feeling responsive even when conditions aren’t perfect.

And the best part: browsers choose it automatically. Nobody needs to configure anything on their device.

### KTLS

KTLS helps the operating system handle part of the secure connection workload more efficiently. The result is simpler to describe than the internals:

* less overhead
* more throughput
* better stability under load

It’s one of those improvements that quietly makes a platform feel “stronger” and less stressed during peak times.


## What you need to do (this is the important part)

We’ll make sure the server side is ready after the upgrades — but to actually *apply* the new capabilities cleanly across your BOA/Aegir-managed stack, you need to run Verify so configurations are regenerated with the updated features.

### After the maintenance completes:

1. Log in to your Aegir Control Panel
2. Go to Platforms → run Verify on all platforms you use to host sites
3. Go to Sites → run Verify on your hosted sites

   * If you host many sites: use the bulk actions on the Sites list so you don’t have to click site-by-site.

This ensures your platform and site configs are refreshed and the upgraded stack is applied consistently.


## “Will anything break?” (No — it’s designed not to)

* If a browser supports HTTP/3, it will use it automatically.
* If it doesn’t, it will quietly fall back to HTTP/2 or HTTP/1.1.
* Your Drupal code stays the same.
* Your visitors don’t have to do anything.


## Want more detail?

We’ll publish our own concise, friendly explainer that goes deeper into:

* what HTTP/3 changes in real-life browsing,
* why KTLS improves HTTPS efficiency,
* and how to confirm your browser is using HTTP/3.

More details: *(link coming soon — we’ll share it as soon as it’s live)*


## Quick checklist (save this)

After the system upgrade:

1. Aegir → Platforms → Verify (all platforms)
2. Aegir → Sites → Verify (use bulk actions if you have many sites)

That’s it. Once Verify is done, you’re ready to benefit automatically — and your visitors get a faster, smoother ride. Enjoy!


